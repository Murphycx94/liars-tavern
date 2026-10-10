extends GutTest
# 斗地主的 3D 层(无头):两张王的牌面接进德州牌面管线(牌面值、纹理尺寸与 mipmap、3D 材质、悬停大图)、
# 身份帽戴上 / 摘掉(藏起与放回酒客自己的帽子、按颅骨缩放、第一人称藏头时一并藏起)、
# DdzCards 只亮已公开的牌(别人的牌扇永远是牌背,一手结束才摊开)、出牌行的顺序与摆放。


const H := preload("res://tests/ddz_helpers.gd")

var world: TableWorld
var cards: DdzCards


func before_each():
	world = TableWorld.new(null)
	add_child_autofree(world)
	world.arrange([{"pid": 1}, {"pid": 2}, {"pid": 3}], 1, true, false)
	cards = DdzCards.new(world)
	cards.my_pid = 1
	world.poker_root.add_child(cards)


func after_each():
	DdzJokerFaces.batch_renderer = Callable()
	DdzJokerFaces.clear()
	Card3D.clear_materials()


# —— 两张王 ——

func test_face_kinds_map_into_the_poker_pipeline():
	assert_eq(DdzJokerFaces.face_kind(DdzHand.BIG_JOKER), DdzJokerFaces.BIG)
	assert_eq(DdzJokerFaces.face_kind(DdzHand.SMALL_JOKER), DdzJokerFaces.SMALL)
	assert_eq(DdzJokerFaces.face_kind(H.cards("A")[0]), PokerCard.make(PokerCard.ACE, 0))
	assert_eq(DdzJokerFaces.face_kind(-1), CardFaces.BACK)
	for kind in DdzJokerFaces.KINDS:
		assert_false(PokerCard.is_card(kind), "王的牌面值不和德州牌撞")
		assert_gt(kind, 3, "也不和骗子酒馆的牌撞")
		assert_true(DdzJokerFaces.is_kind(kind))


func test_baked_jokers_are_full_size_with_mipmaps():
	# 无头模式不出图:用测试钩子交两张烘焙尺寸的图,核对转成的纹理尺寸与 mipmap(2D 小牌从 320 像素缩小要 mipmap)
	DdzJokerFaces.batch_renderer = func(_tree: SceneTree, kinds: Array) -> Array:
		return kinds.map(func(_k) -> Image:
			var img := Image.create(PokerFaces.SIZE.x, PokerFaces.SIZE.y, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.9, 0.8, 0.7))
			return img)
	await DdzJokerFaces.build(world)
	assert_true(DdzJokerFaces.is_built())
	for kind in DdzJokerFaces.KINDS:
		var tex := DdzJokerFaces.texture(kind)
		assert_eq(Vector2i(tex.get_size()), PokerFaces.SIZE, "和德州牌面同尺寸")
		assert_true(tex.get_image().has_mipmaps(), "带 mipmap")
		assert_eq(CardFaces.texture(kind), tex, "CardFaces 转到这里")
	assert_eq(DdzJokerFaces.texture_for(DdzHand.BIG_JOKER), DdzJokerFaces.texture(DdzJokerFaces.BIG))


func test_headless_build_falls_back_and_3d_cards_use_single_face_materials():
	await DdzJokerFaces.build(world)
	assert_true(DdzJokerFaces.is_built(), "无头模式退化成纯色小纹理,逻辑照常")
	var joker := DdzCard3D.new(DdzHand.BIG_JOKER)
	add_child_autofree(joker)
	assert_eq(joker.kind, DdzJokerFaces.BIG)
	assert_eq(Card3D.material_for(DdzJokerFaces.BIG).get_shader_parameter("single_face"), true)
	assert_ne(Card3D.material_for(DdzJokerFaces.BIG), Card3D.material_for(DdzJokerFaces.SMALL), "两张王各一份材质")
	assert_eq(CardPreview.face_of(joker)["texture"], DdzJokerFaces.texture(DdzJokerFaces.BIG), "悬停大图认得王")
	var back := DdzCard3D.new(DdzCard3D.BACK)
	add_child_autofree(back)
	assert_true(back.is_back())
	assert_null(CardPreview.face_of(back)["texture"], "牌背不弹大图")


func test_joker_glyphs_stay_inside_the_index_column():
	for which in [DdzJokerPainter.BIG, DdzJokerPainter.SMALL]:
		var lines := DdzJokerPainter.index_lines(which)
		assert_eq(lines.size(), 2)
		for i in lines.size():
			var box := Rect2(DdzJokerPainter.INDEX_X - DdzJokerPainter.INDEX_GLYPH / 2.0,
				DdzJokerPainter.INDEX_TOP + i * DdzJokerPainter.INDEX_GAP, DdzJokerPainter.INDEX_GLYPH, DdzJokerPainter.INDEX_GLYPH)
			var strokes := DdzJokerPainter.glyph_strokes(lines[i], box)
			assert_gt(strokes.size(), 1, "「%s」有笔画" % lines[i])
			for stroke in strokes:
				for p in stroke:
					assert_lt(p.x, DdzJokerPainter.PANEL.position.x, "角标在画框左边")
	assert_lt(DdzJokerPainter.INDEX_TOP + DdzJokerPainter.INDEX_GAP + DdzJokerPainter.INDEX_GLYPH, PokerFaceArt.SIZE.y / 2.0,
		"角标只占上半张")


# —— 身份帽 ——

func test_hats_swap_and_restore_the_patrons_own_hat():
	var patron: Patron = world.patrons[2]
	var own: Node3D = patron.head.get_node("Hat/HatMesh")
	assert_true(own.visible)
	var hat := DdzHats.put_on(patron, DdzState.ROLE_LANDLORD, false)
	assert_not_null(hat)
	assert_eq(DdzHats.role_of(patron), DdzState.ROLE_LANDLORD)
	assert_false(own.visible, "戴上地主帽时自己的帽子藏起来")
	assert_eq(hat.get_parent(), patron.head.get_node("Hat"), "挂在帽子枢轴下(跳舞抛帽也带着)")
	DdzHats.put_on(patron, DdzState.ROLE_FARMER, false)
	assert_eq(DdzHats.role_of(patron), DdzState.ROLE_FARMER, "换成草帽")
	assert_eq(patron.head.get_node("Hat").get_children().filter(func(c): return c.name == DdzHats.NODE).size(), 1, "只戴一顶")
	DdzHats.take_off(patron)
	await get_tree().process_frame
	assert_eq(DdzHats.role_of(patron), "")
	assert_true(own.visible, "摘帽后自己的帽子放回来")
	assert_null(DdzHats.put_on(patron, "", false), "没有身份不戴")


func test_hats_fit_each_skull_and_hide_in_first_person():
	for pid in world.patrons:
		var patron: Patron = world.patrons[pid]
		var hat := DdzHats.put_on(patron, DdzState.ROLE_FARMER, false)
		var skull: Array = patron.skull_ellipsoid()
		var hat_in_head := patron.head.global_transform.affine_inverse() * hat.global_transform
		assert_gt(hat_in_head.origin.y, (skull[0] as Vector3).y, "帽口在颅骨中心之上")
		# 穿模修复(2026-10-10):按物种贴合表摆(DdzHats.FIT,坐在头顶上、不碰头和耳朵;逐物种的穿模判定见 test_ddz_hats)
		var want := DdzHats.head_transform(DdzHats.fit_for(patron.species_index, DdzState.ROLE_FARMER))
		assert_almost_eq(hat_in_head.origin, want.origin, Vector3.ONE * 0.003, "按物种贴合表摆")
		assert_almost_eq(hat_in_head.basis.get_scale(), want.basis.get_scale(), Vector3.ONE * 0.02, "按物种贴合表缩放")
	var me: Patron = world.patrons[1]
	me.set_head_hidden(true)
	var mesh: GeometryInstance3D = DdzHats.hat_node(me).get_node("HatMesh")
	assert_eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "第一人称时只投影不渲染")
	me.set_head_hidden(false)
	assert_ne(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)


func test_hat_meshes_are_cached():
	assert_eq(DdzProps.landlord_hat(), DdzProps.landlord_hat())
	assert_eq(DdzProps.straw_hat(), DdzProps.straw_hat())
	assert_ne(DdzProps.landlord_hat(), DdzProps.straw_hat())
	var holes := [Vector3(0.12, 0.0, 0.03)]
	assert_eq(DdzProps.straw_hat(holes), DdzProps.straw_hat(holes), "开耳洞的草帽按洞缓存")
	assert_ne(DdzProps.straw_hat(holes), DdzProps.straw_hat())


# —— 牌层:只亮已公开的牌 ——

func test_deal_keeps_other_hands_face_down():
	var mine := H.cards("3 4 5 6 7 8 9 10 J Q K A 2 2 2 2 BJ")
	await cards.deal([1, 2, 3], {1: 17, 2: 17, 3: 17}, mine)
	assert_eq(cards.held_count(2), 17)
	assert_eq(cards.held_count(3), 17)
	assert_eq(cards.my_ids(), mine)
	assert_eq(cards.face_up_ids_of_others(), [], "别人的牌扇全是牌背")
	assert_eq(cards.bottom_cards().size(), 3)
	assert_true(cards.bottom_cards().all(func(c: DdzCard3D) -> bool: return c.is_back()), "底牌扣着")
	var hoverable := cards.hoverable_cards()
	assert_true(hoverable.all(func(c) -> bool: return not c.get_parent() == world.patrons[2].fan), "别人的牌不进悬停候选")


func test_bottom_reveal_goes_back_face_down_into_someone_elses_fan():
	await cards.deal([1, 2, 3], {1: 17, 2: 17, 3: 17}, H.cards("3 4 5 6 7 8 9 10 J Q K A 2 2 2 2 BJ"))
	var bottom := H.cards("7 K SJ")
	await cards.reveal_bottom(bottom, 2, [])
	assert_eq(cards.held_count(2), 20)
	assert_eq(cards.face_up_ids_of_others(), [], "底牌进了别人手里又是牌背")
	assert_eq(cards.bottom_cards().size(), 0)


func test_plays_and_reveal():
	cards.sync({1: 3, 2: 5, 3: 4}, H.cards("3 4 5"), {}, false)
	var played := H.cards("9 9 9 4")
	await cards.play(2, played)
	assert_eq(cards.held_count(2), 1, "别人出了 4 张,牌扇少 4 张")
	assert_eq(cards.row_ids(2), DdzLayout.row_order(played))
	assert_eq(DdzLayout.row_order(played).slice(0, 3).map(func(c): return DdzHand.rank(c)), [6, 6, 6], "三张在前、带的在后")
	await cards.play(1, H.cards("4"))
	assert_eq(cards.my_ids(), H.cards("3 5"))
	await cards.clear_trick()
	await get_tree().process_frame
	assert_eq(cards.row_ids(2), [])
	assert_eq(cards.face_up_ids_of_others(), [])
	await cards.reveal_remaining({2: H.cards("K"), 3: H.cards("5 6 7 8"), 1: H.cards("3 5")})
	assert_eq(cards.row_ids(3), DdzLayout.row_order(H.cards("5 6 7 8")), "一手结束摊开别人的剩牌")
	assert_eq(cards.held_count(3), 0)
	assert_eq(cards.my_ids(), H.cards("3 5"), "自己的牌留在牌扇里")


func test_row_layout_stays_on_the_felt_and_apart():
	var angles := {1: 0.0, 2: TAU / 3.0, 3: TAU * 2.0 / 3.0}
	for pid in angles:
		var mine: bool = pid == 1
		for n in [1, 5, 12, 20]:
			var first := DdzLayout.play_slot(angles[pid], mine, 0, n).origin
			var last := DdzLayout.play_slot(angles[pid], mine, n - 1, n).origin
			assert_lte(first.distance_to(last), DdzLayout.max_row(mine) + 0.001, "一行不超宽")
			for p in [first, last]:
				assert_lt(Vector2(p.x, p.z).length() + Card3D.WIDTH * DdzLayout.PLAY_SCALE, SeatLayout.FELT_RADIUS, "在桌布里")
	var a := DdzLayout.row_center(angles[2], false)
	var b := DdzLayout.row_center(angles[3], false)
	assert_gt(a.distance_to(b), DdzLayout.OPP_MAX_ROW + Card3D.WIDTH * DdzLayout.PLAY_SCALE, "两位对手的行不重叠")
