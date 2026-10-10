class_name DdzSettlement
extends ColorRect
# 斗地主散局结算面板(版式照搬德州散局的 PokerSettlement):标题「散局结算」(有人离开时「牌局提前结束」),
# 一行小字说打了几手、为什么结束;表格三列——名次(同分同名次)、名字(离开的人标灰「已离开」)、累计分(赢绿、输红,带正负号)。
# 按钮:房主「回到等待厅」,其他人「离开房间」。只发信号,不直接调用 Net / Sfx。
# 面板停在屏幕右侧、竖直居中,只压暗右边(UiTheme.settlement_dock):左边留给结算庆祝里跳舞的第一名。


signal lobby_pressed
signal leave_pressed

const ROW_HEIGHT := 40.0
const COLUMN_PLACE := 76.0
const COLUMN_ROLE := 64.0
const COLUMN_SCORE := 110.0
const PANEL_WIDTH := 500.0
const LEFT_TEXT := "已离开"
const HOST_TEXT := "回到等待厅"
const GUEST_TEXT := "离开房间"
const TITLE := "散局结算"
const TITLE_LEFT := "牌局提前结束"
const FOCUS_KEYS := ["ui_accept", "ui_focus_next", "ui_focus_prev", "ui_left", "ui_right", "ui_up", "ui_down"]

var _ranking: Array = []
var _is_host := false
var _reason := ""
var _hands := 0
var _my_pid: Variant = null
var _primary: Button = null


static func subtitle(reason: String, hands: int) -> String:
	var played := "一共打了 %d 手" % hands if hands > 0 else "还没打完一手"
	if reason == DdzState.REASON_PLAYER_LEFT:
		return "%s · 有人离开,按累计分排名" % played
	return "%s · 房主散局" % played


func _init(results: Array, is_host: bool, reason := DdzState.REASON_HOST, hands := 0, my_pid: Variant = null) -> void:
	_ranking = DdzScreenState.ranking(results)
	_is_host = is_host
	_reason = reason
	_hands = hands
	_my_pid = my_pid


func rows() -> Array:
	return _ranking.duplicate()


func primary_button() -> Button:
	return _primary


func _ready() -> void:
	color = Color(0, 0, 0, 0.0)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dock := UiTheme.settlement_dock(self)
	var panel := _build_panel()
	dock.add_child(panel)
	_play_intro(panel)
	_focus_default.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().gui_get_focus_owner() != null or not FOCUS_KEYS.any(func(a: String): return event.is_action_pressed(a)):
		return
	get_viewport().set_input_as_handled()
	_primary.grab_focus()


func _build_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var style := UiTheme.panel_box(Color(0.07, 0.05, 0.04, 0.94), UiTheme.BRASS_BRIGHT, 2, 16)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	style.shadow_color = Color(0, 0, 0, 0.7)
	style.shadow_size = 30
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := UiTheme.label(TITLE_LEFT if _reason == DdzState.REASON_PLAYER_LEFT else TITLE, 40, UiTheme.BRASS_BRIGHT, UiTheme.title_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := UiTheme.label(subtitle(_reason, _hands), 15, UiTheme.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(_header_row())
	for entry in _ranking:
		box.add_child(_rank_row(entry))
	box.add_child(_build_buttons())
	return panel


func _header_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	for col in [["名次", COLUMN_PLACE], ["名字", 0.0], ["累计分", COLUMN_SCORE]]:
		var label := UiTheme.label(col[0], 14, UiTheme.MUTED)
		_place_column(label, col[1])
		row.add_child(label)
	return row


func _rank_row(entry: Dictionary) -> PanelContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.add_theme_constant_override("separation", 12)
	var first: bool = entry["place"] == 1
	var place := UiTheme.label("第 %d 名" % entry["place"], 16, UiTheme.BRASS_BRIGHT if first else UiTheme.MUTED, UiTheme.display_font())
	_place_column(place, COLUMN_PLACE)
	row.add_child(place)
	var mine: bool = entry["pid"] == _my_pid and _my_pid != null
	var name_label := UiTheme.label(entry["name"] + ("(你)" if mine else ""), 20,
		UiTheme.MUTED if entry["left"] else UiTheme.PARCHMENT, UiTheme.display_font())
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_place_column(name_label, 0.0)
	row.add_child(name_label)
	if entry["left"]:
		var gone := UiTheme.label(LEFT_TEXT, 13, UiTheme.MUTED)
		gone.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(gone)
	var score: int = entry["score"]
	var score_label := UiTheme.label(DdzNameplate.signed(score), 22,
		UiTheme.TRUTH if score > 0 else (UiTheme.LIE if score < 0 else UiTheme.PARCHMENT_DIM), UiTheme.latin_font())
	_place_column(score_label, COLUMN_SCORE)
	row.add_child(score_label)
	var holder := PanelContainer.new()
	var tint := UiTheme.flat(Color(UiTheme.BRASS, 0.14) if first else Color(0, 0, 0, 0.2), 8)
	tint.content_margin_left = 10
	tint.content_margin_right = 10
	if first:
		tint.border_width_left = 3
		tint.border_color = UiTheme.BRASS_BRIGHT
	holder.add_theme_stylebox_override("panel", tint)
	holder.add_child(row)
	return holder


func _place_column(label: Label, width: float) -> void:
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if width > 0.0:
		label.custom_minimum_size = Vector2(width, 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if width == COLUMN_SCORE else HORIZONTAL_ALIGNMENT_LEFT
	else:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _build_buttons() -> HBoxContainer:
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	if _is_host:
		_primary = UiTheme.button(HOST_TEXT, true)
		_primary.pressed.connect(func(): lobby_pressed.emit())
	else:
		_primary = UiTheme.button(GUEST_TEXT)
		_primary.pressed.connect(func(): leave_pressed.emit())
	buttons.add_child(_primary)
	if not _is_host:
		buttons.add_child(UiTheme.label("房主可带全员回等待厅", 15, UiTheme.MUTED))
	return buttons


func _play_intro(panel: PanelContainer) -> void:
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.85, 0.85)
	panel.resized.connect(func(): panel.pivot_offset = panel.size / 2.0)
	var tween := create_tween().set_parallel()
	var scrim: Control = get_node("Scrim")
	scrim.modulate.a = 0.0
	tween.tween_property(scrim, "modulate:a", 1.0, 0.5)
	tween.tween_property(panel, "modulate:a", 1.0, 0.45)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _focus_default() -> void:
	if not is_inside_tree():
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not focused.is_visible_in_tree():
		_primary.grab_focus()
