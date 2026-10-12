extends GutTest
# 21 点算点(BjScore)与赔付(BjRules.payout)。


const H := preload("res://tests/poker_helpers.gd")


func test_face_cards_count_ten_and_ace_eleven():
	assert_eq(BjScore.card_value(H.card("Kh")), 10)
	assert_eq(BjScore.card_value(H.card("Td")), 10)
	assert_eq(BjScore.card_value(H.card("As")), 11)
	assert_eq(BjScore.card_value(H.card("7c")), 7)


func test_soft_and_hard_totals():
	assert_eq(BjScore.evaluate(H.cards("As 6d")), {"total": 17, "soft": true})
	assert_eq(BjScore.evaluate(H.cards("As 6d Kc")), {"total": 17, "soft": false})
	assert_eq(BjScore.evaluate(H.cards("As Ad")), {"total": 12, "soft": true})
	assert_eq(BjScore.evaluate(H.cards("As Ad 9c")), {"total": 21, "soft": true})
	assert_eq(BjScore.evaluate(H.cards("Ks Qd 5c")), {"total": 25, "soft": false})


func test_natural_needs_exactly_two_cards():
	assert_true(BjScore.is_natural(H.cards("As Kd")))
	assert_false(BjScore.is_natural(H.cards("7s 7d 7c")))
	assert_false(BjScore.is_natural(H.cards("As 9d")))


func test_split_compares_values_not_ranks():
	assert_true(BjScore.same_value(H.card("Ks"), H.card("Qd")))
	assert_true(BjScore.same_value(H.card("Ts"), H.card("Jd")))
	assert_false(BjScore.same_value(H.card("9s"), H.card("Td")))


func test_dealer_peeks_on_ace_or_ten_and_stands_on_soft_17():
	assert_true(BjScore.dealer_peeks(H.card("Ah")))
	assert_true(BjScore.dealer_peeks(H.card("Jh")))
	assert_false(BjScore.dealer_peeks(H.card("9h")))
	assert_true(BjScore.dealer_draws(H.cards("Th 6d")))
	assert_false(BjScore.dealer_draws(H.cards("Ah 6d")))   # 软 17 也停
	assert_false(BjScore.dealer_draws(H.cards("Th 7d")))


func test_labels():
	assert_eq(BjScore.label([]), "")
	assert_eq(BjScore.label(H.cards("As 6d")), "软 17")
	assert_eq(BjScore.label(H.cards("Ks Qd 5c")), "爆牌 25")
	assert_eq(BjScore.label(H.cards("As Kd")), "21")


func test_payouts_include_the_stake():
	assert_eq(BjRules.payout(BjRules.OUTCOME_BLACKJACK, 100), 250)
	assert_eq(BjRules.payout(BjRules.OUTCOME_WIN, 100), 200)
	assert_eq(BjRules.payout(BjRules.OUTCOME_PUSH, 100), 100)
	assert_eq(BjRules.payout(BjRules.OUTCOME_SURRENDER, 100), 50)
	assert_eq(BjRules.payout(BjRules.OUTCOME_LOSE, 100), 0)
	assert_eq(BjRules.payout(BjRules.OUTCOME_BUST, 100), 0)


func test_every_legal_bet_pays_whole_chips():
	for bet in range(BjRules.MIN_BET, BjRules.MAX_BET + 1, BjRules.BET_UNIT):
		assert_eq(BjRules.payout(BjRules.OUTCOME_BLACKJACK, bet) % BjRules.CHIP_UNIT, 0)
		assert_eq(BjRules.payout(BjRules.OUTCOME_SURRENDER, bet) % BjRules.CHIP_UNIT, 0)


func test_bet_validation():
	assert_true(BjRules.is_valid_bet(20, 2000))
	assert_true(BjRules.is_valid_bet(1000, 2000))
	assert_false(BjRules.is_valid_bet(30, 2000))      # 不是 20 的倍数
	assert_false(BjRules.is_valid_bet(1020, 5000))    # 超过上限
	assert_false(BjRules.is_valid_bet(200, 100))      # 筹码不够
	assert_false(BjRules.is_valid_bet("100", 2000))
	assert_false(BjRules.is_valid_bet(0, 2000))


func test_shoe_has_six_decks_and_reshuffles_when_low():
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var shoe := BjShoe.new(rng)
	assert_eq(shoe.remaining(), 312)
	assert_eq(BjShoe.size(), 312)
	var counts := {}
	for i in 312 - BjRules.RESHUFFLE_BELOW:
		var card := shoe.draw()
		counts[card] = counts.get(card, 0) + 1
	for card in counts:
		assert_true(counts[card] <= BjRules.DECKS)
	assert_false(shoe.needs_shuffle())
	shoe.draw()
	assert_true(shoe.needs_shuffle())
	shoe.shuffle()
	assert_eq(shoe.remaining(), 312)
