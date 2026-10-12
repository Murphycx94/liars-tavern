extends GutTest
# 说明书的 21 点那本:21 点房间翻开的就是这本、章节齐全、块类型都认识、数字跟着规则常量走、
# 算点示例和 BjScore 算出来的一样、bj_hands 块渲染得出来、操作章的快捷键和牌桌控件一致。


const BOOK := RulebookContent.BOOK_BLACKJACK


func _text_of(section: Dictionary) -> String:
	var parts := []
	for block in section.get("blocks", []):
		for key in ["text", "note"]:
			if block.has(key):
				parts.append(str(block[key]))
		for item in block.get("items", []):
			parts.append(str(item))
	return "\n".join(parts)


func test_blackjack_mode_opens_this_book():
	assert_eq(RulebookContent.book_for_mode(GameMode.BLACKJACK), BOOK)
	assert_eq(RulebookContent.book_title(BOOK), "21 点")
	assert_has(RulebookContent.BOOKS, BOOK)


func test_chapters_and_block_types():
	var ids := RulebookContent.sections(BOOK).map(func(s): return s["id"])
	assert_eq(ids, ["goal", "points", "round", "actions", "payout", "session", "controls"])
	for section in RulebookContent.sections(BOOK):
		assert_true(section["title"] != "" and section["tagline"] != "", section["id"])
		for block in section["blocks"]:
			assert_has(RulebookContent.BLOCK_TYPES, block["type"])


func test_numbers_follow_the_rule_constants():
	assert_string_contains(_text_of(RulebookContent.find("goal", BOOK)), "1–7 人")
	assert_string_contains(_text_of(RulebookContent.find("goal", BOOK)), ChipText.format(BjRules.STARTING_STACK))
	var round_text := _text_of(RulebookContent.find("round", BOOK))
	assert_string_contains(round_text, "%d 秒" % int(BlackjackPacing.BET_TIMEOUT))
	assert_string_contains(round_text, "%d 秒" % int(BlackjackPacing.PLAY_TIMEOUT))
	assert_string_contains(round_text, "%s–%s" % [ChipText.format(BjRules.MIN_BET), ChipText.format(BjRules.MAX_BET)])
	assert_string_contains(_text_of(RulebookContent.find("actions", BOOK)), "最多分成 %d 手" % BjRules.MAX_HANDS)
	assert_string_contains(_text_of(RulebookContent.find("points", BOOK)), "%d 副牌" % BjRules.DECKS)


func test_example_totals_match_the_scorer():
	var items: Array = RulebookBlackjack.example_hands()["items"]
	assert_true(BjScore.is_natural(items[0]["cards"]))
	assert_eq(BjScore.label(items[1]["cards"]), items[1]["total"])
	assert_eq(BjScore.label(items[2]["cards"]), items[2]["total"])
	assert_true(BjScore.is_bust(items[3]["cards"]))
	var view: Control = autofree(RulebookBlocks.build(RulebookBlackjack.example_hands()))
	var faces := view.find_children("*", "TextureRect", true, false)
	assert_eq(faces.size(), 2 + 2 + 3 + 3, "每张示例牌一个小牌面")


func test_controls_match_the_table_hotkeys():
	var keys: Array = RulebookContent.find("controls", BOOK)["blocks"][0]["items"]
	var by_action := {}
	for item in keys:
		by_action[item["action"]] = item["keys"]
	assert_eq(BjControls.play_hotkey(KEY_SPACE), BjRules.HIT)
	assert_has(by_action["要牌"], "空格")
	assert_eq(BjControls.play_hotkey(KEY_ENTER), BjRules.STAND)
	assert_has(by_action["停牌"], "Enter")
	assert_eq(BjControls.bet_hotkey(KEY_R), {"kind": "repeat"})
	assert_has(by_action["按上一局的注再下"], "R")
	assert_eq(BjControls.bet_hotkey(KEY_N), {"kind": "skip"})
	assert_has(by_action["这局不玩"], "N")
