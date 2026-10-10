class_name BombCatProps
# 炸弹猫道具效果的 3D 小道具(规格 2026-10-10「道具效果加强」):全部程序生成、动森式圆滚滚的粉彩造型,能加脸的都加一张小脸。
# - 实心道具(平底锅、炸弹猫、放大镜、大剪刀、五种零食、爱心、蝴蝶结、星星、印章)用道具共享材质 WorldMaterials.prop()
#   (颜色、粗糙度、金属度、微微自发光都写在顶点上),每种一份 MeshForge.cached 网格,所有实例共用;
# - 会淡出的薄片(冲击波圈、速度线、脚印、印章印、聚光柱、气泡、闪光十字)用 bomb_fx.gdshader 的两份共享材质(平放 / 公告板),
#   淡出与变色走实例参数 alpha / tint;
# - 卡通烟团粒子用一个低面数球 + 一份 toon StandardMaterial3D(颜色来自粒子颜色渐变)。
# 坐标约定:道具原点在底部中心(能「坐」在桌上),正脸朝 +Z;平底锅开口朝 +Y、锅柄朝 +X;剪刀刀尖朝 +Y。
# 网格与材质都缓存;材质缓存由 main.gd 退出时 clear_cache 释放(网格在 MeshForge 的缓存里)。
# 效果件一律不投影。


const FX_SHADER := preload("res://src/world/shaders/bomb_fx.gdshader")
const SNACK_SIZE := 0.11            # 零食大约这么高(米)
const KITTY_RADIUS := 0.095         # 炸弹猫的身子半径
const FUSE_BASE := Vector3(0.0, KITTY_RADIUS * 2.0 + 0.006, -0.012)   # 导火索根(炸弹猫局部坐标,顶盖上沿)
const FUSE_TIP := Vector3(0.042, 0.066, 0.004)   # 导火索尖(导火索局部坐标,原点在根上)
const PAN_RADIUS := 0.13
const SNIP_PIVOT_GAP := 0.007       # 两片剪刀前后错开一点
const STAMP_RADIUS := 0.16
# 颜色(sRGB,albedo 封顶 0.8):色相照炸弹猫新牌面的插画配色(动森风格设计文档 §10.4),亮度按道具色板的惯例等比压到 0.8 以内
const EYE := Color(0.24, 0.14, 0.1)   # 深棕豆豆眼
const SHINE := Color(0.8, 0.8, 0.8)
const BLUSH := Color(0.8, 0.46, 0.52)
const KITTY_FUR := Color(0.27, 0.25, 0.34)   # 炭灰紫
const KITTY_MUZZLE := Color(0.62, 0.58, 0.66)
const ROPE := Color(0.8, 0.65, 0.45)   # 引信
const BRASS := Color(0.8, 0.68, 0.4)
const SILVER := Color(0.71, 0.74, 0.8)   # 银引信座 / 剪刀刃
const EAR_PINK := Color(0.8, 0.56, 0.61)
const MINT := Color(0.3, 0.7, 0.58)
const CORAL := Color(0.8, 0.49, 0.49)   # 剪刀圆环把
const PAN_SHELL := Color(0.8, 0.4, 0.37)   # 珊瑚红锅身
const PAN_INSIDE := Color(0.62, 0.6, 0.7)   # 灰薰衣草锅底
const WOOD := Color(0.8, 0.6, 0.4)   # 木把手
const HEART_PINK := Color(0.8, 0.35, 0.43)   # 莓粉心
const STAR_YELLOW := Color(0.8, 0.72, 0.28)
const STAMP_RED := Color(0.8, 0.32, 0.34)   # 圆形红印章
const CREAM := Color(0.8, 0.78, 0.74)   # 奶白猫爪
const LILAC := Color(0.58, 0.45, 0.8)   # 放大镜的淡紫框与把
# 牌桌上隔着两三米看:道具都放大成卡通的夸张比例(网格里直接放大;炸弹猫与剪刀在 BombCatFx 里按节点放大)
const MESH_SCALES := {"pan": 1.7, "magnifier": 1.6, "heart": 2.3, "bow": 1.7, "star": 2.3, "paw": 2.3, "bubble": 2.2, "badge": 2.0}
const KITTY_SCALE := 1.4
const SNIP_SCALE := 1.45
const SNACK_SCALE := 2.0
const SNACKS := [BombCatCard.SNACK_FISH, BombCatCard.SNACK_YARN, BombCatCard.SNACK_CARROT, BombCatCard.SNACK_BANANA,
	BombCatCard.SNACK_CACTUS]

static var _cache := {}


static func clear_cache() -> void:
	_cache = {}


# —— 材质 ——

static func fx_material(billboard := false) -> ShaderMaterial:
	# 淡出薄片共用的两份材质:平放 / 公告板(新建,不 duplicate)
	var key := "fx:%s" % billboard
	if not _cache.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = FX_SHADER
		mat.render_priority = 2
		mat.set_shader_parameter("billboard", billboard)
		_cache[key] = mat
	return _cache[key]


static func puff_mesh() -> SphereMesh:
	# 卡通烟团粒子:低面数球,toon 漫反射 + 边光,颜色 = 粒子颜色(顶点色当 albedo)
	if not _cache.has("puff"):
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true   # 粒子颜色按 sRGB 写的粉彩色(不转的话会被当成线性色,全褪成奶白)
		mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mat.roughness = 1.0
		mat.rim_enabled = true
		mat.rim = 0.5
		mat.rim_tint = 0.2
		mat.emission_enabled = true
		mat.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
		mat.emission = Color(0.07, 0.055, 0.05)   # 暗处也是一团软软的亮色,不是黑团
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 14
		mesh.rings = 7
		mesh.material = mat
		_cache["puff"] = mesh
	return _cache["puff"]


static func tuft_material(color: Color) -> StandardMaterial3D:
	# 炸焦的头发:炭灰色 toon 小球(每种颜色一份)
	var key := "tuft:" + color.to_html()
	if not _cache.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mat.roughness = 1.0
		mat.rim_enabled = true
		mat.rim = 0.4
		_cache[key] = mat
	return _cache[key]


static func _prop_mesh(key: String, recipe: Callable) -> ArrayMesh:
	return MeshForge.cached("bombfx:" + key, _scaled(key, recipe), {&"main": WorldMaterials.prop()})


static func _fx_mesh(key: String, recipe: Callable, billboard := false) -> ArrayMesh:
	return MeshForge.cached("bombfx:" + key, _scaled(key, recipe), {&"main": fx_material(billboard)})


static func _scaled(key: String, recipe: Callable) -> Callable:
	var k: float = MESH_SCALES.get(key, 1.0)
	if is_equal_approx(k, 1.0):
		return recipe
	return func(f: MeshForge) -> void:
		f.push(MeshForge.xf(Vector3.ZERO, Vector3.ZERO, Vector3.ONE * k))
		recipe.call(f)
		f.pop()


# —— 小脸(五种零食与炸弹猫共用的画法)——

static func _on_sphere(c: Vector3, r: float, x: float, y: float, lift := 0.0) -> Vector3:
	# 半径 r 的球(球心 c)正面(+Z)上,横 x、纵 y 处的表面点,再往外抬 lift
	var z := sqrt(maxf(r * r - x * x - y * y, 0.0))
	var n := Vector3(x, y, z).normalized()
	return c + n * (r + lift)


static func face(f: MeshForge, c: Vector3, r: float, s: float, eye_gap := 0.016, eye_y := 0.004) -> void:
	# 小脸:两只亮晶晶的黑豆眼(各两颗高光)、两团腮红、一弯 ω 形笑嘴。c / r 是脸所在曲面的近似球心与半径,s 是整体大小
	for side: float in [-1.0, 1.0]:
		var x := eye_gap * s * side
		var y := eye_y * s
		var p := _on_sphere(c, r, x, y)
		f.paint(EYE, 0.3)
		f.glow = Vector2.ZERO
		f.sphere(0.0115 * s, 12, MeshForge.xf(p, Vector3.ZERO, Vector3(1.0, 1.15, 0.6)))
		f.paint(SHINE, 0.2)
		f.glow = Vector2(0.35, 0.0)
		f.sphere(0.0042 * s, 8, MeshForge.xf(_on_sphere(c, r, x - 0.0035 * s, y + 0.0045 * s, 0.006 * s)))
		f.sphere(0.0022 * s, 6, MeshForge.xf(_on_sphere(c, r, x + 0.004 * s, y - 0.004 * s, 0.006 * s)))
		f.glow = Vector2.ZERO
		f.paint(BLUSH, 0.8)
		f.sphere(0.0075 * s, 10, MeshForge.xf(_on_sphere(c, r, x * 1.75, y - 0.012 * s, -0.001 * s), Vector3.ZERO, Vector3(1.35, 0.75, 0.35)))
	# ω 嘴:两小段下弯的弧
	f.paint(EYE, 0.4)
	for side: float in [-1.0, 1.0]:
		var path := PackedVector3Array()
		for k in 6:
			var u := float(k) / 5.0
			var x := (side * 0.0055 * u) * s
			var y := (eye_y - 0.012 - 0.0035 * sin(u * PI)) * s
			path.append(_on_sphere(c, r, x, y, 0.0006 * s))
		f.tube(path, 0.0016 * s, 6)


# —— 平底锅(甩锅)——

static func pan() -> ArrayMesh:
	return _prop_mesh("pan", func(f: MeshForge):
		var r := PAN_RADIUS
		f.paint(PAN_SHELL, 0.55)
		f.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(r * 0.78, 0.0), Vector2(r * 0.94, 0.012), Vector2(r, 0.046),
			Vector2(r * 0.985, 0.052)]), 32)
		f.paint(PAN_INSIDE, 0.5, 0.15)
		f.lathe(PackedVector2Array([Vector2(r * 0.985, 0.052), Vector2(r * 0.92, 0.047), Vector2(r * 0.85, 0.017),
			Vector2(0.0, 0.013)]), 32)
		# 锅里的笑脸(朝 +Y):借 face 的画法,把正脸方向 +Z 转到 +Y
		f.push(MeshForge.xf(Vector3(0, 0.013, 0), Vector3(-90, 0, 0)))
		face(f, Vector3(0, 0, -0.6), 0.6, 2.4, 0.016, 0.0)
		f.pop()
		# 锅柄:奶油色箍 + 木柄,微微上翘,柄尾一个挂绳小圆环
		var tilt := MeshForge.xf(Vector3(r * 0.96, 0.034, 0.0), Vector3(0, 0, 10))
		f.push(tilt)
		f.paint(CREAM, 0.5)
		f.cylinder(0.021, 0.021, 0.03, 16, MeshForge.CAPS_BOTH, MeshForge.xf(Vector3(0.012, 0, 0), Vector3(0, 0, 90)))
		f.paint(WOOD, 0.75)
		f.capsule(0.019, 0.17, 16, MeshForge.xf(Vector3(0.11, 0, 0), Vector3(0, 0, 90)))
		f.paint(PAN_SHELL, 0.55)
		f.torus(0.008, 0.015, 16, MeshForge.xf(Vector3(0.2, 0, 0), Vector3(90, 0, 0)))
		f.pop())


# —— 炸弹猫(摸到炸弹)——

static func kitty_body() -> ArrayMesh:
	# 圆滚滚的深靛色炸弹,长着猫耳、奶白嘴套、胡子、两只小脚、卷尾巴,顶上一圈黄铜盖(眼睛与导火索是单独的件)
	return _prop_mesh("kitty_body", func(f: MeshForge):
		var r := KITTY_RADIUS
		var c := Vector3(0, r, 0)
		f.paint(KITTY_FUR, 0.32, 0.12)
		f.sphere(r, 28, MeshForge.xf(c))
		# 猫耳:两个圆锥,外深内粉
		for side: float in [-1.0, 1.0]:
			var ear := MeshForge.xf(c + Vector3(0.055 * side, 0.068, -0.006), Vector3(0, 0, -28 * side))
			f.paint(KITTY_FUR, 0.4, 0.1)
			f.cylinder(0.003, 0.034, 0.055, 14, MeshForge.CAPS_BOTTOM, ear)
			f.paint(EAR_PINK, 0.6)
			f.cylinder(0.002, 0.02, 0.038, 12, MeshForge.CAPS_BOTTOM, ear * MeshForge.xf(Vector3(0, -0.004, 0.011)))
		# 嘴套 + 小鼻子 + ω 嘴 + 腮红
		var muzzle := _on_sphere(c, r, 0.0, -0.028, -0.012)
		f.paint(KITTY_MUZZLE, 0.6)
		f.sphere(0.032, 16, MeshForge.xf(muzzle, Vector3.ZERO, Vector3(1.25, 0.8, 0.6)))
		f.paint(Color(0.8, 0.45, 0.52), 0.4)
		f.sphere(0.008, 10, MeshForge.xf(muzzle + Vector3(0, 0.012, 0.018), Vector3.ZERO, Vector3(1.3, 0.85, 0.8)))
		f.paint(EYE, 0.4)
		for side: float in [-1.0, 1.0]:
			var path := PackedVector3Array()
			for k in 6:
				var u := float(k) / 5.0
				path.append(muzzle + Vector3(side * 0.009 * u, 0.002 - 0.006 * sin(u * PI), 0.0195 - 0.002 * u))
			f.tube(path, 0.0019, 6)
			f.paint(BLUSH, 0.8)
			f.sphere(0.011, 10, MeshForge.xf(_on_sphere(c, r, 0.05 * side, -0.016, -0.002), Vector3.ZERO, Vector3(1.4, 0.75, 0.35)))
			f.paint(Color(0.8, 0.78, 0.74), 0.5)
			for k in 2:
				var y := 0.004 - k * 0.008
				var start := muzzle + Vector3(0.026 * side, y, 0.006)
				f.tube(PackedVector3Array([start, start + Vector3(0.028 * side, y * 0.6 + 0.003 * (1 - k * 2), -0.004),
					start + Vector3(0.05 * side, y + 0.002 * (1 - k * 2), -0.012)]), 0.0014, 5)
			f.paint(EYE, 0.4)
		# 小脚
		f.paint(KITTY_MUZZLE, 0.65)
		for side: float in [-1.0, 1.0]:
			f.sphere(0.024, 12, MeshForge.xf(Vector3(0.042 * side, 0.012, 0.058), Vector3.ZERO, Vector3(1.0, 0.6, 1.2)))
		# 卷尾巴
		f.paint(KITTY_FUR, 0.4, 0.1)
		var tail := PackedVector3Array()
		for k in 10:
			var u := float(k) / 9.0
			tail.append(Vector3(0.02 * sin(u * 5.0), 0.05 + u * 0.09, -r - 0.012 - 0.035 * sin(u * PI)))
		f.tube(tail, 0.011, 8)
		# 顶盖(银引信座)
		f.paint(SILVER, 0.4, 0.5)
		f.cylinder(0.026, 0.03, 0.022, 18, MeshForge.CAPS_BOTH, MeshForge.xf(Vector3(0, r * 2.0 - 0.006, -0.012)))
		f.paint(SILVER.darkened(0.12), 0.4, 0.5)
		f.torus(0.024, 0.032, 18, MeshForge.xf(Vector3(0, r * 2.0 + 0.004, -0.012))))


static func kitty_eyes() -> ArrayMesh:
	# 两只亮晶晶的大眼睛(单独一件:拆弹后眯成一条缝、惊吓时瞪圆都是缩放它)。原点在两眼中点
	return _prop_mesh("kitty_eyes", func(f: MeshForge):
		for side: float in [-1.0, 1.0]:
			var p := Vector3(0.034 * side, 0.0, 0.0)
			f.paint(Color(0.8, 0.79, 0.76), 0.3)
			f.glow = Vector2.ZERO
			f.sphere(0.025, 16, MeshForge.xf(p, Vector3.ZERO, Vector3(1.0, 1.15, 0.5)))
			f.paint(Color(0.1, 0.09, 0.18), 0.2)
			f.sphere(0.019, 16, MeshForge.xf(p + Vector3(0.002 * side, -0.003, 0.007), Vector3.ZERO, Vector3(1.0, 1.15, 0.5)))
			f.paint(SHINE, 0.15)
			f.glow = Vector2(0.6, 0.0)
			f.sphere(0.0068, 10, MeshForge.xf(p + Vector3(-0.005, 0.007, 0.016)))
			f.sphere(0.0034, 8, MeshForge.xf(p + Vector3(0.007, -0.008, 0.015)))
			f.glow = Vector2.ZERO)


static func kitty_fuse() -> ArrayMesh:
	# 导火索:一截弯弯的麻绳(原点在根上,尖在 FUSE_TIP)
	return _prop_mesh("kitty_fuse", func(f: MeshForge):
		f.paint(ROPE, 0.85)
		var path := PackedVector3Array()
		for k in 9:
			var u := float(k) / 8.0
			path.append(Vector3(FUSE_TIP.x * u * u, FUSE_TIP.y * sin(u * PI * 0.5), FUSE_TIP.z * u + 0.006 * sin(u * PI)))
		f.tube(path, 0.0065, 8)
		f.paint(Color(0.3, 0.22, 0.18), 0.9)
		f.sphere(0.0075, 8, MeshForge.xf(FUSE_TIP)))


# —— 放大镜(偷看)——

static func magnifier() -> ArrayMesh:
	# 镜片在 XY 平面(朝 ±Z),镜框中心在原点,粉色木柄朝 -Y
	return _prop_mesh("magnifier", func(f: MeshForge):
		f.paint(Color(0.68, 0.75, 0.8), 0.08, 0.0)
		f.glow = Vector2(0.18, 0.3)
		f.sphere(0.078, 24, MeshForge.xf(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.16)))
		f.glow = Vector2(0.7, 0.0)
		f.paint(SHINE, 0.1)
		var arc := PackedVector3Array()
		for k in 7:
			var a := deg_to_rad(110.0 + k * 14.0)
			arc.append(Vector3(cos(a) * 0.05, sin(a) * 0.05, 0.0135))
		f.tube(arc, 0.0045, 6)
		f.glow = Vector2.ZERO
		f.paint(LILAC, 0.5)
		f.torus(0.074, 0.096, 32, MeshForge.xf(Vector3.ZERO, Vector3(90, 0, 0)))
		f.paint(CREAM, 0.5)
		f.cylinder(0.022, 0.02, 0.03, 16, MeshForge.CAPS_BOTH, MeshForge.xf(Vector3(0, -0.106, 0)))
		f.paint(LILAC, 0.55)
		f.capsule(0.02, 0.15, 16, MeshForge.xf(Vector3(0, -0.19, 0)))
		f.paint(CREAM, 0.5)
		f.sphere(0.012, 10, MeshForge.xf(Vector3(0, -0.268, 0))))


# —— 大剪刀(拆弹)——

static func snip_half(side: float) -> ArrayMesh:
	# 半把剪刀:浅银蓝刀片朝 +Y,珊瑚粉圆环把在下,薄荷色铆钉;side = ±1 两片镜像(前后错开)。原点在铆钉
	return _prop_mesh("snip:%d" % int(side), func(f: MeshForge):
		var z := SNIP_PIVOT_GAP * side
		f.paint(SILVER, 0.35, 0.45)
		var blade := PackedVector2Array([Vector2(0.004, -0.012), Vector2(0.026, 0.03), Vector2(0.02, 0.13), Vector2(0.004, 0.205),
			Vector2(-0.004, 0.14), Vector2(-0.006, 0.02)])
		for i in blade.size():
			blade[i].x *= side
		f.extrude(blade, 0.01, 0.003, MeshForge.xf(Vector3(0, 0, z)))
		f.paint(CORAL, 0.55)
		f.capsule(0.013, 0.085, 12, MeshForge.xf(Vector3(0.014 * side, -0.045, z), Vector3(0, 0, 22 * side)))
		f.torus(0.022, 0.037, 24, MeshForge.xf(Vector3(0.036 * side, -0.115, z), Vector3(90, 0, 0)))
		f.paint(MINT, 0.5)
		f.cylinder(0.012, 0.012, 0.008, 14, MeshForge.CAPS_BOTH, MeshForge.xf(Vector3(0, 0, z * 1.9), Vector3(90, 0, 0))))


# —— 零食(对子 / 三条)——

static func snack(id: String) -> ArrayMesh:
	match id:
		BombCatCard.SNACK_FISH:
			return _prop_mesh("snack_fish", _fish)
		BombCatCard.SNACK_YARN:
			return _prop_mesh("snack_yarn", _yarn)
		BombCatCard.SNACK_CARROT:
			return _prop_mesh("snack_carrot", _carrot)
		BombCatCard.SNACK_BANANA:
			return _prop_mesh("snack_banana", _banana)
	return _prop_mesh("snack_cactus", _cactus)


static func _fish(f: MeshForge) -> void:
	# 鱼干:焦糖色胖小鱼侧身立着(奶油肚皮)(鱼头朝 +X),尾鳍、背鳍,侧脸朝 +Z
	var c := Vector3(0, 0.045, 0)
	f.paint(Color(0.8, 0.6, 0.37), 0.55)
	f.sphere(0.042, 24, MeshForge.xf(c, Vector3.ZERO, Vector3(1.45, 1.0, 0.62)))
	f.paint(CREAM, 0.6)
	f.sphere(0.036, 18, MeshForge.xf(c + Vector3(0.004, -0.012, 0), Vector3.ZERO, Vector3(1.4, 0.6, 0.6)))
	f.paint(Color(0.8, 0.55, 0.32), 0.55)
	f.extrude(PackedVector2Array([Vector2(-0.052, 0.0), Vector2(-0.09, 0.03), Vector2(-0.082, 0.0), Vector2(-0.09, -0.03)]),
		0.012, 0.004, MeshForge.xf(c))
	f.extrude(PackedVector2Array([Vector2(-0.02, 0.03), Vector2(0.0, 0.052), Vector2(0.018, 0.034)]), 0.008, 0.003, MeshForge.xf(c))
	face(f, c + Vector3(0.03, 0.0, 0.0), 0.028, 1.0, 0.009, 0.006)


static func _yarn(f: MeshForge) -> void:
	# 毛线球:粉色线团缠着几圈深一点的线,拖着一截线头
	var r := 0.048
	var c := Vector3(0, r, 0)
	f.paint(Color(0.8, 0.5, 0.63), 0.85)
	f.sphere(r, 24, MeshForge.xf(c))
	f.paint(Color(0.8, 0.44, 0.65), 0.85)
	for rot: Vector3 in [Vector3(70, 0, 20), Vector3(60, 60, -10), Vector3(100, -50, 30), Vector3(20, 0, 80)]:
		f.torus(r - 0.002, r + 0.0035, 32, MeshForge.xf(c, rot))
	var strand := PackedVector3Array()
	for k in 8:
		var u := float(k) / 7.0
		strand.append(c + Vector3(r * 0.7 + u * 0.05, -r * 0.6 - u * 0.012 + 0.008 * sin(u * 7.0), -0.01 + u * 0.02))
	f.tube(strand, 0.0035, 6)
	face(f, c, r, 1.15)


static func _carrot(f: MeshForge) -> void:
	# 胡萝卜:胖胖的橙色圆锥(尖朝下)、几道浅纹、顶上三片叶子
	var h := 0.1
	f.paint(Color(0.8, 0.48, 0.23), 0.7)
	f.cylinder(0.034, 0.006, h, 20, MeshForge.CAPS_BOTH, MeshForge.xf(Vector3(0, h / 2.0, 0)))
	f.sphere(0.034, 18, MeshForge.xf(Vector3(0, h, 0), Vector3.ZERO, Vector3(1, 0.45, 1)))
	f.paint(Color(0.72, 0.42, 0.2), 0.75)
	for k in 3:
		var y := 0.03 + k * 0.022
		var rr := 0.006 + (0.034 - 0.006) * (y / h)
		f.torus(rr - 0.001, rr + 0.002, 20, MeshForge.xf(Vector3(0, y, 0)))
	f.paint(Color(0.46, 0.77, 0.42), 0.7)
	for k in 3:
		f.capsule(0.009, 0.05, 10, MeshForge.xf(Vector3(0, h + 0.022, 0), Vector3((k - 1) * 28.0, 0, (k - 1) * -14.0)) \
			* MeshForge.xf(Vector3(0, 0.014, 0)))
	face(f, Vector3(0, 0.072, 0), 0.03, 0.95, 0.014)


static func _banana(f: MeshForge) -> void:
	# 香蕉:一根弯弯的黄香蕉侧躺(凸面朝 +Z 对着镜头),两头棕色小尖
	var path := PackedVector3Array()
	var radii := PackedVector2Array()
	for k in 11:
		var u := float(k) / 10.0
		var a := lerpf(-1.0, 1.0, u)
		path.append(Vector3(a * 0.06, 0.03 + 0.03 * (1.0 - a * a) * -1.0 + 0.03, 0.022 * (1.0 - a * a)))
		var w := 0.02 * (0.35 + 0.65 * sin(u * PI))
		radii.append(Vector2(w, w))
	f.paint(Color(0.8, 0.69, 0.3), 0.6)
	f.loft(path, radii, 14, Vector2i(1, 1), Transform3D.IDENTITY, PackedColorArray(), Vector2(-1, -1), Vector3.BACK)
	f.paint(Color(0.42, 0.32, 0.18), 0.7)
	f.sphere(0.008, 8, MeshForge.xf(path[0]))
	f.sphere(0.006, 8, MeshForge.xf(path[path.size() - 1]))
	face(f, Vector3(0, 0.03, 0.022) + Vector3(0, 0.0, -0.02), 0.04, 0.85, 0.013, 0.0)


static func _cactus(f: MeshForge) -> void:
	# 仙人掌:陶土小盆里一根胖绿柱子 + 两条小胳膊,头顶一朵粉花
	f.paint(Color(0.8, 0.5, 0.37), 0.75)
	f.cylinder(0.034, 0.026, 0.032, 18, MeshForge.CAPS_BOTH, MeshForge.xf(Vector3(0, 0.016, 0)))
	f.cylinder(0.038, 0.038, 0.008, 18, MeshForge.CAPS_BOTH, MeshForge.xf(Vector3(0, 0.034, 0)))
	f.paint(Color(0.5, 0.78, 0.5), 0.7)
	f.capsule(0.028, 0.1, 18, MeshForge.xf(Vector3(0, 0.075, 0)))
	f.capsule(0.012, 0.04, 10, MeshForge.xf(Vector3(-0.034, 0.085, 0), Vector3(0, 0, 25)))
	f.capsule(0.011, 0.034, 10, MeshForge.xf(Vector3(0.033, 0.075, 0), Vector3(0, 0, -30)))
	f.paint(Color(0.8, 0.5, 0.59), 0.6)
	for k in 5:
		var a := TAU * k / 5.0
		f.sphere(0.009, 8, MeshForge.xf(Vector3(cos(a) * 0.009, 0.128, sin(a) * 0.009)))
	f.paint(Color(0.8, 0.74, 0.36), 0.5)
	f.sphere(0.006, 8, MeshForge.xf(Vector3(0, 0.131, 0)))
	face(f, Vector3(0, 0.082, 0), 0.028, 0.9, 0.012)


# —— 爱心、蝴蝶结、星星、印章 ——

static func _heart_outline(size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 32:
		var t := TAU * k / 32.0
		var x := 16.0 * pow(sin(t), 3)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		pts.append(Vector2(x, y) * size / 32.0)
	return pts


static func heart() -> ArrayMesh:
	# 胖爱心:约 6 cm 宽,原点在中心,正面朝 +Z
	return _prop_mesh("heart", func(f: MeshForge):
		f.paint(HEART_PINK, 0.5)
		f.glow = Vector2(0.06, 0.0)
		f.extrude(_heart_outline(0.06), 0.022, 0.008)
		f.glow = Vector2(0.5, 0.0)
		f.paint(Color(0.8, 0.7, 0.74), 0.3)
		f.sphere(0.006, 8, MeshForge.xf(Vector3(-0.014, 0.008, 0.011), Vector3.ZERO, Vector3(1.3, 1, 0.5))))


static func bow() -> ArrayMesh:
	# 粉色蝴蝶结(讨要的那张牌上系着):两只圈 + 结 + 两条飘带,原点在结上,正面朝 +Z
	return _prop_mesh("bow", func(f: MeshForge):
		f.paint(Color(0.82, 0.48, 0.62), 0.55)
		for side: float in [-1.0, 1.0]:
			f.torus(0.01, 0.02, 16, MeshForge.xf(Vector3(0.022 * side, 0.004, 0), Vector3(90, 0, 18 * side), Vector3(1.35, 1, 0.8)))
			f.extrude(PackedVector2Array([Vector2(0, 0), Vector2(0.012 * side, -0.035), Vector2(0.002 * side, -0.03), Vector2(-0.004 * side, -0.004)]),
				0.004, 0.0015)
		f.paint(Color(0.76, 0.4, 0.56), 0.55)
		f.sphere(0.009, 10, MeshForge.xf(Vector3.ZERO, Vector3.ZERO, Vector3(1.1, 1, 0.8))))


static func star() -> ArrayMesh:
	# 胖五角星(自带一点暖色自发光):外径 4 cm,原点在中心,正面朝 +Z
	return _prop_mesh("star", func(f: MeshForge):
		var pts := PackedVector2Array()
		for k in 10:
			var a := PI * 0.5 + TAU * k / 10.0
			var r := 0.04 if k % 2 == 0 else 0.019
			pts.append(Vector2(cos(a), sin(a)) * r)
		f.paint(STAR_YELLOW, 0.4)
		f.glow = Vector2(0.4, 0.0)
		f.extrude(pts, 0.016, 0.006, Transform3D.IDENTITY, Vector2i(1, 1), 70.0))


static func stamp() -> ArrayMesh:
	# 「不行!」大印章:胖胖的红色圆印身(顶面鼓起一圈、印着奶白色的大爪印)+ 红色橡胶印面(朝 -Y)+ 奶油色圆木把手;原点在印面中心
	return _prop_mesh("stamp", func(f: MeshForge):
		var r := STAMP_RADIUS
		f.paint(STAMP_RED.darkened(0.15), 0.65)
		f.cylinder(r * 0.96, r * 0.96, 0.014, 32, MeshForge.CAPS_BOTH, MeshForge.xf(Vector3(0, 0.007, 0)))
		f.paint(STAMP_RED, 0.5)
		f.cylinder(r, r * 0.98, 0.05, 32, MeshForge.CAPS_BOTTOM, MeshForge.xf(Vector3(0, 0.039, 0)))
		f.sphere(r, 32, MeshForge.xf(Vector3(0, 0.064, 0), Vector3.ZERO, Vector3(1.0, 0.18, 1.0)))
		f.torus(r - 0.014, r + 0.006, 32, MeshForge.xf(Vector3(0, 0.064, 0)))
		# 顶面的奶白爪印(掌垫 + 四个趾豆),朝本地 -Z
		f.paint(CREAM, 0.6)
		f.sphere(r * 0.3, 18, MeshForge.xf(Vector3(0, 0.078, r * 0.18), Vector3.ZERO, Vector3(1.2, 0.22, 0.95)))
		for k in 4:
			var a := deg_to_rad(-60.0 + k * 40.0)
			f.sphere(r * 0.13, 14, MeshForge.xf(Vector3(sin(a) * r * 0.46, 0.076, -cos(a) * r * 0.42 - r * 0.08), Vector3.ZERO,
				Vector3(0.9, 0.3, 1.1)))
		# 把手:细脖子 + 圆球
		f.paint(Color(0.8, 0.72, 0.56), 0.7)
		f.cylinder(0.026, 0.034, 0.06, 18, MeshForge.CAPS_NONE, MeshForge.xf(Vector3(0, 0.1, 0)))
		f.paint(Color(0.8, 0.64, 0.46), 0.6)
		f.sphere(0.05, 20, MeshForge.xf(Vector3(0, 0.15, 0))))


# —— 淡出薄片(bomb_fx 材质)——

static func _disc(f: MeshForge, center: Vector3, radius: float, normal_axis: int, seg := 24, squash := Vector2.ONE) -> void:
	# 一片实心圆(扇形):normal_axis 1 = 平放(法线 +Y),2 = 立着(法线 +Z)
	var points := PackedVector3Array([center])
	var normals := PackedVector3Array([Vector3.UP if normal_axis == 1 else Vector3.BACK])
	var indices := PackedInt32Array()
	for k in seg:
		var a := TAU * k / seg
		var d := Vector2(cos(a) * squash.x, sin(a) * squash.y) * radius
		points.append(center + (Vector3(d.x, 0, -d.y) if normal_axis == 1 else Vector3(d.x, d.y, 0)))
		normals.append(normals[0])
	for k in seg:
		indices.append_array([0, 1 + k, 1 + (k + 1) % seg])
	f.raw(points, normals, PackedVector2Array(), indices)


static func paw_print() -> ArrayMesh:
	# 平放在桌上的小爪印(掌垫 + 四个趾豆),趾头朝 -Z;约 5 cm
	return _fx_mesh("paw", func(f: MeshForge):
		f.paint(Color.WHITE, 1.0)
		_disc(f, Vector3(0, 0, 0.006), 0.014, 1, 20, Vector2(1.15, 0.95))
		for k in 4:
			var a := deg_to_rad(-62.0 + k * 41.3)
			_disc(f, Vector3(sin(a) * 0.021, 0.0002 * k, -cos(a) * 0.019 - 0.004), 0.0065, 1, 14, Vector2(0.9, 1.1)))


static func ring() -> ArrayMesh:
	# 平放的圆环(冲击波):外径 1、内径 0.82,按需缩放
	return _fx_mesh("ring", func(f: MeshForge):
		f.paint(Color.WHITE, 1.0)
		var points := PackedVector3Array()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		var seg := 48
		for k in seg + 1:
			var a := TAU * k / seg
			points.append(Vector3(cos(a), 0, sin(a)) * 0.82)
			points.append(Vector3(cos(a), 0, sin(a)))
			normals.append(Vector3.UP)
			normals.append(Vector3.UP)
			if k > 0:
				var i := k * 2
				indices.append_array([i - 2, i - 1, i, i - 1, i + 1, i])
		f.raw(points, normals, PackedVector2Array(), indices))


static func streak() -> ArrayMesh:
	# 速度线:一根两头尖的细条(沿 X,长 1、宽 0.06),平放;按需缩放、旋转
	return _fx_mesh("streak", func(f: MeshForge):
		f.paint(Color.WHITE, 1.0)
		var pts := PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(-0.2, 0, -0.03), Vector3(0.5, 0, 0), Vector3(-0.2, 0, 0.03)])
		var n := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
		f.raw(pts, n, PackedVector2Array(), PackedInt32Array([0, 1, 2, 0, 2, 3])))


static func stamp_mark() -> ArrayMesh:
	# 印章盖下去的印子(平放):一圈粗圆框 + 中间一只大爪印;字由 Label3D 另写。外径 1,按需缩放
	return _fx_mesh("stamp_mark", func(f: MeshForge):
		f.paint(Color.WHITE, 1.0)
		var points := PackedVector3Array()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		var seg := 40
		for k in seg + 1:
			var a := TAU * k / seg
			points.append(Vector3(cos(a), 0, sin(a)) * 0.76)
			points.append(Vector3(cos(a), 0, sin(a)))
			normals.append(Vector3.UP)
			normals.append(Vector3.UP)
			if k > 0:
				var i := k * 2
				indices.append_array([i - 2, i - 1, i, i - 1, i + 1, i])
		f.raw(points, normals, PackedVector2Array(), indices)
		# 爪印在印子上半(字在下半)
		_disc(f, Vector3(0, 0.0005, -0.18), 0.17, 1, 22, Vector2(1.15, 0.9))
		for k in 4:
			var a := deg_to_rad(-60.0 + k * 40.0)
			_disc(f, Vector3(sin(a) * 0.3, 0.0008, -cos(a) * 0.26 - 0.28), 0.075, 1, 14, Vector2(0.9, 1.1)))


static func cone() -> ArrayMesh:
	# 聚光柱:上细下粗的开口圆台(高 1,原点在底面中心)
	return _fx_mesh("cone", func(f: MeshForge):
		f.paint(Color.WHITE, 1.0)
		f.cylinder(0.12, 0.36, 1.0, 28, MeshForge.CAPS_NONE, MeshForge.xf(Vector3(0, 0.5, 0)))
		_disc(f, Vector3(0, 0.002, 0), 0.4, 1, 28))


static func bubble() -> ArrayMesh:
	# 公告板气泡:深色描边圆 + 奶白圆 + 朝下的小尾巴(描边先画、白底后画,同一网格里按三角形顺序覆盖)
	return _fx_mesh("bubble", func(f: MeshForge):
		f.paint(Color(0.24, 0.16, 0.12), 1.0)
		_disc(f, Vector3.ZERO, 0.11, 2, 32)
		var tail := PackedVector3Array([Vector3(-0.03, -0.08, 0), Vector3(0.0, -0.15, 0), Vector3(0.03, -0.085, 0)])
		f.raw(tail, PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK]), PackedVector2Array(), PackedInt32Array([0, 1, 2]))
		f.paint(Color(1.0, 0.97, 0.9), 1.0)
		_disc(f, Vector3.ZERO, 0.1, 2, 32)
		var inner := PackedVector3Array([Vector3(-0.022, -0.08, 0), Vector3(0.0, -0.132, 0), Vector3(0.022, -0.085, 0)])
		f.raw(inner, PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK]), PackedVector2Array(), PackedInt32Array([0, 1, 2])),
		true)


static func badge() -> ArrayMesh:
	# 公告板小徽章(「×N」的底):描边圆 + 珊瑚色圆 + 高光
	return _fx_mesh("badge", func(f: MeshForge):
		f.paint(Color(0.3, 0.16, 0.12), 1.0)
		_disc(f, Vector3.ZERO, 0.075, 2, 28)
		f.paint(Color(1.0, 0.56, 0.42), 1.0)
		_disc(f, Vector3.ZERO, 0.066, 2, 28)
		f.paint(Color(1.0, 0.82, 0.7), 1.0)
		_disc(f, Vector3(-0.024, 0.028, 0), 0.014, 2, 12, Vector2(1.3, 0.8)),
		true)


static func glint() -> ArrayMesh:
	# 公告板闪光十字(四个细长尖角):外径 1,按需缩放
	return _fx_mesh("glint", func(f: MeshForge):
		f.paint(Color.WHITE, 1.0)
		var points := PackedVector3Array([Vector3.ZERO])
		var normals := PackedVector3Array([Vector3.BACK])
		var indices := PackedInt32Array()
		for k in 8:
			var a := TAU * k / 8.0 + PI * 0.5
			var r := 1.0 if k % 2 == 0 else 0.14
			points.append(Vector3(cos(a) * r, sin(a) * r, 0))
			normals.append(Vector3.BACK)
		for k in 8:
			indices.append_array([0, 1 + k, 1 + (k + 1) % 8])
		f.raw(points, normals, PackedVector2Array(), indices),
		true)
