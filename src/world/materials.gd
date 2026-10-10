class_name WorldMaterials
# 程序化材质库:所有 3D 物件共用的材质预设(带缓存,同一预设只创建一次)。


const WOOD_SHADER := preload("res://src/world/shaders/wood.gdshader")
const FELT_SHADER := preload("res://src/world/shaders/felt.gdshader")
const STONE_SHADER := preload("res://src/world/shaders/stone.gdshader")
const FLAME_SHADER := preload("res://src/world/shaders/flame.gdshader")
const PARTICLE_SHADER := preload("res://src/world/shaders/soft_particle.gdshader")
const PARTICLE_ADD_SHADER := preload("res://src/world/shaders/soft_particle_add.gdshader")
const PATRON_SHADER := preload("res://src/world/shaders/patron.gdshader")
const PATRON_EYE_SHADER := preload("res://src/world/shaders/patron_eye.gdshader")
const PROP_SHADER := preload("res://src/world/shaders/prop.gdshader")
const BOTTLE_SHADER := preload("res://src/world/shaders/bottle_glass.gdshader")
const DECOR_SHADER := preload("res://src/world/shaders/decor.gdshader")

# 木材预设:颜色 + 纹理参数。颜色是线性值(以 Vector3 传给 source_color uniform,不做 sRGB 转换)。
# 动森式温馨卡通(2026-10-08):蜂蜜色浅木为主,纹理降噪——年轮、纤维的幅度减小、尺度放大,不要钉头和酒渍,
# 远看是干净的色块,近看留一点手绘感
const WOOD_PRESETS := {
	"floor": {
		"color_dark": Color(0.26, 0.125, 0.048), "color_light": Color(0.45, 0.245, 0.10),
		"scale": 1.0, "ring_frequency": 3.5, "grain_strength": 0.18, "grain_axis": 0, "across_axis": 2,
		"plank_width": 0.26, "plank_length": 2.1, "roughness_base": 0.78, "wear": 0.25,
		# 逐板色差与倒角保留(读得出是木地板);牌桌一圈和门口到吧台、壁炉前的走道磨得稍亮
		"plank_tint": 0.07, "bevel": 1.0, "nails": 0.0, "stains": 0.0,
		"wear_ring": Vector4(0.0, -0.05, 2.15, 0.35), "wear_seg_a": Vector4(-0.35, 4.35, -0.3, 1.8),
		"wear_seg_b": Vector4(-1.0, -1.85, -1.5, -3.1),
		"stain_focus_a": Vector3(-2.6, -0.6, 1.6), "stain_focus_b": Vector3(0.0, 0.0, 2.6),
	},
	"wainscot": {
		# 框芯护墙板(部件空间:CUSTOM0 = 沿墙 u、离地 v、深度),四面墙与吧台台身共用一份;比地板偏红一点的焦糖色
		"color_dark": Color(0.30, 0.13, 0.05), "color_light": Color(0.47, 0.235, 0.10),
		"scale": 1.0, "ring_frequency": 3.0, "grain_strength": 0.16, "grain_axis": 1, "across_axis": 0,
		"roughness_base": 0.74, "wear": 0.15, "varnish": 0.1,
		"pattern": 1, "panel": Vector3(0.08, 0.10, 0.045), "panel_pitch": 0.62, "panel_height": 1.1,
		"bevel": 1.0, "plank_tint": 0.05,
	},
	"ceiling": {
		# 天花板木板:板端都落在 z = 1.5k,藏在梁下
		"color_dark": Color(0.30, 0.16, 0.07), "color_light": Color(0.46, 0.27, 0.12),
		"scale": 1.0, "ring_frequency": 3.0, "grain_strength": 0.16, "grain_axis": 2, "across_axis": 0,
		"plank_width": 0.22, "plank_length": 1.5, "stagger": 0.0, "bevel": 1.0, "plank_tint": 0.05,
		"roughness_base": 0.82, "wear": 0.2,
	},
	"table": {
		# 蜂蜜色台面(2026-10-10):更饱和的琥珀蜂蜜、亮部压一点(吊灯正下方不发白),年轮更疏更柔,清漆薄亮
		"color_dark": Color(0.29, 0.125, 0.04), "color_light": Color(0.47, 0.24, 0.07),
		"scale": 1.0, "ring_frequency": 3.5, "grain_strength": 0.14, "grain_axis": 0, "across_axis": 2,
		"roughness_base": 0.6, "varnish": 0.35, "wear": 0.06,
	},
	"dark": {
		# 线脚、椅子、杂物:奶咖色(不再是近黑的深棕)
		"color_dark": Color(0.17, 0.075, 0.03), "color_light": Color(0.30, 0.15, 0.065),
		"scale": 1.0, "ring_frequency": 4.0, "grain_strength": 0.18, "grain_axis": 0, "across_axis": 2,
		"roughness_base": 0.74, "wear": 0.15,
	},
	"beam": {
		"color_dark": Color(0.22, 0.10, 0.04), "color_light": Color(0.37, 0.19, 0.08),
		"scale": 1.0, "ring_frequency": 2.5, "grain_strength": 0.16, "grain_axis": 0, "across_axis": 1,
		"roughness_base": 0.82, "wear": 0.2,
	},
	"barrel": {
		"color_dark": Color(0.34, 0.16, 0.06), "color_light": Color(0.56, 0.31, 0.13),
		"scale": 1.0, "ring_frequency": 2.5, "grain_strength": 0.16, "grain_axis": 1, "across_axis": 0,
		"plank_width": 0.11, "plank_length": 9.0, "roughness_base": 0.76, "wear": 0.15, "plank_tint": 0.05,
	},
	"turned": {
		# 车削件(桌柱、桌腿):纤维沿 Y(顺着长度走),不分木板;比台面深一档
		"color_dark": Color(0.2, 0.09, 0.035), "color_light": Color(0.36, 0.17, 0.07),
		"scale": 1.0, "ring_frequency": 4.0, "grain_strength": 0.18, "grain_axis": 1, "across_axis": 0,
		"roughness_base": 0.66, "varnish": 0.25, "wear": 0.1,
	},
	"log": {
		"color_dark": Color(0.2, 0.1, 0.04), "color_light": Color(0.40, 0.22, 0.10),
		"scale": 2.0, "ring_frequency": 2.0, "grain_strength": 0.2, "grain_axis": 1, "across_axis": 0,
		"roughness_base": 0.92, "wear": 0.3,
	},
}

# 道具顶点色板(MeshForge 写进顶点,prop 着色器读):名字 -> [sRGB 颜色, 粗糙度, 金属度, glow(自发光, 透光)]。
# albedo 封顶 0.8(自发光的灯泡除外)。动森式:哑光为主,金属件是缎面(粗糙度 ≥ 0.45),黄铜偏奶黄,钢偏蓝灰
const PALETTE := {
	"steel": [Color(0.46, 0.52, 0.64), 0.5, 0.4, Vector2.ZERO],   # 玩具枪的蓝灰缎面钢
	"steel_dark": [Color(0.20, 0.20, 0.27), 0.8, 0.1, Vector2.ZERO],   # 膛口、槽底、弹膛孔:深靛,不是纯黑
	"brass": [Color(0.80, 0.66, 0.36), 0.48, 0.65, Vector2.ZERO],
	"iron": [Color(0.27, 0.26, 0.32), 0.62, 0.35, Vector2.ZERO],
	"wax": [Color(0.80, 0.74, 0.62), 0.62, 0.0, Vector2(0.0, 0.18)],
	"wick": [Color(0.18, 0.13, 0.10), 0.9, 0.0, Vector2.ZERO],
	"enamel_green": [Color(0.32, 0.62, 0.55), 0.55, 0.0, Vector2.ZERO],   # 薄荷青珐琅(灯罩外壁)
	"enamel_red": [Color(0.78, 0.36, 0.32), 0.55, 0.0, Vector2.ZERO],     # 柔红
	"enamel_cream": [Color(0.80, 0.76, 0.64), 0.6, 0.0, Vector2(0.12, 0.0)],
	"bulb": [Color(1.0, 0.9, 0.7), 0.3, 0.0, Vector2(1.0, 0.0)],
	# 道具二次打磨(2026-10-10):玩具枪与小道具的软胶粉彩
	"toy_metal": [Color(0.44, 0.58, 0.80), 0.45, 0.25, Vector2.ZERO],    # 粉彩天蓝缎面金属(玩具枪机身;太浅会在暖光下发白发灰)
	"toy_silver": [Color(0.74, 0.74, 0.78), 0.42, 0.35, Vector2.ZERO],   # 奶油银(转轮、击锤:和机身分出两色,一眼认出转轮)
	"candy_pink": [Color(0.80, 0.40, 0.52), 0.55, 0.0, Vector2.ZERO],    # 糖果粉(握把、枪口帽、击锤钮)
	"candy_cream": [Color(0.80, 0.75, 0.62), 0.6, 0.0, Vector2.ZERO],    # 奶油色(徽章、准星珠,不自发光)
	"brass_soft": [Color(0.80, 0.67, 0.40), 0.6, 0.35, Vector2.ZERO],   # 缎面柔黄铜:桌面嵌线、小道具的金边(比 brass 哑、暖)
	"wax_pink": [Color(0.80, 0.62, 0.62), 0.62, 0.0, Vector2(0.0, 0.18)],    # 粉彩蜡烛:淡粉
	"wax_butter": [Color(0.80, 0.71, 0.48), 0.62, 0.0, Vector2(0.0, 0.18)],  # 粉彩蜡烛:奶黄
}

static var _cache := {}


static func paint_prop(f: MeshForge, entry: String) -> MeshForge:
	# 按色板设 MeshForge 的绘制状态(颜色、粗糙度、金属度、glow)
	var p: Array = PALETTE[entry]
	f.paint(p[0], p[1], p[2])
	f.glow = p[3]
	return f


static func wood(preset: String, part_space := false) -> ShaderMaterial:
	# part_space:给 MeshForge 合并网格用,木纹按部件自己的局部坐标算。变体一律新建,不 duplicate()
	# (实测 duplicate 出来的材质木纹会走样)
	return _cached("wood:%s:%s" % [preset, part_space], func():
		var mat := ShaderMaterial.new()
		mat.shader = WOOD_SHADER
		for key in WOOD_PRESETS[preset]:
			var value = WOOD_PRESETS[preset][key]
			mat.set_shader_parameter(key, Vector3(value.r, value.g, value.b) if value is Color else value)
		mat.set_shader_parameter("use_part_space", part_space)
		mat.set_shader_parameter("surface_noise", SurfaceNoise.texture())
		return mat)


static func patron() -> ShaderMaterial:
	# 所有酒客共用的顶点 PBR 材质(出局褪色走实例参数 fade)
	return _cached("patron", func():
		var mat := ShaderMaterial.new()
		mat.shader = PATRON_SHADER
		return mat)


static func bottle_glass() -> ShaderMaterial:
	# 酒瓶 MultiMesh 共用的不透明假玻璃
	return _cached("bottle_glass", func():
		var mat := ShaderMaterial.new()
		mat.shader = BOTTLE_SHADER
		return mat)


static func patron_eye() -> ShaderMaterial:
	# 所有酒客眼睛共用(眨眼、看向、表情、出局都走实例参数)
	return _cached("patron_eye", func():
		var mat := ShaderMaterial.new()
		mat.shader = PATRON_EYE_SHADER
		return mat)


static func prop() -> ShaderMaterial:
	# 道具共用的顶点 PBR 材质
	return _cached("prop", func():
		var mat := ShaderMaterial.new()
		mat.shader = PROP_SHADER
		return mat)


static func felt() -> ShaderMaterial:
	return _cached("felt", func():
		var mat := ShaderMaterial.new()
		mat.shader = FELT_SHADER
		return mat)


static func felt_sized(felt_radius: float) -> ShaderMaterial:
	# 放大的牌桌(德州):边缘压暗跟着毡面半径走(骗子酒馆桌的 felt() 是 0.82 的毡面配 0.8);刺绣圆环不变
	return _cached("felt:%.3f" % felt_radius, func():
		var mat := ShaderMaterial.new()
		mat.shader = FELT_SHADER
		mat.set_shader_parameter("radius", felt_radius - 0.02)
		return mat)


static func stone(kind: String) -> ShaderMaterial:
	return _cached("stone:" + kind, func():
		var mat := ShaderMaterial.new()
		mat.shader = STONE_SHADER
		mat.set_shader_parameter("surface_noise", SurfaceNoise.texture())
		match kind:
			"fireplace":
				# 行高 0.2、块宽 0.32,网格原点对齐壁炉外框左下前角:砖面边上没有细条
				mat.set_shader_parameter("block_size", RoomLayout.FIRE_COURSE)
				mat.set_shader_parameter("grid_origin", RoomLayout.FIRE_GRID_ORIGIN)
				# 暖砂岩色的圆润石块 + 浅色灰缝(卡通里灰缝比石头亮);熏黑只留炉口一圈
				mat.set_shader_parameter("color_a", Vector3(0.50, 0.31, 0.21))
				mat.set_shader_parameter("color_b", Vector3(0.42, 0.25, 0.17))
				mat.set_shader_parameter("mortar_color", Vector3(0.52, 0.44, 0.34))
				mat.set_shader_parameter("soot", 0.5)
				mat.set_shader_parameter("soot_height", 1.0)
			"plaster":
				# 奶油色灰泥:两色只差一点(远看是一块干净的奶油色),露砖少几块,不要裂缝
				mat.set_shader_parameter("color_a", Vector3(0.58, 0.45, 0.27))
				mat.set_shader_parameter("color_b", Vector3(0.53, 0.41, 0.25))
				mat.set_shader_parameter("brick_color", Vector3(0.52, 0.26, 0.17))
				mat.set_shader_parameter("brick_amount", 0.14)
				mat.set_shader_parameter("crack_amount", 0.0)
				mat.set_shader_parameter("rail_y", RoomLayout.RAIL_TOP)
				mat.set_shader_parameter("ceiling_y", Tavern.ROOM_HEIGHT)
				mat.set_shader_parameter("top_soot", 0.12)
				var halos := []
				for sconce in Tavern.SCONCES:
					halos.append(Vector4(sconce[0].x, sconce[0].y + 0.05, sconce[0].z, 0.0))
				mat.set_shader_parameter("halos", halos)
				mat.set_shader_parameter("halo_count", halos.size())
		return mat)


static func decor() -> ShaderMaterial:
	# 墙饰、外景、烟熏镜、地毯、布料、余烬共用一份(模式写在顶点 UV2.x 上,可以跨物件合并)
	return _cached("decor", func():
		var mat := ShaderMaterial.new()
		mat.shader = DECOR_SHADER
		mat.set_shader_parameter("atlas", DecorAtlas.texture())
		mat.set_shader_parameter("surface_noise", SurfaceNoise.texture())
		mat.set_shader_parameter("rug_sizes", RoomLayout.rug_sizes())
		mat.set_shader_parameter("mirror_size", RoomLayout.MIRROR_SIZE)
		return mat)


static func lut() -> GradientTexture1D:
	# 粉彩暖色 1D 调色表(Environment.adjustment_color_correction,逐通道查表):
	# 黑位抬起并带一点靛紫(最暗处也有色相,不死黑),中间调微暖,高光奶油色、不削顶
	return _cached("lut", func():
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 0.82, 1.0])
		gradient.colors = PackedColorArray([Color(0.045, 0.035, 0.07), Color(0.215, 0.195, 0.215),
			Color(0.53, 0.505, 0.475), Color(0.845, 0.815, 0.765), Color(0.985, 0.96, 0.9)])
		var tex := GradientTexture1D.new()
		tex.gradient = gradient
		tex.width = 256
		return tex)


static func decal_soft() -> GradientTexture2D:
	# 接地贴花:中心 alpha 0.7 的径向黑色渐变
	return _cached("decal_soft", func():
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		gradient.colors = PackedColorArray([Color(0, 0, 0, 0.7), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.0)])
		var tex := GradientTexture2D.new()
		tex.gradient = gradient
		tex.width = 64
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		return tex)


static func flame() -> ShaderMaterial:
	# 所有火焰共用这一份;强度与种子是实例参数(set_instance_shader_parameter),见 Tavern._flame
	return _cached("flame", func():
		var mat := ShaderMaterial.new()
		mat.shader = FLAME_SHADER
		return mat)


static func particle(additive: bool, boost: float, softness: float) -> ShaderMaterial:
	# 混合模式是着色器的编译期 render_mode,只能换着色器而不能用 uniform 切换;同参数共用一份
	return _cached("particle:%s:%s:%s" % [additive, boost, softness], func():
		var mat := ShaderMaterial.new()
		mat.shader = PARTICLE_ADD_SHADER if additive else PARTICLE_SHADER
		mat.render_priority = 1
		mat.set_shader_parameter("emission_boost", boost)
		mat.set_shader_parameter("softness", softness)
		return mat)


static func muzzle_fire(shape: int, billboard: bool, boost: float, softness: float, view_offset := 0.0) -> ShaderMaterial:
	# 枪口焰(加色):shape 1 星形火核、2 沿枪管的冠状十字面片;同参数共用一份(见 soft_particle.gdshaderinc)
	return _cached("muzzle:%d:%s:%s:%s:%s" % [shape, billboard, boost, softness, view_offset], func():
		var mat := ShaderMaterial.new()
		mat.shader = PARTICLE_ADD_SHADER
		mat.render_priority = 1
		mat.set_shader_parameter("emission_boost", boost)
		mat.set_shader_parameter("softness", softness)
		mat.set_shader_parameter("shape", shape)
		mat.set_shader_parameter("billboard", billboard)
		mat.set_shader_parameter("view_offset", view_offset)
		return mat)


static func brass() -> StandardMaterial3D:
	return _cached("brass", func(): return _standard(Color(0.78, 0.56, 0.24), 1.0, 0.32))


static func iron() -> StandardMaterial3D:
	return _cached("iron", func(): return _standard(Color(0.09, 0.09, 0.1), 0.8, 0.55))


static func glass(color: Color) -> StandardMaterial3D:
	return _cached("glass:" + color.to_html(), func():
		var mat := _standard(color, 0.0, 0.06)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.55
		mat.metallic_specular = 0.8
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b) * 0.08
		return mat)


static func enamel(color: Color) -> StandardMaterial3D:
	# 珐琅(灯罩):不是金属,背景近乎全黑时金属会显成一块黑;无底圆锥要看得见内壁,双面渲染
	return _cached("enamel:" + color.to_html(), func():
		var mat := _standard(color, 0.0, 0.5)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		return mat)


static func beer() -> StandardMaterial3D:
	# 啤酒液面:不自发光(原来在暗处像一块发亮的金片)
	return _cached("beer", func(): return _standard(Color(0.78, 0.6, 0.28), 0.0, 0.25))


static func emissive(color: Color, energy: float) -> StandardMaterial3D:
	return _cached("emissive:%s:%.2f" % [color.to_html(), energy], func():
		var mat := _standard(color, 0.0, 0.5)
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = energy
		return mat)


static func clear_cache() -> void:
	_cache = {}


static func _standard(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


static func _cached(key: String, factory: Callable) -> Variant:
	# 返回 Variant:调用方声明的具体材质类型在运行时校验
	if not _cache.has(key):
		_cache[key] = factory.call()
	return _cache[key]
