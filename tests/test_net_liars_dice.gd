extends GutTest
# 吹牛骰子的房主端接线(离线 NetworkManager,不是 Net 自动加载;经 _handle_session_rpc / _on_turn_timeout /
# _on_peer_disconnected 等内部函数):按玩法建会话、字典意图入口的校验(会话的 validate_intent)、
# 每批之后的事件与视图下发(私有视图只给本人)、回合计时器时长、断线重摇、不收中途加入、一局打完回等待厅。


const H := preload("res://tests/liars_dice_helpers.gd")
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
var _events: Array = []        # 房主自己收到的最近一批事件
var _rejected: Array = []      # 房主自己被拒的错误码


func before_each():
	net = StubNet.new()
	add_child_autofree(net)
	net.game_events.connect(func(events: Array) -> void: _events = events)
	net.intent_rejected.connect(func(code: String) -> void: _rejected.append(code))
	_rejected = []


func after_each():
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _start(mode := GameMode.LIARS_DICE) -> void:
	net.is_host = true
	net._session_active = true
	net.game_mode = mode
	var lobby := LobbyModel.new()
	lobby.add_host("房主")
	for id in GUESTS:
		lobby.add_member(id, "客%d" % id)
		lobby.set_ready(id, true)
	net._lobby = lobby
	net.start_game()


func _state() -> LiarsDiceState:
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


# —— 开局 ——

func test_start_game_builds_a_liars_dice_session():
	_start()
	assert_true(net._session is LiarsDiceSession)
	assert_eq(_sent_to(10, "rpc_game_started")[0][1], {"mode": GameMode.LIARS_DICE, "late": false})
	assert_eq(H.types(_events), ["round_started"])
	var expected := Protocol.TURN_TIMEOUT + LiarsDicePacing.INTRO + LiarsDicePacing.ROUND_STARTED
	assert_almost_eq(net._turn_timer.time_left, expected, EPS, "开局 = 开场运镜 + 摇盅 + 一个回合")
	assert_almost_eq(net.last_public["turn_time_left"], expected, EPS)
	assert_eq(net.last_public["mode"], GameMode.LIARS_DICE)
	assert_eq(net.last_private["dice"], _state().dice_of(HOST), "房主自己的私有视图")
	for id in GUESTS:
		assert_eq(_private_to(id)["dice"], _state().dice_of(id), "每位客人只收到自己的点数")
		assert_eq(H.view_leak(_public_to(id), _state()), "")
		assert_eq(H.event_leak(_sent_to(id, "rpc_game_events")[0][0][0]), "")


func test_every_mode_gets_its_own_session():
	assert_true(net._new_session(GameMode.LIARS) is LiarsSession)
	assert_true(net._new_session(GameMode.HOLDEM) is PokerSession)
	assert_true(net._new_session(GameMode.BOMB_CAT) is BombCatSession)
	assert_true(net._new_session(GameMode.LIARS_DICE) is LiarsDiceSession)


func test_no_late_join_for_liars_dice():
	_start()
	assert_false(net._accepting_late_join())
	assert_eq(net._lobby.check_join(Protocol.VERSION, true, GameMode.LIARS_DICE, false), LobbyModel.IN_GAME_REASON)
	assert_false(net._room_announcement()["open"])
	assert_eq(net._room_announcement()["cap"], 6)
	assert_eq(net._room_announcement()["mode"], GameMode.LIARS_DICE)


# —— 意图入口 ——

func test_untrusted_intents_are_rejected_to_the_sender():
	_start()
	H.rig(_state(), {HOST: [1, 2, 3], 10: [4, 5, 6], 11: [2, 2]}, HOST)
	_intent(99, {"kind": "challenge"})
	assert_eq(_rejections_to(99), ["not_seated"], "不在名单里")
	for bad in [null, "challenge", 7, [{"kind": "challenge"}], {"kind": "bogus"}, {"kind": "challenge", "x": 1},
			{"kind": "draw"}, {"kind": "bid", "count": 2, "face": 3, "extra": true}]:
		_intent(10, bad)
		assert_eq(_rejections_to(10), [LiarsDiceState.ERR_INVALID_INTENT], str(bad))
	_intent(10, {"kind": "bid", "count": "2", "face": 3})
	assert_eq(_rejections_to(10), [LiarsDiceState.ERR_INVALID_COUNT])
	_intent(10, {"kind": "bid", "count": 2, "face": 1})
	assert_eq(_rejections_to(10), [LiarsDiceState.ERR_NOT_YOUR_TURN], "还没轮到他:先报这个")
	_intent(10, {"kind": "challenge"})
	assert_eq(_rejections_to(10), [LiarsDiceState.ERR_NOT_YOUR_TURN])
	assert_eq(_state().bid, {}, "被拒不改局面")
	assert_eq(_sent_to(10, "rpc_game_events"), [], "被拒不广播")


func test_host_intents_are_rejected_locally():
	_start()
	H.rig(_state(), {HOST: [1, 2, 3], 10: [4, 5, 6]}, HOST)
	net.submit_session_intent({"kind": "bid", "count": 1, "face": 1})
	assert_eq(_rejected, [LiarsDiceState.ERR_INVALID_FACE])
	net.submit_session_intent({"kind": "challenge"})
	assert_eq(_rejected, [LiarsDiceState.ERR_INVALID_FACE, LiarsDiceState.ERR_NO_BID])


func test_bomb_cat_intents_are_refused_in_a_dice_room_and_vice_versa():
	_start()
	_intent(10, {"kind": "draw"})
	assert_eq(_rejections_to(10), [LiarsDiceState.ERR_INVALID_INTENT])
	net._session = null
	net.in_game = false
	_start(GameMode.BOMB_CAT)
	_intent(10, {"kind": "challenge"})
	assert_eq(_rejections_to(10), [BombCatState.ERR_INVALID_INTENT])


func test_session_intents_are_refused_in_liars_and_poker_rooms():
	for mode in [GameMode.LIARS, GameMode.HOLDEM]:
		net._session = null
		net.in_game = false
		_start(mode)
		var before: Dictionary = net.last_public.duplicate(true)
		_intent(10, {"kind": "challenge"})
		assert_eq(_rejections_to(10), ["invalid_intent"], mode)
		assert_eq(net.last_public, before, "%s 的局面不动" % mode)


func test_client_submit_goes_through_the_session_rpc():
	net.in_game = true
	net.is_host = false
	net.submit_session_intent({"kind": "bid", "count": 2, "face": 5})
	assert_eq(net.sent, [[HOST, "rpc_session_intent", [{"kind": "bid", "count": 2, "face": 5}]]])


# —— 一批之后的下发与计时 ——

func test_bid_is_broadcast_and_restarts_the_turn_clock():
	_start()
	H.rig(_state(), {HOST: [1, 2, 3], 10: [4, 5, 6], 11: [2, 2]}, 10)
	net._turn_timer.start(4.0)
	_intent(10, {"kind": "bid", "count": 3, "face": 5})
	assert_eq(H.types(_events), ["bid", "turn_passed"])
	for id in GUESTS:
		assert_eq(H.types(_sent_to(id, "rpc_game_events")[0][0]), ["bid", "turn_passed"], "事件广播给全员")
		assert_eq(_public_to(id)["bid"], {"pid": 10, "count": 3, "face": 5})
		assert_eq(_public_to(id)["current_pid"], 11)
	assert_almost_eq(net._turn_timer.time_left, LiarsDicePacing.BID + LiarsDicePacing.TURN_PASSED + Protocol.TURN_TIMEOUT, EPS,
		"出手的人清掉演出欠账:本批演出 + 一个完整回合")


func test_challenge_reveals_to_everyone_then_rerolls_privately():
	_start()
	H.rig(_state(), {HOST: [1, 2, 3], 10: [4, 5, 6], 11: [2, 2]}, 11, {"pid": 10, "count": 4, "face": 2})
	_intent(11, {"kind": "challenge"})
	assert_eq(H.types(_events), ["challenged", "revealed", "die_lost", "round_started"])
	var revealed := H.find(_events, "revealed")
	assert_eq(revealed["actual"], 4, "1,2 + 2,2")
	assert_true(revealed["truthful"])
	assert_eq(H.find(_events, "die_lost")["pid"], 11, "开错了的人丢一颗")
	for id in GUESTS:
		assert_eq(_private_to(id)["dice"], _state().dice_of(id), "新一轮的点数只给本人")
		assert_eq(_private_to(id)["round"], H.find(_events, "round_started")["round"])
		assert_eq(_public_to(id)["last_reveal"]["actual"], 4)
	assert_eq(_state().dice_count(11), 1)
	var budget := LiarsDicePacing.estimate(_events) + Protocol.TURN_TIMEOUT
	assert_almost_eq(net._turn_timer.time_left, budget, EPS, "开盅、丢骰子、重摇都演完再给满一个回合")


func test_disconnect_rerolls_and_keeps_the_game_going():
	_start()
	H.rig(_state(), {HOST: [1, 2, 3], 10: [4, 5, 6], 11: [2, 2]}, 10)
	net._on_peer_disconnected(10)
	assert_eq(H.types(_events), ["player_left", "round_started"])
	assert_eq(net.last_public["current_pid"], 11)
	assert_false(net._turn_timer.is_stopped())
	net._on_peer_disconnected(11)
	assert_eq(_events[-1]["type"], "match_over")
	assert_true(net._turn_timer.is_stopped())
	assert_eq(net.last_public["winner"], HOST)


func test_timeouts_alone_finish_a_match_and_the_lobby_reopens():
	_start()
	var guard := 0
	while not net._session.is_over() and guard < 3000:
		assert_false(net._turn_timer.is_stopped(), "没结束就一直在计时")
		net._on_turn_timeout()
		guard += 1
	assert_true(net._session.is_over(), "只靠超时代打也能打完一局")
	assert_true(net._turn_timer.is_stopped())
	assert_eq(net.last_public["step"], "over")
	assert_eq(net.last_public["ranking"].size(), 3)
	net.request_rematch_lobby()
	assert_false(net.in_game)
	assert_eq(net._session, null)
