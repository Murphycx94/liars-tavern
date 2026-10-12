class_name PokerPilot
extends PokerBots
# 本机玩家的德州托管(子节点 /root/Net/PokerPilot,各端都有)。打开后轮到自己就替自己出手(见 TrusteePilot):
# 本机 AI 或内置策略,经 Net.submit_session_intent 发给房主(带来源 by)。一手结束自动点「开始下一手」;
# 输光了不替你再领(等你自己决定),托管照开着。德州没有服务器端的托管状态:开关只在本机,开新局、回等待厅、离开时关掉。


signal changed(on: bool)

var enabled := false


func _ready() -> void:
	super()
	_net.game_events.connect(_on_game_events)
	_net.game_started.connect(func(_seats: Array) -> void: set_enabled(false))
	_net.returned_to_lobby.connect(set_enabled.bind(false))
	_net.left_lobby.connect(func(_reason: String) -> void: set_enabled(false))


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	_decision = {}
	_chore_wait = -1.0
	if _ai != null:
		_ai.cancel_all()
	changed.emit(on)


func _on_game_events(events: Array) -> void:
	# 各端每批事件都会到:只记自己这个玩法的(别的玩法的事件字段不一样)
	if _net.in_game and _handles(_net.game_mode):
		on_events(events)


func _active() -> bool:
	return enabled and _net.in_game and _handles(_net.game_mode)


func _controlled_turn() -> Variant:
	var me: int = _net.my_pid()
	return me if _net.last_public.get("current_pid") == me else null


func _turn_key() -> Variant:
	# 同一手同一轮里,轮到自己时可选动作(跟注额、最小加注)变了就是新的一回合
	var pub: Dictionary = _net.last_public
	return var_to_str([pub.get("hand"), pub.get("street"), pub.get("actions")])


func _anim() -> float:
	return TrusteePilot.client_anim(_net.last_public, Protocol.TURN_TIMEOUT)


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
	pass   # 托管不替玩家说话


func _prompts(pid: int, sit: Dictionary) -> Array:
	var table_names := names()
	var me: String = table_names.get(pid, _net.player_name)
	return [PokerBotPrompt.system_prompt(me, TrusteePilot.PERSONA % me),
		PokerBotPrompt.user_prompt(sit, _net.last_public, table_names, _log)]


func _brain(_pid: int, sit: Dictionary) -> Dictionary:
	return PokerBotBrain.decide(sit, PokerBotBrain.style(0), _rng)   # 内置策略用「稳健」


func _log_label() -> String:
	return "德州托管"


func _tick_chores(delta: float) -> void:
	# 一手结束(演完)后替自己点「开始下一手」;输光、观战、离座时不点
	if _chore_wait < 0.0:
		return
	_chore_wait -= delta
	if _chore_wait > 0.0:
		return
	_chore_wait = -1.0
	var me: int = _net.my_pid()
	for row in _net.last_public.get("players", []):
		if row.get("pid") == me and not TrusteePilot.flag(row.get("left")) \
				and not [PokerRules.STATUS_BUSTED, PokerRules.STATUS_SPECTATING, PokerRules.STATUS_AWAY].has(row.get("status")):
			_send(me, {"kind": PokerRules.NEXT, "amount": 0}, "")
