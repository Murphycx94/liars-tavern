extends GutTest


func _make_lobby() -> LobbyModel:
	var lobby := LobbyModel.new()
	lobby.add_host("房主")
	return lobby


func test_host_is_present_and_ready():
	var lobby := _make_lobby()
	assert_eq(lobby.size(), 1)
	var view := lobby.view()
	assert_eq(view[0]["pid"], LobbyModel.HOST_ID)
	assert_true(view[0]["ready"])
	assert_true(view[0]["is_host"])


func _lobby_with(count: int) -> LobbyModel:
	# 房主 + (count - 1) 位客人
	var lobby := _make_lobby()
	for i in count - 1:
		lobby.add_member(10 + i, "客%d" % i)
	return lobby


func test_join_checks_version_game_state_and_capacity():
	var lobby := _make_lobby()
	assert_eq(lobby.check_join(Protocol.VERSION, false, GameMode.LIARS, false), "")
	assert_string_contains(lobby.check_join(Protocol.VERSION + 1, false, GameMode.LIARS, false), "版本")
	assert_string_contains(lobby.check_join(Protocol.VERSION, true, GameMode.LIARS, false), "已开始")
	for id in [10, 11, 12]:
		lobby.add_member(id, "客%d" % id)
	assert_string_contains(lobby.check_join(Protocol.VERSION, false, GameMode.LIARS, false), "已满")


func test_version_is_judged_before_anything_else():
	# 主菜单靠「版本」字样去问房主要更新:对局中、满员的房间也得先报版本不符
	var lobby := _lobby_with(GameMode.max_players(GameMode.HOLDEM))
	for mode in GameMode.ALL:
		for in_game in [false, true]:
			for accepting_late in [false, true]:
				var reason := lobby.check_join(Protocol.VERSION - 1, in_game, mode, accepting_late)
				assert_string_contains(reason, "版本", "%s in_game=%s late=%s" % [mode, in_game, accepting_late])


func test_running_poker_table_seats_late_joiners():
	for mode in [GameMode.HOLDEM, GameMode.SHORT_DECK]:
		assert_eq(_make_lobby().check_join(Protocol.VERSION, true, mode, true), "", mode)


func test_closed_match_reasons_differ_by_mode():
	# 德州散局中或已结算时不再收人,文案和骗子酒馆的「已开始」不同
	assert_eq(_make_lobby().check_join(Protocol.VERSION, true, GameMode.SHORT_DECK, false), "牌局正在散局,请稍后再来")
	assert_eq(_make_lobby().check_join(Protocol.VERSION, true, GameMode.LIARS, false), "游戏已开始,请等这一局结束")


func test_capacity_follows_the_mode():
	var four := _lobby_with(4)
	assert_eq(four.check_join(Protocol.VERSION, false, GameMode.LIARS, false), "房间已满(4/4)")
	assert_eq(four.check_join(Protocol.VERSION, false, GameMode.HOLDEM, false), "")
	var eight := _lobby_with(8)
	assert_eq(eight.check_join(Protocol.VERSION, false, GameMode.HOLDEM, false), "房间已满(8/8)")
	assert_eq(eight.check_join(Protocol.VERSION, true, GameMode.SHORT_DECK, true), "房间已满(8/8)", "对局中满员也不能入座")


func test_members_join_unready_with_sanitized_unique_names():
	var lobby := _make_lobby()
	lobby.add_member(10, "  阿杰 ")
	lobby.add_member(11, "阿杰")
	lobby.add_member(12, "")
	var names := lobby.names()
	assert_eq(names[10], "阿杰")
	assert_eq(names[11], "阿杰 2")
	assert_eq(names[12], "酒客 4")
	assert_false(lobby.view()[1]["ready"])


func test_seat_order_is_join_order():
	var lobby := _make_lobby()
	lobby.add_member(900, "乙")
	lobby.add_member(5, "丙")
	assert_eq(lobby.seat_order(), [1, 900, 5])


func test_can_start_needs_two_players_all_ready():
	var lobby := _make_lobby()
	assert_false(lobby.can_start())
	lobby.add_member(10, "乙")
	assert_false(lobby.can_start())
	assert_true(lobby.set_ready(10, true))
	assert_true(lobby.can_start())
	lobby.add_member(11, "丙")
	assert_false(lobby.can_start())


func test_dou_dizhu_needs_exactly_three_and_caps_at_three():
	var lobby := _make_lobby()
	var need := GameMode.min_players(GameMode.DOU_DIZHU)
	lobby.add_member(10, "乙")
	lobby.set_ready(10, true)
	assert_true(lobby.can_start(), "其他玩法 2 人就能开")
	assert_false(lobby.can_start(need), "斗地主 2 人不能开")
	lobby.add_member(11, "丙")
	lobby.set_ready(11, true)
	assert_true(lobby.can_start(need))
	assert_string_contains(lobby.check_join(Protocol.VERSION, false, GameMode.DOU_DIZHU, false), "已满", "第 4 人进不来")


func test_set_ready_unknown_member_and_host_is_rejected():
	var lobby := _make_lobby()
	assert_false(lobby.set_ready(99, true))
	assert_false(lobby.set_ready(LobbyModel.HOST_ID, false))
	assert_true(lobby.view()[0]["ready"])


func test_remove_member_and_host_cannot_be_removed():
	var lobby := _make_lobby()
	lobby.add_member(10, "乙")
	assert_true(lobby.remove(10))
	assert_false(lobby.remove(10))
	assert_false(lobby.remove(LobbyModel.HOST_ID))
	assert_eq(lobby.seat_order(), [1])


func test_reset_ready_keeps_host_ready_only():
	var lobby := _make_lobby()
	lobby.add_member(10, "乙")
	lobby.set_ready(10, true)
	lobby.reset_ready()
	assert_false(lobby.view()[1]["ready"])
	assert_true(lobby.view()[0]["ready"])


func test_view_is_detached_copy():
	var lobby := _make_lobby()
	var view := lobby.view()
	view[0]["name"] = "篡改"
	assert_eq(lobby.names()[1], "房主")


# —— 自选形象(子项目② §3.4):先到先得,房主分配 ——

const FOX := 0
const BEAR := 1
const PIG := 2
const CROC := 7


func _species_by_pid(lobby: LobbyModel) -> Dictionary:
	var out := {}
	for row in lobby.view():
		out[row["pid"]] = row["species"]
	return out


func test_host_gets_the_preferred_species():
	var lobby := LobbyModel.new()
	lobby.add_host("房主", CROC)
	assert_eq(lobby.species_of(LobbyModel.HOST_ID), CROC)


func test_host_with_an_invalid_preference_falls_back_to_the_first_species():
	for bad in [Species.UNASSIGNED, 10, 999]:   # 10 个物种(下标 0–9)之外
		var lobby := LobbyModel.new()
		lobby.add_host("房主", bad)
		assert_eq(lobby.species_of(LobbyModel.HOST_ID), FOX, str(bad))


func test_new_members_start_unassigned():
	# 形象在握手之后单独发来:这一个往返里是 -1(等待厅显示「挑选中…」,不建角色)
	var lobby := _make_lobby()
	lobby.add_member(10, "乙")
	assert_eq(lobby.species_of(10), Species.UNASSIGNED)
	assert_eq(lobby.view()[1]["species"], Species.UNASSIGNED)


func test_free_species_is_granted():
	var lobby := _make_lobby()
	lobby.add_member(10, "乙")
	assert_true(lobby.request_species(10, CROC))
	assert_eq(lobby.species_of(10), CROC)
	assert_true(lobby.request_species(10, BEAR), "等待厅里还能换")
	assert_eq(lobby.species_of(10), BEAR)


func test_taken_species_gives_the_unassigned_the_first_free_one():
	var lobby := LobbyModel.new()
	lobby.add_host("房主", FOX)
	lobby.add_member(10, "乙")
	assert_true(lobby.request_species(10, FOX), "还没有形象:分第一个空着的")
	assert_eq(lobby.species_of(10), BEAR)


func test_taken_species_keeps_an_assigned_member_unchanged():
	var lobby := LobbyModel.new()
	lobby.add_host("房主", FOX)
	lobby.add_member(10, "乙")
	lobby.request_species(10, PIG)
	assert_false(lobby.request_species(10, FOX), "被占了:已有形象的保持不变,不广播")
	assert_eq(lobby.species_of(10), PIG)
	assert_eq(lobby.species_of(LobbyModel.HOST_ID), FOX, "占用者也不受影响")


func test_out_of_range_requests_are_treated_like_taken_ones():
	var lobby := _make_lobby()
	lobby.add_member(10, "乙")
	assert_true(lobby.request_species(10, 99), "没有形象的分第一个空着的")
	assert_eq(lobby.species_of(10), BEAR)
	for bad in [-1, 10, 99, -500]:
		assert_false(lobby.request_species(10, bad), str(bad))
		assert_eq(lobby.species_of(10), BEAR)


func test_requesting_the_current_species_changes_nothing():
	var lobby := _make_lobby()
	lobby.add_member(10, "乙")
	lobby.request_species(10, PIG)
	assert_false(lobby.request_species(10, PIG))


func test_unknown_members_cannot_request():
	var lobby := _make_lobby()
	assert_false(lobby.request_species(42, PIG))
	assert_eq(lobby.species_of(42), Species.UNASSIGNED)


func test_leaving_frees_only_the_leavers_species():
	var lobby := LobbyModel.new()
	lobby.add_host("房主", CROC)
	lobby.add_member(10, "乙")
	lobby.add_member(11, "丙")
	lobby.request_species(10, FOX)
	lobby.request_species(11, FOX)   # 撞车:分到熊
	lobby.remove(10)
	assert_eq(_species_by_pid(lobby), {1: CROC, 11: BEAR}, "候补形象不会自动换回首选")
	assert_true(lobby.request_species(11, FOX), "空出来的形象可以自己换过去")
	lobby.add_member(12, "丁")
	assert_true(lobby.request_species(12, BEAR), "重新加入算新成员,空着的首选就拿到")


func test_reset_ready_keeps_species():
	# 再来一局:形象不变
	var lobby := LobbyModel.new()
	lobby.add_host("房主", PIG)
	lobby.add_member(10, "乙")
	lobby.request_species(10, CROC)
	lobby.reset_ready()
	assert_eq(_species_by_pid(lobby), {1: PIG, 10: CROC})


func test_assign_unassigned_fills_every_gap_in_join_order():
	var lobby := LobbyModel.new()
	lobby.add_host("房主", BEAR)
	for id in [10, 11, 12]:
		lobby.add_member(id, "客%d" % id)
	lobby.request_species(11, FOX)
	assert_true(lobby.assign_unassigned())
	assert_eq(_species_by_pid(lobby), {1: BEAR, 10: PIG, 11: FOX, 12: 3})
	assert_false(lobby.assign_unassigned(), "都有了:不变")


func test_view_carries_species_as_a_copy():
	var lobby := LobbyModel.new()
	lobby.add_host("房主", CROC)
	var view := lobby.view()
	assert_eq(view[0]["species"], CROC)
	view[0]["species"] = FOX
	assert_eq(lobby.species_of(LobbyModel.HOST_ID), CROC)


func test_eight_seats_always_find_a_free_species():
	# 德州 8 人桌(物种 10 个,2026-10-10 加了熊猫、企鹅):8 个人都要鳄鱼,房主拿到,其余按目录顺序分空着的,不重复
	var lobby := LobbyModel.new()
	lobby.add_host("房主", CROC)
	for i in 7:
		lobby.add_member(10 + i, "客%d" % i)
		lobby.request_species(10 + i, CROC)
	var taken := _species_by_pid(lobby).values()
	taken.sort()
	assert_eq(taken, range(8))


func test_random_joins_leaves_and_requests_keep_species_unique():
	# 性质测试:固定种子随机做 500 步加入 / 离开 / 请求;每一步名单内形象都不重复、取值合法,
	# 已有形象的人不会因为别人的请求而改变
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261007
	var lobby := LobbyModel.new()
	lobby.add_host("房主", rng.randi_range(-2, 9))
	var next_id := 10
	for step in 500:
		var before := _species_by_pid(lobby)
		var members: Array = lobby.seat_order()
		var roll := rng.randf()
		var actor := -1
		if roll < 0.3 and lobby.size() < GameMode.max_players(GameMode.HOLDEM):
			lobby.add_member(next_id, "客%d" % next_id)
			actor = next_id
			next_id += 1
		elif roll < 0.45 and members.size() > 1:
			actor = members[rng.randi_range(1, members.size() - 1)]
			lobby.remove(actor)
		elif roll < 0.5:
			lobby.assign_unassigned()
		else:
			actor = members[rng.randi_range(0, members.size() - 1)]
			var wanted := rng.randi_range(-2, 9)
			var changed := lobby.request_species(actor, wanted)
			assert_eq(changed, lobby.species_of(actor) != before[actor], "返回值等于名单是否变了 · 第 %d 步" % step)
		var now := _species_by_pid(lobby)
		var seen := {}
		for pid in now:
			var s: int = now[pid]
			assert_true(s == Species.UNASSIGNED or Species.is_valid(s), "第 %d 步取值合法" % step)
			if s != Species.UNASSIGNED:
				assert_false(seen.has(s), "第 %d 步形象不重复" % step)
				seen[s] = true
			if pid != actor and before.has(pid) and before[pid] != Species.UNASSIGNED:
				assert_eq(s, before[pid], "第 %d 步别人的形象不变" % step)
