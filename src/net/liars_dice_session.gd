class_name LiarsDiceSession
extends GameSession
# 吹牛骰子会话(设计稿 §2):持有 LiarsDiceState 与名字表,把网络意图校验后分派给引擎。
# 意图字典(来自不可信对端,逐字段校验类型,不认识的键一律拒绝):
#   {"kind": "bid", "count": int, "face": int}    喊「count 个 face」,face ∈ 2..6
#   {"kind": "challenge"}                         「开!」质疑上一口
# 计时语义:只有一种等待——当前玩家喊价或「开!」,时长 Protocol.TURN_TIMEOUT,从本批演出播完算起
# (每口喊价、每轮开始都给满;开盅、丢骰子、重摇的演出都算在 pending 里)。
# 到点调 on_turn_timeout:能加注就按最小合法加注,否则「开!」。不收中途加入;断线 = 出局,作废本轮全员重摇。


const KINDS := ["bid", "challenge"]
const INTENT_KEYS := {"bid": ["kind", "count", "face"], "challenge": ["kind"]}

var _state: LiarsDiceState = null
var _names := {}


func start(seat_order: Array, names: Dictionary, rng: RandomNumberGenerator) -> Array:
	_names = names.duplicate()
	_state = LiarsDiceState.new()
	var result := _state.start(seat_order, rng)
	return result["events"]


func state() -> LiarsDiceState:
	# 测试与机器人读局面用(只读)
	return _state


static func check_intent(intent: Variant) -> String:
	# 结构校验(不看局面):字典、kind 认识、没有多余的键、字段类型对。返回错误码,合法为 ""
	if not intent is Dictionary:
		return LiarsDiceState.ERR_INVALID_INTENT
	var kind: Variant = intent.get("kind")
	if not kind is String or not KINDS.has(kind):
		return LiarsDiceState.ERR_INVALID_INTENT
	for key in intent:
		if not INTENT_KEYS[kind].has(key):
			return LiarsDiceState.ERR_INVALID_INTENT
	if kind == "bid":
		if not intent.get("count") is int:
			return LiarsDiceState.ERR_INVALID_COUNT
		if not intent.get("face") is int:
			return LiarsDiceState.ERR_INVALID_FACE
	return ""


func validate_intent(intent: Variant) -> String:
	return check_intent(intent)


func handle_intent(pid: int, intent: Dictionary) -> Dictionary:
	if _state == null:
		return rejected(LiarsDiceState.ERR_MATCH_OVER)
	var error := check_intent(intent)
	if error != "":
		return rejected(error)
	if not _state.is_member(pid):
		return rejected(LiarsDiceState.ERR_NOT_SEATED)
	var result: Dictionary
	if intent["kind"] == "bid":
		result = _state.place_bid(pid, intent["count"], intent["face"])
	else:
		result = _state.challenge(pid)
	if not result["ok"]:
		return rejected(result["error"])
	return accepted(result["events"], true)


func on_disconnect(pid: int) -> Array:
	if _state == null:
		return []
	return _state.eliminate(pid)["events"]


func on_turn_timeout() -> Dictionary:
	if _state == null or _state.step == LiarsDiceState.Step.OVER:
		return rejected(LiarsDiceState.ERR_MATCH_OVER)
	var result := _state.timeout()
	if not result["ok"]:
		return rejected(result["error"])
	return accepted(result["events"], true)


func public_view(turn_time_left: float) -> Dictionary:
	return LiarsDiceViews.public_view(_state, _names, turn_time_left)


func private_view(pid: int) -> Dictionary:
	return LiarsDiceViews.private_view(_state, pid)


func viewers() -> Array:
	# 全座位(出局者也收:dice 为空、alive 为假,界面据此进观战)
	return _state.seat_order.duplicate() if _state != null else []


func is_over() -> bool:
	return _state == null or _state.step == LiarsDiceState.Step.OVER


func has_turn() -> bool:
	# 没结束就总有人在喊价
	return not is_over()


func estimate(events: Array) -> float:
	return LiarsDicePacing.estimate(events)


func turn_timer_after(events: Array, pending: float, time_left: float) -> float:
	# pending = 含本批在内客户端还要演多久;time_left = 计时器当前剩余(到点触发时为 0)。
	# 换人(喊价之后、新一轮)给满;其他(不该发生:引擎每批都会换人)保留剩余、只补上本批演出
	if LiarsDicePacing.starts_turn(events) or time_left <= 0.0:
		return pending + Protocol.TURN_TIMEOUT
	return time_left + estimate(events)


func seats_with_patrons() -> Array:
	return _state.seat_order.duplicate() if _state != null else []


func name_of(pid: int) -> String:
	return _names.get(pid, str(pid))
