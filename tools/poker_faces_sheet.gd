extends SceneTree
# 德州牌面验收图(需要窗口渲染,不能 --headless):
#   faces_full.png             52 张全尺寸(烘焙尺寸 PokerFaces.SIZE)总览,一行一种花色;faces_detail.png 几张代表牌 + 德州牌背原尺寸一排
#   faces_40x58.png / _30x42   按 2D 小牌的实际过滤(带 mipmap 的线性过滤)缩到说明书与摊牌面板的尺寸,1:1 像素
#   faces_40x58_x3.png 等      上图按最近邻放大,逐像素看缩小后点数与花色是否一眼认得出(宽度不超过 2000,Read 不再缩)
#   tavern_*.png(--tavern)    放进酒馆:吊灯暖光与牌面着色器下的公共牌(放大 1.8、倾斜 35°)与平放的整副牌,
#                              越肩机位下的两张另存牌桌中央的放大裁切(*_crop.png)
# 同时打印生成耗时、每帧同时存在的 SubViewport 数与最慢一帧。
# 用法:godot --path . -s tools/poker_faces_sheet.gd -- --out=/tmp/faces [--tavern]


# 原尺寸细看的几张 + 德州牌背:点数最多的 10♥、有中列的 7♦、♠A 大徽章、三张角色牌 J♣ Q♥ K♠
const DETAIL_CARDS := [[10, 1], [7, 2], [14, 0], [11, 3], [12, 1], [13, 0]]
const SMALL_SIZES := [Vector2i(40, 58), Vector2i(30, 42)]
const SMALL_ZOOMS := [3, 4]                 # 与 SMALL_SIZES 对应的放大倍数
const GAP := 4
const BACKDROP := Color(0.09, 0.07, 0.06)   # 接近酒馆暗处的底色
const SETTLE_FRAMES := 3
const BUILD_WARMUP := 30                    # 计时生成之前空转的帧数
const TAVERN_WARMUP := 45                   # 与 tools/shot.gd 相同:等灯光与后处理稳定
# 规格 §5.5 德州越肩机位(本机座位):牌桌世界的机位函数由 3D 世界任务实现,这里只为看牌面
const SEAT_EYE := Vector3(0.55, 1.92, 2.60)
const SEAT_TARGET := Vector3(0, 0.78, -0.12)
const TOP_EYE := Vector3(0, 1.75, 0.95)     # 斜上方近看平放的整副牌:看暖光与着色器压暗后的四色
const TOP_TARGET := Vector3(0, SeatLayout.TABLE_TOP, 0.05)
const BOARD := [[14, 0], [13, 1], [10, 2], [7, 3], [6, 1]]   # 公共牌样例:四种花色与易混的 6/7/10
const BOARD_SCALE := 1.8
const BOARD_TILT_DEG := 35.0
const BOARD_SPACING := 0.235
const DECK_SCALE := 0.95
const DECK_STEP := Vector2(0.125, 0.19)
const FLAT_LIFT := 0.006                    # 绒布是桌面上 4 毫米厚的圆柱:平放的牌要高过它才看得见
const SEAT_CROP := Rect2i(440, 300, 400, 130)   # 1280×720 越肩截图里牌桌中央那一块
const CROP_ZOOM := 4

var opts := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var out_dir: String = opts.get("out", OS.get_user_data_dir() + "/poker_faces")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var host := Node.new()
	root.add_child(host)
	await _timed_build(host)
	if not PokerFaces.is_built() or PokerFaces.texture(PokerFaces.cards()[0]).get_width() != PokerFaces.SIZE.x:
		push_error("牌面没有生成出来(需要窗口渲染)")
		quit(1)
		return
	_save(_full_sheet(), out_dir + "/faces_full.png")
	_save(_detail_sheet(), out_dir + "/faces_detail.png")
	for i in SMALL_SIZES.size():
		var card_size: Vector2i = SMALL_SIZES[i]
		var zoom: int = SMALL_ZOOMS[i]
		var name := "%s/faces_%dx%d" % [out_dir, card_size.x, card_size.y]
		var small := await _small_sheet(card_size)
		_save(small, name + ".png")
		var zoomed := small.duplicate()
		zoomed.resize(small.get_width() * zoom, small.get_height() * zoom, Image.INTERPOLATE_NEAREST)
		_save(zoomed, "%s_x%d.png" % [name, zoom])
	if opts.has("tavern"):
		await _tavern_shots(out_dir)
	PokerFaces.clear()
	Card3D.clear_materials()
	quit()


func _timed_build(host: Node) -> void:
	# 先空转几帧:刚开窗时的头几帧本来就慢,算进来就看不出生成本身卡不卡
	for i in BUILD_WARMUP:
		await process_frame
	var stamps: Array[int] = [Time.get_ticks_usec()]
	var peak := [0]
	var tick := func():
		stamps.append(Time.get_ticks_usec())
		peak[0] = maxi(peak[0], root.find_children("*", "SubViewport", true, false).size())
	process_frame.connect(tick)
	await PokerFaces.build(host)
	process_frame.disconnect(tick)
	stamps.append(Time.get_ticks_usec())
	var frames := PackedStringArray()
	var worst := 0
	for i in range(1, stamps.size()):
		worst = maxi(worst, stamps[i] - stamps[i - 1])
		frames.append("%.1f" % ((stamps[i] - stamps[i - 1]) / 1000.0))
	print("PokerFaces.build: %.0f ms, peak %d SubViewports, worst frame %.1f ms, frames [%s]" % [
		(stamps[-1] - stamps[0]) / 1000.0, peak[0], worst / 1000.0, " ".join(frames)])


func _full_sheet() -> Image:
	var cell := PokerFaces.SIZE + Vector2i(GAP, GAP)
	var sheet := Image.create(13 * cell.x + GAP, 4 * cell.y + GAP, false, Image.FORMAT_RGBA8)
	sheet.fill(BACKDROP)
	for card in PokerFaces.cards():
		_blit_face(sheet, card, Vector2i(PokerCard.rank(card) - PokerCard.RANK_MIN, PokerCard.suit(card)) * cell)
	return sheet


func _detail_sheet() -> Image:
	# 离得最近、最容易粘连或认错的几张,原尺寸一排:看笔画、纸缝与金边
	var cell := PokerFaces.SIZE + Vector2i(GAP, GAP)
	var sheet := Image.create((DETAIL_CARDS.size() + 1) * cell.x + GAP, cell.y + GAP, false, Image.FORMAT_RGBA8)
	sheet.fill(BACKDROP)
	for i in DETAIL_CARDS.size():
		_blit_face(sheet, PokerCard.make(DETAIL_CARDS[i][0], DETAIL_CARDS[i][1]), Vector2i(i * cell.x, 0))
	_blit(sheet, PokerFaces.back_texture(), Vector2i(DETAIL_CARDS.size() * cell.x, 0))
	return sheet


func _blit_face(sheet: Image, card: int, at: Vector2i) -> void:
	_blit(sheet, PokerFaces.texture(card), at)


func _blit(sheet: Image, texture: Texture2D, at: Vector2i) -> void:
	var face: Image = texture.get_image().duplicate()
	face.clear_mipmaps()
	face.convert(Image.FORMAT_RGBA8)
	sheet.blend_rect(face, Rect2i(Vector2i.ZERO, face.get_size()), Vector2i(GAP, GAP) + at)


func _small_sheet(card_size: Vector2i) -> Image:
	# 在独立视口里按 1:1 像素摆小牌(不受窗口缩放与高分屏影响),过滤方式与 2D 牌条相同
	var cell := card_size + Vector2i(GAP, GAP)
	var vp := SubViewport.new()
	vp.size = Vector2i(13 * cell.x + GAP, 4 * cell.y + GAP)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP
	backdrop.size = Vector2(vp.size)
	vp.add_child(backdrop)
	for card in PokerFaces.cards():
		var rect := TextureRect.new()
		rect.texture = PokerFaces.texture(card)
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.size = Vector2(card_size)
		var at := Vector2i(PokerCard.rank(card) - PokerCard.RANK_MIN, PokerCard.suit(card))
		rect.position = Vector2(Vector2i(GAP, GAP) + at * cell)
		vp.add_child(rect)
	root.add_child(vp)
	for i in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	vp.queue_free()
	return image


# —— 放进酒馆 ——

func _tavern_shots(out_dir: String) -> void:
	var tavern := Tavern.new()
	root.add_child(tavern)
	tavern.set_table_radius(SeatLayout.POKER_TABLE_RADIUS)
	tavern.set_table_decor_visible(false)
	var cards := Node3D.new()
	tavern.add_child(cards)
	_place_board(cards)
	var board := await _shoot(tavern, SEAT_EYE, SEAT_TARGET, out_dir + "/tavern_board.png")
	_save_zoomed(board, SEAT_CROP, CROP_ZOOM, out_dir + "/tavern_board_crop.png")
	for child in cards.get_children():
		child.free()
	_place_deck(cards)
	var deck := await _shoot(tavern, SEAT_EYE, SEAT_TARGET, out_dir + "/tavern_deck_seat.png")
	_save_zoomed(deck, SEAT_CROP, CROP_ZOOM, out_dir + "/tavern_deck_seat_crop.png")
	await _shoot(tavern, TOP_EYE, TOP_TARGET, out_dir + "/tavern_deck_top.png")


func _place_board(parent: Node3D) -> void:
	# 近似规格 §5.3 的公共牌:放大 1.8 倍,牌顶抬起 35°、牌面朝本机镜头(+Z)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(BOARD_TILT_DEG))
	for i in BOARD.size():
		var card := Card3D.new()
		parent.add_child(card)
		card.set_kind(PokerCard.make(BOARD[i][0], BOARD[i][1]))
		var x := (i - (BOARD.size() - 1) / 2.0) * BOARD_SPACING
		var lift := Card3D.HEIGHT * BOARD_SCALE * sin(deg_to_rad(BOARD_TILT_DEG)) / 2.0
		card.transform = Transform3D(tilt.scaled(Vector3.ONE * BOARD_SCALE), Vector3(x, SeatLayout.TABLE_TOP + lift, 0.0))


func _place_deck(parent: Node3D) -> void:
	for card_value in PokerFaces.cards():
		var card := Card3D.new()
		parent.add_child(card)
		card.set_kind(card_value)
		var col := PokerCard.rank(card_value) - PokerCard.RANK_MIN - 6
		var row := PokerCard.suit(card_value) - 1.5
		card.transform = Transform3D(Basis.from_scale(Vector3.ONE * DECK_SCALE),
			Vector3(col * DECK_STEP.x, SeatLayout.TABLE_TOP + FLAT_LIFT, row * DECK_STEP.y))


func _shoot(tavern: Tavern, eye: Vector3, target: Vector3, path: String) -> Image:
	tavern.camera_rig.snap(eye, target)
	tavern.camera_rig.fill_light.light_energy = TableWorld.SEAT_FILL_LIGHT
	for i in TAVERN_WARMUP:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_save(image, path)
	return image


func _save_zoomed(image: Image, rect: Rect2i, zoom: int, path: String) -> void:
	# 截图里牌桌中央那一块按最近邻放大:看 3D 里牌面实际占到的像素
	var region := image.get_region(rect.intersection(Rect2i(Vector2i.ZERO, image.get_size())))
	region.resize(region.get_width() * zoom, region.get_height() * zoom, Image.INTERPOLATE_NEAREST)
	_save(region, path)


func _save(image: Image, path: String) -> void:
	var err := image.save_png(path)
	print("saved %s %dx%d %s" % [path, image.get_width(), image.get_height(), error_string(err)])
