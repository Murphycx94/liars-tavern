class_name DdzBots
extends BotDriver
# 房主端的斗地主机器人(子节点 /root/Net/DdzBots)。轮到谁、等演出、问 AI、超时退回内置策略都在 BotDriver;
# 这里管斗地主的部分:记下本手的叫分 / 出牌记录与已出的牌给 AI 看,局面与出手(DdzBotBrain / DdzBotPrompt)。
# 一手结束后房主的计时器自动开下一手,机器人没有杂事;万一被托管了(不该发生)就自己取消托管。


const AI_WAIT_BID := 9.0        # 秒:最多等 AI 这么久(从演出播完算起),之后改用内置策略;叫分限时 15 秒
const AI_WAIT_PLAY := 20.0      # 出牌限时 30 秒

var _log: Array = []             # 本手的叫分 / 出牌记录(给 AI 看)
var _played: Array = []          # 本手已出的牌(给 AI 算「外面还有的牌」)


static func style_of(pid: int) -> Dictionary:
	return DdzBotBrain.style(style_index(pid))


func _on_reset() -> void:
	_log = []
	_played = []


# —— 事件 ——

func on_events(events: Array) -> void:
	super(events)
	var table_names := names()
	for ev in events:
		match ev.get("type", ""):
			"hand_started", "redeal":
				_log = []
				_played = []
			"played":
				_played.append_array(ev.get("cards", []))
		var line := DdzBotPrompt.describe_event(ev, table_names)
		if line != "":
			_log.append(line)


# —— 出手 ——

func _handles(mode: String) -> bool:
	return GameMode.is_dou_dizhu(mode)


func _situation(pid: int) -> Dictionary:
	return DdzBotBrain.situation(_net.last_public, _net.bot_private_view(pid), pid)


func _can_ask(sit: Dictionary) -> bool:
	return sit["stage"] != ""


func _prompts(pid: int, sit: Dictionary) -> Array:
	var table_names := names()
	var bot_label: String = table_names.get(pid, bot_name(pid))
	return [DdzBotPrompt.system_prompt(bot_label, style_of(pid)["persona"]),
		DdzBotPrompt.user_prompt(sit, _net.last_public, table_names, _log, _played)]


func _parse(text: String, sit: Dictionary) -> Dictionary:
	return DdzBotPrompt.parse(text, sit)


func _brain(pid: int, sit: Dictionary) -> Dictionary:
	return DdzBotBrain.decide(sit, style_of(pid), _rng)


func _apply(pid: int, choice: Dictionary, by_ai: bool) -> bool:
	# 出牌意图要手牌下标:按此刻的私有视图换算(手牌升序)
	match choice.get("kind", ""):
		"bid":
			return _net.bot_intent(pid, {"kind": "bid", "score": choice["score"]}, by_ai)
		"pass":
			return _net.bot_intent(pid, {"kind": "pass"}, by_ai)
		"play":
			var hand: Array = _net.bot_private_view(pid).get("cards", [])
			var indices := DdzState.indices_of(hand, choice["cards"])
			if indices.is_empty() or indices.has(-1):
				return false
			return _net.bot_intent(pid, {"kind": "play", "cards": indices}, by_ai)
	return false


func _fallback(sit: Dictionary) -> Dictionary:
	return DdzBotBrain.fallback(sit)


func _summary(choice: Dictionary) -> Array:
	match choice.get("kind", ""):
		"bid":
			return ["bid", int(choice["score"])]
		"play":
			return ["play:" + DdzBotPrompt.rank_labels(choice["cards"]), choice["cards"].size()]
	return [str(choice.get("kind", "")), 0]


func _ai_wait(sit: Dictionary) -> float:
	return AI_WAIT_BID if sit.get("stage", "") == DdzBotBrain.STAGE_BID else AI_WAIT_PLAY


func _log_label() -> String:
	return "斗地主机器人"


func _tick_chores(_delta: float) -> void:
	# 机器人从不超时,不该进托管;万一进了(比如房主那一帧卡住),自己取消,免得被托管打法抢着出
	for row in _net.last_public.get("players", []):
		var pid: Variant = row.get("pid")
		if pid is int and row.get("trustee", false) and not row.get("left", false) and _net.is_bot(pid):
			_net.bot_intent(pid, {"kind": "trustee", "on": false})
