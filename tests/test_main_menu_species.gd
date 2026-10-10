extends GutTest
# 主菜单挑选形象(子项目② §3.1):名号旁的头像不把面板撑高(1280×720 下面板已经差不多满了);
# 点开的挑选面板弹在侧栏右边;选中后存进设置(id 字符串)、更新本次运行的形象并让桌边预览换人。


const MainMenuScreen := preload("res://src/ui/main_menu/main_menu.gd")
const PANEL_HEIGHT_BEFORE := 718.0   # 加头像之前无头下量到的面板最小高度


class StubWorld:
	extends RefCounted
	var previews: Array = []

	func show_menu_preview(index: int) -> void:
		previews.append(index)


class StubApp:
	extends Node
	var settings_path := ""
	var species := 3
	var world := StubWorld.new()

	func is_rules_open() -> bool:
		return false


var app: StubApp
var menu: Control
var _feed_checked := false


func before_each():
	# 主菜单进树时会查一次网上更新源:测试里不发请求
	_feed_checked = Updater._feed_checked
	Updater._feed_checked = true
	app = autofree(StubApp.new())
	app.settings_path = OS.get_temp_dir().path_join("liars_tavern_menu_species_gut_%d.cfg" % OS.get_process_id())
	DirAccess.remove_absolute(app.settings_path)
	var holder := Control.new()
	holder.theme = UiTheme.theme()
	holder.size = Vector2(1280, 720)
	add_child_autofree(holder)
	menu = MainMenuScreen.new(app)
	menu.size = Vector2(1280, 720)
	holder.add_child(menu)
	await wait_process_frames(2)


func after_each():
	Updater._feed_checked = _feed_checked
	DirAccess.remove_absolute(app.settings_path)


func test_species_chip_does_not_make_the_panel_taller():
	assert_lte(menu._panel.get_combined_minimum_size().y, PANEL_HEIGHT_BEFORE)
	assert_lte(menu._species_chip.get_combined_minimum_size().y, menu._name_edit.get_combined_minimum_size().y,
		"头像不比昵称框高")
	assert_eq(menu._species_chip.species, 3, "用 main 解析好的形象")
	assert_eq(menu._species_chip.tooltip_text, "挑选形象:猫 · 独行枪手")


func test_mode_buttons_fit_in_the_panel_width():
	# 「开一桌」标题右边是六种玩法的三列两行格子:不能把侧栏面板撑宽
	assert_lte(menu._panel.get_combined_minimum_size().x, MainMenuScreen.PANEL_WIDTH)


func test_mode_grid_does_not_make_the_panel_scroll_at_720p():
	# 两行玩法按钮多出来的高度由「局域网房间」标题行收进搜索状态抵掉:1280×720 下整块面板仍放得下,不用滚动
	assert_lte(menu._panel.get_combined_minimum_size().y, menu._scroll.size.y)
	var picker: GridContainer = menu._panel.find_children("*", "GridContainer", true, false)[0]
	assert_eq(picker.get_child_count(), GameMode.MENU_ORDER.size(), "六个格子都在")
	assert_eq(menu._scan_label.get_parent().get_child(0).text, "局域网房间", "搜索状态在「局域网房间」标题行里")


func test_menu_shows_the_preview_on_entry():
	assert_eq(app.world.previews, [3], "0 号椅上坐着自己的形象")


func test_picker_opens_beside_the_panel():
	menu._species_chip.pressed.emit()
	assert_true(menu._picker.is_open())
	var panel_rect: Rect2 = menu._panel.get_global_rect()
	assert_gte(menu._picker._panel.global_position.x, panel_rect.end.x, "弹在侧栏右边,不盖住侧栏")
	assert_eq(menu.get_viewport().gui_get_focus_owner(), menu._picker.cell(3), "焦点落在当前形象")


func test_picking_saves_the_id_and_swaps_the_preview():
	menu._species_chip.pressed.emit()
	menu._picker.cell(7).pressed.emit()
	assert_false(menu._picker.is_open())
	assert_eq(Settings.get_species(app.settings_path), 7)
	var config := ConfigFile.new()
	config.load(app.settings_path)
	assert_eq(config.get_value("player", "species"), "crocodile")
	assert_eq(app.species, 7, "本次运行之后建房 / 加入都用它")
	assert_eq(menu._species_chip.species, 7)
	assert_eq(app.world.previews, [3, 7])
