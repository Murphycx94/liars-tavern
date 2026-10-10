class_name LiarsDiceViews
# 吹牛骰子视图构建:决定每个客户端能看到什么。只用 LiarsDiceState 的只读访问。
# 公共视图所有人一样,不含本轮任何人的点数(只有每人骰子数、出价记录;last_reveal 是上一次开盅、已经公开的结果);
# 私有视图只有自己本轮的点数。字段说明见设计稿「实施记录(阶段一)」。


static func public_view(s: LiarsDiceState, names: Dictionary, turn_time_left := 0.0) -> Dictionary:
	# turn_time_left:房主计时器剩余秒数(含客户端要先播完的演出);over 时为 0
	var over := s.step == LiarsDiceState.Step.OVER
	return {
		"mode": GameMode.LIARS_DICE,
		"step": s.step_name(),
		"round": s.round_no,
		"starter_pid": s.starter_pid,
		"current_pid": s.current_pid,
		"bid": s.bid.duplicate(),
		"bids": s.bids.duplicate(true),
		"total_dice": s.total_dice(),
		"players": players(s, names),
		"last_reveal": s.last_reveal.duplicate(true),
		"out_order": s.out_order.duplicate(),
		"winner": s.winner_pid,
		"ranking": ranking(s, names) if over else [],
		"turn_time_left": 0.0 if over else maxf(turn_time_left, 0.0),
	}


static func private_view(s: LiarsDiceState, pid: int) -> Dictionary:
	# round 与 round_started 事件的 round 对得上:界面据此判断这是不是新摇的一盅
	return {
		"dice": s.dice_of(pid),
		"alive": s.is_alive(pid),
		"round": s.round_no,
	}


static func players(s: LiarsDiceState, names: Dictionary) -> Array:
	# 按座位顺序
	var rows := []
	for pid in s.seat_order:
		rows.append({
			"pid": pid,
			"name": names.get(pid, str(pid)),
			"alive": s.is_alive(pid),
			"dice_count": s.dice_count(pid),
		})
	return rows


static func ranking(s: LiarsDiceState, names: Dictionary) -> Array:
	# 结算名次:第 1 名是胜者,其后按出局顺序倒排
	var rows := []
	var order := [s.winner_pid]
	for i in range(s.out_order.size() - 1, -1, -1):
		order.append(s.out_order[i])
	for i in order.size():
		rows.append({"pid": order[i], "name": names.get(order[i], str(order[i])), "place": i + 1})
	return rows
