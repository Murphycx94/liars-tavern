extends GutTest
# 越肩镜头下自己的手牌不被自己的头(含帽子、耳朵)挡住:坐着、轮到自己前倾时都一样,
# 头往前、往两侧探到最远也一样。从镜头向每张牌上的采样点打射线,先和头部每个网格的包围盒求交,
# 碰到包围盒再逐个三角形精确判定(Q 版大头之后包围盒太保守:礼帽、宽檐帽斜着放,包围盒的角伸到牌扇跟前,
# 实际形状并不挡;规格 §8 已批准改成三角形判定、阈值不变)。只要求被挡的采样点极少,且每张牌的中心都看得见。


const SETTLE := 1.2          # 秒:登场缩放与前倾插值走完
const NECK_SETTLE := 1.2     # 秒:脖子弹簧追到目标(最远 3 米)
const MAX_BLOCKED := 0.05    # 允许被包围盒挡住的采样点比例(包围盒的角比实际形状大)
const R := Patron.NECK_REACH
const NECK_OFFSETS := [Vector3.ZERO, Vector3(0.4, 0, 0), Vector3(0.85, 0, 0), Vector3(0.6, 0, -0.6),
	Vector3(0, 0, -0.85), Vector3(-0.85, 0, 0), Vector3(0.6, 0, 0.6),
	# 伸到最远(3 米):正前、两侧、斜前,以及中途扫过牌扇的位置
	Vector3(R, 0, 0), Vector3(-R, 0, 0), Vector3(0, 0, -R), Vector3(R * 0.7, 0, -R * 0.7), Vector3(-R * 0.7, 0, -R * 0.7),
	Vector3(1.5, 0, 0), Vector3(1.5, 0, -0.5)]
const RISKY_OFFSETS := [Vector3.ZERO, Vector3(0.4, 0, 0), Vector3(0.85, 0, 0), Vector3(0.6, 0, 0.6)]

var world: TableWorld
var me: Patron


func before_each():
	_setup([{"pid": 1}, {"pid": 2}])


func _setup(players: Array) -> void:
	world = TableWorld.new(null)
	add_child_autofree(world)
	world.arrange(players, 1, true, false)
	me = world.patrons[1]
	me.present_hand_to(_eye())
	world.cards.attach_hand(me.fan)
	world.cards.sync({1: 5, 2: 5}, [Card.QUEEN, Card.KING, Card.ACE, Card.JOKER, Card.QUEEN])


func test_head_never_hides_the_hand_while_seated():
	await wait_seconds(SETTLE)
	await _assert_hand_visible_for_all_offsets("坐着")


func test_head_never_hides_the_hand_on_own_turn():
	me.set_active(true)
	await wait_seconds(SETTLE)
	await _assert_hand_visible_for_all_offsets("轮到自己前倾")


func test_every_species_head_spares_the_hand_on_own_turn():
	# Q 版大头之后每个物种都过一遍(帽型、耳朵、吻各不相同),取前倾 + 头往右、右前探这几个最容易挡的姿势
	for species in range(1, Species.count()):
		world.queue_free()
		_setup([{"pid": 1, "species": species}, {"pid": 2, "species": 0}])
		me.set_active(true)
		await wait_seconds(SETTLE)
		await _assert_hand_visible_for_all_offsets(Species.IDS[species], RISKY_OFFSETS)


func test_poker_hand_beside_the_big_head_stays_visible():
	# 德州:自己的两张底牌由 PokerLayout.fan_transform 摆在大头右前方(动森式大头之后挪过 FAN_OFFSET)。
	# 每个物种静坐、往前探、往左探时,牌面区域被自己的头挡住的采样点同样 ≤ MAX_BLOCKED。
	# (德州的牌扇在头的前方,自己按 D 把头往右探就会挡住——那是玩家自己挪的,和 Q 版一样,不在这里测)
	for species in Species.count():
		world.queue_free()
		world = TableWorld.new(null)
		add_child_autofree(world)
		world.configure_table(SeatLayout.POKER_TABLE_RADIUS)
		world.arrange([{"pid": 1, "species": species}, {"pid": 2, "species": (species + 1) % Species.count()}], 1, true, false)
		me = world.patrons[1]
		# 同 PokerCards:hold_fan 举住(穿模修复 2026-10-10 之后直接改 fan.transform 不再算数:默认牌扇每帧立回桌面上空)
		me.hold_fan(PokerLayout.fan_transform(world.seat_transform(world.seat_angles[1]), _eye()))
		await wait_seconds(SETTLE)
		for offset in [Vector3.ZERO, Vector3(0, 0, -0.4), Vector3(-0.4, 0, 0)]:
			me.set_neck_target(offset)
			await wait_seconds(NECK_SETTLE)
			var total := 0
			var blocked := 0
			for i in 9:
				for j in 5:
					var local := Vector3((i / 8.0 - 0.5) * (Card3D.WIDTH + 0.07), 0.0, (j / 4.0 - 0.5) * Card3D.HEIGHT * 0.9)
					total += 1
					if _blocked(me.fan.global_transform * local):
						blocked += 1
			assert_lte(float(blocked) / total, MAX_BLOCKED, "%s 德州底牌,头探到 %s:被挡住 %d/%d" % [Species.IDS[species], offset, blocked, total])


func _assert_hand_visible_for_all_offsets(posture: String, offsets: Array = NECK_OFFSETS) -> void:
	for offset in offsets:
		me.set_neck_target(offset)
		await wait_seconds(NECK_SETTLE)
		var label := "%s,头探到 %s" % [posture, offset]
		var total := 0
		var blocked := 0
		for card in world.cards.my_cards:
			assert_false(_blocked(card.global_transform.origin), label + ":牌的中心被头挡住")
			for point in _card_points(card):
				total += 1
				if _blocked(point):
					blocked += 1
		assert_lte(float(blocked) / total, MAX_BLOCKED, label + ":被挡住 %d/%d 个采样点" % [blocked, total])


func _eye() -> Vector3:
	return world.third_person_view(1).origin


func _card_points(card: Card3D) -> Array:
	var points := []
	for i in 5:
		for j in 5:
			var local := Vector3((i / 4.0 - 0.5) * Card3D.WIDTH * 0.9, 0.0, (j / 4.0 - 0.5) * Card3D.HEIGHT * 0.9)
			points.append(card.global_transform * local)
	return points


func _blocked(point: Vector3) -> bool:
	var eye := _eye()
	for node in me.head.find_children("*", "VisualInstance3D", true, false):
		var mesh := node as VisualInstance3D
		if not mesh.is_visible_in_tree() or (mesh.global_transform * mesh.get_aabb()).intersects_segment(eye, point) == null:
			continue
		if not mesh is MeshInstance3D:
			return true   # 别的可见物(特效)按包围盒算
		var local := mesh.global_transform.affine_inverse()
		var a := local * eye
		var b := local * point
		var faces := (mesh as MeshInstance3D).mesh.get_faces()
		for i in range(0, faces.size(), 3):
			if Geometry3D.segment_intersects_triangle(a, b, faces[i], faces[i + 1], faces[i + 2]) != null:
				return true
	return false
