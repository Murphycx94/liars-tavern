class_name LiarsDiceNameplate
extends PanelContainer
# 吹牛骰子对手头顶铭牌:名字 + 一排小骰子(还剩几颗亮着,丢掉的褪成空心)+ 这一轮他喊过的最后一口;
# 轮到他时黄铜高亮、「噗」地放大一下并留一圈暖金光晕(同炸弹猫铭牌);出局写「骰子输光了」、断线写「离开了」,整块变灰。


const ACTIVE_BG := Color(0.25, 0.15, 0.06, 0.85)
const DIMMED := Color(0.6, 0.6, 0.6, 0.75)
const GLOW := Color(1.0, 0.78, 0.36, 0.55)
const GLOW_REST := 5
const GLOW_PEAK := 16
const PULSE_TIME := 0.5
const PIP := 9.0
const PIP_GAP := 3.0
const PIP_ON := Color(0.98, 0.93, 0.82)
const PIP_OFF := Color(0.5, 0.42, 0.34, 0.6)

var _name: Label
var _info: Label
var _pips: Control
var _style: StyleBoxFlat
var _active := false
var _pulse: Tween = null
var _count := 0
var _alive := true


static func info_text(count: int, alive: bool, left: bool, last_bid: Dictionary) -> String:
	if not alive:
		return "离开了" if left else "骰子输光了"
	var text := "%d 颗" % count
	if not last_bid.is_empty():
		text += " · 喊过 %s" % LiarsDiceScreenState.bid_text(last_bid["count"], last_bid["face"])
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
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_name = UiTheme.label(display_name, 18, UiTheme.PARCHMENT, UiTheme.display_font())
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_name)
	_pips = Control.new()
	_pips.custom_minimum_size = Vector2((PIP + PIP_GAP) * LiarsDiceState.DICE_PER_PLAYER - PIP_GAP, PIP)
	_pips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.draw.connect(_draw_pips)
	box.add_child(_pips)
	_info = UiTheme.label("", 13, UiTheme.PARCHMENT_DIM)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_info)


func set_info(count: int, alive: bool, left: bool, active: bool, last_bid := {}) -> void:
	_info.text = info_text(count, alive, left, last_bid)
	_style.border_color = UiTheme.BRASS_BRIGHT if active else Color(UiTheme.BRASS, 0.45)
	_style.set_border_width_all(2 if active else 1)
	_style.bg_color = ACTIVE_BG if active else UiTheme.PANEL_SOFT
	modulate = DIMMED if not alive else Color.WHITE
	_active = active
	if count != _count or alive != _alive:
		_count = count
		_alive = alive
		_pips.queue_redraw()
	if _pulse == null or not _pulse.is_valid():
		_set_glow(GLOW_REST if active else 0)


func _draw_pips() -> void:
	# 小骰子:亮的是还剩的,空心的是丢掉的
	for i in LiarsDiceState.DICE_PER_PLAYER:
		var rect := Rect2(Vector2(i * (PIP + PIP_GAP), 0), Vector2(PIP, PIP))
		if i < _count and _alive:
			_pips.draw_rect(rect, PIP_ON)
			_pips.draw_circle(rect.get_center(), 1.4, Color(0.6, 0.35, 0.3))
		else:
			_pips.draw_rect(rect, PIP_OFF, false, 1.0)


func pulse() -> void:
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


func pip_count() -> int:
	return _count if _alive else 0
