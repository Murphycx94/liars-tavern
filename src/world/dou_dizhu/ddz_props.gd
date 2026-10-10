class_name DdzProps
# 斗地主的 3D 小道具(全部程序生成、动森式圆滚滚的粉彩造型,网格 MeshForge.cached、所有实例共用):
# - 地主帽:藏青缎面的瓜皮帽,六道金色帽缝,顶上一颗红绒结,帽檐一圈金边,正前方一块翠绿的帽正;
# - 农民的草帽:宽檐稍稍下垂,一圈圈深一档的草编纹,红帽带上别一朵小雏菊;
#   两顶帽子都按「颅骨半径 0.1」建、原点在帽口中心(帽口贴着颅骨上部一圈),DdzHats 按各物种的颅骨缩放;
# - 王炸的小火箭(白身红鼻、圆舷窗里一双豆豆眼、三片青绿尾翼)、飞机的小纸飞机、春天的花瓣(粒子网格);
# - 报警徽章(公告板红圆片,淡出走实例参数)。
# 实心件用道具共享材质 WorldMaterials.prop();薄片用 BombCatProps 的淡出材质(不 duplicate);
# 花瓣粒子的 toon 材质缓存在这里,main.gd 退出时 clear_cache 释放。效果件一律不投影,帽子投影。


const NAVY := Color(0.2, 0.21, 0.36)        # 瓜皮帽缎面
const NAVY_SHINE := Color(0.3, 0.32, 0.5)
const GOLD := Color(0.8, 0.64, 0.3)
const KNOT_RED := Color(0.8, 0.24, 0.26)
const JADE := Color(0.32, 0.72, 0.54)
const STRAW := Color(0.8, 0.67, 0.4)
const STRAW_DARK := Color(0.66, 0.5, 0.27)
const RIBBON := Color(0.8, 0.3, 0.3)
const DAISY := Color(0.8, 0.79, 0.76)
const DAISY_HEART := Color(0.8, 0.66, 0.2)
const ROCKET_WHITE := Color(0.8, 0.79, 0.76)
const ROCKET_RED := Color(0.8, 0.3, 0.32)
const ROCKET_FIN := Color(0.3, 0.66, 0.66)
const WINDOW := Color(0.45, 0.66, 0.8)
const EYE := Color(0.24, 0.14, 0.1)
const PAPER := Color(0.8, 0.79, 0.76)
const PAPER_STRIPE := Color(0.8, 0.5, 0.56)
const PETAL_COLORS := [Color(1.0, 0.72, 0.8), Color(1.0, 0.84, 0.88), Color(0.98, 0.62, 0.72), Color(1.0, 0.93, 0.95)]
const SKULL_REF := 0.122                    # 帽子按这个颅骨半径建(颅骨更大的物种按比例放大)
# 穿模修复(2026-10-10):帽子按物种贴合(DdzHats.FIT),用到的建模尺寸
const RIM_RADIUS := {"landlord": 0.094, "farmer": 0.079}   # 帽口外沿半径:瓜皮帽的金边、草帽的帽冠
const STRAW_CROWN_R := 0.079
const STRAW_BRIM_R := 0.145
const HOLE_PAD := 0.012                     # 耳洞比耳朵穿过帽檐的那一圈再大这么多(建模单位)

static var _cache := {}


static func clear_cache() -> void:
	_cache = {}


static func _prop(key: String, recipe: Callable) -> ArrayMesh:
	return MeshForge.cached("ddz:" + key, recipe, {&"main": WorldMaterials.prop()})


static func _fx(key: String, recipe: Callable, billboard := false) -> ArrayMesh:
	return MeshForge.cached("ddz:" + key, recipe, {&"main": BombCatProps.fx_material(billboard)})


# —— 帽子 ——

static func landlord_hat() -> ArrayMesh:
	return _prop("hat_landlord", func(f: MeshForge):
		var dome := PackedVector2Array([Vector2(0.088, 0.0), Vector2(0.087, 0.012), Vector2(0.081, 0.028), Vector2(0.067, 0.041),
			Vector2(0.044, 0.05), Vector2(0.0, 0.054)])
		f.paint(NAVY, 0.42)
		f.lathe(dome, 36)
		# 缎面上一抹高光(左上)
		f.paint(NAVY_SHINE, 0.35)
		f.sphere(0.012, 10, MeshForge.xf(Vector3(-0.035, 0.044, 0.03), Vector3.ZERO, Vector3(1.6, 0.35, 1.0)))
		# 六道金帽缝:顺着帽顶的轮廓
		f.paint(GOLD, 0.4, 0.35)
		for k in 6:
			var a := TAU * k / 6.0
			var path := PackedVector3Array()
			for p in dome:
				var r := p.x + 0.0012
				path.append(Vector3(sin(a) * r, p.y + 0.0008, cos(a) * r))
			f.tube(path, 0.0019, 5)
		# 帽口一圈金边
		f.lathe(PackedVector2Array([Vector2(0.085, -0.007), Vector2(0.093, -0.006), Vector2(0.094, 0.01), Vector2(0.087, 0.012)]), 36)
		# 顶上红绒结 + 小梗
		f.paint(KNOT_RED.darkened(0.2), 0.6)
		f.cylinder(0.004, 0.006, 0.01, 10, MeshForge.CAPS_NONE, MeshForge.xf(Vector3(0, 0.057, 0)))
		f.paint(KNOT_RED, 0.75)
		f.glow = Vector2(0.08, 0.0)
		f.sphere(0.017, 16, MeshForge.xf(Vector3(0, 0.072, 0)))
		f.glow = Vector2.ZERO
		# 正前方的帽正:金托 + 翠绿圆石(带一点自发光,远看也亮)
		f.paint(GOLD, 0.35, 0.4)
		f.torus(0.008, 0.014, 18, MeshForge.xf(Vector3(0, 0.003, 0.092), Vector3(90, 0, 0)))
		f.paint(JADE, 0.25)
		f.glow = Vector2(0.18, 0.0)
		f.sphere(0.0095, 14, MeshForge.xf(Vector3(0, 0.003, 0.093), Vector3.ZERO, Vector3(1.0, 1.0, 0.6)))
		f.glow = Vector2.ZERO)


static func hat(role: String, holes := []) -> ArrayMesh:
	# role:"landlord" 瓜皮帽 / 其余草帽;holes:草帽帽檐上的耳洞 [Vector3(x, z, 半径)](帽子局部,建模单位;DdzHats.FIT 按物种量好)
	return landlord_hat() if role == "landlord" else straw_hat(holes)


static func straw_hat(holes := []) -> ArrayMesh:
	# 草帽:帽檐按极坐标网格建(开耳洞时跳过洞里的格子、洞边补一圈立壁和深色包边),帽冠、草编纹、帽带、小雏菊同原来
	var key := "hat_straw"
	for h in holes:
		key += "_%d_%d_%d" % [roundi(h.x * 1000.0), roundi(h.y * 1000.0), roundi(h.z * 1000.0)]
	return _prop(key, func(f: MeshForge):
		f.paint(STRAW, 0.88)
		_straw_brim(f, holes)
		# 帽冠
		f.lathe(PackedVector2Array([Vector2(STRAW_CROWN_R, -0.002), Vector2(0.077, 0.03), Vector2(0.067, 0.051), Vector2(0.042, 0.061),
			Vector2(0.0, 0.063)]), 32)
		# 草编纹:深一档的细环(碰到耳洞的地方断开)
		f.paint(STRAW_DARK, 0.9)
		for r in [0.094, 0.116, 0.134]:
			var y: float = -0.0034 * (r - 0.07) / 0.03 + 0.0018
			for path in _ring_paths(r, y, holes):
				f.tube(path, 0.0016, 5)
		for p in [Vector2(0.0765, 0.034), Vector2(0.06, 0.054)]:
			f.torus(p.x - 0.0014, p.x + 0.0014, 32, MeshForge.xf(Vector3(0, p.y, 0)))
		# 耳洞的深色包边(洞挨着帽檐外缘时成了缺口:只包帽檐上的那一段)
		for h in holes:
			var ring := PackedVector3Array()
			for k in 33:
				var a := TAU * k / 32.0
				var q: Vector2 = Vector2(h.x, h.y) + Vector2(cos(a), sin(a)) * h.z
				if q.length() > STRAW_BRIM_R - 0.006 or _in_hole(q, holes.filter(func(o: Vector3) -> bool: return o != h)):
					if ring.size() > 1:
						f.tube(ring, 0.0032, 6)
					ring = PackedVector3Array()
					continue
				ring.append(Vector3(q.x, _brim_y(q.length(), true) - 0.0015, q.y))
			if ring.size() > 1:
				f.tube(ring, 0.0032, 6)
		# 红帽带
		f.paint(RIBBON, 0.7)
		f.lathe(PackedVector2Array([Vector2(0.0805, 0.002), Vector2(0.0795, 0.019)]), 32)
		# 帽带右前方别一朵小雏菊
		var flower := Vector3(sin(0.6) * 0.083, 0.011, cos(0.6) * 0.083)
		f.push(Transform3D(Basis.looking_at(-flower.normalized() * Vector3(1, 0, 1), Vector3.UP), flower))
		f.paint(DAISY, 0.6)
		for k in 6:
			var a := TAU * k / 6.0
			f.sphere(0.0055, 8, MeshForge.xf(Vector3(cos(a) * 0.0075, sin(a) * 0.0075, 0.0), Vector3.ZERO, Vector3(1.0, 1.0, 0.45)))
		f.paint(DAISY_HEART, 0.5)
		f.glow = Vector2(0.15, 0.0)
		f.sphere(0.0045, 8, MeshForge.xf(Vector3(0, 0, 0.002), Vector3.ZERO, Vector3(1.0, 1.0, 0.6)))
		f.glow = Vector2.ZERO
		f.pop())


const BRIM_TOP := [Vector2(0.07, 0.004), Vector2(0.105, 0.0), Vector2(0.138, -0.01), Vector2(STRAW_BRIM_R, -0.015)]
const BRIM_BOTTOM := [Vector2(0.07, -0.003), Vector2(0.105, -0.005), Vector2(0.138, -0.0172), Vector2(STRAW_BRIM_R, -0.015)]
const BRIM_RINGS := [0.07, 0.08, 0.09, 0.1, 0.11, 0.12, 0.13, 0.138, STRAW_BRIM_R]
const BRIM_SEGMENTS := 72


static func _brim_y(r: float, top: bool) -> float:
	# 帽檐上 / 下表面在半径 r 处的高度(外缘往下垂)
	var prof: Array = BRIM_TOP if top else BRIM_BOTTOM
	if r <= prof[0].x:
		return prof[0].y
	for i in range(1, prof.size()):
		if r <= prof[i].x:
			return lerpf(prof[i - 1].y, prof[i].y, (r - prof[i - 1].x) / (prof[i].x - prof[i - 1].x))
	return prof[-1].y


static func _in_hole(q: Vector2, holes: Array) -> bool:
	for h in holes:
		if q.distance_to(Vector2(h.x, h.y)) < h.z:
			return true
	return false


static func _straw_brim(f: MeshForge, holes: Array) -> void:
	# 帽檐:BRIM_RINGS × BRIM_SEGMENTS 的极坐标网格,上下两面;格子中心在耳洞里就跳过,洞边(留下的格子挨着跳过的格子)补立壁
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var nr := BRIM_RINGS.size()
	var keep := {}
	for i in nr - 1:
		for j in BRIM_SEGMENTS:
			var rm: float = (BRIM_RINGS[i] + BRIM_RINGS[i + 1]) * 0.5
			var am := TAU * (j + 0.5) / BRIM_SEGMENTS
			keep[Vector2i(i, j)] = not _in_hole(Vector2(sin(am), cos(am)) * rm, holes)
	for i in nr - 1:
		for j in BRIM_SEGMENTS:
			if not keep[Vector2i(i, j)]:
				continue
			for top in [true, false]:
				var c := [_brim_point(i, j, top), _brim_point(i, j + 1, top), _brim_point(i + 1, j, top), _brim_point(i + 1, j + 1, top)]
				_quad(points, normals, indices, c[0], c[1], c[2], c[3], Vector3.UP if top else Vector3.DOWN)
			# 立壁:四个邻格里跳过的那一侧
			var sides := [[Vector2i(i - 1, j), i, j, i, j + 1], [Vector2i(i + 1, j), i + 1, j, i + 1, j + 1],
				[Vector2i(i, j - 1), i, j, i + 1, j], [Vector2i(i, j + 1), i, j + 1, i + 1, j + 1]]
			for side in sides:
				var n: Vector2i = side[0]
				n.y = posmod(n.y, BRIM_SEGMENTS)
				if n.x < 0 or n.x >= nr - 1 or keep.get(n, true):
					continue
				var a := _brim_point(side[1], side[2], true)
				var b := _brim_point(side[3], side[4], true)
				var a2 := _brim_point(side[1], side[2], false)
				var b2 := _brim_point(side[3], side[4], false)
				var mid := (_brim_point(i, j, true) + _brim_point(i + 1, j + 1, true)) * 0.5
				var out := ((a + b) * 0.5 - mid) * Vector3(1, 0, 1)
				_quad(points, normals, indices, a, b, a2, b2, out.normalized())
	f._append(points, normals, indices, Transform3D.IDENTITY)


static func _brim_point(i: int, j: int, top: bool) -> Vector3:
	var r: float = BRIM_RINGS[i]
	var a := TAU * float(j) / BRIM_SEGMENTS
	return Vector3(sin(a) * r, _brim_y(r, top), cos(a) * r)


static func _quad(points: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array,
		p00: Vector3, p01: Vector3, p10: Vector3, p11: Vector3, n: Vector3) -> void:
	# 四边形两个三角形,绕向按 MeshForge.grid 的口径朝 n
	if (p01 - p00).cross(p10 - p00).dot(n) < 0.0:
		var t := p01
		p01 = p10
		p10 = t
	var base := points.size()
	for p in [p00, p01, p10, p11]:
		points.append(p)
		normals.append(n)
	indices.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3])


static func _ring_paths(r: float, y: float, holes: Array) -> Array:
	# 半径 r 的一圈,在耳洞处断开:返回若干段折线
	var paths := []
	var cur := PackedVector3Array()
	var steps := 48
	for k in steps + 1:
		var a := TAU * k / steps
		var q := Vector2(sin(a), cos(a)) * r
		if _in_hole(q, holes.map(func(h: Vector3) -> Vector3: return Vector3(h.x, h.y, h.z + 0.004))):
			if cur.size() > 1:
				paths.append(cur)
			cur = PackedVector3Array()
		else:
			cur.append(Vector3(q.x, y, q.y))
	if cur.size() > 1:
		paths.append(cur)
	return paths


# —— 王炸的小火箭 ——

static func rocket() -> ArrayMesh:
	# 约 20 cm 高,原点在尾喷口,头朝 +Y,舷窗朝 +Z
	return _prop("rocket", func(f: MeshForge):
		f.paint(Color(0.36, 0.34, 0.38), 0.5, 0.3)
		f.cylinder(0.016, 0.022, 0.02, 16, MeshForge.CAPS_BOTH, MeshForge.xf(Vector3(0, 0.01, 0)))
		f.paint(ROCKET_WHITE, 0.45)
		f.lathe(PackedVector2Array([Vector2(0.024, 0.02), Vector2(0.031, 0.04), Vector2(0.033, 0.08), Vector2(0.032, 0.12),
			Vector2(0.03, 0.13)]), 24)
		f.paint(ROCKET_RED, 0.45)
		f.lathe(PackedVector2Array([Vector2(0.03, 0.13), Vector2(0.026, 0.155), Vector2(0.016, 0.178), Vector2(0.0, 0.19)]), 24)
		f.torus(0.0305, 0.0345, 24, MeshForge.xf(Vector3(0, 0.05, 0)))
		# 舷窗:奶白圈 + 天蓝玻璃 + 一双豆豆眼
		f.paint(ROCKET_WHITE, 0.4, 0.2)
		f.torus(0.009, 0.0145, 18, MeshForge.xf(Vector3(0, 0.092, 0.031), Vector3(90, 0, 0)))
		f.paint(WINDOW, 0.2)
		f.glow = Vector2(0.15, 0.0)
		f.sphere(0.0105, 14, MeshForge.xf(Vector3(0, 0.092, 0.03), Vector3.ZERO, Vector3(1.0, 1.0, 0.4)))
		f.glow = Vector2.ZERO
		f.paint(EYE, 0.3)
		for side: float in [-1.0, 1.0]:
			f.sphere(0.0022, 8, MeshForge.xf(Vector3(side * 0.004, 0.093, 0.0345), Vector3.ZERO, Vector3(1.0, 1.25, 0.5)))
		# 三片尾翼
		f.paint(ROCKET_FIN, 0.5)
		for k in 3:
			var a := TAU * k / 3.0 + PI / 3.0
			f.push(MeshForge.xf(Vector3.ZERO, Vector3(0, rad_to_deg(a), 0)))
			f.extrude(PackedVector2Array([Vector2(0.02, 0.06), Vector2(0.05, 0.012), Vector2(0.05, 0.0), Vector2(0.024, 0.016)]),
				0.006, 0.0015, MeshForge.xf(Vector3(0, 0, 0)))
			f.pop())


# —— 飞机的小纸飞机 ——

static func paper_plane() -> ArrayMesh:
	# 折纸飞机:机头朝 -Z,翼展约 22 cm,原点在机身中部;两面都画(纸很薄)
	return _prop("plane", func(f: MeshForge):
		var nose := Vector3(0, 0.0, -0.13)
		var tail := Vector3(0, 0.012, 0.07)
		var keel := Vector3(0, -0.032, 0.07)
		var wing_l := Vector3(-0.11, 0.02, 0.08)
		var wing_r := Vector3(0.11, 0.02, 0.08)
		f.paint(PAPER, 0.85)
		for tri in [[nose, wing_l, tail], [nose, tail, wing_r]]:
			_two_sided(f, tri)
		f.paint(Color(0.74, 0.72, 0.69), 0.85)
		for tri in [[nose, tail, keel], [nose, keel, tail]]:
			_two_sided(f, tri)
		# 翅膀上一道粉色条纹
		f.paint(PAPER_STRIPE, 0.8)
		for side: float in [-1.0, 1.0]:
			var a := Vector3(side * 0.04, 0.0128, 0.0)
			var b := Vector3(side * 0.085, 0.0178, 0.055)
			var c := Vector3(side * 0.1, 0.0193, 0.068)
			var d := Vector3(side * 0.055, 0.0143, 0.012)
			_two_sided(f, [a, b, c])
			_two_sided(f, [a, c, d]))


static func _two_sided(f: MeshForge, tri: Array) -> void:
	var a: Vector3 = tri[0]
	var b: Vector3 = tri[1]
	var c: Vector3 = tri[2]
	var n := (b - a).cross(c - a).normalized()
	f.raw(PackedVector3Array([a, b, c, a, c, b]), PackedVector3Array([-n, -n, -n, n, n, n]), PackedVector2Array(),
		PackedInt32Array([0, 1, 2, 3, 4, 5]))


# —— 春天的花瓣(粒子网格)——

static func petal_mesh() -> ArrayMesh:
	# 一片两头尖的小花瓣(约 3 cm),颜色 = 粒子颜色;toon 漫反射、双面
	if not _cache.has("petal"):
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mat.roughness = 1.0
		mat.emission_enabled = true
		mat.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
		mat.emission = Color(0.12, 0.06, 0.08)
		var points := PackedVector3Array([Vector3.ZERO])
		var normals := PackedVector3Array([Vector3.UP])
		var indices := PackedInt32Array()
		var seg := 14
		for k in seg:
			var a := TAU * k / seg
			var w := 0.009 * pow(absf(sin(a)), 0.7)
			points.append(Vector3(sin(a) * w, 0.002 * cos(a * 2.0), cos(a) * 0.016))
			normals.append(Vector3.UP)
		for k in seg:
			indices.append_array([0, 1 + k, 1 + (k + 1) % seg])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, mat)
		_cache["petal"] = mesh
	return _cache["petal"]


# —— 报警徽章(公告板)——

static func alarm_badge() -> ArrayMesh:
	# 描边圆 + 番茄红圆 + 左上高光;中间的「!」与张数是 Label3D
	return _fx("alarm", func(f: MeshForge):
		f.paint(Color(0.32, 0.12, 0.1), 1.0)
		BombCatProps._disc(f, Vector3.ZERO, 0.07, 2, 28)
		f.paint(Color(1.0, 0.36, 0.32), 1.0)
		BombCatProps._disc(f, Vector3.ZERO, 0.061, 2, 28)
		f.paint(Color(1.0, 0.7, 0.66), 1.0)
		BombCatProps._disc(f, Vector3(-0.022, 0.026, 0), 0.012, 2, 12, Vector2(1.3, 0.8)),
		true)


static func trail_puff_colors() -> Array:
	return [Color(1.0, 0.95, 0.86), Color(1.0, 0.82, 0.5), Color(0.92, 0.9, 0.95)]
