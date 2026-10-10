extends Control
# 牌桌控制器:接收 Net 的视图与事件 → 事件队列交给导演逐个演出(演出期间锁输入)→
# 演出结束后按最新状态对账。负责手牌拾取、快捷键、意图提交、倒计时与铭牌;视线与探头交给 SeatGaze。


const PLATE_KEY := "plate:%d"   # WorldLabels 里对手铭牌的键
const QUIP_ABOVE_CLAIM := -56.0  # 快捷对话气泡比出牌气泡再高这么多(屏幕像素)

var app: Node
var my_pid := 0
var hud: TableHud
var director: TableDirector
var quips: QuipController
var preview: CardPreview
var world: TableWorld
var cards: CardTable

var pub := {}
var names := {}
var animating := true
var current_pid = null

var _clock := TurnClock.new()
var _gaze: SeatGaze = null   # 视线与探头;_ready 时建(不入树的测试里为空)
var _queue: Array = []
var _intro_done := false
var _initial_hands := {}    # round -> 该局初始手牌(发牌动画使用)
var _my_hand: Array = []
var _selected := {}
var _hovered := -1
var _submitted: Array = []
var _awaiting_intent := false
var _dead := {}
var _shots := {}
var _elimination_order: Array = []
var _round_now := 0         # 演出进行到的局号(按事件流,不按已领先的公共状态)
var _out_round := {}        # pid -> 出局时所在的局号(结算显示存活局数)
var _settlement: Settlement = null


func _init(p_app: Node) -> void:
	app = p_app


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	my_pid = Net.my_pid()
	world = app.world
	cards = world.cards
	# 从德州房间出来再进骗子酒馆:桌子、烛台、立牌、左轮都按本玩法复原(规格 §5.1)
	app.apply_table_mode(Net.game_mode)
	for seat in Net.seats:
		names[seat["pid"]] = seat["name"]
		_shots[seat["pid"]] = 0
	world.revive_all()
	cards.clear_all()
	app.labels.clear()
	# 第三人称:自己的角色也坐在桌边,手牌由自己的角色举在胸前、牌面朝向越肩镜头
	world.arrange(Net.seats, my_pid, true, true)
	var me: Patron = world.patrons[my_pid]
	me.present_hand_to(world.third_person_view(my_pid).origin)
	cards.attach_hand(me.fan)
	hud = TableHud.new()
	add_child(hud)
	hud.play_pressed.connect(_submit_play)
	hud.challenge_pressed.connect(_submit_challenge)
	hud.rules_pressed.connect(func(): app.show_rules())
	hud.set_my_status(names.get(my_pid, ""), 0, true)
	quips = _make_quips()
	add_child(quips)
	hud.quip_pressed.connect(quips.toggle)
	preview = _make_preview()
	add_child(preview)   # 压在 HUD 与九宫格之上;只显示,不接鼠标
	director = TableDirector.new(self, app, hud)
	add_child(director)
	_build_nameplates()
	Net.state_public_updated.connect(_on_public)
	Net.state_private_updated.connect(_on_private)
	Net.game_events.connect(_on_events)
	Net.intent_rejected.connect(_on_rejected)
	_gaze = _make_gaze()
	add_child(_gaze)   # 入树时连上 Net.gaze_updated,之后每帧跟光标、跟他人视线
	if not Net.last_public.is_empty():
		_on_public(Net.last_public)
	if not Net.last_private.is_empty():
		_on_private(Net.last_private)
	_refresh_actions()
	await director.intro()
	_intro_done = true
	_drain()


func _exit_tree() -> void:
	# 只收走自己挂的铭牌与气泡:切屏时新屏幕先 _ready、旧屏幕帧末才退场,
	# 再来一局回到等待厅时,等待厅已经挂好了它自己的铭牌,不能整层清空
	for pid in names:
		app.labels.untrack(PLATE_KEY % pid)
		app.labels.untrack(TableDirector.BUBBLE_KEY % pid)
		app.labels.untrack(QuipController.KEY_PREFIX % pid)
	if world != null and is_instance_valid(world):
		world.stop_celebration()   # 结算庆祝(舞步、礼炮、彩纸)随牌桌退场收起


func _process(delta: float) -> void:
	# delta 随 Engine.time_scale 缩放,与房主的回合 Timer 同速(--fast 时圆环也对得上)
	_clock.tick(delta)
	var show_ring: bool = current_pid != null and not animating and not pub.is_empty()
	hud.set_countdown(_clock.remaining(), Protocol.TURN_TIMEOUT, show_ring)


func _make_quips() -> QuipController:
	# 快捷对话:他人的气泡挂在出牌气泡再往上一层(两句可以同时在),自己的在出牌按钮行上方
	var quip := QuipController.new(app, my_pid)
	quip.name_of = func(pid: int) -> String: return names.get(pid, "?")
	quip.anchor_for = func(pid: int) -> Callable:
		if not world.patrons.has(pid):
			return Callable()
		var patron: Patron = world.patrons[pid]
		return func(): return patron.nameplate_anchor() if is_instance_valid(patron) else Vector3.ZERO
	quip.show_mine = func(text: String) -> void: hud.my_bubble(text, UiTheme.INK, Quips.BUBBLE_SECONDS)
	quip.log_line = hud.log_event
	quip.bubble_offset = Vector2(0, TableDirector.BUBBLE_ABOVE_PLATE + QUIP_ABOVE_CLAIM)
	return quip


func _make_preview() -> CardPreview:
	# 悬停大图:自己牌扇里的牌、翻牌行翻开的牌(牌背与出牌区不算);镜头去拍特写 / 开枪、
	# 快捷语面板或九宫格开着、说明书或确认框盖着、结算时藏起
	var card_preview := CardPreview.new()
	card_preview.source = func(point: Vector2) -> Array:
		var tavern = app.get("tavern")
		if tavern == null or cards == null:
			return []
		return CardPreview.world_candidates(tavern.camera_rig.camera, point, cards.my_cards + cards.revealed)
	card_preview.gate = func() -> Dictionary:
		return {"camera_at_rest": director != null and director.is_camera_at_rest(), "panel_open": _chat_open(),
			"modal_open": app.is_modal_open(), "settlement": _settlement != null}
	return card_preview


func _chat_open() -> bool:
	# 快捷语面板(BanterView)或九宫格快捷对话开着
	var banter = app.get("banter_view")
	return (banter != null and is_instance_valid(banter) and banter.is_panel_open()) or (quips != null and quips.menu.is_open())


func _make_gaze() -> SeatGaze:
	# 镜头没在拍特写(越肩机位或观战俯视)、对局没结算:视线归各玩家自己,否则交还给演出;
	# 出局的人不跟随视线;别人停发视线后看回桌心立牌
	var gaze := SeatGaze.new(app, world, my_pid)
	gaze.gaze_free = func() -> bool: return director != null and director.is_camera_at_rest() and _settlement == null
	gaze.at_seat = director.is_at_seat
	gaze.excluded = is_marked_dead
	gaze.rest_point = cards.stand_position
	return gaze


# —— 网络输入 ——

func _on_public(state: Dictionary) -> void:
	pub = state
	# 房主权威的回合剩余时间(含演出补时);旧版房主没有这个字段(-1)时退回本地计时
	_clock.sync_from_host(state.get("turn_time_left", -1.0))
	if not animating:
		_reconcile()


func _on_private(state: Dictionary) -> void:
	_my_hand = state.get("hand", [])
	var round_number: int = state.get("round", 0)
	if not _initial_hands.has(round_number):
		_initial_hands[round_number] = _my_hand.duplicate()
	if not animating:
		_reconcile()


func _on_events(events: Array) -> void:
	_queue.append_array(events)
	if _intro_done and not animating:
		_drain()


func _on_rejected(code: String) -> void:
	_awaiting_intent = false
	_submitted = []
	app.toast(Protocol.ERROR_MESSAGES.get(code, code), UiTheme.LIE)
	_refresh_actions()


func _drain() -> void:
	animating = true
	_refresh_actions()
	while not _queue.is_empty():
		var ev: Dictionary = _queue.pop_front()
		await director.play(ev)
	animating = false
	_reconcile()
	_refresh_actions()


func _reconcile() -> void:
	# 演出结束后用最新状态兜底对齐(正常流程下视觉已与状态一致)
	if pub.is_empty():
		return
	var counts := {}
	for p in pub["players"]:
		counts[p["pid"]] = p["hand_count"] if p["alive"] else 0
	if not _dead.has(my_pid) and _settlement == null:
		cards.sync(counts, _my_hand)
		if _selected.keys().any(func(i): return i >= _my_hand.size()):
			_selected = {}
		cards.set_selection(_selected, _hovered)
	_update_nameplates()


# —— 导演回调 ——

func name_of(pid) -> String:
	return names.get(pid, "?")


func alive_order() -> Array:
	var order := []
	for seat in Net.seats:
		if not _dead.has(seat["pid"]):
			order.append(seat["pid"])
	return order


func initial_hand(round_number: int) -> Array:
	# 新一局的私有手牌通常紧随事件到达;最多等 3 秒
	var waited := 0.0
	while not _initial_hands.has(round_number) and waited < 3.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return _initial_hands.get(round_number, _my_hand)


func take_submitted() -> Array:
	var indices := _submitted
	_submitted = []
	_awaiting_intent = false
	_selected = {}
	_hovered = -1
	return indices


func begin_round(round_number: int) -> void:
	# 导演在收牌前调用。记下局号(结算的存活局数);新一局发的是一套新手牌,
	# 旧下标会落到别的牌上,预选一律作废(牌的视觉由 CardTable.sweep 一起收走)
	_round_now = round_number
	_selected = {}
	_hovered = -1
	_refresh_actions()


func set_current(pid) -> void:
	current_pid = pid
	_clock.restart_turn()
	_awaiting_intent = false
	# 所有人盯着当前行动者,行动者自己看桌心
	var focus := cards.stand_position()
	if pid != null:
		focus = world.head_position(pid)
	for patron_pid in world.patrons:
		var patron: Patron = world.patrons[patron_pid]
		patron.set_active(patron_pid == pid)
		patron.look_at_point(cards.stand_position() if patron_pid == pid else focus)
	if pid == null:
		hud.set_turn("", false)
	elif pid == my_pid:
		hud.set_turn("轮到你了", true)
		Sfx.play("join")
		if app.is_rules_open():
			# 说明书挡住了牌桌,而回合计时不会暂停
			app.toast("轮到你了!按 %s 合上说明书" % OS.get_keycode_string(Rulebook.HOTKEY), UiTheme.BRASS_BRIGHT)
	else:
		hud.set_turn("等待 %s 行动…" % name_of(pid), false)
	_update_nameplates()
	_refresh_actions()


func on_gunshot_resolved(pid: int, shots_fired: int, hit: bool) -> void:
	_shots[pid] = shots_fired
	if hit:
		mark_eliminated(pid)
	_update_nameplates()
	if pid == my_pid:
		hud.set_my_status(name_of(my_pid), shots_fired, not hit)


func mark_eliminated(pid: int) -> void:
	if _dead.has(pid):
		return
	_dead[pid] = true
	if _gaze != null:
		_gaze.forget(pid)
	_elimination_order.append(pid)
	_out_round[pid] = _round_now
	if pid == my_pid:
		hud.set_my_status(name_of(my_pid), _shots.get(pid, 0), false)
		hud.set_actions_visible(false)


func is_marked_dead(pid: int) -> bool:
	return _dead.has(pid)


func player_stats() -> Dictionary:
	# 结算用:名字、扣扳机次数、存活局数(出局者算到出局那一局,胜者算到最后一局)
	var stats := {}
	for pid in names:
		stats[pid] = {"name": name_of(pid), "shots": _shots.get(pid, 0), "rounds": _out_round.get(pid, _round_now)}
	return stats


func show_settlement(winner) -> void:
	var ranking := Settlement.build_ranking(winner, _elimination_order, player_stats())
	hud.set_actions_visible(false)
	_settlement = Settlement.new(name_of(winner), ranking, winner == my_pid)
	add_child(_settlement)


# —— 铭牌 ——

func _build_nameplates() -> void:
	for seat in Net.seats:
		var pid: int = seat["pid"]
		if pid == my_pid or not world.patrons.has(pid):
			continue
		var patron: Patron = world.patrons[pid]
		app.labels.track(PLATE_KEY % pid, Nameplate.new(seat["name"]), patron.nameplate_anchor)
	_update_nameplates()


func _update_nameplates() -> void:
	var counts := {}
	if not pub.is_empty():
		for p in pub["players"]:
			counts[p["pid"]] = p["hand_count"]
	for seat in Net.seats:
		var pid: int = seat["pid"]
		var plate: Nameplate = app.labels.get_node_for(PLATE_KEY % pid)
		if plate == null:
			continue
		var held: int = cards.held.get(pid, []).size() if animating else counts.get(pid, 0)
		plate.set_info(held, _shots.get(pid, 0), not _dead.has(pid), pid == current_pid)


# —— 输入 ——

func _unhandled_input(event: InputEvent) -> void:
	if _settlement != null:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_confirm_leave()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		# V 切换越肩 / 第一人称:出局后也能改设置(观战机位不变,下次回到座位生效);快捷语面板或九宫格开着时不切
		get_viewport().set_input_as_handled()
		if not _chat_open():
			director.toggle_camera_mode()
		return
	if _dead.has(my_pid):
		return
	if event is InputEventMouseMotion:
		var index := _pick(event.position)
		if index != _hovered:
			_hovered = index
			if index >= 0:
				Sfx.play("ui_hover")
			cards.set_selection(_selected, _hovered)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var index := _pick(event.position)
		if index >= 0:
			get_viewport().set_input_as_handled()
			_toggle(index)
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)


func _handle_key(event: InputEventKey) -> void:
	var key := event.keycode
	if key >= KEY_1 and key <= KEY_5:
		_toggle(key - KEY_1)
	elif key == KEY_ENTER or key == KEY_KP_ENTER:
		_submit_play()
	elif key == KEY_C or key == KEY_SPACE:
		_submit_challenge()


func _pick(screen_pos: Vector2) -> int:
	if animating or cards.my_cards.is_empty():
		return -1
	var camera: Camera3D = app.tavern.camera_rig.camera
	return cards.pick(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))


func _toggle(index: int) -> void:
	if animating or _awaiting_intent or index >= cards.my_cards.size():
		return
	if _selected.has(index):
		_selected.erase(index)
	elif _selected.size() < Rules.MAX_PLAY:
		_selected[index] = true
	else:
		app.toast("一次最多出 %d 张" % Rules.MAX_PLAY, UiTheme.MUTED)
		return
	Sfx.play("ui_click")
	cards.set_selection(_selected, _hovered)
	_refresh_actions()


func _my_turn() -> bool:
	return current_pid == my_pid and not animating and not _awaiting_intent and _settlement == null


static func is_challengeable(last_play: Dictionary, viewer_pid: int) -> bool:
	# 只能质疑别人的出牌:出牌者之后的人都断线或打空手牌时,轮转可能回到出牌者本人
	if last_play.is_empty():
		return false
	var by = last_play.get("pid")
	return not (by is int and by == viewer_pid)


func _can_challenge() -> bool:
	return _my_turn() and is_challengeable(pub.get("last_play", {}), my_pid)


func _refresh_actions() -> void:
	if hud == null:
		return
	var mine := _my_turn()
	var can_play := mine and _selected.size() >= Rules.MIN_PLAY and _selected.size() <= Rules.MAX_PLAY
	hud.set_actions(can_play, _can_challenge(), _selected.size(), mine)


func _submit_play() -> void:
	if not _my_turn() or _selected.is_empty():
		return
	var indices := _selected.keys()
	indices.sort()
	_submitted = indices
	_awaiting_intent = true
	Sfx.play("ui_click")
	Net.submit_play(indices)
	_refresh_actions()


func _submit_challenge() -> void:
	if not _can_challenge():
		return
	_awaiting_intent = true
	# 选了质疑就不出这些牌:预选的牌放回牌扇
	_selected = {}
	cards.set_selection(_selected, _hovered)
	Sfx.play("ui_click")
	Net.submit_challenge()
	_refresh_actions()


func _confirm_leave() -> void:
	var overlay: ConfirmOverlay = app.confirm("离开牌桌会被判出局,确定吗?" if not Net.is_host else "你是房主,离开会解散整桌,确定吗?", "离开")
	overlay.confirmed.connect(func(): Net.end_session())
