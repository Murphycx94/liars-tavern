class_name BombCatFaces
# 炸弹猫的牌面(规格 §3.1):13 种牌 + 牌背在离屏 SubViewport 里矢量绘制(BombCatFacePainter),抓成两份数组纹理:
# 牌面 face_array()(层序见 layer(),0 = 牌背)与烫金遮罩 foil_array(),给 3D 牌共用的一份材质(card.gdshader v2,
# 牌型走实例参数 face);2D 界面(手牌条、说明书、偷看浮层)用单张贴图 texture(id)。
# 只在进入炸弹猫(等待厅、牌桌、说明书翻到这本)时才生成,一批画完(14 张牌面 + 14 张遮罩,约两帧);
# 生成完重绑材质并发出 built 信号。无头模式(哑渲染器不出图)下退化为按牌着色的小纯色纹理,逻辑照常运行。
# 静态缓存(纹理、材质、牌堆侧面材质)由 main.gd 的 _exit_tree 调 clear() 释放。


const SIZE := Vector2i(320, 462)            # 与 Card3D 同比例(0.12 × 0.1733)
const FOIL_SIZE := Vector2i(160, 231)
const FALLBACK_SIZE := 8
const BACK := ""                            # 牌背(未知的牌)
const LAYERS := [BACK, BombCatCard.BOMB, BombCatCard.DEFUSE, BombCatCard.SKIP, BombCatCard.PASS_TURNS,
	BombCatCard.PEEK, BombCatCard.SHUFFLE, BombCatCard.BEG, BombCatCard.NOPE, BombCatCard.SNACK_FISH,
	BombCatCard.SNACK_YARN, BombCatCard.SNACK_CARROT, BombCatCard.SNACK_BANANA, BombCatCard.SNACK_CACTUS]
const CARD_SHADER := preload("res://src/world/shaders/card.gdshader")
const VIEWPORT_MSAA := Viewport.MSAA_4X
# 牌堆侧面:奶油纸边 + 细密的纸页线(三平面贴图,只看得到侧面)
const EDGE_PAPER := Color(0.93, 0.87, 0.74)
const EDGE_LINE := Color(0.7, 0.6, 0.46)
const EDGE_LINES := 16                      # 侧面贴图一格里的纸页线数
const EDGE_STEP := 0.0011                   # 一张牌的厚度(米,= CardTable.PILE_STEP):纸页线的间距


class Notifier:
	extends RefCounted
	signal built


# 每种牌的主色(动森式粉彩,2026-10-10):牌名横幅、插画内框;退化纹理也用它。TINTS 是插画圆盘与说明框的浅底
const ACCENTS := {
	BACK: Color(0.17, 0.45, 0.48),
	BombCatCard.BOMB: Color(0.42, 0.38, 0.52),
	BombCatCard.DEFUSE: Color(0.3, 0.7, 0.58),
	BombCatCard.SKIP: Color(0.38, 0.6, 0.9),
	BombCatCard.PASS_TURNS: Color(0.96, 0.58, 0.36),
	BombCatCard.PEEK: Color(0.62, 0.48, 0.86),
	BombCatCard.SHUFFLE: Color(0.24, 0.64, 0.68),
	BombCatCard.BEG: Color(0.95, 0.52, 0.66),
	BombCatCard.NOPE: Color(0.9, 0.38, 0.4),
	BombCatCard.SNACK_FISH: Color(0.9, 0.62, 0.36),
	BombCatCard.SNACK_YARN: Color(0.84, 0.46, 0.68),
	BombCatCard.SNACK_CARROT: Color(0.96, 0.56, 0.26),
	BombCatCard.SNACK_BANANA: Color(0.9, 0.72, 0.24),
	BombCatCard.SNACK_CACTUS: Color(0.4, 0.68, 0.42),
}
const TINTS := {
	BACK: Color(0.85, 0.94, 0.94),
	BombCatCard.BOMB: Color(0.92, 0.9, 0.97),
	BombCatCard.DEFUSE: Color(0.87, 0.97, 0.93),
	BombCatCard.SKIP: Color(0.88, 0.93, 1.0),
	BombCatCard.PASS_TURNS: Color(1.0, 0.92, 0.85),
	BombCatCard.PEEK: Color(0.94, 0.9, 1.0),
	BombCatCard.SHUFFLE: Color(0.86, 0.96, 0.96),
	BombCatCard.BEG: Color(1.0, 0.9, 0.93),
	BombCatCard.NOPE: Color(1.0, 0.9, 0.89),
	BombCatCard.SNACK_FISH: Color(1.0, 0.93, 0.85),
	BombCatCard.SNACK_YARN: Color(0.99, 0.9, 0.96),
	BombCatCard.SNACK_CARROT: Color(1.0, 0.92, 0.84),
	BombCatCard.SNACK_BANANA: Color(1.0, 0.96, 0.83),
	BombCatCard.SNACK_CACTUS: Color(0.9, 0.97, 0.88),
}

static var _textures := {}
static var _face_array: Texture2DArray = null
static var _foil_array: Texture2DArray = null
static var _fallback_faces: Texture2DArray = null
static var _fallback_foil: Texture2DArray = null
static var _material: ShaderMaterial = null
static var _edge_material: StandardMaterial3D = null
static var _notifier: Notifier = null
static var _building := false
static var _generation := 0


static func layer(id: String) -> int:
	# 牌在数组纹理里的层;不认识的牌(含牌背)给 0 层
	return maxi(LAYERS.find(id), 0)


static func layer_count() -> int:
	return LAYERS.size()


static func is_built() -> bool:
	return _textures.size() == LAYERS.size()


static func built_signal() -> Signal:
	# 同 PokerFaces:没有静态信号,由一个 RefCounted 代发;请连接节点的方法
	if _notifier == null:
		_notifier = Notifier.new()
	return _notifier.built


static func texture(id: String) -> Texture2D:
	# 2D 界面用的单张牌面;还没生成时是按牌着色的小纯色块
	if _textures.has(id):
		return _textures[id]
	return _fallback_texture(id)


static func face_array() -> Texture2DArray:
	if _face_array != null:
		return _face_array
	if _fallback_faces == null:
		var images: Array[Image] = []
		for id in LAYERS:
			images.append(_fallback_image(id))
		_fallback_faces = _array(images)
	return _fallback_faces


static func foil_array() -> Texture2DArray:
	if _foil_array != null:
		return _foil_array
	if _fallback_foil == null:
		var images: Array[Image] = []
		for id in LAYERS:
			var image := Image.create(FALLBACK_SIZE, FALLBACK_SIZE, true, Image.FORMAT_R8)
			image.fill(Color.BLACK)
			images.append(image)
		_fallback_foil = _array(images)
	return _fallback_foil


static func material() -> ShaderMaterial:
	# 所有炸弹猫的 3D 牌共用这一份(不 duplicate):牌型、高亮都是实例参数
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = CARD_SHADER
		_bind(_material)
	return _material


static func edge_material() -> StandardMaterial3D:
	# 牌堆 / 弃牌堆那块按张数缩放的盒子:侧面是一层层纸边
	if _edge_material == null:
		var image := Image.create(4, EDGE_LINES * 4, true, Image.FORMAT_RGBA8)
		for y in image.get_height():
			var line := y % 4 == 0
			for x in image.get_width():
				image.set_pixel(x, y, EDGE_LINE if line else EDGE_PAPER)
		image.generate_mipmaps()
		_edge_material = StandardMaterial3D.new()
		_edge_material.albedo_texture = ImageTexture.create_from_image(image)
		_edge_material.uv1_triplanar = true
		_edge_material.uv1_scale = Vector3(8.0, 1.0 / (EDGE_LINES * EDGE_STEP), 8.0)
		_edge_material.roughness = 0.85
		_edge_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return _edge_material


static func clear() -> void:
	# 退出与测试用:丢掉纹理、材质与信号源;进行中的生成发现代数变了就作废
	_textures = {}
	_face_array = null
	_foil_array = null
	_fallback_faces = null
	_fallback_foil = null
	_material = null
	_edge_material = null
	_notifier = null
	_building = false
	_generation += 1


static func build(host: Node) -> void:
	# 只需调用一次;并发调用时等第一次完成。host 只用来找场景树:视口挂在根节点下
	if is_built():
		return
	if host == null or not host.is_inside_tree():
		push_error("BombCatFaces.build:host 必须在场景树里")
		return
	var tree := host.get_tree()
	var generation := _generation
	if _building:
		while _building and generation == _generation:
			await tree.process_frame
		return
	_building = true
	if DisplayServer.get_name() == "headless":
		for id in LAYERS:
			_textures[id] = _fallback_texture(id)
		_finish()
		return
	var faces: Array = await _render(tree, false)
	if generation != _generation:
		return
	var foils: Array = await _render(tree, true)
	if generation != _generation:
		return
	var face_images: Array[Image] = []
	var foil_images: Array[Image] = []
	var complete := true
	for i in LAYERS.size():
		var image: Image = faces[i]
		var mask: Image = foils[i]
		if image == null or image.is_empty():
			_textures[LAYERS[i]] = _fallback_texture(LAYERS[i])
			complete = false
		else:
			image.generate_mipmaps()
			_textures[LAYERS[i]] = ImageTexture.create_from_image(image)
			face_images.append(image)
		if mask == null or mask.is_empty():
			complete = false
		else:
			mask.convert(Image.FORMAT_R8)
			mask.resize(FOIL_SIZE.x, FOIL_SIZE.y, Image.INTERPOLATE_LANCZOS)
			mask.generate_mipmaps()
			foil_images.append(mask)
	# 数组要求各层同尺寸:任意一张抓图为空就整组用替代图
	if complete:
		_face_array = _array(face_images)
		_foil_array = _array(foil_images)
	_finish()


static func _finish() -> void:
	_building = false
	if _material != null:
		_bind(_material)
	built_signal().emit()


static func _bind(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("faces", face_array())
	mat.set_shader_parameter("foil", foil_array())


static func _render(tree: SceneTree, foil: bool) -> Array:
	var holder := Node.new()
	holder.name = "BombCatFacesBatch"
	var viewports: Array[SubViewport] = []
	for id in LAYERS:
		var vp := SubViewport.new()
		vp.size = SIZE
		vp.transparent_bg = not foil   # 圆角外透明(遮罩是黑底)
		vp.msaa_2d = VIEWPORT_MSAA
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		if not foil:
			vp.add_child(CardFaces.bleed_backdrop(Vector2(SIZE)))   # 圆角外透明像素的 RGB 写成牌边色,mipmap 不发黑
		var painter := BombCatFacePainter.new(id, foil)
		vp.add_child(painter)
		holder.add_child(vp)
		viewports.append(vp)
	# 延迟挂到根节点:调用者可能正处在 _ready 里
	tree.root.add_child.call_deferred(holder)
	await RenderingServer.frame_post_draw
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var images := []
	for vp in viewports:
		images.append(vp.get_texture().get_image() if is_instance_valid(vp) else null)
	if is_instance_valid(holder):
		holder.queue_free()
	await tree.process_frame
	return images


static func _array(images: Array[Image]) -> Texture2DArray:
	var array := Texture2DArray.new()
	array.create_from_images(images)
	return array


static func accent(id: String) -> Color:
	return ACCENTS.get(id, ACCENTS[BACK])


static func tint(id: String) -> Color:
	return TINTS.get(id, TINTS[BACK])


static func _fallback_image(id: String) -> Image:
	var image := Image.create(FALLBACK_SIZE, FALLBACK_SIZE, true, Image.FORMAT_RGBA8)
	image.fill(accent(id) if id == BACK else CardFaces.PAPER.lerp(accent(id), 0.45))
	return image


static func _fallback_texture(id: String) -> Texture2D:
	var image := _fallback_image(id)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
