extends GutTest
# 21 点牌桌的本地状态(BjScreenState):事件推进影子(视图领先于演出时不能先露出暗牌与结算)、底部模式、
# 铭牌与 HUD 的文字、视图里的可选动作;以及底部控件(BjControls)的金额夹取与快捷键。


const H := preload("res://tests/poker_helpers.gd")
const R := preload("res://src/core/blackjack/bj_rules.gd")
const ME := 1

var state: BjScreenState


func before_each():
	state = BjScreenState.new()
	state.set_seats([{"pid": 1, "name": "我"}, {"pid": 2, "name": "乙"}])
	state.apply_public({"round": 1, "phase": "betting", "seats": [1, 2], "players": [
		{"pid": 1, "name": "我", "stack": 2000, "status": R.STATUS_WAITING, "hands": []},
		{"pid": 2, "name": "乙", "stack": 2000, "status": R.STATUS_WAITING, "hands": []},
	], "dealer": {"cards": [], "hidden": false}, "current": null, "actions": {}})
	state.refresh_from_view()


func _round() -> void:
	state.apply_event({"type": "bet_placed", "pid": 1, "amount": 100, "stack": 1900})
	state.apply_event({"type": "bet_placed", "pid": 2, "amount": 40, "stack": 1960})
	state.apply_event({"type": "dealt", "order": [1, 2], "hands": {1: H.cards("8s 8d"), 2: H.cards("As Kd")},
		"dealer_up": H.card("Th")})
	state.apply_event({"type": "turn", "pid": 1, "hand": 0})


func test_betting_modes():
	assert_eq(state.bottom_mode(ME), BjScreenState.BOTTOM_BET)
	assert_eq(state.plate_status(2), "下注中")
	state.apply_event({"type": "bet_placed", "pid": 1, "amount": 100, "stack": 1900})
	assert_eq(state.bottom_mode(ME), BjScreenState.BOTTOM_BET_WAIT)
	assert_eq(state.betting_progress(), [1, 2])
	assert_eq(state.plate_status(1), "下注 100")
	state.apply_event({"type": "bet_skipped", "pid": 2})
	assert_eq(state.plate_status(2), "这局不玩")
	assert_eq(state.betting_progress(), [2, 2])


func test_deal_split_and_settle_follow_the_events():
	_round()
	assert_eq(state.dealer_label(), "庄家 10 + ?")
	assert_true(state.dealer_hidden)
	assert_eq(state.plate_status(2), "黑杰克")
	assert_eq(state.bottom_mode(ME), BjScreenState.BOTTOM_PLAY)
	state.apply_event({"type": "split", "pid": 1, "hand": 0, "cards": [H.cards("8s 3h"), H.cards("8d Kh")], "bet": 100,
		"stack": 1800})
	assert_eq(state.hands_of(ME).size(), 2)
	assert_eq(state.row(ME)["stack"], 1800)
	assert_eq(state.plate_status(1), "11 / 18")
	state.apply_event({"type": "double", "pid": 1, "hand": 0, "card": H.card("Tc"), "bet": 200, "stack": 1600, "total": 21})
	assert_true(state.hands_of(ME)[0]["doubled"])
	assert_true(state.hands_of(ME)[0]["done"])
	state.apply_event({"type": "dealer_reveal", "card": H.card("7c"), "cards": H.cards("Th 7c"), "total": 17})
	assert_eq(state.dealer_label(), "庄家 17")
	assert_eq(state.current, null)
	state.apply_event({"type": "settled", "hands": [
		{"pid": 1, "hand": 0, "outcome": R.OUTCOME_WIN, "bet": 200, "payout": 400},
		{"pid": 1, "hand": 1, "outcome": R.OUTCOME_WIN, "bet": 100, "payout": 200},
		{"pid": 2, "hand": 0, "outcome": R.OUTCOME_BLACKJACK, "bet": 40, "payout": 100},
	], "stacks": {1: 2200, 2: 2060}})
	assert_eq(state.row(ME)["stack"], 2200)
	assert_eq(BjScreenState.hand_label(state.hands_of(ME)[0]), "21 · 赢 +200")
	assert_eq(BjScreenState.hand_label(state.hands_of(2)[0]), "黑杰克 · 黑杰克 +60")
	state.apply_event({"type": "round_over", "busted": []})
	assert_eq(state.bottom_mode(ME), BjScreenState.BOTTOM_NONE)


func test_view_ahead_of_the_show_is_not_shown_until_reconcile():
	_round()
	# 视图已经到了结算之后,但演出还在发牌:影子里没有暗牌
	state.apply_public({"round": 1, "phase": "idle", "seats": [1, 2], "players": [], "current": null,
		"dealer": {"cards": H.cards("Th 9c"), "hidden": false}})
	assert_eq(state.dealer_cards, [H.card("Th")])
	state.refresh_from_view()
	assert_eq(state.dealer_cards, H.cards("Th 9c"))


func test_legal_needs_view_and_show_to_agree():
	_round()
	state.apply_public(state.pub.merged({"actions": {"pid": 1, "hand": 0, "hit": true, "stand": true, "double": true,
		"split": true, "surrender": true}}, true))
	assert_eq(state.legal(ME)[R.SPLIT], true)
	state.current = {"pid": 1, "hand": 1}
	assert_eq(state.legal(ME), {}, "演出还在别的一手")
	state.current = null
	assert_eq(state.legal(ME), {})


func test_seat_modes():
	state.apply_event({"type": "round_over", "busted": [1]})
	assert_eq(state.bottom_mode(ME), BjScreenState.BOTTOM_BUSTED)
	state.apply_event({"type": "rebuy", "pid": 1, "stack": 2000, "buyins": 2})
	state.apply_event({"type": "away", "pid": 1})
	assert_eq(state.bottom_mode(ME), BjScreenState.BOTTOM_AWAY)
	assert_eq(state.plate_status(1), "离座")
	state.apply_event({"type": "player_joined", "pid": 9, "name": "迟到"})
	assert_eq(state.bottom_mode(9), BjScreenState.BOTTOM_JOINING)
	assert_eq(state.name_of(9), "迟到")
	state.apply_event({"type": "round_started", "round": 2, "seats": [1, 2, 9]})
	assert_eq(state.bottom_mode(9), BjScreenState.BOTTOM_BET)
	state.apply_event({"type": "player_left", "pid": 2})
	assert_eq(state.plate_status(2), "已离开")


func test_untrusted_view_fields_are_ignored():
	state.apply_public({"round": "x", "players": [{"pid": "1"}, 7, {"pid": 3, "stack": "lots", "hands": [{"cards": [999, "Ah"]}]}],
		"dealer": "nope", "seats": [3, "a"], "current": {"pid": 3}})
	state.refresh_from_view()
	assert_eq(state.order, [3])
	assert_eq(state.row(3)["stack"], 0)
	assert_eq(state.hands_of(3)[0]["cards"], [])
	assert_eq(state.dealer_cards, [])
	assert_eq(state.current, null)
	assert_eq(state.seats, [3])


# —— 底部控件 ——

func test_bet_amounts_are_clamped_to_units_and_stack():
	assert_eq(BjControls.clamp_bet(100, 2000), 100)
	assert_eq(BjControls.clamp_bet(110, 2000), 120)
	assert_eq(BjControls.clamp_bet(5, 2000), R.MIN_BET)
	assert_eq(BjControls.clamp_bet(5000, 2000), R.MAX_BET)
	assert_eq(BjControls.clamp_bet(500, 330), 320)
	assert_eq(BjControls.clamp_bet(100, 10), 0, "不够最小下注")


func test_hotkeys_avoid_the_lean_keys():
	for key in [KEY_W, KEY_A, KEY_S, KEY_D]:
		assert_eq(BjControls.play_hotkey(key), "", "WASD 留给探头")
		assert_eq(BjControls.bet_hotkey(key), {})
	assert_eq(BjControls.play_hotkey(KEY_SPACE), R.HIT)
	assert_eq(BjControls.play_hotkey(KEY_ENTER), R.STAND)
	assert_eq(BjControls.play_hotkey(KEY_4), R.SPLIT)
	assert_eq(BjControls.bet_hotkey(KEY_ENTER), {"kind": "bet"})
	assert_eq(BjControls.bet_hotkey(KEY_3), {"kind": "preset", "index": 2})


func test_controls_emit_bets_and_actions():
	var controls := BjControls.new()
	add_child_autofree(controls)
	var got := []
	controls.bet_chosen.connect(func(amount): got.append(["bet", amount]))
	controls.skip_chosen.connect(func(): got.append(["skip"]))
	controls.action_chosen.connect(func(kind): got.append(["act", kind]))
	controls.show_betting(1500, 0)
	assert_eq(controls.amount(), BjControls.DEFAULT_BET)
	assert_true(controls.handle_key(KEY_UP))
	assert_true(controls.handle_key(KEY_ENTER))
	assert_false(controls.handle_key(KEY_R), "没有上一局的注")
	controls.show_betting(1500, 300)
	assert_true(controls.handle_key(KEY_N))
	controls.set_mode(BjControls.MODE_HIDDEN)
	controls.show_betting(1500, 300)
	assert_eq(controls.amount(), 300, "从上一局的注开始")
	assert_true(controls.handle_key(KEY_R))
	controls.show_play({R.HIT: true, R.STAND: true, R.DOUBLE: false, R.SPLIT: false, R.SURRENDER: true})
	assert_false(controls.handle_key(KEY_3), "不能加倍")
	assert_true(controls.action_button(R.DOUBLE).disabled)
	assert_true(controls.handle_key(KEY_SPACE))
	assert_eq(got, [["bet", 120], ["skip"], ["bet", 300], ["act", R.HIT]])


func test_betting_controls_keep_the_amount_within_a_round():
	# 别人的下注演出会让牌桌重刷:同一局里再展开不能把调好的金额改回去,新的一局才回到上一局的注
	var controls := BjControls.new()
	add_child_autofree(controls)
	controls.show_betting(2000, 100, 3)
	controls.set_amount(500)
	controls.set_mode(BjControls.MODE_HIDDEN)
	controls.show_betting(2000, 100, 3)
	assert_eq(controls.amount(), 500)
	controls.show_betting(2000, 100, 4)
	assert_eq(controls.amount(), 100)
