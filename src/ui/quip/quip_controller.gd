class_name QuipController
extends Control
# 牌桌上的快捷对话(三种玩法共用):T 键或「对话」按钮开关九宫格,选一句经 Net.send_quip 发给房主;
# 房主转发回来(Net.quip_shown)才显示——说话人头顶冒气泡(自己的由牌桌 HUD 显示在自己那一角)、记一行日志、响一声。
# 本地冷却 Quips.COOLDOWN,冷却中按钮变灰;房主另有限速。作为牌桌屏幕的子节点,先于屏幕收到按键:
# 九宫格打开时 1–9 选句、Esc 收起,不会落到选牌 / 下注预设 / 离开确认上。
# 和 BanterView 的 Q 快捷语面板(动物叫声那套)互斥:打开九宫格就收起它,反之亦然;说明书 / 确认框开着时收起、不响应。
# 牌桌提供:name_of(pid) -> String、anchor_for(pid) -> Callable(没有酒客时返回空 Callable)、
# show_mine(text)、log_line(text, color)。


const KEY_PREFIX := "quip:%d"   # WorldLabels 里他人气泡的键(与出牌的气泡分开,两个可以同时在)
const TOGGLE_KEY := Quips.TOGGLE_KEY

var app: Node
var my_pid := 0
var menu: QuipMenu
var name_of: Callable
var anchor_for: Callable
var show_mine: Callable
var log_line: Callable
var bubble_offset := Vector2.ZERO   # 气泡相对挂点的屏幕偏移(挂在铭牌上方)

var _ready_at_ms := 0


func _init(p_app: Node, p_my_pid: int) -> void:
	app = p_app
	my_pid = p_my_pid


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu = QuipMenu.new()
	add_child(menu)
	menu.chosen.connect(choose)
	Net.quip_shown.connect(_on_quip)


func _process(_delta: float) -> void:
	if menu.is_open():
		if _modal_open():
			menu.close()
			return
		menu.set_cooldown(cooldown_left())


func cooldown_left() -> float:
	return maxf(0.0, (_ready_at_ms - Time.get_ticks_msec()) / 1000.0)


func toggle() -> void:
	if not menu.is_open() and _modal_open():
		return
	menu.set_cooldown(cooldown_left())
	menu.toggle()
	if menu.is_open():
		_close_banter_panel()
	Sfx.play("ui_click")


func close_menu() -> void:
	menu.close()


func _modal_open() -> bool:
	return app != null and app.has_method("is_modal_open") and app.is_modal_open()


func _close_banter_panel() -> void:
	# 和 Q 快捷语面板互斥:数字键不能两边都收到
	var banter: Variant = app.get("banter_view") if app != null else null
	if banter is BanterView and is_instance_valid(banter):
		banter.close_panel()


func choose(index: int) -> bool:
	# 按钮、数字键与 bot 共用的入口
	if cooldown_left() > 0.0 or not Quips.is_valid(index):
		return false
	_ready_at_ms = Time.get_ticks_msec() + int(Quips.COOLDOWN * 1000.0)
	menu.close()
	Net.send_quip(index)
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or _modal_open():
		return
	if menu.is_open() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		menu.close()
		return
	if event.keycode == TOGGLE_KEY:
		get_viewport().set_input_as_handled()
		toggle()
		return
	var index := digit_index(event.keycode)
	if menu.is_open() and index >= 0:
		get_viewport().set_input_as_handled()
		choose(index)


static func digit_index(keycode: int) -> int:
	# 1–9(主键盘或小键盘)→ 0–8;其余 -1
	if keycode >= KEY_1 and keycode <= KEY_9:
		return keycode - KEY_1
	if keycode >= KEY_KP_1 and keycode <= KEY_KP_9:
		return keycode - KEY_KP_1
	return -1


func _on_quip(pid: int, index: int) -> void:
	var text := Quips.text(index)
	if text == "":
		return
	Sfx.play("quip")
	if log_line.is_valid():
		log_line.call("%s:%s" % [name_of.call(pid) if name_of.is_valid() else str(pid), text], UiTheme.PARCHMENT)
	if pid == my_pid:
		if show_mine.is_valid():
			show_mine.call(text)
		return
	var anchor: Callable = anchor_for.call(pid) if anchor_for.is_valid() else Callable()
	if anchor.is_valid():
		app.labels.track(KEY_PREFIX % pid, SpeechBubble.new(text, UiTheme.INK, Quips.BUBBLE_SECONDS), anchor, bubble_offset,
			true)
