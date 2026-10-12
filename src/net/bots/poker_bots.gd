class_name PokerBots
extends Node
# 房主端的德州机器人(子节点 /root/Net/PokerBots)。机器人是等待厅里 pid 为负数的成员,没有网络连接,
# 由这里替它们出手:每批事件之后 NetworkManager 调 on_events,这里记下本手的行动记录;
# 轮到机器人时先等客户端演完、再「想」一两秒,然后出手(经 NetworkManager.bot_intent,和真人的意图走同一套校验)。
# 接了 AI(AiSettings 打开且填好)时,轮到它就把局面发给 AI,按 AI 的回答出手;AI 出错、超时或答非所问时
# 改用内置策略(PokerBotBrain),出错原因经 notice 提示房主(有冷却,不刷屏)。
# 一手结束后机器人自己点「开始下一手」,输光了就再领。


signal notice(text: String)
signal decided(pid: int, action: String, amount: int, by_ai: bool)   # 每次出手(调试与冒烟测试用)

const NAME_PREFIX := "机器人·"
const NAMES := ["阿福", "豆豆", "团团", "旺财", "可乐", "布丁", "年糕", "汤圆", "花卷", "麻薯"]
const THINK_MIN := 0.8          # 秒:轮到机器人后(演出播完)想这么久再出手,看起来像在考虑
const THINK_MAX := 2.2
const AI_WAIT := 20.0           # 秒:最多等 AI 这么久(从演出播完算起),之后改用内置策略;回合限时 30 秒
const SEAT_CHORE_DELAY := 0.8   # 秒:一手结束(演完)后这么久,机器人点「开始下一手」或再领
const NOTICE_COOLDOWN_MS := 30_000
const ANSWER_SNIPPET := 160          # 看不懂的回答在日志里摘录多少字
const SOURCE_AI := "ai"               # action 事件的 by:这一步是 AI 出的
const SOURCE_FALLBACK := "fallback"   # 问过 AI 但没用上(出错、超时、看不懂),内置策略代打

var config := {}                 # AI 设置(AiSettings 的字典);房主在设置面板保存后经 set_config 更新
var _net: Node = null            # NetworkManager(父节点)
var _ai: AiChat = null
var _rng := RandomNumberGenerator.new()
var _turn_serial := 0            # 每个 turn 事件加一:同一个机器人连着两次轮到也能区分
var _decision := {}              # 正在想的一步:{"serial", "pid", "wait", "deadline", "legal", "ask", "choice", "quip"}
var _chore_wait := -1.0          # 一手结束后的杂事倒计时;< 0 表示没有
var _log: Array = []             # 本手的行动记录(给 AI 看)
var _noticed_at := -NOTICE_COOLDOWN_MS


func _ready() -> void:
	_net = get_parent()
	_rng.randomize()
	_ai = AiChat.new()
	_ai.name = "AiChat"
	add_child(_ai)
	_ai.answered.connect(_on_answered)
	config = AiSettings.load_config()


func set_config(values: Dictionary) -> void:
	config = AiSettings.sanitized(values)


func ai_active() -> bool:
	return AiSettings.is_active(config)


static func bot_name(pid: int) -> String:
	# pid 为 -1、-2…:按顺序取名字(重名由等待厅名单补编号)
	return NAME_PREFIX + NAMES[posmod(-pid - 1, NAMES.size())]


static func style_of(pid: int) -> Dictionary:
	return PokerBotBrain.style(-pid - 1)


func reset() -> void:
	# 开局、回等待厅、离开房间时清空:没回来的 AI 请求作废
	_decision = {}
	_chore_wait = -1.0
	_log = []
	if _ai != null:
		_ai.cancel_all()


# —— 事件 ——

func on_events(events: Array) -> void:
	# NetworkManager 每批事件下发、同步之后调用(公共视图已是这一批之后的)
	var names := _names()
	for ev in events:
		match ev.get("type", ""):
			"hand_started":
				_log = []
			"turn":
				_turn_serial += 1
			"hand_over":
				_chore_wait = _net.anim_left() + SEAT_CHORE_DELAY
		var line := PokerBotPrompt.describe_event(ev, names)
		if line != "":
			_log.append(line)


func _names() -> Dictionary:
	var names := {}
	for row in _net.last_public.get("players", []):
		names[row.get("pid")] = row.get("name", "?")
	return names


# —— 每帧:轮到机器人就想、到点出手;一手结束后的杂事 ——

func _process(delta: float) -> void:
	if not _net.is_host or not _net.in_game:
		return
	_tick_chores(delta)
	var current: Variant = _net.last_public.get("current_pid")
	if not current is int or not _net.is_bot(current):
		_decision = {}
		return
	if _decision.get("serial") != _turn_serial or _decision.get("pid") != current:
		_begin(current)
	_decision["wait"] -= delta
	_decision["deadline"] -= delta
	if _decision["wait"] > 0.0:
		return
	if _decision["choice"].is_empty() and _decision["ask"] >= 0 and _decision["deadline"] > 0.0:
		return   # 还在等 AI
	_finish()


func _begin(pid: int) -> void:
	var sit := PokerBotBrain.situation(_net.last_public, _net.bot_private_view(pid), pid)
	var anim: float = _net.anim_left()
	_decision = {
		"serial": _turn_serial, "pid": pid, "sit": sit, "choice": {}, "quip": -1, "ask": -1,
		"wait": anim + _rng.randf_range(THINK_MIN, THINK_MAX), "deadline": anim + AI_WAIT,
	}
	if ai_active() and not sit["legal"].is_empty():
		var style := style_of(pid)
		var bot_label: String = _names().get(pid, bot_name(pid))
		_decision["asked"] = true
		_decision["ask"] = _ai.ask(config, PokerBotPrompt.system_prompt(bot_label, style["persona"]),
			PokerBotPrompt.user_prompt(sit, _net.last_public, _names(), _log))


func _on_answered(id: int, ok: bool, text: String) -> void:
	# 过期的回答(已经超时改用内置策略、或局面变了)不理
	if _decision.is_empty() or _decision["ask"] != id:
		return
	_decision["ask"] = -1
	if not ok:
		_notify("AI 出错:%s。机器人这一步按内置策略打" % text)
		return
	var parsed := PokerBotPrompt.parse(text, _decision["sit"]["legal"])
	if not parsed["ok"]:
		_notify("AI 的回答看不懂(%s),机器人这一步按内置策略打" % parsed["error"],
			"回答开头:" + text.strip_edges().substr(0, ANSWER_SNIPPET).replace("\n", " "))
		return
	_decision["choice"] = {"action": parsed["action"], "amount": parsed["amount"]}
	_decision["quip"] = parsed["quip"]


func _finish() -> void:
	var pid: int = _decision["pid"]
	var sit: Dictionary = _decision["sit"]
	if _decision["ask"] >= 0:
		_notify("AI 超过 %d 秒没回答,机器人这一步按内置策略打" % int(AI_WAIT))
	var choice: Dictionary = _decision["choice"]
	var by_ai := not choice.is_empty()
	if not by_ai:
		choice = PokerBotBrain.decide(sit, style_of(pid), _rng)
	var quip: int = _decision["quip"]
	_decision["wait"] = INF   # 本步已出手:同一个 serial 不再出第二次
	_decision["ask"] = -1
	if choice.is_empty():
		_decision = {}   # 开始想的时候视图里还没有它的可选动作:下一帧按最新视图重来
		return
	# 接了 AI 时给事件标来源:AI 出的「ai」,AI 没接上、内置策略代打的「fallback」;没接 AI 不标
	var asked: bool = _decision.get("asked", false)
	if not _net.bot_intent(pid, {"kind": choice["action"], "amount": choice["amount"]}, _source(asked, by_ai)):
		choice = PokerBotBrain.fallback(sit["legal"])
		by_ai = false
		_net.bot_intent(pid, {"kind": choice["action"], "amount": choice["amount"]}, _source(asked, false))
	decided.emit(pid, choice["action"], choice["amount"], by_ai)
	if quip >= 0:
		_net.bot_quip(pid, quip)


static func _source(asked: bool, by_ai: bool) -> String:
	if not asked:
		return ""
	return SOURCE_AI if by_ai else SOURCE_FALLBACK


func _tick_chores(delta: float) -> void:
	# 一手结束:输光的机器人再领(再领也算点了开始),其余点「开始下一手」;挂机离座的回到牌桌
	if _chore_wait < 0.0:
		return
	_chore_wait -= delta
	if _chore_wait > 0.0:
		return
	_chore_wait = -1.0
	for row in _net.last_public.get("players", []):
		var pid: Variant = row.get("pid")
		if not pid is int or not _net.is_bot(pid) or row.get("left", false):
			continue
		match row.get("status"):
			PokerRules.STATUS_BUSTED:
				_net.bot_intent(pid, {"kind": PokerRules.REBUY, "amount": 0})
			PokerRules.STATUS_AWAY:
				_net.bot_intent(pid, {"kind": PokerRules.SIT_IN, "amount": 0})
				_net.bot_intent(pid, {"kind": PokerRules.NEXT, "amount": 0})
			_:
				_net.bot_intent(pid, {"kind": PokerRules.NEXT, "amount": 0})


func _notify(text: String, detail := "") -> void:
	# detail 只进日志(排查用),不上房主屏幕
	push_warning("德州机器人:" + text + ((";" + detail) if detail != "" else ""))
	var now := Time.get_ticks_msec()
	if now - _noticed_at >= NOTICE_COOLDOWN_MS:
		_noticed_at = now
		notice.emit(text)
