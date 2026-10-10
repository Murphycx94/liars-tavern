class_name LiarsDiceBot
extends RefCounted
# 吹牛骰子的机器人(调试开关 --bot 与无头流程测试共用):每次 act() 走一步,只通过牌桌的公开入口出手
# (set_pick → nudge_count / pick_face,submit_bid / submit_challenge),和真人点出价器、按快捷键是同一条路径。
# 想法同 tests/test_liars_dice_fuzz.gd 的 _random_step:喊得越接近场上总数越想开;加注从最小合法的个数起往上挑一两个,
# 再按自己手里的点数偏一偏(手里多的点数更敢喊)。估计全场个数 = 自己算进去的 + 别人骰子数 / 3(每颗 1/3 的概率是 X 或 1 点)。


const BLUFF_MARGIN := 1.0       # 上一口比估计多出这么多就倾向于开
const CHALLENGE_FLOOR := 0.08   # 怎么都有一点概率开
const RAISE_SPAN := 2           # 加注的个数从最小合法值往上最多加这么多

var rng := RandomNumberGenerator.new()


func _init(seed_value := 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


static func expected_count(face: int, mine: Array, total: int) -> float:
	# 全场 face 点(含 1 点)的期望个数:自己的按实数,别人的每颗 1/3
	var own := LiarsDiceScreenState.count_matches(mine, face)
	return own + maxf(total - mine.size(), 0) / 3.0


func choose(bid: Dictionary, total: int, mine: Array) -> Dictionary:
	# 纯函数式的决定:{"kind": "challenge"} 或 {"kind": "bid", "count", "face"};总是合法(不能加注时一定开)
	var raise := LiarsDiceState.min_raise(bid, total)
	if not bid.is_empty():
		var over: float = bid["count"] - expected_count(bid["face"], mine, total)
		var pressure := clampf(CHALLENGE_FLOOR + over * 0.3 + float(bid["count"]) / maxf(total, 1) * 0.5, CHALLENGE_FLOOR, 0.95)
		if raise.is_empty() or (over >= BLUFF_MARGIN and rng.randf() < pressure) or rng.randf() < pressure * 0.4:
			return {"kind": "challenge"}
	var options := []
	var lo := LiarsDicePicker.min_count(bid)
	for count in range(lo, mini(lo + RAISE_SPAN, total) + 1):
		for face in range(LiarsDiceState.MIN_BID_FACE, LiarsDiceState.FACES + 1):
			if LiarsDiceState.bid_error(count, face, bid, total) == "":
				var weight := 1.0 + LiarsDiceScreenState.count_matches(mine, face) * 1.5 - (count - lo) * 0.6
				options.append([maxf(weight, 0.1), count, face])
	if options.is_empty():
		return {"kind": "challenge"} if not bid.is_empty() else {"kind": "bid", "count": 1, "face": LiarsDiceState.MIN_BID_FACE}
	var sum := 0.0
	for o in options:
		sum += o[0]
	var pick := rng.randf() * sum
	for o in options:
		pick -= o[0]
		if pick <= 0.0:
			return {"kind": "bid", "count": o[1], "face": o[2]}
	var last: Array = options[-1]
	return {"kind": "bid", "count": last[1], "face": last[2]}


func act(screen: Node) -> bool:
	# 走一步;这一刻没什么可做时返回 false
	if screen.settlement() != null or not screen.is_my_turn():
		return false
	var state: LiarsDiceScreenState = screen.state
	var decision := choose(state.pub_bid(), state.pub_total(), state.shown_dice)
	if decision["kind"] == "challenge":
		return screen.submit_challenge()
	screen.set_pick(decision["count"], decision["face"])
	return screen.submit_bid()
