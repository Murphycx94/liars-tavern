extends RefCounted
# 穿模测量(规格 2026-10-08-cozy-toon-style-design §穿模修复):只给测试与 tools/clip_report.gd 用,运行时代码不读网格数组。
# 判定都按真实网格的三角形:每个网格建一次 TriangleMesh(按网格资源缓存,酒客部件网格按物种共享),
# 线段与它求交走引擎的 BVH,不在 GDScript 里逐个三角形循环。
# - 牌 vs 网格:牌面内一组检测线(四条边 + 横竖网格线)只要有一条穿过网格表面,这张牌就算穿模;
#   整张牌埋在大头里(没有线穿过表面)另按「牌心在头的外壳以内」补判。
# - 头 vs 网格:从头心沿一圈方向(辐条)连到头部外壳(含帽、耳、眼),任一辐条穿过对方网格的表面就算两者相交。
#   头部外壳 = 从远处沿该方向往头心打射线的第一个交点(凹处按凸起填平,略保守)。


const CARD_LINES := Vector2i(5, 7)   # 牌面内的横、竖检测线条数(不含四条边):间距约 2 cm,吻、爪、帽檐都比它粗
const SPOKES := 96                   # 头部辐条数(斐波那契球面均匀取向)
const FAR := 2.0                     # 测外壳时从头心外这么远往里打

static var _tri := {}        # 网格 RID -> TriangleMesh
static var _hull := {}       # 物种 -> PackedFloat32Array(每根辐条在 Head 局部的外壳长度)
static var _dirs := PackedVector3Array()


static func tri_mesh(mesh: Mesh) -> TriangleMesh:
	var key := mesh.get_rid()
	if not _tri.has(key):
		_tri[key] = mesh.generate_triangle_mesh()
	return _tri[key]


static func clear() -> void:
	_tri.clear()
	_hull.clear()


# —— 网格收集 ——

static func patron_meshes(p: Patron, parts := "all") -> Array:
	# 酒客自己的可见网格(不含牌扇里的牌、特效 MultiMesh):parts = "all" / "head"(头、眼、眉、耳、帽、脖子)/
	# "body"(躯干、腿、椅子)/ "arms"(手臂、爪子、拳头)/ "torso"(躯干与腿,不含椅子)
	var out := []
	for node in p.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree() or p.fan.is_ancestor_of(mi):
			continue
		var in_head := p.head.is_ancestor_of(mi) or p.body.get_node("Neck").is_ancestor_of(mi)
		var in_arms := p._arm_l.is_ancestor_of(mi) or p._arm_r.is_ancestor_of(mi)
		var group := "head" if in_head else ("arms" if in_arms else "body")
		if mi.name == "Tongue":
			group = "head"
		if parts == "all" or parts == group or (parts == "torso" and group == "body" and mi.name != "Chair"):
			out.append(mi)
	return out


static func fan_cards(p: Patron) -> Array:
	return p.fan.get_children().filter(func(c): return c is Card3D and c.is_visible_in_tree())


# —— 牌 ——

static func card_size(card: Node3D) -> Vector2:
	return Vector2(Card3D.WIDTH, Card3D.HEIGHT)


static func card_segments(card: Node3D) -> Array:
	# 牌面(本地 XZ,宽沿 X、高沿 Z)内的检测线,全局坐标:[[a, b], …]
	var xf := card.global_transform
	var half := card_size(card) * 0.5
	var segs := []
	var corners := [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y)]
	for i in 4:
		segs.append([xf * corners[i], xf * corners[(i + 1) % 4]])
	for i in CARD_LINES.x:
		var z := lerpf(-half.y, half.y, (i + 1.0) / (CARD_LINES.x + 1.0))
		segs.append([xf * Vector3(-half.x, 0, z), xf * Vector3(half.x, 0, z)])
	for i in CARD_LINES.y:
		var x := lerpf(-half.x, half.x, (i + 1.0) / (CARD_LINES.y + 1.0))
		segs.append([xf * Vector3(x, 0, -half.y), xf * Vector3(x, 0, half.y)])
	return segs


static func segs_box(segs: Array) -> AABB:
	var box := AABB(segs[0][0], Vector3.ZERO)
	for s in segs:
		box = box.expand(s[0]).expand(s[1])
	return box


static func segments_hit(segs: Array, mi: MeshInstance3D, bounds = null) -> int:
	# 有几条线段穿过网格表面;bounds = 这组线段的全局包围盒(可先算好传进来),和网格的全局包围盒不交就跳过
	if segs.is_empty():
		return 0
	var outer: AABB = bounds if bounds != null else segs_box(segs)
	if not (mi.global_transform * mi.get_aabb()).grow(0.002).intersects(outer):
		return 0
	var inv := mi.global_transform.affine_inverse()
	var box := mi.get_aabb().grow(0.002)
	var tm := tri_mesh(mi.mesh)
	var hits := 0
	for s in segs:
		var a: Vector3 = inv * s[0]
		var b: Vector3 = inv * s[1]
		if not box.intersects_segment(a, b):
			continue
		if not tm.intersect_segment(a, b).is_empty():
			hits += 1
	return hits


static func card_hits(card: Node3D, meshes: Array) -> int:
	# 这张牌穿过了几个网格(0 = 没穿模)
	var segs := card_segments(card)
	var bounds := segs_box(segs)
	var n := 0
	for mi in meshes:
		if segments_hit(segs, mi, bounds) > 0:
			n += 1
	return n


static func cards_hitting(cards: Array, meshes: Array) -> int:
	# 有几张牌穿模
	var n := 0
	for card in cards:
		if card_hits(card, meshes) > 0:
			n += 1
	return n


# —— 头部外壳 ——

static func spoke_dirs() -> PackedVector3Array:
	if _dirs.is_empty():
		var golden := PI * (3.0 - sqrt(5.0))
		for i in SPOKES:
			var y := 1.0 - 2.0 * (i + 0.5) / SPOKES
			var r := sqrt(1.0 - y * y)
			_dirs.append(Vector3(cos(golden * i) * r, y, sin(golden * i) * r))
	return _dirs


static func head_center_local() -> Vector3:
	return PatronParts.HEAD_CENTER


static func hull(p: Patron) -> PackedFloat32Array:
	# 物种的头部外壳(Head 局部,头没转、没压扁时):每根辐条从头心到最外表面的长度
	# 按物种 + 头上挂的东西缓存(斗地主的身份帽挂在 Head/Hat 下,换帽子外壳就变)
	var key := "%d:%d:%s" % [p.species_index, p.head.find_children("*", "MeshInstance3D", true, false).size(),
		p.head.find_child("DdzRoleHat", true, false) != null]
	if _hull.has(key):
		return _hull[key]
	var parts := []
	for node in p.head.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree() and mi.name != "Tongue":
			parts.append(mi)
	var lengths := PackedFloat32Array()
	var c := head_center_local()
	for dir in spoke_dirs():
		var best := 0.0
		for mi: MeshInstance3D in parts:
			var to_mesh := (p.head.global_transform.affine_inverse() * mi.global_transform).affine_inverse()
			var hit := tri_mesh(mi.mesh).intersect_segment(to_mesh * (c + dir * FAR), to_mesh * c)
			if not hit.is_empty():
				var from_mesh := p.head.global_transform.affine_inverse() * mi.global_transform
				best = maxf(best, (from_mesh * Vector3(hit["position"])).distance_to(c))
		lengths.append(best)
	_hull[key] = lengths
	return lengths


static func head_spokes(p: Patron) -> Array:
	# 当前姿势下头部辐条(全局):[[头心, 外壳点], …]
	var lengths := hull(p)
	var xf := p.head.global_transform
	var c := xf * head_center_local()
	var out := []
	var dirs := spoke_dirs()
	for i in dirs.size():
		out.append([c, xf * (head_center_local() + dirs[i] * lengths[i])])
	return out


static func head_hits(p: Patron, meshes: Array) -> int:
	# 头(外壳)与这些网格中的几个相交
	var spokes := head_spokes(p)
	var bounds := segs_box(spokes)
	var n := 0
	for mi in meshes:
		if segments_hit(spokes, mi, bounds) > 0:
			n += 1
	return n


static func point_in_head(p: Patron, point: Vector3) -> bool:
	var local := p.head.global_transform.affine_inverse() * point - head_center_local()
	var dist := local.length()
	if dist < 0.0001:
		return true
	var dirs := spoke_dirs()
	var lengths := hull(p)
	var best := -1.0
	var reach := 0.0
	for i in dirs.size():
		var d := dirs[i].dot(local / dist)
		if d > best:
			best = d
			reach = lengths[i]
	return dist < reach   # Head 局部坐标(已除掉头的缩放),外壳也是 Head 局部量的


static func cards_in_head(p: Patron, cards: Array) -> int:
	# 整张埋在头里的牌(四条边、网格线都不碰表面时补判):牌心在头的外壳以内
	var n := 0
	for card in cards:
		if point_in_head(p, card.global_position):
			n += 1
	return n


# —— 姿势 ——

static func freeze(p: Patron) -> void:
	# 测量用:停掉酒客的逐帧动画与待机噪声,姿势全由 pose() 摆
	p.set_process(false)
	p._noise.frequency = 0.0
	p._antics._fidget_in = 1.0e9
	p._blink_in = 1.0e9


static func pose(p: Patron, head_add := Vector3.ZERO, neck := Vector3.ZERO, lift := 0.0, head_scale := Vector3.ONE) -> void:
	# 按驱动量摆出一帧的静止姿势(走 Patron 自己的逐帧逻辑,步长取大让插值一步到位):
	# head_add 加到转头角(俯仰 x、转头 y、歪头 z),neck 是座位坐标的探头目标,lift 是身体上下(吓一跳 +、松口气 −)
	p._antics.head_add = head_add
	p.set_neck_target(neck)
	for i in 3:
		p._process(1.0)
	p.body.position.y = Patron.HIP.y + lift
	p.head.scale = head_scale
	p._plant_paws()
	if p.has_method("_place_fan"):
		p._place_fan()
