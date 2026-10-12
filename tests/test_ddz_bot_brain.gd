extends GutTest
# 斗地主机器人的内置策略:拆牌手数、叫分、自由出牌、跟牌、炸弹;三个机器人对打很多手不卡死、分数守恒、每步都合法。


const D := preload("res://tests/ddz_helpers.gd")
const H := preload("res://src/core/dou_dizhu/ddz_hand.gd")
const NAMES := {1: "甲", 2: "乙", 3: "丙"}
const STEADY := 0


var rng := RandomNumberGenerator.new()


func before_each():
	rng.seed = 42


func _sit(s: DdzState, pid: int) -> Dictionary:
	return DdzBotBrain.situation(DouDizhuViews.public_view(s, NAMES), DouDizhuViews.private_view(s, pid), pid)


func _decide(s: DdzState, pid: int, style := STEADY) -> Dictionary:
	return DdzBotBrain.decide(_sit(s, pid), DdzBotBrain.style(style), rng)


func _labels(choice: Dictionary) -> String:
	return DdzBotPrompt.rank_labels(choice.get("cards", []))


func _deal(texts: Dictionary) -> Dictionary:
	# {pid: "3 3 K"} → {pid: [牌 id]}:同点数的牌各家依次取不同花色,不会两家拿到同一张
	var used := {}
	var out := {}
	for pid in texts:
		var cards := []
		for tok in texts[pid].split(" ", false):
			if tok == "SJ" or tok == "BJ":
				cards.append(H.SMALL_JOKER if tok == "SJ" else H.BIG_JOKER)
				continue
			var r: int = D.TOKENS[tok]
			var k: int = used.get(r, 0)
			assert(k < 4, "同点数最多 4 张")
			used[r] = k + 1
			cards.append(H.make(r, k))
		out[pid] = cards
	return out


func _turns(text: String) -> int:
	return DdzBotBrain.turns(H.rank_counts(D.cards(text)))


# —— 拆牌手数 ——

func test_turns_counts_the_plays_needed_to_empty_a_hand():
	assert_eq(_turns("3 4 5 6 7"), 1, "顺子一手")
	assert_eq(_turns("3 3 3 4"), 1, "三带一一手")
	assert_eq(_turns("3 3 3 4 4 4 5 6"), 1, "飞机带两单一手")
	assert_eq(_turns("3 5 7 9 J"), 5, "五个散单")
	assert_eq(_turns("3 3 4 4 5 5 K"), 2, "连对 + 单张")
	assert_eq(_turns("SJ BJ 2 2 2 2"), 2, "王炸 + 炸弹")
	assert_eq(_turns("3 4 5 6 7 8 8 9 9"), 3, "顺子 3–7 带走单张后剩对 8 对 9 更好(或 3–9 顺子 + 8 + 9)")


func test_hand_strength_rewards_jokers_twos_and_bombs():
	var weak := DdzBotBrain.hand_strength(D.cards("3 4 5 7 8 9 9 10 J Q Q K 4 6 6 8 J"))
	var strong := DdzBotBrain.hand_strength(D.cards("SJ BJ 2 2 2 A A K K Q 3 3 3 3 4 5 6"))
	assert_lt(weak, DdzBotBrain.BID_THRESHOLDS[0], "散牌不叫")
	assert_gt(strong, DdzBotBrain.BID_THRESHOLDS[2], "王炸、三个 2、炸弹叫 3 分")


# —— 叫分 ——

func test_strong_hands_bid_three_and_weak_hands_pass():
	var s := D.new_state()
	var pid: int = s.current_pid
	s.hands[pid] = D.cards("SJ BJ 2 2 2 A A K K Q 3 3 3 3 4 5 6")
	assert_eq(_decide(s, pid), {"kind": "bid", "score": 3})
	s.hands[pid] = D.cards("3 4 5 7 8 9 9 10 J Q Q K 4 6 6 8 J")
	assert_eq(_decide(s, pid), {"kind": "bid", "score": 0})


func test_bids_never_go_below_what_is_already_on_the_table():
	var s := D.new_state()
	var first: int = s.current_pid
	s.bid(first, 2)
	var pid: int = s.current_pid
	s.hands[pid] = D.cards("BJ 2 2 A K Q J 10 9 8 7 6 5 4 3 3 3")   # 大概叫 1–2 分的牌
	var choice := _decide(s, pid)
	assert_true(s.bid_options(pid).has(choice["score"]), "只叫可选的分(比 2 分低就不叫)")
	assert_true(s.bid(pid, choice["score"])["ok"])


# —— 出牌 ——

func test_finishes_the_hand_when_one_play_empties_it():
	var s := D.new_state()
	D.rig_play(s, _deal({1: "5 5 5 9 9", 2: "3 4", 3: "6 7"}), 1, 1)
	assert_eq(_labels(_decide(s, 1)), "5 5 5 9 9", "三带一对一把走完")


func test_free_lead_sheds_a_low_multi_card_group_and_keeps_control():
	var s := D.new_state()
	D.rig_play(s, _deal({1: "3 4 5 6 7 9 9 K 2 BJ", 2: "8 8 8 8 10 10 J J Q Q A A 2 2 SJ",
		3: "3 4 5 6 7 9 10 J Q K A"}), 1, 1)
	var choice := _decide(s, 1)
	assert_eq(choice["kind"], "play")
	assert_eq(_labels(choice), "3 4 5 6 7", "先出顺子,不拆、不动 2 和大王")


func test_free_lead_keeps_bombs_instead_of_four_with_two():
	var s := D.new_state()
	D.rig_play(s, _deal({1: "5 K A A A A 9 9 J", 2: "3 4 6 7 8 10", 3: "3 4 6 7 8 10"}), 1, 1)
	var choice := _decide(s, 1)
	assert_ne(_labels(choice), "5 K A A A A", "不把炸弹拆成四带二")
	assert_false(choice["cards"].has(H.make(11, 0)) and choice["cards"].size() < 4, "也不拆开炸弹出单张")


func test_free_lead_avoids_small_singles_when_an_enemy_has_one_card():
	var s := D.new_state()
	D.rig_play(s, _deal({1: "3 9 9 K", 2: "5", 3: "6 7 8 10 J"}), 1, 1)
	var choice := _decide(s, 1)
	assert_ne(_labels(choice), "3", "农民只剩一张:不出小单张")
	assert_eq(_labels(choice), "9 9", "出对子")


func test_farmer_feeds_the_teammate_with_one_card_left():
	# 地主 3,农民 1、2;1 的下家是 2(队友),只剩一张
	var s := D.new_state()
	D.rig_play(s, _deal({1: "3 9 9 K K", 2: "5", 3: "6 7 8 10 J Q"}), 3, 1)
	assert_eq(_labels(_decide(s, 1)), "3", "喂最小的单张给队友")


func test_does_not_beat_the_teammate():
	var s := D.new_state()
	D.rig_play(s, _deal({1: "4 6 8 10 Q K A", 2: "3 5 7 9 J Q K A", 3: "3 4 5 6 7 8 9 10 J"}), 3, 2)
	assert_true(s.play(2, [0])["ok"], "农民 2 出单 3")
	assert_eq(s.current_pid, 3)
	assert_true(s.pass_turn(3)["ok"], "地主不出")
	assert_eq(_decide(s, 1), {"kind": "pass"}, "队友的牌不压")


func test_beats_the_enemy_cheaply_and_keeps_bombs():
	var s := D.new_state()
	D.rig_play(s, _deal({1: "4 6 6 9 9 J J 5 5 5 5 K", 2: "3 3 7 8 10 Q Q A A",
		3: "3 4 6 7 8 9 10 J"}), 1, 2)
	assert_true(s.play(2, [0, 1])["ok"], "农民出对 3")
	assert_true(s.pass_turn(3)["ok"])
	var choice := _decide(s, 1)
	assert_eq(_labels(choice), "6 6", "用最小的对子压,不拆炸弹")


func test_bombs_when_the_enemy_is_about_to_win():
	var s := D.new_state()
	D.rig_play(s, _deal({1: "4 6 8 5 5 5 5", 2: "3 4 6 7 8 9 10 J Q K", 3: "2 K K"}), 3, 3)
	assert_true(s.play(3, [2])["ok"], "地主出单 2,还剩两张")
	var choice := _decide(s, 1)
	assert_eq(_labels(choice), "5 5 5 5", "地主快走完了:炸")


func test_passes_when_nothing_beats_the_lead():
	var s := D.new_state()
	D.rig_play(s, _deal({1: "3 4", 2: "5 6 7", 3: "BJ 8 9"}), 3, 3)
	assert_true(s.play(3, [2])["ok"], "地主出大王")
	assert_eq(_decide(s, 1), {"kind": "pass"})


func test_not_my_turn_means_no_decision():
	var s := D.new_state()
	var other: int = s.next_pid(s.current_pid)
	assert_eq(_decide(s, other), {})


func test_fallback_is_always_legal():
	var s := D.new_state()
	var pid: int = s.current_pid
	assert_eq(DdzBotBrain.fallback(_sit(s, pid)), {"kind": "bid", "score": 0})
	D.rig_play(s, _deal({1: "4 6 8", 2: "3 5", 3: "7 9"}), 1, 1)
	assert_eq(DdzBotBrain.fallback(_sit(s, 1)), {"kind": "play", "cards": [s.hands[1][0]]}, "自由出牌出最小单张")


# —— 三个机器人对打 ——

func _apply(s: DdzState, pid: int, choice: Dictionary) -> Dictionary:
	match choice["kind"]:
		"bid":
			return s.bid(pid, choice["score"])
		"pass":
			return s.pass_turn(pid)
	return s.play(pid, DdzState.indices_of(s.hands[pid], choice["cards"]))


func test_three_bots_play_many_hands_legally_and_scores_sum_to_zero():
	for seed_value in [1, 2, 3, 4, 5, 6, 7, 8]:
		var s := D.new_state(seed_value)
		var hands_done := 0
		var steps := 0
		while hands_done < 4 and steps < 2000:
			steps += 1
			if s.phase == DdzState.Phase.BETWEEN:
				hands_done += 1
				s.start_hand()
				continue
			var pid: int = s.current_pid
			var choice := _decide(s, pid, seed_value)
			assert_false(choice.is_empty(), "轮到自己总有动作")
			var result := _apply(s, pid, choice)
			assert_true(result["ok"], "种子 %d 第 %d 步不合法:%s %s" % [seed_value, steps, str(choice), result.get("error", "")])
			if not result["ok"]:
				return
			assert_eq(s.card_count(), H.CARD_COUNT)
		assert_eq(hands_done, 4, "种子 %d:每手都能打完" % seed_value)
		var total := 0
		for pid in s.seat_order:
			total += s.scores[pid]
		assert_eq(total, 0, "分数守恒")
