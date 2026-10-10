class_name LiarsDiceState
# 吹牛骰子规则引擎(设计稿 §1、§2):仅在房主端运行,不依赖节点/网络/UI。
# 每个改动局面的方法返回 {"ok": bool, "error"?: String, "events": Array};被拒时局面不变、events 为空。
# 公共事件广播给全员,**开盅之前不含任何人的点数**;点数只经 dice_of 给私有视图,
# 「开!」那一刻才把全场点数放进 revealed 事件(之后成为公开信息,也留在 last_reveal 里)。
#
# —— 局面 ——
# 步骤 step:BID 当前玩家喊价或「开!」· OVER 已分胜负。没有别的等待步骤:开盅、丢骰子、下一轮重摇在同一批里完成。
# 每人开局 DICE_PER_PLAYER 颗骰子,每轮开始所有存活者重新摇(传入的 RNG,同种子可复现),骰子按点数从小到大排。
# 出价 bid = {pid, count, face}:「全场至少 count 颗 face 点」,face ∈ 2..6,1 点万能(算作任何点数,所以不能喊 1)。
#   合法加注:count 更多(face 随意),或 count 相同、face 更大;第一口 count ≥ 1;任何一口 count ≤ 场上骰子总数。
# 「开!」:质疑上一口。实际个数 = 全场 face 点 + 1 点。实际 ≥ count → 上家说真话,开的人输;否则上家吹牛,上家输。
#   输的人丢一颗骰子;丢光出局。输的人开下一轮,他出局了由他之后的下一位存活者开。只剩一人有骰子时他获胜。
# 断线 = 出局,骰子移出游戏;对局没结束就**作废本轮、全员重摇**(本轮的出价是按旧的骰子总数喊的),
#   下一轮由当前玩家开(断线的正是当前玩家时由他之后的下一位存活者开)。
# 超时代打:能加注就按最小合法加注(还没人喊时是「1 个 2」),否则「开!」。
# 骰子守恒:骰子总数只会因为输了「开!」(每次恰好 −1)或断线(−他剩下的骰子)而减少,永不增加。
#
# —— 公共事件(字段一览;pid 是玩家 id)——
#   round_started  {round, starter, seats: [pid], counts: [{pid, count}], total}
#                  新一轮开始、全员重摇(不含点数):轮次(从 1 起)、先喊的人、座次、每人骰子数(出局者 0)、场上总数。
#                  开局的第一轮也是它;私有视图随同一批更新为新摇的点数(私有视图里的 round 与它对得上)
#   bid            {pid, count, face, auto}        喊价「count 个 face」;auto = 超时代打
#   turn_passed    {pid}                           轮到 pid 喊价或「开!」(每口喊价之后都发)
#   challenged     {pid, target, count, face, auto} pid「开!」质疑 target 喊的「count 个 face」;auto = 超时代打
#   revealed       {dice: [{pid, dice: [点数]}], face, count, actual, truthful}
#                  开盅:全场存活者的点数(座位顺序)、被质疑的点数与个数、实际个数(face 点 + 1 点)、上家是否说了真话。
#                  **唯一带点数的公共事件**,且只在「开!」时出现
#   die_lost       {pid, left}                     输的人丢一颗骰子,还剩 left 颗
#   player_out     {pid}                           骰子丢光出局(紧跟在 die_lost 之后)
#   player_left    {pid, removed}                  断线出局,removed = 移出游戏的骰子数
#   match_over     {winner, ranking: [pid]}        分出胜负;ranking 第 1 名起(= 胜者 + 出局顺序倒排)
# 所有事件都有 "type" 键。典型批次:
#   开局 [round_started];喊价 [bid, turn_passed];
#   「开!」[challenged, revealed, die_lost, player_out?, round_started 或 match_over];
#   断线 [player_left, round_started 或 match_over];超时 = 喊价或「开!」的批次(auto 为真)。


enum Step { BID, OVER }

const STEP_NAMES := {Step.BID: "bid", Step.OVER: "over"}

# —— 规则常量 ——
const DICE_PER_PLAYER := 5
const FACES := 6
const WILD_FACE := 1            # 1 点万能
const MIN_BID_FACE := 2         # 能喊的点数 2..FACES
const MIN_PLAYERS := 2
const MAX_PLAYERS := 6

# —— 拒绝错误码 ——
const ERR_MATCH_OVER := "match_over"
const ERR_NOT_SEATED := "not_seated"
const ERR_OUT := "out"
const ERR_NOT_YOUR_TURN := "not_your_turn"
const ERR_INVALID_COUNT := "invalid_count"     # 个数不是整数或小于 1
const ERR_INVALID_FACE := "invalid_face"       # 点数不是 2..6 的整数(1 点万能,不能喊)
const ERR_BID_TOO_LOW := "bid_too_low"         # 没比上一口大
const ERR_BID_TOO_HIGH := "bid_too_high"       # 个数超过场上骰子总数
const ERR_NO_BID := "no_bid"                   # 本轮还没人喊价,没得开
const ERR_INVALID_INTENT := "invalid_intent"   # 会话层:意图字典的 kind 或结构不对
const ERR_INVALID_PLAYERS := "invalid_players"

const ERROR_MESSAGES := {
	ERR_MATCH_OVER: "对局已结束",
	ERR_NOT_SEATED: "你不在这一局里",
	ERR_OUT: "你已经出局了",
	ERR_NOT_YOUR_TURN: "还没轮到你",
	ERR_INVALID_COUNT: "个数至少要喊 1",
	ERR_INVALID_FACE: "点数只能喊 2–6(1 点是万能的)",
	ERR_BID_TOO_LOW: "要比上家喊得大:个数更多,或个数相同点数更大",
	ERR_BID_TOO_HIGH: "个数不能超过场上骰子的总数",
	ERR_NO_BID: "这一轮还没人喊,先喊一口",
	ERR_INVALID_INTENT: "操作不合法",
	ERR_INVALID_PLAYERS: "人数不对",
}

var rng: RandomNumberGenerator
var seat_order: Array = []
var dice := {}                  # pid -> Array[int](本轮点数,从小到大;出局者为 [])
var step := Step.OVER
var round_no := 0               # 第几轮(从 1 起)
var starter_pid = null          # 本轮先喊的人
var current_pid = null          # 轮到谁喊价或「开!」
var bid := {}                   # 当前最高的一口 {"pid", "count", "face"};本轮还没人喊为 {}
var bids: Array = []            # 本轮的出价记录 [{"pid", "count", "face"}](公开)
var last_reveal := {}           # 最近一次开盅的结果(同 revealed 事件,不含 type);还没开过为 {}
var winner_pid = null
var out_order: Array = []       # 出局顺序(丢光骰子与断线)


# —— 开局 ——

func start(player_ids: Array, p_rng: RandomNumberGenerator) -> Dictionary:
	if player_ids.size() < MIN_PLAYERS or player_ids.size() > MAX_PLAYERS:
		return _fail(ERR_INVALID_PLAYERS)
	rng = p_rng
	seat_order = player_ids.duplicate()
	dice = {}
	for pid in seat_order:
		dice[pid] = []
	out_order = []
	winner_pid = null
	last_reveal = {}
	round_no = 0
	var counts := {}
	for pid in seat_order:
		counts[pid] = DICE_PER_PLAYER
	# 先喊的人由房主 RNG 随机挑
	return _ok(_start_round(seat_order[rng.randi_range(0, seat_order.size() - 1)], counts))


# —— 当前玩家的动作 ——

func place_bid(pid, count: Variant, face: Variant, auto := false) -> Dictionary:
	# 喊「count 个 face」:比上一口大(或本轮第一口),个数不超过场上骰子总数
	var error := _check_actor(pid)
	if error != "":
		return _fail(error)
	error = bid_error(count, face, bid, total_dice())
	if error != "":
		return _fail(error)
	bid = {"pid": pid, "count": count, "face": face}
	bids.append(bid.duplicate())
	current_pid = _next_alive_after(pid)
	return _ok([
		{"type": "bid", "pid": pid, "count": count, "face": face, "auto": auto},
		{"type": "turn_passed", "pid": current_pid},
	])


func challenge(pid, auto := false) -> Dictionary:
	# 「开!」:质疑上一口。全场开盅数 face 点(1 点算作 face),输的人丢一颗骰子,接着开下一轮或结束
	var error := _check_actor(pid)
	if error != "":
		return _fail(error)
	if bid.is_empty():
		return _fail(ERR_NO_BID)
	var target = bid["pid"]
	var count: int = bid["count"]
	var face: int = bid["face"]
	var actual := count_matching(face)
	var truthful := actual >= count
	var revealed := []
	for p in seat_order:
		if is_alive(p):
			revealed.append({"pid": p, "dice": dice[p].duplicate()})
	last_reveal = {"dice": revealed, "face": face, "count": count, "actual": actual, "truthful": truthful}
	var events := [
		{"type": "challenged", "pid": pid, "target": target, "count": count, "face": face, "auto": auto},
		{"type": "revealed"}.merged(last_reveal.duplicate(true)),
	]
	var loser = pid if truthful else target
	var counts := dice_counts()
	counts[loser] -= 1
	events.append({"type": "die_lost", "pid": loser, "left": counts[loser]})
	var next_starter = loser
	if counts[loser] == 0:
		events.append({"type": "player_out", "pid": loser})
		out_order.append(loser)
		next_starter = _next_with_dice_after(loser, counts)
	if _alive_count(counts) == 1:
		_set_counts(counts)
		return _ok(events + _finish(next_starter))
	return _ok(events + _start_round(next_starter, counts))


# —— 超时代打与断线 ——

func timeout() -> Dictionary:
	# 当前玩家到点:能加注就按最小合法加注,否则「开!」
	if step == Step.OVER:
		return _fail(ERR_MATCH_OVER)
	var raise := min_raise(bid, total_dice())
	if raise.is_empty():
		return challenge(current_pid, true)
	return place_bid(current_pid, raise["count"], raise["face"], true)


func eliminate(pid) -> Dictionary:
	# 断线 = 出局,骰子移出游戏。不在局里、已出局或对局已结束返回空事件。
	# 对局没结束就作废本轮、全员重摇:由当前玩家开(断线的正是当前玩家时由他之后的下一位存活者开)
	if step == Step.OVER or not is_alive(pid):
		return _ok([])
	var counts := dice_counts()
	var removed: int = counts[pid]
	counts[pid] = 0
	out_order.append(pid)
	var events := [{"type": "player_left", "pid": pid, "removed": removed}]
	var next_starter = current_pid
	if current_pid == pid:
		next_starter = _next_with_dice_after(pid, counts)
	if _alive_count(counts) == 1:
		_set_counts(counts)
		return _ok(events + _finish(next_starter))
	return _ok(events + _start_round(next_starter, counts))


# —— 只读访问(视图、机器人与测试用)——

func is_member(pid) -> bool:
	return dice.has(pid)


func is_alive(pid) -> bool:
	return dice.has(pid) and not dice[pid].is_empty()


func alive_pids() -> Array:
	return seat_order.filter(func(pid) -> bool: return is_alive(pid))


func step_name() -> String:
	return STEP_NAMES[step]


func dice_of(pid) -> Array:
	# 私有:他本轮的点数(从小到大);出局者或不在局里为 []
	return dice.get(pid, []).duplicate()


func dice_count(pid) -> int:
	return dice.get(pid, []).size()


func dice_counts() -> Dictionary:
	# pid -> 骰子数(公开信息)
	var counts := {}
	for pid in seat_order:
		counts[pid] = dice[pid].size()
	return counts


func total_dice() -> int:
	var total := 0
	for pid in seat_order:
		total += dice[pid].size()
	return total


func count_matching(face: int) -> int:
	# 全场 face 点的个数,1 点万能也算上
	var total := 0
	for pid in seat_order:
		for value in dice[pid]:
			if value == face or value == WILD_FACE:
				total += 1
	return total


static func is_valid_face(face: Variant) -> bool:
	return face is int and face >= MIN_BID_FACE and face <= FACES


static func is_higher(count: int, face: int, current: Dictionary) -> bool:
	# 比当前这一口大:个数更多,或个数相同点数更大;本轮第一口(current 为 {})任何合法出价都算
	if current.is_empty():
		return true
	return count > current["count"] or (count == current["count"] and face > current["face"])


static func bid_error(count: Variant, face: Variant, current: Dictionary, total: int) -> String:
	# 出价是否合法(不看轮到谁):返回错误码,合法为 ""。阶段二的出价器按它置灰
	if not count is int or count < 1:
		return ERR_INVALID_COUNT
	if not is_valid_face(face):
		return ERR_INVALID_FACE
	if count > total:
		return ERR_BID_TOO_HIGH
	if not is_higher(count, face, current):
		return ERR_BID_TOO_LOW
	return ""


static func min_raise(current: Dictionary, total: int) -> Dictionary:
	# 最小合法加注 {"count", "face"}:还没人喊是「1 个 2」;点数没到 6 就同个数点数 +1;否则个数 +1、点数 2。
	# 个数已经到场上总数且点数是 6(加不上去了)返回 {}
	if current.is_empty():
		return {"count": 1, "face": MIN_BID_FACE} if total >= 1 else {}
	if current["face"] < FACES:
		return {"count": current["count"], "face": current["face"] + 1}
	if current["count"] < total:
		return {"count": current["count"] + 1, "face": MIN_BID_FACE}
	return {}


# —— 内部 ——

func _start_round(starter, counts: Dictionary) -> Array:
	# counts:pid -> 本轮每人的骰子数(出局者 0)。全员重摇,清空出价,轮到 starter
	round_no += 1
	for pid in seat_order:
		var roll := []
		for i in counts[pid]:
			roll.append(rng.randi_range(1, FACES))
		roll.sort()
		dice[pid] = roll
	bid = {}
	bids = []
	starter_pid = starter
	current_pid = starter
	step = Step.BID
	var rows := []
	for pid in seat_order:
		rows.append({"pid": pid, "count": counts[pid]})
	return [{
		"type": "round_started",
		"round": round_no,
		"starter": starter,
		"seats": seat_order.duplicate(),
		"counts": rows,
		"total": total_dice(),
	}]


func _set_counts(counts: Dictionary) -> void:
	# 对局结束时把骰子数落到 counts(胜者留着他本轮的骰子,出局者清空;不再重摇)
	for pid in seat_order:
		if counts[pid] == 0:
			dice[pid] = []
		elif counts[pid] < dice[pid].size():
			dice[pid] = dice[pid].slice(0, counts[pid])


func _finish(winner) -> Array:
	step = Step.OVER
	winner_pid = winner
	current_pid = null
	bid = {}
	bids = []
	var ranking := [winner]
	for i in range(out_order.size() - 1, -1, -1):
		ranking.append(out_order[i])
	return [{"type": "match_over", "winner": winner, "ranking": ranking}]


func _check_actor(pid) -> String:
	if step == Step.OVER:
		return ERR_MATCH_OVER
	if not is_member(pid):
		return ERR_NOT_SEATED
	if not is_alive(pid):
		return ERR_OUT
	if pid != current_pid:
		return ERR_NOT_YOUR_TURN
	return ""


func _next_alive_after(pid):
	return _next_with_dice_after(pid, dice_counts())


func _next_with_dice_after(pid, counts: Dictionary):
	# pid 之后(座位顺序)下一位还有骰子的人;pid 自己排在最后
	var n := seat_order.size()
	var start := seat_order.find(pid)
	for offset in range(1, n + 1):
		var cand = seat_order[(start + offset) % n]
		if counts[cand] > 0:
			return cand
	return null


func _alive_count(counts: Dictionary) -> int:
	var alive := 0
	for pid in counts:
		if counts[pid] > 0:
			alive += 1
	return alive


func _ok(events: Array) -> Dictionary:
	return {"ok": true, "events": events}


func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error, "events": []}
