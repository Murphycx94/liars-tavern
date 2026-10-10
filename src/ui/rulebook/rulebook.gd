class_name Rulebook
extends ColorRect
# 说明书:模态遮罩 + 书本式面板。顶部页签在两本书(骗子酒馆 / 德州扑克)之间切换,
# 左侧章节目录,右侧正文(可滚动),底部翻页。每本书各自记得读到哪页,合上时由 main 记下(bookmarks)。
# 对局中打开不会暂停游戏;遮罩吞掉鼠标与未处理的按键,避免误触牌桌快捷键。
# F1 / Esc / 点遮罩 / 「合上」关闭;← → 或 PageUp/PageDown 翻页。


signal closed
# 翻开或切到某本书。德州牌面在后台生成(规格 §5.2「说明书翻到德州那本」时开始),
# 生成完之前示例小牌是占位色块。接线在 main(任务 7 合并时接上):
# book_shown(德州那本) → PokerFaces.build();PokerFaces.built_signal() → refresh_card_faces()
signal book_shown(book: String)

const HOTKEY := RulebookContent.HOTKEY
const PANEL_SIZE := Vector2(980, 600)      # 最小尺寸;高度随窗口放大到 PANEL_MAX_HEIGHT
const PANEL_MAX_HEIGHT := 760.0
const PANEL_MARGIN := 40.0
const NAV_WIDTH := 200.0                  # 目录最窄的宽度;实际取两本书里最长的章节名
const NUMERALS := ["壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖", "拾"]

var _in_match := false
var _book := RulebookContent.BOOK_LIARS
var _bookmarks := {}        # 书 → 读到的页;切走时记下,切回来接着读
var _sections: Array[Dictionary] = []
var _current := -1
var _closing := false
var _panel: PanelContainer
var _tabs := {}             # 书 → 页签按钮
var _nav: VBoxContainer
var _nav_buttons: Array[Button] = []
var _number: Label
var _title: Label
var _tagline: Label
var _scroll: ScrollContainer
var _content: VBoxContainer
var _page_label: Label
var _prev: Button
var _next: Button
var _fade: Tween = null
var _previous_focus: Control = null


func _init(in_match := false, book := RulebookContent.BOOK_LIARS, pages := {}) -> void:
	# pages:每本书上次读到的页({书: 页码}),翻开时接着读;只读不改调用方的字典
	_in_match = in_match
	_book = book if RulebookContent.BOOKS.has(book) else RulebookContent.BOOK_LIARS
	_bookmarks = pages.duplicate()


func _ready() -> void:
	_sections = RulebookContent.sections(_book)
	color = Color(0, 0, 0, 0.6)
	# 已在树内:必须连同偏移一起重置,只设锚点会保留当前的零尺寸矩形
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_nav.custom_minimum_size.x = _widest_nav_width()
	resized.connect(_fit_panel)
	_fit_panel()
	show_section(_bookmark())
	# 接管键盘焦点:否则背后聚焦的控件(昵称框、结算按钮、确认框)仍会收到按键;合上时归还
	_previous_focus = get_viewport().gui_get_focus_owner()
	_nav_buttons[_current].grab_focus()
	_play_open()
	book_shown.emit(_book)


func current_section() -> int:
	return _current


func current_book() -> String:
	return _book


func bookmarks() -> Dictionary:
	# 每本书读到的页(含正在读的这本):合上时 main 记下,下次翻开接着读
	var marks := _bookmarks.duplicate()
	marks[_book] = _current
	return marks


func show_book(book: String) -> void:
	# 换一本书:记下这本读到的页,按新书重建章节目录,翻到那本上次读到的页
	if book == _book or not RulebookContent.BOOKS.has(book):
		return
	_bookmarks[_book] = _current
	_book = book
	_sections = RulebookContent.sections(book)
	_fill_nav()
	for key in _tabs:
		_tabs[key].set_pressed_no_signal(key == book)
	_current = -1   # 复位:两本都停在第 0 页时,show_section(0) 会当作没换页而不重绘
	show_section(_bookmark())
	book_shown.emit(book)


func refresh_card_faces() -> void:
	# 刷新入口:牌面纹理生成完后由外部调用,当前页的牌面小图重新取纹理。
	# 别的页翻到时才重建,本来就会取到最新的纹理
	RulebookBlocks.refresh_cards(_content)


func _bookmark() -> int:
	# 当前这本书上次读到的页;章节变少了也不越界
	var page: Variant = _bookmarks.get(_book, 0)
	return clampi(page if page is int else 0, 0, _sections.size() - 1)


func show_section(index: int) -> void:
	if index == _current or index < 0 or index >= _sections.size():
		return
	_current = index
	var section := _sections[index]
	_number.text = _numeral(index)
	_title.text = section["title"]
	_tagline.text = section.get("tagline", "")
	for child in _content.get_children():
		child.free()  # 立即释放:正文里没有会触发翻页的控件,不必等到帧末
	for block in section["blocks"]:
		_content.add_child(RulebookBlocks.build(block))
	_scroll.scroll_vertical = 0
	for i in _nav_buttons.size():
		_nav_buttons[i].set_pressed_no_signal(i == index)
	var focused := get_viewport().gui_get_focus_owner()
	if focused is Button and focused in _nav_buttons:  # 先判类型:类型化数组查找别的控件会报错
		_nav_buttons[index].grab_focus()
	_page_label.text = "%d / %d" % [index + 1, _sections.size()]
	_prev.disabled = index == 0
	_next.disabled = index == _sections.size() - 1
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_content.modulate.a = 0.0
	_fade = create_tween()
	_fade.tween_property(_content, "modulate:a", 1.0, 0.22)


func turn_page(step: int) -> void:
	var target := clampi(_current + step, 0, _sections.size() - 1)
	if target != _current:
		Sfx.play("flip")
		show_section(target)


func close() -> void:
	if _closing:
		return
	_closing = true
	Sfx.play("ui_click")
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	else:
		get_viewport().gui_release_focus()
	closed.emit()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.15)
	tween.tween_callback(queue_free)


# —— 输入 ——

func _input(event: InputEvent) -> void:
	# 先于 GUI 焦点导航处理:关闭与翻页
	if _closing:
		return
	if event.is_action_pressed("ui_cancel") or _is_key(event, HOTKEY):
		get_viewport().set_input_as_handled()
		close()
	elif _is_key(event, KEY_RIGHT) or _is_key(event, KEY_PAGEDOWN):
		get_viewport().set_input_as_handled()
		turn_page(1)
	elif _is_key(event, KEY_LEFT) or _is_key(event, KEY_PAGEUP):
		get_viewport().set_input_as_handled()
		turn_page(-1)


func _unhandled_input(event: InputEvent) -> void:
	# 说明书在最上层:按钮没用到的按键一律吞掉,牌桌的选牌/出牌/质疑快捷键不会在背后生效。
	# 合上的淡出期间也继续吞,连按两下 Esc 不会漏到牌桌弹出「离开」确认
	if event is InputEventKey:
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	# 面板会拦下自己范围内的点击,能到这里的是遮罩空白处
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		close()


static func is_hotkey(event: InputEvent) -> bool:
	return _is_key(event, HOTKEY)


static func _is_key(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode


# —— 布局 ——

func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := UiTheme.panel_box(Color(0.07, 0.05, 0.04, 0.96), Color(UiTheme.BRASS, 0.75), 2, 14)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 22
	style.content_margin_bottom = 20
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 30
	_panel.add_theme_stylebox_override("panel", style)
	_panel.resized.connect(func(): _panel.pivot_offset = _panel.size / 2.0)
	center.add_child(_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	_panel.add_child(root)
	root.add_child(_build_header())
	root.add_child(RulebookStyle.divider(true))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 26)
	root.add_child(body)
	body.add_child(_build_nav())
	body.add_child(RulebookStyle.divider(false))
	body.add_child(_build_page())
	root.add_child(RulebookStyle.divider(true))
	root.add_child(_build_footer())


func _fit_panel() -> void:
	var height := clampf(size.y - PANEL_MARGIN * 2.0, PANEL_SIZE.y, PANEL_MAX_HEIGHT)
	_panel.custom_minimum_size = Vector2(PANEL_SIZE.x, height)


func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var title := UiTheme.label("酒馆规矩", 42, UiTheme.BRASS_BRIGHT, UiTheme.title_font())
	title.add_theme_color_override("font_shadow_color", Color(0.35, 0.05, 0.03, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 3)
	row.add_child(title)
	# 五本书的页签放下之后只剩放得下「HOUSE RULES」的宽度(原来还有「· 游戏说明书」,总被截成「HOUSE RULES ·…」);
	# 仍按剩余宽度缩(放不下就省略),不把整本书撑宽
	var subtitle := UiTheme.label("HOUSE  RULES", 15, UiTheme.PARCHMENT_DIM, UiTheme.latin_font())
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	subtitle.clip_text = true
	subtitle.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(subtitle)
	row.add_child(_build_tabs())
	var close_button := UiTheme.button("合上")
	close_button.add_theme_font_size_override("font_size", 17)
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button.pressed.connect(close)
	row.add_child(close_button)
	return row


func _build_tabs() -> Control:
	# 两本书的页签:连在一起的分段按钮,正在看的那本黄铜底
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var group := ButtonGroup.new()
	var books: Array = RulebookContent.BOOKS
	for i in books.size():
		var book: String = books[i]
		var tab := Button.new()
		tab.text = RulebookContent.book_title(book)
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = book == _book
		tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		RulebookStyle.tab(tab, i == 0, i == books.size() - 1)
		tab.pressed.connect(_on_tab_pressed.bind(book))
		tab.mouse_entered.connect(Sfx.play.bind("ui_hover"))
		row.add_child(tab)
		_tabs[book] = tab
	return row


func _on_tab_pressed(book: String) -> void:
	if book != _book:
		Sfx.play("flip")
		show_book(book)


func _build_nav() -> Control:
	_nav = VBoxContainer.new()
	_nav.custom_minimum_size.x = NAV_WIDTH
	_nav.add_theme_constant_override("separation", 4)
	_fill_nav()
	return _nav


func _fill_nav() -> void:
	# 按当前这本书(重)建章节目录。旧按钮立即释放:切书由页签触发,目录按钮不在发信号的途中,
	# 不必留到帧末(那样同一帧里还挂着一批移出树的孤儿按钮)
	for button in _nav_buttons:
		button.free()
	_nav_buttons.clear()
	var group := ButtonGroup.new()
	for i in _sections.size():
		var button := Button.new()
		button.text = _nav_label(i, _sections[i]["title"])
		button.toggle_mode = true
		button.button_group = group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		RulebookStyle.nav_button(button)
		button.pressed.connect(func():
			Sfx.play("flip")
			show_section(i))
		button.mouse_entered.connect(Sfx.play.bind("ui_hover"))
		_nav.add_child(button)
		_nav_buttons.append(button)


func _widest_nav_width() -> float:
	# 目录宽度取两本书里最长的章节名:切书时目录与正文不左右跳。
	# 按目录按钮实际用的字体与边距量(界面字体随系统回退,写死宽度换台机器就不准)
	var probe := _nav_buttons[0]
	var font := probe.get_theme_font("font")
	var font_size := probe.get_theme_font_size("font_size")
	var padding := probe.get_theme_stylebox("normal").get_minimum_size().x
	var widest := NAV_WIDTH
	for book in RulebookContent.BOOKS:
		var sections := RulebookContent.sections(book)
		for i in sections.size():
			var text := _nav_label(i, sections[i]["title"])
			widest = maxf(widest, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + padding)
	return ceilf(widest)


static func _nav_label(index: int, title: String) -> String:
	return "%s   %s" % [_numeral(index), title]


static func _numeral(index: int) -> String:
	# 章节序号用大写数字,超出十章改用阿拉伯数字
	return NUMERALS[index] if index < NUMERALS.size() else str(index + 1)


func _build_page() -> Control:
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 14)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 16)
	page.add_child(heading)
	_number = UiTheme.label("", 52, Color(UiTheme.BRASS, 0.85), UiTheme.title_font())
	heading.add_child(_number)
	var titles := VBoxContainer.new()
	titles.alignment = BoxContainer.ALIGNMENT_CENTER
	titles.add_theme_constant_override("separation", 0)
	heading.add_child(titles)
	_title = UiTheme.label("", 32, UiTheme.PARCHMENT, UiTheme.display_font())
	_title.name = "SectionTitle"
	titles.add_child(_title)
	_tagline = UiTheme.label("", 15, UiTheme.MUTED)
	titles.add_child(_tagline)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 6)
	_scroll.add_child(margin)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.add_theme_constant_override("separation", 16)
	margin.add_child(_content)
	return page


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	if _in_match:
		row.add_child(UiTheme.label("对局不会暂停,计时照常 ·", 14, UiTheme.LIE))
	var keys := UiTheme.label("← → 翻页 · %s / Esc 合上" % OS.get_keycode_string(HOTKEY), 14, UiTheme.MUTED)
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(keys)
	_prev = UiTheme.button("‹ 上一页")
	_prev.add_theme_font_size_override("font_size", 16)
	_prev.pressed.connect(turn_page.bind(-1))
	row.add_child(_prev)
	_page_label = UiTheme.label("", 16, UiTheme.PARCHMENT_DIM, UiTheme.latin_font())
	_page_label.custom_minimum_size.x = 56
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_page_label)
	_next = UiTheme.button("下一页 ›")
	_next.add_theme_font_size_override("font_size", 16)
	_next.pressed.connect(turn_page.bind(1))
	row.add_child(_next)
	return row


func _play_open() -> void:
	modulate.a = 0.0
	_panel.scale = Vector2(0.96, 0.96)
	var tween := create_tween().set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, 0.18)
	tween.tween_property(_panel, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("flip")
