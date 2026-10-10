extends GutTest
# 炸弹猫牌桌整体流程(无头,加速演出):真实的 BombCatScreen + BombCatDirector + BombCatCards + HUD,
# 背后是一个真的 BombCatSession(不走网络:牌桌的 intent_sink 直接交给会话,每批按房主的顺序先发事件、再发公共 / 私有视图)。
# 自己由 BombCatBot 走真实的界面入口出手,别人按会话局面随机出合法的牌,卡住时按房主的计时器到点代打;
# 一直打到 match_over:断言没有脚本错误、3D 牌数与视图一致、结算面板出来、名次与会话一致。


const ScreenScript := preload("res://src/ui/bomb_cat/bomb_cat_screen.gd")
const ME := 1
const SPEED := 16.0
const MAX_STEPS := 900
const MAX_WAIT := 30.0
const TIMEOUT_AFTER := 0.3   # 真实秒:没人出手就当计时器到点


class StubTavern:
	extends Node
	var camera_rig: CameraRig

	func kick_lamp(_strength: float) -> void:
		pass


class FakeBanter:
	extends "res://src/net/banter_net.gd"
	var spoken: Array = []

	func in_room() -> bool:
		return true

	func say(phrase_id: int) -> bool:
		spoken.append(phrase_id)
		return true


class StubApp:
	extends Node
	var banter_view: BanterView = null
	var world: TableWorld
	var labels: WorldLabels
	var tavern: StubTavern
	var toasts: Array = []
	var modes: Array = []

	func apply_table_mode(mode: String) -> void:
		modes.append(mode)
		world.configure_table(SeatLayout.table_radius_for(mode))

	func toast(text: String, _color := Color.WHITE) -> void:
		toasts.append(text)

	func show_rules() -> void:
		pass

	func is_rules_open() -> bool:
		return false

	func is_modal_open() -> bool:
		return false


var app: StubApp
var screen: Node
var session: BombCatSession
var rng := RandomNumberGenerator.new()
var saved := {}
var bot: BombCatBot
var rejected: Array = []
var accepted: Array = []   # 自己被接受的意图(kind)


func before_each():
	saved = {"seats": Net.seats, "pub": Net.last_public, "priv": Net.last_private, "mode": Net.game_mode, "scale": Engine.time_scale}
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Engine.time_scale = SPEED
	app = StubApp.new()
	add_child_autofree(app)
	app.labels = WorldLabels.new(null)
	app.add_child(app.labels)
	app.tavern = StubTavern.new()
	app.tavern.camera_rig = CameraRig.new()
	app.tavern.add_child(app.tavern.camera_rig)
	app.add_child(app.tavern)
	app.world = TableWorld.new(null)
	app.add_child(app.world)
	Net.game_mode = GameMode.BOMB_CAT
	Net.last_public = {}
	Net.last_private = {}
	rejected = []
	accepted = []


func after_each():
	Net.seats = saved["seats"]
	Net.last_public = saved["pub"]
	Net.last_private = saved["priv"]
	Net.game_mode = saved["mode"]
	Engine.time_scale = saved["scale"]
	BombCatFaces.clear()


func _open(pids: Array, seed_value: int) -> void:
	rng.seed = seed_value
	bot = BombCatBot.new(seed_value + 1)
	var names := {}
	for pid in pids:
		names[pid] = "P%d" % pid
	Net.seats = pids.map(func(pid): return {"pid": pid, "name": names[pid], "species": (pid - 1) % Species.count()})
	session = BombCatSession.new()
	var start_rng := RandomNumberGenerator.new()
	start_rng.seed = seed_value
	var events := session.start(pids, names, start_rng)
	screen = ScreenScript.new(app)
	screen.intent_sink = _on_intent
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(screen)
	_send(events)


func _send(events: Array) -> void:
	# 同房主的顺序:先事件,再公共视图,再私有视图
	screen._on_events(events)
	screen._on_public(session.public_view(10.0))
	screen._on_private(session.private_view(ME))


func _on_intent(intent: Dictionary) -> void:
	var result := session.handle_intent(ME, intent)
	if result["ok"]:
		accepted.append(intent["kind"])
		_send(result["events"])
	else:
		rejected.append([intent, result["error"]])
		screen._on_rejected(result["error"])


func _idle() -> bool:
	return screen._intro_done and not screen.animating


func _others_step() -> bool:
	# 别人(会话局面里)该出手的就出手:窗口里偶尔不行、给牌、塞回、自由行动出牌或摸牌
	var s := session.state()
	match s.step:
		BombCatState.Step.TURN:
			if s.current_pid == ME:
				return false
			var hand: Array = s.hands[s.current_pid]
			var plays := BombCatBot.legal_plays(hand)
			if not plays.is_empty() and rng.randf() < 0.45:
				var cards: Array = plays[rng.randi_range(0, plays.size() - 1)]
				var intent := {"kind": "play", "cards": cards}
				var kind := BombCatState.combo_kind(cards.map(func(i: int): return hand[i]))
				if BombCatScreenState.needs_target(kind):
					var targets := s.alive_pids().filter(func(t: int) -> bool: return t != s.current_pid and not s.hands[t].is_empty())
					if targets.is_empty():
						return _apply(s.current_pid, {"kind": "draw"})
					intent["target"] = targets[rng.randi_range(0, targets.size() - 1)]
				if kind == BombCatState.KIND_TRIPLE:
					intent["named"] = BombCatCard.DEFUSE
				return _apply(s.current_pid, intent)
			return _apply(s.current_pid, {"kind": "draw"})
		BombCatState.Step.WINDOW:
			var nopers := s.alive_pids().filter(func(pid: int) -> bool: return pid != ME and pid != s.window["pid"] and s.hands[pid].has(BombCatCard.NOPE))
			if not nopers.is_empty() and rng.randf() < 0.25:
				return _apply(nopers[0], {"kind": "nope"})
			return false
		BombCatState.Step.REINSERT:
			if s.current_pid == ME:
				return false
			return _apply(s.current_pid, {"kind": "reinsert", "pos": rng.randi_range(0, s.deck.size())})
		BombCatState.Step.GIVE:
			var giver: int = s.give_request["from"]
			if giver == ME:
				return false
			return _apply(giver, {"kind": "give", "index": rng.randi_range(0, s.hands[giver].size() - 1)})
	return false


func _apply(pid: int, intent: Dictionary) -> bool:
	var result := session.handle_intent(pid, intent)
	assert_true(result["ok"], "别人的合法意图被拒:%s %s %s" % [pid, intent, result.get("error")])
	if result["ok"]:
		_send(result["events"])
	return result["ok"]


func _play_to_the_end() -> void:
	var idle_for := 0.0
	var steps := 0
	while not session.is_over() and steps < MAX_STEPS:
		steps += 1
		await wait_until(_idle, MAX_WAIT, "演出播完")
		if session.is_over():
			break
		var acted := false
		if bot.act(screen):
			acted = true
		elif _others_step():
			acted = true
		if acted:
			idle_for = 0.0
			await get_tree().process_frame
			continue
		await get_tree().create_timer(0.1 * SPEED).timeout
		idle_for += 0.1
		if idle_for >= TIMEOUT_AFTER:
			idle_for = 0.0
			var result := session.on_turn_timeout()
			if result["ok"]:
				_send(result["events"])
	assert_true(session.is_over(), "一局要能打完")
	await wait_until(func(): return screen.settlement() != null, MAX_WAIT, "结算面板")


func _check_table() -> void:
	# 3D 牌与视图一致:各家牌扇张数 = hand_count,自己的牌面 = 私有手牌
	var pub: Dictionary = session.public_view(0.0)
	for row in pub["players"]:
		var want: int = row["hand_count"] if row["alive"] else 0
		if app.world.patrons.has(row["pid"]):
			assert_eq(screen.cards.held_count(row["pid"]), want, "P%d 的牌扇张数" % row["pid"])
	assert_eq(screen.cards.my_ids(), session.private_view(ME)["hand"], "自己的牌扇")
	assert_eq(screen.hud.strip.ids(), session.private_view(ME)["hand"], "2D 手牌条")
	assert_eq(screen.cards.deck_count, pub["deck_count"], "牌堆张数")


func test_a_whole_three_player_match_to_settlement():
	_open([1, 2, 3], 11)
	assert_eq(app.modes, [GameMode.BOMB_CAT])
	assert_almost_eq(app.world.table_radius, SeatLayout.TABLE_RADIUS, 0.001, "3 人用骗子酒馆的桌子")
	await wait_until(_idle, MAX_WAIT, "开局发牌")
	_check_table()
	await _play_to_the_end()
	var settlement: BombCatSettlement = screen.settlement()
	assert_not_null(settlement)
	var ranking: Array = screen.state.ranking_rows().map(func(r: Dictionary) -> int: return r["pid"])
	assert_eq(ranking, [session.state().winner_pid] + _reversed(session.state().out_order), "名次 = 胜者 + 出局顺序倒排")
	# 结算庆祝(规格 2026-10-09):胜者跳舞,炸飞的人倒着(只抽手、不鼓掌)
	assert_true(app.world.is_celebrating(), "match_over 开演庆祝")
	assert_true(app.world.patrons[session.state().winner_pid].is_dancing(), "胜者跳舞")
	for pid in session.state().out_order:
		if app.world.patrons.has(pid):
			assert_false(app.world.patrons[pid].alive)
			assert_ne(app.world.patrons[pid].dance_routine(), PatronDance.CLAP, "炸飞的 %d 不鼓掌" % pid)
	screen.get_parent().remove_child(screen)
	await get_tree().process_frame
	assert_false(app.world.is_celebrating(), "退场收起庆祝")
	add_child(screen)   # 放回去,交给 autofree 释放
	assert_eq(rejected, [], "自己的意图都按规则出,不该被拒")
	assert_gte(accepted.count("draw") + accepted.count("play"), 3, "自己(机器人走界面入口)真的出过手:%s" % [accepted])


func test_a_six_player_table_uses_the_big_table_and_survives_a_few_rounds():
	_open([1, 2, 3, 4, 5, 6], 23)
	assert_almost_eq(app.world.table_radius, SeatLayout.POKER_TABLE_RADIUS, 0.001, "6 人换大桌")
	await wait_until(_idle, MAX_WAIT, "开局发牌")
	_check_table()
	assert_eq(screen.cards.held_count(2), BombCatDeck.HAND_SIZE + 1, "开局每人 5 张(4 张 + 1 张拆弹)")
	await _play_to_the_end()
	assert_not_null(screen.settlement())


func test_exit_tears_down_the_bomb_cat_nodes():
	_open([1, 2], 5)
	await wait_until(_idle, MAX_WAIT, "开局发牌")
	assert_gt(app.world.poker_root.get_child_count(), 0)
	screen.get_parent().remove_child(screen)
	await get_tree().process_frame
	assert_eq(app.world.poker_root.get_child_count(), 0, "退场拆掉炸弹猫的 3D 节点")
	add_child(screen)   # 放回去,交给 autofree 释放


func test_quick_chat_panel_takes_number_keys_at_the_table():
	# 真的 BanterView 压在牌桌上:面板开着时数字键说话、不选牌;关着时数字键选牌
	_open([1, 2], 7)
	await wait_until(_idle, MAX_WAIT, "开局发牌")
	var banter: FakeBanter = autofree(FakeBanter.new())
	var view := BanterView.new(app, banter)
	app.banter_view = view
	add_child_autofree(view)
	view.set_process(false)
	view.visible = true
	view.toggle_panel()
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	get_viewport().push_input(key)
	assert_eq(banter.spoken, [1], "面板开着:2 说第 2 句")
	assert_eq(screen.selected_indices(), [], "也没有选第 2 张牌")
	assert_false(view.is_panel_open(), "说完自动关上")
	get_viewport().push_input(key)
	assert_eq(screen.selected_indices(), [1], "面板关着:2 选第 2 张牌")


func test_quip_menu_works_at_the_bomb_cat_table():
	# 九宫格快捷对话(T / 右上「对话」,同骗子酒馆):开着时数字键选一句、不选牌,Esc 只收起九宫格;
	# 对手说的冒在他头顶,自己说的弹在出牌按钮行上方;都记一行日志
	_open([1, 2], 9)
	await wait_until(_idle, MAX_WAIT, "开局发牌")
	assert_true(screen.quips is QuipController)
	screen.hud.quip_pressed.emit()
	assert_true(screen.quips.menu.is_open(), "右上「对话」按钮打开九宫格")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	get_viewport().push_input(esc)
	assert_false(screen.quips.menu.is_open(), "Esc 收起九宫格(没有落到「离开牌桌」)")
	var t := InputEventKey.new()
	t.keycode = KEY_T
	t.pressed = true
	get_viewport().push_input(t)
	assert_true(screen.quips.menu.is_open(), "T 打开九宫格")
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	get_viewport().push_input(key)
	assert_eq(screen.selected_indices(), [], "九宫格开着:2 不选牌")
	assert_false(screen.quips.menu.is_open(), "选了一句就收起")
	Net.quip_shown.emit(2, 1)
	assert_not_null(app.labels.get_node_for(QuipController.KEY_PREFIX % 2), "对手头顶冒气泡")
	Net.quip_shown.emit(ME, 0)
	assert_eq(screen.hud._bubble_anchor.get_child_count(), 1, "自己说的弹在出牌按钮行上方")
	var lines: Array = screen.hud._log_box.get_children().map(func(l: Label) -> String: return l.text)
	assert_has(lines, "P2:" + Quips.LINES[1])
	assert_has(lines, "P1:" + Quips.LINES[0])


static func _reversed(items: Array) -> Array:
	var out := items.duplicate()
	out.reverse()
	return out


# —— 道具效果(2026-10-10):导演的事件 → 效果,演完全部释放;隐藏信息;整局之后不留节点 ——

func _fx_drained() -> bool:
	return screen.fx3d.active_count() == 0


func _play_events(events: Array) -> void:
	for ev in events:
		await screen.director.play(ev)


func test_each_card_effect_spawns_its_fx_and_frees_it():
	_open([1, 2, 3], 7)
	await wait_until(_idle, MAX_WAIT, "开局发牌")
	var kinds := []
	screen.fx3d.spawned.connect(func(kind: String): kinds.append(kind))
	await _play_events([{"type": "effect", "kind": "skip", "pid": 2}])
	assert_has(kinds, "skip", "溜了:侧身溜走 + 小脚印")
	kinds.clear()
	await _play_events([{"type": "effect", "kind": "pass_turns", "pid": 2, "to": 3, "turns": 2}])
	assert_has(kinds, "pass_turns", "甩锅:平底锅")
	assert_eq(screen.fx3d.badge_pid(), 3, "×N 徽章挂在被甩锅的人头上")
	assert_eq(screen.fx3d.badge_text(), "×2")
	kinds.clear()
	await _play_events([{"type": "turn_passed", "pid": 3, "turns": 2}])
	assert_has(kinds, "paw_trail", "轮转:爪印跑向下一位")
	assert_eq(screen.fx3d.badge_text(), "×2")
	await _play_events([{"type": "turn_passed", "pid": 3, "turns": 1}])
	assert_null(screen.fx3d.badge_pid(), "只剩一回合:徽章收起")
	kinds.clear()
	await _play_events([{"type": "effect", "kind": "peek", "pid": 2, "count": 3}])
	assert_has(kinds, "peek", "偷看:放大镜")
	kinds.clear()
	await _play_events([{"type": "effect", "kind": "shuffle", "pid": 2}])
	assert_has(kinds, "shuffle", "洗牌:龙卷风星星")
	kinds.clear()
	await _play_events([{"type": "give_requested", "pid": 2, "to": 3, "timeout": 15.0}])
	assert_has(kinds, "beg", "讨要:狗狗眼 + 爱心")
	kinds.clear()
	await _play_events([{"type": "effect", "kind": "beg", "pid": 3, "from": 2, "to": 3, "got": true}])
	assert_has(kinds, "trail", "讨要:蝴蝶结拖尾")
	assert_has(kinds, "heart_pop", "讨要:落手时爱心「啵」")
	kinds.clear()
	await _play_events([{"type": "played", "pid": 2, "cards": ["snack_fish", "snack_fish"], "kind": "pair", "target": 3, "named": "",
		"window": 3.0}, {"type": "window_resolved", "pid": 2, "kind": "pair", "effective": true, "nopes": 0, "aborted": false},
		{"type": "effect", "kind": "steal", "pid": 2, "from": 3, "to": 2, "got": true}])
	assert_has(kinds, "snack", "对子:零食蹦到桌上")
	assert_has(kinds, "trail", "对子:金光拖尾")
	kinds.clear()
	await _play_events([{"type": "played", "pid": 3, "cards": ["snack_yarn", "snack_yarn", "snack_yarn"], "kind": "triple", "target": 2,
		"named": "defuse", "window": 3.0}])
	assert_has(kinds, "spotlight", "三条:聚光灯 + 「?」气泡")
	kinds.clear()
	await _play_events([{"type": "noped", "pid": 2, "depth": 1, "window": 3.0}, {"type": "noped", "pid": 3, "depth": 2, "window": 3.0}])
	assert_eq(kinds.count("nope"), 2, "连环不行!:两枚印章")
	assert_has(kinds, "stamp_mark", "印章盖下去留下印子")
	kinds.clear()
	await _play_events([{"type": "window_resolved", "pid": 3, "kind": "triple", "effective": true, "nopes": 2, "aborted": false},
		{"type": "effect", "kind": "request", "pid": 3, "from": 2, "to": 3, "named": "defuse", "got": true}])
	assert_has(kinds, "snack", "三条:零食蹦到桌上")
	kinds.clear()
	await _play_events([{"type": "bomb_drawn", "pid": 2}])
	assert_has(kinds, "bomb", "摸到炸弹:炸弹猫弹出来")
	assert_not_null(screen.fx3d.kitty())
	kinds.clear()
	await _play_events([{"type": "defused", "pid": 2, "deck_count": 10, "timeout": 15.0}])
	assert_has(kinds, "defuse", "拆弹:大剪刀咔嚓")
	await _play_events([{"type": "reinserted", "pid": 2, "deck_count": 11}])
	assert_null(screen.fx3d.kitty(), "塞回:炸弹猫溜回牌堆")
	kinds.clear()
	await _play_events([{"type": "bomb_drawn", "pid": 3}, {"type": "exploded", "pid": 3, "discarded": 2}])
	assert_has(kinds, "kaboom", "爆炸:卡通烟云")
	assert_has(kinds, "tuft", "爆炸:炸焦的头发")
	await wait_until(_fx_drained, MAX_WAIT, "效果全部演完释放")
	assert_eq(screen.fx3d.active_count(), 0, "没有留下效果节点")


func test_peek_fan_faces_only_for_the_peeker():
	_open([1, 2, 3], 9)
	await wait_until(_idle, MAX_WAIT, "开局发牌")
	# 别人偷看:浮起来的三张都是牌背
	screen.director.play({"type": "effect", "kind": "peek", "pid": 2, "count": 3})
	await wait_until(func(): return screen.cards.rising_nodes().size() == 3, MAX_WAIT, "三张浮起来")
	for card in screen.cards.rising_nodes():
		assert_true(card.is_back(), "别人偷看时看不到牌面")
	await wait_until(func(): return screen.cards.rising_nodes().is_empty(), MAX_WAIT, "落回牌堆")
	# 自己偷看:私有视图里的三张
	var peek: Array = session.state().deck.slice(0, 3)
	var view := session.private_view(ME)
	view["peek"] = peek
	view["peek_seq"] = 999
	screen._on_private(view)
	screen.director.play({"type": "effect", "kind": "peek", "pid": ME, "count": 3})
	await wait_until(func(): return screen.cards.rising_nodes().size() == 3, MAX_WAIT, "三张浮起来")
	assert_eq(screen.cards.rising_nodes().map(func(c): return c.card_id), peek, "自己偷看看得到牌面")


func test_no_fx_left_after_a_whole_match():
	_open([1, 2, 3], 31)
	await wait_until(_idle, MAX_WAIT, "开局发牌")
	await _play_to_the_end()
	await wait_until(_fx_drained, MAX_WAIT, "整局之后效果全部释放")
	assert_eq(screen.fx3d.active_count(), 0, "整局打完不留效果节点(徽章、印子、炸弹猫、聚光灯都收了)")
	assert_true(screen.cards.rising_nodes().is_empty())
	assert_true(screen.cards.tornado_nodes().is_empty())
