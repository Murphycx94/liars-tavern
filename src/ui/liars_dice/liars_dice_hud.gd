class_name LiarsDiceHud
extends Control
# 吹牛骰子牌桌 HUD(设计稿 §3):
# - 左上:场上骰子总数、当前这一口(小骰子图标 + 「阿狸 喊 3 个 5」)、本轮出价记录、轮到谁、自己的状态;
# - 右上:「对话」「规则」按钮;右下:事件日志;画面中部:大字宣告;
# - 底部(自下而上):快捷键提示 / 自己的 5 颗骰子(2D)+ 出价器(个数 − / +、点数 2–6 六个骰子按钮、「加注」「开!」)/
#   回合横幅与环形倒计时 / 自己的对话气泡;
# - 开盅时画面上方居中一块「开盅」面板:每人的名字和点数(2D 骰子),算进去的那几颗随 3D 计数一颗颗亮起来,计数器一路数上去;
# - 出局后底部换成「观战中」的横幅(仍能丢番茄、说快捷语)。
# 出价器只画:合不合法由牌桌问 LiarsDicePicker / LiarsDiceState.bid_error 后经 set_picker 告诉它。
# 只发信号,不直接调用 Net / Sfx;按钮都 FOCUS_NONE(焦点会吃掉空格 / 回车)。


signal count_nudged(delta: int)
signal face_picked(face: int)
signal bid_pressed
signal challenge_pressed
signal rules_pressed
signal quip_pressed

const LOG_LINES := 6
const ANNOUNCE_Y := -110.0
const ANNOUNCE_Y_LOW := 150.0
const MY_BUBBLE_GAP := 2.0
const MY_DIE := 40.0
const FACE_BUTTON := 44.0
const LOG_ABOVE_BOTTOM := 160.0
const BIDS_SHOWN := 4
const HINT_IDLE := "↑↓ 个数 · 2–6 点数 · Enter 加注 · C / 空格 开! · 鼠标停在骰盅上偷看 · V 视角 · T 对话 · G 番茄 · Q 快捷语 · %s 规则 · Esc 离开"
const HINT_SPECTATE := "观战中:鼠标看人 · V 视角 · T 对话 · G 丢番茄 · Q 快捷语 · %s 规则 · Esc 离开"

var bid_button: Button
var challenge_button: Button
var minus_button: Button
var plus_button: Button
var face_buttons := {}           # face -> Button
var face_icons := {}             # face -> DiceIcon(按钮里的)
var my_dice_icons: Array = []    # DiceIcon × 最多 5

var _total_label: Label
var _bid_icon: DiceIcon
var _bid_label: Label
var _bids_label: Label
var _turn_info: Label
var _my_line: Label
var _turn_panel: PanelContainer
var _turn_label: Label
var _ring: CountdownRing
var _hint: Label
var _log_box: VBoxContainer
var _announce_box: VBoxContainer
var _announce: Label
var _announce_sub: Label
var _announce_tween: Tween = null
var _bubble_anchor: Control
var _action_row: HBoxContainer
var _dice_box: HBoxContainer
var _dice_title: Label
var _count_label: Label
var _picker_panel: PanelContainer
var _spectate_panel: PanelContainer
var _reveal_panel: PanelContainer
var _reveal_title: Label
var _reveal_counter: Label
var _reveal_grid: GridContainer
var _reveal_icons: Array = []    # 每行一个 [DiceIcon…](行序 = revealed.dice 的顺序)
var _reveal_face := 0
var _spectating := false
var _away := false
var _my_turn := false
var _face_idle := UiTheme.panel_box(Color(0.12, 0.09, 0.07, 0.8), Color(UiTheme.BRASS, 0.4), 1, 8)
var _face_selected := UiTheme.panel_box(Color(0.24, 0.17, 0.1, 0.95), UiTheme.BRASS_BRIGHT, 2, 8)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_info()
	_build_top_buttons()
	_build_bottom()
	_build_log()
	_build_announce()
	_build_reveal()


# —— 纯逻辑 ——

static func bid_line(bid: Dictionary, bidder: String, mine: bool) -> String:
	# 左上「当前这一口」:「阿狸 喊 3 个 5」;还没人喊时提示先喊一口
	if bid.is_empty():
		return "这一轮还没人喊"
	return "%s 喊 %s" % ["你" if mine else bidder, LiarsDiceScreenState.bid_text(bid["count"], bid["face"])]


static func bids_line(bids: Array) -> String:
	# 本轮出价记录(最近几口):「2 个 3 → 3 个 3 → 3 个 5」
	var parts := []
	for b in bids.slice(maxi(bids.size() - BIDS_SHOWN, 0)):
		if b is Dictionary and b.has("count") and b.has("face"):
			parts.append(LiarsDiceScreenState.bid_text(b["count"], b["face"]))
	if parts.is_empty():
		return ""
	return ("… → " if bids.size() > BIDS_SHOWN else "") + " → ".join(parts)


static func turn_info_text(current_name: String, mine: bool, has_bid: bool) -> String:
	if current_name == "":
		return ""
	if mine:
		return "轮到你:加注,或者「开!」" if has_bid else "轮到你先喊"
	return "轮到 %s" % current_name


static func bid_button_text(count: int, face: int) -> String:
	return "加注 %s" % LiarsDiceScreenState.bid_text(count, face)


# —— 构建 ——

func _build_info() -> void:
	var panel := PanelContainer.new()
	var style := UiTheme.panel_box(UiTheme.PANEL_SOFT, Color(UiTheme.BRASS, 0.5), 1, 12)
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(20, 16)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_to_group(WorldLabels.KEEP_OUT_GROUP)   # 对话气泡让开左上信息
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	_total_label = UiTheme.label("场上 — 颗骰子", 24, UiTheme.BRASS_BRIGHT, UiTheme.display_font())
	box.add_child(_total_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_bid_icon = DiceIcon.new(0, 26.0)
	row.add_child(_bid_icon)
	_bid_label = UiTheme.label("", 18, UiTheme.PARCHMENT, UiTheme.display_font())
	_bid_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_bid_label)
	_bids_label = UiTheme.label("", 13, UiTheme.PARCHMENT_DIM)
	box.add_child(_bids_label)
	_turn_info = UiTheme.label("", 16, UiTheme.PARCHMENT, UiTheme.display_font())
	box.add_child(_turn_info)
	_my_line = UiTheme.label("", 13, UiTheme.MUTED)
	box.add_child(_my_line)


func _build_top_buttons() -> void:
	# 右上:「对话 · T」「规则 · F1」(同其他牌桌)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.add_to_group(WorldLabels.KEEP_OUT_GROUP)
	row.add_child(_top_button("对话 · %s" % OS.get_keycode_string(Quips.TOGGLE_KEY), quip_pressed))
	row.add_child(_top_button("规则 · %s" % OS.get_keycode_string(RulebookContent.HOTKEY), rules_pressed))


func _top_button(text: String, sig: Signal) -> Button:
	var button := UiTheme.button(text)
	button.add_theme_font_size_override("font_size", 15)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): sig.emit())
	return button


func _build_bottom() -> void:
	var holder := VBoxContainer.new()
	holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.position.y -= 12
	holder.alignment = BoxContainer.ALIGNMENT_END
	holder.add_theme_constant_override("separation", 6)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_bubble_anchor = Control.new()
	_bubble_anchor.custom_minimum_size = Vector2(0, 36)
	_bubble_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_bubble_anchor)
	holder.add_child(_build_turn_row())
	_action_row = HBoxContainer.new()
	_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_row.add_theme_constant_override("separation", 12)
	_action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_action_row)
	_action_row.add_child(_build_dice_panel())
	_action_row.add_child(_build_picker())
	_spectate_panel = PanelContainer.new()
	_spectate_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.PANEL, Color(UiTheme.BLOOD, 0.7), 1, 16))
	_spectate_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spectate_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var spectate := UiTheme.label("骰子输光了 · 观战中", 22, UiTheme.PARCHMENT, UiTheme.display_font())
	spectate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectate_panel.add_child(spectate)
	_spectate_panel.visible = false
	holder.add_child(_spectate_panel)
	_hint = UiTheme.label("", 14, UiTheme.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(_hint)
	set_picker(1, LiarsDiceState.MIN_BID_FACE, {}, false, false, false, false, false)


func _panel_style(border: Color) -> StyleBoxFlat:
	var style := UiTheme.panel_box(UiTheme.PANEL, border, 1, 14)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	return style


func _build_dice_panel() -> PanelContainer:
	# 自己的骰子(2D,只有自己看得到):按私有视图、等演到那一轮再换
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(UiTheme.BRASS, 0.6)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_vertical = Control.SIZE_SHRINK_END
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_dice_title = UiTheme.label("你的骰子", 13, UiTheme.PARCHMENT_DIM)
	_dice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_dice_title)
	_dice_box = HBoxContainer.new()
	_dice_box.add_theme_constant_override("separation", 6)
	_dice_box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_dice_box)
	for i in LiarsDiceState.DICE_PER_PLAYER:
		var icon := DiceIcon.new(0, MY_DIE)
		_dice_box.add_child(icon)
		my_dice_icons.append(icon)
	return panel


func _build_picker() -> PanelContainer:
	# 出价器:个数 − [N] +  |  点数 2–6  |  「加注 N 个 X」「开!」
	_picker_panel = PanelContainer.new()
	_picker_panel.add_theme_stylebox_override("panel", _panel_style(Color(UiTheme.BRASS, 0.6)))
	_picker_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picker_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_picker_panel.add_child(row)
	var count_box := VBoxContainer.new()
	count_box.add_theme_constant_override("separation", 2)
	row.add_child(count_box)
	var count_title := UiTheme.label("个数 ↑↓", 13, UiTheme.PARCHMENT_DIM)
	count_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_box.add_child(count_title)
	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 4)
	count_box.add_child(count_row)
	minus_button = _small_button("−")
	minus_button.pressed.connect(func(): count_nudged.emit(-1))
	count_row.add_child(minus_button)
	_count_label = UiTheme.label("1", 30, UiTheme.BRASS_BRIGHT, UiTheme.display_font())
	_count_label.custom_minimum_size = Vector2(44, 0)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_row.add_child(_count_label)
	plus_button = _small_button("+")
	plus_button.pressed.connect(func(): count_nudged.emit(1))
	count_row.add_child(plus_button)
	var face_box := VBoxContainer.new()
	face_box.add_theme_constant_override("separation", 2)
	row.add_child(face_box)
	var face_title := UiTheme.label("点数 2–6(1 点万能)", 13, UiTheme.PARCHMENT_DIM)
	face_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face_box.add_child(face_title)
	var faces := HBoxContainer.new()
	faces.add_theme_constant_override("separation", 4)
	face_box.add_child(faces)
	for f in range(LiarsDiceState.MIN_BID_FACE, LiarsDiceState.FACES + 1):
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(FACE_BUTTON, FACE_BUTTON)
		button.tooltip_text = "点数 %d(按 %d)" % [f, f]
		var icon := DiceIcon.new(f, FACE_BUTTON - 10.0)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
		button.add_child(icon)
		button.pressed.connect(func(): face_picked.emit(f))
		faces.add_child(button)
		face_buttons[f] = button
		face_icons[f] = icon
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	row.add_child(buttons)
	bid_button = UiTheme.button("加注", true)
	bid_button.custom_minimum_size = Vector2(132, 50)
	bid_button.add_theme_font_size_override("font_size", 20)
	bid_button.focus_mode = Control.FOCUS_NONE
	bid_button.size_flags_vertical = Control.SIZE_SHRINK_END
	bid_button.pressed.connect(func(): bid_pressed.emit())
	buttons.add_child(bid_button)
	challenge_button = UiTheme.button("开!", false)
	challenge_button.custom_minimum_size = Vector2(88, 50)
	challenge_button.add_theme_font_size_override("font_size", 24)
	challenge_button.add_theme_color_override("font_color", UiTheme.LIE)
	challenge_button.focus_mode = Control.FOCUS_NONE
	challenge_button.size_flags_vertical = Control.SIZE_SHRINK_END
	challenge_button.tooltip_text = "质疑上一口(C 或空格)"
	challenge_button.pressed.connect(func(): challenge_pressed.emit())
	buttons.add_child(challenge_button)
	return _picker_panel


func _small_button(text: String) -> Button:
	var button := UiTheme.button(text)
	button.custom_minimum_size = Vector2(34, 40)
	button.add_theme_font_size_override("font_size", 22)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _build_turn_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_panel = PanelContainer.new()
	var style := UiTheme.panel_box(UiTheme.PANEL, Color(UiTheme.BRASS, 0.6), 1, 22)
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_turn_panel.add_theme_stylebox_override("panel", style)
	_turn_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_pivot(_turn_panel)
	row.add_child(_turn_panel)
	_turn_label = UiTheme.label("", 22, UiTheme.PARCHMENT, UiTheme.display_font())
	_turn_panel.add_child(_turn_label)
	_ring = CountdownRing.new()
	row.add_child(_ring)
	_turn_panel.visible = false
	_ring.visible = false
	return row


func _build_log() -> void:
	_log_box = VBoxContainer.new()
	_log_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_log_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_log_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_log_box.position += Vector2(-24, -LOG_ABOVE_BOTTOM)
	_log_box.custom_minimum_size = Vector2(280, 0)
	_log_box.alignment = BoxContainer.ALIGNMENT_END
	_log_box.add_theme_constant_override("separation", 4)
	_log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log_box)


func _build_announce() -> void:
	_announce_box = VBoxContainer.new()
	_announce_box.anchor_left = 0.0
	_announce_box.anchor_right = 1.0
	_announce_box.anchor_top = 0.5
	_announce_box.anchor_bottom = 0.5
	_announce_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_set_announce_y(ANNOUNCE_Y)
	_announce_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_announce_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_pivot(_announce_box)
	add_child(_announce_box)
	_announce = UiTheme.label("", 76, UiTheme.BRASS_BRIGHT, UiTheme.title_font())
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.add_theme_constant_override("shadow_offset_x", 3)
	_announce.add_theme_constant_override("shadow_offset_y", 5)
	_announce.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_announce_box.add_child(_announce)
	_announce_sub = UiTheme.label("", 24, UiTheme.PARCHMENT, UiTheme.display_font())
	_announce_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_box.add_child(_announce_sub)
	_announce_box.modulate.a = 0.0


func _build_reveal() -> void:
	_reveal_panel = PanelContainer.new()
	var style := UiTheme.panel_box(Color(0.07, 0.05, 0.04, 0.9), UiTheme.BRASS_BRIGHT, 2, 14)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	_reveal_panel.add_theme_stylebox_override("panel", style)
	_reveal_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_reveal_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_reveal_panel.position.y = 14
	_reveal_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reveal_panel.add_to_group(WorldLabels.KEEP_OUT_GROUP)   # 开盅时上缘的铭牌与气泡挪到面板下面,不被盖住
	add_child(_reveal_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_reveal_panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(head)
	_reveal_title = UiTheme.label("", 18, UiTheme.BRASS_BRIGHT, UiTheme.display_font())
	head.add_child(_reveal_title)
	_reveal_counter = UiTheme.label("", 18, UiTheme.PARCHMENT, UiTheme.display_font())
	head.add_child(_reveal_counter)
	_reveal_grid = GridContainer.new()
	_reveal_grid.add_theme_constant_override("h_separation", 22)
	_reveal_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_reveal_grid)
	_reveal_panel.visible = false


func _center_pivot(control: Control) -> void:
	control.resized.connect(func(): control.pivot_offset = control.size / 2.0)


# —— 左上信息 ——

func set_info(total: int, bid: Dictionary, bid_text: String, bids_text: String, turn_text: String, my_text: String) -> void:
	_total_label.text = "场上 %d 颗骰子" % total
	_bid_icon.set_value(bid["face"] if not bid.is_empty() else 0)
	_bid_icon.visible = not bid.is_empty()
	_bid_label.text = bid_text
	_bids_label.text = bids_text
	_bids_label.visible = bids_text != ""
	_turn_info.text = turn_text
	_turn_info.visible = turn_text != ""
	_my_line.text = my_text


func info_text() -> String:
	return "%s|%s|%s" % [_total_label.text, _bid_label.text, _turn_info.text]


# —— 自己的骰子 ——

func set_my_dice(dice_values: Array, alive: bool, match_face := 0) -> void:
	# match_face > 0:开盅时把算进去的(等于它或 1 点)高亮
	for i in my_dice_icons.size():
		var icon: DiceIcon = my_dice_icons[i]
		icon.visible = i < dice_values.size() or (alive and dice_values.is_empty() and i < LiarsDiceState.DICE_PER_PLAYER)
		icon.set_value(dice_values[i] if i < dice_values.size() else 0)
		icon.set_state(match_face > 0 and i < dice_values.size() and LiarsDiceScreenState.is_match(dice_values[i], match_face),
			not alive)
	_dice_title.text = "你的骰子 · %d 颗" % dice_values.size() if not dice_values.is_empty() else "你的骰子"


func my_dice_values() -> Array:
	var out := []
	for icon: DiceIcon in my_dice_icons:
		if icon.visible and icon.value > 0:
			out.append(icon.value)
	return out


func flash_my_dice() -> void:
	# 新摇的一盅:骰子一颗颗弹一下
	for i in my_dice_icons.size():
		var icon: DiceIcon = my_dice_icons[i]
		icon.pivot_offset = icon.custom_minimum_size / 2.0
		icon.scale = Vector2(0.6, 0.6)
		var tween := icon.create_tween()
		tween.tween_interval(0.05 * i)
		tween.tween_property(icon, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# —— 出价器 ——

func set_picker(count: int, face: int, face_ok: Dictionary, can_dec: bool, can_inc: bool, can_bid: bool, can_challenge: bool,
		my_turn: bool) -> void:
	# face_ok:face -> 当前个数下合不合法(不合法的点数按钮置灰);不是自己的回合时整块变暗但照样能先选好
	_my_turn = my_turn
	_count_label.text = str(count)
	minus_button.disabled = not can_dec
	plus_button.disabled = not can_inc
	for f in face_buttons:
		var ok: bool = face_ok.get(f, false)
		var button: Button = face_buttons[f]
		button.disabled = not ok
		var icon: DiceIcon = face_icons[f]
		icon.set_state(f == face and ok, not ok)
		button.add_theme_stylebox_override("normal", _face_selected if f == face and ok else _face_idle)
	bid_button.text = bid_button_text(count, face)
	bid_button.disabled = not can_bid
	challenge_button.disabled = not can_challenge
	_picker_panel.modulate = Color.WHITE if my_turn else Color(1, 1, 1, 0.72)
	_refresh_hint()


func picker_count() -> int:
	return int(_count_label.text)


func _refresh_hint() -> void:
	var key := OS.get_keycode_string(RulebookContent.HOTKEY)
	if _spectating:
		_hint.text = HINT_SPECTATE % key
	else:
		_hint.text = HINT_IDLE % key


# —— 开盅面板 ——

func show_reveal(rows: Array, face: int, target: int) -> void:
	# rows:[{"name", "dice": [点数]}](座位顺序);face:被质疑的点数;target:喊的个数
	for child in _reveal_grid.get_children():
		_reveal_grid.remove_child(child)
		child.queue_free()
	_reveal_icons = []
	_reveal_face = face
	_reveal_grid.columns = 3 if rows.size() > 4 else mini(maxi(rows.size(), 1), 2)
	for row in rows:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var name_label := UiTheme.label(str(row.get("name", "?")), 14, UiTheme.PARCHMENT_DIM)
		cell.add_child(name_label)
		var dice_row := HBoxContainer.new()
		dice_row.add_theme_constant_override("separation", 3)
		cell.add_child(dice_row)
		var icons := []
		for v in (row["dice"] if row.get("dice") is Array else []):
			var icon := DiceIcon.new(v, 26.0)
			dice_row.add_child(icon)
			icons.append(icon)
		_reveal_icons.append(icons)
		_reveal_grid.add_child(cell)
	_reveal_title.text = "开盅 · 数「%d」(1 点也算)" % face
	set_reveal_count(0, target)
	_reveal_panel.visible = true
	_reveal_panel.modulate.a = 0.0
	create_tween().tween_property(_reveal_panel, "modulate:a", 1.0, 0.2)


func reveal_mark(row: int, index: int) -> void:
	# 3D 里这一颗跳起来、算进去:面板上同一颗亮起来并弹一下
	if row < 0 or row >= _reveal_icons.size() or index < 0 or index >= _reveal_icons[row].size():
		return
	var icon: DiceIcon = _reveal_icons[row][index]
	icon.set_state(true, false)
	icon.pivot_offset = icon.custom_minimum_size / 2.0
	icon.scale = Vector2(1.35, 1.35)
	icon.create_tween().tween_property(icon, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_reveal_count(n: int, target: int) -> void:
	_reveal_counter.text = "数到 %d / 喊了 %d" % [n, target]
	_reveal_counter.add_theme_color_override("font_color", UiTheme.TRUTH if n >= target else UiTheme.PARCHMENT)


func reveal_finish(truthful: bool) -> void:
	# 数完:没算进去的褪色,计数器按判定变色
	for icons in _reveal_icons:
		for icon: DiceIcon in icons:
			if not icon.highlight:
				icon.set_state(false, true)
	_reveal_counter.add_theme_color_override("font_color", UiTheme.TRUTH if truthful else UiTheme.LIE)


func hide_reveal() -> void:
	_reveal_panel.visible = false


func is_reveal_open() -> bool:
	return _reveal_panel.visible


func reveal_marked() -> int:
	var n := 0
	for icons in _reveal_icons:
		for icon: DiceIcon in icons:
			if icon.highlight:
				n += 1
	return n


func reveal_counter_text() -> String:
	return _reveal_counter.text


# —— 回合与计时 ——

func set_turn(text: String, mine: bool) -> void:
	_turn_panel.visible = text != ""
	_turn_label.text = text
	_turn_label.add_theme_color_override("font_color", UiTheme.BRASS_BRIGHT if mine else UiTheme.PARCHMENT)
	var style: StyleBoxFlat = _turn_panel.get_theme_stylebox("panel")
	style.border_color = UiTheme.BRASS_BRIGHT if mine else Color(UiTheme.BRASS, 0.6)
	style.set_border_width_all(2 if mine else 1)
	if mine:
		var tween := create_tween()
		tween.tween_property(_turn_panel, "scale", Vector2(1.12, 1.12), 0.12)
		tween.tween_property(_turn_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func turn_text() -> String:
	return _turn_label.text if _turn_panel.visible else ""


func set_countdown(remaining: float, total: float, visible_ring: bool) -> void:
	_ring.visible = visible_ring
	if visible_ring:
		_ring.set_time(remaining, total)


func is_ring_visible() -> bool:
	return _ring.visible


func set_spectating(on: bool) -> void:
	_spectating = on
	_apply_visibility()
	_refresh_hint()


func set_away_from_seat(away: bool) -> void:
	# 镜头去拍特写(胜利环绕)时收起出价器与骰子
	_away = away
	_apply_visibility()
	if away:
		hide_reveal()


func _apply_visibility() -> void:
	var seated := not _away
	_action_row.visible = seated and not _spectating
	_spectate_panel.visible = seated and _spectating
	_hint.visible = seated


func is_picker_visible() -> bool:
	return _action_row.visible


# —— 日志、宣告、气泡 ——

func log_event(text: String, color := UiTheme.PARCHMENT) -> void:
	var label := UiTheme.label(text, 15, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(280, 0)
	_log_box.add_child(label)
	label.modulate.a = 0.0
	create_tween().tween_property(label, "modulate:a", 1.0, 0.25)
	while _log_box.get_child_count() > LOG_LINES:
		var oldest := _log_box.get_child(0)
		_log_box.remove_child(oldest)
		oldest.queue_free()
	for i in _log_box.get_child_count():
		var child: Control = _log_box.get_child(i)
		child.self_modulate.a = lerpf(0.35, 1.0, float(i + 1) / _log_box.get_child_count())


func log_lines() -> Array:
	return _log_box.get_children().map(func(l: Label) -> String: return l.text)


func announce(text: String, color: Color, sub := "", hold := 1.0, y_offset := ANNOUNCE_Y) -> void:
	if _announce_tween != null and _announce_tween.is_valid():
		_announce_tween.kill()
	_set_announce_y(y_offset)
	_announce.text = text
	_announce.add_theme_color_override("font_color", color)
	_announce_sub.text = sub
	_announce_box.scale = Vector2(1.6, 1.6)
	_announce_box.modulate.a = 0.0
	_announce_tween = create_tween()
	_announce_tween.set_parallel()
	_announce_tween.tween_property(_announce_box, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_announce_tween.tween_property(_announce_box, "modulate:a", 1.0, 0.18)
	_announce_tween.chain().tween_interval(hold)
	_announce_tween.chain().tween_property(_announce_box, "modulate:a", 0.0, 0.4)


func announce_text() -> String:
	return _announce.text


func _set_announce_y(y_offset: float) -> void:
	_announce_box.offset_top = y_offset
	_announce_box.offset_bottom = y_offset


func clear_my_bubble() -> void:
	for old in _bubble_anchor.get_children():
		_bubble_anchor.remove_child(old)
		old.queue_free()


func my_bubble(text: String, color := UiTheme.INK, duration := 1.6) -> void:
	# 自己的喊价 / 九宫格快捷对话:弹在出价器上方居中;新的一句顶掉旧的
	clear_my_bubble()
	var bubble := SpeechBubble.new(text, color, duration)
	_bubble_anchor.add_child(bubble)
	bubble.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE,
		int(SpeechBubble.TAIL_LENGTH + MY_BUBBLE_GAP))
	bubble.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bubble.grow_vertical = Control.GROW_DIRECTION_BEGIN


func has_my_bubble() -> bool:
	return _bubble_anchor.get_child_count() > 0
