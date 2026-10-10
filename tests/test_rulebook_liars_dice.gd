extends GutTest
# 说明书的吹牛骰子那本:章节齐全、块类型都认识、数字跟着规则常量走(骰子数、点数范围、人数、限时)、
# 开盅示例的计数与「1 点万能」一致、操作章列出出价器的快捷键(且和牌桌的快捷键一致、不占 T / Q / G / V / WASD / Esc / F1)、
# 吹牛骰子房间翻开的就是这本,而且 dice 块渲染得出来。


const BOOK := RulebookContent.BOOK_LIARS_DICE
const ScreenScript := preload("res://src/ui/liars_dice/liars_dice_screen.gd")


func _text_of(section: Dictionary) -> String:
	var parts := []
	for block in section.get("blocks", []):
		for key in ["text", "note"]:
			if block.has(key):
				parts.append(str(block[key]))
		for item in block.get("items", []):
			parts.append(str(item))
	return "\n".join(parts)


func test_liars_dice_mode_opens_this_book():
	assert_eq(RulebookContent.book_for_mode(GameMode.LIARS_DICE), BOOK)
	assert_eq(RulebookContent.book_title(BOOK), "吹牛骰子")
	assert_has(RulebookContent.BOOKS, BOOK)


func test_chapters_and_block_types():
	var ids := RulebookContent.sections(BOOK).map(func(s): return s["id"])
	assert_eq(ids, ["goal", "round", "bid", "wild", "challenge", "lose", "controls"])
	for section in RulebookContent.sections(BOOK):
		assert_true(section["title"] != "" and section["tagline"] != "", section["id"])
		for block in section["blocks"]:
			assert_has(RulebookContent.BLOCK_TYPES, block["type"])


func test_numbers_follow_the_rule_constants():
	var goal := _text_of(RulebookContent.find("goal", BOOK))
	assert_string_contains(goal, "%d 颗骰子" % LiarsDiceState.DICE_PER_PLAYER)
	assert_string_contains(goal, "%d–%d 人" % [LiarsDiceState.MIN_PLAYERS, LiarsDiceState.MAX_PLAYERS])
	assert_string_contains(_text_of(RulebookContent.find("round", BOOK)), "%d 秒" % int(Protocol.TURN_TIMEOUT))
	assert_string_contains(_text_of(RulebookContent.find("bid", BOOK)), "%d–%d" % [LiarsDiceState.MIN_BID_FACE, LiarsDiceState.FACES])


func test_the_reveal_example_counts_wild_ones():
	# 示例:数「5」,三颗 5 加两颗 1 点 = 5 个;正文写的也是 5 个
	var block := RulebookLiarsDice.example_reveal()
	var all := []
	for item in block["items"]:
		all.append_array(item["dice"])
	assert_eq(LiarsDiceScreenState.count_matches(all, block["face"]), 5)
	assert_string_contains(_text_of(RulebookContent.find("wild", BOOK)), "一共 5 个")
	var view: Control = autofree(RulebookBlocks.build(block))
	var lit := view.find_children("*", "DiceIcon", true, false).filter(func(icon: DiceIcon) -> bool: return icon.highlight)
	assert_eq(lit.size(), 5, "算进去的 5 颗金边高亮")


func test_challenge_chapter_explains_both_verdicts():
	var text := _text_of(RulebookContent.find("challenge", BOOK))
	assert_string_contains(text, "开的人丢一颗骰子")
	assert_string_contains(text, "喊的人丢一颗骰子")


func test_controls_list_the_bid_keys_that_the_table_uses():
	var keys_block: Dictionary = RulebookContent.find("controls", BOOK)["blocks"][0]
	var listed := []
	for item in keys_block["items"]:
		listed.append_array(item["keys"])
	for key in ["↑", "↓", "2–6", "Enter", "C", "空格", "V", "G", "Q", "T", "Esc"]:
		assert_has(listed, key)
	assert_eq(ScreenScript.key_action(KEY_UP), ScreenScript.ACTION_MORE)
	assert_eq(ScreenScript.key_action(KEY_C), ScreenScript.ACTION_CHALLENGE)
	assert_eq(ScreenScript.key_action(KEY_SPACE), ScreenScript.ACTION_CHALLENGE)
	assert_eq(ScreenScript.key_action(KEY_ENTER), ScreenScript.ACTION_BID)
