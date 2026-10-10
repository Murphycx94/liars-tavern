extends Control
# 等待厅:右侧面板(房名、玩法与人数、房主地址、玩家列表、准备/开局/踢人/离开),
# 3D 场景中已加入的玩家以酒客形象围着本玩法的桌子落座(德州桌更大),头顶单行铭牌显示名字与准备状态。
# 房主的局域网广播发不出去时,面板里用红字提示大家改用 IP 直连。
# 名单每行有房主分配的形象头像;点自己那一行的头像弹出挑选面板(贴在面板左边),被占的格子写占用者名字。
# 换形象发给房主,收到下一份名单时结算:拿到了存进本机设置,被别人抢先了提示一句。


const PANEL_WIDTH := 440.0
const SIDE_MARGIN := 44
const EDGE_MARGIN := 24
const CAMERA_MOVE_TIME := 1.8
const LIST_GAP := 8
# 玩家列表最多露出这么多行,其余在列表里滚动:德州 8 人时面板在 1280×720 下也不超过 672 像素高;
# 骗子酒馆满员正好 4 人,列表不滚动
const LIST_VISIBLE_ROWS := 4
# 名单每行不超过这么高(规格 §3.2):房名折成两行、广播告警同时出现时面板也放得下
const ROW_MAX_HEIGHT := 36.0
const ROW_PADDING_Y := 4
# 名单行里的小按钮(请出):沿用主题样式,只收小内边距,有按钮的行与没按钮的行一样高
const ROW_BUTTON_PADDING := Vector2(12, 3)
const ROW_BUTTON_STATES := ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]
# 3D 铭牌:单行「名字 ✓」,不超过 PLATE_MAX(8 人围坐时两行的铭牌会互相压住)
const PLATE_MAX := Vector2(130, 44)
const PLATE_FONT_SIZE := 16
const PLATE_PADDING := Vector2(10, 5)
const PLATE_GAP := 4
const PLATE_CHECK := "✓"
const PLATE_CHECK_ROOM := 22.0   # 给「✓」与间隔留的宽度
# 名单行里的形象头像:行高上限 36 减去上下内边距
const ROW_CHIP_SIZE := 28.0
const PICK_LOCK_MS := 300        # 点选后这么久不能再点(房主那边每个对端还有 0.25 秒冷却)
const PENDING_TIMEOUT_MS := 1500 # 换形象请求等这么久还没结果(冷却中被拒、名单丢了)就静默放弃

var app: Node
var _title: Label
var _mode_label: Label
var _address: Label
var _hint: Label
var _broadcast_warning: Label
var _list_scroll: ScrollContainer
var _list: VBoxContainer
var _status: Label
var _ready_button: Button = null
var _start_button: Button = null
var _is_ready := false
var _known := {}   # pid -> 名字:上一份名单;为空表示还没有基准
var _table_mode := ""   # 桌子已按哪个玩法摆好;Net.game_mode 后来变了(名单 meta 晚到)就再摆一次
var _panel: PanelContainer
var _picker: SpeciesPicker
var _my_chip: SpeciesChip = null      # 自己那一行的头像(每次刷新名单都重建)
var _my_species := Species.UNASSIGNED
var _pending := Species.UNASSIGNED    # 已发给房主、还没结算的换形象请求
var _pending_deadline := 0
var _pick_locked_until := 0


func _init(p_app: Node) -> void:
	app = p_app


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	Net.lobby_updated.connect(_refresh)
	if Net.is_host:
		Discovery.broadcast_health_changed.connect(_on_broadcast_health)
	_on_broadcast_health(Discovery.is_broadcast_healthy())
	# 从结算回来:收走桌上的牌与左轮,倒下的酒客重新登场;德州的筹码、公共牌等也拆掉(规格 §5.1)
	app.world.clear_poker()
	app.world.cards.clear_all()
	app.world.revive_all()
	app.labels.clear()
	_apply_table_mode()
	_refresh(Net.lobby_players)
	_focus_default.call_deferred()


func _focus_default() -> void:
	# 默认焦点落在主操作上:房主「开始游戏」(凑齐前是灰的),客人「准备」。
	# 延迟执行时可能已被切走(同一帧里开局),不在树内就不抢;
	# 说明书开着时也不抢:它靠握着焦点挡住回车/空格,抢走后按键会在它背后切换准备
	if not is_inside_tree() or app.is_rules_open():
		return
	(_start_button if _start_button != null else _ready_button).grab_focus()


func _exit_tree() -> void:
	# 切屏时同步调用(main 先移出再释放):立刻断开全局信号,离场的等待厅不会再改动座位与铭牌
	Net.lobby_updated.disconnect(_refresh)
	if Discovery.broadcast_health_changed.is_connected(_on_broadcast_health):
		Discovery.broadcast_health_changed.disconnect(_on_broadcast_health)
	for pid in _known:
		app.labels.untrack("lobby:%d" % pid)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_leave_pressed()


# —— 布局 ——

func _build() -> void:
	var box := _build_panel()
	box.add_child(UiTheme.label("等待厅", 15, UiTheme.MUTED))
	_title = UiTheme.label(Net.lobby_meta.get("room", "酒馆"), 34, UiTheme.BRASS_BRIGHT, UiTheme.display_font())
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
	_mode_label = UiTheme.label(GameMode.summary(Net.game_mode), 15, UiTheme.BRASS)
	box.add_child(_mode_label)
	box.add_child(_address_row())
	_hint = UiTheme.label("同一局域网的玩家会在房间列表中看到这里;\n也可以把上面的地址告诉他们直连。", 15, UiTheme.MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)
	_broadcast_warning = UiTheme.label(_broadcast_warning_text(), 15, UiTheme.LIE)
	_broadcast_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_broadcast_warning)
	_list_scroll = ScrollContainer.new()
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.follow_focus = true
	box.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", LIST_GAP)
	_list_scroll.add_child(_list)
	_status = UiTheme.label("", 15, UiTheme.PARCHMENT_DIM)
	box.add_child(_status)
	box.add_child(_build_buttons())
	# 挑选面板铺满屏幕当遮罩、面板贴在侧栏左边:不进侧栏,德州 8 人时面板也不会超过 672 像素
	_picker = SpeciesPicker.new()
	_picker.picked.connect(_request_species)
	_picker.closed.connect(func(): _focus_my_chip.call_deferred())
	add_child(_picker)


func _build_panel() -> VBoxContainer:
	var column := UiTheme.side_column(self, true, SIDE_MARGIN, EDGE_MARGIN)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.add_theme_stylebox_override("panel", UiTheme.screen_panel(0.86, Vector2(28, 22)))
	column.add_child(panel)
	_panel = panel
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	return box


func _build_buttons() -> HBoxContainer:
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var leave := UiTheme.button("离开")
	leave.pressed.connect(_on_leave_pressed)
	buttons.add_child(leave)
	var rules := UiTheme.button("规则")
	rules.tooltip_text = "翻开说明书(%s)" % OS.get_keycode_string(Rulebook.HOTKEY)
	rules.pressed.connect(func(): app.show_rules())
	buttons.add_child(rules)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	if Net.is_host:
		_start_button = UiTheme.button("开始游戏", true)
		_start_button.disabled = true
		_start_button.pressed.connect(_on_start_pressed)
		buttons.add_child(_start_button)
	else:
		_ready_button = UiTheme.button("准备", true)
		_ready_button.pressed.connect(_on_ready_toggled)
		buttons.add_child(_ready_button)
	return buttons


func _address_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UiTheme.label("房主地址", 15, UiTheme.MUTED))
	# 用正文字体:等宽衬线字体的旧式数字会把 1/0 写得像 I/o,地址要让人照着输入
	_address = UiTheme.label("", 20, UiTheme.PARCHMENT, UiTheme.body_font())
	_address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_address)
	var copy := UiTheme.button("复制")
	copy.add_theme_font_size_override("font_size", 15)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(_address.text.split("  ")[0])
		app.toast("已复制房主地址"))
	row.add_child(copy)
	return row


static func _broadcast_warning_text() -> String:
	var text := "局域网广播发不出去:其他人可能看不到这个房间,请让他们用上面的地址 IP 直连。"
	if OS.get_name() == "macOS":
		text += "\nmacOS:到 系统设置 → 隐私与安全性 → 本地网络 中允许本游戏。"
	return text


# —— 刷新 ——

func _refresh(players: Array) -> void:
	_sync_table_mode()
	_title.text = Net.lobby_meta.get("room", _title.text)
	_mode_label.text = GameMode.summary(Net.game_mode)
	_address.text = _address_text()
	_announce_changes(players)
	_settle_species_request(players)
	# 等待厅里还没分到形象的人(握手后形象请求还在路上)先不建酒客,名单显示「挑选中…」
	app.world.arrange(players, Net.my_pid(), true, false, true)
	_my_chip = null
	for child in _list.get_children():
		_list.remove_child(child)   # 立刻移出:下面要按新名单量列表高度
		child.queue_free()
	for i in players.size():
		_list.add_child(_player_row(players[i], i))
		_track_nameplate(players[i])
	_fit_list()
	var ready_count := players.filter(func(p): return p["ready"]).size()
	_status.text = "%d/%d 人 · %d 人已准备" % [players.size(), Net.max_players(), ready_count]
	var min_players := GameMode.min_players(Net.game_mode)   # 斗地主要 3 人
	if players.size() < min_players:
		_status.text += " · 至少 %d 人才能开局" % min_players
	elif Net.is_host and not Net.can_start():
		_status.text += " · 等待全员准备"
	if _start_button != null:
		_start_button.disabled = not Net.can_start()
	if _picker.is_open():
		# 面板开着时别人换了形象:灰掉的格子跟着变
		_picker.update_taken(SpeciesPicker.taken_map(players, Net.my_pid()))


func _sync_table_mode() -> void:
	# 兜底:玩法本该在获准时就到;名单 meta 带来的玩法和已摆的桌子不一样时再摆一次
	if Net.game_mode != _table_mode:
		_apply_table_mode()


func _apply_table_mode() -> void:
	# 桌子按玩法摆(德州桌更大、不摆烛台与立牌),已落座的酒客跟着桌沿挪,镜头换到等待厅机位;
	# 德州等待厅在后台开始生成德州牌面(规格 §3.2、§5.2),进牌桌时多半已经生成完
	_table_mode = Net.game_mode
	app.apply_table_mode(_table_mode)
	if GameMode.is_poker(_table_mode) and is_inside_tree():
		PokerFaces.build(self)
	if GameMode.is_bomb_cat(_table_mode) and is_inside_tree():
		BombCatFaces.build(self)   # 炸弹猫牌面同理(一批画完,约两帧)
	if GameMode.is_dou_dizhu(_table_mode) and is_inside_tree():
		PokerFaces.build(self)     # 斗地主:德州的 52 张牌面 + 两张王
		DdzJokerFaces.build(self)
	app.tavern.camera_rig.move_to(app.world.lobby_view(), CAMERA_MOVE_TIME)


func _fit_list() -> void:
	var heights := _list.get_children().map(func(row: Control) -> float: return row.get_combined_minimum_size().y)
	_list_scroll.custom_minimum_size.y = visible_list_height(heights, LIST_GAP, LIST_VISIBLE_ROWS)


static func visible_list_height(row_heights: Array, gap: float, max_rows: int) -> float:
	# 列表露出的高度:前 max_rows 行加行距,更多的行在列表里滚动
	var shown := row_heights.slice(0, max_rows)
	var height := 0.0
	for row_height: float in shown:
		height += row_height
	return height + gap * maxi(shown.size() - 1, 0)


func _address_text() -> String:
	var addresses: Array = Net.lobby_meta.get("addresses", [])
	var port: int = Net.lobby_meta.get("port", Protocol.GAME_PORT)
	if addresses.is_empty():
		return Protocol.format_address(Lan.LOOPBACK, port)
	return "  ".join(addresses.map(func(ip): return Protocol.format_address(ip, port)))


func _on_broadcast_health(healthy: bool) -> void:
	# 只有房主在广播;发不出去时把「会在房间列表中看到这里」换成红字的直连提示
	_broadcast_warning.visible = Net.is_host and not healthy
	_hint.visible = not _broadcast_warning.visible


static func roster_changes(known: Dictionary, players: Array, my_pid: int) -> Dictionary:
	# 名单对比:known 为空表示还没有基准——首份名单只当基准,已在房里的人不算新来的;
	# 自己永远不算「走进了酒馆」。返回 {"now": pid->名字, "joined": [pid], "left": [pid]}
	var now := {}
	for p in players:
		now[p["pid"]] = p["name"]
	var joined: Array = []
	var left: Array = []
	if not known.is_empty():
		for pid in now:
			if not known.has(pid) and pid != my_pid:
				joined.append(pid)
		for pid in known:
			if not now.has(pid):
				left.append(pid)
	return {"now": now, "joined": joined, "left": left}


func _announce_changes(players: Array) -> void:
	var changes := roster_changes(_known, players, Net.my_pid())
	for pid in changes["joined"]:
		app.toast("%s 走进了酒馆" % changes["now"][pid], UiTheme.BRASS_BRIGHT)
		Sfx.play("join")
	for pid in changes["left"]:
		app.toast("%s 离开了" % _known[pid], UiTheme.MUTED)
		app.labels.untrack("lobby:%d" % pid)
	_known = changes["now"]


func _player_row(player: Dictionary, _index: int) -> Control:
	var panel := PanelContainer.new()
	var mine: bool = player["pid"] == Net.my_pid()
	var style := UiTheme.panel_box(Color(0.13, 0.09, 0.06, 0.9), Color(UiTheme.BRASS, 0.7 if mine else 0.3), 1, 8)
	style.content_margin_top = ROW_PADDING_Y
	style.content_margin_bottom = ROW_PADDING_Y
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var name_label := UiTheme.label(player["name"] + ("(你)" if mine else ""), 19, UiTheme.PARCHMENT,
		UiTheme.display_font())
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS   # 长昵称不撑宽面板
	row.add_child(_species_chip(player, mine))
	row.add_child(name_label)
	if player["is_host"]:
		row.add_child(UiTheme.label("房主", 15, UiTheme.BRASS))
	var badge := UiTheme.label("已准备" if player["ready"] else "未准备", 15,
		UiTheme.TRUTH if player["ready"] else UiTheme.MUTED)
	row.add_child(badge)
	if Net.is_host and not player["is_host"]:
		var kick := row_button("请出")
		kick.pressed.connect(func():
			var overlay: ConfirmOverlay = app.confirm("把 %s 请出酒馆?" % player["name"], "请出")
			overlay.confirmed.connect(Net.kick.bind(player["pid"])))
		row.add_child(kick)
	return panel


static func row_button(text: String) -> Button:
	# 按钮的最小尺寸取各状态样式里最大的那个:每种状态都换成小内边距
	var button := UiTheme.button(text)
	button.add_theme_font_size_override("font_size", 15)
	for state: String in ROW_BUTTON_STATES:
		var box: StyleBox = UiTheme.theme().get_stylebox(state, "Button").duplicate()
		box.content_margin_left = ROW_BUTTON_PADDING.x
		box.content_margin_right = ROW_BUTTON_PADDING.x
		box.content_margin_top = ROW_BUTTON_PADDING.y
		box.content_margin_bottom = ROW_BUTTON_PADDING.y
		button.add_theme_stylebox_override(state, box)
	return button


func _species_chip(player: Dictionary, mine: bool) -> SpeciesChip:
	# 房主分配的形象(不可信数据,非法值当「挑选中…」);自己那一行的头像是按钮,点开挑选面板
	var chip := SpeciesChip.new(Species.sanitize(player.get("species")), ROW_CHIP_SIZE, mine)
	if mine:
		chip.tooltip_prefix = "换形象:"
		chip.pressed.connect(_open_picker)
		_my_chip = chip
		_my_species = chip.species
	return chip


# —— 换形象 ——

func _open_picker() -> void:
	if Time.get_ticks_msec() < _pick_locked_until or _my_chip == null:
		return
	Sfx.play("ui_click")
	var panel := _panel.get_global_rect()
	var chip := _my_chip.get_global_rect()
	_picker.open(_my_species, SpeciesPicker.taken_map(Net.lobby_players, Net.my_pid()),
		Rect2(panel.position.x, chip.position.y, panel.size.x, chip.size.y), false)


func _request_species(index: int) -> void:
	# 先记下挂起的请求再发:房主自己换形象时名单在 request_species 里就同步刷新了
	if index == _my_species:
		return
	Sfx.play("ui_click")
	_pick_locked_until = Time.get_ticks_msec() + PICK_LOCK_MS
	_pending = index
	_pending_deadline = Time.get_ticks_msec() + PENDING_TIMEOUT_MS
	Net.request_species(index)


func _settle_species_request(players: Array) -> void:
	# 收到名单时结算挂起的请求:拿到了 → 存进本机设置(之后再开房、加入都用它);
	# 被别人抢先 → 提示;都不是(与请求无关的名单、冷却中被拒)→ 等下一份,超时静默放弃
	if _pending == Species.UNASSIGNED:
		return
	var outcome := SpeciesPicker.resolve_request(players, Net.my_pid(), _pending)
	match outcome["result"]:
		"granted":
			app.set("species", _pending)
			var path = app.get("settings_path")
			Settings.set_value(Settings.KEY_SPECIES, Species.IDS[_pending], path if path is String else Settings.PATH)
			_pending = Species.UNASSIGNED
		"taken":
			app.toast("「%s」刚被 %s 选走了" % [Species.LABELS[_pending], outcome["by"]], UiTheme.MUTED)
			_pending = Species.UNASSIGNED
		_:
			if Time.get_ticks_msec() > _pending_deadline:
				_pending = Species.UNASSIGNED


func _focus_my_chip() -> void:
	if is_instance_valid(_my_chip) and _my_chip.is_inside_tree() and not app.is_rules_open():
		_my_chip.grab_focus()


func _track_nameplate(player: Dictionary) -> void:
	var pid: int = player["pid"]
	if not app.world.patrons.has(pid):
		return
	var patron: Patron = app.world.patrons[pid]
	app.labels.track("lobby:%d" % pid, nameplate(player["name"], player["ready"]), patron.nameplate_anchor)


static func nameplate(pname: String, ready: bool) -> PanelContainer:
	# 单行「名字 ✓」,准备好了描边变绿。名字一栏按文字宽度给足、超长昵称才省略号截断:
	# 带截断的 Label 最小宽度只剩「…」,不给宽度会缩没
	var plate := PanelContainer.new()
	var style := UiTheme.panel_box(UiTheme.PANEL_SOFT, UiTheme.TRUTH if ready else Color(UiTheme.BRASS, 0.5), 1, 12)
	style.content_margin_left = PLATE_PADDING.x
	style.content_margin_right = PLATE_PADDING.x
	style.content_margin_top = PLATE_PADDING.y
	style.content_margin_bottom = PLATE_PADDING.y
	plate.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", PLATE_GAP)
	plate.add_child(row)
	var font := UiTheme.display_font()
	var name_label := UiTheme.label(pname, PLATE_FONT_SIZE, UiTheme.PARCHMENT, font)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var text_width := ceilf(font.get_string_size(pname, HORIZONTAL_ALIGNMENT_LEFT, -1, PLATE_FONT_SIZE).x)
	name_label.custom_minimum_size.x = minf(text_width, PLATE_MAX.x - 2.0 * PLATE_PADDING.x - PLATE_CHECK_ROOM)
	row.add_child(name_label)
	if ready:
		row.add_child(UiTheme.label(PLATE_CHECK, PLATE_FONT_SIZE, UiTheme.TRUTH))
	return plate


# —— 操作 ——

func _on_start_pressed() -> void:
	Sfx.play("ui_click")
	Net.start_game()


func _on_ready_toggled() -> void:
	Sfx.play("ui_click")
	_is_ready = not _is_ready
	_ready_button.text = "取消准备" if _is_ready else "准备"
	Net.set_ready(_is_ready)


func _on_leave_pressed() -> void:
	var overlay: ConfirmOverlay = app.confirm("确定离开房间吗?" + ("\n你是房主,离开后房间会解散。" if Net.is_host else ""), "离开")
	overlay.confirmed.connect(func(): Net.end_session())
