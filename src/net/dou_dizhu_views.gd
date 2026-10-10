class_name DouDizhuViews
# 斗地主视图构建:决定每个客户端能看到什么。只用 DdzState 的只读访问。
# 公共视图所有人一样,不含任何人的手牌(带牌 id 的只有 bottom(定地主后)、lead.cards、players[].table、
# last_hand.remaining,都是已经公开的牌);私有视图只有自己的手牌与提示。字段说明见设计稿「实施记录(阶段一)」。


const MAX_HINTS := 40   # 提示最多给这么多个(小的在前;自由出牌时顺子各种长度会列出很多)


static func public_view(s: DdzState, names: Dictionary, turn_time_left := 0.0) -> Dictionary:
	# turn_time_left:房主计时器剩余秒数(含客户端要先播完的演出);没人在行动时为 0
	var acting := s.current_pid != null and (s.phase == DdzState.Phase.BIDDING or s.phase == DdzState.Phase.PLAYING)
	return {
		"mode": GameMode.DOU_DIZHU,
		"hand": s.hand_number,
		"phase": s.phase_name(),
		"deal": s.deal_number,
		"first_bidder": s.first_bidder,
		"bids": s.bids.duplicate(true),
		"highest_bid": s.highest_bid,
		"current_pid": s.current_pid,
		"landlord": s.landlord,
		"base": s.base,
		"multiplier": s.multiplier,
		"bombs": s.bombs,
		"bottom": s.bottom.duplicate() if s.bottom_taken else [],
		"lead": _lead(s),
		"passes": s.passes,
		"players": players(s, names),
		"turn_time_left": maxf(turn_time_left, 0.0) if acting else 0.0,
		"ending": s.ending,
		"last_hand": s.last_hand.duplicate(true),
		"results": results(s, names) if s.phase == DdzState.Phase.OVER else [],
		"end_reason": s.end_reason,
	}


static func private_view(s: DdzState, pid: int) -> Dictionary:
	var cards := s.hand_of(pid)
	var hints := []
	for p in s.legal_plays_for(pid).slice(0, MAX_HINTS):
		hints.append({"indices": DdzState.indices_of(cards, p["cards"]), "type": p["type"]})
	return {
		"hand": s.hand_number,
		"cards": cards,                                 # 升序;意图 play 的下标就是它
		"role": s.role_of(pid),
		"trustee": s.trustee.get(pid, false),
		"my_turn": s.current_pid == pid,
		"can_pass": s.can_pass(pid),
		"bid_options": s.bid_options(pid),
		"hints": hints,
	}


static func players(s: DdzState, names: Dictionary) -> Array:
	# 按座位顺序
	var rows := []
	for pid in s.seat_order:
		rows.append({
			"pid": pid,
			"name": names.get(pid, str(pid)),
			"hand_count": s.hands.get(pid, []).size(),
			"score": s.scores[pid],
			"role": s.role_of(pid),
			"trustee": s.trustee[pid],
			"table": s.table.get(pid, {}).get("cards", []).duplicate(),
			"passed": s.table.get(pid, {}).get("pass", false),
			"plays": s.play_counts.get(pid, 0),
			"left": s.left.has(pid),
		})
	return rows


static func results(s: DdzState, names: Dictionary) -> Array:
	return s.results().map(func(row: Dictionary) -> Dictionary:
		return row.merged({"name": names.get(row["pid"], str(row["pid"]))}, true))


static func _lead(s: DdzState) -> Dictionary:
	if s.lead.is_empty():
		return {}
	var l := s.lead
	return {"pid": l["pid"], "cards": l["cards"].duplicate(), "type": l["type"], "rank": l["rank"],
		"length": l["length"], "count": l["count"]}
