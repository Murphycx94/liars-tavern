extends GutTest
# 德州牌面的几何与排版(PokerFaceArt,纯几何;2026-10-10 动森式重画后):
# 圆头粗角标约占牌高 30%、花色在点数下方、右下角标是左上的中心对称;2–10 按经典排法摆点数个花色(下半倒过来),
# A 一枚大花色,J/Q/K 是竖长的角色画框;四色两系(红系 ♥♦、深色系 ♠♣)跨系一眼分清;全部画在内框以内;
# 缩到 30×42 像素仍认得出:角标与中央之间留出纸缝(不粘成一团)、「10」的两个数字分开、点数的笔画里没有被填实的洞;
# 每个多边形都能三角化(draw_colored_polygon 三角化失败会报引擎错误,那一块就画不出来)。


const ALL_RANKS := [2, 3, 4, 5, 6, 7, 8, 9, 10, PokerCard.JACK, PokerCard.QUEEN, PokerCard.KING, PokerCard.ACE]
const SMALLEST_WIDTH := 30.0          # 规格 §6.1 摊牌条小牌 ≥ 30×42
const RANK_SHARE := Vector2(0.28, 0.32)   # 点数约占牌高 30%(重画前 38%:中间要摆真正的点数排法)
const DISC_SEGMENTS := 24


func _cards() -> Array:
	var out := []
	for suit in PokerCard.SUITS:
		for rank in ALL_RANKS:
			out.append(PokerCard.make(rank, suit))
	return out


func _bounds(polys: Array) -> Rect2:
	var rect := Rect2(polys[0][0], Vector2.ZERO)
	for poly in polys:
		for p in poly:
			rect = rect.expand(p)
	return rect


func _keeps_clear(a: Array, b: Array, clearance: float) -> bool:
	# a 外扩 clearance(圆角)后与 b 不相交 ⇔ 两组多边形相距至少 clearance。外扩可能闭合出洞(顺时针),洞不算 a 的地盘
	for pa in a:
		for grown in Geometry2D.offset_polygon(pa, clearance, Geometry2D.JOIN_ROUND):
			if Geometry2D.is_polygon_clockwise(grown):
				continue
			for pb in b:
				if not Geometry2D.intersect_polygons(grown, pb).is_empty():
					return false
	return true


func _corner(card: int) -> Array:
	return PokerFaceArt.index_polygons(PokerCard.rank(card), PokerCard.suit(card))


func _turned(card: int) -> Array:
	return _corner(card).map(func(poly): return PokerFaceArt.half_turn(poly))


func _centre(card: int) -> Array:
	return PokerFaceArt.center_polygons(card)


func _components(polys: Array) -> Array:
	# 互相接触的多边形归成一组(并查集的朴素版):用来数一个点数由几块分开的字形组成
	var groups := []
	for poly in polys:
		var merged := [poly]
		var rest := []
		for group in groups:
			if _keeps_clear(group, [poly], 0.5):
				rest.append(group)
			else:
				merged.append_array(group)
		rest.append(merged)
		groups = rest
	return groups


func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func test_card_art_size_and_bake_size_keep_the_card_ratio():
	assert_eq(PokerFaceArt.SIZE, Vector2i(256, 372))
	var bake := Vector2(PokerFaces.SIZE)
	assert_almost_eq(bake.x / PokerFaceArt.SIZE.x, PokerFaces.BAKE_SCALE, 0.01, "烘焙是画面坐标整体放大")
	assert_almost_eq(bake.y / PokerFaceArt.SIZE.y, PokerFaces.BAKE_SCALE, 0.01)


func test_four_colours_in_two_families():
	var colors: Array = PokerFaceArt.SUIT_COLORS
	assert_eq(colors.size(), 4)
	for suit in PokerCard.SUITS:
		var c: Color = colors[suit]
		if suit in PokerFaceArt.RED_SUITS:
			assert_gt(c.r - maxf(c.g, c.b), 0.4, "%s 是红系 %s" % [PokerCard.SUIT_NAMES[suit], c])
		else:
			assert_lt(c.get_luminance(), 0.4, "%s 是深色系 %s" % [PokerCard.SUIT_NAMES[suit], c])
	for i in 4:
		for j in range(i + 1, 4):
			var same_family := (i in PokerFaceArt.RED_SUITS) == (j in PokerFaceArt.RED_SUITS)
			assert_gt(_distance(colors[i], colors[j]), 0.2 if same_family else 0.4, "花色 %d 与 %d 要分得清" % [i, j])


func test_rank_is_a_big_chunky_index_in_the_top_left():
	for rank in ALL_RANKS:
		var bounds := _bounds(PokerFaceArt.rank_polygons(rank, PokerFaceArt.rank_box(rank)))
		var share := bounds.size.y / PokerFaceArt.SIZE.y
		assert_between(share, RANK_SHARE.x, RANK_SHARE.y, "%s 占牌高 %.3f" % [PokerCard.rank_label(rank), share])
		assert_lt(bounds.get_center().x, PokerFaceArt.SIZE.x / 2.0, PokerCard.rank_label(rank))
		assert_lt(bounds.position.y, PokerFaceArt.SIZE.y * 0.1, PokerCard.rank_label(rank))


func test_index_suit_sits_under_the_rank():
	for card in _cards():
		var rank := PokerCard.rank(card)
		var rank_count := PokerFaceArt.rank_polygons(rank, PokerFaceArt.rank_box(rank)).size()
		var corner := _corner(card)
		var glyph := _bounds(corner.slice(0, rank_count))
		var pip := _bounds(corner.slice(rank_count))
		assert_gt(pip.position.y, glyph.end.y, PokerCard.label(card))
		assert_between(pip.get_center().x, glyph.position.x, glyph.end.x, PokerCard.label(card))


func test_bottom_right_index_is_the_top_left_turned_half_way():
	assert_eq(PokerFaceArt.half_turn(PackedVector2Array([Vector2.ZERO])), PackedVector2Array([Vector2(PokerFaceArt.SIZE)]))
	for card in _cards():
		var corner := _corner(card)
		var index: Array = PokerFaceArt.layout(card)["index"]
		assert_eq(index.size(), corner.size() * 2, PokerCard.label(card))
		for i in corner.size():
			assert_eq(index[i], corner[i])
			assert_eq(index[corner.size() + i], PokerFaceArt.half_turn(corner[i]))


func test_number_cards_show_as_many_pips_as_their_rank():
	for suit in PokerCard.SUITS:
		for rank in range(2, 11):
			var art := PokerFaceArt.layout(PokerCard.make(rank, suit))
			assert_eq(art["pips"].size(), rank, PokerCard.label(PokerCard.make(rank, suit)))
			assert_true(art["panel"].is_empty())
		var ace := PokerFaceArt.layout(PokerCard.make(PokerCard.ACE, suit))
		assert_eq(ace["pips"].size(), 1, "A 一枚大花色")
		assert_eq(ace["emblem"], suit == PokerCard.SPADES, "只有 ♠A 是大徽章")


func test_lower_pips_are_turned_upside_down():
	# 经典牌面:下半的花色倒过来(♥ 的尖朝上)
	var art := PokerFaceArt.layout(PokerCard.make(2, PokerCard.HEARTS))
	var top := _bounds(art["pips"][0])
	var bottom := _bounds(art["pips"][1])
	assert_lt(top.get_center().y, PokerFaceArt.CENTER.y)
	assert_gt(bottom.get_center().y, PokerFaceArt.CENTER.y)
	# ♥ 的尖在下:最低点在中线上;倒过来后最高点在中线上
	var top_tip := Vector2.ZERO
	for poly in art["pips"][0]:
		for p in poly:
			if p.y > top_tip.y:
				top_tip = p
	assert_almost_eq(top_tip.x, top.get_center().x, 1.0, "正着的 ♥ 尖朝下")
	var bottom_tip := Vector2(0, INF)
	for poly in art["pips"][1]:
		for p in poly:
			if p.y < bottom_tip.y:
				bottom_tip = p
	assert_almost_eq(bottom_tip.x, bottom.get_center().x, 1.0, "倒过来的 ♥ 尖朝上")


func test_only_jack_queen_and_king_get_a_character_panel():
	for card in _cards():
		var rank := PokerCard.rank(card)
		var court := rank in [PokerCard.JACK, PokerCard.QUEEN, PokerCard.KING]
		var art := PokerFaceArt.layout(card)
		assert_eq(not art["panel"].is_empty(), court, PokerCard.label(card))
		if court:
			assert_true(art["pips"].is_empty(), PokerCard.label(card))


func test_centre_art_is_centred_on_the_card():
	var middle := Vector2(PokerFaceArt.SIZE) / 2.0
	for card in _cards():
		var center := _bounds(_centre(card)).get_center()
		assert_almost_eq(center.x, middle.x, 1.0, PokerCard.label(card))
		assert_almost_eq(center.y, middle.y, 1.0, PokerCard.label(card))


func test_everything_is_drawn_inside_the_frame():
	# 内框内沿:画家的内框内缩 + 线宽
	var inset := PokerFacePainter.FRAME_INSET + PokerFacePainter.FRAME_WIDTH
	var interior := Rect2(Vector2.ONE * inset, Vector2(PokerFaceArt.SIZE) - Vector2.ONE * inset * 2.0)
	for card in _cards():
		var bounds := _bounds(_corner(card) + _turned(card) + _centre(card))
		assert_true(interior.encloses(bounds), "%s %s" % [PokerCard.label(card), bounds])


func test_corners_and_centre_keep_paper_between_them_at_the_smallest_size():
	# 至少留 MIN_CLEARANCE 宽的纸,缩到 30 像素宽时还有一个多像素的缝:否则角标与中央的花色、画框粘成一团
	assert_gte(PokerFaceArt.MIN_CLEARANCE, PokerFaceArt.SIZE.x / SMALLEST_WIDTH)
	for card in _cards():
		var label := PokerCard.label(card)
		assert_true(_keeps_clear(_corner(card), _centre(card), PokerFaceArt.MIN_CLEARANCE), "左上角标贴着中央 " + label)
		assert_true(_keeps_clear(_turned(card), _centre(card), PokerFaceArt.MIN_CLEARANCE), "右下角标贴着中央 " + label)
		assert_true(_keeps_clear(_corner(card), _turned(card), PokerFaceArt.MIN_CLEARANCE), "两个角标相碰 " + label)


func test_ten_is_two_separate_digits():
	var polys := PokerFaceArt.rank_polygons(10, PokerFaceArt.rank_box(10))
	var digits := _components(polys)
	assert_eq(digits.size(), 2, "「1」和「0」不能连成一块")
	if digits.size() == 2:
		assert_true(_keeps_clear(digits[0], digits[1], PokerFaceArt.MIN_CLEARANCE), "两个数字之间要有缝")


func test_rank_strokes_leave_no_filled_holes():
	# offset_polyline 把闭合的笔画加粗时会多出一个顺时针的「洞」;画家把每个多边形都填色,洞就被填实了(4 的三角形空心)
	for rank in ALL_RANKS:
		for poly in PokerFaceArt.rank_polygons(rank, PokerFaceArt.rank_box(rank)):
			assert_false(Geometry2D.is_polygon_clockwise(poly), PokerCard.rank_label(rank))


func test_every_polygon_can_be_triangulated():
	for card in _cards():
		var art := PokerFaceArt.layout(card)
		for poly in art["index"] + _centre(card):
			assert_false(Geometry2D.triangulate_polygon(poly).is_empty(), PokerCard.label(card))
