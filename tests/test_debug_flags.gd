extends GutTest
# DebugFlags.parse_user_args:命令行 --key=value 解析(调试开关与工具脚本共用)。


func test_parses_values_and_bare_flags():
	var opts := DebugFlags.parse_user_args(PackedStringArray(["--autohost=3", "--bot", "--room=甲=乙", "--fast"]))
	assert_eq_deep(opts, {"autohost": "3", "bot": "true", "room": "甲=乙", "fast": "true"})


func test_later_values_win():
	var opts := DebugFlags.parse_user_args(PackedStringArray(["--port=1", "--port=47811"]))
	assert_eq(opts["port"], "47811")


func test_empty_keys_are_ignored():
	assert_eq_deep(DebugFlags.parse_user_args(PackedStringArray(["--", "--=x"])), {})


func test_no_args_gives_no_flags():
	assert_eq_deep(DebugFlags.parse_user_args(PackedStringArray()), {})


# —— --species=<id>:只覆盖本次运行(不写设置);联机冒烟比对各进程打印的形象表 ——

func test_species_override_reads_a_known_id():
	assert_eq(DebugFlags.species_override(PackedStringArray(["--species=crocodile"])), 7)
	assert_eq(DebugFlags.species_override(PackedStringArray(["--bot"])), Species.UNASSIGNED, "没给就不覆盖")


func test_unknown_species_override_is_ignored():
	assert_eq(DebugFlags.species_override(PackedStringArray(["--species=dragon"])), Species.UNASSIGNED)
	assert_eq(DebugFlags.species_override(PackedStringArray(["--species"])), Species.UNASSIGNED)


func test_species_line_lists_ids_in_seat_order():
	var entries := [{"pid": 1, "species": 7}, {"pid": 2034, "species": 0}, {"pid": 99, "species": -1},
		{"pid": 5, "species": "x"}]
	assert_eq(DebugFlags.species_line(entries), "[debug] species {1: crocodile, 2034: fox, 99: -, 5: -}")


# —— --mode=<玩法>:房主开房的玩法(冒烟测试用它开一桌炸弹猫)——

func test_host_mode_reads_a_known_mode():
	assert_eq(DebugFlags.host_mode({"mode": "bomb_cat"}), GameMode.BOMB_CAT)
	assert_eq(DebugFlags.host_mode({"mode": "short_deck"}), GameMode.SHORT_DECK)
	assert_eq(DebugFlags.host_mode({}), GameMode.DEFAULT, "没给用默认玩法")


func test_unknown_host_mode_falls_back_to_the_default():
	assert_eq(DebugFlags.host_mode({"mode": "chess"}), GameMode.DEFAULT)


# —— 德州开关(规格 §8.1)——

func test_mode_defaults_to_liars():
	assert_eq(DebugFlags.mode_option({}), GameMode.LIARS)


func test_mode_accepts_every_known_mode():
	for mode in GameMode.ALL:
		assert_eq(DebugFlags.mode_option({"mode": mode}), mode)


func test_mode_rejects_unknown_values():
	assert_eq(DebugFlags.mode_option({"mode": "poker"}), "")
	assert_eq(DebugFlags.mode_option({"mode": "true"}), "")


func test_hands_option():
	assert_eq(DebugFlags.hands_option({}), 0, "不写就不自动散局")
	assert_eq(DebugFlags.hands_option({"hands": "6"}), 6)
	assert_eq(DebugFlags.hands_option({"hands": "0"}), -1)
	assert_eq(DebugFlags.hands_option({"hands": "abc"}), -1)
	assert_eq(DebugFlags.hands_option({"hands": "true"}), -1)


func test_default_room_follows_the_mode():
	assert_eq(DebugFlags.room_option({}, "甲", GameMode.LIARS), "甲 的酒馆")
	assert_eq(DebugFlags.room_option({}, "甲", GameMode.SHORT_DECK), "甲 的牌局")
	assert_eq(DebugFlags.room_option({"room": "冒烟1"}, "甲", GameMode.HOLDEM), "冒烟1")


func test_session_over_line_reports_my_net_and_the_sum():
	var results := [{"pid": 1, "net": 300}, {"pid": 7, "net": -500}, {"pid": 9, "net": 200}]
	assert_eq(DebugFlags.net_of(results, 7), -500)
	assert_eq(DebugFlags.net_of(results, 42), 0, "不在结算里(没入座就散局)按 0")
	assert_eq(DebugFlags.net_sum(results), 0)
	assert_eq(DebugFlags.net_sum([{"pid": 1, "net": 10}, {"pid": 2}]), 10, "缺字段的行不算")


func test_ddz_results_line_sorts_by_pid_and_sums():
	var line := DebugFlags.ddz_results_line([{"pid": 9, "score": -6}, {"pid": 1, "score": 12}, {"pid": 4, "score": -6}, {"pid": 5}, "x"])
	assert_eq(line, "[debug] DDZ_RESULTS {1: 12, 4: -6, 9: -6} sum=0")
