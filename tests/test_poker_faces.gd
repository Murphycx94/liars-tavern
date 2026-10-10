extends GutTest
# 德州牌面 PokerFaces:自己的缓存与占位、无头模式退化纹理(带 mipmap)、CardFaces 只分流德州牌、
# 分批生成每批不超过 BATCH_SIZE 张、并发生成只做一次、clear 打断生成并回到占位、生成完刷新 3D 材质并发 built 信号。
# 真实的 SubViewport 渲染在无头模式下不出图,用 batch_renderer 测试钩子替换「渲染一批」来测排期逻辑。


const LIARS_KINDS := [CardFaces.BACK, Card.QUEEN, Card.KING, Card.ACE, Card.JOKER]
const SETTLE_FRAMES := 12   # 假渲染器每批等一帧,4 批 + 余量

var host: Node
var renders: Array = []   # 假渲染器每次收到的那一批牌
var liars_were_built := false   # 测试开始时骗子酒馆的牌面是否已生成,结束时还原


func before_each():
	PokerFaces.clear()
	renders = []
	liars_were_built = CardFaces.is_built()
	host = add_child_autofree(Node.new())


func after_each():
	PokerFaces.batch_renderer = Callable()
	PokerFaces.clear()
	# 有的测试会清掉或生成骗子酒馆的牌面:把全局缓存还原成测试前的样子,后面的测试不受文件顺序影响
	if liars_were_built:
		await CardFaces.build(host)
	else:
		CardFaces.clear()


func _fake_renderer(image_size := Vector2i(PokerFaces.SIZE)) -> Callable:
	# 像真实渲染一样隔一帧才交图;image_size 为零时交回空图(模拟抓图失败)
	return func(tree: SceneTree, batch: Array) -> Array:
		renders.append(batch.duplicate())
		await tree.process_frame
		var images := []
		for card in batch:
			images.append(null if image_size == Vector2i.ZERO else
				Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGBA8))
		return images


func _all_textures() -> Array:
	return PokerFaces.cards().map(func(card): return PokerFaces.texture(card))


func test_size_and_batch_budget_follow_the_spec():
	assert_eq(PokerFaces.SIZE, Vector2i(320, 465), "烘焙尺寸 = 256×372 × 1.25(2026-10-10:第一人称与悬停大图也不糊)")
	assert_eq(PokerFaces.BATCH_SIZE, 7)


func test_cards_lists_all_52_poker_cards_once():
	var cards := PokerFaces.cards()
	assert_eq(cards.size(), 52)
	var seen := {}
	for card in cards:
		assert_true(PokerCard.is_card(card), str(card))
		seen[card] = true
	assert_eq(seen.size(), 52)


func test_batches_split_into_groups_of_at_most_the_budget():
	var groups := PokerFaces.batches(PokerFaces.cards(), PokerFaces.BATCH_SIZE)
	assert_eq(groups.size(), ceili(52.0 / PokerFaces.BATCH_SIZE))
	var joined := []
	for group in groups:
		assert_between(group.size(), 1, PokerFaces.BATCH_SIZE)
		joined.append_array(group)
	assert_eq(joined, PokerFaces.cards())
	assert_eq(PokerFaces.batches([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]])
	assert_eq(PokerFaces.batches([], 13), [])


func test_before_build_every_card_shows_the_same_placeholder():
	assert_false(PokerFaces.is_built())
	var placeholder := PokerFaces.texture(PokerFaces.cards()[0])
	assert_not_null(placeholder)
	for tex in _all_textures():
		assert_same(tex, placeholder)
	assert_true(placeholder.get_image().has_mipmaps(), "2D 小牌用带 mipmap 的线性过滤")


func test_values_that_are_not_poker_cards_get_the_placeholder():
	await PokerFaces.build(host)
	var placeholder := PokerFaces.texture(PokerCard.MIN_VALUE - 1)
	for value in [CardFaces.BACK, Card.QUEEN, Card.JOKER, PokerCard.MAX_VALUE + 1]:
		assert_same(PokerFaces.texture(value), placeholder, str(value))
	assert_false(_all_textures().has(placeholder))


func test_headless_build_gives_every_card_its_own_mipmapped_texture():
	await PokerFaces.build(host)
	assert_true(PokerFaces.is_built())
	var textures := _all_textures()
	var distinct := {}
	for tex in textures:
		assert_not_null(tex)
		assert_true(tex.get_image().has_mipmaps())
		distinct[tex] = true
	assert_eq(distinct.size(), 52, "每张牌一份纹理")


func test_card_faces_hands_poker_cards_to_poker_faces():
	await PokerFaces.build(host)
	for card in PokerFaces.cards():
		assert_same(CardFaces.texture(card), PokerFaces.texture(card), PokerCard.label(card))


func test_liars_faces_and_their_built_flag_are_unaffected():
	CardFaces.clear()
	await PokerFaces.build(host)
	assert_false(CardFaces.is_built(), "CardFaces.is_built 只管骗子酒馆的 5 张")
	await CardFaces.build(host)
	assert_true(CardFaces.is_built())
	var before := LIARS_KINDS.map(func(kind): return CardFaces.texture(kind))
	PokerFaces.clear()
	await PokerFaces.build(host)
	assert_true(CardFaces.is_built())
	for i in LIARS_KINDS.size():
		assert_same(CardFaces.texture(LIARS_KINDS[i]), before[i], str(LIARS_KINDS[i]))


func test_second_build_reuses_the_cache_and_signals_once():
	var count := [0]
	PokerFaces.built_signal().connect(func(): count[0] += 1)
	await PokerFaces.build(host)
	var first := _all_textures()
	await PokerFaces.build(host)
	assert_eq(_all_textures(), first)
	assert_eq(count[0], 1)


func test_clear_returns_every_card_to_the_placeholder():
	await PokerFaces.build(host)
	var built := PokerFaces.texture(PokerFaces.cards()[5])
	PokerFaces.clear()
	assert_false(PokerFaces.is_built())
	var placeholder := PokerFaces.texture(PokerCard.MIN_VALUE - 1)
	assert_not_same(PokerFaces.texture(PokerFaces.cards()[5]), built)
	for tex in _all_textures():
		assert_same(tex, placeholder)


func test_build_renders_in_batches_within_the_budget():
	PokerFaces.batch_renderer = _fake_renderer()
	await PokerFaces.build(host)
	assert_true(PokerFaces.is_built())
	assert_eq(renders.size(), ceili(52.0 / PokerFaces.BATCH_SIZE))
	var covered := []
	for batch in renders:
		assert_lte(batch.size(), PokerFaces.BATCH_SIZE)
		covered.append_array(batch)
	assert_eq(covered, PokerFaces.cards())
	var tex := PokerFaces.texture(PokerFaces.cards()[0])
	assert_eq(Vector2i(tex.get_size()), PokerFaces.SIZE)
	assert_true(tex.get_image().has_mipmaps(), "抓到的图要补上 mipmap")


func test_concurrent_builds_wait_for_the_first_one():
	PokerFaces.batch_renderer = _fake_renderer()
	var count := [0]
	PokerFaces.built_signal().connect(func(): count[0] += 1)
	PokerFaces.build(host)                 # 第一次:不等它,马上发起第二次
	assert_false(PokerFaces.is_built())
	await PokerFaces.build(host)
	assert_true(PokerFaces.is_built(), "第二次调用要等到第一次生成完才返回")
	assert_eq(renders.size(), ceili(52.0 / PokerFaces.BATCH_SIZE), "不重复生成")
	assert_eq(count[0], 1)


func test_clear_during_a_build_discards_the_stale_batches():
	PokerFaces.batch_renderer = _fake_renderer()
	var count := [0]
	PokerFaces.built_signal().connect(func(): count[0] += 1)
	PokerFaces.build(host)
	PokerFaces.clear()
	await wait_process_frames(SETTLE_FRAMES)
	assert_false(PokerFaces.is_built())
	assert_eq(renders.size(), 1, "打断后不再渲染下一批")
	var placeholder := PokerFaces.texture(PokerCard.MIN_VALUE - 1)
	for tex in _all_textures():
		assert_same(tex, placeholder, "作废那一批不能写回缓存")
	assert_eq(count[0], 0)
	await PokerFaces.build(host)
	assert_true(PokerFaces.is_built(), "clear 之后可以重新生成")


func test_failed_captures_fall_back_to_tinted_textures():
	PokerFaces.batch_renderer = _fake_renderer(Vector2i.ZERO)
	await PokerFaces.build(host)
	assert_true(PokerFaces.is_built())
	var placeholder := PokerFaces.texture(PokerCard.MIN_VALUE - 1)
	for tex in _all_textures():
		assert_not_same(tex, placeholder)
		assert_true(tex.get_image().has_mipmaps())


func test_build_refreshes_cached_card_materials():
	Card3D.clear_materials()   # 别的测试可能缓存过同一张牌的材质
	var card := PokerCard.make(PokerCard.ACE, PokerCard.SPADES)
	var mat := Card3D.material_for(card)
	assert_same(mat.get_shader_parameter("card_texture"), PokerFaces.texture(card), "生成前是占位")
	await PokerFaces.build(host)
	assert_same(mat.get_shader_parameter("card_texture"), PokerFaces.texture(card), "生成完换成正式牌面")
	Card3D.clear_materials()
