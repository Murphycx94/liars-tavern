extends GutTest
# 穿模修复(2026-10-10,规格 2026-10-08-cozy-toon-style-design §穿模修复):牌、头、手臂与酒客网格不相交。
# 判定按真实三角形(tests/clip_probe.gd:TriangleMesh 线段求交),姿势走 Patron 自己的逐帧逻辑;完整的计数报告见 tools/clip_report.gd。
# 这里取包络的角上与最容易出事的几组,守住:他人的牌扇不碰持牌者、探头不进别人的头与身体和桌心道具、
# 第一人称手里的牌画面不变而离眼睛更近、出局的牌扇落在桌上、欢呼与鼓掌的爪子不进大头、物种网格没有甩出去的细条。

const Probe := preload("res://tests/clip_probe.gd")
const SETTLE := 0.9
const FANS := [["liars", 5], ["poker", 2], ["bomb", 10]]

var world: TableWorld


func after_each():
	Probe.clear()


func _world(species: Array, radius := SeatLayout.TABLE_RADIUS, revolvers := false) -> TableWorld:
	world = TableWorld.new(null)
	add_child_autofree(world)
	if radius != SeatLayout.TABLE_RADIUS:
		world.configure_table(radius)
	var players := []
	for i in species.size():
		players.append({"pid": i + 1, "species": species[i]})
	world.arrange(players, 1, true, revolvers)
	return world


static func _fill(p: Patron, kind: String, count: int) -> void:
	for c in p.fan.get_children():
		if c is Card3D:
			p.fan.remove_child(c)
			c.free()
	for i in count:
		var card := Card3D.new()
		p.fan.add_child(card)
		card.transform = BombCatLayout.fan_slot(i, count) if kind in ["bomb", "ddz"] else CardTable.fan_slot(i, count, 0.0)


static func _pitch_floor(p: Patron) -> float:
	return float(p._look_data.get("anim", {}).get("look_pitch_min", -0.45)) - Patron.HEAD_DIP_ROOM


# —— 他人的牌扇 ——

func test_opponent_fan_clears_its_holder_for_every_species():
	# 低头到下限(含噪声、点头的余量)、左右转到头、歪头,坐着与轮到他前倾,外加被平底锅拍扁:牌不碰头、躯干、手臂
	for s in Species.count():
		_world([(s + 1) % Species.count(), s], SeatLayout.TABLE_RADIUS, true)
		await wait_seconds(SETTLE)
		var p: Patron = world.patrons[2]
		Probe.freeze(p)
		var head := Probe.patron_meshes(p, "head")
		var rest := Probe.patron_meshes(p, "torso") + Probe.patron_meshes(p, "arms")
		var gun: Array = world.revolvers[2].find_children("*", "MeshInstance3D", true, false)
		for f in FANS + [["ddz", 20]]:
			_fill(p, f[0], f[1])
			var cards := Probe.fan_cards(p)
			for active in [false, true]:
				p.set_active(active)
				for rot in [Vector3.ZERO, Vector3(_pitch_floor(p), 0, 0), Vector3(_pitch_floor(p), 0.95, 0.3),
						Vector3(_pitch_floor(p), -0.95, -0.3), Vector3(_pitch_floor(p) * 0.5, 0.5, 0.0), Vector3(0.55, 0.0, 0.3)]:
					Probe.pose(p, rot)
					var label := "%s %s%d %s 头 %s" % [Species.IDS[s], f[0], f[1], "前倾" if active else "坐着", rot]
					assert_eq(Probe.cards_hitting(cards, head) + Probe.cards_in_head(p, cards), 0, label + ":牌碰到头")
					assert_eq(Probe.cards_hitting(cards, rest), 0, label + ":牌碰到身体或手臂")
					if f[0] == "liars":
						assert_eq(Probe.cards_hitting(cards, gun), 0, label + ":牌碰到桌上的枪")
			Probe.pose(p, Vector3.ZERO, Vector3.ZERO, 0.0, Patron.BONK_SQUASH)
			assert_eq(Probe.cards_hitting(cards, head), 0, "%s 被拍扁的头碰到牌扇" % Species.IDS[s])
		world.queue_free()


func test_fan_stands_in_seat_space_above_the_felt():
	# 立在两爪前方的桌面上空:不跟着前倾转,最低的牌角也高出毡面
	_world([1, 0])
	await wait_seconds(SETTLE)
	var p: Patron = world.patrons[2]
	_fill(p, "bomb", 10)
	Probe.freeze(p)
	var seat_xform := []
	for active in [false, true]:
		p.set_active(active)
		Probe.pose(p)
		seat_xform.append(p.transform.affine_inverse() * p.fan.global_transform)
		var lowest := INF
		for card in Probe.fan_cards(p):
			for s in Probe.card_segments(card).slice(0, 4):
				lowest = minf(lowest, p.to_local(s[0]).y)
		assert_gt(lowest, SeatLayout.FELT_TOP, "牌角在毡面之上")
	assert_true(seat_xform[0].is_equal_approx(seat_xform[1]), "前倾时牌扇在座位里不动")
	assert_true(seat_xform[0].is_equal_approx(Patron.fan_rest_transform(p._look_data)), "就是 fan_rest_transform")


func test_head_stays_above_the_table():
	# 轮到他前倾、低头到下限:鳄鱼的长吻也不戳进桌面
	for s in Species.count():
		_world([(s + 1) % Species.count(), s])
		await wait_seconds(SETTLE)
		var p: Patron = world.patrons[2]
		Probe.freeze(p)
		p.set_active(true)
		for yaw in [-0.5, 0.0, 0.5]:
			Probe.pose(p, Vector3(_pitch_floor(p), yaw, 0.3))
			for sp in Probe.head_spokes(p):
				var e: Vector3 = world.to_local(sp[1])
				if Vector2(e.x, e.z).length() < world.table_radius:
					assert_gt(e.y, SeatLayout.TABLE_TOP, "%s 低头转 %.1f:头伸进桌面" % [Species.IDS[s], yaw])
					break
		world.queue_free()


# —— 探头 ——

func _neck_targets() -> Array:
	var out := []
	for i in 7:
		var a := deg_to_rad(-90.0 + 30.0 * i)
		for r in [0.4, 1.0, 1.8, 3.0]:
			out.append(Vector3(sin(a), 0.0, -cos(a)) * r)
	return out


func test_peeking_head_keeps_out_of_others_fans_and_props():
	# 骗子酒馆 4 人桌:头不进别人的头与身体,也不碰任何人的牌扇、桌心立牌;往前探时自己的牌扇平放、头与脖子从上面过
	_world([0, 7, 5, 3])
	await wait_seconds(SETTLE)
	for pid in world.patrons:
		_fill(world.patrons[pid], "liars", 5)
		Probe.freeze(world.patrons[pid])
		Probe.pose(world.patrons[pid])
	var stand := world.cards.get_node("TargetStand").find_children("*", "MeshInstance3D", true, false)
	for pid in [2, 3]:
		var p: Patron = world.patrons[pid]
		var head := Probe.patron_meshes(p, "head")
		var others := []
		var cards := Probe.fan_cards(p)
		for q in world.patrons:
			if q != pid:
				others.append_array(Probe.patron_meshes(world.patrons[q]))
				cards.append_array(Probe.fan_cards(world.patrons[q]))
		for target in _neck_targets():
			Probe.pose(p, Vector3.ZERO, target)
			var label := "%s 探到 %s" % [Species.IDS[p.species_index], target]
			assert_eq(Probe.head_hits(p, others), 0, label + ":头进了别人的头或身体")
			assert_eq(Probe.cards_hitting(cards, head), 0, label + ":头或脖子碰到牌扇")
			assert_eq(Probe.head_hits(p, stand), 0, label + ":头碰到立牌")
		Probe.pose(p)


func test_head_slides_around_without_jumping_and_comes_home():
	# 把探头目标一路扫过桌心立牌、扫到邻座的头前(每帧 1/60 秒手动推进):头每帧挪动不超过弹簧能走的距离(不跳、不抖),
	# 最后收回原位(不卡在缝里)
	_world([0, 1, 2, 3])
	await wait_seconds(SETTLE)
	for pid in world.patrons:
		Probe.freeze(world.patrons[pid])
		Probe.pose(world.patrons[pid])
	var p: Patron = world.patrons[3]   # 对面
	var prev := p.head_position()
	var worst := 0.0
	var reversals := 0
	var last_step := Vector3.ZERO
	for i in 240:
		var t := minf(i / 180.0, 1.0)
		p.set_neck_target(Vector3(lerpf(-0.6, 1.6, t), 0.0, lerpf(-1.25, -0.4, t)))
		p._process(1.0 / 60.0)
		var now := p.head_position()
		var step := now - prev
		worst = maxf(worst, step.length())
		if step.length() > 0.004 and last_step.length() > 0.004 and step.dot(last_step) < 0.0:
			reversals += 1
		last_step = step
		prev = now
	assert_lt(worst, 0.045, "一帧最多挪 4.5 cm(≈2.7 米/秒,没有瞬移)")
	assert_lt(reversals, 3, "不来回抖")
	p.set_neck_target(Vector3.ZERO)
	for i in 120:
		p._process(1.0 / 60.0)
	assert_lt(p.neck_offset().length(), 0.01, "收回原位")


func test_remote_and_local_resolve_the_same_offset():
	# 网络:同步的是原始探头偏移;两张一样的牌桌各自推、各自抬,结果一致
	var heads := []
	for k in 2:
		_world([0, 1, 2, 3])
		await wait_seconds(SETTLE)
		var p: Patron = world.patrons[2]
		Probe.freeze(p)
		Probe.pose(p, Vector3.ZERO, Vector3(0.0, 0.0, -2.6))
		heads.append(p.neck_offset())
		world.queue_free()
	assert_almost_eq(heads[0], heads[1], Vector3.ONE * 0.001)
	assert_lt(heads[0].length(), 2.6 - 0.2, "探向对面被挡在别人的头前")


func test_head_lifts_over_its_own_fan_and_the_fan_tucks():
	_world([0, 1])
	await wait_seconds(SETTLE)
	var p: Patron = world.patrons[2]
	_fill(p, "liars", 5)
	Probe.freeze(p)
	Probe.pose(p)
	assert_almost_eq(p.neck_offset().length(), 0.0, 0.001, "原位不推不抬")
	var rest_top := _fan_top(p)
	Probe.pose(p, Vector3.ZERO, Vector3(0, 0, -0.6))
	var low := p.transform.affine_inverse() * p.fan.global_transform
	assert_almost_eq(low.basis.get_scale().x, Patron.FAN_SCALE * Patron.FAN_TUCK_SCALE, 0.001, "往前探时牌扇缩小")
	assert_lt(_fan_top(p), rest_top - 0.06, "矮下去")
	assert_gt(_fan_bottom(p), SeatLayout.FELT_TOP, "最低的牌角仍在毡面之上")
	Probe.pose(p)
	assert_true((p.transform.affine_inverse() * p.fan.global_transform).is_equal_approx(Patron.fan_rest_transform(p._look_data)),
		"收回来牌扇立回去")


func _fan_top(p: Patron) -> float:
	var top := -INF
	for card in Probe.fan_cards(p):
		for sgm in Probe.card_segments(card).slice(0, 4):
			top = maxf(top, p.to_local(sgm[0]).y)
	return top


func _fan_bottom(p: Patron) -> float:
	var low := INF
	for card in Probe.fan_cards(p):
		for sgm in Probe.card_segments(card).slice(0, 4):
			low = minf(low, p.to_local(sgm[0]).y)
	return low


func test_dice_cups_and_marker_are_guarded():
	# 吹牛骰子:骰盅(跟着盅走)和桌心出价标记登记成形状,探头的头从骰盅上面拱过去、绕开标记
	_world([0, 7, 5, 3])
	await wait_seconds(SETTLE)
	var cups := LiarsDiceCups.new(world)
	world.poker_root.add_child(cups)
	var fx := LiarsDiceFx.new(world)
	world.poker_root.add_child(fx)
	cups.setup(world.seat_angles.keys(), {})
	fx.bid_marker(3, 4)
	await wait_frames(2)
	assert_true(world.clip_guard.has_prop(&"liars_dice_cup_2"))
	assert_true(world.clip_guard.has_prop(&"liars_dice_marker"))
	var props := world.poker_root.find_children("*", "MeshInstance3D", true, false).filter(
		func(m: MeshInstance3D) -> bool: return m.is_visible_in_tree())
	for pid in world.patrons:
		Probe.freeze(world.patrons[pid])
		Probe.pose(world.patrons[pid])
	for pid in [2, 4]:
		var p: Patron = world.patrons[pid]
		for target in _neck_targets():
			Probe.pose(p, Vector3.ZERO, target)
			assert_eq(Probe.head_hits(p, props), 0, "%s 探到 %s:头碰到骰盅或出价标记" % [Species.IDS[p.species_index], target])
		Probe.pose(p)


func test_dou_dizhu_hats_fans_and_play_rows():
	# 斗地主:戴着地主帽 / 草帽,别人 17–20 张的牌扇立在桌面上空,对手的出牌行收近桌心(DdzLayout.ROW_RADIUS / OPP_MAX_ROW);
	# 坐着与往前探时牌扇不碰头和帽子、不碰出牌行与底牌,越肩时自己缩小的牌扇不碰自己的头
	_world([0, 3, 7])
	await wait_seconds(SETTLE)
	world.third_person_override = DdzLayout.THIRD_PERSON
	for pid in world.patrons:
		DdzHats.put_on(world.patrons[pid], DdzState.ROLE_LANDLORD if pid == 2 else DdzState.ROLE_FARMER, false)
		_fill(world.patrons[pid], "ddz", 20 if pid == 2 else 17)
	var me: Patron = world.patrons[1]
	me.present_hand_to(world.third_person_view(1).origin)
	me.hold_fan(me.fan.transform.translated(DdzLayout.FAN_SHIFT_ME))
	me.hold_fan(me.fan.transform.scaled_local(Vector3.ONE * DdzLayout.FAN_SCALE_ME))
	var table := []
	var xforms := [DdzLayout.deck_transform(10)]
	for i in 3:
		xforms.append(DdzLayout.bottom_slot(i, true))
	for pid in world.seat_angles:
		for i in 12:
			xforms.append(DdzLayout.play_slot(world.seat_angles[pid], pid == 1, i, 12))
	for xf in xforms:
		var card := Card3D.new()
		world.cards.add_child(card)
		card.transform = xf
		table.append(card)
	for pid in world.patrons:
		Probe.freeze(world.patrons[pid])
		Probe.pose(world.patrons[pid])
	for pid in world.patrons:
		var p: Patron = world.patrons[pid]
		var head := Probe.patron_meshes(p, "head")
		for target in [Vector3.ZERO, Vector3(0, 0, -0.1), Vector3(0, 0, -0.6), Vector3(0.6, 0, -0.4), Vector3(-0.6, 0, -0.4)]:
			Probe.pose(p, Vector3(_pitch_floor(p), 0.0, 0.0) if target == Vector3.ZERO else Vector3.ZERO, target)
			var cards := Probe.fan_cards(p)
			var label := "%s 探到 %s" % [Species.IDS[p.species_index], target]
			assert_eq(Probe.cards_hitting(cards, head), 0, label + ":牌扇碰到头或帽子")
			for a in cards:
				for b in table:
					assert_false(_cards_cross(a, b), label + ":牌扇碰到桌上的牌 %s" % world.to_local(b.global_position))
		Probe.pose(p)
	for i in table.size():
		for j in range(i + 1, table.size()):
			if table[i].get_index() >= 0 and i >= 4 and j >= 4 and (i - 4) / 12 != (j - 4) / 12:
				assert_false(_cards_cross(table[i], table[j]), "两行出牌相交")


static func _cards_cross(a: Node3D, b: Node3D) -> bool:
	var xf := b.global_transform
	var h := Vector2(Card3D.WIDTH, Card3D.HEIGHT) * 0.5
	var p0 := xf * Vector3(-h.x, 0, -h.y)
	var p1 := xf * Vector3(h.x, 0, -h.y)
	var p2 := xf * Vector3(h.x, 0, h.y)
	var p3 := xf * Vector3(-h.x, 0, h.y)
	for sgm in Probe.card_segments(a):
		if Geometry3D.segment_intersects_triangle(sgm[0], sgm[1], p0, p1, p2) != null \
				or Geometry3D.segment_intersects_triangle(sgm[0], sgm[1], p0, p2, p3) != null:
			return true
	return false


func test_first_person_comfort_keeps_neighbours_off_the_camera():
	# 第一人称时自己的头在软碰撞里多算一圈(Patron.guard_extra,只在本机):邻座把头探向自己时停得更远
	var dist := []
	for extra in [0.0, 0.25]:
		_world([0, 1, 2, 3])
		await wait_seconds(SETTLE)
		var me: Patron = world.patrons[1]
		var other: Patron = world.patrons[2]
		for pid in world.patrons:
			Probe.freeze(world.patrons[pid])
			Probe.pose(world.patrons[pid])
		me.guard_extra = extra
		var toward := other.transform.affine_inverse().basis * (me.head_position() - other.head_position())
		Probe.pose(other, Vector3.ZERO, Vector3(toward.x, 0.0, minf(toward.z, 0.0)))
		dist.append(other.head_position().distance_to(me.eye_position()))
		world.queue_free()
	assert_gt(dist[1], dist[0] + 0.15, "留白让邻座的头离镜头更远:%s" % [dist])


# —— 第一人称 ——

func test_first_person_fan_pulls_in_without_changing_the_picture():
	_world([0, 1, 2, 3])
	await wait_seconds(SETTLE)
	world.set_first_person(true)
	var me: Patron = world.patrons[1]
	_fill(me, "liars", 5)
	world.present_my_hand()
	Probe.freeze(me)
	Probe.pose(me)
	var eye := me.eye_position()
	var far: Array = Probe.fan_cards(me).map(func(c): return (c.global_transform * Vector3(0.05, 0, 0.07) - eye).normalized())
	var far_dist: float = Probe.fan_cards(me)[2].global_position.distance_to(eye)
	Probe.pose(me, Vector3.ZERO, Vector3(0, 0, -1.2))
	eye = me.eye_position()
	var near: Array = Probe.fan_cards(me).map(func(c): return (c.global_transform * Vector3(0.05, 0, 0.07) - eye).normalized())
	var near_dist: float = Probe.fan_cards(me)[2].global_position.distance_to(eye)
	for i in far.size():
		assert_almost_eq(far[i].dot(near[i]), 1.0, 0.0005, "牌上同一点从眼睛看过去的方向不变(画面一样)")
	assert_almost_eq(near_dist / far_dist, Patron.FP_FAN_NEAR, 0.02, "探头时牌扇收到 FP_FAN_NEAR")


func test_own_fan_stows_onto_the_table_off_seat_and_comes_back():
	# 镜头离开座位(特写、翻牌)时自己举着的牌扇收到桌面上空、矮下去,回座再举回来(越肩与第一人称都一样)
	_world([0, 1])
	await wait_seconds(SETTLE)
	var me: Patron = world.patrons[1]
	_fill(me, "liars", 5)
	for fp in [false, true]:
		world.set_first_person(fp)
		await wait_frames(2)
		var held := me.transform.affine_inverse() * me.fan.global_transform
		me.set_fan_stowed(true)
		await wait_seconds(0.6)
		var stowed := me.transform.affine_inverse() * me.fan.global_transform
		assert_almost_eq(stowed.origin, me.stowed_fan_transform().origin, Vector3.ONE * 0.01, "收到桌面上空 fp=%s" % fp)
		assert_lt(stowed.origin.y, held.origin.y - 0.1, "比举着时低得多")
		me.set_fan_stowed(false)
		await wait_seconds(0.6)
		var back := me.transform.affine_inverse() * me.fan.global_transform
		assert_almost_eq(back.origin, held.origin, Vector3.ONE * 0.02, "回座举回来 fp=%s" % fp)


# —— 出局 / 手臂 ——

func test_dead_fan_lands_face_down_on_the_table_clear_of_the_body():
	_world([1, 7], SeatLayout.TABLE_RADIUS, true)
	await wait_seconds(SETTLE)
	var p: Patron = world.patrons[2]
	_fill(p, "liars", 5)
	var meshes := Probe.patron_meshes(p)
	p.die(world.revolvers[2], world)
	for i in 40:
		await wait_frames(1)
		assert_eq(Probe.cards_hitting(Probe.fan_cards(p), meshes), 0, "倒下第 %d 帧:牌扇碰到自己" % i)
	var xf := p.transform.affine_inverse() * p.fan.global_transform
	assert_lt(xf.basis.y.normalized().y, -0.99, "牌背朝上扣着")
	assert_between(xf.origin.y, SeatLayout.FELT_TOP, SeatLayout.FELT_TOP + 0.04, "落在桌面上")
	assert_lt(xf.origin.z, -(SeatLayout.SEAT_GAP + 0.1), "在桌沿以内")
	p.reset_pose()
	assert_eq(p.fan_mode(), Patron.FAN_TABLE, "复位后立回桌面上空")


func test_cheering_and_clapping_paws_stay_out_of_the_big_head():
	for s in [3, 5, 7]:
		_world([(s + 1) % Species.count(), s])
		await wait_seconds(SETTLE)
		var p: Patron = world.patrons[2]
		var paws := Probe.patron_meshes(p, "arms").filter(func(m): return m.name in ["PawMesh", "FistMesh"])
		for act in ["cheer", "clap", "dance"]:
			p.reset_pose()
			await wait_seconds(0.3)
			match act:
				"cheer":
					p.celebrate()
				"clap":
					p.clap(5)
				"dance":
					p.dance(0, 1)   # 扭腰挥手:双手举成 V 字左右挥
			for i in 50:
				await wait_frames(1)
				assert_eq(Probe.head_hits(p, paws), 0, "%s %s 第 %d 帧:爪子进了头" % [Species.IDS[s], act, i])
			p.stop_dance()
		world.queue_free()


func test_species_meshes_have_no_stray_slivers():
	# 部件网格的包围盒不超出酒客一臂之外(鳄鱼的翻领曾经从背后拉出一条 1.7 米的细条穿过椅背)
	for s in Species.count():
		var p := Patron.new(s)
		add_child_autofree(p)
		for mi in p.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = (mi as MeshInstance3D).get_aabb()
			if mi.name == "NeckMesh":
				continue   # 单位高的圆柱,按脖子长度拉伸
			assert_lt(box.size.length(), 1.4, "%s %s 包围盒 %s" % [Species.IDS[s], mi.name, box])


# —— ClipGuard 纯函数 ——

func test_guard_pushes_out_and_ray_clamps():
	var m := {"rx": 0.3, "front": 0.35, "back": 0.25, "above": 0.45, "below": 0.28, "mx": 0.3}
	var post := ClipGuard.circle(Vector3(1, 0, 0), 0.1, 1.2)
	var res := ClipGuard.push_out([post], Vector2(0.8, 0), Vector2(0, -1), m, 0.9)
	assert_almost_eq((res[0] as Vector2).distance_to(Vector2(1, 0)), 0.1 + 0.3 + ClipGuard.MARGIN, 0.001, "推到椭圆半宽 + 留白")
	var t := ClipGuard.ray_clamp([post], Vector2.ZERO, Vector2(2, 0), Vector2(0, -1), m)
	assert_almost_eq(t * 2.0, 1.0 - 0.1 - 0.3 - ClipGuard.MARGIN, 0.01, "沿直线停在第一次碰到之前")
	var low := ClipGuard.circle(Vector3(1, 0, 0), 0.1, 0.8)
	assert_eq(ClipGuard.push_out([low], Vector2(0.95, 0), Vector2(0, -1), m, 0.9)[0], Vector2(0.95, 0), "顶面低于头下沿的不挡")


func test_guard_lift_is_continuous_and_capped():
	var m := {"rx": 0.3, "front": 0.35, "back": 0.25, "above": 0.45, "below": 0.28, "mx": 0.3}
	var fan := ClipGuard.rect(Vector3(0, 0, -0.6), Vector3.RIGHT, Vector2(0.2, 0.05), 0.97, ClipGuard.LIFT)
	var prev := ClipGuard.lift_needed([fan], Vector2(0, 0), 1.22, Vector2(0, -1), m, -1)
	assert_eq(prev, 0.0, "离得远不抬")
	var worst := 0.0
	for i in range(1, 101):
		var z := -0.6 * i / 100.0
		var lift := ClipGuard.lift_needed([fan], Vector2(0, z), 1.22, Vector2(0, -1), m, -1)
		worst = maxf(worst, absf(lift - prev))
		prev = lift
	assert_gt(prev, 0.0, "头在牌扇正上方时抬起")
	assert_lte(prev, ClipGuard.MAX_LIFT, "封顶")
	assert_lt(worst, 0.02, "一路平滑(每 6 mm 不超过 2 cm)")
	var tall := m.duplicate()
	tall["above"] = 0.52   # 帽子高的(帽顶离罩口只剩 0.11 米)
	assert_lt(ClipGuard.ceiling_cap(Vector2.ZERO, 1.22, tall), ClipGuard.MAX_LIFT, "吊灯下封顶更低")
	assert_eq(ClipGuard.ceiling_cap(Vector2(2, 0), 1.22, tall), INF, "灯外不封顶")


func test_guard_tolerates_shapes_already_touching_at_rest():
	# 原位就挨着的形状(越肩时举在大头边的牌扇)不推原位、只是不许更近
	var m := {"rx": 0.3, "front": 0.35, "back": 0.25, "above": 0.45, "below": 0.28, "mx": 0.3}
	var guard := ClipGuard.new(Node3D.new())
	guard.set_prop(&"near", ClipGuard.circle(Vector3(0.4, 0, 0), 0.1, 1.5))
	var list := guard.blockers_for(-1, Vector2.ZERO, Vector2(0, -1), m)
	assert_eq(list.size(), 1)
	assert_gt(float(list[0].get("slack", 0.0)), 0.0, "记下原位差的那一截")
	assert_eq(ClipGuard.push_out(list, Vector2.ZERO, Vector2(0, -1), m, 0.9)[0], Vector2.ZERO, "原位不推")
	var moved: Vector2 = ClipGuard.push_out(list, Vector2(0.1, 0), Vector2(0, -1), m, 0.9)[0]
	assert_almost_eq(moved.x, 0.0, 0.001, "往它那边挪会被推回原来的距离")
	guard.world.free()


func test_guard_drops_props_whose_node_is_freed():
	# 骰盅、出价标记这类跟节点绑着的形状:节点释放后自动收走,不再报错
	var holder := Node3D.new()
	add_child(holder)
	var guard := ClipGuard.new(holder)
	var cup := Node3D.new()
	holder.add_child(cup)
	guard.set_prop(&"cup", ClipGuard.follow(cup, 0.1, PackedVector3Array([Vector3.ZERO, Vector3(0, 0.18, 0)])))
	await wait_frames(1)
	assert_eq(guard.shapes().size(), 1)
	cup.free()
	await wait_process_frames(2)
	assert_eq(guard.shapes().size(), 0, "节点释放后不算")
	assert_false(guard.has_prop(&"cup"), "登记也收走")
	holder.free()
