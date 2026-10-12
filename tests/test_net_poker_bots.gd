extends GutTest
# 德州机器人的房主端接线(离线 NetworkManager):等待厅里添加 / 请走机器人,开局后机器人自己出手、
# 一手结束自己点开始、输光自己再领;接 AI 时按 AI 的回答出手,AI 出错、超时或回答过期时改用内置策略。


const R := preload("res://src/core/poker/poker_rules.gd")
const HOST := LobbyModel.HOST_ID
const STEP := 0.25


class StubNet:
	extends "res://src/net/network_manager.gd"
	var sent: Array = []

	func _send_to(id: int, method: StringName, args: Array = []) -> void:
		sent.append([id, String(method), args])


class FakeChat:
	extends AiChat
	# 不发网络请求:记下问了什么,回答由测试调 PokerBots._on_answered 送回
	var asked: Array = []

	func ask(config: Dictionary, system: String, user: String) -> int:
		asked.append({"config": config, "system": system, "user": user})
		return asked.size() + 100


var net: StubNet
var chat: FakeChat
var _acted: Array = []   # 房主收到的 action 事件的出手者
var _by: Array = []      # 同上,事件里标的来源(没标为 "")


func before_each():
	net = StubNet.new()
	add_child_autofree(net)
	net.is_host = true
	net._session_active = true
	net.game_mode = GameMode.HOLDEM
	net._lobby = LobbyModel.new()
	net._lobby.add_host("房主")
	net.bots.set_config(AiSettings.defaults())
	net.bots.set_process(false)   # 测试里手动推进,不让引擎的帧插进来
	chat = FakeChat.new()
	net.bots._ai = chat
	net.bots.add_child(chat)
	_acted = []
	_by = []
	net.game_events.connect(func(events: Array) -> void:
		for ev in events:
			if ev["type"] == "action":
				_acted.append(ev["pid"])
				_by.append(ev.get("by", "")))


func after_each():
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _ai_on() -> void:
	net.bots.set_config({AiSettings.KEY_URL: "https://api.example.com/v1", AiSettings.KEY_MODEL: "m",
		AiSettings.KEY_API_KEY: "k", AiSettings.KEY_ENABLED: true})


func _current() -> Variant:
	return net.last_public.get("current_pid")


func _tick(seconds: float) -> void:
	# 推进时间:房主演出预算递减、机器人想 / 出手;房主自己能过牌就过牌,否则跟注,一手结束点开始(输光就再领);
	# 要发牌的人都点了就开下一手(代替一手间隔计时器)
	var t := 0.0
	while t < seconds:
		net._process(STEP)
		net.bots._process(STEP)
		var table: PokerTable = net._session._table
		if _current() == HOST:
			var legal: Dictionary = net.last_public["actions"]
			net._handle_poker_rpc(HOST, R.CHECK if legal["can_check"] else R.CALL, 0)
		elif _current() == null and table.phase() == PokerTable.Phase.IDLE:
			if table.player(HOST)["status"] == R.STATUS_BUSTED:
				net._handle_poker_rpc(HOST, R.REBUY, 0)
			elif table.needs_confirm(HOST) and not table.is_confirmed(HOST):
				net._handle_poker_rpc(HOST, R.NEXT, 0)
			if table.all_confirmed() and net._session.next_hand_ready():
				net._on_hand_timer()
		t += STEP


# —— 等待厅 ——

func test_bots_join_ready_with_a_species_and_count_toward_the_cap():
	assert_true(net.add_bot())
	assert_true(net.add_bot())
	var rows := net.lobby_players
	assert_eq(rows.size(), 3)
	var bots := rows.filter(func(p: Dictionary) -> bool: return p["bot"])
	assert_eq(bots.size(), 2)
	for p in bots:
		assert_true(p["ready"])
		assert_lt(p["pid"], 0, "机器人 pid 为负数")
		assert_true(Species.is_valid(p["species"]))
		assert_true(p["name"].begins_with(PokerBots.NAME_PREFIX))
	assert_ne(bots[0]["species"], bots[1]["species"], "不撞脸")
	assert_true(net.can_start(), "房主 + 机器人就能开")
	for i in GameMode.POKER_MAX_PLAYERS:
		net.add_bot()
	assert_eq(net.lobby_players.size(), GameMode.POKER_MAX_PLAYERS, "满员不再加")
	assert_false(net.can_add_bot())


func test_only_poker_hosts_can_add_bots():
	net.game_mode = GameMode.LIARS
	assert_false(net.add_bot())
	net.game_mode = GameMode.HOLDEM
	net.is_host = false
	assert_false(net.add_bot())


func test_kicking_a_bot_sends_nothing():
	net.add_bot()
	var bot: int = net._lobby.bot_ids()[0]
	net.sent = []
	net.kick(bot)
	assert_false(net._lobby.has(bot))
	assert_false(net.sent.any(func(s: Array) -> bool: return s[0] == bot), "机器人没有连接,不发消息")


func test_rematch_keeps_bots_ready():
	net.add_bot()
	net._lobby.reset_ready()
	assert_true(net.lobby_players.filter(func(p): return p["bot"]).all(func(p): return p["ready"]))


func test_meta_says_when_ai_drives_the_bots():
	net.add_bot()
	assert_false(net.lobby_meta["bot_ai"])
	_ai_on()
	net.refresh_bot_meta()
	assert_true(net.lobby_meta["bot_ai"])


# —— 对局 ——

func test_a_table_of_bots_keeps_playing_and_conserves_chips():
	for i in 3:
		net.add_bot()
	net.start_game()
	_tick(240.0)
	var table: PokerTable = net._session._table
	assert_gt(table.hand_number(), 5, "机器人一手接一手地打")
	assert_eq(table.chips_in_play(), table.total_bought_in(), "筹码守恒")
	for pid in net._lobby.bot_ids():
		assert_ne(table.player(pid)["status"], R.STATUS_AWAY, "机器人从不超时挂机")


func test_bots_wait_for_the_animation_before_acting():
	net.add_bot()
	net.start_game()
	if _current() == HOST:
		net._handle_poker_rpc(HOST, R.CALL, 0)
	var bot: Variant = _current()
	assert_true(net.is_bot(bot))
	var anim := 5.0
	net._anim_left = anim   # 客户端还要演 5 秒
	net.bots._process(STEP)
	net.bots._process(anim - STEP)
	assert_false(_acted.has(bot), "演出还没播完,机器人不出手")
	for i in ceili(PokerBots.THINK_MAX / STEP) + 2:
		net.bots._process(STEP)
	assert_true(_acted.has(bot), "演完、想完就出手")


func test_busted_bots_rebuy():
	net.add_bot()
	net.start_game()
	var bot: int = net._lobby.bot_ids()[0]
	net._session._table._players[bot]["stack"] = 0
	net._session._table._players[bot]["status"] = R.STATUS_BUSTED
	net.bots.on_events([{"type": "hand_over"}])
	net._anim_left = 0.0
	net.bots._chore_wait = 0.0
	net._sync_all()
	net.bots._process(STEP)
	assert_eq(net._session._table.player(bot)["buyins"], 2)


func _bot_turn() -> int:
	net.add_bot()
	net.start_game()
	if _current() == HOST:
		net._handle_poker_rpc(HOST, R.CALL, 0)
	net._anim_left = 0.0
	_acted = []
	_by = []
	return _current()


func test_ai_answer_drives_the_bot():
	_ai_on()
	var bot := _bot_turn()
	net.bots._process(STEP)
	assert_eq(chat.asked.size(), 1, "轮到它就问 AI")
	assert_string_contains(chat.asked[0]["system"], net._session.name_of(bot))
	assert_string_contains(chat.asked[0]["user"], "可选:")
	var legal: Dictionary = net.last_public["actions"]
	var action := R.CHECK if legal["can_check"] else R.CALL
	net.bots._on_answered(101, true, '{"action": "%s", "quip": 1}' % action)
	var heard: Array = []
	net.quip_shown.connect(func(pid: int, index: int) -> void: heard.append([pid, index]))
	net.bots._process(PokerBots.THINK_MAX)
	assert_eq(_acted, [bot], "按 AI 的回答出手了")
	assert_eq(_by, [PokerBots.SOURCE_AI], "事件标上 AI,各端日志写「(AI)」")
	assert_eq(heard, [[bot, 1]], "AI 选的快捷对话也说了")


func test_ai_error_falls_back_to_the_brain():
	_ai_on()
	var bot := _bot_turn()
	net.bots._process(STEP)
	watch_signals(net.bots)
	net.bots._on_answered(101, false, "API Key 不对")
	net.bots._process(PokerBots.THINK_MAX)
	assert_eq(_acted, [bot], "内置策略接手")
	assert_eq(_by, [PokerBots.SOURCE_FALLBACK], "事件标上内置策略代打")
	assert_signal_emitted(net.bots, "notice")


func test_ai_timeout_falls_back_and_late_answers_are_ignored():
	_ai_on()
	var bot := _bot_turn()
	net.bots._process(STEP)
	net.bots._process(PokerBots.THINK_MAX)
	assert_eq(_acted, [], "等 AI 回答")
	net.bots._process(PokerBots.AI_WAIT)
	assert_eq(_acted, [bot], "超时改用内置策略")
	net.bots._on_answered(101, true, '{"action": "allin"}')
	net.bots._process(STEP)
	assert_eq(_acted, [bot], "过期的回答不理")


func test_without_ai_actions_carry_no_source():
	var bot := _bot_turn()
	net.bots._process(STEP)
	net.bots._process(PokerBots.THINK_MAX)
	assert_eq(_acted, [bot])
	assert_eq(_by, [""], "没接 AI 不标")


func test_ai_bots_are_known_from_the_roster():
	net.add_bot()
	var bot: int = net._lobby.bot_ids()[0]
	assert_false(net.is_ai_bot(bot), "没接 AI")
	_ai_on()
	net.refresh_bot_meta()
	assert_true(net.is_ai_bot(bot))
	assert_false(net.is_ai_bot(HOST), "真人不是")
	net.lobby_meta = net.lobby_meta.merged({"bot_ai": "yes"}, true)
	assert_false(net.is_ai_bot(bot), "meta 类型不对当否")


func test_ai_nameplate_drops_the_prefix_for_the_tag():
	assert_eq(PokerNameplate.shown_name("机器人·阿福", true), "阿福")
	assert_eq(PokerNameplate.shown_name("机器人·阿福", false), "机器人·阿福")
	var plate: PokerNameplate = autofree(PokerNameplate.new("机器人·阿福", true))
	assert_not_null(plate.find_child("AiTag", true, false))
	var plain: PokerNameplate = autofree(PokerNameplate.new("老王"))
	assert_null(plain.find_child("AiTag", true, false))
