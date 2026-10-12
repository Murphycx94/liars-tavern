extends GutTest
# 接 AI 的机器人:提示词里有该有的东西(自己的手牌、公共牌、可选动作),没有别人的手牌;
# AI 的回答当不可信输入解析:代码块与废话能容忍,动作对到合法动作,金额夹取,看不懂的判无效。


const H := preload("res://tests/poker_helpers.gd")
const R := preload("res://src/core/poker/poker_rules.gd")


func _owe(to_call: int, min_to := 40, max_to := 2000) -> Dictionary:
	return {"to_call": to_call, "call_amount": to_call, "can_check": to_call == 0, "can_raise": true,
		"can_allin": true, "min_raise_to": min_to, "max_raise_to": max_to}


func _view() -> Dictionary:
	# 真实牌桌:机器人 -1 与房主、另一个机器人,轮到谁就以谁的视角写提示词
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var table := PokerTable.new(false, rng)
	for pid in [1, -1, -2]:
		table.seat(pid)
	table.start_hand()
	var names := {1: "房主", -1: "机器人·阿福", -2: "机器人·豆豆"}
	var pub := PokerViews.public_view(table, names, GameMode.HOLDEM, 30.0)
	var me: int = pub["current_pid"]
	return {"table": table, "pub": pub, "me": me, "names": names,
		"sit": PokerBotBrain.situation(pub, PokerViews.private_view(table, me), me)}


func test_user_prompt_has_my_cards_and_options_but_not_others():
	var v := _view()
	var table: PokerTable = v["table"]
	var text := PokerBotPrompt.user_prompt(v["sit"], v["pub"], v["names"], ["房主 下小盲 10"])
	assert_string_contains(text, PokerCard.labels(table.hole_cards(v["me"])))
	assert_string_contains(text, "可选:")
	assert_string_contains(text, "房主 下小盲 10")
	assert_string_contains(text, "(还没发)")
	for pid in [1, -1, -2]:
		if pid != v["me"]:
			for card in table.hole_cards(pid):
				assert_false(text.contains(PokerCard.label(card)), "不泄露 %d 的手牌" % pid)


func test_system_prompt_names_the_bot_and_its_persona():
	var text := PokerBotPrompt.system_prompt("机器人·阿福", "稳健派")
	assert_string_contains(text, "机器人·阿福")
	assert_string_contains(text, "稳健派")
	assert_string_contains(text, "JSON")


func test_events_are_described_for_the_log():
	var names := {7: "老王"}
	assert_eq(PokerBotPrompt.describe_event({"type": "blind", "pid": 7, "kind": "bb", "amount": 20}, names), "老王 下大盲 20")
	assert_eq(PokerBotPrompt.describe_event({"type": "action", "pid": 7, "action": R.RAISE, "amount": 50, "bet": 60,
		"all_in": false}, names), "老王 加注到 60")
	assert_eq(PokerBotPrompt.describe_event({"type": "action", "pid": 7, "action": R.CALL, "amount": 60, "bet": 60,
		"all_in": true}, names), "老王 跟注 60 (全下)")
	assert_string_contains(PokerBotPrompt.describe_event({"type": "street", "street": R.FLOP,
		"board": H.cards("As Kd 2c")}, names), "翻牌")
	assert_eq(PokerBotPrompt.describe_event({"type": "pot_won"}, names), "")


# —— 解析 ——

func test_parses_plain_json_and_code_fences():
	var plain := PokerBotPrompt.parse('{"action": "call"}', _owe(20))
	assert_eq([plain["ok"], plain["action"], plain["quip"]], [true, R.CALL, -1])
	var fenced := PokerBotPrompt.parse("想了想……\n```json\n{\"action\": \"raise\", \"amount\": 120, \"quip\": 4}\n```", _owe(20))
	assert_eq([fenced["action"], fenced["amount"], fenced["quip"]], [R.RAISE, 120, 4])


func test_fold_when_free_becomes_check_and_check_when_owing_is_invalid():
	assert_eq(PokerBotPrompt.parse('{"action": "fold"}', _owe(0))["action"], R.CHECK)
	assert_false(PokerBotPrompt.parse('{"action": "check"}', _owe(20))["ok"])
	assert_eq(PokerBotPrompt.parse('{"action": "call"}', _owe(0))["action"], R.CHECK)


func test_raise_amounts_are_clamped_and_rounded():
	assert_eq(PokerBotPrompt.parse('{"action": "raise", "amount": 5}', _owe(20))["amount"], 40, "太小 → 最小加注")
	assert_eq(PokerBotPrompt.parse('{"action": "raise", "amount": 333}', _owe(20))["amount"], 340)
	assert_eq(PokerBotPrompt.parse('{"action": "raise"}', _owe(20))["amount"], 40, "没给金额 → 最小加注")
	assert_eq(PokerBotPrompt.parse('{"action": "raise", "amount": 99999}', _owe(20))["action"], R.ALLIN)
	assert_eq(PokerBotPrompt.parse('{"action": "raise", "amount": 1e30}', _owe(20))["action"], R.ALLIN, "超大金额不溢出")
	assert_eq(PokerBotPrompt.parse('{"action": "bet", "amount": 100}', _owe(0))["action"], R.RAISE, "bet 当 raise")


func test_raise_without_raise_rights_becomes_a_call():
	var legal := _owe(20).merged({"can_raise": false, "can_allin": false}, true)
	assert_eq(PokerBotPrompt.parse('{"action": "raise", "amount": 100}', legal)["action"], R.CALL)
	assert_eq(PokerBotPrompt.parse('{"action": "allin"}', legal)["action"], R.CALL)


func test_slightly_broken_json_is_salvaged():
	# 实测 gpt-4.1 偶尔多写一个引号
	var broken := PokerBotPrompt.parse('{"action": "raise", "amount": 130", "quip": null}', _owe(20))
	assert_eq([broken["ok"], broken["action"], broken["amount"], broken["quip"]], [true, R.RAISE, 130, -1])
	var quoted := PokerBotPrompt.parse('{"action": "call", "quip": "4",}', _owe(20))
	assert_eq([quoted["action"], quoted["quip"]], [R.CALL, 4])


func test_bad_answers_are_rejected():
	for text in ["我跟", "{不是 json}", '{"amount": 10}', '{"action": "dance"}', '["call"]', '{"action": 3}']:
		assert_false(PokerBotPrompt.parse(text, _owe(20))["ok"], text)


func test_quip_must_be_a_valid_index():
	assert_eq(PokerBotPrompt.parse('{"action": "call", "quip": 99}', _owe(20))["quip"], -1)
	assert_eq(PokerBotPrompt.parse('{"action": "call", "quip": "1"}', _owe(20))["quip"], 1, "字符串编号也认")
	assert_eq(PokerBotPrompt.parse('{"action": "call", "quip": "哇"}', _owe(20))["quip"], -1)
	assert_eq(PokerBotPrompt.parse('{"action": "call", "quip": null}', _owe(20))["quip"], -1)
	assert_eq(PokerBotPrompt.parse('{"action": "call", "quip": 0}', _owe(20))["quip"], 0)
