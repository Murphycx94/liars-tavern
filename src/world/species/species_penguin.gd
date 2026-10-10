extends RefCounted
# 企鹅「南极来客」(2026-10-10 追加,下标 9):藏青圆头、心形白脸(贴片,边缘干脆)、短短的橙色尖喙(上下两片,嘴缝一道笑线)、
# 白脸上两颗圆圆的粉腮红;没有耳朵,戴一顶红色毛线球帽(翻边、奶油色条纹、奶油色大绒球);
# 藏青圆滚滚的身子配白肚皮;脖子上绕一条红色粗毛线围巾(奶油条纹),一头垂在胸前带流苏、一头甩到背后;
# 藏青鳍状短胳膊、圆手团;橙色扁蹼脚;短短的小尾巴。动森式:纯色、圆润,一身「冬天出远门」的打扮。

const Kit := preload("res://src/world/species/species_fox.gd")   # 衣片工具


const LOOK := {
	"id": "penguin",
	"gun_clearance": 0.326,   # 持枪净空(米,已含动森式大头的放大):按举枪流程实测最小值 0.315 再留 ≥6 mm(没有耳朵)
	"palette": {
		"fur": Color(0.12, 0.14, 0.21), "muzzle": Color(0.80, 0.80, 0.78), "dark": Color(0.07, 0.08, 0.12),
		"fur_back": Color(0.1, 0.12, 0.18), "face": Color(0.80, 0.80, 0.77), "belly": Color(0.80, 0.79, 0.75),
		"coat": Color(0.12, 0.14, 0.21), "accent": Color(0.72, 0.16, 0.14), "beak": Color(0.94, 0.6, 0.16),
		"beak_dark": Color(0.62, 0.32, 0.08), "scarf": Color(0.72, 0.16, 0.14), "stripe": Color(0.82, 0.77, 0.64),
		"beanie": Color(0.70, 0.15, 0.13), "beanie_cuff": Color(0.58, 0.12, 0.11), "bobble": Color(0.84, 0.8, 0.7),
		"blush": Color(0.96, 0.56, 0.58), "pad": Color(0.2, 0.22, 0.3), "paw": Color(0.12, 0.14, 0.21),
		"pants": Color(0.12, 0.14, 0.21),
	},
	"head": {
		"skull": [
			[Vector3(0, 0.12, 0), Vector3(0.164, 0.152, 0.158), "fur"],                 # 主颅骨,中心就是头心
			[Vector3(0, 0.15, 0.05), Vector3(0.14, 0.125, 0.115), "fur_back"],           # 后脑压暗
			[Vector3(0.085, 0.07, -0.07), Vector3(0.085, 0.07, 0.08), "fur", "mirror"],  # 胖腮(白脸贴片盖在上面)
		],
		"blend": 0.045,
		"material": 9.0,   # 光滑皮毛:羽毛短而顺,不出毛簇颗粒
		# 嘴缝:上下喙之间一道往上弯的笑线(舌头从右嘴角吐出来)
		"mouth": {"kind": "smile", "pos": Vector3(0, 0.08, -0.176), "width": 0.07, "color": "beak_dark", "thickness": 0.0028},
	},
	"eyes": {"pos": Vector3(0.062, 0.166, -0.135), "size": Vector3(0.036, 0.042, 0.018), "iris": Color(0.2, 0.15, 0.13),
		"pupil": 0, "lid_rest": 0.1, "lashes": false, "lid": "face", "lift": 0.0055},
	"brows": {"pos": Vector3(0.064, 0.214, -0.142), "color": "dark", "width": 0.048, "thickness": 0.01},
	"ears": {"kind": "none"},
	# 毛线球帽在 extras 里按车削画(PatronHatBuilder 不认识 "beanie" 就什么都不画)
	"hat": {"kind": "beanie", "pivot": Vector3(0, 0.247, 0.008), "rot": Vector3(-10, 0, -6)},
	"neck": {"base": Vector3(0, 0.55, -0.02), "radius": 0.072, "color": "fur"},
	"body": {"build": "round", "coat": "fur", "belly": "fur", "pants": "pants", "collar": "fur", "material": 9.0,
		"buttons": 0, "neckwear": "none"},
	"arms": {"sleeve": "fur", "cuff": "fur", "material": 9.0},
	"paws": {"color": "paw", "pads": "pad", "fingers": 4, "length": 0.026},
	"legs": {"pants": "pants", "foot": "webbed", "foot_color": "beak", "material": 9.0},
	"tail": {"path": [Vector3(0, 0.5, 0.245), Vector3(0, 0.488, 0.3)], "radius": 0.042, "tip_radius": 0.014,
		"color": "fur", "material": 9.0, "sway_range": Vector2(0.0, 1.0), "sway": 0.05},
	"anim": {"look_pitch_min": -0.45, "blink_speed": 1.0, "fidget": "waddle"},
}

# 心形白脸(放大前的 Head 局部,正面平行投影):两瓣圆绕眼睛、下面一个大椭圆盖住两腮和下巴
const FACE_LOBE := Vector3(0.064, 0.17, 0.066)    # 眼瓣圆心 (x, y) 与半径
const FACE_LOW := [Vector2(0, 0.082), Vector2(0.126, 0.088)]   # 下脸椭圆中心与半径
const FACE_CENTER := Vector2(0, 0.115)
const FACE_OFF := 0.0016
const BLUSH_AT := Vector2(0.108, 0.098)
# 喙:上喙从脸里埋进去开始,往前收尖、略往下勾;下喙短一截
const BEAK_UPPER := [Vector3(0, 0.1, -0.13), Vector3(0, 0.096, -0.172), Vector3(0, 0.088, -0.198), Vector3(0, 0.081, -0.212)]
const BEAK_UPPER_R := [Vector2(0.024, 0.03), Vector2(0.019, 0.023), Vector2(0.011, 0.014), Vector2(0.004, 0.004)]
const BEAK_LOWER := [Vector3(0, 0.072, -0.13), Vector3(0, 0.074, -0.17), Vector3(0, 0.077, -0.19)]
const BEAK_LOWER_R := [Vector2(0.014, 0.026), Vector2(0.011, 0.02), Vector2(0.004, 0.006)]


static func extras(f: MeshForge, part: String, look: Dictionary, pal: Dictionary) -> void:
	match part:
		"head":
			_face(f, look, pal)
			_beak(f, pal)
		"hat":
			_beanie(f, pal)
		"body":
			_belly(f, look, pal)
			_scarf(f, look, pal)


# —— 头:白脸、腮红、喙 ——

static func _in_face(p: Vector2) -> bool:
	for side: float in [-1.0, 1.0]:
		if p.distance_to(Vector2(FACE_LOBE.x * side, FACE_LOBE.y)) <= FACE_LOBE.z:
			return true
	var low: Vector2 = FACE_LOW[0]
	var rad: Vector2 = FACE_LOW[1]
	return ((p - low) / rad).length_squared() <= 1.0


static func _face_radius(a: float) -> float:
	# 心形轮廓在 a 方向离 FACE_CENTER 多远(从里往外第一次走出去的位置)
	var d := Vector2(cos(a), sin(a))
	var r := 0.0
	while r < 0.3 and _in_face(FACE_CENTER + d * (r + 0.002)):
		r += 0.002
	return r


static func _front_point(shapes: Array, k: float, p: Vector2, lift: float) -> Vector3:
	# 正面平行投影:从脑后远处往前打射线,取脸上的出射点再沿射线往外抬 lift
	var from := Vector3(p.x, p.y, 2.0)
	var d := Vector3(0, 0, -1)
	return MeshForge.blob_surface(from, d, shapes, k) + d * lift


static func _face(f: MeshForge, look: Dictionary, pal: Dictionary) -> void:
	var shapes := PatronHeadBuilder.skull_shapes(look, pal)
	var k: float = look["head"].get("blend", 0.045)
	var radii := PackedFloat32Array()
	var steps := 48
	for i in steps + 1:
		radii.append(_face_radius(TAU * i / steps))
	PatronBuilder.paint(f, pal, "face", 0.75, PatronBuilder.SMOOTH)
	Kit.panel(f, Vector3(0, FACE_CENTER.y, 2.0), shapes, k, func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var r: float = radii[mini(int(round(u * steps)), steps)]
		var p := FACE_CENTER + Vector2(cos(a), sin(a)) * r * v
		return Vector3(p.x, p.y, -0.2) - Vector3(0, FACE_CENTER.y, 2.0), steps, 10, FACE_OFF, Callable(), false, true)
	# 腮红:白脸上两片扁圆的粉色贴片
	PatronBuilder.paint(f, pal, "blush", 0.7, PatronBuilder.SMOOTH)
	for side: float in [-1.0, 1.0]:
		var at := Vector2(BLUSH_AT.x * side, BLUSH_AT.y)
		var p := _front_point(shapes, k, at, 0.0)
		var px := _front_point(shapes, k, at + Vector2(0.004, 0), 0.0)
		var py := _front_point(shapes, k, at + Vector2(0, 0.004), 0.0)
		var n := (px - p).cross(py - p).normalized()
		if n.z > 0.0:
			n = -n
		var right := Vector3.UP.cross(n).normalized()
		var up := n.cross(right).normalized()
		var basis := Basis(right * 0.022, up * 0.015, n * 0.0028)
		f.sphere(1.0, 12, Transform3D(basis, p + n * (FACE_OFF + 0.0012)))


static func _beak(f: MeshForge, pal: Dictionary) -> void:
	PatronBuilder.paint(f, pal, "beak", 0.45, PatronBuilder.SMOOTH)
	f.loft(PackedVector3Array(BEAK_UPPER), PackedVector2Array(BEAK_UPPER_R), 12, Vector2i(0, 1))
	PatronBuilder.paint(f, pal, "beak_dark", 0.5, PatronBuilder.SMOOTH)
	f.loft(PackedVector3Array(BEAK_LOWER), PackedVector2Array(BEAK_LOWER_R), 10, Vector2i(0, 1))
	# 上喙根部一对小鼻孔
	PatronBuilder.paint(f, pal, "beak_dark", 0.6, PatronBuilder.SMOOTH)
	for side: float in [-1.0, 1.0]:
		f.sphere(1.0, 8, PatronBuilder.xf(Vector3(0.009 * side, 0.112, -0.163), Vector3(-20, 0, 0), Vector3(0.0035, 0.002, 0.004)))


# —— 帽子:毛线球帽 ——

static func _beanie(f: MeshForge, pal: Dictionary) -> void:
	# 翻边一圈(深红)→ 帽身(红,中间一道奶油色条纹)→ 帽顶一个奶油色大绒球。针织材质类出毛线纹。
	# 帽子竖向只放 HAT_SCALE_Y(横向跟头放大),绒球按比例先拉高,放大后还是圆的
	PatronBuilder.paint(f, pal, "beanie_cuff", 0.95, PatronBuilder.KNIT)
	f.lathe(PackedVector2Array([Vector2(0.108, -0.018), Vector2(0.12, -0.014), Vector2(0.126, 0.0), Vector2(0.126, 0.018),
		Vector2(0.12, 0.03), Vector2(0.108, 0.034)]), 32)
	var bands := [["beanie", 0.03, 0.062], ["stripe", 0.062, 0.08], ["beanie", 0.08, 0.14]]
	for b: Array in bands:
		PatronBuilder.paint(f, pal, b[0], 0.95, PatronBuilder.KNIT)
		var profile := PackedVector2Array()
		for i in 5:
			var y := lerpf(b[1], b[2], i / 4.0)
			profile.append(Vector2(_beanie_radius(y), y))
		f.lathe(profile, 32)
	PatronBuilder.paint(f, pal, "bobble", 0.95, PatronBuilder.KNIT)
	var squash := PatronParts.HEAD_SCALE / PatronParts.HAT_SCALE_Y
	var fluff := f.mark()
	f.sphere(0.034, 16, PatronBuilder.xf(Vector3(0, 0.14 + 0.03 * squash * 0.55, 0), Vector3.ZERO, Vector3(1.0, squash * 0.85, 1.0)))
	# 绒球表面鼓几个小包,像一团毛线
	var center := Vector3(0, 0.14 + 0.03 * squash * 0.55, 0)
	f.displace(fluff, func(p: Vector3) -> Vector3:
		var d := p - center
		var bump := 0.003 * sin(d.x * 260.0) * sin(d.y * 150.0 + 1.0) * sin(d.z * 260.0 + 2.0)
		return p + d.normalized() * bump)


static func _beanie_radius(y: float) -> float:
	# 帽身轮廓:翻边上沿 0.11,往上圆圆地收到帽顶 0.14
	var s := clampf((y - 0.03) / 0.11, 0.0, 1.0)
	return 0.11 * sqrt(maxf(1.0 - pow(s, 2.2), 0.0)) if s < 1.0 else 0.0


# —— 躯干:白肚皮、围巾 ——

static func _belly(f: MeshForge, look: Dictionary, pal: Dictionary) -> void:
	# 白肚皮:正面一大片蛋形贴片,从领口(围巾盖住)到骨盆
	var c := PatronBuilder.BODY_CENTER
	var k := PatronBuilder.BLOB_K
	var shapes := PatronBuilder.body_shapes(look, pal)
	PatronBuilder.paint(f, pal, "belly", 0.75, PatronBuilder.SMOOTH)
	Kit.panel(f, c, shapes, k, func(u: float, v: float) -> Vector3:
		var y := lerpf(0.54, -0.02, v)
		var t := clampf((y - 0.22) / 0.34, -1.0, 1.0)
		var half := 50.0 * sqrt(maxf(1.0 - t * t * t * t, 0.0) if t < 0.0 else maxf(1.0 - t * t, 0.0)) * lerpf(1.0, 0.8, maxf(t, 0.0))
		return Kit.aim(c, lerpf(-half, half, u), y), 18, 24, 0.0045, Callable(), false)


static func _scarf(f: MeshForge, look: Dictionary, pal: Dictionary) -> void:
	var c := PatronBuilder.BODY_CENTER
	var k := PatronBuilder.BLOB_K
	var shapes := PatronBuilder.body_shapes(look, pal)
	var red := PatronBuilder.color(pal, "scarf")
	var cream := PatronBuilder.color(pal, "stripe")
	# 绕脖子一圈的粗毛线:上下两道红、中间一道奶油条纹
	var ring := [["scarf", [Vector2(0.098, 0.512), Vector2(0.114, 0.524), Vector2(0.12, 0.545)]],
		["stripe", [Vector2(0.12, 0.545), Vector2(0.121, 0.56)]],
		["scarf", [Vector2(0.121, 0.56), Vector2(0.116, 0.584), Vector2(0.104, 0.598), Vector2(0.09, 0.602)]]]
	for r: Array in ring:
		PatronBuilder.paint(f, pal, r[0], 0.95, PatronBuilder.KNIT)
		f.lathe(PackedVector2Array(r[1]), 24, PackedInt32Array(), PatronBuilder.xf(Vector3(0, 0, -0.02)))
	# 结:左前方一团
	var knot := Vector3(-0.055, 0.53, -0.112)
	PatronBuilder.paint(f, pal, "scarf", 0.95, PatronBuilder.KNIT)
	f.blob(knot, [[knot, Vector3(0.034, 0.028, 0.022), red], [knot + Vector3(0.01, -0.016, -0.004), Vector3(0.026, 0.022, 0.018), red]],
		14, 8, 0.01)
	# 垂在胸前的一头:贴着胸口往下,奶油条纹,末端一排流苏
	var path := PackedVector3Array([knot + Vector3(0.0, -0.01, 0.0)])
	for y: float in [0.48, 0.43, 0.38, 0.33]:
		path.append(Kit.surface_point(c, shapes, k, Kit.aim(c, -15.0 - (0.48 - y) * 30.0, y), 0.016))
	_scarf_tail(f, path, red, cream)
	# 甩到背后的一头:从结绕过左肩,沿后背垂下
	var back := PackedVector3Array([knot + Vector3(-0.01, 0.006, 0.01)])
	for d: Array in [[-60.0, 0.56, 0.02], [-140.0, 0.54, 0.018], [-165.0, 0.47, 0.016], [-172.0, 0.4, 0.016]]:
		back.append(Kit.surface_point(c, shapes, k, Kit.aim(c, d[0], d[1]), d[2]))
	_scarf_tail(f, back, red, cream)


static func _scarf_tail(f: MeshForge, path: PackedVector3Array, red: Color, cream: Color) -> void:
	# 扁扁的围巾尾:按长度画奶油条纹(条纹处复制一圈点,硬边),末端 5 根短流苏
	var dense := PackedVector3Array()
	var colors := PackedColorArray()
	var radii := PackedVector2Array()
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	var length := 0.0
	for i in path.size() - 1:
		var seg := path[i].distance_to(path[i + 1])
		var steps := maxi(int(ceil(seg / 0.012)), 1)
		for j in steps:
			var t := float(j) / steps
			var l := length + seg * t
			dense.append(path[i].lerp(path[i + 1], t))
			var s := l / total
			var col := cream if s > 0.25 and fposmod(l, 0.05) < 0.016 else red
			colors.append(Color(col.r, col.g, col.b, 1.0))
			radii.append(Vector2(0.0075, lerpf(0.036, 0.032, s)))
		length += seg
	dense.append(path[path.size() - 1])
	colors.append(Color(red.r, red.g, red.b, 1.0))
	radii.append(Vector2(0.0075, 0.032))
	f.loft(dense, radii, 8, Vector2i(1, 1), Transform3D.IDENTITY, colors, Vector2(-1, -1), Vector3(0, 0, -1))
	# 流苏:沿末端方向再垂一小截
	var end := dense[dense.size() - 1]
	var dir := (end - dense[dense.size() - 2]).normalized()
	var across := dir.cross(Vector3(0, 0, -1)).normalized()
	f.paint(cream, 0.95)
	for i in 5:
		var o := across * lerpf(-0.024, 0.024, i / 4.0)
		f.tube(PackedVector3Array([end + o - dir * 0.004, end + o + dir * 0.022]), 0.0032, 4)
