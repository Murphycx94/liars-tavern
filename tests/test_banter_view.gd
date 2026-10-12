extends GutTest
# 丢番茄与快捷语的界面(规格 §2、§5、§7,无头):Q 面板开着时数字键只给面板(牌桌的选牌、下注预设收不到),
# Q / Esc 关面板且不漏到牌桌;G 选目标按屏幕投影(≤140 像素、不含自己);T 留给九宫格快捷对话,两个面板互斥;冷却期间不发消息;
# 气泡挂在说话人铭牌之上、同一个人新说一句顶掉旧的、逐字出现、说完停 2.5 秒后自毁。


class FakeBanter:
	extends "res://src/net/banter_net.gd"
	var thrown: Array = []
	var spoken: Array = []
	var tomato_left := 0.0
	var say_left := 0.0

	func in_room() -> bool:
		return true

	func throw_tomato(target_pid: int) -> bool:
		if tomato_left > 0.0:
			return false
		thrown.append(target_pid)
		return true

	func say(phrase_id: int) -> bool:
		if say_left > 0.0:
			return false
		spoken.append(phrase_id)
		return true

	func tomato_cooldown_left() -> float:
		return tomato_left

	func say_cooldown_left() -> float:
		return say_left


class FakeApp:
	extends Node
	var world: TableWorld
	var labels: WorldLabels
	var tavern: Node
	var toasts: Array = []
	var modal := false
	var screen: Node = null
	var banter_view: BanterView = null

	func toast(text: String, _color := Color.WHITE) -> void:
		toasts.append(text)

	func is_modal_open() -> bool:
		return modal

	func current_screen() -> Node:
		return screen


class FakeScreen:
	extends Control
	var quips: QuipController


class KeyProbe:
	extends Node
	var keys := []

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			keys.append(event.keycode)


var banter: FakeBanter
var app: FakeApp
var view: BanterView
var probe: KeyProbe
var camera: Camera3D


func before_each():
	probe = add_child_autofree(KeyProbe.new())   # 在界面之前:界面没拦下的按键它才收得到(牌桌)
	banter = autofree(FakeBanter.new())
	app = add_child_autofree(FakeApp.new())
	camera = Camera3D.new()
	add_child_autofree(camera)
	camera.make_current()
	app.labels = WorldLabels.new(camera)
	add_child_autofree(app.labels)
	app.world = TableWorld.new(null)
	add_child_autofree(app.world)
	view = BanterView.new(app, banter)
	add_child_autofree(view)
	view.set_process(false)   # 由用例控制可见性
	view.visible = true
	# 等一帧再进用例:前一个脚本 await 过时,GUT 在处理组回调里接着跑,回调期间释放的节点地址会被引擎记下、
	# 派发输入时跳过;这里新建的节点碰巧复用了那些地址,push_input 就收不到(偶发)。下一帧那份记录已清空
	await get_tree().process_frame


func _key(keycode: Key, pressed := true) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = pressed
	return ev


func _seat_patrons() -> void:
	# 镜头在 (0, 1.6, 3) 看向桌心;四个人围坐
	camera.global_position = Vector3(0, 1.6, 3.2)
	camera.look_at(Vector3(0, 1.0, 0))
	app.world.arrange([{"pid": 1, "species": 0}, {"pid": 2, "species": 1}, {"pid": 3, "species": 2}, {"pid": 4, "species": 3}],
		1, true, false)
	for pid in app.world.patrons:
		app.world.patrons[pid].scale = Vector3.ONE   # 跳过登场缩放


# —— 快捷语面板与按键 ——

func test_q_opens_the_panel_and_number_keys_say_instead_of_selecting_cards():
	get_viewport().push_input(_key(KEY_Q))
	assert_true(view.is_panel_open())
	get_viewport().push_input(_key(KEY_3))
	assert_eq(banter.spoken, [2], "3 → 第 3 句(编号 2)")
	assert_eq(probe.keys, [], "数字键没有漏到牌桌(不选牌、不选下注预设)")
	assert_false(view.is_panel_open(), "说完自动关上")


func test_keypad_numbers_work_too():
	view.toggle_panel()
	get_viewport().push_input(_key(KEY_KP_8))
	assert_eq(banter.spoken, [7])


func test_number_keys_reach_the_table_when_the_panel_is_closed():
	get_viewport().push_input(_key(KEY_3))
	assert_eq(banter.spoken, [])
	assert_eq(probe.keys, [KEY_3], "面板关着:1–5 照样选牌")


func test_q_and_escape_close_the_panel_without_reaching_the_table():
	view.toggle_panel()
	get_viewport().push_input(_key(KEY_Q))
	assert_false(view.is_panel_open())
	view.toggle_panel()
	get_viewport().push_input(_key(KEY_ESCAPE))
	assert_false(view.is_panel_open())
	assert_eq(probe.keys, [], "Esc 只关面板,不弹「离开牌桌」")


func test_digits_beyond_eight_and_other_keys_pass_through_while_open():
	view.toggle_panel()
	get_viewport().push_input(_key(KEY_9))
	get_viewport().push_input(_key(KEY_C))
	assert_eq(banter.spoken, [])
	assert_true(view.is_panel_open())
	assert_eq(probe.keys, [KEY_9, KEY_C])


func test_say_during_cooldown_sends_nothing_and_keeps_the_panel():
	banter.say_left = 1.0
	view.toggle_panel()
	get_viewport().push_input(_key(KEY_1))
	assert_eq(banter.spoken, [], "冷却期间不发消息")
	assert_true(view.is_panel_open())
	assert_eq(probe.keys, [], "冷却中数字键照样被面板拦下")


func test_clicking_a_phrase_button_says_it():
	view.toggle_panel()
	view._phrase_buttons[5].pressed.emit()
	assert_eq(banter.spoken, [5])


func test_modal_blocks_q_and_g():
	app.modal = true
	get_viewport().push_input(_key(KEY_Q))
	assert_false(view.is_panel_open())
	get_viewport().push_input(_key(KEY_G))
	assert_eq(banter.thrown, [])


func test_g_throws_and_t_is_left_for_the_quip_menu():
	_seat_patrons()
	app.tavern = _rig_holder()
	assert_eq(view.tomato_chip.key_text, "G", "小圆牌写 G")
	get_viewport().push_input(_key(KEY_T))
	assert_eq(probe.keys, [KEY_T], "T 归九宫格快捷对话,界面不拦")
	assert_eq(banter.thrown, [])
	assert_eq(app.toasts, [])
	get_viewport().push_input(_key(KEY_G))
	assert_eq(probe.keys, [KEY_T], "G 被界面用掉,不漏到牌桌")
	assert_eq(banter.thrown.size() + app.toasts.size(), 1, "G 丢番茄(光标下没人就提示)")


func _quip_screen() -> FakeScreen:
	var screen := FakeScreen.new()
	add_child_autofree(screen)
	screen.quips = QuipController.new(app, 1)
	screen.add_child(screen.quips)
	app.screen = screen
	app.banter_view = view
	return screen


func test_q_panel_and_quip_menu_are_mutually_exclusive():
	var quips := _quip_screen().quips
	quips.toggle()
	assert_true(quips.menu.is_open())
	view.toggle_panel()
	assert_true(view.is_panel_open())
	assert_false(quips.menu.is_open(), "开 Q 面板就收起九宫格")
	quips.toggle()
	assert_true(quips.menu.is_open())
	assert_false(view.is_panel_open(), "开九宫格就收起 Q 面板")


func test_quip_menu_digits_do_not_reach_the_q_panel():
	var quips := _quip_screen().quips
	quips.toggle()
	get_viewport().push_input(_key(KEY_2))
	assert_eq(banter.spoken, [], "九宫格开着:数字键归九宫格")
	assert_false(quips.menu.is_open(), "选了一句就收起")
	assert_eq(probe.keys, [], "也没漏到牌桌")


func test_quip_menu_closes_and_ignores_keys_under_a_modal():
	var quips := _quip_screen().quips
	quips.toggle()
	app.modal = true
	await wait_process_frames(2)
	assert_false(quips.menu.is_open(), "说明书 / 确认框盖上来时九宫格收起")
	quips.toggle()
	assert_false(quips.menu.is_open(), "盖着时打不开")
	get_viewport().push_input(_key(KEY_T))
	assert_false(quips.menu.is_open(), "盖着时 T 也不开")


func test_typing_in_a_line_edit_does_not_trigger():
	var edit := LineEdit.new()
	add_child_autofree(edit)
	edit.grab_focus()
	view._unhandled_input(_key(KEY_Q))
	assert_false(view.is_panel_open())


func test_phrase_index_maps_one_to_eight():
	for i in 8:
		assert_eq(BanterView.phrase_index(_key(KEY_1 + i)), i)
	assert_eq(BanterView.phrase_index(_key(KEY_9)), -1)
	assert_eq(BanterView.phrase_index(_key(KEY_1, false)), -1, "松开不算")


# —— 丢番茄:选目标 ——

func test_pick_target_takes_the_nearest_head_within_140_pixels_and_never_self():
	_seat_patrons()
	var patrons := app.world.patrons
	var head3 := camera.unproject_position(patrons[3].head_position())
	assert_eq(BanterView.pick_target(camera, head3 + Vector2(30, 20), patrons, 1), 3)
	assert_eq(BanterView.pick_target(camera, head3 + Vector2(BanterView.PICK_RADIUS + 5, 0), patrons, 1), -1,
		"超过 140 像素不算")
	var head1 := camera.unproject_position(patrons[1].head_position())
	assert_ne(BanterView.pick_target(camera, head1, patrons, 1), 1, "不砸自己")


func test_hidden_or_behind_camera_patrons_are_skipped():
	_seat_patrons()
	var patrons := app.world.patrons
	var head2 := camera.unproject_position(patrons[2].head_position())
	patrons[2].visible = false
	assert_ne(BanterView.pick_target(camera, head2, patrons, 1), 2, "藏起来的(本机观战)不算")
	patrons[2].visible = true
	camera.look_at(Vector3(0, 1.6, 10))   # 转过身去
	assert_eq(BanterView.pick_target(camera, head2, patrons, 1), -1, "在镜头背后不算")


func test_g_throws_at_the_head_under_the_cursor():
	_seat_patrons()
	var head4 := camera.unproject_position(app.world.patrons[4].head_position())
	app.tavern = _rig_holder()
	view.throw_at_cursor(head4)
	assert_eq(banter.thrown, [4])


func test_no_target_shows_a_hint_and_sends_nothing():
	_seat_patrons()
	app.tavern = _rig_holder()
	view.throw_at_cursor(Vector2(-500, -500))
	assert_eq(banter.thrown, [])
	assert_eq(app.toasts, [BanterView.NO_TARGET_TEXT])


func test_cooldown_shakes_the_chip_and_sends_nothing():
	_seat_patrons()
	app.tavern = _rig_holder()
	banter.tomato_left = 2.0
	var head4 := camera.unproject_position(app.world.patrons[4].head_position())
	view.throw_at_cursor(head4)
	assert_eq(banter.thrown, [], "冷却期间不发消息")
	assert_eq(app.toasts, [])


func test_chip_shows_the_cooldown():
	view.tomato_chip.set_cooldown(1.5, Banter.TOMATO_COOLDOWN)
	assert_true(view.tomato_chip.cooling())
	view.tomato_chip.set_cooldown(0.0, Banter.TOMATO_COOLDOWN)
	assert_false(view.tomato_chip.cooling())


# —— 气泡 ——

func test_bubble_sits_above_the_speakers_nameplate_and_replaces_the_old_one():
	_seat_patrons()
	app.tavern = _rig_holder()
	var plate := Nameplate.new("阿熊")
	app.labels.track("plate:2", plate, app.world.patrons[2].nameplate_anchor)
	await wait_process_frames(2)
	var plan := AnimalVoice.layout(1, Banter.PHRASES[0], 2)
	var first := view.show_bubble(2, Banter.PHRASES[0], plan)
	assert_eq(app.labels.get_node_for(BanterView.BUBBLE_KEY % 2), first)
	assert_true(app.labels.anchor_of(BanterView.BUBBLE_KEY % 2) == app.labels.anchor_of("plate:2"), "挂在铭牌的同一个锚点")
	var offset := view.bubble_offset(2)
	assert_lt(offset.y, -plate.size.y, "在铭牌之上")
	var second := view.show_bubble(2, Banter.PHRASES[1], AnimalVoice.layout(1, Banter.PHRASES[1], 2))
	assert_eq(app.labels.get_node_for(BanterView.BUBBLE_KEY % 2), second, "新说一句顶掉旧的")
	assert_true(first.is_queued_for_deletion())


func test_bubble_stacks_above_a_quip_bubble_of_the_same_speaker():
	# 九宫格快捷对话的气泡(固定高度,在声称气泡那一层之上)也在时,快捷语气泡叠在它上面,两个不重叠
	_seat_patrons()
	app.tavern = _rig_holder()
	var anchor: Callable = app.world.patrons[2].nameplate_anchor
	var plate := Nameplate.new("阿熊")
	app.labels.track("plate:2", plate, anchor)
	var quip := SpeechBubble.new(Quips.LINES[0], UiTheme.INK, 30.0)
	app.labels.track(QuipController.KEY_PREFIX % 2, quip, anchor, Vector2(0, TableDirector.BUBBLE_ABOVE_PLATE - 56.0))
	await wait_process_frames(2)
	var bubble := view.show_bubble(2, Banter.PHRASES[0], AnimalVoice.layout(1, Banter.PHRASES[0], 2))
	await wait_process_frames(3)
	assert_true(quip.visible and bubble.visible)
	var mine := Rect2(bubble.position, bubble.size + Vector2(0, BanterBubble.TAIL_LENGTH))
	assert_false(mine.intersects(Rect2(quip.position, quip.size)), "快捷语气泡 %s 与九宫格气泡 %s 不重叠" % [mine, Rect2(quip.position, quip.size)])


func test_bubble_moves_beside_the_plate_when_there_is_no_room_above():
	_seat_patrons()
	app.tavern = _rig_holder()
	var plate := Nameplate.new("阿熊")
	# 铭牌贴着画面上缘:锚点取在画面顶上 70 像素处(铭牌底边在那里,上面只剩几像素)
	var high := camera.project_position(Vector2(get_viewport().get_visible_rect().size.x * 0.5, 70.0), 3.0)
	app.labels.track("plate:3", plate, func(): return high)
	await wait_process_frames(2)
	var bubble := view.show_bubble(3, Banter.PHRASES[2], AnimalVoice.layout(2, Banter.PHRASES[2], 2))
	await wait_process_frames(2)
	var rect := Rect2(bubble.position, bubble.size)
	var plate_rect := Rect2(plate.position, plate.size)
	assert_false(rect.intersects(plate_rect), "不叠在铭牌上:%s vs %s" % [rect, plate_rect])
	assert_true(rect.position.x >= plate_rect.end.x or rect.end.x <= plate_rect.position.x, "挪到铭牌旁边")
	assert_gte(rect.position.y, WorldLabels.EDGE_MARGIN - 0.5, "不出画面上缘")


func test_own_bubble_hangs_above_my_head_and_is_smaller():
	_seat_patrons()
	app.tavern = _rig_holder()
	var mine := view.show_bubble(Net.my_pid(), "好牌啊!", AnimalVoice.layout(0, "好牌啊!", 2))
	if Net.my_pid() != 1:
		pass_test("离线时本机 pid 不是 1")
		return
	await wait_seconds(0.4)   # 弹出动画 0.22 秒
	assert_almost_eq(mine.scale.x, BanterBubble.SMALL_SCALE, 0.05)
	assert_true(app.labels.anchor_of(BanterView.BUBBLE_KEY % 1).is_valid())


func test_speaker_without_patron_gets_a_toast():
	_seat_patrons()
	app.tavern = _rig_holder()
	assert_null(view.show_bubble(55, "快点啦…", AnimalVoice.layout(0, "快点啦…", 2)))
	assert_eq(app.toasts.size(), 1)
	assert_string_contains(app.toasts[0], "快点啦…")


func test_bubble_reveals_character_by_character_and_frees_itself():
	var plan := AnimalVoice.layout(4, "救命啊!", 2)
	var reveal: PackedFloat32Array = plan["reveal"]
	assert_eq(BanterBubble.shown_characters(reveal, 0.0), 0)
	assert_eq(BanterBubble.shown_characters(reveal, reveal[1] + 0.001), 2)
	assert_eq(BanterBubble.shown_characters(reveal, plan["duration"]), "救命啊!".length())
	var bubble := BanterBubble.new("救命啊!", reveal, plan["duration"])
	add_child_autofree(bubble)
	bubble.set_process(false)   # 手动推进时间:不受机器快慢影响
	assert_false(bubble.is_fully_shown())
	assert_almost_eq(bubble.lifetime(), plan["duration"] + BanterBubble.HOLD + BanterBubble.FADE, 0.001)
	bubble._process(reveal[1] + 0.001)
	assert_eq(bubble._label.visible_characters, 2, "跟着音节逐字出现")
	bubble._process(plan["duration"])
	assert_true(bubble.is_fully_shown(), "说完时整句都出来了")
	assert_false(bubble._fading, "说完还要停一会儿")
	bubble._process(BanterBubble.HOLD)
	assert_true(bubble._fading, "停 2.5 秒后开始淡出")
	await wait_seconds(BanterBubble.FADE + 0.2)
	assert_false(is_instance_valid(bubble), "淡出后自毁")


func after_each():
	Engine.time_scale = 1.0


func _rig_holder() -> Node:
	# throw_at_cursor / 气泡侧放读 app.tavern.camera_rig.camera
	var holder := RigHolder.new()
	holder.camera_rig = RigStub.new()
	holder.camera_rig.camera = camera
	autofree(holder)
	autofree(holder.camera_rig)
	return holder


class RigStub:
	extends Node
	var camera: Camera3D


class RigHolder:
	extends Node
	var camera_rig: RigStub
