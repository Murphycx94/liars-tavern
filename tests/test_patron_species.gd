extends GutTest
# 全部物种(2026-10-10 起 10 个)逐个检查结构、预算与几何约束(无头;网格数组在 CPU 上)。这些约束守的是动画与镜头:
# 头心是瞄准点与机位目标、脖子是单位高网格、帽顶不碰名牌、头不往后挡自己的手牌、胸前让出对手的牌扇、
# 膝盖在桌下、脚让开椅腿、尾巴不穿座面。外观怎么改都要守住。

# 动森式 2 头身(2026-10-08,接在 Q 版之后):头按头心放大 PatronParts.HEAD_SCALE 1.95 倍(前后再乘 HEAD_DEPTH),
# 帽子竖向只放 HAT_SCALE_Y。下面几条按实测放宽,意图不变——帽顶不碰名牌:头枢轴在座位上方 ≈1.12 m(坐直),
# 0.66 的帽顶 + 欢呼蹦起 0.08 ≈1.86 m,低于 Patron.NAMEPLATE_HEIGHT 1.92(Q 版 0.627、写实 0.51;羊驼单列的 0.588 并进来,
# 它的耳朵改短后和别人一样);头不往后伸进越肩镜头和手牌之间(test_hand_visibility 按三角形实测遮挡,
# 最远的是猫的宽檐牛仔帽后檐 ≈0.363,Q 版 0.286、写实 0.22)
const HEAD_TOP := 0.66      # 帽顶、耳尖在 Head 局部的上限(狐狸礼帽 ≈0.640、羊驼耳尖 ≈0.628)
const BEHIND := 0.37        # 头部几何离头心往后(+Z,朝越肩镜头)最多这么远
# 吻尖 z 下限(放大前;乘以头的前后放大倍数):动森式吻更短更圆,狐狸 -0.3 → -0.25、羊驼 -0.27 → -0.23;其余 -0.22
const FRONT_TIP := {"fox": -0.25, "alpaca": -0.23, "crocodile": -0.38}
const CHEST_FRONT := -0.24      # 胸前(身体局部 y 0.35–0.55)最靠前的 z
const MAX_VISIBLE := 16
const MAX_TRIANGLES := 15000


func _patron(i: int) -> Patron:
	var p := Patron.new(i)
	add_child_autofree(p)
	return p


func _faces(inst: MeshInstance3D) -> PackedVector3Array:
	return inst.mesh.get_faces() if inst.mesh != null else PackedVector3Array()


func _points(mesh_owner: MeshInstance3D, space: Node3D) -> PackedVector3Array:
	# 网格顶点换到 space 的局部坐标
	var out := PackedVector3Array()
	var xform := space.global_transform.affine_inverse() * mesh_owner.global_transform
	for v in _faces(mesh_owner):
		out.append(xform * v)
	return out


func test_structure_and_budget_for_every_species():
	for i in Species.count():
		var p := _patron(i)
		var id: String = Species.IDS[i]
		for path in ["Chair", "Legs", "Body", "Body/Neck", "Body/Head", "Body/Head/Hat", "Body/ArmL/Hand", "Body/ArmR/Hand", "Body/Fan"]:
			assert_not_null(p.get_node_or_null(path), "%s 缺 %s" % [id, path])
		var visible := p.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.visible)
		assert_lte(visible.size(), MAX_VISIBLE, id + " 可见网格")
		var tris := 0
		for m: MeshInstance3D in visible:
			tris += _faces(m).size() / 3
		assert_lte(tris, MAX_TRIANGLES, id + " 三角形(含椅子)")


func test_neck_stays_a_unit_height_mesh():
	for i in Species.count():
		var p := _patron(i)
		var neck: MeshInstance3D = p.get_node("Body/Neck/NeckMesh")
		var box := neck.mesh.get_aabb()
		assert_almost_eq(box.position.y, 0.0, 0.001, Species.IDS[i])
		assert_almost_eq(box.end.y, 1.0, 0.001, Species.IDS[i])
		assert_eq(p.get_node("Body/Neck").get_child_count(), 1, "脖子上不挂别的东西")


func test_head_center_hat_height_and_nothing_far_behind():
	for i in Species.count():
		var p := _patron(i)
		var id: String = Species.IDS[i]
		var look := SpeciesLooks.look(i)
		assert_eq(look["head"]["skull"][0][0], Vector3(0, 0.12, 0), id + " 主颅骨中心就是头心")
		var head: Node3D = p.head
		var top := -INF
		var back := -INF
		for m: MeshInstance3D in head.find_children("*", "MeshInstance3D", true, false):
			for v in _points(m, head):
				top = maxf(top, v.y)
				back = maxf(back, v.z - 0.0)
		assert_lte(top, HEAD_TOP + 0.002, id + " 帽顶/耳尖高度")
		assert_lte(back, BEHIND, id + " 头部往后伸")


func test_chest_leaves_room_for_opponents_card_fan():
	for i in Species.count():
		var p := _patron(i)
		var body_mesh: MeshInstance3D = p.get_node("Body/BodyMesh")
		var front := INF
		for v in _points(body_mesh, p.body):
			if v.y >= 0.35 and v.y <= 0.55:
				front = minf(front, v.z)
		assert_gte(front, CHEST_FRONT, Species.IDS[i] + " 胸前")


func test_knees_under_the_table_and_feet_clear_the_chair_legs():
	for i in Species.count():
		var p := _patron(i)
		var legs: MeshInstance3D = p.get_node("Legs")
		var id: String = Species.IDS[i]
		var tail_path: Array = SpeciesLooks.look(i).get("tail", {}).get("path", [])
		var tail_root_z: float = tail_path[0].z if not tail_path.is_empty() else INF
		for v in _points(legs, p):
			if v.z < tail_root_z - 0.05 and v.z < 0.05:   # 腿(尾巴在座位后面,另测)
				assert_lte(v.y, 0.6, "%s 膝盖 %s" % [id, v])
				if v.y < 0.3 and absf(v.z - ChairBuilder.FRONT_LEG_Z) < 0.03:
					assert_lte(absf(v.x), ChairBuilder.LEG_X - ChairBuilder.LEG_RADIUS, "%s 脚碰椅腿 %s" % [id, v])


func test_tails_do_not_pass_through_the_seat():
	for i in Species.count():
		var t: Dictionary = SpeciesLooks.look(i).get("tail", {})
		if t.is_empty():
			continue
		var seat: Array = ChairBuilder.solids()[0]
		var center: Vector3 = seat[1]
		var half: Vector3 = seat[2]
		for point in t["path"]:
			var d: Vector3 = (point - center).abs()
			assert_false(d.x < half.x - 0.02 and d.y < half.y and d.z < half.z - 0.02,
				"%s 尾巴路径点 %s 在座面实体里" % [Species.IDS[i], point])


func test_species_recipes_are_deterministic():
	for i in [0, 7]:
		var spec := PatronParts.species(i)
		var a: Array = MeshForge.run(PatronParts.recipes(spec)["head"])[&"main"]
		var b: Array = MeshForge.run(PatronParts.recipes(spec)["head"])[&"main"]
		assert_eq(a[Mesh.ARRAY_VERTEX], b[Mesh.ARRAY_VERTEX], Species.IDS[i])


func test_eyes_get_their_species_parameters():
	var cat := _patron(3)
	var eye: MeshInstance3D = cat.get_node("Body/Head/Eyes")
	assert_eq(eye.get_instance_shader_parameter("pupil_shape"), 1.0, "猫是竖瞳")
	assert_eq(eye.mesh.surface_get_material(0), WorldMaterials.patron_eye())
	var turtle := _patron(4)
	assert_gt(float(turtle.get_node("Body/Head/Eyes").get_instance_shader_parameter("lid_rest")), 0.3, "乌龟眼皮厚")


func test_fist_swaps_in_when_holding_the_gun():
	var world := TableWorld.new(null)
	add_child_autofree(world)
	world.arrange([{"pid": 1}, {"pid": 2}], 1, true, true)
	var patron: Patron = world.patrons[2]
	var fist: MeshInstance3D = patron.right_hand.get_node("FistMesh")
	assert_false(fist.visible)
	Engine.time_scale = 8.0
	await wait_seconds(0.8)
	await patron.pick_up(world.revolvers[2], 0.05)
	assert_true(fist.visible, "握枪是拳头")
	assert_false(patron.right_hand.get_node("PawMesh").visible)
	patron.reset_pose()
	assert_false(fist.visible, "复位后换回张开的爪")
	Engine.time_scale = 1.0


func test_every_species_reaches_equally_far():
	# 2026-10-09 用户要求:所有物种(含长吻的鳄鱼)脖子都一样最远伸到 NECK_REACH
	for i in Species.count():
		var p := _patron(i)
		p.set_neck_target(Vector3(0, 0, -5.0))
		assert_almost_eq(p._neck_target.length(), Patron.NECK_REACH, 0.0001, Species.IDS[i])


func test_snout_tips_and_forward_reach():
	# 头部往前伸(吻、鼻、帽檐)按放大后的尺寸量:吻尖不超过各物种的下限 × 头的前后放大倍数(HEAD_SCALE × HEAD_DEPTH,
	# 鳄鱼是 HEAD_SCALE × scale_z)
	for i in Species.count():
		var p := _patron(i)
		var id: String = Species.IDS[i]
		var head_mesh: MeshInstance3D = p.get_node("Body/Head/HeadMesh")
		var tip := INF
		for v in _points(head_mesh, p.head):
			tip = minf(tip, v.z)
		var scale_z: float = PatronParts.head_scale(SpeciesLooks.look(i)).z
		assert_gte(tip, FRONT_TIP.get(id, -0.22) * scale_z - 0.002, id + " 吻尖")
