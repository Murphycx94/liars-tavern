class_name PatronBuilder
# 酒客部件的合批配方:把物种外观数据(species/*.gd 的 LOOK)变成每个动画枢轴下的一份网格。
# 躯干、脖子、手臂、爪子、拳头、腿和尾巴在这里;头、眼、眉、耳在 PatronHeadBuilder,帽子在 PatronHatBuilder。
# 坐标:body 在 Body 枢轴(HIP)局部;neck 在 Neck 枢轴局部(单位高);arm 在肩枢轴局部(沿 -Z);
# paw / fist 在 Hand 局部;legs(含尾巴)在 Patron 根(座位坐标)。全部纯数组运算,可在工作线程跑。
# 物种特件(龟壳、披毯、子弹带……)由物种脚本的 extras(f, part, look, pal) 补上。

# 材质类(写进 CUSTOM0.x,patron.gdshader 按它叠花纹)
const FUR := 0.0
const CLOTH := 1.0
const LEATHER := 2.0
const METAL := 3.0
const SCALE := 4.0
const SHELL := 5.0
const PLAID := 6.0
const STRAW := 7.0
const KNIT := 8.0
const SMOOTH := 9.0

const BODY_CENTER := Vector3(0, 0.25, 0)
const SLEEVE_END := -0.4      # 袖口压住手腕(Hand 在 -Patron.ARM_LENGTH = -0.45)
# 动森式:坐着时肩比桌面只高一点,手臂几乎是平伸着搭到桌上(俯 ≈5°),圆手团反向烘焙这个角度,底面才平贴桌面
const PAW_PITCH := 5.0
const MITT := Vector3(0.062, 0.043, 0.066)   # 没有手指的圆手团(张开的手)半径;底面离 Hand 原点 ≈ Patron.PAW_RADIUS × PAW_SCALE.y
const FIST_RADIUS := 0.058    # 握枪的圆拳(握把包在拳里)
const BLOB_K := 0.035
# 圆肚子:体型表里的腹部椭球再放大、往前挪;胸口与肩收窄一点,整个躯干是上小下大的蛋形
const BELLY_SCALE := Vector3(1.16, 1.12, 1.2)
const BELLY_SHIFT := Vector3(0, -0.01, -0.022)
const CHEST_SCALE := Vector3(0.95, 0.95, 0.95)
# 腿:左右腿中线离身体中线的距离,沿 leg_path 的截面半径(大腿粗、小腿短粗)
const LEG_X := 0.1
const LEG_RADII := [Vector2(0.088, 0.086), Vector2(0.084, 0.082), Vector2(0.074, 0.072), Vector2(0.066, 0.064), Vector2(0.062, 0.06)]

# 体型:pelvis / belly / chest 三个椭球 [中心, 半径]
const BUILDS := {
	"slim": [[Vector3(0, 0.02, 0.0), Vector3(0.18, 0.12, 0.16)], [Vector3(0, 0.15, -0.025), Vector3(0.185, 0.15, 0.165)],
		[Vector3(0, 0.33, -0.01), Vector3(0.19, 0.17, 0.15)]],
	"round": [[Vector3(0, 0.02, 0.0), Vector3(0.19, 0.12, 0.17)], [Vector3(0, 0.14, -0.05), Vector3(0.21, 0.17, 0.195)],
		[Vector3(0, 0.33, -0.01), Vector3(0.195, 0.17, 0.155)]],
	"big": [[Vector3(0, 0.02, 0.0), Vector3(0.2, 0.12, 0.18)], [Vector3(0, 0.15, -0.065), Vector3(0.235, 0.19, 0.215)],
		[Vector3(0, 0.34, -0.015), Vector3(0.2, 0.17, 0.16)]],
	"stocky": [[Vector3(0, 0.02, 0.0), Vector3(0.19, 0.12, 0.17)], [Vector3(0, 0.15, -0.03), Vector3(0.2, 0.15, 0.175)],
		[Vector3(0, 0.33, -0.01), Vector3(0.205, 0.17, 0.155)]],
}


# —— 调色 ——

static func color(pal: Dictionary, key: String) -> Color:
	return pal.get(key, pal.get("fur", Color(0.5, 0.5, 0.5)))


static func paint(f: MeshForge, pal: Dictionary, key: String, rough := 0.75, mat := FUR, metal := 0.0) -> void:
	f.paint(color(pal, key), rough, metal)
	f.custom = Vector4(mat, 0.0, f.custom.z, 0.0)


static func start(f: MeshForge, part_seed := 0.0) -> void:
	# 所有酒客网格写满同一种顶点格式(CUSTOM0 浮点),哪个物种第一次出现都不编译新管线
	f.write_custom = true
	f.custom = Vector4(0, 0, part_seed, 0)


static func xf(pos := Vector3.ZERO, rot_deg := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	return MeshForge.xf(pos, rot_deg, scale)


static func shapes_colored(shapes: Array, pal: Dictionary) -> Array:
	# 外观数据里的形体用调色板键写颜色:[中心, 半径, 颜色键, 可选 "mirror"] → blob 用的 [中心, 半径, Color, ...]
	var out := []
	for s in shapes:
		var item := [s[0], s[1], color(pal, s[2])]
		if s.size() > 3:
			item.append(s[3])
		out.append(item)
	return out


# —— 躯干与服装 ——

static func body_shapes(look: Dictionary, pal: Dictionary) -> Array:
	var body: Dictionary = look["body"]
	var build: Array = BUILDS[body.get("build", "slim")]
	# Q 版:肚子更圆更挺(往前、往两侧鼓),骨盆略宽;胸口不动(胸前要给对手的牌扇让位)
	var shapes := [
		[build[0][0], build[0][1] * Vector3(1.1, 1.0, 1.06), color(pal, body.get("pants", "pants"))],
		[build[1][0] + BELLY_SHIFT, build[1][1] * BELLY_SCALE, color(pal, body.get("belly", "coat"))],
		[build[2][0], build[2][1] * CHEST_SCALE, color(pal, body.get("coat", "coat"))],
		[Vector3(0.13, 0.46, -0.01), Vector3(0.1, 0.075, 0.095), color(pal, body.get("coat", "coat")), "mirror"],
		[Vector3(0, 0.53, -0.02), Vector3(0.1, 0.05, 0.09), color(pal, body.get("collar", body.get("coat", "coat")))],
	]
	if body.has("shirt"):
		# 衬衫前襟:胸前一片扁椭球,颜色按最近形体取,边缘自然过渡
		shapes.append([Vector3(0, 0.4, -0.1), Vector3(0.07, 0.12, 0.06), color(pal, body["shirt"])])
	if body.has("vest"):
		shapes.append([Vector3(0, 0.22, -0.07), Vector3(0.17, 0.15, 0.12), color(pal, body["vest"])])
	for extra in body.get("shapes", []):
		var item := [extra[0], extra[1], color(pal, extra[2])]
		if extra.size() > 3:
			item.append(extra[3])
		shapes.append(item)
	return shapes


static func body(f: MeshForge, look: Dictionary, pal: Dictionary, hooks: GDScript) -> void:
	start(f, 0.1)
	f.push(body_xform())   # 动森式:躯干连衣片一起压扁、加宽
	var b: Dictionary = look["body"]
	var shapes := body_shapes(look, pal)
	paint(f, pal, b.get("coat", "coat"), 0.85, b.get("material", CLOTH))
	f.blob(BODY_CENTER, shapes, 36, 22, BLOB_K)
	if b.get("lapels", false):
		_lapels(f, pal, b, shapes)
	_neckwear(f, pal, b)
	hooks.extras(f, "body", look, pal)
	f.pop()


static func body_xform() -> Transform3D:
	# 躯干网格(连衣片、物种特件)整体的压扁加宽,绕髋部(Body 局部原点)
	return xf(Vector3.ZERO, Vector3.ZERO, Vector3(PatronParts.BODY_WIDEN, PatronParts.BODY_SQUASH, PatronParts.BODY_WIDEN))


static func _lapels(f: MeshForge, pal: Dictionary, b: Dictionary, shapes: Array) -> void:
	# 翻领:两片贴着胸前斜放的扁片,压暗的外套色
	paint(f, pal, b.get("lapel", "lapel"), 0.8, CLOTH)
	for side: float in [-1.0, 1.0]:
		var top := MeshForge.blob_surface(BODY_CENTER, Vector3(0.12 * side, 0.27, -1), shapes, BLOB_K)
		var bottom := MeshForge.blob_surface(BODY_CENTER, Vector3(0.03 * side, 0.02, -1), shapes, BLOB_K)
		var path := PackedVector3Array([top + Vector3(0, 0, -0.004), (top + bottom) * 0.5 + Vector3(0, 0, -0.012),
			bottom + Vector3(0, 0, -0.004)])
		f.loft(path, PackedVector2Array([Vector2(0.006, 0.03), Vector2(0.006, 0.026), Vector2(0.005, 0.006)]), 6)


static func _neckwear(f: MeshForge, pal: Dictionary, b: Dictionary) -> void:
	var kind: String = b.get("neckwear", "none")
	var key: String = b.get("neckwear_color", "accent")
	var at := Vector3(0, 0.535, -0.11)
	match kind:
		"bowtie":
			paint(f, pal, key, 0.55, CLOTH)
			f.blob(at, [[at + Vector3(0.028, 0, 0), Vector3(0.03, 0.022, 0.012), color(pal, key), "mirror"],
				[at, Vector3(0.012, 0.012, 0.013), color(pal, key).darkened(0.25)]], 14, 8, 0.008)
		"cravat":
			paint(f, pal, key, 0.6, CLOTH)
			f.blob(at + Vector3(0, -0.04, -0.01), [[at + Vector3(0, -0.01, -0.01), Vector3(0.035, 0.03, 0.022), color(pal, key)],
				[at + Vector3(0, -0.065, -0.012), Vector3(0.028, 0.045, 0.016), color(pal, key)]], 14, 10, 0.012)
		"bandana":
			paint(f, pal, key, 0.7, CLOTH)
			f.torus(0.07, 0.1, 18, xf(Vector3(0, 0.55, -0.02), Vector3.ZERO, Vector3(1.0, 0.5, 1.0)))
			f.loft(PackedVector3Array([at + Vector3(0, 0.0, -0.005), at + Vector3(0, -0.06, -0.02), at + Vector3(0, -0.11, -0.025)]),
				PackedVector2Array([Vector2(0.012, 0.06), Vector2(0.01, 0.04), Vector2(0.004, 0.006)]), 6)
		"neckerchief":
			paint(f, pal, key, 0.7, CLOTH)
			f.torus(0.072, 0.098, 18, xf(Vector3(0, 0.552, -0.02), Vector3.ZERO, Vector3(1.0, 0.45, 1.0)))
			f.sphere(0.02, 10, xf(at + Vector3(0.02, -0.01, -0.01), Vector3.ZERO, Vector3(1.2, 1.0, 0.8)))


# —— 脖子 ——

static func neck(f: MeshForge, look: Dictionary, pal: Dictionary) -> void:
	# 单位高的车削体(y 从 0 到 1),Patron 每帧按领口到头的距离拉长;光滑皮毛,拉长 8 倍也不出条纹
	start(f, 0.2)
	var r: float = look["neck"].get("radius", 0.075)
	paint(f, pal, look["neck"].get("color", "fur"), 0.75, SMOOTH)
	f.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(r * 1.12, 0.0), Vector2(r, 0.5), Vector2(r * 0.96, 1.0),
		Vector2(0.0, 1.0)]), 16)


# —— 手臂与爪子 ——

static func arm(f: MeshForge, look: Dictionary, pal: Dictionary, hooks: GDScript) -> void:
	# 短粗的袖子:肩 → 袖口沿 -Z 几乎一样粗,两头圆;袖口一圈换色。卷袖的物种(bear/pig)小臂露出皮毛
	start(f, 0.3)
	var a: Dictionary = look["arms"]
	var sleeve := color(pal, a.get("sleeve", "coat"))
	var cuff := color(pal, a.get("cuff", a.get("sleeve", "coat")))
	var forearm: String = a.get("forearm", "")
	var path := PackedVector3Array([Vector3(0, 0.0, 0.03), Vector3(0, 0, -0.05), Vector3(0, -0.006, -0.18),
		Vector3(0, -0.004, -0.28), Vector3(0, 0, -0.34), Vector3(0, 0, -0.342), Vector3(0, 0, SLEEVE_END)])
	var radii := PackedVector2Array([Vector2(0.076, 0.076), Vector2(0.078, 0.076), Vector2(0.072, 0.07),
		Vector2(0.068, 0.066), Vector2(0.068, 0.066), Vector2(0.072, 0.07), Vector2(0.07, 0.068)])
	var colors := PackedColorArray()
	for i in path.size():
		var c := sleeve
		if forearm != "" and i >= 3:
			c = color(pal, forearm)
		elif i >= 5:
			c = cuff
		colors.append(Color(c.r, c.g, c.b, 1.0))
	if forearm != "":
		# 卷到小臂的袖口:袖子本身到肘下为止,外面一圈胖胖的卷边
		paint(f, pal, a.get("sleeve", "coat"), 0.85, a.get("material", CLOTH))
		f.loft(path.slice(0, 4), radii.slice(0, 4), 14, Vector2i(1, 0), Transform3D.IDENTITY, colors.slice(0, 3) + PackedColorArray([colors[2]]))
		paint(f, pal, a.get("cuff", a.get("sleeve", "coat")), 0.85, CLOTH)
		f.torus(0.062, 0.086, 16, xf(Vector3(0, -0.005, -0.21), Vector3(90, 0, 0)))
		paint(f, pal, forearm, 0.75, FUR)
		f.loft(path.slice(2), PackedVector2Array([Vector2(0.064, 0.062), Vector2(0.06, 0.058), Vector2(0.06, 0.058),
			Vector2(0.06, 0.058), Vector2(0.058, 0.056)]), 12, Vector2i(0, 1))
	else:
		paint(f, pal, a.get("sleeve", "coat"), 0.85, a.get("material", CLOTH))
		f.loft(path, radii, 14, Vector2i(1, 1), Transform3D.IDENTITY, colors)
	hooks.extras(f, "arm", look, pal)


static func paw(f: MeshForge, look: Dictionary, pal: Dictionary, side: float) -> void:
	# 张开的手:没有手指的圆手团(动森式),朝身体内侧鼓一个小拇指包;反向烘焙坐姿的手臂俯角,底面平贴桌面
	start(f, 0.4 + side * 0.05)
	var p: Dictionary = look["paws"]
	var fur := color(pal, p.get("color", "paw"))
	var shapes := [[Vector3(0, 0.0, -0.012), MITT, fur],
		[Vector3(0.05 * side, -0.004, -0.004), Vector3(0.024, 0.022, 0.028), fur]]   # 拇指包朝身体内侧
	paint(f, pal, p.get("color", "paw"), 0.8, SMOOTH)
	f.blob(Vector3(0, 0.0, -0.01), shapes, 22, 12, 0.014, xf(Vector3.ZERO, Vector3(PAW_PITCH, 0, 0)))


static func fist(f: MeshForge, look: Dictionary, pal: Dictionary) -> void:
	# 握枪的拳头(只有右手):一个圆团,顶上压着一个小拇指包;握把包在拳里
	start(f, 0.45)
	var fur := color(pal, look["paws"].get("color", "paw"))
	paint(f, pal, look["paws"].get("color", "paw"), 0.8, SMOOTH)
	f.blob(Vector3.ZERO, [[Vector3.ZERO, Vector3(1.0, 0.96, 1.0) * FIST_RADIUS, fur],
		[Vector3(-0.03, 0.04, -0.02), Vector3(0.022, 0.02, 0.026), fur]], 20, 12, 0.012)


# —— 腿、鞋、尾巴(座位坐标)——

static func legs(f: MeshForge, look: Dictionary, pal: Dictionary, hooks: GDScript) -> void:
	# 短粗的腿:大腿平放在座面上到前沿,小腿垂下来,圆圆的小脚悬在半空(动森式坐椅子)
	start(f, 0.5)
	var l: Dictionary = look["legs"]
	for side: float in [-1.0, 1.0]:
		var path := leg_path(side)
		paint(f, pal, l.get("pants", "pants"), 0.85, l.get("material", CLOTH))
		f.loft(path, PackedVector2Array(LEG_RADII), 12, Vector2i(1, 0), Transform3D.IDENTITY, PackedColorArray(), Vector2(-1, -1), Vector3(0, 0, -1))
		_shoe(f, pal, l, foot_point(side))
	hooks.extras(f, "legs", look, pal)
	_tail(f, look, pal)


static func leg_path(side: float) -> PackedVector3Array:
	# 大腿根 → 膝(座面前沿)→ 小腿往下略往前垂
	var x := LEG_X * side
	return PackedVector3Array([Vector3(x, 0.5, 0.1), Vector3(x, 0.505, -0.02), Vector3(x, 0.49, -0.1),
		Vector3(x * 1.02, 0.38, -0.13), Vector3(x * 1.03, 0.27, -0.14)])


static func foot_point(side: float) -> Vector3:
	# 脚底中心(座位坐标):悬在离地 ≈0.2 m 处
	return Vector3(LEG_X * 1.03 * side, 0.2, -0.15)


static func _shoe(f: MeshForge, pal: Dictionary, l: Dictionary, at: Vector3) -> void:
	# 胖脚:绕脚底中心放大
	f.push(Transform3D(Basis.from_scale(Vector3.ONE * PatronParts.FOOT_CHUBBY), at - at * PatronParts.FOOT_CHUBBY))
	_shoe_shape(f, pal, l, at)
	f.pop()


static func _shoe_shape(f: MeshForge, pal: Dictionary, l: Dictionary, at: Vector3) -> void:
	var kind: String = l.get("foot", "oxford")
	match kind:
		"bare", "hoof", "claws":
			# 光脚:皮毛色的圆脚团(蹄子、爪子都不分趾,颜色区分)
			var fur := color(pal, l.get("foot_color", "paw"))
			paint(f, pal, l.get("foot_color", "paw"), 0.8, SMOOTH)
			f.blob(at + Vector3(0, 0.035, -0.02), [[at + Vector3(0, 0.035, -0.025), Vector3(0.05, 0.038, 0.07), fur],
				[at + Vector3(0, 0.05, 0.01), Vector3(0.046, 0.04, 0.045), fur]], 18, 10, 0.014)
		"webbed":
			# 扁扁的蹼脚(企鹅):脚跟一团、往前摊开的脚掌,前缘三个圆趾头
			var web := color(pal, l.get("foot_color", "paw"))
			paint(f, pal, l.get("foot_color", "paw"), 0.6, SMOOTH)
			f.blob(at + Vector3(0, 0.025, -0.03), [[at + Vector3(0, 0.03, 0.005), Vector3(0.04, 0.03, 0.04), web],
				[at + Vector3(0, 0.014, -0.045), Vector3(0.05, 0.014, 0.05), web],
				[at + Vector3(0.032, 0.013, -0.088), Vector3(0.019, 0.013, 0.022), web, "mirror"],
				[at + Vector3(0, 0.013, -0.096), Vector3(0.019, 0.013, 0.022), web]], 18, 10, 0.012)
		_:
			# 鞋 / 靴:圆头胖鞋,鞋底一圈深色(颜色混合,不另做鞋底块);靴子多一截圆靴筒
			var shoe := color(pal, l.get("shoe", "shoe"))
			var sole := color(pal, "sole")
			paint(f, pal, l.get("shoe", "shoe"), 0.6, LEATHER)
			var shapes := [[at + Vector3(0, 0.04, -0.03), Vector3(0.052, 0.04, 0.075), shoe],
				[at + Vector3(0, 0.05, 0.015), Vector3(0.048, 0.044, 0.048), shoe],
				[at + Vector3(0, 0.008, -0.02), Vector3(0.05, 0.012, 0.07), sole]]
			if kind == "boot" or kind == "cowboy":
				shapes.append([at + Vector3(0, 0.1, 0.005), Vector3(0.052, 0.07, 0.05), shoe])
			if kind == "spats":
				shapes.append([at + Vector3(0, 0.075, 0.0), Vector3(0.05, 0.035, 0.05), color(pal, l.get("spats", "cream"))])
			f.blob(at + Vector3(0, 0.045, -0.01), shapes, 18, 12, 0.014)


static func _tail(f: MeshForge, look: Dictionary, pal: Dictionary) -> void:
	var t: Dictionary = look.get("tail", {})
	if t.is_empty():
		return
	var path := PackedVector3Array(t["path"])
	var radii := PackedVector2Array()
	var base: float = t.get("radius", 0.03)
	var tip_radius: float = t.get("tip_radius", base * 0.35)
	var colors := PackedColorArray()
	var tip_from: float = t.get("tip_from", 2.0)
	for i in path.size():
		var s := float(i) / (path.size() - 1)
		var bulge: float = t.get("bulge", 0.0)
		var r := lerpf(base, tip_radius, s) + bulge * sin(s * PI)
		radii.append(Vector2(r, r))
		var c := color(pal, t.get("tip", t.get("color", "fur"))) if s >= tip_from else color(pal, t.get("color", "fur"))
		colors.append(Color(c.r, c.g, c.b, 1.0))
	paint(f, pal, t.get("color", "fur"), 0.75, t.get("material", FUR))
	var sway: Vector2 = t.get("sway_range", Vector2(0.35, 1.0))
	f.loft(path, radii, 12, Vector2i(1, 1), Transform3D.IDENTITY, colors, sway)
