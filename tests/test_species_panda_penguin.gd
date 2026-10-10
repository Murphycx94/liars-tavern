extends GutTest
# 2026-10-10 追加的熊猫(下标 8)与企鹅(9):标志物在、在对的一侧;眼皮颜色跟着眼斑 / 白脸;物种自己的待机小动作能播完复位。
# 通用的结构、预算、几何约束由 test_patron_species 等按 Species.count() 一起守。


const PANDA := 8
const PENGUIN := 9


func _patron(i: int) -> Patron:
	var p := Patron.new(i)
	add_child_autofree(p)
	return p


func _head_vertices_with_color(p: Patron, want: Color, tolerance := 0.02) -> PackedVector3Array:
	# HeadMesh 里顶点色接近 want 的点(Head 局部)
	var mesh: ArrayMesh = (p.get_node("Body/Head/HeadMesh") as MeshInstance3D).mesh
	var out := PackedVector3Array()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for k in verts.size():
			var c := colors[k]
			if absf(c.r - want.r) < tolerance and absf(c.g - want.g) < tolerance and absf(c.b - want.b) < tolerance:
				out.append(verts[k])
	return out


func test_new_species_sit_at_the_end_of_the_catalog():
	assert_eq(Species.IDS[PANDA], "panda")
	assert_eq(Species.IDS[PENGUIN], "penguin")
	assert_eq(SpeciesLooks.look(PANDA)["id"], "panda")
	assert_eq(SpeciesLooks.look(PENGUIN)["id"], "penguin")


func test_panda_chews_a_bamboo_sprig_on_the_side_away_from_the_gun():
	# 竹枝在头部网格里(头像、对手视角都看得到);右手举枪抵右太阳穴、舌头从右嘴角吐出,竹枝在左边(-x)
	var p := _patron(PANDA)
	var pal := SpeciesLooks.palette(SpeciesLooks.look(PANDA))
	var green := _head_vertices_with_color(p, pal["bamboo"])
	assert_gt(green.size(), 50, "头上有竹枝")
	var leaves := _head_vertices_with_color(p, pal["leaf"])
	assert_gt(leaves.size(), 20, "竹枝上有叶子")
	for v in green + leaves:
		assert_lt(v.x, 0.0, "竹枝和叶子都在左边:%s" % v)


func test_eyelids_match_the_patch_and_the_white_face():
	for row: Array in [[PANDA, "patch"], [PENGUIN, "face"]]:
		var p := _patron(row[0])
		var lid: Vector3 = p.get_node("Body/Head/Eyes").get_instance_shader_parameter("lid_color")
		var want: Color = SpeciesLooks.palette(SpeciesLooks.look(row[0]))[row[1]]
		assert_almost_eq(lid, Vector3(want.r, want.g, want.b), Vector3.ONE * 0.001, Species.IDS[row[0]])


func test_penguin_has_no_ears_and_a_beanie():
	var p := _patron(PENGUIN)
	assert_eq(p._ears.size(), 0, "企鹅没有耳朵")
	var hat: MeshInstance3D = p.get_node("Body/Head/Hat/HatMesh")
	assert_gt(hat.mesh.get_faces().size(), 0, "毛线球帽有网格")


func test_own_fidgets_play_and_settle_back():
	for row: Array in [[PANDA, "chew"], [PENGUIN, "waddle"]]:
		var p := _patron(row[0])
		var antics: PatronAntics = p.get_node("Antics")
		assert_has(antics.fidget_kinds(), row[1], Species.IDS[row[0]])
		antics.play_fidget(row[1])
		var moved := false
		for i in 40:
			await wait_frames(1)
			moved = moved or antics.head_add.length() > 0.01
		await wait_seconds(1.6)
		assert_true(moved, "%s 的 %s 动起来了" % [Species.IDS[row[0]], row[1]])
		assert_almost_eq(antics.head_add.length(), 0.0, 0.001, "%s 播完回到原位" % row[1])
