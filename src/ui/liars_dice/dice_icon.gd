class_name DiceIcon
extends Control
# 2D 骰子面(HUD 的自己的骰子、出价器的点数按钮、铭牌、说明书示例共用):奶油色圆角方块 + 彩色小圆点,
# 1 点画成一颗小星星(万能),配色与 3D 骰子(LiarsDiceProps)一致。value 0 = 背面(画一个「?」,还没摇 / 看不到)。
# highlight:金边 + 外圈暖光(开盅时算进去的那几颗、出价器选中的点数);dim:褪色(不合法 / 已丢掉)。不接鼠标。


const CREAM := Color(0.98, 0.94, 0.85)
const EDGE := Color(0.36, 0.24, 0.16)
const HIGHLIGHT := Color(1.0, 0.8, 0.36)
const BACK := Color(0.62, 0.46, 0.32)
# 点色(2D 版比 3D 的顶点色亮一点,HUD 上更醒目)
const PIP_COLORS := {
	1: Color(0.95, 0.62, 0.3), 2: Color(0.3, 0.74, 0.52), 3: Color(0.32, 0.56, 0.92), 4: Color(0.94, 0.4, 0.34),
	5: Color(0.62, 0.44, 0.9), 6: Color(0.88, 0.3, 0.68),
}

var value := 0
var highlight := false
var dim := false
var _style := StyleBoxFlat.new()
var _glow := StyleBoxFlat.new()


func _init(p_value := 0, size_px := 40.0) -> void:
	value = p_value
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style.corner_detail = 6
	_style.anti_aliasing = true


func set_value(v: int) -> void:
	if v != value:
		value = v
		queue_redraw()


func set_state(p_highlight: bool, p_dim: bool) -> void:
	if p_highlight != highlight or p_dim != dim:
		highlight = p_highlight
		dim = p_dim
		queue_redraw()


static func pip_points(v: int) -> Array:
	# 点位(以面心为原点、半边长为 1 的坐标);1 点只有面心(画星星)
	match v:
		1:
			return [Vector2.ZERO]
		2:
			return [Vector2(-1, -1), Vector2(1, 1)]
		3:
			return [Vector2(-1, -1), Vector2.ZERO, Vector2(1, 1)]
		4:
			return [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
		5:
			return [Vector2(-1, -1), Vector2(1, -1), Vector2.ZERO, Vector2(-1, 1), Vector2(1, 1)]
		6:
			return [Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)]
	return []


static func star_polygon(center: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + TAU * k / 10.0
		pts.append(center + Vector2(cos(a), sin(a)) * (outer if k % 2 == 0 else inner))
	return pts


func _draw() -> void:
	var side := minf(size.x, size.y)
	var rect := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	var tint := Color(1, 1, 1, 0.38) if dim else Color.WHITE
	if highlight:
		_glow.bg_color = Color(HIGHLIGHT, 0.35)
		_glow.set_corner_radius_all(int(side * 0.3))
		draw_style_box(_glow, rect.grow(side * 0.1))
	_style.bg_color = (BACK if value == 0 else CREAM) * tint
	_style.border_color = (HIGHLIGHT if highlight else EDGE) * tint
	_style.set_border_width_all(maxi(int(side * (0.08 if highlight else 0.05)), 1))
	_style.set_corner_radius_all(int(side * 0.24))
	_style.shadow_color = Color(0, 0, 0, 0.35 * tint.a)
	_style.shadow_size = int(side * 0.06)
	_style.shadow_offset = Vector2(0, side * 0.04)
	draw_style_box(_style, rect)
	var c := rect.get_center()
	if value == 0:
		var font := UiTheme.display_font()
		var fs := int(side * 0.6)
		draw_string(font, c + Vector2(-side * 0.17, side * 0.22), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(CREAM, 0.85 * tint.a))
		return
	var color: Color = PIP_COLORS.get(value, EDGE) * tint
	if value == 1:
		var star := star_polygon(c, side * 0.34, side * 0.15)
		draw_colored_polygon(star, color)
		star.append(star[0])
		draw_polyline(star, EDGE * Color(1, 1, 1, 0.5 * tint.a), maxf(side * 0.025, 1.0), true)
		return
	var spread := side * 0.25
	var radius := side * 0.095
	for p: Vector2 in pip_points(value):
		draw_circle(c + p * spread, radius, color)
		draw_circle(c + p * spread + Vector2(-radius * 0.3, -radius * 0.3), radius * 0.32, Color(1, 1, 1, 0.45 * tint.a))
