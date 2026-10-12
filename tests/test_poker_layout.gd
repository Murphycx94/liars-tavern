extends GutTest
# 德州牌桌的摆放数学(纯函数):
# - 8 个座位的筹码堆、下注、庄家按钮、亮牌都在桌面内(离桌心 < 桌面半径 − 5 厘米),骗子酒馆桌与德州桌都成立;
# - 满桌时公共牌、底池、筹码堆、按钮、亮牌、弃牌堆互不重叠(下注与亮牌不同时出现:亮牌前下注已收进底池);
# - 公共牌立在牌架上向本机倾斜 35°,桌上的牌按本机视角正立;自己的牌扇正对越肩镜头。


const RADII := [SeatLayout.TABLE_RADIUS, SeatLayout.POKER_TABLE_RADIUS]
const EDGE_CLEARANCE := 0.05   # 规格:离桌心 < 桌面半径 − 5 厘米
const SEATS := 8
const MAX_POTS := 7            # 8 人全下额度各不相同时最多 7 个底池
const BOARD_REACH := 0.6       # 公共牌都在桌心 0.6 米以内
const BOARD_PIXELS := Vector2(36.0, 44.0)   # 规格 §5.3:越肩机位下约 41×50 像素,留些余量
const OVER_SHOULDER := Vector3(0.55, 1.92, 2.6)   # 德州越肩机位(规格 §5.5)
const CAMERA_TARGET := Vector3(0, 0.78, -0.12)
const FOV_DEG := 66.0          # CameraRig 的竖直视角
const SCREEN_HEIGHT := 720.0


func _angles() -> Array:
	return range(SEATS).map(func(i): return SeatLayout.seat_angle(i, 0, SEATS))


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _card_corners(xform: Transform3D) -> Array:
	var w := Card3D.WIDTH / 2.0
	var h := Card3D.HEIGHT / 2.0
	return [Vector3(-w, 0, -h), Vector3(w, 0, -h), Vector3(w, 0, h), Vector3(-w, 0, h)].map(
		func(c: Vector3) -> Vector3: return xform * c)


func _card_rect(xform: Transform3D) -> Rect2:
	# 牌在桌面上的俯视占地(XZ 包围盒)
	var corners := _card_corners(xform)
	var rect := Rect2(Vector2(corners[0].x, corners[0].z), Vector2.ZERO)
	for c in corners:
		rect = rect.expand(Vector2(c.x, c.z))
	return rect


func _circle_rect(center: Vector3, radius: float) -> Rect2:
	return Rect2(center.x - radius, center.z - radius, radius * 2.0, radius * 2.0)


# —— 都在桌面内 ——

func test_seat_items_stay_on_the_table_for_eight_seats():
	var chip_reach := ChipStack3D.footprint_radius()
	for r in RADII:
		var limit: float = r - EDGE_CLEARANCE
		for a in _angles():
			var label := "r=%.2f 角度 %.0f°" % [r, rad_to_deg(a)]
			assert_lt(_flat(PokerLayout.stack_position(a, r)) + chip_reach, limit, "筹码堆 " + label)
			assert_lt(_flat(PokerLayout.bet_position(a, r)) + chip_reach, limit, "下注 " + label)
			assert_lt(_flat(PokerLayout.button_position(a, r)) + DealerButton3D.RADIUS, limit, "按钮 " + label)
			for i in PokerRules.HOLE_CARDS:
				for corner in _card_corners(PokerLayout.shown_card(a, r, i)):
					assert_lt(_flat(corner), limit, "亮牌 " + label)


func test_items_lie_on_the_table_top():
	for r in RADII:
		for a in _angles():
			assert_almost_eq(PokerLayout.stack_position(a, r).y, SeatLayout.TABLE_TOP, 0.0001)
			assert_almost_eq(PokerLayout.bet_position(a, r).y, SeatLayout.TABLE_TOP, 0.0001)
			assert_almost_eq(PokerLayout.button_position(a, r).y, SeatLayout.TABLE_TOP, 0.0001)
			assert_gt(PokerLayout.shown_card(a, r, 0).origin.y, SeatLayout.TABLE_TOP, "亮牌浮在台面上方一点")


func test_neighbouring_stacks_keep_apart():
	for r in RADII:
		var angles := _angles()
		for i in SEATS:
			var a := PokerLayout.stack_position(angles[i], r)
			var b := PokerLayout.stack_position(angles[(i + 1) % SEATS], r)
			assert_gt(a.distance_to(b), 4.0 * ChipStack3D.CHIP_RADIUS)
			assert_gt(a.distance_to(b), 2.0 * ChipStack3D.footprint_radius(), "两摞最宽时也不相碰")


func test_stack_sits_to_the_right_hand_and_bet_nearer_the_centre():
	var r := SeatLayout.POKER_TABLE_RADIUS
	for a in _angles():
		var seat_right := PokerLayout.facing(a).x
		var stack := PokerLayout.stack_position(a, r)
		assert_gt(stack.dot(seat_right), 0.0, "筹码堆在右手边")
		assert_lt(_flat(PokerLayout.bet_position(a, r)), _flat(stack), "下注比筹码堆更靠桌心")


# —— 公共牌与底池 ——

func test_board_slots_do_not_overlap_and_stay_near_the_centre():
	var rects := []
	for i in PokerRules.BOARD_CARDS:
		var slot := PokerLayout.board_slot(i)
		for corner in _card_corners(slot):
			assert_lt(_flat(corner), BOARD_REACH, "第 %d 张" % i)
		var rect := _card_rect(slot)
		for other in rects:
			assert_false(rect.intersects(other), "第 %d 张与前面的牌重叠" % i)
		rects.append(rect)


func test_board_cards_are_enlarged_and_tilted_toward_the_local_camera():
	for i in PokerRules.BOARD_CARDS:
		var basis := PokerLayout.board_slot(i).basis
		assert_almost_eq(basis.get_scale(), Vector3.ONE * PokerLayout.BOARD_SCALE, Vector3.ONE * 0.0001)
		var normal := basis.y.normalized()
		assert_almost_eq(rad_to_deg(normal.angle_to(Vector3.UP)), PokerLayout.BOARD_TILT_DEG, 0.01)
		assert_gt(normal.z, 0.0, "牌面朝本机一侧(+Z)倾斜")
		assert_almost_eq(normal.x, 0.0, 0.0001)


func test_board_cards_rest_on_the_rack_above_the_table():
	for i in PokerRules.BOARD_CARDS:
		for corner in _card_corners(PokerLayout.board_slot(i)):
			assert_gt(corner.y, SeatLayout.TABLE_TOP, "第 %d 张没有插进桌面" % i)


func test_board_reads_about_forty_pixels_wide_from_the_seat():
	# 规格 §5.3:1280×720 下从自己座位看,牌架上的公共牌约 41×50 像素
	var forward := (CAMERA_TARGET - OVER_SHOULDER).normalized()
	var slot := PokerLayout.board_slot(2)
	var depth := (slot.origin - OVER_SHOULDER).dot(forward)
	var pixels_per_metre := SCREEN_HEIGHT / (2.0 * depth * tan(deg_to_rad(FOV_DEG / 2.0)))
	var width := Card3D.WIDTH * PokerLayout.BOARD_SCALE * pixels_per_metre
	var facing := absf(slot.basis.y.normalized().dot(forward))
	var height := Card3D.HEIGHT * PokerLayout.BOARD_SCALE * facing * pixels_per_metre
	assert_gt(width, BOARD_PIXELS.x)
	assert_gt(height, BOARD_PIXELS.y)


func test_pots_sit_on_the_near_side_of_the_board_without_covering_it():
	var reach := ChipStack3D.footprint_radius()
	var board := []
	for i in PokerRules.BOARD_CARDS:
		board.append(_card_rect(PokerLayout.board_slot(i)))
	for count in range(1, MAX_POTS + 1):
		var pots := []
		for i in count:
			var p := PokerLayout.pot_position(i, count)
			var rect := _circle_rect(p, reach)
			assert_almost_eq(p.y, SeatLayout.TABLE_TOP, 0.0001)
			for card in board:
				assert_false(rect.intersects(card), "%d 个底池时第 %d 个压到公共牌" % [count, i])
				assert_gt(rect.position.y, card.end.y, "底池在公共牌靠本机一侧")
			for other in pots:
				assert_false(rect.intersects(other), "%d 个底池时第 %d 个与旁边的重叠" % [count, i])
			assert_lt(_flat(p) + reach, SeatLayout.POKER_TABLE_RADIUS - EDGE_CLEARANCE)
			pots.append(rect)


# —— 满桌不打架 ——

func test_nothing_overlaps_on_a_full_poker_table():
	var r := SeatLayout.POKER_TABLE_RADIUS
	var reach := ChipStack3D.footprint_radius()
	var items := []   # [名字, Rect2, 类别]
	for i in PokerRules.BOARD_CARDS:
		items.append(["公共牌%d" % i, _card_rect(PokerLayout.board_slot(i)), "board"])
	for i in MAX_POTS:
		items.append(["底池%d" % i, _circle_rect(PokerLayout.pot_position(i, MAX_POTS), reach), "pot"])
	items.append(["弃牌堆", _circle_rect(PokerLayout.muck_position(), PokerLayout.muck_radius()), "muck"])
	for a in _angles():
		var seat := "%.0f°" % rad_to_deg(a)
		items.append(["筹码堆" + seat, _circle_rect(PokerLayout.stack_position(a, r), reach), "stack"])
		items.append(["下注" + seat, _circle_rect(PokerLayout.bet_position(a, r), reach), "bet"])
		items.append(["按钮" + seat, _circle_rect(PokerLayout.button_position(a, r), DealerButton3D.RADIUS), "button"])
		for i in PokerRules.HOLE_CARDS:
			items.append(["亮牌%s/%d" % [seat, i], _card_rect(PokerLayout.shown_card(a, r, i)), "shown"])
	for i in items.size():
		for j in range(i + 1, items.size()):
			var kinds := [items[i][2], items[j][2]]
			if kinds.has("bet") and kinds.has("shown"):
				continue   # 亮牌之前下注已收进底池,两者不会同时在桌上
			assert_false(items[i][1].intersects(items[j][1]), "%s 与 %s 重叠" % [items[i][0], items[j][0]])


# —— 朝向 ——

func test_cards_on_the_table_read_upright_from_the_local_seat():
	# 每个客户端都把自己的座位放在 +Z:牌顶(牌的本地 −Z)朝 −Z,不按座位径向摆
	for i in PokerRules.BOARD_CARDS:
		var top := (PokerLayout.board_slot(i).basis * Vector3.FORWARD).normalized()
		assert_lt(top.z, 0.0)
		assert_almost_eq(top.x, 0.0, 0.0001)
	for a in _angles():
		for i in PokerRules.HOLE_CARDS:
			var basis := PokerLayout.shown_card(a, SeatLayout.POKER_TABLE_RADIUS, i).basis
			assert_almost_eq((basis * Vector3.FORWARD).normalized(), Vector3.FORWARD, Vector3.ONE * 0.0001)
			assert_almost_eq(basis.y.normalized(), Vector3.UP, Vector3.ONE * 0.0001, "牌面朝上")
			assert_almost_eq(basis.get_scale(), Vector3.ONE * PokerLayout.SHOWN_SCALE, Vector3.ONE * 0.0001)


func test_shown_pair_reads_left_to_right():
	for a in _angles():
		var first := PokerLayout.shown_card(a, SeatLayout.POKER_TABLE_RADIUS, 0).origin
		var second := PokerLayout.shown_card(a, SeatLayout.POKER_TABLE_RADIUS, 1).origin
		assert_lt(first.x, second.x)
		assert_almost_eq(first.z, second.z, 0.0001)


func test_muck_and_deck_lie_behind_the_board():
	var board_back := INF
	for i in PokerRules.BOARD_CARDS:
		board_back = minf(board_back, _card_rect(PokerLayout.board_slot(i)).position.y)
	assert_lt(PokerLayout.muck_position().z + PokerLayout.muck_radius(), board_back)
	assert_lt(PokerLayout.deck_position().z, board_back)
	var half_diagonal := Vector2(Card3D.WIDTH, Card3D.HEIGHT).length() / 2.0
	for i in SEATS * PokerRules.HOLE_CARDS:
		var slot := PokerLayout.muck_slot(i)
		var off := slot.origin - PokerLayout.muck_position()
		assert_lte(Vector2(off.x, off.z).length() + half_diagonal, PokerLayout.muck_radius() + 0.0001,
			"第 %d 张弃牌落在弃牌堆范围内" % i)
		assert_gt(slot.origin.y, SeatLayout.TABLE_TOP, "弃牌叠在台面上")
		assert_lt(slot.basis.y.y, 0.0, "弃牌牌面朝下")


# —— 自己的牌扇 ——

func test_poker_fan_is_raised_to_the_spec_spot():
	# 规格 §5.3 的位置是 (0.30, 0.74, -0.30);动森式大头(半宽 ≈0.32 m)会整个挡住它,挪到大头右前方
	# (遮挡由 test_hand_visibility 的德州底牌用例按三角形实测)
	assert_eq(PokerLayout.poker_fan_offset(), Vector3(0.48, 0.72, -0.36))


func test_own_fan_faces_the_over_shoulder_camera():
	var seat := Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), Vector3(0, 0, 1.75))
	var fan_local := PokerLayout.fan_transform(seat, OVER_SHOULDER)
	var body := Patron.figure_transform(Patron.FIGURE_SCALE) * Transform3D(Basis(Vector3.RIGHT, -Patron.SEATED_LEAN), Patron.HIP)
	var fan := seat * body * fan_local
	var in_seat := seat.affine_inverse() * fan.origin
	assert_almost_eq(in_seat, Patron.HIP + PokerLayout.poker_fan_offset(), Vector3.ONE * 0.0001)
	var normal := fan.basis.y.normalized()
	assert_gt(normal.dot((OVER_SHOULDER - fan.origin).normalized()), 0.9999, "牌面正对镜头")
	assert_lt(fan.basis.z.normalized().y, 0.0, "牌顶朝上")
	assert_almost_eq(fan.basis.get_scale(), Vector3.ONE * Patron.SELF_FAN_SCALE, Vector3.ONE * 0.0001)
