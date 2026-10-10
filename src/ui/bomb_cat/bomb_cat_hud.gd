class_name BombCatHud
extends Control
# 炸弹猫牌桌 HUD(规格 §3.2):
# - 左上:玩法名、牌堆剩余张数、场上剩余炸弹(小炸弹图标:亮的还在牌堆里,灰的已炸)、当前玩家与他还要走几回合、自己的状态;
# - 右上:「规则」按钮;右下:事件日志;画面中部:大字宣告;
# - 底部(自下而上):快捷键提示 / 自己的 2D 手牌条 / 「出牌」「摸牌」按钮 / 选目标、点名、塞回滑块、给牌提示这几种临时面板 /
#   反应窗口条(谁打出了什么、倒计时条、大「不行!」按钮)/ 回合横幅与环形倒计时 / 自己的对话气泡;
# - 偷看:画面上方居中一块浮层,三张牌从上到下排好,「知道了」或点一下收起;
# - 出局后底部换成「观战中」的横幅(仍能丢番茄、说快捷语)。
# 只发信号,不直接调用 Net / Sfx;按钮都 FOCUS_NONE(焦点会吃掉空格 / 回车)。


signal play_pressed
signal draw_pressed
signal nope_pressed
signal rules_pressed
signal quip_pressed
signal card_clicked(index: int)
signal card_hovered(index: int)
signal target_chosen(pid: int)
signal named_chosen(id: String)
signal prompt_cancelled
signal reinsert_confirmed(pos: int)
signal peek_dismissed

const LOG_LINES := 6
const ANNOUNCE_Y := -110.0
const ANNOUNCE_Y_LOW := 150.0
const MY_BUBBLE_GAP := 2.0
const NAMED_CARD := Vector2(52, 75)
const PEEK_CARD := Vector2(76, 110)
const BOMB_ICON := 16.0
const WINDOW_BAR := Vector2(320, 10)
const BUTTON_WIDTH := 128.0
const LOG_ABOVE_BOTTOM := 150.0   # 日志在右下、手牌行之上
const PROMPT_NONE := ""
const PROMPT_TARGET := "target"
const PROMPT_NAMED := "named"
const PROMPT_REINSERT := "reinsert"
const PROMPT_GIVE := "give"
const HINT_IDLE := "点手牌或按 1–9 选牌 · Enter 出牌 · 空格 摸牌 · N 不行! · WASD 探头 · V 视角 · T 对话 · G 番茄 · Q 快捷语 · %s 规则 · Esc 离开"
const HINT_SPECTATE := "观战中:鼠标看人 · V 视角 · T 对话 · G 丢番茄 · Q 快捷语 · %s 规则 · Esc 离开"

var strip: BombCatHandStrip
var play_button: Button
var draw_button: Button
var nope_button: Button
var prompt_kind := PROMPT_NONE
var reinsert_slider: HSlider
var window_panel: PanelContainer
var peek_panel: PanelContainer

var _deck_label: Label
var _bombs: Control
var _bombs_label: Label
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
var _prompt_holder: VBoxContainer
var _prompt_panel: PanelContainer = null
var _reinsert_label: Label
var _window_label: Label
var _window_bar: ProgressBar
var _spectate_panel: PanelContainer
var _peek_row: HBoxContainer
var _bombs_total := 0
var _bombs_left := 0
var _spectating := false
var _away := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_info()
	_build_rules_button()
	_build_bottom()
	_build_log()
	_build_announce()
	_build_peek()


# —— 纯逻辑 ——

static func turn_info_text(current_name: String, mine: bool, turns: int, step: String) -> String:
	# 左上「轮到谁」一行:被甩锅时写出还要走几回合
	if current_name == "":
		return ""
	var who := "你" if mine else current_name
	var extra := " · 还要走 %d 回合" % turns if turns > 1 else ""
	match step:
		BombCatScreenState.STEP_WINDOW:
			return "%s 出了牌,等大家反应%s" % [who, extra]
		BombCatScreenState.STEP_REINSERT:
			return "%s 正在把炸弹塞回牌堆" % who
		BombCatScreenState.STEP_GIVE:
			return "%s 在等人给牌" % who
	return "轮到 %s%s" % [who, extra]


static func reinsert_text(pos: int, max_pos: int) -> String:
	# 塞回滑块的说明:0 = 顶(下一张就是它)… max_pos = 底
	if max_pos <= 0:
		return "牌堆空了,只能放在最上面"
	if pos <= 0:
		return "放在第 1 张(最上面,下一个摸牌的人就会摸到)"
	if pos >= max_pos:
		return "放在第 %d 张(最底下)" % (max_pos + 1)
	return "放在第 %d 张" % (pos + 1)


static func window_text(window: Dictionary, names: Callable) -> String:
	# 反应窗口条上的一句话:「阿狸 打出「讨要」→ 小熊 · 已被不行 1 次」
	if window.is_empty():
		return ""
	var who: String = names.call(window.get("pid"))
	var kind := str(window.get("kind", ""))
	var what := ""
	match kind:
		BombCatState.KIND_PAIR:
			what = "两张零食"
		BombCatState.KIND_TRIPLE:
			what = "三张零食(点名「%s」)" % BombCatCard.display_name(str(window.get("named", "")))
		_:
			what = "「%s」" % BombCatCard.display_name(kind)
	var text := "%s 打出%s" % [who, what]
	if window.get("target") is int:
		text += " → %s" % names.call(window["target"])
	var nopes := int(window.get("nopes", 0)) if window.get("nopes") is int else 0
	if nopes > 0:
		text += " · 被「不行!」%d 次(%s)" % [nopes, "作废" if nopes % 2 == 1 else "又生效"]
	return text


# —— 构建 ——

func _build_info() -> void:
	var panel := PanelContainer.new()
	var style := UiTheme.panel_box(UiTheme.PANEL_SOFT, Color(UiTheme.BRASS, 0.5), 1, 12)
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(20, 16)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_to_group(WorldLabels.KEEP_OUT_GROUP)   # 对话气泡让开左上信息
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	_deck_label = UiTheme.label("牌堆 —", 24, UiTheme.BRASS_BRIGHT, UiTheme.display_font())
	row.add_child(_deck_label)
	var bomb_box := VBoxContainer.new()
	bomb_box.add_theme_constant_override("separation", 0)
	bomb_box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(bomb_box)
	_bombs_label = UiTheme.label("", 14, UiTheme.PARCHMENT_DIM)
	bomb_box.add_child(_bombs_label)
	_bombs = Control.new()
	_bombs.custom_minimum_size = Vector2(BOMB_ICON * 5.0, BOMB_ICON + 2.0)
	_bombs.draw.connect(_draw_bombs)
	bomb_box.add_child(_bombs)
	_turn_info = UiTheme.label("", 16, UiTheme.PARCHMENT, UiTheme.display_font())
	box.add_child(_turn_info)
	_my_line = UiTheme.label("", 13, UiTheme.MUTED)
	box.add_child(_my_line)


func _build_rules_button() -> void:
	# 右上:「对话 · T」「规则 · F1」(同骗子酒馆的牌桌)
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
	button.focus_mode = Control.FOCUS_NONE   # 不抢焦点:空格 / 回车照样给牌桌
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
	holder.add_child(_build_window_panel())
	_prompt_holder = VBoxContainer.new()
	_prompt_holder.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_prompt_holder)
	holder.add_child(_build_turn_row())
	# 最底下一行:「出牌」· 手牌条 ·「摸牌」并排(不叠高,越肩镜头下自己举着的 3D 牌扇露在 HUD 上方)
	_action_row = HBoxContainer.new()
	_action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_action_row.add_theme_constant_override("separation", 14)
	_action_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_action_row)
	play_button = _big_button("出牌", true, BUTTON_WIDTH)
	play_button.pressed.connect(func(): play_pressed.emit())
	play_button.size_flags_vertical = Control.SIZE_SHRINK_END
	_action_row.add_child(play_button)
	strip = BombCatHandStrip.new()
	strip.card_clicked.connect(func(i: int): card_clicked.emit(i))
	strip.card_hovered.connect(func(i: int): card_hovered.emit(i))
	_action_row.add_child(strip)
	draw_button = _big_button("摸牌", false, BUTTON_WIDTH)
	draw_button.pressed.connect(func(): draw_pressed.emit())
	draw_button.size_flags_vertical = Control.SIZE_SHRINK_END
	_action_row.add_child(draw_button)
	_spectate_panel = PanelContainer.new()
	_spectate_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(UiTheme.PANEL, Color(UiTheme.BLOOD, 0.7), 1, 16))
	_spectate_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spectate_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var spectate := UiTheme.label("你被炸飞了 · 观战中", 22, UiTheme.PARCHMENT, UiTheme.display_font())
	spectate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectate_panel.add_child(spectate)
	_spectate_panel.visible = false
	holder.add_child(_spectate_panel)
	_hint = UiTheme.label("", 14, UiTheme.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(_hint)
	set_actions(false, false, 0, false)


func _big_button(text: String, primary: bool, width: float) -> Button:
	var button := UiTheme.button(text, primary)
	button.custom_minimum_size = Vector2(width, 50)
	button.add_theme_font_size_override("font_size", 24)
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


func _build_window_panel() -> PanelContainer:
	# 反应窗口:一句话 + 倒计时条 + 大「不行!」按钮
	window_panel = PanelContainer.new()
	var style := UiTheme.panel_box(UiTheme.PANEL, Color(UiTheme.LIE, 0.75), 2, 14)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	window_panel.add_theme_stylebox_override("panel", style)
	window_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	window_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	window_panel.add_child(row)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(box)
	_window_label = UiTheme.label("", 17, UiTheme.PARCHMENT)
	box.add_child(_window_label)
	_window_bar = ProgressBar.new()
	_window_bar.custom_minimum_size = WINDOW_BAR
	_window_bar.show_percentage = false
	_window_bar.max_value = 1.0
	_window_bar.step = 0.001
	_window_bar.add_theme_stylebox_override("background", UiTheme.flat(Color(0, 0, 0, 0.5), 5))
	_window_bar.add_theme_stylebox_override("fill", UiTheme.flat(UiTheme.LIE, 5))
	box.add_child(_window_bar)
	nope_button = UiTheme.button("不行!  N", true)
	nope_button.custom_minimum_size = Vector2(150, 56)
	nope_button.add_theme_font_size_override("font_size", 26)
	nope_button.focus_mode = Control.FOCUS_NONE
	nope_button.pressed.connect(func(): nope_pressed.emit())
	row.add_child(nope_button)
	window_panel.visible = false
	return window_panel


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


func _build_peek() -> void:
	# 偷看浮层:只在本机,三张牌 + 「知道了」;点牌也能收起
	peek_panel = PanelContainer.new()
	var style := UiTheme.panel_box(Color(0.07, 0.05, 0.04, 0.92), UiTheme.BRASS_BRIGHT, 2, 16)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	peek_panel.add_theme_stylebox_override("panel", style)
	peek_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	peek_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	peek_panel.position.y = 64
	add_child(peek_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	peek_panel.add_child(box)
	var title := UiTheme.label("偷看到的牌堆顶(只有你看得到)", 18, UiTheme.BRASS_BRIGHT, UiTheme.display_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_peek_row = HBoxContainer.new()
	_peek_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_peek_row.add_theme_constant_override("separation", 14)
	box.add_child(_peek_row)
	var ok := UiTheme.button("知道了")
	ok.focus_mode = Control.FOCUS_NONE
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(func(): peek_dismissed.emit())
	box.add_child(ok)
	peek_panel.visible = false


func _center_pivot(control: Control) -> void:
	control.resized.connect(func(): control.pivot_offset = control.size / 2.0)


# —— 左上信息 ——

func set_info(deck_count: int, bombs_left: int, bombs_total: int, turn_text: String, my_text: String) -> void:
	_deck_label.text = "牌堆 %d 张" % deck_count
	_bombs_left = bombs_left
	_bombs_total = bombs_total
	_bombs_label.text = "炸弹还剩 %d / %d" % [bombs_left, bombs_total]
	_bombs.custom_minimum_size.x = maxf(BOMB_ICON * 1.2 * bombs_total, BOMB_ICON)
	_bombs.queue_redraw()
	_turn_info.text = turn_text
	_turn_info.visible = turn_text != ""
	_my_line.text = my_text


func _draw_bombs() -> void:
	# 小炸弹:亮的是还在牌堆里的,灰的是已经炸过的
	for i in _bombs_total:
		var live := i < _bombs_left
		var c := Vector2(BOMB_ICON * 0.5 + i * BOMB_ICON * 1.2, BOMB_ICON * 0.6)
		var body := Color(0.26, 0.24, 0.32) if live else Color(0.3, 0.28, 0.27, 0.5)
		_bombs.draw_circle(c, BOMB_ICON * 0.38, body)
		_bombs.draw_line(c + Vector2(BOMB_ICON * 0.2, -BOMB_ICON * 0.3), c + Vector2(BOMB_ICON * 0.36, -BOMB_ICON * 0.5),
			Color(0.8, 0.64, 0.42) if live else Color(0.5, 0.45, 0.4, 0.5), 2.0, true)
		if live:
			_bombs.draw_circle(c + Vector2(BOMB_ICON * 0.38, -BOMB_ICON * 0.52), 2.6, UiTheme.BRASS_BRIGHT)


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


func set_countdown(remaining: float, total: float, visible_ring: bool) -> void:
	_ring.visible = visible_ring
	if visible_ring:
		_ring.set_time(remaining, total)


func set_window(text: String, fraction: float, nope_enabled: bool, nope_visible: bool) -> void:
	# text 为空时收起窗口条
	window_panel.visible = text != "" and not _away
	_window_label.text = text
	_window_bar.value = clampf(fraction, 0.0, 1.0)
	nope_button.visible = nope_visible
	nope_button.disabled = not nope_enabled


# —— 手牌与按钮 ——

func set_hand(ids: Array, selected: Dictionary, enabled: bool) -> void:
	strip.set_hand(ids, selected, enabled)


func set_actions(can_play: bool, can_draw: bool, selected: int, my_turn: bool, hint := "") -> void:
	play_button.disabled = not can_play
	draw_button.disabled = not can_draw
	play_button.text = "出牌 ×%d" % selected if selected > 1 else "出牌"
	if _spectating:
		_hint.text = HINT_SPECTATE % OS.get_keycode_string(RulebookContent.HOTKEY)
	elif hint != "":
		_hint.text = hint
	elif my_turn:
		_hint.text = "出几张功能牌(也可以不出),最后摸一张结束回合 · Enter 出牌 · 空格 摸牌"
	else:
		_hint.text = HINT_IDLE % OS.get_keycode_string(RulebookContent.HOTKEY)


func set_spectating(on: bool) -> void:
	_spectating = on
	_apply_visibility()


func set_away_from_seat(away: bool) -> void:
	# 镜头去拍特写(摸到炸弹、爆炸、胜利)时收起按钮行与手牌条
	_away = away
	_apply_visibility()


func _apply_visibility() -> void:
	var seated := not _away
	_action_row.visible = seated and not _spectating
	var waiting := prompt_kind == PROMPT_REINSERT or prompt_kind == PROMPT_GIVE
	play_button.modulate.a = 0.0 if waiting else 1.0
	draw_button.modulate.a = 0.0 if waiting else 1.0
	_spectate_panel.visible = seated and _spectating
	_prompt_holder.visible = seated and not _spectating
	_hint.visible = seated
	if _away:
		window_panel.visible = false


# —— 临时面板:选目标、点名、塞回、给牌 ——

func show_targets(rows: Array, title: String) -> void:
	# rows:[{pid, name, count}]。也可以直接在 3D 里点酒客
	var panel := _new_prompt(PROMPT_TARGET, title, "也可以直接点桌边的酒客")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	panel.get_child(0).add_child(row)
	for entry in rows:
		var button := UiTheme.button("%s(%d 张)" % [entry["name"], entry["count"]])
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 18)
		button.pressed.connect(func(): target_chosen.emit(entry["pid"]))
		row.add_child(button)
	_add_cancel(panel)


func show_named() -> void:
	# 三张零食:点名要哪一种牌
	var panel := _new_prompt(PROMPT_NAMED, "点名要一种牌", "对方有就必须给你一张,没有就落空")
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	panel.get_child(0).add_child(grid)
	for id in BombCatScreenState.nameable_cards():
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.icon = BombCatFaces.texture(id)
		button.expand_icon = true
		button.custom_minimum_size = NAMED_CARD + Vector2(8, 26)
		button.text = BombCatCard.display_name(id)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_font_size_override("font_size", 13)
		button.tooltip_text = BombCatCard.description(id)
		button.pressed.connect(func(): named_chosen.emit(id))
		grid.add_child(button)
	_add_cancel(panel)


func show_reinsert(max_pos: int) -> void:
	# 拆弹成功:把炸弹塞回牌堆的位置,0 = 顶 … max_pos = 底;确认前可以来回拖
	var panel := _new_prompt(PROMPT_REINSERT, "把炸弹偷偷塞回牌堆", "别人看不到你塞在哪 · ←→ 微调 · Enter 确认")
	reinsert_slider = HSlider.new()
	reinsert_slider.min_value = 0
	reinsert_slider.max_value = maxi(max_pos, 0)
	reinsert_slider.step = 1
	reinsert_slider.value = 0
	reinsert_slider.custom_minimum_size = Vector2(360, 24)
	reinsert_slider.focus_mode = Control.FOCUS_NONE
	reinsert_slider.editable = max_pos > 0
	panel.get_child(0).add_child(reinsert_slider)
	_reinsert_label = UiTheme.label(reinsert_text(0, max_pos), 18, UiTheme.BRASS_BRIGHT, UiTheme.display_font())
	_reinsert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.get_child(0).add_child(_reinsert_label)
	reinsert_slider.value_changed.connect(func(v: float): _reinsert_label.text = reinsert_text(int(v), max_pos))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	panel.get_child(0).add_child(row)
	for spec in [["最上面", 0], ["正中间", maxi(max_pos, 0) / 2], ["最底下", maxi(max_pos, 0)]]:
		var preset := UiTheme.button(spec[0])
		preset.focus_mode = Control.FOCUS_NONE
		preset.add_theme_font_size_override("font_size", 16)
		preset.pressed.connect(func(): reinsert_slider.value = spec[1])
		row.add_child(preset)
	var ok := UiTheme.button("就放这儿", true)
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(func(): reinsert_confirmed.emit(int(reinsert_slider.value)))
	row.add_child(ok)


func reinsert_value() -> int:
	return int(reinsert_slider.value) if is_instance_valid(reinsert_slider) and prompt_kind == PROMPT_REINSERT else -1


func nudge_reinsert(step: int) -> void:
	if is_instance_valid(reinsert_slider) and prompt_kind == PROMPT_REINSERT:
		reinsert_slider.value = clampf(reinsert_slider.value + step, reinsert_slider.min_value, reinsert_slider.max_value)


func show_give(asker_name: String) -> void:
	_new_prompt(PROMPT_GIVE, "%s 向你讨要一张牌" % asker_name, "点一张手牌给他(或按 1–9);不给的话时间到了随机给一张")


func hide_prompt() -> void:
	if is_instance_valid(_prompt_panel):
		_prompt_holder.remove_child(_prompt_panel)
		_prompt_panel.queue_free()
	_prompt_panel = null
	prompt_kind = PROMPT_NONE
	reinsert_slider = null
	_apply_visibility()


func _new_prompt(kind: String, title: String, sub: String) -> PanelContainer:
	hide_prompt()
	prompt_kind = kind
	var panel := PanelContainer.new()
	var style := UiTheme.panel_box(UiTheme.PANEL, UiTheme.BRASS_BRIGHT, 2, 14)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := UiTheme.label(title, 22, UiTheme.BRASS_BRIGHT, UiTheme.display_font())
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(head)
	if sub != "":
		var line := UiTheme.label(sub, 14, UiTheme.PARCHMENT_DIM)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(line)
	_prompt_holder.add_child(panel)
	_prompt_panel = panel
	_apply_visibility()
	panel.scale = Vector2(0.9, 0.9)
	panel.resized.connect(func(): panel.pivot_offset = panel.size / 2.0)
	var tween := panel.create_tween()
	tween.tween_property(panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return panel


func _add_cancel(panel: PanelContainer) -> void:
	var cancel := UiTheme.button("取消(Esc)")
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.add_theme_font_size_override("font_size", 15)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func(): prompt_cancelled.emit())
	panel.get_child(0).add_child(cancel)


# —— 偷看浮层 ——

func show_peek(ids: Array) -> void:
	for child in _peek_row.get_children():
		_peek_row.remove_child(child)
		child.queue_free()
	for i in ids.size():
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		var face := TextureRect.new()
		face.texture = BombCatFaces.texture(ids[i])
		face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.custom_minimum_size = PEEK_CARD
		face.mouse_filter = Control.MOUSE_FILTER_STOP
		face.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed:
				peek_dismissed.emit())
		col.add_child(face)
		var caption := UiTheme.label("第 %d 张%s" % [i + 1, "(最上面)" if i == 0 else ""], 15,
			UiTheme.BLOOD if ids[i] == BombCatCard.BOMB else UiTheme.PARCHMENT)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(caption)
		_peek_row.add_child(col)
	peek_panel.visible = not ids.is_empty()


func hide_peek() -> void:
	peek_panel.visible = false


func is_peek_open() -> bool:
	return peek_panel.visible


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


func hide_announce(duration := 0.15) -> void:
	if _announce_tween != null and _announce_tween.is_valid():
		_announce_tween.kill()
	_announce_tween = create_tween()
	_announce_tween.tween_property(_announce_box, "modulate:a", 0.0, duration)


func _set_announce_y(y_offset: float) -> void:
	_announce_box.offset_top = y_offset
	_announce_box.offset_bottom = y_offset


func clear_my_bubble() -> void:
	for old in _bubble_anchor.get_children():
		_bubble_anchor.remove_child(old)
		old.queue_free()


func my_bubble(text: String, color := UiTheme.INK, duration := 1.6) -> void:
	# 自己的出牌声明 / 九宫格快捷对话:弹在出牌按钮行上方居中;新的一句顶掉旧的
	clear_my_bubble()
	var bubble := SpeechBubble.new(text, color, duration)
	_bubble_anchor.add_child(bubble)
	bubble.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE,
		int(SpeechBubble.TAIL_LENGTH + MY_BUBBLE_GAP))
	bubble.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bubble.grow_vertical = Control.GROW_DIRECTION_BEGIN
