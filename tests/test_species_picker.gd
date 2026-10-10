extends GutTest
# 挑选形象(子项目② §3.1/§3.2):taken_map 不含自己、忽略 -1、映射为 下标→名字;请求结算;
# 被占的格子禁用并写占用者名字、自己当前的格子可选;键盘在格子间回绕;无头下头像是色圆片加首字。


const FOX := 0
const BEAR := 1
const CROC := 7


func _row(pid: int, pname: String, species: Variant) -> Dictionary:
	return {"pid": pid, "name": pname, "ready": false, "is_host": pid == 1, "species": species}


func after_each():
	SpeciesPortraits.clear()


# —— 纯逻辑 ——

func test_taken_map_excludes_me_and_ignores_unassigned():
	var players := [_row(1, "房主", CROC), _row(5, "阿杰", BEAR), _row(6, "我", FOX), _row(7, "新来的", -1)]
	assert_eq(SpeciesPicker.taken_map(players, 6), {CROC: "房主", BEAR: "阿杰"})


func test_taken_map_ignores_junk_from_the_network():
	var players := [_row(1, "房主", 99), _row(5, "阿杰", "bear"), _row(6, "乙", 2.0), "不是字典", _row(8, "丙", 3)]
	assert_eq(SpeciesPicker.taken_map(players, 6), {3: "丙"})


func test_my_cell_stays_free_even_when_everything_else_is_taken():
	var players := []
	for i in Species.count():
		players.append(_row(10 + i, "客%d" % i, i))
	var taken := SpeciesPicker.taken_map(players, 12)
	assert_eq(taken.size(), Species.count() - 1)
	assert_false(taken.has(2), "自己的格子不算被占")


func test_request_resolution():
	var players := [_row(1, "房主", CROC), _row(5, "阿杰", BEAR), _row(6, "我", FOX)]
	assert_eq(SpeciesPicker.resolve_request(players, 6, FOX)["result"], "granted")
	assert_eq(SpeciesPicker.resolve_request(players, 6, BEAR), {"result": "taken", "by": "阿杰"})
	assert_eq(SpeciesPicker.resolve_request(players, 6, 3)["result"], "pending", "名单与请求无关:等下一份或超时静默")


# —— 面板 ——

func _picker() -> SpeciesPicker:
	var holder := Control.new()
	holder.theme = UiTheme.theme()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(holder)
	var picker := SpeciesPicker.new()
	holder.add_child(picker)
	return picker


func test_taken_cells_are_disabled_and_name_the_occupant():
	var picker := _picker()
	picker.open(FOX, {BEAR: "阿杰"}, Rect2(48, 200, 480, 56), true)
	assert_true(picker.is_open())
	assert_true(picker.cell(BEAR).disabled)
	assert_false(picker.cell(FOX).disabled, "自己当前的格子")
	assert_true(picker.is_current(FOX))
	var texts := picker.cell(BEAR).find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_has(texts, "阿杰")
	assert_eq(picker.get_viewport().gui_get_focus_owner(), picker.cell(FOX), "焦点落在当前形象上")


func test_picking_emits_the_index_and_closes():
	var picker := _picker()
	watch_signals(picker)
	picker.open(FOX, {}, Rect2(48, 200, 480, 56), true)
	picker.cell(CROC).pressed.emit()
	assert_signal_emitted_with_parameters(picker, "picked", [CROC])
	assert_signal_emitted(picker, "closed")
	assert_false(picker.is_open())


func test_panel_sits_beside_the_side_panel_inside_the_screen():
	var picker := _picker()
	picker.open(FOX, {}, Rect2(48, 200, 480, 56), true)
	var size := picker.panel_size()
	assert_lte(size.x, 480.0, "面板宽不超过 480(5×2 格;4×2 时是 440)")
	assert_lte(size.y, 330.0)
	var screen := picker.get_viewport_rect().size
	var rect := Rect2(picker._panel.global_position, size)
	assert_gte(rect.position.x, 48 + 480.0, "贴在主菜单侧栏右边,不盖住它")
	assert_lte(rect.end.y, screen.y)
	picker.close()
	picker.open(FOX, {}, Rect2(796, 600, 440, 30), false)
	rect = Rect2(picker._panel.global_position, picker.panel_size())
	assert_lte(rect.end.x, 796.0, "等待厅:贴在面板左边")
	assert_lte(rect.end.y, screen.y, "靠近底部时往上挪,整块留在屏幕里")


func test_arrow_keys_wrap_inside_the_grid():
	var picker := _picker()
	picker.open(FOX, {}, Rect2(48, 200, 480, 56), true)
	var first := picker.cell(0)
	# 5×2 格(10 个物种)
	assert_eq(first.get_node(first.focus_neighbor_left), picker.cell(4), "左边回绕到行尾")
	assert_eq(first.get_node(first.focus_neighbor_top), picker.cell(5), "上边回绕到下一行")
	assert_eq(picker.cell(9).get_node(picker.cell(9).focus_neighbor_right), picker.cell(5))


func test_escape_closes_and_returns_focus():
	var picker := _picker()
	var chip := SpeciesChip.new(FOX, 56.0)
	picker.get_parent().add_child(chip)
	picker.open(FOX, {}, Rect2(48, 200, 480, 56), true, chip)
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	picker._input(esc)
	assert_false(picker.is_open())
	assert_eq(picker.get_viewport().gui_get_focus_owner(), chip, "焦点还给头像")


# —— 头像 ——

func test_headless_build_gives_colored_disc_fallbacks():
	assert_false(SpeciesPortraits.is_built())
	SpeciesPortraits.build(self)
	assert_true(SpeciesPortraits.is_built())
	assert_false(SpeciesPortraits.is_baked(), "现在只有回退圆片")
	for i in Species.count():
		var image := SpeciesPortraits.texture(i).get_image()
		assert_eq(image.get_size(), Vector2i(SpeciesPortraits.SIZE, SpeciesPortraits.SIZE))
		var center := image.get_pixel(SpeciesPortraits.SIZE / 2, SpeciesPortraits.SIZE / 2)
		assert_almost_eq(center.r, SpeciesPortraits.FALLBACK_COLORS[i].r, 0.01, Species.IDS[i])
		assert_eq(image.get_pixel(0, 0).a, 0.0, "圆片外透明")
	assert_same(SpeciesPortraits.texture(FOX), SpeciesPortraits.texture(FOX), "缓存")


func test_chip_overlays_the_glyph_on_fallback_portraits():
	var chip: SpeciesChip = add_child_autofree(SpeciesChip.new(CROC, 28.0, false))
	assert_true(chip.shows_glyph())
	assert_eq(chip.glyph_text(), "鳄")
	assert_eq(chip.tooltip_text, "鳄鱼 · 亡命徒")
	assert_true(chip.is_processing(), "头像还没做好:轮询")
	SpeciesPortraits.build(self)
	await wait_process_frames(2)
	assert_false(chip.is_processing(), "做好了就停止轮询")
	assert_true(chip.shows_glyph(), "回退圆片仍叠首字")
	chip.set_species(-1)
	assert_eq(chip.glyph_text(), "…")
	assert_eq(chip.tooltip_text, "挑选中…")


func test_small_chip_is_not_inflated_by_button_padding():
	var holder := Control.new()
	holder.theme = UiTheme.theme()
	add_child_autofree(holder)
	var chip := SpeciesChip.new(FOX, 28.0)
	holder.add_child(chip)
	assert_eq(chip.get_combined_minimum_size(), Vector2(28, 28), "等待厅一行不超过 36 像素")
