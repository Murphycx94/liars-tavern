class_name BombCatFacePainter
extends Control
# 单张炸弹猫牌面的矢量绘制(放进离屏 SubViewport 抓图,见 BombCatFaces)。全部原创,动森式(2026-10-10 重画):
# 纸与骗子酒馆 / 德州的新牌同一家族(CardFaces.draw_paper + 圆角粉彩内框);顶部一条主色圆头横幅写牌名
# (圆体、描深色边,左端一枚小圆章写首字,牌扇里只露左边也认得出);中间粉彩圆盘里一幅胖乎乎的插画,
# 物件大多带一张小笑脸和腮红;底部浅色圆角框里一行说明(BombCatCard.description)。
# 插画用粗软描边(OUTLINE)、粉彩色块,配色集中在下面的常量里,3D 道具照着同一套颜色做。
# 牌背:深青绿底 + 浅青小爪印花格,中央奶油圈里一只圆滚滚的炸弹猫。
# foil 为真时画烫金遮罩:底色全黑,金色(任何透明度)画白、其余画黑,驱动 card.gdshader 的金属高光。


const GOLD := CardFaces.GOLD
const INK := CardFaces.INK
const PAPER := CardFaces.PAPER
const CREAM := CardFaces.CREAM
const OUTLINE := CardFaces.OUTLINE
const CORNER := 39                         # = 44/360 × 320,与 Card3D.CORNER 同比例
const FRAME_INSET := 12.0
const BANNER := Rect2(24, 24, 272, 64)
const CHIP_CENTER := Vector2(57, 56)
const CHIP_RADIUS := 24.0
const ICON_CENTER := Vector2(160, 214)
const ICON_RADIUS := 96.0
const TEXT_BOX := Rect2(26, 334, 268, 100)
const NAME_SIZE := 44
const TEXT_SIZE := 21
const TEXT_LINE := 27.0
const LINE := 5.0                          # 插画描边
# —— 插画配色(sRGB;3D 道具照这套做) ——
const BOMB_BODY := Color(0.27, 0.25, 0.34)     # 炸弹猫:炭灰紫
const METAL := Color(0.8, 0.83, 0.9)           # 引信座、剪刀刃:浅银蓝
const PINK := Color(1.0, 0.7, 0.76)            # 耳内、肉垫
const FUSE := Color(0.88, 0.72, 0.5)
const SPARK := Color(1.0, 0.62, 0.3)
const SNIP_GRIP := Color(0.98, 0.6, 0.6)       # 剪刀把:珊瑚粉
const PAW_PRINT := Color(0.42, 0.52, 0.78)     # 溜了的脚印:蓝灰
const DUST := Color(0.99, 0.96, 0.9)
const PAN_SHELL := Color(0.93, 0.47, 0.43)     # 甩锅:珊瑚红锅身
const PAN_INSIDE := Color(0.62, 0.6, 0.7)      # 锅底:灰薰衣草
const WOOD := Color(0.87, 0.65, 0.43)
const GLASS := Color(0.84, 0.93, 0.99)
const STAMP_RED := Color(0.9, 0.36, 0.38)
const PAW_CREAM := Color(1.0, 0.97, 0.92)
const FISH := Color(0.99, 0.74, 0.46)
const YARN := Color(0.96, 0.6, 0.76)
const CARROT := Color(0.99, 0.6, 0.28)
const LEAF := Color(0.46, 0.77, 0.42)
const BANANA := Color(1.0, 0.86, 0.38)
const CACTUS := Color(0.5, 0.78, 0.5)
const POT := Color(0.9, 0.56, 0.42)
const FLOWER := Color(1.0, 0.62, 0.74)
const BLUSH := CardFaces.BLUSH
const EYE := Color(0.22, 0.15, 0.13)
const BACK_FIELD := Color(0.17, 0.45, 0.48)    # 牌背深青绿
const BACK_PATTERN := Color(0.25, 0.55, 0.57)
const BACK_BADGE := Color(0.98, 0.74, 0.62)    # 牌背徽章:蜜桃底

var card_id := ""
var foil := false
var _round: SystemFont
var _body: SystemFont


func _init(p_id := "", p_foil := false) -> void:
	card_id = p_id
	foil = p_foil
	size = Vector2(BombCatFaces.SIZE)
	# 牌名用圆体(简体字形要全:不用日文的丸ゴ,缺字会混进别的字体),没有就退到粗黑体
	_round = SystemFont.new()
	_round.font_names = PackedStringArray(["Yuanti SC", "YuanTi SC", "PingFang SC", "Microsoft YaHei",
		"Noto Sans CJK SC", "sans-serif"])
	_round.font_weight = 800
	_body = SystemFont.new()
	_body.font_names = PackedStringArray(UiTheme.FONT_BODY_NAMES)
	_body.font_weight = 600


func _draw() -> void:
	if foil:
		draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)
	if card_id == BombCatFaces.BACK:
		_draw_back()
	else:
		_draw_face()


# —— 颜色与基本形 ——

func _c(color: Color) -> Color:
	# 遮罩模式:金色 → 白,其余 → 黑,透明度不变
	if not foil:
		return color
	var gold := absf(color.r - GOLD.r) + absf(color.g - GOLD.g) + absf(color.b - GOLD.b) < 0.01
	return Color(1, 1, 1, color.a) if gold else Color(0, 0, 0, color.a)


func _rounded(rect: Rect2, fill: Color, radius: int, border := 0, border_color := Color.TRANSPARENT, draw_fill := true) -> void:
	CardFaces.draw_rounded(self, rect, _c(fill), radius, border, _c(border_color), draw_fill)


func _inset(amount: float) -> Rect2:
	return Rect2(Vector2(amount, amount), size - Vector2(amount, amount) * 2.0)


func _poly(points: PackedVector2Array, color: Color, outline := LINE, outline_color := OUTLINE) -> void:
	if points.size() < 3:
		return
	draw_colored_polygon(points, _c(color))
	if outline > 0.0:
		var closed := points.duplicate()
		closed.append(points[0])
		draw_polyline(closed, _c(outline_color), outline, true)


func _circle(center: Vector2, radius: float, color: Color, outline := LINE, outline_color := OUTLINE) -> void:
	_poly(ellipse(center, radius, radius, 0.0, maxi(24, int(radius * 1.3))), color, outline, outline_color)


func _line(points: PackedVector2Array, color: Color, width: float) -> void:
	# 圆头粗线
	draw_polyline(points, _c(color), width, true)
	draw_circle(points[0], width * 0.5, _c(color))
	draw_circle(points[points.size() - 1], width * 0.5, _c(color))


func _outlined_line(points: PackedVector2Array, color: Color, width: float) -> void:
	# 带描边的粗线(把手、引信):先画宽一圈的描边色,再画本色
	_line(points, OUTLINE, width + LINE * 1.4)
	_line(points, color, width)


func _blob(circles: Array, color: Color) -> void:
	# 几个圆的并集带一圈描边(云朵、烟团):先把每个圆放大一圈画描边色,再画本色
	for c in circles:
		draw_circle(c[0], c[1] + LINE * 0.6, _c(OUTLINE))
	for c in circles:
		draw_circle(c[0], c[1], _c(color))


func _shine(c: Vector2, rx: float, ry: float, rot := -0.6) -> void:
	draw_colored_polygon(ellipse(c, rx, ry, rot), _c(Color(1, 1, 1, 0.35)))


func _sparkle(c: Vector2, r: float, color := GOLD) -> void:
	draw_colored_polygon(star(c, r, r * 0.32, 4, 0.0), _c(color))


func _face(c: Vector2, s: float, eye_color := EYE, mouth_color := OUTLINE, blush := true) -> void:
	# 小笑脸:两颗豆豆眼(带高光)+ 弯弯嘴 + 腮红
	for side in [-1.0, 1.0]:
		var e := c + Vector2(side * 11, -2) * s
		draw_colored_polygon(ellipse(e, 4.2 * s, 5.4 * s), _c(eye_color))
		draw_circle(e + Vector2(-1.4, -2.0) * s, 1.6 * s, _c(Color.WHITE))
		if blush:
			draw_colored_polygon(ellipse(c + Vector2(side * 21, 6) * s, 6.0 * s, 3.6 * s), _c(Color(BLUSH, 0.6)))
	_line(arc_points(c + Vector2(0, 3) * s, Vector2(5, 4) * s, 0.25, PI - 0.25, 8), mouth_color, 2.6 * s)


static func ellipse(center: Vector2, rx: float, ry: float, rot := 0.0, segments := 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var basis := Transform2D(rot, Vector2.ZERO)
	for i in segments:
		var a := TAU * i / segments
		pts.append(center + basis * Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func star(center: Vector2, outer: float, inner: float, points := 5, rot := -PI / 2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := rot + PI * i / points
		pts.append(center + Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	return pts


static func arc_points(center: Vector2, radius: Vector2, from: float, to: float, steps := 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(from, to, float(i) / steps)
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
	return pts


static func bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, steps := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / steps
		var u := 1.0 - t
		pts.append(a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t)
	return pts


static func heart(c: Vector2, s: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 48:
		var t := TAU * i / 48.0
		pts.append(c + Vector2(16 * pow(sin(t), 3), -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))) * s / 17.0)
	return pts


# —— 文字 ——

func _text(font: Font, text: String, center: Vector2, font_size: int, color: Color, outline := 0, outline_color := INK) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent := font.get_ascent(font_size)
	var descent := font.get_descent(font_size)
	var baseline := Vector2(center.x - text_size.x / 2.0, center.y + (ascent - descent) / 2.0)
	if outline > 0:
		draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline, _c(outline_color))
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, _c(color))


static func wrap_text(font: Font, text: String, font_size: int, width: float) -> PackedStringArray:
	# 按字符折行(中文没有空格);标点不放在行首
	var lines := PackedStringArray()
	var line := ""
	for ch in text:
		var trial := line + ch
		if line != "" and font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width \
				and ch not in [",", "。", "、", "!", ",", "!", ")"]:
			lines.append(line)
			line = ch
		else:
			line = trial
	if line != "":
		lines.append(line)
	return lines


# —— 牌面 ——

func _draw_face() -> void:
	var accent := BombCatFaces.accent(card_id)
	var tint := BombCatFaces.tint(card_id)
	var mid := accent.lerp(Color.WHITE, 0.45)
	if not foil:
		CardFaces.draw_paper(self, _inset(0), CORNER, 2468 + BombCatFaces.layer(card_id), 260)
	_rounded(_inset(FRAME_INSET), Color.TRANSPARENT, CORNER - int(FRAME_INSET), 5, Color(mid, 0.85), false)
	# 顶部横幅:圆头主色条 + 下沿一道深一档的厚边 + 首字圆章 + 牌名(圆体描深色边)
	var dark := accent.darkened(0.32)
	_rounded(BANNER.grow(2.5), OUTLINE, int(BANNER.size.y / 2.0 + 2.5))
	_rounded(BANNER, dark, int(BANNER.size.y / 2.0))
	_rounded(Rect2(BANNER.position, BANNER.size - Vector2(0, 7)), accent, int(BANNER.size.y / 2.0))
	_rounded(Rect2(BANNER.position + Vector2(36, 7), Vector2(BANNER.size.x - 72, 7)), Color(1, 1, 1, 0.3), 3)
	_circle(CHIP_CENTER, CHIP_RADIUS, PAPER, 3.5, dark)
	var name := BombCatCard.display_name(card_id)
	_text(_round, name.substr(0, 1), CHIP_CENTER + Vector2(0, 1), 28, dark)
	var name_size := NAME_SIZE if name.length() <= 3 else NAME_SIZE - 4
	_text(_round, name, Vector2(180, BANNER.get_center().y - 2), name_size, PAPER, 9, dark.darkened(0.35))
	# 插画圆盘:浅粉彩底 + 中间色圆圈 + 一圈小圆点
	_circle(ICON_CENTER, ICON_RADIUS, tint, 6.0, mid)
	for i in 18:
		var a := TAU * (i + 0.5) / 18.0
		draw_circle(ICON_CENTER + Vector2(cos(a), sin(a)) * (ICON_RADIUS + 11.0), 2.4, _c(Color(mid, 0.75)))
	_icon(card_id, ICON_CENTER, accent)
	# 底部说明
	_rounded(TEXT_BOX, tint, 18, 2, Color(mid, 0.8))
	var lines := wrap_text(_body, BombCatCard.description(card_id), TEXT_SIZE, TEXT_BOX.size.x - 28.0)
	var top := TEXT_BOX.get_center().y - (lines.size() - 1) * TEXT_LINE / 2.0
	for i in lines.size():
		_text(_body, lines[i], Vector2(TEXT_BOX.get_center().x, top + i * TEXT_LINE), TEXT_SIZE, INK)


func _icon(id: String, c: Vector2, accent: Color) -> void:
	match id:
		BombCatCard.BOMB:
			_bomb_kitty(c + Vector2(-4, 12), 1.0)
			_sparkle(c + Vector2(-70, -50), 10)
			_sparkle(c + Vector2(72, 52), 8, Color(1, 1, 1, 0.9))
		BombCatCard.DEFUSE:
			_snips(c, accent)
		BombCatCard.SKIP:
			_footprints(c)
		BombCatCard.PASS_TURNS:
			_pan(c, accent)
		BombCatCard.PEEK:
			_magnifier(c, accent)
		BombCatCard.SHUFFLE:
			_shuffle(c, accent)
		BombCatCard.BEG:
			_beg(c)
		BombCatCard.NOPE:
			_nope(c)
		BombCatCard.SNACK_FISH:
			_fish(c)
		BombCatCard.SNACK_YARN:
			_yarn(c)
		BombCatCard.SNACK_CARROT:
			_carrot(c)
		BombCatCard.SNACK_BANANA:
			_banana(c)
		BombCatCard.SNACK_CACTUS:
			_cactus(c)


# —— 插画 ——

func _bomb_kitty(c: Vector2, s: float) -> void:
	# 炸弹猫:圆滚滚的炭灰紫猫球,粉耳朵,头顶右边一个银引信座,引信末端一颗闪闪的火花;大亮眼 + 腮红 + w 嘴
	for side in [-1.0, 1.0]:
		var ear := PackedVector2Array([c + Vector2(side * 54, -20) * s, c + Vector2(side * 48, -74) * s, c + Vector2(side * 14, -52) * s])
		_poly(CardFaces.rounded_polygon(ear, 8.0 * s), BOMB_BODY, LINE * s)
		var inner := PackedVector2Array([c + Vector2(side * 46, -28) * s, c + Vector2(side * 44, -62) * s, c + Vector2(side * 24, -48) * s])
		draw_colored_polygon(CardFaces.rounded_polygon(inner, 4.0 * s), _c(PINK))
	# 引信:从引信座往右上弯出去
	var socket := c + Vector2(18, -60) * s
	var fuse := bezier(socket + Vector2(0, -4) * s, socket + Vector2(4, -30) * s, socket + Vector2(30, -22) * s, socket + Vector2(36, -44) * s)
	_outlined_line(fuse, FUSE, 6.0 * s)
	_circle(c, 60.0 * s, BOMB_BODY, LINE * s)
	_rounded(Rect2(socket - Vector2(14, 8) * s, Vector2(28, 18) * s), OUTLINE, int(6 * s))
	_rounded(Rect2(socket - Vector2(11.5, 5.5) * s, Vector2(23, 13) * s), METAL, int(4 * s))
	var tip := fuse[fuse.size() - 1]
	draw_colored_polygon(CardFaces.rounded_polygon(star(tip, 22.0 * s, 10.0 * s, 8, 0.2), 2.0 * s), _c(GOLD))
	draw_colored_polygon(star(tip, 12.0 * s, 6.0 * s, 8, 0.0), _c(SPARK))
	draw_circle(tip, 4.0 * s, _c(Color(1, 0.98, 0.88)))
	_sparkle(tip + Vector2(-20, -16) * s, 6.0 * s)
	_sparkle(tip + Vector2(16, 14) * s, 5.0 * s)
	_shine(c + Vector2(-30, -28) * s, 15 * s, 8 * s)
	# 大亮眼:奶白眼底 + 大黑瞳 + 一大一小两个高光
	for side in [-1.0, 1.0]:
		var e := c + Vector2(side * 23, 2) * s
		draw_colored_polygon(ellipse(e, 14.0 * s, 15.5 * s), _c(Color(1, 0.99, 0.96)))
		draw_colored_polygon(ellipse(e + Vector2(side * 1, 2) * s, 9.5 * s, 11.5 * s), _c(Color(0.14, 0.11, 0.18)))
		draw_circle(e + Vector2(-3, -3) * s, 4.0 * s, _c(Color.WHITE))
		draw_circle(e + Vector2(3.5, 5) * s, 2.0 * s, _c(Color.WHITE))
		draw_colored_polygon(ellipse(c + Vector2(side * 40, 24) * s, 9 * s, 5.5 * s), _c(Color(BLUSH, 0.75)))
		for k in 2:
			var from := c + Vector2(side * 44, 12 + k * 8) * s
			_line(PackedVector2Array([from, from + Vector2(side * 18, -3 + k * 6) * s]), Color(1, 1, 1, 0.55), 2.2 * s)
	_line(PackedVector2Array([c + Vector2(-9, 22) * s, c + Vector2(-4.5, 27) * s, c + Vector2(0, 23) * s,
		c + Vector2(4.5, 27) * s, c + Vector2(9, 22) * s]), Color(1, 0.94, 0.9), 2.8 * s)


func _snips(c: Vector2, accent: Color) -> void:
	# 拆弹:一把粉彩小剪刀。两片浅银刃张开成 V、珊瑚粉圆环把手,铆钉是一张薄荷色小笑脸;旁边两截剪断的引线冒火星
	var pivot := c + Vector2(0, 6)
	# 剪断的引线
	var wire := Color(0.98, 0.5, 0.52)
	_outlined_line(bezier(c + Vector2(-92, -18), c + Vector2(-74, -40), c + Vector2(-52, -30), c + Vector2(-24, -44), 12), wire, 6.0)
	_outlined_line(bezier(c + Vector2(24, -44), c + Vector2(52, -30), c + Vector2(74, -40), c + Vector2(92, -18), 12), wire, 6.0)
	for side in [-1.0, 1.0]:
		# 刃:从铆钉往上张开的胖柳叶
		var blade := PackedVector2Array()
		var tip := pivot + Vector2(side * 22, -82)
		var axis := (tip - pivot).normalized()
		var normal := axis.orthogonal()
		for i in 13:
			var t := float(i) / 12.0
			blade.append(pivot.lerp(tip, t) + normal * sin(t * PI) * 13.0 * pow(1.0 - t * 0.5, 1.0))
		for i in range(12, -1, -1):
			var t := float(i) / 12.0
			blade.append(pivot.lerp(tip, t) - normal * sin(t * PI) * 6.0)
		_poly(blade, METAL)
		_line(PackedVector2Array([pivot.lerp(tip, 0.25) + normal * 4.0, pivot.lerp(tip, 0.7) + normal * 4.0]), Color(1, 1, 1, 0.7), 3.0)
	for side in [-1.0, 1.0]:
		var ring := pivot + Vector2(side * 36, 52)
		_outlined_line(PackedVector2Array([pivot + Vector2(side * 4, 8), ring + Vector2(-side * 10, -22)]), SNIP_GRIP, 12.0)
		_circle(ring, 26.0, SNIP_GRIP)
		_circle(ring + Vector2(0, 2), 13.0, BombCatFaces.tint(BombCatCard.DEFUSE))
		_shine(ring + Vector2(-12, -12), 6, 3.5)
	_circle(pivot, 19.0, accent.lerp(Color.WHITE, 0.35))
	_face(pivot + Vector2(0, 1), 0.82)
	_sparkle(c + Vector2(0, -88), 11)
	_sparkle(c + Vector2(-30, -94), 6, Color(1, 1, 1, 0.9))
	_sparkle(c + Vector2(30, -92), 7)


func _paw_print(at: Vector2, rot: float, s: float, color: Color) -> void:
	draw_set_transform(at, rot, Vector2(s, s))
	_poly(CardFaces.rounded_polygon(PackedVector2Array([Vector2(-17, 18), Vector2(17, 18), Vector2(13, -2), Vector2(-13, -2)]), 8.0), color, LINE / s)
	for p in [Vector2(-19, -12), Vector2(-7, -22), Vector2(7, -22), Vector2(19, -12)]:
		_poly(ellipse(p, 6.5, 8.0, 0.0, 20), color, LINE / s)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _footprints(c: Vector2) -> void:
	# 溜了:三个越来越大的小脚印往右上跑走,身后一团带笑脸的烟尘、几道速度线
	_paw_print(c + Vector2(-26, 30), 0.6, 0.62, Color(PAW_PRINT, 0.75))
	_paw_print(c + Vector2(6, 0), 0.6, 0.78, PAW_PRINT)
	_paw_print(c + Vector2(44, -38), 0.6, 0.94, PAW_PRINT)
	for k in 3:
		var y := -56.0 + k * 16.0
		_line(PackedVector2Array([c + Vector2(-74 + k * 8, y), c + Vector2(-34 + k * 10, y + 6)]), Color(PAW_PRINT, 0.55), 5.0)
	var puff := c + Vector2(-46, 58)
	_blob([[puff + Vector2(-22, 6), 17.0], [puff + Vector2(0, -6), 22.0], [puff + Vector2(22, 4), 18.0], [puff + Vector2(4, 12), 16.0]], DUST)
	_face(puff + Vector2(0, 2), 0.8)
	_blob([[c + Vector2(-82, 36), 7.0]], DUST)
	_blob([[c + Vector2(-12, 80), 6.0]], DUST)


func _pan(c: Vector2, accent: Color) -> void:
	# 甩锅:一口珊瑚红小平底锅带木把手往右上甩出去,锅里一张笑脸,身后几道动作线
	var pan := c + Vector2(14, -2)
	var rot := -0.35
	var handle_dir := Vector2(cos(PI + rot + 0.35), sin(PI + rot + 0.35))
	_outlined_line(PackedVector2Array([pan + handle_dir * 56.0, pan + handle_dir * 108.0]), WOOD, 18.0)
	draw_circle(pan + handle_dir * 100.0, 3.5, _c(OUTLINE))
	_poly(ellipse(pan, 64, 54, rot, 56), PAN_SHELL)
	_poly(ellipse(pan + Vector2(2, -3), 50, 41, rot, 56), PAN_INSIDE, 3.5)
	_shine(pan + Vector2(-24, -22), 13, 6)
	_face(pan + Vector2(2, 0), 1.25)
	var dark := accent.darkened(0.15)
	for k in 3:
		var r := 76.0 + k * 13.0
		_line(arc_points(pan, Vector2(r, r * 0.86), -0.95 + k * 0.08, -0.2 - k * 0.02, 10), Color(dark, 0.85 - k * 0.2), 5.0)
	_sparkle(c + Vector2(76, -66), 10)
	_sparkle(c + Vector2(-60, -60), 7, Color(1, 1, 1, 0.9))


func _magnifier(c: Vector2, accent: Color) -> void:
	# 偷看:一只放大镜,镜片里一只大眼睛眨巴着偷瞄;紫色镜框和把手
	var lens := c + Vector2(-10, -12)
	var handle := (Vector2(1, 1)).normalized()
	_outlined_line(PackedVector2Array([lens + handle * 66.0, lens + handle * 118.0]), accent.darkened(0.1), 20.0)
	_circle(lens + handle * 118.0, 8.0, CREAM, 4.0)
	_circle(lens, 66.0, accent.lerp(Color.WHITE, 0.25))
	_circle(lens, 52.0, GLASS, 4.0)
	# 眼睛
	var eye := PackedVector2Array()
	for i in 25:
		var t := float(i) / 24.0
		eye.append(lens + Vector2(lerpf(-36, 36, t), -sin(t * PI) * 22))
	for i in range(23, 0, -1):
		var t := float(i) / 24.0
		eye.append(lens + Vector2(lerpf(-36, 36, t), sin(t * PI) * 18))
	_poly(eye, Color.WHITE, 4.0)
	_circle(lens + Vector2(4, 0), 15.0, accent.lerp(Color.WHITE, 0.15), 3.0)
	draw_circle(lens + Vector2(5, 1), 8.0, _c(EYE))
	draw_circle(lens + Vector2(0, -5), 4.0, _c(Color.WHITE))
	draw_circle(lens + Vector2(9, 5), 2.0, _c(Color.WHITE))
	for k in 3:
		var t := 0.3 + k * 0.2
		var p := lens + Vector2(lerpf(-36, 36, t), -sin(t * PI) * 22)
		_line(PackedVector2Array([p, p + Vector2((t - 0.5) * 16, -10)]), OUTLINE, 3.5)
	_shine(lens + Vector2(-28, -28), 12, 6)
	_sparkle(c + Vector2(64, -64), 11)
	_sparkle(c + Vector2(-74, 54), 7, Color(1, 1, 1, 0.9))


func _mini_card(at: Vector2, rot: float, face_up: bool, accent: Color) -> void:
	draw_set_transform(at, rot, Vector2.ONE)
	if face_up:
		_rounded(Rect2(Vector2(-28, -40), Vector2(56, 80)).grow(2.5), OUTLINE, 11)
		_rounded(Rect2(Vector2(-28, -40), Vector2(56, 80)), PAPER, 9)
		draw_colored_polygon(CardFaces.rounded_polygon(star(Vector2.ZERO, 18, 8), 2.5), _c(accent))
	else:
		_rounded(Rect2(Vector2(-28, -40), Vector2(56, 80)).grow(2.5), OUTLINE, 11)
		_rounded(Rect2(Vector2(-28, -40), Vector2(56, 80)), BACK_FIELD, 9)
		_rounded(Rect2(Vector2(-22, -34), Vector2(44, 68)), Color.TRANSPARENT, 6, 2, CREAM, false)
		draw_circle(Vector2.ZERO, 9.0, _c(BACK_BADGE))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _shuffle(c: Vector2, accent: Color) -> void:
	# 洗牌:两张小牌交叉着转起来,外面两道首尾相接的胖箭头,周围撒星星
	var dark := accent.darkened(0.05)
	for half in 2:
		var from := -2.6 + half * PI
		var to := -0.75 + half * PI
		var arc := arc_points(c, Vector2(76, 76), from, to, 20)
		_line(arc, OUTLINE, 16.0 + LINE * 1.4)
		_line(arc, dark, 16.0)
		var end := c + Vector2(cos(to), sin(to)) * 76.0
		var tangent := Vector2(-sin(to), cos(to))
		var normal := Vector2(cos(to), sin(to))
		_poly(CardFaces.rounded_polygon(PackedVector2Array([end + tangent * 24.0, end + normal * 19.0, end - normal * 19.0]), 3.0), dark, 4.0)
	_mini_card(c + Vector2(-14, 2), -0.32, false, accent)
	_mini_card(c + Vector2(16, -2), 0.28, true, accent)
	_sparkle(c + Vector2(0, -92), 9)
	_sparkle(c + Vector2(-90, 10), 8, Color(1, 1, 1, 0.9))
	_sparkle(c + Vector2(88, -6), 10)


func _paw_pad(c: Vector2, s: float) -> void:
	# 掌心朝前的猫爪:奶白爪 + 粉色肉垫
	_circle(c, 56.0 * s, PAW_CREAM, LINE * s)
	_poly(CardFaces.rounded_polygon(PackedVector2Array([c + Vector2(-26, 34) * s, c + Vector2(26, 34) * s,
		c + Vector2(20, 2) * s, c + Vector2(-20, 2) * s]), 12.0 * s), PINK, 0.0)
	for p in [Vector2(-32, -14), Vector2(-12, -32), Vector2(12, -32), Vector2(32, -14)]:
		draw_colored_polygon(ellipse(c + p * s, 9.5 * s, 11.5 * s), _c(PINK))
	_shine(c + Vector2(-26, -26) * s, 10 * s, 5 * s)


func _beg(c: Vector2) -> void:
	# 讨要:伸出来的猫爪,上方飘一颗带高光的小心心
	_paw_pad(c + Vector2(-4, 14), 1.08)
	var h := c + Vector2(56, -60)
	_poly(heart(h, 26.0), Color(0.96, 0.42, 0.52))
	_shine(h + Vector2(-9, -7), 6, 3.5)
	_sparkle(c + Vector2(-60, -58), 11)
	_sparkle(c + Vector2(-38, -82), 6)
	_sparkle(c + Vector2(84, -18), 7, Color(1, 1, 1, 0.9))


func _nope(c: Vector2) -> void:
	# 不行!:一枚圆圆的红印章,章面是奶白的猫爪,压一道禁止斜杠;印章微微歪着,边上溅几点印泥
	_circle(c, 82.0, STAMP_RED)
	draw_arc(c, 70.0, 0.0, TAU, 64, _c(PAW_CREAM), 5.0, true)
	_paw_print(c + Vector2(0, 4).rotated(-0.12), -0.12, 1.55, PAW_CREAM)
	draw_set_transform(c, -0.12, Vector2.ONE)
	var d := Vector2(cos(-PI * 0.75), sin(-PI * 0.75)) * 62.0
	_line(PackedVector2Array([d, -d]), OUTLINE, 16.0 + LINE * 1.2)
	_line(PackedVector2Array([d, -d]), STAMP_RED.darkened(0.08), 16.0)
	_shine(Vector2(-44, -44), 12, 6)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for p in [Vector2(84, -60), Vector2(94, -44), Vector2(-88, 64)]:
		draw_circle(c + p, 4.5, _c(Color(STAMP_RED, 0.8)))


func _fish(c: Vector2) -> void:
	# 鱼干:一条胖小鱼(朝左),奶油肚皮、两片小鳍、几道鳞纹,脸朝着你笑
	draw_set_transform(c, -0.18, Vector2.ONE)
	_poly(CardFaces.rounded_polygon(PackedVector2Array([Vector2(46, 0), Vector2(88, -34), Vector2(80, 0), Vector2(88, 34)]), 6.0), FISH)
	_poly(CardFaces.rounded_polygon(PackedVector2Array([Vector2(-8, -36), Vector2(18, -54), Vector2(26, -30)]), 5.0), FISH)
	_poly(ellipse(Vector2(-4, 0), 62, 40, 0.0, 56), FISH)
	var body := ellipse(Vector2(-4, 0), 62, 40, 0.0, 56)
	for piece in Geometry2D.intersect_polygons(ellipse(Vector2(-4, 34), 60, 22, 0.0, 48), body):
		draw_colored_polygon(piece, _c(Color(1, 0.94, 0.82)))
	var closed := body.duplicate()
	closed.append(body[0])
	draw_polyline(closed, _c(OUTLINE), LINE, true)
	for k in 3:
		_line(arc_points(Vector2(14 + k * 14, -4), Vector2(9, 12), -PI / 2 + 0.4, PI / 2 - 0.4, 8), Color(FISH.darkened(0.2), 0.9), 3.0)
	_shine(Vector2(-30, -20), 12, 6)
	_face(Vector2(-36, 2), 1.15)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_sparkle(c + Vector2(-66, -58), 9)
	_sparkle(c + Vector2(70, 60), 7, Color(1, 1, 1, 0.9))


func _yarn(c: Vector2) -> void:
	# 毛线球:粉毛线球上几道缠线,线头卷出去;两根木毛衣针斜插在后面;球上一张笑脸
	for side in [-1.0, 1.0]:
		_outlined_line(PackedVector2Array([c + Vector2(side * -66, -70), c + Vector2(side * 34, 50)]), WOOD, 7.0)
		_circle(c + Vector2(side * -66, -70), 9.0, Color(0.98, 0.84, 0.44), 4.0)
	var ball := c + Vector2(0, 6)
	var body := ellipse(ball, 60, 60, 0.0, 64)
	_poly(body, YARN)
	var strand := YARN.darkened(0.22)
	for k in 4:
		var center := ball + Vector2(-96 + k * 52, -76 + k * 12)
		var pts := PackedVector2Array()
		for i in 72:
			var a := TAU * i / 72.0
			var p := center + Vector2(cos(a), sin(a)) * 112.0
			if p.distance_to(ball) < 55.0:
				pts.append(p)
		if pts.size() > 1:
			draw_polyline(pts, _c(strand), 3.5, true)
	_outlined_line(bezier(ball + Vector2(46, 38), ball + Vector2(86, 44), ball + Vector2(62, 88), ball + Vector2(92, 82)), YARN, 5.0)
	_shine(ball + Vector2(-28, -30), 14, 7)
	draw_colored_polygon(ellipse(ball + Vector2(0, 8), 30, 20), _c(Color(YARN.lightened(0.25), 0.9)))
	_face(ball + Vector2(0, 8), 1.15)


func _carrot(c: Vector2) -> void:
	# 胡萝卜:斜着一根胖胡萝卜,顶上三片圆叶,身上两道浅纹,一张笑脸
	draw_set_transform(c + Vector2(4, 4), 0.42, Vector2.ONE)
	for k in 3:
		_poly(ellipse(Vector2(-16 + k * 16, -76), 11, 26, (k - 1) * 0.5, 28), LEAF)
	var body := CardFaces.rounded_polygon(PackedVector2Array([Vector2(-38, -54), Vector2(38, -54), Vector2(8, 82), Vector2(-8, 82)]), 14.0)
	_poly(body, CARROT)
	for k in 2:
		var y := 20.0 + k * 24.0
		var w := 20.0 - k * 6.0
		_line(PackedVector2Array([Vector2(-w, y), Vector2(-w + 10, y + 2)]), CARROT.darkened(0.2), 3.5)
		_line(PackedVector2Array([Vector2(w, y + 10), Vector2(w - 10, y + 12)]), CARROT.darkened(0.2), 3.5)
	_shine(Vector2(-20, -36), 8, 14, 0.0)
	_face(Vector2(0, -22), 1.1)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_sparkle(c + Vector2(-66, 50), 8)
	_sparkle(c + Vector2(70, -60), 9, Color(1, 1, 1, 0.9))


func _banana(c: Vector2) -> void:
	# 香蕉:一弯胖月牙,两头是褐色的蒂和尖,肚子上一张笑脸
	var center := c + Vector2(0, -84)
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in 29:
		var t := float(i) / 28.0
		var a := deg_to_rad(lerpf(28.0, 152.0, t))
		var thick := 50.0 * pow(sin(t * PI), 0.8) + 6.0
		var dir := Vector2(cos(a), sin(a))
		outer.append(center + dir * 128.0)
		inner.append(center + dir * (128.0 - thick))
	inner.reverse()
	var body := outer + inner
	_poly(body, BANANA)
	var shade := PackedVector2Array()
	for i in range(4, 25):
		var t := float(i) / 28.0
		var a := deg_to_rad(lerpf(28.0, 152.0, t))
		shade.append(center + Vector2(cos(a), sin(a)) * 118.0)
	_line(shade, Color(BANANA.darkened(0.12), 0.9), 6.0)
	_circle(outer[outer.size() - 1], 6.0, Color(0.45, 0.32, 0.2), 0.0)
	draw_set_transform(outer[0], -1.0, Vector2.ONE)
	_rounded(Rect2(Vector2(-7, -22), Vector2(14, 24)).grow(2.5), OUTLINE, 6)
	_rounded(Rect2(Vector2(-7, -22), Vector2(14, 24)), Color(0.62, 0.46, 0.26), 5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_shine(center + Vector2(-40, 92), 14, 5, 0.3)
	_face(center + Vector2(0, 100), 1.15)
	_sparkle(c + Vector2(-60, -50), 10)
	_sparkle(c + Vector2(64, -54), 7, Color(1, 1, 1, 0.9))


func _cactus(c: Vector2) -> void:
	# 仙人掌:陶盆里一株胖仙人掌,两只小胳膊,头顶开一朵粉花,一张笑脸
	_rounded(Rect2(c + Vector2(-66, -24), Vector2(28, 54)).grow(2.5), OUTLINE, 16)
	_rounded(Rect2(c + Vector2(-66, -24), Vector2(28, 54)), CACTUS, 14)
	_rounded(Rect2(c + Vector2(40, -48), Vector2(28, 50)).grow(2.5), OUTLINE, 16)
	_rounded(Rect2(c + Vector2(40, -48), Vector2(28, 50)), CACTUS, 14)
	_rounded(Rect2(c + Vector2(-50, 4), Vector2(30, 22)), CACTUS, 10)
	_rounded(Rect2(c + Vector2(20, -14), Vector2(30, 20)), CACTUS, 10)
	_rounded(Rect2(c + Vector2(-30, -72), Vector2(60, 126)).grow(2.5), OUTLINE, 32)
	_rounded(Rect2(c + Vector2(-30, -72), Vector2(60, 126)), CACTUS, 30)
	for p in [Vector2(-16, -46), Vector2(16, -54), Vector2(-18, 30), Vector2(18, 22), Vector2(-56, -10), Vector2(54, -32)]:
		_line(PackedVector2Array([c + p, c + p + Vector2(3, -4)]), Color(1, 1, 1, 0.85), 2.5)
	_shine(c + Vector2(-14, -50), 6, 12, 0.0)
	_face(c + Vector2(0, -16), 1.15)
	for k in 5:
		var a := TAU * k / 5.0 - PI / 2
		_circle(c + Vector2(0, -76) + Vector2(cos(a), sin(a)) * 9.0, 8.0, FLOWER, 3.0)
	_circle(c + Vector2(0, -76), 5.5, Color(1, 0.88, 0.42), 2.5)
	var pot := CardFaces.rounded_polygon(PackedVector2Array([c + Vector2(-44, 48), c + Vector2(44, 48),
		c + Vector2(34, 96), c + Vector2(-34, 96)]), 6.0)
	_poly(pot, POT)
	_rounded(Rect2(c + Vector2(-52, 38), Vector2(104, 22)).grow(2.5), OUTLINE, 10)
	_rounded(Rect2(c + Vector2(-52, 38), Vector2(104, 22)), POT.lightened(0.12), 8)


# —— 牌背 ——

func _draw_back() -> void:
	# 奶油外边 + 深青绿底小爪印花格 + 奶油内框 + 中央蜜桃底徽章里一只炸弹猫
	_rounded(_inset(0), CardFaces.CUT_LINE, CORNER)
	_rounded(_inset(2), CREAM, CORNER - 2)
	var field := _inset(12)
	var field_radius := CORNER - 12
	_rounded(field, BACK_FIELD, field_radius)
	var step := Vector2(44, 44)
	var row := 0
	var y := field.position.y + 10.0
	while y < field.end.y:
		var x := field.position.x + 14.0 + (step.x / 2.0 if row % 2 == 1 else 0.0)
		while x < field.end.x - 6.0:
			_mini_paw(Vector2(x, y), (0.35 if row % 2 == 0 else -0.35))
			x += step.x
		y += step.y * 0.62
		row += 1
	_rounded(_inset(20), Color.TRANSPARENT, field_radius - 8, 4, Color(CREAM, 0.9), false)
	for corner in 4:
		var flip := Vector2(1 if corner % 2 == 0 else -1, 1 if corner < 2 else -1)
		var origin := Vector2(0 if corner % 2 == 0 else size.x, 0 if corner < 2 else size.y)
		_sparkle(origin + Vector2(42, 42) * flip, 10.0)
	var center := size / 2.0
	_circle(center, 96.0, CREAM, 0.0)
	_circle(center, 88.0, BACK_BADGE, 5.0, GOLD)
	for i in 15:
		var a := TAU * (i + 0.5) / 15.0
		draw_circle(center + Vector2(cos(a), sin(a)) * 92.0, 2.2, _c(BACK_FIELD))
	_bomb_kitty(center + Vector2(-4, 12), 0.78)


func _mini_paw(at: Vector2, rot: float) -> void:
	# 牌背花格里的小爪印(不描边,只是浅一档的青色)
	draw_set_transform(at, rot, Vector2.ONE)
	draw_colored_polygon(ellipse(Vector2(0, 3), 6.5, 5.5, 0.0, 16), _c(BACK_PATTERN))
	for p in [Vector2(-6.5, -4), Vector2(-2.2, -7.5), Vector2(2.2, -7.5), Vector2(6.5, -4)]:
		draw_colored_polygon(ellipse(p, 2.2, 2.7, 0.0, 10), _c(BACK_PATTERN))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
