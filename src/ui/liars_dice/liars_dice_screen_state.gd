class_name LiarsDiceScreenState
extends RefCounted
# 吹牛骰子牌桌的本地状态(纯逻辑,不碰场景;牌桌、HUD、导演、机器人都读它):
# - pub / priv:最近一份公共 / 私有视图(房主权威,领先于演出);
# - 影子行:按事件流推进的轮次、每人骰子数、存活、场上总数、当前这一口与出价记录、轮到谁(演出播到哪儿就显示到哪儿),
#   演出结束后 sync_from_view() 用视图兜底对齐;
# - 自己的骰子按轮次缓存:私有视图比「开!」那一批的演出先到(那一批里已经重摇了下一轮),
#   所以私有视图来了只按 round 记下,导演演到对应的 round_started 才 take_round_dice 换到屏幕上(shown_dice);
#   开盅演出用 revealed 事件里的点数,不用私有视图。
# - 别人的点数只在 revealed 事件里出现(last_reveal),之前这里没有任何别人的点数。
# 视图与事件来自网络:字段类型不对的当缺省值,不报错。


const STEP_BID := "bid"
const STEP_OVER := "over"
const KEEP_ROUNDS := 3          # 私有骰子最多缓存这么多轮(只会领先一轮,多留两轮兜底)
const FATE_WINNER := "winner"
const FATE_OUT := "out"
const FATE_LEFT := "left"

var my_pid := 0
var seats: Array = []          # 座位顺序的 pid
var names := {}                # pid -> 名字
var pub := {}
var priv := {}
# —— 影子行(按事件推进)——
var round_no := 0
var counts := {}               # pid -> 骰子数
var alive := {}                # pid -> bool
var total := 0                 # 场上骰子总数
var starter_pid: Variant = null
var current_pid: Variant = null
var bid := {}                  # 本轮当前最高的一口 {pid, count, face};还没人喊为 {}
var bids: Array = []           # 本轮出价记录
var last_reveal := {}          # 最近一次开盅(revealed 事件,不含 type)
var out_order: Array = []
var left := {}                 # pid -> true:断线离开的
var winner: Variant = null
var step := STEP_OVER
var started := false           # 收到过 round_started(或视图)
# —— 自己的骰子 ——
var shown_dice: Array = []     # 屏幕上自己本轮的点数(从小到大)
var shown_round := 0           # shown_dice 是第几轮的
var _dice_by_round := {}       # round -> [点数](私有视图记下来的,等演到那一轮再换上)


func set_seats(entries: Array) -> void:
	# Net.seats:[{pid, name, species}]。开局运镜期间第一轮还没演到:骰子数先按开局的每人 5 颗,
	# 铭牌与左上不会先显示「0 颗」「场上 0 颗骰子」
	seats = []
	for entry in entries:
		if entry is Dictionary and entry.get("pid") is int:
			seats.append(entry["pid"])
			names[entry["pid"]] = str(entry.get("name", entry["pid"]))
			if not counts.has(entry["pid"]):
				counts[entry["pid"]] = LiarsDiceState.DICE_PER_PLAYER
				alive[entry["pid"]] = true
	if not started:
		total = seats.size() * LiarsDiceState.DICE_PER_PLAYER


func name_of(pid: Variant) -> String:
	return names.get(pid, "?") if pid is int else "?"


# —— 视图 ——

func apply_public(view: Dictionary) -> void:
	pub = view
	for row in _players():
		if row.get("pid") is int and row.has("name"):
			names[row["pid"]] = str(row["name"])


func apply_private(view: Dictionary) -> void:
	# 只记下这一轮自己的点数;换到屏幕上由导演按 round_started 决定
	priv = view
	var r := _int(view, "round")
	if r <= 0:
		return
	_dice_by_round[r] = sanitize_dice(view.get("dice"))
	for key in _dice_by_round.keys():
		if key <= r - KEEP_ROUNDS:
			_dice_by_round.erase(key)


static func sanitize_dice(value: Variant) -> Array:
	# 点数数组:只留 1..6 的整数,从小到大
	var out := []
	if value is Array:
		for v in value:
			if v is int and v >= 1 and v <= LiarsDiceState.FACES:
				out.append(v)
	out.sort()
	return out


func has_round_dice(r: int) -> bool:
	return _dice_by_round.has(r)


func round_dice(r: int) -> Array:
	return _dice_by_round.get(r, []).duplicate()


func take_round_dice(r: int) -> Array:
	# 演到第 r 轮的 round_started:屏幕上换成这一轮的点数(私有视图还没到时先清空,到了再补)
	shown_round = r
	shown_dice = round_dice(r)
	return shown_dice.duplicate()


func sync_from_view() -> void:
	# 演出结束:影子行按视图对齐;自己的骰子按视图的轮次取缓存
	if pub.is_empty():
		return
	started = true
	for row in _players():
		var pid: Variant = row.get("pid")
		if not pid is int:
			continue
		counts[pid] = _int(row, "dice_count")
		alive[pid] = row.get("alive") is bool and row["alive"]
	round_no = _int(pub, "round")
	total = _int(pub, "total_dice")
	starter_pid = pub.get("starter_pid") if pub.get("starter_pid") is int else null
	current_pid = pub.get("current_pid") if pub.get("current_pid") is int else null
	bid = clean_bid(pub.get("bid"))
	bids = []
	for row in (pub["bids"] if pub.get("bids") is Array else []):
		var b := clean_bid(row)
		if not b.is_empty():
			bids.append(b)
	if pub.get("last_reveal") is Dictionary and not pub["last_reveal"].is_empty():
		last_reveal = pub["last_reveal"].duplicate(true)
	out_order = pub["out_order"].filter(func(p): return p is int) if pub.get("out_order") is Array else []
	winner = pub.get("winner") if pub.get("winner") is int else null
	step = str(pub.get("step", STEP_OVER))
	if round_no > 0 and has_round_dice(round_no):
		take_round_dice(round_no)
	if not am_alive():
		shown_dice = []


static func clean_bid(value: Variant) -> Dictionary:
	# 出价字典:{pid, count, face} 三项类型都对才算;否则 {}
	if not value is Dictionary:
		return {}
	var b: Dictionary = value
	if not (b.get("count") is int and b.get("face") is int):
		return {}
	return {"pid": b.get("pid") if b.get("pid") is int else null, "count": b["count"], "face": b["face"]}


func apply_event(ev: Dictionary) -> void:
	# 演出每段开始前推进影子行(铭牌、左上信息跟着演出走,不抢先跳到视图)
	match ev.get("type", ""):
		"round_started":
			started = true
			round_no = _int(ev, "round")
			if ev.get("seats") is Array:
				var order: Array = ev["seats"].filter(func(p): return p is int)
				if not order.is_empty():
					seats = order
			for row in (ev["counts"] if ev.get("counts") is Array else []):
				if row is Dictionary and row.get("pid") is int:
					counts[row["pid"]] = _int(row, "count")
					alive[row["pid"]] = _int(row, "count") > 0
			total = _int(ev, "total")
			starter_pid = ev.get("starter") if ev.get("starter") is int else null
			current_pid = starter_pid
			bid = {}
			bids = []
			step = STEP_BID
		"bid":
			var b := clean_bid(ev)
			if not b.is_empty():
				bid = b
				bids.append(b)
		"turn_passed":
			current_pid = ev.get("pid") if ev.get("pid") is int else null
		"challenged":
			current_pid = null
		"revealed":
			last_reveal = ev.duplicate(true)
			last_reveal.erase("type")
		"die_lost":
			var pid: Variant = ev.get("pid")
			if pid is int:
				var before: int = counts.get(pid, 0)
				counts[pid] = maxi(_int(ev, "left"), 0)
				total = maxi(total - maxi(before - counts[pid], 0), 0)
		"player_out", "player_left":
			var pid: Variant = ev.get("pid")
			if pid is int:
				alive[pid] = false
				if ev["type"] == "player_left":
					left[pid] = true
					total = maxi(total - counts.get(pid, 0), 0)
				counts[pid] = 0
				if not out_order.has(pid):
					out_order.append(pid)
				if pid == my_pid:
					shown_dice = []
				if current_pid == pid:
					current_pid = null
		"match_over":
			step = STEP_OVER
			winner = ev.get("winner") if ev.get("winner") is int else null
			current_pid = null
			bid = {}


# —— 视图里的事实 ——

func pub_step() -> String:
	return str(pub.get("step", STEP_OVER))


func pub_current() -> Variant:
	return pub.get("current_pid") if pub.get("current_pid") is int else null


func pub_bid() -> Dictionary:
	return clean_bid(pub.get("bid"))


func pub_total() -> int:
	return _int(pub, "total_dice")


func am_alive() -> bool:
	if priv.has("alive"):
		return priv["alive"] is bool and priv["alive"]
	return alive.get(my_pid, false)


func is_alive(pid: Variant) -> bool:
	return pid is int and alive.get(pid, false)


func alive_pids() -> Array:
	return seats.filter(func(pid) -> bool: return is_alive(pid))


func my_turn_in_view() -> bool:
	# 视图说现在轮到自己喊价或「开!」(演出与回执另由牌桌判断)
	return am_alive() and pub_current() == my_pid and pub_step() == STEP_BID


func can_challenge_in_view() -> bool:
	return my_turn_in_view() and not pub_bid().is_empty()


func bid_error(count: Variant, face: Variant) -> String:
	# 出价器置灰:直接用规则引擎的判定(按视图的当前一口与场上总数)
	return LiarsDiceState.bid_error(count, face, pub_bid(), pub_total())


func default_bid() -> Dictionary:
	# 出价器的默认值:最小合法加注;加不上去了(只能开)时停在当前这一口
	var raise := LiarsDiceState.min_raise(pub_bid(), pub_total())
	if not raise.is_empty():
		return raise
	var b := pub_bid()
	if not b.is_empty():
		return {"count": b["count"], "face": b["face"]}
	return {"count": 1, "face": LiarsDiceState.MIN_BID_FACE}


func revealed_dice_of(pid: Variant) -> Array:
	# 最近一次开盅里 pid 的点数(开盅之前没有别人的点数)
	for row in (last_reveal["dice"] if last_reveal.get("dice") is Array else []):
		if row is Dictionary and row.get("pid") == pid:
			return sanitize_dice(row.get("dice"))
	return []


# —— 文案 ——

static func bid_text(count: Variant, face: Variant) -> String:
	return "%s 个 %s" % [str(count), str(face)]


static func count_matches(dice: Array, face: int) -> int:
	# 一盅里算作 face 的个数(1 点万能也算)
	var n := 0
	for v in dice:
		if v == face or v == LiarsDiceState.WILD_FACE:
			n += 1
	return n


static func is_match(value: int, face: int) -> bool:
	return value == face or value == LiarsDiceState.WILD_FACE


static func verdict_text(ev: Dictionary) -> String:
	# 判定副标题:「实际 7 个 5(含 1 点)· 喊的是 5 个」
	return "实际 %d 个 %s(1 点也算)· 喊的是 %d 个" % [_int(ev, "actual"), str(ev.get("face", "?")), _int(ev, "count")]


static func count_order(rows: Array, face: int) -> Array:
	# 开盅计数的顺序:按座位(revealed.dice 的顺序),每人从左到右;只列算进去的(等于 face 或 1 点)。[[pid, 第几颗], …]
	var out := []
	for row in rows:
		if not row is Dictionary or not row.get("pid") is int:
			continue
		var dice := LiarsDiceScreenState.sanitize_dice(row.get("dice"))
		for i in dice.size():
			if LiarsDiceScreenState.is_match(dice[i], face):
				out.append([row["pid"], i])
	return out


# —— 结算 ——

func ranking_rows() -> Array:
	# [{"pid", "name", "place", "fate", "dice"}]:fate ∈ winner / out / left;dice = 胜者还剩几颗(其余 0)。
	# 优先用视图的 ranking(只在 over 时有)
	var rows := []
	var source: Array = pub["ranking"] if pub.get("ranking") is Array and not pub["ranking"].is_empty() else []
	if source.is_empty():
		var order: Array = [winner] if winner is int else []
		for i in range(out_order.size() - 1, -1, -1):
			if out_order[i] != winner:
				order.append(out_order[i])
		for i in order.size():
			source.append({"pid": order[i], "name": name_of(order[i]), "place": i + 1})
	for row in source:
		if not row is Dictionary or not row.get("pid") is int:
			continue
		var pid: int = row["pid"]
		var place := _int(row, "place")
		var fate := FATE_WINNER if place == 1 else (FATE_LEFT if left.has(pid) else FATE_OUT)
		rows.append({"pid": pid, "name": str(row.get("name", name_of(pid))), "place": place, "fate": fate,
			"dice": counts.get(pid, 0) if fate == FATE_WINNER else 0})
	return rows


# —— 工具 ——

func players_rows() -> Array:
	return _players()


func _players() -> Array:
	return pub["players"].filter(func(r): return r is Dictionary) if pub.get("players") is Array else []


static func _int(d: Dictionary, key: String) -> int:
	var v: Variant = d.get(key, 0)
	if v is int:
		return v
	if v is float and is_finite(v):
		return int(v)
	return 0
