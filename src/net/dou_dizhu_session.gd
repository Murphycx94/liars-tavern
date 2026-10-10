class_name DouDizhuSession
extends GameSession
# 斗地主会话(设计稿 §2):持有 DdzState 与名字表,把网络意图校验后分派给引擎,给结算补名字;
# 像德州一样连续打很多手(next_hand_ready / hand_gap / start_next_hand / request_end),用 NetworkManager 现有的
# 回合计时器与一手之间的计时器,不新增计时器。
# 意图字典(来自不可信对端,逐字段校验类型):
#   {"kind": "bid", "score": 0..3}       0 = 不叫
#   {"kind": "play", "cards": [手牌下标...]}   下标对应私有视图 cards(升序)
#   {"kind": "pass"}                      不出
#   {"kind": "trustee", "on": bool}       托管开 / 关(任何时候,不消耗回合)
# 计时语义:叫分 BID_TIMEOUT、出牌 Protocol.TURN_TIMEOUT,都从本批演出播完算起(换人的批次给满);
# 轮到托管中的人只等 DouDizhuPacing.TRUSTEE_DELAY 就由房主代打。到点调 on_turn_timeout(DdzState.timeout)。


const MAX_INTENT_KEYS := 2      # kind + 一个字段
const BID_TIMEOUT := 15.0
const KINDS := ["bid", "play", "pass", "trustee"]
const TURN_ACTION_KINDS := ["bid", "play", "pass"]   # 行动者要先看完排队演出才出手的动作;托管开关不算

var _state: DdzState = null
var _names := {}


func start(seat_order: Array, names: Dictionary, rng: RandomNumberGenerator) -> Array:
	_names = names.duplicate()
	_state = DdzState.new()
	var result := _state.start(seat_order, rng)
	return result["events"]


func state() -> DdzState:
	# 测试与机器人读局面用(只读)
	return _state


static func check_intent(intent: Variant) -> String:
	# 结构校验(不看局面):字典、kind 认识、字段类型对。返回错误码,合法为 ""
	if not intent is Dictionary or intent.size() > MAX_INTENT_KEYS:
		return DdzState.ERR_INVALID_INTENT
	var kind: Variant = intent.get("kind")
	if not kind is String or not KINDS.has(kind):
		return DdzState.ERR_INVALID_INTENT
	match kind:
		"bid":
			var score: Variant = intent.get("score")
			if not score is int or score < 0 or score > DdzState.MAX_BID:
				return DdzState.ERR_INVALID_BID
		"play":
			var cards: Variant = intent.get("cards")
			if not cards is Array or cards.is_empty() or cards.size() > DdzState.HAND_SIZE + DdzState.BOTTOM_SIZE:
				return DdzState.ERR_INVALID_PLAY
			for i in cards:
				if not i is int:
					return DdzState.ERR_INVALID_PLAY
		"pass":
			if intent.size() != 1:
				return DdzState.ERR_INVALID_INTENT
		"trustee":
			if not intent.get("on") is bool:
				return DdzState.ERR_INVALID_INTENT
	return ""


func validate_intent(intent: Variant) -> String:
	# rpc_session_intent 的结构校验(NetworkManager 通用入口调用)
	return check_intent(intent)


func handle_intent(pid: int, intent: Dictionary) -> Dictionary:
	if _state == null:
		return rejected(DdzState.ERR_SESSION_OVER)
	var error := check_intent(intent)
	if error != "":
		return rejected(error)
	if not _state.is_member(pid):
		return rejected(DdzState.ERR_NOT_SEATED)
	var result: Dictionary
	match intent["kind"]:
		"bid":
			result = _state.bid(pid, intent["score"])
		"play":
			result = _state.play(pid, intent["cards"])
		"pass":
			result = _state.pass_turn(pid)
		"trustee":
			result = _state.set_trustee(pid, intent["on"])
	if not result["ok"]:
		return rejected(result["error"])
	return accepted(_named(result["events"]), TURN_ACTION_KINDS.has(intent["kind"]))


func on_disconnect(pid: int) -> Array:
	if _state == null:
		return []
	return _named(_state.remove_player(pid))


func on_turn_timeout() -> Dictionary:
	if _state == null:
		return rejected(DdzState.ERR_SESSION_OVER)
	var result := _state.timeout()
	if not result["ok"]:
		return rejected(result["error"])
	return accepted(_named(result["events"]), true)


func public_view(turn_time_left: float) -> Dictionary:
	return DouDizhuViews.public_view(_state, _names, turn_time_left)


func private_view(pid: int) -> Dictionary:
	return DouDizhuViews.private_view(_state, pid)


func viewers() -> Array:
	# 全座位里没离开的人
	if _state == null:
		return []
	return _state.seat_order.filter(func(pid: int) -> bool: return not _state.left.has(pid))


func is_over() -> bool:
	return _state == null or _state.phase == DdzState.Phase.OVER


func is_ending() -> bool:
	return _state != null and _state.ending


func has_turn() -> bool:
	return _state != null and _state.current_pid != null \
		and (_state.phase == DdzState.Phase.BIDDING or _state.phase == DdzState.Phase.PLAYING)


func estimate(events: Array) -> float:
	return DouDizhuPacing.estimate(events)


func turn_timer_after(events: Array, pending: float, time_left: float) -> float:
	# pending = 含本批在内客户端还要演多久;time_left = 计时器当前剩余(到点触发时为 0)
	var pid: Variant = _state.current_pid
	if pid != null and _state.trustee.get(pid, false):
		return pending + DouDizhuPacing.TRUSTEE_DELAY
	var full := turn_timeout()
	if DouDizhuPacing.starts_turn(events) or time_left <= 0.0 or _trustee_off(events, pid):
		return pending + full
	# 旁人开关托管等:保留剩余,只补上本批演出
	return time_left + estimate(events)


func turn_timeout() -> float:
	# 当前阶段一个回合的完整时长
	return BID_TIMEOUT if _state.phase == DdzState.Phase.BIDDING else Protocol.TURN_TIMEOUT


func accepts_late_join() -> bool:
	return false


func next_hand_ready() -> bool:
	return _state != null and _state.phase == DdzState.Phase.BETWEEN and _state.can_start_hand()


func hand_gap() -> float:
	return DouDizhuPacing.HAND_GAP


func start_next_hand() -> Array:
	return _named(_state.start_hand()) if _state != null else []


func request_end() -> Array:
	return _named(_state.request_end()) if _state != null else []


func seats_with_patrons() -> Array:
	return _state.seat_order.duplicate() if _state != null else []


func name_of(pid: int) -> String:
	return _names.get(pid, str(pid))


func _named(events: Array) -> Array:
	# session_over 的结算行补名字(引擎不知道名字);引擎的字典不就地改
	return events.map(func(ev: Dictionary) -> Dictionary:
		if ev.get("type", "") == "session_over":
			return ev.merged({"results": ev["results"].map(func(row: Dictionary) -> Dictionary:
				return row.merged({"name": name_of(row["pid"])}, true))}, true)
		return ev)


static func _trustee_off(events: Array, pid: Variant) -> bool:
	# 当前行动者刚取消托管:给他满满一个回合
	for ev in events:
		if ev.get("type", "") == "trustee" and ev.get("pid") == pid and not ev.get("on", true):
			return true
	return false
