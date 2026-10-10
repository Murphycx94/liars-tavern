extends GutTest
# 物种目录(网络与场景共用):下标就是网络上传的值,协议 v5 起冻结;同桌不撞脸,先取第一个空着的。
# 2026-10-10 追加熊猫、企鹅(下标 8、9,协议 v10):只能追加在末尾,前 8 个的下标不动。


func test_catalog_has_ten_unique_species_in_frozen_order():
	assert_eq(Species.IDS, ["fox", "bear", "pig", "cat", "turtle", "alpaca", "monkey", "crocodile", "panda", "penguin"])
	assert_eq(Species.LABELS.size(), Species.IDS.size())
	assert_eq(Species.count(), 10)
	assert_eq(Species.index_of("crocodile"), 7, "老物种的下标不动")


func test_index_of_round_trips():
	for i in Species.count():
		assert_eq(Species.index_of(Species.IDS[i]), i)
	assert_eq(Species.index_of("dragon"), Species.UNASSIGNED)


func test_is_valid_accepts_only_in_range_ints():
	assert_true(Species.is_valid(0))
	assert_true(Species.is_valid(7))
	assert_true(Species.is_valid(9))
	for bad in [-1, 10, 999, 2.0, "fox", null]:
		assert_false(Species.is_valid(bad), str(bad))


func test_sanitize_turns_bad_values_into_unassigned():
	assert_eq(Species.sanitize(3), 3)
	assert_eq(Species.sanitize(8), 8)
	for bad in [-1, 10, "x", null, 1.5]:
		assert_eq(Species.sanitize(bad), Species.UNASSIGNED, str(bad))


func test_first_free_starts_from_zero_and_fills_gaps():
	assert_eq(Species.first_free([]), 0)
	assert_eq(Species.first_free([0, 2]), 1)
	assert_eq(Species.first_free([1, 0, 3]), 2)


func test_first_free_wraps_only_when_every_species_is_taken():
	var all := range(Species.count())
	assert_eq(Species.first_free(all), 0)
	assert_eq(Species.first_free(all + [0]), 1)


func test_patron_species_table_follows_the_catalog_order():
	assert_eq(PatronParts.SPECIES.size(), Species.count())
	for i in Species.count():
		assert_eq(PatronParts.species(i)["id"], Species.IDS[i])
		assert_eq(PatronParts.species(i)["label"], Species.LABELS[i])


func test_roles_and_glyphs_cover_every_species():
	assert_eq(Species.ROLES.size(), Species.count())
	assert_eq(Species.GLYPHS.size(), Species.count())
	for glyph: String in Species.GLYPHS:
		assert_eq(glyph.length(), 1, glyph)
	assert_eq(Species.title(0), "狐狸 · 老千绅士")
	assert_eq(Species.title(7), "鳄鱼 · 亡命徒")
	assert_eq(Species.title(8), "熊猫 · 竹林侠客")
	assert_eq(Species.title(9), "企鹅 · 南极来客")
	var unique := {}
	for glyph: String in Species.GLYPHS:
		unique[glyph] = true
	assert_eq(unique.size(), Species.count(), "回退头像的单字不重复")
	assert_eq(Species.title(Species.UNASSIGNED), "还没有形象")
