extends GutTest
# 炸弹猫道具效果层(无头,加速):BombCatProps 的网格 / 材质缓存与共享、每个效果入口都建出自己的根节点并演完自己释放、
# 效果件一律不投影、粒子数不超上限、×N 徽章跟着还欠的回合数走、偷看浮起来的牌与转手的牌只有当事人看得到正面、拆台全部收走。


const C := preload("res://src/core/bomb_cat/bomb_cat_card.gd")
const ME := 1
const SPEED := 12.0

var world: TableWorld
var cards: BombCatCards
var fx: BombCatFx
var kinds: Array = []
var saved_scale := 1.0


func before_each():
	saved_scale = Engine.time_scale
	Engine.time_scale = SPEED
	BombCatFaces.clear()
	world = TableWorld.new(null)
	add_child_autofree(world)
	world.arrange([{"pid": 1}, {"pid": 2}, {"pid": 3}], ME, true, false)
	cards = BombCatCards.new(world)
	cards.my_pid = ME
	world.poker_root.add_child(cards)
	fx = BombCatFx.new(world)
	fx.my_pid = ME
	world.poker_root.add_child(fx)
	kinds = []
	fx.spawned.connect(func(kind: String): kinds.append(kind))


func after_each():
	Engine.time_scale = saved_scale
	BombCatFaces.clear()


func _game_wait(seconds: float) -> void:
	# 按游戏时间等(跟着 Engine.time_scale 加速)
	await get_tree().create_timer(seconds).timeout


func _drained() -> bool:
	return fx.active_count() == 0


func _all_geometry(root: Node) -> Array:
	return root.find_children("*", "GeometryInstance3D", true, false)


# —— 网格与材质 ——

func test_prop_meshes_are_cached_and_share_materials():
	assert_same(BombCatProps.pan(), BombCatProps.pan(), "平底锅只建一份")
	for id in BombCatProps.SNACKS:
		var mesh := BombCatProps.snack(id)
		assert_same(mesh, BombCatProps.snack(id), "%s 只建一份" % id)
		assert_same(mesh.surface_get_material(0), WorldMaterials.prop(), "零食用道具共享材质")
	for mesh in [BombCatProps.kitty_body(), BombCatProps.kitty_eyes(), BombCatProps.kitty_fuse(), BombCatProps.magnifier(),
			BombCatProps.snip_half(1.0), BombCatProps.snip_half(-1.0), BombCatProps.heart(), BombCatProps.bow(), BombCatProps.star(),
			BombCatProps.stamp()]:
		assert_same(mesh.surface_get_material(0), WorldMaterials.prop())
	for mesh in [BombCatProps.ring(), BombCatProps.paw_print(), BombCatProps.streak(), BombCatProps.stamp_mark(), BombCatProps.cone()]:
		assert_same(mesh.surface_get_material(0), BombCatProps.fx_material(false), "平放薄片共用一份材质")
	for mesh in [BombCatProps.bubble(), BombCatProps.badge(), BombCatProps.glint()]:
		assert_same(mesh.surface_get_material(0), BombCatProps.fx_material(true), "公告板薄片共用一份材质")
	assert_ne(BombCatProps.fx_material(false), BombCatProps.fx_material(true))
	var first := BombCatProps.fx_material(false)
	BombCatProps.clear_cache()
	assert_ne(BombCatProps.fx_material(false), first, "clear_cache 之后重建")


# —— 每个效果:建出来、演完自己释放 ——

func _play_everything() -> void:
	fx.skip(2, 3)
	fx.pass_turns(2, 3, 2)
	fx.peek_glass(2, 0.6)
	fx.shuffle_stars(world.to_global(BombCatLayout.deck_position()), 0.8)
	fx.plead(3)
	fx.heart_pop(world.head_position(3))
	fx.nope_stamp(world.to_global(BombCatLayout.discard_position()), 1, 0.24)
	fx.nope_stamp(world.to_global(BombCatLayout.discard_position()), 2, 0.24)
	fx.snack_hop(C.SNACK_BANANA, 3, world.to_global(BombCatLayout.discard_position()), world.head_position(2))
	var spot := fx.spotlight(3, C.DEFUSE, 3.0)
	fx.paw_trail(2, 3)
	fx.bomb_pop(world.to_global(BombCatLayout.TABLE_FOCUS) + Vector3(0, 0.2, 0), 0.1)
	await _game_wait(0.15)
	fx.kitty_panic(0.5, [0.0, 0.2])
	fx.kitty_snip(0.4)
	await _game_wait(0.6)
	fx.kitty_tiptoe(world.to_global(BombCatLayout.deck_position()), Vector3.RIGHT)
	fx.bomb_pop(world.to_global(BombCatLayout.TABLE_FOCUS), 0.0)
	fx.kaboom(world.to_global(BombCatLayout.TABLE_FOCUS), 3)
	fx.dismiss(spot)


func test_every_effect_spawns_and_frees_itself():
	await _play_everything()
	for kind in ["skip", "pass_turns", "peek", "shuffle", "beg", "heart_pop", "nope", "snack", "spotlight", "paw_trail", "bomb",
			"defuse", "kaboom", "tuft", "text", "puffs", "ring", "stars"]:
		assert_has(kinds, kind, "%s 建出了效果" % kind)
	await _game_wait(0.5)
	assert_has(kinds, "stamp_mark", "印章盖下去留了印子")
	assert_eq(fx.badge_text(), "×2", "平底锅敲中时冒出 ×2")
	fx.clear_stamps()
	fx.set_owed(null, 0)
	await wait_until(_drained, 8.0, "效果演完全部释放")
	assert_eq(fx.active_count(), 0, "没有留下任何效果节点")
	assert_null(fx.kitty())


func test_effect_nodes_cast_no_shadows_and_cap_particles():
	await _play_everything()
	await _game_wait(0.3)
	var geometry := _all_geometry(fx)
	assert_gt(geometry.size(), 10)
	for node in geometry:
		assert_eq((node as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s 不投影" % node.name)
	for root in fx.get_children():
		var alive := 0
		for p in root.find_children("*", "GPUParticles3D", true, false) + ([root] if root is GPUParticles3D else []):
			alive += (p as GPUParticles3D).amount
		assert_lte(alive, BombCatFx.MAX_PARTICLES, "%s 粒子数不超上限" % root.name)


func test_clear_and_teardown_free_everything():
	await _play_everything()
	assert_gt(fx.active_count(), 0)
	world.clear_poker()
	await get_tree().process_frame
	assert_eq(world.poker_root.get_child_count(), 0, "拆台收走效果层与牌层")


# —— ×N 徽章 ——

func test_badge_follows_the_owed_turns():
	fx.set_owed(2, 4)
	assert_eq(fx.badge_pid(), 2)
	assert_eq(fx.badge_text(), "×4")
	fx.set_owed(2, 3)
	assert_eq(fx.badge_text(), "×3", "摸了一张:还欠 3 回合")
	assert_eq(fx.badge_pid(), 2)
	fx.set_owed(2, 1)
	assert_eq(fx.badge_text(), "", "只剩这一回合:收起")
	assert_null(fx.badge_pid())
	fx.set_owed(3, 2)
	assert_eq(fx.badge_pid(), 3)
	fx.set_owed(2, 5)
	assert_eq(fx.badge_pid(), 2, "同时只挂一个:换人就挪过去")
	assert_eq(fx.badge_text(), "×5")
	fx.set_owed(9, 3)
	assert_null(fx.badge_pid(), "不在桌上的人不挂")
	await wait_until(_drained, 3.0, "收起的徽章释放")


# —— 隐藏信息 ——

func test_peek_rise_shows_faces_only_when_given():
	cards.sync({1: 3, 2: 3, 3: 3}, [C.SKIP, C.NOPE, C.BEG], 20, 0, [])
	cards.peek_rise([], 3, world.head_position(2))
	var others := cards.rising_nodes()
	assert_eq(others.size(), 3, "牌堆顶三张浮起来")
	for card in others:
		assert_true(card.is_back(), "别人偷看:一律牌背")
	var faces := [C.BOMB, C.SHUFFLE, C.SNACK_FISH]
	cards.peek_rise(faces, 3, world.head_position(ME))
	assert_eq(cards.rising_nodes().map(func(c): return c.card_id), faces, "自己偷看:看到私有视图里的三张")
	cards.peek_rise(["bogus"], 1, world.head_position(ME))
	assert_true(cards.rising_nodes()[0].is_back(), "坏 id 当牌背")
	cards.peek_sink()
	await wait_until(func(): return cards.rising_nodes().is_empty() and cards.find_children("PeekRise*", "", false, false).is_empty(), 3.0)


func test_transfer_face_only_for_the_receiver():
	cards.sync({1: 3, 2: 3, 3: 3}, [C.SKIP, C.NOPE, C.BEG], 20, 0, [])
	var seen := []
	await cards.transfer(2, 3, "", func(card): seen.append(card.card_id))
	assert_eq(seen, [BombCatFaces.BACK], "别人之间转手:牌背")
	seen = []
	await cards.transfer(2, ME, C.DEFUSE, func(card): seen.append(card.card_id))
	assert_eq(seen, [C.DEFUSE], "转给自己:看得到是哪张")
	seen = []
	await cards.transfer(ME, 3, C.SKIP, func(card): seen.append(card.card_id))
	assert_eq(seen, [BombCatFaces.BACK], "自己给出去:飞行中对别人是牌背")


func test_shuffle_tornado_is_temporary():
	cards.sync({1: 3, 2: 3, 3: 3}, [C.SKIP, C.NOPE, C.BEG], 20, 0, [])
	var before := cards.deck_count
	cards.shuffle()
	await _game_wait(0.3)
	assert_gt(cards.tornado_nodes().size(), 3, "龙卷风里转着一圈牌")
	await wait_until(func(): return cards.tornado_nodes().is_empty(), 3.0)
	assert_eq(cards.deck_count, before, "洗牌不改张数")
	await _game_wait(BombCatCards.SHUFFLE_BOUNCE * 2.0)
	assert_eq(cards.find_children("Tornado*", "", false, false).size(), 0, "龙卷风的牌全部释放")
