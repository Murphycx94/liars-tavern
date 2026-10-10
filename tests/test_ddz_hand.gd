extends GutTest
# 斗地主牌型(DdzHand):牌编号、全部牌型的识别(含各种带牌与非法组合)、多种读法、比较规则、
# 列出能出的组合(提示 / 托管),并用穷举子集核对 legal_plays 与 analyze / match_lead 一致。


const D := preload("res://tests/ddz_helpers.gd")
const H := preload("res://src/core/dou_dizhu/ddz_hand.gd")


func _c(text: String) -> Array:
	return D.cards(text)


# —— 牌 ——

func test_card_numbering():
	assert_eq(H.full_deck().size(), 54)
	assert_eq(H.rank(0), 0, "0 = ♠3")
	assert_eq(H.suit(0), 0)
	assert_eq(H.rank(51), H.RANK_TWO, "51 = ♣2")
	assert_eq(H.rank(H.SMALL_JOKER), H.RANK_SMALL_JOKER)
	assert_eq(H.rank(H.BIG_JOKER), H.RANK_BIG_JOKER)
	assert_eq(H.suit(H.BIG_JOKER), -1)
	assert_eq(H.label(H.make(7, 1)), "10♥")
	assert_eq(H.labels([H.make(11, 0), H.SMALL_JOKER, H.BIG_JOKER]), "A♠ 小王 大王")
	for c in range(53):
		assert_lte(H.rank(c), H.rank(c + 1), "牌 id 升序就是点数升序")
	assert_true(H.is_card(0) and H.is_card(53))
	for bad in [-1, 54, "3", 1.0, null]:
		assert_false(H.is_card(bad), str(bad))


func test_poker_face_mapping():
	assert_eq(H.poker_card(H.make(0, 0)), PokerCard.make(3, PokerCard.SPADES))
	assert_eq(H.poker_card(H.make(11, 3)), PokerCard.make(PokerCard.ACE, PokerCard.CLUBS))
	assert_eq(H.poker_card(H.make(H.RANK_TWO, 1)), PokerCard.make(2, PokerCard.HEARTS))
	assert_eq(H.poker_card(H.SMALL_JOKER), -1)
	var seen := {}
	for c in 52:
		seen[H.poker_card(c)] = true
	assert_eq(seen.size(), 52, "52 张一一对应德州牌面")


# —— 识别:合法牌型 ——

func test_every_combo_type_is_recognised():
	# [牌, 型, 点数(rank 下标), 组数]
	var cases := [
		["3", H.SINGLE, 0, 1], ["BJ", H.SINGLE, 14, 1], ["2", H.SINGLE, 12, 1],
		["5 5", H.PAIR, 2, 1], ["2 2", H.PAIR, 12, 1],
		["K K K", H.TRIPLE, 10, 1],
		["9 9 9 3", H.TRIPLE_SINGLE, 6, 1], ["3 9 9 9", H.TRIPLE_SINGLE, 6, 1], ["2 2 2 SJ", H.TRIPLE_SINGLE, 12, 1],
		["9 9 9 3 3", H.TRIPLE_PAIR, 6, 1], ["A A 2 2 2", H.TRIPLE_PAIR, 12, 1],
		["3 4 5 6 7", H.STRAIGHT, 0, 5], ["10 J Q K A", H.STRAIGHT, 7, 5], ["3 4 5 6 7 8 9 10 J Q K A", H.STRAIGHT, 0, 12],
		["3 3 4 4 5 5", H.PAIR_STRAIGHT, 0, 3], ["Q Q K K A A", H.PAIR_STRAIGHT, 9, 3],
		["3 3 4 4 5 5 6 6 7 7 8 8 9 9 10 10 J J Q Q", H.PAIR_STRAIGHT, 0, 10],
		["3 3 3 4 4 4", H.AIRPLANE, 0, 2], ["K K K A A A", H.AIRPLANE, 10, 2],
		["3 3 3 4 4 4 5 5 5 6 6 6 7 7 7 8 8 8", H.AIRPLANE, 0, 6],
		["3 3 3 4 4 4 9 J", H.AIRPLANE_SINGLE, 0, 2], ["3 3 3 4 4 4 SJ 2", H.AIRPLANE_SINGLE, 0, 2],
		["5 5 5 6 6 6 7 7 7 3 3 9", H.AIRPLANE_SINGLE, 2, 3],
		["3 3 3 4 4 4 5 5 5 6 6 6 7 7 7 8 9 10 J Q", H.AIRPLANE_SINGLE, 0, 5],
		["3 3 3 4 4 4 9 9 J J", H.AIRPLANE_PAIR, 0, 2], ["J J J Q Q Q K K K 3 3 5 5 2 2", H.AIRPLANE_PAIR, 8, 3],
		["6 6 6 6 3 9", H.FOUR_TWO_SINGLE, 3, 1], ["6 6 6 6 3 3", H.FOUR_TWO_SINGLE, 3, 1], ["2 2 2 2 SJ 3", H.FOUR_TWO_SINGLE, 12, 1],
		["6 6 6 6 3 3 9 9", H.FOUR_TWO_PAIR, 3, 1],
		["7 7 7 7", H.BOMB, 4, 1], ["2 2 2 2", H.BOMB, 12, 1],
		["SJ BJ", H.ROCKET, 14, 1],
	]
	for case in cases:
		var k := D.kind(case[0])
		assert_eq([k.get("type"), k.get("rank"), k.get("length"), k.get("count")],
			[case[1], case[2], case[3], _c(case[0]).size()], case[0])


func test_wings_may_repeat_or_use_a_fourth_card():
	# 飞机带单:翅膀可以同点、可以是机身某组的第 4 张(落地规则)
	assert_eq(D.kind("3 3 3 4 4 4 5 5")["type"], H.AIRPLANE_SINGLE, "翅膀是一对也行")
	assert_eq(D.kind("3 3 3 3 4 4 4 5")["type"], H.AIRPLANE_SINGLE, "翅膀用机身的第 4 张")
	var both := D.kind("3 3 3 3 4 4 4 4")
	assert_eq([both["type"], both["rank"]], [H.AIRPLANE_SINGLE, 0], "两个炸弹拆成 33344 4 + 3 4")


# —— 识别:非法组合 ——

func test_invalid_sets_are_rejected():
	var bad := [
		"3 4", "3 3 4", "3 3 3 4 4 4 5",                # 杂牌
		"SJ SJ", "3 SJ",                                 # 王不成对(同一张王只有一张,"SJ SJ" 会被当成重复)
		"J Q K A 2", "10 J Q K A 2", "K A 2 SJ BJ",     # 顺子不含 2 和王
		"3 4 5 6", "3 4 5 6 8",                          # 不够 5 张 / 不连
		"3 3 4 4", "3 3 4 4 6 6", "K K A A 2 2",        # 连对至少 3 对、要连、不含 2
		"3 3 3 3 4", "3 3 3 3 4 4 4",                    # 炸弹不能带一张
		"A A A 2 2 2", "A A A 2 2 2 3 4",               # 飞机不含 2
		"3 3 3 5 5 5", "3 3 3 5 5 5 7 8",               # 飞机要连
		"3 3 3 4 4 4 9", "3 3 3 4 4 4 9 J Q",           # 翅膀数量不对
		"3 3 3 4 4 4 SJ BJ",                             # 翅膀不能是王炸
		"3 3 3 4 4 4 9 9 J",                             # 带对不能混单
		"3 3 3 4 4 4 9 9 9 9",                           # 带对要两个不同的对子
		"6 6 6 6 SJ BJ",                                 # 四带二不能带王炸
		"6 6 6 6 3 3 3 3",                               # 四带两对要不同的对子
		"6 6 6 6 3 9 9",                                 # 四带不成型
		"3 3 3 SJ BJ",                                   # 三带不能带两张单
	]
	for text in bad:
		assert_eq(D.kind(text), {}, text)
	assert_eq(H.classify([]), {})
	assert_eq(H.classify([0, 0]), {}, "重复的牌")
	assert_eq(H.classify([0, 54]), {}, "越界")
	assert_eq(H.analyze(["3"]), [], "不是牌 id")


# —— 多种读法 ——

func test_ambiguous_sets_list_every_reading():
	var readings := H.analyze(_c("3 3 3 4 4 4 5 5 5 6 6 6"))
	var types := readings.map(func(k: Dictionary) -> Array: return [k["type"], k["rank"], k["length"]])
	assert_eq(types, [[H.AIRPLANE, 0, 4], [H.AIRPLANE_SINGLE, 1, 3], [H.AIRPLANE_SINGLE, 0, 3]])
	assert_eq(D.kind("3 3 3 4 4 4 5 5 5 6 6 6")["type"], H.AIRPLANE, "自由出牌按优先级取 4 连飞机")
	var lead := H.combo(H.AIRPLANE_SINGLE, 0, 3, 12)
	var m := H.match_lead(_c("3 3 3 4 4 4 5 5 5 6 6 6"), lead)
	assert_eq([m["type"], m["rank"], m["length"]], [H.AIRPLANE_SINGLE, 1, 3], "跟牌时换成能压过的读法(点数最大的)")
	assert_eq(H.match_lead(_c("3 3 3 4 4 4 5 5 5 6 6 6"), H.combo(H.AIRPLANE_SINGLE, 1, 3, 12)), {}, "同点数压不过")


func test_four_twos_vs_airplane_reading():
	assert_eq(D.kind("4 4 4 4 5 5 6 6")["type"], H.FOUR_TWO_PAIR)
	var m := H.match_lead(_c("4 4 4 4 5 5 5 6"), H.combo(H.AIRPLANE_SINGLE, 0, 2, 8))
	assert_eq([m["type"], m["rank"]], [H.AIRPLANE_SINGLE, 1], "444 555 + 4 6")


# —— 比较 ——

func test_same_type_compares_rank_and_length():
	assert_true(H.beats(D.kind("4"), D.kind("3")))
	assert_false(H.beats(D.kind("3"), D.kind("3")), "一样大压不过")
	assert_true(H.beats(D.kind("2"), D.kind("A")), "2 比 A 大")
	assert_true(H.beats(D.kind("SJ"), D.kind("2")))
	assert_true(H.beats(D.kind("BJ"), D.kind("SJ")))
	assert_true(H.beats(D.kind("4 5 6 7 8"), D.kind("3 4 5 6 7")))
	assert_false(H.beats(D.kind("4 5 6 7 8 9"), D.kind("3 4 5 6 7")), "顺子长度要一样")
	assert_false(H.beats(D.kind("9 9 9 3 3"), D.kind("8 8 8 3")), "三带一对压不了三带一")
	assert_false(H.beats(D.kind("9 9"), D.kind("8")), "对子压不了单张")
	assert_true(H.beats(D.kind("4 4 4 5 5 5 3 3 7 7"), D.kind("3 3 3 4 4 4 9 9 J J")))
	assert_false(H.beats(D.kind("4 4 4 5 5 5 3 7"), D.kind("3 3 3 4 4 4 9 9 J J")), "带单压不了带对")


func test_bombs_and_rocket():
	var bomb3 := D.kind("3 3 3 3")
	var bomb2 := D.kind("2 2 2 2")
	var rocket := D.kind("SJ BJ")
	for text in ["2", "A A", "K K K 3", "3 4 5 6 7 8 9 10 J Q K A", "3 3 3 4 4 4 5 5 5 6 6 6 7 7 7 8 9 10 J Q",
			"2 2 2 2 SJ 3"]:
		assert_true(H.beats(bomb3, D.kind(text)), "炸弹压 " + text)
		assert_false(H.beats(D.kind(text), bomb3), text + " 压不了炸弹")
	assert_true(H.beats(bomb2, bomb3), "炸弹之间比点数")
	assert_false(H.beats(bomb3, bomb2))
	assert_true(H.beats(rocket, bomb2), "王炸最大")
	assert_false(H.beats(bomb2, rocket))
	assert_false(H.beats(rocket, rocket))
	assert_false(H.beats({}, bomb3))
	assert_true(H.is_bomb_like(bomb3) and H.is_bomb_like(rocket))
	assert_false(H.is_bomb_like(D.kind("6 6 6 6 3 9")), "四带二不是炸弹")


# —— 列出能出的组合 ——

func test_following_lists_beating_combos_smallest_first():
	var hand := _c("3 5 5 8 9 9 9 9 SJ BJ")
	var plays := H.legal_plays(hand, D.kind("4"))
	var labels := plays.map(func(p: Dictionary) -> String: return H.labels(p["cards"]))
	assert_eq(labels, ["5♠", "8♠", "9♠", "小王", "大王", "9♠ 9♥ 9♦ 9♣", "小王 大王"], "同型按点数,其后炸弹、王炸")
	for p in plays:
		assert_false(H.match_lead(p["cards"], D.kind("4")).is_empty(), H.labels(p["cards"]))


func test_following_a_bomb_needs_a_bigger_bomb_or_the_rocket():
	var hand := _c("3 3 3 3 K K K K SJ BJ")
	var plays := H.legal_plays(hand, D.kind("5 5 5 5"))
	assert_eq(plays.map(func(p: Dictionary) -> String: return p["type"] + str(p["rank"])), ["bomb10", "rocket14"])
	assert_eq(H.legal_plays(hand, D.kind("SJ BJ")), [], "王炸没人压得了")


func test_wings_prefer_loose_cards_and_never_split_the_rocket():
	var hand := _c("3 3 3 4 4 4 7 7 9 SJ BJ")
	var plays := H.legal_plays(hand, D.kind("A"))
	assert_false(plays.is_empty())
	var winged := _of_type(H.legal_plays(hand, H.combo(H.AIRPLANE_SINGLE, -1, 2, 8)), H.AIRPLANE_SINGLE)
	assert_eq(winged.size(), 1)
	assert_eq(H.labels(winged[0]["cards"]), "3♠ 3♥ 3♦ 4♠ 4♥ 4♦ 9♠ 小王", "先用单出的 9,再用一张王;不拆对子 7")
	var tight := _c("3 3 3 4 4 4 SJ BJ")
	assert_eq(_of_type(H.legal_plays(tight, H.combo(H.AIRPLANE_SINGLE, -1, 2, 8)), H.AIRPLANE_SINGLE), [],
		"只剩王炸当翅膀:不行(王炸本身照样能压)")
	var one := H.legal_plays(_c("8 8 8 SJ BJ"), H.combo(H.TRIPLE_SINGLE, 0, 1, 4))
	assert_eq(H.labels(one[0]["cards"]), "8♠ 8♥ 8♦ 小王")


func _of_type(plays: Array, type: String) -> Array:
	return plays.filter(func(p: Dictionary) -> bool: return p["type"] == type)


func test_free_lead_starts_low_and_keeps_bombs_last():
	var hand := _c("3 4 5 6 7 7 7 7 K SJ BJ")
	var plays := H.legal_plays(hand, {})
	assert_eq(plays[0]["type"], H.STRAIGHT, "同点数先给张数多的:3–7 顺子")
	assert_eq(plays[0]["rank"], 0)
	assert_eq(plays[-1]["type"], H.ROCKET)
	assert_eq(plays[-2]["type"], H.BOMB)
	var seen_bomb := false
	for p in plays:
		if H.is_bomb_like(p):
			seen_bomb = true
		else:
			assert_false(seen_bomb, "炸弹之后不再有普通牌型")
	for p in plays:
		var k := H.classify(p["cards"])
		assert_false(k.is_empty(), H.labels(p["cards"]))
	assert_eq(H.smallest_single(hand), H.make(0, 0))


func test_legal_plays_match_brute_force_on_random_hands():
	# 穷举手牌的每个子集:能压过 lead 的每种(型, 点数, 组数)都要在 legal_plays 里有代表,反过来 legal_plays 每项都合法
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var leads := [{}, D.kind("7"), D.kind("5 5"), D.kind("4 4 4 3"), D.kind("3 4 5 6 7"), D.kind("3 3 4 4 5 5"),
		D.kind("8 8 8 8"), H.combo(H.AIRPLANE_SINGLE, 0, 2, 8), D.kind("3 3 3 3 4 5")]
	for round in 120:
		var deck := H.full_deck()
		for i in range(deck.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = deck[i]
			deck[i] = deck[j]
			deck[j] = t
		# 偏向成组的牌:从 4 个点数里挑,子集更容易成型
		var size := rng.randi_range(6, 11)
		var ranks := [rng.randi_range(0, 11), rng.randi_range(0, 11), rng.randi_range(0, 12), rng.randi_range(0, 12)]
		var hand := deck.filter(func(c: int) -> bool: return ranks.has(H.rank(c)) or c >= H.SMALL_JOKER).slice(0, size)
		if hand.size() < size:
			hand.append_array(deck.filter(func(c: int) -> bool: return not hand.has(c)).slice(0, size - hand.size()))
		var readings := []   # 每个子集的全部读法(只算一次,各个 lead 共用)
		for mask in range(1, 1 << hand.size()):
			var subset := []
			for i in hand.size():
				if mask & (1 << i):
					subset.append(hand[i])
			readings.append_array(H.analyze(subset))
		for lead in leads:
			_check_against_brute_force(hand, lead, readings)


func _check_against_brute_force(hand: Array, lead: Dictionary, readings: Array) -> void:
	var expected := {}
	for k in readings:
		if lead.is_empty() or H.beats(k, lead):
			expected["%s/%d/%d" % [k["type"], k["rank"], k["length"]]] = true
	var got := {}
	for p in H.legal_plays(hand, lead):
		got["%s/%d/%d" % [p["type"], p["rank"], p["length"]]] = true
		assert_false(H.match_lead(p["cards"], lead).is_empty(), "%s 能出(%s)" % [H.labels(p["cards"]), str(lead)])
		for c in p["cards"]:
			assert_true(hand.has(c))
	assert_eq(got.keys().filter(func(k: String) -> bool: return not expected.has(k)), [], "多出的 " + H.labels(hand))
	assert_eq(expected.keys().filter(func(k: String) -> bool: return not got.has(k)), [],
		"漏掉的 %s vs %s" % [H.labels(hand), str(lead)])
