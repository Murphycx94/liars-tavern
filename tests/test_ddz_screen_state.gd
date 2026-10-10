extends GutTest
# DdzScreenState:影子行按事件推进(发牌、叫分、定地主、出牌、不出、清桌、托管、一手结束、散局)、视图兜底对齐、
# 私有视图按「第几手 : 第几次发牌」记快照、提示与叫分选项的校验、选中的牌成不成牌型 / 压不压得过、结算排名与摘要。
# 用一个真的 DouDizhuSession 产生事件与视图(不走网络)。


const H := preload("res://tests/ddz_helpers.gd")
const ME := 1
const PIDS := [1, 2, 3]

var session: DouDizhuSession
var st: DdzScreenState


func before_each():
	session = DouDizhuSession.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var events := session.start(PIDS, {1: "我", 2: "阿狸", 3: "小熊"}, rng)
	st = DdzScreenState.new()
	st.my_pid = ME
	st.set_seats(PIDS.map(func(pid): return {"pid": pid, "name": "P%d" % pid}))
	_feed(events)


func _feed(events: Array) -> void:
	# 同房主的顺序:事件(演出逐个推进影子行),然后公共视图、私有视图
	for ev in events:
		st.apply_event(ev)
	st.apply_public(session.public_view(10.0))
	st.apply_private(session.private_view(ME))


func _act(pid: int, intent: Dictionary) -> Array:
	var r := session.handle_intent(pid, intent)
	assert_true(r["ok"], "意图被拒:%s %s" % [intent, r.get("error")])
	_feed(r["events"])
	return r["events"]


func _bid_until_landlord() -> void:
	var s := session.state()
	var guard := 0
	while s.phase == DdzState.Phase.BIDDING and guard < 20:
		guard += 1
		var pid: int = s.current_pid
		var options: Array = session.private_view(pid)["bid_options"]
		_act(pid, {"kind": "bid", "score": options.max()})


func test_hand_started_resets_the_shadow_rows():
	assert_eq(st.hand, 1)
	assert_eq(st.phase, DdzScreenState.PHASE_BIDDING)
	for pid in PIDS:
		assert_eq(st.counts[pid], DdzState.HAND_SIZE)
	assert_true(st.bottom_hidden, "底牌扣在桌心")
	assert_eq(st.current_pid, session.state().first_bidder, "turn 事件推进到第一个叫分的人")
	assert_eq(st.stage, DdzState.STAGE_BID)
	assert_eq(st.cards_for_deal(1, 1), session.private_view(ME)["cards"], "第 1 手第 1 次发牌的快照")
	assert_null(st.cards_for_deal(1, 2), "还没重发")


func test_bids_landlord_and_roles():
	var first: int = session.state().first_bidder
	_act(first, {"kind": "bid", "score": 1})
	assert_eq(st.bids[first], 1)
	assert_eq(st.plate_row(first)["bid"], 1, "叫分阶段铭牌写叫了几分")
	_bid_until_landlord()
	var landlord: int = session.state().landlord
	assert_eq(st.landlord, landlord)
	assert_eq(st.phase, DdzScreenState.PHASE_PLAYING)
	assert_false(st.bottom_hidden)
	assert_eq(st.bottom.size(), DdzState.BOTTOM_SIZE)
	assert_eq(st.counts[landlord], DdzState.HAND_SIZE + DdzState.BOTTOM_SIZE, "底牌进地主手里")
	for pid in PIDS:
		assert_eq(st.roles[pid], DdzState.ROLE_LANDLORD if pid == landlord else DdzState.ROLE_FARMER)
		assert_eq(st.plate_row(pid)["bid"], -1, "出牌阶段铭牌不再写叫分")
	assert_eq(st.base, session.state().base)


func test_played_passed_and_trick_cleared():
	_bid_until_landlord()
	var s := session.state()
	var lead_pid: int = s.current_pid
	var hint: Dictionary = session.private_view(lead_pid)["hints"][0]
	var events := _act(lead_pid, {"kind": "play", "cards": hint["indices"]})
	var played: Dictionary = events[0]
	assert_eq(st.rows[lead_pid], played["cards"])
	assert_eq(st.counts[lead_pid], played["remaining"])
	assert_eq(st.lead["type"], played["combo"])
	var second: int = s.current_pid
	_act(second, {"kind": "pass"})
	assert_true(st.passed.has(second))
	assert_false(st.rows.has(second))
	var third: int = s.current_pid
	_act(third, {"kind": "pass"})
	assert_eq(st.rows, {}, "两家不出:桌面清掉")
	assert_eq(st.passed, {})
	assert_eq(st.lead, {})
	assert_true(st.free, "接着自由出牌")
	assert_eq(st.current_pid, lead_pid)


func test_sync_from_view_matches_the_session():
	_bid_until_landlord()
	st.sync_from_view()
	var pub: Dictionary = session.public_view(0.0)
	for row in pub["players"]:
		assert_eq(st.counts[row["pid"]], row["hand_count"])
		assert_eq(st.roles[row["pid"]], row["role"])
	assert_eq(st.shown_hand, session.private_view(ME)["cards"])
	assert_eq(st.multiplier, pub["multiplier"])


func test_hints_and_bid_options_are_validated():
	st.priv = {"hand": 1, "cards": [0, 4, 8], "hints": [{"indices": [0], "type": "single"}, {"indices": [9]}, "x", {"indices": [2, 1]}],
		"bid_options": [0, 2, 3, 7, "x"], "can_pass": true}
	st.pub = {"phase": "playing"}
	assert_eq(st.hints(), [[0], [1, 2]], "越界与坏条目丢掉,下标排好序")
	st.pub = {"phase": "bidding"}
	assert_eq(st.bid_options(), [0, 2, 3], "叫分选项只留 0–3")
	assert_eq(st.hints(), [], "叫分阶段没有提示")


func test_selection_check_follows_the_lead():
	st.priv = {"hand": 1, "cards": H.cards("3 4 5 6 7 9 9 K K K K")}
	st.pub = {"phase": "playing", "lead": {}}
	var ok := st.selection_check([0, 1, 2, 3, 4])
	assert_true(ok["ok"])
	assert_eq(ok["combo"]["type"], DdzHand.STRAIGHT)
	assert_eq(ok["text"], "顺子 · 5 张")
	assert_false(st.selection_check([0, 5])["ok"], "3 和 9 不成牌型")
	assert_eq(st.selection_check([0, 5])["text"], "不成牌型")
	st.pub = {"phase": "playing", "lead": {"pid": 2, "type": DdzHand.PAIR, "rank": 8, "length": 1, "count": 2}}
	assert_false(st.selection_check([5, 6])["ok"], "一对 9 压不过一对 J")
	assert_string_contains(st.selection_check([5, 6])["text"], "压不过")
	assert_true(st.selection_check([7, 8, 9, 10])["ok"], "炸弹压一切")
	assert_eq(st.selection_check([])["text"], "")


func test_ranking_and_scores():
	var rows := DdzScreenState.ranking([{"pid": 2, "name": "乙", "score": -4, "place": 2}, {"pid": 1, "name": "甲", "score": 8, "place": 1},
		{"pid": 3, "name": "丙", "score": -4, "place": 2, "left": true}, "坏条目", {"pid": 4}])
	assert_eq(rows.map(func(r): return r["pid"]), [1, 2, 3, 4], "按名次,同名次保持原顺序,缺名次的排最后")
	assert_true(rows[2]["left"])
	assert_eq(DdzScreenState.top_ranked(rows), [1])
	assert_eq(DdzScreenState.score_sum(rows), 0)


func test_hand_over_summary_and_session_over():
	var ev := {"type": "hand_over", "hand": 1, "winner": 2, "landlord": 2, "landlord_won": true, "base": 2, "multiplier": 4, "bombs": 1,
		"spring": false, "deltas": [{"pid": 1, "delta": -8}, {"pid": 2, "delta": 16}, {"pid": 3, "delta": -8}],
		"scores": [{"pid": 1, "score": -8}, {"pid": 2, "score": 16}, {"pid": 3, "score": -8}], "remaining": []}
	st.apply_event(ev)
	assert_eq(st.phase, DdzScreenState.PHASE_BETWEEN)
	assert_eq(st.scores[2], 16)
	var rows := st.summary_rows()
	assert_eq(rows.size(), 3)
	assert_eq(rows[1]["role"], DdzState.ROLE_LANDLORD)
	assert_eq(rows[1]["delta"], 16)
	assert_eq(DdzHud.summary_title(st.last_hand, DdzState.ROLE_FARMER), "你输了…(地主胜)")
	assert_eq(DdzHud.formula_text(st.last_hand), "底分 2 × 倍数 4 = 8 · 炸弹 1 个")
	st.apply_event({"type": "session_over", "reason": "host", "results": [{"pid": 2, "name": "乙", "score": 16, "place": 1}]})
	assert_eq(st.phase, DdzScreenState.PHASE_OVER)
	assert_eq(st.end_reason, "host")


func test_shouts_and_texts():
	assert_eq(DdzScreenState.shout_for(DdzHand.SINGLE, H.cards("K")), "K")
	assert_eq(DdzScreenState.shout_for(DdzHand.PAIR, H.cards("8 8")), "对 8")
	assert_eq(DdzScreenState.shout_for(DdzHand.ROCKET, H.cards("SJ BJ")), "王炸!")
	assert_eq(DdzScreenState.shout_for(DdzHand.STRAIGHT, H.cards("3 4 5 6 7")), "顺子!")
	assert_eq(DdzScreenState.bid_text(0), "不叫")
	assert_eq(DdzScreenState.bid_text(3), "3 分")
	assert_eq(DdzNameplate.info_text({"score": 12, "count": 2, "bid": -1}), "累计 +12 · 剩 2 张")
	assert_eq(DdzNameplate.info_text({"score": -3, "count": 17, "bid": 0}), "累计 -3 · 剩 17 张 · 不叫")
	assert_true(DdzNameplate.is_alarm({"count": 1, "role": "farmer"}))
	assert_false(DdzNameplate.is_alarm({"count": 2, "role": ""}), "定地主之前不报警")
	assert_false(DdzNameplate.is_alarm({"count": 3, "role": "farmer"}))


func test_settlement_panel_rows_and_subtitle():
	var results := [{"pid": 3, "name": "丙", "score": -6, "place": 2}, {"pid": 1, "name": "甲", "score": 12, "place": 1},
		{"pid": 2, "name": "乙", "score": -6, "place": 2, "left": true}]
	var panel := DdzSettlement.new(results, false, DdzState.REASON_PLAYER_LEFT, 4, 1)
	add_child_autofree(panel)
	assert_eq(panel.rows().map(func(r): return r["pid"]), [1, 3, 2], "按名次,同分同名次")
	assert_eq(panel.primary_button().text, DdzSettlement.GUEST_TEXT)
	assert_string_contains(DdzSettlement.subtitle(DdzState.REASON_PLAYER_LEFT, 4), "有人离开")
	assert_string_contains(DdzSettlement.subtitle(DdzState.REASON_HOST, 6), "一共打了 6 手")
	var host := DdzSettlement.new(results, true)
	add_child_autofree(host)
	assert_eq(host.primary_button().text, DdzSettlement.HOST_TEXT)
