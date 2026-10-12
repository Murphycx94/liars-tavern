extends GutTest
# 场景预算(无头):用截图/性能探针同一个展台场景(tools/showcase.gd:4 名酒客、手牌、左轮)检查清单类指标,
# draw call 与帧时间只能由 tools/perf_probe.gd 在窗口里测。

const SceneCensus := preload("res://tools/scene_census.gd")

var _tavern: Tavern
var _showcase: Node


func before_all():
	_tavern = Tavern.new()
	add_child(_tavern)
	_showcase = load("res://tools/showcase.gd").new()
	add_child(_showcase)
	Engine.time_scale = 8.0   # 展台里有发牌、出牌、举枪等补间,无头下加速走完
	await _showcase.build(_tavern)
	Engine.time_scale = 1.0


func after_all():
	Engine.time_scale = 1.0
	_showcase.free()
	_tavern.free()


func _meshes() -> Array:
	return _tavern.find_children("*", "MeshInstance3D", true, false)


func test_small_parts_do_not_cast_shadows():
	var offenders := []
	for inst: MeshInstance3D in _meshes():
		if inst.has_meta(&"force_shadow") or inst.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		if MeshKit.caster_size(inst) < MeshKit.SMALL_CASTER:
			offenders.append("%s (%.3f m)" % [inst.get_path(), MeshKit.caster_size(inst)])
	assert_eq(offenders, [], "小于 8 cm 的件不该投影")


func test_floor_and_solid_wall_panels_do_not_cast_shadows():
	var room := _tavern.get_node("Room")
	assert_eq(room.get_node("Floor").cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	for prefix in ["WallBack", "WallFront", "WallLeft"]:
		for part in ["Wainscot", "Plaster"]:
			assert_eq(room.get_node(prefix + part).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, prefix + part)
		assert_eq(room.get_node(prefix + "Rail").cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, prefix + "Rail")


func test_window_wall_keeps_casting_so_the_moonbeam_keeps_its_shape():
	var room := _tavern.get_node("Room")
	var parts := room.get_children().filter(func(n): return String(n.name).begins_with("WindowWall"))
	assert_gt(parts.size(), 0)
	for part: MeshInstance3D in parts:
		assert_eq(part.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, part.name)


func test_paws_hats_and_cards_still_cast_shadows():
	for patron in _tavern.find_children("*", "Patron", true, false):
		var hand: Node3D = patron.right_hand
		var paw := hand.get_children().filter(func(n): return n is MeshInstance3D)
		assert_eq(paw[0].cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "爪")
	var cards := _tavern.find_children("*", "Card3D", true, false)
	assert_gt(cards.size(), 0)
	for mesh: MeshInstance3D in cards[0].find_children("*", "MeshInstance3D", true, false):
		assert_ne(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "牌")


func test_census_is_within_current_limits():
	var census := SceneCensus.count(_tavern)
	assert_lte(census["shadow_lights"], 3)
	assert_lte(census["lights"], 16)


func test_all_flames_share_one_material_with_distinct_seeds():
	var flames := _meshes().filter(func(m: MeshInstance3D):
		return m.material_override is ShaderMaterial and m.material_override.shader == WorldMaterials.FLAME_SHADER)
	assert_gt(flames.size(), 10)
	var materials := {}
	var seeds := {}
	for flame: MeshInstance3D in flames:
		materials[flame.material_override] = true
		seeds[flame.get_instance_shader_parameter("seed")] = true
	assert_eq(materials.size(), 1, "火焰共用一份材质")
	assert_eq(seeds.size(), flames.size(), "每簇火焰的种子不同,相邻火苗不同步")


func test_cards_share_one_face_mesh():
	var cards := _tavern.find_children("*", "Card3D", true, false)
	assert_gt(cards.size(), 1)
	var meshes := {}
	for card in cards:
		for inst: MeshInstance3D in card.find_children("*", "MeshInstance3D", true, false):
			meshes[inst.mesh] = true
	assert_eq(meshes.size(), 1, "所有牌的正反面共用一份网格")


func test_each_patron_is_merged_per_animation_pivot():
	for patron: Patron in _tavern.find_children("*", "Patron", true, false):
		var meshes := patron.find_children("*", "MeshInstance3D", true, false).filter(func(m: MeshInstance3D):
			return m.is_visible_in_tree() and not patron.fan.is_ancestor_of(m) and not _under_revolver(m))
		assert_lte(meshes.size(), 16, "每名酒客可见网格(含椅子,不含手牌与左轮)")
		var materials := {}
		for m: MeshInstance3D in meshes:
			if m.name == "Chair":
				continue
			for s in m.mesh.get_surface_count():
				var mat := m.get_active_material(s)
				if mat != null:
					materials[mat] = true
		assert_lte(materials.size(), 2, "每名酒客材质(不含椅子):酒客共享材质 + 眼睛")
		for pivot in ["Figure/Body", "Figure/Body/Neck", "Figure/Body/Head", "Figure/Body/Head/Hat", "Figure/Body/ArmL", "Figure/Body/ArmR", "Figure/Body/ArmR/Hand", "Figure/Body/Fan"]:
			assert_not_null(patron.get_node_or_null(pivot), "动画枢轴 %s 还在" % pivot)


func _under_revolver(node: Node) -> bool:
	while node != null:
		if node is Revolver3D:
			return true
		node = node.get_parent()
	return false


func test_chairs_share_one_mesh():
	var chairs := {}
	for patron: Patron in _tavern.find_children("*", "Patron", true, false):
		chairs[patron.get_node("Chair").mesh] = true
	assert_eq(chairs.size(), 1)


func test_bottles_are_opaque_multimeshes_per_shape():
	var bar := _tavern.get_node("Bar")
	var multimeshes := bar.get_children().filter(func(n): return n is MultiMeshInstance3D)
	assert_between(multimeshes.size(), 1, Bottles.KINDS.size())
	var total := 0
	for inst: MultiMeshInstance3D in multimeshes:
		total += inst.multimesh.instance_count
		assert_eq(inst.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_eq(inst.multimesh.mesh.surface_get_material(0), WorldMaterials.bottle_glass(), "不透明假玻璃")
	assert_eq(total, 53, "瓶子数量与合批前一样(同一个随机种子)")
	var glass_left := bar.find_children("*", "MeshInstance3D", true, false).filter(func(m):
		return m.material_override is BaseMaterial3D and m.material_override.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
	assert_eq(glass_left.size(), 0, "吧台不再有半透明的瓶子")


func test_moonlight_only_casts_shadows_from_the_window():
	# 月光只让窗框与窗墙投影(光柱保持窗形),酒客和牌桌不再投月光影子;室内灯不管窗户层
	var moon: SpotLight3D = _tavern.get_node("Moon")
	assert_eq(moon.shadow_caster_mask, MeshKit.LAYER_MOON)
	var window_parts := _tavern.get_node("Window").get_children().filter(func(n): return n is GeometryInstance3D)
	window_parts.append_array(_tavern.get_node("Room").get_children().filter(func(n): return String(n.name).begins_with("WindowWall")))
	assert_gt(window_parts.size(), 6)
	for part: GeometryInstance3D in window_parts:
		assert_eq(part.layers, MeshKit.LAYER_MOON, part.name)
	var lamp: Light3D = _tavern.get_node("LampPivot").find_children("*", "SpotLight3D", false, false)[0]
	var fire: Light3D = _tavern.get_node("Fireplace").find_children("*", "OmniLight3D", false, false)[0]
	assert_eq(lamp.shadow_caster_mask, MeshKit.LAYER_WORLD)
	assert_eq(fire.shadow_caster_mask, MeshKit.LAYER_WORLD)
	for patron in _tavern.find_children("*", "Patron", true, false):
		assert_eq(patron.get_node("Figure/Body/BodyMesh").layers, MeshKit.LAYER_WORLD)


func test_each_candle_holder_has_one_light():
	# 每支蜡烛一盏灯时,烛光在近处的脸上叠出亮斑,还多花约 0.4 ms;每个烛台一盏就够
	var holders := _tavern.get_children().filter(func(n): return String(n.name).begins_with("Candles"))
	assert_eq(holders.size(), 2)
	for holder in holders:
		assert_eq(holder.find_children("*", "OmniLight3D", false, false).size(), 1, holder.name)
