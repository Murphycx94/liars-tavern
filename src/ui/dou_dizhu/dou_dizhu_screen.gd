extends Control
# 斗地主牌桌控制器(设计稿 §3、§6.11):接收 Net 的视图与事件 → 事件队列交给 DdzDirector 逐个演出(演出期间锁出手)
# → 演出结束后按最新视图对账(3D 牌、身份帽、报警、「不出」牌子、铭牌、HUD)。本地状态在 DdzScreenState 里;
# 3D 牌由 DdzCards 管、特效由 DdzFx 管;视线与探头交给 SeatGaze。骗子酒馆的小桌坐 3 人,点烛台、不摆目标牌立牌。
# 出手一律 Net.submit_session_intent(...);被拒时 toast DdzState.ERROR_MESSAGES 的中文。房主「散局」走 Net.end_poker_session()。
# 给按钮、快捷键与机器人的入口是同一套:toggle_card / set_selection / cycle_hint / reset_selection / submit_play / submit_pass /
# submit_bid / toggle_trustee(debug_flags 的机器人走的就是它们)。


const PLATE_KEY := "plate:%d"   # WorldLabels 里对手铭牌的键
const QUIP_ABOVE_PLATE := -56.0  # 九宫格快捷对话的气泡比出牌气泡再高这么多
const PRIVATE_POLL := 0.02
const LEAVE_CONFIRM := "斗地主少一个人就打不下去:离开会让整桌按现在的累计分提前结算,确定吗?"
const HOST_LEAVE_CONFIRM := "你是房主,离开会解散整桌,确定吗?"
const END_CONFIRM := "散局:打完当前这一手后按累计分结算,全员回到等待厅。确定吗?"
const ACTION_PLAY := "play"
const ACTION_PASS := "pass"
const ACTION_HINT := "hint"
const ACTION_RESET := "reset"
const BID_KEYS := {KEY_0: 0, KEY_1: 1, KEY_2: 2, KEY_3: 3, KEY_KP_0: 0, KEY_KP_1: 1, KEY_KP_2: 2, KEY_KP_3: 3}

var app: Node
var my_pid := 0
var hud: DdzHud
var director: DdzDirector
var quips: QuipController
var preview: CardPreview
var world: TableWorld
var cards: DdzCards
var fx3d: DdzFx
var state := DdzScreenState.new()
var animating := true
var intent_sink := Callable()     # 测试钩子:不走 Net,直接把意图交给本地会话(func(intent: Dictionary))

var _clock := TurnClock.new()
var _gaze: SeatGaze = null
var _queue: Array = []
var _intro_done := false
var _awaiting_intent := false     # 已提交叫分 / 出牌 / 不出,等房主回执
var _trustee_pending := false
var _selected := {}               # 私有手牌下标 -> true
var _hint_index := 0
var _hint_key := ""               # 提示列表变了(换了回合)就从第一个重新数
var _end_requested := false
var _settlement: DdzSettlement = null


func _init(p_app: Node) -> void:
	app = p_app


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	my_pid = Net.my_pid()
	world = app.world
	state.my_pid = my_pid
	state.set_seats(Net.seats)
	# 桌子:骗子酒馆的桌与烛台(不摆目标牌立牌),3 个座位均匀分布
	app.apply_table_mode(Net.game_mode)
	world.clear_poker()
	world.revive_all()
	world.cards.clear_all()
	world.third_person_override = DdzLayout.THIRD_PERSON   # 拆台(clear_poker)时复原
	app.labels.clear()
	# 形象用房主分配的(Net.species_of 查本局座位表与等待厅名单),各端一致
	world.arrange(Net.seats.map(func(s: Dictionary) -> Dictionary: return {"pid": s["pid"], "species": Net.species_of(s["pid"])}),
		my_pid, true, false)
	cards = DdzCards.new(world)
	cards.my_pid = my_pid
	world.poker_root.add_child(cards)
	cards.sfx.connect(Sfx.play)
	fx3d = DdzFx.new(world)
	fx3d.my_pid = my_pid
	world.poker_root.add_child(fx3d)
	fx3d.sfx.connect(Sfx.play)
	PokerFaces.build(self)       # 后台生成牌面(等待厅通常已开始);导演在第一次发牌前等它完成
	DdzJokerFaces.build(self)
	hud = DdzHud.new()
	add_child(hud)
	_connect_hud()
	quips = _make_quips()
	add_child(quips)
	hud.quip_pressed.connect(quips.toggle)
	preview = _make_preview()
	add_child(preview)
	director = DdzDirector.new(self, app, hud)
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
	# 只收走自己挂的铭牌与气泡;身份帽摘掉、酒客自己的帽子放回;斗地主的 3D 节点全部拆掉
	if not is_instance_valid(app) or not is_instance_valid(world):
		return
	for pid in state.names:
		app.labels.untrack(PLATE_KEY % pid)
		app.labels.untrack(DdzDirector.BUBBLE_KEY % pid)
		app.labels.untrack(QuipController.KEY_PREFIX % pid)
	for pid in world.patrons:
		DdzHats.take_off(world.patrons[pid])
	world.stop_celebration()
	world.clear_poker()


func _process(delta: float) -> void:
	_clock.tick(delta)
	if hud == null:
		return
	var total := DouDizhuSession.BID_TIMEOUT if state.stage == DdzState.STAGE_BID else Protocol.TURN_TIMEOUT
	var show_ring: bool = state.current_pid != null and not animating and not state.pub.is_empty() and _settlement == null \
		and state.stage != ""
	hud.set_countdown(_clock.remaining(), total, show_ring)


func _connect_hud() -> void:
	hud.set_host(Net.is_host)
	hud.rules_pressed.connect(func(): app.show_rules())
	hud.end_pressed.connect(_confirm_end)
	hud.play_pressed.connect(submit_play)
	hud.pass_pressed.connect(submit_pass)
	hud.hint_pressed.connect(cycle_hint)
	hud.reset_pressed.connect(reset_selection)
	hud.bid_pressed.connect(submit_bid)
	hud.trustee_pressed.connect(toggle_trustee)
	hud.selection_changed.connect(set_selection)
	hud.card_hovered.connect(func(i: int):
		if cards != null:
			cards.set_selection(_selected, i))


func _make_gaze() -> SeatGaze:
	var gaze := SeatGaze.new(app, world, my_pid)
	gaze.gaze_free = func() -> bool: return director.is_camera_at_rest() and _settlement == null
	gaze.at_seat = director.is_at_seat
	gaze.excluded = func(pid: int) -> bool: return state.left.has(pid)
	gaze.rest_point = func() -> Vector3: return DdzDirector.TABLE_FOCUS
	return gaze


func _make_quips() -> QuipController:
	# 九宫格快捷对话:他人的气泡挂在出牌气泡再往上一层,自己的在按钮行上方;没有酒客的人只记日志
	var quip := QuipController.new(app, my_pid)
	quip.name_of = name_of
	quip.anchor_for = func(pid: int) -> Callable:
		if not world.patrons.has(pid):
			return Callable()
		var patron: Patron = world.patrons[pid]
		return func(): return patron.nameplate_anchor() if is_instance_valid(patron) else Vector3.ZERO
	quip.show_mine = func(text: String) -> void: hud.my_bubble(text, UiTheme.INK, Quips.BUBBLE_SECONDS)
	quip.log_line = hud.log_event
	quip.bubble_offset = Vector2(0, DdzDirector.BUBBLE_ABOVE_PLATE + QUIP_ABOVE_PLATE)
	return quip


func _make_preview() -> CardPreview:
	# 悬停大图:底部手牌条、左上亮出来的底牌、3D 牌扇里自己的牌、桌上亮着的牌;镜头不在座位、聊天面板开着、
	# 说明书或确认框盖着、结算时藏起
	var card_preview := CardPreview.new()
	card_preview.source = func(point: Vector2) -> Array:
		var out: Array = hud.preview_candidates() if hud != null else []
		var tavern = app.get("tavern")
		if cards != null and tavern != null:
			out.append_array(CardPreview.world_candidates(tavern.camera_rig.camera, point, cards.hoverable_cards()))
		return out
	card_preview.gate = func() -> Dictionary:
		return {"camera_at_rest": director != null and director.is_camera_at_rest(), "panel_open": chat_open(),
			"modal_open": app.is_modal_open(), "settlement": _settlement != null}
	return card_preview


func chat_open() -> bool:
	# 快捷语面板(BanterView)或九宫格快捷对话开着:数字键归它们,牌桌的快捷键一律不抢
	var banter = app.get("banter_view")
	var banter_open: bool = banter != null and is_instance_valid(banter) and banter.is_panel_open()
	return banter_open or (quips != null and quips.menu != null and quips.menu.is_open())


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
	_trustee_pending = false
	if not animating:
		_reconcile()
	else:
		refresh_actions()


func _on_events(events: Array) -> void:
	# 有新的一批事件 = 房主处理过了:回执到了,可以再出手
	_awaiting_intent = false
	_queue.append_array(events.filter(func(ev): return ev is Dictionary))
	if _intro_done and not animating:
		_drain()


func _on_rejected(code: String) -> void:
	_awaiting_intent = false
	_trustee_pending = false
	app.toast(DdzState.ERROR_MESSAGES.get(code, code), UiTheme.LIE)
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
		_selected = {}
	sync_table()
	if director != null and _settlement == null:
		director.settle_camera()


func sync_table() -> void:
	if cards == null:
		refresh_hud()
		return
	var counts := {}
	for pid in state.seats:
		counts[pid] = state.counts.get(pid, 0)
	cards.sync(counts, state.shown_hand, state.rows, state.bottom_hidden)
	cards.set_selection(_selected, -1)
	put_on_hats(false)
	if fx3d != null:
		for pid in state.seats:
			if state.phase == DdzScreenState.PHASE_PLAYING:
				fx3d.set_alarm(pid, int(state.counts.get(pid, 0)))
			else:
				fx3d.clear_alarm(pid)
			if state.passed.has(pid) and state.phase == DdzScreenState.PHASE_PLAYING:
				if not fx3d.has_pass(pid):
					fx3d.pass_mark(pid, cards.to_global(DdzLayout.pass_point(world.seat_angles.get(pid, 0.0), pid == my_pid)))
			else:
				fx3d.clear_pass(pid)
	refresh_hud()
	if state.phase == DdzScreenState.PHASE_BETWEEN and not state.last_hand.is_empty() and not hud.summary_visible():
		show_hand_summary()


# —— 导演回调 ——

func name_of(pid: Variant) -> String:
	return state.name_of(pid)


func note_event(ev: Dictionary) -> void:
	state.apply_event(ev)
	_update_nameplates()
	_update_info()


func begin_hand(ev: Dictionary) -> void:
	# 新的一手:摘帽、清掉上一手的特效与庆祝表情、收起结算摘要
	state.apply_event(ev)
	set_current(null)
	_selected = {}
	state.shown_hand = []
	if hud != null:
		hud.hide_summary()
		hud.set_hand([], {}, true)
	if fx3d != null:
		fx3d.clear_alarms()
		fx3d.clear_passes()
	for pid in world.patrons:
		var patron: Patron = world.patrons[pid]
		DdzHats.take_off(patron)
		patron.reset_pose()
		patron.set_active(false)
	world.look_all_at(DdzDirector.TABLE_FOCUS)
	refresh_hud()


func set_current(pid: Variant) -> void:
	state.current_pid = pid if pid is int else null
	_clock.restart_turn()
	_awaiting_intent = false
	if hud == null:
		return
	var focus := DdzDirector.TABLE_FOCUS
	if pid is int and world.patrons.has(pid):
		focus = world.head_position(pid)
	for patron_pid in world.patrons:
		var patron: Patron = world.patrons[patron_pid]
		patron.set_active(patron_pid == pid)
		patron.look_at_point(DdzDirector.TABLE_FOCUS if patron_pid == pid else focus)
	if pid == my_pid:
		Sfx.play("join")
		if app.is_rules_open():
			app.toast("轮到你了!按 %s 合上说明书" % OS.get_keycode_string(Rulebook.HOTKEY), UiTheme.BRASS_BRIGHT)
	_update_nameplates()
	refresh_actions()


func cards_for_deal(hand: int, deal: int, max_wait: float) -> Array:
	# 这一次发牌自己的手牌(私有视图快照,通常同一帧就到了);最多等 max_wait
	var waited := 0.0
	while state.cards_for_deal(hand, deal) == null and waited < max_wait and is_inside_tree():
		await get_tree().process_frame
		waited += get_process_delta_time()
	var mine: Variant = state.cards_for_deal(hand, deal)
	if mine == null and state.private_hand_number() == hand and state.view_phase() == DdzScreenState.PHASE_BIDDING:
		mine = state.private_cards()
	return mine if mine is Array else []


func show_dealt(mine: Array) -> void:
	state.shown_hand = mine.duplicate()
	_selected = {}
	refresh_my_hand()


func take_bottom(bottom: Array) -> void:
	# 自己当了地主:底牌并进手牌,手牌条里那三张闪一下
	state.add_bottom_to_shown(bottom)
	_selected = {}
	refresh_my_hand()
	if hud != null:
		hud.strip.flash(bottom)


func take_played(ids: Array) -> void:
	state.take_from_shown(ids)
	_selected = {}
	refresh_my_hand()


func refresh_my_hand() -> void:
	if hud != null:
		hud.set_hand(state.shown_hand, _selected, true)
	if cards != null:
		cards.set_selection(_selected, -1)
	refresh_actions()


func put_on_hats(pop: bool) -> void:
	# 按身份戴帽(已经戴对的不动);还没定地主时摘掉
	for pid in world.patrons:
		var role := str(state.roles.get(pid, ""))
		var patron: Patron = world.patrons[pid]
		if DdzHats.role_of(patron) != role:
			if role == "":
				DdzHats.take_off(patron)
			else:
				DdzHats.put_on(patron, role, pop)
	if pop:
		Sfx.play("pop")


func pulse_nameplate(pid: Variant) -> void:
	if not pid is int or app == null or app.get("labels") == null:
		return
	var plate: Variant = app.labels.get_node_for(PLATE_KEY % pid)
	if plate is DdzNameplate:
		plate.pulse()


func show_hand_summary() -> void:
	if hud == null or state.last_hand.is_empty():
		return
	hud.show_summary(DdzHud.summary_title(state.last_hand, str(state.roles.get(my_pid, ""))), DdzHud.formula_text(state.last_hand),
		state.summary_rows(), my_pid)


func drop_player(pid: Variant) -> void:
	if not pid is int:
		return
	app.labels.untrack(PLATE_KEY % pid)
	if _gaze != null:
		_gaze.forget(pid)
	_update_nameplates()


func show_settlement(results: Array, reason: String) -> void:
	if _settlement != null:
		return
	hud.set_away_from_seat(true)
	hud.hide_summary()
	_settlement = DdzSettlement.new(results, Net.is_host, reason, state.hand if not state.last_hand.is_empty() else 0, my_pid)
	_settlement.lobby_pressed.connect(func():
		Sfx.play("ui_click")
		Net.request_rematch_lobby())
	_settlement.leave_pressed.connect(func():
		Sfx.play("ui_click")
		Net.end_session())
	add_child(_settlement)


func settlement() -> DdzSettlement:
	return _settlement


# —— 铭牌与 HUD ——

func _build_nameplates() -> void:
	for pid in state.seats:
		if pid == my_pid or not world.patrons.has(pid):
			continue
		var patron: Patron = world.patrons[pid]
		app.labels.track(PLATE_KEY % pid, DdzNameplate.new(state.name_of(pid)),
			func(): return patron.nameplate_anchor() if is_instance_valid(patron) else Vector3.ZERO)
	_update_nameplates()


func _update_nameplates() -> void:
	if app == null or app.get("labels") == null:
		return
	for pid in state.seats:
		var plate: Variant = app.labels.get_node_for(PLATE_KEY % pid)
		if plate is DdzNameplate:
			plate.set_info(state.plate_row(pid))


func _update_info() -> void:
	if hud == null:
		return
	var highest := 0
	for pid in state.bids:
		highest = maxi(highest, int(state.bids[pid]))
	hud.set_info(state.hand, state.base, state.multiplier, name_of(state.landlord) if state.landlord != null else "",
		state.bottom, state.bottom_hidden and state.phase == DdzScreenState.PHASE_BIDDING,
		DdzHud.status_text(state.phase, highest, state.ending or _end_requested))
	hud.set_ending(state.ending or _end_requested)
	var row := state.plate_row(my_pid)
	row["count"] = state.shown_hand.size() if not state.shown_hand.is_empty() else row["count"]
	hud.set_me(name_of(my_pid), row, my_trustee(), can_toggle_trustee())


func refresh_hud() -> void:
	if hud == null:
		return
	hud.set_hand(state.shown_hand, _selected, true)
	_update_nameplates()
	_update_info()
	refresh_actions()


func refresh_actions() -> void:
	if hud == null:
		return
	_update_info()
	if _settlement != null:
		hud.set_action_mode(DdzHud.ACTION_NONE)
		hud.set_turn("", false)
		return
	var cur: Variant = state.current_pid
	if is_bidding_turn():
		hud.set_action_mode(DdzHud.ACTION_BID)
		hud.set_bid_actions(state.bid_options())
		hud.set_turn(DdzHud.turn_text(name_of(my_pid), true, DdzState.STAGE_BID), true)
		hud.set_hint_mode(DdzHud.ACTION_BID)
		return
	if is_playing_turn():
		hud.set_action_mode(DdzHud.ACTION_PLAY)
		var check := state.selection_check(selected_indices())
		var hints := state.hints()
		var text: String = check["text"]
		if _selected.is_empty():
			text = "" if not hints.is_empty() or not state.can_pass() else "没有能压过上家的牌"
		hud.set_play_actions(check["ok"], state.can_pass(), not hints.is_empty(), not _selected.is_empty(), text, check["ok"])
		hud.set_turn(DdzHud.turn_text(name_of(my_pid), true, DdzState.STAGE_PLAY), true)
		hud.set_hint_mode(DdzHud.ACTION_PLAY)
		return
	hud.set_action_mode(DdzHud.ACTION_NONE)
	hud.set_hint_mode(DdzHud.ACTION_NONE)
	if cur is int and state.stage != "":
		hud.set_turn(DdzHud.turn_text(name_of(cur), cur == my_pid, state.stage), cur == my_pid and not animating)
	else:
		hud.set_turn("", false)


# —— 出手规则(按钮、快捷键与机器人共用)——

func is_my_turn() -> bool:
	# 演出进行到自己的回合、视图也说轮到自己、没有未回执的动作、没在结算
	return state.current_pid == my_pid and state.view_turn() and not animating and not _awaiting_intent and _settlement == null


func is_bidding_turn() -> bool:
	return is_my_turn() and state.view_phase() == DdzScreenState.PHASE_BIDDING and not state.bid_options().is_empty()


func is_playing_turn() -> bool:
	return is_my_turn() and state.view_phase() == DdzScreenState.PHASE_PLAYING


func my_trustee() -> bool:
	return state.priv.get("trustee") is bool and state.priv["trustee"]


func can_toggle_trustee() -> bool:
	return not state.pub.is_empty() and state.view_phase() != DdzScreenState.PHASE_OVER and state.view_phase() != DdzScreenState.PHASE_IDLE \
		and _settlement == null and not _trustee_pending


func selected_indices() -> Array:
	var out := _selected.keys()
	out.sort()
	return out


func selection() -> Dictionary:
	return _selected.duplicate()


func toggle_card(index: int) -> void:
	if index < 0 or index >= state.shown_hand.size() or _settlement != null:
		return
	if _selected.has(index):
		_selected.erase(index)
	else:
		_selected[index] = true
	Sfx.play("ui_click")
	refresh_my_hand()


func set_selection(selected: Dictionary) -> void:
	# 手牌条拖选 / 提示:只留下标合法的
	var clean := {}
	for i in selected:
		if i is int and i >= 0 and i < state.shown_hand.size():
			clean[i] = true
	if clean == _selected:
		return
	_selected = clean
	Sfx.play("ui_hover")
	refresh_my_hand()


func reset_selection() -> void:
	if _selected.is_empty():
		return
	_selected = {}
	Sfx.play("ui_click")
	refresh_my_hand()


func cycle_hint() -> bool:
	# 提示:按 legal_plays 的顺序(小的在前,炸弹、王炸最后)循环选中;提示列表换了就从头数
	if not is_playing_turn():
		return false
	var hints := state.hints()
	if hints.is_empty():
		app.toast("没有能压过上家的牌,只能不出", UiTheme.MUTED)
		return false
	var key := str(hints)
	if key != _hint_key:
		_hint_key = key
		_hint_index = 0
	var pick: Array = hints[_hint_index % hints.size()]
	_hint_index += 1
	var sel := {}
	for i in pick:
		sel[i] = true
	_selected = sel
	Sfx.play("ui_click")
	refresh_my_hand()
	return true


func submit_play() -> bool:
	if not is_playing_turn() or _selected.is_empty():
		return false
	var indices := selected_indices()
	var check := state.selection_check(indices)
	if not check["ok"]:
		app.toast(str(check["text"]), UiTheme.MUTED)
		return false
	_send({"kind": "play", "cards": indices})
	return true


func submit_pass() -> bool:
	if not is_playing_turn() or not state.can_pass():
		return false
	_send({"kind": "pass"})
	return true


func submit_bid(score: int) -> bool:
	if not is_bidding_turn() or not state.bid_options().has(score):
		return false
	_send({"kind": "bid", "score": score})
	return true


func toggle_trustee() -> bool:
	if not can_toggle_trustee():
		return false
	_trustee_pending = true
	Sfx.play("ui_click")
	_submit({"kind": "trustee", "on": not my_trustee()})
	refresh_actions()
	return true


func _send(intent: Dictionary) -> void:
	_awaiting_intent = true
	Sfx.play("ui_click")
	_submit(intent)
	refresh_actions()


func _submit(intent: Dictionary) -> void:
	if intent_sink.is_valid():
		intent_sink.call(intent)
	else:
		Net.submit_session_intent(intent)


# —— 输入 ——

static func key_action(keycode: Key) -> String:
	# 快捷键 → 动作(不占 T / Q / G / V / WASD / Esc / F1):Enter 出牌、空格或 P 不出(叫分时不叫)、H 提示、R 重选
	match keycode:
		KEY_ENTER, KEY_KP_ENTER:
			return ACTION_PLAY
		KEY_SPACE, KEY_P:
			return ACTION_PASS
		KEY_H:
			return ACTION_HINT
		KEY_R:
			return ACTION_RESET
	return ""


static func bid_key(keycode: Key) -> int:
	# 叫分时 0 不叫、1 / 2 / 3 叫分(含小键盘);不是这几个键 -1
	return BID_KEYS.get(keycode, -1)


func handle_key(keycode: Key) -> bool:
	# 返回 true 表示这个键被用掉了。快捷语面板或九宫格开着时一律不抢(数字键归它们)
	if chat_open() or _settlement != null:
		return false
	if is_bidding_turn():
		var score := bid_key(keycode)
		if score >= 0:
			submit_bid(score)
			return true
		if key_action(keycode) == ACTION_PASS:
			submit_bid(0)
			return true
	match key_action(keycode):
		ACTION_PLAY:
			submit_play()
			return true
		ACTION_PASS:
			submit_pass()
			return true
		ACTION_HINT:
			cycle_hint()
			return true
		ACTION_RESET:
			reset_selection()
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if _settlement != null:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_confirm_leave()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V and not app.is_modal_open():
		get_viewport().set_input_as_handled()
		if not chat_open():
			director.toggle_camera_mode()
		return
	if app.is_modal_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if handle_key(event.keycode):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var index := _pick_card(event.position)
		if index >= 0:
			toggle_card(index)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and not animating and cards != null:
		cards.set_selection(_selected, _pick_card(event.position))


func _pick_card(screen_pos: Vector2) -> int:
	if animating or cards == null or app.get("tavern") == null:
		return -1
	var camera: Camera3D = app.tavern.camera_rig.camera
	return cards.pick(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))


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
