extends Node
# 网络管理(autoload "Net"):房主权威 listen-server。
# 房主持有等待厅名单与唯一的会话对象(LiarsSession / PokerSession / BombCatSession / LiarsDiceSession / DouDizhuSession,
# 规格 §4.2);客户端只发意图、收视图与事件。
# 这里只管连接、等待厅、RPC 收发与计时器,玩法逻辑都在会话里。
# UI 层只使用本类的公开方法、只读属性与信号,不直接触碰 multiplayer API。
# 点对点的 RPC 一律经 _send_to 发出:对方没连着就不发(离线测试里对未知 peer 调 rpc_id 会报引擎错误)。


signal lobby_updated(players: Array)
signal joined_lobby
signal left_lobby(reason: String)
signal join_failed(reason: String)
signal game_started(seats: Array)
signal state_public_updated(state: Dictionary)
signal state_private_updated(state: Dictionary)
signal game_events(events: Array)
signal intent_rejected(code: String)
signal returned_to_lobby
signal gaze_updated(pid: int, point: Vector3, neck: Vector3, active: bool)   # 他人视线落点(发送者座位坐标系)与脖子偏移
signal quip_shown(pid: int, index: int)   # 有人说了一句快捷对话(含自己;房主转发之后才到)

const HOST_ID := LobbyModel.HOST_ID
const DISCONNECT_GRACE := 1.0
const SPECIES_COOLDOWN_MS := 250   # 房主端:每个对端换形象的冷却,冷却内的请求按「被拒」处理
const LATE_SEAT_REASON := "牌桌暂时坐不下,请稍后再来"   # 名单放行但会话拒收中途加入者

# —— 只读状态(UI 读取) ——
var player_name := ""
var player_species := Species.UNASSIGNED   # 本机想要的形象(建房/加入时带上;等待厅换成功后跟着更新)
var is_host := false
var in_game := false
var lobby_players: Array = []
var lobby_meta := {}       # {"room", "host", "addresses", "port", "mode"}
var seats: Array = []      # 本局座位顺序 [{"pid", "name", "species"}]
var last_public := {}
var last_private := {}
var game_mode := GameMode.DEFAULT   # 房主:开房时选的玩法;客户端:来自等待厅 meta 或开局 info

var _session_active := false
var _joining := false
var _awaiting_game := false        # 仅客户端:对局中入座已获准,等房主发来牌局信息(rpc_game_started)
var _lobby: LobbyModel = null      # 仅房主
var _quip_gate := QuipGate.new()   # 仅房主:快捷对话限速
var _session: GameSession = null   # 仅房主:本局的玩法逻辑
var _room_id := ""
var _room_name := ""
var _port := Protocol.GAME_PORT
var _turn_timer: Timer = null
var _hand_timer: Timer = null      # 仅房主(德州、斗地主):一手之间的间隔,到点开下一手
var _join_timer: Timer = null
var _anim_left := 0.0              # 仅房主:客户端还要演多久(按 Pacing 预算估),随时间递减
var _species_asked_at := {}        # 仅房主:peer_id -> 上次换形象请求的时刻(毫秒),冷却用
var _species_wanted := Species.UNASSIGNED   # 仅客户端:等待房主确认的换形象请求
var banter: Banter = null          # 丢番茄与快捷语(子节点 /root/Net/Banter,RPC 在它身上,本类的 RPC 表不变)


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_host)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_host_disconnected)
	_turn_timer = _make_timer(_on_turn_timeout)
	_hand_timer = _make_timer(_on_hand_timer)
	_join_timer = _make_timer(_on_join_timeout)
	banter = Banter.new()
	banter.name = "Banter"
	add_child(banter)


func _process(delta: float) -> void:
	# delta 与 Timer 一样受 Engine.time_scale 影响,两者同步流逝
	if _anim_left > 0.0:
		_anim_left = maxf(_anim_left - delta, 0.0)


func my_pid() -> int:
	return multiplayer.get_unique_id()


# —— 建房 / 加入 / 离开 ——

func host_game(pname: String, room_name: String, preferred_port := 0, mode := GameMode.DEFAULT,
		species := Species.UNASSIGNED) -> Error:
	# 玩法开房时选定,开房后不能改(想换玩法就重开房间);species 是本机想要的形象(房主当场拿到)
	if not GameMode.is_valid(mode):
		push_error("开房失败:未知玩法 %s" % mode)
		return ERR_INVALID_PARAMETER
	var validation := Protocol.validate_name(Protocol.sanitize_name(pname))
	if not validation["ok"]:
		push_warning("开房失败:%s" % validation["error"])
		return ERR_INVALID_PARAMETER
	leave()
	var created := _create_server(preferred_port)
	if created["error"] != OK:
		return created["error"]
	multiplayer.multiplayer_peer = created["peer"]
	(multiplayer as SceneMultiplayer).server_relay = false
	_open_room(pname, room_name, created["port"], mode, species)
	# 游戏端口号的 TCP 上顺带提供更新文件(ENet 走 UDP,互不占用)
	Updater.start_serving(_port)
	Discovery.start_broadcast(_room_announcement)
	joined_lobby.emit()
	_broadcast_lobby()
	return OK


func _open_room(pname: String, room_name: String, port: int, mode: String, species := Species.UNASSIGNED) -> void:
	# 房主一侧的房间状态,不碰网络:离线测试据此搭出房主
	_port = port
	game_mode = mode
	player_name = Protocol.sanitize_name(pname)
	_room_name = Protocol.sanitize_text(room_name, Protocol.MAX_ROOM_NAME_LENGTH)
	_room_id = "%08x%08x" % [randi(), randi()]
	is_host = true
	_session_active = true
	player_species = Species.sanitize(species)
	_lobby = LobbyModel.new()
	_lobby.add_host(player_name, player_species)


func join_game(pname: String, address_text: String, species := Species.UNASSIGNED) -> void:
	# species:本机想要的形象,握手通过后单独发给房主(rpc_lobby_species),握手消息本身不变
	var validation := Protocol.validate_name(Protocol.sanitize_name(pname))
	if not validation["ok"]:
		join_failed.emit(validation["error"])
		return
	var addr := Protocol.parse_address(address_text)
	if not addr["ok"]:
		join_failed.emit(addr["error"])
		return
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(addr["ip"], addr["port"])
	if err != OK:
		join_failed.emit("无法发起连接(错误 %d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	player_name = Protocol.sanitize_name(pname)
	player_species = Species.sanitize(species)
	_session_active = true
	_joining = true
	_join_timer.start(Protocol.JOIN_TIMEOUT)


func leave() -> void:
	# 先清标志再关闭连接:关闭过程中触发的断线回调据此忽略
	_session_active = false
	_joining = false
	_awaiting_game = false
	is_host = false
	in_game = false
	game_mode = GameMode.DEFAULT
	Discovery.stop_broadcast()
	Updater.stop_serving()
	_turn_timer.stop()
	_hand_timer.stop()
	_join_timer.stop()
	_anim_left = 0.0
	_species_asked_at = {}
	_species_wanted = Species.UNASSIGNED
	var peer := multiplayer.multiplayer_peer
	if peer is ENetMultiplayerPeer:
		peer.close()
	multiplayer.multiplayer_peer = null
	_lobby = null
	_session = null
	lobby_players = []
	lobby_meta = {}
	seats = []
	last_public = {}
	last_private = {}


func end_session(reason := "") -> void:
	# 结束联机并让界面回到主菜单;reason 非空时主菜单会弹出说明(主动离开传空串)
	leave()
	left_lobby.emit(reason)


func _create_server(preferred_port: int) -> Dictionary:
	# preferred_port > 0 时优先绑定它(测试隔离用),失败再走默认端口段
	var candidates: Array[int] = []
	if preferred_port > 0:
		candidates.append(preferred_port)
	for i in Protocol.GAME_PORT_ATTEMPTS:
		candidates.append(Protocol.GAME_PORT + i)
	var last_err := ERR_CANT_CREATE
	for port in candidates:
		var peer := ENetMultiplayerPeer.new()
		last_err = peer.create_server(port, Protocol.MAX_TRANSPORT_CLIENTS)
		if last_err == OK:
			return {"error": OK, "peer": peer, "port": port}
	return {"error": last_err}


func _room_announcement() -> Dictionary:
	var cap := max_players()
	var seated := _lobby.size() if _lobby != null else 0
	var legacy_max := mini(cap, Protocol.LEGACY_MAX_PLAYERS)
	return {
		"id": _room_id,
		"room": _room_name,
		"host": player_name,
		# 旧字段压在已发布的 v3 客户端接受的范围里(上限 4):旧玩家也看得到德州房间、能从房主更新;
		# 真实人数与玩法上限在 v4 字段 seated/cap 里
		"players": mini(seated, legacy_max),
		"max": legacy_max,
		"seated": seated,
		"cap": cap,
		"mode": game_mode,
		"playing": in_game,
		"version": Protocol.VERSION,
		"port": _port,
		"open": _lobby != null and seated < cap and (not in_game or _accepting_late_join()),
		"build": BuildInfo.build(),
		"ver": BuildInfo.version(),
		"update": Updater.is_serving(),   # 能从这个房主这里下载他正在运行的版本
		"plat": BuildInfo.platform(),     # 更新包按平台分:只有同平台的玩家能从这里更新
	}


func _accepting_late_join() -> bool:
	# 对局中还收不收新玩家(规格 §3.3):德州现金局在会话没散局、没结算时收,骗子酒馆永远不收
	return GameMode.allows_late_join(game_mode) and in_game and _session != null and _session.accepts_late_join()


# —— 连接生命周期 ——

func _on_connected_to_host() -> void:
	if _joining:
		_shorten_peer_timeout(HOST_ID)
		_send_to(HOST_ID, "rpc_join_request", [player_name, Protocol.VERSION])


func _on_peer_connected(id: int) -> void:
	if is_host and _session_active:
		_shorten_peer_timeout(id)


func _shorten_peer_timeout(id: int) -> void:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null:
		return
	var packet_peer := peer.get_peer(id)
	if packet_peer != null:
		packet_peer.set_timeout(
			Protocol.PEER_TIMEOUT_LIMIT, Protocol.PEER_TIMEOUT_MIN_MS, Protocol.PEER_TIMEOUT_MAX_MS
		)


func _on_connection_failed() -> void:
	if _joining:
		_fail_join("连接失败:请确认房主 IP、端口与防火墙设置")


func _on_join_timeout() -> void:
	if not _joining:
		return
	if _awaiting_game:
		_fail_join("房主没有发来牌局信息")
	else:
		_fail_join("连接超时:%d 秒内没有收到房主响应" % int(Protocol.JOIN_TIMEOUT))


func _on_host_disconnected() -> void:
	if not _session_active:
		return
	if _joining:
		_fail_join("房主断开了连接")
	else:
		end_session("与房主断开连接,房间已解散")


func _on_peer_disconnected(id: int) -> void:
	if not is_host or not _session_active:
		return
	if in_game and _session != null:
		var events := _session.on_disconnect(id)
		if not events.is_empty():
			_after_action(events)
	_species_asked_at.erase(id)
	_quip_gate.forget(id)
	if _lobby.remove(id):
		_broadcast_lobby()


func _fail_join(reason: String) -> void:
	leave()
	join_failed.emit(reason)


# —— 加入握手 ——

@rpc("any_peer", "call_remote", "reliable")
func rpc_join_request(pname: String, version: int) -> void:
	# 参数与 @rpc 模式冻结(规格 §3.3):旧版本靠它收到「版本不匹配」。处理放在可离线测试的函数里
	_handle_join_request(multiplayer.get_remote_sender_id(), pname, version)


func _handle_join_request(id: int, pname: String, version: int) -> void:
	if not is_host or not _session_active or _lobby.has(id):
		return
	var deny := _join_denial(id, pname, version)
	if deny != "":
		_send_to(id, "rpc_join_denied", [deny])
		_disconnect_peer_later(id)
		return
	_lobby.add_member(id, pname)
	# 对局中入座(德州)先让会话收人:名单放行而会话拒收(同一 peer id 本手里刚离开、桌上没座)时按拒绝处理,
	# 否则他会被告知开局却不在会话里(收不到私有视图、意图全被拒)
	var late := _session != null and _accepting_late_join()
	var events: Array = _session.add_player(id, _lobby.names()[id]) if late else []
	if late and events.is_empty():
		_lobby.remove(id)
		_send_to(id, "rpc_join_denied", [LATE_SEAT_REASON])
		_disconnect_peer_later(id)
		return
	# 获准里带上玩法:客户端一进等待厅就要按玩法摆桌,带 meta 的名单比它晚到。
	# 对局中入座的人先不进等待厅:客户端保持「加入中」,等随后发来的牌局信息
	_send_to(id, "rpc_join_accepted", [{"in_game": in_game, "mode": game_mode}])
	if late:
		_seat_late_joiner(id, events)
	_broadcast_lobby()


func _seat_late_joiner(id: int, events: Array) -> void:
	# 中途加入的顺序(规格 §4.2):只对他发牌局信息(当前桌上有酒客的人,不含他:新人要下一手才登场)→ 入座事件与视图全员同步。
	# 他已在名单里,所以加入事件、公共视图与之后的每一批他都收得到
	_send_to(id, "rpc_game_started", [_seat_entries(_session.seats_with_patrons()), {"mode": game_mode, "late": true}])
	_after_action(events)


func _join_denial(id: int, pname: String, version: int) -> String:
	# 昵称来自不可信的对端:超长的在做任何逐字处理前就拒绝;黑名单在sanitize之后检查
	if pname.length() > Protocol.MAX_RAW_NAME_LENGTH:
		push_warning("拒绝连接 %d 的加入请求:昵称长度 %d 超过上限 %d"
			% [id, pname.length(), Protocol.MAX_RAW_NAME_LENGTH])
		return "昵称过长"
	var sanitized := Protocol.sanitize_name(pname)
	var validation := Protocol.validate_name(sanitized)
	if not validation["ok"]:
		return validation["error"]
	return _lobby.check_join(version, in_game, game_mode, _accepting_late_join())


@rpc("authority", "call_remote", "reliable")
func rpc_join_denied(reason: String) -> void:
	if _joining:
		_fail_join(reason)


@rpc("authority", "call_remote", "reliable")
func rpc_join_accepted(info: Dictionary) -> void:
	# info = {"in_game": bool, "mode": String}。玩法在发 joined_lobby 之前写好:等待厅一建起来就按它摆桌。
	# 对局中入座:不进等待厅,「加入中」与加入计时都保持,直到 rpc_game_started 到达;
	# 超时按「房主没有发来牌局信息」失败
	if not _joining:
		return
	_take_mode(info.get("mode"))
	# 握手通过后再报想要的形象(规格 ② §3.4):握手消息的签名与编号不变,旧版本照样收到「版本不匹配」。
	# 对局中入座的人也报:他要等下一手才登场,房主在那之前给他分好
	_send_to(HOST_ID, "rpc_lobby_species", [player_species])
	var late = info.get("in_game", false)
	if late is bool and late:
		_awaiting_game = true
		return
	_finish_join()
	joined_lobby.emit()


func _finish_join() -> void:
	_joining = false
	_awaiting_game = false
	_join_timer.stop()


func _take_mode(mode: Variant) -> void:
	# 客户端的玩法来自房主(获准、等待厅 meta、开局 info),是不可信输入:
	# 认识的才写入,不认识的忽略并保留当前玩法
	if GameMode.is_valid(mode):
		game_mode = mode


# —— 等待厅 ——

func set_ready(ready: bool) -> void:
	if not is_host and _session_active and not _joining:
		_send_to(HOST_ID, "rpc_lobby_ready", [ready])


@rpc("any_peer", "call_remote", "reliable")
func rpc_lobby_ready(ready: bool) -> void:
	if not is_host or in_game:
		return
	if _lobby.set_ready(multiplayer.get_remote_sender_id(), ready):
		_broadcast_lobby()


func kick(id: int) -> void:
	if not is_host or in_game or not _lobby.remove(id):
		return
	_send_to(id, "rpc_kicked")
	_disconnect_peer_later(id)
	_broadcast_lobby()


@rpc("authority", "call_remote", "reliable")
func rpc_kicked() -> void:
	if _session_active:
		end_session("你被房主请出了房间")


func request_species(index: int) -> void:
	# 等待厅换形象:房主直接改名单(变了就广播,没变也在本机刷新一次,界面据此结算);客人发给房主,
	# 结果看随后的名单(被拒时房主也会单独回一份)
	if not _session_active or _joining or in_game:
		return
	if is_host:
		if _lobby.request_species(HOST_ID, index):
			player_species = _lobby.species_of(HOST_ID)
			_broadcast_lobby()
		else:
			_apply_lobby(_lobby.view(), _lobby_meta())
	else:
		_species_wanted = index
		_send_to(HOST_ID, "rpc_lobby_species", [index])


@rpc("any_peer", "call_remote", "reliable")
func rpc_lobby_species(index: int) -> void:
	# 方法名排在 rpc_join_* 之后:握手消息的 RPC 编号不变。处理放在可离线测试的函数里
	_handle_species_request(multiplayer.get_remote_sender_id(), index)


func _handle_species_request(id: int, index: int) -> void:
	# 来自不可信的对端:只认等待厅成员;参数类型由 RPC 签名把关,越界下标交给 LobbyModel 当「没有偏好」处理。
	# 开局后只收对局中入座者的第一次(还没有形象、酒客要等下一手才登场),换形象只在等待厅里
	if not is_host or not _session_active or _lobby == null or not _lobby.has(id):
		return
	if in_game and _lobby.species_of(id) != Species.UNASSIGNED:
		return
	if not _species_cooling_down(id) and _lobby.request_species(id, index):
		_broadcast_lobby()
	else:
		# 被拒(被占、没变、冷却中)也回一份名单:请求者据此结算
		_send_to(id, "rpc_lobby_state", [_lobby.view(), _lobby_meta()])


func _species_cooling_down(id: int) -> bool:
	var now := Time.get_ticks_msec()
	var last: int = _species_asked_at.get(id, -SPECIES_COOLDOWN_MS)
	if now - last < SPECIES_COOLDOWN_MS:
		return true
	_species_asked_at[id] = now
	return false


func can_start() -> bool:
	return is_host and not in_game and _lobby != null and _lobby.can_start(GameMode.min_players(game_mode))


func _lobby_meta() -> Dictionary:
	return {
		"room": _room_name,
		"host": player_name,
		"addresses": Lan.local_private_ipv4s(),
		"port": _port,
		"mode": game_mode,
	}


func _broadcast_lobby() -> void:
	var players := _lobby.view()
	var meta := _lobby_meta()
	_apply_lobby(players, meta)
	_send_to_members("rpc_lobby_state", [players, meta])


@rpc("authority", "call_remote", "reliable")
func rpc_lobby_state(players: Array, meta: Dictionary) -> void:
	_apply_lobby(players, meta)


func _apply_lobby(players: Array, meta: Dictionary) -> void:
	_take_mode(meta.get("mode"))
	lobby_players = players
	lobby_meta = meta
	_take_granted_species(players)
	lobby_updated.emit(players)


func _take_granted_species(players: Array) -> void:
	# 客户端:房主批下了等着的换形象请求,它就是之后再加入时报的形象
	if _species_wanted == Species.UNASSIGNED or is_host:
		return
	for p in players:
		if p is Dictionary and p.get("pid") == my_pid() and Species.sanitize(p.get("species")) == _species_wanted:
			player_species = _species_wanted
			_species_wanted = Species.UNASSIGNED
			return


func species_of(pid: int) -> int:
	# 某位玩家的形象(房主分配):先查本局座位表,再查等待厅名单(对局中入座者的形象随名单下发);
	# 都没有或数据不对时返回 UNASSIGNED,由 TableWorld 在对局里按座位顺序本地补齐
	for list in [seats, lobby_players]:
		for p in list:
			if p is Dictionary and p.get("pid") == pid and Species.is_valid(p.get("species")):
				return p["species"]
	return Species.UNASSIGNED


func patron_entries(pids: Array) -> Array:
	# 喂给 TableWorld.arrange 的 [{pid, species}](德州牌桌按 hand_started / 公共视图的 seats 排座时用)
	return pids.map(func(pid) -> Dictionary: return {"pid": pid, "species": species_of(pid)})


func _disconnect_peer_later(id: int) -> void:
	# 给对方留时间收到拒绝/踢出原因;对方通常会先自行断开
	await get_tree().create_timer(DISCONNECT_GRACE).timeout
	var peer := multiplayer.multiplayer_peer
	if is_host and peer is ENetMultiplayerPeer and multiplayer.get_peers().has(id):
		peer.disconnect_peer(id)


func _send_to_members(method: StringName, args: Array) -> void:
	# 只发给已完成握手的成员;握手中/被拒绝的连接不在名单里,正在断开的由 _send_to 跳过
	for id in _lobby.seat_order():
		if id != HOST_ID:
			_send_to(id, method, args)


func _send_to(id: int, method: StringName, args: Array = []) -> void:
	# 点对点 RPC 的唯一出口:只发给连接仍然有效的对端
	if _is_connected(id):
		callv("rpc_id", [id, method] + args)


func _is_connected(id: int) -> bool:
	var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if peer == null or not multiplayer.get_peers().has(id):
		return false
	var packet_peer := peer.get_peer(id)
	return packet_peer != null and packet_peer.get_state() == ENetPacketPeer.STATE_CONNECTED


# —— 开局与状态同步 ——

func start_game() -> void:
	if not can_start():
		return
	in_game = true
	last_public = {}
	last_private = {}
	# 形象请求没到的人在这里兜底分配:座位表带上房主分配的形象,各端只渲染它(名单不另发,回等待厅时再广播)
	_lobby.assign_unassigned()
	var order := _lobby.seat_order()
	seats = _seat_entries(order, _lobby.names())
	_session = _new_session(game_mode)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var events := _session.start(order, _lobby.names(), rng)
	_send_to_members("rpc_game_started", [seats, {"mode": game_mode, "late": false}])
	game_started.emit(seats)
	# 各端进入牌桌先播开场运镜,第一局的发牌演出排在它后面
	_anim_left = Pacing.INTRO
	_after_action(events)


static func _new_session(mode: String) -> GameSession:
	# 按玩法建会话:德州(长牌 / 短牌)、炸弹猫、吹牛骰子、斗地主,其余是骗子酒馆
	if GameMode.is_poker(mode):
		return PokerSession.new(mode)
	if GameMode.is_bomb_cat(mode):
		return BombCatSession.new()
	if GameMode.is_liars_dice(mode):
		return LiarsDiceSession.new()
	if GameMode.is_dou_dizhu(mode):
		return DouDizhuSession.new()
	return LiarsSession.new()


func _seat_entries(order: Array, names := {}) -> Array:
	# 座位表 [{pid, name, species}]:开局时名字来自等待厅,之后(中途加入的引导)来自会话;形象来自等待厅名单
	# (已离开名单的人是 UNASSIGNED,TableWorld 在对局里本地补齐)
	var entries := []
	for pid in order:
		entries.append({"pid": pid, "name": names[pid] if names.has(pid) else _session.name_of(pid),
			"species": _lobby.species_of(pid)})
	return entries


@rpc("authority", "call_remote", "reliable")
func rpc_game_started(p_seats: Array, info: Dictionary) -> void:
	# info = {"mode", "late"}:发出 game_started 之前玩法已设好。对局中入座的人到这里才算加入完成,
	# 直接进牌桌、不经过等待厅;房主总是先发获准(可靠有序),没获准就到的牌局信息不理
	if _joining and not _awaiting_game:
		return
	_take_mode(info.get("mode"))
	if _joining:
		_finish_join()
	in_game = true
	seats = p_seats
	last_public = {}
	last_private = {}
	game_started.emit(seats)


func _sync_all() -> void:
	var pub: Dictionary = _session.public_view(_turn_time_left())
	_apply_public(pub)
	_send_to_members("rpc_state_public", [pub])
	for pid in _session.viewers():
		var priv: Dictionary = _session.private_view(pid)
		if pid == HOST_ID:
			_apply_private(priv)
		else:
			_send_to(pid, "rpc_state_private", [priv])


@rpc("authority", "call_remote", "reliable")
func rpc_state_public(state: Dictionary) -> void:
	_apply_public(state)


@rpc("authority", "call_remote", "reliable")
func rpc_state_private(state: Dictionary) -> void:
	_apply_private(state)


func _apply_public(state: Dictionary) -> void:
	last_public = state
	state_public_updated.emit(state)


func _apply_private(state: Dictionary) -> void:
	last_private = state
	state_private_updated.emit(state)


# —— 意图(骗子酒馆) ——

func submit_play(indices: Array) -> void:
	if not in_game:
		return
	if is_host:
		_handle_intent(HOST_ID, {"kind": "play", "indices": indices})
	else:
		_send_to(HOST_ID, "rpc_intent_play", [indices])


func submit_challenge() -> void:
	if not in_game:
		return
	if is_host:
		_handle_intent(HOST_ID, {"kind": "challenge"})
	else:
		_send_to(HOST_ID, "rpc_intent_challenge")


func max_players() -> int:
	# 当前玩法的人数上限
	return GameMode.max_players(game_mode)


@rpc("any_peer", "call_remote", "reliable")
func rpc_intent_play(indices: Array) -> void:
	if is_host:
		_handle_intent(multiplayer.get_remote_sender_id(), {"kind": "play", "indices": indices})


@rpc("any_peer", "call_remote", "reliable")
func rpc_intent_challenge() -> void:
	if is_host:
		_handle_intent(multiplayer.get_remote_sender_id(), {"kind": "challenge"})


# —— 意图(德州,规格 §4.3):fold / check / call / raise(amount 为「加注到」)/ allin 与 rebuy / spectate / sit_in ——

func submit_poker_action(action: String, amount := 0) -> void:
	if not in_game:
		return
	if is_host:
		_handle_poker_rpc(HOST_ID, action, amount)
	else:
		_send_to(HOST_ID, "rpc_poker_intent", [action, amount])


func request_rebuy() -> void:
	submit_poker_action(PokerRules.REBUY)


func request_spectate() -> void:
	submit_poker_action(PokerRules.SPECTATE)


func request_sit_in() -> void:
	# 挂机离座的人回到牌桌(规格 §2.8)
	submit_poker_action(PokerRules.SIT_IN)


func end_poker_session() -> void:
	# 仅房主:有进行中的手牌就打完这一手再结算(规格 §2.9);斗地主的「散局」也走这里(DouDizhuSession.request_end)。
	# 骗子酒馆、炸弹猫与已在散局的牌局没有事件
	if not is_host or not in_game or _session == null:
		return
	var events := _session.request_end()
	if not events.is_empty():
		_after_action(events)


@rpc("any_peer", "call_remote", "reliable")
func rpc_poker_intent(action, amount) -> void:
	# 参数不加类型(规格 §3.3):来自不可信对端,在 _handle_poker_rpc 里校验类型与范围。
	# 方法名排在 rpc_join_request 之后:握手消息的 RPC 编号不变
	if is_host:
		_handle_poker_rpc(multiplayer.get_remote_sender_id(), action, amount)


func _handle_poker_rpc(pid: int, action: Variant, amount: Variant) -> void:
	if not in_game or _session == null:
		return
	var error := "" if _lobby.has(pid) else "not_seated"
	if error == "":
		error = PokerSession.check_intent(action, amount)
	if error != "":
		_reject(pid, error)
		return
	_handle_intent(pid, {"kind": action, "amount": amount})


# —— 意图(字典式,炸弹猫、吹牛骰子与斗地主,设计稿 §2):{"kind": ..., ...},结构校验交给会话的 validate_intent ——
# 骗子酒馆与德州仍走各自的 RPC(行为不变);它们的会话不覆盖 validate_intent,这个入口一律拒绝(invalid_intent)

func submit_session_intent(intent: Dictionary) -> void:
	if not in_game:
		return
	if is_host:
		_handle_session_rpc(HOST_ID, intent)
	else:
		_send_to(HOST_ID, "rpc_session_intent", [intent])


@rpc("any_peer", "call_remote", "reliable")
func rpc_session_intent(intent) -> void:
	# 参数不加类型:来自不可信对端,在 _handle_session_rpc 里校验。
	# 方法名排在 rpc_join_request 之后(叫 rpc_bomb_cat_intent 会排到最前,挤动握手消息的编号)
	if is_host:
		_handle_session_rpc(multiplayer.get_remote_sender_id(), intent)


func _handle_session_rpc(pid: int, intent: Variant) -> void:
	if not in_game or _session == null:
		return
	var error := ""
	if not _lobby.has(pid):
		error = "not_seated"
	else:
		error = _session.validate_intent(intent)
	if error != "":
		_reject(pid, error)
		return
	_handle_intent(pid, intent)


func _handle_intent(pid: int, intent: Dictionary) -> void:
	if _session == null or not in_game:
		return
	var result: Dictionary = _session.handle_intent(pid, intent)
	if not result["ok"]:
		_reject(pid, result["error"])
		return
	_after_action(result["events"], result["turn_action"])


func _reject(pid: int, code: String) -> void:
	if pid == HOST_ID:
		intent_rejected.emit(code)
	else:
		_send_to(pid, "rpc_intent_rejected", [code])


# —— 每批事件之后:计时、下发、同步(规格 §4.2 的计时规则) ——

func _after_action(events: Array, turn_action := false) -> void:
	# 行动者那一端要先播完排队的演出才能出手(超时代打时预算也早已耗尽):之前的预算余量不再顺延,
	# 否则玩家出手越快,多给的时间越积越多。再领/观战/加入/离开/散局都不清零。
	# 先定计时再同步:公共视图里的 turn_time_left 要反映这一批之后的截止时间
	if turn_action:
		_anim_left = 0.0
	_anim_left = maxf(_anim_left, 0.0) + _session.estimate(events)
	if _session.is_over() or not _session.has_turn():
		_turn_timer.stop()
	else:
		# 交出回合的批次演完后给满回合时间;否则(旁人离开、再领)保留剩余时间,只补上本批演出
		_turn_timer.start(_session.turn_timer_after(events, _anim_left, _turn_time_left()))
	_schedule_hand_timer()
	game_events.emit(events)
	_send_to_members("rpc_game_events", [events])
	_sync_all()


func _schedule_hand_timer() -> void:
	# 德州 / 斗地主两手之间:演完这一批再停顿 hand_gap()(德州有输光者没做选择时更长)。
	# 已排期时只会提前(输光者选完了间隔变短),不会推迟到比原计划更晚
	if _session.is_over() or not _session.next_hand_ready():
		_hand_timer.stop()
		return
	var delay := _anim_left + _session.hand_gap()
	if not _hand_timer.is_stopped():
		delay = minf(delay, _hand_timer.time_left)
	_hand_timer.start(delay)


func _on_hand_timer() -> void:
	if in_game and _session != null and _session.next_hand_ready():
		# 对局中入座者在下一手登场:形象请求还没到的先兜底分好,名单随之下发
		if _lobby.assign_unassigned():
			_broadcast_lobby()
		_after_action(_session.start_next_hand())


func _turn_time_left() -> float:
	# 房主计时器剩余秒数;没在计时(未开局/两手之间/已结束)为 0
	if _turn_timer.is_stopped() or _session == null or not _session.has_turn():
		return 0.0
	return _turn_timer.time_left


@rpc("authority", "call_remote", "reliable")
func rpc_intent_rejected(code: String) -> void:
	intent_rejected.emit(code)


@rpc("authority", "call_remote", "reliable")
func rpc_game_events(events: Array) -> void:
	game_events.emit(events)


# —— 视线同步:不可靠有序、走独立通道,丢包由 GazeSync 的心跳与超时兜底 ——
# 方法名刻意排在 rpc_join_* 之后(rpc_lobby_species、rpc_poker_intent 同理):RPC 按方法名排序编号,
# 握手消息的编号不变,旧版本仍能收到"版本不匹配"的明确拒绝。对局中「本场成员」= 已完成握手的等待厅成员(含中途加入者)

func send_gaze(point: Vector3, neck: Vector3, active: bool) -> void:
	if not in_game or multiplayer.multiplayer_peer == null:
		return
	if is_host:
		_relay_gaze(HOST_ID, point, neck, active)
	else:
		_send_to(HOST_ID, "rpc_look", [point, neck, active])


@rpc("any_peer", "call_remote", "unreliable_ordered", Protocol.GAZE_CHANNEL)
func rpc_look(point: Vector3, neck: Vector3, active: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if not is_host or not in_game or _lobby == null or not _lobby.has(sender) or not GazeSync.is_valid(point, neck):
		return
	gaze_updated.emit(sender, point, neck, active)
	_relay_gaze(sender, point, neck, active)


func _relay_gaze(from_pid: int, point: Vector3, neck: Vector3, active: bool) -> void:
	# 转给除房主与发送者之外的成员;没连着的由 _send_to 跳过
	for id in _lobby.seat_order():
		if id != HOST_ID and id != from_pid:
			_send_to(id, "rpc_look_relay", [from_pid, point, neck, active])


@rpc("authority", "call_remote", "unreliable_ordered", Protocol.GAZE_CHANNEL)
func rpc_look_relay(pid: int, point: Vector3, neck: Vector3, active: bool) -> void:
	if in_game and GazeSync.is_valid(point, neck):
		gaze_updated.emit(pid, point, neck, active)


# —— 快捷对话:客户端 → 房主校验(对局中的成员、编号合法、限速)→ 发给所有成员(含说话人)。参数不加类型,函数体里校验 ——

func send_quip(index: int) -> void:
	if not in_game or multiplayer.multiplayer_peer == null:
		return
	if is_host:
		_handle_quip(HOST_ID, index)
	else:
		_send_to(HOST_ID, "rpc_quip", [index])


@rpc("any_peer", "call_remote", "reliable")
func rpc_quip(index) -> void:
	_handle_quip(multiplayer.get_remote_sender_id(), index)


func _handle_quip(pid: int, index: Variant) -> void:
	if not is_host or not in_game or _lobby == null or not _lobby.has(pid) or not Quips.is_valid(index):
		return
	if not _quip_gate.accept(pid, Time.get_ticks_msec()):
		return
	quip_shown.emit(pid, index)
	_send_to_members("rpc_quip_shown", [pid, index])


@rpc("authority", "call_remote", "reliable")
func rpc_quip_shown(pid, index) -> void:
	if in_game and pid is int and Quips.is_valid(index):
		quip_shown.emit(pid, index)


# —— 回合限时(仅房主):超时代打由会话决定(骗子酒馆出手牌第一张;德州能过牌就过牌,否则弃牌;
# 炸弹猫按步骤:结算反应窗口 / 随机塞回 / 随机给牌 / 直接摸牌;吹牛骰子按最小合法加注,加不上去就「开!」) ——

func _on_turn_timeout() -> void:
	if _session == null or not _session.has_turn():
		return
	var result: Dictionary = _session.on_turn_timeout()
	if result["ok"]:
		_after_action(result["events"], true)


# —— 结算后回到等待厅 ——

func request_rematch_lobby() -> void:
	if not is_host or not in_game or _session == null or not _session.is_over():
		return
	_session = null
	in_game = false
	_turn_timer.stop()
	_hand_timer.stop()
	_anim_left = 0.0
	_lobby.reset_ready()
	_send_to_members("rpc_returned_to_lobby", [])
	returned_to_lobby.emit()
	_broadcast_lobby()


@rpc("authority", "call_remote", "reliable")
func rpc_returned_to_lobby() -> void:
	in_game = false
	returned_to_lobby.emit()


func _make_timer(callback: Callable) -> Timer:
	var timer := Timer.new()
	timer.one_shot = true
	timer.timeout.connect(callback)
	add_child(timer)
	return timer
