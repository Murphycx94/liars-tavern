extends RefCounted
# 斗地主测试共用:按点数写牌、摆局面、公共事件 / 视图的漏信息检查。


const H := preload("res://src/core/dou_dizhu/ddz_hand.gd")

# 每种公共事件允许出现的键(多出任何键都算可疑:可能夹带了隐藏信息)
const EVENT_KEYS := {
	"hand_started": ["type", "hand", "deal", "seats", "first_bidder", "hands", "bottom_count", "scores"],
	"redeal": ["type", "hand", "deal", "first_bidder", "hands"],
	"turn": ["type", "pid", "stage", "free"],
	"bid": ["type", "pid", "score", "timed_out", "auto"],
	"landlord": ["type", "pid", "base", "bottom", "forced"],
	"played": ["type", "pid", "cards", "combo", "rank", "length", "multiplier", "remaining", "timed_out", "auto"],
	"passed": ["type", "pid", "timed_out", "auto"],
	"trick_cleared": ["type", "pid"],
	"trustee": ["type", "pid", "on", "auto"],
	"hand_over": ["type", "hand", "winner", "landlord", "landlord_won", "base", "multiplier", "bombs", "spring",
		"deltas", "scores", "remaining"],
	"ending": ["type"],
	"player_left": ["type", "pid", "hand_voided"],
	"session_over": ["type", "reason", "results"],
}
const PUBLIC_VIEW_KEYS := ["mode", "hand", "phase", "deal", "first_bidder", "bids", "highest_bid", "current_pid",
	"landlord", "base", "multiplier", "bombs", "bottom", "lead", "passes", "players", "turn_time_left", "ending",
	"last_hand", "results", "end_reason"]
const PLAYER_ROW_KEYS := ["pid", "name", "hand_count", "score", "role", "trustee", "table", "passed", "plays", "left"]
const PRIVATE_VIEW_KEYS := ["hand", "cards", "role", "trustee", "my_turn", "can_pass", "bid_options", "hints"]
const TOKENS := {"3": 0, "4": 1, "5": 2, "6": 3, "7": 4, "8": 5, "9": 6, "10": 7, "J": 8, "Q": 9, "K": 10, "A": 11,
	"2": 12}


static func cards(text: String) -> Array:
	# "3 3 4 SJ BJ" → 牌 id(同点数依次用 ♠ ♥ ♦ ♣);SJ 小王、BJ 大王
	var used := {}
	var out := []
	for tok in text.split(" ", false):
		if tok == "SJ":
			out.append(H.SMALL_JOKER)
		elif tok == "BJ":
			out.append(H.BIG_JOKER)
		else:
			var r: int = TOKENS[tok]
			var s: int = used.get(r, 0)
			used[r] = s + 1
			out.append(H.make(r, s))
	return out


static func kind(text: String) -> Dictionary:
	return H.classify(cards(text))


static func new_state(seed_value := 7, pids := [1, 2, 3]) -> DdzState:
	var s := DdzState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	s.start(pids, rng)
	return s


static func rig_play(s: DdzState, hands: Dictionary, landlord: int, current: int, base := 1) -> void:
	# 直接进出牌阶段:指定手牌(升序)、地主、当前出牌者;自由出牌开始。其余牌都算「已出」,守恒照样成立
	var all := {}
	for pid in s.seat_order:
		s.hands[pid] = H.sorted(hands.get(pid, []))
		for c in s.hands[pid]:
			all[c] = true
	s.played = H.full_deck().filter(func(c: int) -> bool: return not all.has(c))
	s.bottom_taken = true
	s.landlord = landlord
	s.base = base
	s.multiplier = 1
	s.bombs = 0
	s.lead = {}
	s.passes = 0
	s.table = {}
	s.current_pid = current
	s.phase = DdzState.Phase.PLAYING
	for pid in s.seat_order:
		s.play_counts[pid] = 0


static func types(events: Array) -> Array:
	return events.map(func(ev: Dictionary) -> String: return ev["type"])


static func find(events: Array, type: String) -> Dictionary:
	for ev in events:
		if ev.get("type") == type:
			return ev
	return {}


static func event_leak(ev: Dictionary, revealed: Dictionary) -> String:
	# revealed:此时已公开的牌 id 集合。键要在白名单里;带牌的键只能有已公开的牌
	var type: Variant = ev.get("type")
	if not EVENT_KEYS.has(type):
		return "未知事件 %s" % str(type)
	for key in ev:
		if not EVENT_KEYS[type].has(key):
			return "%s 多出键 %s" % [type, key]
	for c in event_cards(ev):
		if not revealed.has(c):
			return "%s 带了没公开的牌 %s" % [type, H.label(c)]
	return ""


static func event_cards(ev: Dictionary) -> Array:
	match ev.get("type"):
		"played":
			return ev["cards"]
		"landlord":
			return ev["bottom"]
		"hand_over":
			var out := []
			for row in ev["remaining"]:
				out.append_array(row["cards"])
			return out
	return []


static func view_leak(view: Dictionary, revealed: Dictionary) -> String:
	for key in view:
		if not PUBLIC_VIEW_KEYS.has(key):
			return "公共视图多出键 %s" % key
	for row in view["players"]:
		for key in row:
			if not PLAYER_ROW_KEYS.has(key):
				return "players 行多出键 %s" % key
	var shown: Array = view["bottom"].duplicate()
	shown.append_array(view["lead"].get("cards", []))
	for row in view["players"]:
		shown.append_array(row["table"])
	if view["last_hand"].get("hand") == view["hand"]:   # 上一手亮的牌属于上一副,不算这一手的
		for row in view["last_hand"].get("remaining", []):
			shown.append_array(row["cards"])
	for c in shown:
		if not revealed.has(c):
			return "公共视图带了没公开的牌 %s" % H.label(c)
	return ""


static func revealed_cards(s: DdzState, include_hands := false) -> Dictionary:
	# 已公开的牌:已出的、亮出的底牌;include_hands(一手结束亮牌之后)= 全部
	var out := {}
	for c in s.played:
		out[c] = true
	if s.bottom_taken:
		for c in s.bottom:
			out[c] = true
	if include_hands:
		for c in H.full_deck():
			out[c] = true
	return out
