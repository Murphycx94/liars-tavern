extends GutTest
# 悬停大图接到真的牌上(无头):3D 牌按射线与四角投影造候选(正面朝镜头才算,牌背、翻面前的牌、藏起来的不算,叠着的取上面那张),
# 炸弹猫的牌带牌名与说明;2D 手牌条 / 德州小牌条给出屏幕矩形;运行时组件按光标显示、不压住悬停的牌,
# 被挡住(镜头切走、面板开着)、窗口失焦、光标出窗口时藏起;自己与子控件都不接鼠标,点击照样落到牌桌。


const C := preload("res://src/core/bomb_cat/bomb_cat_card.gd")

var camera: Camera3D


class ClickProbe:
	extends Node
	var events := []

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			events.append(event)


func before_each():
	camera = Camera3D.new()
	add_child_autofree(camera)
	camera.position = Vector3(0, 0.6, 0.5)
	camera.look_at(Vector3.ZERO)
	camera.make_current()


func after_each():
	Card3D.clear_materials()
	CardFaces.clear()
	BombCatFaces.clear()
	PokerFaces.clear()


func _card(kind: int, at := Vector3.ZERO, face_up := true) -> Card3D:
	var card: Card3D = add_child_autofree(Card3D.new())
	card.set_kind(kind)
	card.transform = Transform3D(Basis() if face_up else Basis(Vector3.BACK, PI), at)
	return card


func _center(card: Node3D) -> Vector2:
	return camera.unproject_position(card.global_position)


func _candidates(point: Vector2, cards: Array) -> Array:
	return CardPreview.world_candidates(camera, point, cards)


# —— 3D 候选 ——

func test_face_up_card_under_the_cursor_is_pickable_with_its_face():
	var card := _card(Card.ACE)
	var point := _center(card)
	var candidates := _candidates(point, [card])
	assert_eq(candidates.size(), 1)
	var c: Dictionary = candidates[0]
	assert_true(c["face_up"])
	assert_true(c["texture"] is Texture2D, "牌面纹理(CardFaces.texture,没生成时是占位图)")
	assert_eq(c["key"], card.get_instance_id())
	assert_true(CardPreview.contains(c["quad"], point), "屏幕轮廓包住牌心")
	assert_eq(CardPreview.pick(point, candidates), 0)
	assert_eq(CardPreview.pick(point + Vector2(400, 0), candidates), -1, "光标在牌外")


func test_backs_face_down_and_hidden_cards_are_not_pickable():
	var back := _card(CardFaces.BACK)
	assert_eq(CardPreview.pick(_center(back), _candidates(_center(back), [back])), -1, "牌背(他人的牌)")
	var down := _card(Card.KING, Vector3(0.2, 0, 0), false)
	assert_eq(CardPreview.pick(_center(down), _candidates(_center(down), [down])), -1, "牌型已知但背面朝上(翻牌前、出牌区)")
	var hidden := _card(Card.QUEEN, Vector3(-0.2, 0, 0))
	hidden.visible = false
	assert_eq(_candidates(_center(hidden), [hidden]), [], "藏起来的(发牌前)")
	assert_eq(_candidates(Vector2.ZERO, [null, "x"]), [], "不是牌的跳过")


func test_upper_card_of_a_stack_wins():
	var lower := _card(Card.QUEEN, Vector3(0, 0, 0))
	var upper := _card(Card.JOKER, Vector3(0.02, 0.01, 0.0))
	var point := _center(upper)
	var candidates := _candidates(point, [upper, lower])
	assert_eq(candidates[CardPreview.pick(point, candidates)]["key"], upper.get_instance_id(), "离镜头近的压在上面")
	candidates = _candidates(point, [lower, upper])
	assert_eq(candidates[CardPreview.pick(point, candidates)]["key"], upper.get_instance_id(), "与传入顺序无关")


func test_cards_behind_the_camera_are_skipped():
	var card := _card(Card.ACE, Vector3(0, 0.6, 1.5))
	assert_eq(_candidates(Vector2(640, 360), [card]), [])


func test_bomb_cat_cards_carry_name_and_description():
	var card: BombCard3D = add_child_autofree(BombCard3D.new(C.SNACK_YARN))
	var point := _center(card)
	var candidates := _candidates(point, [card])
	assert_eq(CardPreview.pick(point, candidates), 0)
	assert_eq(candidates[0]["title"], C.display_name(C.SNACK_YARN))
	assert_eq(candidates[0]["body"], C.description(C.SNACK_YARN))
	assert_true(candidates[0]["texture"] is Texture2D)
	var back: BombCard3D = add_child_autofree(BombCard3D.new())
	back.position = Vector3(0.2, 0, 0)
	assert_eq(CardPreview.pick(_center(back), _candidates(_center(back), [back])), -1, "别人的牌背")


func test_poker_cards_use_the_poker_face():
	var kind := PokerCard.make(PokerCard.ACE, PokerCard.SPADES)
	var card := _card(kind)
	var candidates := _candidates(_center(card), [card])
	assert_true(candidates[0]["face_up"])
	assert_true(candidates[0]["texture"] is Texture2D, "德州牌经 CardFaces.texture 转给 PokerFaces")


# —— 2D 候选 ——

func test_bomb_cat_strip_gives_rects_with_captions_and_no_tooltip():
	var strip: BombCatHandStrip = add_child_autofree(BombCatHandStrip.new())
	var ids := [C.DEFUSE, C.NOPE, C.SNACK_FISH]
	strip.size = Vector2(600, 130)
	strip.set_hand(ids, {}, true)
	var candidates := strip.preview_candidates()
	assert_eq(candidates.size(), 3)
	for i in ids.size():
		assert_eq(candidates[i]["title"], C.display_name(ids[i]))
		assert_eq(candidates[i]["body"], C.description(ids[i]))
		assert_eq(candidates[i]["layer"], CardPreview.LAYER_HUD)
	var rect := CardPreview.bounds_of(candidates[1]["quad"])
	assert_almost_eq(rect.size, BombCatHandStrip.CARD_SIZE, Vector2.ONE * 0.5)
	assert_eq(CardPreview.pick(rect.get_center(), candidates), 1)
	for card in strip.get_children():
		if card is TextureRect:
			assert_eq(card.tooltip_text, "", "牌名与说明改由悬停大图给出,不再弹文字提示框")
	strip.visible = false
	assert_eq(strip.preview_candidates(), [], "手牌条藏起来(观战)时没有候选")


func test_crowded_bomb_cat_strip_prefers_the_card_on_top():
	var strip: BombCatHandStrip = add_child_autofree(BombCatHandStrip.new())
	var ids := []
	for i in 14:
		ids.append(C.SNACK_CARROT if i % 2 == 0 else C.SHUFFLE)
	strip.size = Vector2(BombCatHandStrip.MAX_WIDTH, 130)
	strip.set_hand(ids, {}, true)
	var candidates := strip.preview_candidates()
	var second := CardPreview.bounds_of(candidates[5]["quad"])
	# 第 6 张的右半边被第 7 张压住:光标在压住的那块上时放大第 7 张
	assert_eq(CardPreview.pick(Vector2(second.end.x - 4, second.get_center().y), candidates), 6)


func test_poker_strip_lists_only_dealt_cards():
	var strip: CardStrip = add_child_autofree(CardStrip.new(PokerRules.BOARD_CARDS, Vector2(36, 50)))
	var board := [PokerCard.make(PokerCard.QUEEN, PokerCard.HEARTS), PokerCard.make(9, PokerCard.CLUBS)]
	strip.set_cards(board)
	await wait_process_frames(2)   # 等容器排好
	var candidates := strip.preview_candidates()
	assert_eq(candidates.size(), 2, "空槽不算")
	assert_true(candidates[1]["texture"] is Texture2D)
	strip.visible = false
	assert_eq(strip.preview_candidates(), [])


func test_poker_hud_lists_board_hole_and_showdown_cards_and_clears_their_panels():
	var hud: PokerHud = add_child_autofree(PokerHud.new())
	var board := [PokerCard.make(PokerCard.QUEEN, PokerCard.HEARTS), PokerCard.make(9, PokerCard.CLUBS),
		PokerCard.make(4, PokerCard.SPADES)]
	hud.set_board(board)
	hud.set_my_hole([PokerCard.make(PokerCard.ACE, PokerCard.SPADES), PokerCard.make(PokerCard.KING, PokerCard.HEARTS)])
	hud.set_showdown([{"name": "乙", "cards": [PokerCard.make(10, PokerCard.HEARTS), PokerCard.make(PokerCard.JACK, PokerCard.HEARTS)],
		"hand_name": "顺子", "won": 860}])
	await wait_process_frames(2)
	var candidates := hud.preview_candidates()
	assert_eq(candidates.size(), 3 + 2 + 2, "公共牌 3 + 自己 2 + 摊牌 2")
	var showdown_card: Dictionary = candidates[-1]
	assert_true(CardPreview.avoid_rect(showdown_card).encloses(CardPreview.bounds_of(showdown_card["quad"])))
	assert_gt(CardPreview.avoid_rect(showdown_card).size.x, 200.0, "让开整块摊牌面板")
	hud.set_showdown([])
	assert_eq(hud.preview_candidates().size(), 5, "摊牌面板收起后不再有它的牌")


# —— 运行时组件 ——

func _host() -> Control:
	# 牌桌屏幕的替身:1280×720 的全屏层,大图铺满它
	var host := Control.new()
	host.size = Vector2(1280, 720)
	add_child_autofree(host)
	return host


func _preview(card_rect: Rect2, state := {}) -> CardPreview:
	var preview := CardPreview.new()
	_host().add_child(preview)
	preview.source = func(_point: Vector2) -> Array:
		return [CardPreview.rect_candidate(card_rect, PlaceholderTexture2D.new(), 0, "card", "拆弹", "摸到炸弹时自动用掉")]
	preview.gate = func() -> Dictionary: return state
	return preview


func test_hovering_shows_the_card_beside_it_and_leaving_hides_it():
	var card := Rect2(600, 590, 70, 101)
	var preview := _preview(card)
	preview.hover_at(card.get_center())
	assert_true(preview.is_showing())
	var shown := preview.shown_rect()
	assert_false(shown.intersects(card), "不压住悬停的牌")
	assert_true(Rect2(Vector2.ZERO, preview.size).encloses(shown), "在画面里")
	assert_eq(preview.shown_caption(), {"title": "拆弹", "body": "摸到炸弹时自动用掉"})
	assert_gt(shown.size.y, CardPreview.preview_size(preview.size).y, "下面带说明面板")
	preview.hover_at(Vector2(100, 100))
	assert_false(preview.is_showing(), "光标离开牌就藏")


func test_blocked_states_hide_the_preview():
	var card := Rect2(600, 590, 70, 101)
	for state: Dictionary in [{"camera_at_rest": false}, {"panel_open": true}, {"modal_open": true}, {"settlement": true}]:
		var preview := _preview(card, state)
		preview.hover_at(card.get_center())
		assert_false(preview.is_showing(), str(state))


func test_focus_loss_and_mouse_exit_hide_until_they_come_back():
	var card := Rect2(600, 590, 70, 101)
	var preview := _preview(card)
	preview.hover_at(card.get_center())
	assert_true(preview.is_showing())
	preview.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(preview.is_showing(), "切到别的程序")
	preview.refresh(false)
	assert_false(preview.is_showing(), "失焦期间不再弹出")
	preview.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	preview.refresh(false)
	assert_true(preview.is_showing(), "回来后光标还在牌上就再弹出")
	preview.notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	assert_false(preview.is_showing(), "光标出了窗口")
	preview.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	preview.hover_at(card.get_center())
	assert_true(preview.is_showing(), "截图 / 测试的 hover_at 当作光标回到窗口里")


func test_texture_swap_updates_without_hiding():
	# 牌面后台生成完:同一张牌从占位小图换成正式纹理(尺寸变了),大图跟着换;占位图每次取都是新对象,尺寸不变就不重画
	var card := Rect2(600, 590, 70, 101)
	var textures := [PlaceholderTexture2D.new(), PlaceholderTexture2D.new(), PlaceholderTexture2D.new()]
	textures[0].size = Vector2(8, 8)
	textures[1].size = Vector2(8, 8)
	textures[2].size = Vector2(360, 520)
	var which := [0]
	var preview := CardPreview.new()
	_host().add_child(preview)
	preview.source = func(_point: Vector2) -> Array:
		return [CardPreview.rect_candidate(card, textures[which[0]], 0, "same")]
	preview.hover_at(card.get_center())
	assert_same(preview.shown_texture(), textures[0])
	which[0] = 1
	preview.refresh(false)
	assert_same(preview.shown_texture(), textures[0], "又一张同尺寸的占位图:不重画")
	which[0] = 2
	preview.refresh(false)
	assert_true(preview.is_showing())
	assert_same(preview.shown_texture(), textures[2], "正式牌面到了:换图")


func test_preview_never_takes_the_mouse():
	var preview := _preview(Rect2(600, 590, 70, 101))
	preview.hover_at(Vector2(635, 640))
	assert_eq(preview.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	for child in preview.find_children("*", "Control", true, false):
		assert_eq((child as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE, child.name)
	var probe: ClickProbe = add_child_autofree(ClickProbe.new())
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(635, 640)
	get_viewport().push_input(click)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(635, 640)
	get_viewport().push_input(motion)
	assert_eq(probe.events.size(), 2, "点击与移动都照样落到牌桌的 _unhandled_input")
