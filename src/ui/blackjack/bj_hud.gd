class_name BjHud
extends Control
# 21 点牌桌 HUD(按 1280×720 的布局预算,结构同德州 HUD):
# 左上 ≤ 380 宽(「21 点 · 第 N 局 · 下注 20–1,000」、牌鞋余量;庄家的点数与 2D 牌条)、右上房主的「散局」「对话」「规则」;
# 底部中间:下注 / 决策控件(BjControls)或座位提示(输光「再领」、离座「回到牌桌」、中途加入「下一局入座」);
# 左下 ≤ 300 宽(自己的名字、筹码、盈亏、领取次数;自己的每一手:2D 牌条 + 点数与结果);右下事件日志;画面中部大字宣告。
# 只发信号,不直接调用 Net / Sfx;所有按钮 FOCUS_NONE。界面文字里不出现花色符号。


signal rules_pressed
signal quip_pressed
signal end_pressed
signal rebuy_pressed
signal sit_in_pressed

const MARGIN := Vector2(24, 20)
const DEALER_CARD := Vector2(40, 56)
const HAND_CARD := Vector2(40, 56)
const HEADER_FONT := 14
const LOG_WIDTH := 300.0
const LOG_LINES := 6
const ANNOUNCE_Y := -90.0
const ENDING_TEXT := "本局结束后散局"
const END_TEXT := "散局"
const MY_BUBBLE_GAP := 4.0
const PROMPTS := {
	BjScreenState.BOTTOM_BUSTED: ["你的筹码不够最小下注了", "再领 2,000"],
	BjScreenState.BOTTOM_AWAY: ["你已离座(连续超时)", "回到牌桌"],
	BjScreenState.BOTTOM_JOINING: ["已入座,下一局开始下注", ""],
}
const HAND_COLORS := {
	BjRules.OUTCOME_BLACKJACK: UiTheme.BRASS_BRIGHT, BjRules.OUTCOME_WIN: UiTheme.TRUTH,
	BjRules.OUTCOME_LOSE: UiTheme.LIE, BjRules.OUTCOME_BUST: UiTheme.LIE, BjRules.OUTCOME_SURRENDER: UiTheme.MUTED,
}

var header_panel: PanelContainer
var dealer_strip: CardStrip
var end_button: Button
var controls: BjControls
var prompt_panel: PanelContainer
var my_panel: PanelContainer
var log_box: VBoxContainer
var hand_box: VBoxContainer

var _bottom := BjScreenState.BOTTOM_NONE
var _title: Label
var _shoe_label: Label
var _dealer_label: Label
var _prompt_label: Label
var _prompt_button: Button
var _my_name: Label
var _my_status: Label
var _announce_box: VBoxContainer
var _announce: Label
var _announce_sub: Label
var _announce_tween: Tween = null
var _my_bubble: SpeechBubble = null


# —— 纯逻辑 ——

static func title_text(round_number: int) -> String:
	var round_text := "第 %d 局" % round_number if round_number > 0 else "等待开局"
	return "%s · %s · 下注 %s–%s" % [GameMode.short_label(GameMode.BLACKJACK), round_text,
		ChipText.format(BjRules.MIN_BET), ChipText.format(BjRules.MAX_BET)]


static func shoe_text(left: Variant, size: Variant) -> String:
	if not left is int or not size is int or size <= 0:
		return ""
	return "牌鞋剩 %d / %d 张" % [left, size]


static func my_status_text(row: Dictionary) -> String:
	return "筹码 %s · 盈亏 %s · 领取 %d 次" % [ChipText.format(_int(row, "stack")), ChipText.signed(_int(row, "net")),
		maxi(_int(row, "buyins"), 1)]


static func _int(d: Dictionary, key: String) -> int:
	return d[key] if d.get(key) is int else 0


# —— 构建 ——

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_header()
	_build_top_right()
	_build_bottom()
	_build_my_panel()
	_build_log()
	_build_announce()
	set_bottom(BjScreenState.BOTTOM_NONE)


func _build_header() -> void:
	header_panel = _corner_panel(Control.PRESET_TOP_LEFT, MARGIN)
	header_panel.add_to_group(WorldLabels.KEEP_OUT_GROUP)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	header_panel.add_child(box)
	_title = UiTheme.label(title_text(0), HEADER_FONT, UiTheme.PARCHMENT_DIM)
	box.add_child(_title)
	_shoe_label = UiTheme.label("", HEADER_FONT - 1, UiTheme.MUTED)
	box.add_child(_shoe_label)
	_dealer_label = UiTheme.label("庄家", HEADER_FONT + 3, UiTheme.BRASS_BRIGHT, UiTheme.display_font())
	box.add_child(_dealer_label)
	dealer_strip = CardStrip.new(0, DEALER_CARD)
	box.add_child(dealer_strip)


func _build_top_right() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(MARGIN.x))
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


func _build_bottom() -> void:
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y -= 22.0
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	controls = BjControls.new()
	bottom.add_child(controls)
	prompt_panel = PanelContainer.new()
	var style := UiTheme.panel_box(UiTheme.PANEL_SOFT, Color(UiTheme.BRASS, 0.5), 1, 12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	prompt_panel.add_theme_stylebox_override("panel", style)
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(prompt_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_panel.add_child(row)
	_prompt_label = UiTheme.label("", 20, UiTheme.PARCHMENT, UiTheme.display_font())
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_prompt_label)
	_prompt_button = UiTheme.button("", true)
	_prompt_button.add_theme_font_size_override("font_size", 19)
	_prompt_button.focus_mode = Control.FOCUS_NONE
	_prompt_button.pressed.connect(_on_prompt_button)
	row.add_child(_prompt_button)


func _build_my_panel() -> void:
	my_panel = _corner_panel(Control.PRESET_BOTTOM_LEFT, Vector2(MARGIN.x, -MARGIN.y))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	my_panel.add_child(box)
	_my_name = UiTheme.label("", 18, UiTheme.PARCHMENT, UiTheme.display_font())
	_my_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_my_name)
	_my_status = UiTheme.label("", 14, UiTheme.PARCHMENT_DIM)
	box.add_child(_my_status)
	hand_box = VBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 4)
	box.add_child(hand_box)


func _build_log() -> void:
	log_box = VBoxContainer.new()
	log_box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	log_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	log_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	log_box.position += Vector2(-MARGIN.x, -MARGIN.y)
	log_box.custom_minimum_size = Vector2(LOG_WIDTH, 0)
	log_box.alignment = BoxContainer.ALIGNMENT_END
	log_box.add_theme_constant_override("separation", 4)
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(log_box)


func _build_announce() -> void:
	_announce_box = VBoxContainer.new()
	_announce_box.anchor_left = 0.0
	_announce_box.anchor_right = 1.0
	_announce_box.anchor_top = 0.5
	_announce_box.anchor_bottom = 0.5
	_announce_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_announce_box.offset_top = ANNOUNCE_Y
	_announce_box.offset_bottom = ANNOUNCE_Y
	_announce_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_announce_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_announce_box.resized.connect(func(): _announce_box.pivot_offset = _announce_box.size / 2.0)
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


func _corner_panel(preset: int, offset: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UiTheme.panel_box(UiTheme.PANEL_SOFT, Color(UiTheme.BRASS, 0.5), 1, 12)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(preset)
	if preset == Control.PRESET_BOTTOM_LEFT:
		panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.position += offset
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	return panel


# —— 更新 ——

func set_header(round_number: int, shoe_left: Variant, shoe_size: Variant) -> void:
	_title.text = title_text(round_number)
	_shoe_label.text = shoe_text(shoe_left, shoe_size)
	_shoe_label.visible = _shoe_label.text != ""


func set_dealer(label: String, cards: Array) -> void:
	_dealer_label.text = label
	dealer_strip.set_cards(cards)


func set_host(is_host: bool) -> void:
	end_button.visible = is_host


func set_ending(ending: bool) -> void:
	end_button.disabled = ending
	end_button.text = ENDING_TEXT if ending else END_TEXT


func set_bottom(mode: String) -> void:
	# 底部中间:座位提示与控件互斥;控件的展开方式(下注 / 决策 / 只留横幅)由牌桌另外设
	_bottom = mode
	prompt_panel.visible = PROMPTS.has(mode)
	controls.visible = not prompt_panel.visible and mode != BjScreenState.BOTTOM_NONE
	if prompt_panel.visible:
		_prompt_label.text = PROMPTS[mode][0]
		_prompt_button.text = PROMPTS[mode][1]
		_prompt_button.visible = PROMPTS[mode][1] != ""


func bottom() -> String:
	return _bottom


func _on_prompt_button() -> void:
	if _bottom == BjScreenState.BOTTOM_BUSTED:
		rebuy_pressed.emit()
	elif _bottom == BjScreenState.BOTTOM_AWAY:
		sit_in_pressed.emit()


func set_my_status(display_name: String, row: Dictionary) -> void:
	_my_name.text = display_name + "(你)"
	_my_status.text = my_status_text(row)


func set_my_hands(hands: Array, current_hand: int) -> void:
	# 自己的每一手:2D 牌条 + 「点数 · 注 X」或结果;正在决策的那一手标「▶」
	for child in hand_box.get_children():
		hand_box.remove_child(child)
		child.queue_free()
	for i in hands.size():
		var hand: Dictionary = hands[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		hand_box.add_child(row)
		var strip := CardStrip.new(0, HAND_CARD)
		row.add_child(strip)
		strip.set_cards(hand.get("cards", []))
		var text := BjScreenState.hand_label(hand)
		if Untrusted.same(hand.get("outcome", ""), ""):
			text += " · 注 %s" % ChipText.format(hand.get("bet", 0))
		var color: Color = HAND_COLORS.get(hand.get("outcome", ""), UiTheme.PARCHMENT)
		var label := UiTheme.label(("▶ " if i == current_hand else "") + text, 15, color)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)


func preview_candidates() -> Array:
	var out := dealer_strip.preview_candidates(_screen_rect(header_panel))
	var mine := _screen_rect(my_panel)
	for row in hand_box.get_children():
		for child in row.get_children():
			if child is CardStrip:
				out.append_array(child.preview_candidates(mine))
	return out


static func _screen_rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func my_bubble(text: String, duration := Quips.BUBBLE_SECONDS) -> void:
	if is_instance_valid(_my_bubble):
		_my_bubble.queue_free()
	_my_bubble = SpeechBubble.new(text, UiTheme.INK, duration)
	add_child(_my_bubble)
	var bubble := _my_bubble
	var place := func() -> void:
		if is_instance_valid(bubble):
			bubble.position = Vector2(maxf(MARGIN.x, my_panel.position.x + (my_panel.size.x - bubble.size.x) / 2.0),
				my_panel.position.y - bubble.size.y - SpeechBubble.TAIL_LENGTH - MY_BUBBLE_GAP)
	_my_bubble.resized.connect(place)
	place.call()


func log_event(text: String, color := UiTheme.PARCHMENT) -> void:
	var label := UiTheme.label(text, 15, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(LOG_WIDTH, 0)
	log_box.add_child(label)
	label.modulate.a = 0.0
	create_tween().tween_property(label, "modulate:a", 1.0, 0.25)
	while log_box.get_child_count() > LOG_LINES:
		var oldest := log_box.get_child(0)
		log_box.remove_child(oldest)
		oldest.queue_free()
	for i in log_box.get_child_count():
		var child: Control = log_box.get_child(i)
		child.self_modulate.a = lerpf(0.35, 1.0, float(i + 1) / log_box.get_child_count())


func announce(text: String, color: Color, sub := "", hold := 1.0) -> void:
	if _announce_tween != null and _announce_tween.is_valid():
		_announce_tween.kill()
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
