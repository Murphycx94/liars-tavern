extends Control
# 主菜单:形象与昵称 / 开设房间(选玩法)/ 局域网房间列表(自动发现)/ IP 直连。
# 左侧木牌面板,右侧是环绕镜头下的酒馆。面板在可滚动的侧栏里:1280x720 逻辑分辨率下整块放得下,
# 窗口再矮也只是滚动,底部的 IP 直连、状态行与页脚不会被裁掉。
# 名号旁的头像点开挑选面板(弹出在侧栏右边,不加侧栏的高度);选中的形象坐在桌边 0 号椅上预览。


const RoomRow := preload("res://src/ui/main_menu/room_row.gd")
const ModePicker := preload("res://src/ui/main_menu/mode_picker.gd")
const PANEL_WIDTH := 480.0
const SIDE_MARGIN := 48
const EDGE_MARGIN := 24
const ROW_GAP := 6
const ROOM_LIST_HEIGHT := 80.0   # 正好露出一个房间行,更多房间在列表内滚动
# 「局域网房间」标题行右端的搜索状态(不另占一行,给两行玩法格子腾出高度):定宽右对齐,搜索中的省略号跳动不推动分隔线
const SCAN_LABEL_WIDTH := 170.0
# 名号旁的头像:和昵称输入框一样高(面板在 1280×720 下已经差不多满了,这一行不能再长高)
const SPECIES_CHIP_SIZE := 42.0

var app: Node
var _name_edit: LineEdit
var _species_chip: SpeciesChip
var _picker: SpeciesPicker
var _species := Species.UNASSIGNED   # 本机想要的形象:来自 main(设置或 --species),在这里换了就存进设置
var _room_edit: LineEdit
var _ip_edit: LineEdit
var _room_box: VBoxContainer
var _scan_label: Label
var _status: Label
var _host_button: Button
var _join_button: Button
var _mute_button: Button
var _scroll: ScrollContainer
var _panel: PanelContainer
var _busy := false
var _mode := GameMode.DEFAULT   # 开房用的玩法:预选上次的选择
var _last_join := ""    # 最近一次尝试加入的地址:被拒"版本不匹配"时据此去问房主要更新
var _scan_dots := 0.0


func _init(p_app: Node) -> void:
	app = p_app


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_species = Species.sanitize(app.get("species"))
	_build()
	_show_preview()
	Discovery.rooms_updated.connect(_refresh_rooms)
	Net.join_failed.connect(_on_join_failed)
	# 传 self:旧菜单迟到的 stop_listening 不会关掉这里开的监听
	var listening := Discovery.start_listening(self)
	_scan_label.text = "正在搜索局域网房间" if listening else "广播端口被占用,请用 IP 直连"
	_scan_label.tooltip_text = "" if listening else "无法监听局域网广播(端口被占用),请用下面的 IP 直连"
	_refresh_rooms(Discovery.get_rooms())
	Updater.check_feed()
	_play_intro()
	_focus_default.call_deferred()


func _focus_default() -> void:
	# 默认焦点:还没有名号就先填名号,有了就落在「开设房间」,纯键盘也能直接操作。
	# 延迟执行时可能已被切走(如调试开关直接建房),不在树内就不抢
	if not is_inside_tree() or app.is_rules_open():
		return
	if _name_edit.text == "":
		_name_edit.grab_focus()
	else:
		_host_button.grab_focus()


func _exit_tree() -> void:
	# 切屏时同步调用(main 先移出再释放):立刻断开全局信号,离场的菜单不再响应
	Discovery.rooms_updated.disconnect(_refresh_rooms)
	Net.join_failed.disconnect(_on_join_failed)
	Discovery.stop_listening(self)


func _process(delta: float) -> void:
	if Discovery.is_listening() and Discovery.get_rooms().is_empty():
		_scan_dots = fmod(_scan_dots + delta * 2.0, 4.0)
		_scan_label.text = "正在搜索局域网房间" + ".".repeat(int(_scan_dots))


# —— 布局 ——

func _build() -> void:
	var column := UiTheme.side_column(self, false, SIDE_MARGIN, EDGE_MARGIN)
	_scroll = column.get_parent()
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_panel.add_theme_stylebox_override("panel", UiTheme.screen_panel(0.86, Vector2(34, 22)))
	column.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ROW_GAP)
	_panel.add_child(box)
	_build_title(box)
	box.add_child(UpdateBanner.new())
	_build_identity(box)
	_build_rooms(box)
	_build_direct(box)
	_status = UiTheme.label("", 16, UiTheme.LIE)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	_build_footer(box)
	# 挑选面板压在侧栏之上、铺满屏幕当遮罩:不在滚动侧栏里,展开不会把侧栏撑高
	_picker = SpeciesPicker.new()
	_picker.picked.connect(_select_species)
	add_child(_picker)


func _play_intro() -> void:
	_panel.modulate.a = 0.0
	_panel.position.x -= 60
	var tween := create_tween().set_parallel()
	tween.tween_property(_panel, "modulate:a", 1.0, 0.6)
	tween.tween_property(_panel, "position:x", _panel.position.x + 60, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build_title(box: VBoxContainer) -> void:
	var title := UiTheme.label("骗子酒馆", 64, UiTheme.BRASS_BRIGHT, UiTheme.title_font())
	title.add_theme_color_override("font_shadow_color", Color(0.35, 0.05, 0.03, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	box.add_child(title)
	var subtitle := UiTheme.label("LIAR'S  TAVERN   ·   局域网吹牛出牌", 16, UiTheme.PARCHMENT_DIM, UiTheme.latin_font())
	box.add_child(subtitle)
	box.add_child(_divider())


func _build_identity(box: VBoxContainer) -> void:
	box.add_child(_section("你的名号"))
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 10)
	box.add_child(identity)
	_species_chip = SpeciesChip.new(_species, SPECIES_CHIP_SIZE)
	_species_chip.tooltip_prefix = "挑选形象:"
	_species_chip.pressed.connect(_open_picker)
	identity.add_child(_species_chip)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "输入昵称(最多 %d 字)" % Protocol.MAX_NAME_LENGTH
	_name_edit.max_length = Protocol.MAX_NAME_LENGTH
	_name_edit.text = Settings.get_string(Settings.KEY_NAME)
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_child(_name_edit)
	box.add_child(_mode_section())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_room_edit = LineEdit.new()
	_room_edit.placeholder_text = "房间名(可选)"
	_room_edit.max_length = Protocol.MAX_ROOM_NAME_LENGTH
	_room_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_edit.text_submitted.connect(func(_t): _on_host_pressed())
	row.add_child(_room_edit)
	_host_button = UiTheme.button("开设房间", true)
	_host_button.pressed.connect(_on_host_pressed)
	row.add_child(_host_button)


func _mode_section() -> Control:
	# 「开一桌」小节标题右边放六种玩法的三列两行格子(铺满标题右边的宽度,不画分隔线):不另占一整行,
	# 1280×720 下面板不用滚动(「局域网房间」的搜索状态挪进了它的标题行,腾出这多出来的一行按钮)
	_mode = Settings.last_mode()
	if not GameMode.menu_modes().has(_mode):
		_mode = GameMode.DEFAULT   # 上次选的玩法暂时不在菜单里(GameMode.BOMB_CAT_ENABLED 等开关,或还没登记的玩法)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := UiTheme.label("开一桌", 19, UiTheme.BRASS, UiTheme.display_font())
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var picker := ModePicker.build(_mode, _select_mode)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	return row


# —— 形象 ——

func _open_picker() -> void:
	Sfx.play("ui_click")
	var panel := _panel.get_global_rect()
	var chip := _species_chip.get_global_rect()
	# 面板贴在侧栏右边,和头像这一行对齐;主菜单上没有别人,格子都可选
	_picker.open(_species, {}, Rect2(panel.position.x, chip.position.y, panel.size.x, chip.size.y), true, _species_chip)


func _select_species(index: int) -> void:
	if index == _species:
		return
	Sfx.play("ui_click")
	_species = index
	app.set("species", index)
	Settings.set_value(Settings.KEY_SPECIES, Species.IDS[index], _settings_path())
	_species_chip.set_species(index)
	_show_preview()


func _show_preview() -> void:
	# 桌边 0 号椅上的 3D 预览(冒烟换人);不进树的测试占位 app 没有角色层
	var world = app.get("world")
	if world != null:
		world.show_menu_preview(_species)


func _settings_path() -> String:
	var path = app.get("settings_path")
	return path if path is String else Settings.PATH


func _select_mode(mode: String) -> void:
	if mode == _mode:
		return
	_mode = mode
	Sfx.play("ui_click")
	Settings.set_value(Settings.KEY_LAST_MODE, mode)


func _build_rooms(box: VBoxContainer) -> void:
	var header := _section("局域网房间")
	box.add_child(header)
	_scan_label = UiTheme.label("", 15, UiTheme.MUTED)
	_scan_label.custom_minimum_size = Vector2(SCAN_LABEL_WIDTH, 0)
	_scan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_scan_label.mouse_filter = Control.MOUSE_FILTER_PASS   # 端口被占用时悬停看完整说明
	header.add_child(_scan_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, ROOM_LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_room_box = VBoxContainer.new()
	_room_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_room_box)


func _build_direct(box: VBoxContainer) -> void:
	box.add_child(_section("IP 直连"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "房主 IP,如 192.168.1.8 或 IP:端口"
	_ip_edit.text = Settings.get_string(Settings.KEY_LAST_IP)
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.text_submitted.connect(func(_t): _on_direct_pressed())
	row.add_child(_ip_edit)
	_join_button = UiTheme.button("加入")
	_join_button.pressed.connect(_on_direct_pressed)
	row.add_child(_join_button)


func _build_footer(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var addresses := Lan.local_private_ipv4s()
	var version := UiTheme.label("v%s · 协议 v%d · %s" % [BuildInfo.version(), Protocol.VERSION,
		"本机 " + ", ".join(addresses) if not addresses.is_empty() else "未检测到局域网地址"], 15, UiTheme.MUTED)
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	version.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # 多网卡时地址很长:换行,不撑宽面板
	row.add_child(version)
	var rules := UiTheme.button("游戏规则")
	rules.add_theme_font_size_override("font_size", 15)
	rules.tooltip_text = "翻开说明书(%s)" % OS.get_keycode_string(Rulebook.HOTKEY)
	rules.pressed.connect(func(): app.show_rules())
	row.add_child(rules)
	_mute_button = UiTheme.button("声音:开")
	_mute_button.add_theme_font_size_override("font_size", 15)
	_mute_button.pressed.connect(_toggle_mute)
	row.add_child(_mute_button)
	_update_mute_label()


func _section(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := UiTheme.label(text, 19, UiTheme.BRASS, UiTheme.display_font())
	row.add_child(label)
	var line := _divider()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.modulate.a = 0.45
	row.add_child(line)
	return row


func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = UiTheme.BRASS
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


# —— 房间列表 ——

func _refresh_rooms(rooms: Array) -> void:
	for child in _room_box.get_children():
		child.queue_free()
	if rooms.is_empty():
		var empty := UiTheme.label("暂未发现房间。可以自己开一桌,或用 IP 直连。", 15, UiTheme.MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_room_box.add_child(empty)
		return
	_scan_label.text = "发现 %d 个房间" % rooms.size()
	for room in rooms:
		var on_join := _join.bind(Protocol.format_address(room["ip"], room["port"]))
		var on_update := _update_from.bind(room["ip"], room["port"], room["host"])
		_room_box.add_child(RoomRow.build(room, offers_update(room, BuildInfo.build()), on_join, on_update))


static func offers_update(room: Dictionary, my_build: int, my_platform := BuildInfo.platform()) -> bool:
	# 房主提供更新文件、和自己同一平台、且比自己新:列表里给出"更新"按钮
	return room.get("update", false) and room.get("plat", "") == my_platform and room.get("build", 0) > my_build


func _update_from(ip: String, port: int, host_name: String) -> void:
	Sfx.play("ui_click")
	Updater.check(Updater.lan_source(ip, port), "房主 %s" % host_name)


# —— 操作 ——

func _on_host_pressed() -> void:
	var pname := _validated_name()
	if pname == "" or _busy:
		return
	Sfx.play("ui_click")
	var room_name := _room_edit.text.strip_edges()
	if room_name == "":
		room_name = default_room_name(pname, _mode)
	Discovery.stop_listening(self)
	var err := Net.host_game(pname, room_name, 0, _mode, _species)
	if err != OK:
		_show_status("开设房间失败:端口 %d-%d 都被占用(%s)" % [
			Protocol.GAME_PORT, Protocol.GAME_PORT + Protocol.GAME_PORT_ATTEMPTS - 1, error_string(err)], UiTheme.LIE)
		Discovery.start_listening(self)


static func default_room_name(pname: String, mode: String) -> String:
	# 没填房名时:骗子酒馆「X 的酒馆」,德州「X 的牌局」,炸弹猫「X 的猫窝」,吹牛骰子「X 的骰子局」,斗地主「X 的斗地主」
	if GameMode.is_bomb_cat(mode):
		return "%s 的猫窝" % pname
	if GameMode.is_liars_dice(mode):
		return "%s 的骰子局" % pname
	if mode == GameMode.DOU_DIZHU:
		return "%s 的斗地主" % pname
	return ("%s 的牌局" if GameMode.is_poker(mode) else "%s 的酒馆") % pname


func _on_direct_pressed() -> void:
	var text := _ip_edit.text.strip_edges()
	var addr := Protocol.parse_address(text)
	if not addr["ok"]:
		_show_status(addr["error"], UiTheme.LIE)
		return
	Settings.set_value(Settings.KEY_LAST_IP, text)
	_join(text)


func _join(address: String) -> void:
	var pname := _validated_name()
	if pname == "" or _busy:
		return
	Sfx.play("ui_click")
	_set_busy(true)
	_last_join = address
	_show_status("正在连接 %s …" % address, UiTheme.PARCHMENT_DIM)
	Net.join_game(pname, address, _species)


func _on_join_failed(reason: String) -> void:
	_set_busy(false)
	_show_status(reason, UiTheme.LIE)
	Sfx.play("thud")
	if reason.contains("版本"):
		# 版本不匹配:问问房主那里有没有能用的新版本(房主比自己旧时横幅会说明)
		var addr := Protocol.parse_address(_last_join)
		if addr["ok"]:
			Updater.check(Updater.lan_source(addr["ip"], addr["port"]), "房主")
	if not Discovery.is_listening():
		Discovery.start_listening(self)


func _show_status(text: String, color: Color) -> void:
	_status.add_theme_color_override("font_color", color)
	_status.text = text
	_reveal_status()


func _reveal_status() -> void:
	# 面板高到要滚动时,把状态行(连接中 / 失败原因)滚进可视区;换行后的新尺寸要到下一帧才排好
	if not is_inside_tree():
		return
	await get_tree().process_frame
	_scroll.ensure_control_visible(_status)


func _set_busy(busy: bool) -> void:
	_busy = busy
	_host_button.disabled = busy
	_join_button.disabled = busy


func _validated_name() -> String:
	var raw_text := _name_edit.text
	var pname := Protocol.sanitize_name(raw_text)
	var validation := Protocol.validate_name(pname)
	if not validation["ok"]:
		_show_status(validation["error"], UiTheme.LIE)
		_name_edit.grab_focus()
		return ""
	Settings.set_value(Settings.KEY_NAME, pname)
	return pname


func _toggle_mute() -> void:
	Sfx.set_muted(not Sfx.muted)
	Settings.set_value(Settings.KEY_MUTED, Sfx.muted)
	_update_mute_label()


func _update_mute_label() -> void:
	_mute_button.text = "声音:关" if Sfx.muted else "声音:开"
