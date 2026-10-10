extends Node
# 入口:常驻 3D 酒馆 + 后处理 + 2D 屏幕(主菜单 / 等待厅 / 牌桌)切换。
# 各屏幕通过 app(本节点)访问酒馆、角色层、后处理、铭牌层与提示条。


const MainMenuScreen := preload("res://src/ui/main_menu/main_menu.gd")
const LobbyScreen := preload("res://src/ui/lobby/lobby.gd")
const TableScreen := preload("res://src/ui/table/table_screen.gd")
const PokerScreen := preload("res://src/ui/poker/poker_screen.gd")
const BombCatScreen := preload("res://src/ui/bomb_cat/bomb_cat_screen.gd")
const DouDizhuScreen := preload("res://src/ui/dou_dizhu/dou_dizhu_screen.gd")
const LiarsDiceScreen := preload("res://src/ui/liars_dice/liars_dice_screen.gd")
const VIEW_RESET_TIME := 0.8   # 切换屏幕时紧张度、闪光染色与镜头焦距回到平静的时长

var tavern: Tavern
var world: TableWorld
var post_fx: PostFx
var labels: WorldLabels
var toasts: ToastLayer
var banter_view: BanterView   # 丢番茄与快捷语(等待厅、牌桌常驻一层)
var flags: DebugFlags
var settings_path := Settings.PATH   # 本机设置文件;测试换成临时文件
var species := Species.UNASSIGNED    # 本机想要的形象:设置里的(首次启动随机一个并保存),--species 只覆盖本次运行

var _ui: Control
var _screen: Control = null
var _confirms: Array[ConfirmOverlay] = []
var _default_fov := 0.0
var _rules_root: Control
var _rulebook: Rulebook = null
var _rules_pages := {}   # 每本说明书读到的页 {书: 页码}:合上时记下,下次翻开接着读


func _ready() -> void:
	get_window().min_size = Vector2i(1024, 600)
	RenderBudget.follow(get_window())
	get_tree().auto_accept_quit = false
	species = resolve_species(settings_path)
	# 酒客、椅子、左轮的合批网格先投到工作线程里建(纯数组运算),和下面的场景搭建、牌面生成并行
	MeshForge.prebuild(PatronParts.forge_jobs() + Revolver3D.forge_jobs())
	tavern = Tavern.new()
	add_child(tavern)
	# 记下镜头的初始焦距:切换屏幕时恢复(被打断的演出可能把焦距留在半路)
	_default_fov = tavern.camera_rig.camera.fov
	world = TableWorld.new(tavern)
	tavern.table_root.add_child(world)
	world.cards.sfx.connect(Sfx.play)
	world.banter.sfx.connect(Sfx.play.bind(0.08))
	world.sfx.connect(Sfx.play.bind(0.02))   # 结算庆祝:礼炮、开场小号、掌声
	post_fx = PostFx.new()
	add_child(post_fx)
	_ui = _ui_layer(5)
	labels = WorldLabels.new(tavern.camera_rig.camera)
	_ui.add_child(labels)
	# 丢番茄与快捷语:压在屏幕之上(左侧小圆牌、快捷语面板),说明书之下
	banter_view = BanterView.new(self)
	_ui_layer(6).add_child(banter_view)
	# 说明书单独一层:压在所有屏幕之上(切换屏幕也不会被盖住),提示条仍在它上面
	_rules_root = _ui_layer(10)
	toasts = ToastLayer.new()
	_ui_layer(20).add_child(toasts)
	Net.joined_lobby.connect(_show_lobby)
	Net.returned_to_lobby.connect(_show_lobby)
	Net.left_lobby.connect(_back_to_menu)
	Net.game_started.connect(_show_table)
	RoomTextures.build(self)   # 墙地噪声与墙饰图集(不 await:与牌面共用等待帧,烘好后材质自动换图)
	await CardFaces.build(self)
	await MeshForge.wait_prebuilt(get_tree())
	Card3D.refresh_materials()
	# 先应用上次保存的静音设置再开环境音:静音启动时环境音等取消静音后才开始
	Sfx.set_muted(Settings.get_bool(Settings.KEY_MUTED, false, settings_path))
	Sfx.start_ambience()
	_show_menu()
	# 头像图集在菜单出来之后才开始做,不阻塞启动;没做好之前头像显示色圆片加首字
	SpeciesPortraits.build(self)
	flags = DebugFlags.new(self)
	add_child(flags)


func _unhandled_input(event: InputEvent) -> void:
	# 任何屏幕下按 F1 翻开说明书(合上由说明书自己处理)
	if Rulebook.is_hotkey(event):
		get_viewport().set_input_as_handled()
		show_rules()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game(0)


func quit_game(code: int) -> void:
	# 优雅退出:先断开联机(房主通知客人解散)、停掉音频,等音频线程回收后再退出
	Net.leave()
	Sfx.shutdown()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(code)


func _exit_tree() -> void:
	# 静态缓存持有的资源在退出时释放,避免 ObjectDB 泄漏告警
	Card3D.clear_materials()
	CardFaces.clear()
	PokerFaces.clear()
	BombCatFaces.clear()
	BombCatProps.clear_cache()
	DdzJokerFaces.clear()
	DdzProps.clear_cache()
	WorldMaterials.clear_cache()
	MeshKit.clear_cache()
	MeshForge.clear_cache()
	ChipStack3D.clear_cache()
	Fx.clear_cache()
	UiTheme.clear_cache()
	SpeciesPortraits.clear()
	PatronAntics.clear_cache()
	PatronDance.clear_cache()
	ConfettiFx.clear_cache()
	AnimalVoice.clear_cache()
	RoomTextures.clear()


static func resolve_species(path: String, args: PackedStringArray = OS.get_cmdline_user_args()) -> int:
	# 首次启动(还没存过形象)随机挑一个并立刻保存;调试开关 --species 只覆盖本次运行,不写设置
	var saved := Settings.ensure_species(path)
	var override := DebugFlags.species_override(args)
	return override if override != Species.UNASSIGNED else saved


func toast(text: String, color := UiTheme.PARCHMENT) -> void:
	toasts.show_toast(text, color)


func confirm(message: String, confirm_text := "确定", cancel_text := "取消") -> ConfirmOverlay:
	# 确认框在界面层,低于说明书;先合上说明书,免得确认框(如「房主已解散」)被挡在后面
	if is_rules_open():
		_rulebook.close()
	var overlay := ConfirmOverlay.new(message, confirm_text, cancel_text)
	_ui.add_child(overlay)
	# 记下来:网络驱动的屏幕切换(开局、回等待厅、被请出)时一并收走,旧确认框已没有意义
	_confirms.append(overlay)
	overlay.tree_exited.connect(func(): _confirms.erase(overlay))
	return overlay


func current_screen() -> Control:
	return _screen


func show_rules() -> void:
	# 翻开说明书:默认是当前玩法那本,两本书各停在上次读到的那一章
	if is_rules_open():
		return
	_rulebook = Rulebook.new(Net.in_game, RulebookContent.book_for_mode(_rules_mode()), _rules_pages)
	_rulebook.closed.connect(func():
		_rules_pages = _rulebook.bookmarks()
		_rulebook = null)
	# 翻到德州那本就在后台生成德州牌面(规格 §5.2),生成完让当前页的示例小牌重新取纹理;
	# 连的是说明书节点的方法,说明书合上释放后连接自动断开
	_rulebook.book_shown.connect(_on_book_shown)
	_rules_root.add_child(_rulebook)


func _on_book_shown(book: String) -> void:
	if book == RulebookContent.BOOK_BOMB_CAT and not BombCatFaces.is_built() and is_instance_valid(_rulebook):
		# 炸弹猫那本的牌面小图同理:后台生成,生成完让当前页重新取纹理
		var bomb_built := BombCatFaces.built_signal()
		if not bomb_built.is_connected(_rulebook.refresh_card_faces):
			bomb_built.connect(_rulebook.refresh_card_faces)
		BombCatFaces.build(_rulebook)
		return
	if book == RulebookContent.BOOK_DOU_DIZHU and not DdzJokerFaces.faces_ready() and is_instance_valid(_rulebook):
		# 斗地主那本的牌型小图:德州 52 张 + 两张王,后台生成完让当前页重新取纹理
		for sig in [PokerFaces.built_signal(), DdzJokerFaces.built_signal()]:
			if not sig.is_connected(_rulebook.refresh_card_faces):
				sig.connect(_rulebook.refresh_card_faces)
		PokerFaces.build(_rulebook)
		DdzJokerFaces.build(_rulebook)
		return
	if book != RulebookContent.BOOK_POKER or PokerFaces.is_built() or not is_instance_valid(_rulebook):
		return
	var built := PokerFaces.built_signal()
	if not built.is_connected(_rulebook.refresh_card_faces):
		built.connect(_rulebook.refresh_card_faces)
	PokerFaces.build(_rulebook)


func _rules_mode() -> String:
	# 说明书默认翻哪种玩法(规格 §6.6):在房间里(等待厅、牌桌)看本房的玩法;主菜单上(含它出来之前)
	# 看上次选的玩法。设置里读到非法值时 book_for_mode 回退骗子酒馆那本
	if _screen == null or _screen is MainMenuScreen:
		return Settings.get_string(Settings.KEY_LAST_MODE, GameMode.DEFAULT, settings_path)
	return Net.game_mode


func is_modal_open() -> bool:
	# 说明书或确认框盖在牌桌上:牌桌不再读取持续按住的按键(如 WASD 伸脖子)
	return is_rules_open() or not _confirms.is_empty()


func is_rules_open() -> bool:
	# is_instance_valid:说明书若没走 close() 就被释放,引用不会卡住
	return is_instance_valid(_rulebook)


func apply_table_mode(mode: String) -> void:
	# 桌子跟着玩法走:德州桌更大,不摆烛台与目标牌立牌;主菜单与骗子酒馆用原来的桌子;
	# 炸弹猫与吹牛骰子用骗子酒馆的桌子与烛台,不摆目标牌立牌(5–6 人的大桌由各自的牌桌按本局人数再摆)
	var poker := GameMode.is_poker(mode)
	world.configure_table(SeatLayout.table_radius_for(mode))
	tavern.set_table_decor_visible(not poker)
	world.cards.set_stand_visible(mode == GameMode.LIARS)


# —— 屏幕切换 ——

func _show_menu() -> void:
	world.clear_poker()   # 从德州房间回来:拆掉德州的 3D 节点(规格 §5.1)
	world.clear()
	labels.clear()
	apply_table_mode(GameMode.LIARS)
	tavern.camera_rig.parallax_enabled = false
	tavern.camera_rig.orbit(Vector3(0, 0.9, -0.2), 3.3, 1.15, 0.045, 2.2)
	_switch_to(MainMenuScreen.new(self))


func _show_lobby() -> void:
	tavern.camera_rig.parallax_enabled = false
	_switch_to(LobbyScreen.new(self))


func _show_table(_seats: Array) -> void:
	# 按本房玩法选牌桌屏幕(game_started 发出之前 game_mode 已设好);等待厅的进出提示到这里已经过时
	toasts.clear()
	if GameMode.is_bomb_cat(Net.game_mode):
		_switch_to(BombCatScreen.new(self))
		return
	if GameMode.is_liars_dice(Net.game_mode):
		_switch_to(LiarsDiceScreen.new(self))
		return
	if GameMode.is_dou_dizhu(Net.game_mode):
		_switch_to(DouDizhuScreen.new(self))
		return
	_switch_to(PokerScreen.new(self) if GameMode.is_poker(Net.game_mode) else TableScreen.new(self))


func _back_to_menu(reason: String) -> void:
	_show_menu()
	if reason != "":
		confirm(reason, "知道了", "")


func _ui_layer(index: int) -> Control:
	var layer := CanvasLayer.new()
	layer.layer = index
	add_child(layer)
	var root := Control.new()
	root.theme = UiTheme.theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	return root


func _switch_to(screen: Control) -> void:
	_dismiss_confirms()
	_reset_view()
	if is_instance_valid(_screen):
		# 先移出场景树:旧屏幕的 _exit_tree(清铭牌、停监听)在新屏幕 _ready 之前同步跑完。
		# 用延迟 free 而不是 queue_free:消息队列在本帧计时器与补间之前刷新,旧屏幕停在半路的
		# 演出协程不会在树外被唤醒(树外 get_tree() 为空,create_tween 也会失败)
		_ui.remove_child(_screen)
		_screen.free.call_deferred()
	_screen = screen
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(screen)


func _dismiss_confirms() -> void:
	for overlay in _confirms.duplicate():
		if is_instance_valid(overlay):
			overlay.dismiss()
	_confirms.clear()


func _reset_view() -> void:
	# 旧屏幕的演出可能停在半路(举枪紧张、中弹染红、镜头变焦):共享的后处理与镜头统一回到平静
	post_fx.reset(VIEW_RESET_TIME)
	tavern.camera_rig.set_fov(_default_fov, VIEW_RESET_TIME)
	# 胜者特写留下的补光也要灭掉;进牌桌时开场运镜会马上重新点亮
	tavern.camera_rig.set_fill(0.0, VIEW_RESET_TIME)
