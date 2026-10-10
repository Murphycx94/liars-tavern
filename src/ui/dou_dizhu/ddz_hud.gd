class_name DdzHud
extends Control
# 斗地主牌桌 HUD(设计稿 §3、§6.11):
# - 左上:「斗地主 · 第 N 手」、底分与倍数(倍数变了「噗」地跳一下)、地主是谁、3 张底牌小图(叫分时是牌背,定地主后亮面)、一行状态;
# - 右上:房主的「散局」、「对话 · T」、「规则 · F1」;顶部居中:「本手结束后散局」的横条;
# - 底部(自下而上):快捷键提示 / 自己的 2D 手牌条(点选、拖动连选、右键清空)/ 按钮行(出牌阶段「不出」「重选」「提示」「出牌」,
#   叫分阶段「不叫」「1 分」「2 分」「3 分」;不是自己时是「等待 X 出牌…」的横幅)+ 环形倒计时 / 托管中的横条 / 自己的对话气泡;
# - 左下:自己的名字、身份签、累计分、手牌张数,下面「托管 / 取消托管」;右下:事件日志;画面中部:大字宣告;
# - 一手打完:画面右侧一块这一手的结算(谁赢了、底分 × 倍数、每人得失、春天 / 炸弹)直到下一手开始。
# 只发信号,不直接调用 Net / Sfx;按钮都 FOCUS_NONE(焦点会吃掉空格 / 回车)。


signal play_pressed
signal pass_pressed
signal hint_pressed
signal reset_pressed
signal bid_pressed(score: int)
signal trustee_pressed
signal end_pressed
signal rules_pressed
signal quip_pressed
signal selection_changed(selected: Dictionary)
signal card_hovered(index: int)

const LOG_LINES := 6
const ANNOUNCE_Y := -120.0
const ANNOUNCE_Y_LOW := 140.0
const MY_BUBBLE_GAP := 2.0
const MINI_CARD := Vector2(36, 52)
const BUTTON_SIZE := Vector2(112, 46)
const LOG_ABOVE_BOTTOM := 236.0
const ACTION_NONE := "none"
const ACTION_BID := "bid"
const ACTION_PLAY := "play"
const ENDING_TEXT := "房主已散局 · 打完这一手就结算"
const END_TEXT := "散局"
const HINT_PLAY := "点牌或拖动连选 · Enter 出牌 · 空格 / P 不出 · H 提示 · R 重选 · 右键清空 · V 视角 · T 对话 · G 番茄 · Q 快捷语 · %s 规则 · Esc 离开"
const HINT_BID := "1 / 2 / 3 叫分 · 0、空格或 P 不叫 · 可以先点选手牌 · V 视角 · T 对话 · G 番茄 · Q 快捷语 · %s 规则 · Esc 离开"
const HINT_IDLE := "可以先点选手牌 · WASD 探头 · V 视角 · T 对话 · G 番茄 · Q 快捷语 · %s 规则 · Esc 离开"

var strip: DdzHandStrip
var end_button: Button
var trustee_button: Button
var play_button: Button
var pass_button: Button
var hint_button: Button
var reset_button: Button
var bid_buttons := {}            # 分数 -> Button
var action_mode := ACTION_NONE

var _title: Label
var _base_label: Label
var _mult_label: Label
var _landlord_label: Label
var _status: Label
var _bottom_row: HBoxContainer
var _bottom_faces: Array[TextureRect] = []
var _bottom_ids: Array = []
var _ending_panel: PanelContainer
var _turn_panel: PanelContainer
var _turn_label: Label
var _check_label: Label
var _ring: CountdownRing
var _play_box: HBoxContainer
var _bid_box: HBoxContainer
var _action_row: HBoxContainer
var _trustee_panel: PanelContainer
var _hint: Label
var _log_box: VBoxContainer
var _announce_box: VBoxContainer
var _announce: Label
var _announce_sub: Label
var _announce_tween: Tween = null
var _bubble_anchor: Control
var _my_name: Label
var _my_role: Label
var _my_role_style: StyleBoxFlat
var _my_info: Label
var _summary: PanelContainer
var _summary_box: VBoxContainer
var _bottom_holder: VBoxContainer
var _my_panel: PanelContainer
var _multiplier := 1
var _away := false
var _mult_tween: Tween = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_info()
	_build_top_right()
	_build_ending()
	_build_bottom()
	_build_my_panel()
	_build_log()
	_build_summary()
	_build_announce()
	PokerFaces.built_signal().connect(_refresh_bottom_faces)
	DdzJokerFaces.built_signal().connect(_refresh_bottom_faces)


# —— 纯逻辑 ——

static func turn_text(name: String, mine: bool, stage: String) -> String:
	if name == "":
		return ""
	if mine:
		return "轮到你叫分了" if stage == DdzState.STAGE_BID else "轮到你出牌了"
	return ("等待 %s 叫分…" if stage == DdzState.STAGE_BID else "等待 %s 出牌…") % name


static func status_text(phase: String, highest_bid: int, ending: bool) -> String:
	if ending:
		return "本手结束后散局"
	match phase:
		DdzScreenState.PHASE_BIDDING:
			return "叫分中 · 最高 %d 分" % highest_bid if highest_bid > 0 else "叫分中 · 还没人叫"
		DdzScreenState.PHASE_PLAYING:
			return "出牌中"
		DdzScreenState.PHASE_BETWEEN:
			return "这一手打完了,下一手马上开始"
		DdzScreenState.PHASE_OVER:
			return "牌局结束"
	return "等待开局"


static func summary_title(last_hand: Dictionary, my_role: String) -> String:
	var landlord_won: bool = last_hand.get("landlord_won") is bool and last_hand["landlord_won"]
	if my_role == "":
		return "地主赢了!" if landlord_won else "农民赢了!"
	var i_won := (my_role == DdzState.ROLE_LANDLORD) == landlord_won
	return ("你赢了!" if i_won else "你输了…") + ("(地主胜)" if landlord_won else "(农民胜)")


static func formula_text(last_hand: Dictionary) -> String:
	# 「底分 2 × 倍数 8 = 16 · 炸弹 2 个 · 春天」
	var base := int(last_hand.get("base", 0)) if last_hand.get("base") is int else 0
	var mult := int(last_hand.get("multiplier", 1)) if last_hand.get("multiplier") is int else 1
	var parts := ["底分 %d × 倍数 %d = %d" % [base, mult, base * mult]]
	var bombs := int(last_hand.get("bombs", 0)) if last_hand.get("bombs") is int else 0
	if bombs > 0:
		parts.append("炸弹 %d 个" % bombs)
	if last_hand.get("spring") is bool and last_hand["spring"]:
		parts.append("春天")
	return " · ".join(parts)


# —— 构建 ——

func _build_info() -> void:
	var panel := PanelContainer.new()
	var style := UiTheme.panel_box(UiTheme.PANEL_SOFT, Color(UiTheme.BRASS, 0.5), 1, 12)
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(20, 16)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_to_group(WorldLabels.KEEP_OUT_GROUP)   # 对话气泡让开左上信息
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_title = UiTheme.label("斗地主", 20, UiTheme.BRASS, UiTheme.display_font())
	box.add_child(_title)
	var nums := HBoxContainer.new()
	nums.add_theme_constant_override("separation", 18)
	box.add_child(nums)
	_base_label = UiTheme.label("底分 —", 26, UiTheme.PARCHMENT, UiTheme.display_font())
	nums.add_child(_base_label)
	_mult_label = UiTheme.label("倍数 ×1", 26, UiTheme.BRASS_BRIGHT, UiTheme.display_font())
	_mult_label.resized.connect(func(): _mult_label.pivot_offset = _mult_label.size / 2.0)
	nums.add_child(_mult_label)
	var lord := HBoxContainer.new()
	lord.add_theme_constant_override("separation", 10)
	box.add_child(lord)
	_landlord_label = UiTheme.label("地主:—", 16, UiTheme.PARCHMENT_DIM)
	_landlord_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lord.add_child(_landlord_label)
	_bottom_row = HBoxContainer.new()
	_bottom_row.add_theme_constant_override("separation", 4)
	lord.add_child(_bottom_row)
	for i in DdzState.BOTTOM_SIZE:
		var face := TextureRect.new()
		face.custom_minimum_size = MINI_CARD
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_SCALE
		face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bottom_row.add_child(face)
		_bottom_faces.append(face)
	_bottom_row.visible = false
	_status = UiTheme.label("", 14, UiTheme.MUTED)
	box.add_child(_status)


func _build_top_right() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.add_to_group(WorldLabels.KEEP_OUT_GROUP)
	end_button = _top_button(END_TEXT, end_pressed)
	end_button.visible = false
	row.add_child(end_button)
	row.add_child(_top_button("对话 · %s" % OS.get_keycode_string(Quips.TOGGLE_KEY), quip_pressed))
	row.add_child(_top_button("规则 · %s" % OS.get_keycode_string(RulebookContent.HOTKEY), rules_pressed))


func _top_button(text: String, sig: Signal) -> Button:
	var button := UiTheme.button(text)
	button.add_theme_font_size_override("font_size", 15)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): sig.emit())
	return button


func _build_ending() -> void:
	_ending_panel = PanelContainer.new()
	var style := UiTheme.panel_box(Color(0.3, 0.1, 0.06, 0.85), UiTheme.LIE, 1, 12)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_ending_panel.add_theme_stylebox_override("panel", style)
	_ending_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_ending_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ending_panel.position.y = 18
	_ending_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ending_panel.add_child(UiTheme.label(ENDING_TEXT, 16, UiTheme.PARCHMENT, UiTheme.display_font()))
	_ending_panel.visible = false
	_ending_panel.add_to_group(WorldLabels.KEEP_OUT_GROUP)   # 「房主已散局」横条:铭牌与气泡让开
	add_child(_ending_panel)


func _build_bottom() -> void:
	_bottom_holder = VBoxContainer.new()
	var holder := _bottom_holder
	holder.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
	holder.grow_vertical = Control.GROW_DIRECTION_BEGIN
	holder.position.y -= 10
	holder.alignment = BoxContainer.ALIGNMENT_END
	holder.add_theme_constant_override("separation", 6)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	_bubble_anchor = Control.new()
	_bubble_anchor.custom_minimum_size = Vector2(0, 30)
	_bubble_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_bubble_anchor)
	_trustee_panel = PanelContainer.new()
	var t_style := UiTheme.panel_box(Color(0.12, 0.13, 0.22, 0.9), Color(0.55, 0.6, 0.85), 1, 12)
	t_style.content_margin_left = 14
	t_style.content_margin_right = 14
	t_style.content_margin_top = 3
	t_style.content_margin_bottom = 3
	_trustee_panel.add_theme_stylebox_override("panel", t_style)
	_trustee_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_trustee_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trustee_panel.add_child(UiTheme.label("托管中 · 轮到你时自动出牌(点左下「取消托管」接回来)", 15, Color(0.85, 0.88, 1.0)))
	_trustee_panel.visible = false
	holder.add_child(_trustee_panel)
	_action_row = HBoxContainer.new()
	_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_row.add_theme_constant_override("separation", 12)
	_action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_action_row)
	_turn_panel = PanelContainer.new()
	var style := UiTheme.panel_box(UiTheme.PANEL, Color(UiTheme.BRASS, 0.6), 1, 20)
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	style.content_margin_left = 16
	style.content_margin_right = 16
	_turn_panel.add_theme_stylebox_override("panel", style)
	_turn_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_panel.resized.connect(func(): _turn_panel.pivot_offset = _turn_panel.size / 2.0)
	_turn_label = UiTheme.label("", 20, UiTheme.PARCHMENT, UiTheme.display_font())
	_turn_panel.add_child(_turn_label)
	_turn_panel.visible = false
	_action_row.add_child(_turn_panel)
	_play_box = HBoxContainer.new()
	_play_box.add_theme_constant_override("separation", 10)
	_action_row.add_child(_play_box)
	pass_button = _action_button("不出", false, pass_pressed)
	reset_button = _action_button("重选", false, reset_pressed)
	hint_button = _action_button("提示", false, hint_pressed)
	play_button = _action_button("出牌", true, play_pressed)
	for b in [pass_button, reset_button, hint_button, play_button]:
		_play_box.add_child(b)
	_bid_box = HBoxContainer.new()
	_bid_box.add_theme_constant_override("separation", 10)
	_action_row.add_child(_bid_box)
	for score in range(0, DdzState.MAX_BID + 1):
		var b := UiTheme.button(DdzScreenState.bid_text(score), score > 0)
		b.custom_minimum_size = BUTTON_SIZE
		b.add_theme_font_size_override("font_size", 22)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): bid_pressed.emit(score))
		bid_buttons[score] = b
		_bid_box.add_child(b)
	_check_label = UiTheme.label("", 16, UiTheme.PARCHMENT_DIM, UiTheme.display_font())
	_check_label.custom_minimum_size = Vector2(150, 0)
	_check_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_check_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_action_row.add_child(_check_label)
	_ring = CountdownRing.new()
	_ring.visible = false
	_action_row.add_child(_ring)
	strip = DdzHandStrip.new()
	strip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	strip.selection_changed.connect(func(sel: Dictionary): selection_changed.emit(sel))
	strip.card_hovered.connect(func(i: int): card_hovered.emit(i))
	strip.reset_requested.connect(func(): reset_pressed.emit())
	holder.add_child(strip)
	_hint = UiTheme.label("", 13, UiTheme.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(_hint)
	set_action_mode(ACTION_NONE)


func _action_button(text: String, primary: bool, sig: Signal) -> Button:
	var b := UiTheme.button(text, primary)
	b.custom_minimum_size = BUTTON_SIZE
	b.add_theme_font_size_override("font_size", 22)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): sig.emit())
	return b


func _build_my_panel() -> void:
	_my_panel = PanelContainer.new()
	var style := UiTheme.panel_box(UiTheme.PANEL_SOFT, Color(UiTheme.BRASS, 0.5), 1, 12)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	_my_panel.add_theme_stylebox_override("panel", style)
	_my_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_my_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_my_panel.position += Vector2(20, -16)
	_my_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_my_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_my_panel.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)
	_my_name = UiTheme.label("你", 20, UiTheme.PARCHMENT, UiTheme.display_font())
	top.add_child(_my_name)
	_my_role = UiTheme.label("", 14, Color(0.12, 0.08, 0.04))
	_my_role_style = UiTheme.flat(DdzNameplate.LANDLORD_TINT, 7)
	_my_role_style.content_margin_left = 7
	_my_role_style.content_margin_right = 7
	_my_role.add_theme_stylebox_override("normal", _my_role_style)
	_my_role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_my_role.visible = false
	top.add_child(_my_role)
	_my_info = UiTheme.label("", 15, UiTheme.PARCHMENT_DIM)
	box.add_child(_my_info)
	trustee_button = UiTheme.button("托管")
	trustee_button.add_theme_font_size_override("font_size", 16)
	trustee_button.focus_mode = Control.FOCUS_NONE
	trustee_button.tooltip_text = "托管:轮到你时系统自动替你出牌;再点一下取消"
	trustee_button.pressed.connect(func(): trustee_pressed.emit())
	box.add_child(trustee_button)


func _build_log() -> void:
	_log_box = VBoxContainer.new()
	_log_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_log_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_log_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_log_box.position += Vector2(-24, -LOG_ABOVE_BOTTOM)
	_log_box.custom_minimum_size = Vector2(270, 0)
	_log_box.alignment = BoxContainer.ALIGNMENT_END
	_log_box.add_theme_constant_override("separation", 4)
	_log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_log_box)


func _build_summary() -> void:
	_summary = PanelContainer.new()
	var style := UiTheme.panel_box(Color(0.07, 0.05, 0.04, 0.9), UiTheme.BRASS_BRIGHT, 2, 14)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_summary.add_theme_stylebox_override("panel", style)
	_summary.anchor_left = 1.0
	_summary.anchor_right = 1.0
	_summary.anchor_top = 0.5
	_summary.anchor_bottom = 0.5
	_summary.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_summary.grow_vertical = Control.GROW_DIRECTION_BOTH
	_summary.offset_right = -24
	_summary.offset_top = -170
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_summary_box = VBoxContainer.new()
	_summary_box.add_theme_constant_override("separation", 6)
	_summary.add_child(_summary_box)
	_summary.visible = false
	add_child(_summary)


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
	_announce_box.resized.connect(func(): _announce_box.pivot_offset = _announce_box.size / 2.0)
	add_child(_announce_box)
	_announce = UiTheme.label("", 72, UiTheme.BRASS_BRIGHT, UiTheme.title_font())
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.add_theme_constant_override("shadow_offset_x", 3)
	_announce.add_theme_constant_override("shadow_offset_y", 5)
	_announce.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_announce_box.add_child(_announce)
	_announce_sub = UiTheme.label("", 24, UiTheme.PARCHMENT, UiTheme.display_font())
	_announce_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_box.add_child(_announce_sub)
	_announce_box.modulate.a = 0.0


# —— 左上信息 ——

func set_info(hand: int, base: int, multiplier: int, landlord_name: String, bottom: Array, bottom_hidden: bool, status: String) -> void:
	_title.text = "斗地主 · 第 %d 手" % hand if hand > 0 else "斗地主"
	_base_label.text = "底分 %s" % (str(base) if base > 0 else "—")
	set_multiplier(multiplier, false)   # 跳动交给导演:炸弹、王炸、春天那一拍再 pop_multiplier
	_landlord_label.text = "地主:%s" % (landlord_name if landlord_name != "" else "—")
	_bottom_ids = bottom.duplicate() if not bottom_hidden else []
	_bottom_row.visible = bottom_hidden or not bottom.is_empty()
	_refresh_bottom_faces()
	_status.text = status


func set_multiplier(multiplier: int, pop := true) -> void:
	var changed := multiplier != _multiplier
	_multiplier = multiplier
	_mult_label.text = "倍数 ×%d" % multiplier
	if changed and pop:
		pop_multiplier()


func pop_multiplier() -> void:
	# 倍数翻倍:数字「噗」地放大、闪金光再回弹
	if not is_inside_tree():
		return
	if _mult_tween != null and _mult_tween.is_valid():
		_mult_tween.kill()
	_mult_label.scale = Vector2.ONE * 1.7
	_mult_label.modulate = Color(1.6, 1.3, 0.7)
	_mult_tween = create_tween().set_parallel()
	_mult_tween.tween_property(_mult_label, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_mult_tween.tween_property(_mult_label, "modulate", Color.WHITE, 0.6)


func multiplier_text() -> String:
	return _mult_label.text


func base_text() -> String:
	return _base_label.text


func landlord_text() -> String:
	return _landlord_label.text


func bottom_shown() -> Array:
	return _bottom_ids.duplicate() if _bottom_row.visible else []


func bottom_row_visible() -> bool:
	return _bottom_row.visible


func _refresh_bottom_faces() -> void:
	for i in _bottom_faces.size():
		var id: int = _bottom_ids[i] if i < _bottom_ids.size() else -1
		_bottom_faces[i].texture = DdzJokerFaces.texture_for(id)


func preview_candidates() -> Array:
	# 悬停大图:手牌条与左上亮出来的底牌
	var out: Array = strip.preview_candidates()
	if _bottom_row.is_visible_in_tree() and not _bottom_ids.is_empty():
		for i in _bottom_faces.size():
			var face := _bottom_faces[i]
			var rect := face.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, face.size)
			out.append(CardPreview.rect_candidate(rect, face.texture, 100 + i, face.get_instance_id()))
	return out


func set_ending(on: bool) -> void:
	_ending_panel.visible = on
	end_button.disabled = on
	end_button.text = "已散局" if on else END_TEXT


func set_host(host: bool) -> void:
	end_button.visible = host


# —— 自己 ——

func set_me(display_name: String, row: Dictionary, trustee: bool, can_toggle: bool) -> void:
	_my_name.text = display_name
	var role := str(row.get("role", ""))
	_my_role.visible = DdzNameplate.ROLE_TEXT.has(role)
	_my_role.text = DdzNameplate.ROLE_TEXT.get(role, "")
	_my_role_style.bg_color = DdzNameplate.LANDLORD_TINT if role == DdzState.ROLE_LANDLORD else DdzNameplate.FARMER_TINT
	_my_info.text = "累计 %s · 剩 %d 张" % [DdzNameplate.signed(int(row.get("score", 0))), int(row.get("count", 0))]
	trustee_button.text = "取消托管" if trustee else "托管"
	trustee_button.disabled = not can_toggle
	_trustee_panel.visible = trustee and not _away


func my_info() -> String:
	return _my_info.text


# —— 按钮行 ——

func set_action_mode(mode: String) -> void:
	action_mode = mode
	_play_box.visible = mode == ACTION_PLAY
	_bid_box.visible = mode == ACTION_BID
	_check_label.visible = mode == ACTION_PLAY
	_apply_visibility()


func set_play_actions(can_play: bool, can_pass: bool, can_hint: bool, can_reset: bool, check_text: String, check_ok: bool) -> void:
	play_button.disabled = not can_play
	pass_button.visible = can_pass
	hint_button.disabled = not can_hint
	reset_button.disabled = not can_reset
	_check_label.text = check_text
	_check_label.add_theme_color_override("font_color", UiTheme.TRUTH if check_ok else (UiTheme.LIE if check_text != "" else UiTheme.PARCHMENT_DIM))


func set_bid_actions(options: Array) -> void:
	for score in bid_buttons:
		bid_buttons[score].disabled = not options.has(score)


func set_turn(text: String, mine: bool) -> void:
	var changed := text != _turn_label.text or _turn_panel.visible != (text != "")
	_turn_panel.visible = text != ""
	_turn_label.text = text
	_turn_label.add_theme_color_override("font_color", UiTheme.BRASS_BRIGHT if mine else UiTheme.PARCHMENT)
	var style: StyleBoxFlat = _turn_panel.get_theme_stylebox("panel")
	style.border_color = UiTheme.BRASS_BRIGHT if mine else Color(UiTheme.BRASS, 0.6)
	style.set_border_width_all(2 if mine else 1)
	if mine and changed and is_inside_tree():
		var tween := create_tween()
		tween.tween_property(_turn_panel, "scale", Vector2(1.12, 1.12), 0.12)
		tween.tween_property(_turn_panel, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func turn_label() -> String:
	return _turn_label.text if _turn_panel.visible else ""


func set_countdown(remaining: float, total: float, visible_ring: bool) -> void:
	_ring.visible = visible_ring
	if visible_ring:
		_ring.set_time(remaining, total)


func set_hint_mode(mode: String) -> void:
	var key := OS.get_keycode_string(RulebookContent.HOTKEY)
	match mode:
		ACTION_BID:
			_hint.text = HINT_BID % key
		ACTION_PLAY:
			_hint.text = HINT_PLAY % key
		_:
			_hint.text = HINT_IDLE % key


func set_hand(ids: Array, selected: Dictionary, enabled: bool) -> void:
	strip.set_hand(ids, selected, enabled)


func set_away_from_seat(away: bool) -> void:
	# 镜头去拍结算环绕时收起手牌条与按钮行
	_away = away
	_apply_visibility()


func _apply_visibility() -> void:
	if _bottom_holder == null:
		return
	_bottom_holder.visible = not _away
	if _my_panel != null:
		_my_panel.visible = not _away
	if _away:
		_trustee_panel.visible = false


# —— 一手的结算摘要 ——

func show_summary(title: String, formula: String, rows: Array, my_pid: int) -> void:
	for child in _summary_box.get_children():
		_summary_box.remove_child(child)
		child.queue_free()
	var head := UiTheme.label(title, 30, UiTheme.BRASS_BRIGHT, UiTheme.title_font())
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_box.add_child(head)
	var sub := UiTheme.label(formula, 15, UiTheme.PARCHMENT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_box.add_child(sub)
	for row in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var role := UiTheme.label(DdzNameplate.ROLE_TEXT.get(row["role"], ""), 13, Color(0.12, 0.08, 0.04))
		var rs := UiTheme.flat(DdzNameplate.LANDLORD_TINT if row["role"] == DdzState.ROLE_LANDLORD else DdzNameplate.FARMER_TINT, 6)
		rs.content_margin_left = 5
		rs.content_margin_right = 5
		role.add_theme_stylebox_override("normal", rs)
		role.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(role)
		var who := UiTheme.label(str(row["name"]) + ("(你)" if row["pid"] == my_pid else ""), 18, UiTheme.PARCHMENT, UiTheme.display_font())
		who.custom_minimum_size.x = 150
		who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_child(who)
		var delta: int = row["delta"]
		var d := UiTheme.label(DdzNameplate.signed(delta), 20, UiTheme.TRUTH if delta > 0 else (UiTheme.LIE if delta < 0 else UiTheme.PARCHMENT_DIM),
			UiTheme.latin_font())
		d.custom_minimum_size.x = 56
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(d)
		var total := UiTheme.label("累计 %s" % DdzNameplate.signed(int(row["score"])), 14, UiTheme.MUTED)
		total.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(total)
		_summary_box.add_child(line)
	_summary.visible = true
	_summary.scale = Vector2(0.9, 0.9)
	_summary.pivot_offset = _summary.size / 2.0
	if is_inside_tree():
		_summary.create_tween().tween_property(_summary, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_summary() -> void:
	_summary.visible = false


func summary_visible() -> bool:
	return _summary.visible


# —— 日志、宣告、气泡 ——

func log_event(text: String, color := UiTheme.PARCHMENT) -> void:
	var label := UiTheme.label(text, 15, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(270, 0)
	_log_box.add_child(label)
	label.modulate.a = 0.0
	if is_inside_tree():
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
	if not is_inside_tree():
		return
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
	clear_my_bubble()
	var bubble := SpeechBubble.new(text, color, duration)
	_bubble_anchor.add_child(bubble)
	bubble.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE,
		int(SpeechBubble.TAIL_LENGTH + MY_BUBBLE_GAP))
	bubble.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bubble.grow_vertical = Control.GROW_DIRECTION_BEGIN
