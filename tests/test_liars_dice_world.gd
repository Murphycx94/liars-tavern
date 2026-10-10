extends GutTest
# 吹牛骰子的 3D 道具与布局:骰盅、骰子网格走 MeshForge 缓存(同物种共用一份、清缓存后重建)、点数朝上的朝向、
# 骰盅离烛台够远(2–6 人每个座位、大小两种桌)、开盅那一行不出桌面;LiarsDiceCups 的隐藏信息(开盅前别人的骰子一个都不建)、
# 摇盅后扣回桌上、开盅翻盅排开、计数高亮与光圈、丢骰子、出局歪倒、退场一并释放;小件不投影。


var world: TableWorld


func before_each():
	world = TableWorld.new(null)
	add_child_autofree(world)


func after_each():
	MeshForge.clear_cache()


func _arrange(n: int, radius := 0.0) -> LiarsDiceCups:
	world.configure_table(radius if radius > 0.0 else SeatLayout.table_radius_for(GameMode.LIARS_DICE, n))
	world.arrange(range(1, n + 1).map(func(pid): return {"pid": pid}), 1, true, false)
	var cups := LiarsDiceCups.new(world)
	cups.my_pid = 1
	world.poker_root.add_child(cups)
	cups.setup(range(1, n + 1), {})
	return cups


# —— 网格 ——

func test_meshes_are_cached_and_shared():
	var a := LiarsDiceProps.cup(0)
	assert_same(LiarsDiceProps.cup(0), a, "同物种共用一份骰盅网格")
	assert_ne(LiarsDiceProps.cup(1), a, "不同物种颜色不同")
	assert_true(MeshForge.is_cached(LiarsDiceProps.cup_key(0)))
	assert_same(LiarsDiceProps.die(), LiarsDiceProps.die())
	assert_ne(LiarsDiceProps.die(true), LiarsDiceProps.die(), "高亮用另一份发光网格")
	assert_eq(a.get_surface_count(), 1, "骰盅一个 surface(一次 draw)")
	assert_eq(LiarsDiceProps.die().get_surface_count(), 1)
	assert_same(a.surface_get_material(0), WorldMaterials.prop(), "共用道具材质,不复制")
	MeshForge.clear_cache()
	assert_false(MeshForge.is_cached(LiarsDiceProps.cup_key(0)), "清缓存时释放")
	assert_ne(LiarsDiceProps.cup(0), a, "清掉后重建")


func test_cup_color_follows_the_species():
	for i in Species.count():
		var leather := LiarsDiceProps.leather_of(i)
		assert_lte(maxf(leather.r, maxf(leather.g, leather.b)), PatronParts.ALBEDO_CAP + 0.001, "封顶")
	assert_ne(LiarsDiceProps.leather_of(0), LiarsDiceProps.leather_of(1))
	assert_eq(LiarsDiceProps.leather_of(-1), LiarsDiceProps.LEATHER)


func test_up_basis_puts_the_value_on_top():
	for v in range(1, 7):
		for yaw in [0.0, 1.3, -2.2]:
			assert_eq(LiarsDiceProps.top_face(LiarsDiceProps.up_basis(v, yaw)), v, "点数 %d 朝上" % v)
	for v in range(1, 7):
		assert_eq(v + [0, 6, 5, 4, 3, 2, 1][v], 7, "对面相加为 7")
	assert_eq((LiarsDiceProps.FACE_NORMALS[1] + LiarsDiceProps.FACE_NORMALS[6]).length(), 0.0)


# —— 布局 ——

func test_cups_keep_clear_of_the_candles_and_rows_stay_on_the_felt():
	for n in range(2, 7):
		var radius := SeatLayout.table_radius_for(GameMode.LIARS_DICE, n)
		for k in n:
			var angle := TAU * k / n
			var spot := LiarsDiceLayout.cup_spot(angle, radius)
			for c: Vector3 in LiarsDiceLayout.candle_points():
				var d := Vector2(spot.x - c.x, spot.z - c.z).length()
				assert_gte(d, 0.19, "%d 人第 %d 座的骰盅离烛台 %.2f" % [n, k, d])
				for i in 5:
					var p := LiarsDiceLayout.row_position(angle, radius, i, 5)
					assert_gte(Vector2(p.x - c.x, p.z - c.z).length(), 0.1, "%d 人第 %d 座的骰子行碰到烛台" % [n, k])
			for i in 5:
				var p := LiarsDiceLayout.row_position(angle, radius, i, 5)
				assert_lt(Vector2(p.x, p.z).length(), radius - 0.05, "骰子行在桌面上")
			assert_lt(Vector2(spot.x, spot.z).length() + LiarsDiceLayout.CUP_RADIUS, radius, "骰盅在桌面上")


func test_cups_of_neighbours_do_not_overlap():
	for n in range(2, 7):
		var radius := SeatLayout.table_radius_for(GameMode.LIARS_DICE, n)
		for k in n:
			var a := LiarsDiceLayout.cup_spot(TAU * k / n, radius)
			var b := LiarsDiceLayout.cup_spot(TAU * ((k + 1) % n) / n, radius)
			assert_gt(a.distance_to(b), LiarsDiceLayout.CUP_RADIUS * 3.0, "%d 人相邻两只骰盅" % n)


func test_dice_fit_under_the_cup():
	# 2×2 平铺加一颗叠在上面:都在盅口里面、不互相穿
	var inner := LiarsDiceLayout.CUP_RADIUS - LiarsDiceProps.CUP_WALL
	for i in 5:
		var s := LiarsDiceLayout.under_slot(i)
		assert_lt(Vector2(s.x, s.z).length() + LiarsDiceLayout.DIE_SIZE * 0.72, inner, "第 %d 颗在盅里" % i)
		assert_lt(s.y + LiarsDiceLayout.DIE_SIZE, LiarsDiceLayout.CUP_HEIGHT - LiarsDiceProps.CUP_WALL, "不顶到盅顶")
	assert_gte(LiarsDiceLayout.UNDER_SPREAD * 2.0, LiarsDiceLayout.DIE_SIZE * 1.04, "2×2 之间留缝")


# —— 骰盅层 ——

func test_hidden_information_and_reveal():
	var cups := _arrange(4)
	cups.set_my_dice([1, 2, 3, 5, 6])
	assert_eq(cups.dice_count(1), 5)
	assert_eq(cups.others_dice_count(), 0, "开盅前别人的骰子一个都不建")
	assert_eq(cups.values_of(1), [1, 2, 3, 5, 6])
	for i in 5:
		assert_eq(LiarsDiceProps.top_face(cups.die_node(1, i).basis), cups.values_of(1)[i], "第 %d 颗点数朝上" % i)
		assert_eq(cups.die_node(1, i).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "骰子不投影")
	var rows := [{"pid": 1, "dice": [1, 2, 3, 5, 6]}, {"pid": 2, "dice": [4, 4]}, {"pid": 3, "dice": [1, 6, 6]}, {"pid": 4, "dice": [2]}]
	cups.reveal(rows)
	assert_eq(cups.dice_count(2), 2)
	assert_eq(cups.values_of(3), [1, 6, 6])
	assert_eq(cups.others_dice_count(), 6, "开盅时按 revealed 的点数建出来")
	await wait_seconds(LiarsDiceCups.LIFT_TIME + LiarsDiceCups.SPREAD_TIME + 0.15)
	for pid in [1, 2, 3, 4]:
		assert_eq(cups.state_of(pid), LiarsDiceCups.STATE_OPEN, "P%d 的盅翻开了" % pid)
	var row0 := LiarsDiceLayout.row_position(world.seat_angle_now(3), world.table_radius, 0, 3)
	assert_almost_eq(cups.die_node(3, 0).position.distance_to(row0), 0.0, 0.002, "骰子排成一行")
	cups.hop(3, 1)
	assert_same(cups.die_node(3, 1).mesh, LiarsDiceProps.die(true), "算进去的换发光网格")
	assert_eq(cups.find_children("Halo*", "MeshInstance3D", false, false).size(), 1, "底下一圈金光")
	cups.unglow_all()
	assert_same(cups.die_node(3, 1).mesh, LiarsDiceProps.die())
	await wait_seconds(0.1)
	assert_eq(cups.find_children("Halo*", "MeshInstance3D", false, false).size(), 0)


func test_pop_tip_and_gather():
	var cups := _arrange(3)
	cups.reveal([{"pid": 1, "dice": [2, 3]}, {"pid": 2, "dice": [5, 5, 6]}, {"pid": 3, "dice": [1]}])
	await wait_seconds(LiarsDiceCups.LIFT_TIME + LiarsDiceCups.SPREAD_TIME + 0.1)
	cups.pop_die(2)
	assert_eq(cups.dice_count(2), 2, "丢一颗")
	assert_eq(cups.values_of(2), [5, 5])
	cups.tip(3)
	cups.clear_dice(3)
	assert_eq(cups.state_of(3), LiarsDiceCups.STATE_TIPPED)
	assert_eq(cups.dice_count(3), 0)
	cups.gather([1, 2, 3])
	assert_eq(cups.others_dice_count(), 0, "新一轮:别人的骰子收走")
	await wait_seconds(maxf(LiarsDiceCups.GATHER_TIME, LiarsDiceCups.POP_TIME) + 0.1)
	assert_eq(cups.find_children("Die*", "MeshInstance3D", false, false).size(), 0, "收走的骰子释放了")


func test_shake_slams_the_cups_back_down_and_releases_paws():
	var cups := _arrange(3)
	cups.shake([1, 2, 3])
	assert_eq(cups.state_of(2), LiarsDiceCups.STATE_HELD)
	await wait_seconds(LiarsDiceCups.SHAKE_TOTAL + 0.15)
	for pid in [1, 2, 3]:
		assert_eq(cups.state_of(pid), LiarsDiceCups.STATE_DOWN)
		assert_true(cups.cups[pid].transform.is_equal_approx(cups.rest_of(pid)), "P%d 扣回原位" % pid)
	cups.set_my_dice([3, 4])
	cups.peek(1)
	await wait_seconds(LiarsDiceCups.PEEK_UP + 0.02)
	assert_false(cups.cups[1].transform.is_equal_approx(cups.rest_of(1)), "偷看时掀起盅沿")
	await wait_seconds(LiarsDiceCups.PEEK_TOTAL)
	assert_true(cups.cups[1].transform.is_equal_approx(cups.rest_of(1)), "看完扣回去")


func test_sync_tips_dead_cups_and_never_keeps_others_dice_under_closed_cups():
	var cups := _arrange(3)
	cups.sync({1: true, 2: false, 3: true}, [4, 5])
	assert_eq(cups.state_of(2), LiarsDiceCups.STATE_TIPPED)
	assert_eq(cups.values_of(1), [4, 5])
	assert_eq(cups.others_dice_count(), 0)


func test_hover_peek_picks_only_my_cup():
	var cups := _arrange(2)
	var center: Vector3 = world.to_global(cups.rest_of(1).origin + Vector3(0, 0.07, 0))
	var from := center + Vector3(0, 1.0, 0.8)
	assert_true(cups.pick_my_cup(from, (center - from).normalized()))
	assert_false(cups.pick_my_cup(from, Vector3.UP))
	cups.set_hover_peek(true)
	assert_true(cups.is_hover_peeking())
	cups.set_hover_peek(false)
	assert_false(cups.is_hover_peeking())


func test_clear_poker_frees_everything():
	var cups := _arrange(2)
	var fx := LiarsDiceFx.new(world)
	world.poker_root.add_child(fx)
	fx.bid_marker(3, 5)
	assert_eq(fx.marker_text(), "×3")
	assert_eq(fx.marker_face(), 5)
	fx.set_counter(2, 3)
	assert_eq(fx.counter_text(), "数到 2 / 喊了 3")
	world.clear_poker()
	await get_tree().process_frame
	assert_false(is_instance_valid(cups), "骰盅层随拆台释放")
	assert_false(is_instance_valid(fx))
