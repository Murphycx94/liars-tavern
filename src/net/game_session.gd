class_name GameSession
extends RefCounted
# 房主端会话的共同接口(规格 §4.2):NetworkManager 只管连接、等待厅、RPC 收发与计时器,
# 玩法逻辑在会话对象里。LiarsSession / PokerSession 覆盖这些方法;这里的默认值是「没有下一手、不收新人」。
# 意图字典:骗子酒馆 {"kind": "play", "indices": [...]} / {"kind": "challenge"};德州 {"kind": action, "amount": int};
# 炸弹猫见 BombCatSession(play / nope / draw / reinsert / give);吹牛骰子见 LiarsDiceSession(bid / challenge)。
# 炸弹猫起的玩法都走字典意图入口 rpc_session_intent:会话覆盖 validate_intent 做结构校验,其余玩法一律拒绝。


func start(_seat_order: Array, _names: Dictionary, _rng: RandomNumberGenerator) -> Array:
	# 开局事件(德州直接开第一手)
	return []


func validate_intent(_intent: Variant) -> String:
	# rpc_session_intent 的结构校验(来自不可信对端,不看局面):合法返回 "",否则错误码。
	# 骗子酒馆与德州走各自的 RPC,不收字典意图
	return "invalid_intent"


func handle_intent(_pid: int, _intent: Dictionary) -> Dictionary:
	# {"ok", "error"?, "events"?, "turn_action": bool};turn_action 为真 = 当前行动者消耗回合的动作
	return rejected("invalid_action")


func on_disconnect(_pid: int) -> Array:
	# 不在会话里的 pid 返回 []
	return []


func on_turn_timeout() -> Dictionary:
	return rejected("no_hand")


func public_view(_turn_time_left: float) -> Dictionary:
	return {}


func private_view(_pid: int) -> Dictionary:
	return {}


func viewers() -> Array:
	# 要收私有视图的 pid
	return []


func is_over() -> bool:
	return true


func is_ending() -> bool:
	return false


func has_turn() -> bool:
	# 当前有人在计时行动
	return false


func estimate(_events: Array) -> float:
	return 0.0


func turn_timer_after(_events: Array, pending: float, _time_left: float) -> float:
	return pending + Protocol.TURN_TIMEOUT


func accepts_late_join() -> bool:
	return false


func add_player(_pid: int, _name: String) -> Array:
	return []


func next_hand_ready() -> bool:
	return false


func hand_gap() -> float:
	return 0.0


func start_next_hand() -> Array:
	return []


func request_end() -> Array:
	return []


func seats_with_patrons() -> Array:
	# 当前桌上有酒客的 pid(中途加入者的 rpc_game_started 用)
	return []


func name_of(pid: int) -> String:
	return str(pid)


static func accepted(events: Array, turn_action: bool) -> Dictionary:
	return {"ok": true, "events": events, "turn_action": turn_action}


static func rejected(error: String) -> Dictionary:
	return {"ok": false, "error": error, "turn_action": false}
