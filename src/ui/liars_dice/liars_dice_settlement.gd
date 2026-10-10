class_name LiarsDiceSettlement
extends ColorRect
# 吹牛骰子结算面板:版式、配色、入场动画与焦点规则同炸弹猫的结算(BombCatSettlement)——
# 「骰子留到最后」+ 胜者大字 + 名次行 + 按钮(房主「再来一局」带全员回等待厅,其他人「离开房间」)。
# 名次行:第 1 名写「还剩 N 颗骰子」,其余按出局顺序倒排,写「骰子输光」或「断线离开」。
# 只发信号(lobby_pressed / leave_pressed),不直接调用 Net(截图展台里也能用);
# ranking:LiarsDiceScreenState.ranking_rows() 的 [{"pid", "name", "place", "fate", "dice"}]。
# 面板停在屏幕右侧、竖直居中,只压暗右边(UiTheme.settlement_dock):左边留给结算庆祝里跳舞的胜者。


signal lobby_pressed
signal leave_pressed

const FATE_TEXT := {"winner": "还剩 %d 颗骰子", "out": "骰子输光", "left": "断线离开"}
const FOCUS_KEYS := ["ui_accept", "ui_focus_next", "ui_focus_prev", "ui_left", "ui_right", "ui_up", "ui_down"]

var _winner_name := ""
var _ranking: Array = []
var _mine := false
var _host := false
var _default_button: Button = null


static func fate_text(row: Dictionary) -> String:
	var fate := str(row.get("fate", ""))
	if fate == "winner":
		return FATE_TEXT["winner"] % int(row.get("dice", 0))
	return FATE_TEXT.get(fate, "")


func _init(winner_name: String, ranking: Array, mine: bool, host := false) -> void:
	_winner_name = winner_name
	_ranking = ranking
	_mine = mine
	_host = host


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
	_default_button.grab_focus()


func rows() -> Array:
	return _ranking.duplicate()


func default_button() -> Button:
	return _default_button


func _build_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	var style := UiTheme.panel_box(Color(0.07, 0.05, 0.04, 0.94), UiTheme.BRASS_BRIGHT, 2, 16)
	style.content_margin_left = 36
	style.content_margin_right = 36
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	style.shadow_color = Color(0, 0, 0, 0.7)
	style.shadow_size = 30
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var crown := UiTheme.label("骰子留到最后的人", 18, UiTheme.MUTED)
	crown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(crown)
	var title := UiTheme.label(("你" if _mine else _winner_name), 64, UiTheme.BRASS_BRIGHT, UiTheme.title_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for entry in _ranking:
		box.add_child(_rank_row(entry))
	box.add_child(_build_buttons())
	return panel


func _rank_row(entry: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var first: bool = entry["place"] == 1
	var place := UiTheme.label("第 %d 名" % entry["place"], 16, UiTheme.BRASS if first else UiTheme.MUTED)
	place.custom_minimum_size = Vector2(70, 0)
	place.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(place)
	var name_label := UiTheme.label(entry["name"], 20, UiTheme.PARCHMENT, UiTheme.display_font())
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	if first:
		for i in mini(int(entry.get("dice", 0)), LiarsDiceState.DICE_PER_PLAYER):
			var die := DiceIcon.new(1 + (i * 2) % 6, 20.0)
			die.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(die)
	var fate_color := UiTheme.BRASS_BRIGHT if first else (UiTheme.LIE if entry.get("fate") == "out" else UiTheme.PARCHMENT_DIM)
	var fate := UiTheme.label(fate_text(entry), 16, fate_color)
	fate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(fate)
	return row


func _build_buttons() -> HBoxContainer:
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	var leave := UiTheme.button("离开房间")
	leave.pressed.connect(func(): leave_pressed.emit())
	buttons.add_child(leave)
	_default_button = leave
	if _host:
		var again := UiTheme.button("再来一局", true)
		again.pressed.connect(func(): lobby_pressed.emit())
		buttons.add_child(again)
		_default_button = again
	else:
		buttons.add_child(UiTheme.label("等待房主开新一局…", 16, UiTheme.MUTED))
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
		_default_button.grab_focus()
