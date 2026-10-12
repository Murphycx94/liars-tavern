extends GutTest
# 21 点牌桌整体流程(无头,加速演出):真实的 BlackjackScreen + BlackjackDirector + BjCards + BjChips + HUD,
# 背后是一个真的 BlackjackSession(不走网络:牌桌的 intent_sink 直接交给会话,每批按房主的顺序先发事件、再发公共视图)。
# 自己走真实的界面入口(下注、要牌 / 停牌 / 加倍 / 分牌),别人按会话局面随机出合法的一步,卡住时按房主的计时器到点代打;
# 打几局后房主散局:断言没有被拒的意图、3D 的牌与视图一致、暗牌翻开之前桌上看不到、结算面板与会话一致。


const ScreenScript := preload("res://src/ui/blackjack/blackjack_screen.gd")
const R := preload("res://src/core/blackjack/bj_rules.gd")
const ME := 1
const PIDS := [1, 2, 3]
const SPEED := 16.0
const MAX_STEPS := 1500
const MAX_WAIT := 30.0
const TIMEOUT_AFTER := 0.3


class StubTavern:
	extends Node
	var camera_rig: CameraRig

	func kick_lamp(_strength: float) -> void:
		pass


class StubApp:
	extends Node
	var banter_view: BanterView = null
	var world: TableWorld
	var labels: WorldLabels
	var tavern: StubTavern
	var toasts: Array = []
	var modes: Array = []

	func apply_table_mode(mode: String) -> void:
		modes.append(mode)
		world.configure_table(SeatLayout.table_radius_for(mode))

	func toast(text: String, _color := Color.WHITE) -> void:
		toasts.append(text)

	func show_rules() -> void:
		pass

	func is_rules_open() -> bool:
		return false

	func is_modal_open() -> bool:
		return false

	func confirm(_message: String, _a := "", _b := "") -> ConfirmOverlay:
		return null


var app: StubApp
var screen: Node
var session: BlackjackSession
var rng := RandomNumberGenerator.new()
var saved := {}
var rejected: Array = []
var accepted: Array = []
var leaks: Array = []    # 庄家翻牌之前桌上亮出来的暗牌


func before_each():
	saved = {"seats": Net.seats, "pub": Net.last_public, "priv": Net.last_private, "mode": Net.game_mode, "scale": Engine.time_scale}
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Engine.time_scale = SPEED
	app = StubApp.new()
	add_child_autofree(app)
	app.labels = WorldLabels.new(null)
	app.add_child(app.labels)
	app.tavern = StubTavern.new()
	app.tavern.camera_rig = CameraRig.new()
	app.tavern.add_child(app.tavern.camera_rig)
	app.add_child(app.tavern)
	app.world = TableWorld.new(null)
	app.add_child(app.world)
	Net.game_mode = GameMode.BLACKJACK
	Net.last_public = {}
	Net.last_private = {}
	rejected = []
	accepted = []
	leaks = []


func after_each():
	Net.seats = saved["seats"]
	Net.last_public = saved["pub"]
	Net.last_private = saved["priv"]
	Net.game_mode = saved["mode"]
	Engine.time_scale = saved["scale"]


func _open(seed_value: int, pids := PIDS) -> void:
	rng.seed = seed_value
	var names := {}
	for pid in pids:
		names[pid] = "P%d" % pid
	Net.seats = pids.map(func(pid): return {"pid": pid, "name": names[pid], "species": (pid + 1) % Species.count()})
	session = BlackjackSession.new()
	var start_rng := RandomNumberGenerator.new()
	start_rng.seed = seed_value
	var events := session.start(pids, names, start_rng)
	screen = ScreenScript.new(app)
	screen.intent_sink = _on_intent
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(screen)
	_send(events)


func _send(events: Array) -> void:
	screen._on_events(events)
	screen._on_public(session.public_view(10.0))


func _on_intent(intent: Dictionary) -> void:
	var result := session.handle_intent(ME, intent)
	if result["ok"]:
		accepted.append(intent["kind"])
		_send(result["events"])
	else:
		rejected.append([intent, result["error"]])
		screen._on_rejected(result["error"])


func _idle() -> bool:
	return screen._intro_done and not screen.animating


func _my_step() -> bool:
	# 走真实的界面入口:下注阶段下注(偶尔这局不玩),轮到自己时偏好分牌 / 加倍,否则 16 以下要牌
	if screen.can_bet():
		if rng.randf() < 0.1:
			return screen.submit_skip()
		return screen.submit_bet(R.BET_UNIT * rng.randi_range(1, 10))
	if not screen.is_my_turn():
		return false
	var legal: Dictionary = screen.legal()
	var hand: Array = screen.state.hands_of(ME)[screen.state.current["hand"]]["cards"]
	if legal[R.SPLIT]:
		return screen.submit_action(R.SPLIT)
	if legal[R.DOUBLE] and BjScore.total(hand) in [10, 11]:
		return screen.submit_action(R.DOUBLE)
	return screen.submit_action(R.HIT if BjScore.total(hand) < 16 else R.STAND)


func _others_step() -> bool:
	var view := session.public_view(1.0)
	if view["phase"] == "betting":
		for pid in PIDS:
			if pid != ME and session.table().awaiting_bets().has(pid):
				return _apply(pid, {"kind": R.BET, "amount": R.BET_UNIT * rng.randi_range(1, 25)})
		return false
	var current: Variant = view["current"]
	if current == null or current["pid"] == ME:
		return false
	var kinds := R.PLAY_ACTIONS.filter(func(kind): return view["actions"].get(kind, false))
	return _apply(current["pid"], {"kind": kinds[rng.randi_range(0, kinds.size() - 1)]})


func _apply(pid: int, intent: Dictionary) -> bool:
	var result := session.handle_intent(pid, intent)
	assert_true(result["ok"], "别人的合法意图被拒:%s %s %s" % [pid, intent, result.get("error")])
	if result["ok"]:
		_send(result["events"])
	return result["ok"]


func _check_hole() -> void:
	# 打牌中(庄家还没翻牌)桌上的庄家牌只能是一张明牌 + 一张背面
	var view := session.public_view(0.0)
	if view["phase"] == "playing" and view["dealer"]["hidden"]:
		var kinds: Array = screen.cards.dealer_kinds()
		if kinds.size() == 2 and kinds[1] != CardFaces.BACK:
			leaks.append(kinds)


func _check_table() -> void:
	# 演出放完后,3D 的牌与视图一致
	var view := session.public_view(0.0)
	var dealer: Array = view["dealer"]["cards"].duplicate()
	if view["dealer"]["hidden"]:
		dealer.append(CardFaces.BACK)
	assert_eq(screen.cards.dealer_kinds(), dealer, "庄家的牌")
	for row in view["players"]:
		if not app.world.seat_angles.has(row["pid"]):
			continue
		var want: Array = row["hands"].map(func(hand: Dictionary) -> Array:
			return [] if hand["surrendered"] else hand["cards"])
		if not want.is_empty():
			assert_eq(screen.cards.hand_kinds(row["pid"]), want, "P%d 的牌" % row["pid"])


func _play_rounds(target_rounds: int) -> void:
	var idle_for := 0.0
	var steps := 0
	while not session.is_over() and steps < MAX_STEPS:
		steps += 1
		await wait_until(_idle, MAX_WAIT, "演出播完")
		_check_hole()
		if session.is_over():
			break
		if not session.has_turn():
			if session.next_hand_ready():
				if session.table().round_number() >= target_rounds:
					_send(session.request_end())
				else:
					_check_table()
					_send(session.start_next_hand())
			else:
				for result in [session.handle_intent(ME, {"kind": R.REBUY}), session.handle_intent(ME, {"kind": R.SIT_IN})]:
					if result["ok"]:
						_send(result["events"])
			await get_tree().process_frame
			continue
		if _my_step() or _others_step():
			idle_for = 0.0
			await get_tree().process_frame
			continue
		await get_tree().create_timer(0.1 * SPEED).timeout
		idle_for += 0.1
		if idle_for >= TIMEOUT_AFTER:
			idle_for = 0.0
			var result := session.on_turn_timeout()
			if result["ok"]:
				_send(result["events"])
	assert_true(session.is_over(), "牌局要能散")
	await wait_until(func(): return screen.settlement() != null, MAX_WAIT, "结算面板")


func test_rounds_then_host_ends_and_settles():
	_open(7)
	assert_eq(app.modes, [GameMode.BLACKJACK])
	assert_almost_eq(app.world.table_radius, SeatLayout.POKER_TABLE_RADIUS, 0.001, "用德州的大桌")
	await wait_until(_idle, MAX_WAIT, "开局")
	assert_eq(screen.hud.controls.mode(), BjControls.MODE_BET, "开局就是下注阶段")
	await _play_rounds(6)
	assert_eq(leaks, [], "庄家翻牌之前看不到暗牌")
	assert_eq(rejected, [], "自己的意图都按规则出,不该被拒")
	assert_true(accepted.has(R.BET), "自己下过注:%s" % [accepted])
	assert_true(accepted.has(R.HIT) or accepted.has(R.STAND), "自己做过决策:%s" % [accepted])
	var settlement: PokerSettlement = screen.settlement()
	assert_not_null(settlement)
	assert_true(app.world.is_celebrating(), "散局开演庆祝")
	screen.get_parent().remove_child(screen)
	await get_tree().process_frame
	assert_false(app.world.is_celebrating(), "退场收起庆祝")
	add_child(screen)


func test_solo_round_matches_the_view():
	_open(21, [ME])
	await wait_until(_idle, MAX_WAIT, "开局")
	assert_true(screen.submit_bet(100))
	await wait_until(_idle, MAX_WAIT, "发牌")
	_check_table()
	assert_eq(screen.hud.controls.mode() if session.has_turn() else BjControls.MODE_HIDDEN,
		BjControls.MODE_PLAY if session.has_turn() else BjControls.MODE_HIDDEN, "轮到自己时展开决策按钮")
	var steps := 0
	while session.has_turn() and session.public_view(0.0)["phase"] == "playing" and steps < 10:
		steps += 1
		assert_true(screen.submit_action(R.STAND))
		await wait_until(_idle, MAX_WAIT, "停牌")
	assert_eq(session.public_view(0.0)["phase"], "idle")
	_check_table()
	var mine: Array = session.public_view(0.0)["players"][0]["hands"]
	assert_ne(mine[0]["outcome"], "", "结算过")
	assert_eq(screen.state.hands_of(ME)[0]["outcome"], mine[0]["outcome"], "HUD 的影子跟上了结算")
	assert_eq(rejected, [])
