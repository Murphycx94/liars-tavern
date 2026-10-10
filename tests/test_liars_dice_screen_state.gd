extends GutTest
# 吹牛骰子牌桌的本地状态(LiarsDiceScreenState):事件推进影子行、视图兜底对齐、自己的骰子按轮次缓存
# (私有视图比「开!」那一批的演出先到,演到 round_started 才换)、开盅之前没有任何别人的点数、结算名次、坏数据不报错。


const H := preload("res://tests/liars_dice_helpers.gd")

var session: LiarsDiceSession
var st: LiarsDiceScreenState


func _open(pids: Array, seed_value := 3) -> Array:
	session = LiarsDiceSession.new()
	var names := {}
	for pid in pids:
		names[pid] = "P%d" % pid
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var events := session.start(pids, names, rng)
	st = LiarsDiceScreenState.new()
	st.my_pid = pids[0]
	st.set_seats(pids.map(func(pid): return {"pid": pid, "name": names[pid]}))
	return events


func _feed(events: Array) -> void:
	# 同牌桌:事件先排队(这里直接推进影子行),再到公共、私有视图
	for ev in events:
		st.apply_event(ev)
	st.apply_public(session.public_view(10.0))
	st.apply_private(session.private_view(st.my_pid))


func test_round_started_sets_counts_total_and_starter():
	var events := _open([1, 2, 3])
	st.apply_event(events[0])
	assert_eq(st.round_no, 1)
	assert_eq(st.total, 15)
	assert_eq(st.counts, {1: 5, 2: 5, 3: 5})
	assert_eq(st.current_pid, events[0]["starter"])
	assert_eq(st.step, LiarsDiceScreenState.STEP_BID)
	assert_true(st.bid.is_empty())


func test_seats_start_with_five_dice_before_the_first_round_is_played():
	# 开局运镜期间(round_started 还没演到):铭牌与左上按每人 5 颗,不显示 0 颗
	_open([1, 2, 3])
	assert_eq(st.counts, {1: 5, 2: 5, 3: 5})
	assert_eq(st.total, 15)
	assert_false(st.started)


func test_bids_and_turns_follow_the_events():
	var events := _open([1, 2, 3])
	_feed(events)
	var cur: int = session.state().current_pid
	var result := session.handle_intent(cur, {"kind": "bid", "count": 2, "face": 4})
	_feed(result["events"])
	assert_eq(st.bid, {"pid": cur, "count": 2, "face": 4})
	assert_eq(st.bids.size(), 1)
	assert_eq(st.current_pid, session.state().current_pid)


func test_private_dice_are_buffered_until_the_round_started_is_played():
	# 「开!」那一批里已经重摇了下一轮:私有视图(第 2 轮的点数)先到,屏幕上还是第 1 轮的,演到 round_started 才换
	var events := _open([1, 2, 3])
	_feed(events)
	st.take_round_dice(1)
	var round1 := st.shown_dice.duplicate()
	assert_eq(round1, session.state().dice_of(1), "第 1 轮的点数")
	var cur: int = session.state().current_pid
	_feed(session.handle_intent(cur, {"kind": "bid", "count": 1, "face": 2})["events"])
	var challenger: int = session.state().current_pid
	var batch: Array = session.handle_intent(challenger, {"kind": "challenge"})["events"]
	# 视图先到(牌桌排队演出期间私有视图照样送达)
	st.apply_public(session.public_view(10.0))
	st.apply_private(session.private_view(1))
	assert_true(st.has_round_dice(2), "第 2 轮的点数记下来了")
	assert_eq(st.shown_dice, round1, "还没演到第 2 轮的 round_started:屏幕上不换")
	for ev in batch:
		st.apply_event(ev)
		if ev["type"] == "revealed":
			assert_eq(st.revealed_dice_of(1), round1, "开盅用 revealed 事件里的点数(第 1 轮)")
		if ev["type"] == "round_started":
			st.take_round_dice(ev["round"])
	if session.state().is_alive(1):
		assert_eq(st.shown_dice, session.state().dice_of(1), "演到 round_started 才换成第 2 轮")
		assert_eq(st.shown_round, 2)


func test_old_rounds_are_pruned_and_missing_rounds_are_empty():
	_open([1, 2])
	for r in range(1, 8):
		st.apply_private({"dice": [r % 6 + 1], "alive": true, "round": r})
	assert_false(st.has_round_dice(1), "很早的轮次丢掉")
	assert_true(st.has_round_dice(7))
	assert_eq(st.round_dice(42), [])
	assert_eq(st.take_round_dice(42), [], "还没到的轮次先清空")


func test_no_other_players_dice_before_a_reveal():
	# 公共视图与事件里没有别人的点数:本地状态在开盅之前也拿不到
	var events := _open([1, 2, 3, 4])
	_feed(events)
	for pid in [2, 3, 4]:
		assert_eq(st.revealed_dice_of(pid), [], "开盅前没有 P%d 的点数" % pid)
	assert_eq(H.view_leak(st.pub, session.state()), "", "公共视图不漏点数")
	assert_true(st.last_reveal.is_empty())


func test_sync_from_view_aligns_the_shadow_rows():
	var events := _open([1, 2, 3])
	st.apply_public(session.public_view(10.0))
	st.apply_private(session.private_view(1))
	st.sync_from_view()
	assert_eq(st.round_no, 1)
	assert_eq(st.total, 15)
	assert_eq(st.current_pid, events[0]["starter"])
	assert_eq(st.shown_dice, session.state().dice_of(1), "对账时按视图的轮次取缓存")
	assert_true(st.am_alive())


func test_bid_error_and_default_bid_use_the_view():
	_open([1, 2, 3])
	st.apply_public(session.public_view(10.0))
	assert_eq(st.default_bid(), {"count": 1, "face": 2}, "本轮第一口默认「1 个 2」")
	st.pub["bid"] = {"pid": 2, "count": 3, "face": 6}
	assert_eq(st.default_bid(), {"count": 4, "face": 2})
	assert_eq(st.bid_error(3, 6), LiarsDiceState.ERR_BID_TOO_LOW)
	assert_eq(st.bid_error(4, 1), LiarsDiceState.ERR_INVALID_FACE)
	assert_eq(st.bid_error(16, 2), LiarsDiceState.ERR_BID_TOO_HIGH)
	assert_eq(st.bid_error(4, 3), "")
	st.pub["bid"] = {"pid": 2, "count": 15, "face": 6}
	assert_eq(st.default_bid(), {"count": 15, "face": 6}, "加不上去了:停在当前这一口(只能开)")


func test_die_lost_out_and_left_update_counts():
	_open([1, 2, 3])
	st.apply_event({"type": "round_started", "round": 1, "starter": 1, "seats": [1, 2, 3],
		"counts": [{"pid": 1, "count": 1}, {"pid": 2, "count": 3}, {"pid": 3, "count": 2}], "total": 6})
	st.apply_event({"type": "die_lost", "pid": 1, "left": 0})
	st.apply_event({"type": "player_out", "pid": 1})
	assert_false(st.is_alive(1))
	assert_eq(st.total, 5)
	assert_false(st.am_alive())
	st.apply_event({"type": "player_left", "pid": 3, "removed": 2})
	assert_eq(st.total, 3)
	assert_true(st.left.has(3))
	assert_eq(st.out_order, [1, 3])


func test_ranking_rows_mark_winner_out_and_left():
	_open([1, 2, 3])
	st.counts = {1: 0, 2: 3, 3: 0}
	st.left = {3: true}
	st.out_order = [1, 3]
	st.winner = 2
	var rows := st.ranking_rows()
	assert_eq(rows.map(func(r): return r["pid"]), [2, 3, 1], "胜者 + 出局顺序倒排")
	assert_eq(rows.map(func(r): return r["fate"]), ["winner", "left", "out"])
	assert_eq(rows[0]["dice"], 3)
	st.pub = {"ranking": [{"pid": 2, "name": "阿狸", "place": 1}, {"pid": 1, "name": "我", "place": 2}]}
	assert_eq(st.ranking_rows()[0]["name"], "阿狸", "优先用视图的 ranking")


func test_count_order_and_matches_count_wild_ones():
	var rows := [{"pid": 1, "dice": [1, 2, 5]}, {"pid": 2, "dice": [5, 6]}, {"pid": 3, "dice": [1, 1]}]
	assert_eq(LiarsDiceScreenState.count_order(rows, 5), [[1, 0], [1, 2], [2, 0], [3, 0], [3, 1]])
	assert_eq(LiarsDiceScreenState.count_matches([1, 1, 5, 6], 6), 3)
	assert_eq(LiarsDiceScreenState.bid_text(3, 5), "3 个 5")
	assert_string_contains(LiarsDiceScreenState.verdict_text({"actual": 7, "face": 5, "count": 5}), "实际 7 个 5")


func test_bad_network_data_is_ignored():
	_open([1, 2])
	st.apply_event({"type": "round_started", "round": "x", "counts": "nope", "seats": 5})
	st.apply_event({"type": "bid", "count": "3", "face": 4})
	assert_true(st.bid.is_empty(), "类型不对的出价不认")
	st.apply_private({"dice": [0, 7, "3", 2.5, 4], "round": 1, "alive": true})
	assert_eq(st.round_dice(1), [4], "只留 1..6 的整数")
	st.apply_public({"players": "x", "ranking": 3})
	st.sync_from_view()
	assert_eq(st.ranking_rows(), [])
