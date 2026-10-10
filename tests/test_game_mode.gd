extends GutTest
# 玩法常量:id 校验(来自不可信报文)、德州 / 炸弹猫 / 吹牛骰子 / 斗地主判定、人数上限、中途加入、桌子尺寸、主菜单顺序。


func test_known_modes_are_valid():
	for mode in GameMode.ALL:
		assert_true(GameMode.is_valid(mode), mode)


func test_untrusted_values_are_not_valid_modes():
	for value in ["", "poker", "LIARS", 1, null, [GameMode.HOLDEM], {"mode": GameMode.HOLDEM}]:
		assert_false(GameMode.is_valid(value), str(value))


func test_default_mode_is_the_original_game():
	assert_eq(GameMode.DEFAULT, GameMode.LIARS)
	assert_true(GameMode.is_valid(GameMode.DEFAULT))


func test_poker_modes():
	assert_false(GameMode.is_poker(GameMode.LIARS))
	assert_true(GameMode.is_poker(GameMode.HOLDEM))
	assert_true(GameMode.is_poker(GameMode.SHORT_DECK))
	assert_true(GameMode.is_short_deck(GameMode.SHORT_DECK))
	assert_false(GameMode.is_short_deck(GameMode.HOLDEM))


func test_bomb_cat_mode():
	assert_true(GameMode.is_valid(GameMode.BOMB_CAT))
	assert_true(GameMode.is_bomb_cat(GameMode.BOMB_CAT))
	assert_false(GameMode.is_poker(GameMode.BOMB_CAT))
	assert_false(GameMode.is_bomb_cat(GameMode.LIARS))
	assert_eq(GameMode.label(GameMode.BOMB_CAT), "炸弹猫")
	assert_eq(GameMode.short_label(GameMode.BOMB_CAT), "炸弹猫")
	assert_eq(GameMode.summary(GameMode.BOMB_CAT), "炸弹猫 · 2–6 人")
	assert_false(GameMode.allows_late_join(GameMode.BOMB_CAT), "一局打到底,不收中途加入")


func test_liars_dice_mode():
	assert_true(GameMode.is_valid(GameMode.LIARS_DICE))
	assert_true(GameMode.is_liars_dice(GameMode.LIARS_DICE))
	assert_false(GameMode.is_liars_dice(GameMode.LIARS))
	assert_false(GameMode.is_poker(GameMode.LIARS_DICE))
	assert_false(GameMode.is_bomb_cat(GameMode.LIARS_DICE))
	assert_eq(GameMode.LIARS_DICE, "liars_dice")
	assert_eq(GameMode.label(GameMode.LIARS_DICE), "吹牛骰子")
	assert_eq(GameMode.short_label(GameMode.LIARS_DICE), "吹牛骰子")
	assert_eq(GameMode.summary(GameMode.LIARS_DICE), "吹牛骰子 · 2–6 人")
	assert_false(GameMode.allows_late_join(GameMode.LIARS_DICE), "一局打到底,不收中途加入")
	assert_eq(GameMode.max_players(GameMode.LIARS_DICE), LiarsDiceState.MAX_PLAYERS)
	assert_eq(GameMode.min_players(GameMode.LIARS_DICE), LiarsDiceState.MIN_PLAYERS)


func test_dou_dizhu_mode():
	assert_true(GameMode.is_valid(GameMode.DOU_DIZHU), "登记进 ALL")
	assert_eq(GameMode.DOU_DIZHU, "dou_dizhu")
	assert_true(GameMode.is_dou_dizhu(GameMode.DOU_DIZHU))
	assert_false(GameMode.is_dou_dizhu(GameMode.LIARS))
	assert_false(GameMode.is_poker(GameMode.DOU_DIZHU))
	assert_false(GameMode.is_bomb_cat(GameMode.DOU_DIZHU))
	assert_false(GameMode.is_liars_dice(GameMode.DOU_DIZHU))
	assert_eq(GameMode.label(GameMode.DOU_DIZHU), "斗地主")
	assert_eq(GameMode.short_label(GameMode.DOU_DIZHU), "斗地主")
	assert_eq([GameMode.min_players(GameMode.DOU_DIZHU), GameMode.max_players(GameMode.DOU_DIZHU)], [3, 3], "正好 3 人")
	assert_eq(GameMode.max_players(GameMode.DOU_DIZHU), DdzState.PLAYERS)
	assert_eq(GameMode.summary(GameMode.DOU_DIZHU), "斗地主 · 3 人", "人数固定时只写一个数")
	assert_false(GameMode.allows_late_join(GameMode.DOU_DIZHU), "不收中途加入")
	assert_true(GameMode.menu_modes().has(GameMode.DOU_DIZHU), "进了 ALL,菜单格子自动亮起")
	assert_eq(SeatLayout.table_radius_for(GameMode.DOU_DIZHU), SeatLayout.TABLE_RADIUS, "用骗子酒馆的桌子")
	assert_eq(SeatLayout.table_radius_for(GameMode.DOU_DIZHU, 3), SeatLayout.TABLE_RADIUS)


func test_mode_order_puts_the_new_modes_before_the_two_poker_modes():
	assert_eq(GameMode.ALL, [GameMode.LIARS, GameMode.BOMB_CAT, GameMode.LIARS_DICE, GameMode.DOU_DIZHU, GameMode.HOLDEM,
		GameMode.SHORT_DECK])
	assert_eq(GameMode.MENU_ORDER, [GameMode.LIARS, GameMode.BOMB_CAT, GameMode.LIARS_DICE,
		GameMode.DOU_DIZHU, GameMode.HOLDEM, GameMode.SHORT_DECK], "三列两行:骗子酒馆 炸弹猫 吹牛骰子 / 斗地主 德州×2")
	for mode in GameMode.ALL:
		assert_true(GameMode.MENU_ORDER.has(mode), "每种玩法在菜单里都有格子:%s" % mode)
	var expected := GameMode.MENU_ORDER.filter(func(mode: String) -> bool: return GameMode.is_valid(mode))
	if GameMode.BOMB_CAT_ENABLED and GameMode.LIARS_DICE_ENABLED:
		assert_eq(GameMode.menu_modes(), expected)
	if not GameMode.BOMB_CAT_ENABLED:
		assert_false(GameMode.menu_modes().has(GameMode.BOMB_CAT))
	if not GameMode.LIARS_DICE_ENABLED:
		assert_false(GameMode.menu_modes().has(GameMode.LIARS_DICE))


func test_player_caps_per_mode():
	assert_eq(GameMode.max_players(GameMode.LIARS), 4)
	assert_eq(GameMode.max_players(GameMode.BOMB_CAT), 6)
	assert_eq(GameMode.max_players(GameMode.LIARS_DICE), 6)
	assert_eq(GameMode.max_players(GameMode.HOLDEM), 8)
	assert_eq(GameMode.max_players(GameMode.SHORT_DECK), 8)
	assert_eq(GameMode.max_players(GameMode.DOU_DIZHU), 3)
	for mode in GameMode.ALL:
		assert_eq(GameMode.min_players(mode), 3 if mode == GameMode.DOU_DIZHU else 2, mode)


func test_liars_deck_fits_the_liars_cap():
	assert_lte(GameMode.max_players(GameMode.LIARS) * Deck.HAND_SIZE, Deck.build().size())


func test_only_poker_allows_late_join():
	assert_false(GameMode.allows_late_join(GameMode.LIARS))
	assert_true(GameMode.allows_late_join(GameMode.HOLDEM))
	assert_true(GameMode.allows_late_join(GameMode.SHORT_DECK))


func test_labels():
	assert_eq(GameMode.label(GameMode.LIARS), "骗子酒馆")
	assert_eq(GameMode.label(GameMode.HOLDEM), "德州扑克·长牌")
	assert_eq(GameMode.short_label(GameMode.SHORT_DECK), "德州·短牌")
	assert_eq(GameMode.label("bogus"), GameMode.UNKNOWN_LABEL)


func test_summary_names_the_mode_and_its_player_range():
	# 等待厅标题下一行、主菜单玩法按钮的提示
	assert_eq(GameMode.summary(GameMode.SHORT_DECK), "德州扑克·短牌 · 2–8 人")
	assert_eq(GameMode.summary(GameMode.HOLDEM), "德州扑克·长牌 · 2–8 人")
	assert_eq(GameMode.summary(GameMode.LIARS), "骗子酒馆 · 2–4 人")


func test_bomb_cat_uses_the_small_table_up_to_four_and_the_big_one_from_five():
	assert_eq(SeatLayout.table_radius_for(GameMode.BOMB_CAT), SeatLayout.TABLE_RADIUS, "人数未知(等待厅)用小桌")
	for players in [2, 3, 4]:
		assert_eq(SeatLayout.table_radius_for(GameMode.BOMB_CAT, players), SeatLayout.TABLE_RADIUS, str(players))
	for players in [5, 6]:
		assert_eq(SeatLayout.table_radius_for(GameMode.BOMB_CAT, players), SeatLayout.POKER_TABLE_RADIUS, str(players))
	assert_eq(SeatLayout.table_radius_for(GameMode.LIARS, 4), SeatLayout.TABLE_RADIUS, "骗子酒馆不看人数")
	assert_eq(SeatLayout.table_radius_for(GameMode.HOLDEM, 2), SeatLayout.POKER_TABLE_RADIUS, "德州不看人数")


func test_liars_dice_uses_the_small_table_up_to_four_and_the_big_one_from_five():
	assert_eq(SeatLayout.table_radius_for(GameMode.LIARS_DICE), SeatLayout.TABLE_RADIUS, "人数未知(等待厅)用小桌")
	for players in [2, 3, 4]:
		assert_eq(SeatLayout.table_radius_for(GameMode.LIARS_DICE, players), SeatLayout.TABLE_RADIUS, str(players))
	for players in [5, 6]:
		assert_eq(SeatLayout.table_radius_for(GameMode.LIARS_DICE, players), SeatLayout.POKER_TABLE_RADIUS, str(players))


func test_poker_table_is_bigger_and_keeps_the_seat_gap():
	assert_eq(SeatLayout.table_radius_for(GameMode.LIARS), SeatLayout.TABLE_RADIUS)
	assert_gt(SeatLayout.table_radius_for(GameMode.HOLDEM), SeatLayout.TABLE_RADIUS)
	assert_eq(SeatLayout.table_radius_for(GameMode.SHORT_DECK), SeatLayout.POKER_TABLE_RADIUS)
	assert_almost_eq(SeatLayout.seat_radius_for(SeatLayout.TABLE_RADIUS), SeatLayout.SEAT_RADIUS, 0.0001)
	var poker := SeatLayout.POKER_TABLE_RADIUS
	assert_almost_eq(SeatLayout.seat_radius_for(poker) - poker, SeatLayout.SEAT_RADIUS - SeatLayout.TABLE_RADIUS, 0.0001)
