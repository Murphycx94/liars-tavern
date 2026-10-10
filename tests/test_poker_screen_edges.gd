extends "res://tests/poker_screen_harness.gd"
# 德州牌桌的边角情形(任务 7b 审查发现的问题各一条回归):迟到者开场运镜期间开了新的一手、
# 手牌中途有人全下后离开、旁人的事件不重置已调好的加注额、结算面板下不再露出输光提示也不拉回机位、
# 再领只等自己的回执、旧的弃牌确认在换了行动者后作废;
# 一轮下注结束后(收注、发公共牌、摊牌分池)回合横幅不再写上一个行动者(2026-10-10 试玩)。


func _hand1() -> void:
	await _feed([{"type": "hand_started", "hand": 1, "button": 1, "sb": 2, "bb": 3, "seats": [1, 2, 3], "dealt": [2, 3, 1]},
		_blind(2, "sb", 10), _blind(3, "bb", 20), {"type": "hole_cards", "hand": 1, "pids": [2, 3, 1]}, {"type": "turn", "pid": ME}],
		_pub(ME), {"hand": 1, "hole": H.cards("Ah Kd"), "best": {}})


func _join_as_waiting(pid: int) -> void:
	stacks[pid] = PokerRules.STARTING_STACK
	statuses[pid] = PokerRules.STATUS_WAITING
	bets[pid] = 0
	shown[pid] = []


func test_late_joiner_dealt_in_during_the_intro_gets_a_seat_and_a_patron():
	# 两手之间加入:房主 1.5 秒后开下一手,迟到者的开场运镜 1.7 秒,hand_started 在运镜期间到达并被第一帧丢掉
	_open_table([2, 3], true)
	_join_as_waiting(ME)
	screen._on_events([{"type": "player_joined", "pid": ME, "name": "我"}])
	screen._on_public(_pub(null))
	seats = [2, 3, 1]
	for pid in seats:
		statuses[pid] = PokerRules.STATUS_ACTIVE
	await _feed([{"type": "hand_started", "hand": 2, "button": 3, "sb": 1, "bb": 2, "seats": [2, 3, 1], "dealt": [1, 2, 3]},
		_blind(ME, "sb", 10), _blind(2, "bb", 20), {"type": "hole_cards", "hand": 2, "pids": [1, 2, 3]}, {"type": "turn", "pid": 3}],
		_pub(3, {"hand": 2, "button": 3, "sb": 1, "bb": 2}), {"hand": 2, "hole": H.cards("Ah Kd"), "best": {}})
	assert_eq(screen.state.seats, [2, 3, 1])
	assert_true(app.world.patrons.has(ME), "第一帧按视图重排:自己的酒客登场")
	assert_eq(app.world.patrons[ME].fan.get_child_count(), 2, "自己的两张手牌在牌扇里")
	assert_eq(screen.director.camera_mode(), PokerDirector.MODE_SEAT)
	assert_eq(screen.state.current_pid, 3, "行动者从视图取")


func test_a_departed_all_in_player_keeps_his_seat_for_the_reveal():
	_open_table([1, 2, 3], false)
	await _hand1()
	await _feed([_bet(ME, PokerRules.CALL, 20), _bet(2, PokerRules.CALL, 20), _bet(3, PokerRules.RAISE, 2000, true),
		{"type": "turn", "pid": ME}], _pub(ME, {"current_bet": 2000}))
	seats = [1, 2]
	var pub := _pub(ME, {"current_bet": 2000})
	for p in pub["players"]:
		if p["pid"] == 3:
			p["left"] = true
	await _feed([{"type": "player_left", "pid": 3, "folded": false}], pub)
	assert_true(app.world.seat_angles.has(3), "同一手里不重排:离场者的座位留到下一手")
	assert_false(_live_patrons().has(3), "但他的酒客已经离场")
	assert_gt(screen.chips.bet_amount(3), 0, "他留在桌上的注还在")
	await screen.director.play({"type": "reveal", "hands": [{"pid": 3, "cards": H.cards("Qh Qs")}], "reason": "showdown"})
	var card: Node3D = screen.cards.shown_cards(3)[0]
	var mine := PokerLayout.shown_card(0.0, app.world.table_radius, 0).origin
	assert_gt(card.position.distance_to(mine), 0.2, "他亮的牌摆在他的座位前,不在本机座位前")


func test_unrelated_events_keep_my_chosen_raise_amount():
	_open_table([1, 2, 3], false)
	await _hand1()
	assert_true(screen.is_my_turn())
	screen.hud.controls.set_amount(200)
	_join_as_waiting(9)
	await _feed([{"type": "player_joined", "pid": 9, "name": "迟到"}], _pub(ME))
	assert_true(screen.is_my_turn())
	assert_eq(screen.hud.controls.amount(), 200, "同一回合:旁人的事件不把金额打回最小加注")


func test_settlement_keeps_the_orbit_and_hides_the_bust_prompt():
	_open_table([1, 2, 3], false)
	await _hand1()
	stacks[ME] = 0
	statuses[ME] = PokerRules.STATUS_BUSTED
	var results := [{"pid": 1, "name": "我", "stack": 0, "buyins": 1, "net": -2000, "left": false}]
	await _feed([{"type": "hand_over", "hand": 1, "stacks": {1: 0}, "busted": [1]}, {"type": "session_over", "results": results}],
		_pub(null, {"phase": "over", "results": results}))
	screen._on_public(_pub(null, {"phase": "over", "results": results}))
	assert_not_null(screen._settlement)
	assert_eq(screen.director.camera_mode(), PokerDirector.MODE_ORBIT, "结算时留在散局环绕镜头")
	assert_eq(screen.hud.bottom_mode(), PokerHud.BOTTOM_NONE, "结算面板下不露出输光提示")
	assert_lt(screen._next_left, 0.0, "倒计时停了")
	assert_false(screen.choose_rebuy(), "散局后不能再领")


func test_seat_requests_wait_for_their_own_receipt():
	_open_table([1, 2, 3], false)
	await _hand1()
	statuses[ME] = PokerRules.STATUS_BUSTED
	stacks[ME] = 0
	await _feed([{"type": "hand_over", "hand": 1, "stacks": {1: 0}, "busted": [1]}], _pub(null))
	assert_true(screen.choose_rebuy())
	_join_as_waiting(9)
	await _feed([{"type": "player_joined", "pid": 9, "name": "迟到"}], _pub(null))
	assert_false(screen.choose_rebuy(), "别人的事件不算回执:不重复发")
	assert_false(screen.choose_spectate())
	statuses[ME] = PokerRules.STATUS_WAITING
	stacks[ME] = PokerRules.STARTING_STACK
	await _feed([{"type": "rebuy", "pid": ME, "amount": 2000, "buyins": 2, "stack": 2000}], _pub(null))
	assert_false(screen._seat_request_pending, "自己的回执到了")


func test_a_stale_fold_confirm_is_dropped_when_the_turn_moves_on():
	_open_table([1, 2, 3], false)
	await _hand1()
	screen._confirm_fold()
	var overlay: ConfirmOverlay = screen._fold_confirm
	assert_true(is_instance_valid(overlay))
	await _feed([_bet(ME, PokerRules.CALL, 20), {"type": "turn", "pid": 2}], _pub(2))
	await wait_process_frames(2)
	assert_false(is_instance_valid(overlay), "换了行动者,旧的弃牌确认作废")


func test_quips_pop_a_bubble_over_the_speaker_and_log_a_line():
	_open_table([1, 2, 3], false)
	await _hand1()
	Net.quip_shown.emit(2, 1)
	assert_not_null(app.labels.get_node_for(QuipController.KEY_PREFIX % 2), "乙头顶冒气泡")
	Net.quip_shown.emit(ME, 6)
	assert_true(is_instance_valid(screen.hud._my_bubble), "自己说的弹在左下自己那一栏上方")
	await wait_process_frames(3)
	assert_true(screen.hud._my_bubble.position.x >= PokerHud.MARGIN.x - 0.5, "长句不出左边画面")
	Net.quip_shown.emit(9, 0)
	assert_null(app.labels.get_node_for(QuipController.KEY_PREFIX % 9), "没有酒客的人只记日志")
	var lines: Array = screen.hud.log_box.get_children().map(func(l: Label) -> String: return l.text)
	assert_has(lines, "乙:打得不错")
	assert_has(lines, "我:快点吧,我等到花儿都谢了")


func test_start_button_after_a_hand_then_waiting_for_others_and_auto_press():
	_open_table([1, 2, 3], false)
	await _hand1()
	for pid in [2, 3]:
		statuses[pid] = PokerRules.STATUS_FOLDED
	await _feed([_bet(ME, PokerRules.CALL, 20), _bet(2, PokerRules.FOLD, 10), _bet(3, PokerRules.FOLD, 20),
		{"type": "pot_won", "index": 0, "amount": 50, "winners": [ME], "shares": {ME: 50}, "hand_name": "", "best": {},
			"uncontested": true},
		{"type": "hand_over", "hand": 1, "stacks": {1: 2030, 2: 1990, 3: 1980}, "busted": []},
		{"type": "hand_record", "hand": 1, "board": [], "players": [
			{"pid": 2, "cards": H.cards("Ah Ad"), "hand_name": "", "folded": true, "left": false, "delta": -10},
			{"pid": 3, "cards": H.cards("7s 2h"), "hand_name": "", "folded": true, "left": false, "delta": -20},
			{"pid": 1, "cards": H.cards("Ah Kd"), "hand_name": "", "folded": false, "left": false, "delta": 30}]}],
		_pub(null, {"phase": "idle"}))
	assert_eq(screen.hud.bottom_mode(), PokerHud.BOTTOM_NEXT, "一手结束:开始下一手")
	assert_gt(screen._next_left, PokerPacing.NEXT_HAND_TIMEOUT - 1.0, "15 秒倒计时")
	assert_eq(screen.state.history.size(), 1, "牌局记录收下了")
	screen.toggle_history()
	assert_true(is_instance_valid(screen._history))
	assert_eq(screen._history.row_count(), 3, "弃牌的乙、丙的手牌也能看到")
	screen.toggle_history()
	await wait_process_frames(2)
	assert_false(is_instance_valid(screen._history))
	assert_true(screen.choose_next())
	assert_false(screen.choose_next(), "等回执期间不重复发")
	confirmed[ME] = true
	await _feed([{"type": "next_ready", "pid": ME}], _pub(null, {"phase": "idle"}))
	assert_eq(screen.hud.bottom_mode(), PokerHud.BOTTOM_NEXT_WAIT)
	assert_false(screen._seat_request_pending, "回执到了")
	assert_true(screen.hud.prompts._message.text.contains("1/3"), screen.hud.prompts._message.text)


func test_start_is_pressed_automatically_when_the_countdown_runs_out():
	_open_table([1, 2, 3], false)
	await _hand1()
	await _feed([{"type": "hand_over", "hand": 1, "stacks": {}, "busted": []}], _pub(null, {"phase": "idle"}))
	assert_eq(screen.hud.bottom_mode(), PokerHud.BOTTOM_NEXT)
	screen._next_left = 0.01
	await wait_process_frames(3)
	assert_true(screen._seat_request_pending, "时间到自动点了开始")


func test_patrons_use_the_species_the_host_assigned():
	# Bug:德州牌桌排座时没带形象,各端按本地「第一个空着的」补,别人看到的不是自己选的那只
	var saved_lobby: Array = Net.lobby_players
	_reset_table([1, 2, 3])
	Net.seats = [{"pid": 1, "name": "我", "species": 3}, {"pid": 2, "name": "乙", "species": 5}, {"pid": 3, "name": "丙", "species": 7}]
	Net.lobby_players = [{"pid": 9, "name": "迟到", "species": 6}]
	screen = PokerScreenScript.new(app)
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(screen)
	await _hand1()
	for pid in [1, 2, 3]:
		assert_eq(app.world.patrons[pid].species_index, {1: 3, 2: 5, 3: 7}[pid], "开局:%d 号用房主分配的形象" % pid)
	_join_as_waiting(9)
	seats = [1, 2, 3, 9]
	await _feed([{"type": "hand_over", "hand": 1, "stacks": {}, "busted": []},
		{"type": "hand_started", "hand": 2, "button": 2, "sb": 3, "bb": 9, "seats": [1, 2, 3, 9], "dealt": [3, 9, 1, 2]}],
		_pub(null, {"hand": 2}))
	assert_eq(app.world.patrons[9].species_index, 6, "中途入座的人也用房主分配的形象")
	Net.lobby_players = saved_lobby


func test_turn_banner_clears_once_the_betting_round_is_over():
	# 大盲全下、自己跟注全下:之后没有 turn 事件,收注、亮牌、发完公共牌、分池期间横幅原来一直写「等待 X 行动…」
	_open_table([1, 2, 3], false)
	await _hand1()
	await _feed([_bet(ME, PokerRules.CALL, 20), _bet(2, PokerRules.FOLD, 10), {"type": "turn", "pid": 3}], _pub(3))
	assert_eq(screen.state.current_pid, 3)
	assert_eq(screen.hud.controls._turn_label.text, "等待 %s 行动…" % names[3])
	var flop := H.cards("Qc 7h 2s")
	screen._on_events([_bet(3, PokerRules.CHECK, 20), _collect(),
		{"type": "street", "street": PokerRules.FLOP, "cards": flop, "board": flop}])
	await wait_until(func(): return screen.state.current_pid == null, MAX_WAIT, "收注时行动者清空")
	assert_false(screen.hud.controls._turn_panel.visible, "没人在行动:回合横幅收起")
