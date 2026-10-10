class_name DebugFlags
extends Node
# 命令行调试开关(写在 -- 之后),用于联机冒烟测试与截图检查:
#   --name=甲            自动填写昵称
#   --species=物种id     本次运行想要的形象(fox/bear/…/crocodile),只覆盖本次、不写设置;
#                        每次名单更新与开局时打印 [debug] species {pid: id}(冒烟测试比对各进程)
#   --autohost[=N]       自动建房;满 N 人(默认 2)且全员准备后自动开局
#   --mode=玩法id        配合 --autohost:liars / bomb_cat / liars_dice / dou_dizhu / holdem / short_deck(默认 liars;非法值退出码 1),默认房名跟着玩法
#   --hands=N            德州 / 斗地主房主:演到第 N 手开始时散局(本手结束后结算);非法值退出码 1
#   --port=端口          房主优先绑定的游戏端口(并行测试互不串房)
#   --room=房名          房主的房间名
#   --autojoin=IP[:端口] 自动直连
#   --discover[=房名]    自动加入局域网发现的(指定名字的)房间
#   --bot                自动准备/选牌/出牌/质疑(走真实界面路径);开局后朝别人丢一个番茄、按 Q 说一句快捷语;
#                        对局中隔几秒说一句快捷对话(九宫格,同样走真实界面路径);
#                        德州按合法动作下注、输光再领(见 PokerBot);
#                        炸弹猫里由 BombCatBot 出牌、偶尔不行!、摸牌、塞回、给牌(同样走牌桌的公开入口);
#                        斗地主里由 DdzBot 随机叫分、按「提示」出牌、偶尔不出(同样走牌桌的公开入口);
#                        吹牛骰子里由 LiarsDiceBot 喊价或「开!」(经出价器的 nudge_count / pick_face 与 submit_bid / submit_challenge)
#   --no-fidget          配合 --bot:不按 W / S 探头缩头(截图检查时画面不被自己伸出去的头挡住;冒烟测试的脖子同步要靠它,别加)
#   --fast[=倍率]        加速演出(Engine.time_scale,默认 3)
#   --quit-after-match   对局结束后退出(退出码 0);中途失败退出码 1
#   --shots=目录         在关键时刻截图
#   --shots-every=秒     配合 --shots:另外每隔这么久(真实时间)拍一张 <名>_t<序号>.png,逐帧检查演出节奏
#   --camera=first|third 本次运行的牌桌视角(第一人称 / 越肩),只覆盖本次、不写设置
#   --update-from=IP:端口 从这个房主下载更新并装好,装好后打印 UPDATE_READY 退出(失败退出码 1)
#   --update-url=网址    同上,但从任意更新源(如 BuildInfo.FEED_URL + 平台 + "/")


const BOT_THINK := Vector2(0.6, 1.6)
const CHALLENGE_CHANCE := 0.35
const BOT_FIDGET := 1.5    # bot 按住 W 探头、松开、按住 S 收回、松开,每步这么久(秒);冒烟测试据此确认脖子偏移走通了网络
const BOT_FIDGET_KEYS := [KEY_W, KEY_S]
const SHOT_SETTLE_DRAWS := 8   # 截图前连续强制绘制的帧数(体积雾的时域累积要几帧才收敛)
const BOT_BANTER_DELAY := 2.0  # 开局后 bot 过这么久丢番茄,再过 BOT_SAY_DELAY 说快捷语(冒烟测试核对各端都收到)
const BOT_SAY_DELAY := 1.8
const BOT_RETRY := 2.0         # 德州 bot 提交后(被拒或没生效)再试的间隔
const BOT_QUIP_EVERY := Vector2(6.0, 12.0)   # bot 每隔这么久(游戏秒)说一句快捷对话;冒烟测试据此确认对话走通了网络
const SPECTATE_HOLD := 5.0     # 截图模式下 bot 第一次输光先观战,看这么久再领筹码上桌(拍到观战机位)
const MainMenuScreen := preload("res://src/ui/main_menu/main_menu.gd")

var app: Node
var opts := {}
var _think_timer := 0.0
var _shot_counts := {}
var _match_finished := false
var _gaze_from := {}   # 收到过谁的视线同步(冒烟测试据此确认视线消息走通)
var _neck_from := {}   # 收到过谁伸出的脖子
var _fidget_timer := BOT_FIDGET
var _fidget_step := 0
var _tomato_from := {}   # 收到过谁丢的番茄(冒烟测试据此确认丢番茄走通)
var _said_from := {}     # 收到过谁说的快捷语
var _bomb_bot: BombCatBot = null
var _ddz_bot: DdzBot = null
var _dice_bot: LiarsDiceBot = null
var _hands_limit := 0      # --hands:演到第几手开始时散局;0 = 不自动散局
var _hands_dealt := 0      # 自己被发到牌的手数(冒烟测试据此确认迟到者真的上了桌)
var _spectated := false    # 截图模式下已经观战过一次
var _quip_timer := BOT_QUIP_EVERY.x
var _quip_from := {}       # 收到过谁的快捷对话(不含自己)


func _init(p_app: Node) -> void:
	app = p_app
	opts = parse_user_args()


static func parse_user_args(args: PackedStringArray = OS.get_cmdline_user_args()) -> Dictionary:
	# "--key=value" → {key: value};不带值的 "--flag" → {flag: "true"};空键忽略。
	# 注意:以 -s 启动的工具脚本编译时 autoload(Net/Discovery)还没注册,引用本类会编译失败,
	# 所以 tools/*.gd 不能直接调用这里
	var out := {}
	for arg in args:
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv[0] != "":
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out


static func species_override(args: PackedStringArray = OS.get_cmdline_user_args()) -> int:
	# --species=<id> 的物种下标;没给或 id 不认识时返回 UNASSIGNED(后者告警),沿用设置里的形象
	var value: String = parse_user_args(args).get("species", "")
	if value == "":
		return Species.UNASSIGNED
	var index := Species.index_of(value)
	if index == Species.UNASSIGNED:
		push_warning("--species=%s 不是已知形象(可选:%s),沿用设置里的形象" % [value, ", ".join(Species.IDS)])
	return index


static func patrons_line(patrons: Dictionary) -> String:
	# 本机实际建出来的酒客形象(按 pid 排序):「[debug] patrons {1: crocodile, 2034: fox}」;冒烟测试比对各端画面是否一致
	var pids := patrons.keys().filter(func(pid): return is_instance_valid(patrons[pid]))
	pids.sort()
	var parts := pids.map(func(pid) -> String: return "%d: %s" % [pid, Species.IDS[patrons[pid].species_index]])
	return "[debug] patrons {%s}" % ", ".join(parts)


static func species_line(entries: Array) -> String:
	# entries:[{pid, species}](名单或座位表,按座位顺序)→「[debug] species {1: crocodile, 2034: fox}」;没有形象写「-」
	var parts := entries.map(func(p: Dictionary) -> String:
		var index := Species.sanitize(p.get("species"))
		return "%s: %s" % [p.get("pid"), Species.IDS[index] if index != Species.UNASSIGNED else "-"])
	return "[debug] species {%s}" % ", ".join(parts)


static func mode_option(p_opts: Dictionary) -> String:
	# --mode:不写为默认玩法;不认识的值返回 "",由调用方以退出码 1 结束
	var mode: String = p_opts.get("mode", GameMode.DEFAULT)
	return mode if GameMode.is_valid(mode) else ""


static func hands_option(p_opts: Dictionary) -> int:
	# --hands:不写为 0(不自动散局);不是正整数返回 -1
	if not p_opts.has("hands"):
		return 0
	var text: String = p_opts["hands"]
	return int(text) if text.is_valid_int() and int(text) > 0 else -1


static func room_option(p_opts: Dictionary, player_name: String, mode: String) -> String:
	return p_opts.get("room", MainMenuScreen.default_room_name(player_name, mode))


static func net_of(results: Array, pid: int) -> int:
	for row in results:
		if row is Dictionary and row.get("pid") == pid and row.get("net") is int:
			return row["net"]
	return 0


static func net_sum(results: Array) -> int:
	var total := 0
	for row in results:
		if row is Dictionary and row.get("net") is int:
			total += row["net"]
	return total


func _ready() -> void:
	if opts.is_empty():
		set_process(false)
		return
	print("[debug] flags: ", opts)
	print("[debug] build=%d active_update=%d installer=%d" % [BuildInfo.build(), UpdateBoot.active_build,
		UpdateBoot.installer["build"]])
	if opts.has("update-from") or opts.has("update-url"):
		_update_from(opts.get("update-from", ""), opts.get("update-url", ""))
		return
	if opts.has("fast"):
		Engine.time_scale = float(opts["fast"]) if opts["fast"] != "true" else 3.0
	var mode := mode_option(opts)
	_hands_limit = hands_option(opts)
	if mode == "" or _hands_limit < 0:
		push_error("[debug] FAIL bad_flag mode=%s hands=%s" % [opts.get("mode", ""), opts.get("hands", "")])
		app.quit_game(1)
		return
	Net.joined_lobby.connect(_on_joined)
	Net.lobby_updated.connect(_on_lobby)
	Net.game_events.connect(_on_events)
	Net.game_started.connect(_on_game_started)
	Net.gaze_updated.connect(func(pid: int, _point: Vector3, neck: Vector3, _active: bool):
		_gaze_from[pid] = true
		if neck != Vector3.ZERO:
			_neck_from[pid] = true)
	Net.banter.tomato_thrown.connect(func(from_pid: int, _target: int, _seed: int): _tomato_from[from_pid] = true)
	Net.banter.said.connect(func(pid: int, _phrase: int): _said_from[pid] = true)
	Net.quip_shown.connect(func(pid: int, _index: int):
		if pid != Net.my_pid():
			_quip_from[pid] = true
			_capture_once("quip", 0.8))
	Net.join_failed.connect(_fail.bind("join_failed"))
	Net.left_lobby.connect(_on_left)
	if opts.has("shots"):
		DirAccess.make_dir_recursive_absolute(opts["shots"])
		_capture_later("menu", 2.5)
		if opts.has("shots-every"):
			_capture_every(maxf(0.2, float(opts["shots-every"])))
	var player_name: String = opts.get("name", "测试%d" % (OS.get_process_id() % 1000))
	if opts.has("autohost"):
		var err := Net.host_game(player_name, room_option(opts, player_name, mode), int(opts.get("port", "0")), mode, _species())
		print("[debug] host_game -> ", error_string(err))
		if err != OK:
			_fail("host_failed")
	elif opts.has("autojoin"):
		Net.join_game(player_name, opts["autojoin"], _species())
	elif opts.has("discover"):
		Discovery.rooms_updated.connect(_join_discovered.bind(player_name))


func _join_discovered(rooms: Array, player_name: String) -> void:
	if Net.in_game or not Net.lobby_players.is_empty() or Net.player_name != "":
		return
	var wanted: String = opts["discover"]
	for room in rooms:
		if room["open"] and (wanted == "true" or room["room"] == wanted):
			print("[debug] discovered ", room["room"], " at ", room["ip"], ":", room["port"])
			Net.join_game(player_name, Protocol.format_address(room["ip"], room["port"]), _species())
			return


static func host_mode(flags: Dictionary) -> String:
	# --mode=<玩法 id>;没给或不认识时用默认玩法(后者告警)
	var mode: String = flags.get("mode", GameMode.DEFAULT)
	if not GameMode.is_valid(mode):
		push_warning("--mode=%s 不是已知玩法(可选:%s),用默认玩法" % [mode, ", ".join(GameMode.ALL)])
		return GameMode.DEFAULT
	return mode


func _species() -> int:
	# 本机想要的形象:main 已经按设置解析好,--species 覆盖本次运行
	return Species.sanitize(app.get("species"))


func _process(delta: float) -> void:
	if not opts.has("bot"):
		return
	_fidget(delta)
	var screen: Node = app.current_screen()
	_bot_quip(screen, delta)
	if screen != null and screen.get("state") is BombCatScreenState:
		_bomb_bot_tick(screen, delta)
		return
	if screen != null and screen.get("state") is DdzScreenState:
		_ddz_bot_tick(screen, delta)
		return
	if screen != null and screen.get("state") is LiarsDiceScreenState:
		_dice_bot_tick(screen, delta)
		return
	if screen != null and screen.has_method("choose_rebuy"):
		_poker_tick(screen, delta)
		return
	if screen == null or not screen.has_method("_my_turn") or not screen._my_turn():
		_think_timer = randf_range(BOT_THINK.x, BOT_THINK.y)
		return
	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = 999.0
	_bot_act(screen)


func _bot_quip(screen: Node, delta: float) -> void:
	# 与九宫格按钮同一入口(QuipController.choose)
	_quip_timer -= delta
	if _quip_timer > 0.0 or not Net.in_game or screen == null:
		return
	_quip_timer = randf_range(BOT_QUIP_EVERY.x, BOT_QUIP_EVERY.y)
	var quips: Variant = screen.get("quips")
	if not quips is QuipController:
		return
	if opts.has("shots") and not _shot_counts.has("quip_menu"):
		# 截图模式第一次先把九宫格打开拍一张,再选
		quips.menu.open()
		_capture_once("quip_menu", 0.3)
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(quips):
			return
	quips.choose(randi() % Quips.LINES.size())


func _poker_tick(screen: Node, delta: float) -> void:
	# 轮到自己就下注;输光再领(截图模式第一次先观战);挂机离座就回座;一手结束点「开始下一手」。都走 PokerScreen 给按钮用的入口。
	# 散局后什么都不做(结算事件到了、面板还没弹出时去领筹码只会被房主拒绝)
	if _match_finished:
		return
	var status: String = screen.my_status()
	var seat_choice: bool = status in [PokerRules.STATUS_BUSTED, PokerRules.STATUS_SPECTATING, PokerRules.STATUS_AWAY] \
		or screen.wants_next()
	if not screen.is_my_turn() and not seat_choice:
		_think_timer = randf_range(BOT_THINK.x, BOT_THINK.y)
		return
	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = BOT_RETRY
	if screen.is_my_turn():
		PokerBot.act(screen)
	elif status == PokerRules.STATUS_BUSTED and opts.has("shots") and not _spectated:
		_spectated = screen.choose_spectate()
		_think_timer = SPECTATE_HOLD
	elif status == PokerRules.STATUS_AWAY:
		screen.choose_sit_in()
	elif screen.wants_next():
		screen.choose_next()
	else:
		screen.choose_rebuy()


func _update_from(address: String, url: String) -> void:
	Updater.changed.connect(_on_update_changed)
	if url != "":
		Updater.check(url, "网络")
		return
	var addr := Protocol.parse_address(address)
	Updater.check(Updater.lan_source(addr["ip"], addr["port"]), "房主")


func _on_update_changed() -> void:
	match Updater.state:
		Updater.State.AVAILABLE:
			Updater.download()
		Updater.State.READY:
			print("[debug] UPDATE_READY build=%d" % Updater.manifest["build"])
			get_tree().quit(0)
		Updater.State.BLOCKED, Updater.State.FAILED:
			print("[debug] UPDATE_FAIL ", Updater.message)
			get_tree().quit(1)


func _fidget(delta: float) -> void:
	# 对局中轮流按住 W、S:走与真人相同的按键读取,头探出去再收回来
	_fidget_timer -= delta
	if not Net.in_game or _fidget_timer > 0.0 or opts.has("no-fidget"):
		return
	_fidget_timer = BOT_FIDGET
	var key := InputEventKey.new()
	key.physical_keycode = BOT_FIDGET_KEYS[floori(_fidget_step / 2.0) % BOT_FIDGET_KEYS.size()]
	key.pressed = _fidget_step % 2 == 0
	Input.parse_input_event(key)
	_fidget_step += 1


func _bot_act(screen: Node) -> void:
	# 与界面同一规则:不能质疑自己的出牌(断线后轮转可能回到出牌者)
	var can_challenge: bool = screen._can_challenge()
	var hand_size: int = screen.cards.my_cards.size()
	if can_challenge and (randf() < CHALLENGE_CHANCE or hand_size == 0):
		screen._submit_challenge()
		return
	var indices := range(hand_size)
	indices.shuffle()
	for i in indices.slice(0, randi_range(1, mini(3, hand_size))):
		screen._toggle(i)
	screen._submit_play()


func _bomb_bot_tick(screen: Node, delta: float) -> void:
	# 炸弹猫:想一会儿再走一步;这一刻没事可做就过一小会儿再看(反应窗口只有 3 秒)
	if _bomb_bot == null:
		_bomb_bot = BombCatBot.new()
	_think_timer -= delta
	if _think_timer > 0.0:
		return
	if _bomb_bot.act(screen):
		_think_timer = randf_range(BOT_THINK.x, BOT_THINK.y)
	else:
		_think_timer = 0.25


func _ddz_bot_tick(screen: Node, delta: float) -> void:
	# 斗地主:轮到自己就想一会儿再出手(叫分 / 提示出牌 / 不出);散局后什么都不做
	if _ddz_bot == null:
		_ddz_bot = DdzBot.new()
	if _match_finished:
		return
	if not screen.is_my_turn():
		_think_timer = randf_range(BOT_THINK.x, BOT_THINK.y)
		return
	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = BOT_RETRY
	_ddz_bot.act(screen)


static func ddz_results_line(results: Array) -> String:
	# 斗地主结算(按 pid 排序):「[debug] DDZ_RESULTS {1: 12, 2034: -6, 5120: -6} sum=0」;冒烟测试比对三端一致、总和为 0
	var rows := results.filter(func(r): return r is Dictionary and r.get("pid") is int and r.get("score") is int)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["pid"] < b["pid"])
	var total := 0
	var parts := []
	for row in rows:
		parts.append("%d: %d" % [row["pid"], row["score"]])
		total += row["score"]
	return "[debug] DDZ_RESULTS {%s} sum=%d" % [", ".join(parts), total]


func _dice_bot_tick(screen: Node, delta: float) -> void:
	# 吹牛骰子:轮到自己时想一会儿再喊价或「开!」
	if _dice_bot == null:
		_dice_bot = LiarsDiceBot.new()
	if not screen.is_my_turn():
		_think_timer = randf_range(BOT_THINK.x, BOT_THINK.y)
		return
	_think_timer -= delta
	if _think_timer > 0.0:
		return
	_think_timer = BOT_RETRY
	_dice_bot.act(screen)


func _bot_banter(seats: Array) -> void:
	# 走真实界面:光标移到下家的头上丢番茄(同 G / 右键的入口,界面按屏幕投影选目标),再按 Q 打开快捷语面板、按数字说出
	await get_tree().create_timer(BOT_BANTER_DELAY + randf() * 0.5).timeout
	var order := seats.map(func(s): return s["pid"])
	var me := order.find(Net.my_pid())
	var target: int = order[(me + 1) % order.size()]
	var view: BanterView = app.get("banter_view")
	var world: TableWorld = app.get("world")
	if view != null and world != null and world.patrons.has(target):
		var camera: Camera3D = app.tavern.camera_rig.camera
		var head: Vector3 = world.patrons[target].head_position()
		var picked := BanterView.pick_target(camera, camera.unproject_position(head), world.patrons, Net.my_pid())
		if picked == target:
			view.throw_at_cursor(camera.unproject_position(head))
		else:
			Net.banter.throw_tomato(target)   # 镜头在拍特写、下家不在画面里:直接发
	await get_tree().create_timer(BOT_SAY_DELAY).timeout
	for keycode in [KEY_Q, KEY_1 + randi() % Banter.PHRASES.size()]:
		for pressed in [true, false]:
			var key := InputEventKey.new()
			key.keycode = keycode
			key.pressed = pressed
			Input.parse_input_event(key)
			await get_tree().process_frame


func _on_joined() -> void:
	print("[debug] joined lobby as ", Net.my_pid())
	if opts.has("shots"):
		_capture_later("lobby", 3.0)
	if opts.has("bot") and not Net.is_host:
		await get_tree().create_timer(0.8).timeout
		var screen: Node = app.current_screen()
		if screen != null and screen.has_method("_on_ready_toggled"):
			screen._on_ready_toggled()


func _on_lobby(players: Array) -> void:
	# 对局中的名单更新(有人散场离开、德州有人入座)不打印:冒烟测试比对的最后一条要是开局时的座位表
	if not Net.in_game:
		print(species_line(players))
	if not Net.is_host or not opts.has("autohost"):
		return
	var want := int(opts["autohost"]) if opts["autohost"] != "true" else 2
	if players.size() >= want and Net.can_start():
		print("[debug] starting game with ", players.size(), " players")
		await get_tree().create_timer(1.0).timeout
		if Net.can_start():
			Net.start_game()


func _on_events(events: Array) -> void:
	for ev in events:
		match ev["type"]:
			"match_over":
				print("[debug] GAZE peers=%d necks=%d" % [_gaze_from.size(), _neck_from.size()])
				print("[debug] BANTER tomatoes=%d said=%d" % [_tomato_from.size(), _said_from.size()])
				print("[debug] QUIPS heard=%d" % _quip_from.size())
				print("[debug] MATCH_OVER winner=", ev["winner"])
				_match_finished = true
			"hand_started":
				print("[debug] HAND_STARTED hand=", ev.get("hand"))
			"hole_cards":
				if Net.my_pid() in ev.get("pids", []):
					_hands_dealt += 1
					print("[debug] DEALT hand=", ev.get("hand"))
			"hand_over":
				if GameMode.is_dou_dizhu(Net.game_mode):
					print("[debug] DDZ_HAND_OVER hand=%s landlord_won=%s" % [ev.get("hand"), ev.get("landlord_won")])
			"session_over":
				var results: Array = ev.get("results", [])
				if GameMode.is_dou_dizhu(Net.game_mode):
					print(ddz_results_line(results))
				print("[debug] GAZE peers=%d necks=%d" % [_gaze_from.size(), _neck_from.size()])
				print("[debug] BANTER tomatoes=%d said=%d" % [_tomato_from.size(), _said_from.size()])
				print("[debug] QUIPS heard=%d" % _quip_from.size())
				print(patrons_line(app.world.patrons))
				print("[debug] SESSION_OVER hands_dealt=%d net=%d" % [_hands_dealt, net_of(results, Net.my_pid())])
				if Net.is_host:
					print("[debug] net_sum=%d" % net_sum(results))
				_match_finished = true


func _on_game_started(seats: Array) -> void:
	print(species_line(seats))
	if opts.has("bot"):
		_bot_banter(seats)
	# 截图与退出按演出进度触发:事件批到达时前面的动画可能还要播好几秒
	await get_tree().process_frame
	var screen: Node = app.current_screen()
	var director = screen.get("director") if screen != null else null
	if director is TableDirector or director is BombCatDirector or director is LiarsDiceDirector:
		director.event_started.connect(_on_director_event)
	elif director is PokerDirector:
		director.event_started.connect(_on_poker_event)
	elif director is DdzDirector:
		director.event_started.connect(_on_ddz_event)
	if director != null and opts.has("camera") and director.get("seat_camera") != null:
		director.seat_camera.set_first_person(opts["camera"] == "first", false)
		_capture_once("seat", 3.0)


func _on_director_event(ev: Dictionary) -> void:
	match ev["type"]:
		"round_started":
			_capture_once("deal", 3.0)
			if GameMode.is_liars_dice(Net.game_mode):
				_capture_once("shake", 0.6)   # 吹牛骰子:全员捧着骰盅摇
				_capture_once("peek", 1.3)   # 扣下后掀开盅沿偷看
		"played":
			_capture_once("played", 0.55)
		"reveal":
			_capture_once("reveal", 1.2 + 0.68 * ev.get("cards", []).size())
		"gunshot":
			_capture_once("suspense", 2.0)
			_capture_once("shot_result", 3.0)
		"bomb_drawn":
			_capture_once("bomb", 1.0)
		"exploded":
			_capture_once("exploded", 1.6)
		"defused":
			_capture_once("defused", 1.2)
		"bid":
			_capture_once("bid", 0.6)
		"revealed":
			_capture_once("dice_reveal", 1.0)
		"die_lost":
			_capture_once("die_lost", 0.35)
		"player_out":
			_capture_once("player_out", 1.0)
		"match_over":
			_capture_once("victory", 1.5)
			_capture_once("settlement", 3.3)
			if opts.has("quit-after-match"):
				await get_tree().create_timer(5.0 if Net.is_host else 4.0).timeout
				app.quit_game(0)


func _on_poker_event(ev: Dictionary) -> void:
	# 德州截图标记(规格 §8):deal、flop、my_turn、allin、showdown、pot_won、spectate、settlement
	match ev.get("type", ""):
		"hand_started":
			_capture_once("deal", PokerDirector.HAND_START_SETTLE + 1.5)
			if Net.is_host and _hands_limit > 0 and ev.get("hand") == _hands_limit:
				print("[debug] ending session after hand ", _hands_limit)
				Net.end_poker_session()
		"street":
			if ev.get("street") == PokerRules.FLOP:
				_capture_once("flop", 1.0)
		"turn":
			if ev.get("pid") == Net.my_pid():
				_capture_once("my_turn", 0.3)
		"action":
			if ev.get("all_in", false):
				_capture_once("allin", 0.8)
		"reveal":
			if ev.get("reason") == PokerRules.SHOWDOWN:
				_capture_once("showdown", 1.0)
		"pot_won":
			_capture_once("pot_won", 1.2)
		"hand_over":
			_capture_once("next_prompt", 1.0)
		"hand_record":
			if opts.has("shots") and not _shot_counts.has("history") and _hands_dealt >= 2:
				# 打过两手后打开牌局记录拍一张,再收起
				var screen: Node = app.current_screen()
				screen.toggle_history()
				_capture_once("history", 0.5)
				await get_tree().create_timer(1.5).timeout
				if is_instance_valid(screen) and is_instance_valid(screen.get("_history")):
					screen.toggle_history()
		"spectate":
			if ev.get("pid") == Net.my_pid():
				_capture_once("spectate", PokerDirector.CAMERA_MOVE + 0.8)
		"session_over":
			_capture_once("settlement", PokerDirector.SESSION_OVER_HOLD + 1.0)
			if opts.has("quit-after-match"):
				await get_tree().create_timer(5.0 if Net.is_host else 4.0).timeout
				app.quit_game(0)


func _on_ddz_event(ev: Dictionary) -> void:
	# 斗地主截图标记:deal、bidding、landlord、played、bomb / rocket / plane、hand_over、settlement;房主打到 --hands 手散局
	match ev.get("type", ""):
		"hand_started":
			_capture_once("deal", 2.6)
			if Net.is_host and _hands_limit > 0 and ev.get("hand") == _hands_limit:
				print("[debug] ending session after hand ", _hands_limit)
				Net.end_poker_session()
		"turn":
			if ev.get("pid") == Net.my_pid():
				_capture_once("my_turn_bid" if ev.get("stage") == DdzState.STAGE_BID else "my_turn", 0.4)
		"landlord":
			_capture_once("landlord", 1.0)
		"played":
			match DdzDirector.effect_for(str(ev.get("combo", ""))):
				"bomb":
					_capture_once("bomb", 0.75)
				"rocket":
					_capture_once("rocket", 0.95)
				"plane":
					_capture_once("plane", 0.75)
				_:
					_capture_once("played", 0.6)
		"hand_over":
			_capture_once("hand_over", 1.6)
		"session_over":
			_capture_once("settlement", DdzDirector.SESSION_OVER_HOLD + 1.0)
			if opts.has("quit-after-match"):
				await get_tree().create_timer(5.0 if Net.is_host else 4.0).timeout
				app.quit_game(0)


func _on_left(reason: String) -> void:
	if opts.has("quit-after-match") and not _match_finished:
		_fail("left_lobby: " + reason)


func _fail(reason: String, detail := "") -> void:
	push_error("[debug] FAIL %s %s" % [reason, detail])
	if opts.has("quit-after-match") or opts.has("autojoin") or opts.has("autohost"):
		app.quit_game(1)


# —— 截图 ——

func _capture_once(tag: String, delay: float) -> void:
	if not opts.has("shots") or _shot_counts.has(tag):
		return
	_shot_counts[tag] = true
	_capture_later(tag, delay)


func _capture_every(period: float) -> void:
	# 按真实时间定时拍(不受 --fast 影响),序号连续
	var index := 0
	while is_inside_tree():
		await get_tree().create_timer(period, true, false, true).timeout
		_capture_later("t%03d" % index, 0.0)
		index += 1


func _capture_later(tag: String, delay: float) -> void:
	if not opts.has("shots"):
		return
	await get_tree().create_timer(delay).timeout
	# 窗口被别的窗口挡住时 macOS 不再调度正常绘制,等 frame_post_draw 会永远卡住;
	# 强制绘制几帧再读图,不依赖窗口可见(同 tools/shot.gd)
	for i in SHOT_SETTLE_DRAWS:
		RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return
	var path := "%s/%s_%s.png" % [opts["shots"], opts.get("name", "p"), tag]
	image.save_png(path)
	print("[debug] shot ", path)
