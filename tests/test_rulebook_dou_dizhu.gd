extends GutTest
# 说明书的斗地主那本:有页签、玩法默认翻到它、章节齐全、块类型都认得;牌型表覆盖全部 14 种牌型且每组示例真的是那种牌型;
# 数字取自规则常量;操作章写着斗地主的快捷键与 T / Q / G / V;牌型小图(德州牌面 + 两张王)能渲染、牌面生成完能重新取。


const BOOK := RulebookContent.BOOK_DOU_DIZHU


func test_book_is_registered_and_picked_for_the_mode():
	assert_has(RulebookContent.BOOKS, BOOK)
	assert_eq(RulebookContent.book_title(BOOK), "斗地主")
	assert_eq(RulebookContent.book_for_mode(GameMode.DOU_DIZHU), BOOK)
	assert_eq(RulebookContent.book_for_mode(GameMode.BOMB_CAT), RulebookContent.BOOK_BOMB_CAT, "其他玩法不变")
	assert_eq(RulebookContent.book_for_mode(GameMode.HOLDEM), RulebookContent.BOOK_POKER)


func test_sections_and_block_types():
	var ids := RulebookContent.sections(BOOK).map(func(s): return s["id"])
	assert_eq(ids, ["goal", "bidding", "play", "combos", "scoring", "session", "controls"])
	for section in RulebookContent.sections(BOOK):
		assert_true(section.has("title") and section.has("tagline"), section["id"])
		for block in section["blocks"]:
			assert_has(RulebookContent.BLOCK_TYPES, block["type"], "%s 的块类型" % section["id"])


func test_combo_table_covers_every_type_with_real_examples():
	var block := RulebookDouDizhu.combos_block()
	assert_eq(block["items"].size(), DdzHand.TYPE_NAMES.size(), "全部牌型")
	var seen := {}
	for item in block["items"]:
		seen[item["type"]] = true
		assert_eq(item["name"], DdzHand.type_name(item["type"]))
		var got := DdzHand.classify(item["cards"])
		assert_eq(got.get("type", ""), item["type"], "%s 的示例真的是这种牌型" % item["name"])
		var unique := {}
		for c in item["cards"]:
			unique[c] = true
		assert_eq(unique.size(), item["cards"].size(), "%s 的示例没有重复的牌" % item["name"])
	assert_eq(seen.size(), DdzHand.TYPE_NAMES.size())
	assert_eq(RulebookDouDizhu.order_cards().size(), DdzHand.RANK_COUNT, "大小顺序一种点数一张")


func test_numbers_come_from_the_rules():
	var text := str(RulebookContent.sections(BOOK))
	assert_string_contains(text, "%d 张牌" % DdzHand.CARD_COUNT)
	assert_string_contains(text, "每人 %d 张" % DdzState.HAND_SIZE)
	assert_string_contains(text, "连续 %d 次都没人叫" % DdzState.MAX_DEALS)
	assert_string_contains(text, "%d 秒" % int(DouDizhuSession.BID_TIMEOUT))
	assert_string_contains(text, "%d 秒" % int(Protocol.TURN_TIMEOUT))
	assert_string_contains(text, "连续 %d 次超时" % DdzState.TRUSTEE_AFTER_TIMEOUTS)
	assert_string_contains(text, "春天")


func test_controls_list_the_table_keys_and_banter():
	var keys := []
	for block in RulebookContent.find("controls", BOOK)["blocks"]:
		if block["type"] == "keys":
			for item in block["items"]:
				keys.append_array(item["keys"])
	for k in ["Enter", "空格", "P", "H", "R", "V", "G", "Q", "T", "Esc", OS.get_keycode_string(RulebookContent.HOTKEY)]:
		assert_has(keys, k, "操作章写着 %s" % k)
	var notes: Array = RulebookContent.find("controls", BOOK)["blocks"].filter(func(b): return b["type"] == "note").map(func(b): return b["text"])
	assert_has(notes, RulebookContent.SPECIES_NOTE)
	assert_has(notes, RulebookContent.BANTER_NOTE)


func test_combo_blocks_render_card_faces_that_refresh():
	var block := RulebookBlocks.build(RulebookDouDizhu.combos_block())
	add_child_autofree(block)
	var faces := block.find_children("*", "TextureRect", true, false)
	var total := 0
	for item in RulebookDouDizhu.combos_block()["items"]:
		total += item["cards"].size()
	assert_eq(faces.size(), total, "每张示例牌一个小图")
	var jokers := faces.filter(func(f: TextureRect) -> bool: return DdzJokerFaces.is_kind(f.get_meta(RulebookBlocks.CARD_META)))
	assert_eq(jokers.size(), 2, "王炸那行是两张王")
	RulebookBlocks.refresh_cards(block)
	assert_eq(jokers[0].texture, CardFaces.texture(jokers[0].get_meta(RulebookBlocks.CARD_META)), "牌面生成完重新取纹理")
	var order := RulebookBlocks.build({"type": "ddz_order", "cards": RulebookDouDizhu.order_cards(), "caption": "x"})
	add_child_autofree(order)
	assert_eq(order.find_children("*", "TextureRect", true, false).size(), DdzHand.RANK_COUNT)
