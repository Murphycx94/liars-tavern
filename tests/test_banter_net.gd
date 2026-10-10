extends GutTest
# 丢番茄与快捷语的网络层(规格 §3、§7,离线 NetworkManager + Banter 子节点):房主校验发送者、目标、编号与冷却,
# 合法的向全员(含房主本机)广播且种子一致;不合法的静默丢弃。RPC 都在 Banter 上,NetworkManager 的表不变。


const HOST := LobbyModel.HOST_ID
const CROC := 7


class StubNet:
	extends "res://src/net/network_manager.gd"
	var late := false

	func _send_to(_id: int, _method: StringName, _args: Array = []) -> void:
		pass

	func _accepting_late_join() -> bool:
		return late


class StubBanter:
	extends "res://src/net/banter_net.gd"
	var sent: Array = []
	var clock := 100000

	func _init() -> void:
		now_ms = func() -> int: return clock

	func _send_to(id: int, method: StringName, args: Array = []) -> void:
		sent.append([id, String(method), args])


var net: StubNet
var banter: StubBanter
var heard: Array = []   # 本机收到的 [信号, 参数...]


func before_each():
	net = StubNet.new()
	add_child_autofree(net)
	# 换上记录发送的 Banter(名字仍是 Banter:各端路径一致)
	var original: Node = net.get_node("Banter")
	net.remove_child(original)
	original.free()
	banter = StubBanter.new()
	banter.name = "Banter"
	net.add_child(banter)
	net.banter = banter
	heard = []
	banter.tomato_thrown.connect(func(a, b, c): heard.append(["tomato", a, b, c]))
	banter.said.connect(func(a, b): heard.append(["said", a, b]))


func after_each():
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _host(guests := [10, 11], assign := true) -> void:
	net._open_room("房主", "房间", Protocol.GAME_PORT, GameMode.LIARS, CROC)
	for id in guests:
		net._handle_join_request(id, "客%d" % id, Protocol.VERSION)
		if assign:
			net._species_asked_at.erase(id)
			net._handle_species_request(id, 0)
	banter.sent = []


func _sent(method: String) -> Array:
	return banter.sent.filter(func(e: Array) -> bool: return e[1] == method)


func _advance(seconds: float) -> void:
	banter.clock += int(seconds * 1000.0)


# —— 节点与协议 ——

func test_banter_lives_at_a_fixed_child_path_of_the_network_manager():
	var fresh := StubNet.new()
	add_child_autofree(fresh)
	var child := fresh.get_node_or_null("Banter")
	assert_not_null(child)
	assert_true(child is Banter)
	assert_eq(fresh.banter, child)


func test_rpc_table_is_four_reliable_methods():
	var config: Dictionary = (load("res://src/net/banter_net.gd") as Script).get_rpc_config()
	var names: Array = config.keys().map(func(k) -> String: return String(k))
	names.sort()
	assert_eq(names, ["rpc_said", "rpc_say", "rpc_tomato", "rpc_tomato_thrown"])
	for name in ["rpc_say", "rpc_tomato"]:
		assert_eq(config[name]["rpc_mode"], MultiplayerAPI.RPC_MODE_ANY_PEER, name)
	for name in ["rpc_said", "rpc_tomato_thrown"]:
		assert_eq(config[name]["rpc_mode"], MultiplayerAPI.RPC_MODE_AUTHORITY, name)
	for name in names:
		assert_eq(config[name]["transfer_mode"], MultiplayerPeer.TRANSFER_MODE_RELIABLE, name)
		assert_false(config[name]["call_local"], name)


func test_protocol_number_is_v10():
	# 德州单独随 0.7.0 用 v5 发布;丢番茄、快捷语、自选形象、炸弹猫随 0.8.0 升到 v6;
	# 上游的九宫格快捷对话也叫 v6 但 RPC 表不同,两边合并后升到 v7,两种 v6 都不能同桌
	# 再之后德州加了「开始下一手」与牌局记录(意图 next、事件 next_ready / hand_record),升到 v8(0.9.1);
	# 新玩法吹牛骰子与斗地主的 id 旧版本不认识(RPC 表没变,吹牛骰子走现有的 rpc_session_intent),升到 v9;
	# 新形象熊猫、企鹅(物种下标 8、9)v9 客户端不认识,升到 v10
	assert_eq(Protocol.VERSION, 10)


# —— 丢番茄 ——

func test_valid_tomato_is_broadcast_to_everyone_with_one_seed():
	_host()
	banter._handle_tomato(10, 11)
	assert_eq(heard.size(), 1, "房主本机也收到")
	assert_eq(heard[0].slice(0, 3), ["tomato", 10, 11])
	var seed: int = heard[0][3]
	var out := _sent("rpc_tomato_thrown")
	assert_eq(out.map(func(e): return e[0]), [10, 11], "发给除房主外的每位成员(含丢的人自己)")
	for e in out:
		assert_eq(e[2], [10, 11, seed], "各端种子一致")


func test_host_can_throw_locally_through_the_same_validation():
	_host()
	assert_true(banter.throw_tomato(10))
	assert_eq(heard.size(), 1)
	assert_eq(heard[0].slice(0, 3), ["tomato", HOST, 10])
	assert_eq(_sent("rpc_tomato_thrown").size(), 2)


func test_tomato_at_self_is_rejected():
	_host()
	banter._handle_tomato(10, 10)
	assert_eq(heard, [])
	assert_eq(banter.sent, [])


func test_tomato_from_a_non_member_is_rejected():
	_host()
	banter._handle_tomato(99, 10)
	assert_eq(heard, [])


func test_tomato_at_a_non_member_or_bad_type_is_rejected():
	_host()
	for bad in [99, "10", 10.0, null, [10], -1]:
		banter._handle_tomato(11, bad)
	assert_eq(heard, [])
	assert_eq(banter.sent, [])


func test_tomato_at_someone_without_a_patron_is_rejected():
	# 等待厅里还没分到形象的人(握手后形象请求还在路上)桌上没有酒客
	_host([10, 11], false)
	banter._handle_tomato(HOST, 10)
	assert_eq(heard, [])


func test_tomato_cooldown_is_enforced_by_the_host():
	_host()
	banter._handle_tomato(10, 11)
	_advance(Banter.TOMATO_COOLDOWN - 0.1)
	banter._handle_tomato(10, HOST)
	assert_eq(heard.size(), 1, "冷却中被拒")
	_advance(0.2)
	banter._handle_tomato(10, HOST)
	assert_eq(heard.size(), 2)
	# 冷却按人算:别人不受影响
	banter._handle_tomato(11, 10)
	assert_eq(heard.size(), 3)


func test_local_cooldown_stops_sending_and_reports_time_left():
	_host()
	assert_true(banter.throw_tomato(10))
	assert_almost_eq(banter.tomato_cooldown_left(), Banter.TOMATO_COOLDOWN, 0.01)
	assert_false(banter.throw_tomato(11), "冷却期间不发消息")
	assert_eq(heard.size(), 1)
	_advance(1.0)
	assert_almost_eq(banter.tomato_cooldown_left(), Banter.TOMATO_COOLDOWN - 1.0, 0.01)
	_advance(Banter.TOMATO_COOLDOWN)
	assert_eq(banter.tomato_cooldown_left(), 0.0)
	assert_true(banter.throw_tomato(11))


func test_client_sends_intent_to_host_and_respects_local_cooldown():
	# 客户端:握手完成后在等待厅里
	net._session_active = true
	net._joining = false
	net.lobby_players = [{"pid": 1}, {"pid": 5}]
	assert_true(banter.throw_tomato(1))
	assert_eq(banter.sent, [[HOST, "rpc_tomato", [1]]])
	assert_false(banter.throw_tomato(1))
	assert_eq(banter.sent.size(), 1, "冷却期间不发")
	assert_eq(heard, [], "客户端本机不自己演,等房主广播")


func test_nothing_is_sent_outside_a_room():
	assert_false(banter.throw_tomato(1))
	assert_false(banter.say(0))
	assert_eq(banter.sent, [])


func test_spectators_and_the_dead_can_throw_in_game_and_dead_patrons_are_targets():
	_host([10, 11, 12])
	for id in [10, 11, 12]:
		net._lobby.set_ready(id, true)
	net.start_game()
	assert_true(net.in_game)
	banter.sent = []
	# 骗子酒馆的座位表里出局的人还在(酒客倒在桌上);任何成员都能丢
	assert_has(banter.patron_holders(), 12)
	banter._handle_tomato(12, 10)
	assert_eq(heard.size(), 1)


func test_poker_late_joiner_without_patron_is_not_a_target_but_can_throw():
	net._open_room("房主", "房间", Protocol.GAME_PORT, GameMode.HOLDEM, CROC)
	for id in [10, 11]:
		net._handle_join_request(id, "客%d" % id, Protocol.VERSION)
		net._lobby.set_ready(id, true)
	net.start_game()
	assert_true(net.in_game)
	net.late = true
	net._handle_join_request(20, "迟到", Protocol.VERSION)
	assert_false(banter.patron_holders().has(20), "新人等下一手才登场")
	banter._handle_tomato(HOST, 20)
	assert_eq(heard, [])
	banter._handle_tomato(20, 10)
	assert_eq(heard.size(), 1, "迟到的人(观战)也能丢")


func test_cooldowns_reset_when_returning_to_lobby_or_leaving():
	_host()
	banter._handle_tomato(10, 11)
	banter.throw_tomato(10)
	net.returned_to_lobby.emit()
	assert_eq(banter.tomato_cooldown_left(), 0.0)
	banter._handle_tomato(10, 11)
	assert_eq(heard.size(), 3, "回到等待厅后不再冷却")
	net.left_lobby.emit("")
	banter._handle_tomato(10, 11)
	assert_eq(heard.size(), 4)


# —— 快捷语 ——

func test_valid_phrase_is_broadcast():
	_host()
	banter._handle_say(11, 4)
	assert_eq(heard, [["said", 11, 4]])
	assert_eq(_sent("rpc_said").map(func(e): return e[2]), [[11, 4], [11, 4]])


func test_invalid_phrase_ids_are_rejected():
	_host()
	for bad in [-1, Banter.PHRASES.size(), 99, "1", 1.0, null]:
		banter._handle_say(10, bad)
	assert_eq(heard, [])
	assert_eq(banter.sent, [])


func test_phrase_from_non_member_is_rejected():
	_host()
	banter._handle_say(77, 0)
	assert_eq(heard, [])


func test_say_cooldown_is_enforced_by_the_host():
	_host()
	banter._handle_say(10, 0)
	_advance(Banter.SAY_COOLDOWN - 0.05)
	banter._handle_say(10, 1)
	assert_eq(heard.size(), 1)
	_advance(0.1)
	banter._handle_say(10, 1)
	assert_eq(heard.size(), 2)


func test_say_and_tomato_cooldowns_are_independent():
	_host()
	banter._handle_tomato(10, 11)
	banter._handle_say(10, 2)
	assert_eq(heard.size(), 2)


func test_host_says_locally():
	_host()
	assert_true(banter.say(3))
	assert_eq(heard, [["said", HOST, 3]])
	assert_false(banter.say(3), "本机冷却")
	assert_false(banter.say(42), "非法编号不发")


# —— 客户端收到广播 ——

func test_client_accepts_broadcasts_and_validates_types():
	net._session_active = true
	net._joining = false
	net.lobby_players = [{"pid": 1}, {"pid": 5}]
	banter.rpc_tomato_thrown(1, 5, 1234)
	banter.rpc_said(5, 2)
	assert_eq(heard, [["tomato", 1, 5, 1234], ["said", 5, 2]])
	heard = []
	banter.rpc_tomato_thrown("1", 5, 1234)
	banter.rpc_tomato_thrown(1, 5, 1.5)
	banter.rpc_said(5, 8)
	banter.rpc_said(5, "2")
	assert_eq(heard, [], "类型或范围不对的广播丢弃")


func test_client_ignores_broadcasts_before_joining():
	net._session_active = true
	net._joining = true
	banter.rpc_said(5, 2)
	assert_eq(heard, [])


func test_phrase_texts_are_short_and_exist():
	assert_eq(Banter.PHRASES.size(), 8)
	for text: String in Banter.PHRASES:
		assert_between(text.length(), 2, 8, text)
	assert_eq(Banter.phrase_text(0), Banter.PHRASES[0])
	assert_eq(Banter.phrase_text(99), "")
