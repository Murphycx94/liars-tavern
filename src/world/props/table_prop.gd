class_name TableProp
# 牌桌:台面(封闭圆盘,桌面在 r ≤ 半径 + 0.03 内严格平整,外缘椭圆枕头边)、裙板、瓶状桌柱、四条 cabriole 弯腿与圆爪足、
# 两道齐平的细黄铜嵌线、毡面。台面、裙板、嵌条与毡面跟着桌面半径重建(按半径缓存网格);桌柱与腿不随半径变。
# 节点:Table(桌根,原点在桌心地面)下 TableTop(木纹 table / dark + prop 三个 surface)、TableBase(turned + prop)、
# Felt(毡面材质,不投影;放在桌根原点,毡面着色器的 obj_pos 以桌心为原点)。


const SEGMENTS := 96
const FLAT_REACH := 0.03       # 桌面在 r ≤ 半径 + FLAT_REACH 内严格平整(爪心落在 r≈0.92±0.058)
const NOSE := 0.016            # 圆鼻边横向半径:外沿在 半径 + 0.046(骗子酒馆桌 0.996)
const NOSE_DROP := 0.021       # 圆鼻边竖向半径(椭圆,比横向长:桌沿看起来更软更厚)
const THICKNESS := 0.045       # 台面厚度
const FELT_THICKNESS := SeatLayout.FELT_TOP - SeatLayout.TABLE_TOP
const FELT_EDGE := 0.003       # 毡面边缘圆角
# 两道细黄铜嵌线的内外半径(相对桌面半径),只高出台面 0.5 mm:细而柔的点缀,不再是一整条亮带
const INLAYS := [Vector2(-0.0095, -0.0055), Vector2(0.0035, 0.0075)]
const LEG_COUNT := 4


static func build(parent: Node3D) -> Node3D:
	var table := MeshKit.pivot(parent, Vector3.ZERO, "Table")
	MeshKit.add(table, top_mesh(SeatLayout.TABLE_RADIUS), null).name = "TableTop"
	MeshKit.add(table, MeshForge.cached("prop:table_base", base_recipe,
		{&"turned": WorldMaterials.wood("turned", true), &"metal": WorldMaterials.prop()}), null).name = "TableBase"
	var felt := MeshKit.add(table, felt_mesh(SeatLayout.TABLE_RADIUS), felt_material(SeatLayout.TABLE_RADIUS),
		Vector3.ZERO, Vector3.ZERO, Vector3.ONE, MeshKit.SHADOW_OFF)
	felt.name = "Felt"
	return table


static func set_radius(table: Node3D, radius: float) -> void:
	# 桌面、包边、铜嵌条与毡面按半径换网格(缓存);桌面高度、桌柱与腿不变
	(table.get_node("TableTop") as MeshInstance3D).mesh = top_mesh(radius)
	var felt: MeshInstance3D = table.get_node("Felt")
	felt.mesh = felt_mesh(radius)
	felt.material_override = felt_material(radius)


static func felt_radius(radius: float) -> float:
	# 毡面外沿到桌沿的木边宽度不变(骗子酒馆桌 0.95 → 0.82)
	return SeatLayout.FELT_RADIUS + (radius - SeatLayout.TABLE_RADIUS)


static func felt_material(radius: float) -> ShaderMaterial:
	return WorldMaterials.felt() if is_equal_approx(radius, SeatLayout.TABLE_RADIUS) \
		else WorldMaterials.felt_sized(felt_radius(radius))


static func top_mesh(radius: float) -> ArrayMesh:
	return MeshForge.cached("prop:table_top:%.3f" % radius, func(f: MeshForge): top_recipe(f, radius),
		{&"table": WorldMaterials.wood("table"), &"dark": WorldMaterials.wood("dark"), &"metal": WorldMaterials.prop()})


static func felt_mesh(radius: float) -> ArrayMesh:
	return MeshForge.cached("prop:table_felt:%.3f" % radius, func(f: MeshForge): felt_recipe(f, radius))


static func profile(radius: float) -> PackedVector2Array:
	# 台面车削轮廓 (r, y),自下而上(底面从桌心往外 → 外缘 → 圆鼻边 → 桌面回到桌心),封闭圆盘
	var top := SeatLayout.TABLE_TOP
	var flat := radius + FLAT_REACH
	var outer := flat + NOSE
	# 下沿 1.6 cm 圆角;圆鼻边是竖向拉长的椭圆(横 NOSE、竖 NOSE_DROP),像软软的枕头边
	# (外沿半径不变,酒客躯干离桌沿的净空不受影响)
	var pts := PackedVector2Array([Vector2(0.0, top - THICKNESS), Vector2(radius - 0.06, top - THICKNESS)])
	for k in 6:
		var a := -PI / 2.0 + PI / 2.0 * k / 5.0
		pts.append(Vector2(outer - 0.016 + cos(a) * 0.016, top - THICKNESS + 0.016 + sin(a) * 0.016))
	pts.append(Vector2(outer, top - NOSE_DROP))
	for k in range(1, 11):
		var a := PI / 2.0 * k / 10.0
		pts.append(Vector2(flat + cos(a) * NOSE, top - NOSE_DROP + sin(a) * NOSE_DROP))
	pts.append(Vector2(radius - 0.15, top))
	pts.append(Vector2(0.0, top))
	return pts


static func top_recipe(f: MeshForge, radius: float) -> void:
	var top := SeatLayout.TABLE_TOP
	f.surface(&"table")
	f.lathe(profile(radius), SEGMENTS)
	# 裙板(深色木,底边一道串珠线脚):挂在台面下,跟着半径走
	f.surface(&"dark")
	f.lathe(PackedVector2Array([Vector2(radius - 0.09, top - THICKNESS - 0.001), Vector2(radius - 0.09, top - 0.125),
		Vector2(radius - 0.068, top - 0.125), Vector2(radius - 0.062, top - 0.121), Vector2(radius - 0.059, top - 0.114),
		Vector2(radius - 0.062, top - 0.107), Vector2(radius - 0.07, top - 0.103), Vector2(radius - 0.07, top - THICKNESS - 0.001)]),
		SEGMENTS, PackedInt32Array([1, 2, 6]))
	# 两道齐平的细嵌线:只高出台面 0.5 mm(爪子就搭在这一圈上);缎面柔黄铜,远看是一圈淡淡的金边
	f.surface(&"metal")
	WorldMaterials.paint_prop(f, "brass_soft")
	for inlay: Vector2 in INLAYS:
		var r0 := radius + inlay.x
		var r1 := radius + inlay.y
		# 只有顶面一条环带(0.5 mm 高的侧墙看不见,省下面数给圆爪足和枕头边)
		f.lathe(PackedVector2Array([Vector2(r1, top + 0.0005), Vector2(r0, top + 0.0005)]), SEGMENTS)


static func felt_recipe(f: MeshForge, radius: float) -> void:
	# 车削垫:顶面 = FELT_TOP,边缘 3 mm 圆角,外沿 = 毡面半径 − 2 mm
	var top := SeatLayout.TABLE_TOP
	var outer := felt_radius(radius) - 0.002
	var pts := PackedVector2Array([Vector2(0.0, top), Vector2(outer, top), Vector2(outer, top + FELT_THICKNESS - FELT_EDGE)])
	for k in range(1, 5):
		var a := PI / 2.0 * k / 4.0
		pts.append(Vector2(outer - FELT_EDGE + cos(a) * FELT_EDGE, top + FELT_THICKNESS - FELT_EDGE + sin(a) * FELT_EDGE))
	pts.append(Vector2(0.0, SeatLayout.FELT_TOP))
	f.lathe(pts, SEGMENTS, PackedInt32Array([1]))


static func base_recipe(f: MeshForge) -> void:
	# 瓶状桌柱(y 0.10–0.66,三道环)+ 柱头托盘 + 四条 cabriole 弯腿(朝 45° + k·90°,落在座位之间)+ 黄铜柱箍与圆爪足
	var top := SeatLayout.TABLE_TOP
	f.surface(&"turned")
	f.part_space = true
	f.lathe(PackedVector2Array([Vector2(0.0, 0.06), Vector2(0.15, 0.06), Vector2(0.155, 0.10), Vector2(0.13, 0.13),
		Vector2(0.10, 0.15), Vector2(0.115, 0.17), Vector2(0.09, 0.19), Vector2(0.12, 0.27), Vector2(0.13, 0.34),
		Vector2(0.11, 0.42), Vector2(0.075, 0.49), Vector2(0.092, 0.51), Vector2(0.07, 0.53), Vector2(0.06, 0.58),
		Vector2(0.07, 0.62), Vector2(0.095, 0.64), Vector2(0.085, 0.652), Vector2(0.12, 0.668), Vector2(0.16, 0.69),
		Vector2(0.21, 0.70), Vector2(0.22, 0.71), Vector2(0.22, top - THICKNESS - 0.001), Vector2(0.0, top - THICKNESS - 0.001)]),
		40, PackedInt32Array([1, 2, 4, 5, 6, 11, 12, 15, 16, 20, 21]))
	for k in LEG_COUNT:
		var yaw := PI / 4.0 + k * PI / 2.0
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var path := PackedVector3Array()
		var radii := PackedVector2Array()
		# 动森式:腿更粗更圆
		var stations := [[0.10, 0.17, 0.062], [0.17, 0.165, 0.06], [0.24, 0.14, 0.055], [0.29, 0.10, 0.044],
			[0.33, 0.067, 0.034], [0.365, 0.048, 0.027], [0.395, 0.042, 0.026], [0.415, 0.046, 0.026]]
		for st in stations:
			path.append(dir * st[0] + Vector3(0, st[1], 0))
			radii.append(Vector2(st[2], st[2] * 0.8))
		f.seed = float(k)
		f.loft(path, radii, 12, Vector2i(1, 1), Transform3D.IDENTITY, PackedColorArray(), Vector2(-1, -1), Vector3.UP)
	f.part_space = false
	f.seed = 0.0
	f.surface(&"metal")
	WorldMaterials.paint_prop(f, "brass")
	f.lathe(PackedVector2Array([Vector2(0.086, 0.650), Vector2(0.104, 0.653), Vector2(0.108, 0.660), Vector2(0.104, 0.667),
		Vector2(0.086, 0.670)]), 40)
	for k in LEG_COUNT:
		var yaw := PI / 4.0 + k * PI / 2.0
		var dir := Vector3(sin(yaw), 0, cos(yaw))
		var side := Vector3(dir.z, 0, -dir.x)
		# 圆滚滚的小爪足(代替爪球足,动物酒馆的桌子):扁圆的掌垫 + 前面三颗趾豆
		f.sphere(0.036, 12, MeshForge.xf(dir * 0.418 + Vector3(0, 0.0245, 0), Vector3(0, rad_to_deg(yaw), 0), Vector3(1.0, 0.64, 1.12)))
		for toe in 3:
			var at := dir * (0.452 - absf(toe - 1) * 0.008) + side * (toe - 1) * 0.0215
			f.sphere(0.0128, 8, MeshForge.xf(at + Vector3(0, 0.0128, 0), Vector3.ZERO, Vector3(1.0, 0.95, 1.1)))
