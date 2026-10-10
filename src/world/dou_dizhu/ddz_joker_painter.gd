class_name DdzJokerPainter
extends PokerFacePainter
# 斗地主的两张王(原创插画,和德州 J/Q/K 同一家族):同样的暖奶油纸、粉彩内框、软描边、动森式 2 头身大头角色。
# - 大王:戴大金冠的大熊猫国王,莓红长袍 + 白貂毛领,一手举着顶端一颗星的金权杖,背后一圈淡淡的放射光;
# - 小王:歪戴小金冠的小浣熊王子,黑眼罩、白眉毛,藏青小斗篷,身后一条一圈一圈的大尾巴,举着一根星星小魔杖。
# 角标是竖排的「大 / 王」「小 / 王」(自己画的圆头粗笔画,不靠字体;大王莓红、小王藏青墨),下面一颗小星,右下角绕牌心转 180°。
# 坐标按 PokerFaceArt.SIZE(256×372)写,由 DdzJokerFaces 烘焙时整体放大;多边形靠离屏视口的 2D MSAA 抗锯齿。


const SMALL := 0
const BIG := 1
const PANEL := Rect2(66, 30, 124, 312)       # 王的画框比 J/Q/K 宽(角标只有一个字宽,左右各让出 10 像素以上的纸缝)
const PANEL_RADIUS := 34.0
const INDEX_X := 36.0                        # 角标字的中线
const INDEX_TOP := 15.0
const INDEX_GLYPH := 46.0                   # 一个字的方框边长
const INDEX_STROKE := 9.5                    # 笔画粗细(缩到手牌条的 66 像素宽时还有一个多像素)
const INDEX_GAP := 59.0                      # 两个字的行距
const INK_BIG := Color(0.86, 0.26, 0.4)      # 大王:暖莓红(同 ♥)
const INK_SMALL := Color(0.2, 0.22, 0.42)    # 小王:软藏青墨(同 ♠)
const PANDA_BLACK := Color(0.2, 0.18, 0.21)
const PANDA_WHITE := Color(1.0, 0.98, 0.95)
const RACCOON_FUR := Color(0.62, 0.58, 0.6)
const RACCOON_DARK := Color(0.3, 0.27, 0.3)
const RACCOON_LIGHT := Color(0.98, 0.96, 0.93)

var which := BIG


func _init(p_which: int) -> void:
	super(PokerCard.MIN_VALUE)
	which = p_which


func _draw() -> void:
	var ink := INK_BIG if which == BIG else INK_SMALL
	CardFaces.draw_paper(self, Rect2(Vector2.ZERO, size), CORNER_RADIUS, SPECKLE_SEED + 90 + which, SPECKLES)
	CardFaces.draw_rounded(self, _inset(FRAME_INSET), Color.TRANSPARENT, FRAME_RADIUS, FRAME_WIDTH,
		Color(pastel(ink, 0.55), 0.6), false)
	_draw_index(ink)
	draw_set_transform(size, PI, Vector2.ONE)   # 右下角标:绕牌心转 180°
	_draw_index(ink)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var panel := PokerFaceArt.rounded_rect(PANEL, PANEL_RADIUS)
	_shape(panel, pastel(ink, 0.87), 3.0, pastel(ink, 0.55))
	var clip: PackedVector2Array = Geometry2D.offset_polygon(panel, -2.0)[0]
	if which == BIG:
		_panda_king(clip, ink)
	else:
		_raccoon_prince(clip, ink)


static func index_lines(p_which: int) -> Array:
	return ["大", "王"] if p_which == BIG else ["小", "王"]


func _draw_index(ink: Color) -> void:
	# 竖排两个字(粗笔画、圆头,不依赖字体:各平台的系统字体不一样,缩到手牌条那么小也认得出)+ 一颗小星
	var lines := index_lines(which)
	for i in lines.size():
		var box := Rect2(INDEX_X - INDEX_GLYPH / 2.0, INDEX_TOP + i * INDEX_GAP, INDEX_GLYPH, INDEX_GLYPH)
		for stroke in glyph_strokes(lines[i], box):
			_stroke(stroke, ink.darkened(0.12), INDEX_STROKE + 2.0)
			_stroke(stroke, ink, INDEX_STROKE)
	var star_y := INDEX_TOP + INDEX_GAP * lines.size() + 10.0
	draw_colored_polygon(CardFaces.star_points(Vector2(INDEX_X, star_y), 13.0, 5.6), CardFaces.GOLD if which == BIG else pastel(ink, 0.35))
	draw_polyline(_closed(CardFaces.star_points(Vector2(INDEX_X, star_y), 13.0, 5.6)), ink.darkened(0.2), 1.6, true)


static func glyph_strokes(ch: String, box: Rect2) -> Array[PackedVector2Array]:
	# 「大」「小」「王」三个字的笔画(单位框坐标 0..1 换到 box 里),每笔一条折线
	var unit: Array = []
	match ch:
		"王":
			unit = [[Vector2(0.12, 0.1), Vector2(0.88, 0.1)], [Vector2(0.18, 0.5), Vector2(0.82, 0.5)],
				[Vector2(0.06, 0.9), Vector2(0.94, 0.9)], [Vector2(0.5, 0.1), Vector2(0.5, 0.9)]]
		"大":
			unit = [[Vector2(0.06, 0.34), Vector2(0.94, 0.34)],
				[Vector2(0.5, 0.04), Vector2(0.5, 0.36), Vector2(0.42, 0.62), Vector2(0.08, 0.95)],
				[Vector2(0.52, 0.5), Vector2(0.72, 0.76), Vector2(0.94, 0.95)]]
		"小":
			unit = [[Vector2(0.5, 0.04), Vector2(0.5, 0.88), Vector2(0.38, 0.96)],
				[Vector2(0.24, 0.36), Vector2(0.06, 0.74)], [Vector2(0.76, 0.36), Vector2(0.94, 0.72)]]
	var out: Array[PackedVector2Array] = []
	for line in unit:
		var pts := PackedVector2Array()
		for p in line:
			pts.append(box.position + p * box.size)
		out.append(pts)
	return out


static func _closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	out.append(poly[0])
	return out


# —— 大王:大熊猫国王 ——

func _panda_king(clip: PackedVector2Array, ink: Color) -> void:
	var cx := PANEL.get_center().x
	var robe := Color(0.86, 0.3, 0.4)
	var robe_dark := Color(0.7, 0.22, 0.32)
	# 背后一圈放射光(浅一档的粉),从头后面散开
	var glow_center := Vector2(cx, 150)
	for i in 14:
		var a0 := TAU * i / 14.0
		var a1 := a0 + TAU / 28.0
		var wedge := PackedVector2Array([glow_center, glow_center + Vector2(cos(a0), sin(a0)) * 260.0,
			glow_center + Vector2(cos(a1), sin(a1)) * 260.0])
		for piece in Geometry2D.intersect_polygons(wedge, clip):
			draw_colored_polygon(piece, Color(pastel(ink, 0.78), 0.55))
	for p in [Vector2(cx - 44, 58), Vector2(cx + 46, 74), Vector2(cx - 50, 250), Vector2(cx + 50, 318)]:
		_sparkle(p, 7.0, pastel(ink, 0.4))
	# 斗篷(身后铺开)、小脚
	_clipped(CardFaces.rounded_polygon(PackedVector2Array([Vector2(cx - 34, 206), Vector2(cx + 34, 206),
		Vector2(cx + 54, 316), Vector2(cx - 54, 316)]), 14.0), clip, robe_dark)
	for side in [-1.0, 1.0]:
		_shape(CardFaces.ellipse(Vector2(cx + side * 17, 312), 15, 9), PANDA_BLACK, 3.0)
	# 身子:莓红长袍,前襟一道金边,胸口一颗金星
	var body := CardFaces.rounded_polygon(PackedVector2Array([Vector2(cx - 30, 204), Vector2(cx + 30, 204),
		Vector2(cx + 42, 308), Vector2(cx - 42, 308)]), 15.0)
	_shape(body, robe)
	_stroke(PackedVector2Array([Vector2(cx, 222), Vector2(cx, 304)]), CardFaces.GOLD, 5.0)
	for k in 3:
		_disc(Vector2(cx, 240 + k * 22), 3.6, PANDA_WHITE, 1.8)
	# 权杖(右手,竖着举到肩膀上方):金杆 + 顶上一颗胖星星
	var top := Vector2(cx + 46, 150)
	_stroke(PackedVector2Array([Vector2(cx + 42, 296), top + Vector2(0, 14)]), OUTLINE, 9.0)
	_stroke(PackedVector2Array([Vector2(cx + 42, 296), top + Vector2(0, 14)]), CardFaces.GOLD, 5.0)
	var star := CardFaces.star_points(top, 17.0, 8.0)
	_shape(star, CardFaces.GOLD, 3.0)
	_disc(top + Vector2(0, 1), 4.0, Color(0.95, 0.4, 0.45), 1.8)
	# 两只黑胳膊(左手叉腰、右手握权杖)
	_shape(CardFaces.ellipse(Vector2(cx - 34, 238), 12, 21, 0.4), PANDA_BLACK, 3.0)
	_shape(CardFaces.ellipse(Vector2(cx + 36, 234), 12, 20, -0.5), PANDA_BLACK, 3.0)
	_disc(Vector2(cx + 42, 222), 9.5, PANDA_BLACK, 3.0)
	# 白貂毛领(带小黑点)
	_shape(CardFaces.ellipse(Vector2(cx, 206), 42, 12, 0.0, 36), PANDA_WHITE, 2.5)
	for i in 5:
		draw_colored_polygon(CardFaces.ellipse(Vector2(cx - 28 + i * 14, 207), 2.0, 3.2, 0.0, 12), PANDA_BLACK)
	# 大头(绕下巴放大)
	var pivot := Vector2(cx, 200)
	draw_set_transform(pivot * (1.0 - HEAD_SCALE), 0.0, Vector2.ONE * HEAD_SCALE)
	var h := Vector2(cx, 156)
	for side in [-1.0, 1.0]:
		_disc(h + Vector2(side * 32, -30), 14.0, PANDA_BLACK, 3.0)
	_shape(CardFaces.ellipse(h, 42, 36, 0.0, 56), PANDA_WHITE)
	draw_colored_polygon(CardFaces.ellipse(h + Vector2(-20, -18), 10, 5, -0.6), Color(1, 1, 1, 0.6))
	# 眼圈(八字形的黑眼斑)里一双亮晶晶的眼睛
	for side in [-1.0, 1.0]:
		draw_colored_polygon(CardFaces.ellipse(h + Vector2(side * 16, 0), 12.5, 15.5, side * -0.55), PANDA_BLACK)
		var e := h + Vector2(side * 15, 1)
		draw_colored_polygon(CardFaces.ellipse(e, 5.2, 6.4), Color(1, 1, 1))
		draw_colored_polygon(CardFaces.ellipse(e + Vector2(0, 0.6), 3.6, 4.6), EYE)
		draw_circle(e + Vector2(-1.4, -1.8), 1.6, Color.WHITE)
	draw_colored_polygon(CardFaces.rounded_polygon(PackedVector2Array([h + Vector2(-7, 13), h + Vector2(7, 13), h + Vector2(0, 20)]), 2.5),
		PANDA_BLACK)
	_stroke(PackedVector2Array([h + Vector2(-7, 23), h + Vector2(-3.5, 26), h + Vector2(0, 22.5), h + Vector2(3.5, 26),
		h + Vector2(7, 23)]), OUTLINE, 2.4)
	_blush(h + Vector2(0, 17), 28)
	# 大金冠:五个尖,中间红宝石,两侧青绿宝石,底下一圈白貂毛边
	var crown_base := h + Vector2(0, -30)
	_crown(crown_base, 60, 34, 5, Color(0.92, 0.36, 0.42))
	for side in [-1.0, 1.0]:
		_disc(crown_base + Vector2(side * 18, -5), 3.4, Color(0.3, 0.72, 0.68), 1.8)
	_shape(CardFaces.rounded_polygon(PackedVector2Array([crown_base + Vector2(-33, -2), crown_base + Vector2(33, -2),
		crown_base + Vector2(33, 7), crown_base + Vector2(-33, 7)]), 4.0), PANDA_WHITE, 2.5)
	for i in 4:
		draw_colored_polygon(CardFaces.ellipse(crown_base + Vector2(-21 + i * 14, 2.5), 1.8, 2.6, 0.0, 10), PANDA_BLACK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# —— 小王:小浣熊王子 ——

func _raccoon_prince(clip: PackedVector2Array, ink: Color) -> void:
	var cx := PANEL.get_center().x
	var cape := Color(0.24, 0.5, 0.56)
	var tunic := Color(0.33, 0.38, 0.62)
	for p in [Vector2(cx + 44, 60), Vector2(cx - 46, 86), Vector2(cx + 48, 262), Vector2(cx - 40, 322)]:
		_sparkle(p, 6.5, pastel(ink, 0.45))
	# 身后一条一圈一圈的大尾巴(从屁股绕到左边翘起来)
	var tail_path := []
	for k in 7:
		var t := k / 6.0
		tail_path.append(Vector2(cx - 20 - 32 * sin(t * 1.9), 300 - 120 * t))
	for k in tail_path.size():
		var radius := 17.0 - k * 0.6
		var fill := RACCOON_DARK if k % 2 == 1 else RACCOON_FUR
		for piece in Geometry2D.intersect_polygons(CardFaces.ellipse(tail_path[k], radius, radius * 0.92), clip):
			_shape(piece, fill, 3.0)
	_clipped(CardFaces.ellipse(tail_path[-1] + Vector2(-1, -11), 9.0, 8.0), clip, RACCOON_DARK)
	# 小斗篷、小脚
	_clipped(CardFaces.rounded_polygon(PackedVector2Array([Vector2(cx - 30, 210), Vector2(cx + 30, 210),
		Vector2(cx + 44, 306), Vector2(cx - 44, 306)]), 13.0), clip, cape)
	for side in [-1.0, 1.0]:
		_shape(CardFaces.ellipse(Vector2(cx + side * 15, 306), 13, 8), RACCOON_DARK, 3.0)
	# 身子:藏青小礼服,两排金纽扣,金腰带
	var body := CardFaces.rounded_polygon(PackedVector2Array([Vector2(cx - 26, 208), Vector2(cx + 26, 208),
		Vector2(cx + 34, 302), Vector2(cx - 34, 302)]), 13.0)
	_shape(body, tunic)
	_stroke(PackedVector2Array([Vector2(cx - 31, 268), Vector2(cx + 31, 268)]), CardFaces.GOLD, 5.0)
	for k in 2:
		for side in [-1.0, 1.0]:
			_disc(Vector2(cx + side * 9, 232 + k * 20), 3.2, CardFaces.GOLD, 1.8)
	# 星星小魔杖(右手往上挥),左爪叉腰
	var tip := Vector2(cx + 44, 172)
	_stroke(PackedVector2Array([Vector2(cx + 36, 238), tip + Vector2(0, 10)]), OUTLINE, 7.0)
	_stroke(PackedVector2Array([Vector2(cx + 36, 238), tip + Vector2(0, 10)]), Color(1.0, 0.95, 0.84), 3.6)
	_shape(CardFaces.star_points(tip, 13.0, 6.0), CardFaces.GOLD, 2.6)
	for k in 3:
		_sparkle(tip + Vector2(-14 + k * 14, -18 + absf(k - 1) * 6), 4.0, CardFaces.GOLD)
	_shape(CardFaces.ellipse(Vector2(cx - 30, 240), 10, 18, 0.45), RACCOON_FUR, 3.0)
	_shape(CardFaces.ellipse(Vector2(cx + 31, 228), 10, 18, -0.75), RACCOON_FUR, 3.0)
	_disc(Vector2(cx + 37, 236), 8.0, RACCOON_DARK, 3.0)
	# 小领结
	for side in [-1.0, 1.0]:
		_shape(CardFaces.rounded_polygon(PackedVector2Array([Vector2(cx, 212), Vector2(cx + side * 14, 204),
			Vector2(cx + side * 14, 220)]), 3.0), Color(0.95, 0.5, 0.42), 2.5)
	_disc(Vector2(cx, 212), 4.0, Color(0.95, 0.5, 0.42), 2.2)
	# 大头
	var pivot := Vector2(cx, 204)
	draw_set_transform(pivot * (1.0 - HEAD_SCALE), 0.0, Vector2.ONE * HEAD_SCALE)
	var h := Vector2(cx, 162)
	for side in [-1.0, 1.0]:
		var ear := CardFaces.rounded_polygon(PackedVector2Array([h + Vector2(side * 38, -10), h + Vector2(side * 30, -46),
			h + Vector2(side * 10, -30)]), 6.0)
		_shape(ear, RACCOON_FUR)
		draw_colored_polygon(CardFaces.rounded_polygon(PackedVector2Array([h + Vector2(side * 31, -16), h + Vector2(side * 28, -38),
			h + Vector2(side * 16, -28)]), 3.0), RACCOON_DARK)
	var face := CardFaces.ellipse(h, 40, 33, 0.0, 56)
	_shape(face, RACCOON_FUR)
	draw_colored_polygon(CardFaces.ellipse(h + Vector2(-18, -18), 9, 5, -0.6), Color(1, 1, 1, 0.4))
	# 白眉毛、白吻部
	for side in [-1.0, 1.0]:
		draw_colored_polygon(CardFaces.ellipse(h + Vector2(side * 15, -13), 11, 5.5, side * 0.25), RACCOON_LIGHT)
	_shape(CardFaces.ellipse(h + Vector2(0, 16), 19, 13), RACCOON_LIGHT, 2.5)
	# 黑眼罩:一条横过两眼的圆滚滚的带子
	var mask := PackedVector2Array()
	for poly in [CardFaces.ellipse(h + Vector2(-16, 1), 15, 10.5, 0.2), CardFaces.ellipse(h + Vector2(16, 1), 15, 10.5, -0.2)]:
		mask = poly if mask.is_empty() else Geometry2D.merge_polygons(mask, poly)[0]
	mask = Geometry2D.merge_polygons(mask, CardFaces.ellipse(h + Vector2(0, -1), 10, 6))[0]
	draw_colored_polygon(mask, RACCOON_DARK)
	for side in [-1.0, 1.0]:
		var e := h + Vector2(side * 15, 1)
		draw_colored_polygon(CardFaces.ellipse(e, 5.0, 6.0), Color(1, 1, 1))
		draw_colored_polygon(CardFaces.ellipse(e + Vector2(0, 0.6), 3.5, 4.4), EYE)
		draw_circle(e + Vector2(-1.3, -1.7), 1.5, Color.WHITE)
	draw_colored_polygon(CardFaces.ellipse(h + Vector2(0, 11), 5.5, 4.0), Color(0.24, 0.17, 0.16))
	_stroke(_arc(h + Vector2(0, 17), Vector2(6, 4.5), 0.25, PI - 0.25, 8), OUTLINE, 2.4)
	draw_colored_polygon(PackedVector2Array([h + Vector2(2.5, 20.5), h + Vector2(6.5, 20.5), h + Vector2(4.5, 24.5)]), Color.WHITE)
	_blush(h + Vector2(0, 14), 27)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 歪戴的小金冠(绕冠底转一点)
	var base := pivot + (h + Vector2(8, -30) - pivot) * HEAD_SCALE
	draw_set_transform(base, 0.28, Vector2.ONE * HEAD_SCALE)
	_crown(Vector2.ZERO, 34, 22, 3, Color(0.3, 0.72, 0.68))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
