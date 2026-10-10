extends GutTest
# 炸弹猫的房主端接线(离线 NetworkManager,不是 Net 自动加载;经 _handle_session_rpc / _on_turn_timeout /
# _on_peer_disconnected 等内部函数):按玩法建会话、字典意图入口的校验、每批之后的事件与视图下发
# (私有视图只给本人,含偷看结果)、窗口 / 塞回 / 给牌的真实计时器时长、断线、一局打完回等待厅。


const H := preload("res://tests/bomb_cat_helpers.gd")
const C := preload("res://src/core/bomb_cat/bomb_cat_card.gd")
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


func _start(mode := GameMode.BOMB_CAT) -> void:
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


func _state() -> BombCatState:
	return net._session.state()


func _rig(hands: Dictionary, deck: Array, current: int) -> void:
	H.rig(_state(), hands, deck, current)


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

func test_start_game_builds_a_bomb_cat_session():
	_start()
	assert_true(net._session is BombCatSession)
	assert_eq(_sent_to(10, "rpc_game_started")[0][1], {"mode": GameMode.BOMB_CAT, "late": false})
	assert_eq(H.types(_events), ["round_started"])
	var expected := Protocol.TURN_TIMEOUT + BombCatPacing.INTRO + BombCatPacing.ROUND_STARTED
	assert_almost_eq(net._turn_timer.time_left, expected, EPS, "开局 = 开场运镜 + 发牌 + 一个回合")
	assert_almost_eq(net.last_public["turn_time_left"], expected, EPS)
	assert_eq(net.last_public["mode"], GameMode.BOMB_CAT)
	assert_eq(net.last_private["hand"].size(), BombCatDeck.HAND_SIZE + 1, "房主自己的私有视图")
	for id in GUESTS:
		assert_eq(_private_to(id)["hand"], _state().hand_of(id), "每位客人只收到自己的手牌")
		assert_eq(H.view_leak(_public_to(id)), "")


func test_other_modes_keep_their_sessions():
	assert_true(net._new_session(GameMode.LIARS) is LiarsSession)
	assert_true(net._new_session(GameMode.HOLDEM) is PokerSession)
	assert_true(net._new_session(GameMode.SHORT_DECK) is PokerSession)
	assert_true(net._new_session(GameMode.BOMB_CAT) is BombCatSession)


func test_no_late_join_for_bomb_cat():
	_start()
	assert_false(net._accepting_late_join())
	assert_eq(net._lobby.check_join(Protocol.VERSION, true, GameMode.BOMB_CAT, false), LobbyModel.IN_GAME_REASON)
	assert_false(net._room_announcement()["open"])
	assert_eq(net._room_announcement()["cap"], 6)


# —— 意图入口 ——

func test_untrusted_intents_are_rejected_to_the_sender():
	_start()
	_rig({HOST: [C.SKIP], 10: [C.NOPE], 11: [C.SKIP]}, [C.PEEK, C.BEG], HOST)
	_intent(99, {"kind": "draw"})
	assert_eq(_rejections_to(99), ["not_seated"], "不在名单里")
	for bad in [null, "draw", 7, [{"kind": "draw"}], {"kind": "draw", "a": 1, "b": 2, "c": 3, "d": 4}, {"kind": "bogus"}]:
		_intent(10, bad)
		assert_eq(_rejections_to(10), [BombCatState.ERR_INVALID_INTENT], str(bad))
	_intent(10, {"kind": "draw"})
	assert_eq(_rejections_to(10), [BombCatState.ERR_NOT_YOUR_TURN])
	_intent(10, {"kind": "nope"})
	assert_eq(_rejections_to(10), [BombCatState.ERR_NO_WINDOW], "窗口外打不行")
	assert_eq(_state().step, BombCatState.Step.TURN, "被拒不改局面")
	assert_eq(_sent_to(10, "rpc_game_events"), [], "被拒不广播")


func test_host_intents_are_rejected_locally():
	_start()
	_rig({HOST: [C.SKIP], 10: [C.NOPE]}, [C.PEEK, C.BEG], 10)
	net.submit_session_intent({"kind": "draw"})
	assert_eq(_rejected, [BombCatState.ERR_NOT_YOUR_TURN])


func test_session_intents_are_refused_in_other_modes():
	_start(GameMode.LIARS)
	var before: Dictionary = net.last_public.duplicate(true)
	_intent(10, {"kind": "draw"})
	assert_eq(_rejections_to(10), [BombCatState.ERR_INVALID_INTENT])
	assert_eq(net.last_public, before, "骗子酒馆的局面不动")


func test_client_submit_goes_through_the_new_rpc():
	net.in_game = true
	net.is_host = false
	net.submit_session_intent({"kind": "nope"})
	assert_eq(net.sent, [[HOST, "rpc_session_intent", [{"kind": "nope"}]]])


# —— 一批之后的下发与计时 ——

func test_peek_result_goes_only_to_the_peeker_after_the_window():
	_start()
	_rig({HOST: [C.SKIP], 10: [C.PEEK, C.DEFUSE], 11: [C.NOPE]}, [C.BOMB, C.SHUFFLE, C.BEG, C.SKIP], 10)
	_intent(10, {"kind": "play", "cards": [0]})
	assert_eq(H.types(_events), ["played"])
	for id in GUESTS:
		assert_eq(H.types(_sent_to(id, "rpc_game_events")[0][0]), ["played"], "事件广播给全员")
		assert_eq(_public_to(id)["step"], "window")
	assert_almost_eq(net._turn_timer.time_left, BombCatPacing.PLAYED + BombCatState.REACT_WINDOW, EPS,
		"窗口 = 本批演出 + 3 秒")
	net.sent = []
	net._on_turn_timeout()   # 窗口到点
	assert_eq(H.types(_events), ["window_resolved", "effect"])
	assert_eq(_private_to(10)["peek"], [C.BOMB, C.SHUFFLE, C.BEG])
	assert_eq(_private_to(11)["peek"], [])
	assert_eq(net.last_private["peek"], [], "房主也看不到")
	for ev in _events:
		assert_eq(H.event_leak(ev), "")


func test_window_pauses_the_turn_clock_and_resumes_it():
	_start()
	_rig({HOST: [C.SKIP], 10: [C.PEEK, C.DEFUSE], 11: [C.NOPE]}, [C.BOMB, C.SHUFFLE, C.BEG, C.SKIP], 10)
	net._turn_timer.start(20.0)
	_intent(10, {"kind": "play", "cards": [0]})
	assert_almost_eq(net.last_public["paused_turn_left"], 20.0, EPS)
	_intent(11, {"kind": "nope"})
	var nope_budget := BombCatPacing.PLAYED + BombCatPacing.NOPED + BombCatState.REACT_WINDOW
	assert_almost_eq(net._turn_timer.time_left, nope_budget, EPS, "不行不清演出欠账,窗口从排队演出播完算起")
	net._on_turn_timeout()
	assert_almost_eq(net._turn_timer.time_left, BombCatPacing.WINDOW_RESOLVED + 20.0, EPS, "恢复暂停前的 20 秒")
	assert_eq(net.last_public["step"], "turn")


func test_reinsert_and_give_use_their_own_timeouts():
	_start()
	_rig({HOST: [C.SKIP], 10: [C.DEFUSE, C.BEG], 11: [C.NOPE]}, [C.BOMB, C.SHUFFLE, C.BEG], 10)
	_intent(10, {"kind": "draw"})
	assert_eq(_private_to(10)["reinsert"], {"deck_count": 2})
	assert_eq(_private_to(11)["reinsert"], {})
	var budget := BombCatPacing.DREW + BombCatPacing.BOMB_DRAWN + BombCatPacing.DEFUSED + BombCatState.REINSERT_TIMEOUT
	assert_almost_eq(net._turn_timer.time_left, budget, EPS)
	_intent(10, {"kind": "reinsert", "pos": 1})
	assert_eq(_state().deck[1], C.BOMB)
	assert_eq(net.last_public["current_pid"], 11)
	assert_almost_eq(net._turn_timer.time_left, BombCatPacing.REINSERTED + BombCatPacing.TURN_PASSED + Protocol.TURN_TIMEOUT, EPS)
	# 11 号讨要 10 号
	_state().hands[11] = [C.BEG]
	_intent(11, {"kind": "play", "cards": [0], "target": 10})
	net.sent = []
	net._on_turn_timeout()
	assert_eq(_private_to(10)["give"], {"to": 11})
	assert_almost_eq(net._turn_timer.time_left, BombCatPacing.WINDOW_RESOLVED + BombCatPacing.GIVE_REQUESTED + BombCatState.GIVE_TIMEOUT, EPS)
	_intent(10, {"kind": "give", "index": 0})
	assert_eq(_private_to(11)["transfer"]["card"], C.BEG)
	assert_eq(_private_to(10)["transfer"]["to"], 11)
	assert_eq(net.last_public["step"], "turn")


func test_disconnect_eliminates_and_keeps_the_game_going():
	_start()
	_rig({HOST: [C.SKIP], 10: [C.SKIP], 11: [C.SKIP]}, [C.PEEK, C.BEG], 10)
	net._on_peer_disconnected(10)
	assert_eq(H.types(_events), ["player_left", "turn_passed"])
	assert_eq(net.last_public["current_pid"], 11)
	assert_false(net._turn_timer.is_stopped())
	net._on_peer_disconnected(11)
	assert_eq(_events[-1]["type"], "match_over")
	assert_true(net._turn_timer.is_stopped())
	assert_eq(net.last_public["winner"], HOST)


func test_timeouts_alone_finish_a_match_and_the_lobby_reopens():
	_start()
	var guard := 0
	while not net._session.is_over() and guard < 2000:
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
