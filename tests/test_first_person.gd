extends GutTest
# 第一人称视角(V 切换,规格 2026-10-08-first-person-toggle):
# - 选择存进设置,默认越肩;
# - 第一人称机位在自己的眼睛上(头心 + FP_EYE_OFFSET),跟着脖子偏移(WASD 探头)走,朝向跟着转头(像 CS,2026-10-09 用户要求);
# - 自己的头(含眼、眉、耳、帽、脖子)只投影不渲染,换回越肩、复位、离座拍特写时恢复;
# - 手里的牌扇在画面里、在近裁剪面之前、不被自己的身体与手臂挡住(骗子酒馆与德州,探头时也一样);
# - 导演拍完特写回到当前视角的座位机位;出局观战时按 V 只改设置,镜头不动。


const SETTLE := 1.2          # 秒:登场缩放与前倾插值走完
const NECK_SETTLE := 0.8     # 秒:脖子弹簧追到目标
const ASPECTS := [16.0 / 9.0, 4.0 / 3.0]
const MIN_DEPTH := 0.15      # 牌离眼睛至少这么远(近裁剪面 0.03)
const MAX_BLOCKED := 0.02
const PEEKS := [Vector3.ZERO, Vector3(0.45, 0, -0.35), Vector3(-0.6, 0, 0), Vector3(0, 0, -0.85), Vector3(0.85, 0, 0)]
const SETTINGS := "user://test_first_person_settings.cfg"


class StubApp:
	extends Node
	var world: TableWorld
	var tavern: Node
	var post_fx = null
	var settings_path := SETTINGS
	var toasts: Array = []

	func toast(text: String, _color := Color.WHITE) -> void:
		toasts.append(text)


class StubTavern:
	extends Node
	var camera_rig: CameraRig


class StubScreen:
	extends Node
	var my_pid := 1


var world: TableWorld
var me: Patron


func before_each():
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func after_all():
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _setup(players: Array, poker := false) -> void:
	world = TableWorld.new(null)
	add_child_autofree(world)
	if poker:
		world.configure_table(SeatLayout.POKER_TABLE_RADIUS)
	world.arrange(players, 1, true, false)
	me = world.patrons[1]


func _liars_hand() -> void:
	world.cards.attach_hand(me.fan)
	world.cards.sync({1: 5, 2: 5}, [Card.QUEEN, Card.KING, Card.ACE, Card.JOKER, Card.QUEEN])


# —— 设置 ——

func test_default_is_first_person():
	# 2026-10-09 用户要求默认第一人称;存过「越肩」的人照旧
	assert_true(Settings.first_person(SETTINGS))


func test_toggle_persists_to_settings():
	_setup([{"pid": 1}, {"pid": 2}])
	var rig := _rig()
	var cam := SeatCamera.new(rig, world, 1, SETTINGS)
	add_child_autofree(cam)
	assert_true(cam.first_person, "默认第一人称")
	assert_false(cam.toggle())
	assert_false(Settings.first_person(SETTINGS), "存进设置")
	assert_false(world.first_person, "牌桌跟着换")
	assert_false(autofree(SeatCamera.new(rig, world, 1, SETTINGS)).first_person, "下次进牌桌沿用")
	assert_true(cam.toggle())
	assert_true(Settings.first_person(SETTINGS))


func test_unknown_setting_falls_back_to_first_person():
	Settings.set_value(Settings.KEY_CAMERA_MODE, "sideways", SETTINGS)
	assert_true(Settings.first_person(SETTINGS))
	assert_push_warning("不是已知视角")


# —— 机位 ——

func test_first_person_eye_sits_on_the_head_and_follows_the_neck():
	_setup([{"pid": 1}, {"pid": 2}])
	await wait_seconds(SETTLE)
	var seat_basis := world.seat_transform(world.seat_angles[1]).basis
	var rest := world.first_person_view(1).origin
	assert_lt(rest.distance_to(me.head_position() + seat_basis * Patron.FP_EYE_OFFSET), 0.05, "眼睛 = 头心 + 偏移")
	assert_lt(rest.distance_to(world.first_person_rest_view(1).origin), 0.04, "坐着时就在静止机位上")
	var peek := Vector3(0.4, 0, -0.3)
	me.set_neck_target(peek)
	await wait_seconds(NECK_SETTLE)
	var moved := world.first_person_view(1).origin - rest
	assert_lt(moved.distance_to(seat_basis * peek), 0.03, "探头时镜头跟着头走:%s" % moved)
	assert_true(world.first_person_view(1).basis.is_equal_approx(world.first_person_rest_view(1).basis), "朝向不跟着变")


func test_first_person_turns_with_the_head():
	# 像 CS:头转向哪边,镜头就跟着转过去;不看任何东西时朝向回到静止机位
	_setup([{"pid": 1}, {"pid": 2}])
	await wait_seconds(SETTLE)
	var rest_forward := -world.first_person_rest_view(1).basis.z
	var eye := me.eye_position()
	var seat_basis := world.seat_transform(world.seat_angles[1]).basis
	var right := eye + seat_basis * Vector3(2.0, 0.0, -1.0)
	me.look_at_point(right)
	await wait_seconds(1.0)
	var forward := -world.first_person_view(1).basis.z
	var to_right := (right - eye).normalized()
	assert_gt(forward.dot(to_right), rest_forward.dot(to_right) + 0.1, "镜头朝右转过去了")
	var up := world.first_person_view(1).basis.y
	assert_gt(up.dot(Vector3.UP), 0.9, "不歪头(没有横滚)")
	assert_true(world.first_person_view(1).origin.is_equal_approx(me.eye_position()), "位置仍在眼睛上")


func test_first_person_looks_at_the_table():
	for poker in [false, true]:
		_setup([{"pid": 1}, {"pid": 2}], poker)
		var view := world.first_person_rest_view(1)
		var forward := -view.basis.z
		assert_lt(forward.y, -0.2, "往下看向桌面")
		var center := Vector3(0, SeatLayout.TABLE_TOP, 0)
		assert_gt(forward.dot((center - view.origin).normalized()), 0.99, "桌心在画面正中附近")
		world.queue_free()


func test_rest_view_and_seat_view_follow_the_mode():
	_setup([{"pid": 1}, {"pid": 2}])
	assert_eq(world.seat_view(1), world.third_person_view(1))
	world.set_first_person(true)
	assert_eq(world.seat_view(1), world.first_person_view(1))
	assert_eq(world.rest_view(1, true, PokerRules.STATUS_ACTIVE), world.first_person_view(1))
	assert_eq(world.rest_view(1, true, PokerRules.STATUS_SPECTATING), world.overview_view(), "观战机位不变")
	assert_eq(world.rest_view(1, false, PokerRules.STATUS_WAITING), world.overview_view(), "迟到者不变")


# —— 藏头 ——

func test_head_renders_shadows_only_and_comes_back():
	_setup([{"pid": 1}, {"pid": 2}])
	var parts := _head_parts(me)
	assert_gt(parts.size(), 4)
	var before := parts.map(func(g: GeometryInstance3D) -> Array: return [g.cast_shadow, g.layers])
	me.set_head_hidden(true)
	var cull := _rig().camera.cull_mask
	for g: GeometryInstance3D in parts:
		assert_true(_hidden_from(g, cull), "%s 第一人称时不渲染" % g.name)
	var casters := parts.filter(func(g: GeometryInstance3D) -> bool: return g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	assert_gt(casters.size(), 0, "头照样投影")
	for g: GeometryInstance3D in me.body.find_children("*", "GeometryInstance3D", false, false):
		assert_false(_hidden_from(g, cull), "%s 身体照常显示" % g.name)
	for arm in ["ArmL", "ArmR"]:
		for g: GeometryInstance3D in me.body.get_node(arm).find_children("*", "GeometryInstance3D", true, false):
			if g.visible:
				assert_false(_hidden_from(g, cull), "%s 手臂照常显示" % g.name)
	me.set_head_hidden(false)
	assert_eq(parts.map(func(g: GeometryInstance3D) -> Array: return [g.cast_shadow, g.layers]), before, "换回越肩时原样恢复")


func test_reset_pose_restores_the_head():
	_setup([{"pid": 1}, {"pid": 2}])
	var parts := _head_parts(me)
	var before := parts.map(func(g: GeometryInstance3D) -> int: return g.cast_shadow)
	me.set_head_hidden(true)
	me.reset_pose()
	assert_false(me.is_head_hidden())
	assert_eq(parts.map(func(g: GeometryInstance3D) -> int: return g.cast_shadow), before)


func test_parts_added_to_the_head_while_hidden_are_hidden_too():
	# 番茄印子之类后挂上去的东西
	_setup([{"pid": 1}, {"pid": 2}])
	me.set_head_hidden(true)
	var splat := MeshInstance3D.new()
	splat.mesh = SphereMesh.new()
	me.head.add_child(splat)
	await wait_seconds(0.1)
	assert_eq(splat.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	me.set_head_hidden(false)
	assert_eq(splat.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON)


func test_tomato_splats_on_my_head_are_hidden_in_first_person():
	# 番茄泥挂在 Head 下:进第一人称之前贴上的、之后才贴上的都不渲染,换回越肩都回来
	_setup([{"pid": 1}, {"pid": 2}])
	var fx := BanterFx.new(world)
	add_child_autofree(fx)
	var before := fx.splat(me, Vector3(0, 0.12, -0.25), Vector3(0, 0, -1))
	me.set_head_hidden(true)
	var after := fx.splat(me, Vector3(0.1, 0.15, -0.24), Vector3(0, 0, -1))
	await wait_seconds(0.1)
	var cull := _rig_cull()
	assert_true(_hidden_from(before, cull), "进第一人称前贴上的")
	assert_true(_hidden_from(after, cull), "进第一人称后贴上的")
	me.set_head_hidden(false)
	assert_false(_hidden_from(before, cull))
	assert_false(_hidden_from(after, cull))


func test_my_speech_bubble_hangs_in_front_of_the_eyes_in_first_person():
	_setup([{"pid": 1}, {"pid": 2}])
	await wait_seconds(SETTLE)
	var above := me.speech_anchor()
	assert_gt(above.y, me.head_position().y, "越肩:头顶上方")
	me.set_head_hidden(true)
	var view := world.first_person_view(1)
	var local := view.affine_inverse() * me.speech_anchor()
	var half := tan(deg_to_rad(TableWorld.FIRST_PERSON_FOV) / 2.0)
	assert_gt(-local.z, 0.3, "第一人称:在镜头前")
	assert_lt(absf(local.y), -local.z * half * 0.8, "在画面里")
	assert_gt(local.y, 0.0, "画面上半")


func test_other_patrons_are_never_touched():
	_setup([{"pid": 1}, {"pid": 2}])
	var rig := _rig()
	var cam := SeatCamera.new(rig, world, 1, SETTINGS)
	add_child_autofree(cam)
	cam.set_first_person(true)
	await cam.enter(0.05).finished
	await wait_seconds(0.2)
	assert_true(me.is_head_hidden(), "第一人称坐好后藏头")
	assert_false(world.patrons[2].is_head_hidden(), "别人的头不动")


func test_head_hides_only_while_the_camera_is_at_the_eye():
	_setup([{"pid": 1}, {"pid": 2}])
	var rig := _rig()
	rig.snap(Vector3(0, 2.5, 3.5), Vector3.ZERO)
	var cam := SeatCamera.new(rig, world, 1, SETTINGS)
	add_child_autofree(cam)
	cam.set_first_person(true)
	cam.enter(0.6)
	await wait_seconds(0.1)
	assert_false(me.is_head_hidden(), "镜头还在远处:头照常显示")
	await wait_seconds(0.9)
	assert_true(me.is_head_hidden(), "到了眼睛上:藏头")
	cam.leave()
	rig.move_to(world.focus_view(1), 0.5)   # 拍自己的特写(开枪)
	await wait_seconds(0.45)
	assert_false(me.is_head_hidden(), "离座拍特写:镜头一出头就露出来")
	await cam.enter(0.05).finished
	await wait_seconds(0.2)
	assert_true(me.is_head_hidden())
	cam.toggle()
	await wait_seconds(0.3)
	assert_false(me.is_head_hidden(), "换回越肩:镜头退出头外就露出来")
	await wait_seconds(0.3)
	assert_lt(rig.global_position.distance_to(world.third_person_view(1).origin), 0.01, "回到越肩机位")


func test_head_hides_whenever_the_camera_is_inside_it():
	# 翻牌机位在自己座位上方(越肩视角也一样)、开局运镜穿过后脑:镜头在头里就藏头,出来就露出
	_setup([{"pid": 1}, {"pid": 2}, {"pid": 3}])
	var rig := _rig()
	var cam := SeatCamera.new(rig, world, 1, SETTINGS)
	add_child_autofree(cam)
	cam.set_first_person(false, false)
	await cam.enter(0.05).finished
	await wait_seconds(0.1)
	assert_false(me.is_head_hidden(), "越肩:头照常显示")
	cam.leave()
	var reveal := world.reveal_view(2)
	assert_lt(reveal.origin.distance_to(me.head_position()), SeatCamera.HEAD_INSIDE, "前提:翻牌机位在自己头里")
	rig.snap(reveal.origin, reveal.origin - reveal.basis.z)
	await wait_seconds(0.1)
	assert_true(me.is_head_hidden(), "翻牌机位:藏头,看不到自己的胡须和耳朵")
	assert_false(world.patrons[2].is_head_hidden(), "别人的头不动")
	rig.snap(world.overview_view().origin, Vector3.ZERO)
	await wait_seconds(0.1)
	assert_false(me.is_head_hidden(), "镜头离开:头露出来")


func test_rebuilt_patron_gets_hidden_and_the_old_one_released():
	_setup([{"pid": 1}, {"pid": 2}])
	var rig := _rig()
	var cam := SeatCamera.new(rig, world, 1, SETTINGS)
	add_child_autofree(cam)
	cam.set_first_person(true)
	await cam.enter(0.05).finished
	await wait_seconds(0.2)
	var old := me
	assert_true(old.is_head_hidden())
	old.die()
	await wait_seconds(0.1)
	assert_false(old.is_head_hidden(), "出局:头露出来")
	world.revive_all()
	me = world.patrons[1]
	await wait_seconds(0.8)
	assert_true(me.is_head_hidden(), "复活后的新酒客照样藏头")


func test_leaving_the_screen_shows_the_head_and_stops_following():
	_setup([{"pid": 1}, {"pid": 2}])
	var rig := _rig()
	var cam := SeatCamera.new(rig, world, 1, SETTINGS)
	add_child(cam)
	cam.set_first_person(true)
	await cam.enter(0.05).finished
	await wait_seconds(0.2)
	assert_true(me.is_head_hidden())
	cam.free()
	assert_false(me.is_head_hidden(), "换屏(等待厅)看得见自己")
	assert_false(rig.is_following(), "跟随回调属于牌桌,随之停下")


# —— 手里的牌 ——

func test_liars_hand_is_in_view_and_clear_of_own_body():
	for species in Species.count():
		_setup([{"pid": 1, "species": species}, {"pid": 2, "species": (species + 1) % Species.count()}])
		_liars_hand()
		world.set_first_person(true)
		me.set_head_hidden(true)
		me.set_active(true)   # 轮到自己时再前倾
		await wait_seconds(SETTLE)
		for peek in PEEKS:
			me.set_neck_target(peek)
			await wait_seconds(NECK_SETTLE)
			_assert_cards_visible(world.cards.my_cards, "%s 探头 %s" % [Species.IDS[species], peek])
		world.queue_free()


func test_selected_cards_stay_in_view():
	_setup([{"pid": 1}, {"pid": 2}])
	_liars_hand()
	world.set_first_person(true)
	world.cards.set_selection({0: true, 1: true, 2: true, 3: true, 4: true}, -1)
	me.set_head_hidden(true)
	await wait_seconds(SETTLE)
	_assert_cards_visible(world.cards.my_cards, "全部选中抬起")


func test_toggling_re_presents_the_hand():
	_setup([{"pid": 1}, {"pid": 2}])
	_liars_hand()
	world.set_first_person(false)
	var third := me.fan.transform
	world.set_first_person(true)
	assert_true(me.holds_fan_first_person())
	assert_false(me.fan.transform.is_equal_approx(third))
	world.set_first_person(false)
	assert_false(me.holds_fan_first_person())
	assert_true(me.fan.transform.is_equal_approx(third), "换回越肩时牌扇回到原位")


func test_cards_can_be_picked_through_the_first_person_camera():
	_setup([{"pid": 1}, {"pid": 2}])
	_liars_hand()
	world.set_first_person(true)
	await wait_seconds(SETTLE)
	var eye := world.first_person_view(1).origin
	for i in world.cards.my_cards.size():
		var card: Card3D = world.cards.my_cards[i]
		var hit := card.global_transform * Vector3(0, 0, -Card3D.HEIGHT * 0.3)   # 牌的上半截(不被右边那张盖住)
		assert_eq(world.cards.pick(eye, (hit - eye).normalized()), i, "点第 %d 张" % i)


func test_dead_player_fan_is_left_on_the_lap():
	_setup([{"pid": 1}, {"pid": 2}])
	_liars_hand()
	me.die()
	await wait_seconds(0.6)
	var lap := me.fan.transform
	world.set_first_person(true)
	assert_true(me.fan.transform.is_equal_approx(lap), "出局后换视角不动扣在大腿上的牌")


func test_poker_hole_cards_are_in_view_and_clear_of_own_body():
	for species in Species.count():
		_setup([1, 2, 3, 4].map(func(pid): return {"pid": pid, "species": (species + pid - 1) % Species.count()}), true)
		var cards := PokerCards.new(world)
		world.poker_root.add_child(cards)
		world.set_first_person(true)
		me.set_head_hidden(true)
		await cards.deal_hole([2, 3, 4, 1], 1, [PokerCard.make(14, 0), PokerCard.make(13, 0)])
		assert_true(me.holds_fan_first_person(), "德州底牌也拿在镜头前")
		await wait_seconds(SETTLE)
		var held := me.fan.get_children().filter(func(n: Node) -> bool: return n is Card3D)
		assert_eq(held.size(), 2)
		for peek in [Vector3.ZERO, Vector3(-0.4, 0, -0.3), Vector3(0.6, 0, 0)]:
			me.set_neck_target(peek)
			await wait_seconds(NECK_SETTLE)
			_assert_cards_visible(held, "德州 %s 探头 %s" % [Species.IDS[species], peek])
		world.queue_free()


func test_poker_fan_follows_the_toggle():
	_setup([1, 2, 3, 4].map(func(pid): return {"pid": pid}), true)
	var cards := PokerCards.new(world)
	world.poker_root.add_child(cards)
	await cards.deal_hole([2, 3, 4, 1], 1, [PokerCard.make(14, 0), PokerCard.make(13, 0)])
	var seat := world.seat_transform(world.seat_angles[1])
	world.set_first_person(true)
	assert_true(me.holds_fan_first_person(), "第一人称:拿在镜头前")
	world.set_first_person(false)
	assert_false(me.holds_fan_first_person())
	assert_true(me.fan.transform.is_equal_approx(PokerLayout.fan_transform(seat, world.third_person_view(1).origin)))


# —— 导演 ——

func test_director_returns_to_the_first_person_seat_after_a_reveal():
	var director := _director([{"pid": 1}, {"pid": 2}])
	director.seat_camera.set_first_person(true)
	await director.back_to_seat(0.05)
	await wait_seconds(0.2)
	assert_true(me.is_head_hidden())
	director._leave_seat()
	var rig := director.rig
	rig.move_to(world.reveal_view(2), 0.05)
	await wait_seconds(0.6)
	assert_true(me.is_head_hidden(), "翻牌机位就在自己头上:照样藏头(否则满屏是自己的胡须和耳朵)")
	assert_almost_eq(rig.camera.fov, CameraRig.DEFAULT_FOV, 0.5, "特写按默认视角取景")
	await director.back_to_seat(0.05)
	await wait_seconds(0.3)
	assert_true(rig.is_following(), "回到第一人称:跟着眼睛")
	assert_lt(rig.global_position.distance_to(world.first_person_view(1).origin), 0.02)
	assert_almost_eq(rig.camera.fov, TableWorld.FIRST_PERSON_FOV, 0.5)
	assert_true(me.is_head_hidden())


func test_director_returns_to_the_shoulder_in_third_person():
	Settings.set_first_person(false, SETTINGS)   # 从越肩开始(默认已是第一人称)
	var director := _director([{"pid": 1}, {"pid": 2}])
	director._leave_seat()
	director.rig.move_to(world.reveal_view(2), 0.05)
	await wait_seconds(0.1)
	await director.back_to_seat(0.05)
	assert_false(director.rig.is_following())
	assert_true(director.rig.global_transform.is_equal_approx(world.third_person_view(1)))
	assert_false(me.is_head_hidden())


func test_toggle_during_the_seat_move_does_not_stall_the_director():
	Settings.set_first_person(false, SETTINGS)   # 从越肩开始(默认已是第一人称)
	# 回座运镜还在走时按 V:导演等的补间不能被打断
	var director := _director([{"pid": 1}, {"pid": 2}])
	director._leave_seat()
	var done := [false]
	var run := func():
		await director.back_to_seat(0.3)
		done[0] = true
	run.call()
	await wait_seconds(0.1)
	director.toggle_camera_mode()
	await wait_seconds(1.0)
	assert_true(done[0], "导演照常回座")
	assert_true(director.rig.is_following(), "回座后切到第一人称")


func test_v_while_dead_only_changes_the_setting():
	Settings.set_first_person(false, SETTINGS)   # 从越肩开始(默认已是第一人称)
	var director := _director([{"pid": 1}, {"pid": 2}])
	var app: StubApp = director.app
	director.spectator = true
	director._leave_seat()
	await director.back_to_seat(0.05)   # 观战俯视
	var before := director.rig.global_transform
	director.toggle_camera_mode()
	await wait_seconds(0.3)
	assert_true(Settings.first_person(SETTINGS), "设置改了")
	assert_false(director.rig.is_following(), "镜头不动")
	assert_true(director.rig.global_transform.is_equal_approx(before))
	assert_false(me.is_head_hidden())
	assert_string_contains(app.toasts.back(), "回到座位后生效")


# —— 工具 ——

func _rig() -> CameraRig:
	var rig := CameraRig.new()
	add_child_autofree(rig)
	return rig


func _director(players: Array) -> TableDirector:
	_setup(players)
	var app := StubApp.new()
	add_child_autofree(app)
	app.world = world
	var tavern := StubTavern.new()
	app.add_child(tavern)
	tavern.camera_rig = CameraRig.new()
	tavern.add_child(tavern.camera_rig)
	app.tavern = tavern
	var screen := StubScreen.new()
	add_child_autofree(screen)
	var hud := TableHud.new()
	add_child_autofree(hud)
	var director := TableDirector.new(screen, app, hud)
	add_child_autofree(director)
	return director


func _head_parts(patron: Patron) -> Array:
	var parts := patron.head.find_children("*", "GeometryInstance3D", true, false)
	parts.append_array(patron.body.get_node("Neck").find_children("*", "GeometryInstance3D", true, false))
	return parts


static func _hidden_from(g: GeometryInstance3D, cull_mask: int) -> bool:
	return g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY or (g.layers & cull_mask) == 0


func _assert_cards_visible(cards: Array, label: String) -> void:
	# 每张牌的采样点:在第一人称视锥里(16:9 与 4:3)、离眼睛不太近,从眼睛看过去不被自己身上还在渲染的网格挡住
	var view := world.first_person_view(1)
	var half := tan(deg_to_rad(TableWorld.FIRST_PERSON_FOV) / 2.0)
	var total := 0
	var blocked := 0
	for card: Card3D in cards:
		for i in 5:
			for j in 5:
				var p: Vector3 = card.global_transform * Vector3((i / 4.0 - 0.5) * Card3D.WIDTH * 0.95, 0.0, (j / 4.0 - 0.5) * Card3D.HEIGHT * 0.95)
				var local := view.affine_inverse() * p
				var depth := -local.z
				assert_gt(depth, MIN_DEPTH, "%s:牌在近裁剪面之前" % label)
				assert_lt(absf(local.y), depth * half * 0.97, "%s:牌在画面上下边之内" % label)
				for aspect in ASPECTS:
					assert_lt(absf(local.x), depth * half * aspect * 0.97, "%s:牌在 %.2f 画面左右边之内" % [label, aspect])
				total += 1
				if _blocked(view.origin, p):
					blocked += 1
	assert_lte(float(blocked) / total, MAX_BLOCKED, "%s:被自己挡住 %d/%d" % [label, blocked, total])


func _blocked(eye: Vector3, point: Vector3) -> bool:
	# 自己身上还在渲染的网格(藏起来的头不算,牌扇里的牌不算)
	var cull := _rig_cull()
	for node in me.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree() or me.fan.is_ancestor_of(mesh) or _hidden_from(mesh, cull):
			continue
		if (mesh.global_transform * mesh.get_aabb()).intersects_segment(eye, point) == null:
			continue
		var local := mesh.global_transform.affine_inverse()
		var a := local * eye
		var b := local * point
		var faces := mesh.mesh.get_faces()
		for k in range(0, faces.size(), 3):
			if Geometry3D.segment_intersects_triangle(a, b, faces[k], faces[k + 1], faces[k + 2]) != null:
				return true
	return false


func _rig_cull() -> int:
	return (1 << 20) - 1 & ~MeshKit.LAYER_LOCAL_HIDDEN


func test_cursor_maps_to_a_fixed_direction_in_the_rest_view():
	# 第一人称时光标按「没转头时的画面」换算方向:镜头转过去之后光标不动,头也不会一直转下去
	var view := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var size := Vector2(1280, 720)
	assert_true(SeatGaze.rest_ray(view, size / 2.0, size, 72.0).is_equal_approx(Vector3(0, 0, -1)), "正中 = 正前方")
	var right := SeatGaze.rest_ray(view, Vector2(1280, 360), size, 72.0)
	assert_almost_eq(atan2(right.x, -right.z), atan(tan(deg_to_rad(36.0)) * 1280.0 / 720.0), 0.001, "右边缘 = 半个水平视角")
	var down := SeatGaze.rest_ray(view, Vector2(640, 720), size, 72.0)
	assert_almost_eq(asin(down.y), -deg_to_rad(36.0), 0.001, "下边缘 = 往下半个垂直视角")

