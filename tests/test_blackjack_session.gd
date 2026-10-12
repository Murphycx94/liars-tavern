extends GutTest
# 21 点会话:意图结构校验、分派与 turn_action、计时(下注 15 秒、决策 20 秒)、视图不漏暗牌、
# 中途加入、离开、散局,以及随机乱打的模糊测试(不变量:筹码不为负、结算行盈亏一致、阶段与计时一致)。


const H := preload("res://tests/poker_helpers.gd")
const R := preload("res://src/core/blackjack/bj_rules.gd")
const NAMES := {1: "甲", 2: "乙", 3: "丙"}

var session: BlackjackSession


func before_each():
	session = BlackjackSession.new()


func _start(pids := [1, 2], seed_value := 5) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return session.start(pids, NAMES, rng)


func _do(pid: int, kind: String, amount := -1) -> Dictionary:
	var intent := {"kind": kind}
	if amount >= 0:
		intent["amount"] = amount
	return session.handle_intent(pid, intent)


# —— 意图校验 ——

func test_intent_structure_is_checked():
	_start()
	assert_eq(session.validate_intent({"kind": "bet", "amount": 100}), "")
	assert_eq(session.validate_intent({"kind": "hit"}), "")
	assert_eq(session.validate_intent({"kind": "bet"}), "invalid_amount")
	assert_eq(session.validate_intent({"kind": "bet", "amount": "100"}), "invalid_amount")
	assert_eq(session.validate_intent({"kind": "hit", "amount": 1}), "invalid_intent")
	assert_eq(session.validate_intent({"kind": "fold"}), "invalid_intent")
	assert_eq(session.validate_intent({"kind": 3}), "invalid_intent")
	assert_eq(session.validate_intent("hit"), "invalid_intent")
	assert_eq(session.validate_intent({"kind": "bet", "amount": 100, "extra": 1}), "invalid_intent")


func test_start_opens_betting_with_a_bet_timer():
	var events := _start()
	assert_eq(H.types(events), ["round_started"])
	assert_true(session.has_turn(), "下注阶段计时")
	assert_eq(session.turn_timer_after(events, 1.0, 0.0), 1.0 + BlackjackPacing.BET_TIMEOUT)
	var view := session.public_view(12.0)
	assert_eq(view["phase"], "betting")
	assert_eq(view["turn_time_left"], 12.0)
	assert_eq(view["mode"], GameMode.BLACKJACK)
	assert_eq(view["players"].map(func(p): return p["name"]), ["甲", "乙"])
	assert_eq(session.viewers(), [], "没有私有视图")


func test_bets_do_not_use_the_turn_and_play_actions_do():
	_start()
	session.table().rig(H.cards("9s 5d 7c Ts 6h Kd"))
	var first := _do(1, R.BET, 100)
	assert_true(first["ok"])
	assert_false(first["turn_action"])
	assert_eq(session.turn_timer_after(first["events"], 0.5, 9.0), 9.0 + BlackjackPacing.BET_PLACED, "旁人下注只补演出")
	var second := _do(2, R.BET, 100)
	assert_eq(H.types(second["events"]), ["bet_placed", "dealt", "turn"])
	assert_eq(session.turn_timer_after(second["events"], 3.0, 8.0), 3.0 + BlackjackPacing.PLAY_TIMEOUT)
	var hit := _do(1, R.STAND)
	assert_true(hit["turn_action"])
	assert_eq(_do(1, R.HIT)["error"], "not_your_turn")


func test_view_never_shows_the_hole_card_before_the_reveal():
	_start([1])
	session.table().rig(H.cards("9s 7c Ts Kd"))
	_do(1, R.BET, 100)
	var view := session.public_view(5.0)
	assert_eq(view["dealer"], {"cards": [H.card("7c")], "hidden": true, "total": 7, "soft": false})
	assert_eq(view["current"], {"pid": 1, "hand": 0})
	assert_eq(view["actions"]["pid"], 1)
	assert_true(view["actions"][R.HIT])
	var events: Array = _do(1, R.STAND)["events"]
	view = session.public_view(0.0)
	assert_eq(view["dealer"]["cards"], H.cards("7c Kd"))
	assert_false(view["dealer"]["hidden"])
	assert_eq(view["phase"], "idle")
	assert_eq(view["turn_time_left"], 0.0)
	assert_false(session.has_turn())
	assert_true(session.next_hand_ready())
	assert_eq(session.hand_gap(), BlackjackPacing.ROUND_GAP)
	assert_eq(H.find(events, "settled")["hands"][0]["outcome"], R.OUTCOME_WIN)


func test_timeouts_skip_bets_and_stand_hands():
	_start([1])
	var result := session.on_turn_timeout()
	assert_true(result["ok"])
	assert_eq(H.types(result["events"]), ["bet_skipped", "round_over"])
	assert_false(session.has_turn())
	var events := session.start_next_hand()
	assert_eq(events[0]["round"], 2)
	session.table().rig(H.cards("9s 7c Ts Kd"))
	_do(1, R.BET, 100)
	result = session.on_turn_timeout()
	assert_eq(H.find(result["events"], "stand")["timeout"], true)


func test_late_joiner_is_named_and_offstage_when_leaving():
	_start([1])
	var events := session.add_player(3, "丙")
	assert_eq(events[0]["name"], "丙")
	assert_true(session.accepts_late_join())
	assert_eq(session.seats_with_patrons(), [1])
	events = session.on_disconnect(3)
	assert_eq(events[0]["type"], "player_left")
	assert_true(events[0]["offstage"])


func test_end_names_the_result_rows():
	_start()
	var events := session.request_end()
	assert_eq(events[0]["type"], "session_over")
	assert_eq(events[0]["results"].map(func(r): return r["name"]), ["甲", "乙"])
	assert_true(session.is_over())
	assert_false(session.accepts_late_join())
	assert_eq(session.public_view(0.0)["results"].size(), 2)


func test_seat_actions():
	_start([1])
	session.table().set_stack(1, 20)
	session.table().rig(H.cards("Ts 9c 6s Td Kh"))
	_do(1, R.BET, 20)
	_do(1, R.HIT)
	assert_eq(session.public_view(0.0)["players"][0]["status"], R.STATUS_BUSTED)
	var result := _do(1, R.REBUY)
	assert_true(result["ok"])
	assert_false(result["turn_action"])
	assert_eq(_do(1, R.SIT_IN)["error"], "invalid_action")


# —— 模糊测试 ——

func test_random_play_keeps_the_books_straight():
	for seed_value in 12:
		_fuzz(seed_value)


func _fuzz(seed_value: int) -> void:
	session = BlackjackSession.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var names := {1: "a", 2: "b", 3: "c", 4: "d"}
	session.start([1, 2, 3], names, rng)
	var present := [1, 2, 3]
	var joined := false
	for step in 400:
		if session.is_over():
			break
		var roll := rng.randf()
		if not session.has_turn():
			if session.next_hand_ready():
				session.start_next_hand()
			else:
				for pid in present:
					_do(pid, R.REBUY)
					_do(pid, R.SIT_IN)
				if not session.next_hand_ready():
					break
			continue
		if roll < 0.08:
			session.on_turn_timeout()
		elif roll < 0.1 and not joined:
			joined = true
			session.add_player(4, "d")
			present.append(4)
		elif roll < 0.11 and present.size() > 1:
			var gone: int = present.pop_at(rng.randi_range(0, present.size() - 1))
			session.on_disconnect(gone)
		else:
			var view := session.public_view(1.0)
			if view["phase"] == "betting":
				var pid: int = present[rng.randi_range(0, present.size() - 1)]
				var amount: int = R.BET_UNIT * rng.randi_range(0, 60)
				if rng.randf() < 0.15:
					_do(pid, R.SKIP)
				else:
					_do(pid, R.BET, amount)
			elif view["current"] != null:
				var pid: int = view["current"]["pid"]
				var kinds := R.PLAY_ACTIONS.filter(func(k): return view["actions"].get(k, false))
				var result := _do(pid, kinds[rng.randi_range(0, kinds.size() - 1)])
				assert_true(result["ok"], "合法动作被拒:%s" % result.get("error", ""))
		_check(session.public_view(1.0))
	if not session.is_over():
		var events: Array = session.request_end()
		if not events.is_empty() and events.back()["type"] == "ending":
			while session.has_turn():
				session.on_turn_timeout()
	assert_true(session.is_over(), "种子 %d 最后能散局" % seed_value)
	var results: Array = session.public_view(0.0)["results"]
	for row in results:
		assert_eq(row["net"], row["stack"] - row["buyins"] * R.STARTING_STACK)
		assert_true(row["stack"] >= 0)


func _check(view: Dictionary) -> void:
	for p in view["players"]:
		assert_true(p["stack"] >= 0, "筹码不为负")
		assert_true(p["hands"].size() <= R.MAX_HANDS)
	if view["phase"] == "playing":
		assert_true(view["dealer"]["hidden"], "打牌中暗牌不公开")
		assert_eq(view["dealer"]["cards"].size(), 1)
	assert_eq(view["current"] != null, not view["actions"].is_empty())
