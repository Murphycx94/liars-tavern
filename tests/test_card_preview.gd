extends GutTest
# 悬停大图的纯逻辑(无头):光标下哪张牌胜出(2D 界面层先于 3D、同层离镜头近的 / 后画的在上)、牌背不放大、光标在牌外没有;
# 藏起的条件(失焦、光标出窗口、镜头不在常驻机位、快捷语 / 九宫格、说明书 / 确认框、结算);
# 大图尺寸随视口缩放;摆位永远在画面里、不压住悬停的那张牌与光标(手牌在底部 → 上方,公共牌条在左上 → 右侧),
# 界面上的小牌可以要求让开整块面板(摊牌面板 → 左侧)。


const VIEWPORT := Vector2(1280, 720)


func _world(rect: Rect2, depth: float, face_up := true, key: Variant = null) -> Dictionary:
	return {"quad": CardPreview.quad_of(rect), "depth": depth, "layer": CardPreview.LAYER_WORLD, "face_up": face_up,
		"texture": PlaceholderTexture2D.new() if face_up else null, "key": key}


func _hud(rect: Rect2, order: int, key: Variant = null) -> Dictionary:
	return CardPreview.rect_candidate(rect, PlaceholderTexture2D.new(), order, key)


# —— 选牌 ——

func test_nearest_world_card_under_the_cursor_wins():
	var far := _world(Rect2(100, 100, 80, 120), 2.0, true, "far")
	var near := _world(Rect2(140, 120, 80, 120), 1.2, true, "near")
	var candidates := [far, near]
	assert_eq(CardPreview.pick(Vector2(160, 150), candidates), 1, "两张都压着光标:离镜头近的胜出")
	assert_eq(CardPreview.pick(Vector2(110, 110), candidates), 0, "只压着远的那张")
	assert_eq(CardPreview.pick(Vector2(400, 400), candidates), -1, "光标在牌外:没有")
	assert_eq(CardPreview.pick(Vector2(160, 150), []), -1)


func test_backs_are_never_picked():
	var face := _world(Rect2(100, 100, 80, 120), 2.0, true)
	var back := _world(Rect2(100, 100, 80, 120), 1.0, false)
	assert_eq(CardPreview.pick(Vector2(140, 150), [face, back]), 0, "上面那张是牌背:放大下面亮着的")
	assert_eq(CardPreview.pick(Vector2(140, 150), [back]), -1, "只有牌背:不放大")
	var no_texture := _world(Rect2(100, 100, 80, 120), 1.0, true)
	no_texture["face_up"] = false
	assert_eq(CardPreview.pick(Vector2(140, 150), [no_texture]), -1)


func test_hud_cards_beat_world_cards_and_later_hud_cards_are_on_top():
	var world := _world(Rect2(0, 0, 400, 400), 0.1)
	var first := _hud(Rect2(100, 100, 70, 101), 0, "a")
	var second := _hud(Rect2(140, 100, 70, 101), 1, "b")
	assert_eq(CardPreview.pick(Vector2(120, 150), [world, first, second]), 1, "2D 界面画在 3D 之上")
	assert_eq(CardPreview.pick(Vector2(150, 150), [world, first, second]), 2, "手牌条里后面的牌压在前面的上面")
	assert_eq(CardPreview.pick(Vector2(300, 300), [world, first, second]), 0, "界面上没有牌的地方:3D 的牌")


func test_tilted_quads_use_the_real_outline_not_the_bounds():
	# 牌扇里斜着的牌:光标落在外接矩形里、轮廓外面不算
	var diamond := {"quad": PackedVector2Array([Vector2(100, 0), Vector2(200, 100), Vector2(100, 200), Vector2(0, 100)]),
		"depth": 1.0, "layer": CardPreview.LAYER_WORLD, "face_up": true, "texture": PlaceholderTexture2D.new()}
	assert_eq(CardPreview.pick(Vector2(100, 100), [diamond]), 0)
	assert_eq(CardPreview.pick(Vector2(10, 10), [diamond]), -1, "外接矩形的角上")


func test_malformed_candidates_are_skipped():
	var good := _world(Rect2(0, 0, 50, 50), 1.0)
	assert_eq(CardPreview.pick(Vector2(10, 10), [null, {}, "x", {"face_up": true}, good]), 4)


# —— 藏起 ——

func test_nothing_blocks_by_default():
	assert_false(CardPreview.is_blocked({}))
	assert_false(CardPreview.is_blocked({"focused": true, "mouse_inside": true, "camera_at_rest": true,
		"panel_open": false, "modal_open": false, "settlement": false}))


func test_each_hiding_rule_blocks_on_its_own():
	assert_true(CardPreview.is_blocked({"focused": false}), "窗口失焦")
	assert_true(CardPreview.is_blocked({"mouse_inside": false}), "光标出了窗口")
	assert_true(CardPreview.is_blocked({"camera_at_rest": false}), "镜头去拍特写 / 开枪 / 庆祝")
	assert_true(CardPreview.is_blocked({"panel_open": true}), "快捷语面板或九宫格开着")
	assert_true(CardPreview.is_blocked({"modal_open": true}), "说明书或确认框开着")
	assert_true(CardPreview.is_blocked({"settlement": true}), "结算面板")


# —— 尺寸 ——

func test_preview_size_scales_with_the_viewport_and_keeps_the_card_aspect():
	var at_720 := CardPreview.preview_size(Vector2(1280, 720))
	assert_almost_eq(at_720.y, 209.0, 1.0, "16:9 界面坐标下约 209(1080p 窗口约 313 物理像素)")
	assert_almost_eq(at_720.x / at_720.y, Card3D.WIDTH / Card3D.HEIGHT, 0.01, "与牌同比例")
	assert_gt(CardPreview.preview_size(Vector2(1280, 960)).y, at_720.y, "4:3 视口更高,大图跟着变大")
	assert_eq(CardPreview.preview_size(Vector2(1280, 2000)).y, CardPreview.MAX_HEIGHT, "有上限")
	assert_eq(CardPreview.preview_size(Vector2(1024, 400)).y, CardPreview.MIN_HEIGHT, "有下限")
	var small := Vector2(54, 76)   # 德州左下的手牌小图
	assert_gt(at_720.y / small.y, 2.5, "比牌桌上的小图大好几倍")


func test_caption_adds_a_wider_panel_under_the_card():
	var card := CardPreview.preview_size(VIEWPORT)
	assert_eq(CardPreview.caption_height("", "", 250.0), 0.0, "没有文字就没有说明面板")
	assert_eq(CardPreview.box_size(card, 0.0), card)
	var caption := CardPreview.caption_height("毛线球", "零食:两张一样的抽一张,三张一样的点名要牌", 250.0)
	assert_gt(caption, 40.0)
	var box := CardPreview.box_size(card, caption)
	assert_eq(box.x, maxf(card.x, CardPreview.CAPTION_MIN_WIDTH))
	assert_almost_eq(box.y, card.y + CardPreview.CAPTION_GAP + caption, 0.01)


# —— 摆位 ——

func _assert_on_screen(rect: Rect2, viewport := VIEWPORT, msg := "") -> void:
	assert_true(rect.position.x >= CardPreview.EDGE - 0.01 and rect.position.y >= CardPreview.EDGE - 0.01, "左上在画面里 " + msg)
	assert_true(rect.end.x <= viewport.x - CardPreview.EDGE + 0.01 and rect.end.y <= viewport.y - CardPreview.EDGE + 0.01,
		"右下在画面里 " + msg)


func test_hand_card_at_the_bottom_gets_the_preview_above_it():
	var box := CardPreview.preview_size(VIEWPORT)
	var card := Rect2(600, 590, 70, 101)
	var cursor := card.get_center()
	var at := CardPreview.place(box, card, cursor, VIEWPORT)
	var shown := Rect2(at, box)
	_assert_on_screen(shown)
	assert_false(shown.intersects(card), "不压住悬停的牌")
	assert_lte(shown.end.y, card.position.y - CardPreview.GAP + 0.01, "在牌的上方")
	assert_almost_eq(shown.get_center().x, cursor.x, 0.5, "以光标为中线")


func test_board_strip_in_the_top_left_corner_gets_the_preview_beside_it():
	var box := CardPreview.preview_size(VIEWPORT)
	var card := Rect2(30, 70, 36, 50)
	var at := CardPreview.place(box, card, card.get_center(), VIEWPORT)
	var shown := Rect2(at, box)
	_assert_on_screen(shown)
	assert_false(shown.intersects(card))
	assert_gte(shown.position.x, card.end.x + CardPreview.GAP - 0.01, "上方放不下:放右侧")


func test_card_at_the_right_edge_goes_left_or_below():
	var box := CardPreview.preview_size(VIEWPORT)
	var card := Rect2(1240, 20, 36, 50)
	var shown := Rect2(CardPreview.place(box, card, card.get_center(), VIEWPORT), box)
	_assert_on_screen(shown)
	assert_false(shown.intersects(card))


func test_cursor_near_the_left_edge_is_clamped_on_screen():
	var box := CardPreview.preview_size(VIEWPORT)
	var card := Rect2(0, 600, 60, 90)
	var shown := Rect2(CardPreview.place(box, card, Vector2(4, 640), VIEWPORT), box)
	_assert_on_screen(shown)
	assert_false(shown.intersects(card))
	assert_false(shown.has_point(Vector2(4, 640)), "不压住光标")


func test_the_cursor_is_avoided_even_outside_the_card_bounds():
	var box := Vector2(100, 150)
	var card := Rect2(500, 400, 60, 90)
	var cursor := Vector2(530, 380)   # 牌上沿外一点(3D 牌刚抬起来)
	var shown := Rect2(CardPreview.place(box, card, cursor, VIEWPORT), box)
	assert_false(shown.has_point(cursor))
	assert_false(shown.intersects(card))


func test_random_cards_never_get_covered_and_the_preview_stays_on_screen():
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bad := []
	for viewport: Vector2 in [Vector2(1280, 720), Vector2(1280, 960), Vector2(1707, 720)]:
		var box := CardPreview.box_size(CardPreview.preview_size(viewport), 0.0)
		var screen := Rect2(Vector2.ONE * CardPreview.EDGE, viewport - Vector2.ONE * CardPreview.EDGE * 2.0).grow(0.01)
		for i in 300:
			var size := Vector2(rng.randf_range(20, 140), rng.randf_range(30, 200))
			var card := Rect2(Vector2(rng.randf_range(0, viewport.x - size.x), rng.randf_range(0, viewport.y - size.y)), size)
			var cursor := card.position + size * Vector2(rng.randf(), rng.randf())
			var shown := Rect2(CardPreview.place(box, card, cursor, viewport), box)
			if not screen.encloses(shown) or shown.intersects(card):
				bad.append([viewport, card, shown])
	assert_eq(bad, [], "900 个随机位置:都在画面里、都不压住悬停的牌")


func test_when_nothing_fits_the_least_overlap_wins_and_it_stays_on_screen():
	var viewport := Vector2(400, 300)
	var box := Vector2(200, 260)
	var card := Rect2(150, 100, 100, 100)
	var shown := Rect2(CardPreview.place(box, card, card.get_center(), viewport), box)
	_assert_on_screen(shown, viewport)
	assert_lt(shown.intersection(card).get_area(), card.get_area(), "放不下时也尽量少压")


func test_hud_cards_can_ask_the_preview_to_clear_their_whole_panel():
	# 摊牌面板里的小牌:大图让开整块面板(不挡住同一行的名字、牌型与输赢)
	var card := Rect2(1000, 110, 30, 42)
	var panel := Rect2(956, 76, 300, 400)
	var c := CardPreview.rect_candidate(card, PlaceholderTexture2D.new(), 0, "q", "", "", panel)
	assert_eq(CardPreview.avoid_rect(c), panel)
	assert_eq(CardPreview.avoid_rect(_hud(card, 0)), card, "没给面板:只让开这张牌")
	var box := CardPreview.preview_size(VIEWPORT)
	var shown := Rect2(CardPreview.place(box, CardPreview.avoid_rect(c), card.get_center(), VIEWPORT), box)
	_assert_on_screen(shown)
	assert_false(shown.intersects(panel), "摆在面板外面")
