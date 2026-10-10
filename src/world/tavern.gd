class_name Tavern
extends Node3D
# 常驻 3D 酒馆:房间、牌桌、灯光、环境与道具(全部程序化生成)。
# 布局:牌桌在原点;本机座位朝 -Z 看,对面墙是壁炉,左墙吧台,右墙月光窗。


const ROOM_HALF := 4.5
const ROOM_HEIGHT := 3.4
const WALL_THICKNESS := 0.2
const WAINSCOT_HEIGHT := 1.1
const LAMP_DROP := 1.3
const FIREPLACE_X := -1.5
const WINDOW_Z := -0.9
const WINDOW_SIZE := Vector2(1.3, 1.25)
const WINDOW_BOTTOM := 1.15
const SCONCE_HEIGHT := 2.15
const CANDLE_ENERGY := 0.42   # 一支蜡烛的光(烛台的灯按支数折算)
# 壁灯:[墙内表面上的位置, 朝向房间的偏航角]。补亮房间四周,避免只有牌桌一圈亮
const SCONCES := [
	[Vector3(-1.7, SCONCE_HEIGHT, 4.4), 0.0], [Vector3(1.7, SCONCE_HEIGHT, 4.4), 0.0],
	[Vector3(1.4, SCONCE_HEIGHT, -4.4), PI], [Vector3(3.2, SCONCE_HEIGHT, -4.4), PI],
	[Vector3(-4.4, SCONCE_HEIGHT, 2.0), -PI / 2.0], [Vector3(-4.4, SCONCE_HEIGHT, -3.1), -PI / 2.0],
	[Vector3(4.4, SCONCE_HEIGHT, 1.7), PI / 2.0],
]

var camera_rig: CameraRig
var table_root: Node3D
var environment: Environment

var _lamp_pivot: Node3D
var _table: Node3D                       # 牌桌模型:德州时按半径放大
var _table_decor: Array[Node3D] = []     # 桌面摆设(烛台):德州时隐藏,给筹码与公共牌让位
var _lamp_swing := 0.015
var _flickers: Array = []   # [{"light": Light3D, "base": float, "speed": float, "depth": float, "seed": float}]
var _time := 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	_noise.frequency = 1.0
	_build_environment()
	_build_room()
	_build_table()
	_build_lamp()
	_build_candles()
	_build_fireplace()
	_build_bar()
	_build_window()
	_build_sconces()
	_build_dust()
	table_root = MeshKit.pivot(self, Vector3.ZERO, "TableRoot")
	camera_rig = CameraRig.new()
	add_child(camera_rig)


func _process(delta: float) -> void:
	_time += delta
	for f in _flickers:
		var n := _noise.get_noise_2d(_time * f["speed"], f["seed"])
		f["light"].light_energy = f["base"] * (1.0 + n * f["depth"])
	# 吊灯钟摆:开枪等事件会加大摆幅,随后衰减回微弱摆动
	_lamp_swing = lerpf(_lamp_swing, 0.015, delta * 0.35)
	_lamp_pivot.rotation.x = sin(_time * 1.9) * _lamp_swing
	_lamp_pivot.rotation.z = sin(_time * 1.3 + 1.0) * _lamp_swing * 0.6


func kick_lamp(strength: float) -> void:
	_lamp_swing = maxf(_lamp_swing, strength)


func set_table_radius(radius: float) -> void:
	# 德州放大 / 骗子酒馆复原:桌面、包边、铜嵌条与毡面按半径换网格(桌高、桌柱与腿不变),吊灯聚光跟着放宽,主毯跟着放大
	TableProp.set_radius(_table, radius)
	LampProp.fit_spot(_lamp_pivot, radius)
	RoomProps.fit_rug(radius)


func table_decor() -> Array[Node3D]:
	# 桌面摆设(烛台)的节点:牌桌按它们登记穿模防护形状
	return _table_decor


func set_table_decor_visible(shown: bool) -> void:
	# 烛台连同它们的灯一起显示 / 隐藏;藏起来时留一盏桌沿暖光
	CandlesProp.set_decor_visible(self, _table_decor, shown, _flickers)


# —— 环境 ——

func _build_environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.035, 0.07)   # 深靛夜色(不是纯黑)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# 动森式温馨卡通(2026-10-08):环境光提亮、偏奶油淡紫——暗面不黑、不发灰;暖黄主光仍在灯下
	environment.ambient_light_color = Color(0.42, 0.42, 0.56)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.95
	environment.tonemap_white = 6.0
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_strength = 0.9
	environment.glow_bloom = 0.02
	# 阈值高于漫反射能达到的亮度:只有火焰、灯泡等自发光会泛光,平放在灯下的牌不会糊成一团白
	environment.glow_hdr_threshold = 1.25
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	environment.ssao_enabled = true
	environment.ssao_radius = 0.6
	environment.ssao_intensity = 1.0
	environment.ssao_light_affect = 0.12   # 接触暗部还在(墙角、椅脚),但又软又浅
	# 不开 SSIL(屏幕空间间接光):实测内部 1080p 下约 3 毫秒/帧,开关前后画面几乎看不出差别
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.05
	environment.volumetric_fog_albedo = Color(0.9, 0.86, 0.82)
	environment.volumetric_fog_anisotropy = 0.5
	environment.volumetric_fog_length = 14.0
	environment.volumetric_fog_ambient_inject = 0.04
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 0.92    # 低对比:柔和的卡通画面
	environment.adjustment_saturation = 1.04
	RoomProps.atmosphere(self, environment)   # 暖色 LUT 与分层体积雾
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)


# —— 房间 ——

func _build_room() -> void:
	RoomShell.build(self)   # 墙地、线脚与木构(src/world/room/)


# —— 牌桌 ——

func _build_table() -> void:
	_table = TableProp.build(self)


# —— 吊灯 ——

func _build_lamp() -> void:
	_lamp_pivot = LampProp.build(self, ROOM_HEIGHT, _flickers)


# —— 烛台 ——

func _build_candles() -> void:
	_table_decor = CandlesProp.build(self, _flickers)


func _flame(parent: Node3D, size: Vector2, pos: Vector3, intensity: float, seed: float) -> MeshInstance3D:
	# 火焰公告板:共用一份材质,强度与种子按实例设定
	var flame := MeshKit.add(parent, MeshKit.quad(size), WorldMaterials.flame(), pos)
	flame.set_instance_shader_parameter("intensity", intensity)
	flame.set_instance_shader_parameter("seed", seed)
	return flame


# —— 壁炉 ——

func _build_fireplace() -> void:
	_flickers.append_array(FireplaceSet.build(self))   # 石体、台梁、柴、炉具、牛骷髅与炉火(src/world/room/)


# —— 吧台 ——

func _build_bar() -> void:
	BarSet.build(self)   # 台身、后吧、烟熏镜、吧凳、酒瓶与啤酒杯、吧台灯(src/world/room/)


# —— 门窗与陈设 ——

func _build_window() -> void:
	OpeningsSet.build(self)   # 月光窗、窗帘、窗外夜景与月光;前墙弹簧门与街景(src/world/room/)


func _build_sconces() -> void:
	# 墙饰、钢琴、衣帽架、角落杂物、地毯、贴花与黄铜蜡烛壁灯(src/world/room/)
	_flickers.append_array(RoomProps.build(self))


# —— 浮尘 ——

func _build_dust() -> void:
	add_child(Fx.dust_motes(Vector3(0, 1.6, 0), Vector3(1.6, 1.0, 1.6)))
	add_child(Fx.dust_motes(Vector3(2.6, 1.6, -0.6), Vector3(1.6, 0.9, 0.7)))
