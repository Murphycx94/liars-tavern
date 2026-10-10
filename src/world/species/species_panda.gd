extends RefCounted
# 熊猫「竹林侠客」(2026-10-10 追加,下标 8):白毛圆脸、短圆吻、黑鼻头;两块往外下方耷拉的泪滴形黑眼斑(贴在脸上的贴片,边缘干脆);
# 黑色圆耳朵;两耳之间一顶竹编小斗笠(顶上红珠);嘴角斜叼一根带两片叶子的嫩竹枝(像牛仔叼草,离开枪口那一侧、舌头的另一侧);
# 红色短夹棉坎肩(对襟、金色滚边、立领、三对金盘扣),露出黑肩膀、黑胳膊和下面圆滚滚的白肚子;黑腿、黑脚掌;白色短圆尾。

const Kit := preload("res://src/world/species/species_fox.gd")   # 衣片工具


const LOOK := {
	"id": "panda",
	"gun_clearance": 0.336,   # 持枪净空(米,已含动森式大头的放大):按举枪流程实测最小值 0.325(含抖耳)再留 ≥6 mm
	"palette": {
		"fur": Color(0.80, 0.79, 0.76), "muzzle": Color(0.82, 0.81, 0.78), "dark": Color(0.13, 0.12, 0.13),
		"fur_back": Color(0.70, 0.69, 0.66), "patch": Color(0.12, 0.11, 0.12), "ear_in": Color(0.2, 0.18, 0.19),
		"coat": Color(0.70, 0.14, 0.12), "accent": Color(0.84, 0.64, 0.24), "vest": Color(0.68, 0.13, 0.11),
		"vest_back": Color(0.56, 0.1, 0.09), "gold": Color(0.86, 0.66, 0.26), "pants": Color(0.13, 0.12, 0.13),
		"hat": Color(0.80, 0.66, 0.40), "hat_rim": Color(0.62, 0.48, 0.26), "bead": Color(0.74, 0.14, 0.12),
		"bamboo": Color(0.46, 0.66, 0.28), "bamboo_node": Color(0.32, 0.5, 0.18), "leaf": Color(0.36, 0.62, 0.26),
		"leaf_dark": Color(0.26, 0.48, 0.18), "nose": Color(0.08, 0.07, 0.08), "pad": Color(0.3, 0.26, 0.26),
		"blush": Color(0.92, 0.58, 0.58), "paw": Color(0.13, 0.12, 0.13),
	},
	"head": {
		"skull": [
			[Vector3(0, 0.12, 0), Vector3(0.168, 0.15, 0.16), "fur"],                   # 主颅骨,中心就是头心
			[Vector3(0, 0.14, 0.05), Vector3(0.14, 0.125, 0.115), "fur_back"],           # 后脑压暗一点(越肩镜头里不是一颗发光的白球)
			[Vector3(0.095, 0.06, -0.05), Vector3(0.08, 0.066, 0.075), "fur", "mirror"],  # 胖腮
			[Vector3(0, 0.068, -0.125), Vector3(0.072, 0.054, 0.066), "muzzle"],         # 短圆吻
			[Vector3(0.108, 0.07, -0.108), Vector3(0.026, 0.017, 0.016), "blush", "mirror"],   # 腮红:眼斑外下方,露出一小片
		],
		"blend": 0.04,
		"nose": {"pos": Vector3(0, 0.098, -0.186), "radii": Vector3(0.027, 0.018, 0.018), "color": "nose"},
		"mouth": {"kind": "smile", "pos": Vector3(0, 0.054, -0.19), "width": 0.054},
	},
	"eyes": {"pos": Vector3(0.066, 0.16, -0.132), "size": Vector3(0.036, 0.04, 0.018), "iris": Color(0.3, 0.2, 0.12),
		"pupil": 0, "lid_rest": 0.12, "lashes": false, "lid": "patch", "lift": 0.005},
	"brows": {"pos": Vector3(0.066, 0.222, -0.142), "color": "dark", "width": 0.042, "thickness": 0.0095},
	"ears": {"kind": "round", "pivot": Vector3(0.132, 0.218, 0.012), "rot": Vector3(0, 0, -24),
		"size": Vector3(0.056, 0.054, 0.03), "color": "dark", "inner": "ear_in"},
	# 竹编小斗笠:扣在两只黑耳朵中间(帽子在 extras 里按车削画,PatronHatBuilder 不认识 "douli" 就什么都不画)
	"hat": {"kind": "douli", "pivot": Vector3(0, 0.262, 0.012), "rot": Vector3(-8, 0, -6)},
	"neck": {"base": Vector3(0, 0.55, -0.02), "radius": 0.076, "color": "fur"},
	# 躯干:白肚子;肩头一圈黑(坎肩袖窿露出来);坎肩、立领、盘扣在 extras 里按衣片画
	"body": {"build": "round", "coat": "fur", "belly": "fur", "pants": "pants", "buttons": 0, "neckwear": "none",
		"collar": "dark", "shapes": [[Vector3(0.15, 0.45, 0.0), Vector3(0.1, 0.085, 0.1), "dark", "mirror"]]},
	"arms": {"sleeve": "dark", "cuff": "dark", "material": 0.0},
	"paws": {"color": "paw", "pads": "pad", "fingers": 4, "length": 0.026},
	"legs": {"pants": "pants", "foot": "bare", "foot_color": "paw", "material": 0.0},
	"tail": {"path": [Vector3(0, 0.5, 0.25), Vector3(0, 0.49, 0.295)], "radius": 0.042, "tip_radius": 0.034,
		"color": "fur", "sway_range": Vector2(0.0, 1.0), "sway": 0.05},
	"anim": {"look_pitch_min": -0.45, "blink_speed": 1.0, "fidget": "chew"},
}

# 泪滴眼斑(放大前的 Head 局部):以眼心为中心、在眼睛朝向的切平面里画极坐标轮廓,往外下方 DROP_DEG 方向拉长成泪滴
const PATCH_RADII := Vector2(0.05, 0.056)
const PATCH_SHIFT := Vector2(0.006, -0.008)   # 眼斑中心相对眼心(往外、往下)
const PATCH_DROP := 0.55       # 泪滴尖端拉长的比例
const PATCH_DROP_DEG := -62.0  # 尖端方向(0 = 正外侧,负 = 往下)
const PATCH_OFF := 0.0014      # 贴片离颅骨(放大前;眼睛 LOOK eyes.lift 抬高到贴片之上)
# 嫩竹枝:从左嘴角(-x,离开右手举枪那一侧,也不挡右嘴角吐舌头)斜着伸向左腮外上方
const BAMBOO_FROM := Vector3(-0.012, 0.053, -0.19)
const BAMBOO_TO := Vector3(-0.125, 0.09, -0.162)
const BAMBOO_RADIUS := 0.0062
const BAMBOO_NODES := [0.36, 0.7]   # 竹节位置(沿竹枝的比例)


static func extras(f: MeshForge, part: String, look: Dictionary, pal: Dictionary) -> void:
	match part:
		"head":
			_patches(f, look, pal)
			_bamboo(f, pal)
		"hat":
			_douli(f, pal)
		"body":
			_vest(f, look, pal)


# —— 头:眼斑、竹枝 ——

static func head_shapes(look: Dictionary, pal: Dictionary) -> Array:
	return PatronHeadBuilder.skull_shapes(look, pal)


static func _patches(f: MeshForge, look: Dictionary, pal: Dictionary) -> void:
	var hc := PatronHeadBuilder.HEAD_CENTER
	var shapes := head_shapes(look, pal)
	var k: float = look["head"].get("blend", 0.04)
	var eye: Vector3 = look["eyes"]["pos"]
	var yaw := deg_to_rad(look["eyes"].get("yaw", 12.0))
	PatronBuilder.paint(f, pal, "patch", 0.8, PatronBuilder.FUR)
	for side: float in [-1.0, 1.0]:
		var basis := Basis(Vector3.UP, -yaw * side)
		var out := basis * Vector3(side, 0, 0)
		var center := Vector3(eye.x * side, eye.y, eye.z) + out * PATCH_SHIFT.x + Vector3.UP * PATCH_SHIFT.y
		var drop := deg_to_rad(PATCH_DROP_DEG)
		Kit.panel(f, hc, shapes, k, func(u: float, v: float) -> Vector3:
			var a := u * TAU
			var e := Vector2(cos(a) * PATCH_RADII.x, sin(a) * PATCH_RADII.y)
			var stretch := 1.0 + PATCH_DROP * pow(maxf(cos(a - drop), 0.0), 2.5)
			var q := center + (out * e.x + Vector3.UP * e.y) * stretch * v
			return q - hc, 28, 7, PATCH_OFF, Callable(), false, true)


static func _bamboo(f: MeshForge, pal: Dictionary) -> void:
	# 竹枝:两节嫩竹(节处一圈略鼓的深绿),末端两片细长竹叶往上、往外张开
	var from := BAMBOO_FROM
	var to := BAMBOO_TO
	var stalk := PackedVector3Array()
	var radii := PackedVector2Array()
	var colors := PackedColorArray()
	var green := PatronBuilder.color(pal, "bamboo")
	var node := PatronBuilder.color(pal, "bamboo_node")
	var stops := [0.0, 0.08]
	for n: float in BAMBOO_NODES:
		stops.append_array([n - 0.035, n - 0.012, n, n + 0.012, n + 0.035])
	stops.append_array([0.94, 1.0])
	for t: float in stops:
		stalk.append(from.lerp(to, t))
		var bump := 0.0
		var col := green
		for n: float in BAMBOO_NODES:
			var d := absf(t - n)
			bump = maxf(bump, 0.0016 * (1.0 - smoothstep(0.0, 0.03, d)))
			if d < 0.02:
				col = node
		var r := BAMBOO_RADIUS * lerpf(1.0, 0.82, t) + bump
		radii.append(Vector2(r, r))
		colors.append(Color(col.r, col.g, col.b, 1.0))
	PatronBuilder.paint(f, pal, "bamboo", 0.55, PatronBuilder.SMOOTH)
	f.loft(stalk, radii, 8, Vector2i(1, 1), Transform3D.IDENTITY, colors)
	# 竹叶:细长的柳叶形扁片,从末节长出,一片往上翘、一片往外垂一点
	var tip := to
	for leaf: Array in [[Vector3(-0.35, 0.95, -0.15), 0.066, "leaf"], [Vector3(-0.9, 0.25, 0.2), 0.058, "leaf_dark"],
			[Vector3(-0.25, 0.6, -0.75), 0.04, "leaf"]]:
		var dir: Vector3 = (leaf[0] as Vector3).normalized()
		var length: float = leaf[1]
		var path := PackedVector3Array()
		var widths := PackedVector2Array()
		for i in 6:
			var s := i / 5.0
			path.append(tip + dir * length * s + Vector3(0, -0.006 * s * s, 0))
			var w := 0.0145 * sin(PI * minf(s * 1.15 + 0.05, 1.0)) + 0.0012
			widths.append(Vector2(0.0014, w))
		PatronBuilder.paint(f, pal, leaf[2], 0.6, PatronBuilder.SMOOTH)
		f.loft(path, widths, 6, Vector2i(1, 1), Transform3D.IDENTITY, PackedColorArray(), Vector2(-1, -1), Vector3(0, 0, -1))


# —— 帽子:竹编小斗笠 ——

static func _douli(f: MeshForge, pal: Dictionary) -> void:
	# 浅圆锥:帽面略往外鼓、帽檐一圈深色竹篾包边、帽顶一颗红珠。草编材质类出编织纹
	var r := 0.108
	PatronBuilder.paint(f, pal, "hat", 0.9, PatronBuilder.STRAW)
	var profile := PackedVector2Array()
	profile.append(Vector2(0.0, 0.03))
	profile.append(Vector2(r * 0.96, -0.002))
	profile.append(Vector2(r, 0.002))
	for i in 7:
		var s := i / 6.0
		var rr := lerpf(r, 0.012, s)
		profile.append(Vector2(rr, 0.002 + 0.082 * (1.0 - pow(1.0 - s, 1.25)) + 0.008 * sin(PI * s)))
	profile.append(Vector2(0.0, 0.086))
	f.lathe(profile, 28, PackedInt32Array([2]))
	PatronBuilder.paint(f, pal, "hat_rim", 0.8, PatronBuilder.STRAW)
	f.torus(r - 0.004, r + 0.004, 24, PatronBuilder.xf(Vector3(0, 0.001, 0)))
	PatronBuilder.paint(f, pal, "bead", 0.45, PatronBuilder.SMOOTH)
	f.sphere(0.012, 12, PatronBuilder.xf(Vector3(0, 0.092, 0), Vector3.ZERO, Vector3(1.0, PatronParts.HEAD_SCALE / PatronParts.HAT_SCALE_Y, 1.0)))


# —— 躯干:红色夹棉坎肩 ——

static func _vest(f: MeshForge, look: Dictionary, pal: Dictionary) -> void:
	var c := PatronBuilder.BODY_CENTER
	var k := PatronBuilder.BLOB_K
	var shapes := PatronBuilder.body_shapes(look, pal)
	# 前片左右两片对襟:上面在胸口正中合拢,下摆圆角、往两边略分开,露出圆肚子;外侧开袖窿露出黑肩膀
	var fronts := []
	for side: float in [-1.0, 1.0]:
		PatronBuilder.paint(f, pal, "vest", 0.85, PatronBuilder.CLOTH)
		fronts.append(Kit.panel(f, c, shapes, k, func(u: float, v: float) -> Vector3:
			var y := lerpf(0.53, lerpf(0.215, 0.18, u) + 0.03 * pow(1.0 - u, 3.0), v)
			var a_in := lerpf(0.5, 9.0, smoothstep(0.3, 0.2, y))
			var a_out := lerpf(54.0, 100.0, smoothstep(0.44, 0.33, y))
			return Kit.aim(c, lerpf(a_in, a_out, u) * side, y), 7, 10, 0.013 if side > 0.0 else 0.0125))
	# 后片
	PatronBuilder.paint(f, pal, "vest_back", 0.85, PatronBuilder.CLOTH)
	Kit.panel(f, c, shapes, k, func(u: float, v: float) -> Vector3:
		var a := lerpf(100.0, 260.0, u)
		var top := lerpf(0.535, 0.34, smoothstep(45.0, 78.0, absf(a - 180.0)))
		return Kit.aim(c, a, lerpf(top, 0.18, v)), 8, 6, 0.011)
	# 金色滚边:前襟一道 + 下摆一道
	PatronBuilder.paint(f, pal, "gold", 0.45, PatronBuilder.METAL, 0.6)
	for front: Array in fronts:
		var rows: Array = front[0]
		var normals: Array = front[1]
		var edge := PackedVector3Array()
		for j in rows.size():
			edge.append(rows[j][0] + normals[j][0] * 0.002)
		var last: PackedVector3Array = rows[rows.size() - 1]
		var last_n: PackedVector3Array = normals[normals.size() - 1]
		for i in range(1, last.size()):
			edge.append(last[i] + last_n[i] * 0.002)
		f.tube(edge, 0.0058, 6)
	# 立领:红色矮领圈,上沿金边
	PatronBuilder.paint(f, pal, "vest", 0.8, PatronBuilder.CLOTH)
	f.lathe(PackedVector2Array([Vector2(0.094, 0.528), Vector2(0.092, 0.57), Vector2(0.086, 0.584)]), 22,
		PackedInt32Array(), PatronBuilder.xf(Vector3(0, 0, -0.02)))
	PatronBuilder.paint(f, pal, "gold", 0.45, PatronBuilder.METAL, 0.6)
	var collar := PackedVector3Array()
	for i in 23:
		var a := TAU * i / 22.0
		collar.append(Vector3(sin(a) * 0.088, 0.583, cos(a) * 0.088 - 0.02))
	f.tube(collar, 0.0055, 6)
	# 三对金盘扣:对襟中线上一颗圆疙瘩,左右各一道横着的盘绳
	for y: float in [0.47, 0.39, 0.31]:
		var p := Kit.surface_point(c, shapes, k, Kit.aim(c, 0.0, y), 0.016)
		f.sphere(0.0105, 10, PatronBuilder.xf(p + Vector3(0, 0, -0.003)))
		for side: float in [-1.0, 1.0]:
			var q := Kit.surface_point(c, shapes, k, Kit.aim(c, 9.0 * side, y), 0.015)
			f.loft(PackedVector3Array([p, p.lerp(q, 0.5) + Vector3(0, 0.003, -0.002), q]),
				PackedVector2Array([Vector2(0.0055, 0.0055), Vector2(0.0058, 0.0058), Vector2(0.005, 0.005)]), 6)
