class_name DdzNameplate
extends PanelContainer
# 斗地主对手头顶铭牌:第一行 名字 + 身份签(「地主」金底 / 「农民」青绿底,定地主之前没有)+「托管」小签;
# 第二行 累计分(正绿负红)· 手牌张数(小牌背图标)· 叫分阶段写他叫了几分;只剩 1–2 张时张数变红并闪(报警)。
# 轮到他时黄铜高亮、放大一下再回弹,留一圈淡淡的暖光;离开的人整块变灰。


const ACTIVE_BG := Color(0.25, 0.15, 0.06, 0.85)
const DIMMED := Color(0.6, 0.6, 0.6, 0.75)
const GLOW := Color(1.0, 0.78, 0.36, 0.55)
const GLOW_REST := 5
const GLOW_PEAK := 16
const PULSE_TIME := 0.5
const LANDLORD_TINT := Color(0.86, 0.58, 0.2)
const FARMER_TINT := Color(0.3, 0.6, 0.48)
const TRUSTEE_TINT := Color(0.42, 0.46, 0.62)
const ALARM := Color(1.0, 0.42, 0.36)
const ROLE_TEXT := {DdzState.ROLE_LANDLORD: "地主", DdzState.ROLE_FARMER: "农民"}

var _name: Label
var _role: Label
var _trustee: Label
var _info: Label
var _style: StyleBoxFlat
var _role_style: StyleBoxFlat
var _active := false
var _pulse: Tween = null
var _blink: Tween = null
var _alarm := false


static func info_text(row: Dictionary) -> String:
	# 「累计 +12 · 剩 7 张 · 叫 2 分」
	if row.get("left", false):
		return "已离开"
	var parts := ["累计 %s" % signed(int(row.get("score", 0))), "剩 %d 张" % int(row.get("count", 0))]
	var bid: int = row.get("bid", -1)
	if bid >= 0:
		parts.append("叫 %d 分" % bid if bid > 0 else "不叫")
	return " · ".join(parts)


static func signed(n: int) -> String:
	return "+%d" % n if n > 0 else str(n)


static func is_alarm(row: Dictionary) -> bool:
	var n := int(row.get("count", 0))
	return n >= 1 and n <= 2 and str(row.get("role", "")) != ""


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
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 6)
	box.add_child(top)
	_name = UiTheme.label(display_name, 18, UiTheme.PARCHMENT, UiTheme.display_font())
	top.add_child(_name)
	_role = UiTheme.label("", 13, Color(0.12, 0.08, 0.04), UiTheme.body_font())
	_role_style = UiTheme.flat(LANDLORD_TINT, 7)
	_role_style.content_margin_left = 6
	_role_style.content_margin_right = 6
	_role.add_theme_stylebox_override("normal", _role_style)
	_role.visible = false
	top.add_child(_role)
	_trustee = UiTheme.label("托管", 12, Color(0.95, 0.95, 1.0), UiTheme.body_font())
	var t_style := UiTheme.flat(TRUSTEE_TINT, 7)
	t_style.content_margin_left = 5
	t_style.content_margin_right = 5
	_trustee.add_theme_stylebox_override("normal", t_style)
	_trustee.visible = false
	top.add_child(_trustee)
	_info = UiTheme.label("", 14, UiTheme.PARCHMENT_DIM)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_info)


func set_info(row: Dictionary) -> void:
	var role := str(row.get("role", ""))
	_role.visible = ROLE_TEXT.has(role)
	_role.text = ROLE_TEXT.get(role, "")
	_role_style.bg_color = LANDLORD_TINT if role == DdzState.ROLE_LANDLORD else FARMER_TINT
	_trustee.visible = bool(row.get("trustee", false)) and not bool(row.get("left", false))
	_info.text = info_text(row)
	var active := bool(row.get("active", false))
	_style.border_color = UiTheme.BRASS_BRIGHT if active else Color(UiTheme.BRASS, 0.45)
	_style.set_border_width_all(2 if active else 1)
	_style.bg_color = ACTIVE_BG if active else UiTheme.PANEL_SOFT
	modulate = DIMMED if row.get("left", false) else Color.WHITE
	_active = active
	if _pulse == null or not _pulse.is_valid():
		_set_glow(GLOW_REST if active else 0)
	_set_alarm(is_alarm(row))


func pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	pivot_offset = size / 2.0
	_pulse = create_tween().set_parallel()
	_pulse.tween_method(func(v: float) -> void: _set_glow(int(round(v))), float(GLOW_PEAK), float(GLOW_REST if _active else 0), PULSE_TIME)
	_pulse.tween_property(self, "scale", Vector2.ONE * 1.16, PULSE_TIME * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pulse.chain().tween_property(self, "scale", Vector2.ONE, PULSE_TIME * 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func info() -> String:
	return _info.text


func role_text() -> String:
	return _role.text if _role.visible else ""


func trustee_shown() -> bool:
	return _trustee.visible


func alarm_on() -> bool:
	return _alarm


func _set_alarm(on: bool) -> void:
	if on == _alarm:
		return
	_alarm = on
	if _blink != null and _blink.is_valid():
		_blink.kill()
	_info.add_theme_color_override("font_color", ALARM if on else UiTheme.PARCHMENT_DIM)
	_info.modulate = Color.WHITE
	if on:
		_blink = _info.create_tween().set_loops()
		_blink.tween_property(_info, "modulate", Color(1, 1, 1, 0.35), 0.35)
		_blink.tween_property(_info, "modulate", Color.WHITE, 0.35)


func _set_glow(px: int) -> void:
	_style.shadow_size = px
	_style.shadow_color = GLOW if px > 0 else Color(0, 0, 0, 0)
