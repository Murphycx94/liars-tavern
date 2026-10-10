extends GutTest
# 斗地主牌桌整体流程(无头,加速演出):真实的 DouDizhuScreen + DdzDirector + DdzCards + DdzFx + HUD,
# 背后是一个真的 DouDizhuSession(不走网络:牌桌的 intent_sink 直接交给会话,每批按房主的顺序先发事件、再发公共 / 私有视图)。
# 自己由 DdzBot 走真实的界面入口出手(叫分、提示、出牌、不出),别人按会话局面随机出合法的牌,卡住时按房主的计时器到点代打;
# 打几手后房主散局:断言没有被拒的意图、3D 牌数与视图一致、一手结束前看不到别人的牌、帽子跟着身份、结算面板与会话一致。


const ScreenScript := preload("res://src/ui/dou_dizhu/dou_dizhu_screen.gd")
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
var session: DouDizhuSession
var rng := RandomNumberGenerator.new()
var saved := {}
var bot: DdzBot
var rejected: Array = []
var accepted: Array = []
var leaks: Array = []            # 一手结束前别人牌扇里亮出来的牌


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
	Net.game_mode = GameMode.DOU_DIZHU
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


func _open(seed_value: int) -> void:
	rng.seed = seed_value
	bot = DdzBot.new(seed_value + 1)
	var names := {}
	for pid in PIDS:
		names[pid] = "P%d" % pid
	Net.seats = PIDS.map(func(pid): return {"pid": pid, "name": names[pid], "species": (pid + 1) % Species.count()})
	session = DouDizhuSession.new()
	var start_rng := RandomNumberGenerator.new()
	start_rng.seed = seed_value
	var events := session.start(PIDS, names, start_rng)
	screen = ScreenScript.new(app)
	screen.intent_sink = _on_intent
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(screen)
	_send(events)


func _send(events: Array) -> void:
	# 同房主的顺序:先事件,再公共视图,再私有视图
	screen._on_events(events)
	screen._on_public(session.public_view(10.0))
	screen._on_private(session.private_view(ME))


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


func _others_step() -> bool:
	var s := session.state()
	if not session.has_turn() or s.current_pid == ME:
		return false
	var pid: int = s.current_pid
	var view := session.private_view(pid)
	if s.phase == DdzState.Phase.BIDDING:
		var options: Array = view["bid_options"]
		var score: int = 0 if rng.randf() < 0.5 else options[rng.randi_range(0, options.size() - 1)]
		return _apply(pid, {"kind": "bid", "score": score})
	if view["can_pass"] and rng.randf() < 0.3:
		return _apply(pid, {"kind": "pass"})
	var hints: Array = view["hints"]
	if hints.is_empty():
		return _apply(pid, {"kind": "pass"})
	var i := rng.randi_range(0, mini(hints.size() - 1, 2)) if rng.randf() < 0.85 else rng.randi_range(0, hints.size() - 1)
	return _apply(pid, {"kind": "play", "cards": hints[i]["indices"]})


func _apply(pid: int, intent: Dictionary) -> bool:
	var result := session.handle_intent(pid, intent)
	assert_true(result["ok"], "别人的合法意图被拒:%s %s %s" % [pid, intent, result.get("error")])
	if result["ok"]:
		_send(result["events"])
	return result["ok"]


func _check_hidden() -> void:
	# 一手结束之前,别人的牌扇里不能有亮面的牌
	if session.state().phase == DdzState.Phase.PLAYING or session.state().phase == DdzState.Phase.BIDDING:
		var shown: Array = screen.cards.face_up_ids_of_others()
		if not shown.is_empty():
			leaks.append(shown)


func _play_hands(target_hands: int) -> void:
	var idle_for := 0.0
	var steps := 0
	while not session.is_over() and steps < MAX_STEPS:
		steps += 1
		await wait_until(_idle, MAX_WAIT, "演出播完")
		_check_hidden()
		if session.is_over():
			break
		if not session.has_turn():
			if session.next_hand_ready():
				if session.state().hand_number >= target_hands:
					_send(session.request_end())
				else:
					_send(session.start_next_hand())
			await get_tree().process_frame
			continue
		var acted := false
		if bot.act(screen):
			acted = true
		elif _others_step():
			acted = true
		if acted:
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


func _check_table() -> void:
	var pub: Dictionary = session.public_view(0.0)
	for row in pub["players"]:
		assert_eq(screen.cards.held_count(row["pid"]), row["hand_count"], "P%d 的牌扇张数" % row["pid"])
		assert_eq(screen.cards.row_ids(row["pid"]), DdzLayout.row_order(row["table"]), "P%d 面前的牌" % row["pid"])
	assert_eq(screen.cards.my_ids(), session.private_view(ME)["cards"], "自己的牌扇")
	assert_eq(screen.hud.strip.ids(), session.private_view(ME)["cards"], "2D 手牌条")


func test_three_hands_then_host_ends_and_settles():
	_open(7)
	assert_eq(app.modes, [GameMode.DOU_DIZHU])
	assert_almost_eq(app.world.table_radius, SeatLayout.TABLE_RADIUS, 0.001, "3 人用骗子酒馆的小桌")
	await wait_until(_idle, MAX_WAIT, "开局发牌")
	_check_table()
	assert_eq(screen.cards.bottom_cards().size(), DdzState.BOTTOM_SIZE, "底牌扣在桌心")
	await _play_hands(3)
	assert_eq(leaks, [], "一手结束前看不到别人的牌")
	var settlement: DdzSettlement = screen.settlement()
	assert_not_null(settlement)
	var expected := DdzScreenState.ranking(session.public_view(0.0)["results"]).map(func(r: Dictionary): return [r["pid"], r["score"]])
	assert_eq(settlement.rows().map(func(r: Dictionary): return [r["pid"], r["score"]]), expected, "结算行与会话一致")
	assert_eq(DdzScreenState.score_sum(settlement.rows()), 0, "三人总和为 0")
	assert_true(app.world.is_celebrating(), "散局开演庆祝")
	assert_eq(rejected, [], "自己的意图都按规则出,不该被拒")
	assert_true(accepted.has("bid"), "自己叫过分:%s" % [accepted])
	assert_true(accepted.has("play"), "自己出过牌:%s" % [accepted])
	screen.get_parent().remove_child(screen)
	await get_tree().process_frame
	assert_false(app.world.is_celebrating(), "退场收起庆祝")
	for pid in app.world.patrons:
		assert_eq(DdzHats.role_of(app.world.patrons[pid]), "", "退场摘帽")
	add_child(screen)


func test_hats_follow_roles_and_table_matches_mid_hand():
	_open(11)
	await wait_until(_idle, MAX_WAIT, "开局发牌")
	var steps := 0
	while session.state().phase == DdzState.Phase.BIDDING and steps < 60:
		steps += 1
		if not bot.act(screen) and not _others_step():
			var result := session.on_turn_timeout()
			if result["ok"]:
				_send(result["events"])
		await wait_until(_idle, MAX_WAIT, "叫分演完")
	assert_eq(session.state().phase, DdzState.Phase.PLAYING, "叫完分进出牌")
	var landlord: int = session.state().landlord
	for pid in app.world.patrons:
		var want := DdzState.ROLE_LANDLORD if pid == landlord else DdzState.ROLE_FARMER
		assert_eq(DdzHats.role_of(app.world.patrons[pid]), want, "P%d 的帽子" % pid)
	assert_eq(screen.hud.bottom_shown(), session.public_view(0.0)["bottom"], "左上亮出底牌")
	assert_eq(screen.cards.bottom_cards().size(), 0, "底牌进了地主手里")
	_check_table()
	assert_eq(screen.cards.face_up_ids_of_others(), [], "别人手里的底牌也是牌背")
