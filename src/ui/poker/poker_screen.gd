extends Control
# 德州牌桌控制器(规格 §4.2、§5.5、§6、§7):接收 Net 的视图与事件 → 事件队列交给 PokerDirector 逐个演出
# (演出期间锁输入)→ 演出结束后按最新视图对账(3D 筹码与牌、铭牌、HUD、机位)。
# 本地状态在 PokerScreenState 里;3D 节点由 PokerChips / PokerCards 管;视线与探头交给 SeatGaze。
# 任何时刻都能只凭公共 + 私有视图把整张桌摆对(中途加入的人靠它画出进行中的这一手),事件只负责动画。
# 给 bot 与快捷键的入口与按钮同路径:is_my_turn / legal / submit / my_status / choose_rebuy / choose_spectate / choose_sit_in。


const PLATE_KEY := "plate:%d"   # WorldLabels 里对手铭牌的键
const HOLE_WAIT := 3.0          # 发牌事件到了、这一手的私有手牌最多再等这么久
const ERROR_MESSAGES := {
	"not_your_turn": "还没轮到你",
	"invalid_action": "现在不能这么做",
	"invalid_amount": "金额不合法",
	"no_hand": "现在没有进行中的手牌",
	"session_over": "牌局已经结束",
	"cannot_rebuy": "现在不能领取筹码",
	"not_seated": "你不在这场牌局里",
}
const END_CONFIRM := "散局:打完当前这一手后结算,全员回到等待厅。确定吗?"
const LEAVE_CONFIRM := "离开牌桌后这一手按弃牌处理,确定吗?"
const HOST_LEAVE_CONFIRM := "你是房主,离开会解散整桌,确定吗?"
const FOLD_CONFIRM := "现在可以免费过牌,确定要弃牌吗?"
const QUIP_GAP := 6.0   # 他人快捷对话气泡的小三角尖与铭牌之间的留白
const SEAT_EVENTS := ["rebuy", "spectate", "sit_in", "next_ready"]   # 再领 / 观战 / 回座 / 开始下一手的回执(自己的 pid)
const COUNTDOWN_MODES := [PokerHud.BOTTOM_BUST, PokerHud.BOTTOM_NEXT, PokerHud.BOTTOM_NEXT_WAIT]

var app: Node
var my_pid := 0
var hud: PokerHud
var director: PokerDirector
var world: TableWorld
var chips: PokerChips
var cards: PokerCards
var state := PokerScreenState.new()
var animating := true
var late := false   # 迟到者:进牌桌时不在座位表里,第一帧按视图摆(规格 §7)

var _clock := TurnClock.new()
var _gaze: SeatGaze = null   # _ready 时建(不入树的测试里为空)
var _queue: Array = []
var _intro_done := false
var _awaiting_intent := false        # 已提交下注动作,等房主回执
var _seat_request_pending := false   # 已提交再领 / 观战 / 回座,等房主回执
var _next_left := -1.0               # 一手结束后到下一手自动开始的本地倒计时(15 秒,到点自动点「开始」);< 0 表示没在数
var _history: HandHistoryPanel = null
var _settlement: PokerSettlement = null
var quips: QuipController
var preview: CardPreview
var _end_requested := false             # 房主已确认散局:按钮立刻变灰,不等 ending 事件演到
var _fold_confirm: ConfirmOverlay = null   # 「可以免费过牌,确定弃牌吗」:换了行动者就作废


func _init(p_app: Node) -> void:
	app = p_app


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	my_pid = Net.my_pid()
	world = app.world
	state.mode = Net.game_mode
	state.set_seats(Net.seats)
	late = not state.seats.has(my_pid)
	# 迟到者直接从主菜单进牌桌,没经过等待厅:桌子、烛台与立牌都要在这里按玩法摆
	app.apply_table_mode(Net.game_mode)
	world.clear_poker()
	world.revive_all()
	world.cards.clear_all()
	app.labels.clear()
	_arrange()
	chips = PokerChips.new(world)
	cards = PokerCards.new(world)
	world.poker_root.add_child(chips)
	world.poker_root.add_child(cards)
	chips.sfx.connect(Sfx.play)
	cards.sfx.connect(Sfx.play)
	hud = PokerHud.new()
	add_child(hud)
	_connect_hud()
	quips = _make_quips()
	add_child(quips)
	hud.quip_pressed.connect(quips.toggle)
	preview = _make_preview()
	add_child(preview)   # 压在 HUD 与九宫格之上;只显示,不接鼠标
	director = PokerDirector.new(self, app, hud)
	add_child(director)
	_sync_nameplates()
	# 先同步连上信号、读取已到的视图,之后才 await:与 game_started 同一批到达的事件不能丢
	Net.state_public_updated.connect(_on_public)
	Net.state_private_updated.connect(_on_private)
	Net.game_events.connect(_on_events)
	Net.intent_rejected.connect(_on_rejected)
	_gaze = _make_gaze()
	add_child(_gaze)
	PokerFaces.build(self)   # 后台生成牌面(等待厅通常已开始);导演在第一次发牌前等它完成
	if not Net.last_public.is_empty():
		_on_public(Net.last_public)
	if not Net.last_private.is_empty():
		_on_private(Net.last_private)
	refresh_hud()
	await director.intro()
	if late:
		await _first_frame()
	_intro_done = true
	_drain()


func _exit_tree() -> void:
	# 只收走自己挂的铭牌(等待厅已挂好它自己的);本机藏起来的观战者酒客要还原,德州节点全部拆掉(规格 §5.1)。
	# 退出游戏时酒馆可能先于本屏幕释放(测试里也是),那时没有东西要收
	if not is_instance_valid(app) or not is_instance_valid(world):
		return
	for pid in state.names:
		app.labels.untrack(PLATE_KEY % pid)
		app.labels.untrack(QuipController.KEY_PREFIX % pid)
	world.set_patron_visible(my_pid, true)
	world.stop_celebration()   # 结算庆祝(舞步、礼炮、彩纸)随牌桌退场收起
	world.clear_poker()


func _process(delta: float) -> void:
	# delta 随 Engine.time_scale 缩放,与房主的回合 Timer 同速
	_clock.tick(delta)
	var show_ring: bool = state.current_pid != null and not animating and not state.pub.is_empty()
	hud.set_countdown(_clock.remaining(), Protocol.TURN_TIMEOUT, show_ring)
	if _next_left >= 0.0 and _settlement == null and COUNTDOWN_MODES.has(hud.bottom_mode()):
		_next_left = maxf(_next_left - delta, 0.0)
		hud.set_bust_countdown(minf(_next_left, PokerPacing.NEXT_HAND_TIMEOUT), PokerPacing.NEXT_HAND_TIMEOUT)
		if _next_left <= 0.0 and hud.bottom_mode() == PokerHud.BOTTOM_NEXT:
			choose_next()   # 时间到自动点「开始下一手」(房主那边到点也会照常开)


func _connect_hud() -> void:
	hud.set_host(Net.is_host)
	hud.rules_pressed.connect(func(): app.show_rules())
	hud.end_pressed.connect(_confirm_end)
	hud.rebuy_pressed.connect(choose_rebuy)
	hud.spectate_pressed.connect(choose_spectate)
	hud.sit_in_pressed.connect(choose_sit_in)
	hud.next_pressed.connect(choose_next)
	hud.history_pressed.connect(toggle_history)
	hud.action_chosen.connect(submit)
	hud.fold_confirm_requested.connect(_confirm_fold)


func _make_quips() -> QuipController:
	# 快捷对话:他人的气泡挂在铭牌正上方(没登场的人只记日志),自己的弹在左下自己那一栏上方
	var quip := QuipController.new(app, my_pid)
	quip.name_of = name_of
	quip.anchor_for = func(pid: int) -> Callable:
		return world.nameplate_anchor.bind(pid) if world.patrons.has(pid) else Callable()
	quip.show_mine = func(text: String) -> void: hud.my_bubble(text)
	quip.log_line = hud.log_event
	quip.bubble_offset = Vector2(0, -PokerNameplate.MAX_SIZE.y - QUIP_GAP)
	return quip


func _make_preview() -> CardPreview:
	# 悬停大图:HUD 上的公共牌条、自己的两张、摊牌面板里亮的牌,以及 3D 桌上的公共牌、亮牌与自己牌扇里的底牌
	# (别人的牌背、弃牌堆不算);镜头去拍特写、快捷语面板或九宫格开着、说明书或确认框盖着、结算时藏起
	var card_preview := CardPreview.new()
	card_preview.source = func(point: Vector2) -> Array:
		var out: Array = hud.preview_candidates() if hud != null else []
		var tavern = app.get("tavern")
		if cards != null and tavern != null:
			out.append_array(CardPreview.world_candidates(tavern.camera_rig.camera, point, cards.hoverable_cards(my_pid)))
		return out
	card_preview.gate = func() -> Dictionary:
		return {"camera_at_rest": director != null and director.is_camera_at_rest(), "panel_open": _chat_open(),
			"modal_open": app.is_modal_open(), "settlement": _settlement != null}
	return card_preview


func _chat_open() -> bool:
	# 快捷语面板(BanterView)或九宫格快捷对话开着
	var banter = app.get("banter_view")
	return (banter != null and is_instance_valid(banter) and banter.is_panel_open()) or (quips != null and quips.menu.is_open())


func _make_gaze() -> SeatGaze:
	# 镜头停在常驻机位且没在结算:视线归各玩家自己;只有在自己座位的越肩机位才跟光标、读 WASD;
	# 观战 / 已离开的人不跟随(是自己时探头收回);别人停发视线后看回桌心
	var gaze := SeatGaze.new(app, world, my_pid)
	gaze.gaze_free = func() -> bool: return director.is_camera_at_rest() and _settlement == null
	gaze.at_seat = director.is_at_seat
	gaze.excluded = state.is_excluded
	gaze.rest_point = func() -> Vector3: return PokerDirector.TABLE_FOCUS
	return gaze


# —— 网络输入 ——

func _on_public(view: Dictionary) -> void:
	state.apply_public(view)
	# 房主权威的回合剩余时间(含演出补时)
	_clock.sync_from_host(view.get("turn_time_left", -1.0))
	if not animating:
		_reconcile()


func _on_private(view: Dictionary) -> void:
	state.apply_private(view)
	if not animating:
		_reconcile()


func _on_events(events: Array) -> void:
	# 再领 / 观战 / 回座只等自己的回执:别人的事件先到时仍不能重复发(房主会拒,界面弹多余的错误)
	for ev in events:
		if ev is Dictionary and ev.get("pid") == my_pid and SEAT_EVENTS.has(ev.get("type")):
			_seat_request_pending = false
	_queue.append_array(events)
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
	# 迟到者的第一帧(规格 §7):等第一份视图到达,整张桌按它瞬时摆好;之前排队的事件丢掉(视图已包含它们)
	while state.pub.is_empty() and is_inside_tree():
		await get_tree().process_frame
	_queue.clear()
	# 开场运镜期间可能已开了新的一手(他被排进座位)或有人离开:座位表变了就按视图重排
	if state.sync_from_view():
		_arrange()
	if state.between_hands:
		_next_left = PokerPacing.NEXT_HAND_TIMEOUT   # 中途进来正赶上两手之间:不知道房主还剩几秒,按整 15 秒数
	_sync_table()
	set_current(state.current_pid)


func _reconcile() -> void:
	# 演出结束后用最新视图兜底对齐(正常流程下视觉已与状态一致);座位表变了就重排
	if state.pub.is_empty():
		return
	var reseat := state.refresh_from_view()
	if reseat:
		_arrange()
	_sync_table()


func _sync_table() -> void:
	if chips == null or cards == null:
		refresh_hud()   # 不入树的测试:没有 3D 层
		return
	var pub := state.pub
	chips.sync(pub.get("players", []), state.pots)
	chips.place_button(state.positions["button"])
	cards.sync(state.seats, pub.get("players", []), state.board, my_pid, state.hole())
	_update_visibility()
	_sync_nameplates()
	refresh_hud()
	if director != null and _settlement == null:
		director.settle_camera()   # 结算时留在散局环绕镜头


# —— 3D ——

func _arrange() -> void:
	# 按座位表排座;迟到者按「座位表 + 自己」排、不建自己的酒客(规格 §5.5),入座时桌子不用转
	var seated := state.seats.has(my_pid)
	# 形象用房主分配的(Net.species_of 查本局座位表与等待厅名单):不带 species 时各端会按本地「第一个空着的」补,
	# 别人看到的就不是自己选的那只
	var entries := state.seat_entries(my_pid)
	for entry in entries:
		entry["species"] = Net.species_of(entry["pid"])
	world.arrange(entries, my_pid, seated, false)
	_update_visibility()
	_sync_nameplates()


func _update_visibility() -> void:
	# 本机观战者的酒客只在本机藏起来(别人照样看得到)
	world.set_patron_visible(my_pid, my_status() != PokerRules.STATUS_SPECTATING)


# —— 铭牌 ——

func _sync_nameplates() -> void:
	# 桌上有酒客的其他人各一块铭牌;离场的收走
	for pid in state.names:
		var wanted: bool = pid != my_pid and world.patrons.has(pid) and state.seats.has(pid)
		var plate: Control = app.labels.get_node_for(PLATE_KEY % pid)
		if wanted and plate == null:
			app.labels.track(PLATE_KEY % pid, PokerNameplate.new(name_of(pid)), world.nameplate_anchor.bind(pid))
		elif not wanted and plate != null:
			app.labels.untrack(PLATE_KEY % pid)
	_update_nameplates()


func _update_nameplates() -> void:
	for pid in state.names:
		var plate: PokerNameplate = app.labels.get_node_for(PLATE_KEY % pid)
		if plate != null:
			plate.set_info(state.row(pid), state.badge(pid), pid == state.current_pid)


# —— HUD ——

func refresh_hud() -> void:
	if hud == null:
		return
	hud.set_header(state.mode, state.pub.get("blinds", []), state.hand)
	hud.set_pots(state.pots)
	hud.set_board(state.board)
	hud.set_ending(state.ending or _end_requested)
	hud.set_my_status(name_of(my_pid), state.row(my_pid))
	hud.set_my_hole(state.hole())
	hud.set_my_best(state.best_detail())
	hud.set_showdown(state.showdown_entries(state.is_short_deck()) if state.in_showdown else [])
	_update_nameplates()
	refresh_actions()


func refresh_actions() -> void:
	# 底部中间放什么(规格 §6.1);下注控件只在演到自己回合、视图也说轮到自己时才展开
	if hud == null:
		return
	if _settlement != null:
		hud.set_bottom_mode(PokerHud.BOTTOM_NONE)   # 结算面板下面不再露出输光 / 观战提示
		return
	var mode := state.bottom_mode(my_pid)
	hud.set_bottom_mode(mode)
	if mode == PokerHud.BOTTOM_BET:
		hud.controls.update(state.pub if is_my_turn() else {}, my_pid)
	elif mode == PokerHud.BOTTOM_NEXT_WAIT:
		var progress := state.confirm_progress()
		hud.set_next_progress(progress[0], progress[1])


# —— 导演回调 ——

func name_of(pid: Variant) -> String:
	return state.name_of(pid)


func set_current(pid: Variant) -> void:
	state.current_pid = pid if pid is int else null
	_clock.restart_turn()
	_awaiting_intent = false
	if is_instance_valid(_fold_confirm):
		_fold_confirm.dismiss()   # 换了行动者(超时代打、下一手):旧的弃牌确认已没有意义
	_fold_confirm = null
	if hud == null:
		return   # 不入树的测试:没有 HUD 与酒客,只改状态
	# 所有人盯着当前行动者,行动者自己看桌心(规格 §5.6)
	var focus := PokerDirector.TABLE_FOCUS
	if pid is int and world.patrons.has(pid):
		focus = world.head_position(pid)
	for patron_pid in world.patrons:
		var patron: Patron = world.patrons[patron_pid]
		patron.set_active(patron_pid == pid)
		patron.look_at_point(PokerDirector.TABLE_FOCUS if patron_pid == pid else focus)
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
	refresh_actions()


func begin_hand(ev: Dictionary) -> void:
	# 导演在收牌前调用:换到新座位表,所有酒客复位(清掉上一手的庆祝、表情),HUD 清掉上一手
	state.apply_event(ev)
	_next_left = -1.0
	set_current(null)
	_arrange()
	for pid in world.patrons:
		world.patrons[pid].reset_pose()
		world.patrons[pid].set_active(false)
	world.look_all_at(PokerDirector.TABLE_FOCUS)
	hud.set_showdown([])
	refresh_hud()
	hud.set_my_hole([])   # 新一手的私有手牌可能已先到:2D 大图等发牌动画之后再露


func note_event(ev: Dictionary) -> void:
	# 演出每段开始前推进影子行:铭牌与自己的筹码行跟着演出走,不抢先跳到视图
	state.apply_event(ev)
	_update_nameplates()
	hud.set_my_status(name_of(my_pid), state.row(my_pid))


func hole_for_hand(number: int) -> Array:
	# 这一手的私有手牌通常紧随事件到达;最多等 HOLE_WAIT
	var waited := 0.0
	while state.hole_for_hand(number) == null and waited < HOLE_WAIT and is_inside_tree():
		await get_tree().process_frame
		waited += get_process_delta_time()
	var hole: Variant = state.hole_for_hand(number)
	return hole if hole is Array else []


func end_hand(_ev: Dictionary) -> void:
	# 房主等「开始下一手」的 15 秒从这一手演完(含 hand_over 本身)才开始算
	_next_left = PokerPacing.NEXT_HAND_TIMEOUT + PokerPacing.HAND_OVER
	set_current(null)


func add_record() -> void:
	# 导演演到 hand_record:记录已进 state.history;记录面板开着就刷新(停在当前页)
	if is_instance_valid(_history):
		_history.set_records(state.history, false)


func toggle_history() -> void:
	if is_instance_valid(_history):
		_history.close()
		return
	Sfx.play("ui_click")
	_history = HandHistoryPanel.new()
	_history.set_records(state.history)
	add_child(_history)


func drop_player(pid: Variant) -> void:
	# 离桌:铭牌与视线记录都不要了(酒客由导演让他离场)
	if not pid is int:
		return
	app.labels.untrack(PLATE_KEY % pid)
	if _gaze != null:
		_gaze.forget(pid)


func show_settlement(results: Array) -> void:
	hud.set_bottom_mode(PokerHud.BOTTOM_NONE)
	_next_left = -1.0
	_settlement = PokerSettlement.new(results, Net.is_host)
	_settlement.lobby_pressed.connect(func(): Net.request_rematch_lobby())
	_settlement.leave_pressed.connect(func(): Net.end_session())
	add_child(_settlement)


# —— 给按钮、快捷键与 bot 的入口 ——

func is_my_turn() -> bool:
	# 演出进行到自己的回合、视图也说轮到自己、没有未回执的动作、没在结算
	return state.current_pid == my_pid and not animating and not _awaiting_intent and _settlement == null \
		and not legal().is_empty()


func legal() -> Dictionary:
	return state.legal(my_pid)


func my_status() -> String:
	return state.status_of(my_pid)


func submit(action: String, amount := 0) -> bool:
	if not is_my_turn() or not PokerRules.BET_ACTIONS.has(action):
		return false
	_awaiting_intent = true
	Sfx.play("ui_click")
	Net.submit_poker_action(action, amount)
	refresh_actions()
	return true


func choose_rebuy() -> bool:
	# 「领取」按 status 显示,不按筹码数(规格 §6.4)
	return _request_seat([PokerRules.STATUS_BUSTED, PokerRules.STATUS_SPECTATING], Net.request_rebuy)


func choose_spectate() -> bool:
	return _request_seat([PokerRules.STATUS_BUSTED], Net.request_spectate)


func choose_next() -> bool:
	# 一手结束后点「开始下一手」(按钮、时间到与 bot 同一入口);等房主回执期间不重复发
	if _seat_request_pending or _settlement != null or not wants_next():
		return false
	_seat_request_pending = true
	Sfx.play("ui_click")
	Net.submit_poker_action(PokerRules.NEXT)
	return true


func wants_next() -> bool:
	return state.bottom_mode(my_pid) == PokerHud.BOTTOM_NEXT


func choose_sit_in() -> bool:
	return _request_seat([PokerRules.STATUS_AWAY], Net.request_sit_in)


func _request_seat(statuses: Array, request: Callable) -> bool:
	# 再领 / 观战 / 回座:等房主回执(下一批事件或拒绝)期间不重复发
	if _seat_request_pending or _settlement != null or state.pub.get("phase") == "over" or not statuses.has(my_status()):
		return false
	_seat_request_pending = true
	Sfx.play("ui_click")
	request.call()
	return true


# —— 输入 ——

func _unhandled_input(event: InputEvent) -> void:
	if _settlement != null:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		# 输光提示打开时 Esc 选观战(规格 §6.4),其余情况确认离开
		if not hud.handle_cancel():
			_confirm_leave()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V and not app.is_modal_open():
		# V 切换越肩 / 第一人称:观战时也能改设置(下次回座生效);快捷语面板或九宫格开着时不切
		get_viewport().set_input_as_handled()
		if not _chat_open():
			director.toggle_camera_mode()
		return
	if event is InputEventKey and event.pressed and not event.echo and not app.is_modal_open():
		if event.keycode == HandHistoryPanel.HOTKEY:
			get_viewport().set_input_as_handled()
			toggle_history()
		elif is_my_turn() and hud.controls.handle_key(event.keycode):
			get_viewport().set_input_as_handled()


func _confirm_fold() -> void:
	_fold_confirm = app.confirm(FOLD_CONFIRM, "弃牌")
	_fold_confirm.confirmed.connect(func(): submit(PokerRules.FOLD))


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
