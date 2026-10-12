class_name BlackjackViews
# 21 点视图构建(设计稿 §3):所有人一样的公共视图;庄家暗牌翻开之前不在里面。21 点没有私有视图。
# 只用 BjTable 的只读访问。


const PHASE_NAMES := {
	BjTable.Phase.IDLE: "idle", BjTable.Phase.BETTING: "betting", BjTable.Phase.PLAYING: "playing",
	BjTable.Phase.OVER: "over",
}


static func public_view(t: BjTable, names: Dictionary, turn_time_left := 0.0) -> Dictionary:
	# turn_time_left:房主计时器的剩余秒数(含客户端要先播完的演出);下注阶段是下注的限时,没人在计时为 0
	var dealer := t.dealer_cards()
	var score := BjScore.evaluate(dealer)
	var current: Variant = t.current()
	var timed := t.phase() == BjTable.Phase.BETTING or current != null
	return {
		"mode": GameMode.BLACKJACK,
		"round": t.round_number(),
		"phase": PHASE_NAMES[t.phase()],
		"shoe_left": t.shoe_left(),
		"shoe_size": BjShoe.size(),
		"limits": [BjRules.MIN_BET, BjRules.MAX_BET, BjRules.BET_UNIT],
		"dealer": {"cards": dealer, "hidden": t.dealer_hidden(), "total": score["total"], "soft": score["soft"]},
		"current": current,
		"actions": actions(t),
		"seats": t.seats_with_patrons(),
		"players": players(t, names),
		"turn_time_left": maxf(turn_time_left, 0.0) if timed else 0.0,
		"ending": t.is_ending(),
		"results": results(t, names) if t.phase() == BjTable.Phase.OVER else [],
	}


static func actions(t: BjTable) -> Dictionary:
	# 当前决策者的可选动作(与 legal_actions 一致,多一个 pid);没人在决策时为 {}
	var pid: Variant = t.current_pid()
	if pid == null:
		return {}
	var legal := t.legal_actions(pid)
	return {} if legal.is_empty() else {"pid": pid}.merged(legal)


static func players(t: BjTable, names: Dictionary) -> Array:
	# 按座位顺序;还没登场的新人排在最后
	var rows := []
	for pid in t.seat_order():
		var row := t.player(pid)
		row["pid"] = pid
		row["name"] = names.get(pid, str(pid))
		rows.append(row)
	return rows


static func results(t: BjTable, names: Dictionary) -> Array:
	var rows := []
	for row in t.results():
		var named: Dictionary = row.duplicate()
		named["name"] = names.get(row["pid"], str(row["pid"]))
		rows.append(named)
	return rows
