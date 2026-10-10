class_name BombCatSession
extends GameSession
# 炸弹猫会话(设计稿 §2):持有 BombCatState 与名字表,把网络意图校验后分派给引擎,
# 用 NetworkManager 现有的回合计时器实现反应窗口、塞回、给牌三种等待(不新增计时器)。
# 意图字典(来自不可信对端,逐字段校验类型):
#   {"kind": "play", "cards": [手牌下标...], "target"?: pid, "named"?: 牌 id}
#   {"kind": "nope"}                 反应窗口里打出手里第一张「不行!」
#   {"kind": "draw"}
#   {"kind": "reinsert", "pos": int}  0 = 顶 … 牌堆张数 = 底
#   {"kind": "give", "index": int}    被讨要时给出第几张手牌
# 计时语义:自由行动 = Protocol.TURN_TIMEOUT(交出回合的批次演完后给满);打出牌 → 回合计时暂停,
# 计时器改走反应窗口(REACT_WINDOW,每张「不行!」重新计);窗口或给牌结束回到当前玩家时恢复暂停前的剩余
# (至少 RESUME_MIN);拆弹后塞回 = REINSERT_TIMEOUT;被讨要的人给牌 = GIVE_TIMEOUT。都从本批演出播完算起。
# 到点调 on_turn_timeout:窗口 → 结算;塞回 → 随机位置;给牌 → 随机一张;自由行动 → 直接摸牌。


const MAX_INTENT_KEYS := 4     # 意图字典最多这么多键:kind + 三个字段
const RESUME_MIN := 3.0        # 窗口 / 给牌结束后恢复的回合剩余至少这么多秒:看清偷看、抽到的牌再决定
const KINDS := ["play", "nope", "draw", "reinsert", "give"]
const TURN_ACTION_KINDS := ["play", "draw", "reinsert", "give"]   # 行动者要先看完排队演出才出手的动作

var _state: BombCatState = null
var _names := {}
var _step_before := BombCatState.Step.OVER   # 本批事件之前的步骤:计时规则据此判断「暂停」与「恢复」
var _paused_left := 0.0                       # 窗口 / 给牌期间暂停保存的回合剩余


func start(seat_order: Array, names: Dictionary, rng: RandomNumberGenerator) -> Array:
	_names = names.duplicate()
	_state = BombCatState.new()
	_step_before = BombCatState.Step.OVER
	_paused_left = 0.0
	var result := _state.start(seat_order, rng)
	return result["events"]


func state() -> BombCatState:
	# 测试与机器人读局面用(只读)
	return _state


static func check_intent(intent: Variant) -> String:
	# 结构校验(不看局面):字典、kind 认识、字段类型对。返回错误码,合法为 ""
	if not intent is Dictionary or intent.size() > MAX_INTENT_KEYS:
		return BombCatState.ERR_INVALID_INTENT
	var kind: Variant = intent.get("kind")
	if not kind is String or not KINDS.has(kind):
		return BombCatState.ERR_INVALID_INTENT
	match kind:
		"play":
			var cards: Variant = intent.get("cards")
			if not cards is Array or cards.size() > BombCatState.MAX_COMBO:
				return BombCatState.ERR_INVALID_PLAY
			for i in cards:
				if not i is int:
					return BombCatState.ERR_INVALID_PLAY
			var target: Variant = intent.get("target")
			if target != null and not target is int:
				return BombCatState.ERR_INVALID_TARGET
			var named: Variant = intent.get("named", "")
			if not named is String:
				return BombCatState.ERR_INVALID_NAMED
		"reinsert":
			if not intent.get("pos") is int:
				return BombCatState.ERR_INVALID_POS
		"give":
			if not intent.get("index") is int:
				return BombCatState.ERR_INVALID_INDEX
	return ""


func validate_intent(intent: Variant) -> String:
	return check_intent(intent)


func handle_intent(pid: int, intent: Dictionary) -> Dictionary:
	if _state == null:
		return rejected(BombCatState.ERR_MATCH_OVER)
	var error := check_intent(intent)
	if error != "":
		return rejected(error)
	if not _state.is_member(pid):
		return rejected(BombCatState.ERR_NOT_SEATED)
	var before := _state.step
	var result: Dictionary
	match intent["kind"]:
		"play":
			result = _state.play(pid, intent["cards"], intent.get("target"), intent.get("named", ""))
		"nope":
			result = _state.nope(pid)
		"draw":
			result = _state.draw(pid)
		"reinsert":
			result = _state.reinsert(pid, intent["pos"])
		"give":
			result = _state.give(pid, intent["index"])
	if not result["ok"]:
		return rejected(result["error"])
	_step_before = before
	# 「不行!」不清演出欠账:谁都能打,打的人不一定看完了前面的演出,窗口要从排队演出播完算起
	return accepted(result["events"], TURN_ACTION_KINDS.has(intent["kind"]))


func on_disconnect(pid: int) -> Array:
	if _state == null:
		return []
	var before := _state.step
	var events: Array = _state.eliminate(pid)["events"]
	if not events.is_empty():
		_step_before = before
	return events


func on_turn_timeout() -> Dictionary:
	if _state == null or _state.step == BombCatState.Step.OVER:
		return rejected(BombCatState.ERR_MATCH_OVER)
	var before := _state.step
	var result := _state.timeout()
	if not result["ok"]:
		return rejected(result["error"])
	_step_before = before
	return accepted(result["events"], true)


func public_view(turn_time_left: float) -> Dictionary:
	return BombCatViews.public_view(_state, _names, turn_time_left, _paused_left)


func private_view(pid: int) -> Dictionary:
	return BombCatViews.private_view(_state, pid)


func viewers() -> Array:
	# 全座位(出局者也收:手牌为空、alive 为假,界面据此进观战)
	return _state.seat_order.duplicate() if _state != null else []


func is_over() -> bool:
	return _state == null or _state.step == BombCatState.Step.OVER


func has_turn() -> bool:
	# 没结束就总有人在计时:当前玩家、反应窗口、塞回或给牌
	return not is_over()


func estimate(events: Array) -> float:
	return BombCatPacing.estimate(events)


func turn_timer_after(events: Array, pending: float, time_left: float) -> float:
	# pending = 含本批在内客户端还要演多久;time_left = 计时器当前剩余(到点触发时为 0)。按本批之后的步骤定时长
	var step := _state.step
	match step:
		BombCatState.Step.WINDOW:
			if BombCatPacing.has_event(events, "played"):
				# 回合计时暂停:记下出牌那一刻的剩余
				_paused_left = maxf(time_left, RESUME_MIN) if time_left > 0.0 else Protocol.TURN_TIMEOUT
				return pending + BombCatState.REACT_WINDOW
			if BombCatPacing.has_event(events, "noped"):
				return pending + BombCatState.REACT_WINDOW
			return _keep(events, pending, time_left, BombCatState.REACT_WINDOW)
		BombCatState.Step.REINSERT:
			if _step_before != BombCatState.Step.REINSERT:
				return pending + BombCatState.REINSERT_TIMEOUT
			return _keep(events, pending, time_left, BombCatState.REINSERT_TIMEOUT)
		BombCatState.Step.GIVE:
			if _step_before != BombCatState.Step.GIVE:
				return pending + BombCatState.GIVE_TIMEOUT
			return _keep(events, pending, time_left, BombCatState.GIVE_TIMEOUT)
	# 自由行动:换人(或同一人连走下一回合)给满;从窗口 / 给牌回来恢复暂停的剩余;其他(旁人断线)只顺延
	if BombCatPacing.starts_turn(events):
		_paused_left = 0.0
		return pending + Protocol.TURN_TIMEOUT
	if _step_before == BombCatState.Step.WINDOW or _step_before == BombCatState.Step.GIVE:
		var resumed := maxf(_paused_left, RESUME_MIN)
		_paused_left = 0.0
		return pending + resumed
	return _keep(events, pending, time_left, Protocol.TURN_TIMEOUT)


func paused_turn_left() -> float:
	return _paused_left


func seats_with_patrons() -> Array:
	return _state.seat_order.duplicate() if _state != null else []


func name_of(pid: int) -> String:
	return _names.get(pid, str(pid))


func _keep(events: Array, pending: float, time_left: float, full: float) -> float:
	# 本批没换步骤(如旁人断线):保留剩余,只补上本批演出;计时器没在走时给满
	if time_left <= 0.0:
		return pending + full
	return time_left + estimate(events)
