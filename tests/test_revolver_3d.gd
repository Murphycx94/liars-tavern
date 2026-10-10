extends GutTest
# 左轮模型与规则一致:弹膛孔数等于 Revolver.CHAMBERS,每扳一次击锤转轮转一格。


func test_drum_has_one_bore_per_chamber():
	var gun := Revolver3D.new()
	add_child_autofree(gun)
	var bores := gun.drum.get_children().filter(func(n): return n.name.begins_with("Chamber"))
	assert_eq(bores.size(), Revolver.CHAMBERS)


func test_cocking_advances_the_drum_one_chamber():
	var gun := Revolver3D.new()
	add_child_autofree(gun)
	var before := gun.drum.rotation.z
	await gun.cock_hammer(0.05).finished
	assert_almost_eq(gun.drum.rotation.z - before, TAU / Revolver.CHAMBERS, 0.0001)


func test_revolver_is_three_shared_meshes():
	# 合批:机身 / 转轮 / 击锤各一个实例,所有左轮共用同一份网格(自动实例化)
	var a := Revolver3D.new()
	var b := Revolver3D.new()
	add_child_autofree(a)
	add_child_autofree(b)
	var meshes_a := a.find_children("*", "MeshInstance3D", true, false)
	var meshes_b := b.find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes_a.size(), 3)
	for i in meshes_a.size():
		assert_same(meshes_a[i].mesh, meshes_b[i].mesh, meshes_a[i].name)


func test_chambers_are_markers():
	var gun := Revolver3D.new()
	add_child_autofree(gun)
	for node in gun.drum.get_children().filter(func(n): return n.name.begins_with("Chamber")):
		assert_true(node is Marker3D, node.name)


func test_spinning_stops_on_a_whole_chamber():
	var gun := Revolver3D.new()
	add_child_autofree(gun)
	await gun.spin_drum(0.05, 2.37).finished
	await gun.cock_hammer(0.05).finished
	var step := TAU / Revolver.CHAMBERS
	var rest := fposmod(gun.drum.rotation.z, step)
	assert_true(rest < 0.001 or step - rest < 0.001, "停在整格(余 %.4f)" % rest)


func test_a_chamber_lines_up_with_the_barrel():
	var gun := Revolver3D.new()
	add_child_autofree(gun)
	var chamber: Marker3D = gun.drum.get_node("Chamber1")
	var p := gun.to_local(chamber.global_position)
	assert_almost_eq(p.x, 0.0, 0.0005)
	assert_almost_eq(p.y, Revolver3D.MUZZLE_POS.y, 0.002)


# —— 重塑后的左轮(子项目③ §2)——

const SceneCensus := preload("res://tools/scene_census.gd")


func _verts(inst: MeshInstance3D, xform: Transform3D) -> PackedVector3Array:
	# 无头测试里网格数组在 CPU 上,可以直接读(src 里禁止)
	var out := PackedVector3Array()
	for s in inst.mesh.get_surface_count():
		for v: Vector3 in inst.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			out.append(xform * v)
	return out


func _in_gun(gun: Revolver3D, node: Node3D) -> Transform3D:
	# 节点相对枪根的变换(不依赖是否在场景树里)
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != gun:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _assert_a_chamber_on_the_barrel_axis(gun: Revolver3D, label: String) -> void:
	var hits := 0
	for marker in gun.drum.get_children().filter(func(n): return n.name.begins_with("Chamber")):
		var p := _in_gun(gun, marker).origin
		if absf(p.x) < 0.0005 and absf(p.y - Revolver3D.BARREL_Y) < 0.0005:
			hits += 1
	assert_eq(hits, 1, label + ":恰好一个弹膛与枪管同轴")


func test_a_chamber_lines_up_with_the_barrel_after_cocking_and_spinning():
	var gun := Revolver3D.new()
	add_child_autofree(gun)
	_assert_a_chamber_on_the_barrel_axis(gun, "初始")
	await gun.cock_hammer(0.05).finished
	_assert_a_chamber_on_the_barrel_axis(gun, "扳击锤之后")
	await gun.spin_drum(0.05, 2.37).finished
	_assert_a_chamber_on_the_barrel_axis(gun, "转轮之后")
	assert_almost_eq(Revolver3D.aligned_angle(0.3 * Revolver3D.CHAMBER_STEP), 0.0, 1e-6)
	assert_almost_eq(Revolver3D.aligned_angle(2.6 * Revolver3D.CHAMBER_STEP), 3.0 * Revolver3D.CHAMBER_STEP, 1e-6)


func test_drum_mesh_is_five_fold_symmetric():
	# 五个弹膛外观完全一样:转轮网格每个顶点绕 Z 转一格后,都能在 0.1 mm 内找到原有顶点(空间哈希)
	var gun := Revolver3D.new()
	add_child_autofree(gun)
	var drum_mesh: MeshInstance3D = gun.drum.get_node("DrumMesh")
	var verts := _verts(drum_mesh, Transform3D.IDENTITY)
	var cell := 0.0005
	var grid := {}
	for v in verts:
		var key := Vector3i((v / cell).floor())
		if not grid.has(key):
			grid[key] = []
		grid[key].append(v)
	var turn := Basis(Vector3.BACK, Revolver3D.CHAMBER_STEP)
	var missing := 0
	for v in verts:
		var r := turn * v
		var key := Vector3i((r / cell).floor())
		var found := false
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for w in grid.get(key + Vector3i(dx, dy, dz), []):
						if w.distance_to(r) < 0.0001:
							found = true
		if not found:
			missing += 1
	assert_eq(missing, 0, "转一格后找不到对应顶点的个数")
	var others := gun.drum.get_children().filter(func(n): return not (n is Marker3D) and n != drum_mesh)
	assert_eq(others, [], "转轮下除弹膛标记外只有网格")


func test_guns_share_meshes_and_stay_in_budget():
	var a := Revolver3D.new()
	var b := Revolver3D.new()
	add_child_autofree(a)
	add_child_autofree(b)
	var census := SceneCensus.count(a)
	assert_eq(census["meshes"], 3, "机身 / 转轮 / 击锤各一个实例")
	assert_lte(census["triangles"], 8000)
	var surfaces := 0
	for inst: MeshInstance3D in a.find_children("*", "MeshInstance3D", true, false):
		surfaces += inst.mesh.get_surface_count()
	assert_eq(surfaces, 3, "机身、转轮、击锤各一个 prop surface(握把换成糖果色顶点色,不再单开木纹 surface)")
	for name in ["Body/BodyMesh", "Body/Drum/DrumMesh", "Body/Hammer/HammerMesh"]:
		assert_same(a.get_node(name).mesh, b.get_node(name).mesh, name)


func _lowest(points: PackedVector3Array, basis: Basis) -> float:
	var low := INF
	for v in points:
		low = minf(low, (basis * v).y)
	return low


func test_rest_constants_match_the_mesh():
	var gun := Revolver3D.new()
	add_child_autofree(gun)
	var drum := _verts(gun.drum.get_node("DrumMesh"), _in_gun(gun, gun.drum.get_node("DrumMesh")))
	var body := _verts(gun.get_node("Body/BodyMesh"), Transform3D.IDENTITY)
	var cap := PackedVector3Array()
	for v in body:
		if v.y < -0.066:
			cap.append(v)   # 握把下端与黄铜底帽
	var all := drum + body
	# 地上:转轮与底帽同时着地,最低点离原点 REST_HALF_WIDTH
	var floor_basis := Basis(Vector3.BACK, PI / 2.0 + Revolver3D.REST_ROLL)
	assert_almost_eq(_lowest(drum, floor_basis), _lowest(cap, floor_basis), 0.0005, "地上:转轮与底帽一样低")
	assert_almost_eq(-_lowest(all, floor_basis), Revolver3D.REST_HALF_WIDTH, 0.0005, "地上:最低点")
	# 桌上:转轮比底帽高出毡面厚度,转轮最低点离原点 TABLE_REST_LIFT
	var table_basis := Basis(Vector3.BACK, PI / 2.0 + Revolver3D.TABLE_REST_ROLL)
	assert_almost_eq(_lowest(drum, table_basis) - _lowest(cap, table_basis), SeatLayout.FELT_TOP - SeatLayout.TABLE_TOP, 0.0005,
		"桌上:转轮比底帽高 4 mm")
	assert_almost_eq(-_lowest(drum, table_basis), Revolver3D.TABLE_REST_LIFT, 0.0005, "桌上:转轮最低点")
	# 枪口标记在枪口冠前方,离握持点不超过 0.27
	var crown := INF
	for v in body:
		crown = minf(crown, v.z)
	assert_lte(Revolver3D.MUZZLE_POS.z, crown, "枪口标记不在枪管里")
	assert_lte(absf(Revolver3D.MUZZLE_POS.z), 0.27)
