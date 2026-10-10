class_name BanterView
extends Control
# 丢番茄与快捷语的界面(规格 2026-10-08 丢番茄与快捷语 §2、§5),main 常驻一层,等待厅和两种牌桌共用:
# - G 或鼠标右键:丢番茄,目标是屏幕上离光标最近的酒客头(投影距离 ≤ PICK_RADIUS,不含自己);
#   (原来是 T;上游的九宫格快捷对话 QuipController 用 T,两套都留,番茄让到 G)
# - Q:打开 / 关上快捷语面板;面板开着时 1–8 或点击说出,Q / Esc 关上,数字键只给面板(不再选牌、不选下注预设),说完自动关上;
#   和九宫格互斥:打开一个就收起另一个,数字键不会两边都收到;
# - 左侧两枚小圆牌显示 G / Q 与冷却;
# - 收到 Net.banter 的广播:番茄交给 TableWorld.banter 演;快捷语让说话人的酒客念出来,头顶冒气泡(挂在他铭牌之上)。
# 说明书、确认框开着或输入框有焦点时不响应。


const PICK_RADIUS := 140.0      # 像素:光标离酒客头的屏幕距离上限
const TOMATO_KEY := Banter.TOMATO_KEY   # 丢番茄 G(T 归九宫格快捷对话)
const SAY_KEY := Banter.SAY_KEY
const BUBBLE_KEY := "banter:%d" # WorldLabels 里快捷语气泡的键
const PLATE_KEYS := ["plate:%d", "lobby:%d"]   # 牌桌 / 等待厅的铭牌键:气泡挂在它们之上
const CLAIM_KEY := "bubble:%d"  # 牌桌上声称 /「骗子!」的气泡(TableDirector.BUBBLE_KEY):快捷语气泡再叠在它上面
const QUIP_KEY := QuipController.KEY_PREFIX   # 九宫格快捷对话的气泡:同时在时快捷语气泡叠在它上面
const GAP := 6.0
const PHRASE_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8]
const PHRASE_KP_KEYS := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8]
const CHIP_SIZE := 46.0
const NO_TARGET_TEXT := "把光标移到要砸的人身上"

var app: Node
var banter: Banter = null                 # Net.banter;测试换成别的
var panel: PanelContainer
var tomato_chip: BanterChip
var say_chip: BanterChip
var _bar: VBoxContainer
var _phrase_buttons: Array[Button] = []


func _init(p_app: Node, p_banter: Banter = null) -> void:
	app = p_app
	banter = p_banter


func _ready() -> void:
	name = "BanterView"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if banter == null:
		banter = Net.banter
	_build()
	if banter != null:
		banter.tomato_thrown.connect(_on_tomato)
		banter.said.connect(_on_said)
	visible = false


# —— 布局 ——

func _build() -> void:
	# 左侧居中两枚小圆牌(G 丢番茄、Q 快捷语),快捷语面板在它右边弹出
	_bar = VBoxContainer.new()
	_bar.name = "BanterBar"
	_bar.anchor_top = 0.5
	_bar.anchor_bottom = 0.5
	_bar.offset_left = 20
	_bar.offset_top = -CHIP_SIZE - 6
	_bar.add_theme_constant_override("separation", 10)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)
	var tomato_key := OS.get_keycode_string(TOMATO_KEY)
	tomato_chip = BanterChip.new(BanterChip.TOMATO, tomato_key, "丢番茄:把光标移到某人身上,按 %s 或鼠标右键" % tomato_key)
	_bar.add_child(tomato_chip)
	say_chip = BanterChip.new(BanterChip.SPEECH, "Q", "快捷语:按 Q 打开")
	say_chip.pressed.connect(toggle_panel)
	_bar.add_child(say_chip)
	panel = PanelContainer.new()
	panel.name = "PhrasePanel"
	var style := UiTheme.panel_box(UiTheme.PANEL, Color(UiTheme.BRASS, 0.7), 1, 14)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = 20 + CHIP_SIZE + 14
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.visible = false
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var title := UiTheme.label("快捷语 · 按数字说出 · Q 关上", 14, UiTheme.MUTED)
	box.add_child(title)
	for i in Banter.PHRASES.size():
		var button := UiTheme.button("%d   %s" % [i + 1, Banter.PHRASES[i]])
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 18)
		button.focus_mode = Control.FOCUS_NONE   # 不抢焦点:空格 / 回车照样给牌桌
		button.pressed.connect(say_phrase.bind(i))
		box.add_child(button)
		_phrase_buttons.append(button)


# —— 每帧 ——

func _process(_delta: float) -> void:
	var active := in_room()
	# 说明书、确认框盖上来时一起藏起(确认框和屏幕同一层,本层在它之上)
	visible = active and not (app != null and app.has_method("is_modal_open") and app.is_modal_open())
	if not active:
		close_panel()
		return
	if app != null and app.get("world") != null:
		app.world.banter.voice_enabled = not _muted()
	if banter != null:
		tomato_chip.set_cooldown(banter.tomato_cooldown_left(), Banter.TOMATO_COOLDOWN)
		say_chip.set_cooldown(banter.say_cooldown_left(), Banter.SAY_COOLDOWN)
	if panel.visible and _blocked():
		close_panel()


func in_room() -> bool:
	# 在等待厅或牌桌里(握手完成、名单到了)才显示、才响应
	return banter != null and banter.in_room()


func _muted() -> bool:
	return Sfx.muted


func _blocked() -> bool:
	# 说明书 / 确认框开着、输入框(如昵称)有焦点:不响应
	if app != null and app.has_method("is_modal_open") and app.is_modal_open():
		return true
	return get_viewport() != null and get_viewport().gui_get_focus_owner() is LineEdit


# —— 输入 ——

func _input(event: InputEvent) -> void:
	# 面板开着:数字键、Q、Esc 在这里先拦下,牌桌的选牌 / 下注预设 / 离开确认收不到
	if not panel.visible or not visible:
		return
	var index := phrase_index(event)
	if index >= 0:
		get_viewport().set_input_as_handled()
		say_phrase(index)
	elif _is_key(event, SAY_KEY) or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _blocked():
		return
	if _is_key(event, TOMATO_KEY):
		get_viewport().set_input_as_handled()
		throw_at_cursor(get_viewport().get_mouse_position())
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		throw_at_cursor(event.position)
	elif _is_key(event, SAY_KEY):
		get_viewport().set_input_as_handled()
		toggle_panel()


static func phrase_index(event: InputEvent) -> int:
	# 1–8(主键盘或小键盘)→ 0–7;其余 -1
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return -1
	var index := PHRASE_KEYS.find(event.keycode)
	return index if index >= 0 else PHRASE_KP_KEYS.find(event.keycode)


static func _is_key(event: InputEvent, keycode: Key) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == keycode


# —— 丢番茄 ——

func throw_at_cursor(mouse: Vector2) -> void:
	if banter == null:
		return
	if banter.tomato_cooldown_left() > 0.0:
		tomato_chip.shake()
		return
	var camera: Camera3D = app.tavern.camera_rig.camera
	var target := pick_target(camera, mouse, app.world.patrons, _my_pid())
	if target < 0:
		app.toast(NO_TARGET_TEXT, UiTheme.MUTED)
		return
	banter.throw_tomato(target)


static func pick_target(camera: Camera3D, mouse: Vector2, patrons: Dictionary, my_pid: int,
		radius := PICK_RADIUS) -> int:
	# 屏幕上离光标最近的酒客头(不含自己、不含藏起来的、不含在镜头背后的),超过 radius 像素不算;没有返回 -1
	var best := -1
	var best_d := radius
	for pid in patrons:
		var patron: Patron = patrons[pid]
		if pid == my_pid or not is_instance_valid(patron) or not patron.is_visible_in_tree():
			continue
		var head := patron.head_position()
		if camera.is_position_behind(head):
			continue
		var d := camera.unproject_position(head).distance_to(mouse)
		if d <= best_d:
			best_d = d
			best = pid
	return best


func _on_tomato(from_pid: int, target_pid: int, seed: int) -> void:
	if app != null and app.get("world") != null:
		app.world.banter.throw_tomato(from_pid, target_pid, seed)


# —— 快捷语 ——

func toggle_panel() -> void:
	if panel.visible:
		close_panel()
	elif visible and not _blocked():
		_close_quip_menu()
		panel.visible = true


func close_panel() -> void:
	panel.visible = false


func is_panel_open() -> bool:
	return panel.visible


func _close_quip_menu() -> void:
	# 和九宫格快捷对话互斥:牌桌屏幕上的 QuipController(screen.quips)开着就收起
	if app == null or not app.has_method("current_screen"):
		return
	var screen: Node = app.current_screen()
	var quips: Variant = screen.get("quips") if screen != null else null
	if quips is QuipController and is_instance_valid(quips):
		quips.close_menu()


func say_phrase(index: int) -> void:
	if banter == null:
		return
	if banter.say_cooldown_left() > 0.0:
		say_chip.shake()
		return
	if banter.say(index):
		close_panel()


func _on_said(pid: int, phrase_id: int) -> void:
	if app == null or app.get("world") == null:
		return
	var world: TableWorld = app.world
	var plan: Dictionary = world.banter.say(pid, phrase_id, _species_of(pid))
	show_bubble(pid, Banter.phrase_text(phrase_id), plan)


func show_bubble(pid: int, text: String, plan: Dictionary) -> BanterBubble:
	# 说话人头顶(铭牌之上)冒气泡;同一个人新说一句就顶掉旧的。没有酒客的人(观战、迟到)改成提示条
	var world: TableWorld = app.world
	var patron: Patron = world.patrons.get(pid)
	var labels: WorldLabels = app.labels
	if patron == null or not is_instance_valid(patron):
		labels.untrack(BUBBLE_KEY % pid)
		app.toast("%s:%s" % [_name_of(pid), text], UiTheme.PARCHMENT)
		return null
	var mine := pid == _my_pid()
	var bubble := BanterBubble.new(text, plan["reveal"], plan["duration"], mine)
	var anchor := bubble_anchor(pid)
	labels.track(BUBBLE_KEY % pid, bubble, anchor, bubble_offset.bind(pid, anchor), true)
	return bubble


func bubble_anchor(pid: int) -> Callable:
	# 有铭牌就挂在铭牌的同一个锚点(德州铭牌按座位错开高度,气泡跟着);自己没有铭牌时挂在自己头顶
	var labels: WorldLabels = app.labels
	for key: String in PLATE_KEYS:
		var anchor := labels.anchor_of(key % pid)
		if anchor.is_valid():
			return anchor
	# 绑定酒客自己的方法:酒客被换掉(复活、换形象)后 Callable 失效,WorldLabels 就把气泡藏起来
	var world: TableWorld = app.world
	var patron: Patron = world.patrons[pid]
	if pid == _my_pid():
		return patron.speech_anchor
	if world.is_poker_table():
		return world.nameplate_anchor.bind(pid)
	return patron.nameplate_anchor


func bubble_offset(pid: int, anchor: Callable = Callable()) -> Vector2:
	# 屏幕上往上让开铭牌、牌桌上的声称气泡,再加小三角的长度;上面没地方了(铭牌贴着画面上缘,
	# 越肩机位下对面的人常这样)就挪到铭牌 / 声称气泡旁边,朝画面中间那一侧,不叠在它们身上
	var labels: WorldLabels = app.labels
	var bubble := labels.get_node_for(BUBBLE_KEY % pid)
	var size := bubble.size if bubble != null else Vector2(120, 44)
	var y := -BanterBubble.TAIL_LENGTH
	var top: Control = null    # 气泡下面最上面的那个控件(铭牌或声称气泡)
	for key: String in PLATE_KEYS:
		var plate := labels.get_node_for(key % pid)
		if plate != null and plate.visible:
			y -= plate.size.y + GAP
			top = plate
			break
	var claim := labels.get_node_for(CLAIM_KEY % pid)
	if claim != null and claim.visible:
		y -= claim.size.y + SpeechBubble.TAIL_LENGTH + GAP
		top = claim
	var at := _screen_point(anchor.call()) if anchor.is_valid() else Vector2(INF, INF)
	var quip := labels.get_node_for(QUIP_KEY % pid)
	if quip != null and quip.visible:
		# 九宫格的气泡挂在自己的固定高度(骗子酒馆在声称气泡之上、德州贴着铭牌):它在哪就叠在它上面
		var above_quip := (quip.position.y - at.y) if at.x != INF else y - quip.size.y
		above_quip -= BanterBubble.TAIL_LENGTH + GAP
		if above_quip < y:
			y = above_quip
			top = quip
	if top == null or at.x == INF:
		return Vector2(0, y)
	if at.y + y - size.y >= WorldLabels.EDGE_MARGIN:
		return Vector2(0, y)
	var side := 1.0 if at.x < labels.size.x * 0.5 else -1.0
	var x := (top.position.x + top.size.x / 2.0 - at.x) + side * (top.size.x / 2.0 + GAP + size.x / 2.0)
	return Vector2(x, top.position.y + top.size.y - at.y)


func _screen_point(world_pos: Vector3) -> Vector2:
	# 世界坐标在铭牌层里的位置(同 WorldLabels._place);在镜头背后返回 INF
	var camera: Camera3D = app.tavern.camera_rig.camera
	if camera == null or not camera.is_inside_tree() or camera.is_position_behind(world_pos):
		return Vector2(INF, INF)
	var labels: WorldLabels = app.labels
	return labels.get_global_transform_with_canvas().affine_inverse() * camera.unproject_position(world_pos)


func _my_pid() -> int:
	return Net.my_pid()


func _species_of(pid: int) -> int:
	return Net.species_of(pid)


func _name_of(pid: int) -> String:
	for list in [Net.seats, Net.lobby_players]:
		for p in list:
			if p is Dictionary and p.get("pid") == pid:
				return str(p.get("name", pid))
	return str(pid)
