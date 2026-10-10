extends Control
# 吹牛骰子牌桌控制器(设计稿 §3、§6.11):接收 Net 的视图与事件 → 事件队列交给 LiarsDiceDirector 逐个演出(演出期间锁出价)
# → 演出结束后按最新视图对账(骰盅、自己的骰子、铭牌、HUD、机位)。本地状态在 LiarsDiceScreenState 里;3D 骰盅与骰子由
# LiarsDiceCups 管,特效在 LiarsDiceFx;视线与探头交给 SeatGaze。
# 出手一律 Net.submit_session_intent(...);被拒时 toast LiarsDiceState.ERROR_MESSAGES 的中文。
# 给按钮、快捷键与机器人的入口是同一套:nudge_count / pick_face / submit_bid / submit_challenge(debug_flags 的机器人走的就是它们)。
# 私有视图比「开!」那一批的演出先到:按 round 缓存,导演演到对应的 round_started 才换上(wait_round_dice)。


const PLATE_KEY := "plate:%d"   # WorldLabels 里对手铭牌的键
const QUIP_ABOVE_CLAIM := -56.0  # 九宫格快捷对话的气泡比喊价气泡再高这么多(屏幕像素,同其他牌桌)
const LEAVE_CONFIRM := "离开牌桌会被判出局,确定吗?"
const HOST_LEAVE_CONFIRM := "你是房主,离开会解散整桌,确定吗?"
# 快捷键 → 动作(设计稿 §3):不占 T / G / Q / V / WASD / Esc / F1;数字键 2–6 选点数(快捷语面板、九宫格开着时归面板)
const ACTION_BID := "bid"
const ACTION_CHALLENGE := "challenge"
const ACTION_MORE := "more"
const ACTION_LESS := "less"
const FACE_KEYS := {KEY_2: 2, KEY_3: 3, KEY_4: 4, KEY_5: 5, KEY_6: 6, KEY_KP_2: 2, KEY_KP_3: 3, KEY_KP_4: 4, KEY_KP_5: 5, KEY_KP_6: 6}

var app: Node
var my_pid := 0
var hud: LiarsDiceHud
var director: LiarsDiceDirector
var quips: QuipController
var world: TableWorld
var cups: LiarsDiceCups
var fx3d: LiarsDiceFx              # 出价标记、「开!」、计数与判定字,挂在 poker_root 下随拆台收走
var state := LiarsDiceScreenState.new()
var picker := LiarsDicePicker.new()
var animating := true
var intent_sink := Callable()     # 测试钩子:不走 Net,直接把意图交给本地会话(func(intent: Dictionary))

var _clock := TurnClock.new()
var _gaze: SeatGaze = null
var _queue: Array = []
var _intro_done := false
var _awaiting_intent := false     # 已提交喊价 / 开,等房主回执
var _settlement: LiarsDiceSettlement = null
var _reveal_face := 0             # 开盅演出期间:自己的 2D 骰子标出算进去的(0 = 不标)


func _init(p_app: Node) -> void:
	app = p_app


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	my_pid = Net.my_pid()
	world = app.world
	state.my_pid = my_pid
	state.set_seats(Net.seats)
	# 桌子:骗子酒馆的桌与烛台(不摆立牌);5–6 人换德州的大桌(设计稿 §6.8)
	app.apply_table_mode(Net.game_mode)
	world.configure_table(SeatLayout.table_radius_for(Net.game_mode, Net.seats.size()))
	world.clear_poker()
	world.revive_all()
	world.cards.clear_all()
	app.labels.clear()
	world.arrange(Net.seats, my_pid, true, false)
	cups = LiarsDiceCups.new(world)
	cups.my_pid = my_pid
	world.poker_root.add_child(cups)
	cups.sfx.connect(Sfx.play)
	var species := {}
	for pid in state.seats:
		species[pid] = world.species_index_of(pid)
	cups.setup(state.seats, species)
	fx3d = LiarsDiceFx.new(world)
	fx3d.my_pid = my_pid
	world.poker_root.add_child(fx3d)
	fx3d.sfx.connect(Sfx.play)
	hud = LiarsDiceHud.new()
	add_child(hud)
	_connect_hud()
	quips = _make_quips()
	add_child(quips)
	hud.quip_pressed.connect(quips.toggle)
	director = LiarsDiceDirector.new(self, app, hud)
	add_child(director)
	_build_nameplates()
	Net.state_public_updated.connect(_on_public)
	Net.state_private_updated.connect(_on_private)
	Net.game_events.connect(_on_events)
	Net.intent_rejected.connect(_on_rejected)
	_gaze = _make_gaze()
	add_child(_gaze)
	if not Net.last_public.is_empty():
		_on_public(Net.last_public)
	if not Net.last_private.is_empty():
		_on_private(Net.last_private)
	refresh_hud()
	await director.intro()
	_intro_done = true
	_drain()


func _exit_tree() -> void:
	# 只收走自己挂的铭牌与气泡;骰盅、骰子与特效挂在 poker_root 下,一并拆掉
	if not is_instance_valid(app) or not is_instance_valid(world):
		return
	for pid in state.names:
		app.labels.untrack(PLATE_KEY % pid)
		app.labels.untrack(LiarsDiceDirector.BUBBLE_KEY % pid)
		app.labels.untrack(QuipController.KEY_PREFIX % pid)
	world.stop_celebration()   # 结算庆祝(舞步、礼炮、彩纸)随牌桌退场收起
	world.clear_poker()


func _process(delta: float) -> void:
	_clock.tick(delta)
	if hud == null:
		return
	var show_ring: bool = state.pub_current() != null and not animating and not state.pub.is_empty() \
		and state.pub_step() != LiarsDiceScreenState.STEP_OVER and _settlement == null
	hud.set_countdown(_clock.remaining(), Protocol.TURN_TIMEOUT, show_ring)


func _connect_hud() -> void:
	hud.rules_pressed.connect(func(): app.show_rules())
	hud.count_nudged.connect(func(delta: int): nudge_count(delta))
	hud.face_picked.connect(func(face: int): pick_face(face))
	hud.bid_pressed.connect(func(): submit_bid())
	hud.challenge_pressed.connect(func(): submit_challenge())


func _make_gaze() -> SeatGaze:
	var gaze := SeatGaze.new(app, world, my_pid)
	gaze.gaze_free = func() -> bool: return director.is_camera_at_rest() and _settlement == null
	gaze.at_seat = director.is_at_seat
	gaze.excluded = func(pid: int) -> bool: return not state.is_alive(pid)
	gaze.rest_point = func() -> Vector3: return LiarsDiceDirector.TABLE_FOCUS
	return gaze


# —— 网络输入 ——

func _on_public(view: Dictionary) -> void:
	state.apply_public(view)
	_clock.sync_from_host(view.get("turn_time_left", -1.0))
	if not animating:
		_reconcile()
	else:
		refresh_actions()


func _on_private(view: Dictionary) -> void:
	# 只按轮次记下来:换到屏幕上等导演演到那一轮的 round_started
	state.apply_private(view)
	if not animating:
		_reconcile()
	else:
		refresh_actions()


func _on_events(events: Array) -> void:
	# 有新的一批事件 = 房主处理过了(自己的意图被接受,或局面变了):回执到了,可以再出手
	_awaiting_intent = false
	_queue.append_array(events.filter(func(ev): return ev is Dictionary))
	if _intro_done and not animating:
		_drain()


func _on_rejected(code: String) -> void:
	_awaiting_intent = false
	app.toast(LiarsDiceState.ERROR_MESSAGES.get(code, code), UiTheme.LIE)
	refresh_actions()


func _drain() -> void:
	animating = true
	cups.set_hover_peek(false)
	refresh_actions()
	while not _queue.is_empty():
		var ev: Dictionary = _queue.pop_front()
		await director.play(ev)
	animating = false
	_reveal_face = 0
	_reconcile()


func _reconcile() -> void:
	# 演出结束后用最新视图兜底对齐(正常流程下视觉已与状态一致)
	if state.pub.is_empty():
		return
	state.sync_from_view()
	sync_table()
	if director != null and _settlement == null and director.camera_mode() != LiarsDiceDirector.MODE_ORBIT:
		if not state.am_alive() and state.started:
			director.spectator = true
			hud.set_spectating(true)
		director.settle_camera()
	if is_my_turn() and not picker.is_legal(state.pub_bid(), state.pub_total()):
		picker.reset(state.pub_bid(), state.pub_total())
	refresh_actions()


func sync_table() -> void:
	if cups != null and state.pub_step() != LiarsDiceScreenState.STEP_OVER:
		var alive := {}
		for pid in state.seats:
			alive[pid] = state.is_alive(pid)
		cups.sync(alive, state.shown_dice if state.am_alive() else [])
	refresh_hud()


# —— 导演回调 ——

func name_of(pid: Variant) -> String:
	return state.name_of(pid)


func note_event(ev: Dictionary) -> void:
	state.apply_event(ev)
	_update_nameplates()
	_update_info()


func set_current(pid: Variant) -> void:
	_clock.restart_turn()
	_awaiting_intent = false
	if hud == null:
		return
	var focus := world.to_global(LiarsDiceDirector.TABLE_FOCUS)
	if pid is int and world.patrons.has(pid):
		focus = world.head_position(pid)
	for patron_pid in world.patrons:
		var patron: Patron = world.patrons[patron_pid]
		patron.set_active(patron_pid == pid)
		if patron.alive:
			patron.look_at_point(world.to_global(LiarsDiceDirector.TABLE_FOCUS) if patron_pid == pid else focus)
	if pid == null:
		hud.set_turn("", false)
	elif pid == my_pid:
		picker.reset(state.bid, state.total)
		hud.set_turn("轮到你了" if state.bid.is_empty() else "轮到你了 · 加注还是开?", true)
		Sfx.play("join")
		if app.is_rules_open():
			app.toast("轮到你了!按 %s 合上说明书" % OS.get_keycode_string(Rulebook.HOTKEY), UiTheme.BRASS_BRIGHT)
	else:
		hud.set_turn("等待 %s 喊…" % name_of(pid), false)
	_update_nameplates()
	_update_info()
	refresh_actions()


func wait_round_dice(round_no: int, max_wait: float) -> Array:
	# 演到第 round_no 轮的 round_started:私有骰子通常早到了(按轮次缓存);最多再等 max_wait
	var waited := 0.0
	while not state.has_round_dice(round_no) and waited < max_wait and is_inside_tree() and state.am_alive():
		await get_tree().process_frame
		waited += get_process_delta_time()
	return state.take_round_dice(round_no) if state.am_alive() else state.take_round_dice(-1)


func refresh_my_dice(flash := false) -> void:
	if hud == null:
		return
	hud.set_my_dice(state.shown_dice, state.am_alive(), _reveal_face)
	if flash and not state.shown_dice.is_empty():
		hud.flash_my_dice()
	_update_info()


func show_reveal_dice(face: int) -> void:
	# 开盅:自己的 2D 骰子用开盅里自己的点数,标出算进去的
	_reveal_face = face
	var mine := state.revealed_dice_of(my_pid)
	if not mine.is_empty():
		state.shown_dice = mine
	refresh_my_dice()


func drop_my_die() -> void:
	# 自己丢了一颗:屏幕上的骰子少一颗(下一轮重摇时按私有视图换新的)
	if not state.shown_dice.is_empty():
		state.shown_dice.pop_back()
	refresh_my_dice()


func mark_out(pid: int) -> void:
	if _gaze != null:
		_gaze.forget(pid)
	if pid == my_pid:
		state.shown_dice = []
		if hud != null:
			hud.set_spectating(true)
	_update_nameplates()


func show_settlement() -> void:
	if _settlement != null:
		return
	var rows := state.ranking_rows()
	var winner: Variant = state.winner
	hud.set_away_from_seat(true)
	_settlement = LiarsDiceSettlement.new(name_of(winner), rows, winner == my_pid, Net.is_host)
	_settlement.lobby_pressed.connect(func():
		Sfx.play("ui_click")
		Net.request_rematch_lobby())
	_settlement.leave_pressed.connect(func():
		Sfx.play("ui_click")
		Net.end_session())
	add_child(_settlement)


func settlement() -> LiarsDiceSettlement:
	return _settlement


# —— 铭牌与 HUD ——

func _build_nameplates() -> void:
	for pid in state.seats:
		if pid == my_pid or not world.patrons.has(pid):
			continue
		var anchor: Callable = world.nameplate_anchor.bind(pid) if world.is_poker_table() else world.patrons[pid].nameplate_anchor
		app.labels.track(PLATE_KEY % pid, LiarsDiceNameplate.new(state.name_of(pid)), anchor)
	_update_nameplates()


func pulse_nameplate(pid: Variant) -> void:
	if not pid is int or app == null or app.get("labels") == null:
		return
	var plate: Variant = app.labels.get_node_for(PLATE_KEY % pid)
	if plate is LiarsDiceNameplate:
		plate.pulse()


func _last_bid_of(pid: int) -> Dictionary:
	for i in range(state.bids.size() - 1, -1, -1):
		if state.bids[i].get("pid") == pid:
			return state.bids[i]
	return {}


func _update_nameplates() -> void:
	if app == null or app.get("labels") == null:
		return
	for pid in state.seats:
		var plate: LiarsDiceNameplate = app.labels.get_node_for(PLATE_KEY % pid)
		if plate != null:
			plate.set_info(state.counts.get(pid, 0), state.is_alive(pid), state.left.has(pid), pid == state.current_pid,
				_last_bid_of(pid))


func _update_info() -> void:
	if hud == null:
		return
	var cur: Variant = state.current_pid
	var bidder: Variant = state.bid.get("pid")
	var turn_text := LiarsDiceHud.turn_info_text(state.name_of(cur) if cur is int else "", cur == my_pid, not state.bid.is_empty()) \
		if state.step != LiarsDiceScreenState.STEP_OVER else ""
	var my_text := "已出局,观战中"
	if state.am_alive():
		my_text = "你:%d 颗骰子" % state.counts.get(my_pid, state.shown_dice.size())
	# step 的初值是 over:第一轮演到之前(开局运镜)不能写「对局结束」
	var over := state.started and state.step == LiarsDiceScreenState.STEP_OVER
	var bid_text := LiarsDiceHud.bid_line(state.bid, state.name_of(bidder), bidder == my_pid) if not over else "对局结束"
	hud.set_info(state.total, state.bid, bid_text,
		LiarsDiceHud.bids_line(state.bids), turn_text, my_text)


func refresh_hud() -> void:
	if hud == null:
		return
	hud.set_my_dice(state.shown_dice, state.am_alive(), _reveal_face)
	hud.set_spectating(state.started and not state.am_alive())
	_update_nameplates()
	_update_info()
	refresh_actions()


func refresh_actions() -> void:
	# 出价器:合不合法按视图的当前一口与场上总数问规则引擎(不是自己的回合时也能先选,只是「加注」「开!」不亮)
	if hud == null:
		return
	var bid := state.pub_bid() if not state.pub.is_empty() else state.bid
	var total := state.pub_total() if not state.pub.is_empty() else state.total
	var face_ok := {}
	for f in range(LiarsDiceState.MIN_BID_FACE, LiarsDiceState.FACES + 1):
		face_ok[f] = picker.face_legal(f, bid, total)
	var mine := is_my_turn()
	hud.set_picker(picker.count, picker.face, face_ok, picker.can_dec(bid, total), picker.can_inc(bid, total),
		mine and picker.is_legal(bid, total), can_challenge(), mine)


# —— 出手规则(按钮、快捷键与机器人共用)——

func is_my_turn() -> bool:
	# 演出进行到自己的回合、视图也说轮到自己、没有未回执的动作、没在结算
	return state.current_pid == my_pid and state.my_turn_in_view() and not animating and not _awaiting_intent \
		and _settlement == null


func can_challenge() -> bool:
	return is_my_turn() and state.can_challenge_in_view()


func nudge_count(delta: int) -> bool:
	if not state.am_alive() or _settlement != null:
		return false
	var changed := picker.nudge(delta, state.pub_bid(), state.pub_total())
	if changed:
		Sfx.play("ui_click")
	refresh_actions()
	return changed


func pick_face(face: int) -> bool:
	if not state.am_alive() or _settlement != null:
		return false
	var ok := picker.pick_face(face, state.pub_bid(), state.pub_total())
	if ok:
		Sfx.play("ui_click")
	refresh_actions()
	return ok


func set_pick(count: int, face: int) -> void:
	# 机器人与测试:直接把出价器摆到 count 个 face(经过与按钮相同的 nudge / pick_face)
	pick_face(face)
	var guard := 0
	while picker.count != count and guard < 64:
		guard += 1
		if not nudge_count(1 if count > picker.count else -1):
			break
	if picker.face != face:
		pick_face(face)


func submit_bid() -> bool:
	if not is_my_turn():
		return false
	var error := picker.error(state.pub_bid(), state.pub_total())
	if error != "":
		app.toast(LiarsDiceState.ERROR_MESSAGES.get(error, error), UiTheme.MUTED)
		return false
	_awaiting_intent = true
	Sfx.play("ui_click")
	_submit({"kind": "bid", "count": picker.count, "face": picker.face})
	refresh_actions()
	return true


func submit_challenge() -> bool:
	if not is_my_turn():
		return false
	if not state.can_challenge_in_view():
		app.toast(LiarsDiceState.ERROR_MESSAGES[LiarsDiceState.ERR_NO_BID], UiTheme.MUTED)
		return false
	_awaiting_intent = true
	Sfx.play("ui_click")
	_submit({"kind": "challenge"})
	refresh_actions()
	return true


func _submit(intent: Dictionary) -> void:
	if intent_sink.is_valid():
		intent_sink.call(intent)
	else:
		Net.submit_session_intent(intent)


# —— 输入 ——

static func key_action(keycode: Key) -> String:
	# 快捷键 → 动作:Enter 加注、C / 空格 开、↑↓ 个数(数字键另由 face_key 处理)
	match keycode:
		KEY_ENTER, KEY_KP_ENTER:
			return ACTION_BID
		KEY_C, KEY_SPACE:
			return ACTION_CHALLENGE
		KEY_UP:
			return ACTION_MORE
		KEY_DOWN:
			return ACTION_LESS
	return ""


static func face_key(keycode: Key) -> int:
	# 2–6(含小键盘)→ 点数;不是这几个键 -1
	return FACE_KEYS.get(keycode, -1)


func _unhandled_input(event: InputEvent) -> void:
	if _settlement != null:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_confirm_leave()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V and not app.is_modal_open():
		# 快捷语面板或九宫格开着时不切
		get_viewport().set_input_as_handled()
		if not _banter_panel_open() and not quips.menu.is_open():
			director.toggle_camera_mode()
		return
	if not state.am_alive() or app.is_modal_open():
		return
	if event is InputEventKey and event.pressed:
		if face_key(event.keycode) >= 0 and (_banter_panel_open() or quips.menu.is_open()):
			return   # 快捷语面板 / 九宫格开着:数字键归面板
		if event.echo and key_action(event.keycode) not in [ACTION_MORE, ACTION_LESS]:
			return   # 按住 ↑↓ 连续调个数;其余键不连发
		if handle_key(event.keycode):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_hover_cup(event.position)


func _hover_cup(point: Vector2) -> void:
	# 鼠标停在自己扣着的骰盅上:盅沿掀起来偷看一眼(演出中、镜头不在座位上时不掀)
	if cups == null:
		return
	if animating or director == null or not director.is_at_seat():
		cups.set_hover_peek(false)
		return
	var tavern = app.get("tavern")
	if tavern == null or tavern.camera_rig == null:
		return
	var camera: Camera3D = tavern.camera_rig.camera
	cups.set_hover_peek(cups.pick_my_cup(camera.project_ray_origin(point), camera.project_ray_normal(point)))


func handle_key(keycode: Key) -> bool:
	# 返回 true 表示这个键被用掉了
	var face := face_key(keycode)
	if face >= 0:
		pick_face(face)
		return true
	match key_action(keycode):
		ACTION_BID:
			submit_bid()
			return true
		ACTION_CHALLENGE:
			submit_challenge()
			return true
		ACTION_MORE:
			nudge_count(1)
			return true
		ACTION_LESS:
			nudge_count(-1)
			return true
	return false


func _make_quips() -> QuipController:
	# 九宫格快捷对话(同其他牌桌):他人的气泡挂在喊价气泡再往上一层,自己的在出价器上方;没有酒客的人只记日志
	var quip := QuipController.new(app, my_pid)
	quip.name_of = name_of
	quip.anchor_for = func(pid: int) -> Callable:
		if not world.patrons.has(pid):
			return Callable()
		if world.is_poker_table():
			return world.nameplate_anchor.bind(pid)
		var patron: Patron = world.patrons[pid]
		return func(): return patron.nameplate_anchor() if is_instance_valid(patron) else Vector3.ZERO
	quip.show_mine = func(text: String) -> void: hud.my_bubble(text, UiTheme.INK, Quips.BUBBLE_SECONDS)
	quip.log_line = hud.log_event
	quip.bubble_offset = Vector2(0, LiarsDiceDirector.BUBBLE_ABOVE_PLATE + QUIP_ABOVE_CLAIM)
	return quip


func _banter_panel_open() -> bool:
	var banter = app.get("banter_view")
	return banter != null and is_instance_valid(banter) and banter.is_panel_open()


func _confirm_leave() -> void:
	var overlay: ConfirmOverlay = app.confirm(HOST_LEAVE_CONFIRM if Net.is_host else LEAVE_CONFIRM, "离开")
	overlay.confirmed.connect(func(): Net.end_session())
