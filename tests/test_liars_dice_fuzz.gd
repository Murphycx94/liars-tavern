extends GutTest
# 吹牛骰子随机自对弈(设计稿 §4):几百局固定种子(2–6 人),随机合法喊价 / 「开!」+ 随机超时 + 偶尔断线 +
# 夹杂的垃圾意图,经会话驱动。每一步检查不变量:骰子只会因为输了「开!」(每次恰好 −1)或断线而减少、
# 每人的骰子数从不增加、开盅前公共事件与公共视图不含点数、开盅的点数与判定属实、出价严格递增且不超过总数、
# 私有视图与引擎一致、计时时长为正;每局必须在步数上限内结束,且恰好一个胜者。


const H := preload("res://tests/liars_dice_helpers.gd")
const GAMES := 400
const MAX_STEPS := 3000

var _failures := 0   # 只把第一处失败的细节报出来,免得一处 bug 刷出成千上万条
var _seen := {}      # 事件类型(及几种细分)-> 出现次数:确认自对弈真的走到了每条路径
var _left_this_game := false


func test_random_self_play_keeps_every_invariant():
	var steps_total := 0
	for game in GAMES:
		steps_total += _play_one(game)
		if _failures > 0:
			break
	assert_eq(_failures, 0, "自对弈全部不变量成立")
	gut.p("吹牛骰子自对弈:%d 局,共 %d 步;%s" % [GAMES, steps_total, str(_seen)])
	for type in H.EVENT_KEYS:
		assert_gt(_seen.get(type, 0), 0, "走到过 %s" % type)
	for key in ["truthful", "bluff", "auto_bid", "auto_challenge", "out_by_challenge_then_win", "left_with_a_bid_standing"]:
		assert_gt(_seen.get(key, 0), 0, "走到过 %s" % key)
	for n in range(LiarsDiceState.MIN_PLAYERS, LiarsDiceState.MAX_PLAYERS + 1):
		assert_gt(_seen.get("players_%d" % n, 0), 0, "%d 人局" % n)


func _check(cond: bool, what: String) -> bool:
	if not cond and _failures == 0:
		fail_test(what)
	if not cond:
		_failures += 1
	return cond


func _play_one(game: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2000 + game
	var n := rng.randi_range(LiarsDiceState.MIN_PLAYERS, LiarsDiceState.MAX_PLAYERS)
	_seen["players_%d" % n] = _seen.get("players_%d" % n, 0) + 1
	var pids := []
	var names := {}
	for i in n:
		pids.append(200 + i * 3)
		names[200 + i * 3] = "玩家%d" % i
	_left_this_game = false
	var session := LiarsDiceSession.new()
	var engine_rng := RandomNumberGenerator.new()
	engine_rng.seed = 9000 + game
	var events := session.start(pids, names, engine_rng)
	var s := session.state()
	var tag := "第 %d 局(%d 人)" % [game, n]
	_check(s.total_dice() == n * LiarsDiceState.DICE_PER_PLAYER, "%s 开局骰子总数不对" % tag)
	_check_batch(session, {}, events, tag, rng)
	var match_overs := 0
	var steps := 0
	while not session.is_over() and steps < MAX_STEPS and _failures == 0:
		steps += 1
		var before := _snapshot(s)
		var result := _random_step(session, s, rng, tag)
		if result.is_empty() or not result["ok"]:
			continue
		_check_batch(session, before, result["events"], tag, rng)
		match_overs += result["events"].filter(func(ev: Dictionary) -> bool: return ev["type"] == "match_over").size()
	if _failures > 0:
		return steps
	_check(session.is_over(), "%s 在 %d 步内没有结束" % [tag, MAX_STEPS])
	_check(match_overs == 1, "%s match_over 出现 %d 次" % [tag, match_overs])
	var alive := s.alive_pids()
	_check(alive.size() == 1 and alive[0] == s.winner_pid, "%s 恰好一个有骰子的胜者:%s / %s" % [tag, str(alive), str(s.winner_pid)])
	var ranking: Array = session.public_view(0.0)["ranking"].map(func(row: Dictionary): return row["pid"])
	var sorted_ranking := ranking.duplicate()
	sorted_ranking.sort()
	_check(sorted_ranking == pids, "%s 名次包含每人一次:%s" % [tag, str(ranking)])
	_check(ranking[0] == s.winner_pid, "%s 第 1 名是胜者" % tag)
	if not _left_this_game:
		_seen["out_by_challenge_then_win"] = _seen.get("out_by_challenge_then_win", 0) + 1
	return steps


func _snapshot(s: LiarsDiceState) -> Dictionary:
	return {
		"counts": s.dice_counts(),
		"dice": s.dice.duplicate(true),
		"bid": s.bid.duplicate(),
		"current": s.current_pid,
		"round": s.round_no,
		"total": s.total_dice(),
	}


func _random_step(session: LiarsDiceSession, s: LiarsDiceState, rng: RandomNumberGenerator, tag: String) -> Dictionary:
	var roll := rng.randf()
	if roll < 0.004:
		var alive := s.alive_pids()
		var had_bid := not s.bid.is_empty()
		var events := session.on_disconnect(alive[rng.randi_range(0, alive.size() - 1)])
		if not events.is_empty():
			_left_this_game = true
			if had_bid:
				_seen["left_with_a_bid_standing"] = _seen.get("left_with_a_bid_standing", 0) + 1
		return {"ok": true, "events": events} if not events.is_empty() else {}
	if roll < 0.05:
		_garbage(session, s, rng, tag)
		return {}
	if roll < 0.12:
		return session.on_turn_timeout()
	var cur: int = s.current_pid
	var total := s.total_dice()
	if not s.bid.is_empty():
		# 喊得越接近总数越想开
		var pressure := clampf(float(s.bid["count"]) / float(total) * 1.6, 0.1, 0.95)
		if rng.randf() < pressure or LiarsDiceState.min_raise(s.bid, total).is_empty():
			return _accepted(session, cur, {"kind": "challenge"}, tag)
	var options := []
	var min_count: int = s.bid["count"] if not s.bid.is_empty() else 1
	for count in range(min_count, mini(min_count + 2, total) + 1):
		for face in range(LiarsDiceState.MIN_BID_FACE, LiarsDiceState.FACES + 1):
			if LiarsDiceState.bid_error(count, face, s.bid, total) == "":
				options.append([count, face])
	if options.is_empty():
		return _accepted(session, cur, {"kind": "challenge"}, tag)
	var pick: Array = options[rng.randi_range(0, options.size() - 1)]
	return _accepted(session, cur, {"kind": "bid", "count": pick[0], "face": pick[1]}, tag)


func _accepted(session: LiarsDiceSession, pid: int, intent: Dictionary, tag: String) -> Dictionary:
	# 按引擎局面挑出来的都是合法意图:必须被接受
	var result := session.handle_intent(pid, intent)
	_check(result["ok"], "%s 合法意图被拒:%s %s → %s" % [tag, pid, str(intent), str(result.get("error"))])
	return result


func _garbage(session: LiarsDiceSession, s: LiarsDiceState, rng: RandomNumberGenerator, tag: String) -> void:
	# 夹杂的非法意图:必须被拒,且局面一点不变
	var before := _snapshot(s)
	var pid: int = s.seat_order[rng.randi_range(0, s.seat_order.size() - 1)]
	var total := s.total_dice()
	var junk := [
		{"kind": "bid", "count": total + 1, "face": 3},
		{"kind": "bid", "count": 2, "face": 1},
		{"kind": "bid", "count": 0, "face": 4},
		{"kind": "bid", "count": 2.0, "face": 4},
		{"kind": "bid", "count": 2, "face": "4"},
		{"kind": "bid", "count": 2, "face": 4, "sneaky": [1]},
		{"kind": "challenge", "pid": pid},
		{"kind": "challenge"} if pid != s.current_pid or s.bid.is_empty() else {"kind": "nope"},
		{"kind": "bid", "count": 1, "face": 2} if pid != s.current_pid or not s.bid.is_empty() else {"kind": 5},
		{"kind": 12},
		{},
	]
	if not s.bid.is_empty():
		junk.append({"kind": "bid", "count": s.bid["count"], "face": s.bid["face"]})
	var intent: Dictionary = junk[rng.randi_range(0, junk.size() - 1)]
	var result := session.handle_intent(pid, intent)
	_check(not result["ok"], "%s 垃圾意图被接受:%s %s" % [tag, pid, str(intent)])
	_check(_snapshot(s) == before, "%s 被拒的意图改了局面:%s" % [tag, str(intent)])


func _check_batch(session: LiarsDiceSession, before: Dictionary, events: Array, tag: String, rng: RandomNumberGenerator) -> void:
	var s := session.state()
	var lost := 0
	var removed := 0
	var challenge := {}
	var revealed := {}
	var die_lost := []
	for ev in events:
		var type: String = ev["type"]
		_seen[type] = _seen.get(type, 0) + 1
		var leak := H.event_leak(ev)
		if not _check(leak == "", "%s 公共事件漏信息:%s %s" % [tag, leak, str(ev)]):
			return
		match type:
			"die_lost":
				lost += 1
				die_lost.append(ev)
			"player_left":
				removed += ev["removed"]
			"challenged":
				challenge = ev
				if ev["auto"]:
					_seen["auto_challenge"] = _seen.get("auto_challenge", 0) + 1
			"revealed":
				revealed = ev
				_seen["truthful" if ev["truthful"] else "bluff"] = _seen.get("truthful" if ev["truthful"] else "bluff", 0) + 1
			"bid":
				if ev["auto"]:
					_seen["auto_bid"] = _seen.get("auto_bid", 0) + 1
	# —— 骰子守恒:只因输了「开!」(恰好一颗)或断线而减少,每人从不增加 ——
	if not before.is_empty():
		_check(before["total"] - s.total_dice() == lost + removed,
			"%s 骰子总数 %d → %d,但丢了 %d、断线移出 %d" % [tag, before["total"], s.total_dice(), lost, removed])
		for pid in s.seat_order:
			_check(s.dice_count(pid) <= before["counts"][pid], "%s %d 的骰子变多了" % [tag, pid])
	_check(challenge.is_empty() == revealed.is_empty(), "%s 「开!」与开盅要成对出现" % tag)
	if not challenge.is_empty():
		_check(lost == 1, "%s 一次「开!」丢了 %d 颗" % [tag, lost])
		_check(challenge["count"] == before["bid"]["count"] and challenge["face"] == before["bid"]["face"]
			and challenge["target"] == before["bid"]["pid"] and challenge["pid"] == before["current"], "%s 开的不是上一口" % tag)
		# 开盅的点数是开之前那一盅,实际个数与判定属实,输家对
		var shown := []
		var actual := 0
		for pid in s.seat_order:
			if not before["dice"][pid].is_empty():
				shown.append({"pid": pid, "dice": before["dice"][pid]})
				for value in before["dice"][pid]:
					if value == challenge["face"] or value == LiarsDiceState.WILD_FACE:
						actual += 1
		_check(revealed["dice"] == shown, "%s 开盅的点数不是这一盅" % tag)
		_check(revealed["actual"] == actual and revealed["truthful"] == (actual >= challenge["count"]), "%s 开盅判定不对" % tag)
		var loser = challenge["pid"] if revealed["truthful"] else challenge["target"]
		_check(die_lost[0]["pid"] == loser and die_lost[0]["left"] == before["counts"][loser] - 1, "%s 丢骰子的不是输家" % tag)
	# —— 出价:本轮严格递增,不超过当时的总数 ——
	var prev := {}
	for b in s.bids:
		_check(LiarsDiceState.is_higher(b["count"], b["face"], prev) and b["count"] <= s.total_dice()
			and LiarsDiceState.is_valid_face(b["face"]), "%s 出价记录不合法:%s" % [tag, str(s.bids)])
		prev = b
	# —— 视图 ——
	var view := session.public_view(rng.randf_range(0.0, 30.0))
	_check(H.view_leak(view, s) == "", "%s 公共视图漏信息:%s" % [tag, H.view_leak(view, s)])
	var counted := 0
	for row in view["players"]:
		counted += row["dice_count"]
		_check(row["alive"] == (row["dice_count"] > 0) and row["dice_count"] <= LiarsDiceState.DICE_PER_PLAYER,
			"%s 玩家行不一致:%s" % [tag, str(row)])
	_check(counted == view["total_dice"], "%s 公共视图的骰子数加起来不等于总数" % tag)
	for pid in session.viewers():
		var priv := session.private_view(pid)
		_check(priv["dice"] == s.dice_of(pid) and priv["round"] == s.round_no, "%s 私有视图不符" % tag)
		if not s.is_alive(pid):
			_check(priv["dice"].is_empty() and not priv["alive"], "%s 出局者还有骰子" % tag)
	if not session.is_over():
		var duration := session.turn_timer_after(events, rng.randf_range(0.0, 8.0), rng.randf_range(0.0, 30.0))
		_check(duration > 0.0 and duration <= Protocol.TURN_TIMEOUT + 60.0, "%s 计时时长不合理:%f" % [tag, duration])
		_check(s.current_pid != null and s.is_alive(s.current_pid), "%s 当前玩家不在场" % tag)
		_check(s.alive_pids().size() >= 2, "%s 没结束却只剩不到两人" % tag)
