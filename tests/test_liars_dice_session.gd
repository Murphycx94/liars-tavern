extends GutTest
# 吹牛骰子会话(设计稿 §2、§4):意图逐字段校验(不可信输入)、哪些动作消耗回合、视图里谁看到什么
# (私有视图只有自己的点数,公共视图只有骰子数与出价)、回合计时、超时代打、断线、不收中途加入。


const H := preload("res://tests/liars_dice_helpers.gd")
const NAMES := {1: "甲", 2: "乙", 3: "丙"}
const EPS := 0.001
const PENDING := 1.25   # 假装客户端还要演这么久

var session: LiarsDiceSession


func before_each():
	session = LiarsDiceSession.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	session.start([1, 2, 3], NAMES, rng)


func _s() -> LiarsDiceState:
	return session.state()


func _rig(dice: Dictionary, current := 1, bid := {}) -> void:
	H.rig(_s(), dice, current, bid)


func _ok(pid: int, intent: Dictionary) -> Dictionary:
	var result := session.handle_intent(pid, intent)
	assert_true(result["ok"], "%s 应当成功:%s" % [str(intent), str(result.get("error", ""))])
	return result


func _err(pid: int, intent: Variant, code: String) -> void:
	var result := session.handle_intent(pid, intent)
	assert_eq([result["ok"], result.get("error")], [false, code], str(intent))
	assert_false(result["turn_action"])


# —— 开局 ——

func test_start_returns_round_started_and_the_turn_timer_is_full():
	var fresh := LiarsDiceSession.new()
	var events := fresh.start([1, 2], {1: "甲", 2: "乙"}, RandomNumberGenerator.new())
	assert_eq(H.types(events), ["round_started"])
	assert_true(fresh.has_turn())
	assert_false(fresh.is_over())
	assert_false(fresh.accepts_late_join(), "不收中途加入")
	assert_eq(fresh.add_player(9, "迟到"), [])
	assert_almost_eq(fresh.turn_timer_after(events, PENDING, 0.0), PENDING + Protocol.TURN_TIMEOUT, EPS)


func test_session_without_a_match_is_over_and_rejects_everything():
	var idle := LiarsDiceSession.new()
	assert_true(idle.is_over())
	assert_eq(idle.handle_intent(1, {"kind": "challenge"})["error"], LiarsDiceState.ERR_MATCH_OVER)
	assert_eq(idle.on_turn_timeout()["error"], LiarsDiceState.ERR_MATCH_OVER)
	assert_eq(idle.on_disconnect(1), [])
	assert_eq(idle.viewers(), [])


# —— 意图校验 ——

func test_check_intent_accepts_exactly_the_two_shapes():
	assert_eq(LiarsDiceSession.check_intent({"kind": "bid", "count": 3, "face": 4}), "")
	assert_eq(LiarsDiceSession.check_intent({"kind": "challenge"}), "")
	assert_eq(session.validate_intent({"kind": "challenge"}), "", "NetworkManager 的入口用 validate_intent")


func test_malformed_intents_are_rejected_without_touching_the_state():
	_rig({1: [1, 2, 3], 2: [2, 4, 6], 3: [5, 5]}, 1, {"pid": 3, "count": 2, "face": 3})
	var before := [_s().current_pid, _s().bid.duplicate(), _s().dice.duplicate(true), _s().round_no]
	var bad := [
		[null, LiarsDiceState.ERR_INVALID_INTENT],
		["challenge", LiarsDiceState.ERR_INVALID_INTENT],
		[[{"kind": "challenge"}], LiarsDiceState.ERR_INVALID_INTENT],
		[{}, LiarsDiceState.ERR_INVALID_INTENT],
		[{"kind": 3}, LiarsDiceState.ERR_INVALID_INTENT],
		[{"kind": "fold"}, LiarsDiceState.ERR_INVALID_INTENT],
		[{"kind": "draw"}, LiarsDiceState.ERR_INVALID_INTENT],
		[{"kind": "challenge", "target": 2}, LiarsDiceState.ERR_INVALID_INTENT],
		[{"kind": "bid", "count": 3, "face": 4, "pid": 2}, LiarsDiceState.ERR_INVALID_INTENT],
		[{"kind": "bid", "face": 4}, LiarsDiceState.ERR_INVALID_COUNT],
		[{"kind": "bid", "count": "3", "face": 4}, LiarsDiceState.ERR_INVALID_COUNT],
		[{"kind": "bid", "count": 3.0, "face": 4}, LiarsDiceState.ERR_INVALID_COUNT],
		[{"kind": "bid", "count": [3], "face": 4}, LiarsDiceState.ERR_INVALID_COUNT],
		[{"kind": "bid", "count": 3}, LiarsDiceState.ERR_INVALID_FACE],
		[{"kind": "bid", "count": 3, "face": 4.5}, LiarsDiceState.ERR_INVALID_FACE],
		[{"kind": "bid", "count": 3, "face": null}, LiarsDiceState.ERR_INVALID_FACE],
		[{"kind": "bid", "count": 3, "face": 1}, LiarsDiceState.ERR_INVALID_FACE],
		[{"kind": "bid", "count": 3, "face": 7}, LiarsDiceState.ERR_INVALID_FACE],
		[{"kind": "bid", "count": 0, "face": 4}, LiarsDiceState.ERR_INVALID_COUNT],
		[{"kind": "bid", "count": -4, "face": 4}, LiarsDiceState.ERR_INVALID_COUNT],
		[{"kind": "bid", "count": 99, "face": 4}, LiarsDiceState.ERR_BID_TOO_HIGH],
		[{"kind": "bid", "count": 2, "face": 3}, LiarsDiceState.ERR_BID_TOO_LOW],
		[{"kind": "bid", "count": 1, "face": 6}, LiarsDiceState.ERR_BID_TOO_LOW],
	]
	for case in bad:
		if case[0] is Dictionary:
			_err(1, case[0], case[1])
		else:
			assert_eq(LiarsDiceSession.check_intent(case[0]), case[1], str(case[0]))
	assert_eq([_s().current_pid, _s().bid, _s().dice, _s().round_no], before, "被拒的意图不改局面")


func test_seat_and_turn_are_checked():
	_rig({1: [1, 2, 3], 2: [2, 4, 6]}, 1)
	_err(9, {"kind": "challenge"}, LiarsDiceState.ERR_NOT_SEATED)
	_err(2, {"kind": "bid", "count": 1, "face": 2}, LiarsDiceState.ERR_NOT_YOUR_TURN)
	_err(3, {"kind": "bid", "count": 1, "face": 2}, LiarsDiceState.ERR_OUT)
	_err(1, {"kind": "challenge"}, LiarsDiceState.ERR_NO_BID)


func test_bid_and_challenge_are_turn_actions():
	_rig({1: [1, 2, 3], 2: [2, 4, 6], 3: [5, 5]}, 1)
	var bid := _ok(1, {"kind": "bid", "count": 2, "face": 5})
	assert_true(bid["turn_action"])
	assert_eq(H.types(bid["events"]), ["bid", "turn_passed"])
	var challenge := _ok(2, {"kind": "challenge"})
	assert_true(challenge["turn_action"])
	assert_eq(H.types(challenge["events"]).slice(0, 3), ["challenged", "revealed", "die_lost"])
	assert_eq(H.find(challenge["events"], "revealed")["actual"], 3, "1 点万能 + 5,5")


# —— 视图 ——

func test_private_view_is_only_your_own_dice():
	_rig({1: [1, 2, 3], 2: [2, 4, 6], 3: [5, 5]}, 1)
	for pid in [1, 2, 3]:
		var priv := session.private_view(pid)
		assert_eq(priv.keys(), H.PRIVATE_VIEW_KEYS)
		assert_eq(priv["dice"], _s().dice_of(pid))
		assert_true(priv["alive"])
		assert_eq(priv["round"], _s().round_no)
	assert_eq(session.viewers(), [1, 2, 3], "出局者也收私有视图")


func test_eliminated_players_see_no_dice():
	_rig({1: [1, 2, 3], 2: [2, 4, 6]}, 1)
	assert_eq(session.private_view(3), {"dice": [], "alive": false, "round": _s().round_no})


func test_public_view_has_counts_and_bids_but_no_dice():
	_rig({1: [1, 2, 3], 2: [2, 4, 6], 3: [5, 5]}, 1)
	_ok(1, {"kind": "bid", "count": 2, "face": 5})
	var view := session.public_view(12.5)
	assert_eq(H.view_leak(view, _s()), "")
	assert_eq(view["mode"], GameMode.LIARS_DICE)
	assert_eq(view["step"], "bid")
	assert_eq(view["current_pid"], 2)
	assert_eq(view["bid"], {"pid": 1, "count": 2, "face": 5})
	assert_eq(view["bids"], [{"pid": 1, "count": 2, "face": 5}])
	assert_eq(view["total_dice"], 8)
	assert_eq(view["players"], [
		{"pid": 1, "name": "甲", "alive": true, "dice_count": 3},
		{"pid": 2, "name": "乙", "alive": true, "dice_count": 3},
		{"pid": 3, "name": "丙", "alive": true, "dice_count": 2},
	])
	assert_eq(view["last_reveal"], {})
	assert_eq(view["ranking"], [])
	assert_almost_eq(view["turn_time_left"], 12.5, EPS)


func test_public_view_keeps_the_last_reveal_and_ranks_at_the_end():
	_rig({1: [2], 2: [3], 3: []}, 1, {"pid": 2, "count": 2, "face": 6})
	_ok(1, {"kind": "challenge"})
	var view := session.public_view(5.0)
	assert_eq(view["step"], "over")
	assert_eq(view["winner"], 1)
	assert_eq(view["last_reveal"]["dice"], [{"pid": 1, "dice": [2]}, {"pid": 2, "dice": [3]}])
	assert_eq(view["ranking"], [
		{"pid": 1, "name": "甲", "place": 1}, {"pid": 2, "name": "乙", "place": 2},
	])
	assert_eq(view["turn_time_left"], 0.0, "结束后不计时")
	assert_true(session.is_over())
	assert_false(session.has_turn())


# —— 计时 ——

func test_every_batch_hands_over_a_full_turn_after_the_show():
	_rig({1: [1, 2, 3], 2: [2, 4, 6], 3: [5, 5]}, 1)
	var bid := _ok(1, {"kind": "bid", "count": 2, "face": 5})
	assert_almost_eq(session.turn_timer_after(bid["events"], PENDING, 7.0), PENDING + Protocol.TURN_TIMEOUT, EPS)
	var challenge := _ok(2, {"kind": "challenge"})
	assert_almost_eq(session.turn_timer_after(challenge["events"], PENDING, 7.0), PENDING + Protocol.TURN_TIMEOUT, EPS)


func test_batches_without_a_turn_change_keep_the_clock():
	assert_almost_eq(session.turn_timer_after([], PENDING, 9.0), 9.0, EPS, "没换人:保留剩余")
	assert_almost_eq(session.turn_timer_after([], PENDING, 0.0), PENDING + Protocol.TURN_TIMEOUT, EPS, "计时器没在走:给满")


func test_estimate_follows_the_pacing_budget():
	var events := [
		{"type": "challenged"}, {"type": "revealed", "actual": 4}, {"type": "die_lost"}, {"type": "player_out"},
		{"type": "round_started"},
	]
	var expected := LiarsDicePacing.CHALLENGED + LiarsDicePacing.REVEAL_BASE + 4 * LiarsDicePacing.REVEAL_PER_MATCH \
		+ LiarsDicePacing.DIE_LOST + LiarsDicePacing.PLAYER_OUT + LiarsDicePacing.ROUND_STARTED
	assert_almost_eq(session.estimate(events), expected, EPS)
	assert_almost_eq(LiarsDicePacing.reveal_time({"actual": 999}),
		LiarsDicePacing.REVEAL_BASE + LiarsDicePacing.REVEAL_MATCH_CAP * LiarsDicePacing.REVEAL_PER_MATCH, EPS, "计数有上限")
	assert_almost_eq(LiarsDicePacing.reveal_time({"actual": "x"}), LiarsDicePacing.REVEAL_BASE, EPS)


func test_timeout_auto_plays_as_a_turn_action():
	_rig({1: [1, 2, 3], 2: [2, 4, 6], 3: [5, 5]}, 1, {"pid": 3, "count": 8, "face": 5})
	var result := session.on_turn_timeout()
	assert_true(result["ok"])
	assert_true(result["turn_action"])
	assert_eq(result["events"][0], {"type": "bid", "pid": 1, "count": 8, "face": 6, "auto": true})
	result = session.on_turn_timeout()
	assert_eq(result["events"][0]["type"], "challenged", "加不上去就开")
	assert_true(result["events"][0]["auto"])


# —— 断线 ——

func test_disconnect_rerolls_and_unknown_pids_do_nothing():
	_rig({1: [1, 2, 3], 2: [2, 4, 6], 3: [5, 5]}, 2)
	assert_eq(session.on_disconnect(42), [])
	var events := session.on_disconnect(2)
	assert_eq(H.types(events), ["player_left", "round_started"])
	assert_eq(_s().current_pid, 3)
	assert_eq(session.on_disconnect(2), [], "已经出局的人再断线不重复")
	events = session.on_disconnect(3)
	assert_eq(H.types(events), ["player_left", "match_over"])
	assert_true(session.is_over())


func test_names_and_patrons():
	assert_eq(session.name_of(2), "乙")
	assert_eq(session.name_of(77), "77")
	assert_eq(session.seats_with_patrons(), [1, 2, 3])
