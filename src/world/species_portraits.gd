class_name SpeciesPortraits
# 物种头像(主菜单与等待厅的 SpeciesChip / SpeciesPicker 用):texture(i) 取第 i 个物种的头像。
# 头像是 3D 烘焙的:主菜单出来后在一个独立的 SubViewport 里摆全部物种(10 位酒客),正交相机拍一排头,读回后
# 每格叠在物种主色的圆片上,切成一张张图。烘好之前(以及无头运行时)用回退圆片(SpeciesChip 在上面叠物种首字);
# SpeciesChip 轮询 is_built(),烘好后换图。


const SIZE := 72                 # 回退圆片的边长(像素);头像按控件大小缩放
const RIM := 3.0                 # 圆片描边宽度
const RIM_DARKEN := 0.45
const UNASSIGNED_COLOR := Color(0.36, 0.33, 0.3)   # 还没有形象(挑选中…)的灰圆片
const CELL := 192                # 烘焙时每个头像的像素
# 动森式 2 头身(头 ×1.95、帽子更宽)之后格子再放大:Q 版 0.8 / 1.37,最初 SPACING / VIEW_SIZE 0.62、HEAD_HEIGHT 1.34
const SPACING := 1.1             # 烘焙台上酒客之间的间距(米):等于每格宽度(正交相机按高度定宽,8:1 的画面每格 VIEW_SIZE 宽)
const HEAD_HEIGHT := 1.43        # 坐姿下头心离地约 1.27 m,礼帽顶 ≈1.8 m,镜头对准头心上方一点
const VIEW_SIZE := 1.1           # 正交相机竖直方向拍多少米(一个大头加帽子、羊驼耳朵)
# 各物种主色(sRGB,取自子项目② §2 造型表的皮毛色),只用于回退圆片;下标与 Species.IDS 一致
const FALLBACK_COLORS := [
	Color(0.80, 0.40, 0.14),   # 狐狸
	Color(0.36, 0.21, 0.11),   # 熊
	Color(0.76, 0.47, 0.45),   # 猪
	Color(0.46, 0.47, 0.52),   # 猫
	Color(0.42, 0.55, 0.28),   # 乌龟
	Color(0.78, 0.66, 0.50),   # 羊驼
	Color(0.42, 0.26, 0.14),   # 猴子
	Color(0.24, 0.46, 0.22),   # 鳄鱼
	Color(0.50, 0.66, 0.40),   # 熊猫:竹青(黑白的头在白圆片上不显,换成竹子的颜色)
	Color(0.42, 0.60, 0.76),   # 企鹅:冰蓝(藏青的头在藏青圆片上不显)
]

static var _textures: Array = []   # 下标 = 物种;build 之后才有
static var _fallbacks := {}        # 物种下标(含 UNASSIGNED)-> 回退圆片
static var _baked := false         # 是真头像(3D 烘焙)而不是回退圆片


static var _building := false


static func build(host: Node) -> void:
	# 菜单出来之后调用一次,不必 await(协程:烘焙要等几帧)。无头运行没有渲染,直接用回退圆片
	if is_built() or _building:
		return
	if DisplayServer.get_name() == "headless":
		_textures = []
		for i in Species.count():
			_textures.append(fallback_texture(i))
		_baked = false
		return
	_building = true
	var stage := _make_stage()
	host.add_child(stage)
	var viewport: SubViewport = stage.get_child(0)
	for i in 4:
		await host.get_tree().process_frame   # 酒客摆好姿势、看向镜头
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var strip := viewport.get_texture().get_image()
	stage.queue_free()
	_building = false
	if not is_instance_valid(host):
		return
	strip.convert(Image.FORMAT_RGBA8)
	var textures := []
	for i in Species.count():
		var disc := fallback_texture(i).get_image()
		disc.resize(CELL, CELL, Image.INTERPOLATE_BILINEAR)
		disc.blend_rect(strip, Rect2i(i * CELL, 0, CELL, CELL), Vector2i.ZERO)
		textures.append(ImageTexture.create_from_image(disc))
	_textures = textures
	_baked = true


static func _make_stage() -> Node:
	# 烘焙台:独立世界、透明背景,全部酒客一字排开面朝镜头;主光 + 补光 + 轮廓光,色调与酒馆一致
	var stage := Node.new()
	stage.name = "PortraitStage"
	var viewport := SubViewport.new()
	viewport.size = Vector2i(CELL * Species.count(), CELL)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	stage.add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.45, 0.42)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15   # 粉彩调色板更亮,曝光比写实版(1.32)低一点,白脸不发白
	env.tonemap_white = 6.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = VIEW_SIZE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.position = Vector3(0, HEAD_HEIGHT, 3.0)
	viewport.add_child(camera)
	for spec in [[Vector3(-35, -25, 0), Color(1.0, 0.86, 0.7), 1.6], [Vector3(-10, 30, 0), Color(0.75, 0.8, 1.0), 0.5],
			[Vector3(-20, 180, 0), Color(1.0, 0.8, 0.6), 1.2]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = spec[0]
		light.light_color = spec[1]
		light.light_energy = spec[2]
		viewport.add_child(light)
	for i in Species.count():
		var patron := Patron.new(i)
		patron.position = Vector3((i - (Species.count() - 1) * 0.5) * SPACING, 0, 0)
		patron.rotation.y = PI
		viewport.add_child(patron)
		patron.look_at_point(camera.position + Vector3(patron.position.x, 0, 0))
	return stage


static func is_built() -> bool:
	return _textures.size() == Species.count()


static func is_baked() -> bool:
	# 假:头像是回退圆片,SpeciesChip 要在上面叠物种首字
	return _baked


static func texture(index: int) -> Texture2D:
	if is_built() and Species.is_valid(index):
		return _textures[index]
	return fallback_texture(index)


static func fallback_color(index: int) -> Color:
	return FALLBACK_COLORS[index] if Species.is_valid(index) else UNASSIGNED_COLOR


static func fallback_texture(index: int) -> Texture2D:
	# 物种主色的圆片加深色描边,边缘按像素覆盖率抗锯齿;非法下标(含 UNASSIGNED)是灰圆片
	var key := Species.sanitize(index)
	if _fallbacks.has(key):
		return _fallbacks[key]
	var fill := fallback_color(key)
	var rim := fill.darkened(RIM_DARKEN)
	var image := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var center := Vector2(SIZE, SIZE) / 2.0
	var radius := SIZE / 2.0 - 0.5
	for y in SIZE:
		for x in SIZE:
			var d := (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(center)
			var color := rim if d > radius - RIM else fill
			color.a = clampf(radius - d + 0.5, 0.0, 1.0)
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_fallbacks[key] = texture
	return texture


static func clear() -> void:
	_textures = []
	_fallbacks = {}
	_baked = false
	_building = false
