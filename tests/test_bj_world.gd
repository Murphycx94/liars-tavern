extends GutTest
# 21 点牌桌的摆放(BjLayout)与 3D 层(BjCards / BjChips / BjShoeProp):7 人桌、每人最多 4 手、每手 6 张时,
# 牌和下注都在桌面上、不压到桌心的庄家牌架、相邻座位的牌不打架;本机自己的牌往右手边挪后仍在桌面上;
# 对账按视图摆出对的牌与筹码,暗牌是背面;牌鞋与弃牌盘登记了穿模防护。


const H := preload("res://tests/poker_helpers.gd")
const R := preload("res://src/core/blackjack/bj_rules.gd")
const RADIUS := SeatLayout.POKER_TABLE_RADIUS
const CARD_HALF_DIAG := 0.106   # Card3D 放大 HAND_SCALE 后的半对角线(约)


func _rack_rect() -> Rect2:
	# 庄家牌架的俯视占地(x 横向,y 是 z)
	var depth := Card3D.HEIGHT * PokerLayout.BOARD_SCALE * cos(deg_to_rad(PokerLayout.BOARD_TILT_DEG))
	var half := PokerLayout.board_width() / 2.0 + BoardRack.MARGIN
	return Rect2(-half, PokerLayout.board_front_z() - depth - BoardRack.MARGIN, half * 2.0, depth + BoardRack.MARGIN * 2.0)


func test_every_card_and_bet_stays_on_the_felt_and_off_the_rack():
	var rack := _rack_rect()
	for seats in range(1, R.MAX_SEATS + 1):
		for seat in seats:
			var angle := SeatLayout.seat_angle(seat, 0, seats)
			for count in range(1, R.MAX_HANDS + 1):
				for hand in count:
					for mine in [false, true]:
						if mine and seat != 0:
							continue
						for index in 6:
							var pos := BjLayout.card_slot(angle, RADIUS, hand, count, index, false, mine).origin
							var flat := Vector2(pos.x, pos.z)
							assert_lt(flat.length() + CARD_HALF_DIAG, RADIUS, "%d 人桌 %d 号 %d/%d 手第 %d 张在桌面上" % [seats, seat, hand, count, index])
							assert_false(rack.grow(-0.01).has_point(flat), "不压庄家牌架")
						var bet := BjLayout.bet_position(angle, RADIUS, hand, count, mine)
						assert_lt(Vector2(bet.x, bet.z).length() + ChipStack3D.footprint_radius(), RADIUS, "下注在桌面上")
			var stack := BjLayout.stack_position(angle, RADIUS, seat == 0)
			assert_lt(Vector2(stack.x, stack.z).length() + ChipStack3D.footprint_radius(), RADIUS, "筹码堆在桌面上")


func test_neighbours_single_hands_do_not_touch():
	var seats := R.MAX_SEATS
	for seat in seats:
		var a := BjLayout.hand_center(SeatLayout.seat_angle(seat, 0, seats), RADIUS, 0, 1)
		var b := BjLayout.hand_center(SeatLayout.seat_angle((seat + 1) % seats, 0, seats), RADIUS, 0, 1)
		assert_gt(Vector2(a.x - b.x, a.z - b.z).length(), 2.0 * CARD_HALF_DIAG + 0.1, "相邻两家的牌有间隔")


func test_my_cards_move_to_my_right():
	var mine := BjLayout.hand_center(0.0, RADIUS, 0, 1, true)
	var theirs := BjLayout.hand_center(0.0, RADIUS, 0, 1)
	assert_almost_eq(mine.x - theirs.x, BjLayout.MY_SIDE, 0.001, "本机座位在 +Z,右手是 +X")
	assert_almost_eq(mine.z, theirs.z, 0.001)


func test_dealer_cards_squeeze_but_stay_on_the_rack():
	for count in range(1, 12):
		var first := BjLayout.dealer_slot(0, count).origin
		var last := BjLayout.dealer_slot(count - 1, count).origin
		assert_lte(last.x - first.x + Card3D.WIDTH * PokerLayout.BOARD_SCALE, PokerLayout.board_width() + 0.001, "%d 张" % count)
		assert_almost_eq(first.x, -last.x, 0.001, "居中")


func test_table_layers_follow_the_view():
	var world := TableWorld.new(null)
	add_child_autofree(world)
	world.configure_table(RADIUS)
	world.arrange([{"pid": 1}, {"pid": 2}, {"pid": 3}], 1, true, false)
	var cards := BjCards.new(world)
	var chips := BjChips.new(world)
	world.poker_root.add_child(cards)
	world.poker_root.add_child(chips)
	assert_true(world.clip_guard.has_prop(&"bj_shoe"))
	assert_true(world.clip_guard.has_prop(&"bj_discard"))
	var players := [
		{"pid": 1, "stack": 1700, "bet": 0, "left": false, "hands": [
			{"cards": H.cards("8s 3h Kd"), "bet": 200, "outcome": "", "doubled": true},
			{"cards": H.cards("8d 9c"), "bet": 100, "outcome": ""}]},
		{"pid": 2, "stack": 1900, "bet": 100, "left": false, "hands": []},
		{"pid": 3, "stack": 2000, "bet": 0, "left": false, "hands": [{"cards": H.cards("Ts 6c"), "bet": 50, "surrendered": true}]},
	]
	cards.sync(players, {"cards": H.cards("Th"), "hidden": true})
	chips.sync(players)
	assert_eq(cards.dealer_kinds(), [H.card("Th"), CardFaces.BACK], "暗牌是背面")
	assert_eq(cards.hand_kinds(1), [H.cards("8s 3h Kd"), H.cards("8d 9c")])
	assert_eq(cards.hand_kinds(3), [[]], "投降的牌不在桌上")
	assert_eq(chips.bet_amounts(1), [200, 100])
	assert_eq(chips.bet_amounts(2), [100], "下注阶段的注摆在第一手的位置")
	assert_eq(chips.bet_amounts(3), [0])
	assert_eq(chips.stack_amount(1), 1700)
	cards.sync(players, {"cards": H.cards("Th 7c 5d"), "hidden": false})
	assert_eq(cards.dealer_kinds(), H.cards("Th 7c 5d"))
	cards.clear()
	chips.clear()
	assert_eq(cards.dealer_kinds(), [])
	assert_eq(chips.stack_amount(1), 0)
