extends SceneTree
# 斗地主两张王的验收图(需要窗口渲染,不能 --headless):
#   ddz_jokers.png       大王、小王全尺寸(PokerFaces.SIZE),旁边放 K♠、Q♥、J♣ 对照同一家族的画风
#   ddz_jokers_small.png 按手牌条(66×96)与说明书(38×55)的尺寸缩小(带 mipmap 的线性过滤),再 ×3 最近邻放大看清楚
# 用法:godot --path . -s tools/ddz_faces_sheet.gd -- --out=/tmp/ddz_faces


const GAP := 8
const BACKDROP := Color(0.09, 0.07, 0.06)
const SMALL_SIZES := [Vector2i(66, 96), Vector2i(38, 55)]
const ZOOM := 3

var opts := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var out_dir: String = opts.get("out", OS.get_user_data_dir() + "/ddz_faces")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var host := Node.new()
	root.add_child(host)
	for i in 20:
		await process_frame
	await PokerFaces.build(host)
	await DdzJokerFaces.build(host)
	var big := DdzJokerFaces.texture(DdzJokerFaces.BIG)
	if big.get_width() != PokerFaces.SIZE.x:
		push_error("王的牌面没有生成出来(需要窗口渲染)")
		quit(1)
		return
	print("joker size=%s mipmaps=%s" % [big.get_size(), big.get_image().has_mipmaps()])
	var faces: Array[Texture2D] = [DdzJokerFaces.texture(DdzJokerFaces.BIG), DdzJokerFaces.texture(DdzJokerFaces.SMALL),
		PokerFaces.texture(PokerCard.make(13, 0)), PokerFaces.texture(PokerCard.make(12, 1)), PokerFaces.texture(PokerCard.make(11, 3))]
	_save(_row(faces, PokerFaces.SIZE), out_dir + "/ddz_jokers.png")
	var rows: Array[Image] = []
	for size in SMALL_SIZES:
		var small := _row(faces, size)
		small.resize(small.get_width() * ZOOM, small.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
		rows.append(small)
	var w := 0
	var h := 0
	for img in rows:
		w = maxi(w, img.get_width())
		h += img.get_height() + GAP
	var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(BACKDROP)
	var y := 0
	for img in rows:
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(0, y))
		y += img.get_height() + GAP
	_save(sheet, out_dir + "/ddz_jokers_small.png")
	PokerFaces.clear()
	DdzJokerFaces.clear()
	Card3D.clear_materials()
	quit()


func _row(faces: Array[Texture2D], size: Vector2i) -> Image:
	var sheet := Image.create(GAP + (size.x + GAP) * faces.size(), size.y + GAP * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(BACKDROP)
	for i in faces.size():
		var img := faces[i].get_image()
		img.clear_mipmaps()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_size() != size:
			img.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, size), Vector2i(GAP + i * (size.x + GAP), GAP))
	return sheet


func _save(image: Image, path: String) -> void:
	image.save_png(path)
	print("saved ", path)
