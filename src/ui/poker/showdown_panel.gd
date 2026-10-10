class_name ShowdownPanel
extends PanelContainer
# 摊牌面板(规格 §6.1):画面右侧,从这一手第一次亮牌到下一手开始一直显示,让人看清每个亮了牌的人——
# 名字、2 张 ≥ 30×42 的小牌、牌型名与这一手的结果(赢家排在最前,「赢 1,240」)。
# 弃牌的人没亮牌,他的牌是隐藏信息,不在这里。条目来自事件与视图,坏条目丢掉、坏字段当空。


const WIDTH := 300.0
const TOP := 76.0                  # 右上「散局」「规则」按钮下面
const MAX_HEIGHT := 440.0          # 底边 ≤ 516:下面是右下角的事件日志
const MAX_ENTRIES := 8
const CARD_SIZE := Vector2(30, 42)
const TITLE := "摊牌"
const TITLE_FONT := 15
const NAME_FONT := 14
const HAND_FONT := 13
const RESULT_FONT := 15
const ROW_GAP := 4
const CELL_GAP := 8
const PADDING := Vector2(10, 6)
const LOSER_ALPHA := 0.72          # 没赢的人整行压暗一点,赢家一眼能看出来
const NO_WIN_TEXT := "—"
const BACKGROUND_ALPHA := 0.95

var _rows: VBoxContainer


static func sanitize(entries: Variant) -> Array:
	# won:这一手赢到的总额;不知道(迟到者没看到分池)为 null
	if not entries is Array:
		return []
	var out := []
	for entry in entries:
		if not entry is Dictionary:
			continue
		var won: Variant = entry.get("won")
		out.append({
			"name": entry["name"] if entry.get("name") is String else "?",
			"cards": CardStrip.sanitize(entry.get("cards")),
			"hand_name": entry["hand_name"] if entry.get("hand_name") is String else "",
			"won": won if won is int else null,
		})
		if out.size() == MAX_ENTRIES:
			break
	return out


static func result_text(won: Variant) -> String:
	if not won is int:
		return ""
	return "赢 %s" % ChipText.format(won) if won > 0 else NO_WIN_TEXT


func _ready() -> void:
	# 底色几乎不透明:右侧座位的铭牌在它下面,半透明会透出来和牌、字叠在一起
	var style := UiTheme.panel_box(Color(UiTheme.PANEL_SOFT, BACKGROUND_ALPHA), Color(UiTheme.BRASS, 0.5), 1, 12)
	style.content_margin_left = PADDING.x
	style.content_margin_right = PADDING.x
	style.content_margin_top = PADDING.y
	style.content_margin_bottom = PADDING.y
	add_theme_stylebox_override("panel", style)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.x = WIDTH
	# 贴右边、在右上按钮下面,向下长
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -PokerHud.MARGIN.x - WIDTH
	offset_right = -PokerHud.MARGIN.x
	offset_top = TOP
	offset_bottom = TOP
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ROW_GAP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	box.add_child(UiTheme.label(TITLE, TITLE_FONT, UiTheme.BRASS, UiTheme.display_font()))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", ROW_GAP)
	_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_rows)
	visible = false


func set_entries(entries: Variant) -> void:
	for old in _rows.get_children():
		_rows.remove_child(old)
		old.free()   # 已出树,直接释放(queue_free 在无头测试里会留到帧末成为孤儿)
	var clean := sanitize(entries)
	for entry in clean:
		_rows.add_child(_row(entry))
	visible = not clean.is_empty()


func strips() -> Array:
	# 每行的小牌条(悬停大图从这里取候选)
	return _rows.get_children().map(func(row: Node) -> Node: return row.get_child(0))


func row_count() -> int:
	return _rows.get_child_count()


func _row(entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", CELL_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var winner: bool = entry["won"] is int and entry["won"] > 0
	if entry["won"] is int and not winner:
		row.modulate.a = LOSER_ALPHA
	var strip := CardStrip.new(0, CARD_SIZE)
	strip.set_cards(entry["cards"])
	row.add_child(strip)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var name_label := UiTheme.label(entry["name"], NAME_FONT, UiTheme.PARCHMENT, UiTheme.display_font())
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	text.add_child(name_label)
	var hand_label := UiTheme.label(entry["hand_name"], HAND_FONT, UiTheme.BRASS_BRIGHT)
	hand_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hand_label.clip_text = true
	text.add_child(hand_label)
	var result := UiTheme.label(result_text(entry["won"]), RESULT_FONT, UiTheme.TRUTH if winner else UiTheme.PARCHMENT_DIM,
		UiTheme.display_font())
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(result)
	return row
