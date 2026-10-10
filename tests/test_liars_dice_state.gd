extends GutTest
# 吹牛骰子规则引擎(设计稿 §1、§4):加注合法性、1 点万能计数、「开!」判定双方向、丢骰子与出局、
# 下一轮谁先喊、胜负与名次、超时代打、断线、开盅前公共事件不含点数、同种子可复现。


const H := preload("res://tests/liars_dice_helpers.gd")
const S := LiarsDiceState.Step


func _ok(result: Dictionary) -> Array:
	assert_true(result["ok"], "应当成功:%s" % str(result.get("error", "")))
	return result["events"]


func _err(result: Dictionary, code: String) -> void:
	assert_eq([result["ok"], result.get("error"), result["events"]], [false, code, []])


func _snapshot(s: LiarsDiceState) -> Array:
	return [s.step, s.current_pid, s.bid.duplicate(), s.bids.duplicate(true), s.dice.duplicate(true), s.round_no, s.out_order.duplicate()]


# —— 开局 ——

func test_start_rolls_five_dice_each_and_announces_counts_only():
	var s := H.new_state([1, 2, 3])
	assert_eq(s.step, S.BID)
	assert_eq(s.round_no, 1)
	assert_eq(s.total_dice(), 15)
	for pid in [1, 2, 3]:
		var roll := s.dice_of(pid)
		assert_eq(roll.size(), LiarsDiceState.DICE_PER_PLAYER)
		var sorted := roll.duplicate()
		sorted.sort()
		assert_eq(roll, sorted, "点数从小到大")
		for value in roll:
			assert_between(value, 1, 6)
	assert_true([1, 2, 3].has(s.current_pid))
	assert_eq(s.starter_pid, s.current_pid)
	assert_eq(s.bid, {})


func test_start_event_is_round_started_without_dice():
	var s := LiarsDiceState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var events := _ok(s.start([4, 5], rng))
	assert_eq(H.types(events), ["round_started"])
	var ev: Dictionary = events[0]
	assert_eq(ev["round"], 1)
	assert_eq(ev["seats"], [4, 5])
	assert_eq(ev["counts"], [{"pid": 4, "count": 5}, {"pid": 5, "count": 5}])
	assert_eq(ev["total"], 10)
	assert_eq(ev["starter"], s.current_pid)
	assert_eq(H.event_leak(ev), "")


func test_player_count_must_be_two_to_six():
	for pids in [[], [1], [1, 2, 3, 4, 5, 6, 7]]:
		_err(LiarsDiceState.new().start(pids, RandomNumberGenerator.new()), LiarsDiceState.ERR_INVALID_PLAYERS)
	assert_true(LiarsDiceState.new().start([1, 2, 3, 4, 5, 6], RandomNumberGenerator.new())["ok"])


func test_same_seed_rolls_the_same_dice():
	var a := H.new_state([1, 2, 3], 99)
	var b := H.new_state([1, 2, 3], 99)
	assert_eq(a.dice, b.dice)
	assert_eq(a.current_pid, b.current_pid)


# —— 喊价 ——

func test_bid_passes_the_turn_to_the_next_seat():
	var s := H.new_state([1, 2, 3])
	H.rig(s, {1: [1, 2, 3, 4, 5], 2: [2, 2, 2, 2, 2], 3: [6, 6, 6, 6, 6]}, 3)
	var events := _ok(s.place_bid(3, 4, 6))
	assert_eq(events, [
		{"type": "bid", "pid": 3, "count": 4, "face": 6, "auto": false},
		{"type": "turn_passed", "pid": 1},
	])
	assert_eq(s.bid, {"pid": 3, "count": 4, "face": 6})
	assert_eq(s.bids, [{"pid": 3, "count": 4, "face": 6}])
	assert_eq(s.current_pid, 1, "绕回座位第一位")


func test_raise_rules_more_dice_or_same_count_higher_face():
	var s := H.new_state([1, 2])
	H.rig(s, {1: [1, 2, 3, 4, 5], 2: [2, 3, 4, 5, 6]}, 1, {"pid": 2, "count": 3, "face": 4})
	_err(s.place_bid(1, 3, 4), LiarsDiceState.ERR_BID_TOO_LOW)
	_err(s.place_bid(1, 3, 3), LiarsDiceState.ERR_BID_TOO_LOW)
	_err(s.place_bid(1, 2, 6), LiarsDiceState.ERR_BID_TOO_LOW)
	assert_true(s.place_bid(1, 3, 5)["ok"], "个数相同、点数更大")
	assert_true(s.place_bid(2, 4, 2)["ok"], "个数更多、点数随意")


func test_face_must_be_two_to_six_because_ones_are_wild():
	var s := H.new_state([1, 2])
	H.rig(s, {1: [1, 2, 3, 4, 5], 2: [2, 3, 4, 5, 6]}, 1)
	for face in [1, 0, 7, -2, 2.0, "3", null]:
		_err(s.place_bid(1, 2, face), LiarsDiceState.ERR_INVALID_FACE)
	for count in [0, -1, 1.0, "2", null]:
		_err(s.place_bid(1, count, 3), LiarsDiceState.ERR_INVALID_COUNT)


func test_count_cannot_exceed_the_dice_on_the_table():
	var s := H.new_state([1, 2])
	H.rig(s, {1: [1, 2, 3], 2: [2, 3]}, 1)
	_err(s.place_bid(1, 6, 2), LiarsDiceState.ERR_BID_TOO_HIGH)
	assert_true(s.place_bid(1, 5, 2)["ok"], "正好等于总数可以")


func test_first_bid_can_be_one_die():
	var s := H.new_state([1, 2])
	H.rig(s, {1: [1, 2, 3, 4, 5], 2: [2, 3, 4, 5, 6]}, 1)
	assert_true(s.place_bid(1, 1, 2)["ok"])


func test_only_the_current_living_member_may_act():
	var s := H.new_state([1, 2, 3])
	H.rig(s, {1: [1, 2], 2: [3, 4]}, 1)
	_err(s.place_bid(2, 1, 2), LiarsDiceState.ERR_NOT_YOUR_TURN)
	_err(s.place_bid(3, 1, 2), LiarsDiceState.ERR_OUT)
	_err(s.place_bid(9, 1, 2), LiarsDiceState.ERR_NOT_SEATED)
	_err(s.challenge(9), LiarsDiceState.ERR_NOT_SEATED)


func test_rejections_leave_the_state_untouched():
	var s := H.new_state([1, 2, 3])
	H.rig(s, {1: [1, 2, 3], 2: [3, 4, 5], 3: [6, 6]}, 2, {"pid": 1, "count": 3, "face": 5})
	var before := _snapshot(s)
	s.place_bid(2, 3, 4)
	s.place_bid(2, 9, 6)
	s.place_bid(3, 4, 6)
	s.challenge(3)
	assert_eq(_snapshot(s), before)


func test_challenge_needs_a_bid_this_round():
	var s := H.new_state([1, 2])
	H.rig(s, {1: [1, 2], 2: [3, 4]}, 1)
	_err(s.challenge(1), LiarsDiceState.ERR_NO_BID)


# —— 开盅判定 ——

func test_ones_count_as_the_called_face():
	var s := H.new_state([1, 2, 3])
	H.rig(s, {1: [1, 1, 3, 4, 5], 2: [3, 3, 6, 6, 2], 3: [1, 4, 4, 4, 2]}, 1)
	assert_eq(s.count_matching(3), 6, "1,1,3 + 3,3 + 1")
	assert_eq(s.count_matching(4), 7)
	assert_eq(s.count_matching(6), 5)


func test_truthful_bid_makes_the_challenger_lose_a_die():
	var s := H.new_state([1, 2, 3])
	H.rig(s, {1: [1, 3, 3, 5, 6], 2: [2, 2, 4, 5, 6], 3: [1, 1, 3, 4, 6]}, 2, {"pid": 1, "count": 5, "face": 3})
	var events := _ok(s.challenge(2))
	assert_eq(H.types(events), ["challenged", "revealed", "die_lost", "round_started"])
	assert_eq(events[0], {"type": "challenged", "pid": 2, "target": 1, "count": 5, "face": 3, "auto": false})
	var revealed: Dictionary = events[1]
	assert_eq(revealed["actual"], 6, "3,3 + 1 + 1,1,3")
	assert_true(revealed["truthful"])
	assert_eq(revealed["face"], 3)
	assert_eq(revealed["count"], 5)
	assert_eq(revealed["dice"], [
		{"pid": 1, "dice": [1, 3, 3, 5, 6]}, {"pid": 2, "dice": [2, 2, 4, 5, 6]}, {"pid": 3, "dice": [1, 1, 3, 4, 6]},
	], "开盅时全场点数按座位顺序")
	assert_eq(events[2], {"type": "die_lost", "pid": 2, "left": 4})
	assert_eq(s.dice_count(2), 4)
	assert_eq(events[3]["starter"], 2, "输的人开下一轮")
	assert_eq(events[3]["round"], s.round_no)
	assert_eq(s.current_pid, 2)
	assert_eq(s.bid, {}, "新一轮清空出价")
	assert_eq(s.total_dice(), 14)


func test_exactly_the_count_is_still_truthful():
	var s := H.new_state([1, 2])
	H.rig(s, {1: [1, 4, 4], 2: [2, 3, 5]}, 2, {"pid": 1, "count": 3, "face": 4})
	var events := _ok(s.challenge(2))
	assert_eq(H.find(events, "revealed")["actual"], 3)
	assert_eq(H.find(events, "die_lost")["pid"], 2, "实际 = 喊的个数也算真话")


func test_bluff_makes_the_bidder_lose_a_die():
	var s := H.new_state([1, 2, 3])
	H.rig(s, {1: [2, 2, 2, 5, 6], 2: [3, 4, 4, 5, 6], 3: [2, 3, 4, 5, 6]}, 3, {"pid": 2, "count": 4, "face": 6})
	var events := _ok(s.challenge(3))
	var revealed := H.find(events, "revealed")
	assert_eq(revealed["actual"], 3)
	assert_false(revealed["truthful"])
	assert_eq(H.find(events, "die_lost"), {"type": "die_lost", "pid": 2, "left": 4})
	assert_eq(H.find(events, "round_started")["starter"], 2, "吹牛的上家输了,他开下一轮")
	var expected := revealed.duplicate(true)
	expected.erase("type")
	assert_eq(s.last_reveal, expected, "开盅结果留在 last_reveal(公共视图用)")


func test_new_round_rerolls_everyone_with_their_remaining_dice():
	var s := H.new_state([1, 2, 3], 5)
	H.rig(s, {1: [6, 6, 6], 2: [6, 6], 3: [6]}, 1, {"pid": 3, "count": 6, "face": 2})
	var events := _ok(s.challenge(1))
	var started := H.find(events, "round_started")
	assert_eq(started["counts"], [{"pid": 1, "count": 3}, {"pid": 2, "count": 2}, {"pid": 3, "count": 0}])
	assert_eq(started["total"], 5)
	assert_eq(H.find(events, "player_out"), {"type": "player_out", "pid": 3})
	assert_eq([s.dice_count(1), s.dice_count(2), s.dice_count(3)], [3, 2, 0])
	assert_false(s.is_alive(3))
	assert_eq(started["starter"], 1, "输家出局,由他之后的下一位存活者开(3 之后绕回 1)")
	assert_eq(s.out_order, [3])


func test_losing_the_last_die_eliminates_and_the_last_one_standing_wins():
	var s := H.new_state([1, 2, 3])
	H.rig(s, {1: [2, 3], 2: [5], 3: [4, 4]}, 3, {"pid": 2, "count": 3, "face": 5})
	var events := _ok(s.challenge(3))
	assert_eq(H.types(events), ["challenged", "revealed", "die_lost", "player_out", "round_started"])
	assert_eq(H.find(events, "round_started")["starter"], 3, "2 出局,由 2 之后的 3 开")
	# 再来一轮:1 喊 5 个 6 被 3 开,1 没有骰子了
	H.rig(s, {1: [2], 3: [4, 4]}, 3, {"pid": 1, "count": 3, "face": 6})
	events = _ok(s.challenge(3))
	assert_eq(H.types(events), ["challenged", "revealed", "die_lost", "player_out", "match_over"])
	assert_eq(events[-1], {"type": "match_over", "winner": 3, "ranking": [3, 1, 2]})
	assert_eq(s.step, S.OVER)
	assert_eq(s.winner_pid, 3)
	assert_eq(s.current_pid, null)
	assert_eq(s.dice_count(3), 2, "胜者留着他的骰子(不再重摇)")
	assert_eq(s.alive_pids(), [3])
	_err(s.place_bid(3, 1, 2), LiarsDiceState.ERR_MATCH_OVER)
	_err(s.challenge(3), LiarsDiceState.ERR_MATCH_OVER)
	_err(s.timeout(), LiarsDiceState.ERR_MATCH_OVER)


# —— 超时代打 ——

func test_timeout_opens_with_one_two():
	var s := H.new_state([1, 2])
	H.rig(s, {1: [3, 4], 2: [5, 6]}, 2)
	var events := _ok(s.timeout())
	assert_eq(events[0], {"type": "bid", "pid": 2, "count": 1, "face": 2, "auto": true})


func test_timeout_makes_the_minimum_legal_raise():
	var s := H.new_state([1, 2])
	H.rig(s, {1: [3, 4, 5], 2: [5, 6, 6]}, 1, {"pid": 2, "count": 2, "face": 4})
	assert_eq(_ok(s.timeout())[0], {"type": "bid", "pid": 1, "count": 2, "face": 5, "auto": true})
	H.rig(s, {1: [3, 4, 5], 2: [5, 6, 6]}, 1, {"pid": 2, "count": 2, "face": 6})
	assert_eq(_ok(s.timeout())[0], {"type": "bid", "pid": 1, "count": 3, "face": 2, "auto": true}, "点数到 6 就个数 +1、点数 2")


func test_timeout_challenges_when_no_raise_is_possible():
	var s := H.new_state([1, 2])
	H.rig(s, {1: [3, 4], 2: [5, 6]}, 1, {"pid": 2, "count": 4, "face": 6})
	var events := _ok(s.timeout())
	assert_eq(events[0], {"type": "challenged", "pid": 1, "target": 2, "count": 4, "face": 6, "auto": true})


func test_min_raise_and_bid_error_helpers():
	assert_eq(LiarsDiceState.min_raise({}, 10), {"count": 1, "face": 2})
	assert_eq(LiarsDiceState.min_raise({"count": 3, "face": 5}, 10), {"count": 3, "face": 6})
	assert_eq(LiarsDiceState.min_raise({"count": 3, "face": 6}, 10), {"count": 4, "face": 2})
	assert_eq(LiarsDiceState.min_raise({"count": 10, "face": 6}, 10), {})
	assert_eq(LiarsDiceState.min_raise({"count": 10, "face": 5}, 10), {"count": 10, "face": 6})
	var bid := {"pid": 1, "count": 3, "face": 4}
	assert_eq(LiarsDiceState.bid_error(3, 5, bid, 10), "")
	assert_eq(LiarsDiceState.bid_error(4, 2, bid, 10), "")
	assert_eq(LiarsDiceState.bid_error(3, 4, bid, 10), LiarsDiceState.ERR_BID_TOO_LOW)
	assert_eq(LiarsDiceState.bid_error(11, 4, bid, 10), LiarsDiceState.ERR_BID_TOO_HIGH)
	assert_eq(LiarsDiceState.bid_error(5, 1, bid, 10), LiarsDiceState.ERR_INVALID_FACE)
	assert_eq(LiarsDiceState.bid_error(0, 3, {}, 10), LiarsDiceState.ERR_INVALID_COUNT)
	assert_true(LiarsDiceState.ERROR_MESSAGES.has(LiarsDiceState.ERR_BID_TOO_LOW))


# —— 断线 ——

func test_disconnect_removes_the_dice_and_rerolls_the_round():
	var s := H.new_state([1, 2, 3])
	H.rig(s, {1: [1, 2, 3, 4, 5], 2: [2, 2], 3: [3, 3, 3]}, 3, {"pid": 2, "count": 4, "face": 3})
	var round_before := s.round_no
	var events := _ok(s.eliminate(1))
	assert_eq(H.types(events), ["player_left", "round_started"])
	assert_eq(events[0], {"type": "player_left", "pid": 1, "removed": 5})
	assert_eq(events[1]["starter"], 3, "当前玩家还在:由他开重摇的这一轮")
	assert_eq(events[1]["total"], 5)
	assert_eq(s.round_no, round_before + 1)
	assert_eq(s.bid, {}, "旧出价作废")
	assert_eq([s.dice_count(1), s.dice_count(2), s.dice_count(3)], [0, 2, 3])
	assert_eq(s.out_order, [1])


func test_disconnect_of_the_current_player_hands_the_new_round_to_the_next_seat():
	var s := H.new_state([1, 2, 3])
	H.rig(s, {1: [1, 2], 2: [2, 2], 3: [3, 3]}, 2, {"pid": 1, "count": 2, "face": 3})
	var events := _ok(s.eliminate(2))
	assert_eq(H.find(events, "round_started")["starter"], 3)
	assert_eq(s.current_pid, 3)


func test_disconnect_down_to_one_player_ends_the_match():
	var s := H.new_state([1, 2])
	H.rig(s, {1: [1, 2], 2: [2, 2]}, 1)
	var events := _ok(s.eliminate(1))
	assert_eq(events, [
		{"type": "player_left", "pid": 1, "removed": 2},
		{"type": "match_over", "winner": 2, "ranking": [2, 1]},
	])
	assert_eq(s.step, S.OVER)


func test_disconnect_of_spectators_or_strangers_is_a_no_op():
	var s := H.new_state([1, 2, 3])
	H.rig(s, {1: [1, 2], 2: [2, 2]}, 1)
	var before := _snapshot(s)
	assert_eq(_ok(s.eliminate(3)), [], "已出局的观战者")
	assert_eq(_ok(s.eliminate(42)), [], "不在局里")
	assert_eq(_snapshot(s), before)


# —— 隐藏信息 ——

func test_only_the_reveal_carries_dice():
	var s := H.new_state([1, 2, 3], 21)
	var all_events := []
	all_events.append_array(_ok(s.place_bid(s.current_pid, 2, 3)))
	all_events.append_array(_ok(s.timeout()))
	var challenge := _ok(s.challenge(s.current_pid))
	all_events.append_array(challenge)
	all_events.append_array(_ok(s.eliminate(s.alive_pids()[0])))
	for ev in all_events:
		assert_eq(H.event_leak(ev), "", str(ev))
		if ev["type"] != "revealed":
			assert_false(ev.has("dice"), "%s 不带点数" % ev["type"])
	assert_eq(all_events.filter(func(ev): return ev.has("dice")).size(), 1, "只有一次开盅带点数")
