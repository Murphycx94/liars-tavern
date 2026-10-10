class_name CardFaces
# 牌面纹理:启动时在离屏 SubViewport 中用矢量绘制 Q/K/A/鬼牌与牌背,抓取成带 mipmap 的贴图;
# 同一帧再画一遍烫金遮罩(金色画白、其余画黑)。3D 卡牌用两份数组纹理(层序见 LAYERS):牌面 face_array()、
# 烫金 foil_array();2D 界面仍用单张贴图 texture(kind)。
# 无渲染环境(headless)下抓图为空,退化为纯色纹理与 8×8 的替代数组,保证逻辑照常运行。
# 美术(道具二次打磨,2026-10-10):动森式「可爱、好认」——暖奶油纸、圆角粉彩内框、四角超大圆头角标、
# 中央一幅大插画(Q 戴王冠的猫皇后、K 披斗篷的熊国王、A 笑脸大星星、鬼 戴小丑帽的狐狸),烫金只留在王冠、星星、铃铛这些点缀上;
# 牌背是莓果色小花格 + 青绿底的五孔转轮徽章。全部原创,程序绘制。


const SIZE := Vector2i(360, 520)
const FOIL_SIZE := Vector2i(180, 260)
const BACK := -1
const CORNER_RADIUS := 44   # 动森式:圆角再加大(38 → 44,Card3D.CORNER 同比例)
const FONT_WEIGHT_BOLD := 700
const LAYERS := [BACK, Card.QUEEN, Card.KING, Card.ACE, Card.JOKER]   # 数组纹理的层序:0 = 牌背
const FALLBACK_SIZE := 8
const VIEWPORT_MSAA := Viewport.MSAA_4X   # 插画是多边形拼的,多边形自己不抗锯齿,靠离屏视口的 2D MSAA

# 每种牌一套颜色:ACCENTS 是角标与描边用的「墨色」(同色相里够深,纸上远看也清楚),
# TINTS 是插画圆盘的浅粉彩底,MIDS 是内框与衣服的中间色。粉红、天蓝、薄荷、淡紫,四张一眼分得清
const ACCENTS := {
	Card.QUEEN: Color(0.84, 0.29, 0.42),
	Card.KING: Color(0.2, 0.42, 0.78),
	Card.ACE: Color(0.1, 0.55, 0.45),
	Card.JOKER: Color(0.52, 0.32, 0.76),
}
const TINTS := {
	Card.QUEEN: Color(0.99, 0.87, 0.88),
	Card.KING: Color(0.85, 0.91, 0.99),
	Card.ACE: Color(0.85, 0.96, 0.9),
	Card.JOKER: Color(0.92, 0.88, 0.99),
}
const MIDS := {
	Card.QUEEN: Color(0.96, 0.6, 0.68),
	Card.KING: Color(0.48, 0.66, 0.94),
	Card.ACE: Color(0.42, 0.8, 0.66),
	Card.JOKER: Color(0.74, 0.6, 0.94),
}
const PAPER := Color(0.99, 0.96, 0.88)       # 暖奶油纸
const PAPER_EDGE := Color(0.9, 0.8, 0.62)
const CREAM := Color(0.97, 0.91, 0.76)       # 奶油外边(牌背在毡面上要靠它和桌面分开)
const CUT_LINE := Color(0.62, 0.46, 0.32)    # 外沿切线:暖棕,不是黑
const INK := Color(0.28, 0.2, 0.16)
const OUTLINE := Color(0.36, 0.24, 0.2)      # 插画描边:深可可色(动森式图标那种软描边)
const GOLD := Color(0.95, 0.75, 0.32)        # 奶黄烫金(只给王冠、星星、铃铛、牌背徽章)
const BACK_RED := Color(0.6, 0.24, 0.4)      # 牌背莓果底(名字沿用:德州 / 炸弹猫的小牌背图标也用它)
const BACK_LIGHT := Color(0.71, 0.35, 0.51)  # 牌背花格
const BACK_BADGE := Color(0.18, 0.5, 0.52)   # 牌背徽章的青绿底
const BACK_HOLE := Color(0.42, 0.13, 0.27)   # 弹膛孔:深一档的莓果色,不是近黑
const BLUSH := Color(1.0, 0.56, 0.62)

static var _textures := {}
static var _face_array: Texture2DArray = null
static var _foil_array: Texture2DArray = null
static var _fallback_faces: Texture2DArray = null
static var _fallback_foil: Texture2DArray = null
static var _building := false
static var _bleed_shader: Shader = null


static func chamber_points(center: Vector2, radius: float) -> PackedVector2Array:
	# 牌背上的弹巢:孔数与规则的膛数一致,第一个孔在正上方
	var points := PackedVector2Array()
	for i in Revolver.CHAMBERS:
		var a := -PI / 2 + TAU * i / Revolver.CHAMBERS
		points.append(center + Vector2(cos(a), sin(a)) * radius)
	return points


static func texture(kind: int) -> Texture2D:
	# 德州牌(取值 8–59)另有缓存与生成时机,转给 PokerFaces;-1 牌背与 0–3 骗子酒馆的牌仍在这里
	if PokerCard.is_card(kind):
		return PokerFaces.texture(kind)
	if DdzJokerFaces.is_kind(kind):
		return DdzJokerFaces.texture(kind)   # 斗地主的大王 / 小王(德州牌面那一家)
	if _textures.has(kind):
		return _textures[kind]
	return _fallback(kind)


static func layer(kind: int) -> int:
	# 牌型在数组纹理里的层;不认识的(德州牌)给牌背层
	return maxi(LAYERS.find(kind), 0)


static func face_array() -> Texture2DArray:
	if _face_array != null:
		return _face_array
	if _fallback_faces == null:
		var images: Array[Image] = []
		for kind in LAYERS:
			images.append(_fallback_image(kind))
		_fallback_faces = _array(images)
	return _fallback_faces


static func foil_array() -> Texture2DArray:
	if _foil_array != null:
		return _foil_array
	if _fallback_foil == null:
		var images: Array[Image] = []
		for kind in LAYERS:
			var image := Image.create(FALLBACK_SIZE, FALLBACK_SIZE, true, Image.FORMAT_R8)
			image.fill(Color.BLACK)
			images.append(image)
		_fallback_foil = _array(images)
	return _fallback_foil


static func clear() -> void:
	_bleed_shader = null
	_textures = {}
	_face_array = null
	_foil_array = null
	_fallback_faces = null
	_fallback_foil = null


static func is_built() -> bool:
	return _textures.size() == ACCENTS.size() + 1


static func build(host: Node) -> void:
	# 只需调用一次;并发调用时等待第一次完成
	if is_built():
		return
	if _building:
		while not is_built():
			await host.get_tree().process_frame
		return
	if DisplayServer.get_name() == "headless":
		# 无头模式的哑渲染器不会发出 frame_post_draw,直接使用纯色纹理(数组用替代图)
		for kind in LAYERS:
			_textures[kind] = _fallback(kind)
		return
	_building = true
	var viewports := []
	for foil in [false, true]:
		for kind in LAYERS:
			var vp := SubViewport.new()
			vp.size = SIZE
			vp.transparent_bg = not foil
			vp.msaa_2d = VIEWPORT_MSAA
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			if not foil:
				vp.add_child(bleed_backdrop(Vector2(SIZE)))
			var painter := CardPainter.new()
			painter.kind = kind
			painter.foil = foil
			painter.size = Vector2(SIZE)
			vp.add_child(painter)
			host.add_child(vp)
			viewports.append(vp)
	await RenderingServer.frame_post_draw
	await host.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var faces: Array[Image] = []
	var foils: Array[Image] = []
	var complete := true
	for i in LAYERS.size():
		var image: Image = viewports[i].get_texture().get_image()
		var mask: Image = viewports[i + LAYERS.size()].get_texture().get_image()
		if image == null or image.is_empty():
			_textures[LAYERS[i]] = _fallback(LAYERS[i])
			complete = false
		else:
			image.generate_mipmaps()
			_textures[LAYERS[i]] = ImageTexture.create_from_image(image)
			faces.append(image)
		if mask == null or mask.is_empty():
			complete = false
		else:
			mask.convert(Image.FORMAT_R8)
			mask.resize(FOIL_SIZE.x, FOIL_SIZE.y, Image.INTERPOLATE_LANCZOS)
			mask.generate_mipmaps()
			foils.append(mask)
	for vp in viewports:
		vp.queue_free()
	# 数组要求各层同尺寸:任意一张抓图为空就整组用替代图
	if complete:
		_face_array = _array(faces)
		_foil_array = _array(foils)
	_building = false


static func bleed_backdrop(rect_size: Vector2, edge := CUT_LINE) -> ColorRect:
	# 透明视口的「底色」:把牌外圆角处的透明像素的 RGB 写成牌边色(透明度仍是 0,不混合直接覆盖)。
	# 否则透明处是黑色,生成 mipmap 时黑色渗进牌边,远处与 2D 小牌的边缘会发脏、发暗,像一圈锯齿
	if _bleed_shader == null:
		_bleed_shader = Shader.new()
		_bleed_shader.code = "shader_type canvas_item;\nrender_mode blend_disabled;\n" \
			+ "uniform vec3 edge : source_color;\nvoid fragment() { COLOR = vec4(edge, 0.0); }\n"
	var mat := ShaderMaterial.new()
	mat.shader = _bleed_shader
	mat.set_shader_parameter("edge", edge)
	var rect := ColorRect.new()
	rect.size = rect_size
	rect.material = mat
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func _array(images: Array[Image]) -> Texture2DArray:
	var array := Texture2DArray.new()
	array.create_from_images(images)
	return array


static func _fallback_image(kind: int) -> Image:
	var image := Image.create(FALLBACK_SIZE, FALLBACK_SIZE, true, Image.FORMAT_RGBA8)
	image.fill(BACK_RED if kind == BACK else PAPER.lerp(ACCENTS.get(kind, INK), 0.3))
	return image


static func _fallback(kind: int) -> Texture2D:
	return ImageTexture.create_from_image(_fallback_image(kind))


static func letter_font() -> SystemFont:
	# 西文衬线体(墙饰招牌也用):与界面的西文衬线体同一组回退字体
	return _bold_font(UiTheme.FONT_LATIN_NAMES)


static func glyph_font() -> SystemFont:
	# 展示用楷体(墙饰招牌、炸弹猫牌名也用):与界面的展示用楷体同一组回退字体
	return _bold_font(UiTheme.FONT_DISPLAY_NAMES)


static func round_font() -> SystemFont:
	# 鬼牌角标的圆体:没有圆体的平台退到粗黑体(角标再描一圈同色边,笔画照样圆胖)
	var font := _bold_font(["Hiragino Maru Gothic ProN", "Yuanti SC", "YuanTi SC", "PingFang SC",
		"Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	font.font_weight = 800
	return font


static func _bold_font(names: Array) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(names)
	font.font_weight = FONT_WEIGHT_BOLD
	return font


static func draw_rounded(target: CanvasItem, rect: Rect2, fill: Color, radius: int, border := 0,
		border_color := Color.TRANSPARENT, draw_fill := true) -> void:
	# 抗锯齿的圆角矩形(可只画边框),骗子酒馆与德州牌面的纸底、纸边、金边都用它;只能在 target 的 _draw 里调用
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.draw_center = draw_fill
	box.set_corner_radius_all(radius)
	box.set_corner_detail(16)
	box.set_border_width_all(border)
	box.border_color = border_color
	box.anti_aliasing = true
	target.draw_style_box(box, rect)


static func draw_paper(target: CanvasItem, rect: Rect2, radius: int, seed_value: int, speckles: int) -> void:
	# 三种牌共用的纸:切线 + 暖奶油纸 + 极淡的纸纤维杂点 + 一圈很软的边缘压暗(做出纸的厚度感,不做旧)
	draw_rounded(target, rect, CUT_LINE, radius)
	draw_rounded(target, rect.grow(-2.0), PAPER, radius - 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var margin := radius * 0.4
	for i in speckles:
		var p := Vector2(rng.randf_range(rect.position.x + margin, rect.end.x - margin),
			rng.randf_range(rect.position.y + margin, rect.end.y - margin))
		var half := Vector2(rng.randf_range(0.5, 1.4), rng.randf_range(0.5, 1.4))
		target.draw_rect(Rect2(p - half, half * 2.0), Color(0.55, 0.42, 0.28, rng.randf_range(0.02, 0.05)))
	for i in 4:
		draw_rounded(target, rect.grow(-2.0 - i * 2.0), Color.TRANSPARENT, radius - 2 - i * 2, 2,
			Color(0.62, 0.48, 0.3, 0.05 - i * 0.01), false)


static func rank_glyph(rank: int, box: Rect2, stroke: float) -> Array[PackedVector2Array]:
	# 圆头粗笔画的点数字形(笔画中心线与德州角标同一套 PokerFaceArt.rank_strokes):
	# 不依赖字体,每台机器上都是同样圆胖的 Q / K / A;笔画外缘正好贴着 box
	var half := stroke / 2.0
	var inner := box.grow(-half)
	var polys: Array[PackedVector2Array] = []
	for line in PokerFaceArt.rank_strokes(rank):
		var pts := PackedVector2Array()
		for p in line:
			pts.append(inner.position + p * inner.size)
		polys.append_array(Geometry2D.offset_polyline(pts, half, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND))
	return polys


static func rounded_polygon(poly: PackedVector2Array, radius: float) -> PackedVector2Array:
	# 把多边形的凸角磨圆:先内缩再外扩(圆角连接)。星星的尖、王冠的齿都靠它变得软乎乎
	var shrunk := Geometry2D.offset_polygon(poly, -radius)
	if shrunk.is_empty():
		return poly
	var grown := Geometry2D.offset_polygon(shrunk[0], radius, Geometry2D.JOIN_ROUND)
	return grown[0] if not grown.is_empty() else poly


static func ellipse(center: Vector2, rx: float, ry: float, rot := 0.0, segments := 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var basis := Transform2D(rot, Vector2.ZERO)
	for i in segments:
		var a := TAU * i / segments
		pts.append(center + basis * Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func star_points(center: Vector2, outer: float, inner: float, points := 5, rot := -PI / 2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := rot + PI * i / points
		pts.append(center + Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	return pts


class CardPainter:
	extends Control
	# 单张牌面的矢量绘制;foil 时画烫金遮罩:底色全黑,金色画白、其余画黑

	const INDEX_BOX := Rect2(31, 31, 66, 98)     # 左上角标的点数框(约占牌高 19%;右下角标绕牌心转 180°)
	const INDEX_STROKE := 19.5
	const EMBLEM_CENTER := Vector2(64, 154)      # 角标点数下方的小标记
	const FRAME_INSET := 13.0                    # 圆角粉彩内框
	const FRAME_WIDTH := 5
	const DISC_CENTER := Vector2(180, 272)       # 中央插画的圆盘
	const DISC_RADIUS := 116.0
	const ART_SCALE := 1.1                       # 插画按 1.1 倍绕圆盘心放大(五官坐标按 1.0 写)
	const HEAD := Vector2(180, 268)              # 角色头心
	const LINE := 4.5                            # 插画描边粗细

	var kind := BACK
	var foil := false
	var _base := Transform2D.IDENTITY   # 插画的放大变换(王冠歪戴时在它上面再叠一层)
	var _round := CardFaces.round_font()

	func _draw() -> void:
		if foil:
			draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
		if kind == BACK:
			_draw_back()
		else:
			_draw_face()

	func _ink(color: Color) -> Color:
		# 遮罩模式:金色(任何透明度)→ 白,其余 → 黑,透明度不变
		if not foil:
			return color
		var gold := absf(color.r - CardFaces.GOLD.r) + absf(color.g - CardFaces.GOLD.g) + absf(color.b - CardFaces.GOLD.b) < 0.01
		return Color(1, 1, 1, color.a) if gold else Color(0, 0, 0, color.a)

	func _rounded(rect: Rect2, fill: Color, radius: int, border := 0, border_color := Color.TRANSPARENT,
			draw_fill := true) -> void:
		CardFaces.draw_rounded(self, rect, _ink(fill), radius, border, _ink(border_color), draw_fill)

	func _card_rect(inset: float) -> Rect2:
		return Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)

	func _shape(poly: PackedVector2Array, fill: Color, line := LINE, line_color := CardFaces.OUTLINE) -> void:
		# 填色 + 抗锯齿的软描边(动森式图标的画法)
		if poly.size() < 3:
			return
		draw_colored_polygon(poly, _ink(fill))
		if line > 0.0:
			var closed := poly.duplicate()
			closed.append(poly[0])
			draw_polyline(closed, _ink(line_color), line, true)

	func _disc(center: Vector2, radius: float, fill: Color, line := LINE, line_color := CardFaces.OUTLINE) -> void:
		_shape(CardFaces.ellipse(center, radius, radius, 0.0, maxi(24, int(radius * 1.2))), fill, line, line_color)

	func _stroke(points: PackedVector2Array, color: Color, width: float) -> void:
		# 圆头线:两端补圆
		draw_polyline(points, _ink(color), width, true)
		draw_circle(points[0], width * 0.5, _ink(color))
		draw_circle(points[points.size() - 1], width * 0.5, _ink(color))

	func _clipped(poly: PackedVector2Array, clip: PackedVector2Array, fill: Color, line := LINE) -> void:
		# 只画 poly 落在 clip 里的部分(衣服、斗篷收进插画圆盘)
		for piece in Geometry2D.intersect_polygons(poly, clip):
			if not Geometry2D.is_polygon_clockwise(piece):
				_shape(piece, fill, line)

	func _arc_points(center: Vector2, radius: Vector2, from: float, to: float, steps := 16) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in steps + 1:
			var a := lerpf(from, to, float(i) / steps)
			pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
		return pts

	func _sparkle(center: Vector2, radius: float, color: Color) -> void:
		# 四角亮晶晶:细腰的四芒星
		draw_colored_polygon(CardFaces.star_points(center, radius, radius * 0.32, 4, 0.0), _ink(color))

	# —— 牌面 ——

	func _draw_face() -> void:
		var accent: Color = CardFaces.ACCENTS[kind]
		var tint: Color = CardFaces.TINTS[kind]
		var mid: Color = CardFaces.MIDS[kind]
		if not foil:
			CardFaces.draw_paper(self, _card_rect(0), CardFaces.CORNER_RADIUS, 1234 + kind, 320)
		# 圆角粉彩内框:一道中间色的软框
		_rounded(_card_rect(FRAME_INSET), Color.TRANSPARENT, CardFaces.CORNER_RADIUS - int(FRAME_INSET),
			FRAME_WIDTH, Color(mid, 0.85), false)
		# 插画圆盘:浅粉彩底 + 中间色圆圈 + 一圈小圆点
		_disc(DISC_CENTER, DISC_RADIUS, tint, 6.0, mid)
		for i in 20:
			var a := TAU * (i + 0.5) / 20.0
			draw_circle(DISC_CENTER + Vector2(cos(a), sin(a)) * (DISC_RADIUS + 13.0), 2.6, _ink(Color(mid, 0.7)))
		_base = Transform2D(0.0, Vector2.ONE * ART_SCALE, 0.0, DISC_CENTER * (1.0 - ART_SCALE))
		draw_set_transform_matrix(_base)
		var r := (DISC_RADIUS - 3.0) / ART_SCALE
		var clip := CardFaces.ellipse(DISC_CENTER, r, r, 0.0, 96)
		match kind:
			Card.QUEEN:
				_queen_cat(clip, accent, mid)
			Card.KING:
				_king_bear(clip, accent, mid)
			Card.ACE:
				_ace_star(accent, mid)
			Card.JOKER:
				_jester_fox(clip, accent, mid)
		_base = Transform2D.IDENTITY
		draw_set_transform_matrix(_base)
		_corner_index(accent, mid, false)
		_corner_index(accent, mid, true)

	func _corner_index(accent: Color, mid: Color, flipped: bool) -> void:
		if flipped:
			draw_set_transform(size, PI, Vector2.ONE)
		if kind == Card.JOKER:
			_glyph_text("鬼", INDEX_BOX.get_center() + Vector2(4, 0), 74, accent)
		else:
			var rank: int = {Card.QUEEN: PokerCard.QUEEN, Card.KING: PokerCard.KING, Card.ACE: PokerCard.ACE}[kind]
			for poly in CardFaces.rank_glyph(rank, INDEX_BOX, INDEX_STROKE):
				draw_colored_polygon(poly, _ink(accent))
		_emblem(EMBLEM_CENTER, accent)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _glyph_text(text: String, center: Vector2, font_size: int, color: Color) -> void:
		# 圆体字再描一圈同色边:笔画更胖、转角更圆
		var text_size := _round.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var ascent := _round.get_ascent(font_size)
		var descent := _round.get_descent(font_size)
		var baseline := Vector2(center.x - text_size.x / 2.0, center.y + (ascent - descent) / 2.0)
		draw_string_outline(_round, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, _ink(color))
		draw_string(_round, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _ink(color))

	func _emblem(c: Vector2, accent: Color) -> void:
		# 角标下的小标记:Q 心、K 小王冠、A 星、鬼 菱形(小丑格)
		match kind:
			Card.QUEEN:
				draw_colored_polygon(_heart(c + Vector2(0, 1), 15.0), _ink(accent))
			Card.KING:
				var crown := PackedVector2Array([c + Vector2(-17, 12), c + Vector2(-19, -12), c + Vector2(-8, -2),
					c + Vector2(0, -16), c + Vector2(8, -2), c + Vector2(19, -12), c + Vector2(17, 12)])
				draw_colored_polygon(CardFaces.rounded_polygon(crown, 3.0), _ink(accent))
			Card.ACE:
				draw_colored_polygon(CardFaces.rounded_polygon(CardFaces.star_points(c, 17, 8), 2.0), _ink(accent))
			Card.JOKER:
				var d := PackedVector2Array([c + Vector2(0, -15), c + Vector2(12, 0), c + Vector2(0, 15), c + Vector2(-12, 0)])
				draw_colored_polygon(CardFaces.rounded_polygon(d, 2.5), _ink(accent))

	func _heart(c: Vector2, s: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 48:
			var t := TAU * i / 48.0
			pts.append(c + Vector2(16 * pow(sin(t), 3), -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))) * s / 17.0)
		return pts

	# —— 角色的五官(四张牌共用) ——

	func _eyes(c: Vector2, spread: float, lashes: bool) -> void:
		# 动森式大眼:深色竖椭圆 + 一大一小两个高光
		for side in [-1.0, 1.0]:
			var e := c + Vector2(side * spread, 0)
			draw_colored_polygon(CardFaces.ellipse(e, 9.5, 12.5), _ink(Color(0.22, 0.15, 0.13)))
			draw_circle(e + Vector2(-3, -4.5), 3.6, _ink(Color.WHITE))
			draw_circle(e + Vector2(3, 4.5), 1.8, _ink(Color.WHITE))
			if lashes:
				var root := e + Vector2(side * 8, -9)
				_stroke(PackedVector2Array([root, root + Vector2(side * 7, -5)]), CardFaces.OUTLINE, 3.0)
				_stroke(PackedVector2Array([root + Vector2(-side * 4, -3), root + Vector2(side * 1, -10)]), CardFaces.OUTLINE, 3.0)

	func _blush(c: Vector2, spread: float) -> void:
		for side in [-1.0, 1.0]:
			draw_colored_polygon(CardFaces.ellipse(c + Vector2(side * spread, 0), 12, 7), _ink(Color(CardFaces.BLUSH, 0.55)))

	func _w_mouth(c: Vector2, w: float) -> void:
		_stroke(PackedVector2Array([c + Vector2(-w, -2), c + Vector2(-w * 0.5, 3), c + Vector2(0, -1),
			c + Vector2(w * 0.5, 3), c + Vector2(w, -2)]), CardFaces.OUTLINE, 3.2)

	func _highlight(c: Vector2, rx: float, ry: float) -> void:
		draw_colored_polygon(CardFaces.ellipse(c, rx, ry, -0.6), _ink(Color(1, 1, 1, 0.32)))

	func _crown(base: Vector2, w: float, h: float, points: int, gem: Color) -> void:
		# 软乎乎的金王冠:齿尖磨圆,齿尖各一颗珍珠,冠带上一颗宝石
		var poly := PackedVector2Array([base + Vector2(-w / 2, 0)])
		for i in points:
			var x := -w / 2 + w * (i + 0.5) / points
			poly.append(base + Vector2(x - w / points * 0.5, -h * 0.42))
			poly.append(base + Vector2(x, -h))
		poly.append(base + Vector2(w / 2, -h * 0.42))
		poly.append(base + Vector2(w / 2, 0))
		_shape(CardFaces.rounded_polygon(poly, 4.0), CardFaces.GOLD)
		for i in points:
			var x := -w / 2 + w * (i + 0.5) / points
			_disc(base + Vector2(x, -h - 2), 6.0, Color(1.0, 0.97, 0.9), 3.0)
		_rounded(Rect2(base + Vector2(-w / 2 + 2, -12), Vector2(w - 4, 10)), CardFaces.GOLD.darkened(0.12), 4)
		_disc(base + Vector2(0, -7), 7.0, gem, 3.0)
		draw_circle(base + Vector2(-2, -9), 2.2, _ink(Color(1, 1, 1, 0.8)))

	# —— 插画 ——

	func _queen_cat(clip: PackedVector2Array, accent: Color, mid: Color) -> void:
		# Q:猫皇后。粉色小礼服 + 白色花边领,奶白小猫(一只耳朵是蜜桃色花斑),歪戴一顶小金冠,长睫毛
		var h := HEAD
		var fur := Color(1.0, 0.98, 0.94)
		var patch := Color(0.98, 0.76, 0.56)
		_clipped(CardFaces.ellipse(h + Vector2(0, 128), 92, 70), clip, mid)
		var collar := PackedVector2Array()
		for i in 9:
			var x := -60.0 + i * 15.0
			collar.append_array(_arc_points(h + Vector2(x, 62), Vector2(9, 9), PI, 0.0, 6))
		collar.append(h + Vector2(66, 74))
		collar.append(h + Vector2(-66, 74))
		_clipped(collar, clip, Color(1, 1, 1), 3.5)
		for side in [-1.0, 1.0]:
			var ear := PackedVector2Array([h + Vector2(side * 66, -18), h + Vector2(side * 58, -84), h + Vector2(side * 16, -54)])
			_shape(CardFaces.rounded_polygon(ear, 7.0), patch if side < 0 else fur)
			var inner := PackedVector2Array([h + Vector2(side * 56, -28), h + Vector2(side * 54, -68), h + Vector2(side * 28, -50)])
			draw_colored_polygon(CardFaces.rounded_polygon(inner, 4.0), _ink(Color(1.0, 0.72, 0.76)))
		var head := CardFaces.ellipse(h, 74, 60, 0.0, 64)
		_shape(head, fur)
		# 额头上一块蜜桃色花斑
		for piece in Geometry2D.intersect_polygons(CardFaces.ellipse(h + Vector2(-46, -40), 36, 30, 0.4), head):
			draw_colored_polygon(piece, _ink(patch))
		var closed := head.duplicate()
		closed.append(head[0])
		draw_polyline(closed, _ink(CardFaces.OUTLINE), LINE, true)
		_highlight(h + Vector2(-34, -30), 16, 9)
		_eyes(h + Vector2(0, 4), 28, true)
		_blush(h + Vector2(0, 24), 46)
		draw_colored_polygon(CardFaces.rounded_polygon(PackedVector2Array([h + Vector2(-7, 14), h + Vector2(7, 14),
			h + Vector2(0, 22)]), 2.0), _ink(Color(0.95, 0.5, 0.58)))
		_w_mouth(h + Vector2(0, 28), 10)
		for side in [-1.0, 1.0]:
			for k in 2:
				var from := h + Vector2(side * 52, 14 + k * 9)
				_stroke(PackedVector2Array([from, from + Vector2(side * 22, -3 + k * 6)]), Color(CardFaces.OUTLINE, 0.6), 2.4)
		draw_set_transform_matrix(_base * Transform2D(0.16, h + Vector2(10, -56)))
		_crown(Vector2.ZERO, 66, 44, 3, accent)
		draw_set_transform_matrix(_base)
		_sparkle(DISC_CENTER + Vector2(-82, -50), 11, CardFaces.GOLD)
		_sparkle(DISC_CENTER + Vector2(86, 30), 8, Color(1, 1, 1, 0.9))
		_disc(h + Vector2(46, 58), 8.0, accent, 3.0)   # 礼服上的小蝴蝶结扣

	func _king_bear(clip: PackedVector2Array, accent: Color, mid: Color) -> void:
		# K:熊国王。天蓝斗篷 + 白貂毛领(带小黑点),棕熊圆耳、浅色吻部,头顶一顶三齿大金冠
		var h := HEAD + Vector2(0, 6)
		var fur := Color(0.78, 0.55, 0.38)
		var light := Color(0.97, 0.86, 0.7)
		_clipped(CardFaces.ellipse(h + Vector2(0, 132), 104, 76), clip, mid)
		_clipped(CardFaces.ellipse(h + Vector2(0, 132), 26, 76), clip, accent, 3.5)
		var ermine := CardFaces.ellipse(h + Vector2(0, 66), 78, 20, 0.0, 48)
		_clipped(ermine, clip, Color(1, 0.99, 0.96), 3.5)
		for i in 5:
			draw_colored_polygon(CardFaces.ellipse(h + Vector2(-48 + i * 24, 68 + (i % 2) * 4), 3.2, 5.0), _ink(CardFaces.INK))
		for side in [-1.0, 1.0]:
			_disc(h + Vector2(side * 56, -44), 23.0, fur)
			draw_colored_polygon(CardFaces.ellipse(h + Vector2(side * 56, -44), 12, 12), _ink(light))
		_shape(CardFaces.ellipse(h, 72, 62, 0.0, 64), fur)
		_highlight(h + Vector2(-34, -30), 16, 9)
		_shape(CardFaces.ellipse(h + Vector2(0, 24), 32, 23), light, 3.5)
		draw_colored_polygon(CardFaces.ellipse(h + Vector2(0, 13), 12, 8.5), _ink(Color(0.3, 0.19, 0.15)))
		draw_circle(h + Vector2(-3, 10), 2.4, _ink(Color(1, 1, 1, 0.7)))
		_stroke(_arc_points(h + Vector2(0, 26), Vector2(9, 6), 0.3, PI - 0.3, 8), CardFaces.OUTLINE, 3.2)
		_eyes(h + Vector2(0, -6), 29, false)
		_blush(h + Vector2(0, 16), 48)
		_crown(h + Vector2(0, -50), 84, 54, 3, Color(0.92, 0.36, 0.42))
		_sparkle(DISC_CENTER + Vector2(84, -56), 11, CardFaces.GOLD)
		_sparkle(DISC_CENTER + Vector2(-88, 22), 8, Color(1, 1, 1, 0.9))
		_disc(h + Vector2(0, 92), 9.0, CardFaces.GOLD, 3.0)   # 斗篷的金扣

	func _ace_star(accent: Color, mid: Color) -> void:
		# A:一颗圆胖的笑脸大星星,背后一圈薄荷色光芒,四周撒亮晶晶
		var c := DISC_CENTER + Vector2(0, 6)
		for i in 10:
			var a := -PI / 2 + TAU * (i + 0.5) / 10.0
			var ray := PackedVector2Array([c + Vector2(cos(a - 0.09), sin(a - 0.09)) * 70.0,
				c + Vector2(cos(a), sin(a)) * 104.0, c + Vector2(cos(a + 0.09), sin(a + 0.09)) * 70.0])
			draw_colored_polygon(CardFaces.rounded_polygon(ray, 3.0), _ink(Color(mid, 0.55)))
		var star := CardFaces.rounded_polygon(CardFaces.star_points(c, 96, 46), 13.0)
		_shape(star, CardFaces.GOLD, 5.0)
		# 星星的软阴影面(右下半边略深)与高光
		for piece in Geometry2D.intersect_polygons(star, CardFaces.ellipse(c + Vector2(40, 46), 80, 70)):
			draw_colored_polygon(piece, _ink(Color(CardFaces.GOLD.darkened(0.12), 1.0)))
		var closed := star.duplicate()
		closed.append(star[0])
		draw_polyline(closed, _ink(CardFaces.OUTLINE), 5.0, true)
		_highlight(c + Vector2(-24, -30), 14, 8)
		# 笑脸:眯眼弯弯 + 张嘴笑 + 腮红
		for side in [-1.0, 1.0]:
			_stroke(_arc_points(c + Vector2(side * 22, 4), Vector2(9, 8), PI + 0.2, TAU - 0.2, 10), CardFaces.OUTLINE, 4.5)
		var mouth := _arc_points(c + Vector2(0, 16), Vector2(13, 12), 0.0, PI, 12)
		_shape(mouth, Color(0.86, 0.38, 0.4), 3.5)
		_blush(c + Vector2(0, 20), 38)
		_sparkle(DISC_CENTER + Vector2(-84, -62), 14, CardFaces.GOLD)
		_sparkle(DISC_CENTER + Vector2(80, -72), 9, Color(1, 1, 1, 0.95))
		_sparkle(DISC_CENTER + Vector2(88, 64), 12, CardFaces.GOLD)
		_sparkle(DISC_CENTER + Vector2(-78, 74), 8, Color(1, 1, 1, 0.95))

	func _jester_fox(clip: PackedVector2Array, accent: Color, mid: Color) -> void:
		# 鬼:戴两角小丑帽的狐狸。淡紫 / 薄荷撞色的帽子和锯齿领,铃铛是烫金;眯着一只眼坏笑,露一颗小虎牙
		var h := HEAD + Vector2(0, 10)
		var fur := Color(0.98, 0.64, 0.38)
		var white := Color(1.0, 0.97, 0.92)
		var mint := Color(0.5, 0.84, 0.74)
		# 锯齿领
		var points := 7
		for i in points:
			var x0 := -105.0 + i * 30.0
			var tri := PackedVector2Array([h + Vector2(x0, 58), h + Vector2(x0 + 30, 58), h + Vector2(x0 + 15, 108)])
			_clipped(CardFaces.rounded_polygon(tri, 3.0), clip, mid if i % 2 == 0 else mint, 3.5)
		# 帽子的两只角(先画,脸压在上面)
		var horns := [
			[Vector2(-20, -52), Vector2(-78, -88), Vector2(-94, -36), Vector2(-60, -30), mid],
			[Vector2(20, -52), Vector2(78, -88), Vector2(94, -36), Vector2(60, -30), mint],
		]
		var tips: Array[Vector2] = []
		for horn in horns:
			var base_a: Vector2 = h + horn[0]
			var tip: Vector2 = h + horn[1]
			var bulge: Vector2 = h + horn[2]
			var base_b: Vector2 = h + horn[3]
			var poly := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				poly.append(base_a.lerp(tip, t) + (tip - base_a).orthogonal().normalized() * sin(t * PI) * 8.0 * signf(horn[0].x))
			for i in 13:
				var t := float(i) / 12.0
				var u := 1.0 - t
				poly.append(tip * u * u + bulge * 2.0 * u * t + base_b * t * t)
			_shape(poly, horn[4])
			tips.append(tip)
		# 脸:上宽下尖的狐狸脸,两颊白毛
		var face := CardFaces.rounded_polygon(PackedVector2Array([h + Vector2(-78, -14), h + Vector2(-52, -50),
			h + Vector2(52, -50), h + Vector2(78, -14), h + Vector2(38, 40), h + Vector2(0, 60), h + Vector2(-38, 40)]), 20.0)
		_shape(face, fur)
		for side in [-1.0, 1.0]:
			var cheek := CardFaces.ellipse(h + Vector2(side * 38, 30), 40, 30, side * 0.5)
			for piece in Geometry2D.intersect_polygons(cheek, face):
				draw_colored_polygon(piece, _ink(white))
		var closed := face.duplicate()
		closed.append(face[0])
		draw_polyline(closed, _ink(CardFaces.OUTLINE), LINE, true)
		# 帽檐:一条带菱形的帽带
		var band := CardFaces.rounded_polygon(PackedVector2Array([h + Vector2(-70, -58), h + Vector2(70, -58),
			h + Vector2(62, -36), h + Vector2(-62, -36)]), 6.0)
		_shape(band, accent)
		for i in 3:
			var d := h + Vector2(-34 + i * 34, -47)
			draw_colored_polygon(PackedVector2Array([d + Vector2(0, -8), d + Vector2(7, 0), d + Vector2(0, 8),
				d + Vector2(-7, 0)]), _ink(CardFaces.GOLD))
		for tip in tips:
			_disc(tip, 12.0, CardFaces.GOLD)
			draw_line(tip + Vector2(-5, 3), tip + Vector2(5, 3), _ink(CardFaces.OUTLINE), 2.5, true)
			draw_circle(tip + Vector2(-4, -4), 2.5, _ink(Color(1, 1, 1, 0.8)))
		_highlight(h + Vector2(-38, -24), 14, 7)
		# 眼睛:左眼眯成一道弯,右眼大眼眨巴,眉毛挑起来
		_stroke(_arc_points(h + Vector2(-26, -2), Vector2(10, 7), PI + 0.3, TAU - 0.3, 10), CardFaces.OUTLINE, 4.5)
		var e := h + Vector2(26, -4)
		draw_colored_polygon(CardFaces.ellipse(e, 9.5, 12.0), _ink(Color(0.22, 0.15, 0.13)))
		draw_circle(e + Vector2(-3, -4), 3.4, _ink(Color.WHITE))
		draw_circle(e + Vector2(3, 4), 1.7, _ink(Color.WHITE))
		_stroke(PackedVector2Array([h + Vector2(14, -24), h + Vector2(38, -28)]), CardFaces.OUTLINE, 4.0)
		_stroke(PackedVector2Array([h + Vector2(-38, -20), h + Vector2(-16, -16)]), CardFaces.OUTLINE, 4.0)
		# 鼻子与坏笑
		draw_colored_polygon(CardFaces.ellipse(h + Vector2(0, 20), 9, 6.5), _ink(Color(0.3, 0.19, 0.15)))
		var grin := PackedVector2Array()
		grin.append_array(_arc_points(h + Vector2(2, 30), Vector2(26, 16), 0.15, PI - 0.15, 14))
		_shape(grin, Color(0.55, 0.22, 0.24), 3.5)
		draw_colored_polygon(CardFaces.ellipse(h + Vector2(4, 40), 10, 4.5), _ink(Color(0.98, 0.56, 0.6)))
		draw_colored_polygon(PackedVector2Array([h + Vector2(12, 32), h + Vector2(20, 32), h + Vector2(16, 40)]),
			_ink(Color.WHITE))
		_blush(h + Vector2(0, 16), 50)
		_sparkle(DISC_CENTER + Vector2(-86, 54), 10, CardFaces.GOLD)
		_sparkle(DISC_CENTER + Vector2(84, 58), 8, Color(1, 1, 1, 0.9))

	# —— 牌背 ——

	func _draw_back() -> void:
		# 奶油外边(在毡面上和桌面分开)+ 莓果底小花格 + 奶油内框 + 中央青绿底五孔转轮徽章
		_rounded(_card_rect(0), CardFaces.CUT_LINE, CardFaces.CORNER_RADIUS)
		_rounded(_card_rect(2), CardFaces.CREAM, CardFaces.CORNER_RADIUS - 2)
		var field := _card_rect(13)
		var field_radius := CardFaces.CORNER_RADIUS - 13
		_rounded(field, CardFaces.BACK_RED, field_radius)
		# 花格:错开排列的圆角小菱形 + 中间的小圆点,裁在底色的圆角矩形里
		var clip := _rounded_rect_polygon(field.grow(-6.0), field_radius - 6)
		var step := Vector2(36, 36)
		var row := 0
		var y := field.position.y - step.y
		while y < field.end.y + step.y:
			var x := field.position.x - step.x + (step.x / 2.0 if row % 2 == 1 else 0.0)
			while x < field.end.x + step.x:
				var p := Vector2(x, y)
				var diamond := CardFaces.rounded_polygon(PackedVector2Array([p + Vector2(0, -9), p + Vector2(9, 0),
					p + Vector2(0, 9), p + Vector2(-9, 0)]), 2.5)
				for piece in Geometry2D.intersect_polygons(diamond, clip):
					draw_colored_polygon(piece, _ink(CardFaces.BACK_LIGHT))
				var dot := p + step / 2.0
				if Geometry2D.is_point_in_polygon(dot, clip):
					draw_circle(dot, 2.6, _ink(Color(CardFaces.CREAM, 0.45)))
				x += step.x
			y += step.y
			row += 1
		_rounded(_card_rect(22), Color.TRANSPARENT, field_radius - 9, 4, Color(CardFaces.CREAM, 0.9), false)
		for corner in 4:
			var flip := Vector2(1 if corner % 2 == 0 else -1, 1 if corner < 2 else -1)
			var origin := Vector2(0 if corner % 2 == 0 else size.x, 0 if corner < 2 else size.y)
			_sparkle(origin + Vector2(46, 46) * flip, 11.0, CardFaces.GOLD)
		# 中央徽章:奶油圆圈 + 金边,青绿底上一只圆鼓鼓的金色转轮(5 道凹槽、5 个弹膛,第一个在 12 点)
		var center := size / 2.0
		_disc(center, 98.0, CardFaces.CREAM, 0.0)
		_disc(center, 90.0, CardFaces.BACK_BADGE, 5.0, CardFaces.GOLD)
		for i in 15:
			var a := TAU * (i + 0.5) / 15.0
			draw_circle(center + Vector2(cos(a), sin(a)) * 94.0, 2.2, _ink(CardFaces.BACK_RED))
		var drum := PackedVector2Array()
		for i in 120:
			var a := -PI / 2 + TAU * i / 120.0
			# 凹槽在两个弹膛之间(相对弹膛转半格):那里半径收 8 像素,其余是圆
			var notch := pow(maxf(0.0, -cos((a + PI / 2) * Revolver.CHAMBERS)), 6.0)
			drum.append(center + Vector2(cos(a), sin(a)) * (64.0 - 12.0 * notch))
		_shape(drum, CardFaces.GOLD, 4.5, CardFaces.BACK_HOLE)
		for piece in Geometry2D.intersect_polygons(drum, CardFaces.ellipse(center + Vector2(26, 30), 60, 52)):
			draw_colored_polygon(piece, _ink(Color(CardFaces.GOLD.darkened(0.12), 1.0)))
		var closed := drum.duplicate()
		closed.append(drum[0])
		draw_polyline(closed, _ink(CardFaces.BACK_HOLE), 4.5, true)
		for p in CardFaces.chamber_points(center, 34.0):
			_disc(p, 13.0, CardFaces.BACK_HOLE, 0.0)
			draw_circle(p + Vector2(-4, -4), 3.0, _ink(Color(1, 1, 1, 0.35)))
		_disc(center, 9.0, CardFaces.GOLD, 3.5, CardFaces.BACK_HOLE)
		_highlight(center + Vector2(-30, -34), 12, 6)

	func _rounded_rect_polygon(rect: Rect2, radius: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var corners := [Vector2(rect.end.x - radius, rect.position.y + radius), Vector2(rect.end.x - radius, rect.end.y - radius),
			Vector2(rect.position.x + radius, rect.end.y - radius), Vector2(rect.position.x + radius, rect.position.y + radius)]
		for c in 4:
			for k in 9:
				var a := -PI / 2 + c * PI / 2 + PI / 2 * k / 8.0
				pts.append(corners[c] + Vector2(cos(a), sin(a)) * radius)
		return pts
