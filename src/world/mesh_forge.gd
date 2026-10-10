class_name MeshForge
extends RefCounted
# 合批构建器:把多个部件写进同一组顶点数组(纯数组运算,可在工作线程跑),主线程 commit 成共享 ArrayMesh。
# 顶点布局:COLOR.rgb = sRGB albedo、COLOR.a = 烘焙 AO;UV2 = (roughness, metallic);
# CUSTOM0 = (部件原始局部坐标 xyz, 种子 w),只在该 surface 有部件开了 part_space 时才写(木纹等物体空间着色器用)。
# UV = glow(自发光强度, 透光强度):只在该 surface 有部件设过 glow 或用 raw 自带 UV 时才写(prop 着色器读它)。
# 旧基础体逐顶点复刻 Godot 的 PrimitiveMesh(运行时读 PrimitiveMesh 的数组在 Metal 上要从 GPU 回读,每次约 1.2 ms)。
# 配方(recipe: func(f: MeshForge))只用 MeshForge 的方法加数学运算:不建 Node/Resource、不用全局 randf()、不碰 autoload。

const CAPS_NONE := 0     # 与 MeshKit.CAPS_* 取值一致
const CAPS_TOP := 1
const CAPS_BOTTOM := 2
const CAPS_BOTH := 3
const CUSTOM0_FORMAT := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT

static var _cache := {}       # key -> ArrayMesh
static var _jobs := {}        # key -> _Job(后台预建中)

# —— 绘制状态(作用于之后加入的部件)——
var color := Color.WHITE      # sRGB albedo,口径同 StandardMaterial3D.albedo_color
var ao := 1.0
var rough := 0.7
var metal := 0.0
var part_space := false
var part_basis := Basis.IDENTITY   # part_space 时先把部件局部坐标转一下再写(竖直的车削件让木纹顺着长度走)
var part_origin := Vector3.ZERO    # part_space 时再加的偏移:CUSTOM0.xyz = part_basis × 局部顶点 + part_origin(护墙板按墙段写 u/v)
var seed := 0.0
var write_custom := false     # true:CUSTOM0 写 custom(酒客网格:材质类, 摆动权重, 种子, 透光)
var custom := Vector4.ZERO
var glow := Vector2.ZERO      # 写进 UV:x 自发光强度(0..1),y 透光(0..1);prop 着色器用,木纹 surface 不读

var _surfaces := {}           # StringName -> _Surface(按首次使用顺序)
var _order: Array[StringName] = []
var _current: _Surface
var _stack: Array[Transform3D] = [Transform3D.IDENTITY]


class _Surface:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv2 := PackedVector2Array()
	var custom0 := PackedFloat32Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var has_custom := false
	var has_uv := false


class _Job:
	var key: String
	var recipe: Callable
	var materials: Dictionary
	var task_id := -1
	var built: Dictionary


func _init() -> void:
	surface(&"main")


# —— 状态 ——

func paint(c: Color, r: float, m := 0.0) -> MeshForge:
	color = c
	rough = r
	metal = m
	return self


func surface(surface_name: StringName) -> MeshForge:
	# 切换 / 新建 surface:一个 surface 一个材质槽、一次 draw
	if not _surfaces.has(surface_name):
		_surfaces[surface_name] = _Surface.new()
		_order.append(surface_name)
	_current = _surfaces[surface_name]
	return self


func push(t: Transform3D) -> MeshForge:
	_stack.append(_stack.back() * t)
	return self


func pop() -> MeshForge:
	if _stack.size() > 1:
		_stack.pop_back()
	return self


static func xf(pos := Vector3.ZERO, rot_deg := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	# 与 Node3D(position / rotation_degrees / scale)以及 MeshKit.add 同口径
	var rot := Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z))
	return Transform3D(Basis.from_euler(rot) * Basis.from_scale(scale), pos)


func vertex_count() -> int:
	var n := 0
	for s in _surfaces.values():
		n += s.vertices.size()
	return n


# —— 旧基础体:逐顶点复刻 Godot primitive_meshes.cpp,参数与 MeshKit 同名函数一致 ——

func sphere(radius: float, segments := 24, t := Transform3D.IDENTITY) -> MeshForge:
	return _sphere(radius, radius * 2.0, segments, maxi(segments / 2, 6), false, t)


func hemisphere(radius: float, segments := 24, t := Transform3D.IDENTITY) -> MeshForge:
	return _sphere(radius, radius, segments, maxi(segments / 2, 6), true, t)


func _sphere(radius: float, height: float, radial: int, rings: int, is_hemisphere: bool, t: Transform3D) -> MeshForge:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var scale := height * (1.0 if is_hemisphere else 0.5)
	var point := 0
	var thisrow := 0
	var prevrow := 0
	for j in rings + 2:
		var v := float(j) / (rings + 1)
		var w := sin(PI * v)
		var y := scale * cos(PI * v)
		for i in radial + 1:
			var u := float(i) / radial
			var x := sin(u * TAU)
			var z := cos(u * TAU)
			if is_hemisphere and y < 0.0:
				points.append(Vector3(x * radius * w, 0.0, z * radius * w))
				normals.append(Vector3(0.0, -1.0, 0.0))
			else:
				points.append(Vector3(x * radius * w, y, z * radius * w))
				normals.append(Vector3(x * w * scale, radius * (y / scale), z * w * scale).normalized())
			point += 1
			if i > 0 and j > 0:
				indices.append_array([prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1])
		prevrow = thisrow
		thisrow = point
	return _append(points, normals, indices, t)


func cylinder(top_r: float, bottom_r: float, height: float, segments := 32, caps := CAPS_BOTH,
		t := Transform3D.IDENTITY) -> MeshForge:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var rings := 1   # MeshKit.cylinder 固定 rings = 1
	var side_normal_y := (bottom_r - top_r) / height
	var point := 0
	var thisrow := 0
	var prevrow := 0
	for j in rings + 2:
		var v := float(j) / (rings + 1)
		var radius := top_r + (bottom_r - top_r) * v
		var y := height * 0.5 - height * v
		for i in segments + 1:
			var u := float(i) / segments
			var x := sin(u * TAU)
			var z := cos(u * TAU)
			points.append(Vector3(x * radius, y, z * radius))
			normals.append(Vector3(x, side_normal_y, z).normalized())
			point += 1
			if i > 0 and j > 0:
				indices.append_array([prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1])
		prevrow = thisrow
		thisrow = point
	if caps & CAPS_TOP and top_r > 0.0:
		var y := height * 0.5
		thisrow = point
		points.append(Vector3(0.0, y, 0.0))
		normals.append(Vector3.UP)
		point += 1
		for i in segments + 1:
			var r := float(i) / segments
			points.append(Vector3(sin(r * TAU) * top_r, y, cos(r * TAU) * top_r))
			normals.append(Vector3.UP)
			point += 1
			if i > 0:
				indices.append_array([thisrow, point - 1, point - 2])
	if caps & CAPS_BOTTOM and bottom_r > 0.0:
		var y := height * -0.5
		thisrow = point
		points.append(Vector3(0.0, y, 0.0))
		normals.append(Vector3.DOWN)
		point += 1
		for i in segments + 1:
			var r := float(i) / segments
			points.append(Vector3(sin(r * TAU) * bottom_r, y, cos(r * TAU) * bottom_r))
			normals.append(Vector3.DOWN)
			point += 1
			if i > 0:
				indices.append_array([thisrow, point - 2, point - 1])
	return _append(points, normals, indices, t)


func capsule(radius: float, height: float, segments := 20, t := Transform3D.IDENTITY) -> MeshForge:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var rings := 6   # MeshKit.capsule 固定 rings = 6
	height = maxf(height, radius * 2.0)
	var point := 0
	# 上半球
	var thisrow := 0
	var prevrow := 0
	for j in rings + 2:
		var v := float(j) / (rings + 1)
		var w := 1.0 if j == rings + 1 else sin(0.5 * PI * v)
		var y := 0.0 if j == rings + 1 else cos(0.5 * PI * v)
		for i in segments + 1:
			var p := _capsule_dir(i, segments, w, y)
			points.append(p * radius + Vector3(0.0, 0.5 * height - radius, 0.0))
			normals.append(p)
			point += 1
			if i > 0 and j > 0:
				indices.append_array([prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1])
		prevrow = thisrow
		thisrow = point
	# 圆柱段
	thisrow = point
	prevrow = 0
	for j in rings + 2:
		var v := float(j) / (rings + 1)
		var y := (0.5 * height - radius) - (height - 2.0 * radius) * v
		for i in segments + 1:
			var d := _capsule_dir(i, segments, 1.0, 0.0)
			points.append(Vector3(d.x * radius, y, d.z * radius))
			normals.append(Vector3(d.x, 0.0, d.z))
			point += 1
			if i > 0 and j > 0:
				indices.append_array([prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1])
		prevrow = thisrow
		thisrow = point
	# 下半球
	thisrow = point
	prevrow = 0
	for j in rings + 2:
		var v := float(j) / (rings + 1)
		var w := 0.0 if j == rings + 1 else cos(0.5 * PI * v)
		var y := -1.0 if j == rings + 1 else -sin(0.5 * PI * v)
		for i in segments + 1:
			var p := _capsule_dir(i, segments, w, y)
			points.append(p * radius + Vector3(0.0, -0.5 * height + radius, 0.0))
			normals.append(p)
			point += 1
			if i > 0 and j > 0:
				indices.append_array([prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1])
		prevrow = thisrow
		thisrow = point
	return _append(points, normals, indices, t)


static func _capsule_dir(i: int, segments: int, w: float, y: float) -> Vector3:
	var x := 0.0
	var z := 1.0
	if i != segments:
		var u := float(i) / segments
		x = -sin(u * TAU)
		z = cos(u * TAU)
	return Vector3(x * w, y, -z * w)


func box(size: Vector3, t := Transform3D.IDENTITY) -> MeshForge:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var start := size * -0.5
	var point := 0
	# 前 + 后
	var y := start.y
	var thisrow := point
	var prevrow := 0
	for j in 2:
		var x := start.x
		for i in 2:
			points.append(Vector3(x, -y, -start.z))
			normals.append(Vector3(0.0, 0.0, 1.0))
			points.append(Vector3(-x, -y, start.z))
			normals.append(Vector3(0.0, 0.0, -1.0))
			point += 2
			if i > 0 and j > 0:
				_quad_pair(indices, prevrow, thisrow, i * 2)
			x += size.x
		y += size.y
		prevrow = thisrow
		thisrow = point
	# 右 + 左
	y = start.y
	thisrow = point
	prevrow = 0
	for j in 2:
		var z := start.z
		for i in 2:
			points.append(Vector3(-start.x, -y, -z))
			normals.append(Vector3(1.0, 0.0, 0.0))
			points.append(Vector3(start.x, -y, z))
			normals.append(Vector3(-1.0, 0.0, 0.0))
			point += 2
			if i > 0 and j > 0:
				_quad_pair(indices, prevrow, thisrow, i * 2)
			z += size.z
		y += size.y
		prevrow = thisrow
		thisrow = point
	# 上 + 下
	var z := start.z
	thisrow = point
	prevrow = 0
	for j in 2:
		var x := start.x
		for i in 2:
			points.append(Vector3(-x, -start.y, -z))
			normals.append(Vector3(0.0, 1.0, 0.0))
			points.append(Vector3(x, start.y, -z))
			normals.append(Vector3(0.0, -1.0, 0.0))
			point += 2
			if i > 0 and j > 0:
				_quad_pair(indices, prevrow, thisrow, i * 2)
			x += size.x
		z += size.z
		prevrow = thisrow
		thisrow = point
	return _append(points, normals, indices, t)


static func _quad_pair(indices: PackedInt32Array, prevrow: int, thisrow: int, i2: int) -> void:
	# 盒子与棱柱:同一行交替存放的两个面各出一个四边形
	indices.append_array([prevrow + i2 - 2, prevrow + i2, thisrow + i2 - 2, prevrow + i2, thisrow + i2, thisrow + i2 - 2])
	indices.append_array([prevrow + i2 - 1, prevrow + i2 + 1, thisrow + i2 - 1, prevrow + i2 + 1, thisrow + i2 + 1, thisrow + i2 - 1])


func torus(inner: float, outer: float, segments := 32, t := Transform3D.IDENTITY) -> MeshForge:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var rings := segments
	var ring_segments := 12   # MeshKit.torus 固定 ring_segments = 12
	var min_r := minf(inner, outer)
	var max_r := maxf(inner, outer)
	var radius := (max_r - min_r) * 0.5
	for i in rings + 1:
		var prevrow := (i - 1) * (ring_segments + 1)
		var thisrow := i * (ring_segments + 1)
		var angi := float(i) / rings * TAU
		var ni := Vector2(0.0, -1.0) if i == rings else Vector2(-sin(angi), -cos(angi))
		for j in ring_segments + 1:
			var angj := float(j) / ring_segments * TAU
			var nj := Vector2(-1.0, 0.0) if j == ring_segments else Vector2(-cos(angj), sin(angj))
			var nk := nj * radius + Vector2(min_r + radius, 0.0)
			points.append(Vector3(ni.x * nk.x, nk.y, ni.y * nk.x))
			normals.append(Vector3(ni.x * nj.x, nj.y, ni.y * nj.x))
			if i > 0 and j > 0:
				indices.append_array([thisrow + j - 1, prevrow + j, prevrow + j - 1, thisrow + j - 1, thisrow + j, prevrow + j])
	return _append(points, normals, indices, t)


func prism(size: Vector3, t := Transform3D.IDENTITY) -> MeshForge:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var ltr := 0.5   # PrismMesh.left_to_right 默认值
	var start := size * -0.5
	var point := 0
	# 前 + 后
	var y := start.y
	var thisrow := point
	var prevrow := 0
	for j in 2:
		var scale := (y - start.y) / size.y
		var scaled_x := size.x * scale
		var start_x := start.x + (1.0 - scale) * size.x * ltr
		var x := 0.0
		for i in 2:
			points.append(Vector3(start_x + x, -y, -start.z))
			normals.append(Vector3(0.0, 0.0, 1.0))
			points.append(Vector3(start_x + scaled_x - x, -y, start.z))
			normals.append(Vector3(0.0, 0.0, -1.0))
			point += 2
			if i > 0 and j == 1:
				var i2 := i * 2
				indices.append_array([prevrow + i2, thisrow + i2, thisrow + i2 - 2])
				indices.append_array([prevrow + i2 + 1, thisrow + i2 + 1, thisrow + i2 - 1])
			elif i > 0 and j > 0:
				_quad_pair(indices, prevrow, thisrow, i * 2)
			x += scale * size.x
		y += size.y
		prevrow = thisrow
		thisrow = point
	# 右 + 左(斜面)
	var normal_left := Vector3(-size.y, size.x * ltr, 0.0).normalized()
	var normal_right := Vector3(size.y, size.x * (1.0 - ltr), 0.0).normalized()
	y = start.y
	thisrow = point
	prevrow = 0
	for j in 2:
		var scale := (y - start.y) / size.y
		var left := start.x + size.x * (1.0 - scale) * ltr
		var right := left + size.x * scale
		var z := start.z
		for i in 2:
			points.append(Vector3(right, -y, -z))
			normals.append(normal_right)
			points.append(Vector3(left, -y, z))
			normals.append(normal_left)
			point += 2
			if i > 0 and j > 0:
				_quad_pair(indices, prevrow, thisrow, i * 2)
			z += size.z
		y += size.y
		prevrow = thisrow
		thisrow = point
	# 底
	var z := start.z
	thisrow = point
	prevrow = 0
	for j in 2:
		var x := start.x
		for i in 2:
			points.append(Vector3(x, start.y, -z))
			normals.append(Vector3(0.0, -1.0, 0.0))
			point += 1
			if i > 0 and j > 0:
				indices.append_array([prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1])
			x += size.x
		z += size.z
		prevrow = thisrow
		thisrow = point
	return _append(points, normals, indices, t)


# —— 新几何 ——

func lathe(profile: PackedVector2Array, segments := 24, creases := PackedInt32Array(),
		t := Transform3D.IDENTITY) -> MeshForge:
	# 车削体:profile 为 (半径, 高度) 自下而上;creases 里的轮廓点复制一份做硬边;
	# 半径为 0 的端点自然收口。法线按轮廓切线解析计算
	var rows: Array[Dictionary] = []   # 每行:轮廓点与它的轮廓法线(r, y 方向)
	var n := profile.size()
	for k in n:
		var prev := profile[maxi(k - 1, 0)]
		var next := profile[mini(k + 1, n - 1)]
		if creases.has(k) and k > 0 and k < n - 1:
			rows.append({"p": profile[k], "n": _lathe_normal(prev, profile[k])})
			rows.append({"p": profile[k], "n": _lathe_normal(profile[k], next)})
		else:
			rows.append({"p": profile[k], "n": _lathe_normal(prev, next)})
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var stride := segments + 1
	for r in rows.size():
		var p: Vector2 = rows[r]["p"]
		var pn: Vector2 = rows[r]["n"]
		for i in stride:
			var a := float(i) / segments * TAU
			var dir := Vector3(sin(a), 0.0, cos(a))
			points.append(Vector3(dir.x * p.x, p.y, dir.z * p.x))
			normals.append((dir * pn.x + Vector3(0.0, pn.y, 0.0)).normalized())
			if r > 0 and i > 0 and rows[r]["p"] != rows[r - 1]["p"]:
				var a0 := (r - 1) * stride + i - 1
				var b0 := r * stride + i - 1
				indices.append_array([a0, b0, a0 + 1, a0 + 1, b0, b0 + 1])
	return _append(points, normals, indices, t)


func quad(size: Vector2, rect := Rect2(0, 0, 1, 1), t := Transform3D.IDENTITY, curl := 0.0, seg := 1) -> MeshForge:
	# 贴图面片:XY 平面、朝 +Z、中心在原点;UV 按 rect 铺(u 向右、v 向下,同图集像素方向)。
	# curl > 0 时下沿向 +Z 卷起(海报卷边):离下沿越近抬得越高,最大 curl 米;seg 是竖向分段数
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rows := maxi(seg, 1)
	for j in rows + 1:
		var v := float(j) / rows            # 0 = 上沿,1 = 下沿
		var lift := curl * pow(maxf(v - 0.55, 0.0) / 0.45, 2.0)
		var slope := curl * 2.0 * maxf(v - 0.55, 0.0) / (0.45 * 0.45) / maxf(size.y, 1e-6)
		var n := Vector3(0.0, -slope, 1.0).normalized()
		for i in 2:
			points.append(Vector3((float(i) - 0.5) * size.x, (0.5 - v) * size.y, lift))
			normals.append(n)
			uvs.append(Vector2(rect.position.x + rect.size.x * i, rect.position.y + rect.size.y * v))
			if j > 0 and i > 0:
				var a := (j - 1) * 2
				indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])
	return _append(points, normals, indices, t, PackedColorArray(), PackedFloat32Array(), uvs)


func extrude_x(profile: PackedVector2Array, length: float, t := Transform3D.IDENTITY, caps := Vector2i(1, 1)) -> MeshForge:
	# 截面沿 X 挤出(线脚、托架、门套;沿 Z、带倒角的见 extrude):profile 是局部 (z, y) 平面上的闭合多边形(逆时针,从 +X 看),
	# 沿局部 X 从 -length/2 挤到 +length/2;侧面每条边各自一组法线(硬边),两端按多边形三角化封口
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var n := profile.size()
	if n < 3:
		return self
	var area := 0.0
	for k in n:
		var a := profile[k]
		var b := profile[(k + 1) % n]
		area += a.x * b.y - b.x * a.y
	var orient := 1.0 if area > 0.0 else -1.0   # 顺时针给的截面也按外法线算
	var hx := length * 0.5
	for k in n:
		var a := profile[k]
		var b := profile[(k + 1) % n]
		var d := b - a
		if d.length_squared() < 1e-14:
			continue
		var nn := Vector3(0.0, -d.x, d.y).normalized() * orient   # (z, y) 边的外法线:z 分量 = dy,y 分量 = -dz
		var base := points.size()
		points.append_array([Vector3(-hx, a.y, a.x), Vector3(hx, a.y, a.x), Vector3(-hx, b.y, b.x), Vector3(hx, b.y, b.x)])
		normals.append_array([nn, nn, nn, nn])
		if orient > 0.0:
			indices.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3])
		else:
			indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
	var tris := Geometry2D.triangulate_polygon(profile)
	for end in 2:
		if (end == 0 and caps.x == 0) or (end == 1 and caps.y == 0):
			continue
		var x := -hx if end == 0 else hx
		var nn := Vector3(-1.0 if end == 0 else 1.0, 0.0, 0.0)
		var base := points.size()
		for p in profile:
			points.append(Vector3(x, p.y, p.x))
			normals.append(nn)
		for k in range(0, tris.size(), 3):
			# 逐个三角形按封口法线定绕序(与 Godot 基础体同向:叉积背向法线)
			var i0 := tris[k]
			var i1 := tris[k + 1]
			var i2 := tris[k + 2]
			var face := (points[base + i1] - points[base + i0]).cross(points[base + i2] - points[base + i0])
			if face.dot(nn) > 0.0:
				indices.append_array([base + i0, base + i2, base + i1])
			else:
				indices.append_array([base + i0, base + i1, base + i2])
	return _append(points, normals, indices, t)


func grid(rows: Array, t := Transform3D.IDENTITY) -> MeshForge:
	# 网格面(布料、窗帘):rows 是若干行等长的 PackedVector3Array(自上而下),相邻两行连成四边形带;
	# 法线按相邻点差分,朝向 (列方向 × 行方向)
	var nr := rows.size()
	if nr < 2:
		return self
	var nc: int = rows[0].size()
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for r in nr:
		var row: PackedVector3Array = rows[r]
		for c in nc:
			var du: Vector3 = row[mini(c + 1, nc - 1)] - row[maxi(c - 1, 0)]
			var dv: Vector3 = rows[mini(r + 1, nr - 1)][c] - rows[maxi(r - 1, 0)][c]
			var n := du.cross(dv)
			points.append(row[c])
			normals.append(n.normalized() if n.length_squared() > 1e-14 else Vector3.UP)
			if r > 0 and c > 0:
				var a := (r - 1) * nc + c - 1
				var b := r * nc + c - 1
				indices.append_array([a, b, a + 1, a + 1, b, b + 1])
	return _append(points, normals, indices, t)


# —— 有机形体 ——

func blob(center: Vector3, shapes: Array, seg := 40, rings := 24, k := 0.03, t := Transform3D.IDENTITY) -> MeshForge:
	# 椭球平滑并集(头雕、腮、口鼻、爪掌):从 center 向外星形射线行进。
	# shapes:[[中心, 半径 Vector3, 颜色 Color, 可选 "mirror"(同时放一份 x 镜像)], ...];center 要在主体里面。
	# 各椭球远交点的最大值是表面下界 t0(平滑并集只会往外鼓,幅度 ≤ k),在 [t0, t0 + k] 里二分;
	# 法线取 SDF 的差分,颜色按离表面最近(最靠里)的形体在 k 内平滑混合
	var list := _expand_shapes(shapes)
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var eps := 0.0015
	for j in rings + 1:
		var theta := PI * j / rings
		for i in seg + 1:
			var phi := TAU * i / seg
			var d := Vector3(sin(phi) * sin(theta), cos(theta), cos(phi) * sin(theta))
			var lo := 0.0
			for shape in list:
				lo = maxf(lo, _ray_ellipsoid_far(center, d, shape[0], shape[1]))
			var hi := lo + k
			for _step in 8:
				var mid := (lo + hi) * 0.5
				if _blob_sdf(center + d * mid, list, k) < 0.0:
					lo = mid
				else:
					hi = mid
			var p := center + d * ((lo + hi) * 0.5)
			var grad := Vector3(
				_blob_sdf(p + Vector3(eps, 0, 0), list, k) - _blob_sdf(p - Vector3(eps, 0, 0), list, k),
				_blob_sdf(p + Vector3(0, eps, 0), list, k) - _blob_sdf(p - Vector3(0, eps, 0), list, k),
				_blob_sdf(p + Vector3(0, 0, eps), list, k) - _blob_sdf(p - Vector3(0, 0, eps), list, k))
			points.append(p)
			normals.append(grad.normalized() if grad.length_squared() > 1e-12 else d)
			colors.append(_blob_color(p, list, k))
			if i > 0 and j > 0:
				var prevrow := (j - 1) * (seg + 1)
				var thisrow := j * (seg + 1)
				indices.append_array([prevrow + i - 1, prevrow + i, thisrow + i - 1, prevrow + i, thisrow + i, thisrow + i - 1])
	return _append(points, normals, indices, t, colors)


static func blob_surface(center: Vector3, d: Vector3, shapes: Array, k := 0.03) -> Vector3:
	# 平滑并集表面上沿射线 center + d·t 的那一点(扣子、斑纹、胡须挂点贴在表面上用);坐标与 blob 相同,不含变换
	var list := _expand_shapes(shapes)
	d = d.normalized()
	var lo := 0.0
	for shape in list:
		lo = maxf(lo, _ray_ellipsoid_far(center, d, shape[0], shape[1]))
	var hi := lo + k
	for _step in 10:
		var mid := (lo + hi) * 0.5
		if _blob_sdf(center + d * mid, list, k) < 0.0:
			lo = mid
		else:
			hi = mid
	return center + d * ((lo + hi) * 0.5)


func mark() -> int:
	# 当前 surface 已有的顶点数:配合 displace 只改之后加入的部件
	return _current.vertices.size()


func displace(from: int, fn: Callable) -> MeshForge:
	# 把当前 surface 第 from 个之后的顶点逐个换成 fn(位置) 的结果(帽檐卷边、压痕);法线不重算,只适合小幅变形
	var s := _current
	for i in range(from, s.vertices.size()):
		s.vertices[i] = fn.call(s.vertices[i])
	return self


static func _expand_shapes(shapes: Array) -> Array:
	var out := []
	for shape in shapes:
		var c: Color = shape[2] if shape.size() > 2 else Color.WHITE
		out.append([shape[0], shape[1], c])
		if shape.size() > 3 and shape[3] == "mirror":
			out.append([Vector3(-shape[0].x, shape[0].y, shape[0].z), shape[1], c])
	return out


static func _ellipsoid_sdf(p: Vector3, r: Vector3) -> float:
	# 椭球近似距离(Inigo Quilez):表面上为 0,内部为负
	var k0 := (p / r).length()
	var k1 := (p / (r * r)).length()
	return k0 * (k0 - 1.0) / maxf(k1, 1e-9)


static func _blob_sdf(p: Vector3, list: Array, k: float) -> float:
	var d := INF
	for shape in list:
		var e := _ellipsoid_sdf(p - shape[0], shape[1])
		if d == INF:
			d = e
		else:
			var h := maxf(k - absf(d - e), 0.0) / k
			d = minf(d, e) - h * h * k * 0.25
	return d


static func _blob_color(p: Vector3, list: Array, k: float) -> Color:
	var dists := []
	var best := INF
	for shape in list:
		var e := _ellipsoid_sdf(p - shape[0], shape[1])
		dists.append(e)
		best = minf(best, e)
	var total := 0.0
	var mixed := Color(0, 0, 0, 0)
	var band := k * 0.6
	for n in list.size():
		var w := clampf(1.0 - (dists[n] - best) / band, 0.0, 1.0)
		w = w * w * (3.0 - 2.0 * w)
		mixed += list[n][2] * w
		total += w
	return mixed / total


static func _ray_ellipsoid_far(origin: Vector3, d: Vector3, center: Vector3, r: Vector3) -> float:
	# 射线 origin + d·t 与椭球的远交点 t;不相交返回 0
	var o := (origin - center) / r
	var v := d / r
	var a := v.dot(v)
	var b := 2.0 * o.dot(v)
	var c := o.dot(o) - 1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return 0.0
	return maxf((-b + sqrt(disc)) / (2.0 * a), 0.0)


func loft(path: PackedVector3Array, radii: PackedVector2Array, sides := 16, caps := Vector2i(1, 1),
		t := Transform3D.IDENTITY, ring_colors := PackedColorArray(), sway := Vector2(-1, -1),
		up_hint := Vector3.UP) -> MeshForge:
	# 沿路径放样椭圆截面(躯干、袖子、尾巴、腿):radii[i] = (rx, rz),rx 沿起始「上方」方向,rz 沿侧向;
	# 截面朝向按平行移动传递,不会扭。ring_colors 逐圈颜色(硬边色带要在边界处重复一圈点);
	# sway.x ≥ 0 时把沿路径参数在 [sway.x, sway.y] 里平滑升到 1 的摆动权重写进 CUSTOM0.y(尾巴)
	var n := path.size()
	if n < 2:
		return self
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var customs := PackedFloat32Array()
	var indices := PackedInt32Array()
	var lengths := PackedFloat32Array([0.0])
	for i in range(1, n):
		lengths.append(lengths[i - 1] + path[i].distance_to(path[i - 1]))
	var total_len := maxf(lengths[n - 1], 1e-6)
	var tangents: Array[Vector3] = []
	for i in n:
		tangents.append((path[mini(i + 1, n - 1)] - path[maxi(i - 1, 0)]).normalized())
	var normal := up_hint - tangents[0] * up_hint.dot(tangents[0])
	if normal.length_squared() < 1e-6:
		normal = Vector3.RIGHT - tangents[0] * Vector3.RIGHT.dot(tangents[0])
	normal = normal.normalized()
	var frames: Array[Basis] = []
	for i in n:
		if i > 0:
			normal = (normal - tangents[i] * normal.dot(tangents[i])).normalized()
		frames.append(Basis(normal, tangents[i].cross(normal), tangents[i]))
	var use_custom := write_custom or sway.x >= 0.0
	var stride := sides + 1
	for i in n:
		var f := frames[i]
		var r := radii[i]
		var span := maxf(lengths[mini(i + 1, n - 1)] - lengths[maxi(i - 1, 0)], 1e-6)
		var slope := ((radii[mini(i + 1, n - 1)].x + radii[mini(i + 1, n - 1)].y)
			- (radii[maxi(i - 1, 0)].x + radii[maxi(i - 1, 0)].y)) * 0.5 / span
		var col: Color = ring_colors[i] if not ring_colors.is_empty() else Color(color.r, color.g, color.b, ao)
		var w := 0.0
		if sway.x >= 0.0:
			w = smoothstep(sway.x, sway.y, lengths[i] / total_len)
		for jj in stride:
			var a := TAU * jj / sides
			var ca := cos(a)
			var sa := sin(a)
			points.append(path[i] + f.x * (ca * r.x) + f.y * (sa * r.y))
			var sec := (f.x * (ca / maxf(r.x, 1e-6)) + f.y * (sa / maxf(r.y, 1e-6))).normalized()
			normals.append((sec - f.z * slope).normalized())
			colors.append(col)
			if use_custom:
				customs.append_array([custom.x, w if sway.x >= 0.0 else custom.y, custom.z, custom.w])
			if i > 0 and jj > 0:
				var a0 := (i - 1) * stride + jj - 1
				var b0 := i * stride + jj - 1
				indices.append_array([a0, b0, a0 + 1, a0 + 1, b0, b0 + 1])
	for end in 2:
		if (end == 0 and caps.x == 0) or (end == 1 and caps.y == 0):
			continue
		var i := 0 if end == 0 else n - 1
		var f := frames[i]
		var outward := -f.z if end == 0 else f.z
		var col: Color = ring_colors[i] if not ring_colors.is_empty() else Color(color.r, color.g, color.b, ao)
		var center_index := points.size()
		points.append(path[i])
		normals.append(outward)
		colors.append(col)
		var w := smoothstep(sway.x, sway.y, lengths[i] / total_len) if sway.x >= 0.0 else custom.y
		if use_custom:
			customs.append_array([custom.x, w, custom.z, custom.w])
		for jj in stride:
			var a := TAU * jj / sides
			points.append(path[i] + f.x * (cos(a) * radii[i].x) + f.y * (sin(a) * radii[i].y))
			normals.append(outward)
			colors.append(col)
			if use_custom:
				customs.append_array([custom.x, w, custom.z, custom.w])
			if jj > 0:
				if end == 0:
					indices.append_array([center_index, center_index + jj, center_index + jj + 1])
				else:
					indices.append_array([center_index, center_index + jj + 1, center_index + jj])
	return _append(points, normals, indices, t, colors, customs)


func tube(path: PackedVector3Array, radius: float, sides := 6, t := Transform3D.IDENTITY) -> MeshForge:
	# 细管(胡须、表链、嘴线、颏绳):圆截面放样,两端封口
	var radii := PackedVector2Array()
	for i in path.size():
		radii.append(Vector2(radius, radius))
	return loft(path, radii, sides, Vector2i(1, 1), t)


static func _lathe_normal(a: Vector2, b: Vector2) -> Vector2:
	# 轮廓从 a 到 b(自下而上)的外法线:切线 (dr, dy) 顺时针转 90°
	var d := b - a
	if d.length_squared() < 1e-12:
		return Vector2(1.0, 0.0)
	return Vector2(d.y, -d.x).normalized()



func paint_glow(from: int, fn: Callable) -> MeshForge:
	# 把当前 surface 第 from 个之后的顶点的 glow 改成 fn(位置) -> Vector2(蜡烛顶端渐亮)
	var s := _current
	if not s.has_uv:
		s.has_uv = true
		s.uv.resize(s.vertices.size())
	for i in range(from, s.vertices.size()):
		s.uv[i] = fn.call(s.vertices[i])
	return self


func raw(points: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array,
		t := Transform3D.IDENTITY) -> MeshForge:
	# 直接写一组顶点(卡牌牌体自己算 UV);uvs 为空时用当前 glow
	return _append(points, normals, indices, t, PackedColorArray(), PackedFloat32Array(), uvs)


func extrude(outline: PackedVector2Array, depth: float, bevel := 0.0, t := Transform3D.IDENTITY,
		caps := Vector2i(1, 1), crease_deg := 40.0, round_steps := 1) -> MeshForge:
	# 把 XY 平面上的轮廓沿 Z 挤出,z ∈ [−depth/2, depth/2];两端各一圈倒角(斜接内缩,凹角限幅 0.35)。
	# 轮廓自动转成逆时针;转角大于 crease_deg 的地方侧墙硬边。不支持带洞轮廓(端面用 Geometry2D 三角化)。
	# caps.x / caps.y:是否封 −Z / +Z 端面(转轮前端面另外拼,见 Revolver 网格)。
	# round_steps > 1:倒角换成 round_steps 段的四分之一圆弧(软胶玩具式的圆边),法线沿圆弧平滑过渡;
	# 端面仍是内缩 bevel 的轮廓(与 extrude_inset(outline, bevel) 一致)。默认 1 = 原来的单斜面
	var pts := outline.duplicate()
	if _signed_area(pts) < 0.0:
		pts.reverse()
	var n := pts.size()
	if n < 3:
		return self
	var half := depth * 0.5
	bevel = clampf(bevel, 0.0, half * 0.95)
	var edge_n: Array[Vector2] = []   # 第 i 条边(i → i+1)的外法线
	for i in n:
		var d := pts[(i + 1) % n] - pts[i]
		edge_n.append(Vector2(d.y, -d.x).normalized())
	var inset := extrude_inset(pts, bevel)
	# 侧墙一圈:硬边处复制顶点。ring 里每项 [点下标, 2D 法线]
	var ring: Array = []
	var cos_crease := cos(deg_to_rad(crease_deg))
	for i in n:
		var a: Vector2 = edge_n[(i - 1 + n) % n]
		var b: Vector2 = edge_n[i]
		if a.dot(b) < cos_crease:
			ring.append([i, a])
			ring.append([i, b])
		else:
			ring.append([i, (a + b).normalized()])
	# 首尾相接:第一项若是硬边的后半(属于边 0),要放到最前面已是;把末尾那条边接回开头
	var rows: Array = []   # 每行 [z, 该行轮廓, 侧向法线权重, 法线 z 分量]
	if bevel > 0.0 and round_steps > 1:
		# 圆弧倒角:a 从端面(PI/2)转到侧墙(0),内缩 bevel·(1 − cos a),离端面 bevel·(1 − sin a)
		var arc: Array = []
		for s in range(round_steps, -1, -1):
			var a := PI / 2.0 * s / round_steps
			var ring_pts := inset if s == round_steps else (pts if s == 0 else extrude_inset(pts, bevel * (1.0 - cos(a))))
			arc.append([bevel * (1.0 - sin(a)), ring_pts, cos(a), sin(a)])
		for item in arc:
			rows.append([-half + item[0], item[1], item[2], -item[3]])
		for i in range(arc.size() - 1, -1, -1):
			rows.append([half - arc[i][0], arc[i][1], arc[i][2], arc[i][3]])
	elif bevel > 0.0:
		rows = [[-half, inset, 1.0, -1.2], [-half + bevel, pts, 1.0, 0.0], [half - bevel, pts, 1.0, 0.0], [half, inset, 1.0, 1.2]]
	else:
		rows = [[-half, pts, 1.0, 0.0], [half, pts, 1.0, 0.0]]
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var stride := ring.size() + 1
	for row in rows:
		var row_pts: PackedVector2Array = row[1]
		for k in stride:
			var item: Array = ring[k % ring.size()]
			var p2: Vector2 = row_pts[item[0]]
			var n2: Vector2 = item[1] * row[2]
			points.append(Vector3(p2.x, p2.y, row[0]))
			normals.append(Vector3(n2.x, n2.y, row[3]).normalized())
	for r in range(1, rows.size()):
		for k in ring.size():
			var item: Array = ring[k]
			var next: Array = ring[(k + 1) % ring.size()]
			if item[0] == next[0]:
				continue   # 硬边的两份顶点之间不连面
			var a0 := (r - 1) * stride + k
			var b0 := r * stride + k
			indices.append_array([a0, b0, a0 + 1, a0 + 1, b0, b0 + 1])
	var cap_poly := inset if bevel > 0.0 else pts
	var tris := Geometry2D.triangulate_polygon(cap_poly)
	for end in 2:
		if (end == 0 and caps.x == 0) or (end == 1 and caps.y == 0):
			continue
		var z := -half if end == 0 else half
		var base := points.size()
		for p in cap_poly:
			points.append(Vector3(p.x, p.y, z))
			normals.append(Vector3(0, 0, -1.0 if end == 0 else 1.0))
		for k in range(0, tris.size(), 3):
			# triangulate_polygon 出的是(从 +Z 看)逆时针;Godot 正面是顺时针
			if end == 1:
				indices.append_array([base + tris[k], base + tris[k + 2], base + tris[k + 1]])
			else:
				indices.append_array([base + tris[k], base + tris[k + 1], base + tris[k + 2]])
	return _append(points, normals, indices, t)


static func extrude_inset(pts: PackedVector2Array, amount: float) -> PackedVector2Array:
	# 逆时针轮廓按斜接内缩 amount(凹角处限幅 0.35,免得尖角处戳出去太远)
	var n := pts.size()
	var out := PackedVector2Array()
	for i in n:
		var d0 := pts[i] - pts[(i - 1 + n) % n]
		var d1 := pts[(i + 1) % n] - pts[i]
		var n0 := Vector2(d0.y, -d0.x).normalized()
		var n1 := Vector2(d1.y, -d1.x).normalized()
		var m := (n0 + n1)
		m = m.normalized() if m.length_squared() > 1e-12 else n0
		var k := maxf(m.dot(n0), 0.35)
		out.append(pts[i] - m * (amount / k))
	return out


static func _signed_area(pts: PackedVector2Array) -> float:
	var area := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


# —— 写入 ——

func _append(points: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array, t: Transform3D,
		colors := PackedColorArray(), customs := PackedFloat32Array(), uvs := PackedVector2Array()) -> MeshForge:
	# colors / customs / uvs 可选:逐顶点颜色(sRGB,a = AO)、逐顶点 CUSTOM0(每顶点 4 个数)与 UV;不给就用当前绘制状态。
	# 一个 surface 里只要有部件给了 UV 或发光,整个 surface 都写 UV(没给的部件补发光值或 0)
	var xform: Transform3D = _stack.back() * t
	var det := xform.basis.determinant()
	if absf(det) < 1e-9:
		return self   # 缩放退化的部件不写
	var normal_basis := xform.basis.inverse().transposed()
	var s := _current
	var base := s.vertices.size()
	var c := Color(color.r, color.g, color.b, ao)
	var pbr := Vector2(rough, metal)
	var wants_custom := part_space or write_custom or not customs.is_empty()
	if wants_custom and not s.has_custom:
		s.has_custom = true
		s.custom0.resize(base * 4)   # 之前的部件补 0
	if (glow != Vector2.ZERO or not uvs.is_empty()) and not s.has_uv:
		s.has_uv = true
		s.uv.resize(base)            # 之前的部件补 0
	for k in points.size():
		s.vertices.append(xform * points[k])
		s.normals.append((normal_basis * normals[k]).normalized())
		s.colors.append(colors[k] if not colors.is_empty() else c)
		s.uv2.append(pbr)
		if s.has_uv:
			s.uv.append(uvs[k] if not uvs.is_empty() else glow)
		if s.has_custom:
			if not customs.is_empty():
				s.custom0.append_array([customs[k * 4], customs[k * 4 + 1], customs[k * 4 + 2], customs[k * 4 + 3]])
			elif part_space:
				var q := part_basis * points[k] + part_origin
				s.custom0.append_array([q.x, q.y, q.z, seed])
			elif write_custom:
				s.custom0.append_array([custom.x, custom.y, custom.z, custom.w])
			else:
				s.custom0.append_array([0.0, 0.0, 0.0, 0.0])
	if det < 0.0:
		# 镜像变换翻转绕序
		for k in range(0, indices.size(), 3):
			s.indices.append_array([base + indices[k], base + indices[k + 2], base + indices[k + 1]])
	else:
		for k in indices.size():
			s.indices.append(base + indices[k])
	return self


# —— 输出 ——

func build() -> Dictionary:
	# {surface 名: Mesh.ARRAY_MAX 长度的数组},纯数据,线程安全
	var out := {}
	for surface_name in _order:
		var s: _Surface = _surfaces[surface_name]
		if s.vertices.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s.vertices
		arrays[Mesh.ARRAY_NORMAL] = s.normals
		arrays[Mesh.ARRAY_COLOR] = s.colors
		arrays[Mesh.ARRAY_TEX_UV2] = s.uv2
		if s.has_uv:
			arrays[Mesh.ARRAY_TEX_UV] = s.uv
		arrays[Mesh.ARRAY_INDEX] = s.indices
		if s.has_custom:
			arrays[Mesh.ARRAY_CUSTOM0] = s.custom0
		out[surface_name] = arrays
	return out


static func commit(built: Dictionary, materials := {}) -> ArrayMesh:
	# 只在主线程调用;材质挂在网格的 surface 上,共享网格的实例照样自动实例化
	var mesh := ArrayMesh.new()
	for surface_name in built:
		var arrays: Array = built[surface_name]
		var flags := CUSTOM0_FORMAT if arrays[Mesh.ARRAY_CUSTOM0] != null else 0
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		var index := mesh.get_surface_count() - 1
		mesh.surface_set_name(index, surface_name)
		if materials.has(surface_name):
			mesh.surface_set_material(index, materials[surface_name])
	return mesh


static func run(recipe: Callable) -> Dictionary:
	var forge := MeshForge.new()
	recipe.call(forge)
	return forge.build()


# —— 缓存与预建 ——

static func cached(key: String, recipe: Callable, materials := {}) -> ArrayMesh:
	if _cache.has(key):
		return _cache[key]
	var built: Dictionary
	if _jobs.has(key):
		var job: _Job = _jobs[key]
		WorkerThreadPool.wait_for_task_completion(job.task_id)   # 纯数学任务,不会死锁
		_jobs.erase(key)
		built = job.built
	else:
		built = run(recipe)
	_cache[key] = commit(built, materials)
	return _cache[key]


static func is_cached(key: String) -> bool:
	return _cache.has(key)


static func prebuild(jobs: Array) -> void:
	# jobs: [[key, recipe, materials], …]:投递到工作线程,不等待;材质在投递前由调用方建好
	for spec in jobs:
		var key: String = spec[0]
		if _cache.has(key) or _jobs.has(key):
			continue
		var job := _Job.new()
		job.key = key
		job.recipe = spec[1]
		job.materials = spec[2] if spec.size() > 2 else {}
		job.task_id = WorkerThreadPool.add_task(func(): job.built = run(job.recipe), true, "MeshForge " + key)   # 高优先级:低优先级任务在 8 核上只有 2 个线程,4 核上串行
		_jobs[key] = job


static func wait_prebuilt(tree: SceneTree) -> void:
	# 协程:每帧轮询,完成一个就回收任务(每个任务都必须 wait 一次)并 commit 进缓存
	while not _jobs.is_empty():
		for key in _jobs.keys():
			var job: _Job = _jobs[key]
			if WorkerThreadPool.is_task_completed(job.task_id):
				WorkerThreadPool.wait_for_task_completion(job.task_id)
				_jobs.erase(key)
				_cache[key] = commit(job.built, job.materials)
		if not _jobs.is_empty():
			await tree.process_frame


static func clear_cache() -> void:
	for job: _Job in _jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task_id)
	_jobs = {}
	_cache = {}
