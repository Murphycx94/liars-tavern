extends GutTest
# 斗地主会话(DouDizhuSession):不可信意图的结构校验、分派与 turn_action、公共 / 私有视图(手牌只给本人、
# 提示下标可直接出)、计时语义(叫分 / 出牌 / 托管)、连续多手(下一手、散局、结算补名字)、离开提前结算。


const D := preload("res://tests/ddz_helpers.gd")
const H := preload("res://src/core/dou_dizhu/ddz_hand.gd")
const NAMES := {1: "甲", 2: "乙", 3: "丙"}

var session: DouDizhuSession


func before_each():
	session = DouDizhuSession.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	session.start([1, 2, 3], NAMES, rng)


func _s() -> DdzState:
	return session.state()


func _to_landlord(pid: int) -> void:
	while _s().current_pid != pid:
		assert_true(session.handle_intent(_s().current_pid, {"kind": "bid", "score": 0})["ok"])
	assert_true(session.handle_intent(pid, {"kind": "bid", "score": 3})["ok"])


# —— 意图校验 ——

func test_untrusted_intent_structures_are_rejected():
	var cases := [
		[null, DdzState.ERR_INVALID_INTENT], ["bid", DdzState.ERR_INVALID_INTENT], [[{"kind": "pass"}], DdzState.ERR_INVALID_INTENT],
		[{}, DdzState.ERR_INVALID_INTENT], [{"kind": "nope"}, DdzState.ERR_INVALID_INTENT], [{"kind": 1}, DdzState.ERR_INVALID_INTENT],
		[{"kind": "pass", "x": 1}, DdzState.ERR_INVALID_INTENT], [{"kind": "bid", "score": 1, "x": 2}, DdzState.ERR_INVALID_INTENT],
		[{"kind": "bid"}, DdzState.ERR_INVALID_BID], [{"kind": "bid", "score": "3"}, DdzState.ERR_INVALID_BID],
		[{"kind": "bid", "score": 4}, DdzState.ERR_INVALID_BID], [{"kind": "bid", "score": -1}, DdzState.ERR_INVALID_BID],
		[{"kind": "bid", "score": 1.0}, DdzState.ERR_INVALID_BID],
		[{"kind": "play"}, DdzState.ERR_INVALID_PLAY], [{"kind": "play", "cards": []}, DdzState.ERR_INVALID_PLAY],
		[{"kind": "play", "cards": "0"}, DdzState.ERR_INVALID_PLAY], [{"kind": "play", "cards": [0, "1"]}, DdzState.ERR_INVALID_PLAY],
		[{"kind": "play", "cards": range(21)}, DdzState.ERR_INVALID_PLAY],
		[{"kind": "trustee"}, DdzState.ERR_INVALID_INTENT], [{"kind": "trustee", "on": 1}, DdzState.ERR_INVALID_INTENT],
	]
	for case in cases:
		assert_eq(DouDizhuSession.check_intent(case[0]), case[1], str(case[0]))
		assert_eq(session.validate_intent(case[0]), case[1], "NetworkManager 通用入口走 validate_intent")
	for ok in [{"kind": "bid", "score": 0}, {"kind": "bid", "score": 3}, {"kind": "play", "cards": [0, 1]}, {"kind": "pass"},
			{"kind": "trustee", "on": false}]:
		assert_eq(DouDizhuSession.check_intent(ok), "", str(ok))


func test_handle_intent_validates_then_dispatches():
	var first: int = _s().first_bidder
	var other := _s().next_pid(first)
	assert_eq(session.handle_intent(99, {"kind": "pass"})["error"], DdzState.ERR_NOT_SEATED)
	assert_eq(session.handle_intent(other, {"kind": "bid", "score": 1})["error"], DdzState.ERR_NOT_YOUR_TURN)
	assert_eq(session.handle_intent(first, {"kind": "play", "cards": [0]})["error"], DdzState.ERR_NOT_PLAYING)
	assert_eq(session.handle_intent(first, {"kind": "bid", "score": 7})["error"], DdzState.ERR_INVALID_BID)
	var r := session.handle_intent(first, {"kind": "bid", "score": 2})
	assert_true(r["ok"])
	assert_true(r["turn_action"], "叫分消耗回合")
	assert_eq(D.types(r["events"]), ["bid", "turn"])
	r = session.handle_intent(first, {"kind": "trustee", "on": true})
	assert_true(r["ok"])
	assert_false(r["turn_action"], "托管开关不算出手")
	assert_eq(D.types(r["events"]), ["trustee"])


func test_play_uses_private_view_indices():
	_to_landlord(2)
	var view := session.private_view(2)
	assert_eq(view["cards"].size(), 20)
	assert_eq(view["role"], "landlord")
	assert_true(view["my_turn"])
	assert_false(view["can_pass"], "自由出牌不能不出")
	var hint: Dictionary = view["hints"][0]
	var r := session.handle_intent(2, {"kind": "play", "cards": hint["indices"]})
	assert_true(r["ok"], "提示的下标直接能出")
	var played := D.find(r["events"], "played")
	assert_eq(played["cards"], hint["indices"].map(func(i: int) -> int: return view["cards"][i]), "出的就是提示那几张")
	assert_eq(session.private_view(2)["cards"].size(), 20 - played["cards"].size())
	assert_eq(session.handle_intent(3, {"kind": "play", "cards": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]})["error"],
		DdzState.ERR_INVALID_PLAY, "下标越界")
	assert_true(session.handle_intent(3, {"kind": "pass"})["ok"])


# —— 视图 ——

func test_private_view_shows_only_your_own_hand_and_options():
	var first: int = _s().first_bidder
	for pid in [1, 2, 3]:
		var view := session.private_view(pid)
		assert_eq(view.keys().filter(func(k: String) -> bool: return not D.PRIVATE_VIEW_KEYS.has(k)), [])
		assert_eq(view["cards"], _s().hand_of(pid))
		assert_eq(view["hand"], 1)
		assert_eq(view["role"], "")
		assert_eq(view["hints"], [], "叫分阶段没有出牌提示")
		assert_eq(view["bid_options"], [0, 1, 2, 3] if pid == first else [])
		assert_eq(view["my_turn"], pid == first)


func test_hints_are_capped_and_every_hint_is_playable():
	_to_landlord(1)
	var view := session.private_view(1)
	assert_gt(view["hints"].size(), 0)
	assert_lte(view["hints"].size(), DouDizhuViews.MAX_HINTS)
	for hint in view["hints"]:
		var cards: Array = hint["indices"].map(func(i: int) -> int: return view["cards"][i])
		assert_eq(H.classify(cards).is_empty(), false, str(hint))
	assert_eq(session.private_view(2)["hints"], [], "不轮到他")


func test_public_view_hides_hands_and_the_bottom_until_the_landlord_is_known():
	var view := session.public_view(12.0)
	assert_eq(D.view_leak(view, D.revealed_cards(_s())), "")
	assert_eq(view["mode"], GameMode.DOU_DIZHU)
	assert_eq([view["phase"], view["hand"], view["deal"], view["bottom"], view["landlord"]], ["bidding", 1, 1, [], null])
	assert_almost_eq(view["turn_time_left"], 12.0, 0.001)
	assert_eq(view["players"].map(func(row: Dictionary) -> Array: return [row["pid"], row["name"], row["hand_count"]]),
		[[1, "甲", 17], [2, "乙", 17], [3, "丙", 17]])
	_to_landlord(3)
	view = session.public_view(0.0)
	assert_eq(view["bottom"], _s().bottom, "定地主后底牌公开")
	assert_eq([view["landlord"], view["base"], view["multiplier"], view["phase"]], [3, 3, 1, "playing"])
	assert_eq(view["players"][2]["role"], "landlord")
	assert_eq(view["players"][0]["role"], "farmer")
	assert_eq(view["players"][2]["hand_count"], 20)
	assert_eq(D.view_leak(view, D.revealed_cards(_s())), "")


func test_public_view_tracks_lead_and_table():
	_s().seat_order = [1, 2, 3]
	D.rig_play(_s(), {1: D.cards("3 3 9"), 2: D.cards("5 K"), 3: D.cards("6 2")}, 1, 1)
	session.handle_intent(1, {"kind": "play", "cards": [0, 1]})
	session.handle_intent(2, {"kind": "pass"})
	var view := session.public_view(5.0)
	assert_eq(view["lead"], {"pid": 1, "cards": D.cards("3 3"), "type": H.PAIR, "rank": 0, "length": 1, "count": 2})
	assert_eq(view["players"][0]["table"], D.cards("3 3"))
	assert_true(view["players"][1]["passed"])
	assert_eq([view["passes"], view["current_pid"]], [1, 3])
	assert_true(session.private_view(3)["can_pass"])


# —— 计时 ——

func test_turn_timer_after_by_stage_and_trustee():
	var first: int = _s().first_bidder
	assert_true(session.has_turn())
	var turn := [{"type": "turn", "pid": first, "stage": "bid", "free": false}]
	assert_almost_eq(session.turn_timer_after(turn, 2.0, 5.0), 2.0 + DouDizhuSession.BID_TIMEOUT, 0.001, "叫分 15 秒")
	assert_almost_eq(session.turn_timer_after([], 0.0, 5.0), 5.0, 0.001, "没换人:保留剩余")
	assert_almost_eq(session.turn_timer_after([], 1.0, 0.0), 1.0 + DouDizhuSession.BID_TIMEOUT, 0.001, "计时器没在走:给满")
	_to_landlord(first)
	assert_almost_eq(session.turn_timer_after(turn, 1.0, 5.0), 1.0 + Protocol.TURN_TIMEOUT, 0.001, "出牌 30 秒")
	session.handle_intent(first, {"kind": "trustee", "on": true})
	assert_almost_eq(session.turn_timer_after([], 3.0, 20.0), 3.0 + DouDizhuPacing.TRUSTEE_DELAY, 0.001, "托管:很快代打")
	var off: Array = session.handle_intent(first, {"kind": "trustee", "on": false})["events"]
	assert_almost_eq(session.turn_timer_after(off, 0.0, 0.5), Protocol.TURN_TIMEOUT, 0.001, "取消托管:给满一个回合")
	var other_off := [{"type": "trustee", "pid": _s().next_pid(first), "on": false, "auto": false}]
	assert_almost_eq(session.turn_timer_after(other_off, 0.0, 7.0), 7.0, 0.001, "旁人开关托管不动计时")


func test_pacing_budgets():
	assert_almost_eq(DouDizhuPacing.estimate([{"type": "played", "combo": H.ROCKET}]), DouDizhuPacing.PLAYED_ROCKET, 0.001)
	assert_almost_eq(DouDizhuPacing.estimate([{"type": "played", "combo": H.AIRPLANE_PAIR}]), DouDizhuPacing.PLAYED_AIRPLANE, 0.001)
	assert_almost_eq(DouDizhuPacing.estimate([{"type": "played", "combo": H.PAIR_STRAIGHT}]), DouDizhuPacing.PLAYED_CHAIN, 0.001)
	assert_almost_eq(DouDizhuPacing.estimate([{"type": "hand_over", "spring": true}]),
		DouDizhuPacing.HAND_OVER + DouDizhuPacing.HAND_OVER_SPRING, 0.001)
	for type in D.EVENT_KEYS:
		assert_gte(DouDizhuPacing.estimate([{"type": type}]), 0.0, type)
	assert_true(DouDizhuPacing.starts_turn([{"type": "turn"}]))
	assert_false(DouDizhuPacing.starts_turn([{"type": "bid"}]))


func test_timeout_through_the_session_is_a_turn_action():
	var r := session.on_turn_timeout()
	assert_true(r["ok"])
	assert_true(r["turn_action"])
	assert_eq(r["events"][0]["type"], "bid")


# —— 连续多手、散局、离开 ——

func test_hands_chain_like_poker_until_the_host_ends_it():
	_s().seat_order = [1, 2, 3]
	D.rig_play(_s(), {1: D.cards("3"), 2: D.cards("4"), 3: D.cards("5")}, 1, 1)
	assert_false(session.next_hand_ready())
	var r := session.handle_intent(1, {"kind": "play", "cards": [0]})
	assert_eq(D.types(r["events"]), ["played", "hand_over"])
	assert_false(session.has_turn(), "两手之间没人计时")
	assert_true(session.next_hand_ready())
	assert_almost_eq(session.hand_gap(), DouDizhuPacing.HAND_GAP, 0.001)
	assert_false(session.accepts_late_join())
	var events := session.start_next_hand()
	assert_eq(D.types(events), ["hand_started", "turn"])
	assert_eq(events[0]["hand"], 2)
	assert_true(session.has_turn())
	assert_eq(D.types(session.request_end()), ["ending"])
	assert_true(session.is_ending())
	assert_false(session.is_over())
	# 散局后这一手照常打完:一路超时代打
	var guard := 0
	var last := []
	while not session.is_over() and guard < 500:
		guard += 1
		last = session.on_turn_timeout()["events"]
	assert_true(session.is_over())
	var so := D.find(last, "session_over")
	assert_eq(so["reason"], "host")
	assert_eq(so["results"].map(func(row: Dictionary) -> String: return row["name"]).size(), 3)
	for row in so["results"]:
		assert_eq(row["name"], NAMES[row["pid"]], "结算补名字")
	assert_false(session.next_hand_ready())
	assert_eq(session.public_view(0.0)["results"].size(), 3)
	assert_eq(session.public_view(0.0)["phase"], "over")


func test_request_end_between_hands_settles_immediately():
	_s().seat_order = [1, 2, 3]
	D.rig_play(_s(), {1: D.cards("3"), 2: D.cards("4"), 3: D.cards("5")}, 1, 1)
	session.handle_intent(1, {"kind": "play", "cards": [0]})
	var events := session.request_end()
	assert_eq(D.types(events), ["session_over"])
	assert_eq(events[0]["results"][0]["name"], "甲")
	assert_true(session.is_over())
	assert_eq(session.request_end(), [])


func test_disconnect_ends_the_session_early():
	assert_eq(session.viewers(), [1, 2, 3])
	assert_eq(session.on_disconnect(99), [], "不在会话里")
	var events := session.on_disconnect(2)
	assert_eq(D.types(events), ["player_left", "session_over"])
	assert_eq(events[1]["reason"], "player_left")
	assert_eq(events[1]["results"].filter(func(r: Dictionary) -> bool: return r["left"])[0]["name"], "乙")
	assert_true(session.is_over())
	assert_eq(session.viewers(), [1, 3], "离开的人不再收私有视图")
	assert_eq(session.on_disconnect(3), [])
	assert_eq(session.handle_intent(1, {"kind": "pass"})["error"], DdzState.ERR_SESSION_OVER)
	assert_eq(session.on_turn_timeout()["ok"], false)
	assert_eq(session.seats_with_patrons(), [1, 2, 3])
	assert_eq(session.name_of(2), "乙")
