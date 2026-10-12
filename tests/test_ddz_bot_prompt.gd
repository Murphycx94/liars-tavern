extends GutTest
# 斗地主机器人的 AI 提示词与回答解析:提示词只含机器人看得到的东西;回答里的点数换成手里的牌,
# 手里没有的、不成牌型的、压不过的、自由出牌说不出的都判无效。


const D := preload("res://tests/ddz_helpers.gd")
const H := preload("res://src/core/dou_dizhu/ddz_hand.gd")
const NAMES := {1: "甲", 2: "乙", 3: "丙"}


func _sit(s: DdzState, pid: int) -> Dictionary:
	return DdzBotBrain.situation(DouDizhuViews.public_view(s, NAMES), DouDizhuViews.private_view(s, pid), pid)


func _play_state() -> DdzState:
	# 地主 1 自由出牌;手牌两两不撞
	var s := D.new_state()
	D.rig_play(s, {1: [H.make(0, 0), H.make(0, 1), H.make(0, 2), H.make(8, 0), H.make(7, 0), H.BIG_JOKER],
		2: [H.make(1, 0), H.make(2, 0)], 3: [H.make(3, 0), H.make(4, 0)]}, 1, 1)
	return s


# —— 提示词 ——

func test_user_prompt_shows_my_hand_and_counts_but_not_other_hands():
	var s := _play_state()
	var sit := _sit(s, 1)
	var text := DdzBotPrompt.user_prompt(sit, DouDizhuViews.public_view(s, NAMES), NAMES, ["甲 叫 3 分"], [])
	assert_string_contains(text, "你的手牌(6 张):3 3 3 10 J 大王")
	assert_string_contains(text, "地主(两个农民一伙对付你)")
	assert_string_contains(text, "乙:农民,剩 2 张(你的下家)")
	assert_string_contains(text, "自由出牌")
	assert_string_contains(text, "甲 叫 3 分")
	# 别人换成同样张数的另一手牌,提示词一字不变:看不到别人的手牌
	var other := D.new_state()
	D.rig_play(other, {1: s.hand_of(1), 2: [H.make(9, 1), H.make(10, 1)], 3: [H.make(11, 1), H.make(12, 1)]}, 1, 1)
	assert_eq(DdzBotPrompt.user_prompt(_sit(other, 1), DouDizhuViews.public_view(other, NAMES), NAMES, ["甲 叫 3 分"], []),
		text)


func test_unseen_cards_are_derived_from_my_hand_and_played_cards():
	var s := _play_state()
	var text := DdzBotPrompt.user_prompt(_sit(s, 1), DouDizhuViews.public_view(s, NAMES), NAMES, [],
		[H.SMALL_JOKER, H.make(12, 0)])
	assert_string_contains(text, "外面还有的牌")
	assert_string_contains(text, "2×3 A×4", "已出一张 2 和小王,剩三张 2")
	assert_false(text.contains("小王 "), "小王出过了")


func test_follow_prompt_names_the_lead_and_lists_options():
	var s := _play_state()
	assert_true(s.play(1, [4])["ok"], "地主出单 J(升序第 5 张)")
	var text := DdzBotPrompt.user_prompt(_sit(s, 2), DouDizhuViews.public_view(s, NAMES), NAMES, [], [])
	assert_string_contains(text, "要压的牌:甲 出的单张 J")
	assert_string_contains(text, "只能 pass", "4 和 5 压不过 J")


func test_bid_prompt_lists_bid_options():
	var s := D.new_state()
	var pid: int = s.current_pid
	var text := DdzBotPrompt.user_prompt(_sit(s, pid), DouDizhuViews.public_view(s, NAMES), NAMES, [], [])
	assert_string_contains(text, "叫分阶段")
	assert_string_contains(text, "可叫:不叫(0)、1 分、2 分、3 分")
	assert_string_contains(DdzBotPrompt.system_prompt("机器人·阿福", "稳健派"), "机器人·阿福")


func test_describe_event_lines():
	assert_eq(DdzBotPrompt.describe_event({"type": "bid", "pid": 1, "score": 0}, NAMES), "甲 不叫")
	assert_eq(DdzBotPrompt.describe_event({"type": "bid", "pid": 2, "score": 2}, NAMES), "乙 叫 2 分")
	var played := {"type": "played", "pid": 3, "cards": [H.make(4, 0), H.make(4, 1), H.make(4, 2), H.make(4, 3)],
		"combo": H.BOMB, "multiplier": 4, "remaining": 5}
	assert_eq(DdzBotPrompt.describe_event(played, NAMES), "丙 出 炸弹 7 7 7 7(剩 5 张),倍数变成 4")
	assert_eq(DdzBotPrompt.describe_event({"type": "passed", "pid": 1}, NAMES), "甲 不出")
	assert_eq(DdzBotPrompt.describe_event({"type": "turn", "pid": 1}, NAMES), "")


# —— 解析 ——

func test_parse_bid():
	var s := D.new_state()
	var sit := _sit(s, s.current_pid)
	var ok := DdzBotPrompt.parse('好的 {"action": "bid", "score": 2, "quip": 3}', sit)
	assert_true(ok["ok"])
	assert_eq(ok["choice"], {"kind": "bid", "score": 2})
	assert_eq(ok["quip"], 3)
	assert_eq(DdzBotPrompt.parse('{"action": "pass"}', sit)["choice"], {"kind": "bid", "score": 0}, "叫分时 pass = 不叫")
	assert_false(DdzBotPrompt.parse('{"action": "bid", "score": 5}', sit)["ok"])
	assert_false(DdzBotPrompt.parse('{"action": "play", "cards": ["3"]}', sit)["ok"], "叫分阶段不能出牌")


func test_parse_play_picks_cards_by_rank():
	var s := _play_state()
	var sit := _sit(s, 1)
	var parsed := DdzBotPrompt.parse('```json\n{"action": "play", "cards": ["3", "3", "3", "J"], "quip": null}\n```', sit)
	assert_true(parsed["ok"], str(parsed))
	assert_eq(parsed["choice"]["cards"], [H.make(0, 0), H.make(0, 1), H.make(0, 2), H.make(8, 0)])
	assert_eq(parsed["quip"], -1)
	assert_eq(DdzBotPrompt.parse('{"action": "play", "cards": "333 10"}', sit)["choice"]["cards"].size(), 4,
		"连着写也认")
	assert_eq(DdzBotPrompt.parse('{"action": "play", "cards": ["大王"]}', sit)["choice"]["cards"], [H.BIG_JOKER])


func test_parse_play_rejects_bad_answers():
	var s := _play_state()
	var sit := _sit(s, 1)
	assert_false(DdzBotPrompt.parse('{"action": "play", "cards": ["2"]}', sit)["ok"], "手里没有 2")
	assert_false(DdzBotPrompt.parse('{"action": "play", "cards": ["3", "J"]}', sit)["ok"], "不成牌型")
	assert_false(DdzBotPrompt.parse('{"action": "pass"}', sit)["ok"], "自由出牌不能不出")
	assert_false(DdzBotPrompt.parse('{"action": "play", "cards": ["Z"]}', sit)["ok"], "认不出的点数")
	assert_false(DdzBotPrompt.parse("我出三个三", sit)["ok"], "没有 JSON")
	assert_false(DdzBotPrompt.parse('{"action": "play", "cards": 3}', sit)["ok"])


func test_parse_play_must_beat_the_lead():
	var s := _play_state()
	assert_true(s.play(1, [4])["ok"], "地主出单 J(升序第 5 张)")
	assert_true(s.pass_turn(2)["ok"])
	var sit := _sit(s, 3)
	assert_false(DdzBotPrompt.parse('{"action": "play", "cards": ["6"]}', sit)["ok"], "6 压不过 J")
	assert_eq(DdzBotPrompt.parse('{"action": "pass"}', sit)["choice"], {"kind": "pass"})


func test_parse_ranks_aliases():
	assert_eq(DdzBotPrompt.parse_ranks(["10♠", "T", "j", "小王", "BJ"]), [7, 7, 8, 13, 14])
	assert_eq(DdzBotPrompt.parse_ranks("JJQQKK"), [8, 8, 9, 9, 10, 10])
	assert_eq(DdzBotPrompt.parse_ranks([2.0]), [12], "数字也认")
	assert_eq(DdzBotPrompt.parse_ranks(["11"]), [], "认不出的整个无效")
