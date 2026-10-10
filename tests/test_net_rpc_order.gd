extends GutTest
# 协议的完整 RPC 表(子项目② §3.6;现为 v7):Godot 按方法名排序给 RPC 编号。
# 自选形象新增的 rpc_lobby_species 排在 rpc_join_request 之后,v1 以来的握手前缀(下标 0–7)一个不动,
# 新旧版本互连时照样收到「版本不匹配」;握手前缀与参数的冻结另见 test_rpc_order。


const NETWORK_MANAGER := "res://src/net/network_manager.gd"
# v7 的完整列表(德州的 rpc_poker_intent + 自选形象的 rpc_lobby_species + 炸弹猫的字典意图 rpc_session_intent
# + 上游九宫格快捷对话的 rpc_quip / rpc_quip_shown);以后加 RPC 要升协议并改这里
const V7_RPCS := [
	"rpc_game_events", "rpc_game_started", "rpc_intent_challenge", "rpc_intent_play",
	"rpc_intent_rejected", "rpc_join_accepted", "rpc_join_denied", "rpc_join_request",
	"rpc_kicked", "rpc_lobby_ready", "rpc_lobby_species", "rpc_lobby_state", "rpc_look", "rpc_look_relay",
	"rpc_poker_intent", "rpc_quip", "rpc_quip_shown", "rpc_returned_to_lobby", "rpc_session_intent", "rpc_state_private", "rpc_state_public",
]
# v1 起的握手前缀(v4 的 eadc745 也是这 8 个排在最前)
const HANDSHAKE_PREFIX := [
	"rpc_game_events", "rpc_game_started", "rpc_intent_challenge", "rpc_intent_play",
	"rpc_intent_rejected", "rpc_join_accepted", "rpc_join_denied", "rpc_join_request",
]


func _script() -> Script:
	return load(NETWORK_MANAGER) as Script


func _sorted_names() -> Array:
	var names: Array = _script().get_rpc_config().keys().map(func(key) -> String: return String(key))
	names.sort()
	return names


func _args(method: String) -> Array:
	for info in _script().get_script_method_list():
		if info["name"] == method:
			return info["args"]
	return []


func test_sorted_rpc_table_is_the_frozen_v7_list():
	assert_eq(_sorted_names(), V7_RPCS)


func test_handshake_prefix_is_unchanged_up_to_the_join_request():
	var names := _sorted_names()
	var cut := names.find("rpc_join_request") + 1
	assert_eq(names.slice(0, cut), HANDSHAKE_PREFIX)


func test_lobby_species_is_a_reliable_intent_from_any_peer():
	var config: Dictionary = _script().get_rpc_config()["rpc_lobby_species"]
	assert_eq(config["rpc_mode"], MultiplayerAPI.RPC_MODE_ANY_PEER)
	assert_false(config["call_local"], "call_remote")
	assert_eq(config["transfer_mode"], MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	assert_eq(config.get("channel", 0), 0)
	assert_eq(_args("rpc_lobby_species").map(func(arg: Dictionary) -> int: return arg["type"]), [TYPE_INT],
		"rpc_lobby_species(index: int):类型由签名把关")


func test_session_intent_is_a_reliable_untyped_intent_from_any_peer():
	# 炸弹猫的意图入口:参数不加类型(来自不可信对端,房主在 _handle_session_rpc 里校验是不是字典)
	var config: Dictionary = _script().get_rpc_config()["rpc_session_intent"]
	assert_eq(config["rpc_mode"], MultiplayerAPI.RPC_MODE_ANY_PEER)
	assert_false(config["call_local"], "call_remote")
	assert_eq(config["transfer_mode"], MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	assert_eq(config.get("channel", 0), 0)
	assert_eq(_args("rpc_session_intent").map(func(arg: Dictionary) -> int: return arg["type"]), [TYPE_NIL])


func test_join_request_still_takes_two_arguments():
	assert_eq(_args("rpc_join_request").size(), 2, "rpc_join_request(pname, version)")


func test_protocol_is_v10():
	# 德州单独随 0.7.0 用 v5 发布了;自选形象、丢番茄与快捷语、炸弹猫随 0.8.0 升到 v6;上游的九宫格快捷对话
	# (rpc_quip / rpc_quip_shown)也用了 v6,两个 v6 的 RPC 表不同。合在一起升 v7(握手仍能告诉旧客户端「版本不匹配」)
	# 再之后德州加了「开始下一手」与牌局记录(意图 next、事件 next_ready / hand_record),升到 v8(0.9.1);
	# 新玩法吹牛骰子与斗地主的 id 旧版本不认识(RPC 表没变,吹牛骰子走现有的 rpc_session_intent),升到 v9;
	# 新形象熊猫、企鹅(物种下标 8、9)v9 客户端不认识,升到 v10
	assert_eq(Protocol.VERSION, 10)
