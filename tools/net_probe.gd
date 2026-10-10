extends SceneTree
# 无界面联机探针:直接驱动 Net/Discovery 跑完整局,用于验证网络层(不加载 3D 表现)。
# 用法(在仓库根目录):
#   godot --headless --path . -s tools/net_probe.gd -- --role=host --players=3
#   godot --headless --path . -s tools/net_probe.gd -- --role=client --addr=127.0.0.1
#   godot --headless --path . -s tools/net_probe.gd -- --role=client --discover
#   任一角色都可加 --species=物种id(fox / bear / … / panda / penguin):建房、加入时报的形象
# 退出码:0 = 收到 match_over;1 = 超时或出错。


const TIMEOUT := 90.0
const CHALLENGE_CHANCE := 0.35

var net: Node
var discovery: Node
var opts := {}
var stats := {"played": 0, "reveal": 0, "gunshot": 0, "hit": 0, "round_started": 0, "eliminated": 0}
var acting := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	# autoload 在第一帧才进入场景树,之前访问 multiplayer 为空
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	net = root.get_node("Net")
	discovery = root.get_node("Discovery")
	net.joined_lobby.connect(_on_joined)
	net.join_failed.connect(_fail.bind("join_failed"))
	net.left_lobby.connect(_fail.bind("left_lobby"))
	net.lobby_updated.connect(_on_lobby)
	net.state_public_updated.connect(_on_public)
	net.game_events.connect(_on_events)
	net.intent_rejected.connect(func(code): _log("rejected %s" % code))
	create_timer(TIMEOUT).timeout.connect(_fail.bind("timeout"))
	var role: String = opts.get("role", "host")
	if role == "host":
		var err: Error = net.host_game("房主", "探针房间", 0, GameMode.DEFAULT, _species())
		_log("host_game -> %s" % error_string(err))
		if err != OK:
			quit(1)
	elif opts.has("discover"):
		discovery.rooms_updated.connect(_on_rooms)
		_log("listening on discovery port %d" % [discovery.listen_port() if discovery.start_listening() else -1])
	else:
		net.join_game(opts.get("name", "客%d" % OS.get_process_id()), opts.get("addr", "127.0.0.1"), _species())


func _on_rooms(rooms: Array) -> void:
	if rooms.is_empty() or net.player_name != "":
		return
	var room: Dictionary = rooms[0]
	_log("discovered room '%s' at %s:%d" % [room["room"], room["ip"], room["port"]])
	discovery.stop_listening()
	net.join_game("发现客%d" % OS.get_process_id(), Protocol.format_address(room["ip"], room["port"]), _species())


func _species() -> int:
	return Species.index_of(opts.get("species", ""))


func _on_joined() -> void:
	_log("joined lobby as pid %d (host=%s)" % [net.my_pid(), net.is_host])
	if not net.is_host:
		net.set_ready(true)


func _on_lobby(players: Array) -> void:
	_log("lobby: %s" % [players.map(func(p): return "%s%s(%s)" % [p["name"], "✓" if p["ready"] else "…",
		Species.IDS[p["species"]] if Species.is_valid(p.get("species")) else "-"])])
	var want := int(opts.get("players", "2"))
	if net.is_host and players.size() >= want and net.can_start():
		_log("starting game")
		net.start_game()


func _on_public(state: Dictionary) -> void:
	if state["phase"] != GameState.Phase.PLAYING or state["current_pid"] != net.my_pid() or acting:
		return
	acting = true
	await create_timer(float(opts.get("think", "0.05"))).timeout
	acting = false
	var hand: Array = net.last_private.get("hand", [])
	if not state["last_play"].is_empty() and (randf() < CHALLENGE_CHANCE or hand.is_empty()):
		net.submit_challenge()
		return
	var count := randi_range(1, mini(3, hand.size()))
	var indices := range(hand.size())
	indices.shuffle()
	net.submit_play(indices.slice(0, count))


func _on_events(events: Array) -> void:
	for ev in events:
		if stats.has(ev["type"]):
			stats[ev["type"]] += 1
		if ev["type"] == "gunshot" and ev["hit"]:
			stats["hit"] += 1
		if ev["type"] == "match_over":
			_log("MATCH_OVER winner=%s stats=%s" % [ev["winner"], stats])
			await create_timer(1.5).timeout
			quit(0)


func _fail(reason: String, detail = "") -> void:
	_log("FAIL %s %s" % [reason, detail])
	quit(1)


func _log(text: String) -> void:
	print("[%s %d] %s" % [opts.get("role", "host"), OS.get_process_id(), text])
