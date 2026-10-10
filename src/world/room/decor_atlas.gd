class_name DecorAtlas
# 墙饰图集(2048×1024):启动时在离屏 SubViewport 里用矢量画 10 张物种通缉令(前 8 张排在第一行,熊猫、企鹅的两张塞在右下的空位)、钟面、乐谱、箱子印字、琴键、
# 窗外夜景、门外夜街、3 幅画、门廊木板与两块招牌,抓取成带 mipmap 的贴图(做法同 CardFaces)。
# texture() 始终返回同一份 ImageTexture:画好之前(以及无头运行时)是 8×8 羊皮纸色,画好后原地换图。
# rect(id) 是常量表(归一化 UV),无头时照样可用,几何照样生成。


const SIZE := Vector2i(2048, 1024)
const POSTER := Vector2i(192, 256)
# 动森式明快配色(2026-10-08):奶油纸、暖棕墨(不是黑)、奶黄金;decor 着色器把纸面 albedo 夹在 0.8 以内
const PAPER := Color(0.96, 0.90, 0.74)       # 纸色(sRGB)
const PAPER_DARK := Color(0.86, 0.74, 0.54)
const INK := Color(0.36, 0.22, 0.16)
const GOLD := Color(0.92, 0.72, 0.34)
# 通缉令标题色带与头像框底色:按物种轮换的粉彩(柔红、天蓝、薄荷、奶黄、淡紫、蜜桃、青绿、粉)
const POSTER_BANDS := [Color(0.94, 0.52, 0.48), Color(0.52, 0.72, 0.92), Color(0.52, 0.82, 0.66), Color(0.98, 0.82, 0.42),
	Color(0.74, 0.62, 0.90), Color(0.98, 0.68, 0.50), Color(0.40, 0.76, 0.74), Color(0.96, 0.62, 0.74),
	Color(0.62, 0.84, 0.46), Color(0.56, 0.80, 0.94)]   # 熊猫竹青、企鹅冰蓝
const MIN_FONT := 8
# 像素矩形
const RECTS := {
	"clock": Rect2i(1536, 0, 256, 256),
	"music": Rect2i(1792, 0, 128, 160),
	"stencil_xxx": Rect2i(1920, 0, 128, 64),
	"stencil_dynamite": Rect2i(1920, 64, 128, 64),
	"stencil_beans": Rect2i(1920, 128, 128, 64),
	"keys": Rect2i(1792, 224, 256, 32),
	"night": Rect2i(0, 256, 512, 512),
	"street": Rect2i(512, 256, 512, 512),
	"painting_mesa": Rect2i(1024, 256, 320, 224),
	"painting_coach": Rect2i(1344, 256, 320, 224),
	"painting_bison": Rect2i(1664, 256, 320, 224),
	"porch": Rect2i(1024, 480, 512, 256),
	"sign_tavern": Rect2i(0, 768, 1024, 128),
	"sign_cheat": Rect2i(1024, 768, 512, 128),
	"chalkboard": Rect2i(1536, 480, 256, 192),
}
# 玩笑赏金(不出现数字金额、货币符号或筹码):按物种 id 查,查不到用回退
const BOUNTIES := {
	"fox": ["赏金:一顶新礼帽", "REWARD: ONE FINE TOP HAT"],
	"bear": ["赏金:一罐蜂蜜", "REWARD: A JAR OF HONEY"],
	"pig": ["赏金:一筐松露", "REWARD: A BASKET OF TRUFFLES"],
	"cat": ["赏金:一条烤鱼", "REWARD: ONE GRILLED FISH"],
	"turtle": ["赏金:慢慢再说", "REWARD: WILL GET BACK TO YOU"],
	"alpaca": ["赏金:一捆干草", "REWARD: A BALE OF HAY"],
	"monkey": ["赏金:一串香蕉", "REWARD: A BUNCH OF BANANAS"],
	"crocodile": ["赏金:一副假牙", "REWARD: A SET OF FALSE TEETH"],
	"panda": ["赏金:一捆嫩竹子", "REWARD: A BUNDLE OF BAMBOO"],
	"penguin": ["赏金:一桶冰鲜鱼", "REWARD: A BUCKET OF ICED FISH"],
}
const BOUNTY_FALLBACK := ["赏金:一桶啤酒", "REWARD: ONE KEG OF BEER"]

static var _texture: ImageTexture = null
static var _built := false
static var _building := false
static var _fonts := {}


# 第一行只放得下 8 张通缉令(1536 像素后是钟面):之后追加的物种放在其余区域之间的空位(左上角)
const EXTRA_POSTERS := [Vector2i(1792, 480), Vector2i(1536, 672)]


static func poster_rect_px(index: int) -> Rect2i:
	var row: int = RECTS["clock"].position.x / POSTER.x
	if index < row:
		return Rect2i(index * POSTER.x, 0, POSTER.x, POSTER.y)
	return Rect2i(EXTRA_POSTERS[index - row], POSTER)


static func rect_px(id: String) -> Rect2i:
	if id.begins_with("poster"):
		return poster_rect_px(int(id.trim_prefix("poster")))
	return RECTS[id]


static func rect(id: String) -> Rect2:
	# 归一化 UV 矩形(u 向右,v 向下)
	var r := rect_px(id)
	return Rect2(Vector2(r.position) / Vector2(SIZE), Vector2(r.size) / Vector2(SIZE))


static func all_ids() -> Array:
	var ids := []
	for i in Species.count():
		ids.append("poster%d" % i)
	ids.append_array(RECTS.keys())
	return ids


static func bounty(species_id: String) -> Array:
	return BOUNTIES.get(species_id, BOUNTY_FALLBACK)


static func texture() -> ImageTexture:
	if _texture == null:
		var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		image.fill(PAPER)
		_texture = ImageTexture.create_from_image(image)
	return _texture


static func is_built() -> bool:
	return _built


static func clear() -> void:
	_texture = null
	_built = false
	_building = false
	_fonts = {}


static func font(kind: String) -> Font:
	# SystemFont 建一次要 10 ms 级,按种类缓存:latin 西文衬线、glyph 展示用楷体
	if not _fonts.has(kind):
		_fonts[kind] = CardFaces.letter_font() if kind == "latin" else CardFaces.glyph_font()
	return _fonts[kind]


static func build(host: Node) -> void:
	# 协程,只需调用一次;并发调用时等第一次完成。无头模式没有渲染,保留回退纸色
	if _built:
		return
	if _building:
		while _building:
			await host.get_tree().process_frame
		return
	texture()
	if DisplayServer.get_name() == "headless":
		_built = true
		return
	_building = true
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = false
	vp.msaa_2d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var painter := DecorPainter.new()
	vp.add_child(painter)
	host.add_child(vp)
	await RenderingServer.frame_post_draw
	await host.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = vp.get_texture().get_image()
	vp.queue_free()
	_building = false
	if _texture == null:
		return
	if image != null and not image.is_empty():
		image.convert(Image.FORMAT_RGBA8)
		image.generate_mipmaps()
		_texture.set_image(image)
	_built = true


class DecorPainter:
	extends Node2D
	# 整张图集的矢量绘制:每块区域用 draw_set_transform 平移到区域原点,在区域局部坐标里画

	var _latin := DecorAtlas.font("latin")
	var _glyph := DecorAtlas.font("glyph")
	var _rng := RandomNumberGenerator.new()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(DecorAtlas.SIZE)), Color(0.62, 0.46, 0.32))
		for i in Species.count():
			_region(DecorAtlas.poster_rect_px(i))
			_poster(i)
		_region(DecorAtlas.RECTS["clock"])
		_clock()
		_region(DecorAtlas.RECTS["music"])
		_music()
		for id in ["stencil_xxx", "stencil_dynamite", "stencil_beans"]:
			_region(DecorAtlas.RECTS[id])
			_stencil({"stencil_xxx": "XXX", "stencil_dynamite": "DYNAMITE", "stencil_beans": "BEANS"}[id])
		_region(DecorAtlas.RECTS["keys"])
		_keys()
		_region(DecorAtlas.RECTS["night"])
		_night()
		_region(DecorAtlas.RECTS["street"])
		_street()
		_region(DecorAtlas.RECTS["painting_mesa"])
		_painting_mesa()
		_region(DecorAtlas.RECTS["painting_coach"])
		_painting_coach()
		_region(DecorAtlas.RECTS["painting_bison"])
		_painting_bison()
		_region(DecorAtlas.RECTS["porch"])
		_porch()
		_region(DecorAtlas.RECTS["sign_tavern"])
		_sign_tavern()
		_region(DecorAtlas.RECTS["sign_cheat"])
		_sign_cheat()
		_region(DecorAtlas.RECTS["chalkboard"])
		_chalkboard()
		draw_set_transform(Vector2.ZERO)

	func _region(r: Rect2i) -> void:
		draw_set_transform(Vector2(r.position))

	# —— 文字 ——

	func _text(f: Font, text: String, center: Vector2, font_size: int, color: Color, width := 0.0) -> void:
		# 居中单行;给了 width 时字号缩到放得下为止
		var fs := font_size
		if width > 0.0:
			while fs > DecorAtlas.MIN_FONT and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
				fs -= 1
		var sz := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var ascent := f.get_ascent(fs)
		var descent := f.get_descent(fs)
		draw_string(f, Vector2(center.x - sz.x / 2.0, center.y + (ascent - descent) / 2.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

	func _has_all(f: Font, text: String) -> bool:
		for k in text.length():
			var c := text.unicode_at(k)
			if c > 127 and not f.has_char(c):
				return false
		return true

	func _cn_or(cn: String, latin: String, center: Vector2, font_size: int, color: Color, width: float) -> void:
		# 中文缺字(Windows 上可能没有楷体)时改画拉丁文本
		if _has_all(_glyph, cn):
			_text(_glyph, cn, center, font_size, color, width)
		else:
			_text(_latin, latin, center, int(font_size * 0.7), color, width)

	# —— 形状 ——

	func _ellipse_points(c: Vector2, r: Vector2, n := 40, a0 := 0.0, a1 := TAU) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for k in n + 1:
			var a := lerpf(a0, a1, float(k) / n)
			pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
		return pts

	func _blob(c: Vector2, r: Vector2, fill: Color, line: Color, width := 2.5) -> void:
		var pts := _ellipse_points(c, r)
		draw_colored_polygon(pts, fill)
		draw_polyline(pts, line, width, true)

	func _poly(pts: PackedVector2Array, fill: Color, line: Color, width := 2.5) -> void:
		draw_colored_polygon(pts, fill)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, line, width, true)

	func _hatch(c: Vector2, r: Vector2, ink: Color, spacing := 5.0) -> void:
		# 木刻排线:椭圆右下 1/3 的斜线
		var k := -r.x
		while k < r.x * 2.0:
			var a := c + Vector2(k, -r.y)
			var b := c + Vector2(k - r.y * 1.2, r.y)
			var seg := _clip_to_ellipse(a, b, c, r)
			if seg.size() == 2:
				var t0 := seg[0]
				var t1 := seg[1]
				var mid := (t0 + t1) / 2.0
				if (mid - c).x + (mid - c).y * 0.6 > r.x * 0.25:
					draw_line(t0.lerp(t1, 0.15), t1, Color(ink, 0.85), 1.2, true)
			k += spacing

	func _clip_to_ellipse(a: Vector2, b: Vector2, c: Vector2, r: Vector2) -> PackedVector2Array:
		var p := (a - c) / r
		var d := (b - a) / r
		var qa := d.dot(d)
		var qb := 2.0 * p.dot(d)
		var qc := p.dot(p) - 1.0
		var disc := qb * qb - 4.0 * qa * qc
		if disc <= 0.0:
			return PackedVector2Array()
		var s := sqrt(disc)
		var t0 := clampf((-qb - s) / (2.0 * qa), 0.0, 1.0)
		var t1 := clampf((-qb + s) / (2.0 * qa), 0.0, 1.0)
		if t1 - t0 < 0.02:
			return PackedVector2Array()
		return PackedVector2Array([a.lerp(b, t0), a.lerp(b, t1)])

	func _paper(size: Vector2, base: Color, seed_value: int, torn := true) -> void:
		# 羊皮纸:底色、边缘做旧、斑点;torn 时四角缺口
		_rng.seed = seed_value
		draw_rect(Rect2(Vector2.ZERO, size), DecorAtlas.PAPER_DARK)
		var inset := 3.0
		var pts := PackedVector2Array()
		var corners := [Vector2(inset, inset), Vector2(size.x - inset, inset), Vector2(size.x - inset, size.y - inset), Vector2(inset, size.y - inset)]
		for k in 4:
			var c: Vector2 = corners[k]
			var nxt: Vector2 = corners[(k + 1) % 4]
			pts.append(c)
			for j in range(1, 8):
				var t := j / 8.0
				var p := c.lerp(nxt, t)
				var n := (nxt - c).orthogonal().normalized()
				pts.append(p + n * _rng.randf_range(-1.5, 1.5))
		draw_colored_polygon(pts, base)
		for i in 7:
			draw_rect(Rect2(Vector2(inset + i * 2, inset + i * 2), size - Vector2(inset + i * 2, inset + i * 2) * 2.0),
				Color(0.62, 0.45, 0.25, 0.04), false, 3.0)
		for i in 40:   # 卡通:斑点少而淡
			var p := Vector2(_rng.randf_range(6, size.x - 6), _rng.randf_range(6, size.y - 6))
			draw_circle(p, _rng.randf_range(0.5, 1.6), Color(DecorAtlas.INK, _rng.randf_range(0.02, 0.05)))
		if torn:
			for c in [Vector2(inset, inset), Vector2(size.x - inset, size.y - inset)]:
				var dir := Vector2(1, 1) if c.x < size.x / 2 else Vector2(-1, -1)
				draw_colored_polygon(PackedVector2Array([c - dir * 4, c + Vector2(dir.x * 16, 0), c + Vector2(0, dir.y * 12)]),
					DecorAtlas.PAPER_DARK.darkened(0.25))

	# —— 通缉令 ——

	func _poster(index: int) -> void:
		var size := Vector2(DecorAtlas.POSTER)
		var id: String = Species.IDS[index]
		var ink := DecorAtlas.INK
		var band: Color = DecorAtlas.POSTER_BANDS[index % DecorAtlas.POSTER_BANDS.size()]
		_paper(size, DecorAtlas.PAPER, 100 + index)
		draw_rect(Rect2(Vector2(10, 10), size - Vector2(20, 20)), ink, false, 2.0)
		draw_rect(Rect2(Vector2(14, 14), size - Vector2(28, 28)), Color(ink, 0.7), false, 1.0)
		CardFaces.draw_rounded(self, Rect2(Vector2(20, 17), Vector2(size.x - 40, 38)), band, 10)   # 粉彩标题色带
		_text(_latin, "WANTED", Vector2(size.x / 2.0, 36), 40, ink, size.x - 32)
		draw_line(Vector2(26, 58), Vector2(size.x - 26, 58), ink, 1.5, true)
		_text(_latin, "FOR CHEATING AT CARDS", Vector2(size.x / 2.0, 67), 11, ink, size.x - 40)
		# 头像框
		var frame := Rect2(Vector2(30, 78), Vector2(size.x - 60, 104))
		draw_rect(frame, DecorAtlas.PAPER.lerp(band, 0.35))
		draw_rect(frame, ink, false, 2.0)
		# 头像缩到 0.8 倍、略往下放:礼帽、羊驼耳朵这类高个子也收在框里
		draw_set_transform(Vector2(DecorAtlas.poster_rect_px(index).position) + frame.get_center() + Vector2(0, 12), 0.0, Vector2(0.8, 0.8))
		_portrait(id, ink)
		_region(DecorAtlas.poster_rect_px(index))
		_cn_or("通缉 " + Species.LABELS[index], id.to_upper(), Vector2(size.x / 2.0, 200), 26, ink, size.x - 36)
		var b: Array = DecorAtlas.bounty(id)
		_cn_or(b[0], b[1], Vector2(size.x / 2.0, 223), 15, ink, size.x - 34)
		_text(_latin, b[1], Vector2(size.x / 2.0, 235), 8, Color(ink, 0.85), size.x - 40)

	func _portrait(id: String, ink: Color) -> void:
		# 单色木刻头像(局部坐标:头心在原点,头半径约 34 px);只用墨色,和角色毛色解耦
		var paper := DecorAtlas.PAPER.lightened(0.04)
		var shade := DecorAtlas.PAPER.darkened(0.22)
		match id:
			"fox":
				_poly(PackedVector2Array([Vector2(-26, -22), Vector2(-16, -56), Vector2(-4, -26)]), shade, ink)
				_poly(PackedVector2Array([Vector2(26, -22), Vector2(16, -56), Vector2(4, -26)]), shade, ink)
				_poly(PackedVector2Array([Vector2(-36, -6), Vector2(-46, 14), Vector2(-24, 12)]), paper, ink)
				_poly(PackedVector2Array([Vector2(36, -6), Vector2(46, 14), Vector2(24, 12)]), paper, ink)
				_blob(Vector2(0, -4), Vector2(33, 28), paper, ink)
				_hatch(Vector2(0, -4), Vector2(33, 28), ink)
				_poly(PackedVector2Array([Vector2(-14, 6), Vector2(14, 6), Vector2(0, 34)]), paper, ink, 2.0)
				draw_circle(Vector2(0, 32), 4.0, ink)
				_eyes(Vector2(0, -6), 12.0, ink, true)
				_top_hat(Vector2(0, -28), ink, shade)
			"bear":
				for s in [-1, 1]:
					_blob(Vector2(s * 28, -26), Vector2(12, 12), shade, ink)
					draw_circle(Vector2(s * 28, -26), 5.0, Color(ink, 0.6))
				_blob(Vector2(0, 0), Vector2(37, 33), paper, ink)
				_hatch(Vector2(0, 0), Vector2(37, 33), ink)
				_blob(Vector2(0, 14), Vector2(17, 13), DecorAtlas.PAPER, ink, 2.0)
				_blob(Vector2(0, 8), Vector2(6, 4.5), ink, ink, 1.0)
				draw_line(Vector2(0, 12), Vector2(0, 19), ink, 2.0, true)
				draw_arc(Vector2(-4, 19), 4.0, 0.0, PI, 10, ink, 1.6, true)
				draw_arc(Vector2(4, 19), 4.0, 0.0, PI, 10, ink, 1.6, true)
				_eyes(Vector2(0, -6), 14.0, ink, false)
				_bowler(Vector2(0, -26), ink, shade)
			"pig":
				for s in [-1, 1]:
					_poly(PackedVector2Array([Vector2(s * 16, -24), Vector2(s * 40, -30), Vector2(s * 34, -2)]), shade, ink)
				_blob(Vector2(0, 0), Vector2(37, 32), paper, ink)
				_hatch(Vector2(0, 0), Vector2(37, 32), ink)
				_blob(Vector2(0, 10), Vector2(15, 11), DecorAtlas.PAPER, ink, 2.2)
				_blob(Vector2(-5, 10), Vector2(2.6, 4.2), ink, ink, 1.0)
				_blob(Vector2(5, 10), Vector2(2.6, 4.2), ink, ink, 1.0)
				draw_arc(Vector2(0, 22), 9.0, 0.3, PI - 0.3, 12, ink, 1.6, true)
				_eyes(Vector2(0, -10), 14.0, ink, false)
				_conductor_cap(Vector2(0, -24), ink, shade)
			"cat":
				for s in [-1, 1]:
					_poly(PackedVector2Array([Vector2(s * 8, -24), Vector2(s * 30, -50), Vector2(s * 34, -12)]), shade, ink)
				_blob(Vector2(0, 0), Vector2(35, 29), paper, ink)
				_hatch(Vector2(0, 0), Vector2(35, 29), ink)
				_poly(PackedVector2Array([Vector2(-4, 6), Vector2(4, 6), Vector2(0, 11)]), ink, ink, 1.0)
				draw_arc(Vector2(-4, 13), 4.0, 0.0, PI, 8, ink, 1.4, true)
				draw_arc(Vector2(4, 13), 4.0, 0.0, PI, 8, ink, 1.4, true)
				for s in [-1, 1]:
					for k in 3:
						draw_line(Vector2(s * 10, 10 + k * 3), Vector2(s * 40, 4 + k * 6), ink, 1.0, true)
				_eyes(Vector2(0, -6), 13.0, ink, true)
				_cowboy_hat(Vector2(0, -26), ink, shade)
			"turtle":
				_blob(Vector2(0, 2), Vector2(32, 30), paper, ink)
				_hatch(Vector2(0, 2), Vector2(32, 30), ink)
				for k in 6:
					var a := 0.6 + k * 0.42
					draw_arc(Vector2(cos(a) * 18, sin(a) * 14 + 6), 4.0, 0.0, TAU, 10, Color(ink, 0.55), 1.0, true)
				draw_line(Vector2(-16, 18), Vector2(16, 18), ink, 2.0, true)
				draw_line(Vector2(-16, 18), Vector2(-19, 15), ink, 2.0, true)
				draw_circle(Vector2(-4, 4), 1.6, ink)
				draw_circle(Vector2(4, 4), 1.6, ink)
				_eyes(Vector2(0, -8), 13.0, ink, false, true)
				_slouch_hat(Vector2(0, -24), ink, shade)
			"alpaca":
				for s in [-1, 1]:
					_poly(PackedVector2Array([Vector2(s * 10, -34), Vector2(s * 20, -62), Vector2(s * 25, -58), Vector2(s * 20, -30)]), shade, ink)
				_blob(Vector2(0, 0), Vector2(26, 38), paper, ink)
				_hatch(Vector2(0, 0), Vector2(26, 38), ink)
				for k in 5:
					_blob(Vector2(-16 + k * 8, -34 + (k % 2) * 3), Vector2(7, 6), DecorAtlas.PAPER, ink, 1.6)
				_blob(Vector2(0, 26), Vector2(15, 12), DecorAtlas.PAPER, ink, 2.0)
				draw_line(Vector2(0, 22), Vector2(0, 30), ink, 1.8, true)
				draw_line(Vector2(0, 22), Vector2(-5, 18), ink, 1.8, true)
				draw_line(Vector2(0, 22), Vector2(5, 18), ink, 1.8, true)
				_eyes(Vector2(0, -4), 12.0, ink, false)
				_straw_hat(Vector2(0, -40), ink, shade)
			"monkey":
				for s in [-1, 1]:
					_blob(Vector2(s * 38, 2), Vector2(12, 13), shade, ink)
					_blob(Vector2(s * 38, 2), Vector2(6, 7), DecorAtlas.PAPER, ink, 1.2)
				_blob(Vector2(0, 0), Vector2(33, 32), shade, ink)
				_hatch(Vector2(0, 0), Vector2(33, 32), ink)
				var mask := PackedVector2Array()
				for k in 33:
					var a := TAU * k / 32.0
					var r := 22.0 + 4.0 * cos(2.0 * a)
					mask.append(Vector2(cos(a) * r, sin(a) * r * 0.85 + 6 - (6.0 if sin(a) < 0.0 and absf(cos(a)) < 0.3 else 0.0)))
				_poly(mask, paper, ink, 2.0)
				draw_circle(Vector2(-3, 8), 1.8, ink)
				draw_circle(Vector2(3, 8), 1.8, ink)
				draw_arc(Vector2(0, 12), 11.0, 0.25, PI - 0.25, 14, ink, 2.0, true)
				_eyes(Vector2(0, -4), 10.0, ink, false)
				_pillbox(Vector2(6, -30), ink, shade)
			"crocodile":
				var head := PackedVector2Array([Vector2(-36, -12), Vector2(-20, -26), Vector2(10, -20), Vector2(52, -10),
					Vector2(56, 2), Vector2(52, 14), Vector2(10, 18), Vector2(-24, 24), Vector2(-38, 8)])
				_poly(head, paper, ink)
				_hatch(Vector2(-6, 0), Vector2(34, 22), ink)
				draw_line(Vector2(-18, 4), Vector2(54, 2), ink, 2.0, true)
				for k in 8:
					var x := -10.0 + k * 8.0
					draw_colored_polygon(PackedVector2Array([Vector2(x, 2.6), Vector2(x + 4, 2.4), Vector2(x + 2, 8)]), ink)
				draw_circle(Vector2(48, -8), 2.0, ink)
				for s in [-1, 1]:
					_blob(Vector2(-14 + s * 9, -24), Vector2(7, 6), DecorAtlas.PAPER, ink, 2.0)
					draw_circle(Vector2(-14 + s * 9, -24), 2.4, ink)
				draw_line(Vector2(-24, -30), Vector2(-16, -27), ink, 2.0, true)
				_flat_hat(Vector2(-12, -32), ink, shade)
			"panda":
				for s in [-1, 1]:
					_blob(Vector2(s * 27, -25), Vector2(12, 12), ink, ink)
				_blob(Vector2(0, 0), Vector2(36, 31), paper, ink)
				_hatch(Vector2(0, 0), Vector2(36, 31), ink)
				for s in [-1, 1]:
					# 往外下方耷拉的泪滴眼斑
					var patch := PackedVector2Array()
					for k in 24:
						var a := TAU * k / 24.0
						var drop := 1.0 + 0.5 * pow(maxf(cos(a - 1.1), 0.0), 2.5)
						var q := Vector2(cos(a) * 8.0, sin(a) * 10.0) * drop
						patch.append(Vector2(s * (12.0 + q.x), -5.0 + q.y))
					_poly(patch, ink, ink, 1.0)
					draw_circle(Vector2(s * 12, -6), 3.6, DecorAtlas.PAPER)
					draw_circle(Vector2(s * 12, -5.5), 2.0, ink)
				_blob(Vector2(0, 9), Vector2(6, 4.5), ink, ink, 1.0)
				draw_arc(Vector2(-3.5, 16), 3.5, 0.0, PI, 8, ink, 1.6, true)
				draw_arc(Vector2(3.5, 16), 3.5, 0.0, PI, 8, ink, 1.6, true)
				# 嘴角斜叼的竹枝:竹节两道、末端两片叶子
				draw_line(Vector2(-6, 18), Vector2(-42, 8), ink, 3.2, true)
				for t in [0.4, 0.75]:
					var n := Vector2(-6, 18).lerp(Vector2(-42, 8), t)
					draw_line(n + Vector2(-0.8, -3), n + Vector2(0.8, 3), DecorAtlas.PAPER, 1.4, true)
				_poly(PackedVector2Array([Vector2(-42, 8), Vector2(-50, -6), Vector2(-46, -14), Vector2(-40, -2)]), shade, ink, 1.4)
				_poly(PackedVector2Array([Vector2(-42, 8), Vector2(-56, 4), Vector2(-62, 9), Vector2(-48, 11)]), shade, ink, 1.4)
				_douli(Vector2(0, -27), ink, shade)
			"penguin":
				_blob(Vector2(0, 0), Vector2(34, 32), shade, ink)
				_hatch(Vector2(0, 0), Vector2(34, 32), ink)
				for s in [-1, 1]:
					_blob(Vector2(s * 11, -5), Vector2(12, 13), paper, paper, 0.0)
				_blob(Vector2(0, 9), Vector2(25, 17), paper, paper, 0.0)
				var face := _ellipse_points(Vector2(0, 9), Vector2(25, 17), 40, -0.2, PI + 0.2)
				draw_polyline(face, ink, 2.0, true)
				_eyes(Vector2(0, -5), 11.0, ink, false)
				_poly(PackedVector2Array([Vector2(-7, 4), Vector2(7, 4), Vector2(0, 15)]), shade, ink, 2.0)
				for s in [-1, 1]:
					draw_circle(Vector2(s * 20, 8), 4.0, Color(ink, 0.3))
				_beanie(Vector2(0, -22), ink, shade)
			_:
				push_warning("通缉令:没有物种 %s 的画法,用通用头像" % id)
				_blob(Vector2(0, 0), Vector2(34, 30), paper, ink)
				_eyes(Vector2(0, -6), 12.0, ink, false)

	func _eyes(c: Vector2, spread: float, ink: Color, sly: bool, sleepy := false) -> void:
		for s in [-1, 1]:
			var e := c + Vector2(s * spread, 0)
			if sleepy:
				draw_arc(e, 4.0, 0.2, PI - 0.2, 8, ink, 2.0, true)
				continue
			draw_circle(e, 4.2, ink)
			draw_circle(e + Vector2(-1.2, -1.4), 1.3, DecorAtlas.PAPER)
			# 眉:sly 时外高内低(狡黠)
			var tilt := 3.0 if sly else -1.0
			draw_line(e + Vector2(-6 * s, -8 - tilt), e + Vector2(6 * s, -8 + tilt), ink, 2.2, true)

	# —— 帽子(c = 帽檐中心)——

	func _top_hat(c: Vector2, ink: Color, shade: Color) -> void:
		_poly(PackedVector2Array([c + Vector2(-20, 0), c + Vector2(-17, -44), c + Vector2(17, -44), c + Vector2(20, 0)]), shade, ink)
		draw_rect(Rect2(c + Vector2(-19, -12), Vector2(38, 7)), ink)
		_blob(c, Vector2(36, 6), shade, ink)

	func _bowler(c: Vector2, ink: Color, shade: Color) -> void:
		_poly(_ellipse_points(c + Vector2(0, -2), Vector2(26, 24), 24, PI, TAU), shade, ink)
		draw_rect(Rect2(c + Vector2(-25, -8), Vector2(50, 5)), ink)
		_blob(c, Vector2(36, 6), shade, ink)

	func _conductor_cap(c: Vector2, ink: Color, shade: Color) -> void:
		var top := PackedVector2Array([c + Vector2(-26, 0), c + Vector2(-24, -20), c + Vector2(24, -20), c + Vector2(26, 0)])
		_poly(top, DecorAtlas.PAPER, ink)
		for k in 7:
			var x := -21.0 + k * 7.0
			draw_line(c + Vector2(x, -19), c + Vector2(x * 1.05, -1), ink, 2.4, true)
		_poly(PackedVector2Array([c + Vector2(-14, 0), c + Vector2(14, 0), c + Vector2(10, 8), c + Vector2(-10, 8)]), shade, ink)

	func _cowboy_hat(c: Vector2, ink: Color, shade: Color) -> void:
		var brim := PackedVector2Array()
		for k in 25:
			var t := float(k) / 24.0
			var x := lerpf(-48, 48, t)
			brim.append(c + Vector2(x, -pow(absf(x) / 48.0, 3.0) * 12.0 - 3.0))
		for k in 25:
			var t := float(k) / 24.0
			var x := lerpf(48, -48, t)
			brim.append(c + Vector2(x, -pow(absf(x) / 48.0, 3.0) * 10.0 + 4.0))
		_poly(brim, shade, ink)
		_poly(PackedVector2Array([c + Vector2(-22, -1), c + Vector2(-18, -28), c + Vector2(-6, -32), c + Vector2(0, -26),
			c + Vector2(6, -32), c + Vector2(18, -28), c + Vector2(22, -1)]), shade, ink)
		draw_rect(Rect2(c + Vector2(-21, -9), Vector2(42, 5)), ink)

	func _slouch_hat(c: Vector2, ink: Color, shade: Color) -> void:
		_poly(PackedVector2Array([c + Vector2(-44, 6), c + Vector2(-30, -4), c + Vector2(30, -4), c + Vector2(44, 8),
			c + Vector2(30, 4), c + Vector2(-30, 4)]), shade, ink)
		_poly(_ellipse_points(c + Vector2(0, -3), Vector2(22, 20), 20, PI, TAU), shade, ink)
		draw_rect(Rect2(c + Vector2(-21, -8), Vector2(42, 4)), ink)

	func _straw_hat(c: Vector2, ink: Color, shade: Color) -> void:
		_blob(c, Vector2(34, 7), DecorAtlas.PAPER, ink)
		for k in 9:
			var a := PI + k * PI / 8.0
			draw_line(c + Vector2(cos(a) * 12, sin(a) * 2.5), c + Vector2(cos(a) * 32, sin(a) * 6.5), Color(ink, 0.6), 1.0, true)
		_poly(PackedVector2Array([c + Vector2(-12, 0), c + Vector2(-11, -12), c + Vector2(11, -12), c + Vector2(12, 0)]), DecorAtlas.PAPER, ink)
		draw_rect(Rect2(c + Vector2(-12, -5), Vector2(24, 4)), ink)

	func _pillbox(c: Vector2, ink: Color, shade: Color) -> void:
		_poly(PackedVector2Array([c + Vector2(-13, 2), c + Vector2(-12, -14), c + Vector2(12, -16), c + Vector2(14, 0)]), shade, ink)
		_blob(c + Vector2(0, -15), Vector2(12, 3.5), shade, ink, 1.8)
		draw_line(c + Vector2(0, -18), c + Vector2(0, -24), ink, 2.0, true)
		draw_circle(c + Vector2(0, -25), 2.5, ink)

	func _douli(c: Vector2, ink: Color, shade: Color) -> void:
		# 竹编小斗笠:浅圆锥 + 编织线 + 顶珠
		_poly(PackedVector2Array([c + Vector2(-30, 2), c + Vector2(0, -15), c + Vector2(30, 2), c + Vector2(0, 5)]), DecorAtlas.PAPER, ink)
		for k in 5:
			var x := -20.0 + k * 10.0
			draw_line(c + Vector2(0, -14), c + Vector2(x * 1.3, 3), Color(ink, 0.55), 1.0, true)
		draw_circle(c + Vector2(0, -16), 3.0, ink)

	func _beanie(c: Vector2, ink: Color, shade: Color) -> void:
		# 毛线球帽:圆帽身 + 一道条纹 + 翻边 + 绒球
		var dome := _ellipse_points(c, Vector2(27, 20), 24, PI, TAU)
		_poly(dome, DecorAtlas.PAPER, ink)
		draw_line(c + Vector2(-24, -9), c + Vector2(24, -9), ink, 3.0, true)
		_poly(PackedVector2Array([c + Vector2(-29, -3), c + Vector2(29, -3), c + Vector2(29, 5), c + Vector2(-29, 5)]), shade, ink, 2.0)
		for k in 9:
			var x := -24.0 + k * 6.0
			draw_line(c + Vector2(x, -2), c + Vector2(x, 4), Color(ink, 0.6), 1.0, true)
		_blob(c + Vector2(0, -23), Vector2(7, 7), DecorAtlas.PAPER, ink, 2.0)

	func _flat_hat(c: Vector2, ink: Color, shade: Color) -> void:
		_blob(c, Vector2(38, 6), shade, ink)
		_poly(PackedVector2Array([c + Vector2(-20, -1), c + Vector2(-19, -14), c + Vector2(19, -14), c + Vector2(20, -1)]), shade, ink)
		_blob(c + Vector2(0, -14), Vector2(19, 3), shade, ink, 1.8)
		draw_rect(Rect2(c + Vector2(-20, -6), Vector2(40, 4)), ink)

	# —— 钟面、乐谱、印字、琴键 ——

	func _clock() -> void:
		var s := 256.0
		var c := Vector2(s, s) / 2.0
		draw_rect(Rect2(Vector2.ZERO, Vector2(s, s)), Color(0.58, 0.36, 0.22))
		draw_circle(c, 118, DecorAtlas.GOLD)
		draw_circle(c, 110, Color(0.98, 0.94, 0.82))
		draw_arc(c, 98, 0, TAU, 96, DecorAtlas.INK, 1.5, true)
		draw_arc(c, 82, 0, TAU, 96, DecorAtlas.INK, 1.0, true)
		var numerals := ["XII", "I", "II", "III", "IIII", "V", "VI", "VII", "VIII", "IX", "X", "XI"]
		for i in 12:
			var a := -PI / 2.0 + TAU * i / 12.0
			draw_set_transform(Vector2(DecorAtlas.RECTS["clock"].position) + c + Vector2(cos(a), sin(a)) * 90.0, a + PI / 2.0)
			_text(_latin, numerals[i], Vector2.ZERO, 17, DecorAtlas.INK, 34)
		_region(DecorAtlas.RECTS["clock"])
		for i in 60:
			var a := TAU * i / 60.0
			var r0 := 98.0 if i % 5 else 94.0
			draw_line(c + Vector2(cos(a), sin(a)) * r0, c + Vector2(cos(a), sin(a)) * 102.0, DecorAtlas.INK, 1.0, true)
		# 指针停在 11:55
		var minute := -PI / 2.0 + TAU * 55.0 / 60.0
		var hour := -PI / 2.0 + TAU * (11.0 + 55.0 / 60.0) / 12.0
		draw_line(c, c + Vector2(cos(hour), sin(hour)) * 52.0, DecorAtlas.INK, 6.0, true)
		draw_line(c, c + Vector2(cos(minute), sin(minute)) * 76.0, DecorAtlas.INK, 3.5, true)
		draw_circle(c, 7, DecorAtlas.GOLD)

	func _music() -> void:
		var size := Vector2(128, 160)
		_paper(size, DecorAtlas.PAPER, 7, false)
		_rng.seed = 77
		for staff in 4:
			var y0 := 22.0 + staff * 34.0
			for k in 5:
				draw_line(Vector2(10, y0 + k * 4), Vector2(118, y0 + k * 4), Color(DecorAtlas.INK, 0.8), 1.0)
			var x := 22.0
			while x < 112.0:
				var y := y0 + _rng.randi_range(-1, 9) * 2.0
				draw_circle(Vector2(x, y), 2.6, DecorAtlas.INK)
				draw_line(Vector2(x + 2.4, y), Vector2(x + 2.4, y - 12), DecorAtlas.INK, 1.0)
				x += _rng.randf_range(8, 14)

	func _stencil(text: String) -> void:
		draw_rect(Rect2(0, 0, 128, 64), Color(0.86, 0.68, 0.44))
		draw_rect(Rect2(3, 3, 122, 58), Color(0.72, 0.30, 0.26), false, 2.5)
		_text(_latin, text, Vector2(64, 33), 30, Color(0.72, 0.30, 0.26), 112)

	func _keys() -> void:
		draw_rect(Rect2(0, 0, 256, 32), Color(0.30, 0.22, 0.22))
		var n := 26
		var w := 256.0 / n
		for k in n:
			draw_rect(Rect2(k * w + 0.5, 0, w - 1.0, 32), Color(0.97, 0.94, 0.86))
		for k in n - 1:
			if k % 7 in [2, 6]:
				continue
			draw_rect(Rect2((k + 1) * w - w * 0.3, 0, w * 0.6, 19), Color(0.26, 0.2, 0.22))

	# —— 窗外夜景(外景板 3.0 × 2.4 m 拉到 512²:横向每米 170.7 px、竖向 213.3 px)——

	func _night() -> void:
		var s := 512.0
		var px := Vector2(s / (RoomLayout.BACKDROP_Z.y - RoomLayout.BACKDROP_Z.x), s / (RoomLayout.BACKDROP_Y.y - RoomLayout.BACKDROP_Y.x))
		for k in 64:
			var t := k / 63.0
			var col := Color(0.06, 0.08, 0.22).lerp(Color(0.20, 0.27, 0.48), pow(t, 1.6))   # 深靛夜空(卡通:饱和一点)
			draw_rect(Rect2(0, t * s, s, s / 63.0 + 1.0), col)
		_rng.seed = 2024
		for i in 160:
			var p := Vector2(_rng.randf() * s, pow(_rng.randf(), 1.5) * s * 0.7)
			draw_circle(p, _rng.randf_range(0.6, 1.6), Color(0.9, 0.92, 1.0, _rng.randf_range(0.35, 0.95)))
		var moon := RoomLayout.moon_uv() * s
		var r := 0.13
		for k in 28:
			var g := 4.5 - k * 0.125
			_filled_ellipse(moon, Vector2(r * px.x, r * px.y) * g, Color(0.75, 0.82, 1.0, 0.022))
		_filled_ellipse(moon, Vector2(r * px.x, r * px.y), Color(0.97, 0.96, 0.88))
		_filled_ellipse(moon + Vector2(-6, 4), Vector2(5, 6), Color(0.86, 0.85, 0.78))
		_filled_ellipse(moon + Vector2(7, -5), Vector2(4, 4), Color(0.88, 0.87, 0.8))
		# 远山与台地剪影
		var far := PackedVector2Array([Vector2(0, s)])
		for k in 33:
			var x := s * k / 32.0
			far.append(Vector2(x, s * 0.70 - 18.0 * sin(k * 0.7) - 10.0 * sin(k * 1.9)))
		far.append(Vector2(s, s))
		draw_colored_polygon(far, Color(0.12, 0.13, 0.26))
		var mesa := PackedVector2Array([Vector2(0, s), Vector2(0, s * 0.74), Vector2(60, s * 0.74), Vector2(84, s * 0.66),
			Vector2(170, s * 0.65), Vector2(196, s * 0.74), Vector2(300, s * 0.76), Vector2(330, s * 0.69),
			Vector2(372, s * 0.69), Vector2(392, s * 0.77), Vector2(s, s * 0.78), Vector2(s, s)])
		draw_colored_polygon(mesa, Color(0.08, 0.08, 0.17))
		draw_rect(Rect2(0, s * 0.80, s, s * 0.2), Color(0.07, 0.07, 0.13))
		_cactus(Vector2(120, s * 0.86), 1.0, Color(0.05, 0.09, 0.10))
		_cactus(Vector2(430, s * 0.83), 0.7, Color(0.06, 0.10, 0.12))

	func _filled_ellipse(c: Vector2, r: Vector2, col: Color) -> void:
		draw_colored_polygon(_ellipse_points(c, r, 32), col)

	func _cactus(base: Vector2, k: float, col: Color) -> void:
		draw_rect(Rect2(base + Vector2(-7, -110) * k, Vector2(14, 110) * k), col)
		draw_circle(base + Vector2(0, -110) * k, 7 * k, col)
		for s in [-1, 1]:
			var arm := base + Vector2(s * 7, -55 - s * 10) * k
			draw_rect(Rect2(arm + Vector2(minf(0, s * 24) , -6) * k, Vector2(24, 12) * k), col)
			draw_rect(Rect2(arm + Vector2(s * 24 - 6, -40) * k, Vector2(12, 40) * k), col)
			draw_circle(arm + Vector2(s * 24, -40) * k, 6 * k, col)

	# —— 门外夜街(4.9 × 3.0 m 拉到 512²)——

	func _street() -> void:
		var s := 512.0
		for k in 32:
			var t := k / 31.0
			draw_rect(Rect2(0, t * s * 0.4, s, s * 0.4 / 31.0 + 1.0), Color(0.06, 0.07, 0.18).lerp(Color(0.14, 0.17, 0.32), t))
		_rng.seed = 909
		for i in 60:
			draw_circle(Vector2(_rng.randf() * s, _rng.randf() * s * 0.3), _rng.randf_range(0.5, 1.3), Color(0.9, 0.9, 1.0, _rng.randf_range(0.3, 0.8)))
		# 街面
		draw_rect(Rect2(0, s * 0.80, s, s * 0.2), Color(0.14, 0.12, 0.16))
		# 对面的假立面:HOTEL / BANK / SHERIFF(夜色里的柔红、灰蓝、青绿)
		var fronts := [[10.0, 160.0, 0.24, "HOTEL", Color(0.34, 0.18, 0.20)], [175.0, 160.0, 0.32, "BANK", Color(0.20, 0.22, 0.34)],
			[340.0, 165.0, 0.28, "SHERIFF", Color(0.16, 0.28, 0.28)]]
		for f in fronts:
			var x: float = f[0]
			var w: float = f[1]
			var top: float = s * f[2]
			draw_rect(Rect2(x, top, w, s * 0.80 - top), f[4])
			draw_rect(Rect2(x - 4, top - 6, w + 8, 8), Color(f[4]).darkened(0.3))
			draw_rect(Rect2(x + 14, top + 12, w - 28, 26), Color(0.48, 0.34, 0.22))
			_text(_latin, f[3], Vector2(x + w / 2.0, top + 26), 22, Color(0.98, 0.86, 0.55), w - 36)
			for row in 2:
				for col in 3:
					var wx := x + 18 + col * (w - 36) / 3.0
					var wy := top + 56 + row * 70
					var lit: bool = (int(x) + row * 3 + col) % 3 != 0
					var c := Color(1.0, 0.76, 0.42) if lit else Color(0.12, 0.12, 0.2)
					draw_rect(Rect2(wx, wy, (w - 36) / 3.0 - 10, 44), c)
					if lit:
						draw_line(Vector2(wx + ((w - 36) / 3.0 - 10) / 2.0, wy), Vector2(wx + ((w - 36) / 3.0 - 10) / 2.0, wy + 44), Color(0.25, 0.15, 0.08), 2.0)
			# 门廊顶棚与门
			draw_rect(Rect2(x, s * 0.62, w, 6), Color(f[4]).darkened(0.4))
			draw_rect(Rect2(x + w / 2.0 - 16, s * 0.66, 32, s * 0.14), Color(0.9, 0.6, 0.3) if f[3] != "BANK" else Color(0.07, 0.07, 0.09))
		# 拴马栏、水槽、灯笼光
		draw_rect(Rect2(40, s * 0.84, 180, 5), Color(0.20, 0.14, 0.09))
		for x in [46.0, 130.0, 214.0]:
			draw_rect(Rect2(x - 3, s * 0.84, 6, 34), Color(0.20, 0.14, 0.09))
		draw_rect(Rect2(300, s * 0.86, 120, 26), Color(0.17, 0.12, 0.08))
		draw_rect(Rect2(304, s * 0.86 + 2, 112, 6), Color(0.25, 0.33, 0.45))
		for lantern in [Vector2(92, s * 0.56), Vector2(424, s * 0.57)]:
			for k in 8:
				draw_circle(lantern, 34.0 - k * 4.0, Color(1.0, 0.65, 0.3, 0.05 + k * 0.02))
			draw_circle(lantern, 6.0, Color(1.0, 0.92, 0.7))

	# —— 画 ——

	func _frame_inner(size: Vector2) -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.4, 0.25, 0.12, 0.25), false, 6.0)

	func _painting_mesa() -> void:
		var size := Vector2(320, 224)
		for k in 40:
			var t := k / 39.0
			draw_rect(Rect2(0, t * size.y * 0.7, size.x, size.y * 0.7 / 39.0 + 1.0),
				Color(0.62, 0.52, 0.80).lerp(Color(0.99, 0.70, 0.46), pow(t, 1.3)))
		draw_circle(Vector2(210, size.y * 0.62), 26, Color(1.0, 0.88, 0.52))
		draw_colored_polygon(PackedVector2Array([Vector2(0, size.y), Vector2(0, 140), Vector2(40, 140), Vector2(60, 104),
			Vector2(140, 100), Vector2(158, 140), Vector2(230, 146), Vector2(250, 120), Vector2(300, 118), Vector2(320, 150),
			Vector2(size.x, size.y)]), Color(0.86, 0.48, 0.38))
		draw_colored_polygon(PackedVector2Array([Vector2(0, size.y), Vector2(0, 176), Vector2(120, 168), Vector2(260, 178),
			Vector2(size.x, 172), Vector2(size.x, size.y)]), Color(0.92, 0.66, 0.44))
		_cactus(Vector2(56, 210), 0.45, Color(0.36, 0.62, 0.38))
		_frame_inner(size)

	func _painting_coach() -> void:
		var size := Vector2(320, 224)
		for k in 40:
			var t := k / 39.0
			draw_rect(Rect2(0, t * size.y * 0.75, size.x, size.y * 0.75 / 39.0 + 1.0),
				Color(0.56, 0.76, 0.92).lerp(Color(0.99, 0.86, 0.62), t))
		draw_rect(Rect2(0, size.y * 0.72, size.x, size.y * 0.28), Color(0.88, 0.72, 0.48))
		draw_line(Vector2(0, 190), Vector2(size.x, 170), Color(0.95, 0.82, 0.60), 10.0)
		var ink := Color(0.42, 0.28, 0.22)
		# 驿站马车剪影 + 两匹马
		draw_rect(Rect2(150, 122, 86, 44), ink)
		draw_rect(Rect2(140, 116, 106, 8), ink)
		draw_circle(Vector2(162, 172), 14, ink)
		draw_circle(Vector2(226, 172), 16, ink)
		draw_circle(Vector2(162, 172), 9, Color(0.88, 0.72, 0.48))
		draw_circle(Vector2(226, 172), 11, Color(0.88, 0.72, 0.48))
		for hx in [70.0, 102.0]:
			draw_rect(Rect2(hx, 140, 40, 18), ink)
			draw_colored_polygon(PackedVector2Array([Vector2(hx, 142), Vector2(hx - 14, 126), Vector2(hx - 20, 132), Vector2(hx - 8, 152)]), ink)
			for lx in [hx + 4, hx + 14, hx + 28, hx + 36]:
				draw_line(Vector2(lx, 156), Vector2(lx + 3, 176), ink, 3.0)
		draw_line(Vector2(140, 150), Vector2(110, 148), ink, 2.0)
		_frame_inner(size)

	func _painting_bison() -> void:
		var size := Vector2(320, 224)
		for k in 40:
			var t := k / 39.0
			draw_rect(Rect2(0, t * size.y * 0.6, size.x, size.y * 0.6 / 39.0 + 1.0),
				Color(0.58, 0.78, 0.94).lerp(Color(0.97, 0.94, 0.78), t))
		draw_colored_polygon(PackedVector2Array([Vector2(0, size.y), Vector2(0, 128), Vector2(90, 118), Vector2(200, 126),
			Vector2(size.x, 114), Vector2(size.x, size.y)]), Color(0.60, 0.78, 0.46))
		draw_rect(Rect2(0, 160, size.x, 64), Color(0.74, 0.84, 0.48))
		var ink := Color(0.48, 0.32, 0.24)
		for b in [[Vector2(90, 160), 1.0], [Vector2(200, 150), 0.75], [Vector2(262, 172), 0.9]]:
			var c: Vector2 = b[0]
			var k: float = b[1]
			_filled_ellipse(c, Vector2(30, 16) * k, ink)
			_filled_ellipse(c + Vector2(-24, -8) * k, Vector2(16, 18) * k, ink)
			_filled_ellipse(c + Vector2(-38, 0) * k, Vector2(9, 10) * k, ink)
			for lx in [-18.0, -6.0, 12.0, 22.0]:
				draw_line(c + Vector2(lx, 8) * k, c + Vector2(lx, 26) * k, ink, 3.0 * k)
		_frame_inner(size)

	func _porch() -> void:
		var size := Vector2(512, 256)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.26, 0.26, 0.36))
		_rng.seed = 55
		for k in 12:
			var y := k * size.y / 12.0
			var shade := 0.85 + _rng.randf() * 0.3
			draw_rect(Rect2(0, y + 1, size.x, size.y / 12.0 - 2), Color(0.30, 0.30, 0.42) * shade)
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.08, 0.08, 0.10), 2.0)
			var x := _rng.randf_range(40, 200)
			while x < size.x:
				draw_line(Vector2(x, y), Vector2(x, y + size.y / 12.0), Color(0.08, 0.08, 0.10), 2.0)
				x += _rng.randf_range(160, 300)

	# —— 招牌 ——

	func _sign_tavern() -> void:
		var size := Vector2(1024, 128)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.18, 0.42, 0.42))   # 青绿底招牌、奶黄字(和柔红灯罩互补)
		for k in 5:
			draw_line(Vector2(0, 10 + k * 26), Vector2(size.x, 14 + k * 26), Color(0.15, 0.36, 0.36), 2.0, true)
		draw_rect(Rect2(Vector2(8, 8), size - Vector2(16, 16)), DecorAtlas.GOLD, false, 4.0)
		draw_rect(Rect2(Vector2(16, 16), size - Vector2(32, 32)), Color(DecorAtlas.GOLD, 0.6), false, 1.5)
		var gold := Color(0.99, 0.86, 0.50)
		if _has_all(_glyph, "骗子酒馆"):
			_text(_glyph, "骗子酒馆", Vector2(300, 66), 78, gold, 460)
			_text(_latin, "LIAR'S TAVERN", Vector2(740, 68), 56, gold, 440)
		else:
			_text(_latin, "LIAR'S TAVERN", Vector2(size.x / 2.0, 68), 72, gold, 900)
		for x in [36.0, 988.0]:
			draw_circle(Vector2(x, 64), 9, gold)

	func _chalkboard() -> void:
		# 吧台边的粉笔菜单:只写酒名,不写价钱
		var size := Vector2(256, 192)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.20, 0.32, 0.30))
		_rng.seed = 404
		for i in 40:
			var p := Vector2(_rng.randf_range(8, size.x - 50), _rng.randf_range(8, size.y - 8))
			draw_line(p, p + Vector2(_rng.randf_range(10, 40), _rng.randf_range(-3, 3)), Color(0.8, 0.8, 0.75, 0.04), 6.0)
		var chalk := Color(0.86, 0.84, 0.76)
		_cn_or("今日供应", "TODAY", Vector2(size.x / 2.0, 30), 28, chalk, size.x - 30)
		draw_line(Vector2(40, 50), Vector2(size.x - 40, 50), Color(chalk, 0.7), 1.5, true)
		var lines := ["WHISKEY", "COLD BEER", "SARSAPARILLA", "BEANS & BREAD"]
		for k in lines.size():
			_text(_latin, lines[k], Vector2(size.x / 2.0, 72 + k * 28), 19, Color(chalk, 0.92), size.x - 40)
		draw_circle(Vector2(30, 72), 3, Color(0.9, 0.6, 0.5))
		draw_circle(Vector2(30, 100), 3, Color(0.9, 0.8, 0.5))

	func _sign_cheat() -> void:
		var size := Vector2(512, 128)
		_paper(size, DecorAtlas.PAPER, 31, false)
		draw_rect(Rect2(Vector2(10, 10), size - Vector2(20, 20)), DecorAtlas.INK, false, 3.0)
		var red := Color(0.84, 0.30, 0.28)
		if _has_all(_glyph, "不许出老千"):
			_text(_glyph, "不许出老千", Vector2(size.x / 2.0, 52), 52, red, 460)
			_text(_latin, "NO CHEATING", Vector2(size.x / 2.0, 98), 28, DecorAtlas.INK, 440)
		else:
			_text(_latin, "NO CHEATING", Vector2(size.x / 2.0, 64), 56, red, 460)
