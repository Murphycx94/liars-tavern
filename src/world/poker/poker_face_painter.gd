class_name PokerFacePainter
extends Control
# 单张德州牌面(或德州牌背)的绘制,放进离屏 SubViewport 抓图。动森式重画(2026-10-10):
# 纸与骗子酒馆的新牌同一家族(CardFaces.draw_paper:暖奶油纸、暖棕切线、极淡纸纤维、一圈软压暗),
# 内框是花色浅色的圆角软框;角标与花色的位置全部来自 PokerFaceArt 的多边形,花色带软描边与一点高光;
# 数字牌空角上点一颗小亮晶晶;A 是一枚大花色(♠A 是带圆盘、笑脸与星星的大徽章);
# J/Q/K 的画框里是角色:狐狸侍从、猫皇后、熊国王,衣服用花色的粉彩色,胸口一枚花色。
# 牌背(card == BACK):软藏青底 + 浅色小花色花格 + 奶油内框,中央奶油圈里一枚莓果色筹码。
# 画家按 PokerFaceArt.SIZE 的坐标画,烘焙时由 scale 整体放大到 PokerFaces.SIZE;多边形靠视口的 2D MSAA 抗锯齿。


const BACK := -1
const CORNER_RADIUS := 31          # 与 CardFaces 的圆角同比例(44/360 ≈ 31/256)
const FRAME_INSET := 5.0           # 内框贴着纸边走,给角标让出地方
const FRAME_WIDTH := 3
const FRAME_RADIUS := CORNER_RADIUS - int(FRAME_INSET)   # 与牌的圆角同心
const SPECKLES := 160              # 纸面杂点(按面积从 CardFaces 的 320 折算)
const SPECKLE_SEED := 4321         # 杂点随机种子的基数(加牌值;与 CardFaces 的 1234 错开,同一张牌每次生成都一样)
const PIP_LINE := 2.2              # 花色的软描边(深一档的同色)
const LINE := 3.5                  # 角色插画的描边
const HEAD_SCALE := 1.14           # 角色的头再放大一点(动森式大头)
const OUTLINE := CardFaces.OUTLINE
const EYE := Color(0.22, 0.15, 0.13)
const BACK_FIELD := Color(0.22, 0.27, 0.46)    # 牌背软藏青
const BACK_PATTERN := Color(0.3, 0.36, 0.56)
const CHIP := Color(0.86, 0.32, 0.44)          # 牌背筹码:莓果色

var card := PokerCard.MIN_VALUE


func _init(p_card: int) -> void:
	card = p_card
	size = Vector2(PokerFaceArt.SIZE)


func _draw() -> void:
	if card == BACK:
		_draw_back()
		return
	var art := PokerFaceArt.layout(card)
	var ink: Color = art["ink"]
	CardFaces.draw_paper(self, Rect2(Vector2.ZERO, size), CORNER_RADIUS, SPECKLE_SEED + card, SPECKLES)
	CardFaces.draw_rounded(self, _inset(FRAME_INSET), Color.TRANSPARENT, FRAME_RADIUS, FRAME_WIDTH,
		Color(pastel(ink, 0.55), 0.6), false)
	for poly in art["index"]:
		draw_colored_polygon(poly, ink)
	var rank := PokerCard.rank(card)
	if not art["panel"].is_empty():
		_draw_court(rank, PokerCard.suit(card), ink, art["panel"])
	elif art["emblem"]:
		_draw_spade_emblem(ink, art["pips"][0])
	else:
		if rank == PokerCard.ACE:
			_disc(PokerFaceArt.CENTER, 58.0, pastel(ink, 0.86), 2.5, pastel(ink, 0.6))
		for pip in art["pips"]:
			_draw_pip(pip, ink)
		_doodles(ink)


static func pastel(ink: Color, amount: float) -> Color:
	# 花色往暖奶油纸里混:amount 越大越浅
	return ink.lerp(CardFaces.PAPER, amount)


func _inset(amount: float) -> Rect2:
	return Rect2(Vector2(amount, amount), size - Vector2(amount, amount) * 2.0)


# —— 基本形 ——

func _shape(poly: PackedVector2Array, fill: Color, line := LINE, line_color := OUTLINE) -> void:
	if poly.size() < 3:
		return
	draw_colored_polygon(poly, fill)
	if line > 0.0:
		var closed := poly.duplicate()
		closed.append(poly[0])
		draw_polyline(closed, line_color, line, true)


func _disc(center: Vector2, radius: float, fill: Color, line := LINE, line_color := OUTLINE) -> void:
	_shape(CardFaces.ellipse(center, radius, radius, 0.0, maxi(24, int(radius * 1.3))), fill, line, line_color)


func _stroke(points: PackedVector2Array, color: Color, width: float) -> void:
	draw_polyline(points, color, width, true)
	draw_circle(points[0], width * 0.5, color)
	draw_circle(points[points.size() - 1], width * 0.5, color)


func _arc(center: Vector2, radius: Vector2, from: float, to: float, steps := 12) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(from, to, float(i) / steps)
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	return pts


func _sparkle(center: Vector2, radius: float, color: Color) -> void:
	draw_colored_polygon(CardFaces.star_points(center, radius, radius * 0.32, 4, 0.0), color)


func _clipped(poly: PackedVector2Array, clip: PackedVector2Array, fill: Color, line := LINE) -> void:
	for piece in Geometry2D.intersect_polygons(poly, clip):
		if not Geometry2D.is_polygon_clockwise(piece):
			_shape(piece, fill, line)


# —— 花色 ——

func _draw_pip(parts: Array, ink: Color) -> void:
	# 胖花色:先把每块外扩一圈画深一档的软描边,再填本色,左上点一处高光
	var edge := ink.darkened(0.28)
	for poly in parts:
		for grown in Geometry2D.offset_polygon(poly, PIP_LINE, Geometry2D.JOIN_ROUND):
			if not Geometry2D.is_polygon_clockwise(grown):
				draw_colored_polygon(grown, edge)
	for poly in parts:
		draw_colored_polygon(poly, ink)
	var bounds := _bounds_of(parts)
	draw_colored_polygon(CardFaces.ellipse(bounds.position + bounds.size * Vector2(0.3, 0.3),
		bounds.size.x * 0.12, bounds.size.y * 0.07, -0.6), Color(1, 1, 1, 0.32))


func _doodles(ink: Color) -> void:
	# 数字牌的空角(右上、左下)各点一颗小亮晶晶,和一粒小圆点
	var soft := pastel(ink, 0.5)
	_sparkle(Vector2(214, 50), 10.0, soft)
	draw_circle(Vector2(196, 74), 3.0, soft)
	_sparkle(Vector2(256, 372) - Vector2(214, 50), 10.0, soft)
	draw_circle(Vector2(256, 372) - Vector2(196, 74), 3.0, soft)


func _draw_spade_emblem(ink: Color, parts: Array) -> void:
	# ♠A:粉彩圆盘 + 一圈小圆点 + 一枚大黑桃(带软描边和高光)+ 奶油色小笑脸 + 金色亮晶晶
	var c := PokerFaceArt.CENTER
	_disc(c, 56.0, pastel(ink, 0.86), 3.0, pastel(ink, 0.55))
	for i in 16:
		var a := TAU * (i + 0.5) / 16.0
		draw_circle(c + Vector2(cos(a), sin(a)) * 64.0, 2.2, pastel(ink, 0.55))
	_draw_pip(parts, ink)
	var face := c + Vector2(0, 6)
	for side in [-1.0, 1.0]:
		draw_colored_polygon(CardFaces.ellipse(face + Vector2(side * 11, 0), 4.0, 5.2), CardFaces.PAPER)
		draw_colored_polygon(CardFaces.ellipse(face + Vector2(side * 21, 9), 6.0, 3.5), Color(CardFaces.BLUSH, 0.75))
	_stroke(_arc(face + Vector2(0, 7), Vector2(5, 4), 0.25, PI - 0.25, 8), CardFaces.PAPER, 2.6)
	_sparkle(c + Vector2(-48, -50), 9.0, CardFaces.GOLD)
	_sparkle(c + Vector2(50, 46), 7.0, CardFaces.GOLD)


# —— 角色(J/Q/K) ——

func _draw_court(rank: int, suit: int, ink: Color, panel: PackedVector2Array) -> void:
	var tint := pastel(ink, 0.86)
	var robe := pastel(ink, 0.42)
	_shape(panel, tint, 3.0, pastel(ink, 0.55))
	var clip := Geometry2D.offset_polygon(panel, -2.0)[0]
	var cx := PokerFaceArt.CENTER.x
	# 身子(动森式 2 头身):上窄下宽的圆角小袍子,两只小胳膊,一双小脚;胸口一枚花色
	for side in [-1.0, 1.0]:
		_shape(CardFaces.ellipse(Vector2(cx + side * 15, 290), 13, 8), Color(0.45, 0.32, 0.26), 3.0)
	var body := CardFaces.rounded_polygon(PackedVector2Array([Vector2(cx - 28, 192), Vector2(cx + 28, 192),
		Vector2(cx + 38, 286), Vector2(cx - 38, 286)]), 14.0)
	if rank == PokerCard.KING:
		# 斗篷在身后铺开一点
		_clipped(CardFaces.rounded_polygon(PackedVector2Array([Vector2(cx - 32, 194), Vector2(cx + 32, 194),
			Vector2(cx + 45, 290), Vector2(cx - 45, 290)]), 12.0), clip, ink.lerp(Color.WHITE, 0.2))
	_shape(body, robe)
	for side in [-1.0, 1.0]:
		_shape(CardFaces.ellipse(Vector2(cx + side * 33, 226), 11, 19, side * -0.35), robe, 3.0)
		_shape(CardFaces.ellipse(Vector2(cx + side * 38, 244), 8.5, 8.5), _fur(rank), 3.0)
	var pip := PokerFaceArt.suit_polygons(suit, Vector2(cx, 244), 34.0)
	_draw_pip(pip, ink)
	_sparkle(Vector2(cx - 30, 60), 6.0, pastel(ink, 0.45))
	_sparkle(Vector2(cx + 30, 312), 6.0, pastel(ink, 0.45))
	# 大头:头部整体绕下巴放大 HEAD_SCALE(五官坐标按 1.0 写)
	var pivot := Vector2(cx, 196)
	draw_set_transform(pivot * (1.0 - HEAD_SCALE), 0.0, Vector2.ONE * HEAD_SCALE)
	match rank:
		PokerCard.JACK:
			_fox_page(cx, ink)
		PokerCard.QUEEN:
			_cat_queen(cx, ink)
		PokerCard.KING:
			_bear_king(cx, ink)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _fur(rank: int) -> Color:
	match rank:
		PokerCard.JACK:
			return Color(0.98, 0.64, 0.38)
		PokerCard.QUEEN:
			return Color(1.0, 0.98, 0.94)
	return Color(0.78, 0.55, 0.38)


func _eyes(c: Vector2, spread: float, s := 1.0) -> void:
	for side in [-1.0, 1.0]:
		var e := c + Vector2(side * spread, 0)
		draw_colored_polygon(CardFaces.ellipse(e, 5.0 * s, 6.6 * s), EYE)
		draw_circle(e + Vector2(-1.6, -2.4) * s, 2.0 * s, Color.WHITE)
		draw_circle(e + Vector2(1.6, 2.4) * s, 1.0 * s, Color.WHITE)


func _blush(c: Vector2, spread: float) -> void:
	for side in [-1.0, 1.0]:
		draw_colored_polygon(CardFaces.ellipse(c + Vector2(side * spread, 0), 7, 4), Color(CardFaces.BLUSH, 0.6))


func _crown(base: Vector2, w: float, h: float, points: int, gem: Color) -> void:
	var poly := PackedVector2Array([base + Vector2(-w / 2, 0)])
	for i in points:
		var x := -w / 2 + w * (i + 0.5) / points
		poly.append(base + Vector2(x - w / points * 0.5, -h * 0.42))
		poly.append(base + Vector2(x, -h))
	poly.append(base + Vector2(w / 2, -h * 0.42))
	poly.append(base + Vector2(w / 2, 0))
	_shape(CardFaces.rounded_polygon(poly, 2.5), CardFaces.GOLD, 3.0)
	for i in points:
		var x := -w / 2 + w * (i + 0.5) / points
		_disc(base + Vector2(x, -h - 1), 3.6, Color(1.0, 0.97, 0.9), 2.0)
	_disc(base + Vector2(0, -5), 4.2, gem, 2.0)


func _fox_page(cx: float, ink: Color) -> void:
	# J:狐狸侍从。尖耳朵、白脸颊,歪戴一顶花色的贝雷帽插一根奶油色羽毛,眨一只眼
	var h := Vector2(cx, 156)
	var fur := _fur(PokerCard.JACK)
	for side in [-1.0, 1.0]:
		var ear := PackedVector2Array([h + Vector2(side * 36, -6), h + Vector2(side * 30, -50), h + Vector2(side * 8, -28)])
		_shape(CardFaces.rounded_polygon(ear, 4.0), fur)
		draw_colored_polygon(CardFaces.rounded_polygon(PackedVector2Array([h + Vector2(side * 30, -14),
			h + Vector2(side * 28, -40), h + Vector2(side * 15, -27)]), 2.0), Color(0.45, 0.3, 0.26))
	var face := CardFaces.rounded_polygon(PackedVector2Array([h + Vector2(-40, -6), h + Vector2(-26, -30),
		h + Vector2(26, -30), h + Vector2(40, -6), h + Vector2(20, 22), h + Vector2(0, 32), h + Vector2(-20, 22)]), 11.0)
	_shape(face, fur)
	for side in [-1.0, 1.0]:
		for piece in Geometry2D.intersect_polygons(CardFaces.ellipse(h + Vector2(side * 20, 17), 21, 16, side * 0.5), face):
			draw_colored_polygon(piece, Color(1.0, 0.97, 0.92))
	var closed := face.duplicate()
	closed.append(face[0])
	draw_polyline(closed, OUTLINE, LINE, true)
	# 贝雷帽 + 羽毛
	_stroke(PackedVector2Array([h + Vector2(14, -40), h + Vector2(30, -62), h + Vector2(44, -70)]), OUTLINE, 9.0)
	_stroke(PackedVector2Array([h + Vector2(14, -40), h + Vector2(30, -62), h + Vector2(44, -70)]), Color(1.0, 0.95, 0.84), 5.5)
	_shape(CardFaces.ellipse(h + Vector2(-4, -34), 34, 12, -0.12), ink.lerp(Color.WHITE, 0.15))
	_disc(h + Vector2(-6, -46), 4.5, CardFaces.GOLD, 2.0)
	_stroke(_arc(h + Vector2(-13, 0), Vector2(5.5, 4), PI + 0.3, TAU - 0.3, 8), OUTLINE, 3.0)
	_eyes(h + Vector2(26, -1), 0.0)
	draw_colored_polygon(CardFaces.ellipse(h + Vector2(0, 11), 5, 3.6), Color(0.3, 0.19, 0.15))
	_stroke(_arc(h + Vector2(1, 16), Vector2(7, 5), 0.25, PI - 0.25, 8), OUTLINE, 2.6)
	_blush(h + Vector2(0, 10), 26)


func _cat_queen(cx: float, ink: Color) -> void:
	# Q:猫皇后。奶白小猫、粉耳朵,白色花边领,头顶一顶小金冠,长睫毛
	var h := Vector2(cx, 158)
	var fur := _fur(PokerCard.QUEEN)
	var collar := PackedVector2Array()
	for i in 6:
		var arc := _arc(Vector2(cx - 30 + i * 12, 194), Vector2(6, 6), PI, 0.0, 5)
		if i > 0:
			arc.remove_at(0)   # 与上一段的终点重合
		collar.append_array(arc)
	collar.append(Vector2(cx + 36, 204))
	collar.append(Vector2(cx - 36, 204))
	_shape(collar, Color.WHITE, 2.5)
	for side in [-1.0, 1.0]:
		var ear := PackedVector2Array([h + Vector2(side * 36, -8), h + Vector2(side * 32, -46), h + Vector2(side * 8, -30)])
		_shape(CardFaces.rounded_polygon(ear, 4.0), fur)
		draw_colored_polygon(CardFaces.rounded_polygon(PackedVector2Array([h + Vector2(side * 31, -14),
			h + Vector2(side * 30, -38), h + Vector2(side * 16, -28)]), 2.0), Color(1.0, 0.72, 0.76))
	_shape(CardFaces.ellipse(h, 38, 32, 0.0, 48), fur)
	draw_colored_polygon(CardFaces.ellipse(h + Vector2(-18, -16), 9, 5, -0.6), Color(1, 1, 1, 0.5))
	_eyes(h + Vector2(0, 2), 15)
	for side in [-1.0, 1.0]:
		var root := h + Vector2(side * 19, -4)
		_stroke(PackedVector2Array([root, root + Vector2(side * 5, -4)]), OUTLINE, 2.2)
	_blush(h + Vector2(0, 13), 25)
	draw_colored_polygon(PackedVector2Array([h + Vector2(-4, 8), h + Vector2(4, 8), h + Vector2(0, 13)]), Color(0.95, 0.5, 0.58))
	_stroke(PackedVector2Array([h + Vector2(-6, 15), h + Vector2(-3, 18), h + Vector2(0, 15.5), h + Vector2(3, 18),
		h + Vector2(6, 15)]), OUTLINE, 2.2)
	_crown(h + Vector2(0, -28), 40, 26, 3, ink)


func _bear_king(cx: float, ink: Color) -> void:
	# K:熊国王。圆耳朵、浅色吻部,白貂毛领(带小黑点),头顶一顶三齿大金冠
	var h := Vector2(cx, 160)
	var fur := _fur(PokerCard.KING)
	var light := Color(0.97, 0.86, 0.7)
	_shape(CardFaces.ellipse(Vector2(cx, 198), 38, 11, 0.0, 32), Color(1, 0.99, 0.96), 2.5)
	for i in 4:
		draw_colored_polygon(CardFaces.ellipse(Vector2(cx - 21 + i * 14, 199), 2.0, 3.2, 0.0, 12), CardFaces.INK)
	for side in [-1.0, 1.0]:
		_disc(h + Vector2(side * 28, -24), 12.0, fur, 3.0)
		draw_colored_polygon(CardFaces.ellipse(h + Vector2(side * 28, -24), 6, 6), light)
	_shape(CardFaces.ellipse(h, 37, 32, 0.0, 48), fur)
	draw_colored_polygon(CardFaces.ellipse(h + Vector2(-18, -16), 9, 5, -0.6), Color(1, 1, 1, 0.35))
	_shape(CardFaces.ellipse(h + Vector2(0, 12), 16, 12), light, 2.5)
	draw_colored_polygon(CardFaces.ellipse(h + Vector2(0, 7), 6, 4.4), Color(0.3, 0.19, 0.15))
	_stroke(_arc(h + Vector2(0, 13), Vector2(4.5, 3), 0.3, PI - 0.3, 6), OUTLINE, 2.2)
	_eyes(h + Vector2(0, -4), 15)
	_blush(h + Vector2(0, 8), 25)
	_crown(h + Vector2(0, -26), 46, 30, 3, Color(0.92, 0.36, 0.42))


# —— 牌背 ——

func _draw_back() -> void:
	# 奶油外边 + 软藏青底小花色花格 + 奶油内框 + 中央奶油圈里一枚莓果色筹码(中间一枚黑桃)
	CardFaces.draw_rounded(self, Rect2(Vector2.ZERO, size), CardFaces.CUT_LINE, CORNER_RADIUS)
	CardFaces.draw_rounded(self, _inset(2), CardFaces.CREAM, CORNER_RADIUS - 2)
	var field := _inset(10)
	CardFaces.draw_rounded(self, field, BACK_FIELD, CORNER_RADIUS - 10)
	var clip := PokerFaceArt.rounded_rect(field.grow(-4.0), CORNER_RADIUS - 14)
	var row := 0
	var y := field.position.y + 14.0
	while y < field.end.y:
		var x := field.position.x + 16.0 + (16.0 if row % 2 == 1 else 0.0)
		var k := row
		while x < field.end.x:
			if Geometry2D.is_point_in_polygon(Vector2(x, y), clip):
				for poly in PokerFaceArt.suit_polygons(k % 4, Vector2(x, y), 11.0):
					draw_colored_polygon(poly, BACK_PATTERN)
			x += 32.0
			k += 1
		y += 26.0
		row += 1
	CardFaces.draw_rounded(self, _inset(17), Color.TRANSPARENT, CORNER_RADIUS - 17, 3, Color(CardFaces.CREAM, 0.9), false)
	for corner in 4:
		var flip := Vector2(1 if corner % 2 == 0 else -1, 1 if corner < 2 else -1)
		var origin := Vector2(0 if corner % 2 == 0 else size.x, 0 if corner < 2 else size.y)
		_sparkle(origin + Vector2(34, 34) * flip, 8.0, CardFaces.GOLD)
	var c := PokerFaceArt.CENTER
	_disc(c, 70.0, CardFaces.CREAM, 0.0)
	_disc(c, 60.0, CHIP, 3.5)
	for i in 8:
		var a := TAU * i / 8.0
		var notch := CardFaces.rounded_polygon(PackedVector2Array([
			c + Vector2(cos(a - 0.15), sin(a - 0.15)) * 58.0, c + Vector2(cos(a + 0.15), sin(a + 0.15)) * 58.0,
			c + Vector2(cos(a + 0.13), sin(a + 0.13)) * 44.0, c + Vector2(cos(a - 0.13), sin(a - 0.13)) * 44.0]), 2.0)
		draw_colored_polygon(notch, CardFaces.CREAM)
	_disc(c, 38.0, CardFaces.CREAM, 3.0)
	_draw_pip(PokerFaceArt.suit_polygons(PokerCard.SPADES, c, 42.0), BACK_FIELD)
	draw_colored_polygon(CardFaces.ellipse(c + Vector2(-26, -30), 10, 5, -0.6), Color(1, 1, 1, 0.3))


static func _bounds_of(polys: Array) -> Rect2:
	var rect := Rect2(polys[0][0], Vector2.ZERO)
	for poly in polys:
		for p in poly:
			rect = rect.expand(p)
	return rect
