extends Control
# 炸弹猫牌桌控制器(规格 §3、设计稿 §7.11):接收 Net 的视图与事件 → 事件队列交给 BombCatDirector 逐个演出(演出期间锁出牌、摸牌)
# → 演出结束后按最新视图对账(3D 牌、铭牌、HUD、机位)。本地状态在 BombCatScreenState 里;3D 牌由 BombCatCards 管;视线与探头交给 SeatGaze。
# 出手一律 Net.submit_session_intent(...);被拒时 toast BombCatState.ERROR_MESSAGES 的中文。
# 「不行!」不等演出:视图在反应窗口里、自己活着、手里有不行! 就能打(谁都能打,拼的是手快)。
# 给按钮、快捷键与机器人的入口是同一套:toggle_card / submit_play / choose_target / choose_named / submit_draw /
# submit_nope / submit_reinsert / submit_give(debug_flags 的机器人走的就是它们)。


const PLATE_KEY := "plate:%d"   # WorldLabels 里对手铭牌的键
const QUIP_ABOVE_CLAIM := -56.0  # 九宫格快捷对话的气泡比出牌气泡再高这么多(屏幕像素,同骗子酒馆)
const TARGET_PICK_RADIUS := 140.0   # 选目标时在 3D 里点酒客:光标离他头的屏幕距离上限(像素)
const LEAVE_CONFIRM := "离开牌桌会被判出局,确定吗?"
const HOST_LEAVE_CONFIRM := "你是房主,离开会解散整桌,确定吗?"
const STEP_TOTALS := {
	BombCatScreenState.STEP_TURN: Protocol.TURN_TIMEOUT,
	BombCatScreenState.STEP_WINDOW: BombCatState.REACT_WINDOW,
	BombCatScreenState.STEP_REINSERT: BombCatState.REINSERT_TIMEOUT,
	BombCatScreenState.STEP_GIVE: BombCatState.GIVE_TIMEOUT,
}
const CARD_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]
const CARD_KP_KEYS := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9]
# 快捷键 → 动作(规格 §3.2):不占 T / G / Q / V / WASD / Esc / F1(T 九宫格对话、G 丢番茄、Q 快捷语);D 是探头键,摸牌只用空格
const ACTION_PLAY := "play"
const ACTION_DRAW := "draw"
const ACTION_NOPE := "nope"

var app: Node
var my_pid := 0
var hud: BombCatHud
var director: BombCatDirector
var quips: QuipController
var preview: CardPreview
var world: TableWorld
var cards: BombCatCards
var fx3d: BombCatFx                # 道具效果层(平底锅、放大镜、炸弹猫……),挂在 poker_root 下随拆台收走
var state := BombCatScreenState.new()
var animating := true
var intent_sink := Callable()     # 测试钩子:不走 Net,直接把意图交给本地会话(func(intent: Dictionary))

var _clock := TurnClock.new()
var _gaze: SeatGaze = null
var _queue: Array = []
var _intro_done := false
var _awaiting_intent := false     # 已提交出牌 / 摸牌 / 塞回 / 给牌,等房主回执
var _nope_pending := false        # 已提交不行!,等房主回执
var _selected := {}               # 私有手牌下标 -> true
var _submitted: Array = []        # 自己刚出的牌的下标(导演拿去让 3D 牌扇里对应的牌飞出去)
var _pending := {}                # 选目标 / 点名中的出牌:{"cards", "kind", "target"?}
var _settlement: BombCatSettlement = null
var _seen := {"draw": 0, "transfer": 0, "peek": 0}   # 私有视图里各种 seq 已演到哪
var _hand_before: Array = []


func _init(p_app: Node) -> void:
	app = p_app


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	my_pid = Net.my_pid()
	world = app.world
	state.my_pid = my_pid
	state.set_seats(Net.seats)
	# 桌子:骗子酒馆的桌与烛台(不摆立牌);5–6 人换德州的大桌(设计稿 §7.8)
	app.apply_table_mode(Net.game_mode)
	world.configure_table(SeatLayout.table_radius_for(Net.game_mode, Net.seats.size()))
	world.clear_poker()
	world.revive_all()
	world.cards.clear_all()
	app.labels.clear()
	world.arrange(Net.seats, my_pid, true, false)
	cards = BombCatCards.new(world)
	cards.my_pid = my_pid
	world.poker_root.add_child(cards)
	cards.sfx.connect(Sfx.play)
	fx3d = BombCatFx.new(world)
	fx3d.my_pid = my_pid
	world.poker_root.add_child(fx3d)
	fx3d.sfx.connect(Sfx.play)
	BombCatFaces.build(self)
	hud = BombCatHud.new()
	add_child(hud)
	_connect_hud()
	quips = _make_quips()
	add_child(quips)
	hud.quip_pressed.connect(quips.toggle)
	preview = _make_preview()
	add_child(preview)   # 压在 HUD 与九宫格之上;只显示,不接鼠标
	director = BombCatDirector.new(self, app, hud)
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
	# 只收走自己挂的铭牌与气泡;偷看浮在镜头前的牌、炸弹猫的 3D 节点全部拆掉
	if not is_instance_valid(app) or not is_instance_valid(world):
		return
	for pid in state.names:
		app.labels.untrack(PLATE_KEY % pid)
		app.labels.untrack(BombCatDirector.BUBBLE_KEY % pid)
		app.labels.untrack(QuipController.KEY_PREFIX % pid)
	if cards != null:
		cards.clear_peek()
	world.stop_celebration()   # 结算庆祝(舞步、礼炮、彩纸)随牌桌退场收起
	world.clear_poker()


func _process(delta: float) -> void:
	_clock.tick(delta)
	if hud == null:
		return
	var step := state.pub_step()
	var total: float = STEP_TOTALS.get(step, Protocol.TURN_TIMEOUT)
	var show_ring: bool = state.pub_current() != null and not animating and not state.pub.is_empty() \
		and step != BombCatScreenState.STEP_OVER and _settlement == null
	hud.set_countdown(_clock.remaining(), total, show_ring)
	if step == BombCatScreenState.STEP_WINDOW and _settlement == null:
		var window: Dictionary = state.pub["window"] if state.pub.get("window") is Dictionary else {}
		hud.set_window(BombCatHud.window_text(window, name_of), _clock.remaining() / BombCatState.REACT_WINDOW,
			can_nope(), state.am_alive())
	else:
		hud.set_window("", 0.0, false, false)


func _connect_hud() -> void:
	hud.rules_pressed.connect(func(): app.show_rules())
	hud.play_pressed.connect(submit_play)
	hud.draw_pressed.connect(submit_draw)
	hud.nope_pressed.connect(submit_nope)
	hud.card_clicked.connect(_on_card_clicked)
	hud.card_hovered.connect(func(i: int):
		if cards != null:
			cards.set_selection(_selected, i))
	hud.target_chosen.connect(choose_target)
	hud.named_chosen.connect(choose_named)
	hud.prompt_cancelled.connect(cancel_prompt)
	hud.reinsert_confirmed.connect(submit_reinsert)
	hud.peek_dismissed.connect(clear_peek)


func _make_gaze() -> SeatGaze:
	var gaze := SeatGaze.new(app, world, my_pid)
	gaze.gaze_free = func() -> bool: return director.is_camera_at_rest() and _settlement == null
	gaze.at_seat = director.is_at_seat
	gaze.excluded = func(pid: int) -> bool: return not state.is_alive(pid)
	gaze.rest_point = func() -> Vector3: return BombCatDirector.TABLE_FOCUS
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
	state.apply_private(view)
	# 牌堆变了(摸牌 / 洗牌 / 塞回)偷看结果就作废:浮着的牌收起来
	if state.peek_cards().is_empty() and hud != null and hud.is_peek_open():
		clear_peek()
	if not animating:
		_reconcile()
	else:
		refresh_actions()


func _on_events(events: Array) -> void:
	# 有新的一批事件 = 房主处理过了(自己的意图被接受,或局面变了):回执到了,可以再出手
	_awaiting_intent = false
	for ev in events:
		if ev is Dictionary and ev.get("type") == "noped" and ev.get("pid") == my_pid:
			_nope_pending = false
	_queue.append_array(events.filter(func(ev): return ev is Dictionary))
	if _intro_done and not animating:
		_drain()


func _on_rejected(code: String) -> void:
	_awaiting_intent = false
	_nope_pending = false
	_submitted = []
	app.toast(BombCatState.ERROR_MESSAGES.get(code, code), UiTheme.LIE)
	refresh_actions()


func _drain() -> void:
	animating = true
	refresh_actions()
	while not _queue.is_empty():
		var ev: Dictionary = _queue.pop_front()
		await director.play(ev)
	animating = false
	_reconcile()


func _reconcile() -> void:
	# 演出结束后用最新视图兜底对齐(正常流程下视觉已与状态一致)
	if state.pub.is_empty():
		return
	var before := state.shown_hand.duplicate()
	state.sync_from_view()
	if state.shown_hand != before:
		_validate_selection()
	sync_table()
	if director != null and _settlement == null and director.camera_mode() != BombCatDirector.MODE_ORBIT:
		if not state.am_alive() and state.started:
			director.spectator = true
			hud.set_spectating(true)
		director.settle_camera()


func sync_table() -> void:
	if cards == null:
		refresh_hud()
		return
	var counts := {}
	for pid in state.seats:
		counts[pid] = state.counts.get(pid, 0) if state.is_alive(pid) else 0
	cards.sync(counts, state.shown_hand, state.deck_count, state.discard_count, state.discard_recent,
		state.step == BombCatScreenState.STEP_REINSERT)
	cards.set_selection(_selected, -1)
	refresh_hud()


# —— 导演回调 ——

func name_of(pid: Variant) -> String:
	return state.name_of(pid)


func note_event(ev: Dictionary) -> void:
	state.apply_event(ev)
	_update_nameplates()
	_update_info()


func set_current(pid: Variant, turns := 1) -> void:
	_clock.restart_turn()
	_awaiting_intent = false
	if hud == null:
		return
	var focus := BombCatDirector.TABLE_FOCUS
	if pid is int and world.patrons.has(pid):
		focus = world.head_position(pid)
	for patron_pid in world.patrons:
		var patron: Patron = world.patrons[patron_pid]
		patron.set_active(patron_pid == pid)
		if patron.alive:
			patron.look_at_point(BombCatDirector.TABLE_FOCUS if patron_pid == pid else focus)
	if pid == null:
		hud.set_turn("", false)
	elif pid == my_pid:
		hud.set_turn("轮到你了" if turns <= 1 else "轮到你了 · 要走 %d 回合" % turns, true)
		Sfx.play("join")
		if app.is_rules_open():
			app.toast("轮到你了!按 %s 合上说明书" % OS.get_keycode_string(Rulebook.HOTKEY), UiTheme.BRASS_BRIGHT)
	else:
		hud.set_turn("等待 %s 行动…" % name_of(pid), false)
	_update_nameplates()
	_update_info()
	refresh_actions()


func take_submitted() -> Array:
	var indices := _submitted
	_submitted = []
	_awaiting_intent = false
	return indices


func refresh_my_hand(flash_last := false) -> void:
	# 导演改了屏幕上的手牌(state.shown_hand):2D 手牌条跟着变;3D 牌扇由 BombCatCards 自己的动画处理
	_validate_selection()
	if hud != null:
		hud.set_hand(state.shown_hand, _selected, state.am_alive())
		if flash_last:
			hud.strip.flash(state.shown_hand.size() - 1)
	refresh_actions()


func mark_out(pid: int) -> void:
	if _gaze != null:
		_gaze.forget(pid)
	if pid == my_pid:
		_selected = {}
		_pending = {}
		if hud != null:
			hud.hide_prompt()
			hud.set_spectating(true)
			clear_peek()
	_update_nameplates()


func wait_private_hand(max_wait: float) -> Array:
	# 开局:私有手牌通常紧随事件到达;最多等 max_wait
	var waited := 0.0
	while state.private_hand().is_empty() and waited < max_wait and is_inside_tree():
		await get_tree().process_frame
		waited += get_process_delta_time()
	state.shown_hand = state.private_hand()
	return state.shown_hand.duplicate()


func wait_drawn(max_wait: float) -> Dictionary:
	await _wait_seq("draw", func() -> int: return state.last_drawn()["seq"], max_wait)
	return state.last_drawn()


func wait_transfer(max_wait: float) -> Dictionary:
	await _wait_seq("transfer", func() -> int: return BombCatScreenState._int(state.transfer(), "seq"), max_wait)
	return state.transfer()


func wait_peek(max_wait: float) -> void:
	await _wait_seq("peek", state.peek_seq, max_wait)


func _wait_seq(key: String, seq: Callable, max_wait: float) -> void:
	# 私有视图里这种 seq 比上次演到的大了 = 新的一次(同一份私有视图每批都重发)
	var waited := 0.0
	while seq.call() <= _seen[key] and waited < max_wait and is_inside_tree():
		await get_tree().process_frame
		waited += get_process_delta_time()
	_seen[key] = maxi(_seen[key], seq.call())


func show_peek() -> void:
	var ids := state.peek_cards()
	if ids.is_empty() or hud == null:
		return
	hud.show_peek(ids)
	var camera: Node3D = app.tavern.camera_rig.camera if app.tavern != null and app.tavern.camera_rig != null else null
	cards.show_peek(ids, camera)


func clear_peek() -> void:
	if hud != null:
		hud.hide_peek()
	if cards != null:
		cards.clear_peek()


func show_settlement() -> void:
	if _settlement != null:
		return
	var rows := state.ranking_rows()
	var winner: Variant = state.winner
	hud.hide_prompt()
	hud.set_away_from_seat(true)
	_settlement = BombCatSettlement.new(name_of(winner), rows, winner == my_pid, Net.is_host)
	_settlement.lobby_pressed.connect(func():
		Sfx.play("ui_click")
		Net.request_rematch_lobby())
	_settlement.leave_pressed.connect(func():
		Sfx.play("ui_click")
		Net.end_session())
	add_child(_settlement)


func settlement() -> BombCatSettlement:
	return _settlement


# —— 铭牌与 HUD ——

func _build_nameplates() -> void:
	for pid in state.seats:
		if pid == my_pid or not world.patrons.has(pid):
			continue
		var anchor: Callable = world.nameplate_anchor.bind(pid) if world.is_poker_table() else world.patrons[pid].nameplate_anchor
		app.labels.track(PLATE_KEY % pid, BombCatNameplate.new(state.name_of(pid)), anchor)
	_update_nameplates()


func pulse_nameplate(pid: Variant) -> void:
	# 轮到他了:铭牌亮一下(自己没有铭牌,有回合横幅)
	if not pid is int or app == null or app.get("labels") == null:
		return
	var plate: Variant = app.labels.get_node_for(PLATE_KEY % pid)
	if plate is BombCatNameplate:
		plate.pulse()


func _update_nameplates() -> void:
	if app == null or app.get("labels") == null:
		return
	for pid in state.seats:
		var plate: BombCatNameplate = app.labels.get_node_for(PLATE_KEY % pid)
		if plate != null:
			plate.set_info(state.counts.get(pid, 0), state.is_alive(pid), state.exploded.has(pid), pid == state.current_pid, state.turns)


func _update_info() -> void:
	if hud == null:
		return
	var cur: Variant = state.current_pid
	var turn_text := BombCatHud.turn_info_text(state.name_of(cur) if cur is int else "", cur == my_pid, state.turns, state.step) \
		if state.step != BombCatScreenState.STEP_OVER else ""
	var my_text := "已出局,观战中"
	if state.am_alive():
		var defuses := state.shown_hand.count(BombCatCard.DEFUSE)
		var nopes := state.shown_hand.count(BombCatCard.NOPE)
		my_text = "你:手牌 %d 张 · 拆弹 ×%d · 不行! ×%d" % [state.shown_hand.size(), defuses, nopes]
	hud.set_info(state.deck_count, state.bombs_left, state.bombs_total, turn_text, my_text)


func refresh_hud() -> void:
	if hud == null:
		return
	hud.set_hand(state.shown_hand, _selected, state.am_alive())
	hud.set_spectating(state.started and not state.am_alive())
	_update_nameplates()
	_update_info()
	refresh_actions()


func refresh_actions() -> void:
	if hud == null:
		return
	_update_prompts()
	var mine := is_my_turn()
	var kind := state.selection_kind(_selected_indices())
	var can_play := mine and kind != "" and _pending.is_empty()
	var hint := state.selection_hint(_selected_indices()) if not _selected.is_empty() else ""
	if hud.prompt_kind == BombCatHud.PROMPT_GIVE:
		hint = "被讨要:点一张手牌给出去"
	hud.set_actions(can_play, mine and _pending.is_empty(), _selected.size(), mine, hint)
	hud.set_hand(state.shown_hand, _selected, state.am_alive())


func _update_prompts() -> void:
	# 塞回滑块与给牌提示按视图出现(演完之后);选目标 / 点名只在自己回合
	if _settlement != null:
		hud.hide_prompt()
		return
	var ready := not animating and not _awaiting_intent
	if ready and state.reinsert_max() >= 0 and state.pub_step() == BombCatScreenState.STEP_REINSERT:
		if hud.prompt_kind != BombCatHud.PROMPT_REINSERT:
			hud.show_reinsert(state.reinsert_max())
		return
	if ready and state.give_to() != null and state.pub_step() == BombCatScreenState.STEP_GIVE:
		if hud.prompt_kind != BombCatHud.PROMPT_GIVE:
			hud.show_give(name_of(state.give_to()))
		return
	if hud.prompt_kind == BombCatHud.PROMPT_REINSERT or hud.prompt_kind == BombCatHud.PROMPT_GIVE:
		hud.hide_prompt()
	if not _pending.is_empty() and not is_my_turn():
		_pending = {}
		hud.hide_prompt()


# —— 出手规则(按钮、快捷键与机器人共用)——

func is_my_turn() -> bool:
	# 演出进行到自己的回合、视图也说轮到自己、没有未回执的动作、没在结算
	return state.current_pid == my_pid and state.my_turn_in_view() and not animating and not _awaiting_intent \
		and _settlement == null


func can_nope() -> bool:
	return state.can_nope() and not _nope_pending and _settlement == null


func can_reinsert() -> bool:
	return state.reinsert_max() >= 0 and not animating and not _awaiting_intent and _settlement == null


func can_give() -> bool:
	return state.give_to() != null and not animating and not _awaiting_intent and _settlement == null


func selected_indices() -> Array:
	return _selected_indices()


func pending_play() -> Dictionary:
	return _pending.duplicate()


func clear_selection() -> void:
	_selected = {}
	if cards != null:
		cards.set_selection(_selected, -1)
	refresh_actions()


func toggle_card(index: int) -> void:
	# 选牌:单张功能牌只能单选,零食可以选两三张一样的;点别的牌就换成选那张
	if not state.am_alive() or index < 0 or index >= state.shown_hand.size() or not _pending.is_empty():
		return
	if _selected.has(index):
		_selected.erase(index)
	elif state.can_select_more(_selected_indices(), index):
		_selected[index] = true
	else:
		_selected = {index: true}
	Sfx.play("ui_click")
	if cards != null:
		cards.set_selection(_selected, -1)
	refresh_actions()


func submit_play() -> bool:
	if not is_my_turn() or _selected.is_empty() or not _pending.is_empty():
		return false
	var indices := _selected_indices()
	var kind := state.selection_kind(indices)
	if kind == "":
		app.toast(state.selection_hint(indices), UiTheme.MUTED)
		return false
	if BombCatScreenState.needs_target(kind):
		var candidates := state.target_candidates()
		if candidates.is_empty():
			app.toast("没有能选的人:别人手里都没牌了", UiTheme.MUTED)
			return false
		_pending = {"cards": indices, "kind": kind}
		var rows := candidates.map(func(pid: int) -> Dictionary:
			return {"pid": pid, "name": name_of(pid), "count": state.counts.get(pid, 0)})
		var title := "讨要谁的牌?" if kind == BombCatCard.BEG else "从谁手里要?"
		hud.show_targets(rows, title)
		refresh_actions()
		return true
	return _send_play(indices, null, "")


func choose_target(pid: int) -> bool:
	if _pending.is_empty() or not is_my_turn():
		return false
	if not state.is_valid_target(pid):
		app.toast(BombCatState.ERROR_MESSAGES[BombCatState.ERR_INVALID_TARGET], UiTheme.MUTED)
		return false
	_pending["target"] = pid
	if BombCatScreenState.needs_named(_pending["kind"]):
		hud.show_named()
		return true
	return _send_play(_pending["cards"], pid, "")


func choose_named(id: String) -> bool:
	if _pending.is_empty() or not _pending.has("target") or not BombCatCard.can_be_named(id):
		return false
	return _send_play(_pending["cards"], _pending["target"], id)


func cancel_prompt() -> void:
	if hud.prompt_kind == BombCatHud.PROMPT_TARGET or hud.prompt_kind == BombCatHud.PROMPT_NAMED:
		_pending = {}
		hud.hide_prompt()
		refresh_actions()


func _send_play(indices: Array, target: Variant, named: String) -> bool:
	var intent := {"kind": "play", "cards": indices.duplicate()}
	if target is int:
		intent["target"] = target
	if named != "":
		intent["named"] = named
	_submitted = indices.duplicate()
	_awaiting_intent = true
	_selected = {}
	_pending = {}
	hud.hide_prompt()
	Sfx.play("ui_click")
	_submit(intent)
	refresh_actions()
	return true


func submit_draw() -> bool:
	if not is_my_turn() or not _pending.is_empty():
		return false
	_awaiting_intent = true
	_selected = {}
	Sfx.play("ui_click")
	_submit({"kind": "draw"})
	refresh_actions()
	return true


func submit_nope() -> bool:
	if not can_nope():
		return false
	_nope_pending = true
	Sfx.play("ui_click")
	_submit({"kind": "nope"})
	return true


func submit_reinsert(pos: int) -> bool:
	if not can_reinsert() or pos < 0 or pos > state.reinsert_max():
		return false
	_awaiting_intent = true
	hud.hide_prompt()
	Sfx.play("ui_click")
	_submit({"kind": "reinsert", "pos": pos})
	refresh_actions()
	return true


func submit_give(index: int) -> bool:
	if not can_give() or index < 0 or index >= state.private_hand().size():
		return false
	_awaiting_intent = true
	_selected = {}
	hud.hide_prompt()
	Sfx.play("ui_click")
	_submit({"kind": "give", "index": index})
	refresh_actions()
	return true


func _submit(intent: Dictionary) -> void:
	if intent_sink.is_valid():
		intent_sink.call(intent)
	else:
		Net.submit_session_intent(intent)


func _on_card_clicked(index: int) -> void:
	if can_give():
		submit_give(index)
		return
	toggle_card(index)


func _selected_indices() -> Array:
	var out := _selected.keys()
	out.sort()
	return out


func _validate_selection() -> void:
	# 手牌变了(摸牌、被抢、出牌):下标可能落到别的牌上,预选作废
	if state.shown_hand != _hand_before:
		_selected = {}
		_hand_before = state.shown_hand.duplicate()


# —— 输入 ——

static func key_action(keycode: Key) -> String:
	# 快捷键 → 动作:Enter 出牌、空格摸牌、N 不行!(数字键另由 card_key_index 处理)
	match keycode:
		KEY_ENTER, KEY_KP_ENTER:
			return ACTION_PLAY
		KEY_SPACE:
			return ACTION_DRAW
		KEY_N:
			return ACTION_NOPE
	return ""


static func card_key_index(keycode: Key) -> int:
	# 1–9(含小键盘)→ 第几张手牌;不是数字键 -1
	var at := CARD_KEYS.find(keycode)
	return at if at >= 0 else CARD_KP_KEYS.find(keycode)


func _unhandled_input(event: InputEvent) -> void:
	if _settlement != null:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if hud.is_peek_open():
			clear_peek()
		elif hud.prompt_kind == BombCatHud.PROMPT_TARGET or hud.prompt_kind == BombCatHud.PROMPT_NAMED:
			cancel_prompt()
		else:
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
	if event is InputEventKey and event.pressed and not event.echo:
		if card_key_index(event.keycode) >= 0 and _banter_panel_open():
			return   # 快捷语面板开着:数字键归面板(它没用掉的 9 也不拿来选牌)
		if handle_key(event.keycode):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _handle_click(event.position):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and not animating:
		var index := _pick_card(event.position)
		cards.set_selection(_selected, index)


func _make_quips() -> QuipController:
	# 九宫格快捷对话(同骗子酒馆):他人的气泡挂在出牌气泡再往上一层,自己的在出牌按钮行上方;没有酒客的人只记日志
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
	quip.bubble_offset = Vector2(0, BombCatDirector.BUBBLE_ABOVE_PLATE + QUIP_ABOVE_CLAIM)
	return quip


func _make_preview() -> CardPreview:
	# 悬停大图(带牌名与说明):底部 2D 手牌条、3D 牌扇里自己的牌、弃牌堆顶上摊开的几张(牌背不算);
	# 镜头去拍特写、快捷语面板或九宫格开着、说明书或确认框盖着、结算时藏起
	var card_preview := CardPreview.new()
	card_preview.source = func(point: Vector2) -> Array:
		var out: Array = hud.strip.preview_candidates() if hud != null else []
		var tavern = app.get("tavern")
		if cards != null and tavern != null:
			out.append_array(CardPreview.world_candidates(tavern.camera_rig.camera, point, cards.hoverable_cards()))
		return out
	card_preview.gate = func() -> Dictionary:
		return {"camera_at_rest": director != null and director.is_camera_at_rest(),
			"panel_open": _banter_panel_open() or (quips != null and quips.menu.is_open()),
			"modal_open": app.is_modal_open(), "settlement": _settlement != null}
	return card_preview


func _banter_panel_open() -> bool:
	var banter = app.get("banter_view")
	return banter != null and is_instance_valid(banter) and banter.is_panel_open()


func handle_key(keycode: Key) -> bool:
	# 返回 true 表示这个键被用掉了
	var index := card_key_index(keycode)
	if index >= 0:
		if can_give():
			submit_give(index)
		else:
			toggle_card(index)
		return true
	if hud.prompt_kind == BombCatHud.PROMPT_REINSERT:
		match keycode:
			KEY_LEFT:
				hud.nudge_reinsert(-1)
				return true
			KEY_RIGHT:
				hud.nudge_reinsert(1)
				return true
			KEY_ENTER, KEY_KP_ENTER:
				submit_reinsert(hud.reinsert_value())
				return true
	match key_action(keycode):
		ACTION_PLAY:
			submit_play()
			return true
		ACTION_DRAW:
			submit_draw()
			return true
		ACTION_NOPE:
			submit_nope()
			return true
	return false


func _handle_click(screen_pos: Vector2) -> bool:
	# 选目标时点 3D 里的酒客;平时点自己 3D 牌扇里的牌
	if hud.prompt_kind == BombCatHud.PROMPT_TARGET:
		var pid := pick_patron(screen_pos)
		if pid != -1:
			choose_target(pid)
			return true
		return false
	var index := _pick_card(screen_pos)
	if index >= 0:
		_on_card_clicked(index)
		return true
	return false


func pick_patron(screen_pos: Vector2) -> int:
	# 光标离哪位候选酒客的头最近(屏幕投影距离 ≤ TARGET_PICK_RADIUS);没有 -1
	var camera: Camera3D = app.tavern.camera_rig.camera
	var best := -1
	var best_dist := TARGET_PICK_RADIUS
	for pid in state.target_candidates():
		if not world.patrons.has(pid):
			continue
		var head: Vector3 = world.patrons[pid].head_position()
		if camera.is_position_behind(head):
			continue
		var dist := camera.unproject_position(head).distance_to(screen_pos)
		if dist < best_dist:
			best_dist = dist
			best = pid
	return best


func _pick_card(screen_pos: Vector2) -> int:
	if animating or cards == null:
		return -1
	var camera: Camera3D = app.tavern.camera_rig.camera
	return cards.pick(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))


func _confirm_leave() -> void:
	var overlay: ConfirmOverlay = app.confirm(HOST_LEAVE_CONFIRM if Net.is_host else LEAVE_CONFIRM, "离开")
	overlay.confirmed.connect(func(): Net.end_session())
