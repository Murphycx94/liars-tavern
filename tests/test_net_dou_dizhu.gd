extends GutTest
# 斗地主的房主端接线(离线 NetworkManager,不是 Net 自动加载;经 _handle_session_rpc / _on_turn_timeout /
# _on_hand_timer / _on_peer_disconnected 等内部函数):正好 3 人才能开局、按玩法建会话、字典意图入口的校验、
# 每批之后的事件与视图下发(手牌只给本人)、回合计时与托管、两手之间的计时器、散局、离开提前结算、回等待厅。


const D := preload("res://tests/ddz_helpers.gd")
const EPS := 0.05
const HOST := LobbyModel.HOST_ID
const GUESTS := [10, 11]


class StubNet:
	extends "res://src/net/network_manager.gd"
	# sent:经 _send_to 发出的 [id, 方法, 参数]
	var sent: Array = []

	func _send_to(id: int, method: StringName, args: Array = []) -> void:
		sent.append([id, String(method), args])


var net: StubNet
var _events: Array = []
var _rejected: Array = []


func before_each():
	net = StubNet.new()
	add_child_autofree(net)
	net.game_events.connect(func(events: Array) -> void: _events = events)
	net.intent_rejected.connect(func(code: String) -> void: _rejected.append(code))
	_rejected = []


func after_each():
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _lobby(guests: Array, mode := GameMode.DOU_DIZHU) -> void:
	net.is_host = true
	net._session_active = true
	net.game_mode = mode
	var lobby := LobbyModel.new()
	lobby.add_host("房主")
	for id in guests:
		lobby.add_member(id, "客%d" % id)
		lobby.set_ready(id, true)
	net._lobby = lobby


func _start(mode := GameMode.DOU_DIZHU) -> void:
	_lobby(GUESTS, mode)
	net.start_game()


func _state() -> DdzState:
	return net._session.state()


func _intent(pid: int, intent: Variant) -> void:
	net.sent = []
	net._handle_session_rpc(pid, intent)


func _sent_to(id: int, method: String) -> Array:
	return net.sent.filter(func(e: Array) -> bool: return e[0] == id and e[1] == method).map(func(e: Array): return e[2])


func _rejections_to(id: int) -> Array:
	return _sent_to(id, "rpc_intent_rejected").map(func(args: Array) -> String: return args[0])


func _private_to(id: int) -> Dictionary:
	var list := _sent_to(id, "rpc_state_private")
	return list[-1][0] if not list.is_empty() else {}


func _public_to(id: int) -> Dictionary:
	var list := _sent_to(id, "rpc_state_public")
	return list[-1][0] if not list.is_empty() else {}


func _rig(hands: Dictionary, landlord: int, current: int) -> void:
	D.rig_play(_state(), hands, landlord, current)


# —— 开局 ——

func test_needs_exactly_three_players():
	_lobby([10])
	assert_false(net.can_start(), "2 人不能开斗地主")
	net.start_game()
	assert_false(net.in_game)
	_lobby(GUESTS)
	assert_true(net.can_start())
	assert_eq(net._lobby.check_join(Protocol.VERSION, false, GameMode.DOU_DIZHU, false), "房间已满(3/3)", "第 4 人进不来")
	assert_eq(net._room_announcement()["cap"], 3)
	_lobby([10], GameMode.LIARS)
	assert_true(net.can_start(), "其他玩法照旧 2 人能开")


func test_start_game_builds_a_dou_dizhu_session():
	_start()
	assert_true(net._session is DouDizhuSession)
	assert_eq(_sent_to(10, "rpc_game_started")[0][1], {"mode": GameMode.DOU_DIZHU, "late": false})
	assert_eq(D.types(_events), ["hand_started", "turn"])
	var expected := DouDizhuSession.BID_TIMEOUT + DouDizhuPacing.INTRO + DouDizhuPacing.HAND_STARTED
	assert_almost_eq(net._turn_timer.time_left, expected, EPS, "开局 = 开场运镜 + 发牌 + 叫分时间")
	assert_almost_eq(net.last_public["turn_time_left"], expected, EPS)
	assert_eq(net.last_public["mode"], GameMode.DOU_DIZHU)
	assert_eq(net.last_private["cards"], _state().hand_of(HOST), "房主自己的私有视图")
	for id in GUESTS:
		assert_eq(_private_to(id)["cards"], _state().hand_of(id), "每位客人只收到自己的手牌")
		assert_eq(D.view_leak(_public_to(id), D.revealed_cards(_state())), "")


func test_session_factory_and_no_late_join():
	assert_true(net._new_session(GameMode.DOU_DIZHU) is DouDizhuSession)
	assert_true(net._new_session(GameMode.BOMB_CAT) is BombCatSession)
	assert_true(net._new_session(GameMode.LIARS) is LiarsSession)
	_start()
	assert_false(net._accepting_late_join())
	assert_eq(net._lobby.check_join(Protocol.VERSION, true, GameMode.DOU_DIZHU, false), LobbyModel.IN_GAME_REASON)
	assert_false(net._room_announcement()["open"])


# —— 意图入口 ——

func test_untrusted_intents_are_rejected_to_the_sender():
	_start()
	var first: int = _state().first_bidder
	var other: int = GUESTS[0] if GUESTS[0] != first else GUESTS[1]   # 不轮到他的客人
	_intent(99, {"kind": "pass"})
	assert_eq(_rejections_to(99), ["not_seated"])
	for bad in [null, "bid", 7, [{"kind": "pass"}], {"kind": "draw"}, {"kind": "pass", "x": 1}]:
		_intent(other, bad)
		assert_eq(_rejections_to(other), [DdzState.ERR_INVALID_INTENT], str(bad))
	_intent(other, {"kind": "bid", "score": 9})
	assert_eq(_rejections_to(other), [DdzState.ERR_INVALID_BID])
	_intent(other, {"kind": "bid", "score": 1})
	assert_eq(_rejections_to(other), [DdzState.ERR_NOT_YOUR_TURN])
	assert_eq(_sent_to(other, "rpc_game_events"), [], "被拒不广播")
	assert_eq(_state().bids, [], "被拒不改局面")


func test_host_intents_are_handled_locally():
	_start()
	var first: int = _state().first_bidder
	if first == HOST:
		net.submit_session_intent({"kind": "play", "cards": [0]})
		assert_eq(_rejected, [DdzState.ERR_NOT_PLAYING])
	else:
		net.submit_session_intent({"kind": "bid", "score": 1})
		assert_eq(_rejected, [DdzState.ERR_NOT_YOUR_TURN])


func test_dou_dizhu_intents_are_refused_in_other_modes():
	_start(GameMode.BOMB_CAT)
	_intent(10, {"kind": "bid", "score": 1})
	assert_eq(_rejections_to(10), [BombCatState.ERR_INVALID_INTENT], "炸弹猫不认 bid")
	net.in_game = false
	_start(GameMode.LIARS)
	assert_true(net._session is LiarsSession)
	_intent(10, {"kind": "pass"})
	assert_eq(_rejections_to(10), [BombCatState.ERR_INVALID_INTENT])


func test_client_submit_goes_through_the_session_rpc():
	net.in_game = true
	net.is_host = false
	net.submit_session_intent({"kind": "bid", "score": 2})
	assert_eq(net.sent, [[HOST, "rpc_session_intent", [{"kind": "bid", "score": 2}]]])


# —— 叫分、出牌与计时 ——

func test_bids_broadcast_and_the_timer_follows_the_stage():
	_start()
	var first: int = _state().first_bidder
	_intent(first, {"kind": "bid", "score": 3})
	assert_eq(D.types(_events), ["bid", "landlord", "turn"])
	for id in GUESTS:
		assert_eq(D.types(_sent_to(id, "rpc_game_events")[0][0]), ["bid", "landlord", "turn"], "事件广播给全员")
		assert_eq(_public_to(id)["bottom"], _state().bottom, "底牌亮给所有人")
	var budget := DouDizhuPacing.BID + DouDizhuPacing.LANDLORD + DouDizhuPacing.TURN + Protocol.TURN_TIMEOUT
	assert_almost_eq(net._turn_timer.time_left, budget, EPS, "出牌回合 30 秒,从演出播完算起")
	var priv := _private_to(first) if first != HOST else net.last_private
	assert_eq(priv["cards"].size(), 20)
	assert_gt(priv["hints"].size(), 0)


func test_trustee_shortens_the_clock_and_gets_auto_played():
	_start()
	_rig({HOST: D.cards("3 4 5"), 10: D.cards("6 7"), 11: D.cards("8 9")}, HOST, 10)
	net._anim_left = 0.0   # 开局演出已播完
	_intent(10, {"kind": "trustee", "on": true})
	assert_eq(D.types(_events), ["trustee"])
	assert_almost_eq(net._turn_timer.time_left, DouDizhuPacing.TRUSTEE_DELAY, EPS, "轮到托管的人:很快代打")
	net._on_turn_timeout()
	var played := D.find(_events, "played")
	assert_eq([played["pid"], played["auto"]], [10, true])
	assert_eq(net.last_public["current_pid"], 11)
	assert_almost_eq(net._turn_timer.time_left, DouDizhuPacing.PLAYED + Protocol.TURN_TIMEOUT, EPS)


func test_hand_timer_starts_the_next_hand_after_the_gap():
	_start()
	_rig({HOST: D.cards("3"), 10: D.cards("4"), 11: D.cards("5")}, HOST, HOST)
	net.submit_session_intent({"kind": "play", "cards": [0]})
	assert_eq(D.types(_events), ["played", "hand_over"])
	assert_true(net._turn_timer.is_stopped(), "两手之间不计回合")
	assert_false(net._hand_timer.is_stopped())
	assert_almost_eq(net._hand_timer.time_left, DouDizhuPacing.PLAYED + DouDizhuPacing.HAND_OVER + DouDizhuPacing.HAND_OVER_SPRING
		+ DouDizhuPacing.HAND_GAP, EPS, "演完结算再停 HAND_GAP")
	assert_eq(net.last_public["phase"], "between")
	assert_eq(net.last_public["last_hand"]["winner"], HOST)
	net._on_hand_timer()
	assert_eq(D.types(_events), ["hand_started", "turn"])
	assert_eq(_events[0]["hand"], 2)
	assert_false(net._turn_timer.is_stopped())
	assert_true(net._hand_timer.is_stopped())


func test_host_ends_the_session_after_the_current_hand():
	_start()
	_rig({HOST: D.cards("3 9"), 10: D.cards("4 K"), 11: D.cards("5 2")}, HOST, HOST)
	net.end_poker_session()
	assert_eq(D.types(_events), ["ending"])
	assert_true(net.last_public["ending"])
	net.submit_session_intent({"kind": "play", "cards": [1]})
	_intent(10, {"kind": "pass"})
	_intent(11, {"kind": "pass"})
	net.submit_session_intent({"kind": "play", "cards": [0]})
	assert_eq(D.types(_events), ["played", "hand_over", "session_over"])
	assert_true(net._session.is_over())
	assert_true(net._turn_timer.is_stopped())
	assert_true(net._hand_timer.is_stopped(), "散局后不再开下一手")
	assert_eq(net.last_public["results"].size(), 3)
	assert_eq(net.last_public["results"][0]["name"], "房主")
	net.request_rematch_lobby()
	assert_false(net.in_game)
	assert_eq(net._session, null)


func test_a_leaver_ends_the_session_early():
	_start()
	net.sent = []
	net._on_peer_disconnected(10)
	assert_eq(D.types(_events), ["player_left", "session_over"])
	assert_eq(_events[1]["reason"], "player_left")
	assert_true(net._session.is_over())
	assert_true(net._turn_timer.is_stopped())
	assert_true(net._hand_timer.is_stopped())
	assert_eq(net.last_public["phase"], "over")
	assert_eq(_sent_to(10, "rpc_state_private"), [], "离开的人不再收私有视图")


func test_timeouts_alone_keep_dealing_hands_until_the_host_ends_it():
	_start()
	var guard := 0
	while net.last_public.get("hand", 0) < 3 and guard < 3000:
		guard += 1
		if net._session.has_turn():
			assert_false(net._turn_timer.is_stopped(), "有人行动就在计时")
			net._on_turn_timeout()
		else:
			assert_false(net._hand_timer.is_stopped(), "两手之间排着下一手")
			net._on_hand_timer()
	assert_eq(net.last_public["hand"], 3, "只靠超时代打也能一手接一手")
	net.end_poker_session()
	while not net._session.is_over() and guard < 6000:
		guard += 1
		net._on_turn_timeout()
	assert_true(net._session.is_over())
	var total := 0
	for row in net.last_public["results"]:
		total += row["score"]
	assert_eq(total, 0, "三人总分为 0")
