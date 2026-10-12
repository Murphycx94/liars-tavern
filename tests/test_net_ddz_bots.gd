extends GutTest
# 斗地主机器人的房主端接线(离线 NetworkManager):等待厅里添加机器人(凑满 3 人就能开),开局后机器人自己叫分、出牌,
# 一手接一手地打、从不超时进托管;接 AI 时按 AI 的回答出手,AI 出错、答错、超时或回答过期时改用内置策略。


const HOST := LobbyModel.HOST_ID
const STEP := 0.25


class StubNet:
	extends "res://src/net/network_manager.gd"
	var sent: Array = []

	func _send_to(id: int, method: StringName, args: Array = []) -> void:
		sent.append([id, String(method), args])


class FakeChat:
	extends AiChat
	# 不发网络请求:记下问了什么,回答由测试调 DdzBots._on_answered 送回
	var asked: Array = []

	func ask(config: Dictionary, system: String, user: String) -> int:
		asked.append({"config": config, "system": system, "user": user})
		return asked.size() + 100


var net: StubNet
var chat: FakeChat
var _acted: Array = []   # 房主收到的 bid / played / passed 事件:[pid, type, timed_out 或 auto]
var _by: Array = []      # 同上,事件里标的来源(没标为 "")


func before_each():
	net = StubNet.new()
	add_child_autofree(net)
	net.is_host = true
	net._session_active = true
	net.game_mode = GameMode.DOU_DIZHU
	net._lobby = LobbyModel.new()
	net._lobby.add_host("房主")
	net.set_bot_ai_config(AiSettings.defaults())
	net.ddz_bots.set_process(false)   # 测试里手动推进,不让引擎的帧插进来
	net.bots.set_process(false)
	chat = FakeChat.new()
	net.ddz_bots._ai = chat
	net.ddz_bots.add_child(chat)
	_acted = []
	_by = []
	net.game_events.connect(func(events: Array) -> void:
		for ev in events:
			if ["bid", "played", "passed"].has(ev["type"]):
				_acted.append([ev["pid"], ev["type"], ev.get("timed_out", false) or ev.get("auto", false)])
				_by.append(ev.get("by", "")))


func after_each():
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _ai_on() -> void:
	net.set_bot_ai_config({AiSettings.KEY_URL: "https://api.example.com/v1", AiSettings.KEY_MODEL: "m",
		AiSettings.KEY_API_KEY: "k", AiSettings.KEY_ENABLED: true})


func _state() -> DdzState:
	return net._session.state()


func _current() -> Variant:
	return net.last_public.get("current_pid")


func _host_acts() -> void:
	# 房主照托管打法出手(经真实的意图入口)
	var s := _state()
	var hand := s.hand_of(HOST)
	if s.phase == DdzState.Phase.BIDDING:
		net._handle_session_rpc(HOST, {"kind": "bid", "score": 0})
	elif s.lead.is_empty():
		net._handle_session_rpc(HOST, {"kind": "play",
			"cards": DdzState.indices_of(hand, DdzHand.legal_plays(hand, {})[0]["cards"])})
	else:
		net._handle_session_rpc(HOST, {"kind": "pass"})


func _tick(seconds: float) -> void:
	# 推进时间:房主演出预算递减、机器人想 / 出手;轮到房主就出;一手打完立即开下一手(代替一手间隔计时器)
	var t := 0.0
	while t < seconds:
		net._process(STEP)
		net.ddz_bots._process(STEP)
		if _current() == HOST:
			_host_acts()
		elif net._session.next_hand_ready():
			net._on_hand_timer()
		t += STEP


func _bot_turn() -> int:
	# 两个机器人开局,推进到轮到某个机器人(演出已播完)
	net.add_bot()
	net.add_bot()
	net.start_game()
	if _current() == HOST:
		_host_acts()
	net._anim_left = 0.0
	_acted = []
	_by = []
	return _current()


# —— 等待厅 ——

func test_two_bots_fill_the_table_and_the_host_can_start():
	assert_true(net.can_add_bot())
	assert_true(net.add_bot())
	assert_false(net.can_start(), "斗地主要正好 3 人")
	assert_true(net.add_bot())
	assert_true(net.can_start())
	assert_false(net.add_bot(), "满 3 人不再加")
	for p in net.lobby_players.filter(func(p: Dictionary) -> bool: return p["bot"]):
		assert_true(p["ready"])
		assert_true(p["name"].begins_with(BotDriver.NAME_PREFIX))


func test_ai_config_reaches_both_drivers_and_the_lobby_meta():
	net.add_bot()
	_ai_on()
	assert_true(net.ddz_bots.ai_active())
	assert_true(net.bots.ai_active())
	assert_true(net.lobby_meta["bot_ai"])


func test_ai_bots_get_the_ai_tag_on_their_nameplate():
	net.add_bot()
	var bot: int = net._lobby.bot_ids()[0]
	assert_false(net.is_ai_bot(bot), "没接 AI")
	_ai_on()
	assert_true(net.is_ai_bot(bot))
	var plate: DdzNameplate = autofree(DdzNameplate.new(net._lobby.names()[bot], net.is_ai_bot(bot)))
	assert_not_null(plate.find_child("AiTag", true, false), "铭牌标「AI」")
	assert_false(plate._name.text.begins_with(BotDriver.NAME_PREFIX), "「机器人·」前缀让位给 AI 小标")
	var plain: DdzNameplate = autofree(DdzNameplate.new("老王"))
	assert_null(plain.find_child("AiTag", true, false), "真人没有")


# —— 对局 ——

func test_host_and_two_bots_play_many_hands():
	net.add_bot()
	net.add_bot()
	net.start_game()
	_tick(600.0)
	var s := _state()
	assert_gt(s.hand_number, 3, "一手接一手地打")
	assert_eq(s.card_count(), DdzHand.CARD_COUNT)
	var total := 0
	for pid in s.seat_order:
		total += s.scores[pid]
	assert_eq(total, 0, "分数守恒")
	var bot_moves := _acted.filter(func(a: Array) -> bool: return net.is_bot(a[0]))
	assert_gt(bot_moves.size(), 20)
	assert_true(bot_moves.all(func(a: Array) -> bool: return not a[2]), "机器人从不超时、不被托管代打")
	assert_true(_by.all(func(b: String) -> bool: return b == ""), "没接 AI 时不标来源")
	for pid in net._lobby.bot_ids():
		assert_false(s.trustee[pid])


func test_bots_wait_for_the_animation_before_acting():
	var bot := _bot_turn()
	assert_true(net.is_bot(bot))
	var anim := 5.0
	net._anim_left = anim
	net.ddz_bots._process(STEP)
	net.ddz_bots._process(anim - STEP)
	assert_eq(_acted, [], "演出还没播完,机器人不出手")
	for i in ceili(BotDriver.THINK_MAX / STEP) + 2:
		net.ddz_bots._process(STEP)
	assert_false(_acted.is_empty())
	assert_eq(_acted[0][0], bot, "演完、想完就出手(之后下一个机器人也可能接着出)")


func test_a_bot_in_trustee_turns_it_off():
	var bot := _bot_turn()
	net.bot_intent(bot, {"kind": "trustee", "on": true})
	assert_true(_state().trustee[bot])
	net.ddz_bots._process(STEP)
	assert_false(_state().trustee[bot], "机器人自己取消托管")


# —— AI ——

func test_ai_answer_drives_the_bid():
	_ai_on()
	var bot := _bot_turn()
	net.ddz_bots._process(STEP)
	assert_eq(chat.asked.size(), 1, "轮到它就问 AI")
	assert_string_contains(chat.asked[0]["system"], net._session.name_of(bot))
	assert_string_contains(chat.asked[0]["user"], "可叫:")
	var top: int = _state().bid_options(bot).max()
	var heard: Array = []
	net.quip_shown.connect(func(pid: int, index: int) -> void: heard.append([pid, index]))
	net.ddz_bots._on_answered(101, true, '{"action": "bid", "score": %d, "quip": 2}' % top)
	net.ddz_bots._process(BotDriver.THINK_MAX)
	assert_eq(_acted, [[bot, "bid", false]], "按 AI 的回答叫分")
	assert_eq(_state().bids[-1], {"pid": bot, "score": top})
	assert_eq(heard, [[bot, 2]], "AI 选的快捷对话也说了")
	assert_eq(_by, [BotDriver.SOURCE_AI], "AI 出的这一步标上来源(记录里写「(AI)」)")
	var sent_events: Array = net.sent.filter(func(s: Array) -> bool: return s[1] == "rpc_game_events")
	assert_true(sent_events[-1][2][0].any(func(ev: Dictionary) -> bool: return ev.get("by") == BotDriver.SOURCE_AI), "发给客人的事件也带标记")


func test_ai_answer_drives_a_play():
	_ai_on()
	net.add_bot()
	net.add_bot()
	net.start_game()
	var s := _state()
	var bot: int = net._lobby.bot_ids()[0]
	# 直接进出牌阶段,机器人当地主自由出牌
	var hands := {HOST: [DdzHand.make(1, 0), DdzHand.make(2, 0)], bot: [DdzHand.make(0, 0), DdzHand.make(0, 1),
		DdzHand.make(9, 0)]}
	var other: int = net._lobby.bot_ids()[1]
	hands[other] = [DdzHand.make(3, 0), DdzHand.make(4, 0)]
	preload("res://tests/ddz_helpers.gd").rig_play(s, hands, bot, bot)
	net._sync_all()
	net.ddz_bots.on_events([{"type": "turn", "pid": bot}])
	net._anim_left = 0.0
	_acted = []
	_by = []
	net.ddz_bots._process(STEP)
	assert_eq(chat.asked.size(), 1)
	assert_string_contains(chat.asked[0]["user"], "你的手牌(3 张):3 3 Q")
	net.ddz_bots._on_answered(101, true, '{"action": "play", "cards": ["3", "3"]}')
	net.ddz_bots._process(BotDriver.THINK_MAX)
	assert_eq(_acted, [[bot, "played", false]])
	assert_eq(_by, [BotDriver.SOURCE_AI])
	assert_eq(s.hand_of(bot), [DdzHand.make(9, 0)], "出了一对 3")


func test_ai_error_falls_back_to_the_brain():
	_ai_on()
	var bot := _bot_turn()
	net.ddz_bots._process(STEP)
	watch_signals(net.ddz_bots)
	net.ddz_bots._on_answered(101, false, "API Key 不对")
	net.ddz_bots._process(BotDriver.THINK_MAX)
	assert_eq(_acted.size(), 1)
	assert_eq(_acted[0][0], bot, "内置策略接手")
	assert_eq(_by, [BotDriver.SOURCE_FALLBACK], "AI 出错、内置策略代打的标「(内置策略)」")
	assert_signal_emitted(net.ddz_bots, "notice")


func test_ai_illegal_answer_falls_back_to_the_brain():
	_ai_on()
	var bot := _bot_turn()
	net.ddz_bots._process(STEP)
	watch_signals(net.ddz_bots)
	net.ddz_bots._on_answered(101, true, '{"action": "play", "cards": ["3"]}')
	net.ddz_bots._process(BotDriver.THINK_MAX)
	assert_eq(_acted.size(), 1, "叫分阶段出牌判无效,内置策略叫分")
	assert_eq(_acted[0], [bot, "bid", false])
	assert_eq(_by, [BotDriver.SOURCE_FALLBACK])
	assert_signal_emitted(net.ddz_bots, "notice")


func test_ai_timeout_falls_back_and_late_answers_are_ignored():
	_ai_on()
	var bot := _bot_turn()
	net.ddz_bots._process(STEP)
	net.ddz_bots._process(BotDriver.THINK_MAX)
	assert_eq(_acted, [], "等 AI 回答")
	net.ddz_bots._process(DdzBots.AI_WAIT_BID)
	assert_eq(_acted.size(), 1)
	assert_eq(_acted[0][0], bot, "超时改用内置策略")
	assert_lt(DdzBots.AI_WAIT_BID, DouDizhuSession.BID_TIMEOUT, "叫分限时之内就出手")
	net.ddz_bots._on_answered(101, true, '{"action": "bid", "score": 3}')
	net.ddz_bots._process(STEP)
	assert_eq(_acted.size(), 1, "过期的回答不理")


func test_poker_driver_ignores_dou_dizhu_tables():
	var bot := _bot_turn()
	net.bots._process(BotDriver.THINK_MAX + 1.0)
	assert_eq(_acted, [], "德州机器人不碰斗地主")
	assert_eq(_current(), bot)
