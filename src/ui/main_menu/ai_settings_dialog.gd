class_name AiSettingsDialog
extends ColorRect
# 主菜单的「AI 设置」(每个玩家都能设,只存本机):填接口地址、API Key、模型,打开「启用 AI」后,
# 你开房加的机器人与你自己的托管(德州、斗地主)都由这个 AI 来打。
# 可以先「测试连接」(真的发一句话过去,看模型回不回);保存时开关打开但没填好会提示、不保存。
# 半透明遮罩吞掉鼠标与按键,背后等待厅的快捷键(Esc 离开)不会生效;Esc 关闭本面板。


signal saved(values: Dictionary)

const PANEL_WIDTH := 560.0
const FIELD_FONT_SIZE := 17
const TEST_SYSTEM := "你是连通性测试。"
const TEST_USER := "只回复 OK 两个字母,不要别的。"
const TEST_REPLY_MAX := 40
const HELP := "填上大模型的接口:你开房时加的机器人、你自己点「托管」时,都由这个 AI 来打(它只看得到你能看到的牌)。\n" \
	+ "支持 OpenAI 兼容接口(DeepSeek、通义千问、Kimi、OpenRouter、本机 Ollama 等)和 Anthropic。\n" \
	+ "接口地址与 Key 只保存在这台电脑上,不会发给别人;别人的托管用他们自己的设置。AI 出错或太慢时改用内置策略。"

var _values := {}
var _url: LineEdit
var _key: LineEdit
var _model: LineEdit
var _enabled: CheckButton
var _status: Label
var _test_button: Button
var _chat: AiChat
var _test_id := -1
var _closed := false


func _init(values: Dictionary) -> void:
	_values = AiSettings.sanitized(values)


func _ready() -> void:
	color = Color(0, 0, 0, 0.55)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_chat = AiChat.new()
	add_child(_chat)
	_chat.answered.connect(_on_test_answered)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", UiTheme.screen_panel(0.95, Vector2(28, 22)))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(UiTheme.label("AI 设置", 26, UiTheme.BRASS_BRIGHT, UiTheme.display_font()))
	var help := UiTheme.label(HELP, 14, UiTheme.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	_url = _field(box, "接口地址", "https://api.deepseek.com/v1", _values[AiSettings.KEY_URL])
	_key = _field(box, "API Key", "sk-…(本机模型可以不填)", _values[AiSettings.KEY_API_KEY])
	_key.secret = true
	_model = _field(box, "模型", "deepseek-chat", _values[AiSettings.KEY_MODEL])
	_enabled = CheckButton.new()
	_enabled.text = "启用 AI(我的机器人与托管)"
	_enabled.button_pressed = _values[AiSettings.KEY_ENABLED]
	_enabled.add_theme_font_size_override("font_size", FIELD_FONT_SIZE)
	box.add_child(_enabled)
	_status = UiTheme.label("", 15, UiTheme.PARCHMENT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	box.add_child(_buttons())
	_url.grab_focus.call_deferred()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)


func _field(box: VBoxContainer, title: String, hint: String, value: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var label := UiTheme.label(title, 15, UiTheme.MUTED)
	label.custom_minimum_size.x = 80
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = hint
	edit.max_length = AiSettings.MAX_FIELD_LENGTH
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", FIELD_FONT_SIZE)
	row.add_child(edit)
	return edit


func _buttons() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_test_button = UiTheme.button("测试连接")
	_test_button.pressed.connect(_on_test_pressed)
	row.add_child(_test_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var cancel := UiTheme.button("取消")
	cancel.pressed.connect(close)
	row.add_child(cancel)
	var save := UiTheme.button("保存", true)
	save.pressed.connect(_on_save_pressed)
	row.add_child(save)
	return row


func values() -> Dictionary:
	return AiSettings.sanitized({
		AiSettings.KEY_URL: _url.text, AiSettings.KEY_API_KEY: _key.text,
		AiSettings.KEY_MODEL: _model.text, AiSettings.KEY_ENABLED: _enabled.button_pressed,
	})


func _unhandled_input(event: InputEvent) -> void:
	# Esc 关闭;其余按键吞掉(输入框里的打字由输入框先收到,不经过这里)
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif event is InputEventKey:
		get_viewport().set_input_as_handled()


func _on_test_pressed() -> void:
	Sfx.play("ui_click")
	var current := values()
	var problem := AiSettings.check(current)
	if problem != "":
		_show(problem, UiTheme.LIE)
		return
	_test_button.disabled = true
	_show("正在连接…", UiTheme.PARCHMENT_DIM)
	_test_id = _chat.ask(current, TEST_SYSTEM, TEST_USER)


func _on_test_answered(id: int, ok: bool, text: String) -> void:
	if id != _test_id or _closed:
		return
	_test_button.disabled = false
	if ok:
		_show("连接成功,模型回答:「%s」" % text.strip_edges().substr(0, TEST_REPLY_MAX), UiTheme.TRUTH)
	else:
		_show("连接失败:" + text, UiTheme.LIE)


func _on_save_pressed() -> void:
	Sfx.play("ui_click")
	var current := values()
	if current[AiSettings.KEY_ENABLED]:
		var problem := AiSettings.check(current)
		if problem != "":
			_show(problem, UiTheme.LIE)
			return
	saved.emit(current)
	close()


func _show(text: String, tint: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", tint)


func close() -> void:
	if _closed:
		return
	_closed = true
	_chat.cancel_all()
	queue_free()
