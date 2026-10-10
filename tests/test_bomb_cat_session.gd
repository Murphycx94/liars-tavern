extends GutTest
# 炸弹猫会话(设计稿 §2、§5):意图逐字段校验(不是你的回合、窗口外打不行、下标越界、目标是死人或自己、类型不对)、
# 哪些动作消耗回合、视图里什么人看到什么、四种等待的计时(回合 / 反应窗口 / 塞回 / 给牌)与窗口暂停回合计时。


const H := preload("res://tests/bomb_cat_helpers.gd")
const C := preload("res://src/core/bomb_cat/bomb_cat_card.gd")
const NAMES := {1: "甲", 2: "乙", 3: "丙"}
const EPS := 0.001
const PENDING := 1.25   # 假装客户端还要演这么久

var session: BombCatSession


func before_each():
	session = BombCatSession.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	session.start([1, 2, 3], NAMES, rng)


func _s() -> BombCatState:
	return session.state()


func _rig(hands: Dictionary, deck: Array, current := 1, turns := 1) -> void:
	H.rig(_s(), hands, deck, current, turns)


func _ok(pid: int, intent: Dictionary) -> Dictionary:
	var result := session.handle_intent(pid, intent)
	assert_true(result["ok"], "%s 应当成功:%s" % [str(intent), str(result.get("error", ""))])
	return result


func _err(pid: int, intent: Variant, code: String) -> void:
	var result := session.handle_intent(pid, intent)
	assert_eq([result["ok"], result.get("error")], [false, code], str(intent))
	assert_false(result["turn_action"])


func _timer(result: Dictionary, time_left: float) -> float:
	return session.turn_timer_after(result["events"], PENDING, time_left)


# —— 开局 ——

func test_start_returns_round_started_and_the_turn_timer_is_full():
	var rng := RandomNumberGenerator.new()
	var fresh := BombCatSession.new()
	var events := fresh.start([1, 2], {1: "甲", 2: "乙"}, rng)
	assert_eq(H.types(events), ["round_started"])
	assert_true(fresh.has_turn())
	assert_false(fresh.is_over())
	assert_false(fresh.accepts_late_join(), "不收中途加入")
	assert_almost_eq(fresh.turn_timer_after(events, PENDING, 0.0), PENDING + Protocol.TURN_TIMEOUT, EPS)


# —— 意图校验 ——

func test_malformed_intents_are_rejected_without_touching_the_state():
	_rig({1: [C.SKIP, C.BEG], 2: [C.NOPE]}, [C.PEEK, C.SHUFFLE])
	var bad := [
		[{}, BombCatState.ERR_INVALID_INTENT],
		[{"kind": 3}, BombCatState.ERR_INVALID_INTENT],
		[{"kind": "fold"}, BombCatState.ERR_INVALID_INTENT],
		[{"kind": "challenge"}, BombCatState.ERR_INVALID_INTENT],
		[{"kind": "play", "indices": [0]}, BombCatState.ERR_INVALID_PLAY],
		[{"kind": "play", "cards": "0"}, BombCatState.ERR_INVALID_PLAY],
		[{"kind": "play", "cards": [0.0]}, BombCatState.ERR_INVALID_PLAY],
		[{"kind": "play", "cards": [0, 1, 2, 3]}, BombCatState.ERR_INVALID_PLAY],
		[{"kind": "play", "cards": [1], "target": "2"}, BombCatState.ERR_INVALID_TARGET],
		[{"kind": "play", "cards": [1], "target": 2.0}, BombCatState.ERR_INVALID_TARGET],
		[{"kind": "play", "cards": [1], "target": 2, "named": 5}, BombCatState.ERR_INVALID_NAMED],
		[{"kind": "reinsert", "pos": "1"}, BombCatState.ERR_INVALID_POS],
		[{"kind": "reinsert"}, BombCatState.ERR_INVALID_POS],
		[{"kind": "give", "index": null}, BombCatState.ERR_INVALID_INDEX],
		[{"kind": "draw", "a": 1, "b": 2, "c": 3, "d": 4}, BombCatState.ERR_INVALID_INTENT],
	]
	for case in bad:
		_err(1, case[0], case[1])
	assert_eq(_s().hands[1], [C.SKIP, C.BEG])
	assert_eq(_s().step, BombCatState.Step.TURN)


func test_check_intent_rejects_non_dictionaries():
	for value in [null, 3, "draw", [], ["draw"]]:
		assert_eq(BombCatSession.check_intent(value), BombCatState.ERR_INVALID_INTENT, str(value))
	assert_eq(BombCatSession.check_intent({"kind": "draw"}), "")
	assert_eq(BombCatSession.check_intent({"kind": "play", "cards": [0], "target": null}), "", "target 可以是 null")


func test_rule_violations_come_back_with_engine_codes():
	_rig({1: [C.SKIP, C.BEG, C.NOPE], 2: [C.NOPE], 3: [C.SKIP]}, [C.PEEK, C.SHUFFLE])
	_err(2, {"kind": "draw"}, BombCatState.ERR_NOT_YOUR_TURN)
	_err(2, {"kind": "play", "cards": [0]}, BombCatState.ERR_NOT_YOUR_TURN)
	_err(2, {"kind": "nope"}, BombCatState.ERR_NO_WINDOW)
	_err(1, {"kind": "play", "cards": [9]}, BombCatState.ERR_INVALID_PLAY)
	_err(1, {"kind": "play", "cards": [2]}, BombCatState.ERR_INVALID_PLAY)
	_err(1, {"kind": "play", "cards": [1], "target": 1}, BombCatState.ERR_INVALID_TARGET)
	_s().alive[3] = false
	_err(1, {"kind": "play", "cards": [1], "target": 3}, BombCatState.ERR_INVALID_TARGET)
	_err(3, {"kind": "nope"}, BombCatState.ERR_OUT)
	_s().alive[3] = true
	_err(1, {"kind": "reinsert", "pos": 0}, BombCatState.ERR_NOT_WAITING)
	_err(1, {"kind": "give", "index": 0}, BombCatState.ERR_NOT_WAITING)
	_err(42, {"kind": "draw"}, BombCatState.ERR_NOT_SEATED)


func test_turn_actions_and_nope():
	_rig({1: [C.SKIP], 2: [C.NOPE]}, [C.PEEK, C.SHUFFLE])
	assert_true(_ok(1, {"kind": "play", "cards": [0]})["turn_action"], "出牌消耗回合")
	assert_false(_ok(2, {"kind": "nope"})["turn_action"], "「不行!」不清演出欠账")
	session.on_turn_timeout()
	assert_true(_ok(1, {"kind": "draw"})["turn_action"])


# —— 计时 ——

func test_play_pauses_the_turn_and_the_window_resumes_it():
	_rig({1: [C.PEEK, C.SKIP], 2: [C.NOPE]}, [C.BEG, C.SHUFFLE, C.SKIP, C.DEFUSE])
	var result := _ok(1, {"kind": "play", "cards": [0]})
	assert_almost_eq(_timer(result, 17.5), PENDING + BombCatState.REACT_WINDOW, EPS, "窗口 3 秒从演出播完算起")
	assert_almost_eq(session.paused_turn_left(), 17.5, EPS, "记下出牌那一刻的回合剩余")
	assert_almost_eq(session.public_view(4.0)["paused_turn_left"], 17.5, EPS)
	result = _ok(2, {"kind": "nope"})
	assert_almost_eq(_timer(result, 1.0), PENDING + BombCatState.REACT_WINDOW, EPS, "每张不行重开窗口")
	result = session.on_turn_timeout()
	assert_true(result["ok"])
	assert_eq(H.types(result["events"]), ["window_resolved"])
	assert_almost_eq(_timer(result, 0.0), PENDING + 17.5, EPS, "窗口结束恢复暂停前的剩余")
	assert_eq(session.paused_turn_left(), 0.0)
	assert_eq(session.public_view(9.0)["paused_turn_left"], 0.0)


func test_resumed_time_has_a_floor():
	_rig({1: [C.PEEK]}, [C.BEG, C.SHUFFLE, C.SKIP])
	_timer(_ok(1, {"kind": "play", "cards": [0]}), 0.4)
	var result := session.on_turn_timeout()
	assert_almost_eq(_timer(result, 0.0), PENDING + BombCatSession.RESUME_MIN, EPS)


func test_effects_that_end_the_turn_give_the_next_player_a_full_turn():
	_rig({1: [C.SKIP]}, [C.BEG])
	_timer(_ok(1, {"kind": "play", "cards": [0]}), 12.0)
	var result := session.on_turn_timeout()
	assert_true(H.find(result["events"], "turn_passed").size() > 0)
	assert_almost_eq(_timer(result, 0.0), PENDING + Protocol.TURN_TIMEOUT, EPS)


func test_beg_gives_the_target_fifteen_seconds_then_resumes():
	_rig({1: [C.BEG], 2: [C.SKIP]}, [C.PEEK])
	_timer(_ok(1, {"kind": "play", "cards": [0], "target": 2}), 20.0)
	var result := session.on_turn_timeout()
	assert_true(H.find(result["events"], "give_requested").size() > 0)
	assert_almost_eq(_timer(result, 0.0), PENDING + BombCatState.GIVE_TIMEOUT, EPS)
	assert_almost_eq(session.public_view(5.0)["paused_turn_left"], 20.0, EPS, "给牌期间回合计时仍暂停")
	_err(1, {"kind": "give", "index": 0}, BombCatState.ERR_NOT_WAITING)
	result = _ok(2, {"kind": "give", "index": 0})
	assert_true(result["turn_action"])
	assert_almost_eq(_timer(result, 8.0), PENDING + 20.0, EPS, "给完回到讨要者,恢复暂停的剩余")


func test_give_timeout_gives_a_random_card_and_resumes():
	_rig({1: [C.BEG], 2: [C.SKIP]}, [C.PEEK])
	_timer(_ok(1, {"kind": "play", "cards": [0], "target": 2}), 20.0)
	_timer(session.on_turn_timeout(), 0.0)
	var result := session.on_turn_timeout()
	assert_eq(H.find(result["events"], "effect")["got"], true)
	assert_eq(_s().hands[1], [C.SKIP])
	assert_almost_eq(_timer(result, 0.0), PENDING + 20.0, EPS)


func test_reinsert_gets_fifteen_seconds_then_the_next_turn_is_full():
	_rig({1: [C.DEFUSE]}, [C.BOMB, C.PEEK, C.SKIP])
	var result := _ok(1, {"kind": "draw"})
	assert_almost_eq(_timer(result, 25.0), PENDING + BombCatState.REINSERT_TIMEOUT, EPS)
	_err(1, {"kind": "reinsert", "pos": 3}, BombCatState.ERR_INVALID_POS)
	_err(2, {"kind": "reinsert", "pos": 0}, BombCatState.ERR_NOT_WAITING)
	result = _ok(1, {"kind": "reinsert", "pos": 2})
	assert_almost_eq(_timer(result, 9.0), PENDING + Protocol.TURN_TIMEOUT, EPS)


func test_timeouts_in_each_step():
	_rig({1: [C.DEFUSE]}, [C.BOMB, C.PEEK, C.SKIP])
	assert_eq(H.types(session.on_turn_timeout()["events"]), ["drew", "bomb_drawn", "defused"], "自由行动超时 = 摸牌")
	var result := session.on_turn_timeout()
	assert_eq(H.types(result["events"]), ["reinserted", "turn_passed"], "塞回超时 = 随机位置")
	assert_true(result["turn_action"])


func test_bystander_disconnect_keeps_the_running_clock():
	_rig({1: [C.SKIP], 3: [C.NOPE]}, [C.BEG])
	var events := session.on_disconnect(3)
	assert_eq(H.types(events), ["player_left"])
	assert_almost_eq(session.turn_timer_after(events, PENDING, 11.0), 11.0 + BombCatPacing.PLAYER_LEFT, EPS)
	assert_eq(session.on_disconnect(3), [], "已出局")
	assert_eq(session.on_disconnect(99), [], "不在局里")


func test_bystander_disconnect_during_a_window_extends_it():
	_rig({1: [C.SKIP], 3: [C.NOPE]}, [C.BEG])
	_timer(_ok(1, {"kind": "play", "cards": [0]}), 14.0)
	var events := session.on_disconnect(3)
	assert_almost_eq(session.turn_timer_after(events, PENDING, 2.0), 2.0 + BombCatPacing.PLAYER_LEFT, EPS)
	var resolved := session.on_turn_timeout()
	assert_almost_eq(_timer(resolved, 0.0), PENDING + Protocol.TURN_TIMEOUT, EPS, "溜了生效 → 换人")


func test_giver_disconnect_resumes_the_askers_turn():
	_rig({1: [C.BEG], 2: [C.SKIP]}, [C.PEEK])
	_timer(_ok(1, {"kind": "play", "cards": [0], "target": 2}), 16.0)
	_timer(session.on_turn_timeout(), 0.0)
	var events := session.on_disconnect(2)
	assert_almost_eq(session.turn_timer_after(events, PENDING, 6.0), PENDING + 16.0, EPS)


func test_match_over_stops_everything():
	for pid in [2, 3]:
		session.on_disconnect(pid)
	assert_true(session.is_over())
	assert_false(session.has_turn())
	assert_eq(session.on_turn_timeout()["ok"], false)
	assert_eq(session.handle_intent(1, {"kind": "draw"})["error"], BombCatState.ERR_MATCH_OVER)
	var view := session.public_view(5.0)
	assert_eq(view["step"], "over")
	assert_eq(view["winner"], 1)
	assert_eq(view["turn_time_left"], 0.0)
	assert_eq(view["ranking"].map(func(r: Dictionary) -> int: return r["pid"]), [1, 3, 2])
	assert_eq(view["ranking"][0], {"pid": 1, "name": "甲", "place": 1})


# —— 视图 ——

func test_public_view_shows_counts_but_no_cards():
	_rig({1: [C.BEG, C.DEFUSE], 2: [C.SKIP, C.NOPE, C.PEEK], 3: []}, [C.BOMB, C.SHUFFLE])
	_ok(1, {"kind": "play", "cards": [0], "target": 2})
	var view := session.public_view(2.5)
	assert_eq(H.view_leak(view), "")
	assert_eq(view["mode"], GameMode.BOMB_CAT)
	assert_eq(view["step"], "window")
	assert_eq(view["current_pid"], 1)
	assert_eq(view["turns"], 1)
	assert_eq(view["deck_count"], 2)
	assert_eq(view["discard_top"], C.BEG)
	assert_eq(view["bombs_left"], 2)
	assert_eq(view["window"], {"pid": 1, "cards": [C.BEG], "kind": C.BEG, "target": 2, "named": "", "nopes": 0})
	assert_almost_eq(view["turn_time_left"], 2.5, EPS)
	assert_eq(view["players"], [
		{"pid": 1, "name": "甲", "alive": true, "hand_count": 1},
		{"pid": 2, "name": "乙", "alive": true, "hand_count": 3},
		{"pid": 3, "name": "丙", "alive": true, "hand_count": 0},
	])
	session.on_turn_timeout()
	view = session.public_view(0.0)
	assert_eq([view["step"], view["give"], view["window"]], ["give", {"from": 2, "to": 1}, {}])


func test_private_views_belong_to_their_owner():
	_rig({1: [C.PEEK, C.DEFUSE], 2: [C.SKIP]}, [C.BOMB, C.SHUFFLE, C.BEG, C.NOPE])
	_ok(1, {"kind": "play", "cards": [0]})
	session.on_turn_timeout()
	var mine := session.private_view(1)
	assert_eq(mine["hand"], [C.DEFUSE])
	assert_eq(mine["peek"], [C.BOMB, C.SHUFFLE, C.BEG], "偷看结果只给打出者")
	assert_gt(mine["peek_seq"], 0)
	assert_eq(session.private_view(2)["peek"], [])
	assert_eq(session.private_view(2)["hand"], [C.SKIP])
	_ok(1, {"kind": "draw"})
	mine = session.private_view(1)
	assert_eq(mine["last_drawn"], C.BOMB)
	assert_eq(mine["peek"], [], "摸牌后偷看作废")
	assert_eq(mine["reinsert"], {"deck_count": 3})
	assert_eq(session.private_view(2)["reinsert"], {})
	assert_eq(session.viewers(), [1, 2, 3])


func test_private_view_keys_are_stable():
	var view := session.private_view(2)
	var keys := view.keys()
	keys.sort()
	assert_eq(keys, ["alive", "draw_seq", "give", "hand", "last_drawn", "peek", "peek_seq", "reinsert", "transfer"])


func test_estimate_sums_the_pacing_budget():
	var events := [{"type": "played"}, {"type": "noped"}, {"type": "window_resolved"},
		{"type": "effect", "kind": "steal", "got": true}, {"type": "effect", "kind": "beg", "got": false},
		{"type": "drew"}, {"type": "bomb_drawn"}, {"type": "exploded"}, {"type": "turn_passed"}, {"type": "match_over"}]
	var expected := BombCatPacing.PLAYED + BombCatPacing.NOPED + BombCatPacing.WINDOW_RESOLVED + BombCatPacing.EFFECT_SNACK_TRANSFER \
		+ BombCatPacing.EFFECT_MISS + BombCatPacing.DREW + BombCatPacing.BOMB_DRAWN + BombCatPacing.EXPLODED \
		+ BombCatPacing.TURN_PASSED + BombCatPacing.MATCH_OVER
	assert_almost_eq(session.estimate(events), expected, EPS)
	assert_eq(session.estimate([{"type": "bogus"}]), 0.0)


func test_names():
	assert_eq(session.name_of(2), "乙")
	assert_eq(session.name_of(9), "9")
	assert_eq(session.seats_with_patrons(), [1, 2, 3])
