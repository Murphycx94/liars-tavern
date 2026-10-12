extends GutTest
# 21 点导演:每段演出的实际时长(导演与 BjCards / BjChips 的节奏常量)不超过房主排期用的 BlackjackPacing 预算;
# 日志文案与自己这一局的大字宣告。


const D := preload("res://src/ui/blackjack/blackjack_director.gd")
const P := preload("res://src/net/blackjack_pacing.gd")
const R := preload("res://src/core/blackjack/bj_rules.gd")
const H := preload("res://tests/poker_helpers.gd")


func test_every_animation_fits_its_budget():
	assert_lte(D.INTRO_MOVE, P.INTRO)
	assert_lte(D.ROUND_SETTLE, P.ROUND_STARTED)
	assert_lte(BjCards.SWEEP_FLIGHT + BjCards.SWEEP_JITTER, P.ROUND_STARTED)
	assert_lte(D.SHUFFLE_HOLD, P.SHUFFLE)
	assert_lte(BjChips.BET_SLIDE, P.BET_PLACED)
	for players in range(1, R.MAX_SEATS + 1):
		var cards := 2 * players + 2
		assert_lte(BjCards.deal_duration(cards), P.DEAL_BASE + P.DEAL_PER_CARD * cards, "%d 人发牌" % players)
	assert_lte(BjCards.PEEK_TIME, P.PEEK)
	assert_lte(BjCards.HIT_FLIGHT, P.HIT)
	assert_lte(D.STAND_PAUSE, P.STAND)
	assert_lte(BjChips.BET_SLIDE + BjCards.HIT_FLIGHT, P.DOUBLE, "加倍:先推筹码再横着发一张")
	assert_lte(maxf(BjCards.split_duration(), BjChips.BET_SLIDE), P.SPLIT)
	assert_lte(BjCards.SURRENDER_FLIGHT, P.SURRENDER)
	assert_lte(BjCards.FLIP + D.REVEAL_HOLD, P.DEALER_REVEAL)
	assert_lte(BjCards.DEALER_FLIGHT, P.DEALER_HIT)
	assert_lte(BjChips.settle_duration() + D.SETTLE_HOLD, P.SETTLED)
	assert_lte(D.ROUND_OVER_PAUSE, P.ROUND_OVER)
	assert_lte(BjChips.REBUY_DROP, P.REBUY)
	assert_lte(D.LEFT_PAUSE, P.PLAYER_LEFT)
	assert_lte(D.SESSION_OVER_HOLD, P.SESSION_OVER)


func test_estimate_adds_up_a_whole_round():
	var events := [
		{"type": "bet_placed"}, {"type": "dealt", "order": [1, 2]}, {"type": "turn"}, {"type": "hit"},
		{"type": "stand"}, {"type": "dealer_reveal"}, {"type": "dealer_hit"}, {"type": "settled"}, {"type": "round_over"},
	]
	var want := P.BET_PLACED + P.DEAL_BASE + P.DEAL_PER_CARD * 6 + P.HIT + P.STAND + P.DEALER_REVEAL + P.DEALER_HIT \
		+ P.SETTLED + P.ROUND_OVER
	assert_almost_eq(P.estimate(events), want, 0.0001)
	assert_almost_eq(P.estimate([{"type": "round_started", "shuffled": true}]), P.ROUND_STARTED + P.SHUFFLE, 0.0001)
	assert_eq(P.estimate([{"type": "player_left", "offstage": true}, {"type": "bet_skipped"}]), 0.0)


func test_timer_gives_full_time_to_new_turns_and_keeps_it_otherwise():
	assert_eq(P.timer_after([{"type": "round_started"}], 1.5, 0.0, true), 1.5 + P.BET_TIMEOUT)
	assert_eq(P.timer_after([{"type": "hit"}, {"type": "turn"}], 0.5, 4.0, false), 0.5 + P.PLAY_TIMEOUT)
	assert_eq(P.timer_after([{"type": "bet_placed"}], 0.5, 7.0, true), 7.0 + P.BET_PLACED)
	assert_eq(P.timer_after([{"type": "rebuy"}], 0.6, 0.0, true), 0.6 + P.BET_TIMEOUT)


func test_action_text():
	assert_eq(D.action_text({"type": "hit", "total": 18, "bust": false}), "要牌 → 18")
	assert_eq(D.action_text({"type": "hit", "total": 24, "bust": true}), "要牌 → 爆牌 24")
	assert_eq(D.action_text({"type": "double", "total": 21}), "加倍 → 21")
	assert_eq(D.action_text({"type": "stand", "timeout": true}), "停牌(超时)")
	assert_eq(D.action_text({"type": "split", "aces": true}), "分牌(A 各补一张)")
	assert_eq(D.action_text({"type": "surrender"}), "投降,收回一半")


func test_my_result_sums_split_hands():
	var rows := [
		{"pid": 1, "hand": 0, "outcome": R.OUTCOME_WIN, "bet": 100, "payout": 200},
		{"pid": 1, "hand": 1, "outcome": R.OUTCOME_LOSE, "bet": 200, "payout": 0},
		{"pid": 2, "hand": 0, "outcome": R.OUTCOME_BLACKJACK, "bet": 100, "payout": 250},
	]
	var mine := D.my_result(rows, 1)
	assert_eq(mine, {"net": -100, "outcomes": [R.OUTCOME_WIN, R.OUTCOME_LOSE]})
	assert_eq(D.result_title(mine)["text"], "输了")
	assert_eq(D.result_title(D.my_result(rows, 2))["text"], "黑杰克!")
	assert_eq(D.result_title(D.my_result(rows, 3)), {}, "没有自己的手不宣告")
	assert_eq(D.result_title({"net": 0, "outcomes": [R.OUTCOME_PUSH]})["text"], "平手")
	assert_eq(D.result_title({"net": -100, "outcomes": [R.OUTCOME_BUST]})["text"], "爆牌")
	assert_eq(D.result_title({"net": 0, "outcomes": [R.OUTCOME_WIN, R.OUTCOME_LOSE]})["text"], "平手")
