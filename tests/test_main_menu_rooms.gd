extends GutTest
# 主菜单房间行:局域网报文里的人数/上限不可信,画座位前夹到合法范围;大桌子的座位写成数字;
# 房主那一行写出玩法;加入按钮按房间状态给文案(加入 / 入座 / 已满 / 对局中 / 版本不同)。
# 开房的默认房名跟着玩法。


const MainMenuScreen := preload("res://src/ui/main_menu/main_menu.gd")
const RoomRow := preload("res://src/ui/main_menu/room_row.gd")


func _room(overrides := {}) -> Dictionary:
	# RoomList.decode 的字段 + 列表补上的 ip;默认是一桌还没开打、有空位的德州长牌
	var room := {
		"id": "r1", "room": "老王的牌局", "host": "老王", "version": Protocol.VERSION,
		"port": Protocol.GAME_PORT, "open": true, "mode": GameMode.HOLDEM, "playing": false,
		"seated": 3, "cap": 8, "compatible": true, "build": 0, "ver": "", "update": false, "plat": "",
		"ip": "192.168.1.8",
	}
	return room.merged(overrides, true)


func test_normal_counts_pass_through():
	assert_eq(RoomRow.clamp_seats(2, 4), Vector2i(2, 4))
	assert_eq(RoomRow.seat_dots(Vector2i(2, 4)), "●●○○")


func test_huge_counts_are_capped_at_max_players():
	assert_eq(RoomRow.clamp_seats(2000000000, 99999999), Vector2i(Protocol.MAX_PLAYERS, Protocol.MAX_PLAYERS))


func test_negative_counts_become_empty_seats():
	assert_eq(RoomRow.clamp_seats(-3, 99999999), Vector2i(0, Protocol.MAX_PLAYERS))
	assert_eq(RoomRow.clamp_seats(0, -5), Vector2i(0, 0))


func test_capacity_never_below_players():
	assert_eq(RoomRow.clamp_seats(3, 1), Vector2i(3, 3))
	assert_eq(RoomRow.seat_dots(RoomRow.clamp_seats(3, 1)), "●●●")


func test_small_tables_draw_dots_and_big_tables_write_the_count():
	# 8 个圆点在 480 宽的面板里太挤:上限超过 4 的桌子写成「3/8」
	assert_eq(RoomRow.seat_text(Vector2i(2, 4)), "●●○○")
	assert_eq(RoomRow.seat_text(Vector2i(0, 2)), "○○")
	assert_eq(RoomRow.seat_text(Vector2i(3, 8)), "3/8")
	assert_eq(RoomRow.seat_text(Vector2i(8, 8)), "8/8")


func test_host_line_names_the_mode():
	assert_eq(RoomRow.host_line(_room({"mode": GameMode.SHORT_DECK})), "房主 老王 · 德州·短牌 · 192.168.1.8")
	assert_eq(RoomRow.host_line(_room({"mode": GameMode.LIARS, "port": Protocol.GAME_PORT + 1})),
		"房主 老王 · 骗子酒馆 · 192.168.1.8:%d" % (Protocol.GAME_PORT + 1))
	assert_eq(RoomRow.host_line(_room({"mode": "mahjong"})), "房主 老王 · %s · 192.168.1.8" % GameMode.UNKNOWN_LABEL)


func test_join_button_follows_the_room_state():
	var cases := [
		[{}, "加入", true],
		[{"playing": true}, "入座", true],
		[{"open": false, "seated": 8}, "已满", false],
		[{"open": false, "playing": true, "seated": 8}, "已满", false],
		[{"open": false, "playing": true}, "对局中", false],
		[{"mode": GameMode.LIARS, "cap": 4, "seated": 4, "open": false}, "已满", false],
		# 旧房主的报文没有 playing:没满却不开放,就是在对局中
		[{"mode": GameMode.LIARS, "cap": 4, "open": false}, "对局中", false],
		[{"compatible": false}, "版本不同", false],
		[{"compatible": false, "playing": true}, "版本不同", false],
	]
	for c in cases:
		var state: Dictionary = RoomRow.join_button(_room(c[0]))
		assert_eq([state.get("text"), state.get("enabled")], [c[1], c[2]], str(c[0]))


func test_join_button_explains_version_mismatch_and_late_seating():
	assert_string_contains(RoomRow.join_button(_room({"compatible": false}))["tooltip"], "版本")
	assert_string_contains(RoomRow.join_button(_room({"playing": true}))["tooltip"], "下一手")
	assert_eq(RoomRow.join_button(_room())["tooltip"], "")


func test_default_room_name_follows_the_mode():
	assert_eq(MainMenuScreen.default_room_name("老王", GameMode.LIARS), "老王 的酒馆")
	assert_eq(MainMenuScreen.default_room_name("老王", GameMode.HOLDEM), "老王 的牌局")
	assert_eq(MainMenuScreen.default_room_name("老王", GameMode.SHORT_DECK), "老王 的牌局")
	assert_eq(MainMenuScreen.default_room_name("老王", GameMode.BOMB_CAT), "老王 的猫窝")
	assert_eq(MainMenuScreen.default_room_name("老王", GameMode.LIARS_DICE), "老王 的骰子局")
	assert_eq(MainMenuScreen.default_room_name("老王", GameMode.DOU_DIZHU), "老王 的斗地主")
