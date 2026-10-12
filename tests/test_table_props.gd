extends GutTest
# 桌面道具不穿帮:牌堆与翻牌行的牌都在毡面之上(底牌曾陷进桌布 0.3 mm、和毡面抢深度);牌背的弹孔数等于膛数。


func test_pile_and_reveal_cards_sit_above_the_felt():
	# 牌底(中面 − 半个牌厚)高出毡面,相邻两层不相交
	for seed in 20:
		for i in 30:
			var bottom := CardTable.pile_transform(i, seed).origin.y - Card3D.THICKNESS / 2.0
			assert_gte(bottom, SeatLayout.FELT_TOP + 0.0002, "牌堆第 %d 张的牌底" % i)
			if i > 0:
				var below := CardTable.pile_transform(i - 1, seed).origin.y + Card3D.THICKNESS / 2.0
				assert_gt(bottom, below, "第 %d 张不和下面那张相交" % i)
	for n in [1, 2, 3, 4]:
		for i in n:
			var bottom := CardTable.reveal_transform(i, n).origin.y - Card3D.THICKNESS / 2.0
			assert_gte(bottom, SeatLayout.FELT_TOP + 0.0002, "翻牌行")


func test_felt_matches_the_layout_constants():
	var tavern := Tavern.new()
	add_child_autofree(tavern)
	var felt: MeshInstance3D = tavern.get_node("Table/Felt")
	var box := felt.mesh.get_aabb()
	assert_almost_eq(felt.position.y + box.end.y, SeatLayout.FELT_TOP, 0.00001, "毡面顶 = FELT_TOP")
	assert_between(box.size.x / 2.0, SeatLayout.FELT_RADIUS - 0.003, SeatLayout.FELT_RADIUS, "毡面外沿")


func test_only_the_clip_spins():
	# 目标架:底座固定,只有立轴、叉形夹与目标牌在转;翻面回弹时牌底不低于夹子叶片下端
	var world := TableWorld.new(null)
	add_child_autofree(world)
	var stand: Node3D = world.cards.get_node("TargetStand")
	var spinner: Node3D = stand.get_node("Spinner")
	var card: Card3D = world.cards._target_card
	assert_true(spinner.is_ancestor_of(card), "目标牌挂在 Spinner 下")
	var stand_rot := stand.rotation
	var spin_rot := spinner.rotation.y
	await wait_frames(10)
	assert_eq(stand.rotation, stand_rot, "底座不转")
	assert_ne(spinner.rotation.y, spin_rot, "夹子在转")
	assert_almost_eq(world.cards.stand_position(), Vector3(0, SeatLayout.TABLE_TOP + CardTable.STAND_HEIGHT, 0), Vector3.ONE * 1e-5)
	var lowest := INF
	world.cards.call("set_target", Card.ACE)   # 协程:不等它,边播边取样
	var elapsed := 0.0
	while elapsed < CardTable.TARGET_FLIP_HALF * 2.0 + 0.35:
		var bottom := stand.to_local(card.global_transform * Vector3(0, 0, Card3D.HEIGHT / 2.0))
		lowest = minf(lowest, bottom.y)
		await wait_frames(1)
		elapsed += get_process_delta_time()
	assert_gte(lowest, StandModel.CLIP_BOTTOM, "牌底始终在夹口里,不插进立轴")
	var base: MeshInstance3D = stand.get_node("StandBase")
	var aabb := base.mesh.get_aabb()
	assert_almost_eq(aabb.position.y, SeatLayout.FELT_TOP - SeatLayout.TABLE_TOP, 0.0001, "底座坐在毡面上")
	assert_lte(maxf(aabb.size.x, aabb.size.z) / 2.0, 0.045, "裙边半径")
	assert_eq(spinner.get_node("Clip").cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "夹子不投影")


func test_card_back_has_one_hole_per_chamber():
	assert_eq(CardFaces.chamber_points(Vector2.ZERO, 44.0).size(), Revolver.CHAMBERS)


# —— 左轮 ——

const FAST_CLOCK := 8.0


func after_each():
	Engine.time_scale = 1.0


func _lowest_point(root: Node3D) -> float:
	# 节点下所有网格顶点的最低世界高度(无头测试里网格数组在 CPU 上,可以直接读)
	var lowest := INF
	for inst: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for v in inst.mesh.get_faces():
			lowest = minf(lowest, (inst.global_transform * v).y)
	return lowest


func _world(count: int) -> TableWorld:
	var world := TableWorld.new(null)
	add_child_autofree(world)
	var players := []
	for pid in range(1, count + 1):
		players.append({"pid": pid})
	world.arrange(players, 1, true, true)
	return world


func _part_points(gun: Revolver3D, part: String) -> PackedVector3Array:
	# 静置枪的转轮顶点 / 握把底帽顶点(全局坐标)
	var out := PackedVector3Array()
	var inst: MeshInstance3D = gun.get_node("Body/Drum/DrumMesh" if part == "drum" else "Body/BodyMesh")
	for s in inst.mesh.get_surface_count():
		for v: Vector3 in inst.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			if part == "drum" or v.y < -0.066:
				out.append(inst.global_transform * v)
	return out


func test_resting_guns_lie_on_felt_and_table():
	# 转轮压在毡面上、底帽落在毡面外的木桌面上:不悬空也不陷桌(按网格顶点精确算)
	for count in [2, 3, 4]:
		var world := _world(count)
		for pid in world.revolvers:
			var label := "%d 人局 %d 号座" % [count, pid]
			var drum := _part_points(world.revolvers[pid], "drum")
			var cap := _part_points(world.revolvers[pid], "cap")
			var drum_low := INF
			var drum_far := 0.0
			for v in drum:
				if v.y < drum_low:
					drum_low = v.y
					drum_far = Vector2(v.x, v.z).length()
			var cap_low := INF
			var cap_near := INF
			for v in cap:
				cap_low = minf(cap_low, v.y)
				cap_near = minf(cap_near, Vector2(v.x, v.z).length())
			assert_almost_eq(drum_low, SeatLayout.FELT_TOP, 0.001, label + " 转轮最低点在毡面上")
			assert_lt(drum_far, SeatLayout.FELT_RADIUS, label + " 转轮着地处在毡面范围内")
			assert_almost_eq(cap_low, SeatLayout.TABLE_TOP, 0.001, label + " 底帽落在木桌面上")
			assert_gt(cap_near, SeatLayout.FELT_RADIUS, label + " 底帽在毡面外")
			assert_gte(_lowest_point(world.revolvers[pid]), SeatLayout.TABLE_TOP - 0.0005, label + " 不陷桌")


func test_dropped_gun_lands_on_the_table():
	var world := _world(2)
	var patron: Patron = world.patrons[2]
	var gun: Revolver3D = world.revolvers[2]
	Engine.time_scale = FAST_CLOCK
	await wait_seconds(0.8)   # 等登场缩放动画放完
	await patron.pick_up(gun, 0.05)
	patron.die(gun, world)
	await wait_seconds(1.0)
	var flat := Vector2(gun.global_position.x, gun.global_position.z)
	assert_lt(flat.length(), SeatLayout.TABLE_RADIUS, "落在桌面范围内")
	assert_gte(_lowest_point(gun), SeatLayout.FELT_TOP - 0.0005, "不陷进桌布")


func test_muzzle_rests_against_the_temple_not_inside_the_head():
	var world := _world(4)
	Engine.time_scale = FAST_CLOCK
	await wait_seconds(0.8)   # 等登场缩放动画(0.55 s)放完,角色才是正常大小
	for pid in world.patrons:
		var patron: Patron = world.patrons[pid]
		var gun: Revolver3D = world.revolvers[pid]
		await patron.pick_up(gun, 0.05)
		await patron.raise_gun_to_head(gun, 0.05)
		var gap := gun.muzzle_transform().origin.distance_to(patron.head_position())
		# 枪口贴在太阳穴外(持枪净空 + 2~25 mm)。头缩放 1.0 时是原来的 0.172–0.20;动森式大头前后压扁(HEAD_DEPTH)、
		# 熊的颅骨收窄,太阳穴离头心不再整整是 1.95 倍,下限放到 0.15 倍(大头的 0.29 m),上限不变
		var k := patron.figure_scale   # 角色缩放(净空按原尺寸量的)
		var r := Patron.gun_clearance_for(patron.species_index) * k
		assert_between(gap, r + 0.002, r + 0.025, "%s 枪口到头心" % PatronParts.species(patron.species_index)["id"])
		assert_between(gap, 0.15 * Patron.head_scale() * k, 0.20 * Patron.head_scale() * k, "不插进头里,也不离太远")
