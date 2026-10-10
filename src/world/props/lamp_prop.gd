class_name LampProp
# 牌桌上方的吊灯:黄铜吊顶碗、柔黄铜链条(MultiMesh,一次 draw)、颈箍、蘑菇帽式双层灯罩(外壁柔红珐琅带奶油波点、内壁奶油色微微自发光)、
# 罩口黄铜珠边、灯泡(自发光的球)。全部挂在 LampPivot 下(开枪踢灯时整盏摆动);灯罩与链条都不投影。
# 两盏灯(投影的聚光与补光)是 LampPivot 的直接子节点:性能探针按这个名字找灯。


const DROP := 1.3               # 颈部在枢轴下方
const MOUTH_Y := -1.499         # 罩口(最低点 MOUTH_Y − BEAD = −1.51,世界高度约 1.89,与原来的灯罩一样高)
const MOUTH_RADIUS := 0.36
const BEAD := 0.011             # 罩口珠边(动森式:胖胖的一圈黄铜)
const SPOT_Y := -1.45
const FILL_Y := -1.35
const LIARS_SPOT_ANGLE := 52.0  # Godot 的 spot_angle 是半角;骗子酒馆桌的聚光
const EDGE_REACH := 0.15        # 放大的桌:聚光在桌面高度照到桌沿外这么远
const SOFT_EDGE_DEG := 2.5      # 再加一点半影
const LINK_PITCH := 0.03
const CANOPY_DEPTH := 0.03
const COLLAR_TOP := -1.27
const DOT_ROWS := [Vector2(0.13, 12), Vector2(0.38, 9)]   # 波点:(从罩口沿外壁的弧长比例, 个数);偏下两圈,座位机位看得到
const DOT_RADIUS := 0.028


static func build(parent: Node3D, top: float, flickers: Array) -> Node3D:
	var pivot := MeshKit.pivot(parent, Vector3(0, top, 0), "LampPivot")
	var lamp := MeshKit.add(pivot, MeshForge.cached("prop:lamp", lamp_recipe, {&"metal": WorldMaterials.prop()}), null,
		Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF)
	lamp.name = "LampMesh"
	var chain := MultiMeshInstance3D.new()
	chain.name = "LampChain"
	chain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = MeshForge.cached("prop:chain_link", link_recipe, {&"metal": WorldMaterials.prop()})
	mm.instance_count = link_count()
	for i in mm.instance_count:
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, PI / 2.0 * (i % 2)), Vector3(0, -CANOPY_DEPTH - i * LINK_PITCH - 0.012, 0)))
	chain.multimesh = mm
	pivot.add_child(chain)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, SPOT_Y, 0)
	spot.rotation_degrees = Vector3(-90, 0, 0)
	spot.light_color = Color(1.0, 0.84, 0.66)
	spot.light_energy = 3.5
	spot.spot_range = 3.4
	spot.spot_angle = LIARS_SPOT_ANGLE
	spot.spot_angle_attenuation = 0.7
	spot.shadow_enabled = true
	spot.shadow_caster_mask = MeshKit.LAYER_WORLD   # 窗户层只给月光投影
	spot.shadow_blur = 2.5
	spot.shadow_opacity = 0.72   # 卡通:影子又浅又软
	spot.light_volumetric_fog_energy = 2.2
	pivot.add_child(spot)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, FILL_Y, 0)
	fill.light_color = Color(1.0, 0.78, 0.55)
	fill.light_energy = 0.8
	fill.omni_range = 7.5
	fill.light_volumetric_fog_energy = 0.3
	pivot.add_child(fill)
	flickers.append({"light": spot, "base": spot.light_energy, "speed": 0.7, "depth": 0.04, "seed": 3.0})
	return pivot


static func link_count() -> int:
	return int((-COLLAR_TOP - CANOPY_DEPTH) / LINK_PITCH) + 1


static func spot_angle_for(spot_height: float, radius: float) -> float:
	# 桌面高度上照到桌沿外 EDGE_REACH 的半角;骗子酒馆桌保持原来的角度
	var needed := rad_to_deg(atan((radius + EDGE_REACH) / (spot_height - SeatLayout.TABLE_TOP))) + SOFT_EDGE_DEG
	return maxf(LIARS_SPOT_ANGLE, needed) if radius > SeatLayout.TABLE_RADIUS + 0.001 else LIARS_SPOT_ANGLE


static func fit_spot(pivot: Node3D, radius: float) -> void:
	for spot in pivot.get_children().filter(func(n: Node) -> bool: return n is SpotLight3D):
		spot.spot_angle = spot_angle_for((pivot.transform * spot.transform).origin.y, radius)


static func _p(f: MeshForge, entry: String) -> void:
	WorldMaterials.paint_prop(f, entry)


static func shade_profile() -> PackedVector2Array:
	# 钟形罩外壁 (r, y),自罩口往上到颈部
	# 更饱满的圆顶钟形(卡通)
	# 二次打磨(2026-10-10):肩部更鼓的圆顶,像一顶胖胖的蘑菇帽
	var radii := [MOUTH_RADIUS, 0.357, 0.338, 0.294, 0.230, 0.164, 0.112, 0.080, 0.064]
	var heights := [0.0, 0.07, 0.22, 0.41, 0.59, 0.75, 0.88, 0.95, 1.0]   # 罩口到颈部的比例
	var out := PackedVector2Array()
	for k in radii.size():
		out.append(Vector2(radii[k], lerpf(MOUTH_Y, -DROP, heights[k])))
	return out


static func _on_profile(profile: PackedVector2Array, t: float) -> Array:
	# 外壁轮廓上按弧长比例 t 取点:[点 (r, y), 外法线 (r, y)]
	var total := 0.0
	for k in profile.size() - 1:
		total += profile[k].distance_to(profile[k + 1])
	var want := total * t
	for k in profile.size() - 1:
		var seg := profile[k].distance_to(profile[k + 1])
		if want <= seg or k == profile.size() - 2:
			var d := (profile[k + 1] - profile[k]).normalized()
			# 轮廓自下而上、半径收小:方向转 −90° 就是朝外朝上的法线
			return [profile[k].lerp(profile[k + 1], clampf(want / seg, 0.0, 1.0)), Vector2(d.y, -d.x)]
		want -= seg
	return [profile[0], Vector2(1, 0)]


static func lamp_recipe(f: MeshForge) -> void:
	var xf := MeshForge.xf
	f.surface(&"metal")
	# 吊顶碗
	_p(f, "brass")
	f.lathe(PackedVector2Array([Vector2(0.0, -CANOPY_DEPTH), Vector2(0.03, -CANOPY_DEPTH + 0.002), Vector2(0.06, -0.016),
		Vector2(0.075, -0.004), Vector2(0.075, 0.0)]), 32)
	# 钟形罩:外壁柔红珐琅、内壁奶油色(微微自发光,灯泡照亮的那一圈)
	var outer := shade_profile()
	_p(f, "enamel_red")
	f.lathe(outer, 48)
	# 外壁两圈奶油色圆点(交错排开,半嵌在罩面里的扁圆片):动森小店里那种波点灯罩
	_p(f, "candy_cream")
	var dot := PackedVector2Array([Vector2(DOT_RADIUS, -0.002), Vector2(DOT_RADIUS * 0.9, 0.0018), Vector2(DOT_RADIUS * 0.55, 0.0036),
		Vector2(0.0, 0.0042)])
	for row in DOT_ROWS.size():
		var spec: Vector2 = DOT_ROWS[row]
		var at := _on_profile(outer, spec.x)
		var at_point: Vector2 = at[0]
		var at_normal: Vector2 = at[1]
		for k in int(spec.y):
			var a := TAU * (k + 0.5 * row) / spec.y
			var dir := Vector3(sin(a), 0, cos(a))
			var normal := (dir * at_normal.x + Vector3(0, at_normal.y, 0)).normalized()
			# 车削的小圆顶(轴 +Y 转到罩面法线),底边埋进罩壁 2 mm
			var basis := Basis.looking_at(-normal, Vector3.UP) * Basis(Vector3.RIGHT, PI / 2.0)
			f.lathe(dot, 12, PackedInt32Array(), Transform3D(basis, dir * at_point.x + Vector3(0, at_point.y, 0)))
	var inner := PackedVector2Array()
	for k in range(outer.size() - 1, -1, -1):
		inner.append(outer[k] + Vector2(-0.003, 0.002 if k > 0 else 0.003))
	_p(f, "enamel_cream")
	f.lathe(inner, 48)
	# 罩口黄铜珠边(最低点 MOUTH_Y − BEAD)
	_p(f, "brass")
	f.torus(MOUTH_RADIUS - BEAD, MOUTH_RADIUS + BEAD, 64, xf.call(Vector3(0, MOUTH_Y, 0)))
	# 颈箍与灯座
	f.lathe(PackedVector2Array([Vector2(0.0, -DROP - 0.03), Vector2(0.03, -DROP - 0.03), Vector2(0.038, -DROP - 0.012),
		Vector2(0.066, -DROP - 0.004), Vector2(0.066, -DROP + 0.004), Vector2(0.05, -DROP + 0.01), Vector2(0.05, -DROP + 0.022),
		Vector2(0.03, COLLAR_TOP), Vector2(0.0, COLLAR_TOP)]), 32, PackedInt32Array([1, 3, 4, 6]))
	f.cylinder(0.024, 0.024, 0.06, 20, MeshForge.CAPS_BOTH, xf.call(Vector3(0, -DROP - 0.06, 0)))
	# 灯泡:自发光的球(能量 = prop 着色器的 emission_energy)
	_p(f, "bulb")
	f.sphere(0.055, 24, xf.call(Vector3(0, -DROP - 0.13, 0), Vector3.ZERO, Vector3(1, 1.1, 1)))


static func link_recipe(f: MeshForge) -> void:
	# 椭圆链节:竖着的扁环(4 边截面,约 90 面);相邻两节在 build 里转 90°
	f.surface(&"metal")
	# 缎面柔黄铜的胖链节(原来是深靛铁链):更圆、更粗一点
	_p(f, "brass_soft")
	var path := PackedVector3Array()
	for k in 11:
		var a := TAU * k / 10.0
		path.append(Vector3(sin(a) * 0.0105, cos(a) * 0.0170, 0))
	f.tube(path, 0.0038, 5)
