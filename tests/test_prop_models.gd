extends GutTest
# 牌桌、烛台、吊灯(子项目③ §5–§7):台面是封闭圆盘且 r ≤ 0.98 内平整、毡面顶 = FELT_TOP、桌腿不出 0.5 米、
# 酒客躯干离桌沿 ≥ 1.5 cm;德州按半径换台面与毡面网格(按半径缓存,桌柱与腿不变)、聚光放宽、藏烛台连同烛光;
# 两个烛台各一盏灯、5 片火焰;吊灯零件都挂在 LampPivot 下、链条是 MultiMesh、灯罩和链条不投影;各道具的面数预算。

const SceneCensus := preload("res://tools/scene_census.gd")

var tavern: Tavern


func before_each():
	tavern = Tavern.new()
	add_child_autofree(tavern)


func _arrays(inst: MeshInstance3D) -> Array:
	# [顶点, 索引] 按 surface 拼起来(无头测试里网格数组在 CPU 上)
	var out := []
	for s in inst.mesh.get_surface_count():
		var a := inst.mesh.surface_get_arrays(s)
		out.append([a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_INDEX]])
	return out


func test_table_top_is_closed_and_flat():
	var top: MeshInstance3D = tavern.get_node("Table/TableTop")
	# 朝上的三角形按 2 cm 网格分桶,再在 r ∈ [0, 0.98] 每 1 cm、每 5° 向下打竖直射线
	var cell := 0.02
	var bins := {}
	for part in _arrays(top):
		var v: PackedVector3Array = part[0]
		var idx: PackedInt32Array = part[1]
		for k in range(0, idx.size(), 3):
			var a := v[idx[k]]
			var b := v[idx[k + 1]]
			var c := v[idx[k + 2]]
			if (c - a).cross(b - a).y <= 0.0:
				continue   # 只要朝上的面(Godot 正面顺时针)
			var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z)))
			var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z)))
			for i in range(floori(lo.x / cell), floori(hi.x / cell) + 1):
				for j in range(floori(lo.y / cell), floori(hi.y / cell) + 1):
					var key := Vector2i(i, j)
					if not bins.has(key):
						bins[key] = []
					bins[key].append([a, b, c])
	var misses := 0
	var off_level := 0
	var r := 0.0
	while r <= 0.9801:
		var steps := 1 if r == 0.0 else 72
		for s in steps:
			# 稍微错开车削的分段线与环线:射线正好擦过三角形的边时两边都可能不算命中
			var ang := TAU * s / 72.0 + 0.0017
			var p := Vector3(cos(ang) * (r + 0.0003), 2.0, sin(ang) * (r + 0.0003))
			var best := -INF
			for tri in bins.get(Vector2i(floori(p.x / cell), floori(p.z / cell)), []):
				var hit = Geometry3D.ray_intersects_triangle(p, Vector3.DOWN, tri[0], tri[1], tri[2])
				if hit != null:
					best = maxf(best, hit.y)
			if best == -INF:
				misses += 1
			elif absf(best - SeatLayout.TABLE_TOP) > 0.0006 and not (r < SeatLayout.FELT_RADIUS - 0.01 and best > SeatLayout.TABLE_TOP - 0.002 and best < SeatLayout.TABLE_TOP):
				off_level += 1
		r += 0.01
	assert_eq(misses, 0, "竖直射线都打在台面朝上的三角形上(封闭圆盘,吊灯光漏不到桌下)")
	assert_eq(off_level, 0, "r ≤ 0.98 处台面高度 = TABLE_TOP")
	var felt: MeshInstance3D = tavern.get_node("Table/Felt")
	assert_almost_eq(felt.mesh.get_aabb().end.y, SeatLayout.FELT_TOP, 0.0003, "毡面顶 = FELT_TOP")
	assert_eq(felt.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "桌布不投影")
	var base: MeshInstance3D = tavern.get_node("Table/TableBase")
	for part in _arrays(base):
		for v: Vector3 in part[0]:
			assert_lte(Vector2(v.x, v.z).length(), 0.5, "桌腿不出 0.5 米")
			if Vector2(v.x, v.z).length() > 0.5:
				return


func _profile_distance(p: Vector2, profile: PackedVector2Array) -> float:
	var best := INF
	for k in profile.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, profile[k], profile[k + 1])))
	return best


func test_table_clears_every_torso():
	# 8 个物种坐下、轮到自己时再前倾:躯干网格离台面轮廓(圆鼻边)都 ≥ 1.5 cm
	var profile := TableProp.profile(SeatLayout.TABLE_RADIUS)
	for i in Species.count():
		var patron := Patron.new(i)
		patron.transform = Transform3D(Basis(), Vector3(0, 0, SeatLayout.SEAT_RADIUS))
		add_child_autofree(patron)
		patron.set_active(true)
		await wait_seconds(1.2)
		var body_mesh: MeshInstance3D = patron.get_node("Figure/Body/BodyMesh")
		var closest := INF
		for part in _arrays(body_mesh):
			for v: Vector3 in part[0]:
				var w := body_mesh.global_transform * v
				closest = minf(closest, _profile_distance(Vector2(Vector2(w.x, w.z).length(), w.y), profile))
		assert_gte(closest, 0.015, "%s 的躯干离桌沿" % PatronParts.species(i)["id"])
		patron.queue_free()


func test_set_table_radius_rebuilds_top_and_felt_per_radius():
	var top: MeshInstance3D = tavern.get_node("Table/TableTop")
	var felt: MeshInstance3D = tavern.get_node("Table/Felt")
	var base: MeshInstance3D = tavern.get_node("Table/TableBase")
	var liars_top := top.mesh
	var liars_felt := felt.mesh
	var legs := base.mesh
	var poker := SeatLayout.POKER_TABLE_RADIUS
	tavern.set_table_radius(poker)
	assert_almost_eq(top.mesh.get_aabb().size.x / 2.0, poker + TableProp.FLAT_REACH + TableProp.NOSE, 0.002, "台面外沿跟着半径")
	assert_almost_eq(top.mesh.get_aabb().end.y, SeatLayout.TABLE_TOP + 0.0005, 0.0002, "桌面高度不变(嵌条高出 0.5 mm)")
	assert_almost_eq(felt.mesh.get_aabb().size.x / 2.0, TableProp.felt_radius(poker) - 0.002, 0.002, "毡面跟着半径")
	assert_almost_eq(felt.mesh.get_aabb().end.y, SeatLayout.FELT_TOP, 0.0003)
	assert_gt(TableProp.felt_radius(poker), PokerLayout.STACK_INSET + 0.03, "筹码堆在毡面上")
	assert_same(base.mesh, legs, "桌柱与腿不动")
	assert_eq(tavern.get_node("Table").scale, Vector3.ONE, "不再整张桌横向缩放")
	var poker_top := top.mesh
	tavern.set_table_radius(SeatLayout.TABLE_RADIUS)
	assert_same(top.mesh, liars_top, "按半径缓存")
	assert_same(felt.mesh, liars_felt)
	tavern.set_table_radius(poker)
	assert_same(top.mesh, poker_top)


func test_decor_visibility_hides_the_candle_lights():
	var holders := tavern.get_children().filter(func(n): return String(n.name).begins_with("Candles"))
	tavern.set_table_decor_visible(false)
	for holder in holders:
		for light: OmniLight3D in holder.find_children("*", "OmniLight3D", false, false):
			assert_false(light.is_visible_in_tree(), "烛光跟着烛台藏起来")
	assert_true((tavern.get_node("TableRimLight") as Light3D).visible, "留一盏桌沿暖光")
	tavern.set_table_decor_visible(true)
	for holder in holders:
		assert_true(holder.visible)


func test_candle_holders():
	var holders := tavern.get_children().filter(func(n): return String(n.name).begins_with("Candles"))
	assert_eq(holders.map(func(n): return String(n.name)), ["Candles0", "Candles1"], "两个烛台各自命名")
	var flames := 0
	for k in holders.size():
		var holder: Node3D = holders[k]
		var lights := holder.get_children().filter(func(n): return n is OmniLight3D)
		assert_eq(lights.size(), 1, "%s 恰有一盏灯(直接子节点)" % holder.name)
		var flickering := tavern._flickers.filter(func(f): return f["light"] == lights[0])
		assert_eq(flickering.size(), 1, "烛光在闪烁表里")
		var mesh: MeshInstance3D = holder.get_node("Holder")
		var box := mesh.mesh.get_aabb()
		assert_lte(maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z))), 0.09, "碟子半宽")
		assert_almost_eq(TableWorld.angle_of(holder.position), CandlesProp.SPECS[k][0], 0.001, "角度不变")
		flames += holder.get_children().filter(func(n): return n is MeshInstance3D and n.material_override == WorldMaterials.flame()).size()
	assert_eq(flames, 5, "共 5 片火焰")


func test_lamp_parts_hang_under_the_pivot():
	var pivot: Node3D = tavern.get_node("LampPivot")
	var shade: MeshInstance3D = pivot.get_node("LampMesh")
	var chain: MultiMeshInstance3D = pivot.get_node("LampChain")
	assert_eq(shade.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "灯罩不投影")
	assert_eq(chain.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "链条不投影")
	assert_gte(chain.multimesh.instance_count, 40, "链节数")
	var lights := tavern.find_children("*", "Light3D", true, false).filter(func(l): return pivot.is_ancestor_of(l))
	assert_eq(lights.size(), 2)
	for light in lights:
		assert_eq(light.get_parent(), pivot, "灯的直接父节点是 LampPivot")
	var box := shade.mesh.get_aabb()
	assert_lte(box.size.x / 2.0, 0.38, "灯罩半径")


func test_cameras_see_under_the_shade():
	# 观战 / 越肩 / 等待厅机位看 2–4 人局各座位头部的视线,在灯罩半径(加摆幅余量)范围内都低于罩口 5 cm 以上
	var lowest := Tavern.ROOM_HEIGHT + LampProp.MOUTH_Y - LampProp.BEAD - 0.05
	var reach := LampProp.MOUTH_RADIUS + 0.1
	for count in [2, 3, 4]:
		var world := TableWorld.new(null)
		add_child_autofree(world)
		var players := []
		for pid in range(1, count + 1):
			players.append({"pid": pid})
		world.arrange(players, 1, true, false)
		for view in [world.overview_view(), world.third_person_view(1), world.lobby_view()]:
			for pid in world.seat_angles:
				var head := SeatLayout.seat_position(world.seat_angles[pid]) + Vector3(0, 1.32, 0)
				for s in 41:
					var p: Vector3 = view.origin.lerp(head, s / 40.0)
					if Vector2(p.x, p.z).length() < reach:
						assert_lte(p.y, lowest, "%d 人局看 %d 号座的视线" % [count, pid])


func test_prop_budgets():
	assert_lte(SceneCensus.count(tavern.get_node("Table"))["triangles"], 12000, "牌桌")
	assert_lte(SceneCensus.count(tavern.get_node("Candles0"))["triangles"], 3000, "单个烛台")
	assert_lte(SceneCensus.count(tavern.get_node("LampPivot"))["triangles"], 7000 + 100 * 43, "吊灯(含链条)")
	assert_lte(SceneCensus.count(tavern.get_node("LampPivot/LampMesh"))["triangles"], 7000, "灯罩")
	var world := TableWorld.new(null)
	add_child_autofree(world)
	assert_lte(SceneCensus.count(world.cards.get_node("TargetStand"))["triangles"], 3000 + 112, "目标架(含目标牌)")
