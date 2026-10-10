class_name DdzJokerFaces
# 斗地主的大王 / 小王牌面:在离屏 SubViewport 里画 DdzJokerPainter(和德州牌面同尺寸、同 MSAA、同出血底),
# 抓成带 mipmap 的贴图。接进德州牌面那条管线:CardFaces.texture 遇到 SMALL / BIG 两个牌面值转到这里,
# Card3D.material_for 给它们和德州牌一样的单张材质(背面是德州牌背),悬停大图(CardPreview)照常取得到。
# 牌面值 SMALL / BIG 落在德州(8–59)与骗子酒馆(-1–3)之外;斗地主的牌 id 用 face_kind() 换成牌面值(52 张走 DdzHand.poker_card)。
# 两张一批画完(约两帧),只在进斗地主时(等待厅、牌桌、说明书翻到斗地主那本)才生成;无头模式下是退化的纯色小纹理。


const SMALL := 60
const BIG := 61
const KINDS := [SMALL, BIG]
const FALLBACK_TINT := {SMALL: Color(0.2, 0.22, 0.42), BIG: Color(0.86, 0.26, 0.4)}


class Notifier:
	extends RefCounted
	signal built


# 测试钩子:替换「渲染这两张」,func(tree: SceneTree, kinds: Array) -> Array[Image](可以是协程)
static var batch_renderer := Callable()

static var _textures := {}
static var _fallbacks := {}                # 还没生成时的纯色占位(每种一份,不每次新建)
static var _notifier: Notifier = null
static var _building := false
static var _generation := 0


static func is_kind(value: Variant) -> bool:
	return value is int and (value == SMALL or value == BIG)


static func face_kind(card: int) -> int:
	# 斗地主牌 id(0–53)→ 3D / 2D 牌面值:王换成 SMALL / BIG,其余是德州牌值;不是牌返回 CardFaces.BACK
	if not DdzHand.is_card(card):
		return CardFaces.BACK
	if card == DdzHand.SMALL_JOKER:
		return SMALL
	if card == DdzHand.BIG_JOKER:
		return BIG
	return DdzHand.poker_card(card)


static func texture_for(card: int) -> Texture2D:
	# 斗地主牌 id 的牌面纹理(2D 手牌条、HUD 小牌、说明书);不是牌时是德州牌背
	var kind := face_kind(card)
	return PokerFaces.back_texture() if kind == CardFaces.BACK else CardFaces.texture(kind)


static func texture(kind: int) -> Texture2D:
	if _textures.has(kind):
		return _textures[kind]
	return _fallback(kind)


static func is_built() -> bool:
	return _textures.size() == KINDS.size()


static func faces_ready() -> bool:
	# 斗地主要的全部牌面(德州 52 张 + 两张王)都有了
	return is_built() and PokerFaces.is_built()


static func built_signal() -> Signal:
	if _notifier == null:
		_notifier = Notifier.new()
	return _notifier.built


static func clear() -> void:
	_textures = {}
	_fallbacks = {}
	_notifier = null
	_building = false
	_generation += 1


static func build(host: Node) -> void:
	if is_built():
		return
	if host == null or not host.is_inside_tree():
		push_error("DdzJokerFaces.build:host 必须在场景树里")
		return
	var tree := host.get_tree()
	var generation := _generation
	if _building:
		while _building and generation == _generation:
			await tree.process_frame
		return
	_building = true
	if batch_renderer.is_null() and DisplayServer.get_name() == "headless":
		for kind in KINDS:
			_textures[kind] = _fallback(kind)
	else:
		var images: Array = []
		if batch_renderer.is_null():
			images = await _render(tree)
		else:
			images = await batch_renderer.call(tree, KINDS)
		if generation != _generation:
			return
		for i in KINDS.size():
			_textures[KINDS[i]] = to_texture(images[i] if i < images.size() else null, KINDS[i])
	_building = false
	Card3D.refresh_materials()
	built_signal().emit()


static func to_texture(image: Image, kind: int) -> Texture2D:
	# 抓到的图生成 mipmap 再上传(2D 小牌要从 320 像素缩小很多倍);空图退化成纯色
	if image == null or image.is_empty():
		return _fallback(kind)
	image.generate_mipmaps()
	_fallbacks[kind] = ImageTexture.create_from_image(image)
	return _fallbacks[kind]


static func _render(tree: SceneTree) -> Array:
	var holder := Node.new()
	holder.name = "DdzJokerFacesBatch"
	var viewports: Array[SubViewport] = []
	for kind in KINDS:
		var vp := SubViewport.new()
		vp.size = PokerFaces.SIZE
		vp.transparent_bg = true
		vp.msaa_2d = PokerFaces.VIEWPORT_MSAA
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		vp.add_child(CardFaces.bleed_backdrop(Vector2(PokerFaces.SIZE)))
		var painter := DdzJokerPainter.new(DdzJokerPainter.BIG if kind == BIG else DdzJokerPainter.SMALL)
		painter.scale = Vector2.ONE * PokerFaces.BAKE_SCALE
		vp.add_child(painter)
		holder.add_child(vp)
		viewports.append(vp)
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


static func _fallback(kind: int) -> Texture2D:
	if _fallbacks.has(kind):
		return _fallbacks[kind]
	var image := Image.create(PokerFaces.FALLBACK_SIZE, PokerFaces.FALLBACK_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(CardFaces.PAPER.lerp(FALLBACK_TINT.get(kind, CardFaces.INK), PokerFaces.FALLBACK_TINT))
	image.generate_mipmaps()
	_fallbacks[kind] = ImageTexture.create_from_image(image)
	return _fallbacks[kind]
