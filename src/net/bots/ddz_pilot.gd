class_name DdzPilot
extends DdzBots
# 本机玩家的斗地主托管(子节点 /root/Net/DdzPilot,各端都有)。开关是房主那边的托管状态(「托管」按钮、连续超时自动进入),
# 托管中轮到自己就替自己出手(见 TrusteePilot):本机 AI 或机器人的内置策略,经 Net.submit_session_intent 发给房主(带来源 by)。
# 房主给托管中的人一个完整回合;本机没出手(比如旧的出牌逻辑卡住)就到点由房主按托管打法代打。


func _ready() -> void:
	super()
	_net.game_events.connect(_on_game_events)
	_net.intent_rejected.connect(func(_code: String) -> void:
		if _active():
			_retry_after_rejection())


func _on_game_events(events: Array) -> void:
	# 各端每批事件都会到:只记自己这个玩法的(别的玩法的事件字段不一样)
	if _net.in_game and _handles(_net.game_mode):
		on_events(events)


func _active() -> bool:
	return _net.in_game and _handles(_net.game_mode) and TrusteePilot.flag(_net.last_private.get("trustee"))


func _controlled_turn() -> Variant:
	var me: int = _net.my_pid()
	var mine: bool = _net.last_public.get("current_pid") == me and TrusteePilot.flag(_net.last_private.get("my_turn"))
	return me if mine else null


func _turn_key() -> Variant:
	var pub: Dictionary = _net.last_public
	return var_to_str([pub.get("hand"), pub.get("deal"), pub.get("phase"), pub.get("lead"), pub.get("passes"),
		pub.get("bids")])


func _process(delta: float) -> void:
	# 托管关了(或牌局结束):想到一半的这一步作废,还没回来的 AI 请求取消(不再花你的额度)
	if not _active():
		if not _decision.is_empty():
			reset()
		return
	super(delta)


func _anim() -> float:
	var full := DouDizhuSession.BID_TIMEOUT if _net.last_public.get("phase") == "bidding" else Protocol.TURN_TIMEOUT
	return TrusteePilot.client_anim(_net.last_public, full)


func _turn_left() -> float:
	return TrusteePilot.turn_left(_net.last_public)


func _private(_pid: int) -> Dictionary:
	return _net.last_private


func _send(_pid: int, intent: Dictionary, from: String) -> bool:
	_net.submit_session_intent(TrusteePilot.with_source(intent, from))
	return true


func _source(asked: bool, by_ai: bool) -> String:
	return TrusteePilot.source(asked, by_ai)


func _who() -> String:
	return "托管"


func _say(_pid: int, _quip: int) -> void:
	pass


func _prompts(pid: int, sit: Dictionary) -> Array:
	var table_names := names()
	var me: String = table_names.get(pid, _net.player_name)
	return [DdzBotPrompt.system_prompt(me, TrusteePilot.PERSONA % me),
		DdzBotPrompt.user_prompt(sit, _net.last_public, table_names, _log, _played)]


func _brain(_pid: int, sit: Dictionary) -> Dictionary:
	return DdzBotBrain.decide(sit, DdzBotBrain.style(0), _rng)


func _log_label() -> String:
	return "斗地主托管"


func _tick_chores(_delta: float) -> void:
	pass   # 机器人那边会自己取消误入的托管;玩家的托管由玩家自己开关
