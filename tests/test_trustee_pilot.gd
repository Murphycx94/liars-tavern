extends GutTest
# 本机玩家的托管(PokerPilot / DdzPilot):用本机 AI 设置或内置策略替自己出手,意图带来源 by 发给房主,
# 房主只认托管的两种来源并标在出手事件上。离线 NetworkManager 当房主,托管的是房主自己(pid 1,意图走本机入口)。


const R := preload("res://src/core/poker/poker_rules.gd")
const HOST := LobbyModel.HOST_ID
const GUEST := 10
const STEP := 0.25
const LONG := 60.0   # 一下推进足够久:演出与「想」都过去


class StubNet:
	extends "res://src/net/network_manager.gd"
	var sent: Array = []

	func _send_to(id: int, method: StringName, args: Array = []) -> void:
		sent.append([id, String(method), args])


class FakeChat:
	extends AiChat
	var asked: Array = []

	func ask(config: Dictionary, system: String, user: String) -> int:
		asked.append({"config": config, "system": system, "user": user})
		return asked.size() + 100


var net: StubNet
var chat: FakeChat
var _acted: Array = []   # 出手事件 [pid, by]
var _rejected: Array = []


func before_each():
	net = StubNet.new()
	add_child_autofree(net)
	for driver: BotDriver in [net.bots, net.ddz_bots, net.poker_pilot, net.ddz_pilot]:
		driver.set_process(false)   # 测试里手动推进
	net.set_ai_config(AiSettings.defaults())
	_acted = []
	_rejected = []
	net.game_events.connect(func(events: Array) -> void:
		for ev in events:
			if NetworkManagerConst.SOURCE_EVENTS.has(ev["type"]):
				_acted.append([ev["pid"], ev.get("by", "")]))
	net.intent_rejected.connect(func(code: String) -> void: _rejected.append(code))


func after_each():
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


class NetworkManagerConst:
	const SOURCE_EVENTS := ["action", "bid", "played", "passed"]


func _open(mode: String, guests: Array) -> void:
	net.is_host = true
	net._session_active = true
	net.game_mode = mode
	net._lobby = LobbyModel.new()
	net._lobby.add_host("房主")
	for id in guests:
		net._lobby.add_member(id, "客%d" % id)
		net._lobby.set_ready(id, true)
	net.start_game()
	_acted = []


func _ai_on(pilot: BotDriver) -> void:
	chat = FakeChat.new()
	pilot._ai = chat
	pilot.add_child(chat)
	net.set_ai_config({AiSettings.KEY_URL: "https://api.example.com/v1", AiSettings.KEY_MODEL: "m",
		AiSettings.KEY_API_KEY: "k", AiSettings.KEY_ENABLED: true})


func _current() -> Variant:
	return net.last_public.get("current_pid")


func _poker_my_turn() -> void:
	# 德州单挑:轮到客人就替他过牌 / 跟注,直到轮到房主
	_open(GameMode.HOLDEM, [GUEST])
	for i in 4:
		if _current() == HOST:
			break
		var legal: Dictionary = net.last_public["actions"]
		net._handle_poker_rpc(GUEST, R.CHECK if legal["can_check"] else R.CALL, 0)
	assert_eq(_current(), HOST)
	_acted = []


# —— 德州 ——

func test_poker_pilot_is_off_until_switched_on():
	_poker_my_turn()
	net.poker_pilot._process(LONG)
	assert_eq(_acted, [], "没开托管不替你出手")
	watch_signals(net.poker_pilot)
	net.poker_pilot.set_enabled(true)
	assert_signal_emitted_with_parameters(net.poker_pilot, "changed", [true])
	net.poker_pilot._process(STEP)
	net.poker_pilot._process(LONG)
	assert_eq(_acted, [[HOST, BotDriver.SOURCE_TRUSTEE]], "内置策略替你出手,标「托管」")


func test_poker_pilot_uses_my_own_ai():
	_poker_my_turn()
	_ai_on(net.poker_pilot)
	net.poker_pilot.set_enabled(true)
	net.poker_pilot._process(STEP)
	assert_eq(chat.asked.size(), 1, "问的是本机的 AI")
	assert_string_contains(chat.asked[0]["system"], "托管")
	assert_string_contains(chat.asked[0]["system"], "房主")
	var legal: Dictionary = net.last_public["actions"]
	net.poker_pilot._on_answered(101, true, '{"action": "%s", "quip": 2}' % ("check" if legal["can_check"] else "call"))
	var quips: Array = []
	net.quip_shown.connect(func(pid: int, index: int) -> void: quips.append([pid, index]))
	net.poker_pilot._process(LONG)
	assert_eq(_acted, [[HOST, BotDriver.SOURCE_TRUSTEE_AI]], "AI 出的标「托管·AI」")
	assert_eq(quips, [], "托管不替玩家说话")


func test_poker_pilot_falls_back_when_my_ai_fails():
	_poker_my_turn()
	_ai_on(net.poker_pilot)
	net.poker_pilot.set_enabled(true)
	net.poker_pilot._process(STEP)
	watch_signals(net.poker_pilot)
	net.poker_pilot._on_answered(101, false, "API Key 不对或没有权限(HTTP 401)")
	net.poker_pilot._process(LONG)
	assert_eq(_acted, [[HOST, BotDriver.SOURCE_TRUSTEE]])
	assert_signal_emitted(net.poker_pilot, "notice")
	var text: String = get_signal_parameters(net.poker_pilot, "notice")[0]
	assert_string_contains(text, "托管这一步")


func test_poker_pilot_clicks_next_after_the_hand():
	_poker_my_turn()
	net.poker_pilot.set_enabled(true)
	net._handle_poker_rpc(HOST, R.FOLD, 0)
	assert_eq(net._session._table.phase(), PokerTable.Phase.IDLE, "一手结束")
	assert_false(net._session._table.is_confirmed(HOST))
	net.poker_pilot._process(LONG)
	assert_true(net._session._table.is_confirmed(HOST), "托管替你点「开始下一手」")


func test_a_new_game_switches_poker_trustee_off():
	_poker_my_turn()
	net.poker_pilot.set_enabled(true)
	net.game_started.emit([])
	assert_false(net.poker_pilot.enabled)


# —— 来源校验 ——

func test_clients_may_only_claim_trustee_sources():
	_open(GameMode.HOLDEM, [GUEST])
	if _current() == HOST:
		net._handle_poker_rpc(HOST, R.CALL, 0)
	assert_eq(_current(), GUEST)
	var legal: Dictionary = net.last_public["actions"]
	var move := R.CHECK if legal["can_check"] else R.CALL
	net.sent = []
	_acted = []
	net._handle_session_rpc(GUEST, {"kind": move, "amount": 0, "by": BotDriver.SOURCE_AI})
	assert_eq(_acted, [], "冒充机器人的来源:拒绝")
	assert_true(net.sent.any(func(s: Array) -> bool: return s[1] == "rpc_intent_rejected"))
	net._handle_session_rpc(GUEST, {"kind": move, "amount": 0, "by": BotDriver.SOURCE_TRUSTEE_AI})
	assert_eq(_acted, [[GUEST, BotDriver.SOURCE_TRUSTEE_AI]], "托管来源:照常出手并标上")


func test_poker_session_accepts_dictionary_intents():
	var session := PokerSession.new(GameMode.HOLDEM)
	assert_eq(session.validate_intent({"kind": R.CALL, "amount": 0}), "")
	assert_eq(session.validate_intent({"kind": R.NEXT}), "")
	assert_eq(session.validate_intent({"kind": R.RAISE, "amount": 60}), "")
	assert_ne(session.validate_intent({"kind": "dance", "amount": 0}), "")
	assert_ne(session.validate_intent({"kind": R.CALL, "amount": -5}), "")
	assert_ne(session.validate_intent({"kind": R.CALL, "amount": 0, "extra": 1}), "")
	assert_ne(session.validate_intent([R.CALL]), "")


# —— 斗地主 ——

func test_ddz_pilot_plays_for_me_only_while_in_trustee():
	_open(GameMode.DOU_DIZHU, [GUEST, GUEST + 1])
	var state: DdzState = net._session.state()
	for i in 3:
		if _current() == HOST:
			break
		net._handle_session_rpc(_current(), {"kind": "bid", "score": 0})
	assert_eq(_current(), HOST, "轮到房主叫分")
	_acted = []
	net.ddz_pilot._process(LONG)
	assert_eq(_acted, [], "没托管不替你出手")
	net.submit_session_intent({"kind": "trustee", "on": true})
	assert_true(state.trustee[HOST])
	net.ddz_pilot._process(STEP)
	net.ddz_pilot._process(LONG)
	assert_eq(_acted.size(), 1)
	assert_eq(_acted[0], [HOST, BotDriver.SOURCE_TRUSTEE], "本机替你叫分,标「托管」(不是房主的托管打法)")


func test_trustee_tags_read_in_both_logs():
	assert_eq(PokerDirector.source_tag(BotDriver.SOURCE_TRUSTEE_AI), "(托管·AI)")
	assert_eq(PokerDirector.source_tag(BotDriver.SOURCE_TRUSTEE), "(托管)")
	assert_eq(DdzDirector._auto_tag({"by": BotDriver.SOURCE_TRUSTEE_AI}), "(托管·AI)")
	assert_eq(DdzDirector._auto_tag({"auto": true}), "(托管)", "房主到点按托管打法代打")
	assert_eq(PokerDirector.source_tag(7), "")


func test_client_animation_estimate():
	assert_almost_eq(TrusteePilot.client_anim({"turn_time_left": 33.5}, 30.0), 3.5, 0.001)
	assert_eq(TrusteePilot.client_anim({"turn_time_left": 12.0}, 30.0), 0.0)
	assert_eq(TrusteePilot.client_anim({"turn_time_left": "x"}, 30.0), 0.0)


# —— 审查后的修复 ——

func test_late_trustee_does_not_wait_for_ai_past_the_turn():
	# 回合只剩 2 秒才打开托管:不问 AI,内置策略马上出手,赶在房主到点之前
	_poker_my_turn()
	_ai_on(net.poker_pilot)
	net.last_public = net.last_public.merged({"turn_time_left": 2.0}, true)
	net.poker_pilot.set_enabled(true)
	net.poker_pilot._process(STEP)
	assert_eq(chat.asked.size(), 0, "来不及等 AI 就不问")
	assert_eq(_acted, [[HOST, BotDriver.SOURCE_TRUSTEE]])


func test_ai_wait_is_capped_by_the_turn_left():
	_poker_my_turn()
	_ai_on(net.poker_pilot)
	net.last_public = net.last_public.merged({"turn_time_left": 10.0}, true)
	net.poker_pilot.set_enabled(true)
	net.poker_pilot._process(STEP)
	assert_eq(chat.asked.size(), 1)
	assert_lte(net.poker_pilot._decision["deadline"], 10.0 - BotDriver.TURN_MARGIN)
	net.poker_pilot._process(10.0 - BotDriver.TURN_MARGIN)
	assert_eq(_acted, [[HOST, BotDriver.SOURCE_TRUSTEE]], "AI 没赶上:到点前内置策略出手")


func test_rejected_trustee_move_is_retried_once_with_a_safe_move():
	_poker_my_turn()
	net.poker_pilot.set_enabled(true)
	net.poker_pilot._process(STEP)
	# 模拟这一步刚出手、还没被房主处理就被拒:把决定停在「已出手」,局面不变
	net.poker_pilot._decision["wait"] = INF
	net.poker_pilot._retry_after_rejection()
	assert_eq(_acted, [[HOST, BotDriver.SOURCE_TRUSTEE]], "改出一定合法的一步")
	net.poker_pilot._retry_after_rejection()
	assert_eq(_acted.size(), 1, "只重试一次 / 已换人就不重试")


func test_poker_pilot_waits_for_this_hands_private_view():
	_poker_my_turn()
	net.poker_pilot.set_enabled(true)
	net.last_private = net.last_private.merged({"hand": -1}, true)
	net.poker_pilot._process(LONG)
	assert_eq(_acted, [], "私有视图还是上一手的:先不出手")


func test_switching_poker_trustee_on_between_hands_still_clicks_next():
	_poker_my_turn()
	net._handle_poker_rpc(HOST, R.FOLD, 0)
	assert_false(net._session._table.is_confirmed(HOST))
	net.poker_pilot.set_enabled(true)
	net.poker_pilot._process(LONG)
	assert_true(net._session._table.is_confirmed(HOST))


func test_ddz_pilot_drops_its_thinking_when_trustee_goes_off():
	_open(GameMode.DOU_DIZHU, [GUEST, GUEST + 1])
	for i in 3:
		if _current() == HOST:
			break
		net._handle_session_rpc(_current(), {"kind": "bid", "score": 0})
	_ai_on(net.ddz_pilot)
	net.submit_session_intent({"kind": "trustee", "on": true})
	net.ddz_pilot._process(STEP)
	assert_false(net.ddz_pilot._decision.is_empty(), "在想")
	net.submit_session_intent({"kind": "trustee", "on": false})
	net.ddz_pilot._process(STEP)
	assert_true(net.ddz_pilot._decision.is_empty(), "关了托管就不想了")
