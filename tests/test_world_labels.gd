extends GutTest
# WorldLabels 的条目可能指向已释放的控件(对话气泡淡出后自行释放),查找/替换/清理都不能报错。
# 让位:对面的人铭牌贴着画面上缘时,声称气泡和九宫格气泡都被收进画面、原来会叠在同一处(2026-10-10 试玩);
# 登记时 avoid = true 的气泡要左右让开,铭牌不动。


var labels: WorldLabels


func before_each():
	labels = WorldLabels.new(null)
	add_child_autofree(labels)


func _anchor() -> Vector3:
	return Vector3.ZERO


func test_retracking_a_key_after_its_node_freed_itself():
	# 气泡已自行释放、_process 还没清掉旧条目时,同一个人又说了一句话
	var first := Label.new()
	labels.track("bubble:2", first, _anchor)
	first.free()
	var second := Label.new()
	labels.track("bubble:2", second, _anchor)
	assert_eq(labels.get_node_for("bubble:2"), second)


func test_lookup_of_a_freed_node_returns_null():
	var node := Label.new()
	labels.track("plate:3", node, _anchor)
	node.free()
	assert_null(labels.get_node_for("plate:3"))


func test_untrack_and_clear_skip_freed_nodes():
	var gone := Label.new()
	var kept := Label.new()
	labels.track("bubble:2", gone, _anchor)
	labels.track("plate:2", kept, _anchor)
	gone.free()
	labels.untrack("bubble:2")
	assert_null(labels.get_node_for("bubble:2"))
	labels.clear()
	assert_null(labels.get_node_for("plate:2"))
	assert_true(kept.is_queued_for_deletion())


func test_process_drops_entries_whose_node_is_gone():
	var node := Label.new()
	labels.track("bubble:4", node, _anchor)
	node.free()
	labels._process(0.016)
	assert_false(labels._entries.has("bubble:4"))


func test_untrack_leaves_other_screens_keys_alone():
	# 牌桌退场只收自己的铭牌,不能连带等待厅刚挂好的铭牌
	var lobby_plate := Label.new()
	var table_plate := Label.new()
	labels.track("lobby:1", lobby_plate, _anchor)
	labels.track("plate:1", table_plate, _anchor)
	labels.untrack("plate:1")
	assert_eq(labels.get_node_for("lobby:1"), lobby_plate)
	assert_null(labels.get_node_for("plate:1"))


# —— 让位 ——

const AREA := Vector2(1600, 900)

func test_clear_spot_keeps_a_free_rect_where_it_is():
	var rect := Rect2(100, 10, 80, 40)
	assert_eq(WorldLabels.clear_spot(rect, [Rect2(300, 10, 80, 40)], AREA), rect)


func test_clear_spot_moves_sideways_by_the_smallest_shift():
	var obstacle := Rect2(100, 10, 100, 40)
	var moved := WorldLabels.clear_spot(Rect2(130, 20, 60, 40), [obstacle], AREA)
	assert_false(moved.intersects(obstacle))
	assert_eq(moved.position.y, 20.0, "只横着挪")
	assert_eq(moved.position.x, obstacle.end.x + WorldLabels.AVOID_GAP, "往右挪 74 比往左挪 94 近")


func test_clear_spot_stays_on_screen_and_skips_crowded_sides():
	# 左边贴着画面边缘放不下,右边紧挨着又有一个:挪到两个都让开的地方
	var a := Rect2(10, 10, 100, 40)
	var b := Rect2(114, 10, 100, 40)
	var moved := WorldLabels.clear_spot(Rect2(20, 10, 60, 40), [a, b], AREA)
	assert_false(moved.intersects(a) or moved.intersects(b))
	assert_gte(moved.position.x, WorldLabels.EDGE_MARGIN)


func test_clear_spot_gives_up_when_there_is_no_room():
	var wall := Rect2(0, 0, 400, 300)
	var rect := Rect2(100, 10, 60, 40)
	assert_eq(WorldLabels.clear_spot(rect, [wall], Vector2(400, 300)), rect, "整块都被占了:留在原处")


func test_clear_spot_without_sideways_only_moves_down():
	# 铭牌:被右上按钮行盖住时往下挪到按钮下面,不横着挪
	var buttons := Rect2(1190, 24, 380, 52)
	var plate := WorldLabels.clear_spot(Rect2(1300, 4, 220, 60), [buttons], AREA, false)
	assert_eq(plate.position.x, 1300.0)
	assert_eq(plate.position.y, buttons.end.y + WorldLabels.AVOID_GAP)


func test_bubbles_clamped_to_the_top_edge_move_apart_but_plates_stay():
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.position = Vector3(0, 0, 3)
	var layer := WorldLabels.new(camera)
	add_child_autofree(layer)
	await wait_process_frames(1)
	# 挂点在画面最上面:往上偏的两个气泡都被收到上缘,原来叠在一起
	var top := camera.project_position(Vector2(layer.size.x * 0.5, 40.0), 3.0)
	var anchor := func(): return top
	var plate := Label.new()
	plate.text = "铭牌"
	plate.custom_minimum_size = Vector2(150, 50)
	layer.track("plate", plate, anchor)
	var claim := Label.new()
	claim.custom_minimum_size = Vector2(90, 44)
	layer.track("claim", claim, anchor, Vector2(0, -66), true)
	var quip := Label.new()
	quip.custom_minimum_size = Vector2(120, 44)
	layer.track("quip", quip, anchor, Vector2(0, -140), true)
	await wait_process_frames(2)
	var plate_rect := Rect2(plate.position, plate.size)
	var claim_rect := Rect2(claim.position, claim.size)
	var quip_rect := Rect2(quip.position, quip.size)
	assert_false(claim_rect.intersects(quip_rect), "声称气泡 %s 与九宫格气泡 %s 不重叠" % [claim_rect, quip_rect])
	assert_false(claim_rect.intersects(plate_rect))
	assert_false(quip_rect.intersects(plate_rect))
	var center_x := layer.size.x * 0.5
	assert_almost_eq(plate_rect.get_center().x, center_x, 1.0, "铭牌不让位,还在挂点正上方")


func test_bubbles_keep_out_of_hud_corner_panels():
	# 左上信息面板在 KEEP_OUT_GROUP 里:被收到画面左上角的气泡挪到它右边,不盖住目标牌 / 底池
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.position = Vector3(0, 0, 3)
	var layer := WorldLabels.new(camera)
	add_child_autofree(layer)
	var hud := Panel.new()
	hud.position = Vector2(20, 16)
	hud.size = Vector2(300, 120)
	hud.add_to_group(WorldLabels.KEEP_OUT_GROUP)
	add_child_autofree(hud)
	await wait_process_frames(1)
	var corner := camera.project_position(Vector2(60.0, 60.0), 3.0)
	var bubble := Label.new()
	bubble.custom_minimum_size = Vector2(120, 44)
	layer.track("bubble", bubble, func(): return corner, Vector2(0, -20), true)
	await wait_process_frames(2)
	var rect := Rect2(bubble.position, bubble.size)
	assert_false(rect.intersects(Rect2(hud.position, hud.size)), "气泡 %s 让开 HUD 面板" % rect)
	hud.visible = false
	await wait_process_frames(2)
	assert_lt(bubble.position.x, 60.0, "面板藏起来以后不再让")
