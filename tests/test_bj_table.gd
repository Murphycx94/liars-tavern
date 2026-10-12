extends GutTest
# 21 点状态机(BjTable):下注阶段、发牌与庄家看牌、要牌 / 停牌 / 加倍 / 分牌 / 投降、庄家要牌、结算与赔付、
# 超时与离座、输光再领、中途加入、离开与散局。牌用 rig 按发牌顺序指定:
# 每人一张 → 庄家明牌 → 每人第二张 → 庄家暗牌 → 之后按要牌顺序。


const H := preload("res://tests/poker_helpers.gd")
const R := preload("res://src/core/blackjack/bj_rules.gd")

var table: BjTable


func before_each():
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	table = BjTable.new(rng)


func _open(pids := [1]) -> Array:
	for pid in pids:
		table.seat(pid)
	return table.start_round()


func _ok(result: Dictionary) -> Array:
	assert_true(result["ok"], "动作应当成功:%s" % result.get("error", ""))
	return result.get("events", [])


func _bet_all(bets: Dictionary) -> Array:
	var events := []
	for pid in bets:
		events.append_array(_ok(table.bet(pid, bets[pid])))
	return events


func _outcomes(events: Array) -> Array:
	return H.find(events, "settled")["hands"].map(func(row): return row["outcome"])


# —— 下注阶段 ——

func test_round_opens_betting_and_deals_once_everyone_decides():
	var events := _open([1, 2])
	assert_eq(events[0]["type"], "round_started")
	assert_eq(events[0]["seats"], [1, 2])
	assert_eq(table.phase(), BjTable.Phase.BETTING)
	assert_eq(table.awaiting_bets(), [1, 2])
	table.rig(H.cards("9s 5d 7c Ts 6h Kd"))
	assert_eq(H.types(_ok(table.bet(1, 100))), ["bet_placed"])
	assert_eq(table.player(1)["stack"], 1900)
	events = _ok(table.bet(2, 40))
	assert_eq(H.types(events), ["bet_placed", "dealt", "turn"])
	var dealt := H.find(events, "dealt")
	assert_eq(dealt["order"], [1, 2])
	assert_eq(dealt["hands"][1], H.cards("9s Ts"))
	assert_eq(dealt["dealer_up"], H.card("7c"))
	assert_eq(table.dealer_cards(), [H.card("7c")], "暗牌翻开之前不公开")
	assert_true(table.dealer_hidden())
	assert_eq(table.current(), {"pid": 1, "hand": 0})


func test_bet_must_be_a_legal_amount_and_only_once():
	_open([1, 2])
	assert_eq(table.bet(1, 30)["error"], "invalid_amount")
	assert_eq(table.bet(1, 2020)["error"], "invalid_amount")
	assert_eq(table.bet(1, "100")["error"], "invalid_amount")
	_ok(table.bet(1, 100))
	assert_eq(table.bet(1, 100)["error"], "invalid_action")
	assert_eq(table.bet(9, 100)["error"], "not_seated")
	assert_eq(table.act(1, R.HIT)["error"], "no_round")


func test_everyone_skipping_ends_the_round_without_dealing():
	_open([1, 2])
	_ok(table.skip(1))
	var events := _ok(table.skip(2))
	assert_eq(H.types(events), ["bet_skipped", "round_over"])
	assert_eq(table.phase(), BjTable.Phase.IDLE)
	assert_true(table.can_start_round())


func test_betting_timeout_skips_the_undecided():
	_open([1, 2])
	table.rig(H.cards("9s 7c Ts Kd"))
	_ok(table.bet(1, 100))
	var events := _ok(table.timeout_action())
	assert_eq(H.find(events, "bet_skipped"), {"type": "bet_skipped", "pid": 2, "timeout": true})
	assert_eq(H.find(events, "dealt")["order"], [1])
	assert_eq(table.player(2)["status"], R.STATUS_SKIP)


# —— 结算 ——

func test_stand_on_20_beats_dealer_17():
	_open()
	table.rig(H.cards("Ks 7c Qd Td"))
	_bet_all({1: 100})
	var events := _ok(table.act(1, R.STAND))
	assert_eq(H.types(events), ["stand", "dealer_reveal", "settled", "round_over"])
	assert_eq(_outcomes(events), [R.OUTCOME_WIN])
	assert_eq(table.player(1)["stack"], 2100)
	assert_eq(table.dealer_cards().size(), 2)
	assert_false(table.dealer_hidden())


func test_dealer_draws_to_17_and_stands_on_soft_17():
	_open()
	table.rig(H.cards("Ks 6c Qd 5d"))
	_bet_all({1: 100})
	table.rig(H.cards("Ah 5s"))           # 庄家 6 + 5 + A = 12(A 只能算 1),再要 5 → 17 停
	var events := _ok(table.act(1, R.STAND))
	assert_eq(H.find_all(events, "dealer_hit").size(), 2)
	assert_eq(H.find(events, "settled")["dealer_total"], 17)
	assert_eq(_outcomes(events), [R.OUTCOME_WIN])


func test_dealer_bust_pays_every_standing_hand():
	_open([1, 2])
	table.rig(H.cards("Ks 5h 6c Qd 7h Td 9s"))
	_bet_all({1: 100, 2: 200})
	_ok(table.act(1, R.STAND))
	var events := _ok(table.act(2, R.STAND))
	assert_true(H.find(events, "settled")["dealer_bust"])
	assert_eq(_outcomes(events), [R.OUTCOME_WIN, R.OUTCOME_WIN])
	assert_eq(table.player(2)["stack"], 2200)


func test_player_blackjack_pays_three_to_two_without_a_turn():
	_open([1, 2])
	table.rig(H.cards("As 9h 7c Kd 9d Td"))
	var events := _bet_all({1: 100, 2: 100})
	assert_eq(table.current(), {"pid": 2, "hand": 0}, "黑杰克的人不用决策")
	assert_true(H.find(events, "peek").is_empty(), "明牌 7 不看牌")
	events = _ok(table.act(2, R.STAND))
	assert_eq(_outcomes(events), [R.OUTCOME_BLACKJACK, R.OUTCOME_WIN])
	assert_eq(table.player(1)["stack"], 2150)


func test_dealer_blackjack_ends_the_round_at_once():
	_open([1, 2])
	table.rig(H.cards("As 9s Ah Kd Th Kc"))   # 玩家 1 黑杰克,庄家 A + K
	var events := _bet_all({1: 100, 2: 100})
	assert_eq(H.find(events, "peek"), {"type": "peek", "blackjack": true})
	assert_eq(_outcomes(events), [R.OUTCOME_PUSH, R.OUTCOME_LOSE], "黑杰克对黑杰克是平手")
	assert_eq(table.phase(), BjTable.Phase.IDLE)
	assert_eq(table.player(1)["stack"], 2000)
	assert_eq(table.player(2)["stack"], 1900)


func test_peek_without_blackjack_continues():
	_open()
	table.rig(H.cards("Ts Ad 8s 6c"))
	var events := _bet_all({1: 100})
	assert_eq(H.find(events, "peek"), {"type": "peek", "blackjack": false})
	assert_eq(table.current(), {"pid": 1, "hand": 0})


func test_bust_loses_and_dealer_does_not_draw_when_nobody_is_left():
	_open()
	table.rig(H.cards("Ts 6c 6s Td"))
	_bet_all({1: 100})
	table.rig(H.cards("Kh"))
	var events := _ok(table.act(1, R.HIT))
	assert_true(H.find(events, "hit")["bust"])
	assert_true(H.find_all(events, "dealer_hit").is_empty())
	assert_eq(_outcomes(events), [R.OUTCOME_BUST])
	assert_eq(table.player(1)["stack"], 1900)


func test_hit_keeps_the_turn_and_21_stands_automatically():
	_open()
	table.rig(H.cards("5s 9c 6s 8d"))
	_bet_all({1: 100})
	table.rig(H.cards("4h"))
	var events := _ok(table.act(1, R.HIT))
	assert_eq(H.types(events), ["hit", "turn"], "没打完:还是他,重新给回合")
	table.rig(H.cards("6h"))
	events = _ok(table.act(1, R.HIT))
	assert_eq(H.find(events, "hit")["total"], 21)
	assert_eq(H.find(events, "dealer_reveal").is_empty(), false, "到 21 自动停牌")


func test_double_takes_one_card_and_doubles_the_bet():
	_open()
	table.rig(H.cards("6s 9c 5d 8d"))
	_bet_all({1: 100})
	assert_true(table.legal_actions(1)[R.DOUBLE])
	table.rig(H.cards("Ts"))
	var events := _ok(table.act(1, R.DOUBLE))
	var double := H.find(events, "double")
	assert_eq(double["bet"], 200)
	assert_eq(double["stack"], 1800)
	assert_eq(double["total"], 21)
	assert_eq(_outcomes(events), [R.OUTCOME_WIN])
	assert_eq(table.player(1)["stack"], 2200)


func test_cannot_double_or_split_without_chips():
	_open()
	table.set_stack(1, 140)
	table.rig(H.cards("8s 9c 8d 8h"))
	_bet_all({1: 100})
	var legal := table.legal_actions(1)
	assert_false(legal[R.DOUBLE])
	assert_false(legal[R.SPLIT])
	assert_eq(table.act(1, R.SPLIT)["error"], "invalid_action")


func test_split_plays_each_hand_in_turn():
	_open()
	table.rig(H.cards("8s 9c 8d Td"))
	_bet_all({1: 100})
	table.rig(H.cards("3h Kh"))
	var events := _ok(table.act(1, R.SPLIT))
	var split := H.find(events, "split")
	assert_eq(split["cards"], [H.cards("8s 3h"), H.cards("8d Kh")])
	assert_eq(split["stack"], 1800)
	assert_eq(H.find(events, "turn"), {"type": "turn", "pid": 1, "hand": 0})
	assert_false(table.legal_actions(1)[R.SURRENDER], "分牌后不能投降")
	assert_true(table.legal_actions(1)[R.DOUBLE], "分牌后可以加倍")
	table.rig(H.cards("Th"))
	events = _ok(table.act(1, R.DOUBLE))   # 8 3 T = 21
	assert_eq(H.find(events, "turn"), {"type": "turn", "pid": 1, "hand": 1})
	events = _ok(table.act(1, R.STAND))   # 18 对 19
	assert_eq(_outcomes(events), [R.OUTCOME_WIN, R.OUTCOME_LOSE])
	assert_eq(table.player(1)["stack"], 2000 - 300 + 400)


func test_split_aces_take_one_card_each_and_21_is_not_blackjack():
	_open()
	table.rig(H.cards("As 9c Ad 7d"))
	_bet_all({1: 100})
	table.rig(H.cards("Kh 5c 2h"))   # 庄家 16 再要 2 → 18
	var events := _ok(table.act(1, R.SPLIT))
	assert_true(H.find(events, "split")["aces"])
	assert_true(H.find(events, "turn").is_empty(), "分 A 各补一张就停")
	assert_eq(_outcomes(events), [R.OUTCOME_WIN, R.OUTCOME_LOSE])
	assert_eq(table.player(1)["stack"], 2000 - 200 + 200, "A+K 只按普通 21 赔 1:1")


func test_split_tens_of_different_ranks_and_at_most_four_hands():
	_open()
	table.rig(H.cards("Ks 9c Qd 7d"))
	_bet_all({1: 100})
	table.rig(H.cards("Jh 5c"))
	_ok(table.act(1, R.SPLIT))   # K J / Q 5
	table.rig(H.cards("Th 4c"))
	_ok(table.act(1, R.SPLIT))   # K T / J 4 / Q 5
	table.rig(H.cards("Tc 2c"))
	_ok(table.act(1, R.SPLIT))   # K T / T 2 / J 4 / Q 5
	assert_eq(table.player(1)["hands"].size(), 4)
	assert_false(table.legal_actions(1)[R.SPLIT], "最多 4 手")


func test_surrender_returns_half():
	_open()
	table.rig(H.cards("Ts 9c 6d Td"))
	_bet_all({1: 100})
	var events := _ok(table.act(1, R.SURRENDER))
	assert_eq(H.find(events, "surrender")["refund"], 50)
	assert_true(H.find_all(events, "dealer_hit").is_empty(), "没有要比的手,庄家只翻牌")
	assert_eq(_outcomes(events), [R.OUTCOME_SURRENDER])
	assert_eq(table.player(1)["stack"], 1950)


func test_turn_timeout_stands():
	_open()
	table.rig(H.cards("Ts 9c 9d Td"))
	_bet_all({1: 100})
	var events := _ok(table.timeout_action())
	assert_eq(H.find(events, "stand")["timeout"], true)
	assert_eq(_outcomes(events), [R.OUTCOME_PUSH])


func test_not_your_turn_and_wrong_actions_are_rejected():
	_open([1, 2])
	table.rig(H.cards("Ts 9s 9c 9d 8h Td"))
	_bet_all({1: 100, 2: 100})
	assert_eq(table.act(2, R.HIT)["error"], "not_your_turn")
	assert_eq(table.act(1, "fold")["error"], "invalid_action")
	assert_eq(table.act(1, R.SPLIT)["error"], "invalid_action")
	assert_eq(table.legal_actions(2), {})


# —— 座位:超时离座、输光再领、中途加入、离开 ——

func test_two_timeouts_send_a_player_away_until_they_sit_in():
	_open([1])
	_ok(table.timeout_action())
	assert_eq(table.phase(), BjTable.Phase.IDLE)
	_ok_round_start()
	var events := _ok(table.timeout_action())
	assert_eq(H.find(events, "away"), {"type": "away", "pid": 1})
	assert_false(table.can_start_round(), "唯一的人离座了:不开新局")
	assert_eq(H.types(_ok(table.sit_in(1))), ["sit_in"])
	assert_true(table.can_start_round())


func _ok_round_start() -> void:
	assert_eq(table.start_round()[0]["type"], "round_started")


func test_busted_player_rebuys():
	_open([1])
	table.set_stack(1, 100)
	table.rig(H.cards("Ts 9c 6s Td Kh"))
	_bet_all({1: 100})
	var events := _ok(table.act(1, R.HIT))
	assert_eq(H.find(events, "round_over")["busted"], [1])
	assert_eq(table.player(1)["status"], R.STATUS_BUSTED)
	assert_false(table.can_start_round())
	events = _ok(table.rebuy(1))
	assert_eq(events[0]["stack"], 2000)
	assert_eq(table.player(1)["buyins"], 2)
	assert_true(table.can_start_round())
	assert_eq(table.rebuy(1)["error"], "cannot_rebuy")


func test_late_joiner_waits_for_the_next_round():
	_open([1])
	assert_eq(H.types(table.add_player(2)), ["player_joined"])
	assert_eq(table.awaiting_bets(), [1], "新人不在这一局里,下注不等他")
	assert_eq(table.seats_with_patrons(), [1])
	assert_eq(table.bet(2, 100)["error"], "invalid_action")
	_ok(table.skip(1))
	var events := table.start_round()
	assert_eq(events[0]["seats"], [1, 2])
	assert_eq(table.awaiting_bets(), [1, 2])


func test_table_is_capped_at_seven():
	for pid in range(1, 8):
		table.seat(pid)
	assert_eq(table.add_player(8), [])


func test_leaving_while_betting_refunds_the_bet():
	_open([1, 2])
	table.rig(H.cards("Ts 9c 6s Td"))
	_ok(table.bet(1, 100))
	var events := table.remove_player(1)
	assert_eq(events[0]["type"], "player_left")
	assert_eq(table.player(1)["stack"], 2000, "押的注退回")
	events = _ok(table.bet(2, 200))
	assert_eq(H.find(events, "dealt")["order"], [2])
	_ok(table.act(2, R.STAND))
	assert_eq(table.player(1), {}, "这一局结束后移出")
	var row: Dictionary = table.results().filter(func(r): return r["pid"] == 1)[0]
	assert_eq(row["stack"], 2000)
	assert_true(row["left"])


func test_leaving_on_your_turn_stands_and_moves_on():
	_open([1, 2])
	table.rig(H.cards("Ts 9s 9c 9d 8h Td"))
	_bet_all({1: 100, 2: 100})
	var events := table.remove_player(1)
	assert_eq(H.types(events), ["player_left", "turn"])
	assert_eq(table.current(), {"pid": 2, "hand": 0})
	events = _ok(table.act(2, R.STAND))
	assert_eq(_outcomes(events), [R.OUTCOME_PUSH, R.OUTCOME_LOSE], "离开者的 19 照常和庄家的 19 比")
	assert_eq(table.player(1), {})


func test_leaving_between_rounds_departs_at_once():
	_open([1, 2])
	_ok(table.skip(1))
	_ok(table.skip(2))
	var events := table.remove_player(2)
	assert_eq(H.types(events), ["player_left"])
	assert_eq(table.seat_order(), [1])


# —— 散局 ——

func test_end_while_betting_settles_at_once_and_refunds():
	_open([1, 2])
	_ok(table.bet(1, 100))
	var events := table.request_end()
	assert_eq(H.types(events), ["session_over"])
	assert_eq(table.phase(), BjTable.Phase.OVER)
	assert_eq(events[0]["results"][0]["stack"], 2000)
	assert_eq(table.request_end(), [])
	assert_eq(table.bet(2, 100)["error"], "session_over")


func test_end_while_playing_finishes_the_round_first():
	_open()
	table.rig(H.cards("Ks 7c Qd Td"))
	_bet_all({1: 100})
	assert_eq(H.types(table.request_end()), ["ending"])
	assert_true(table.is_ending())
	var events := _ok(table.act(1, R.STAND))
	assert_eq(events.back()["type"], "session_over")
	assert_eq(events.back()["results"][0]["net"], 100)
	assert_false(table.can_start_round())


func test_results_count_chips_on_the_table():
	_open([1, 2])
	table.rig(H.cards("Ks 9s 7c Qd 9d Td"))
	_bet_all({1: 100, 2: 300})
	var rows := table.results()
	assert_eq(rows.map(func(r): return r["net"]), [0, 0], "押着的注还算自己的")


func test_reshuffles_when_the_shoe_runs_low():
	_open([1])
	var shuffled := false
	for i in 80:
		if table.phase() == BjTable.Phase.IDLE:
			var events := table.start_round()
			if events[0]["shuffled"]:
				shuffled = true
				break
		_ok(table.bet(1, 20))
		while table.phase() == BjTable.Phase.PLAYING:
			_ok(table.act(1, R.STAND))
		if table.player(1)["status"] == R.STATUS_BUSTED:
			_ok(table.rebuy(1))
	assert_true(shuffled)


func test_a_departed_pid_cannot_take_a_second_seat():
	_open([1, 2])
	_ok(table.skip(1))
	_ok(table.skip(2))
	table.remove_player(2)
	assert_eq(table.seats_with_patrons(), [1], "离开的人不再算桌上有酒客")
	assert_eq(table.add_player(2), [], "同一个 pid 回来不收")
	assert_eq(table.results().filter(func(r): return r["pid"] == 2).size(), 1, "结算表里只有一行")
