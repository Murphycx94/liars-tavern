extends GutTest
# 吹牛骰子牌桌整体流程(无头,加速演出):真实的 LiarsDiceScreen + LiarsDiceDirector + LiarsDiceCups + HUD,
# 背后是一个真的 LiarsDiceSession(不走网络:牌桌的 intent_sink 直接交给会话,每批按房主的顺序先发事件、再发公共 / 私有视图)。
# 自己由 LiarsDiceBot 走真实的出价器入口出手,别人按会话局面随机喊价或「开!」,卡住时按房主的计时器到点代打;
# 一直打到 match_over:断言没有被拒的意图、开盅之前桌上没有别人的骰子、私有骰子按轮次缓存(开盅演的是这一轮的点数,
# 下一轮的私有视图已经先到了)、结算面板出来、名次与会话一致、胜者跳舞。另测快捷键、面板抢数字键、被拒 toast、退场拆台。


const ScreenScript := preload("res://src/ui/liars_dice/liars_dice_screen.gd")
const ME := 1
const SPEED := 16.0
const MAX_STEPS := 600
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
var session: LiarsDiceSession
var rng := RandomNumberGenerator.new()
var saved := {}
var bot: LiarsDiceBot
var rejected: Array = []
var accepted: Array = []    # 自己被接受的意图(kind)
var leaks: Array = []       # 开盅之前桌上出现别人的骰子
var reveals_checked := 0    # 核对过「开盅演的是这一轮的点数、下一轮的私有骰子已经先到」的次数


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
	Net.game_mode = GameMode.LIARS_DICE
	Net.last_public = {}
	Net.last_private = {}
	rejected = []
	accepted = []
	leaks = []
	reveals_checked = 0


func after_each():
	Net.seats = saved["seats"]
	Net.last_public = saved["pub"]
	Net.last_private = saved["priv"]
	Net.game_mode = saved["mode"]
	Engine.time_scale = saved["scale"]


func _open(pids: Array, seed_value: int) -> void:
	rng.seed = seed_value
	bot = LiarsDiceBot.new(seed_value + 1)
	var names := {}
	for pid in pids:
		names[pid] = "P%d" % pid
	Net.seats = pids.map(func(pid): return {"pid": pid, "name": names[pid], "species": (pid - 1) % Species.count()})
	session = LiarsDiceSession.new()
	var start_rng := RandomNumberGenerator.new()
	start_rng.seed = seed_value
	var events := session.start(pids, names, start_rng)
	screen = ScreenScript.new(app)
	screen.intent_sink = _on_intent
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(screen)
	screen.director.event_started.connect(_on_director_event)
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


func _on_director_event(ev: Dictionary) -> void:
	match ev.get("type", ""):
		"bid", "challenged":
			# 新一轮里(上一轮开盅排开的骰子已收走)桌上不该有任何别人的骰子
			if screen.cups.others_dice_count() != 0:
				leaks.append(ev)
		"revealed":
			# 演到开盅时:屏幕上自己的骰子还是这一轮的(= revealed 里自己的点数),下一轮的私有骰子已经到了(如果还有下一轮)
			var mine := []
			for row in ev.get("dice", []):
				if row.get("pid") == ME:
					mine = row["dice"]
			if not mine.is_empty():
				assert_eq(screen.state.shown_dice, mine, "开盅前屏幕上是这一轮的点数")
				assert_eq(screen.cups.values_of(ME), mine, "3D 盅底下也是这一轮的点数")
				reveals_checked += 1


func _idle() -> bool:
	return screen._intro_done and not screen.animating


func _others_step() -> bool:
	var s := session.state()
	if s.step == LiarsDiceState.Step.OVER or s.current_pid == ME:
		return false
	var cur: int = s.current_pid
	var total := s.total_dice()
	if not s.bid.is_empty():
		var pressure := clampf(float(s.bid["count"]) / float(total) * 1.6, 0.1, 0.95)
		if rng.randf() < pressure or LiarsDiceState.min_raise(s.bid, total).is_empty():
			return _apply(cur, {"kind": "challenge"})
	var options := []
	var lo := LiarsDicePicker.min_count(s.bid)
	for count in range(lo, mini(lo + 1, total) + 1):
		for face in range(2, 7):
			if LiarsDiceState.bid_error(count, face, s.bid, total) == "":
				options.append([count, face])
	var pick: Array = options[rng.randi_range(0, options.size() - 1)]
	return _apply(cur, {"kind": "bid", "count": pick[0], "face": pick[1]})


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
	# 3D 与视图一致:每人一只盅,出局的歪倒;自己盅底下是私有骰子;别人桌上没有骰子(没开盅)
	var pub: Dictionary = session.public_view(0.0)
	for row in pub["players"]:
		var want := LiarsDiceCups.STATE_DOWN if row["alive"] else LiarsDiceCups.STATE_TIPPED
		assert_eq(screen.cups.state_of(row["pid"]), want, "P%d 的骰盅" % row["pid"])
	assert_eq(screen.cups.values_of(ME), session.private_view(ME)["dice"], "自己盅底下的骰子")
	assert_eq(screen.hud.my_dice_values(), session.private_view(ME)["dice"], "2D 骰子")
	assert_eq(screen.cups.others_dice_count(), 0, "别人的骰子在开盅前不建")


func test_a_whole_three_player_match_to_settlement():
	_open([1, 2, 3], 11)
	assert_eq(app.modes, [GameMode.LIARS_DICE])
	assert_almost_eq(app.world.table_radius, SeatLayout.TABLE_RADIUS, 0.001, "3 人用骗子酒馆的桌子")
	await wait_until(_idle, MAX_WAIT, "开局摇盅")
	_check_table()
	await _play_to_the_end()
	var settlement: LiarsDiceSettlement = screen.settlement()
	assert_not_null(settlement)
	var ranking: Array = screen.state.ranking_rows().map(func(r: Dictionary) -> int: return r["pid"])
	assert_eq(ranking, [session.state().winner_pid] + _reversed(session.state().out_order), "名次 = 胜者 + 出局顺序倒排")
	assert_true(app.world.is_celebrating(), "match_over 开演庆祝")
	assert_true(app.world.patrons[session.state().winner_pid].is_dancing(), "胜者跳舞")
	for pid in session.state().out_order:
		assert_false(app.world.patrons[pid].alive, "出局的 P%d 倒着(蚊香眼)" % pid)
		assert_eq(screen.cups.state_of(pid), LiarsDiceCups.STATE_TIPPED, "出局的骰盅歪倒")
	assert_eq(rejected, [], "自己的意图都按规则出,不该被拒")
	assert_eq(leaks, [], "开盅之前桌上没有别人的骰子")
	assert_gt(reveals_checked, 0, "核对过开盅时屏幕上的点数")
	assert_gte(accepted.size(), 2, "自己(机器人走出价器)真的出过手:%s" % [accepted])
	screen.get_parent().remove_child(screen)
	await get_tree().process_frame
	assert_false(app.world.is_celebrating(), "退场收起庆祝")
	add_child(screen)   # 放回去,交给 autofree 释放


func test_a_six_player_table_uses_the_big_table_and_plays_out():
	_open([1, 2, 3, 4, 5, 6], 23)
	assert_almost_eq(app.world.table_radius, SeatLayout.POKER_TABLE_RADIUS, 0.001, "6 人换大桌")
	await wait_until(_idle, MAX_WAIT, "开局摇盅")
	_check_table()
	assert_eq(screen.state.total, 30)
	await _play_to_the_end()
	assert_not_null(screen.settlement())
	assert_eq(leaks, [])


func test_keys_drive_the_picker_and_reject_toasts():
	_open([1, 2], 5)
	await wait_until(_idle, MAX_WAIT, "开局摇盅")
	if session.state().current_pid != ME:
		_others_step()
		await wait_until(_idle, MAX_WAIT, "别人喊完")
	assert_true(screen.is_my_turn(), "轮到自己")
	var before: int = screen.picker.count
	assert_true(screen.handle_key(KEY_UP))
	assert_eq(screen.picker.count, before + 1, "↑ 个数 +1")
	assert_true(screen.handle_key(KEY_DOWN))
	assert_eq(screen.picker.count, before)
	assert_true(screen.handle_key(KEY_6))
	assert_eq(screen.picker.face, 6, "6 选点数 6")
	assert_false(screen.handle_key(KEY_T), "T 留给九宫格")
	var count: int = screen.picker.count
	assert_true(screen.handle_key(KEY_ENTER), "Enter 加注")
	assert_eq(accepted, ["bid"])
	assert_eq(session.state().bid["count"], count)
	assert_eq(session.state().bid["face"], 6)
	assert_false(screen.is_my_turn(), "等回执 / 演出期间不能再出手")
	screen._on_rejected(LiarsDiceState.ERR_BID_TOO_LOW)
	assert_has(app.toasts, LiarsDiceState.ERROR_MESSAGES[LiarsDiceState.ERR_BID_TOO_LOW], "被拒时 toast 中文")


func test_challenge_needs_a_bid_and_my_turn():
	_open([1, 2], 9)
	await wait_until(_idle, MAX_WAIT, "开局摇盅")
	if session.state().current_pid != ME:
		assert_false(screen.submit_challenge(), "不是自己的回合")
		_others_step()
		await wait_until(_idle, MAX_WAIT, "别人喊完")
		if session.is_over() or session.state().current_pid != ME:
			return
	if session.state().bid.is_empty():
		assert_false(screen.can_challenge(), "本轮还没人喊:开! 不亮")
		assert_false(screen.submit_challenge())
		assert_true(screen.hud.challenge_button.disabled)
	else:
		assert_true(screen.can_challenge())
		assert_false(screen.hud.challenge_button.disabled)
		assert_true(screen.handle_key(KEY_C), "C 开")
		assert_eq(accepted, ["challenge"])


func test_quick_chat_panel_takes_number_keys_at_the_table():
	# 真的 BanterView 压在牌桌上:面板开着时数字键说话、不选点数;关着时数字键选点数
	_open([1, 2], 7)
	await wait_until(_idle, MAX_WAIT, "开局摇盅")
	var banter: FakeBanter = autofree(FakeBanter.new())
	var view := BanterView.new(app, banter)
	app.banter_view = view
	add_child_autofree(view)
	view.set_process(false)
	view.visible = true
	view.toggle_panel()
	var face_before: int = screen.picker.face
	var key := InputEventKey.new()
	key.keycode = KEY_4
	key.pressed = true
	get_viewport().push_input(key)
	assert_eq(banter.spoken, [3], "面板开着:4 说第 4 句")
	assert_eq(screen.picker.face, face_before, "也没有选点数 4")
	assert_false(view.is_panel_open(), "说完自动关上")
	get_viewport().push_input(key)
	assert_eq(screen.picker.face, 4, "面板关着:4 选点数 4")


func test_quip_menu_captures_number_keys_and_escape():
	_open([1, 2], 13)
	await wait_until(_idle, MAX_WAIT, "开局摇盅")
	screen.hud.quip_pressed.emit()
	assert_true(screen.quips.menu.is_open(), "右上「对话」按钮打开九宫格")
	var face_before: int = screen.picker.face
	var key := InputEventKey.new()
	key.keycode = KEY_3
	key.pressed = true
	get_viewport().push_input(key)
	assert_eq(screen.picker.face, face_before, "九宫格开着:3 不选点数")
	assert_false(screen.quips.menu.is_open(), "选了一句就收起")
	var t := InputEventKey.new()
	t.keycode = KEY_T
	t.pressed = true
	get_viewport().push_input(t)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	get_viewport().push_input(esc)
	assert_false(screen.quips.menu.is_open(), "Esc 收起九宫格(没有落到「离开牌桌」)")


func test_exit_tears_down_the_dice_nodes():
	_open([1, 2], 5)
	await wait_until(_idle, MAX_WAIT, "开局摇盅")
	assert_gt(app.world.poker_root.get_child_count(), 0)
	screen.get_parent().remove_child(screen)
	await get_tree().process_frame
	assert_eq(app.world.poker_root.get_child_count(), 0, "退场拆掉骰盅、骰子与特效")
	add_child(screen)


func test_director_maps_a_challenge_batch_within_its_budgets():
	# 实速(time_scale 1)演一批「开!」:每段演出从开始到下一段开始的时长不超过 LiarsDicePacing 的预算;
	# 演到开盅时所有骰盅翻开、开盅面板与桌心计数器数到实际个数;丢骰子少一颗;出局的骰盅歪倒、酒客蚊香眼;新一轮重新摇
	_open([1, 2, 3], 17)
	Engine.time_scale = 1.0
	await wait_until(_idle, MAX_WAIT, "开局摇盅")
	var s := session.state()
	const H := preload("res://tests/liars_dice_helpers.gd")
	H.rig(s, {1: [1, 5, 6], 2: [5, 6, 6], 3: [2]}, 3, {"pid": 2, "count": 2, "face": 5})
	screen._on_public(session.public_view(10.0))
	screen._on_private(session.private_view(ME))   # 摆过的局面:屏幕上自己的点数跟着换
	var stamps := []
	screen.director.event_started.connect(func(ev: Dictionary) -> void:
		stamps.append([ev, Time.get_ticks_msec()]))
	var batch: Array = session.handle_intent(3, {"kind": "challenge"})["events"]
	assert_eq(H.types(batch), ["challenged", "revealed", "die_lost", "player_out", "round_started"])
	_send(batch)
	await wait_until(func(): return stamps.size() >= 3, MAX_WAIT, "演到丢骰子")
	assert_true(screen.hud.is_reveal_open(), "开盅面板")
	for pid in [1, 2, 3]:
		assert_eq(screen.cups.state_of(pid), LiarsDiceCups.STATE_OPEN, "P%d 的骰盅翻开" % pid)
	assert_eq(screen.fx3d.counter_text(), "数到 3 / 喊了 2", "桌心计数器数到实际个数(含 1 点)")
	assert_eq(screen.hud.reveal_marked(), 3)
	await wait_until(func(): return stamps.size() >= 4, MAX_WAIT, "演到出局")
	assert_eq(screen.cups.dice_count(3), 0, "输家的骰子弹飞了")
	await wait_until(func(): return stamps.size() >= 5, MAX_WAIT, "演到新一轮")
	assert_eq(screen.cups.state_of(3), LiarsDiceCups.STATE_TIPPED, "出局的骰盅歪倒")
	assert_false(app.world.patrons[3].alive, "出局的酒客蚊香眼倒下")
	await wait_until(_idle, MAX_WAIT, "新一轮摇完")
	stamps.append([{"type": "end"}, Time.get_ticks_msec()])
	for i in range(stamps.size() - 1):
		var ev: Dictionary = stamps[i][0]
		var took: float = (stamps[i + 1][1] - stamps[i][1]) / 1000.0
		assert_lte(took, LiarsDicePacing.estimate([ev]) + 0.12, "%s 演了 %.2f 秒" % [ev["type"], took])
	assert_eq(screen.cups.others_dice_count(), 0, "新一轮:别人的骰子收走了")
	assert_eq(screen.cups.values_of(ME), session.private_view(ME)["dice"], "自己盅底下换成新一轮的点数")
	assert_true(screen.fx3d.counter_text() == "", "新一轮桌心清空")


static func _reversed(items: Array) -> Array:
	var out := items.duplicate()
	out.reverse()
	return out
