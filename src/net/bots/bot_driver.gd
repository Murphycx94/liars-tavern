class_name BotDriver
extends Node
# 房主端机器人的公共骨架(德州 PokerBots、斗地主 DdzBots 继承它,都是 /root/Net 的子节点,没有 RPC)。
# 机器人是等待厅里 pid 为负数的成员,没有网络连接,由这里替它们出手:每批事件之后 NetworkManager 调 on_events;
# 轮到机器人时先等客户端演完、再「想」一两秒,然后出手(经 NetworkManager.bot_intent,和真人的意图走同一套校验)。
# 接了 AI(AiSettings 打开且填好)时,轮到它就把局面发给 AI,按 AI 的回答出手;AI 出错、超时或答非所问时
# 改用内置策略,出错原因经 notice 提示房主(有冷却,不刷屏)。
# 子类只管玩法:_handles / _situation / _can_ask / _prompts / _parse / _brain / _apply / _fallback / _ai_wait,
# 需要时再覆盖 on_events、_tick_chores、_on_reset。局面 sit 与出手 choice 都是子类自己定义的字典。
# 本机玩家的托管(PokerPilot / DdzPilot)也用这套骨架,只是「替谁出手、看谁的牌、怎么发意图」不同:
# 覆盖 _active / _controlled_turn / _turn_key / _anim / _private / _send / _source / _say。


signal notice(text: String)
signal decided(pid: int, action: String, amount: int, by_ai: bool)   # 每次出手(调试与冒烟测试用)

const NAME_PREFIX := "机器人·"
const NAMES := ["阿福", "豆豆", "团团", "旺财", "可乐", "布丁", "年糕", "汤圆", "花卷", "麻薯"]
const THINK_MIN := 0.8          # 秒:轮到机器人后(演出播完)想这么久再出手,看起来像在考虑
const THINK_MAX := 2.2
const NOTICE_COOLDOWN_MS := 30_000
const ANSWER_SNIPPET := 160          # 看不懂的回答在日志里摘录多少字
const SOURCE_AI := "ai"               # 出手事件的 by:这一步是 AI 出的
const SOURCE_FALLBACK := "fallback"   # 问过 AI 但没用上(出错、超时、看不懂),内置策略代打
const SOURCE_TRUSTEE := "trustee"         # 玩家托管:本机内置策略代打(或本机 AI 没接上)
const SOURCE_TRUSTEE_AI := "trustee_ai"   # 玩家托管:本机 AI 代打

var config := {}                 # AI 设置(AiSettings 的字典);房主在设置面板保存后经 set_config 更新
var _net: Node = null            # NetworkManager(父节点)
var _ai: AiChat = null
var _rng := RandomNumberGenerator.new()
var _turn_serial := 0            # 每个 turn 事件加一:同一个机器人连着两次轮到也能区分
var _decision := {}              # 正在想的一步:{"key", "pid", "sit", "wait", "deadline", "ask", "asked", "choice", "quip"}
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


static func style_index(pid: int) -> int:
	# 性格按 pid 轮换:-1 是第一种,-2 是第二种…
	return -pid - 1


func reset() -> void:
	# 开局、回等待厅、离开房间时清空:没回来的 AI 请求作废
	_decision = {}
	if _ai != null:
		_ai.cancel_all()
	_on_reset()


func on_events(events: Array) -> void:
	# NetworkManager 每批事件下发、同步之后调用(公共视图已是这一批之后的);子类覆盖时先调 super
	for ev in events:
		if ev.get("type", "") == "turn":
			_turn_serial += 1


func names() -> Dictionary:
	var out := {}
	for row in _net.last_public.get("players", []):
		out[row.get("pid")] = row.get("name", "?")
	return out


# —— 每帧:轮到机器人就想、到点出手 ——

func _process(delta: float) -> void:
	if not _active():
		return
	_tick_chores(delta)
	var current: Variant = _controlled_turn()
	if current == null:
		_decision = {}
		return
	var key: Variant = _turn_key()
	if _decision.get("key") != key or _decision.get("pid") != current:
		_begin(current, key)
	_decision["wait"] -= delta
	_decision["deadline"] -= delta
	if _decision["wait"] > 0.0:
		return
	if _decision["choice"].is_empty() and _decision["ask"] >= 0 and _decision["deadline"] > 0.0:
		return   # 还在等 AI
	_finish()


func _begin(pid: int, key: Variant) -> void:
	var sit := _situation(pid)
	var anim := _anim()
	_decision = {
		"key": key, "pid": pid, "sit": sit, "choice": {}, "quip": -1, "ask": -1, "asked": false,
		"wait": anim + _rng.randf_range(THINK_MIN, THINK_MAX), "deadline": anim + _ai_wait(sit),
	}
	if ai_active() and _can_ask(sit):
		var prompts := _prompts(pid, sit)
		_decision["asked"] = true
		_decision["ask"] = _ai.ask(config, prompts[0], prompts[1])


func _on_answered(id: int, ok: bool, text: String) -> void:
	# 过期的回答(已经超时改用内置策略、或局面变了)不理
	if _decision.is_empty() or _decision["ask"] != id:
		return
	_decision["ask"] = -1
	if not ok:
		_notify("AI 出错:%s。%s这一步按内置策略打" % [text, _who()])
		return
	var parsed := _parse(text, _decision["sit"])
	if not parsed["ok"]:
		_notify("AI 的回答看不懂(%s),%s这一步按内置策略打" % [parsed["error"], _who()],
			"回答开头:" + text.strip_edges().substr(0, ANSWER_SNIPPET).replace("\n", " "))
		return
	_decision["choice"] = parsed["choice"]
	_decision["quip"] = parsed["quip"]


func _finish() -> void:
	var pid: int = _decision["pid"]
	var sit: Dictionary = _decision["sit"]
	if _decision["ask"] >= 0:
		_notify("AI 超过 %d 秒没回答,%s这一步按内置策略打" % [int(_ai_wait(sit)), _who()])
	var choice: Dictionary = _decision["choice"]
	var by_ai := not choice.is_empty()
	if not by_ai:
		choice = _brain(pid, sit)
	var quip: int = _decision["quip"]
	_decision["wait"] = INF   # 本步已出手:同一个 serial 不再出第二次
	_decision["ask"] = -1
	if choice.is_empty():
		_decision = {}   # 开始想的时候视图里还没有它的可选动作:下一帧按最新视图重来
		return
	# 接了 AI 时给事件标来源:AI 出的「ai」,AI 没接上、内置策略代打的「fallback」;没接 AI 不标(托管另有来源)
	var asked: bool = _decision["asked"]
	if not _apply(pid, choice, _source(asked, by_ai)):
		choice = _fallback(sit)
		by_ai = false
		_apply(pid, choice, _source(asked, false))
	var summary := _summary(choice)
	decided.emit(pid, summary[0], summary[1], by_ai)
	if quip >= 0:
		_say(pid, quip)


static func source(asked: bool, by_ai: bool) -> String:
	if not asked:
		return ""
	return SOURCE_AI if by_ai else SOURCE_FALLBACK


func _notify(text: String, detail := "") -> void:
	# detail 只进日志(排查用),不上房主屏幕
	push_warning("%s:%s%s" % [_log_label(), text, (";" + detail) if detail != "" else ""])
	var now := Time.get_ticks_msec()
	if now - _noticed_at >= NOTICE_COOLDOWN_MS:
		_noticed_at = now
		notice.emit(text)


# —— 替谁出手(默认:房主替机器人;托管覆盖成本机玩家) ——

func _active() -> bool:
	return _net.is_host and _net.in_game and _handles(_net.game_mode)


func _controlled_turn() -> Variant:
	# 现在轮到的、由这里出手的人;没有返回 null
	var current: Variant = _net.last_public.get("current_pid")
	return current if current is int and _net.is_bot(current) else null


func _turn_key() -> Variant:
	# 区分「同一个人的不同回合」:变了就重新想
	return _turn_serial


func _anim() -> float:
	# 客户端还要演多久(出手要等演完)
	return _net.anim_left()


func _private(pid: int) -> Dictionary:
	return _net.bot_private_view(pid)


func _send(pid: int, intent: Dictionary, from: String) -> bool:
	# 发意图;被拒返回 false(托管经网络发,结果晚到,一律当成功)
	return _net.bot_intent(pid, intent, from)


func _source(asked: bool, by_ai: bool) -> String:
	return source(asked, by_ai)


func _say(pid: int, quip: int) -> void:
	_net.bot_quip(pid, quip)


func _who() -> String:
	# 提示里替谁出手:「机器人」或「托管」
	return "机器人"


# —— 子类实现 ——

func _handles(_mode: String) -> bool:
	return false


func _situation(_pid: int) -> Dictionary:
	# 只用玩家看得到的东西(公共视图 + 这个机器人的私有视图)
	return {}


func _can_ask(_sit: Dictionary) -> bool:
	# 轮到它且有事可做时才问 AI
	return false


func _prompts(_pid: int, _sit: Dictionary) -> Array:
	# → [系统提示词, 用户提示词]
	return ["", ""]


func _parse(_text: String, _sit: Dictionary) -> Dictionary:
	# AI 的回答 → {"ok": true, "choice", "quip": 编号或 -1} 或 {"ok": false, "error"}
	return {"ok": false, "error": "没有实现"}


func _brain(_pid: int, _sit: Dictionary) -> Dictionary:
	# 内置策略的出手;还没有可选动作时返回 {}
	return {}


func _apply(_pid: int, _choice: Dictionary, _from: String) -> bool:
	# 把出手换成意图经 _send 发出(来源原样传过去,标在出手事件上);被拒返回 false
	return false


func _fallback(_sit: Dictionary) -> Dictionary:
	# 出手被拒时的兜底(一定合法的那一步)
	return {}


func _summary(choice: Dictionary) -> Array:
	# → [动作名, 数额](decided 信号用)
	return [str(choice.get("action", "")), int(choice.get("amount", 0))]


func _ai_wait(_sit: Dictionary) -> float:
	# 秒:最多等 AI 这么久(从演出播完算起),之后改用内置策略;要比回合限时短
	return 0.0


func _tick_chores(_delta: float) -> void:
	pass


func _on_reset() -> void:
	pass


func _log_label() -> String:
	return "机器人"
