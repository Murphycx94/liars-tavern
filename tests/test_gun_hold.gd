extends GutTest
# 握枪与举枪(子项目③ §2.4):枪挂在右手的 HOLD_OFFSET 上,手举到按物种净空求出的手位后「转手不转枪」,
# 枪管轴线穿过头心、枪口贴在太阳穴外;放下枪、出局、复位后手的转角回到单位;枪不插进头、耳朵或帽子。


const FAST_CLOCK := 8.0
const RAISE_SETTLE := 0.5    # 举枪结束后再等的游戏秒(头回正、坐直的插值)
const DRIFT_WINDOW := 1.5    # 之后观察头心漂移的时长
const BARREL_RADIUS := RevolverModel.BARREL_RADIUS   # 枪管半径(玩具感左轮一路加粗:0.0105 → 0.0128 → 0.0142):沿枪管表面上下左右取样


func after_each():
	Engine.time_scale = 1.0


func _clearance(patron: Patron) -> float:
	return patron._gun_clearance()


func _hold(species: int) -> Array:
	# 按导演流程:先看自己的头,再拿枪、举到太阳穴。返回 [酒客, 枪]
	var stage: Node3D = add_child_autofree(Node3D.new())
	var patron := Patron.new(species)
	stage.add_child(patron)
	var gun := Revolver3D.new()
	stage.add_child(gun)
	gun.global_transform = Transform3D(Basis(), patron.global_transform * Vector3(0.3, SeatLayout.FELT_TOP + 0.02, -0.45))
	Engine.time_scale = FAST_CLOCK
	patron.look_at_point(patron.head_position())
	await patron.pick_up(gun, 0.2)
	await patron.raise_gun_to_head(gun, 0.3)
	await wait_seconds(RAISE_SETTLE)
	return [patron, gun, stage]


func _axis_miss(gun: Revolver3D, center: Vector3) -> float:
	# 枪管轴线(枪本地 y = BARREL_Y、沿 −Z)到 center 的距离
	var xf := gun.global_transform.orthonormalized()
	var origin := xf * Vector3(0, Revolver3D.BARREL_Y, 0)
	var dir := -xf.basis.z
	var to_center := center - origin
	return (to_center - dir * to_center.dot(dir)).length()


func test_muzzle_rests_on_the_temple_for_every_species():
	for i in Species.count():
		var held: Array = await _hold(i)
		var patron: Patron = held[0]
		var gun: Revolver3D = held[1]
		var label: String = PatronParts.species(i)["id"]
		var r := _clearance(patron)
		var center := patron.head_position()
		var gap := gun.muzzle_transform().origin.distance_to(center)
		assert_between(gap, r + 0.002, r + 0.025, "%s 枪口到头心(净空 %.3f)" % [label, r])
		assert_lte(_axis_miss(gun, center), 0.01, "%s 枪管轴线穿过头心" % label)
		# 之后头心相对枪的漂移(呼吸、坐直让头和手一起动,只看两者之间)
		var in_gun := gun.global_transform.affine_inverse() * center
		var drift := 0.0
		var t := 0.0
		while t < DRIFT_WINDOW:
			await wait_frames(1)
			t += get_process_delta_time() * Engine.time_scale
			drift = maxf(drift, (gun.global_transform.affine_inverse() * patron.head_position()).distance_to(in_gun))
		assert_lte(drift, 0.005, "%s 举着枪时头心相对枪不漂" % label)
		Engine.time_scale = 1.0
		held[2].queue_free()


func _gun_samples(gun: Revolver3D) -> PackedVector3Array:
	# 枪口冠中心、准星顶、枪管表面上下左右每 1 cm 一圈点(全局坐标)
	var xf := gun.global_transform
	var points := PackedVector3Array([xf * Revolver3D.MUZZLE_POS, xf * Vector3(0, Revolver3D.BARREL_Y + 0.019, -0.242)])
	var z := -0.075
	while z > -0.256:
		for d: Vector2 in [Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0), Vector2(0, -1)]:
			points.append(xf * Vector3(d.x * BARREL_RADIUS, Revolver3D.BARREL_Y + d.y * BARREL_RADIUS, z))
		z -= 0.01
	return points


func _inside(point: Vector3, inst: MeshInstance3D) -> bool:
	# 网格局部沿 +X 发射线,与三角形交点数为奇数即在网格里面(无头测试里可以读网格数组)
	var local := inst.global_transform.affine_inverse() * point
	if not inst.mesh.get_aabb().grow(0.001).has_point(local):
		return false
	var faces := inst.mesh.get_faces()
	var hits := 0
	for k in range(0, faces.size(), 3):
		if Geometry3D.ray_intersects_triangle(local, Vector3.RIGHT, faces[k], faces[k + 1], faces[k + 2]) != null:
			hits += 1
	return hits % 2 == 1


func _assert_outside_the_head(patron: Patron, gun: Revolver3D, label: String) -> void:
	var meshes := patron.head.find_children("*", "MeshInstance3D", true, false)
	var offenders := []
	for point in _gun_samples(gun):
		for inst: MeshInstance3D in meshes:
			if inst.is_visible_in_tree() and _inside(point, inst):
				offenders.append(String(inst.name))
	assert_eq(offenders, [], label)


func test_gun_never_enters_the_head():
	for i in Species.count():
		var held: Array = await _hold(i)
		var patron: Patron = held[0]
		var gun: Revolver3D = held[1]
		var label: String = PatronParts.species(i)["id"]
		Engine.time_scale = 1.0
		_assert_outside_the_head(patron, gun, label)
		for ear in patron._ears:
			ear.rotation.x -= 0.3   # 抖耳朵
		_assert_outside_the_head(patron, gun, label + "(抖耳)")
		held[2].queue_free()


func test_gun_hand_target_reaches_the_wanted_distance():
	var center := Patron.HEAD_PIVOT + Vector3(0, 0.12, 0)
	var clearance := 0.14
	while clearance <= 0.2201:
		var hand := Patron.gun_hand_target(clearance)
		assert_almost_eq(hand.distance_to(Patron.SHOULDER), Patron.ARM_LENGTH, 0.0001, "手在肩球面上")
		var muzzle := Patron.gun_pose(hand, center) * Revolver3D.MUZZLE_POS
		assert_almost_eq(muzzle.distance_to(center), clearance + Patron.GUN_CLEARANCE, 0.001, "净空 %.2f 的枪口距离" % clearance)
		assert_gt(hand.y, Patron.SHOULDER.y, "手高于肩")
		clearance += 0.01
	assert_almost_eq(Patron.HAND_GUN_HEAD.distance_to(Patron.gun_hand_target(Patron.DEFAULT_GUN_CLEARANCE)), 0.0, 0.0005,
		"HAND_GUN_HEAD 是默认净空的解")
	assert_almost_eq(Patron.GUN_APPROACH.distance_to(Vector3(1, 0.25, -0.1).normalized()), 0.0, 0.0002)


func test_hand_rotation_resets_after_lowering_and_dying():
	var held: Array = await _hold(0)
	var patron: Patron = held[0]
	var gun: Revolver3D = held[1]
	assert_false(patron.right_hand.quaternion.is_equal_approx(Quaternion.IDENTITY), "举枪时转了手")
	assert_true(gun.transform.is_equal_approx(Revolver3D.HOLD_OFFSET), "枪相对手始终是 HOLD_OFFSET")
	await patron.lower_gun(gun, Transform3D(Basis(), Vector3(0.3, SeatLayout.FELT_TOP + 0.03, -0.45)), held[2], 0.2)
	assert_true(patron.right_hand.quaternion.is_equal_approx(Quaternion.IDENTITY), "放下枪后手转回来")
	assert_eq(patron.right_hand.position, Vector3(0, 0, -Patron.ARM_LENGTH))
	await patron.pick_up(gun, 0.1)
	await patron.raise_gun_to_head(gun, 0.1)
	patron.die(gun, held[2])
	assert_true(patron.right_hand.quaternion.is_equal_approx(Quaternion.IDENTITY), "出局时手复位")
	assert_eq(patron.right_hand.position, Vector3(0, 0, -Patron.ARM_LENGTH))
