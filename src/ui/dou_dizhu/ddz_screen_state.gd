class_name DdzScreenState
extends RefCounted
# 斗地主牌桌的本地状态(纯逻辑,不碰场景;牌桌、HUD、导演、机器人都读它):
# - pub / priv:最近一份公共 / 私有视图(房主权威,领先于演出);
# - 影子行:按事件流推进的手牌张数、累计分、身份、叫分、面前的牌、「不出」、地主、底分、倍数、底牌、当前行动者与阶段、托管
#   (演出播到哪儿就显示到哪儿),演出结束后 sync_from_view() 用视图兜底对齐;
# - shown_hand:屏幕上自己的手牌(升序 = 私有视图 cards 的顺序;发牌时按这一手 / 这次发牌的私有视图快照,定地主时并入底牌,
#   出牌时按事件里的牌 id 拿走),演完以私有视图为准;
# - 出手规则:选中的牌成不成牌型、压不压得过上家、按钮该不该亮、提示列表——都按视图判断。
# 视图与事件来自网络:字段类型不对的当缺省值,不报错。


const STAGE_BID := DdzState.STAGE_BID
const STAGE_PLAY := DdzState.STAGE_PLAY
const PHASE_IDLE := "idle"
const PHASE_BIDDING := "bidding"
const PHASE_PLAYING := "playing"
const PHASE_BETWEEN := "between"
const PHASE_OVER := "over"
const BID_TEXT := {0: "不叫", 1: "1 分", 2: "2 分", 3: "3 分"}

var my_pid := 0
var seats: Array = []          # 座位顺序的 pid
var names := {}                # pid -> 名字
var pub := {}
var priv := {}
# —— 影子行(按事件推进)——
var hand := 0
var deal := 0
var phase := PHASE_IDLE
var stage := ""                # 当前行动的阶段:bid / play / ""
var free := false              # 当前行动者是自由出牌
var current_pid: Variant = null
var counts := {}               # pid -> 手牌张数
var scores := {}               # pid -> 累计分
var roles := {}                # pid -> "" / landlord / farmer
var trustee := {}              # pid -> bool
var bids := {}                 # pid -> 本次发牌叫的分(没叫过不在表里)
var rows := {}                 # pid -> 面前这一圈他最后出的牌
var passed := {}               # pid -> 这一圈他最后是「不出」
var left := {}                 # pid -> true:离开的人
var landlord: Variant = null
var base := 0
var multiplier := 1
var bottom: Array = []         # 亮出来的底牌(定地主之后)
var bottom_hidden := false     # 桌心扣着 3 张底牌(叫分阶段)
var lead := {}                 # 本圈要压的牌型 {"pid", "cards", "type", "rank", "length", "count"};自由出牌时 {}
var ending := false
var last_hand := {}            # 上一手的结算摘要(hand_over 去掉 type)
var results: Array = []
var end_reason := ""
var shown_hand: Array = []     # 屏幕上自己的手牌(牌 id 升序)
var _snapshots := {}           # "hand:deal" -> 叫分阶段的私有手牌(发牌 / 重发的演出按它亮面)


func set_seats(entries: Array) -> void:
	# Net.seats:[{pid, name, species}]
	seats = []
	for entry in entries:
		if entry is Dictionary and entry.get("pid") is int:
			seats.append(entry["pid"])
			names[entry["pid"]] = str(entry.get("name", entry["pid"]))
			for table in [counts, scores]:
				if not table.has(entry["pid"]):
					table[entry["pid"]] = 0


func name_of(pid: Variant) -> String:
	return names.get(pid, "?") if pid is int else "?"


# —— 视图 ——

func apply_public(view: Dictionary) -> void:
	pub = view
	for row in _players():
		if row.get("pid") is int and row.get("name") is String:
			names[row["pid"]] = row["name"]


func apply_private(view: Dictionary) -> void:
	priv = view
	# 叫分阶段的手牌按「第几手 : 第几次发牌」记一份:私有视图比演出先到,发牌 / 重发的演出要亮的是那一次发到的牌
	if str(pub.get("phase", "")) == PHASE_BIDDING:
		var key := "%d:%d" % [_int(view, "hand"), _int(pub, "deal")]
		if not _snapshots.has(key):
			_snapshots[key] = private_cards()
	if _snapshots.size() > 12:
		_snapshots.erase(_snapshots.keys()[0])


func sync_from_view() -> void:
	# 演出结束:影子行与屏幕上的手牌全部按视图对齐
	if pub.is_empty():
		return
	hand = _int(pub, "hand")
	deal = _int(pub, "deal")
	phase = str(pub.get("phase", PHASE_IDLE))
	current_pid = pub["current_pid"] if pub.get("current_pid") is int else null
	landlord = pub["landlord"] if pub.get("landlord") is int else null
	base = _int(pub, "base")
	multiplier = maxi(_int(pub, "multiplier"), 1)
	bottom = _cards(pub.get("bottom"))
	bottom_hidden = phase == PHASE_BIDDING
	lead = pub["lead"].duplicate(true) if pub.get("lead") is Dictionary else {}
	ending = pub.get("ending") is bool and pub["ending"]
	last_hand = pub["last_hand"].duplicate(true) if pub.get("last_hand") is Dictionary else {}
	results = pub["results"].duplicate(true) if pub.get("results") is Array else []
	end_reason = str(pub.get("end_reason", ""))
	free = current_pid != null and phase == PHASE_PLAYING and lead.is_empty()
	stage = STAGE_BID if phase == PHASE_BIDDING and current_pid != null else (STAGE_PLAY if phase == PHASE_PLAYING and current_pid != null else "")
	bids = {}
	for b in (pub["bids"] if pub.get("bids") is Array else []):
		if b is Dictionary and b.get("pid") is int and b.get("score") is int:
			bids[b["pid"]] = b["score"]
	rows = {}
	passed = {}
	for row in _players():
		var pid: Variant = row.get("pid")
		if not pid is int:
			continue
		counts[pid] = _int(row, "hand_count")
		scores[pid] = _int(row, "score")
		roles[pid] = str(row.get("role", ""))
		trustee[pid] = row.get("trustee") is bool and row["trustee"]
		if row.get("left") is bool and row["left"]:
			left[pid] = true
		var table := _cards(row.get("table"))
		if not table.is_empty():
			rows[pid] = table
		if row.get("passed") is bool and row["passed"]:
			passed[pid] = true
	if hand == private_hand_number():
		shown_hand = private_cards()


func private_hand_number() -> int:
	return _int(priv, "hand")


func private_cards() -> Array:
	return _cards(priv.get("cards"))


func cards_for_deal(p_hand: int, p_deal: int) -> Variant:
	# 这一手第几次发牌时自己的手牌(私有视图快照);还没到时为 null
	var key := "%d:%d" % [p_hand, p_deal]
	return _snapshots[key].duplicate() if _snapshots.has(key) else null


# —— 事件 ——

func apply_event(ev: Dictionary) -> void:
	match str(ev.get("type", "")):
		"hand_started":
			hand = _int(ev, "hand")
			deal = maxi(_int(ev, "deal"), 1)
			phase = PHASE_BIDDING
			_reset_hand()
			_take_counts(ev.get("hands"))
			_take_scores(ev.get("scores"))
			last_hand = {}
		"redeal":
			deal = _int(ev, "deal")
			bids = {}
			bottom_hidden = true
			_take_counts(ev.get("hands"))
		"turn":
			current_pid = ev["pid"] if ev.get("pid") is int else null
			stage = str(ev.get("stage", ""))
			free = ev.get("free") is bool and ev["free"]
			if free:
				lead = {}
		"bid":
			if ev.get("pid") is int:
				bids[ev["pid"]] = _int(ev, "score")
		"landlord":
			landlord = ev["pid"] if ev.get("pid") is int else null
			base = _int(ev, "base")
			bottom = _cards(ev.get("bottom"))
			bottom_hidden = false
			phase = PHASE_PLAYING
			for pid in seats:
				roles[pid] = DdzState.ROLE_LANDLORD if pid == landlord else DdzState.ROLE_FARMER
			if landlord != null:
				counts[landlord] = counts.get(landlord, 0) + bottom.size()
		"played":
			var pid: Variant = ev.get("pid")
			if pid is int:
				var cards := _cards(ev.get("cards"))
				rows[pid] = cards
				passed.erase(pid)
				counts[pid] = _int(ev, "remaining")
				lead = {"pid": pid, "cards": cards, "type": str(ev.get("combo", "")), "rank": _int(ev, "rank"),
					"length": _int(ev, "length"), "count": cards.size()}
			multiplier = maxi(_int(ev, "multiplier"), 1)
		"passed":
			if ev.get("pid") is int:
				rows.erase(ev["pid"])
				passed[ev["pid"]] = true
		"trick_cleared":
			rows = {}
			passed = {}
			lead = {}
		"trustee":
			if ev.get("pid") is int:
				trustee[ev["pid"]] = ev.get("on") is bool and ev["on"]
		"hand_over":
			_take_scores(ev.get("scores"))
			var summary := ev.duplicate(true)
			summary.erase("type")
			last_hand = summary
			multiplier = maxi(_int(ev, "multiplier"), 1)
			phase = PHASE_BETWEEN
			current_pid = null
			stage = ""
		"ending":
			ending = true
		"player_left":
			if ev.get("pid") is int:
				left[ev["pid"]] = true
		"session_over":
			results = ev["results"].duplicate(true) if ev.get("results") is Array else []
			end_reason = str(ev.get("reason", ""))
			phase = PHASE_OVER
			current_pid = null
			stage = ""


func _reset_hand() -> void:
	bids = {}
	rows = {}
	passed = {}
	roles = {}
	landlord = null
	base = 0
	multiplier = 1
	bottom = []
	bottom_hidden = true
	lead = {}
	current_pid = null
	stage = ""
	free = false


func _take_counts(rows_in: Variant) -> void:
	if not rows_in is Array:
		return
	for row in rows_in:
		if row is Dictionary and row.get("pid") is int:
			counts[row["pid"]] = _int(row, "count")


func _take_scores(rows_in: Variant) -> void:
	if not rows_in is Array:
		return
	for row in rows_in:
		if row is Dictionary and row.get("pid") is int:
			scores[row["pid"]] = _int(row, "score")


# —— 屏幕上的手牌 ——

func take_from_shown(ids: Array) -> void:
	# 自己出的牌:按 id 从屏幕上的手牌里拿走
	for id in ids:
		shown_hand.erase(id)


func add_bottom_to_shown(ids: Array) -> Array:
	# 自己当了地主:底牌并进手牌(升序);返回新手牌
	for id in ids:
		if DdzHand.is_card(id) and not shown_hand.has(id):
			shown_hand.append(id)
	shown_hand.sort()
	return shown_hand.duplicate()


# —— 出手规则(都按视图) ——

func view_turn() -> bool:
	return priv.get("my_turn") is bool and priv["my_turn"] and pub.get("current_pid") == my_pid


func view_phase() -> String:
	return str(pub.get("phase", PHASE_IDLE))


func bid_options() -> Array:
	var out := []
	if view_phase() != PHASE_BIDDING:
		return out
	for score in (priv["bid_options"] if priv.get("bid_options") is Array else []):
		if score is int and score >= 0 and score <= DdzState.MAX_BID:
			out.append(score)
	return out


func can_pass() -> bool:
	return view_phase() == PHASE_PLAYING and priv.get("can_pass") is bool and priv["can_pass"]


func hints() -> Array:
	# 提示列表:每项是私有手牌下标(已按手牌张数校验);legal_plays 的顺序(小的在前,炸弹、王炸最后)
	var out := []
	if view_phase() != PHASE_PLAYING:
		return out
	var n := private_cards().size()
	for h in (priv["hints"] if priv.get("hints") is Array else []):
		if not h is Dictionary or not h.get("indices") is Array:
			continue
		var indices: Array = h["indices"]
		if indices.is_empty() or not indices.all(func(i): return i is int and i >= 0 and i < n):
			continue
		var sorted := indices.duplicate()
		sorted.sort()
		out.append(sorted)
	return out


func hint_types() -> Array:
	var out := []
	for h in (priv["hints"] if priv.get("hints") is Array else []):
		out.append(str(h.get("type", "")) if h is Dictionary else "")
	return out


func view_lead() -> Dictionary:
	# 视图里本圈要压的牌型(自由出牌时为 {})
	var l: Variant = pub.get("lead")
	if not l is Dictionary or l.is_empty() or not l.get("type") is String:
		return {}
	return {"type": l["type"], "rank": _int(l, "rank"), "length": maxi(_int(l, "length"), 1), "count": _int(l, "count"),
		"pid": l.get("pid")}


func selection_cards(indices: Array) -> Array:
	var hand_cards := private_cards()
	var out := []
	for i in indices:
		if i is int and i >= 0 and i < hand_cards.size():
			out.append(hand_cards[i])
	return out


func selection_check(indices: Array) -> Dictionary:
	# 选中的这几张:{"ok": 能不能出, "combo": 牌型字典, "text": 给人看的一句话}
	if indices.is_empty():
		return {"ok": false, "combo": {}, "text": ""}
	var cards := selection_cards(indices)
	if cards.size() != indices.size():
		return {"ok": false, "combo": {}, "text": "选的牌不对"}
	var l := view_lead()
	if l.is_empty():
		var c := DdzHand.classify(cards)
		if c.is_empty():
			return {"ok": false, "combo": {}, "text": "不成牌型"}
		return {"ok": true, "combo": c, "text": combo_text(c)}
	var lead_combo := DdzHand.combo(l["type"], l["rank"], l["length"], l["count"])
	var m := DdzHand.match_lead(cards, lead_combo)
	if not m.is_empty():
		return {"ok": true, "combo": m, "text": combo_text(m)}
	if DdzHand.classify(cards).is_empty():
		return {"ok": false, "combo": {}, "text": "不成牌型"}
	return {"ok": false, "combo": {}, "text": "压不过上家的「%s」" % DdzHand.type_name(l["type"])}


static func combo_text(c: Dictionary) -> String:
	# 「顺子 · 7 张」「炸弹」「对子」
	var name := DdzHand.type_name(str(c.get("type", "")))
	var n := int(c.get("count", 0))
	match str(c.get("type", "")):
		DdzHand.STRAIGHT, DdzHand.PAIR_STRAIGHT, DdzHand.AIRPLANE, DdzHand.AIRPLANE_SINGLE, DdzHand.AIRPLANE_PAIR:
			return "%s · %d 张" % [name, n]
	return name


static func shout_for(combo: String, cards: Array) -> String:
	# 出牌人头顶的气泡:单张 / 对子 / 三张写点数(「K」「对 K」「三个 5」),其余写牌型名
	var r := DdzHand.rank(cards[0]) if not cards.is_empty() and DdzHand.is_card(cards[0]) else -1
	var label: String = DdzHand.RANK_LABELS[r] if r >= 0 else ""
	match combo:
		DdzHand.SINGLE:
			return label
		DdzHand.PAIR:
			return "对 %s" % label
		DdzHand.TRIPLE:
			return "三个 %s" % label
		DdzHand.BOMB:
			return "炸弹!"
		DdzHand.ROCKET:
			return "王炸!"
	return DdzHand.type_name(combo) + "!"


static func bid_text(score: int) -> String:
	return BID_TEXT.get(score, "%d 分" % score)


# —— 铭牌与结算 ——

func plate_row(pid: int) -> Dictionary:
	# 铭牌要的:名字、身份、累计分、手牌张数、托管、正在行动、本次叫分(叫分阶段)、离开
	return {"name": name_of(pid), "role": str(roles.get(pid, "")), "score": int(scores.get(pid, 0)), "count": int(counts.get(pid, 0)),
		"trustee": bool(trustee.get(pid, false)), "active": pid == current_pid, "bid": bids.get(pid, -1) if phase == PHASE_BIDDING else -1,
		"left": left.has(pid)}


static func ranking(results_in: Variant) -> Array:
	# 结算行来自网络:坏条目丢掉,坏字段当默认值;按名次(同分同名次)、再按原顺序
	var rows_out := []
	if results_in is Array:
		for row in results_in:
			if row is Dictionary:
				rows_out.append({"pid": row.get("pid"), "name": row["name"] if row.get("name") is String else "?",
					"score": row["score"] if row.get("score") is int else 0, "place": row["place"] if row.get("place") is int else 0,
					"left": row.get("left") is bool and row["left"]})
	var order := range(rows_out.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var pa: int = rows_out[a]["place"] if rows_out[a]["place"] > 0 else 99
		var pb: int = rows_out[b]["place"] if rows_out[b]["place"] > 0 else 99
		return pa < pb or (pa == pb and a < b))
	return order.map(func(i: int) -> Dictionary: return rows_out[i])


static func top_ranked(results_in: Variant) -> Array:
	# 名次第一的人(同分并列都算)
	return ranking(results_in).filter(func(r: Dictionary) -> bool: return r["place"] == 1 and r["pid"] is int) \
		.map(func(r: Dictionary) -> int: return r["pid"])


static func score_sum(results_in: Variant) -> int:
	var total := 0
	for row in ranking(results_in):
		total += int(row["score"])
	return total


func summary_rows() -> Array:
	# 两手之间画的结算摘要:[{pid, name, role, delta, score}](座位顺序)
	var out := []
	var deltas := {}
	for d in (last_hand["deltas"] if last_hand.get("deltas") is Array else []):
		if d is Dictionary and d.get("pid") is int:
			deltas[d["pid"]] = _int(d, "delta")
	var hand_scores := {}
	for s in (last_hand["scores"] if last_hand.get("scores") is Array else []):
		if s is Dictionary and s.get("pid") is int:
			hand_scores[s["pid"]] = _int(s, "score")
	for pid in seats:
		if deltas.has(pid):
			out.append({"pid": pid, "name": name_of(pid), "role": DdzState.ROLE_LANDLORD if last_hand.get("landlord") == pid else DdzState.ROLE_FARMER,
				"delta": deltas[pid], "score": hand_scores.get(pid, scores.get(pid, 0))})
	return out


# —— 工具 ——

func _players() -> Array:
	return pub["players"] if pub.get("players") is Array else []


static func _cards(value: Variant) -> Array:
	var out := []
	if value is Array:
		for c in value:
			if DdzHand.is_card(c):
				out.append(c)
	return out


static func _int(d: Variant, key: String) -> int:
	if not d is Dictionary:
		return 0
	var v: Variant = d.get(key, 0)
	return v if v is int else 0
