extends GutTest
# RoomLayout(纯数据与纯函数):墙段切分、面板拟合、梁端支撑、壁炉砌块网格、墙饰摆放、特写背景、
# 越肩机位下的头部剪影、镜头净空、月亮在外景板上的位置。

const PITCH := 0.62


func test_wainscot_segments_stay_inside_the_wall_and_do_not_overlap():
	var limit := RoomLayout.CORNER_POST_CENTER - RoomLayout.CORNER_POST / 2.0
	for wall in ["back", "front", "left", "right"]:
		var segs: Array = RoomLayout.wainscot_segments(wall)
		assert_gt(segs.size(), 0, wall)
		var last := -INF
		for seg in segs:
			assert_lt(seg[0], seg[1], "%s 墙段 %s 方向正确" % [wall, seg])
			assert_gte(seg[0], -limit - 1e-6, wall)
			assert_lte(seg[1], limit + 1e-6, wall)
			assert_gte(seg[0], last - 1e-6, "%s 墙段互不重叠" % wall)
			last = seg[1]


func test_segments_leave_room_for_door_window_fireplace_backbar_and_posts():
	var front: Array = RoomLayout.wainscot_segments("front")
	for seg in front:
		assert_false(seg[0] < RoomLayout.DOOR_X1 and seg[1] > RoomLayout.DOOR_X0, "门洞处没有护墙板")
	var back: Array = RoomLayout.wainscot_segments("back")
	for seg in back:
		assert_false(seg[0] < -0.38 and seg[1] > RoomLayout.FIRE_GRID_ORIGIN.x, "壁炉后面没有护墙板")
	var left: Array = RoomLayout.wainscot_segments("left")
	for seg in left:
		assert_false(seg[0] < RoomLayout.BACKBAR_Z.y and seg[1] > RoomLayout.BACKBAR_Z.x, "后吧段没有护墙板")
	for wall in ["left", "right"]:
		for post in RoomLayout.WALL_POSTS[wall]:
			for seg in RoomLayout.wainscot_segments(wall):
				assert_false(seg[0] < post and seg[1] > post, "%s 墙柱 %s 处断开" % [wall, post])


func test_panel_fit_gives_whole_panels_closest_to_the_target_pitch():
	for wall in ["back", "front", "left", "right"]:
		for seg in RoomLayout.wainscot_segments(wall):
			var length: float = seg[1] - seg[0]
			var pitch := RoomLayout.panel_fit(length, PITCH)
			var n := roundi(length / pitch)
			assert_gte(n, 1)
			assert_almost_eq(n * pitch, length, 1e-5, "整数块")
			for other in [n - 1, n + 1]:
				if other >= 1:
					assert_lte(absf(pitch - PITCH), absf(length / other - PITCH) + 1e-6, "%s 墙段 %.2f m 取了最接近的块数" % [wall, length])
			# 短墙段(后吧与墙柱之间 0.38 m、窗下两道窗套之间 1.5 m)块数太少,只能取最接近的;够 2.5 个节距的墙段拉伸 ≤ 15%
			if length >= PITCH * 2.5:
				assert_lte(absf(pitch - PITCH) / PITCH, 0.15, "%s 长墙段拉伸 ≤ 15%%" % wall)


func test_only_four_beam_ends_get_posts():
	var posts := []
	for end in RoomLayout.beam_ends():
		if RoomLayout.beam_support(end[0], end[1]) == RoomLayout.POST:
			posts.append("%s %.1f" % [end[0], end[1]])
	assert_eq(RoomLayout.beam_ends().size(), 10)
	assert_eq(posts, ["left 1.5", "left 3.0", "right -3.0", "right 3.0"])


func test_fireplace_boxes_sit_on_the_half_block_grid():
	var o := RoomLayout.FIRE_GRID_ORIGIN
	for id in RoomLayout.FIRE_BOXES:
		var box: Array = RoomLayout.FIRE_BOXES[id]
		for corner in [box[0], box[1]]:
			var gx: float = (corner.x - o.x) / RoomLayout.FIRE_HALF
			var gz: float = (corner.z - o.z) / RoomLayout.FIRE_HALF
			var gy: float = corner.y / RoomLayout.FIRE_COURSE
			assert_almost_eq(gx, roundf(gx), 1e-4, "%s x 在 0.16 网格上" % id)
			assert_almost_eq(gz, roundf(gz), 1e-4, "%s z 在 0.16 网格上" % id)
			assert_almost_eq(gy, roundf(gy), 1e-4, "%s y 在 0.2 网格上" % id)
	var hearth: Array = RoomLayout.HEARTH
	assert_lt(hearth[1].y - hearth[0].y, RoomLayout.FIRE_COURSE, "炉床石板整块落在一层砖内")
	assert_almost_eq(RoomLayout.FIRE_BACK_Z, -4.24, 1e-6)
	assert_almost_eq(RoomLayout.FIRE_BOXES["breast"][1].y, Tavern.ROOM_HEIGHT, 1e-6, "烟囱腔顶在天花板")


func _decor_rect(item: Dictionary) -> Rect2:
	var size: Vector2 = item["size"]
	return Rect2(Vector2(item["u"], item["y"]) - size / 2.0, size)


func _feature_rect(f: Dictionary) -> Rect2:
	return Rect2(Vector2(f["u"] - f["width"] / 2.0, f["y0"]), Vector2(f["width"], f["y1"] - f["y0"]))


func test_wall_decor_avoids_sconces_openings_posts_and_each_other():
	var limit := RoomLayout.CORNER_POST_CENTER - RoomLayout.CORNER_POST / 2.0
	var items: Array = RoomLayout.DECOR
	for i in items.size():
		var item: Dictionary = items[i]
		var r := _decor_rect(item)
		var wall: String = item["wall"]
		assert_true(r.position.x >= -limit and r.end.x <= limit, "%s 在墙面范围内" % item["id"])
		assert_true(r.position.y > RoomLayout.RAIL_TOP and r.end.y < RoomLayout.CROWN_BOTTOM, "%s 在压条与顶线之间" % item["id"])
		for sconce in Tavern.SCONCES:
			var p: Vector3 = sconce[0]
			var on_wall := RoomLayout.wall_hit(Vector3(0, p.y, 0), Vector3(p.x, 0, p.z))
			if on_wall.get("wall", "") != wall:
				continue
			var u: float = p.x if wall in ["back", "front"] else p.z
			assert_true(r.end.x <= u - 0.3 or r.position.x >= u + 0.3, "%s 避开壁灯 ±0.3 m" % item["id"])
		for id in RoomLayout.WALL_FEATURES:
			var f: Dictionary = RoomLayout.WALL_FEATURES[id]
			if f["wall"] == wall and id != "fireplace":
				assert_false(r.intersects(_feature_rect(f)), "%s 不压 %s" % [item["id"], id])
		for post in RoomLayout.WALL_POSTS.get(wall, []):
			assert_true(r.end.x <= post - RoomLayout.WALL_POST.x / 2.0 or r.position.x >= post + RoomLayout.WALL_POST.x / 2.0,
				"%s 不压墙柱" % item["id"])
		for j in range(i + 1, items.size()):
			if items[j]["wall"] == wall:
				assert_false(r.intersects(_decor_rect(items[j])), "%s 与 %s 不重叠" % [item["id"], items[j]["id"]])


func test_flat_decor_sits_a_few_millimetres_off_the_wall():
	assert_between(RoomLayout.FLAT_OFFSET, 0.003, 0.015)
	for item in RoomLayout.DECOR:
		assert_lte(float(item.get("curl", 0.0)), 0.025, "%s 卷边 ≤ 25 mm" % item["id"])


func test_every_focus_close_up_has_decor_beside_the_head():
	for angle in [0.0, PI / 2.0, PI, PI * 1.5, TAU / 3.0, TAU * 2.0 / 3.0]:
		var hit := RoomLayout.focus_backdrop(angle)
		assert_false(hit.is_empty(), "角度 %.2f 有背景墙" % angle)
		var found := []
		for item in RoomLayout.DECOR:
			if item["wall"] == hit["wall"] and absf(item["u"] - hit["u"]) >= 0.75 and absf(item["u"] - hit["u"]) <= 2.4:
				found.append(item["id"])
		for id in RoomLayout.WALL_FEATURES:
			var f: Dictionary = RoomLayout.WALL_FEATURES[id]
			if f["wall"] == hit["wall"] and absf(f["u"] - hit["u"]) >= 0.75 and absf(f["u"] - hit["u"]) <= 2.4:
				found.append(id)
		assert_gt(found.size(), 0, "角度 %.2f 的特写(%s 墙 u=%.2f)头旁边有陈设" % [angle, hit["wall"], hit["u"]])


func test_opponent_heads_and_hats_never_overlap_high_wall_decor_from_the_seat_camera():
	# 越肩机位(本机座位 0°)把对手的头(r 0.17,座位外移 0.10 m、高 1.27 m)和帽(帽檐 r 0.25,在头心 +0.15)
	# 投到墙上,不与 y ≥ 1.35 的墙饰重叠,留 0.10 m 余量
	var camera := Vector3(TableWorld.THIRD_PERSON_SIDE, TableWorld.THIRD_PERSON_HEIGHT,
		SeatLayout.SEAT_RADIUS + TableWorld.THIRD_PERSON_BEHIND)
	for count in [2, 3, 4]:
		for seat in range(1, count):
			var angle := SeatLayout.seat_angle(seat, 0, count)
			var head := SeatLayout.direction(angle) * (SeatLayout.SEAT_RADIUS + 0.10) + Vector3(0, 1.27, 0)
			for blob in [[head, 0.17], [head + Vector3(0, 0.15, 0), 0.25]]:
				var center: Vector3 = blob[0]
				var hit := RoomLayout.wall_hit(camera, center - camera)
				if hit.is_empty() or hit["y"] <= 0.0:
					continue   # 先落到地板上
				var radius: float = blob[1] * hit["t"] / camera.distance_to(center)
				for item in RoomLayout.DECOR:
					var r := _decor_rect(item)
					if item["wall"] != hit["wall"] or r.position.y < 1.35:
						continue
					var q := Vector2(clampf(hit["u"], r.position.x, r.end.x), clampf(hit["y"], r.position.y, r.end.y))
					var gap := q.distance_to(Vector2(hit["u"], hit["y"])) - radius
					assert_gte(gap, 0.10, "%d 人局座位 %d 的剪影离 %s 至少 0.10 m" % [count, seat, item["id"]])


func test_no_placement_comes_within_30cm_of_any_camera_path():
	assert_eq(RoomLayout.clearance_violations(0.3), [])


func test_moon_sits_where_the_moonbeam_points_on_the_backdrop():
	var uv := RoomLayout.moon_uv()
	assert_almost_eq(uv.x, 0.516, 0.005)
	assert_almost_eq(uv.y, 0.292, 0.005)


func test_rug_sizes_feed_the_decor_shader():
	# 2026-10-10 地毯重做:圆形主毯 + 条纹长毯 + 门口小毯;rug_sizes = (半宽, 半长, 包边 / 流苏宽, 款式)
	var sizes := RoomLayout.rug_sizes()
	assert_eq(sizes.size(), 3, "decor 着色器 rug_sizes[3]")
	assert_almost_eq(sizes[0].x, 1.75, 1e-5, "主毯半径 1.75 m")
	assert_almost_eq(sizes[0].y, sizes[0].x, 1e-5, "主毯是圆的")
	assert_almost_eq(sizes[1].x, 0.31, 1e-5, "吧台长条毯横宽 0.62 m")
	assert_eq(sizes[1].w, 1.0, "1 号是条纹长毯")
	assert_eq(RoomLayout.RUGS[0][0], Vector2.ZERO, "主毯圆心在原点(着色器绕原点放大)")


func test_main_rug_grows_with_the_table_and_stays_off_the_runner():
	# 小桌:椅子(座位 + 30 cm)整个落在毯上;德州 / 炸弹猫大桌同理,且放大后不压到吧台长条毯、不碰炉床
	for table_radius in [SeatLayout.TABLE_RADIUS, SeatLayout.POKER_TABLE_RADIUS]:
		var radius := RoomLayout.RUG_MAIN_RADIUS * RoomLayout.main_rug_scale(table_radius)
		assert_gt(radius, SeatLayout.seat_radius_for(table_radius) + 0.3, "椅背落在毯上")
		var runner: Array = RoomLayout.RUGS[1]
		assert_lt(radius, -(runner[0].x + runner[1] / 2.0), "不压吧台长条毯")
		assert_lt(radius, -RoomLayout.HEARTH[1].z, "不碰炉床")
	assert_almost_eq(RoomLayout.main_rug_scale(SeatLayout.TABLE_RADIUS), 1.0, 1e-6)


func test_door_mat_sits_inside_the_door_clear_of_the_piano_and_main_rug():
	var mat: Array = RoomLayout.RUGS[2]
	var c: Vector2 = mat[0]
	assert_lt(c.y + mat[2] / 2.0, RoomLayout.prop_aabb("door").position.z, "门口小毯在门里")
	assert_gt(c.x - mat[1] / 2.0, RoomLayout.prop_aabb("piano_bench").end.x, "不钻到琴凳下")
	assert_gt(c.y - mat[2] / 2.0, RoomLayout.RUG_MAIN_RADIUS * RoomLayout.main_rug_scale(SeatLayout.POKER_TABLE_RADIUS) + 0.5,
		"和放大后的主毯之间也留着一段地板")
