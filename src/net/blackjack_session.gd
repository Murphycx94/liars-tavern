class_name BlackjackSession
extends GameSession
# 21 点会话(设计稿 §3):持有 BjTable 与名字表,把字典意图(经 rpc_session_intent)分派给引擎,给事件补名字,
# 决定计时与两局之间的间隔。视图由 BlackjackViews 构建;没有私有视图(所有牌都是明牌,庄家暗牌不进视图)。


const KINDS := BjRules.BET_ACTIONS + BjRules.PLAY_ACTIONS + BjRules.SEAT_ACTIONS

var _table: BjTable = null
var _names := {}   # 含已离开者:结算行要用


func start(seat_order: Array, names: Dictionary, rng: RandomNumberGenerator) -> Array:
	_names = names.duplicate()
	_table = BjTable.new(rng)
	for pid in seat_order:
		_table.seat(pid)
	return _named(_table.start_round())


func table() -> BjTable:
	return _table


func validate_intent(intent: Variant) -> String:
	# {"kind": 动作} 或 {"kind": "bet", "amount": 整数};来自不可信对端,只看结构
	if not intent is Dictionary or not intent.get("kind") is String or not KINDS.has(intent["kind"]):
		return "invalid_intent"
	var allowed := ["kind", "amount"] if intent["kind"] == BjRules.BET else ["kind"]
	for key in intent:
		if not allowed.has(key):
			return "invalid_intent"
	if intent["kind"] == BjRules.BET and not intent.get("amount") is int:
		return "invalid_amount"
	return ""


func handle_intent(pid: int, intent: Dictionary) -> Dictionary:
	# 决策动作消耗回合;下注、这局不玩、再领、回座不消耗(下注阶段是同时进行的,最后一个人下完注才发牌)
	var error := validate_intent(intent)
	if error != "":
		return rejected(error)
	var kind: String = intent["kind"]
	var result: Dictionary
	match kind:
		BjRules.BET:
			result = _table.bet(pid, intent["amount"])
		BjRules.SKIP:
			result = _table.skip(pid)
		BjRules.REBUY:
			result = _table.rebuy(pid)
		BjRules.SIT_IN:
			result = _table.sit_in(pid)
		_:
			result = _table.act(pid, kind)
	if not result["ok"]:
		return rejected(result["error"])
	return accepted(_named(result["events"]), BjRules.PLAY_ACTIONS.has(kind))


func on_disconnect(pid: int) -> Array:
	# 桌上没有他的酒客(还没登场的新人):离开事件标 offstage,不占演出时间
	var offstage := not _table.seats_with_patrons().has(pid)
	return _named(_table.remove_player(pid)).map(func(ev: Dictionary) -> Dictionary:
		if offstage and ev.get("type") == "player_left":
			return ev.merged({"offstage": true}, true)
		return ev)


func on_turn_timeout() -> Dictionary:
	var result := _table.timeout_action()
	if not result["ok"]:
		return rejected(result["error"])
	return accepted(_named(result["events"]), true)


func public_view(turn_time_left: float) -> Dictionary:
	return BlackjackViews.public_view(_table, _names, turn_time_left)


func viewers() -> Array:
	return []


func is_over() -> bool:
	return _table.phase() == BjTable.Phase.OVER


func is_ending() -> bool:
	return _table.is_ending()


func has_turn() -> bool:
	# 下注阶段(大家同时下注,共用一个限时)或者有人在决策
	return _table.phase() == BjTable.Phase.BETTING or (_table.phase() == BjTable.Phase.PLAYING and _table.current() != null)


func estimate(events: Array) -> float:
	return BlackjackPacing.estimate(events)


func turn_timer_after(events: Array, pending: float, time_left: float) -> float:
	return BlackjackPacing.timer_after(events, pending, time_left, _table.phase() == BjTable.Phase.BETTING)


func accepts_late_join() -> bool:
	return not is_over() and not is_ending()


func add_player(pid: int, name: String) -> Array:
	var events := _table.add_player(pid)
	if not events.is_empty():
		_names[pid] = name
	return _named(events)


func next_hand_ready() -> bool:
	return _table.can_start_round()


func hand_gap() -> float:
	return BlackjackPacing.ROUND_GAP


func start_next_hand() -> Array:
	return _named(_table.start_round())


func request_end() -> Array:
	return _named(_table.request_end())


func seats_with_patrons() -> Array:
	return _table.seats_with_patrons() if _table != null else []


func name_of(pid: int) -> String:
	return _names.get(pid, str(pid))


func _named(events: Array) -> Array:
	# player_joined 与 session_over 里的名字由会话补(引擎不知道名字);补了名字的是新字典
	return events.map(func(ev: Dictionary) -> Dictionary:
		match ev.get("type", ""):
			"player_joined":
				return ev.merged({"name": name_of(ev["pid"])}, true)
			"session_over":
				return ev.merged({"results": ev["results"].map(func(row: Dictionary) -> Dictionary:
					return row.merged({"name": name_of(row["pid"])}, true))}, true)
		return ev)
