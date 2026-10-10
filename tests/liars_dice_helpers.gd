extends RefCounted
# 吹牛骰子测试共用:摆局面、找事件、检查公共事件 / 公共视图不漏本轮的点数。


# 每种公共事件允许出现的键(多出任何键都算可疑:可能夹带了点数)
const EVENT_KEYS := {
	"round_started": ["type", "round", "starter", "seats", "counts", "total"],
	"bid": ["type", "pid", "count", "face", "auto"],
	"turn_passed": ["type", "pid"],
	"challenged": ["type", "pid", "target", "count", "face", "auto"],
	"revealed": ["type", "dice", "face", "count", "actual", "truthful"],
	"die_lost": ["type", "pid", "left"],
	"player_out": ["type", "pid"],
	"player_left": ["type", "pid", "removed"],
	"match_over": ["type", "winner", "ranking"],
}
const PUBLIC_VIEW_KEYS := ["mode", "step", "round", "starter_pid", "current_pid", "bid", "bids", "total_dice", "players",
	"last_reveal", "out_order", "winner", "ranking", "turn_time_left"]
const PLAYER_ROW_KEYS := ["pid", "name", "alive", "dice_count"]
const PRIVATE_VIEW_KEYS := ["dice", "alive", "round"]


static func new_state(pids: Array, seed_value := 7) -> LiarsDiceState:
	var s := LiarsDiceState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	s.start(pids, rng)
	return s


static func rig(s: LiarsDiceState, dice: Dictionary, current, bid := {}) -> void:
	# 换成指定的点数(没列出的人当作出局:没有骰子),从 current 喊价开始;bid 为当前最高的一口(可空)
	for pid in s.seat_order:
		var roll: Array = dice.get(pid, []).duplicate()
		roll.sort()
		s.dice[pid] = roll
	s.current_pid = current
	s.starter_pid = current
	s.bid = bid.duplicate()
	s.bids = [bid.duplicate()] if not bid.is_empty() else []
	s.step = LiarsDiceState.Step.BID


static func find(events: Array, type: String) -> Dictionary:
	for ev in events:
		if ev.get("type") == type:
			return ev
	return {}


static func types(events: Array) -> Array:
	return events.map(func(ev: Dictionary) -> String: return ev["type"])


static func event_leak(ev: Dictionary) -> String:
	# 返回问题描述,没问题为 ""。只有 revealed 能带点数数组;别的事件的值只能是标量或 pid / 个数的数组
	var type: Variant = ev.get("type")
	if not EVENT_KEYS.has(type):
		return "未知事件 %s" % str(type)
	for key in ev:
		if not EVENT_KEYS[type].has(key):
			return "%s 多出键 %s" % [type, key]
	if type != "revealed":
		for key in ev:
			if key != "seats" and key != "counts" and key != "ranking" and (ev[key] is Array or ev[key] is Dictionary):
				return "%s.%s 不是标量" % [type, key]
		for row in ev.get("counts", []):
			if row.keys() != ["pid", "count"] or not row["count"] is int:
				return "round_started.counts 行不对:%s" % str(row)
	return ""


static func view_leak(view: Dictionary, s: LiarsDiceState) -> String:
	# 公共视图:键在白名单里、玩家行只有骰子数;last_reveal 只能是上一次开盅的(已公开)结果
	for key in view:
		if not PUBLIC_VIEW_KEYS.has(key):
			return "公共视图多出键 %s" % key
	for row in view["players"]:
		for key in row:
			if not PLAYER_ROW_KEYS.has(key):
				return "players[] 多出键 %s" % key
	if view["last_reveal"] != s.last_reveal:
		return "last_reveal 与最近一次开盅不符"
	for key in ["bid", "bids", "out_order", "ranking"]:
		if str(view[key]).contains("dice"):
			return "公共视图 %s 带了点数" % key
	return ""
