class_name PokerHud
extends Control
# 德州牌桌 HUD(规格 §6.1,按 1280×720 的布局预算):
# 左上 ≤ 380×108(玩法 · 盲注 · 第 N 手;底池合计与边池摘要;5 张公共牌的 2D 牌条)、右上「规则」与房主的「散局」、
# 底部中间 ≤ 600×170(轮到自己时的下注控件 / 输光、观战、等待、离座的提示)、右侧摊牌面板(亮牌到下一手开始)、
# 左下 ≤ 300 宽(自己的名字、筹码、盈亏、领取次数;两张手牌的 2D 大图 + 当前最大牌型)、右下事件日志、画面中部大字宣告。
# 只发信号,不直接调用 Net / Sfx;所有按钮 FOCUS_NONE(焦点会吃掉空格/回车)。界面文字里不出现花色符号。


signal rules_pressed
signal quip_pressed
signal end_pressed
signal rebuy_pressed
signal spectate_pressed
signal sit_in_pressed
signal next_pressed
signal history_pressed
signal action_chosen(action: String, amount: int)
signal fold_confirm_requested

const MARGIN := Vector2(24, 20)
const TOP_LEFT_MAX := Vector2(380, 108)
const TOP_LEFT_BOTTOM := 128.0
const BOTTOM_MAX := BetControls.MAX_SIZE
const BOTTOM_LEFT := 340.0
const BOTTOM_RIGHT := 940.0
const BOTTOM_TOP_MIN := 528.0
const BOTTOM_OFFSET := 22.0          # 底部中间区域离画面底边
const LEFT_RIGHT_EDGE := 324.0       # 左下栏右缘
const LOG_LEFT_EDGE := 956.0         # 日志左缘
const LOG_WIDTH := 300.0
const LOG_LINES := 6
const BOARD_CARD := Vector2(36, 50)
const HOLE_CARD := Vector2(54, 76)
const HEADER_FONT := 14
const ANNOUNCE_Y := -90.0
const ENDING_TEXT := "本手结束后散局"
const END_TEXT := "散局"
const WAITING_TEXT := "等待开局"
const MY_BUBBLE_GAP := 4.0           # 自己气泡的小三角尖与左下栏之间的留白

const BOTTOM_NONE := "none"
const BOTTOM_BET := "bet"
const BOTTOM_BUST := PokerPrompts.BUST
const BOTTOM_SPECTATE := PokerPrompts.SPECTATE
const BOTTOM_WAITING := PokerPrompts.WAITING
const BOTTOM_AWAY := PokerPrompts.AWAY
const BOTTOM_NEXT := PokerPrompts.NEXT
const BOTTOM_NEXT_WAIT := PokerPrompts.NEXT_WAIT
const STATUS_MODES := {
	PokerRules.STATUS_BUSTED: BOTTOM_BUST,
	PokerRules.STATUS_SPECTATING: BOTTOM_SPECTATE,
	PokerRules.STATUS_AWAY: BOTTOM_AWAY,
	PokerRules.STATUS_WAITING: BOTTOM_WAITING,
}

var header_panel: PanelContainer
var board_strip: CardStrip
var rules_button: Button
var end_button: Button
var bottom_box: VBoxContainer
var controls: BetControls
var showdown: ShowdownPanel
var prompts: PokerPrompts
var my_panel: PanelContainer
var my_strip: CardStrip
var log_box: VBoxContainer

var _bottom_mode := BOTTOM_NONE
var _title: Label
var _pot_label: Label
var _my_name: Label
var _my_status: Label
var _best_label: Label
var _announce_box: VBoxContainer
var _announce: Label
var _announce_sub: Label
var _announce_tween: Tween = null
var _my_bubble: SpeechBubble = null


# —— 纯逻辑 ——

static func title_text(mode: String, blinds: Array, hand: int) -> String:
	var sb: Variant = blinds[0] if blinds.size() > 0 else PokerRules.SMALL_BLIND
	var bb: Variant = blinds[1] if blinds.size() > 1 else PokerRules.BIG_BLIND
	var hand_text := "第 %d 手" % hand if hand > 0 else WAITING_TEXT
	return "%s · 盲注 %s/%s · %s" % [GameMode.short_label(mode), sb, bb, hand_text]


static func pot_summary(pots: Variant) -> String:
	# 「底池 3,240 · 边池 ×2」:合计所有底池;边池数 = 底池数 − 1
	var total := 0
	var count := 0
	if pots is Array:
		for pot in pots:
			if pot is Dictionary and pot.get("amount") is int:
				total += maxi(pot["amount"], 0)
				count += 1
	var text := "底池 %s" % ChipText.format(total)
	return text + (" · 边池 ×%d" % (count - 1) if count > 1 else "")


static func my_status_text(player: Dictionary) -> String:
	return "筹码 %s · 盈亏 %s · 领取 %d 次" % [ChipText.format(_int(player, "stack")), ChipText.signed(_int(player, "net")), _int(player, "buyins")]


static func bottom_mode_for(player: Dictionary, between_hands := false) -> String:
	# 按 status 的座位提示(输光 / 观战 / 离座 / 等待下一手);两手之间要接着打的人是「开始下一手」(点过了是等别人);
	# 否则下注控件(含旁人回合的横幅)。摊牌在右侧面板,不占底部
	if player.is_empty():
		return BOTTOM_NONE
	var status: Variant = player.get("status")
	if between_hands and not [PokerRules.STATUS_BUSTED, PokerRules.STATUS_SPECTATING, PokerRules.STATUS_AWAY].has(status):
		return BOTTOM_NEXT_WAIT if player.get("confirmed") == true else BOTTOM_NEXT
	return STATUS_MODES.get(status, BOTTOM_BET)


static func _int(player: Dictionary, key: String) -> int:
	var value: Variant = player.get(key, 0)
	return value if value is int else 0


# —— 构建 ——

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_header()
	_build_top_right()
	_build_bottom()
	showdown = ShowdownPanel.new()
	showdown.add_to_group(WorldLabels.KEEP_OUT_GROUP)
	add_child(showdown)
	_build_my_panel()
	_build_log()
	_build_announce()
	set_bottom_mode(BOTTOM_NONE)


func _build_header() -> void:
	header_panel = _corner_panel(Control.PRESET_TOP_LEFT, MARGIN)
	header_panel.add_to_group(WorldLabels.KEEP_OUT_GROUP)   # 对话气泡让开底池与公共牌
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	header_panel.add_child(box)
	_title = UiTheme.label(title_text(GameMode.HOLDEM, [], 0), HEADER_FONT, UiTheme.PARCHMENT_DIM)
	box.add_child(_title)
	_pot_label = UiTheme.label(pot_summary([]), HEADER_FONT + 1, UiTheme.BRASS_BRIGHT, UiTheme.display_font())
	box.add_child(_pot_label)
	board_strip = CardStrip.new(PokerRules.BOARD_CARDS, BOARD_CARD)
	box.add_child(board_strip)


func _build_top_right() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(MARGIN.x))
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.add_to_group(WorldLabels.KEEP_OUT_GROUP)
	end_button = UiTheme.button(END_TEXT)
	end_button.add_theme_font_size_override("font_size", 15)
	end_button.focus_mode = Control.FOCUS_NONE
	end_button.visible = false
	end_button.pressed.connect(func(): end_pressed.emit())
	row.add_child(end_button)
	row.add_child(_top_button("记录 · %s" % OS.get_keycode_string(HandHistoryPanel.HOTKEY), history_pressed))
	row.add_child(_top_button("对话 · %s" % OS.get_keycode_string(Quips.TOGGLE_KEY), quip_pressed))
	rules_button = UiTheme.button("规则 · %s" % OS.get_keycode_string(RulebookContent.HOTKEY))
	rules_button.add_theme_font_size_override("font_size", 15)
	rules_button.focus_mode = Control.FOCUS_NONE
	rules_button.pressed.connect(func(): rules_pressed.emit())
	row.add_child(rules_button)


func _top_button(text: String, sig: Signal) -> Button:
	var button := UiTheme.button(text)
	button.add_theme_font_size_override("font_size", 15)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func(): sig.emit())
	return button


func _build_bottom() -> void:
	# 底部中间:居中、贴底向上长;里面同一时间只显示一种内容
	bottom_box = VBoxContainer.new()
	bottom_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_box.position.y -= BOTTOM_OFFSET
	bottom_box.alignment = BoxContainer.ALIGNMENT_END
	bottom_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_box)
	controls = BetControls.new()
	controls.action_chosen.connect(func(action: String, amount: int): action_chosen.emit(action, amount))
	controls.fold_confirm_requested.connect(func(): fold_confirm_requested.emit())
	bottom_box.add_child(controls)
	prompts = PokerPrompts.new()
	prompts.rebuy_pressed.connect(func(): rebuy_pressed.emit())
	prompts.spectate_pressed.connect(func(): spectate_pressed.emit())
	prompts.sit_in_pressed.connect(func(): sit_in_pressed.emit())
	prompts.next_pressed.connect(func(): next_pressed.emit())
	bottom_box.add_child(prompts)


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
	my_strip = CardStrip.new(PokerRules.HOLE_CARDS, HOLE_CARD)
	box.add_child(my_strip)
	_best_label = UiTheme.label("", 15, UiTheme.BRASS_BRIGHT)
	box.add_child(_best_label)


func _build_log() -> void:
	# 右下角:越肩镜头下那里只有地板与椅腿
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

func preview_candidates() -> Array:
	# 悬停大图的 2D 候选:左上公共牌条、左下自己的两张、右侧摊牌面板里每人亮的牌;大图让开牌所在的整块面板
	var out := board_strip.preview_candidates(_screen_rect(header_panel))
	out.append_array(my_strip.preview_candidates(_screen_rect(my_panel)))
	var showdown_rect := _screen_rect(showdown)
	for strip: CardStrip in showdown.strips():
		out.append_array(strip.preview_candidates(showdown_rect))
	return out


static func _screen_rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)


func set_header(mode: String, blinds: Array, hand: int) -> void:
	_title.text = title_text(mode, blinds, hand)


func set_pots(pots: Variant) -> void:
	_pot_label.text = pot_summary(pots)


func set_board(cards: Variant) -> void:
	board_strip.set_cards(cards)


func set_host(is_host: bool) -> void:
	end_button.visible = is_host


func set_ending(ending: bool) -> void:
	# 请求散局后变灰:本手结束后结算
	end_button.disabled = ending
	end_button.text = ENDING_TEXT if ending else END_TEXT


func set_bottom_mode(mode: String) -> void:
	_bottom_mode = mode
	controls.visible = mode == BOTTOM_BET
	prompts.visible = PokerPrompts.MESSAGES.has(mode)
	if prompts.visible:
		prompts.show_mode(mode)


func bottom_mode() -> String:
	return _bottom_mode


func set_showdown(entries: Variant) -> void:
	# 有人亮牌时显示,传空收起
	showdown.set_entries(entries)


func set_bust_countdown(remaining: float, total: float) -> void:
	# 输光 / 开始下一手:距下一手自动开始的倒计时
	prompts.set_countdown(remaining, total)


func set_next_progress(confirmed: int, needed: int) -> void:
	prompts.set_progress(confirmed, needed)


func set_turn(text: String, mine: bool) -> void:
	controls.set_turn(text, mine)


func set_countdown(remaining: float, total: float, show: bool) -> void:
	if show:
		controls.set_countdown(remaining, total)
	else:
		controls.hide_countdown()


func set_my_status(display_name: String, player: Dictionary) -> void:
	_my_name.text = display_name + "(你)"
	_my_status.text = my_status_text(player)


func set_my_hole(cards: Variant) -> void:
	my_strip.set_cards(cards)


func set_my_best(detail: String) -> void:
	_best_label.text = detail


func my_bubble(text: String, duration := Quips.BUBBLE_SECONDS) -> void:
	# 自己说的快捷对话:越肩镜头下自己头顶在画面外,弹在左下自己那一栏的正上方;新的一句顶掉旧的
	if is_instance_valid(_my_bubble):
		_my_bubble.queue_free()
	_my_bubble = SpeechBubble.new(text, UiTheme.INK, duration)
	add_child(_my_bubble)
	var bubble := _my_bubble
	var place := func() -> void:
		if is_instance_valid(bubble):
			# 长句比左下栏宽:居中后左边出画,所以贴住左边距
			bubble.position = Vector2(maxf(MARGIN.x, my_panel.position.x + (my_panel.size.x - bubble.size.x) / 2.0),
				my_panel.position.y - bubble.size.y - SpeechBubble.TAIL_LENGTH - MY_BUBBLE_GAP)
	_my_bubble.resized.connect(place)
	place.call()


func handle_cancel() -> bool:
	# Esc:输光提示打开时选观战(规格 §6.4);其余情况交给牌桌(离开确认)
	if _bottom_mode != BOTTOM_BUST:
		return false
	spectate_pressed.emit()
	return true


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


func hide_announce(duration := 0.15) -> void:
	if _announce_tween != null and _announce_tween.is_valid():
		_announce_tween.kill()
	_announce_tween = create_tween()
	_announce_tween.tween_property(_announce_box, "modulate:a", 0.0, duration)
