extends GutTest


func test_sections_have_unique_ids_titles_and_blocks():
	var ids := {}
	for section in RulebookContent.sections():
		assert_false(ids.has(section["id"]), "重复的章节 id:" + section["id"])
		ids[section["id"]] = true
		assert_ne(section["title"], "")
		assert_false(section["blocks"].is_empty(), section["id"] + " 没有内容")


func test_every_block_type_is_known():
	for section in RulebookContent.sections():
		for block in section["blocks"]:
			assert_has(RulebookContent.BLOCK_TYPES, block["type"])


func test_find_returns_section_by_id_or_empty():
	assert_eq(RulebookContent.find("deck")["id"], "deck")
	assert_eq(RulebookContent.find("no_such_section"), {})


func test_card_block_matches_deck_composition():
	var items: Array = _block("deck", "cards")["items"]
	var total := 0
	for item in items:
		assert_eq(item["count"], Deck.COMPOSITION[item["kind"]])
		total += item["count"]
	assert_eq(items.size(), Deck.COMPOSITION.size())
	assert_eq(total, Deck.build().size())
	var text := _text_of(RulebookContent.find("deck"))
	assert_string_contains(text, "共 %d 张" % total)
	assert_string_contains(text, "发 %d 张" % Deck.HAND_SIZE)


func test_odds_rise_until_last_chamber_is_certain():
	var items: Array = _block("revolver", "odds")["items"]
	assert_eq(items.size(), Revolver.CHAMBERS)
	assert_almost_eq(items[0]["chance"], 1.0 / Revolver.CHAMBERS, 0.0001)
	assert_eq(items[-1]["chance"], 1.0)
	for i in range(1, items.size()):
		assert_gt(items[i]["chance"], items[i - 1]["chance"])


func test_hit_chance_matches_hud_formula_and_never_divides_by_zero():
	for fired in Revolver.CHAMBERS:
		assert_almost_eq(RulebookContent.hit_chance(fired), 1.0 / (Revolver.CHAMBERS - fired), 0.0001)
	assert_eq(RulebookContent.hit_chance(Revolver.CHAMBERS), 1.0)


func test_text_follows_rule_constants():
	var text := ""
	for section in RulebookContent.sections():
		text += _text_of(section)
	# 人数取骗子酒馆自己的上限:Protocol.MAX_PLAYERS 是所有玩法的绝对上限(德州 8 人),不再指骗子酒馆
	var liars := GameMode.LIARS
	assert_string_contains(text, "%d–%d 人" % [GameMode.min_players(liars), GameMode.max_players(liars)])
	assert_false(text.contains("%d–%d 人" % [GameMode.min_players(liars), GameMode.max_players(GameMode.HOLDEM)]),
		"骗子酒馆那本不能写成德州的人数")
	assert_string_contains(text, "%d–%d 张" % [Rules.MIN_PLAY, Rules.MAX_PLAY])
	assert_string_contains(text, "%d 秒" % int(Protocol.TURN_TIMEOUT))


func test_liars_book_is_the_default_and_keeps_its_chapters():
	# 骗子酒馆那本内容不变:章节与顺序照旧;不指定书时就是这本
	var ids := RulebookContent.sections().map(func(section): return section["id"])
	assert_eq(ids, ["goal", "deck", "turn", "reveal", "revolver", "rounds", "controls"])
	assert_eq(RulebookContent.sections(RulebookContent.BOOK_LIARS), RulebookContent.sections())


func test_each_book_has_a_tab_title():
	assert_eq(RulebookContent.BOOKS, [RulebookContent.BOOK_LIARS, RulebookContent.BOOK_BOMB_CAT, RulebookContent.BOOK_LIARS_DICE,
		RulebookContent.BOOK_DOU_DIZHU, RulebookContent.BOOK_POKER])
	assert_eq(RulebookContent.book_title(RulebookContent.BOOK_LIARS), "骗子酒馆")
	assert_eq(RulebookContent.book_title(RulebookContent.BOOK_POKER), "德州扑克")


func test_both_poker_modes_share_the_poker_book():
	assert_eq(RulebookContent.book_for_mode(GameMode.LIARS), RulebookContent.BOOK_LIARS)
	assert_eq(RulebookContent.book_for_mode(GameMode.HOLDEM), RulebookContent.BOOK_POKER)
	assert_eq(RulebookContent.book_for_mode(GameMode.SHORT_DECK), RulebookContent.BOOK_POKER)
	assert_eq(RulebookContent.book_for_mode("chess"), RulebookContent.BOOK_LIARS, "未知玩法回退到骗子酒馆那本")


func test_find_looks_only_in_the_given_book():
	assert_eq(RulebookContent.find("hands", RulebookContent.BOOK_POKER)["id"], "hands")
	assert_eq(RulebookContent.find("hands"), {})
	assert_eq(RulebookContent.find("deck", RulebookContent.BOOK_POKER), {})


func test_controls_list_the_rulebook_hotkey():
	var keys := []
	for item in _block("controls", "keys")["items"]:
		keys.append_array(item["keys"])
	assert_has(keys, OS.get_keycode_string(RulebookContent.HOTKEY))


func test_both_books_explain_how_to_pick_a_species():
	for book in [RulebookContent.BOOK_LIARS, RulebookContent.BOOK_POKER]:
		var notes: Array = RulebookContent.find("controls", book)["blocks"].filter(func(b: Dictionary) -> bool:
			return b["type"] == "note").map(func(b: Dictionary) -> String: return b["text"])
		assert_has(notes, RulebookContent.SPECIES_NOTE, book)
	assert_string_contains(RulebookContent.SPECIES_NOTE, "先选先得")


func _block(section_id: String, type: String) -> Dictionary:
	for block in RulebookContent.find(section_id).get("blocks", []):
		if block["type"] == type:
			return block
	fail_test("章节 %s 中没有 %s 块" % [section_id, type])
	return {"items": []}


func _text_of(value: Variant) -> String:
	# 递归收集章节里的全部文字,用于检查文案中的数字
	match typeof(value):
		TYPE_STRING:
			return value + "\n"
		TYPE_ARRAY:
			return "".join(value.map(_text_of))
		TYPE_DICTIONARY:
			return "".join(value.values().map(_text_of))
	return ""
