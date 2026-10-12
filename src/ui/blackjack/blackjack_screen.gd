extends Control
# 21 点牌桌控制器(设计稿 §3、§4):接收 Net 的视图与事件 → 事件队列交给 BlackjackDirector 逐个演出(演出期间锁输入)
# → 演出结束后按最新视图对账(3D 的牌与筹码、铭牌、HUD、机位)。结构同德州牌桌(PokerScreen)。
# 本地状态在 BjScreenState 里;3D 节点由 BjCards / BjChips 管;视线与探头交给 SeatGaze。
# 任何时刻都能只凭公共视图把整张桌摆对(中途加入的人靠它画出进行中的这一局),事件只负责动画。
# 给按钮、快捷键与调试 bot 的入口同路径:can_bet / submit_bet / submit_skip / legal / submit_action / choose_rebuy / choose_sit_in。


const PLATE_KEY := "plate:%d"
const ERROR_MESSAGES := {
	"not_your_turn": "还没轮到你",
	"invalid_action": "现在不能这么做",
	"invalid_amount": "下注金额不合法",
	"invalid_intent": "现在不能这么做",
	"not_betting": "现在不是下注的时候",
	"no_round": "现在没有进行中的牌局",
	"session_over": "牌局已经结束",
	"cannot_rebuy": "现在不能领取筹码",
	"not_seated": "你不在这场牌局里",
}
const END_CONFIRM := "散局:还没发牌就立即结算(押的注退回),打牌中就打完这一局再结算。确定吗?"
const LEAVE_CONFIRM := "离开牌桌后,已经发了牌的手按停牌和庄家比,确定吗?"
const HOST_LEAVE_CONFIRM := "你是房主,离开会解散整桌,确定吗?"
const QUIP_GAP := 6.0
const MY_ACTION_EVENTS := ["bet_placed", "bet_skipped", "hit", "stand", "double", "split", "surrender"]

var app: Node
var my_pid := 0
var hud: BjHud
var director: BlackjackDirector
var world: TableWorld
var cards: BjCards
var chips: BjChips
var state := BjScreenState.new()
var animating := true
var late := false
var quips: QuipController
var preview: CardPreview
var intent_sink := Callable()   # 测试钩子:不走 Net,直接把意图交给本地会话(func(intent: Dictionary))

var _clock := TurnClock.new()
var _gaze: SeatGaze = null
var _queue: Array = []
var _intro_done := false
var _awaiting_intent := false
var _seat_request_pending := false
var _settlement: PokerSettlement = null
var _end_requested := false
var _last_bet := 0


func _init(p_app: Node) -> void:
	app = p_app


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	my_pid = Net.my_pid()
	world = app.world
	state.set_seats(Net.seats)
	late = not state.seats.has(my_pid)
	app.apply_table_mode(Net.game_mode)
	world.clear_poker()
	world.revive_all()
	world.cards.clear_all()
	app.labels.clear()
	_arrange()
	cards = BjCards.new(world)
	chips = BjChips.new(world)
	world.poker_root.add_child(cards)
	world.poker_root.add_child(chips)
	cards.sfx.connect(Sfx.play)
	chips.sfx.connect(Sfx.play)
	hud = BjHud.new()
	add_child(hud)
	_connect_hud()
	quips = _make_quips()
	add_child(quips)
	hud.quip_pressed.connect(quips.toggle)
	preview = _make_preview()
	add_child(preview)
	director = BlackjackDirector.new(self, app, hud)
	add_child(director)
	_sync_nameplates()
	Net.state_public_updated.connect(_on_public)
	Net.game_events.connect(_on_events)
	Net.intent_rejected.connect(_on_rejected)
	_gaze = _make_gaze()
	add_child(_gaze)
	PokerFaces.build(self)
	if not Net.last_public.is_empty():
		_on_public(Net.last_public)
	refresh_hud()
	await director.intro()
	if late:
		await _first_frame()
	_intro_done = true
	_drain()


func _exit_tree() -> void:
	if not is_instance_valid(app) or not is_instance_valid(world):
		return
	for pid in state.names:
		app.labels.untrack(PLATE_KEY % pid)
		app.labels.untrack(QuipController.KEY_PREFIX % pid)
	world.stop_celebration()
	world.clear_poker()


func _process(delta: float) -> void:
	_clock.tick(delta)
	if hud == null:
		return
	var timed := not animating and not state.pub.is_empty() and (state.phase == "betting" or state.current != null)
	var total := BlackjackPacing.BET_TIMEOUT if state.phase == "betting" else BlackjackPacing.PLAY_TIMEOUT
	if timed:
		hud.controls.set_countdown(_clock.remaining(), total)
	else:
		hud.controls.hide_countdown()


func _connect_hud() -> void:
	hud.set_host(Net.is_host)
	hud.rules_pressed.connect(func(): app.show_rules())
	hud.end_pressed.connect(_confirm_end)
	hud.rebuy_pressed.connect(choose_rebuy)
	hud.sit_in_pressed.connect(choose_sit_in)
	hud.controls.bet_chosen.connect(submit_bet)
	hud.controls.skip_chosen.connect(submit_skip)
	hud.controls.action_chosen.connect(submit_action)


func _make_quips() -> QuipController:
	var quip := QuipController.new(app, my_pid)
	quip.name_of = name_of
	quip.anchor_for = func(pid: int) -> Callable:
		return world.nameplate_anchor.bind(pid) if world.patrons.has(pid) else Callable()
	quip.show_mine = func(text: String) -> void: hud.my_bubble(text)
	quip.log_line = hud.log_event
	quip.bubble_offset = Vector2(0, -PokerNameplate.MAX_SIZE.y - QUIP_GAP)
	return quip


func _make_preview() -> CardPreview:
	# 悬停大图:HUD 上庄家的牌条、自己的几手牌,以及 3D 桌上所有亮着的牌
	var card_preview := CardPreview.new()
	card_preview.source = func(point: Vector2) -> Array:
		var out: Array = hud.preview_candidates() if hud != null else []
		var tavern = app.get("tavern")
		if cards != null and tavern != null:
			out.append_array(CardPreview.world_candidates(tavern.camera_rig.camera, point, cards.hoverable_cards()))
		return out
	card_preview.gate = func() -> Dictionary:
		return {"camera_at_rest": director != null and director.is_camera_at_rest(), "panel_open": _chat_open(),
			"modal_open": app.is_modal_open(), "settlement": _settlement != null}
	return card_preview


func _chat_open() -> bool:
	var banter = app.get("banter_view")
	return (banter != null and is_instance_valid(banter) and banter.is_panel_open()) or (quips != null and quips.menu.is_open())


func _make_gaze() -> SeatGaze:
	var gaze := SeatGaze.new(app, world, my_pid)
	gaze.gaze_free = func() -> bool: return director.is_camera_at_rest() and _settlement == null
	gaze.at_seat = director.is_at_seat
	gaze.excluded = state.is_excluded
	gaze.rest_point = func() -> Vector3: return BlackjackDirector.TABLE_FOCUS
	return gaze


# —— 网络输入 ——

func _on_public(view: Dictionary) -> void:
	state.apply_public(view)
	_clock.sync_from_host(view.get("turn_time_left", -1.0))
	if not animating:
		_reconcile()


func _on_events(events: Array) -> void:
	for ev in events:
		if not ev is Dictionary:
			continue
		if Untrusted.same(ev.get("pid"), my_pid):
			if ["rebuy", "sit_in"].has(ev.get("type")):
				_seat_request_pending = false
			if MY_ACTION_EVENTS.has(ev.get("type")):
				_awaiting_intent = false   # 自己的下注 / 决策回执到了(演出期间控件本来就收着)
			if Untrusted.same(ev.get("type"), "bet_placed") and ev.get("amount") is int:
				_last_bet = ev["amount"]
	_queue.append_array(events.filter(func(ev): return ev is Dictionary))
	if _intro_done and not animating:
		_drain()


func _on_rejected(code: String) -> void:
	_awaiting_intent = false
	_seat_request_pending = false
	app.toast(ERROR_MESSAGES.get(code, code), UiTheme.LIE)
	refresh_actions()


func _drain() -> void:
	animating = true
	refresh_actions()
	while not _queue.is_empty():
		var ev: Dictionary = _queue.pop_front()
		await director.play(ev)
	animating = false
	_reconcile()


func _first_frame() -> void:
	# 迟到者的第一帧:等第一份视图,整张桌按它瞬时摆好;之前排队的事件丢掉(视图已包含它们)
	while state.pub.is_empty() and is_inside_tree():
		await get_tree().process_frame
	_queue.clear()
	if state.sync_from_view():
		_arrange()
	_sync_table()


func _reconcile() -> void:
	if state.pub.is_empty():
		return
	if state.refresh_from_view():
		_arrange()
	_sync_table()


func _sync_table() -> void:
	if chips == null or cards == null:
		refresh_hud()
		return
	var players: Array = state.pub.get("players", []) if state.pub.get("players") is Array else []
	chips.sync(players)
	cards.sync(players, state.pub.get("dealer", {}) if state.pub.get("dealer") is Dictionary else {})
	_sync_nameplates()
	refresh_hud()
	if director != null and _settlement == null:
		director.settle_camera()


# —— 3D ——

func _arrange() -> void:
	var seated := state.seats.has(my_pid)
	var entries := state.seat_entries(my_pid)
	for entry in entries:
		entry["species"] = Net.species_of(entry["pid"])
	world.arrange(entries, my_pid, seated, false)
	_sync_nameplates()


# —— 铭牌 ——

func _sync_nameplates() -> void:
	for pid in state.names:
		var wanted: bool = pid != my_pid and world.patrons.has(pid) and state.seats.has(pid)
		var plate: Control = app.labels.get_node_for(PLATE_KEY % pid)
		if wanted and plate == null:
			app.labels.track(PLATE_KEY % pid, BjNameplate.new(name_of(pid)), world.nameplate_anchor.bind(pid))
		elif not wanted and plate != null:
			app.labels.untrack(PLATE_KEY % pid)
	_update_nameplates()


func _update_nameplates() -> void:
	for pid in state.names:
		var plate = app.labels.get_node_for(PLATE_KEY % pid)
		if plate is BjNameplate:
			plate.set_plate(state.row(pid).get("stack", 0), state.plate_status(pid), pid == state.current_pid())


# —— HUD ——

func refresh_hud() -> void:
	if hud == null:
		return
	hud.set_header(state.round_number, state.pub.get("shoe_left"), state.pub.get("shoe_size"))
	hud.set_dealer(state.dealer_label(), state.dealer_cards)
	hud.set_ending(state.ending or _end_requested)
	hud.set_my_status(name_of(my_pid), state.row(my_pid))
	var current_hand: int = state.current["hand"] if state.current != null and state.current["pid"] == my_pid else -1
	hud.set_my_hands(state.hands_of(my_pid), current_hand)
	_update_nameplates()
	refresh_actions()


func refresh_actions() -> void:
	# 底部中间:座位提示 / 下注控件 / 决策按钮 / 只留横幅。控件只在演出放完、没有等回执时展开
	if hud == null:
		return
	if _settlement != null:
		hud.set_bottom(BjScreenState.BOTTOM_NONE)
		return
	var mode := state.bottom_mode(my_pid)
	hud.set_bottom(mode)
	var ready := not animating and not _awaiting_intent
	match mode:
		BjScreenState.BOTTOM_BET:
			# 不因别人的事件收起:调好的金额与按键都不丢
			if not _awaiting_intent:
				hud.controls.show_betting(state.row(my_pid).get("stack", 0), _last_bet, state.round_number)
			else:
				hud.controls.set_mode(BjControls.MODE_HIDDEN)
			hud.controls.set_turn("请下注", true)
		BjScreenState.BOTTOM_BET_WAIT:
			hud.controls.set_mode(BjControls.MODE_HIDDEN)
			var progress := state.betting_progress()
			var mine := state.status_of(my_pid)
			var head := "已下注 %s" % ChipText.format(state.row(my_pid).get("bet", 0)) if mine == BjRules.STATUS_BET else "这局不玩"
			hud.controls.set_turn("%s · 等待其他人(%d/%d)" % [head, progress[0], progress[1]], false)
		BjScreenState.BOTTOM_PLAY:
			if is_my_turn():
				hud.controls.show_play(legal())
				hud.controls.set_turn("轮到你了" + _hand_suffix(), true)
			else:
				hud.controls.set_mode(BjControls.MODE_HIDDEN)
				var pid: Variant = state.current_pid()
				hud.controls.set_turn("等待 %s 决策…" % name_of(pid) if pid != my_pid else "轮到你了" + _hand_suffix(), pid == my_pid)
		_:
			hud.controls.set_mode(BjControls.MODE_HIDDEN)
			hud.controls.set_turn("", false)


func _hand_suffix() -> String:
	# 分牌后标出是第几手
	if state.current == null or state.hands_of(my_pid).size() <= 1:
		return ""
	return " · 第 %d 手" % (state.current["hand"] + 1)


# —— 导演回调 ——

func name_of(pid: Variant) -> String:
	return state.name_of(pid)


func note_event(ev: Dictionary) -> void:
	state.apply_event(ev)
	_update_nameplates()
	if hud != null:
		hud.set_my_status(name_of(my_pid), state.row(my_pid))


func begin_round(ev: Dictionary) -> void:
	# 新一局:换到新座位表(中途加入的人登场),酒客复位,HUD 清掉上一局
	state.apply_event(ev)
	set_current(null)
	_arrange()
	for pid in world.patrons:
		world.patrons[pid].reset_pose()
		world.patrons[pid].set_active(false)
	world.look_all_at(BlackjackDirector.TABLE_FOCUS)
	if chips != null:
		chips.sync(_shadow_players())
	refresh_hud()


func _shadow_players() -> Array:
	# 影子状态里的筹码与下注(新一局开始时视图可能已领先到发牌之后)
	return state.order.map(func(pid: int) -> Dictionary:
		return state.row(pid).merged({"pid": pid}, true))


func set_current(turn: Variant) -> void:
	# turn:turn 事件({pid, hand})或 null。所有人看向正在决策的人,他自己看向自己的牌
	state.current = BjScreenState._turn(turn) if turn != null else null
	_clock.restart_turn()
	_awaiting_intent = false
	if hud == null:
		return
	var pid: Variant = state.current_pid()
	var focus := BlackjackDirector.TABLE_FOCUS
	if pid is int and world.patrons.has(pid):
		focus = world.head_position(pid)
	for patron_pid in world.patrons:
		var patron: Patron = world.patrons[patron_pid]
		patron.set_active(patron_pid == pid)
		patron.look_at_point(BlackjackDirector.TABLE_FOCUS if patron_pid == pid else focus)
	if pid == my_pid:
		Sfx.play("join")
		if app.is_rules_open():
			app.toast("轮到你了!按 %s 合上说明书" % OS.get_keycode_string(Rulebook.HOTKEY), UiTheme.BRASS_BRIGHT)
	refresh_hud()


func drop_player(pid: Variant) -> void:
	if not pid is int:
		return
	app.labels.untrack(PLATE_KEY % pid)
	if _gaze != null:
		_gaze.forget(pid)


func settlement() -> PokerSettlement:
	return _settlement


func show_settlement(results: Array) -> void:
	hud.set_bottom(BjScreenState.BOTTOM_NONE)
	_settlement = PokerSettlement.new(results, Net.is_host)
	_settlement.lobby_pressed.connect(func(): Net.request_rematch_lobby())
	_settlement.leave_pressed.connect(func(): Net.end_session())
	add_child(_settlement)


# —— 给按钮、快捷键与 bot 的入口 ——

func can_bet() -> bool:
	# 下注是大家同时进行的:别人的下注、加入、离座还在演时也能下(不等演出),只等自己上一个意图的回执
	return state.bottom_mode(my_pid) == BjScreenState.BOTTOM_BET and not _awaiting_intent and _settlement == null


func is_my_turn() -> bool:
	return state.current_pid() == my_pid and not animating and not _awaiting_intent and _settlement == null \
		and not legal().is_empty()


func legal() -> Dictionary:
	return state.legal(my_pid)


func my_status() -> String:
	return state.status_of(my_pid)


func submit_bet(amount: int) -> bool:
	if not can_bet() or not BjRules.is_valid_bet(amount, state.row(my_pid).get("stack", 0)):
		return false
	_send({"kind": BjRules.BET, "amount": amount})
	return true


func submit_skip() -> bool:
	if not can_bet():
		return false
	_send({"kind": BjRules.SKIP})
	return true


func submit_action(kind: String) -> bool:
	if not is_my_turn() or not legal().get(kind, false):
		return false
	_send({"kind": kind})
	return true


func _send(intent: Dictionary) -> void:
	_awaiting_intent = true
	Sfx.play("ui_click")
	refresh_actions()
	_submit(intent)


func _submit(intent: Dictionary) -> void:
	if intent_sink.is_valid():
		intent_sink.call(intent)
	else:
		Net.submit_session_intent(intent)


func choose_rebuy() -> bool:
	return _request_seat(BjRules.STATUS_BUSTED, BjRules.REBUY)


func choose_sit_in() -> bool:
	return _request_seat(BjRules.STATUS_AWAY, BjRules.SIT_IN)


func _request_seat(status: String, kind: String) -> bool:
	if _seat_request_pending or _settlement != null or state.phase == "over" or my_status() != status:
		return false
	_seat_request_pending = true
	Sfx.play("ui_click")
	_submit({"kind": kind})
	return true


# —— 输入 ——

func _unhandled_input(event: InputEvent) -> void:
	if _settlement != null:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_confirm_leave()
		return
	if not event is InputEventKey or not event.pressed or event.echo or app.is_modal_open():
		return
	if event.keycode == KEY_V:
		get_viewport().set_input_as_handled()
		if not _chat_open():
			director.toggle_camera_mode()
		return
	if _chat_open():
		return
	if (can_bet() or is_my_turn()) and hud.controls.handle_key(event.keycode):
		get_viewport().set_input_as_handled()


func _confirm_end() -> void:
	if not Net.is_host or state.ending or _end_requested:
		return
	var overlay: ConfirmOverlay = app.confirm(END_CONFIRM, "散局")
	overlay.confirmed.connect(func():
		_end_requested = true
		hud.set_ending(true)
		Net.end_poker_session())


func _confirm_leave() -> void:
	var overlay: ConfirmOverlay = app.confirm(HOST_LEAVE_CONFIRM if Net.is_host else LEAVE_CONFIRM, "离开")
	overlay.confirmed.connect(func(): Net.end_session())
