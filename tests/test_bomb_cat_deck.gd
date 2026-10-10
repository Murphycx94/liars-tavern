extends GutTest
# 炸弹猫的牌与配牌(设计稿 §1.2、§1.4):每种人数的总张数、开局手牌、牌堆里的炸弹与拆弹、可复现的洗牌;
# 牌名与说明齐全且原创。


const C := preload("res://src/core/bomb_cat/bomb_cat_card.gd")

# 设计稿 §1.4 的表,逐格抄一遍(和引擎常量分开写:改了表这里会提醒)
# (2026-10-10 减量后的表)
const TABLE := {
	"skip": [3, 3, 4, 4, 5], "pass_turns": [2, 2, 3, 3, 4], "peek": [3, 3, 4, 4, 5],
	"shuffle": [2, 2, 3, 3, 4], "beg": [2, 2, 3, 3, 3], "nope": [3, 3, 4, 4, 5],
	"snack": [3, 3, 3, 3, 4],
}
# 每种人数的总张数:功能牌 + 拆弹(n + 2,5 人起 n + 1)+ 炸弹(n − 1)
const TOTALS := {2: 30 + 4 + 1, 3: 30 + 5 + 2, 4: 36 + 6 + 3, 5: 36 + 6 + 4, 6: 46 + 7 + 5}
const OPENING_HAND := 5   # 4 张 + 1 张拆弹


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _count(cards: Array, id: String) -> int:
	return cards.filter(func(c: String) -> bool: return c == id).size()


func _pids(n: int) -> Array:
	return range(1, n + 1)


func test_action_counts_follow_the_table_for_every_player_count():
	for n in range(2, 7):
		var counts := BombCatDeck.action_counts(n)
		for id in TABLE:
			if id == "snack":
				for snack in C.SNACKS:
					assert_eq(counts[snack], TABLE["snack"][n - 2], "%d 人 %s" % [n, snack])
			else:
				assert_eq(counts[id], TABLE[id][n - 2], "%d 人 %s" % [n, id])
		assert_false(counts.has(C.BOMB) or counts.has(C.DEFUSE), "功能牌表里不含炸弹和拆弹")


func test_defuse_and_bomb_counts():
	assert_eq([BombCatDeck.defuse_total(2), BombCatDeck.defuse_total(4), BombCatDeck.defuse_total(5), BombCatDeck.defuse_total(6)], [4, 6, 6, 7])
	for n in range(2, 7):
		assert_eq(BombCatDeck.bomb_count(n), n - 1)


func test_total_cards_per_player_count():
	for n in TOTALS:
		assert_eq(BombCatDeck.total_cards(n), TOTALS[n], "%d 人" % n)


func test_deal_gives_four_plus_one_defuse_and_mixes_the_rest():
	for n in range(2, 7):
		var dealt := BombCatDeck.deal(_pids(n), _rng(n * 13))
		var everything: Array = dealt["deck"].duplicate()
		for pid in _pids(n):
			var hand: Array = dealt["hands"][pid]
			assert_eq(hand.size(), OPENING_HAND, "%d 人:开局手牌 5 张" % n)
			assert_eq(_count(hand, C.DEFUSE), 1, "%d 人:手里正好 1 张拆弹" % n)
			assert_eq(_count(hand, C.BOMB), 0, "开局手里没有炸弹")
			everything.append_array(hand)
		assert_eq(everything.size(), TOTALS[n], "%d 人:牌数守恒" % n)
		assert_eq(_count(dealt["deck"], C.BOMB), n - 1, "%d 人:牌堆里 n − 1 张炸弹" % n)
		assert_eq(_count(dealt["deck"], C.DEFUSE), BombCatDeck.defuse_total(n) - n, "%d 人:剩余拆弹放回牌堆" % n)
		assert_eq(dealt["deck"].size(), TOTALS[n] - OPENING_HAND * n)


func test_deal_is_reproducible_with_the_same_seed():
	var a := BombCatDeck.deal(_pids(4), _rng(42))
	var b := BombCatDeck.deal(_pids(4), _rng(42))
	var c := BombCatDeck.deal(_pids(4), _rng(43))
	assert_eq(a, b, "同一种子同一结果")
	assert_ne(a["deck"], c["deck"], "换种子牌堆顺序不同")


func test_bombs_are_mixed_in_not_stacked_at_the_bottom():
	# 炸弹混入后又洗了一次:多个种子里总有炸弹不在最底下几张
	var tops := 0
	for seed_value in 20:
		var deck: Array = BombCatDeck.deal(_pids(3), _rng(seed_value))["deck"]
		if deck.slice(0, deck.size() - 2).has(C.BOMB):
			tops += 1
	assert_gt(tops, 10)


func test_shuffle_keeps_the_multiset():
	var cards := BombCatDeck.action_pile(5)
	var before := cards.duplicate()
	BombCatDeck.shuffle(cards, _rng(1))
	assert_ne(cards, before)
	cards.sort()
	before.sort()
	assert_eq(cards, before)


func test_every_card_has_an_original_name_and_description():
	for id in C.ALL:
		assert_ne(C.display_name(id), C.UNKNOWN_NAME, id)
		assert_ne(C.description(id), "", id)
	assert_eq(C.display_name(C.PASS_TURNS), "甩锅")
	assert_eq(C.display_name(C.NOPE), "不行!")
	assert_eq(C.display_name("bogus"), C.UNKNOWN_NAME)


func test_card_predicates():
	for id in C.SNACKS:
		assert_true(C.is_snack(id))
		assert_false(C.is_playable(id), "零食单张不能打")
	for id in [C.BOMB, C.DEFUSE, C.NOPE]:
		assert_false(C.is_playable(id), id)
	for id in [C.SKIP, C.PASS_TURNS, C.PEEK, C.SHUFFLE, C.BEG]:
		assert_true(C.is_playable(id), id)
	assert_true(C.needs_target(C.BEG))
	assert_false(C.can_be_named(C.BOMB))
	assert_true(C.can_be_named(C.DEFUSE))
	for value in [null, 3, "", "BOMB", ["skip"]]:
		assert_false(C.is_valid(value), str(value))
		assert_false(C.can_be_named(value), str(value))


func test_game_mode_cap_matches_the_deck_table():
	assert_eq(GameMode.max_players(GameMode.BOMB_CAT), BombCatDeck.MAX_PLAYERS)
	assert_eq(GameMode.min_players(GameMode.BOMB_CAT), BombCatDeck.MIN_PLAYERS)
