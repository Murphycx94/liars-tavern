class_name BombCatNameplate
extends PanelContainer
# 炸弹猫对手头顶铭牌:名字 + 手牌张数(小牌背图标 × N);轮到他时黄铜高亮(被甩锅时标出还要走几回合),
# 炸飞的写「炸飞了」、断线的写「离开了」,整块变灰。轮到他时(pulse)铭牌「噗」地放大一下、外圈泛起一圈暖金光,
# 之后一直留一圈淡淡的光晕直到不再轮到他。


const ACTIVE_BG := Color(0.25, 0.15, 0.06, 0.85)
const DIMMED := Color(0.6, 0.6, 0.6, 0.75)
const GLOW := Color(1.0, 0.78, 0.36, 0.55)
const GLOW_REST := 5                  # 轮到他时一直留着的光晕(像素)
const GLOW_PEAK := 16
const PULSE_TIME := 0.5

var _name: Label
var _info: Label
var _style: StyleBoxFlat
var _active := false
var _pulse: Tween = null


static func info_text(hand_count: int, alive: bool, exploded: bool, active: bool, turns: int) -> String:
	if not alive:
		return "炸飞了" if exploded else "离开了"
	var text := "手牌 %d" % hand_count
	if active and turns > 1:
		text += " · 还要走 %d 回合" % turns
	return text


func _init(display_name: String) -> void:
	_style = UiTheme.panel_box(UiTheme.PANEL_SOFT, Color(UiTheme.BRASS, 0.45), 1, 10)
	_style.content_margin_left = 12
	_style.content_margin_right = 12
	_style.content_margin_top = 5
	_style.content_margin_bottom = 5
	add_theme_stylebox_override("panel", _style)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	add_child(box)
	_name = UiTheme.label(display_name, 18, UiTheme.PARCHMENT, UiTheme.display_font())
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_name)
	_info = UiTheme.label("", 14, UiTheme.PARCHMENT_DIM)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_info)


func set_info(hand_count: int, alive: bool, exploded: bool, active: bool, turns := 1) -> void:
	_info.text = info_text(hand_count, alive, exploded, active, turns)
	_info.add_theme_color_override("font_color", UiTheme.BLOOD if not alive and exploded else UiTheme.PARCHMENT_DIM)
	_style.border_color = UiTheme.BRASS_BRIGHT if active else Color(UiTheme.BRASS, 0.45)
	_style.set_border_width_all(2 if active else 1)
	_style.bg_color = ACTIVE_BG if active else UiTheme.PANEL_SOFT
	modulate = DIMMED if not alive else Color.WHITE
	_active = active
	if _pulse == null or not _pulse.is_valid():
		_set_glow(GLOW_REST if active else 0)


func pulse() -> void:
	# 轮到他了:放大一下再回弹,光晕从大到小收成常驻的一圈
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	pivot_offset = size / 2.0
	_pulse = create_tween().set_parallel()
	_pulse.tween_method(func(v: float) -> void: _set_glow(int(round(v))), float(GLOW_PEAK), float(GLOW_REST if _active else 0), PULSE_TIME)
	_pulse.tween_property(self, "scale", Vector2.ONE * 1.18, PULSE_TIME * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pulse.chain().tween_property(self, "scale", Vector2.ONE, PULSE_TIME * 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func glow_size() -> int:
	return _style.shadow_size


func _set_glow(px: int) -> void:
	_style.shadow_size = px
	_style.shadow_color = GLOW if px > 0 else Color(0, 0, 0, 0)


func info() -> String:
	return _info.text
