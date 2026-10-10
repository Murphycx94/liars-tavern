class_name RoomProps
# 房间陈设:四面墙的墙饰(10 张通缉令、3 幅鎏金框画、摆钟与钟摆、马蹄铁、套索、「不许出老千」告示)、
# 钢琴与琴凳、衣帽架、角落杂物(共享车削木桶 + 桶箍、货箱、麻袋、小酒桶架)、三块动森式毛绒地毯、接地贴花、黄铜蜡烛壁灯,
# 以及氛围(暖色 LUT、分层体积雾)。墙饰与地毯、外景都用 decor 材质;布景件一律不投影。


const GRAIN_ALONG_Y := Basis(Vector3.BACK, PI / 2.0)
const BARREL_SPOTS := [Vector3(3.7, 0, -3.6), Vector3(3.1, 0, -3.9), Vector3(3.85, 0, -2.9)]
const LYING_BARREL := [Vector3(3.0, 0.29, -2.95), Vector3(90, 15, 0)]
const KEGS := [[Vector3(-3.92, 0.2, -3.96), Vector3(0, 0, 90)], [Vector3(-3.9, 0.53, -3.95), Vector3(0, 12, 90)]]
const CRATES := [[Vector3(3.85, 0.0, 3.85), 0.6, 8.0], [Vector3(3.8, 0.6, 3.9), 0.45, -14.0], [Vector3(3.15, 0.0, 4.0), 0.5, 21.0]]
const SACKS := [Vector3(3.35, 0, 3.45), Vector3(4.0, 0, 3.2), Vector3(4.0, 0, -2.25), Vector3(3.6, 0, -2.35)]
const PIANO := {"x": Vector2(-3.45, -2.05), "z": Vector2(3.78, 4.33), "height": 1.25}
const PIANO_BENCH := Vector3(-2.75, 0.0, 3.15)
const COAT_RACK := Vector3(2.55, 0.0, 4.12)
const PENDULUM_DROP := 0.08     # 钟摆枢轴在钟壳中心之上
const PENDULUM_SWING := 6.0      # 度
const PENDULUM_PERIOD := 2.4     # 秒(来回一趟)
const BURLAP := Color(0.78, 0.66, 0.48)


static func build(tavern: Node3D) -> Array:
	# 返回要闪烁的灯(壁灯)
	for wall in ["back", "front", "left", "right"]:
		var items := RoomLayout.DECOR.filter(func(d): return d["wall"] == wall)
		RoomKit.add(tavern, "Decor_" + wall, "decor:" + wall, _decor_recipe.bind(items), {&"main": WorldMaterials.decor()},
			MeshKit.LAYER_SCENERY, false)
		RoomKit.add(tavern, "WallProps_" + wall, "wallprops:" + wall, _wall_props_recipe.bind(items), {&"main": WorldMaterials.prop()},
			MeshKit.LAYER_SCENERY, false)
	_clock(tavern)
	RoomKit.add(tavern, "Piano", "piano", _piano_recipe, {&"wood": WorldMaterials.wood("table", true), &"prop": WorldMaterials.prop(),
		&"decor": WorldMaterials.decor()}, MeshKit.LAYER_SCENERY, false)
	var bench := MeshKit.add(tavern, BarSet.stool_mesh(), null, PIANO_BENCH, Vector3(0, 20, 0), Vector3(1, 0.68, 1), MeshKit.SHADOW_ON)
	bench.name = "PianoBench"
	RoomKit.add(tavern, "CoatRack", "coat_rack", _coat_rack_recipe, {&"wood": WorldMaterials.wood("dark", true),
		&"prop": WorldMaterials.prop()}, MeshKit.LAYER_SCENERY, false)
	_clutter(tavern)
	var rugs := RoomKit.add(tavern, "Rugs", "rugs", _rugs_recipe, {&"main": WorldMaterials.decor()}, MeshKit.LAYER_SCENERY, false)
	# 主毯在着色器里随牌桌放大:包围盒按最大的桌子留足,免得大桌时被视锥剔掉
	var big := RoomLayout.RUG_MAIN_RADIUS * RoomLayout.main_rug_scale(SeatLayout.POKER_TABLE_RADIUS)
	rugs.custom_aabb = rugs.mesh.get_aabb().merge(AABB(Vector3(-big, 0.0, -big), Vector3(big * 2.0, 0.05, big * 2.0)))
	fit_rug(SeatLayout.TABLE_RADIUS)
	_decals(tavern)
	return _sconces(tavern)


# —— 墙饰 ——

static func _decor_recipe(f: MeshForge, items: Array) -> void:
	for item in items:
		var size: Vector2 = item["size"]
		var wall: String = item["wall"]
		match item["kind"]:
			"poster":
				RoomKit.decor_paint(f, 0, 0.0, Color(1, 1, 1))
				var xf := RoomLayout.wall_xform(wall, item["u"], item["y"], RoomLayout.FLAT_OFFSET, item["tilt"])
				f.quad(size, DecorAtlas.rect("poster%d" % item["species"]), xf, item.get("curl", 0.0), 6)
			"painting":
				RoomKit.decor_paint(f, 0, 0.0, Color(0.95, 0.92, 0.86))
				var inner := size - Vector2(0.08, 0.08)
				f.quad(inner, DecorAtlas.rect("painting_" + item["art"]),
					RoomLayout.wall_xform(wall, item["u"], item["y"], RoomLayout.FLAT_OFFSET + 0.008))
			"sign":
				RoomKit.decor_paint(f, 0, 0.0, Color(1, 1, 1))
				f.quad(size, DecorAtlas.rect("sign_cheat"), RoomLayout.wall_xform(wall, item["u"], item["y"], RoomLayout.FLAT_OFFSET))
			"chalkboard":
				RoomKit.decor_paint(f, 0, 0.0, Color(1, 1, 1))
				f.quad(size - Vector2(0.05, 0.05), DecorAtlas.rect("chalkboard"),
					RoomLayout.wall_xform(wall, item["u"], item["y"], RoomLayout.FLAT_OFFSET + 0.006, item["tilt"]))
			"clock":
				RoomKit.decor_paint(f, 0, 0.0, Color(1, 1, 1))
				f.quad(Vector2(0.26, 0.26), DecorAtlas.rect("clock"), RoomLayout.wall_xform(wall, item["u"], item["y"] + 0.23, 0.121))
				# 钟摆窗的暗底
				RoomKit.decor_paint(f, 0, 0.0, Color(0.26, 0.2, 0.18), 0.8)
				f.quad(Vector2(0.2, 0.3), Rect2(0.99, 0.99, 0.005, 0.005), RoomLayout.wall_xform(wall, item["u"], item["y"] - 0.17, 0.022))


static func _wall_props_recipe(f: MeshForge, items: Array) -> void:
	for item in items:
		var size: Vector2 = item["size"]
		var wall: String = item["wall"]
		var b := RoomLayout.wall_basis(wall)
		match item["kind"]:
			"chalkboard":
				# 木框 + 粉笔槽
				RoomKit.paint(f, [Color(0.60, 0.38, 0.22), 0.75, 0.0])
				var xf := RoomLayout.wall_xform(wall, item["u"], item["y"], 0.0, item["tilt"])
				for k in 4:
					var horizontal := k < 2
					var len: float = size.x if horizontal else size.y - 0.05
					var off := Vector3(0, (size.y - 0.025) / 2.0 * (1 if k == 0 else -1), 0.008) if horizontal \
						else Vector3((size.x - 0.025) / 2.0 * (1 if k == 2 else -1), 0, 0.008)
					RoomKit.rounded_box(f, Vector3(len, 0.03, 0.02) if horizontal else Vector3(0.03, len, 0.02), 0.009,
						xf * Transform3D(Basis.IDENTITY, off), 1)
				RoomKit.rounded_box(f, Vector3(size.x * 0.8, 0.016, 0.04), 0.007, xf * Transform3D(Basis.IDENTITY, Vector3(0, -size.y / 2.0 - 0.006, 0.02)), 1)
				RoomKit.paint(f, RoomKit.CREAM)
				f.box(Vector3(0.05, 0.01, 0.01), xf * Transform3D(Basis.IDENTITY, Vector3(0.1, -size.y / 2.0 + 0.005, 0.03)))
			"wheel":
				# 马车轮:木轮辋 + 铁箍 + 12 根辐条 + 轮毂
				var xf := RoomLayout.wall_xform(wall, item["u"], item["y"], 0.05)
				var r: float = size.x / 2.0
				var flat := Basis(Vector3.RIGHT, PI / 2.0)
				RoomKit.paint(f, [Color(0.66, 0.43, 0.25), 0.78, 0.0])
				f.torus(r - 0.06, r - 0.012, 40, xf * Transform3D(flat, Vector3.ZERO) * Transform3D(Basis.from_scale(Vector3(1, 1.6, 1)), Vector3.ZERO))
				for k in 12:
					var a := TAU * k / 12.0
					f.cylinder(0.012, 0.016, r - 0.08, 6, MeshForge.CAPS_NONE,
						xf * Transform3D(Basis(Vector3(0, 0, 1), a), Vector3(-sin(a), cos(a), 0) * (r - 0.04) * 0.5))
				f.cylinder(0.06, 0.07, 0.09, 14, MeshForge.CAPS_BOTH, xf * Transform3D(flat, Vector3.ZERO))
				RoomKit.paint(f, RoomKit.IRON)
				f.torus(r - 0.016, r + 0.002, 40, xf * Transform3D(flat, Vector3.ZERO) * Transform3D(Basis.from_scale(Vector3(1, 1.4, 1)), Vector3.ZERO))
				f.cylinder(0.03, 0.03, 0.11, 10, MeshForge.CAPS_BOTH, xf * Transform3D(flat, Vector3.ZERO))
			"poster", "sign":
				# 顶上两颗钉子
				RoomKit.paint(f, RoomKit.IRON)
				for s in [-1, 1]:
					var p := RoomLayout.wall_xform(wall, item["u"], item["y"], RoomLayout.FLAT_OFFSET, item["tilt"]) \
						* Vector3(s * (size.x / 2.0 - 0.025), size.y / 2.0 - 0.025, 0.004)
					f.sphere(0.007, 8, Transform3D(b, p))
			"painting":
				# 鎏金画框:四根倒角框条
				RoomKit.paint(f, RoomKit.GILT)
				var xf := RoomLayout.wall_xform(wall, item["u"], item["y"], 0.0)
				var w := 0.05
				for k in 4:
					var horizontal := k < 2
					var len: float = size.x if horizontal else size.y
					var off := Vector3(0, (size.y - w) / 2.0 * (1 if k == 0 else -1), 0) if horizontal \
						else Vector3((size.x - w) / 2.0 * (1 if k == 2 else -1), 0, 0)
					var rot := Basis.IDENTITY if horizontal else Basis(Vector3(0, 0, 1), PI / 2.0)
					f.extrude_x(PackedVector2Array([Vector2(0.0, -w / 2.0), Vector2(0.02, -w / 2.0), Vector2(0.03, -w / 4.0),
						Vector2(0.03, w / 4.0), Vector2(0.02, w / 2.0), Vector2(0.0, w / 2.0)]), len,
						xf * Transform3D(rot, off))
			"horseshoe":
				RoomKit.paint(f, RoomKit.IRON)
				var xf := RoomLayout.wall_xform(wall, item["u"], item["y"], 0.012)
				var path := PackedVector3Array()
				for k in 15:
					var a := deg_to_rad(160.0 + k * (220.0 / 14.0))   # 开口朝上的 U
					path.append(xf * Vector3(cos(a) * 0.055, sin(a) * 0.06 - 0.005, 0))
				f.tube(path, 0.011, 6)
				RoomKit.paint(f, RoomKit.BRASS)
				f.sphere(0.008, 8, Transform3D(b, xf * Vector3(0, 0.065, -0.004)))
			"lasso":
				# 挂钉上盘三圈的绳子,下面垂一截绳头(外框 size 以 y 为中心)
				RoomKit.paint(f, RoomKit.ROPE)
				var xf := RoomLayout.wall_xform(wall, item["u"], item["y"], 0.03)
				for loop in 3:
					var path := PackedVector3Array()
					for k in 25:
						var a := TAU * k / 24.0
						path.append(xf * Vector3(cos(a) * (0.14 - loop * 0.01) + loop * 0.012, sin(a) * 0.15 + 0.04 + loop * 0.008, loop * 0.012))
					f.tube(path, 0.009, 6)
				var tail := PackedVector3Array([xf * Vector3(0.1, -0.08, 0.03), xf * Vector3(0.12, -0.17, 0.04), xf * Vector3(0.09, -0.25, 0.03)])
				f.tube(tail, 0.009, 6)
				RoomKit.paint(f, RoomKit.IRON)
				f.cylinder(0.01, 0.01, 0.06, 8, MeshForge.CAPS_BOTH, Transform3D(b * Basis(Vector3.RIGHT, PI / 2.0), xf * Vector3(0, 0.19, -0.03)))


static func _clock(tavern: Node3D) -> void:
	var item: Dictionary = RoomLayout.DECOR.filter(func(d): return d["kind"] == "clock")[0]
	var size: Vector2 = item["size"]
	RoomKit.add(tavern, "Clock", "clock_case", func(f: MeshForge): _clock_case(f, item), {&"main": WorldMaterials.wood("dark", true),
		&"prop": WorldMaterials.prop()}, MeshKit.LAYER_SCENERY, false)
	var pivot := MeshKit.pivot(tavern, RoomLayout.wall_point("back", item["u"], item["y"] + PENDULUM_DROP, 0.07), "Pendulum")
	var mesh := MeshForge.cached("clock_pendulum", func(f: MeshForge):
		RoomKit.paint(f, RoomKit.BRASS)
		f.box(Vector3(0.008, 0.3, 0.004), MeshForge.xf(Vector3(0, -0.15, 0)))
		f.cylinder(0.04, 0.04, 0.008, 18, MeshForge.CAPS_BOTH, MeshForge.xf(Vector3(0, -0.31, 0), Vector3(90, 0, 0))),
		{&"main": WorldMaterials.prop()})
	MeshKit.add(pivot, mesh, null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF).layers = MeshKit.LAYER_SCENERY
	if pivot.is_inside_tree():
		pivot.rotation.z = deg_to_rad(-PENDULUM_SWING)
		var tween := pivot.create_tween().set_loops()
		tween.tween_property(pivot, "rotation:z", deg_to_rad(PENDULUM_SWING), PENDULUM_PERIOD / 2.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(pivot, "rotation:z", deg_to_rad(-PENDULUM_SWING), PENDULUM_PERIOD / 2.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


static func _clock_case(f: MeshForge, item: Dictionary) -> void:
	# 摆钟壳 0.34 × 0.85 × 0.12:背板、侧板、顶帽与尖饰、底座;前脸上半是钟面板,下半开 0.20 × 0.30 的钟摆窗
	var u: float = item["u"]
	var cy: float = item["y"]
	var size: Vector2 = item["size"]
	var y0 := cy - size.y / 2.0
	var y1 := cy + size.y / 2.0
	var d := 0.12
	f.surface(&"main")
	f.part_space = true
	f.paint(Color.WHITE, 0.6)
	var wall := "back"
	f.part_basis = GRAIN_ALONG_Y
	f.seed = 1.0
	RoomShell.wall_box(f, wall, u - size.x / 2.0, u + size.x / 2.0, y0, y1, 0.0, 0.015)
	for s in [-1, 1]:
		RoomShell.wall_box(f, wall, u + s * (size.x / 2.0 - 0.01), u + s * size.x / 2.0, y0, y1, 0.0, d)
	f.part_basis = Basis.IDENTITY
	f.seed = 2.0
	var win0 := cy - 0.32   # 钟摆窗 0.20 × 0.30
	var win1 := cy - 0.02
	RoomShell.wall_box(f, wall, u - size.x / 2.0, u + size.x / 2.0, win1, y1, d - 0.02, d)
	RoomShell.wall_box(f, wall, u - size.x / 2.0, u + size.x / 2.0, y0, win0, d - 0.02, d)
	for s in [-1, 1]:
		RoomShell.wall_box(f, wall, u + s * 0.10, u + s * size.x / 2.0, win0, win1, d - 0.02, d)
	RoomShell.wall_box(f, wall, u - size.x / 2.0 - 0.025, u + size.x / 2.0 + 0.025, y1, y1 + 0.05, 0.0, d + 0.025)
	RoomShell.wall_box(f, wall, u - size.x / 2.0 - 0.015, u + size.x / 2.0 + 0.015, y0 - 0.04, y0, 0.0, d + 0.015)
	f.part_space = false
	f.surface(&"prop")
	RoomKit.paint(f, RoomKit.BRASS)
	f.sphere(0.022, 10, RoomShell.wall_frame(wall, u) * Transform3D(Basis.IDENTITY, Vector3(0, y1 + 0.075, d / 2.0)))
	f.torus(0.128, 0.142, 28, RoomShell.wall_frame(wall, u) * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, cy + 0.23, d + 0.002)))


# —— 钢琴与衣帽架 ——

static func _piano_recipe(f: MeshForge) -> void:
	var x0: float = PIANO["x"].x
	var x1: float = PIANO["x"].y
	var z0: float = PIANO["z"].x
	var z1: float = PIANO["z"].y
	var h: float = PIANO["height"]
	var cx := (x0 + x1) / 2.0
	f.surface(&"wood")
	f.part_space = true
	f.paint(Color.WHITE, 0.45)
	f.seed = 1.0
	# 上半琴身、下半琴身(膝下内凹)、顶盖、键床、两侧颊板与前腿、踢脚
	RoomKit.rounded_box(f, Vector3(x1 - x0, h - 0.74, z1 - z0), 0.045, MeshForge.xf(Vector3(cx, (h + 0.74) / 2.0, (z0 + z1) / 2.0)))
	RoomKit.rounded_box(f, Vector3(x1 - x0, 0.66, z1 - z0 - 0.15), 0.035, MeshForge.xf(Vector3(cx, 0.04 + 0.33, (z0 + 0.15 + z1) / 2.0)))
	RoomKit.extrude_smooth(f, RoomKit.round_rect(z1 - z0 + 0.04, 0.04, 0.019), x1 - x0 + 0.04,
		Transform3D(Basis.IDENTITY, Vector3(cx, h + 0.0175, (z0 + z1) / 2.0 - 0.01)))
	f.seed = 2.0
	f.box(Vector3(x1 - x0 - 0.1, 0.04, z0 - 3.55 + 0.02), MeshForge.xf(Vector3(cx, 0.72, (3.55 + z0) / 2.0)))
	f.box(Vector3(x1 - x0 - 0.1, 0.12, 0.03), MeshForge.xf(Vector3(cx, 0.80, z0 - 0.015)))
	for s in [-1, 1]:
		var x: float = cx + s * ((x1 - x0) / 2.0 - 0.025)
		f.box(Vector3(0.05, 0.16, z0 - 3.55 + 0.02), MeshForge.xf(Vector3(x, 0.80, (3.55 + z0) / 2.0)))
		f.part_basis = GRAIN_ALONG_Y
		f.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.035, 0.0), Vector2(0.03, 0.08), Vector2(0.04, 0.3),
			Vector2(0.026, 0.62), Vector2(0.034, 0.7), Vector2(0.0, 0.7)]), 10, PackedInt32Array([1, 5]),
			MeshForge.xf(Vector3(x - s * 0.02, 0.0, 3.62)))
		f.part_basis = Basis.IDENTITY
	f.box(Vector3(x1 - x0, 0.05, 0.02), MeshForge.xf(Vector3(cx, 0.025, z0 + 0.14)))
	# 乐谱架
	f.box(Vector3(0.5, 0.03, 0.03), MeshForge.xf(Vector3(cx, 0.94, z0 - 0.04)))
	f.part_space = false
	# 正面两只黄铜烛台(未点燃)
	f.surface(&"prop")
	for s in [-1, 1]:
		var p := Vector3(cx + s * 0.55, 1.0, z0 - 0.06)
		RoomKit.paint(f, RoomKit.BRASS)
		f.box(Vector3(0.012, 0.08, 0.06), MeshForge.xf(p + Vector3(0, 0, 0.03)))
		f.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.034, 0.012), Vector2(0.012, 0.02), Vector2(0.0, 0.02)]),
			12, PackedInt32Array([1, 2]), MeshForge.xf(p))
		RoomKit.paint(f, RoomKit.WAX)
		f.cylinder(0.011, 0.012, 0.11, 10, MeshForge.CAPS_BOTH, MeshForge.xf(p + Vector3(0, 0.075, 0)))
	# 琴键与乐谱(decor 纸面)
	f.surface(&"decor")
	RoomKit.decor_paint(f, 0, 0.0, Color(1, 1, 1))
	f.quad(Vector2(1.22, 0.16), DecorAtlas.rect("keys"), Transform3D(Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)),
		Vector3(cx, 0.7405, 3.65)))
	var lean := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)) * Basis(Vector3.RIGHT, deg_to_rad(-12))
	f.quad(Vector2(0.21, 0.27), DecorAtlas.rect("music"), Transform3D(lean, Vector3(cx - 0.05, 1.08, z0 - 0.045)))
	f.quad(Vector2(0.21, 0.27), DecorAtlas.rect("music"), Transform3D(lean * Basis(Vector3(0, 0, 1), 0.04), Vector3(cx + 0.17, 1.08, z0 - 0.05)))


static func _coat_rack_recipe(f: MeshForge) -> void:
	var p := COAT_RACK
	f.surface(&"wood")
	f.part_space = true
	f.paint(Color.WHITE, 0.7)
	f.part_basis = GRAIN_ALONG_Y
	f.seed = 1.0
	f.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.03, 0.0), Vector2(0.024, 0.1), Vector2(0.02, 1.6), Vector2(0.028, 1.66),
		Vector2(0.02, 1.72), Vector2(0.035, 1.76), Vector2(0.0, 1.8)]), 12, PackedInt32Array([1]), MeshForge.xf(p))
	# 三条脚
	for k in 3:
		var a := TAU * k / 3.0 + 0.4
		var foot := p + Vector3(cos(a), 0, sin(a)) * 0.24
		var top := p + Vector3(cos(a), 0, sin(a)) * 0.02 + Vector3(0, 0.22, 0)
		var d := top - foot
		f.seed = 2.0 + k
		f.cylinder(0.014, 0.018, d.length(), 8, MeshForge.CAPS_BOTH, Transform3D(Basis(Quaternion(Vector3.UP, d.normalized())), (top + foot) / 2.0))
	# 四根挂钉
	for k in 4:
		var a := TAU * k / 4.0 + 0.3
		var base := p + Vector3(0, 1.62, 0)
		var tip := base + Vector3(cos(a) * 0.14, 0.08, sin(a) * 0.14)
		var d := tip - base
		f.seed = 6.0 + k
		f.cylinder(0.009, 0.012, d.length(), 8, MeshForge.CAPS_BOTH, Transform3D(Basis(Quaternion(Vector3.UP, d.normalized())), (tip + base) / 2.0))
	f.part_space = false
	f.part_basis = Basis.IDENTITY
	f.surface(&"prop")
	# 牛仔帽挂在一根钉上
	var hat := p + Vector3(cos(0.3) * 0.15, 1.66, sin(0.3) * 0.15)
	RoomKit.paint(f, RoomKit.FELT_HAT)
	var tilt := MeshForge.xf(hat, Vector3(-12, 20, 70))
	f.cylinder(0.17, 0.17, 0.012, 22, MeshForge.CAPS_BOTH, tilt)
	f.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.075, 0.0), Vector2(0.07, 0.09), Vector2(0.04, 0.11), Vector2(0.0, 0.1)]),
		16, PackedInt32Array([1]), tilt)
	RoomKit.paint(f, RoomKit.LEATHER)
	f.cylinder(0.077, 0.077, 0.018, 16, MeshForge.CAPS_NONE, tilt * MeshForge.xf(Vector3(0, 0.015, 0)))
	# 圆顶礼帽戴在杆顶
	RoomKit.paint(f, RoomKit.BLACK)
	var bowler := MeshForge.xf(p + Vector3(0, 1.78, 0), Vector3(0, 30, 6))
	f.cylinder(0.12, 0.12, 0.01, 20, MeshForge.CAPS_BOTH, bowler)
	f.hemisphere(0.08, 16, bowler * MeshForge.xf(Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1, 1.15, 1)))
	# 风衣:从一根钉上垂下的长衣(上窄下宽的扁筒)
	RoomKit.paint(f, RoomKit.COAT)
	var a := TAU * 2.0 / 4.0 + 0.3
	var hook := p + Vector3(cos(a) * 0.13, 1.68, sin(a) * 0.13)
	var path := PackedVector3Array()
	var radii := PackedVector2Array()
	for k in 7:
		var t := k / 6.0
		path.append(hook + Vector3(cos(a) * (0.05 + t * 0.06), -t * 1.0, sin(a) * (0.05 + t * 0.06)))
		radii.append(Vector2(lerpf(0.06, 0.12, t), lerpf(0.10, 0.24, t)))
	f.loft(path, radii, 14, Vector2i(1, 1), Transform3D.IDENTITY, PackedColorArray(), Vector2(-1, -1), Vector3(cos(a), 0, sin(a)))


# —— 角落杂物 ——

static func barrel_radius(y: float) -> float:
	# 桶身半径:两端 0.265,鼓肚 +0.075(动森式胖桶)
	var t := (y - 0.43) / 0.43
	return 0.265 + 0.075 * (1.0 - t * t)


static func barrel_mesh() -> ArrayMesh:
	# 共享车削桶身:20 弧段、15 个轮廓点(底部内陷桶底、鼓肚、桶口凹槽、内陷桶盖)
	return MeshForge.cached("barrel", func(f: MeshForge):
		f.part_space = true
		f.paint(Color.WHITE, 0.7)
		var profile := PackedVector2Array([Vector2(0.0, 0.03), Vector2(0.245, 0.03), Vector2(0.245, 0.0)])
		for y in [0.0, 0.1, 0.22, 0.34, 0.43, 0.52, 0.64, 0.76, 0.86]:
			profile.append(Vector2(barrel_radius(y), y))
		profile.append_array([Vector2(0.245, 0.86), Vector2(0.245, 0.83), Vector2(0.0, 0.83)])
		f.lathe(profile, 20, PackedInt32Array([1, 2, 3, 11, 12, 13])),
		{&"main": WorldMaterials.wood("barrel", true)})


static func hoops_mesh() -> ArrayMesh:
	# 共享桶箍:4 道铁箍
	return MeshForge.cached("barrel_hoops", func(f: MeshForge):
		RoomKit.paint(f, RoomKit.IRON)
		for y in [0.09, 0.27, 0.59, 0.77]:
			var r := barrel_radius(y) + 0.004
			# 圆鼓鼓的箍:截面是半圆
			var hoop := PackedVector2Array()
			for k in 7:
				var a := -PI / 2.0 + PI * k / 6.0
				hoop.append(Vector2(r - 0.004 + cos(a) * 0.01, y + sin(a) * 0.024))
			f.lathe(hoop, 20),
		{&"main": WorldMaterials.prop()})


static func crate_mesh() -> ArrayMesh:
	# 共享货箱(单位立方体,实例按尺寸缩放):箱体 + 12 根边条 + 侧面斜撑
	return MeshForge.cached("crate", func(f: MeshForge):
		f.part_space = true
		f.paint(Color.WHITE, 0.8)
		f.seed = 1.0
		RoomKit.rounded_box(f, Vector3(0.96, 0.96, 0.96), 0.06, MeshForge.xf(Vector3(0, 0.5, 0)))
		var e := 0.11
		for axis in 3:
			for a in [-1, 1]:
				for b in [-1, 1]:
					var size := Vector3(e, e, e)
					var pos := Vector3(0, 0.5, 0)
					size[axis] = 1.0
					var o1 := (axis + 1) % 3
					var o2 := (axis + 2) % 3
					pos[o1] += a * (0.5 - e / 2.0)
					pos[o2] += b * (0.5 - e / 2.0)
					f.seed = 2.0 + axis + a * 0.3 + b * 0.7
					RoomKit.rounded_box(f, size, 0.04, MeshForge.xf(pos), 1)
		for s in [-1, 1]:
			RoomKit.rounded_box(f, Vector3(0.08, 1.15, 0.03), 0.012, MeshForge.xf(Vector3(0, 0.5, s * 0.49), Vector3(0, 0, 45)), 1)
		f.part_space = false,
		{&"main": WorldMaterials.wood("barrel", true)})


static func _clutter(tavern: Node3D) -> void:
	var barrel := barrel_mesh()
	var hoops := hoops_mesh()
	var spots := []
	for i in BARREL_SPOTS.size():
		spots.append([BARREL_SPOTS[i], Vector3(0, rad_to_deg(i * 1.3), 0), Vector3.ONE])
	spots.append([LYING_BARREL[0] - Basis.from_euler(LYING_BARREL[1] * PI / 180.0) * Vector3(0, 0.43, 0), LYING_BARREL[1], Vector3.ONE])
	for keg in KEGS:
		spots.append([keg[0] - Basis.from_euler(keg[1] * PI / 180.0) * Vector3(0, 0.43 * 0.55, 0), keg[1], Vector3.ONE * 0.55])
	for i in spots.size():
		var s: Array = spots[i]
		var body := MeshKit.add(tavern, barrel, null, s[0], s[1], s[2], MeshKit.SHADOW_ON)
		body.name = "Barrel%d" % i
		var ring := MeshKit.add(tavern, hoops, null, s[0], s[1], s[2], MeshKit.SHADOW_ON)
		ring.name = "BarrelHoops%d" % i
	var crate := crate_mesh()
	for i in CRATES.size():
		var c: Array = CRATES[i]
		var inst := MeshKit.add(tavern, crate, null, c[0], Vector3(0, c[2], 0), Vector3.ONE * c[1], MeshKit.SHADOW_ON)
		inst.name = "Crate%d" % i
	RoomKit.add(tavern, "Clutter", "clutter", _clutter_recipe, {&"wood": WorldMaterials.wood("dark", true),
		&"decor": WorldMaterials.decor(), &"prop": WorldMaterials.prop()}, MeshKit.LAYER_SCENERY, false)


static func _clutter_recipe(f: MeshForge) -> void:
	# 躺桶与小酒桶下的垫木、酒桶架;货箱印字;麻袋
	f.surface(&"wood")
	f.part_space = true
	f.paint(Color.WHITE, 0.8)
	var lying: Vector3 = LYING_BARREL[0]
	var axis := Basis.from_euler(LYING_BARREL[1] * PI / 180.0) * Vector3.UP
	for s in [-0.3, 0.3]:
		var p: Vector3 = lying + axis * s
		f.seed = 1.0 + s
		f.prism(Vector3(0.2, 0.1, 0.14), MeshForge.xf(Vector3(p.x, 0.05, p.z), Vector3(0, rad_to_deg(atan2(axis.x, axis.z)) + 90.0, 0)))
	# 小酒桶架:两根横木 + 四条短腿
	for z in [-4.12, -3.80]:
		f.seed = 3.0 + z
		f.box(Vector3(0.6, 0.05, 0.06), MeshForge.xf(Vector3(-3.92, 0.06, z)))
	f.part_space = false
	f.surface(&"decor")
	RoomKit.decor_paint(f, 0, 0.0, Color(1, 1, 1), 0.9)
	var labels := ["stencil_xxx", "stencil_dynamite", "stencil_beans"]
	for i in CRATES.size():
		var c: Array = CRATES[i]
		var size: float = c[1]
		var basis := Basis(Vector3.UP, deg_to_rad(c[2]))
		# 印字贴在朝屋里(−X 或 −Z)的那一面
		var face := basis * Basis(Vector3.UP, PI if i != 1 else -PI / 2.0)
		var center: Vector3 = c[0] + Vector3(0, size * 0.5, 0) + face * Vector3(0, 0, size * 0.5 + 0.004)
		f.quad(Vector2(size * 0.62, size * 0.31), DecorAtlas.rect(labels[i]), Transform3D(face, center))
	RoomKit.decor_paint(f, 4, 0.0, BURLAP)
	for i in SACKS.size():
		var p: Vector3 = SACKS[i]
		var k := 0.9 + 0.1 * (i % 3)
		var lean := Vector3(0.03 * ((i % 2) * 2 - 1), 0, 0.02)
		f.blob(p + Vector3(0, 0.16, 0) * k, [
			[p + Vector3(0, 0.13, 0) * k, Vector3(0.22, 0.14, 0.19) * k, BURLAP],
			[p + Vector3(0, 0.27, 0) * k + lean, Vector3(0.17, 0.11, 0.15) * k, BURLAP],
			[p + Vector3(0, 0.38, 0) * k + lean * 1.6, Vector3(0.07, 0.05, 0.065) * k, BURLAP.darkened(0.1)],
			[p + Vector3(0.02, 0.45, 0) * k + lean * 2.0, Vector3(0.09, 0.04, 0.07) * k, BURLAP.darkened(0.15)],
		], 20, 12, 0.05)
	# 扎口麻绳与前左角的扫帚
	f.surface(&"prop")
	RoomKit.paint(f, RoomKit.ROPE)
	for i in SACKS.size():
		var p: Vector3 = SACKS[i]
		var k := 0.9 + 0.1 * (i % 3)
		var lean := Vector3(0.03 * ((i % 2) * 2 - 1), 0, 0.02)
		f.torus(0.05 * k, 0.068 * k, 14, MeshForge.xf(p + Vector3(0, 0.40, 0) * k + lean * 1.7))
	var broom := Vector3(-4.12, 0.0, 4.12)
	var tilt := MeshForge.xf(broom, Vector3(-9, 45, 9))
	RoomKit.paint(f, [Color(0.48, 0.34, 0.2), 0.7, 0.0])
	f.cylinder(0.014, 0.014, 1.25, 8, MeshForge.CAPS_BOTH, tilt * MeshForge.xf(Vector3(0, 0.62 + 0.25, 0)))
	RoomKit.paint(f, [Color(0.66, 0.54, 0.3), 0.95, 0.0])
	f.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.12, 0.0), Vector2(0.1, 0.12), Vector2(0.05, 0.26), Vector2(0.02, 0.3),
		Vector2(0.0, 0.3)]), 12, PackedInt32Array([1]), tilt * MeshForge.xf(Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.45)))
	RoomKit.paint(f, RoomKit.ROPE)
	f.torus(0.035, 0.05, 12, tilt * MeshForge.xf(Vector3(0, 0.24, 0), Vector3.ZERO, Vector3(1, 1, 0.6)))


# —— 地毯、贴花 ——

static func fit_rug(table_radius: float) -> void:
	# 主毯随牌桌放大 / 复原(Tavern.set_table_radius 调用):decor 材质只有一份,改它的 rug_scale 就行
	WorldMaterials.decor().set_shader_parameter("rug_scale", RoomLayout.main_rug_scale(table_radius))


static func _rugs_recipe(f: MeshForge) -> void:
	# 三块地毯合成一个网格。UV = 相对毯心的米制坐标 (x, z),图案全在 decor 模式 3 里程序绘制(与分辨率无关,近看也清楚)
	for i in RoomLayout.RUGS.size():
		var rug: Array = RoomLayout.RUGS[i]
		var center: Vector2 = rug[0]
		var half := Vector2(rug[1], rug[2]) / 2.0
		RoomKit.decor_paint(f, 3, float(i))
		if rug[3] == "runner":
			_runner_rug(f, center, half)
		else:
			_round_rug(f, center, half, RoomLayout.rug_edge(rug), 96 if rug[3] == "main" else 48)


# 毛绒包边截面:(离外沿向里的距离 / 包边宽, 高度 m);外沿贴地,鼓起 1.9 cm,向里落回毯面
const RUG_RIM_PROFILE := [Vector2(0.0, 0.002), Vector2(0.12, 0.010), Vector2(0.3, 0.017), Vector2(0.55, 0.019),
	Vector2(0.8, 0.015), Vector2(1.0, 0.008)]
const RUG_FLOOR_Y := 0.008       # 毯面高度


static func _round_rug(f: MeshForge, center: Vector2, half: Vector2, rim: float, segs: int) -> void:
	# 椭圆毯:中间一片扇形面 + 一圈凸起的毛绒包边(按截面放样,法线随截面弯下去,外沿自然落进阴影里)
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rings := RUG_RIM_PROFILE.size()
	# 截面各点的外法线(相邻两段斜率平均),(朝外分量, 朝上分量)
	var prof_n: Array[Vector2] = []
	for k in rings:
		var a: Vector2 = RUG_RIM_PROFILE[maxi(k - 1, 0)]
		var b: Vector2 = RUG_RIM_PROFILE[mini(k + 1, rings - 1)]
		var slope := (b.y - a.y) / ((b.x - a.x) * rim)   # 向里每米升高多少
		prof_n.append(Vector2(slope, 1.0).normalized())
	for j in segs:
		var t := TAU * j / segs
		var edge := Vector2(cos(t) * half.x, sin(t) * half.y)
		var out_n := Vector2(cos(t) / half.x, sin(t) / half.y).normalized()   # 椭圆外法线
		for k in rings:
			var pr: Vector2 = RUG_RIM_PROFILE[k]
			var q := edge - out_n * pr.x * rim
			points.append(Vector3(center.x + q.x, pr.y, center.y + q.y))
			var n: Vector2 = prof_n[k]
			normals.append(Vector3(out_n.x * n.x, n.y, out_n.y * n.x).normalized())
			uvs.append(q)
	for j in segs:
		var a := j * rings
		var b := ((j + 1) % segs) * rings
		for k in rings - 1:
			indices.append_array([a + k, b + k, a + k + 1, a + k + 1, b + k, b + k + 1])
	# 毯面:圆心一个点,扇形连到包边内沿(绕序:从上往下看顺时针为正面——decor 双面渲染,背面法线会被翻过去)
	var hub := points.size()
	points.append(Vector3(center.x, RUG_FLOOR_Y, center.y))
	normals.append(Vector3.UP)
	uvs.append(Vector2.ZERO)
	for j in segs:
		indices.append_array([hub, j * rings + rings - 1, ((j + 1) % segs) * rings + rings - 1])
	f.raw(points, normals, uvs, indices)


static func _runner_rug(f: MeshForge, center: Vector2, half: Vector2) -> void:
	# 圆角长条毯(纵向沿 z)+ 两端流苏条;平铺,包边与条纹在着色器里画
	var outline := RoomKit.round_rect(half.x * 2.0, half.y * 2.0, RoomLayout.RUG_CORNER, 4)
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var y := RUG_FLOOR_Y * 0.6
	points.append(Vector3(center.x, y, center.y))
	normals.append(Vector3.UP)
	uvs.append(Vector2.ZERO)
	for p in outline:
		points.append(Vector3(center.x + p.x, y, center.y + p.y))
		normals.append(Vector3.UP)
		uvs.append(p)
	var n := outline.size()
	for k in n:
		indices.append_array([0, 1 + k, 1 + (k + 1) % n])
	# 流苏条:两端直边外各一条(避开圆角)
	var fringe := RoomLayout.FRINGE
	var w := half.x - RoomLayout.RUG_CORNER
	for side in [-1.0, 1.0]:
		var base := points.size()
		for c in [Vector2(-w, half.y), Vector2(w, half.y), Vector2(-w, half.y + fringe), Vector2(w, half.y + fringe)]:
			var q := Vector2(c.x, c.y * side)
			points.append(Vector3(center.x + q.x, y, center.y + q.y))
			normals.append(Vector3.UP)
			uvs.append(q)
		# 绕序:从上往下看顺时针为正面(另一端镜像,绕序反过来)
		if side > 0.0:
			indices.append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
		else:
			indices.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3])
	f.raw(points, normals, uvs, indices)


static func _decals(tavern: Node3D) -> void:
	# 接地贴花:径向渐变,只投到布景层(地板、地毯),酒客与腿脚投不上
	var root := MeshKit.pivot(tavern, Vector3.ZERO, "Decals")
	var spots := [
		[Vector3(0, 0, 0), Vector2(1.3, 1.3)],
		[BARREL_SPOTS[0], Vector2(0.9, 0.9)], [BARREL_SPOTS[1], Vector2(0.9, 0.9)], [BARREL_SPOTS[2], Vector2(0.9, 0.9)],
		[Vector3(3.6, 0, 3.9), Vector2(1.6, 1.1)],
		[Vector3(-3.12, 0, -4.1), Vector2(0.8, 0.7)],
		[Vector3(-2.75, 0, 4.05), Vector2(1.8, 0.9)],
		[COAT_RACK, Vector2(0.7, 0.7)],
		[Vector3(-1.5, 0, -3.45), Vector2(1.4, 0.6)],
		[Vector3(-3.0, 0, -0.6), Vector2(0.4, 3.7)],
		[Vector3(-2.62, 0, -0.7), Vector2(0.7, 3.2)],
		[Vector3(-3.92, 0, -0.6), Vector2(0.35, 3.4)],
	]
	for s in spots:
		var decal := Decal.new()
		decal.size = Vector3(s[1].x, 0.3, s[1].y)
		decal.position = s[0] + Vector3(0, 0.05, 0)
		decal.texture_albedo = WorldMaterials.decal_soft()
		decal.modulate = Color(0, 0, 0, 1)
		decal.albedo_mix = 1.0
		decal.normal_fade = 0.5
		decal.distance_fade_enabled = true
		decal.distance_fade_begin = 9.0
		decal.distance_fade_length = 3.0
		decal.cull_mask = MeshKit.LAYER_SCENERY
		root.add_child(decal)


# —— 壁灯 ——

static func sconce_mesh() -> ArrayMesh:
	# 黄铜蜡烛壁灯(本地 -Z 指向屋里):带串珠边的圆润底板、弯臂、接蜡杯、奶油色蜡烛;不要玻璃
	return MeshForge.cached("sconce", func(f: MeshForge):
		RoomKit.paint(f, RoomKit.BRASS)
		RoomKit.extrude_smooth(f, RoomKit.round_rect(0.11, 0.22, 0.05), 0.018, Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0, 0, -0.009)))
		for k in 8:
			var a := TAU * k / 8.0
			f.sphere(0.009, 8, MeshForge.xf(Vector3(cos(a) * 0.04, sin(a) * 0.09, -0.019)))
		var arm := PackedVector3Array()
		for k in 9:
			var t := k / 8.0
			arm.append(Vector3(0, -0.06 + sin(t * PI) * 0.035 - t * 0.045, -0.015 - t * 0.135))
		f.tube(arm, 0.011, 8)
		f.lathe(PackedVector2Array([Vector2(0.0, -0.016), Vector2(0.016, -0.016), Vector2(0.044, -0.004), Vector2(0.048, 0.004),
			Vector2(0.044, 0.01), Vector2(0.024, 0.006), Vector2(0.0, 0.006)]), 16, PackedInt32Array([1]), MeshForge.xf(Vector3(0, -0.10, -0.15)))
		# 胖蜡烛:圆顶、一滴圆滚滚的蜡泪
		RoomKit.paint(f, RoomKit.WAX)
		f.cylinder(0.02, 0.021, 0.08, 14, MeshForge.CAPS_BOTTOM, MeshForge.xf(Vector3(0, -0.055, -0.15)))
		f.sphere(0.02, 14, MeshForge.xf(Vector3(0, -0.015, -0.15), Vector3.ZERO, Vector3(1, 0.35, 1)))
		f.sphere(0.009, 8, MeshForge.xf(Vector3(0.018, -0.035, -0.15), Vector3.ZERO, Vector3(0.7, 1.4, 0.7))),
		{&"main": WorldMaterials.prop()})


static func _sconces(tavern: Node3D) -> Array:
	var flickers := []
	var mesh := sconce_mesh()
	for i in Tavern.SCONCES.size():
		var root := MeshKit.pivot(tavern, Tavern.SCONCES[i][0], "Sconce%d" % i)   # 名字各不相同(重名会被自动改名,探针按前缀找灯)
		root.rotation.y = Tavern.SCONCES[i][1]
		MeshKit.add(root, mesh, null, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF).layers = MeshKit.LAYER_SCENERY
		var seed := 60.0 + i
		RoomKit.flame(root, Vector2(0.035, 0.07), Vector3(0, 0.025, -0.15), 3.5, seed)
		var light := OmniLight3D.new()
		light.position = Vector3(0, 0.05, -0.2)
		light.light_color = Color(1.0, 0.8, 0.58)
		light.light_energy = 0.65
		light.omni_range = 4.6
		light.light_volumetric_fog_energy = 0.5
		root.add_child(light)
		flickers.append(RoomKit.flicker(light, 4.0, 0.12, seed))
	return flickers


# —— 氛围:暖色 LUT 与分层体积雾 ——

static func atmosphere(tavern: Node3D, environment: Environment) -> void:
	environment.adjustment_color_correction = WorldMaterials.lut()
	environment.volumetric_fog_density = 0.014   # 薄雾:只留一点灯光的空气感
	var smoke := FogVolume.new()
	smoke.name = "SmokeLayer"
	smoke.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	smoke.size = Vector3(8.8, 1.6, 8.8)
	smoke.position = Vector3(0, 3.0, 0)
	var smoke_mat := FogMaterial.new()
	smoke_mat.density = 0.02
	smoke_mat.edge_fade = 0.6
	smoke.material = smoke_mat
	tavern.add_child(smoke)
	var haze := FogVolume.new()
	haze.name = "HearthHaze"
	haze.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	haze.size = Vector3(1.8, 1.4, 1.2)
	haze.position = Vector3(-1.5, 1.0, -3.6)
	var haze_mat := FogMaterial.new()
	haze_mat.density = 0.025
	haze_mat.emission = Color(0.08, 0.036, 0.012)
	haze.material = haze_mat
	tavern.add_child(haze)
