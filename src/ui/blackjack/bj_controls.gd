class_name BjControls
extends PanelContainer
# 21 点底部中间的控件(≤ 600×170):第一行回合横幅 + 倒计时环;下注时一行预设与 −/+、一行「下注 X」「同上局」「这局不玩」;
# 轮到自己决策时一行 要牌 / 停牌 / 加倍 / 分牌 / 投降(不能做的变灰);最后一行快捷键提示。
# 只发信号,不直接调用 Net / Sfx;快捷键由牌桌的 _unhandled_input 转给 handle_key。所有控件 FOCUS_NONE。
# 不展开时(别人在决策、自己已下注等别人)只留横幅那一行。


signal bet_chosen(amount: int)
signal skip_chosen
signal action_chosen(kind: String)

const MAX_SIZE := Vector2(600, 170)
const MODE_HIDDEN := "hidden"     # 只留横幅
const MODE_BET := "bet"
const MODE_PLAY := "play"
const PRESETS := [20, 100, 200, 500, 1000]
const BUTTON_HEIGHT := 46.0
const BUTTON_FONT := 19
const BUTTON_PADDING := Vector2(14, 4)
const PRESET_FONT := 14
const PRESET_PADDING := Vector2(8, 3)
const HINT_FONT := 13
const ROW_GAP := 4
const PANEL_PADDING := Vector2(10, 6)
const DEFAULT_BET := 100
const BET_HINT := "回车 下注 · ↑↓ 加减 %d · 1–5 预设 · R 同上局 · N 这局不玩" % BjRules.BET_UNIT
const PLAY_HINT := "空格/1 要牌 · 回车/2 停牌 · 3 加倍 · 4 分牌 · 5 投降"
const PLAY_KEYS := {
	KEY_SPACE: BjRules.HIT, KEY_1: BjRules.HIT, KEY_KP_1: BjRules.HIT,
	KEY_ENTER: BjRules.STAND, KEY_KP_ENTER: BjRules.STAND, KEY_2: BjRules.STAND, KEY_KP_2: BjRules.STAND,
	KEY_3: BjRules.DOUBLE, KEY_KP_3: BjRules.DOUBLE, KEY_4: BjRules.SPLIT, KEY_KP_4: BjRules.SPLIT,
	KEY_5: BjRules.SURRENDER, KEY_KP_5: BjRules.SURRENDER,
}
const ACTION_ORDER := [BjRules.HIT, BjRules.STAND, BjRules.DOUBLE, BjRules.SPLIT, BjRules.SURRENDER]

var _mode := MODE_HIDDEN
var _stack := 0
var _amount := DEFAULT_BET
var _last_bet := 0
var _legal := {}
var _turn_mine := false
var _bet_round := -1   # 上一次展开下注控件是第几局:同一局里收起又展开时保留调好的金额
var _turn_panel: PanelContainer
var _turn_label: Label
var _ring: CountdownRing
var _bet_box: VBoxContainer
var _preset_buttons: Array = []
var _amount_label: Label
var _bet_button: Button
var _repeat_button: Button
var _skip_button: Button
var _play_row: HBoxContainer
var _action_buttons := {}
var _hint: Label


# —— 纯逻辑 ——

static func clamp_bet(value: int, stack: int) -> int:
	# 下注额:BET_UNIT 的倍数,夹在最小下注与 min(上限, 筹码) 之间(筹码不够最小下注时返回 0)
	var high := mini(BjRules.MAX_BET, stack - stack % BjRules.BET_UNIT)
	if high < BjRules.MIN_BET:
		return 0
	var stepped := int(roundf(float(value) / BjRules.BET_UNIT)) * BjRules.BET_UNIT
	return clampi(stepped, BjRules.MIN_BET, high)


static func play_hotkey(keycode: int) -> String:
	return PLAY_KEYS.get(keycode, "")


static func bet_hotkey(keycode: int) -> Dictionary:
	match keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			return {"kind": "bet"}
		KEY_UP:
			return {"kind": "step", "delta": 1}
		KEY_DOWN:
			return {"kind": "step", "delta": -1}
		KEY_R:
			return {"kind": "repeat"}
		KEY_N:
			return {"kind": "skip"}
	if keycode >= KEY_1 and keycode <= KEY_5:
		return {"kind": "preset", "index": keycode - KEY_1}
	return {}


# —— 构建 ——

func _ready() -> void:
	var style := UiTheme.panel_box(UiTheme.PANEL_SOFT, Color(UiTheme.BRASS, 0.5), 1, 12)
	style.content_margin_left = PANEL_PADDING.x
	style.content_margin_right = PANEL_PADDING.x
	style.content_margin_top = PANEL_PADDING.y
	style.content_margin_bottom = PANEL_PADDING.y
	add_theme_stylebox_override("panel", style)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ROW_GAP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	box.add_child(_build_turn_row())
	_bet_box = VBoxContainer.new()
	_bet_box.add_theme_constant_override("separation", ROW_GAP)
	_bet_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_bet_box)
	_bet_box.add_child(_build_amount_row())
	_bet_box.add_child(_build_bet_buttons())
	_play_row = _row(10)
	box.add_child(_play_row)
	for kind in ACTION_ORDER:
		var button := _big_button(BjRules.ACTION_NAMES[kind], kind == BjRules.HIT or kind == BjRules.STAND)
		button.pressed.connect(func(): action_chosen.emit(kind))
		_play_row.add_child(button)
		_action_buttons[kind] = button
	_hint = UiTheme.label("", HINT_FONT, UiTheme.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)
	set_mode(MODE_HIDDEN)


func _build_turn_row() -> HBoxContainer:
	var row := _row(10)
	_turn_panel = PanelContainer.new()
	var style := UiTheme.panel_box(UiTheme.PANEL, Color(UiTheme.BRASS, 0.6), 1, 22)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	style.content_margin_left = 14
	style.content_margin_right = 14
	_turn_panel.add_theme_stylebox_override("panel", style)
	_turn_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_panel.resized.connect(func(): _turn_panel.pivot_offset = _turn_panel.size / 2.0)
	row.add_child(_turn_panel)
	_turn_label = UiTheme.label("", 20, UiTheme.PARCHMENT, UiTheme.display_font())
	_turn_panel.add_child(_turn_label)
	_ring = CountdownRing.new()
	row.add_child(_ring)
	_turn_panel.visible = false
	_ring.visible = false
	return row


func _build_amount_row() -> HBoxContainer:
	var row := _row(4)
	var minus := _small_button("−")
	minus.pressed.connect(func(): set_amount(_amount - BjRules.BET_UNIT))
	row.add_child(minus)
	_preset_buttons.append(minus)
	_amount_label = UiTheme.label("", 22, UiTheme.BRASS_BRIGHT, UiTheme.display_font())
	_amount_label.custom_minimum_size = Vector2(76, 0)
	_amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_amount_label)
	var plus := _small_button("+")
	plus.pressed.connect(func(): set_amount(_amount + BjRules.BET_UNIT))
	row.add_child(plus)
	_preset_buttons.append(plus)
	row.add_child(_spacer(10))
	for value in PRESETS:
		var preset := _small_button(ChipText.format(value))
		preset.pressed.connect(func(): set_amount(value))
		row.add_child(preset)
		_preset_buttons.append(preset)
	return row


func _build_bet_buttons() -> HBoxContainer:
	var row := _row(10)
	_bet_button = _big_button("下注", true)
	_bet_button.pressed.connect(_submit_bet)
	row.add_child(_bet_button)
	_repeat_button = _big_button("同上局", false)
	_repeat_button.pressed.connect(_repeat)
	row.add_child(_repeat_button)
	_skip_button = _big_button("这局不玩", false)
	_skip_button.pressed.connect(func(): skip_chosen.emit())
	row.add_child(_skip_button)
	return row


func _row(separation: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", separation)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row


func _spacer(width: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(width, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _big_button(text: String, primary: bool) -> Button:
	var button := UiTheme.button(text, primary)
	button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	button.add_theme_font_size_override("font_size", BUTTON_FONT)
	button.focus_mode = Control.FOCUS_NONE
	_shrink_padding(button, BUTTON_PADDING)
	return button


func _small_button(text: String) -> Button:
	var button := UiTheme.button(text)
	button.add_theme_font_size_override("font_size", PRESET_FONT)
	button.focus_mode = Control.FOCUS_NONE
	_shrink_padding(button, PRESET_PADDING)
	return button


func _shrink_padding(button: Button, padding: Vector2) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box: StyleBoxFlat = button.get_theme_stylebox(state).duplicate()
		box.content_margin_left = padding.x
		box.content_margin_right = padding.x
		box.content_margin_top = padding.y
		box.content_margin_bottom = padding.y
		box.shadow_size = 0
		button.add_theme_stylebox_override(state, box)


# —— 更新 ——

func set_mode(mode: String) -> void:
	_mode = mode
	_bet_box.visible = mode == MODE_BET
	_play_row.visible = mode == MODE_PLAY
	_hint.visible = mode != MODE_HIDDEN
	_hint.text = BET_HINT if mode == MODE_BET else PLAY_HINT


func mode() -> String:
	return _mode


func show_betting(stack: int, last_bet: int, round_number := -1) -> void:
	# 下注阶段轮到自己:新的一局金额从上一局的注(没有就 100)开始,夹到筹码以内;同一局里再展开保留已调好的金额;
	# 同上局只在上一局下过注时可点
	var fresh := round_number != _bet_round or (round_number < 0 and _mode != MODE_BET)
	_bet_round = round_number
	_stack = stack
	_last_bet = last_bet
	set_mode(MODE_BET)
	if fresh:
		set_amount(last_bet if last_bet > 0 else DEFAULT_BET)
	else:
		set_amount(_amount)
	var repeat := clamp_bet(last_bet, stack)
	_repeat_button.disabled = last_bet <= 0 or repeat != last_bet
	_repeat_button.text = "同上局 %s" % ChipText.format(last_bet) if last_bet > 0 else "同上局"


func show_play(legal: Dictionary) -> void:
	_legal = legal
	set_mode(MODE_PLAY)
	for kind in _action_buttons:
		(_action_buttons[kind] as Button).disabled = not legal.get(kind, false)


func set_amount(value: int) -> void:
	_amount = clamp_bet(value, _stack)
	_amount_label.text = ChipText.format(_amount)
	_bet_button.text = "下注 %s" % ChipText.format(_amount) if _amount > 0 else "下注"
	_bet_button.disabled = _amount <= 0


func amount() -> int:
	return _amount


func set_turn(text: String, mine: bool) -> void:
	# 同样的横幅不重设:牌桌每次刷新都会调,轮到自己时的弹一下只在文字变了时播
	if text == _turn_label.text and mine == _turn_mine and _turn_panel.visible == (text != ""):
		return
	_turn_mine = mine
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


func set_countdown(remaining: float, total: float) -> void:
	_ring.visible = true
	_ring.set_time(remaining, total)


func hide_countdown() -> void:
	_ring.visible = false


func action_button(kind: String) -> Button:
	return _action_buttons.get(kind)


# —— 输入 ——

func handle_key(keycode: int) -> bool:
	# 牌桌在没有说明书 / 确认框时把按键转到这里;返回真表示已处理
	if _mode == MODE_PLAY:
		var kind := play_hotkey(keycode)
		if kind == "" or not _legal.get(kind, false):
			return false
		action_chosen.emit(kind)
		return true
	if _mode != MODE_BET:
		return false
	var key := bet_hotkey(keycode)
	match key.get("kind", ""):
		"bet":
			_submit_bet()
		"step":
			set_amount(_amount + key["delta"] * BjRules.BET_UNIT)
		"preset":
			set_amount(PRESETS[key["index"]])
		"repeat":
			if _repeat_button.disabled:
				return false
			_repeat()
		"skip":
			skip_chosen.emit()
		_:
			return false
	return true


func _submit_bet() -> void:
	if _amount > 0:
		bet_chosen.emit(_amount)


func _repeat() -> void:
	if _last_bet > 0:
		set_amount(_last_bet)
		bet_chosen.emit(_amount)
