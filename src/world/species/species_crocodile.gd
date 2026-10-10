extends RefCounted
# 鳄鱼「亡命徒」:扁宽的圆头长吻分上下两颌(上颌罩住下颌、嘴角上翘的嘴缝)、上颌几颗圆钝大牙加一颗金牙、下颌两颗獠牙;
# 吻尖两个鼻孔包、头顶两个眼包(眼睛长在包上)、后脑一排圆疙瘩;没有耳朵,黑色平檐低冠帽向后推露出眼包;
# 炭灰衬衫敞开 V 领露米黄腹鳞、红色强盗方巾、一条斜挎的宽皮带;深色裤、圆圆的光脚;
# 粗鳞尾从左侧翻过座面落地、沿地面往后弯,背上一排鳞脊,只有尾尖贴着地面扫。
# 动森式:两条子弹带简化成一条斜挎皮带(没有弹壳),牙只留几颗大的,去掉破裤边。


const LOOK := {
	"id": "crocodile",
	"gun_clearance": 0.306,   # 持枪净空(米,已含动森式大头的放大):按举枪流程实测最小值(含抖耳)再留 ≥4 mm
	"palette": {
		"fur": Color(0.24, 0.46, 0.22), "muzzle": Color(0.28, 0.48, 0.24), "dark": Color(0.1, 0.16, 0.08),
		"fur_back": Color(0.17, 0.34, 0.16), "jaw": Color(0.34, 0.50, 0.28), "coat": Color(0.22, 0.22, 0.24),
		"lapel": Color(0.17, 0.17, 0.19), "accent": Color(0.72, 0.16, 0.12), "belly": Color(0.76, 0.70, 0.45),
		"hat": Color(0.07, 0.07, 0.08), "band": Color(0.2, 0.2, 0.22), "pants": Color(0.16, 0.15, 0.14),
		"tooth": Color(0.80, 0.78, 0.7), "gold": Color(0.85, 0.65, 0.2), "leather": Color(0.3, 0.2, 0.12),
		"mouth": Color(0.12, 0.06, 0.05), "nose": Color(0.12, 0.2, 0.1), "pad": Color(0.2, 0.32, 0.18),
		"ridge": Color(0.16, 0.32, 0.15),
	},
	"head": {
		"skull": [
			[Vector3(0, 0.12, 0), Vector3(0.15, 0.12, 0.15), "fur"],
			[Vector3(0, 0.14, 0.05), Vector3(0.13, 0.1, 0.11), "fur_back"],                  # 后脑压暗
			[Vector3(0.085, 0.075, -0.06), Vector3(0.075, 0.065, 0.085), "fur", "mirror"],   # 腮帮(两颌的根)
			[Vector3(0.058, 0.205, -0.085), Vector3(0.044, 0.042, 0.044), "fur", "mirror"],  # 头顶眼包
			[Vector3(0, 0.035, -0.05), Vector3(0.1, 0.045, 0.09), "belly"],                  # 喉下浅色
		],
		"blend": 0.04,
		"material": 4.0,
		"scale_z": 0.72,   # 放大时前后方向少放一点(其他物种 PatronParts.HEAD_DEPTH):长吻不捅到桌心,伸脖子也不至于短太多
	},
	"eyes": {"pos": Vector3(0.058, 0.222, -0.112), "size": Vector3(0.032, 0.03, 0.016), "iris": Color(0.72, 0.62, 0.12),
		"pupil": 1, "lid_rest": 0.28, "lashes": false, "yaw": 18.0},
	"brows": {"pos": Vector3(0.058, 0.256, -0.105), "color": "dark", "width": 0.045, "thickness": 0.012},
	"ears": {"kind": "none"},
	"hat": {"kind": "flat", "pivot": Vector3(0, 0.25, 0.018), "rot": Vector3(12, 0, 2), "brim": 0.182, "band": "band"},
	"neck": {"base": Vector3(0, 0.55, -0.02), "radius": 0.08, "color": "fur"},
	"body": {"build": "stocky", "coat": "coat", "belly": "coat", "pants": "pants",
		"buttons": 0, "neckwear": "bandana", "neckwear_color": "accent", "collar": "coat"},
	"arms": {"sleeve": "coat", "cuff": "coat"},
	"paws": {"color": "fur", "pads": "pad", "fingers": 3, "length": 0.03, "claws": "nose"},
	"legs": {"pants": "pants", "foot": "claws", "foot_color": "fur"},
	# 粗尾:从左后胯出来,高过座面翻到椅子左外侧,落地后沿地面往后弯;只有贴地的尾尖摆(绕尾根竖轴转,贴着地面扫)
	"tail": {"path": [Vector3(-0.02, 0.52, 0.2), Vector3(-0.14, 0.565, 0.24), Vector3(-0.25, 0.565, 0.26), Vector3(-0.33, 0.48, 0.27),
		Vector3(-0.36, 0.3, 0.3), Vector3(-0.35, 0.13, 0.36), Vector3(-0.32, 0.058, 0.46), Vector3(-0.26, 0.042, 0.58),
		Vector3(-0.16, 0.03, 0.68), Vector3(-0.045, 0.022, 0.74)], "radius": 0.07, "tip_radius": 0.012,
		"color": "fur", "material": 4.0, "sway_range": Vector2(0.86, 1.0), "sway": 0.07},
	# 低头下限比别人浅:长吻低头会戳进桌面(穿模修复 2026-10-10 实测:−0.3 再加噪声与点头,轮到他前倾时下颌尖低于桌面)
	"anim": {"look_pitch_min": -0.25, "blink_speed": 1.0},
}

# 两颌(Head 局部):上颌宽而罩住下颌,吻尖 z ≥ −0.38
const UPPER := [
	[Vector3(0, 0.08, -0.12), Vector3(0.09, 0.044, 0.1)],
	[Vector3(0, 0.077, -0.235), Vector3(0.074, 0.038, 0.1)],
	[Vector3(0, 0.078, -0.322), Vector3(0.066, 0.034, 0.05)],
]
const NOSTRILS := [Vector3(0.021, 0.111, -0.335), Vector3(0.016, 0.012, 0.016)]
const LOWER := [
	[Vector3(0, 0.04, -0.12), Vector3(0.066, 0.03, 0.1)],
	[Vector3(0, 0.036, -0.235), Vector3(0.054, 0.027, 0.1)],
	[Vector3(0, 0.038, -0.31), Vector3(0.048, 0.025, 0.042)],
]
const SEAM_Y := 0.052
const TEETH := 3               # 每侧上牙数(动森式:几颗圆圆的大牙)
const GOLD_TOOTH := 1          # 右侧第几颗是金牙
# 斜挎皮带:绕躯干一整圈,从右肩斜到左胯
const BELT_FROM := Vector3(0, 0.29, 0.0)
const BELT_WIDTH := 0.05


static func extras(f: MeshForge, part: String, look: Dictionary, pal: Dictionary) -> void:
	match part:
		"head":
			_jaws(f, pal)
			_ridge(f, look, pal)
		"body":
			var shapes := PatronBuilder.body_shapes(look, pal)
			_open_shirt(f, pal, shapes)
			_belt(f, pal, shapes, 1.0)
		"legs":
			_tail_ridge(f, look, pal)


# —— 头:两颌、牙、嘴缝、后脑疙瘩 ——

static func _colored(list: Array, c: Color) -> Array:
	var out := []
	for s in list:
		out.append([s[0], s[1], c])
	return out


static func _jaws(f: MeshForge, pal: Dictionary) -> void:
	var upper := _colored(UPPER, pal["muzzle"])
	upper.append([NOSTRILS[0], NOSTRILS[1], pal["muzzle"], "mirror"])
	PatronBuilder.paint(f, pal, "muzzle", 0.6, PatronBuilder.SCALE)
	f.blob(Vector3(0, 0.08, -0.2), upper, 24, 12, 0.02)
	var lower := _colored(LOWER, pal["jaw"])
	lower.append([Vector3(0, 0.024, -0.2), Vector3(0.055, 0.016, 0.15), pal["belly"]])
	PatronBuilder.paint(f, pal, "jaw", 0.6, PatronBuilder.SCALE)
	f.blob(Vector3(0, 0.035, -0.2), lower, 22, 10, 0.016)
	# 鼻孔:鼻孔包上两个小黑点
	PatronBuilder.paint(f, pal, "mouth", 0.4, PatronBuilder.SMOOTH)
	for side: float in [-1.0, 1.0]:
		f.sphere(1.0, 8, PatronBuilder.xf(Vector3(0.021 * side, 0.122, -0.342), Vector3(-30, 0, 0), Vector3(0.006, 0.003, 0.005)))
	# 嘴缝:沿上颌下沿,嘴角往上翘;两侧在吻尖前面接起来
	var seam := PackedVector3Array()
	var zs := []
	for k in 9:
		zs.append(lerpf(-0.055, -0.33, k / 8.0))
	for side: float in [1.0, -1.0]:
		var order := zs.duplicate()
		if side < 0.0:
			order.reverse()
		for z: float in order:
			var lift := smoothstep(-0.11, -0.055, z) * 0.02
			seam.append(_outline(upper, z, side, SEAM_Y + lift, 0.0015))
		if side > 0.0:
			seam.append(Vector3(0, SEAM_Y, -0.356))
	PatronBuilder.paint(f, pal, "mouth", 0.5, PatronBuilder.SMOOTH)
	f.tube(seam, 0.0032, 4)
	# 上牙:沿上颌外沿往下的圆钝牙,右侧一颗金牙;下颌吻尖两颗往上的獠牙
	var tooth := PackedVector2Array([Vector2(0.01, 0.0), Vector2(0.0095, 0.008), Vector2(0.006, 0.016), Vector2(0.0, 0.02)])
	for side: float in [-1.0, 1.0]:
		for k in TEETH:
			var z := lerpf(-0.16, -0.3, float(k) / (TEETH - 1))
			var p := _outline(upper, z, side, SEAM_Y + 0.004, -0.001)
			var gold := side > 0.0 and k == GOLD_TOOTH
			if gold:
				PatronBuilder.paint(f, pal, "gold", 0.25, PatronBuilder.METAL, 1.0)
			else:
				PatronBuilder.paint(f, pal, "tooth", 0.45, PatronBuilder.SMOOTH)
			f.lathe(tooth, 6, PackedInt32Array(), PatronBuilder.xf(p, Vector3(180, 0, -12 * side)))
		PatronBuilder.paint(f, pal, "tooth", 0.45, PatronBuilder.SMOOTH)
		var fang := _outline(_colored(LOWER, Color.WHITE), -0.29, side, SEAM_Y - 0.008, 0.01)
		f.lathe(tooth, 6, PackedInt32Array(), PatronBuilder.xf(fang, Vector3(0, 0, 10 * side), Vector3(1.1, 1.3, 1.1)))


static func _outline(shapes: Array, z: float, side: float, y: float, lift: float) -> Vector3:
	# 颌部在高度 y、截面 z 处的侧边轮廓点(往外抬 lift)
	var from := Vector3(0, y, z)
	return MeshForge.blob_surface(from, Vector3(side, 0, 0), shapes, 0.02) + Vector3(side * lift, 0, 0)


static func _ridge(f: MeshForge, look: Dictionary, pal: Dictionary) -> void:
	# 后脑到颈背一排圆疙瘩(贴着头雕表面),后伸不超过 0.22
	var skull := PatronHeadBuilder.skull_shapes(look, pal)
	PatronBuilder.paint(f, pal, "ridge", 0.7, PatronBuilder.SCALE)
	for k in 5:
		var a := lerpf(0.55, 1.75, k / 4.0)
		var d := Vector3(0, cos(a), sin(a))
		var p := MeshForge.blob_surface(PatronHeadBuilder.HEAD_CENTER, d, skull, 0.04)
		var r := 0.017 - k * 0.0015
		f.sphere(r, 8, PatronBuilder.xf(p - d * r * 0.35, Vector3(rad_to_deg(a), 0, 0), Vector3(1.0, 0.8, 1.0)))


# —— 躯干:敞开的衬衫、腹鳞、斜挎皮带 ——

static func _v_half(y: float) -> float:
	# 敞开的 V 领在高度 y 处的半宽(身体局部):领口 0.09,往下收到 y 0.22 成尖
	return lerpf(0.004, 0.092, smoothstep(0.22, 0.52, y))


static func _front(shapes: Array, x: float, y: float, lift: float) -> Vector3:
	var from := Vector3(0, y, 1.5)
	var d := (Vector3(x, y, -0.2) - from).normalized()
	var p := MeshForge.blob_surface(from, d, shapes, PatronBuilder.BLOB_K)
	if p.z > 0.0:
		# 射线从背后擦过躯干外面(一个椭球都没碰到)时 blob_surface 返回起点 (0, y, 1.5):
		# 翻领、腹鳞的边角会拉出一条 1.7 米长、穿过椅背的细条(穿模修复 2026-10-10 实测)。改从躯干里面往外找胸前表面
		from = Vector3(0, y, 0.0)
		d = (Vector3(x, y, -0.2) - from).normalized()
		p = MeshForge.blob_surface(from, d, shapes, PatronBuilder.BLOB_K)
	return p + d * lift


static func _open_shirt(f: MeshForge, pal: Dictionary, shapes: Array) -> void:
	# 腹鳞片:V 形区域贴着胸口(鳞纹由着色器的鳞片格子画),两侧压上炭灰翻领
	var ys := [0.22, 0.27, 0.32, 0.37, 0.42, 0.465, 0.505, 0.535]
	var xs := [-1.0, -0.7, -0.35, 0.0, 0.35, 0.7, 1.0]
	var rows := []
	var colors := []
	var belly: Color = pal["belly"]
	for y: float in ys:
		var row := PackedVector3Array()
		var crow := PackedColorArray()
		for x: float in xs:
			row.append(_front(shapes, x * (_v_half(y) + 0.012), y, 0.005 * (1.0 - absf(x) * 0.6)))
			var c := belly.darkened(0.15 * absf(x))
			crow.append(Color(c.r, c.g, c.b, 1.0))
		rows.append(row)
		colors.append(crow)
	PatronBuilder.paint(f, pal, "belly", 0.6, PatronBuilder.SCALE)
	_grid(f, rows, colors, Vector3(0, 0.38, 0.0))
	# 翻领:沿 V 两边的扁条,领口处翻得更宽
	PatronBuilder.paint(f, pal, "lapel", 0.8, PatronBuilder.CLOTH)
	for side: float in [-1.0, 1.0]:
		var path := PackedVector3Array()
		var radii := PackedVector2Array()
		for k in 7:
			var y := lerpf(0.2, 0.535, k / 6.0)
			path.append(_front(shapes, side * (_v_half(y) + 0.008 + 0.02 * smoothstep(0.35, 0.535, y)), y, 0.01))
			radii.append(Vector2(0.006, lerpf(0.01, 0.026, smoothstep(0.25, 0.535, y))))
		f.loft(path, radii, 6, Vector2i(1, 1), Transform3D.IDENTITY, PackedColorArray(), Vector2(-1, -1), Vector3(0, 0, -1))


static func _belt_point(shapes: Array, axis: Vector3, t: float, lift: float) -> Vector3:
	var phi := t * TAU
	var d := axis * cos(phi) + Vector3(0, 0, -1) * sin(phi)
	return MeshForge.blob_surface(BELT_FROM, d, shapes, PatronBuilder.BLOB_K) + d * lift


static func _belt(f: MeshForge, pal: Dictionary, shapes: Array, side: float) -> void:
	# 从一侧肩头斜过胸口到另一侧胯,再从背后绕回来的一条宽皮带,胸前一个大铜扣
	var axis := Vector3(0.55 * side, 1.0, 0.0).normalized()
	var path := PackedVector3Array()
	var radii := PackedVector2Array()
	var rows := 32
	for i in rows + 1:
		path.append(_belt_point(shapes, axis, float(i) / rows, 0.012))
		radii.append(Vector2(0.007, BELT_WIDTH * 0.5))
	PatronBuilder.paint(f, pal, "leather", 0.7, PatronBuilder.LEATHER)
	var up := (path[0] - BELT_FROM).normalized()
	f.loft(path, radii, 4, Vector2i(0, 0), Transform3D.IDENTITY, PackedColorArray(), Vector2(-1, -1), up)
	var p := _belt_point(shapes, axis, 0.22, 0.02)
	PatronBuilder.paint(f, pal, "gold", 0.45, PatronBuilder.METAL, 1.0)
	f.sphere(1.0, 12, Transform3D(Basis.looking_at(BELT_FROM - p, Vector3.UP).scaled(Vector3(0.026, 0.022, 0.008)), p))


# —— 尾巴鳞脊 ——

static func _tail_ridge(f: MeshForge, look: Dictionary, pal: Dictionary) -> void:
	# 尾背一排三角鳞脊:沿尾巴放样路径取点,贴在上表面;尾尖会摆的那段不放
	var t: Dictionary = look["tail"]
	var path: Array = t["path"]
	var base: float = t["radius"]
	var tip: float = t["tip_radius"]
	var n := path.size()
	PatronBuilder.paint(f, pal, "ridge", 0.7, PatronBuilder.SCALE)
	for k in 13:
		var s := lerpf(0.14, 0.8, k / 12.0)
		var fi := s * (n - 1)
		var i := mini(int(fi), n - 2)
		var p: Vector3 = (path[i] as Vector3).lerp(path[i + 1], fi - i)
		var tangent: Vector3 = ((path[i + 1] as Vector3) - path[i]).normalized()
		# 鳞脊朝上;竖直下垂的一段朝椅子外侧(-X)
		var v := absf(tangent.y)
		var ref := Vector3(-v, 1.0 - v + 0.05, 0.0)
		var up := (ref - tangent * ref.dot(tangent)).normalized()
		var r := lerpf(base, tip, s)
		var h := lerpf(0.032, 0.014, s)
		var basis := Basis(up.cross(tangent).normalized(), up, tangent)
		f.prism(Vector3(r * 0.5, h, lerpf(0.04, 0.022, s)), Transform3D(basis, p + up * (r + h * 0.3)))


# —— 网格工具 ——

static func _grid(f: MeshForge, rows: Array, colors: Array, inside: Vector3) -> void:
	# 行列点阵 → 三角网:法线按相邻点差分、朝离开 inside 的一侧;逐四边形按法线定绕序(Godot 顺时针为正面)
	var nr := rows.size()
	var nc: int = rows[0].size()
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	var indices := PackedInt32Array()
	for r in nr:
		for c in nc:
			var p: Vector3 = rows[r][c]
			var tr: Vector3 = rows[mini(r + 1, nr - 1)][c] - rows[maxi(r - 1, 0)][c]
			var tc: Vector3 = rows[r][mini(c + 1, nc - 1)] - rows[r][maxi(c - 1, 0)]
			var n := tr.cross(tc)
			if n.length_squared() < 1e-12:
				n = p - inside
			n = n.normalized()
			if n.dot(p - inside) < 0.0:
				n = -n
			points.append(p)
			normals.append(n)
			cols.append(colors[r][c])
	for r in nr - 1:
		for c in nc - 1:
			var a := r * nc + c
			var b := a + 1
			var d := a + nc
			var e := d + 1
			var g := (points[b] - points[a]).cross(points[d] - points[a]) + (points[e] - points[b]).cross(points[d] - points[b])
			if g.dot(normals[a] + normals[e]) > 0.0:
				indices.append_array([a, d, b, b, d, e])
			else:
				indices.append_array([a, b, d, b, e, d])
	f._append(points, normals, indices, Transform3D.IDENTITY, cols)
