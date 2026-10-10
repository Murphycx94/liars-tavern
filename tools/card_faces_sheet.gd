extends SceneTree
# 骗子酒馆牌面验收图(需要窗口渲染,不能 --headless):
#   liar_faces_full.png    5 张全尺寸(360×520)一排:牌背、Q、K、A、鬼
#   liar_foil_full.png     烫金遮罩(180×260)
#   liar_faces_small.png   按 2D 界面的实际尺寸(目标牌 54×78、说明书 40×58,带 mipmap 的线性过滤)缩小,1:1 像素,再 ×3 最近邻放大
# 用法:godot --path . -s tools/card_faces_sheet.gd -- --out=/tmp/liar_faces


const GAP := 8
const BACKDROP := Color(0.09, 0.07, 0.06)
const SMALL_SIZES := [Vector2i(54, 78), Vector2i(40, 58)]   # 桌面 HUD 的目标牌 / 说明书小牌
const SMALL_ZOOM := 3

var opts := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var out_dir: String = opts.get("out", OS.get_user_data_dir() + "/liar_faces")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var host := Node.new()
	root.add_child(host)
	var started := Time.get_ticks_msec()
	await CardFaces.build(host)
	print("built in %d ms" % (Time.get_ticks_msec() - started))
	if CardFaces.texture(CardFaces.BACK).get_width() != CardFaces.SIZE.x:
		push_error("牌面没有生成出来(需要窗口渲染)")
		quit(1)
		return
	_save(_row(func(i: int) -> Image: return CardFaces.face_array().get_layer_data(i), CardFaces.SIZE),
		out_dir + "/liar_faces_full.png")
	_save(_row(func(i: int) -> Image:
		var img := CardFaces.foil_array().get_layer_data(i)
		img.convert(Image.FORMAT_RGBA8)
		return img, CardFaces.FOIL_SIZE), out_dir + "/liar_foil_full.png")
	var small := await _small()
	_save(small, out_dir + "/liar_faces_small.png")
	small.resize(small.get_width() * SMALL_ZOOM, small.get_height() * SMALL_ZOOM, Image.INTERPOLATE_NEAREST)
	_save(small, out_dir + "/liar_faces_small_x3.png")
	quit()


func _row(layer_image: Callable, card: Vector2i) -> Image:
	var count := CardFaces.LAYERS.size()
	var sheet := Image.create(count * (card.x + GAP) + GAP, card.y + GAP * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(BACKDROP)
	for i in count:
		var img: Image = layer_image.call(i)
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(GAP + i * (card.x + GAP), GAP))
	return sheet


func _small() -> Image:
	var count := CardFaces.LAYERS.size()
	var width := 0
	var height := GAP
	for s: Vector2i in SMALL_SIZES:
		width = maxi(width, count * (s.x + GAP) + GAP)
		height += s.y + GAP
	var vp := SubViewport.new()
	vp.size = Vector2i(width, height)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.size = Vector2(vp.size)
	vp.add_child(backdrop)
	var y := GAP
	for s: Vector2i in SMALL_SIZES:
		for i in count:
			var rect := TextureRect.new()
			rect.texture = CardFaces.texture(CardFaces.LAYERS[i])
			rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rect.size = Vector2(s)
			rect.position = Vector2(GAP + i * (s.x + GAP), y)
			vp.add_child(rect)
		y += s.y + GAP
	root.add_child(vp)
	for i in 3:
		await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	vp.queue_free()
	return image


func _save(image: Image, path: String) -> void:
	var err := image.save_png(path)
	print("saved %s %dx%d %s" % [path, image.get_width(), image.get_height(), error_string(err)])
