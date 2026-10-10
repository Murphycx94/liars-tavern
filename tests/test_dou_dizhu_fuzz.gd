extends GutTest
# 斗地主随机自对局(设计稿 §4):几百个固定种子的牌局,经会话驱动——随机叫分、随机挑提示出牌、随机不出、
# 随机超时、开关托管、夹杂垃圾意图、偶尔散局或断线;一手打完就开下一手,打够随机手数后房主散局。
# 每一步检查不变量:54 张牌只在手牌 / 已出 / 底牌之间流转、公共事件与公共视图不漏没公开的牌、私有视图与引擎一致、
# 被拒的意图不改局面、计时器时长为正、累计分总和为 0、每手结算的 delta 总和为 0;每个牌局必须在步数上限内结算。


const D := preload("res://tests/ddz_helpers.gd")
const H := preload("res://src/core/dou_dizhu/ddz_hand.gd")
const P := DdzState.Phase
const GAMES := 250
const MAX_STEPS := 6000
const PIDS := [1, 20, 300]

var _failures := 0   # 只把第一处失败的细节报出来
var _seen := {}      # 事件类型、牌型(combo:xx)与特殊情形的出现次数:确认真的走到了每条路径


func test_random_self_play_keeps_every_invariant():
	var steps_total := 0
	var hands_total := 0
	for game in GAMES:
		var r := _play_one(game)
		steps_total += r[0]
		hands_total += r[1]
		if _failures > 0:
			break
	assert_eq(_failures, 0, "自对局全部不变量成立")
	gut.p("斗地主自对局:%d 局、%d 手、%d 步;%s" % [GAMES, hands_total, steps_total, str(_seen)])
	for type in D.EVENT_KEYS:
		assert_gt(_seen.get(type, 0), 0, "走到过 %s" % type)
	for combo in [H.SINGLE, H.PAIR, H.TRIPLE, H.TRIPLE_SINGLE, H.TRIPLE_PAIR, H.STRAIGHT, H.PAIR_STRAIGHT, H.AIRPLANE,
			H.BOMB, H.ROCKET]:
		assert_gt(_seen.get("combo:" + combo, 0), 0, "出过 %s" % combo)
	for what in ["spring", "forced", "auto_trustee", "rejected", "player_left_mid_hand"]:
		assert_gt(_seen.get(what, 0), 0, "走到过 %s" % what)


func _check(cond: bool, what: String) -> bool:
	if not cond and _failures == 0:
		fail_test(what)
	if not cond:
		_failures += 1
	return cond


func _play_one(game: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + game
	var session := DouDizhuSession.new()
	var engine_rng := RandomNumberGenerator.new()
	engine_rng.seed = 9000 + game
	var names := {1: "甲", 20: "乙", 300: "丙"}
	var tag := "第 %d 局" % game
	_check_batch(session, session.start(PIDS, names, engine_rng), tag)
	var s := session.state()
	var target_hands := rng.randi_range(1, 4)
	var steps := 0
	while not session.is_over() and steps < MAX_STEPS and _failures == 0:
		steps += 1
		var events := _step(session, s, rng, target_hands, tag)
		if not events.is_empty():
			_check_batch(session, events, "%s 第 %d 步" % [tag, steps])
	_check(session.is_over(), "%s 在 %d 步内没结算" % [tag, MAX_STEPS])
	return [steps, s.hand_number]


func _step(session: DouDizhuSession, s: DdzState, rng: RandomNumberGenerator, target_hands: int, tag: String) -> Array:
	if not session.has_turn():
		_check(session.next_hand_ready(), "%s 没人行动也不能开下一手" % tag)
		if s.hand_number >= target_hands or rng.randf() < 0.05:
			return session.request_end()
		return session.start_next_hand()
	var roll := rng.randf()
	if roll < 0.002:
		var gone: int = PIDS[rng.randi_range(0, 2)]
		if s.phase == P.PLAYING:
			_seen["player_left_mid_hand"] = _seen.get("player_left_mid_hand", 0) + 1
		return session.on_disconnect(gone)
	if roll < 0.006 and not s.ending:
		return session.request_end()
	if roll < 0.06:
		_garbage(session, s, rng, tag)
		return []
	if roll < 0.09:
		var who: int = PIDS[rng.randi_range(0, 2)]
		return _accept(session, who, {"kind": "trustee", "on": rng.randf() < 0.5}, tag)
	if roll < 0.22:
		var t := session.on_turn_timeout()
		_check(t["ok"] and t["turn_action"], "%s 超时代打失败 %s" % [tag, str(t)])
		return t["events"]
	var pid: int = s.current_pid
	var view := session.private_view(pid)
	if s.phase == P.BIDDING:
		var options: Array = view["bid_options"]
		var score: int = 0 if rng.randf() < 0.65 else options[rng.randi_range(0, options.size() - 1)]
		return _accept(session, pid, {"kind": "bid", "score": score}, tag)
	if view["can_pass"] and rng.randf() < 0.25:
		return _accept(session, pid, {"kind": "pass"}, tag)
	var hints: Array = view["hints"]
	if hints.is_empty():
		_check(view["can_pass"], "%s 自由出牌却没有提示" % tag)
		return _accept(session, pid, {"kind": "pass"}, tag)
	# 偏向小的组合,偶尔挑后面的(炸弹、王炸)
	var i := rng.randi_range(0, mini(hints.size() - 1, 2)) if rng.randf() < 0.8 else rng.randi_range(0, hints.size() - 1)
	return _accept(session, pid, {"kind": "play", "cards": hints[i]["indices"]}, tag)


func _accept(session: DouDizhuSession, pid: int, intent: Dictionary, tag: String) -> Array:
	var r := session.handle_intent(pid, intent)
	_check(r["ok"], "%s 合法意图被拒 %s → %s" % [tag, str(intent), str(r)])
	return r.get("events", [])


func _garbage(session: DouDizhuSession, s: DdzState, rng: RandomNumberGenerator, tag: String) -> void:
	# 不合法的意图:被拒且局面不变
	var not_current: int = PIDS.filter(func(p: int) -> bool: return p != s.current_pid)[rng.randi_range(0, 1)]
	var hand_size: int = s.hands[s.current_pid].size()
	var bads := [
		[s.current_pid, {"kind": "play", "cards": [hand_size]}],
		[s.current_pid, {"kind": "play", "cards": [0, 0]}],
		[s.current_pid, {"kind": "bid", "score": 5}],
		[s.current_pid, {"kind": "bogus"}],
		[s.current_pid, {"kind": "pass", "extra": true}],
		[not_current, {"kind": "pass"}],
		[not_current, {"kind": "bid", "score": 3}],
		[not_current, {"kind": "play", "cards": [0]}],
		[999, {"kind": "trustee", "on": true}],
	]
	if s.phase == P.PLAYING and s.lead.is_empty():
		bads.append([s.current_pid, {"kind": "pass"}])
	if s.phase == P.BIDDING:
		bads.append([s.current_pid, {"kind": "play", "cards": [0]}])
		if s.highest_bid > 0:
			bads.append([s.current_pid, {"kind": "bid", "score": s.highest_bid}])
	var pick: Array = bads[rng.randi_range(0, bads.size() - 1)]
	var before := _snapshot(session)
	var r := session.handle_intent(pick[0], pick[1])
	_check(not r["ok"], "%s 垃圾意图被接受 %s" % [tag, str(pick)])
	_check(r.get("events", []).is_empty(), "%s 被拒还有事件" % tag)
	_check(_snapshot(session) == before, "%s 被拒改了局面 %s" % [tag, str(pick)])
	_seen["rejected"] = _seen.get("rejected", 0) + 1


func _snapshot(session: DouDizhuSession) -> String:
	var parts := [session.public_view(0.0)]
	for pid in PIDS:
		parts.append(session.private_view(pid))
	return var_to_str(parts)


func _check_batch(session: DouDizhuSession, events: Array, tag: String) -> void:
	var s := session.state()
	var after_hand: bool = s.phase == P.BETWEEN or (s.phase == P.OVER and s.last_hand.get("hand", 0) == s.hand_number)
	var revealed := D.revealed_cards(s, after_hand)
	for ev in events:
		var type: String = ev["type"]
		_seen[type] = _seen.get(type, 0) + 1
		_check(D.event_leak(ev, revealed) == "" or type == "session_over", "%s %s" % [tag, D.event_leak(ev, revealed)])
		match type:
			"played":
				_seen["combo:" + ev["combo"]] = _seen.get("combo:" + ev["combo"], 0) + 1
			"landlord":
				if ev["forced"]:
					_seen["forced"] = _seen.get("forced", 0) + 1
			"trustee":
				if ev["auto"]:
					_seen["auto_trustee"] = _seen.get("auto_trustee", 0) + 1
			"hand_over":
				if ev["spring"]:
					_seen["spring"] = _seen.get("spring", 0) + 1
				var sum := 0
				for row in ev["deltas"]:
					sum += row["delta"]
				_check(sum == 0, "%s 一手结算总和 %d" % [tag, sum])
				_check(ev["multiplier"] >= 1 and ev["base"] >= 1 and ev["base"] <= 3, "%s 底分 / 倍数不对 %s" % [tag, str(ev)])
			"session_over":
				var total := 0
				for row in ev["results"]:
					total += row["score"]
					_check(row.has("name"), "%s 结算行没有名字" % tag)
				_check(total == 0, "%s 牌局结算总和 %d" % [tag, total])
	_check(s.card_count() == 54, "%s 牌数 %d" % [tag, s.card_count()])
	var total := 0
	for pid in PIDS:
		total += s.scores[pid]
	_check(total == 0, "%s 累计分总和 %d" % [tag, total])
	var view := session.public_view(1.0)
	_check(D.view_leak(view, revealed) == "", "%s %s" % [tag, D.view_leak(view, revealed)])
	for row in view["players"]:
		_check(row["hand_count"] == s.hands[row["pid"]].size(), "%s 手牌张数不一致" % tag)
	for pid in session.viewers():
		var priv := session.private_view(pid)
		_check(priv["cards"] == s.hand_of(pid), "%s 私有视图手牌不一致" % tag)
		_check(priv["cards"] == H.sorted(priv["cards"]), "%s 手牌没排序" % tag)
		for hint in priv["hints"]:
			var cards: Array = hint["indices"].map(func(i: int) -> int: return priv["cards"][i])
			if not _check(not H.match_lead(cards, s.lead_combo()).is_empty(), "%s 提示出不了 %s" % [tag, H.labels(cards)]):
				break
	if session.has_turn():
		_check(session.turn_timer_after(events, 0.0, 0.0) > 0.0, "%s 计时时长不为正" % tag)
		_check(s.current_pid != null and s.hands[s.current_pid].size() > 0, "%s 当前行动者没牌" % tag)
	else:
		_check(s.phase == P.BETWEEN or s.phase == P.OVER, "%s 没人行动却在叫分 / 出牌" % tag)
