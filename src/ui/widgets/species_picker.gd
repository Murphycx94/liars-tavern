class_name SpeciesPicker
extends Control
# 挑选形象面板(子项目② §3.1/§3.2):5×2 格(2026-10-10 加了熊猫、企鹅,10 个物种;原来 4×2),每格大头像 +「狐狸」+「老千绅士」;
# 被别人占着的格子头像压灰、小字写占用者名字、按钮禁用;自己当前的格子黄铜边框。
# 弹出式:本节点铺满屏幕当遮罩(点空白处收起),面板贴在侧栏旁边浮在 3D 场景上,
# 不挤占侧栏的高度(主菜单在 1280×720 下已经差不多满了,德州等待厅的面板也压在 672 像素内)。
# 纯键盘:方向键在格子间移动(到边回绕,不会跑到背后的菜单里),Enter 选,Esc 收起并把焦点还给头像。


signal picked(index: int)
signal closed

const COLUMNS := 5
const CELL := Vector2(82, 112)    # 5 列以后每格收窄 6 像素(原 88),整块面板 ≈470 宽
const PORTRAIT := 72.0
const GAP := 6
const SIDE_GAP := 16.0          # 面板与侧栏的间距
const SCREEN_MARGIN := 8.0      # 面板离屏幕边缘至少这么远
const TAKEN_TINT := Color(0.45, 0.45, 0.45, 0.8)
const NAME_SIZE := 15
const SUB_SIZE := 12
const CELL_PADDING := 4

var _panel: PanelContainer
var _cells: Array[Button] = []
var _chips: Array[SpeciesChip] = []
var _subs: Array[Label] = []
var _current := Species.UNASSIGNED
var _return_focus: Control = null


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.screen_panel(0.92, Vector2(18, 14)))
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_child(UiTheme.label("挑选形象", 19, UiTheme.BRASS, UiTheme.display_font()))
	var hint := UiTheme.label("同桌不撞脸,先选先得", 13, UiTheme.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hint)
	box.add_child(head)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	box.add_child(grid)
	for i in Species.count():
		grid.add_child(_cell(i))
	_link_focus()


# —— 打开 / 收起 ——

func open(current: int, taken: Dictionary, beside: Rect2, to_right: bool, return_focus: Control = null) -> void:
	# beside:侧栏在屏幕上的矩形,y 取触发它的头像那一行;面板贴在它右边(to_right)或左边。
	# taken:{物种下标 → 占用者名字}(SpeciesPicker.taken_map 算出,不含自己)
	_current = Species.sanitize(current)
	_return_focus = return_focus
	for i in _cells.size():
		_set_cell(i, taken.get(i, ""))
	visible = true
	_place(beside, to_right)
	var focus := _current if _current != Species.UNASSIGNED else 0
	_cells[focus].grab_focus()


func update_taken(taken: Dictionary) -> void:
	# 面板开着时名单变了(别人换了形象):只改格子状态,不动焦点与位置
	for i in _cells.size():
		_set_cell(i, taken.get(i, ""))


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()
	if is_instance_valid(_return_focus) and _return_focus.is_inside_tree() and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()


func is_open() -> bool:
	return visible


func cell(index: int) -> Button:
	return _cells[index]


func panel_size() -> Vector2:
	return _panel.get_combined_minimum_size()


func _place(beside: Rect2, to_right: bool) -> void:
	var size_now := panel_size()
	var screen := get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var x := beside.end.x + SIDE_GAP if to_right else beside.position.x - SIDE_GAP - size_now.x
	var y := clampf(beside.position.y, SCREEN_MARGIN, maxf(screen.y - size_now.y - SCREEN_MARGIN, SCREEN_MARGIN))
	x = clampf(x, SCREEN_MARGIN, maxf(screen.x - size_now.x - SCREEN_MARGIN, SCREEN_MARGIN))
	# 本节点铺满所在图层:屏幕坐标换算到本地
	var local := get_global_transform().affine_inverse() * Vector2(x, y) if is_inside_tree() else Vector2(x, y)
	_panel.position = local
	_panel.size = size_now


func _gui_input(event: InputEvent) -> void:
	# 点面板外的空白处:收起(面板自己吃掉落在它上面的点击)
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		close()


func _input(event: InputEvent) -> void:
	# Esc 收起;说明书之类盖在上面、焦点不在面板里时不抢它的按键
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	var owner := get_viewport().gui_get_focus_owner()
	if owner == null or is_ancestor_of(owner):
		get_viewport().set_input_as_handled()
		close()


# —— 格子 ——

func _cell(index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = CELL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = Species.title(index)
	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 0)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	button.add_child(content)
	var chip := SpeciesChip.new(index, PORTRAIT, false)
	content.add_child(chip)
	var name_label := UiTheme.label(Species.LABELS[index], NAME_SIZE, UiTheme.PARCHMENT, UiTheme.display_font())
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_label)
	var sub := UiTheme.label(Species.ROLES[index], SUB_SIZE, UiTheme.PARCHMENT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.custom_minimum_size.x = CELL.x - 2 * CELL_PADDING
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(sub)
	button.pressed.connect(func():
		if not button.disabled:
			picked.emit(index)
			close())
	_cells.append(button)
	_chips.append(chip)
	_subs.append(sub)
	return button


func _set_cell(index: int, occupant: String) -> void:
	var button := _cells[index]
	var taken := occupant != ""
	button.disabled = taken
	_chips[index].modulate = TAKEN_TINT if taken else Color.WHITE
	_subs[index].text = occupant if taken else Species.ROLES[index]
	_subs[index].add_theme_color_override("font_color", UiTheme.LIE if taken else UiTheme.PARCHMENT_DIM)
	button.tooltip_text = "%s(%s 已选)" % [Species.title(index), occupant] if taken else Species.title(index)
	_style_cell(button, index == _current)


func _style_cell(button: Button, current: bool) -> void:
	var border := UiTheme.BRASS_BRIGHT if current else Color(UiTheme.BRASS, 0.35)
	var states := {
		"normal": [Color(0.16, 0.11, 0.07, 0.9), border, 2 if current else 1],
		"hover": [Color(0.26, 0.17, 0.09, 0.95), UiTheme.BRASS_BRIGHT, 2],
		"pressed": [Color(0.1, 0.07, 0.05, 0.95), UiTheme.BRASS_BRIGHT, 2],
		"hover_pressed": [Color(0.1, 0.07, 0.05, 0.95), UiTheme.BRASS_BRIGHT, 2],
		"disabled": [Color(0.08, 0.06, 0.05, 0.85), Color(UiTheme.BRASS, 0.2), 1],
		"focus": [Color.TRANSPARENT, UiTheme.BRASS_BRIGHT, 2],
	}
	for state: String in states:
		var box := UiTheme.panel_box(states[state][0], states[state][1], states[state][2], 8)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			box.set_content_margin(side, CELL_PADDING)
		if state == "focus":
			box.draw_center = false
			box.expand_margin_left = 2
			box.expand_margin_right = 2
			box.expand_margin_top = 2
			box.expand_margin_bottom = 2
		button.add_theme_stylebox_override(state, box)


func is_current(index: int) -> bool:
	return index == _current


func _link_focus() -> void:
	# 方向键只在格子之间走,到边回绕;Tab 也在格子里转
	var rows := ceili(_cells.size() / float(COLUMNS))
	for i in _cells.size():
		var row := i / COLUMNS
		var col := i % COLUMNS
		var button := _cells[i]
		var left := _cells[row * COLUMNS + posmod(col - 1, COLUMNS)]
		var right := _cells[row * COLUMNS + posmod(col + 1, COLUMNS)]
		var up := _cells[posmod(row - 1, rows) * COLUMNS + col]
		var down := _cells[posmod(row + 1, rows) * COLUMNS + col]
		var next := _cells[posmod(i + 1, _cells.size())]
		var previous := _cells[posmod(i - 1, _cells.size())]
		# 路径要等进树后才能解析:先存节点,进树时再换成路径
		button.set_meta("focus_links", [left, right, up, down, next, previous])
		button.tree_entered.connect(_apply_focus_links.bind(button))


func _apply_focus_links(button: Button) -> void:
	var links: Array = button.get_meta("focus_links")
	button.focus_neighbor_left = button.get_path_to(links[0])
	button.focus_neighbor_right = button.get_path_to(links[1])
	button.focus_neighbor_top = button.get_path_to(links[2])
	button.focus_neighbor_bottom = button.get_path_to(links[3])
	button.focus_next = button.get_path_to(links[4])
	button.focus_previous = button.get_path_to(links[5])


# —— 纯逻辑(等待厅与测试共用) ——

static func taken_map(players: Array, my_pid: int) -> Dictionary:
	# {物种下标 → 占用者名字}:不含自己,忽略 -1 与非法值(房主发来的名单也当不可信数据)
	var out := {}
	for p in players:
		if not p is Dictionary or p.get("pid") == my_pid:
			continue
		var index := Species.sanitize(p.get("species"))
		if index != Species.UNASSIGNED:
			out[index] = str(p.get("name", ""))
	return out


static func resolve_request(players: Array, my_pid: int, wanted: int) -> Dictionary:
	# 换形象请求的结算(收到新名单时):{"result": "granted" | "taken" | "pending", "by": 占用者名字}。
	# 自己拿到了 → granted;别人拿着 → taken;都不是(名单与请求无关、冷却中被拒)→ pending,由调用方超时后静默放弃
	for p in players:
		if p is Dictionary and p.get("pid") == my_pid and Species.sanitize(p.get("species")) == wanted:
			return {"result": "granted", "by": ""}
	var taken := taken_map(players, my_pid)
	if taken.has(wanted):
		return {"result": "taken", "by": taken[wanted]}
	return {"result": "pending", "by": ""}
