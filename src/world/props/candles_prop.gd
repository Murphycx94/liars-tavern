class_name CandlesProp
# 桌上的两个烛台:每个烛台一份合并网格(糖果粉花瓣碟、带托盘的黄铜烛杯、粉彩蜡烛身带熔口与蜡泪、溢出杯沿的蜡池、微弯的烛芯;
# prop 材质,投影)、每支一片火焰公告板(共用火焰材质,种子各不相同)、一盏 OmniLight3D(烛台枢轴的直接子节点)。
# 枢轴名 Candles0 / Candles1:性能探针按 Candles 前缀找烛光,两个各自命名免得重名被自动改名。
# 德州时整组藏起来(连同灯),换一盏桌沿暖光(TableRimLight)。


const RADIUS := 0.7
# [角度, 支数, 种子]:角度避开各座位的左轮摆放位置(3 人局 240° 座位的枪原本会穿过第二个烛台)
const SPECS := [[PI * 0.76, 3, 1.0], [PI * 1.31, 2, 7.0]]
const DISH_RADIUS := 0.085
const CUP_RADIUS := 0.031       # 动森式:烛杯、蜡烛都更胖更矮(CUP_SCALE 把原来的杯形整体放大)
const CUP_SCALE := CUP_RADIUS / 0.026
const CUP_TOP := 0.028          # 烛杯上沿(烛台局部,原点在桌面)
const WAX_BASE := 0.024
const WAX_RADIUS := 0.0235
const FLAME_SIZE := Vector2(0.03, 0.06)
const FLAME_ABOVE := 0.024      # 火焰中心在蜡烛顶上方
const LIGHT_SHARE := 0.75       # 每个烛台的灯 = 一支蜡烛的光 × 支数 × 这个比例
const FELT := SeatLayout.FELT_TOP - SeatLayout.TABLE_TOP
const DISH_THICKNESS := 0.0075  # 花瓣碟的厚度(烛杯底在 FELT + 0.004,压进碟里)
const DISH_PETALS := 8
const WAX_COLORS := ["wax", "wax_pink", "wax_butter"]


static func candle_offset(i: int, count: int) -> Vector3:
	return Vector3(cos(i * 2.1) * 0.043, 0, sin(i * 2.1) * 0.043) if count > 1 else Vector3.ZERO


static func candle_height(i: int, seed: float) -> float:
	return 0.06 + 0.035 * ((i * 37 + int(seed)) % 3)


static func top_height() -> float:
	# 最高那支蜡烛的火焰顶(牌桌坐标):穿模防护里头从烛台上面拱过去按它算
	return SeatLayout.TABLE_TOP + WAX_BASE + 0.06 + 0.035 * 2 + FLAME_ABOVE + FLAME_SIZE.y * 0.5


static func build(parent: Node3D, flickers: Array) -> Array[Node3D]:
	var holders: Array[Node3D] = []
	for k in SPECS.size():
		var spec: Array = SPECS[k]
		var count: int = spec[1]
		var seed: float = spec[2]
		var holder := MeshKit.pivot(parent, SeatLayout.direction(spec[0]) * RADIUS + Vector3(0, SeatLayout.TABLE_TOP, 0),
			"Candles%d" % k)
		holders.append(holder)
		MeshKit.add(holder, MeshForge.cached("prop:candle_holder:%d:%d" % [count, int(seed)],
			func(f: MeshForge): holder_recipe(f, count, seed), {&"metal": WorldMaterials.prop()}), null).name = "Holder"
		var flame_sum := Vector3.ZERO
		for i in count:
			var flame_pos := candle_offset(i, count) + Vector3(0, WAX_BASE + candle_height(i, seed) + FLAME_ABOVE, 0)
			flame_sum += flame_pos
			var flame := MeshKit.add(holder, MeshKit.quad(FLAME_SIZE), WorldMaterials.flame(), flame_pos)
			flame.set_instance_shader_parameter("intensity", 4.0)
			flame.set_instance_shader_parameter("seed", seed + i)
		# 每个烛台一盏灯(每支一盏会在近处的脸上叠出亮斑):放在这簇火焰的平均位置上方
		var light := OmniLight3D.new()
		light.position = flame_sum / count + Vector3(0, 0.02, 0)
		light.light_color = Color(1.0, 0.74, 0.48)
		light.light_energy = Tavern.CANDLE_ENERGY * count * LIGHT_SHARE
		light.omni_range = 2.4
		light.light_volumetric_fog_energy = 0.4
		holder.add_child(light)
		flickers.append({"light": light, "base": light.light_energy, "speed": 6.0, "depth": 0.35, "seed": seed * 13.0})
	return holders


static func set_decor_visible(tavern: Node3D, holders: Array[Node3D], shown: bool, flickers: Array) -> void:
	# 烛台连同它们的灯一起显示 / 隐藏;藏起来时桌沿与酒客的脸少了暖色补光,
	# 换一盏桌心上方、不投影、像烛光一样微微起伏的暖光(第一次藏的时候才建)
	for holder in holders:
		holder.visible = shown
	var rim := tavern.get_node_or_null("TableRimLight") as OmniLight3D
	if rim == null and not shown:
		rim = OmniLight3D.new()
		rim.name = "TableRimLight"
		rim.position = Vector3(0, SeatLayout.TABLE_TOP + 0.35, 0)
		rim.light_color = Color(1.0, 0.74, 0.48)
		rim.light_energy = 0.9
		rim.omni_range = 2.8
		rim.light_volumetric_fog_energy = 0.0
		tavern.add_child(rim)
		flickers.append({"light": rim, "base": rim.light_energy, "speed": 3.0, "depth": 0.08, "seed": 91.0})
	if rim != null:
		rim.visible = not shown


static func _p(f: MeshForge, entry: String) -> void:
	WorldMaterials.paint_prop(f, entry)


static func dish_outline() -> PackedVector2Array:
	# 8 瓣的圆润花形:半径在 0.071–0.085 之间起伏,瓣尖是圆的、瓣间是浅浅的弧形凹口
	var out := PackedVector2Array()
	for k in DISH_PETALS * 6:
		var a := TAU * k / (DISH_PETALS * 6)
		var petal := pow(absf(cos(a * DISH_PETALS / 2.0)), 0.7)
		out.append(Vector2(cos(a), sin(a)) * (DISH_RADIUS - 0.014 * (1.0 - petal)))
	return out


static func holder_recipe(f: MeshForge, count: int, seed: float) -> void:
	var xf := MeshForge.xf
	f.surface(&"metal")
	# 花瓣形糖果粉瓷碟(外沿 r 0.085,8 瓣,圆弧倒角的软边;平放在毡面上,底面贴毡不封)
	_p(f, "candy_pink")
	f.extrude(dish_outline(), DISH_THICKNESS, 0.0028, Transform3D(Basis(Vector3.RIGHT, -PI / 2.0),
		Vector3(0, FELT + DISH_THICKNESS / 2.0, 0)), Vector2i(0, 1), 40.0, 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed * 101.0) + count
	for i in count:
		var at := candle_offset(i, count)
		var height := candle_height(i, seed)
		var cup: Transform3D = xf.call(at)
		# 带托盘的烛杯
		_p(f, "brass")
		var k := CUP_SCALE
		f.lathe(PackedVector2Array([Vector2(0.0, FELT + 0.004), Vector2(CUP_RADIUS, FELT + 0.004), Vector2(CUP_RADIUS, FELT + 0.0065),
			Vector2(0.021 * k, FELT + 0.0075), Vector2(0.0185 * k, FELT + 0.011), Vector2(0.0195 * k, CUP_TOP - 0.004),
			Vector2(0.0215 * k, CUP_TOP - 0.001), Vector2(0.021 * k, CUP_TOP), Vector2(0.0175 * k, CUP_TOP), Vector2(0.0, CUP_TOP - 0.003)]),
			12, PackedInt32Array([1, 2, 7]), cup)
		# 蜡烛身:半径按种子抖 ±0.4 mm;顶上一圈 5 mm 的圆肩,中心微微下凹(软软的玩具蜡烛);
		# 每支一种粉彩蜡色(奶油 / 淡粉 / 奶黄,按种子轮换),蜡泪与蜡池同色
		_p(f, WAX_COLORS[(i + int(seed)) % WAX_COLORS.size()])
		var r := WAX_RADIUS + rng.randf_range(-0.0004, 0.0004)
		var top := WAX_BASE + height
		var from := f.mark()
		var body := PackedVector2Array([Vector2(r, WAX_BASE)])
		for s in 5:
			var a := PI / 2.0 * s / 4.0
			body.append(Vector2(r - 0.005 + cos(a) * 0.005, top - 0.005 + sin(a) * 0.005))
		body.append_array([Vector2(r - 0.009, top - 0.0004), Vector2(0.0, top - 0.0015)])
		f.lathe(body, 14, PackedInt32Array(), cup)
		# 顶端 2 cm 渐亮:蜡被火苗从里面照透(取代整支蜡烛自发光,那是蜡烛削顶的原因之一)
		f.paint_glow(from, func(p: Vector3) -> Vector2:
			return Vector2(clampf((p.y - (top - 0.02)) / 0.02, 0.0, 1.0) * 0.06, 0.18))
		# 两道蜡泪(末端带泪珠)
		for d in 2:
			var a := rng.randf_range(0.0, TAU) + d * PI * 0.8
			var dir := Vector3(cos(a), 0, sin(a))
			var length := rng.randf_range(0.015, 0.035)
			var path := PackedVector3Array()
			for s in 5:
				var t := s / 4.0
				path.append(at + dir * (r + 0.0006 - t * 0.0002) + Vector3(0, top + 0.001 - t * length, 0)
					+ Vector3(-dir.z, 0, dir.x) * sin(t * 2.0) * 0.0015)
			f.tube(path, 0.0028, 5)
			f.sphere(0.0038, 6, xf.call(path[4] + dir * 0.0004 + Vector3(0, -0.001, 0), Vector3.ZERO, Vector3(1, 1.3, 1)))
		# 溢出杯沿的蜡池
		f.lathe(PackedVector2Array([Vector2(r - 0.001, CUP_TOP - 0.001), Vector2(0.0225 * k, CUP_TOP - 0.0012),
			Vector2(0.0232 * k, CUP_TOP + 0.0004), Vector2(0.0205 * k, CUP_TOP + 0.002), Vector2(r, CUP_TOP + 0.0025)]), 12,
			PackedInt32Array(), cup)
		# 烛芯:微弯的细管
		_p(f, "wick")
		var bend := Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0)).normalized() * 0.0018
		f.tube(PackedVector3Array([at + Vector3(0, top - 0.002, 0), at + Vector3(0, top + 0.003, 0) + bend * 0.3,
			at + Vector3(0, top + 0.006, 0) + bend]), 0.0016, 4)
