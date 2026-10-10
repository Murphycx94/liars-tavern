extends GutTest
# 斗地主规则引擎(DdzState):发牌、叫分(含重发与连续不叫)、出牌与一圈结束、倍数、春天、计分总和为 0、
# 累计分、超时代打与托管、散局、离开提前结算、公共事件不漏手牌。


const D := preload("res://tests/ddz_helpers.gd")
const H := preload("res://src/core/dou_dizhu/ddz_hand.gd")
const P := DdzState.Phase


func _c(text: String) -> Array:
	return D.cards(text)


func _idx(s: DdzState, pid: int, text: String) -> Array:
	# 按点数写要出的牌 → 手牌下标(同点数取手里靠前的)
	var hand := s.hand_of(pid)
	var out := []
	var counts := {}
	for tok in text.split(" ", false):
		var r: int = H.RANK_SMALL_JOKER if tok == "SJ" else (H.RANK_BIG_JOKER if tok == "BJ" else D.TOKENS[tok])
		var skip: int = counts.get(r, 0)
		counts[r] = skip + 1
		var seen := 0
		for i in hand.size():
			if H.rank(hand[i]) == r:
				if seen == skip:
					out.append(i)
					break
				seen += 1
	return out


func _bid_to_landlord(s: DdzState, landlord: int) -> void:
	# 让 landlord 叫 3 分(轮到前面的人都不叫)
	while s.current_pid != landlord:
		s.bid(s.current_pid, 0)
	s.bid(landlord, 3)


# —— 开局与发牌 ——

func test_start_needs_exactly_three_distinct_players():
	for pids in [[1, 2], [1, 2, 3, 4], [1, 1, 2], [1, "2", 3]]:
		var s := DdzState.new()
		var r := s.start(pids, RandomNumberGenerator.new())
		assert_eq([r["ok"], r.get("error")], [false, DdzState.ERR_INVALID_PLAYERS], str(pids))


func test_deal_gives_seventeen_each_and_three_bottom():
	var s := D.new_state()
	assert_eq(s.phase, P.BIDDING)
	var all := {}
	for pid in s.seat_order:
		assert_eq(s.hands[pid].size(), 17)
		assert_eq(s.hands[pid], H.sorted(s.hands[pid]), "手牌升序")
		for c in s.hands[pid]:
			all[c] = true
	for c in s.bottom:
		all[c] = true
	assert_eq(s.bottom.size(), 3)
	assert_eq(all.size(), 54, "54 张都在、不重复")
	assert_eq(s.card_count(), 54)
	var again := D.new_state()
	assert_eq(again.hands, s.hands, "同种子同牌")
	assert_eq(again.first_bidder, s.first_bidder)
	var other := D.new_state(8)
	assert_ne(other.hands, s.hands)


func test_start_events_carry_counts_not_cards():
	var s := DdzState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var events: Array = s.start([5, 6, 7], rng)["events"]
	assert_eq(D.types(events), ["hand_started", "turn"])
	var ev: Dictionary = events[0]
	assert_eq([ev["hand"], ev["deal"], ev["seats"], ev["bottom_count"]], [1, 1, [5, 6, 7], 3])
	assert_eq(ev["hands"], [{"pid": 5, "count": 17}, {"pid": 6, "count": 17}, {"pid": 7, "count": 17}])
	assert_eq(ev["scores"], [{"pid": 5, "score": 0}, {"pid": 6, "score": 0}, {"pid": 7, "score": 0}])
	assert_eq(events[1], {"type": "turn", "pid": s.first_bidder, "stage": "bid", "free": false})
	for e in events:
		assert_eq(D.event_leak(e, {}), "")


func test_first_bidder_is_random_across_seeds():
	var seen := {}
	for seed_value in 30:
		seen[D.new_state(seed_value).first_bidder] = true
	assert_eq(seen.size(), 3)


# —— 叫分 ——

func test_bid_three_ends_bidding_and_landlord_takes_the_bottom():
	var s := D.new_state()
	var first: int = s.first_bidder
	var bottom := s.bottom.duplicate()
	var r := s.bid(first, 3)
	assert_true(r["ok"])
	assert_eq(D.types(r["events"]), ["bid", "landlord", "turn"])
	var ll := D.find(r["events"], "landlord")
	assert_eq([ll["pid"], ll["base"], ll["bottom"], ll["forced"]], [first, 3, bottom, false])
	assert_eq(s.hands[first].size(), 20)
	for c in bottom:
		assert_true(s.hands[first].has(c), "底牌进了地主手里")
	assert_eq(s.hands[first], H.sorted(s.hands[first]))
	assert_eq([s.phase, s.landlord, s.base, s.current_pid], [P.PLAYING, first, 3, first])
	assert_eq(r["events"][-1], {"type": "turn", "pid": first, "stage": "play", "free": true}, "地主先自由出牌")
	assert_eq(s.card_count(), 54)
	assert_eq(s.role_of(first), "landlord")
	assert_eq(s.role_of(s.next_pid(first)), "farmer")


func test_bids_must_go_up_and_the_highest_wins_after_one_round():
	var s := D.new_state()
	var a: int = s.first_bidder
	var b := s.next_pid(a)
	var c := s.next_pid(b)
	assert_eq(s.bid_options(a), [0, 1, 2, 3])
	assert_eq(s.bid_options(b), [], "不轮到他")
	assert_eq(s.bid(b, 1)["error"], DdzState.ERR_NOT_YOUR_TURN)
	assert_true(s.bid(a, 1)["ok"])
	assert_eq(s.bid_options(b), [0, 2, 3])
	for bad in [1, 4, -1, "2", 2.0, null]:
		assert_eq(s.bid(b, bad)["error"], DdzState.ERR_INVALID_BID, str(bad))
	assert_true(s.bid(b, 2)["ok"])
	var r := s.bid(c, 0)
	assert_eq(D.types(r["events"]), ["bid", "landlord", "turn"])
	assert_eq([s.landlord, s.base], [b, 2], "一圈后最高分的当地主")
	assert_eq(s.bid(c, 3)["error"], DdzState.ERR_NOT_BIDDING)
	assert_eq(s.play(c, [0])["error"], DdzState.ERR_NOT_YOUR_TURN)


func test_play_and_pass_are_refused_while_bidding():
	var s := D.new_state()
	assert_eq(s.play(s.first_bidder, [0])["error"], DdzState.ERR_NOT_PLAYING)
	assert_eq(s.pass_turn(s.first_bidder)["error"], DdzState.ERR_NOT_PLAYING)
	assert_eq(s.bid(99, 1)["error"], DdzState.ERR_NOT_SEATED)


func test_all_pass_redeals_and_three_all_pass_deals_force_the_first_bidder():
	var s := D.new_state()
	var first: int = s.first_bidder
	for deal in [1, 2]:
		var before := s.hands.duplicate(true)
		s.bid(s.current_pid, 0)
		s.bid(s.current_pid, 0)
		var r := s.bid(s.current_pid, 0)
		assert_eq(D.types(r["events"]), ["bid", "redeal", "turn"], "第 %d 次都不叫" % deal)
		var rd := D.find(r["events"], "redeal")
		assert_eq([rd["hand"], rd["deal"], rd["first_bidder"]], [1, deal + 1, first], "第一个叫分的人不变")
		assert_eq(s.deal_number, deal + 1)
		assert_ne(s.hands, before, "重新洗牌")
		assert_eq([s.phase, s.current_pid, s.bids, s.landlord], [P.BIDDING, first, [], null])
		assert_eq(s.card_count(), 54)
		assert_eq(D.event_leak(rd, {}), "")
	s.bid(s.current_pid, 0)
	s.bid(s.current_pid, 0)
	var r := s.bid(s.current_pid, 0)
	assert_eq(D.types(r["events"]), ["bid", "landlord", "turn"])
	var ll := D.find(r["events"], "landlord")
	assert_eq([ll["pid"], ll["base"], ll["forced"]], [first, 1, true], "连续 3 次不叫:第一个人当 1 分地主")
	assert_eq(s.hands[first].size(), 20)
	assert_eq(s.hand_number, 1, "还是同一手")


func test_a_late_bid_after_passes_still_wins():
	var s := D.new_state()
	s.bid(s.current_pid, 0)
	s.bid(s.current_pid, 0)
	var last: int = s.current_pid
	s.bid(last, 1)
	assert_eq([s.landlord, s.base], [last, 1])


# —— 出牌 ——

func test_following_needs_a_bigger_combo_and_two_passes_clear_the_trick():
	var s := D.new_state()
	s.seat_order = [1, 2, 3]
	D.rig_play(s, {1: _c("3 3 9 K"), 2: _c("4 4 5 5 A"), 3: _c("6 6 7 2")}, 1, 1)
	assert_eq(s.pass_turn(1)["error"], DdzState.ERR_CANNOT_PASS, "自由出牌不能不出")
	assert_eq(s.play(1, _idx(s, 1, "3 9"))["error"], DdzState.ERR_INVALID_COMBO)
	for bad in [[], [0, 0], [9], [-1], ["0"], "0", null, [0, 1, 2, 3, 4]]:
		assert_eq(s.play(1, bad)["error"], DdzState.ERR_INVALID_PLAY, str(bad))
	var r := s.play(1, _idx(s, 1, "3 3"))
	assert_eq(D.types(r["events"]), ["played", "turn"])
	var pl := D.find(r["events"], "played")
	assert_eq([pl["pid"], pl["cards"], pl["combo"], pl["rank"], pl["remaining"], pl["multiplier"]],
		[1, _c("3 3"), H.PAIR, 0, 2, 1])
	assert_eq(r["events"][-1], {"type": "turn", "pid": 2, "stage": "play", "free": false})
	assert_eq(s.play(2, _idx(s, 2, "A"))["error"], DdzState.ERR_CANNOT_BEAT, "单张压不了对子")
	assert_true(s.play(2, _idx(s, 2, "5 5"))["ok"])
	assert_eq(s.play(3, _idx(s, 3, "6 6"))["ok"], true)
	assert_eq(s.lead["pid"], 3)
	assert_true(s.pass_turn(1)["ok"])
	r = s.pass_turn(2)
	assert_eq(D.types(r["events"]), ["passed", "trick_cleared", "turn"])
	assert_eq(D.find(r["events"], "trick_cleared")["pid"], 3)
	assert_eq(r["events"][-1], {"type": "turn", "pid": 3, "stage": "play", "free": true}, "最后出牌的人重新自由出牌")
	assert_eq([s.lead, s.passes, s.table], [{}, 0, {}])
	assert_eq(s.card_count(), 54)


func test_table_shows_each_players_last_action_this_trick():
	var s := D.new_state()
	s.seat_order = [1, 2, 3]
	D.rig_play(s, {1: _c("3 9"), 2: _c("4 K"), 3: _c("5 2")}, 1, 1)
	s.play(1, _idx(s, 1, "3"))
	s.pass_turn(2)
	assert_eq(s.table, {1: {"cards": _c("3"), "type": H.SINGLE}, 2: {"pass": true}})


func test_bombs_and_rocket_double_the_multiplier():
	var s := D.new_state()
	s.seat_order = [1, 2, 3]
	D.rig_play(s, {1: _c("3 4"), 2: _c("8 8 8 8 9"), 3: _c("SJ BJ 5")}, 1, 1, 2)
	s.play(1, _idx(s, 1, "3"))
	var r := s.play(2, _idx(s, 2, "8 8 8 8"))
	assert_eq([D.find(r["events"], "played")["multiplier"], s.bombs], [2, 1])
	r = s.play(3, _idx(s, 3, "SJ BJ"))
	assert_eq([D.find(r["events"], "played")["combo"], D.find(r["events"], "played")["multiplier"], s.bombs],
		[H.ROCKET, 4, 2])


# —— 一手结束:计分与春天 ——

func test_landlord_wins_with_spring_and_scores_sum_to_zero():
	var s := D.new_state()
	s.seat_order = [1, 2, 3]
	D.rig_play(s, {1: _c("3 3 4 4 5 5"), 2: _c("6 9"), 3: _c("7 10")}, 1, 1, 2)
	var r := s.play(1, _idx(s, 1, "3 3 4 4 5 5"))
	assert_eq(D.types(r["events"]), ["played", "hand_over"])
	var ho := D.find(r["events"], "hand_over")
	assert_eq([ho["winner"], ho["landlord"], ho["landlord_won"], ho["spring"], ho["base"], ho["multiplier"]],
		[1, 1, true, true, 2, 2], "农民一张没出:春天 ×2")
	assert_eq(ho["deltas"], [{"pid": 1, "delta": 8}, {"pid": 2, "delta": -4}, {"pid": 3, "delta": -4}])
	assert_eq(ho["scores"], [{"pid": 1, "score": 8}, {"pid": 2, "score": -4}, {"pid": 3, "score": -4}])
	assert_eq(ho["remaining"], [{"pid": 1, "cards": []}, {"pid": 2, "cards": _c("6 9")}, {"pid": 3, "cards": _c("7 10")}])
	assert_eq([s.phase, s.current_pid], [P.BETWEEN, null])
	assert_eq(s.last_hand["winner"], 1)
	assert_false(s.last_hand.has("type"))
	assert_eq(D.event_leak(ho, D.revealed_cards(s, true)), "")


func test_farmers_win_with_reverse_spring_when_landlord_played_once():
	var s := D.new_state()
	s.seat_order = [1, 2, 3]
	D.rig_play(s, {1: _c("3 9 9"), 2: _c("4"), 3: _c("K")}, 1, 1, 3)
	s.play(1, _idx(s, 1, "3"))
	var r := s.play(2, _idx(s, 2, "4"))
	var ho := D.find(r["events"], "hand_over")
	assert_eq([ho["winner"], ho["landlord_won"], ho["spring"], ho["multiplier"]], [2, false, true, 2], "反春")
	assert_eq(ho["deltas"], [{"pid": 1, "delta": -12}, {"pid": 2, "delta": 6}, {"pid": 3, "delta": 6}])


func test_no_spring_when_both_sides_played_and_bombs_count():
	var s := D.new_state()
	s.seat_order = [1, 2, 3]
	D.rig_play(s, {1: _c("3 6 6 6 6"), 2: _c("4 9"), 3: _c("5 K")}, 1, 1, 1)
	s.play(1, _idx(s, 1, "3"))
	s.play(2, _idx(s, 2, "4"))
	s.play(3, _idx(s, 3, "5"))
	var r := s.play(1, _idx(s, 1, "6 6 6 6"))
	var ho := D.find(r["events"], "hand_over")
	assert_eq([ho["landlord_won"], ho["spring"], ho["bombs"], ho["multiplier"]], [true, false, 1, 2])
	var total := 0
	for row in ho["deltas"]:
		total += row["delta"]
	assert_eq(total, 0)
	assert_eq(ho["deltas"][0]["delta"], 4)


func test_scores_accumulate_over_hands():
	var s := D.new_state()
	s.seat_order = [1, 2, 3]
	D.rig_play(s, {1: _c("3"), 2: _c("4"), 3: _c("5")}, 1, 1, 1)
	s.play(1, [0])
	assert_eq(s.scores, {1: 4, 2: -2, 3: -2}, "春天 ×2:地主 +4")
	assert_true(s.can_start_hand())
	var events := s.start_hand()
	assert_eq(D.types(events), ["hand_started", "turn"])
	assert_eq(events[0]["hand"], 2)
	assert_eq(events[0]["scores"], [{"pid": 1, "score": 4}, {"pid": 2, "score": -2}, {"pid": 3, "score": -2}])
	assert_eq([s.phase, s.multiplier, s.base, s.landlord, s.bombs, s.played], [P.BIDDING, 1, 0, null, 0, []])
	assert_eq(s.card_count(), 54)
	assert_eq(s.last_hand["hand"], 1, "上一手摘要留着")


# —— 超时与托管 ——

func test_timeouts_pass_the_bid_or_play_the_smallest_single_or_pass():
	var s := D.new_state()
	var first: int = s.first_bidder
	var r := s.timeout()
	assert_eq(r["events"][0], {"type": "bid", "pid": first, "score": 0, "timed_out": true, "auto": false})
	assert_eq(s.timeouts[first], 1)
	s.seat_order = [1, 2, 3]
	s.timeouts = {1: 0, 2: 0, 3: 0}
	D.rig_play(s, {1: _c("5 3 9"), 2: _c("4 K"), 3: _c("6 7")}, 1, 1)
	r = s.timeout()
	var pl := D.find(r["events"], "played")
	assert_eq([pl["cards"], pl["timed_out"]], [_c("3"), true], "必须出时出最小的单张")
	r = s.timeout()
	assert_eq(D.find(r["events"], "passed"), {"type": "passed", "pid": 2, "timed_out": true, "auto": false}, "能不出就不出")


func test_two_consecutive_timeouts_enter_trustee_and_manual_play_resets_the_count():
	var s := D.new_state()
	s.seat_order = [1, 2, 3]
	s.timeouts = {1: 0, 2: 0, 3: 0}
	s.trustee = {1: false, 2: false, 3: false}
	D.rig_play(s, {1: _c("3 4 5 9 9 K"), 2: _c("6 7 8 J"), 3: _c("10 Q A 2")}, 1, 1)
	s.timeout()                      # 1 号超时一次:出 3
	assert_eq(s.timeouts[1], 1)
	s.play(2, _idx(s, 2, "6"))       # 2 号亲自出
	s.play(3, _idx(s, 3, "10"))
	assert_true(s.play(1, _idx(s, 1, "K"))["ok"], "1 号亲自出:连续超时清零")
	assert_eq(s.timeouts[1], 0)
	s.timeout()                      # 2 号超时(跟牌 → 不出)
	s.timeout()                      # 3 号超时
	assert_eq([s.timeouts[2], s.timeouts[3]], [1, 1])
	# 一圈清掉,1 号自由出牌;超时两次进托管
	assert_eq(s.current_pid, 1)
	s.timeout()
	s.timeout()   # 2 号第二次超时 → 托管
	assert_true(s.trustee[2])
	var log := []
	# 再让 2 号的回合到点:走托管打法(auto),不再记超时
	while s.current_pid != 2:
		log.append(s.timeout())
	var r := s.timeout()
	for ev in r["events"]:
		if ev["type"] == "played" or ev["type"] == "passed":
			assert_true(ev["auto"], "托管代打")
			assert_false(ev["timed_out"])
	assert_eq(s.timeouts[2], 0)


func test_the_entering_timeout_reports_trustee_before_the_action():
	var s := D.new_state()
	var first: int = s.first_bidder
	s.timeouts[first] = 1
	var r := s.timeout()
	assert_eq(D.types(r["events"]).slice(0, 2), ["trustee", "bid"])
	assert_eq(r["events"][0], {"type": "trustee", "pid": first, "on": true, "auto": true})
	assert_true(s.trustee[first])


func test_trustee_toggle_and_auto_play_rules():
	var s := D.new_state()
	s.seat_order = [1, 2, 3]
	s.trustee = {1: false, 2: false, 3: false}
	assert_eq(s.set_trustee(2, true)["events"], [{"type": "trustee", "pid": 2, "on": true, "auto": false}])
	assert_eq(s.set_trustee(2, true)["events"], [], "没变化:成功但没事件")
	assert_eq(s.set_trustee(9, true)["error"], DdzState.ERR_NOT_SEATED)
	assert_eq(s.set_trustee(2, "yes")["error"], DdzState.ERR_INVALID_INTENT)
	s.set_trustee(3, true)
	# 地主 1 号出 5;农民 2 号托管跟对手:最小的能压过的非炸弹(6),不拆炸弹
	D.rig_play(s, {1: _c("5 K 3"), 2: _c("6 9 9 9 9 Q"), 3: _c("7 8")}, 1, 1)
	s.play(1, _idx(s, 1, "5"))
	var r := s.timeout()
	assert_eq(D.find(r["events"], "played")["cards"], _c("6"))
	assert_true(D.find(r["events"], "played")["auto"])
	# 3 号托管:上家是队友 2 号 → 不出
	r = s.timeout()
	assert_eq(D.find(r["events"], "passed")["auto"], true, "队友出的牌不压")
	# 1 号压 K,2 号托管:只有炸弹能压 → 不出(托管不用炸弹)
	s.play(1, _idx(s, 1, "K"))
	r = s.timeout()
	assert_eq(D.types(r["events"])[0], "passed")
	assert_eq(s.set_trustee(2, false)["events"], [{"type": "trustee", "pid": 2, "on": false, "auto": false}])


func test_trustee_free_lead_plays_the_first_hint():
	var s := D.new_state()
	s.seat_order = [1, 2, 3]
	s.trustee = {1: true, 2: false, 3: false}
	D.rig_play(s, {1: _c("3 4 5 6 7 Q"), 2: _c("8"), 3: _c("9")}, 1, 1)
	var r := s.timeout()
	assert_eq(D.find(r["events"], "played")["combo"], H.STRAIGHT)


func test_timeout_outside_a_turn_is_refused():
	var s := D.new_state()
	s.seat_order = [1, 2, 3]
	D.rig_play(s, {1: _c("3"), 2: _c("4"), 3: _c("5")}, 1, 1)
	s.play(1, [0])
	assert_eq(s.timeout()["error"], DdzState.ERR_NO_HAND, "两手之间")
	assert_eq(s.play(2, [0])["error"], DdzState.ERR_NO_HAND)


# —— 散局与离开 ——

func test_request_end_finishes_the_current_hand_first():
	var s := D.new_state()
	s.seat_order = [1, 2, 3]
	D.rig_play(s, {1: _c("3 9"), 2: _c("5 6"), 3: _c("7 8")}, 1, 1)
	assert_eq(s.request_end(), [{"type": "ending"}])
	assert_eq(s.request_end(), [], "只发一次")
	assert_true(s.ending)
	s.play(1, _idx(s, 1, "3"))
	s.play(2, _idx(s, 2, "5"))
	s.play(3, _idx(s, 3, "7"))
	var r := s.play(1, _idx(s, 1, "9"))
	assert_eq(D.types(r["events"]), ["played", "hand_over", "session_over"])
	var so := D.find(r["events"], "session_over")
	assert_eq(so["reason"], "host")
	assert_eq(so["results"][0], {"pid": 1, "score": 2, "left": false, "place": 1})
	assert_eq([s.phase, s.can_start_hand()], [P.OVER, false])
	assert_eq(s.bid(1, 1)["error"], DdzState.ERR_SESSION_OVER)
	assert_eq(s.set_trustee(1, true)["error"], DdzState.ERR_SESSION_OVER)


func test_request_end_between_hands_settles_at_once():
	var s := D.new_state()
	s.seat_order = [1, 2, 3]
	D.rig_play(s, {1: _c("3"), 2: _c("4"), 3: _c("5")}, 1, 1)
	s.play(1, [0])
	var events := s.request_end()
	assert_eq(D.types(events), ["session_over"])
	assert_eq(events[0]["results"].map(func(row: Dictionary) -> Array: return [row["pid"], row["score"], row["place"]]),
		[[1, 4, 1], [2, -2, 2], [3, -2, 2]], "按累计分排名,同分同名次")


func test_a_leaver_ends_the_session_and_voids_the_hand():
	var s := D.new_state()
	s.scores = {s.seat_order[0]: 6, s.seat_order[1]: -3, s.seat_order[2]: -3}
	var gone: int = s.seat_order[1]
	var events := s.remove_player(gone)
	assert_eq(D.types(events), ["player_left", "session_over"])
	assert_eq(events[0], {"type": "player_left", "pid": gone, "hand_voided": true})
	assert_eq(events[1]["reason"], "player_left")
	var row: Dictionary = events[1]["results"].filter(func(r: Dictionary) -> bool: return r["pid"] == gone)[0]
	assert_true(row["left"])
	assert_eq(s.phase, P.OVER)
	assert_eq(s.remove_player(gone), [], "结算后不再有事件")
	assert_eq(s.remove_player(99), [])


# —— 隐藏信息 ——

func test_a_scripted_hand_never_leaks_hidden_cards():
	var s := D.new_state(21)
	var events := []
	_bid_to_landlord(s, s.seat_order[2])
	var guard := 0
	while s.phase == P.PLAYING and guard < 200:
		guard += 1
		var batch: Array = s.timeout()["events"]
		var revealed := D.revealed_cards(s, s.phase != P.PLAYING)
		for ev in batch:
			assert_eq(D.event_leak(ev, revealed), "", str(ev))
		events.append_array(batch)
	assert_eq(s.phase, P.BETWEEN, "只靠超时代打也能打完一手")
	assert_eq(s.card_count(), 54)
	var total := 0
	for pid in s.seat_order:
		total += s.scores[pid]
	assert_eq(total, 0)
