class_name LiarsDiceProps
# 吹牛骰子的 3D 道具网格(设计稿 §3,全部程序生成、原创):动森式圆胖皮革骰盅、奶油色圆角骰子。
# - 骰盅:鼓肚子的车削体,口沿一圈深色皮带缝着奶油色针脚,顶上一颗小皮扣,侧面一枚黄铜小徽章(凸起的小星星);
#   皮色跟着物种主色(调色板的 fur,往暖皮革色里调一点),每个物种一份网格(颜色烘在顶点上,共用道具材质 WorldMaterials.prop())。
#   盅里面是深棕色(俯看张口的盅时像装着骰子的阴影)。坐标:原点在盅口中心,扣着时闭合的顶朝 +Y;徽章朝 +Z。
# - 骰子:奶油色圆角立方体,点是彩色小圆点,1 点画成一颗小星星(万能)。各面:1 +Y、6 −Y、2 +Z、5 −Z、3 +X、4 −X(对面相加为 7)。
#   原点在骰子中心,边长 LiarsDiceLayout.DIE_SIZE。开盅计数时高亮的那几颗换成同形的「发光」网格(暖色自发光烘在顶点上),
#   不用实例参数、不复制材质;所有骰子共用一份网格,Forward+ 自动合批。
# 网格都走 MeshForge.cached(主线程建一次,MeshForge.clear_cache 时释放);本类没有自己的静态缓存。效果件一律不投影。


const CUP_SEGMENTS := 36
const STITCHES := 22
const CUP_WALL := 0.007
const LEATHER := Color(0.72, 0.5, 0.32)        # 暖皮革色:物种主色往它里面调
const LEATHER_MIX := 0.38
const INSIDE := Color(0.2, 0.13, 0.09)
const STITCH := Color(0.8, 0.76, 0.66)
const BRASS := Color(0.8, 0.66, 0.36)
const DIE_CREAM := Color(0.8, 0.77, 0.69)
const DIE_ROUND := 0.28                        # 圆角半径占半边长的比例
const DIE_GRID := 7                            # 每个面的网格细分
const PIP_RADIUS := 0.095                      # 点的半径(占边长)
const PIP_SPREAD := 0.26                       # 点离面心的距离(占边长)
# 各点数的点色(sRGB,封顶 0.8):1 点是星星(暖金粉)
const PIP_COLORS := {
	1: Color(0.8, 0.5, 0.36), 2: Color(0.3, 0.64, 0.46), 3: Color(0.3, 0.5, 0.8), 4: Color(0.8, 0.36, 0.3),
	5: Color(0.56, 0.4, 0.8), 6: Color(0.78, 0.28, 0.62),
}
const STAR_COLOR := Color(0.8, 0.6, 0.24)
const GLOW := Vector2(0.2, 0.0)                # 高亮骰子的自发光(prop 着色器读 UV.x;只亮骰身,点不发光免得被冲白)
# 各点数朝哪个面(骰子局部):value -> 面法线
const FACE_NORMALS := {1: Vector3.UP, 6: Vector3.DOWN, 2: Vector3.BACK, 5: Vector3.FORWARD, 3: Vector3.RIGHT, 4: Vector3.LEFT}


# —— 颜色 ——

static func leather_of(species_index: int) -> Color:
	# 骰盅皮色:物种主色(粉彩化、封顶后的 fur)往暖皮革色里调一点;物种下标不对时用皮革色
	if species_index < 0 or species_index >= Species.count():
		return LEATHER
	var fur: Color = PatronParts.palette(PatronParts.species(species_index))["fur"]
	return PatronParts.capped(fur.lerp(LEATHER, LEATHER_MIX))


static func band_of(species_index: int) -> Color:
	return leather_of(species_index).darkened(0.32)


# —— 骰盅 ——

static func cup_key(species_index: int) -> String:
	return "dice:cup:%d" % species_index


static func cup(species_index: int) -> ArrayMesh:
	var leather := leather_of(species_index)
	var band := band_of(species_index)
	return MeshForge.cached(cup_key(species_index), func(f: MeshForge): cup_recipe(f, leather, band),
		{&"main": WorldMaterials.prop()})


static func cup_profile() -> PackedVector2Array:
	# 外轮廓 (半径, 高度) 自下(盅口)而上(闭合的顶):口沿略收、肚子鼓出来、肩膀圆圆地收到顶
	var r := LiarsDiceLayout.CUP_RADIUS
	var h := LiarsDiceLayout.CUP_HEIGHT
	return PackedVector2Array([
		Vector2(r * 0.97, 0.0), Vector2(r, h * 0.06), Vector2(r * 1.08, h * 0.32), Vector2(r * 1.06, h * 0.56),
		Vector2(r * 0.96, h * 0.76), Vector2(r * 0.8, h * 0.9), Vector2(r * 0.55, h * 0.975), Vector2(r * 0.25, h * 0.998),
		Vector2(0.0, h),
	])


static func cup_recipe(f: MeshForge, leather: Color, band: Color) -> void:
	var r := LiarsDiceLayout.CUP_RADIUS
	var h := LiarsDiceLayout.CUP_HEIGHT
	var outer := cup_profile()
	f.paint(leather, 0.62)
	f.lathe(outer, CUP_SEGMENTS)
	# 盅里:深棕色内壁(轮廓自上而下,法线朝里)+ 口沿一圈厚度
	var inner := PackedVector2Array()
	for k in range(outer.size() - 1, -1, -1):
		var p := outer[k]
		inner.append(Vector2(maxf(p.x - CUP_WALL, 0.0), minf(p.y, h - CUP_WALL)))
	f.paint(INSIDE, 0.9)
	f.lathe(inner, CUP_SEGMENTS)
	f.paint(band, 0.6)
	f.lathe(PackedVector2Array([Vector2(outer[0].x - CUP_WALL, 0.0), Vector2(outer[0].x, 0.0)]), CUP_SEGMENTS)
	# 口沿的皮带:一圈鼓起的深色皮条,上面缝一圈奶油色针脚
	var band_y := h * 0.13
	f.paint(band, 0.58)
	f.torus(r * 0.98, r * 1.1, CUP_SEGMENTS, MeshForge.xf(Vector3(0, band_y, 0), Vector3.ZERO, Vector3(1, 2.1, 1)))
	f.paint(STITCH, 0.7)
	for k in STITCHES:
		var a := TAU * (k + 0.5) / STITCHES
		var dir := Vector3(sin(a), 0, cos(a))
		var pos := dir * (r * 1.105) + Vector3(0, band_y, 0)
		f.capsule(0.0026, 0.012, 6, Transform3D(Basis(dir.cross(Vector3.UP).normalized(), Vector3.UP, dir) \
			* Basis(Vector3.BACK, PI * 0.5), pos))
	# 肩上第二圈细针脚(装饰缝线)
	var seam_y := h * 0.78
	var seam_r := r * 0.955
	for k in STITCHES - 4:
		var a := TAU * k / (STITCHES - 4)
		var dir := Vector3(sin(a), 0, cos(a))
		f.capsule(0.002, 0.009, 6, Transform3D(Basis(dir.cross(Vector3.UP).normalized(), Vector3.UP, dir) \
			* Basis(Vector3.BACK, PI * 0.5), dir * (seam_r + 0.001) + Vector3(0, seam_y, 0)))
	# 顶上的小皮扣
	f.paint(band, 0.55)
	f.sphere(r * 0.2, 14, MeshForge.xf(Vector3(0, h + r * 0.06, 0), Vector3.ZERO, Vector3(1, 0.55, 1)))
	f.paint(STITCH, 0.7)
	f.torus(r * 0.19, r * 0.24, 18, MeshForge.xf(Vector3(0, h - 0.002, 0), Vector3.ZERO, Vector3(1, 0.6, 1)))
	# 黄铜小徽章(朝 +Z):圆片 + 一圈边 + 凸起的小星星
	var badge_y := h * 0.45
	var badge_pos := Vector3(0, badge_y, r * 1.07)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(-4.0))
	f.paint(BRASS, 0.3, 0.7)
	f.glow = Vector2(0.06, 0.0)
	f.cylinder(0.024, 0.024, 0.006, 22, MeshForge.CAPS_BOTH, Transform3D(tilt * Basis(Vector3.RIGHT, PI * 0.5), badge_pos))
	f.paint(BRASS.darkened(0.15), 0.35, 0.7)
	f.torus(0.021, 0.026, 22, Transform3D(tilt * Basis(Vector3.RIGHT, PI * 0.5), badge_pos + tilt * Vector3(0, 0, 0.003)))
	f.paint(Color(0.8, 0.74, 0.5), 0.3, 0.6)
	f.extrude(star_outline(0.016, 0.0072), 0.004, 0.0012, Transform3D(tilt, badge_pos + tilt * Vector3(0, 0, 0.0045)))
	f.glow = Vector2.ZERO


static func star_outline(outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var a := PI * 0.5 + TAU * k / 10.0
		var rr := outer if k % 2 == 0 else inner
		pts.append(Vector2(cos(a), sin(a)) * rr)
	return pts


# —— 骰子 ——

static func die(glow := false) -> ArrayMesh:
	return MeshForge.cached("dice:die:glow" if glow else "dice:die", func(f: MeshForge): die_recipe(f, glow),
		{&"main": WorldMaterials.prop()})


static func die_recipe(f: MeshForge, glowing := false) -> void:
	var s := LiarsDiceLayout.DIE_SIZE
	f.paint(DIE_CREAM, 0.5)
	f.glow = GLOW if glowing else Vector2.ZERO
	rounded_cube(f, s * 0.5, s * 0.5 * DIE_ROUND, DIE_GRID)
	for value in range(1, 7):
		_face_marks(f, value, s, glowing)
		f.glow = GLOW if glowing else Vector2.ZERO
	f.glow = Vector2.ZERO


static func rounded_cube(f: MeshForge, half: float, radius: float, grid: int) -> void:
	# 圆角立方体:每个面一张 grid×grid 的网格,顶点推到「内缩立方体 + 半径 radius 的圆角」表面上,法线解析
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var core := half - radius
	var axes := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	for face in axes:
		var n: Vector3 = face[0]
		var u: Vector3 = face[1]
		var v: Vector3 = face[2]
		var base := points.size()
		for j in grid + 1:
			for i in grid + 1:
				var a := lerpf(-1.0, 1.0, float(i) / grid)
				var b := lerpf(-1.0, 1.0, float(j) / grid)
				var p: Vector3 = (n + u * a + v * b) * half
				var inner := p.clamp(Vector3.ONE * -core, Vector3.ONE * core)
				var d := (p - inner).normalized()
				points.append(inner + d * radius)
				normals.append(d)
		for j in grid:
			for i in grid:
				var i0 := base + j * (grid + 1) + i
				var tri := [i0, i0 + 1, i0 + grid + 1, i0 + 1, i0 + grid + 2, i0 + grid + 1]
				var e1: Vector3 = points[tri[1]] - points[tri[0]]
				var e2: Vector3 = points[tri[2]] - points[tri[0]]
				if e1.cross(e2).dot(n) > 0.0:   # Godot 正面是顺时针
					tri = [tri[0], tri[2], tri[1], tri[3], tri[5], tri[4]]
				indices.append_array(PackedInt32Array(tri))
	f.raw(points, normals, PackedVector2Array(), indices)


static func pip_layout(value: int) -> Array:
	# 面上的点位(面内坐标,单位:PIP_SPREAD);1 点只有面心(画星星)
	match value:
		1:
			return [Vector2.ZERO]
		2:
			return [Vector2(-1, -1), Vector2(1, 1)]
		3:
			return [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)]
		4:
			return [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
		5:
			return [Vector2(-1, -1), Vector2(1, -1), Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1)]
	return [Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)]


static func face_basis(value: int) -> Basis:
	# 把「朝 +Z 的面内坐标」转到 value 那一面:z 轴 = 面法线
	var n: Vector3 = FACE_NORMALS[value]
	var up := Vector3.UP if absf(n.y) < 0.9 else Vector3.BACK
	var x := up.cross(n).normalized()
	return Basis(x, n.cross(x).normalized(), n)


static func _face_marks(f: MeshForge, value: int, s: float, glowing: bool) -> void:
	var basis := face_basis(value)
	var surface := s * 0.5
	if value == 1:
		# 1 点:一颗胖星星(万能)
		f.paint(STAR_COLOR, 0.4)
		f.glow = Vector2(0.12, 0.0)
		f.extrude(star_outline(s * 0.3, s * 0.135), s * 0.05, s * 0.016, Transform3D(basis, basis.z * (surface + s * 0.006)),
			Vector2i(1, 1), 70.0)
		f.glow = GLOW if glowing else Vector2.ZERO
		return
	f.glow = Vector2.ZERO
	f.paint(PIP_COLORS[value], 0.45)
	for p: Vector2 in pip_layout(value):
		var local := Vector3(p.x, p.y, 0.0) * s * PIP_SPREAD
		var center := basis * local + basis.z * (surface - s * 0.012)
		f.sphere(s * PIP_RADIUS, 10, Transform3D(basis * Basis.from_scale(Vector3(1, 1, 0.42)), center))


static func up_basis(value: int, yaw := 0.0) -> Basis:
	# 让 value 那一面朝上(+Y),再绕竖轴转 yaw
	var n: Vector3 = FACE_NORMALS[clampi(value, 1, 6)]
	var to_up := Basis(Quaternion(n, Vector3.UP)) if n.dot(Vector3.UP) > -0.999 else Basis(Vector3.RIGHT, PI)
	return Basis(Vector3.UP, yaw) * to_up


static func top_face(basis: Basis) -> int:
	# 哪一面朝上(测试与对账用)
	var best := 1
	var best_dot := -2.0
	for value in FACE_NORMALS:
		var d: float = (basis * FACE_NORMALS[value]).normalized().dot(Vector3.UP)
		if d > best_dot:
			best_dot = d
			best = value
	return best
