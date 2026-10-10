extends GutTest
# 主菜单开房的玩法切换(ModePicker):GameMode.MENU_ORDER 的六个格子排成三列两行,每格一个互斥的小号切换按钮、
# 预选传入的玩法;开房选不了的(menu_modes 之外,如斗地主登记之前)灰掉但照样占格子;
# 切到别的玩法只回调一次(被挤掉的那个按钮不回调);每种状态的样式都换成小内边距,键盘焦点只画一圈框。


const ModePicker := preload("res://src/ui/main_menu/mode_picker.gd")


var _selected: Array = []
var _picker: GridContainer


func before_each():
	_selected = []
	_picker = ModePicker.build(GameMode.SHORT_DECK, func(mode: String): _selected.append(mode))
	add_child_autofree(_picker)


func _buttons() -> Array:
	return _picker.get_children()


func test_one_toggle_per_menu_slot_in_order_with_label_and_summary():
	var modes := GameMode.MENU_ORDER
	assert_eq(_picker.columns, ModePicker.COLUMNS)
	assert_eq(ModePicker.COLUMNS, 3, "六种玩法三列两行")
	assert_eq(_buttons().size(), modes.size())
	for i in modes.size():
		var button: Button = _buttons()[i]
		assert_true(button.toggle_mode, "是切换按钮")
		assert_eq(button.text, GameMode.short_label(modes[i]))
		var available := GameMode.menu_modes().has(modes[i])
		assert_eq(button.disabled, not available, modes[i])
		if available:
			assert_eq(button.tooltip_text, GameMode.summary(modes[i]))
		else:
			assert_eq(button.tooltip_text, "%s · %s" % [GameMode.summary(modes[i]), ModePicker.UNAVAILABLE_NOTE])
		assert_eq(button.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "同一列等宽铺满")


func test_layout_is_two_rows_of_three():
	var labels := _buttons().map(func(b: Button) -> String: return b.text)
	assert_eq(labels.slice(0, 3), ["骗子酒馆", "炸弹猫", "吹牛骰子"])
	assert_eq(labels.slice(3, 6), ["斗地主", "德州·长牌", "德州·短牌"])


func test_unregistered_modes_are_greyed_out_and_cannot_be_preselected():
	if GameMode.is_valid(GameMode.DOU_DIZHU):
		pass_test("斗地主已登记,没有灰掉的格子")
		return
	var picker := ModePicker.build(GameMode.DOU_DIZHU, func(mode: String): _selected.append(mode))
	add_child_autofree(picker)
	var slot: Button = picker.get_children()[GameMode.MENU_ORDER.find(GameMode.DOU_DIZHU)]
	assert_true(slot.disabled)
	assert_false(slot.button_pressed, "灰掉的格子不能是选中状态")
	assert_eq(picker.get_children().filter(func(b: Button): return b.button_pressed), [])


func test_only_the_given_mode_starts_pressed():
	var pressed := _buttons().filter(func(b: Button): return b.button_pressed)
	assert_eq(pressed.size(), 1)
	assert_eq(pressed[0].text, GameMode.short_label(GameMode.SHORT_DECK))
	assert_eq(_selected, [], "预选不算选择,不回调")


func test_pressing_another_mode_reports_it_once_and_unpresses_the_old_one():
	_buttons()[0].button_pressed = true
	assert_eq(_selected, [GameMode.LIARS])
	assert_false(_buttons()[GameMode.MENU_ORDER.find(GameMode.SHORT_DECK)].button_pressed, "互斥:原来选中的被挤掉")
	_buttons()[0].button_pressed = true
	assert_eq(_selected, [GameMode.LIARS], "再点已选中的不重复回调")


func test_every_state_uses_the_small_padding_and_focus_is_only_a_ring():
	var button: Button = _buttons()[0]
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box: StyleBoxFlat = button.get_theme_stylebox(state)
		assert_eq(Vector2(box.content_margin_left, box.content_margin_top), ModePicker.PADDING, state)
		assert_eq(Vector2(box.content_margin_right, box.content_margin_bottom), ModePicker.PADDING, state)
	var focus: StyleBoxFlat = button.get_theme_stylebox("focus")
	assert_false(focus.draw_center, "焦点框不盖住底色")
	assert_true(button.get_theme_stylebox("normal").draw_center)
