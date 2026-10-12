class_name PokerBots
extends BotDriver
# 房主端的德州机器人(子节点 /root/Net/PokerBots)。轮到谁、等演出、问 AI、超时退回内置策略都在 BotDriver;
# 这里管德州的部分:记下本手的行动记录给 AI 看,局面与出手(PokerBotBrain / PokerBotPrompt),
# 一手结束后机器人自己点「开始下一手」,输光了就再领。


const AI_WAIT := 20.0           # 秒:最多等 AI 这么久(从演出播完算起),之后改用内置策略;回合限时 30 秒
const SEAT_CHORE_DELAY := 0.8   # 秒:一手结束(演完)后这么久,机器人点「开始下一手」或再领

var _chore_wait := -1.0          # 一手结束后的杂事倒计时;< 0 表示没有
var _log: Array = []             # 本手的行动记录(给 AI 看)


static func style_of(pid: int) -> Dictionary:
	return PokerBotBrain.style(style_index(pid))


func _on_reset() -> void:
	_chore_wait = -1.0
	_log = []


# —— 事件 ——

func on_events(events: Array) -> void:
	super(events)
	var table_names := names()
	for ev in events:
		match ev.get("type", ""):
			"hand_started":
				_log = []
			"hand_over":
				_chore_wait = _net.anim_left() + SEAT_CHORE_DELAY
		var line := PokerBotPrompt.describe_event(ev, table_names)
		if line != "":
			_log.append(line)


# —— 出手 ——

func _handles(mode: String) -> bool:
	return GameMode.is_poker(mode)


func _situation(pid: int) -> Dictionary:
	return PokerBotBrain.situation(_net.last_public, _private(pid), pid)


func _can_ask(sit: Dictionary) -> bool:
	return not sit["legal"].is_empty()


func _prompts(pid: int, sit: Dictionary) -> Array:
	var table_names := names()
	var bot_label: String = table_names.get(pid, bot_name(pid))
	return [PokerBotPrompt.system_prompt(bot_label, style_of(pid)["persona"]),
		PokerBotPrompt.user_prompt(sit, _net.last_public, table_names, _log)]


func _parse(text: String, sit: Dictionary) -> Dictionary:
	var parsed := PokerBotPrompt.parse(text, sit["legal"])
	if not parsed["ok"]:
		return parsed
	return {"ok": true, "choice": {"action": parsed["action"], "amount": parsed["amount"]}, "quip": parsed["quip"]}


func _brain(pid: int, sit: Dictionary) -> Dictionary:
	return PokerBotBrain.decide(sit, style_of(pid), _rng)


func _apply(pid: int, choice: Dictionary, from: String) -> bool:
	return _send(pid, {"kind": choice["action"], "amount": choice["amount"]}, from)


func _fallback(sit: Dictionary) -> Dictionary:
	return PokerBotBrain.fallback(sit["legal"])


func _ai_wait(_sit: Dictionary) -> float:
	return AI_WAIT


func _log_label() -> String:
	return "德州机器人"


# —— 一手结束后的杂事 ——

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
