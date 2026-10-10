extends GutTest
# 说明书的炸弹猫那本:章节齐全、块类型都认识、每张牌都列出来(名字与说明取 BombCatCard,张数取 BombCatDeck)、
# 数字跟着规则常量走、操作章有快捷键(不占 T / Q / V / WASD 之外的键)、炸弹猫房间翻开的就是这本,而且翻得开。


const C := preload("res://src/core/bomb_cat/bomb_cat_card.gd")
const BOOK := RulebookContent.BOOK_BOMB_CAT


func after_each():
	BombCatFaces.clear()


func _text_of(section: Dictionary) -> String:
	var parts := []
	for block in section.get("blocks", []):
		for key in ["text", "note"]:
			if block.has(key):
				parts.append(str(block[key]))
		for item in block.get("items", []):
			parts.append(str(item))
	return "\n".join(parts)


func test_bomb_cat_mode_opens_this_book():
	assert_eq(RulebookContent.book_for_mode(GameMode.BOMB_CAT), BOOK)
	assert_eq(RulebookContent.book_title(BOOK), "炸弹猫")
	assert_has(RulebookContent.BOOKS, BOOK)


func test_chapters_and_block_types():
	var ids := RulebookContent.sections(BOOK).map(func(s): return s["id"])
	assert_eq(ids, ["goal", "turn", "cards", "nope", "bomb", "snacks", "setup", "controls"])
	for section in RulebookContent.sections(BOOK):
		assert_true(section["title"] != "" and section["tagline"] != "", section["id"])
		for block in section["blocks"]:
			assert_has(RulebookContent.BLOCK_TYPES, block["type"])


func test_every_card_is_listed_with_its_own_name_text_and_count():
	var block := RulebookBombCat.cards_block()
	var ids: Array = block["items"].map(func(item): return item["id"])
	assert_eq(ids, C.ALL, "按 BombCatCard.ALL 的顺序")
	for item in block["items"]:
		assert_eq(item["name"], C.display_name(item["id"]))
		assert_eq(item["text"], C.description(item["id"]))
		assert_ne(item["count"], "")
	assert_eq(RulebookBombCat.count_text(C.SKIP), "2–3 人 3 · 4–5 人 4 · 6 人 5")
	assert_eq(RulebookBombCat.count_text(C.BOMB), "人数 − 1 张")


func test_numbers_follow_the_rule_constants():
	var nope := _text_of(RulebookContent.find("nope", BOOK))
	assert_string_contains(nope, "%d 秒" % int(BombCatState.REACT_WINDOW))
	var bomb := _text_of(RulebookContent.find("bomb", BOOK))
	assert_string_contains(bomb, "%d 秒" % int(BombCatState.REINSERT_TIMEOUT))
	var turn := _text_of(RulebookContent.find("turn", BOOK))
	assert_string_contains(turn, "%d 秒" % int(Protocol.TURN_TIMEOUT))
	var setup := _text_of(RulebookContent.find("setup", BOOK))
	assert_string_contains(setup, "整副 %d 张" % BombCatDeck.total_cards(6))


func test_controls_list_the_bomb_cat_keys_and_the_shared_ones():
	var keys := []
	for block in RulebookContent.find("controls", BOOK)["blocks"]:
		if block["type"] == "keys":
			for item in block["items"]:
				keys.append_array(item["keys"])
	for key in ["1–9", "Enter", "空格", "N", "V", "T", "G", "Q", "W", OS.get_keycode_string(RulebookContent.HOTKEY), "Esc"]:
		assert_has(keys, key)


func test_the_book_opens_and_every_page_builds():
	var book := Rulebook.new(true, BOOK)
	add_child_autofree(book)
	assert_eq(book.current_book(), BOOK)
	for i in RulebookContent.sections(BOOK).size():
		book.show_section(i)
	var faces := book.find_children("*", "TextureRect", true, false).filter(func(t): return t.has_meta(RulebookBlocks.BOMB_CARD_META))
	assert_eq(faces.size(), 0, "最后一页(操作)没有小牌面")
	book.show_section(2)
	faces = book.find_children("*", "TextureRect", true, false).filter(func(t): return t.has_meta(RulebookBlocks.BOMB_CARD_META))
	assert_eq(faces.size(), C.ALL.size(), "牌那一页每种牌一张小牌面")
	book.refresh_card_faces()
