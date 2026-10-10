class_name DdzState
# 斗地主规则引擎(设计稿 §1、§2):仅在房主端运行,不依赖节点 / 网络 / UI。三人叫分制,连续打很多手、分数累计。
# 每个改动局面的方法返回 {"ok": bool, "error"?: String, "events": Array};被拒时局面不变、events 为空。
# 公共事件广播给全员,**不含任何隐藏信息**(手牌内容、没亮的底牌、牌堆顺序);手牌只经 hand_of 给私有视图。
#
# —— 局面 ——
# 阶段 phase:IDLE 还没开局 · BIDDING 叫分 · PLAYING 出牌 · BETWEEN 一手打完、等下一手 · OVER 牌局结算(散局或有人离开)。
# 一手:洗 54 张(房主 RNG),按座位每人 17 张、留 3 张底牌;手牌永远按牌 id 升序(= 点数升序),意图里的下标就是这个顺序。
# 叫分:本手开始时随机挑「第一个叫分的人」first_bidder,从他起按座位每人叫一次(0 = 不叫,1–3 只能比之前最高的高);
#   叫 3 立即当地主;一圈后最高的当地主;三人都不叫重新发牌(first_bidder 不变,deal_number + 1),
#   第 MAX_DEALS 次发牌还是都不叫,first_bidder 当 1 分地主(forced)。
# 地主拿走底牌(亮给所有人,bottom_taken),手里 20 张,先自由出牌。
# 出牌:lead = 本圈最后一手牌(自由出牌时为 {});跟牌要压过 lead,或者「不出」;连续两家不出,lead 清空、
#   最后出牌的人重新自由出牌(trick_cleared)。自由出牌不能不出。
# 倍数 multiplier 从 1 开始:每个炸弹 / 王炸 ×2;春天 ×2(地主出完时农民一张没出过,或农民赢而地主只出过第一手)。
# 结算:单位 = 底分 base × 倍数;地主赢 地主 +2 单位、两个农民各 −1 单位,地主输反过来;三人总和为 0,累计进 scores。
# 超时代打:叫分 → 不叫;出牌 → 能不出就不出,必须出时出最小的单张。同一人连续超时 TRUSTEE_AFTER_TIMEOUTS 次
#   进入托管(trustee),之后轮到他由引擎代打(timeout() 走托管打法,不再计超时),本人点「取消托管」恢复。
#   托管打法:叫分不叫;自由出牌出 legal_plays 的第一个;跟牌时上家是队友就不出,否则出最小的能压过的非炸弹组合,没有就不出。
#   本人亲自出手(叫分 / 出牌 / 不出)清零连续超时次数。
# 散局 request_end:一手进行中就打完这一手再结算(先发 ending),两手之间立即结算。
# 有人离开(断线)remove_player:牌局立即结算,进行中的这一手作废(不计分)。
# 牌数守恒(card_count):各手牌 + 已出 played + 底牌(没被拿走时)= 54。
#
# —— 公共事件(所有事件有 "type";pid 是玩家 id,cards 是牌 id 数组)——
#   hand_started   {hand, deal, seats: [pid], first_bidder, hands: [{pid, count}], bottom_count, scores: [{pid, score}]}
#                  新的一手(第 hand 手),第 1 次发牌
#   redeal         {hand, deal, first_bidder, hands: [{pid, count}]}       三人都不叫,重新发牌(deal = 第几次发牌)
#   turn           {pid, stage: "bid" | "play", free: bool}               轮到 pid;free = 自由出牌(叫分时为 false)
#   bid            {pid, score, timed_out, auto}                         叫分(0 = 不叫);timed_out 超时代打,auto 托管代打
#   landlord       {pid, base, bottom: [3 张], forced}                     定地主,底牌亮出并进他的手牌;forced = 连续不叫强制
#   played         {pid, cards, combo: type, rank, length, multiplier, remaining, timed_out, auto}
#                  出牌:combo 是牌型(DdzHand.TYPE_*),multiplier 是出完这手之后的倍数,remaining 是他剩几张
#   passed         {pid, timed_out, auto}                                不出
#   trick_cleared  {pid}                                                 两家不出,桌面清掉,pid 重新自由出牌
#   trustee        {pid, on, auto}                                       托管开 / 关;auto = 连续超时自动进入
#   hand_over      {hand, winner, landlord, landlord_won, base, multiplier, bombs, spring,
#                   deltas: [{pid, delta}], scores: [{pid, score}], remaining: [{pid, cards}]}
#                  一手结束:winner = 出完牌的人;multiplier 含春天;remaining = 各人剩下的牌(这时亮牌,已不再是秘密)
#   ending         {}                                                    房主散局:打完这一手再结算
#   player_left    {pid, hand_voided}                                    有人离开;hand_voided = 进行中的一手作废
#   session_over   {reason: "host" | "player_left", results: [{pid, score, place, left}]}
#                  牌局结算:按累计分从高到低(同分同名次,按座位排);会话层给每行补 name
# 只有 landlord.bottom、played.cards、hand_over.remaining 带牌 id,都是这时已公开的牌。


enum Phase { IDLE, BIDDING, PLAYING, BETWEEN, OVER }

const PHASE_NAMES := {
	Phase.IDLE: "idle", Phase.BIDDING: "bidding", Phase.PLAYING: "playing", Phase.BETWEEN: "between", Phase.OVER: "over",
}

const PLAYERS := 3
const HAND_SIZE := 17
const BOTTOM_SIZE := 3
const MAX_BID := 3
const MAX_DEALS := 3                  # 连续这么多次发牌都没人叫,第一个叫分的人当 1 分地主
const FORCED_BASE := 1
const TRUSTEE_AFTER_TIMEOUTS := 2
const LANDLORD_SHARE := 2             # 地主输赢是每个农民的 2 倍

const STAGE_BID := "bid"
const STAGE_PLAY := "play"
const ROLE_LANDLORD := "landlord"
const ROLE_FARMER := "farmer"
const REASON_HOST := "host"
const REASON_PLAYER_LEFT := "player_left"

# —— 拒绝错误码 ——
const ERR_SESSION_OVER := "session_over"
const ERR_NOT_SEATED := "not_seated"
const ERR_NO_HAND := "no_hand"                  # 两手之间(或还没开局)
const ERR_NOT_YOUR_TURN := "not_your_turn"
const ERR_NOT_BIDDING := "not_bidding"          # 出牌阶段想叫分
const ERR_NOT_PLAYING := "not_playing"          # 叫分阶段想出牌 / 不出
const ERR_INVALID_BID := "invalid_bid"          # 分数超范围或不比之前高
const ERR_INVALID_PLAY := "invalid_play"        # 下标不对(越界、重复、空)
const ERR_INVALID_COMBO := "invalid_combo"      # 不是合法牌型
const ERR_CANNOT_BEAT := "cannot_beat"          # 牌型合法但压不过上家
const ERR_CANNOT_PASS := "cannot_pass"          # 自由出牌不能不出
const ERR_INVALID_INTENT := "invalid_intent"    # 会话层:意图字典的 kind 或字段类型不对 / 不是斗地主房间
const ERR_INVALID_PLAYERS := "invalid_players"  # 开局人数不是 3

const ERROR_MESSAGES := {
	ERR_SESSION_OVER: "牌局已结束",
	ERR_NOT_SEATED: "你不在这一局里",
	ERR_NO_HAND: "下一手还没开始",
	ERR_NOT_YOUR_TURN: "还没轮到你",
	ERR_NOT_BIDDING: "叫分已经结束了",
	ERR_NOT_PLAYING: "还在叫分",
	ERR_INVALID_BID: "要比前面叫得高",
	ERR_INVALID_PLAY: "选的牌不对",
	ERR_INVALID_COMBO: "这几张牌不成牌型",
	ERR_CANNOT_BEAT: "压不过上家",
	ERR_CANNOT_PASS: "该你出牌,不能不出",
	ERR_INVALID_INTENT: "操作不合法",
	ERR_INVALID_PLAYERS: "斗地主要正好 3 个人",
}

var rng: RandomNumberGenerator
var seat_order: Array = []
var scores := {}                # pid -> 累计分
var hand_number := 0
var phase := Phase.IDLE
var hands := {}                 # pid -> Array[牌 id](升序)
var bottom: Array = []          # 底牌 3 张
var bottom_taken := false       # 地主已拿走(底牌公开)
var deal_number := 0            # 本手第几次发牌(1 … MAX_DEALS)
var first_bidder = null
var bids: Array = []            # 本次发牌的叫分 [{pid, score}]
var highest_bid := 0
var highest_bidder = null
var landlord = null
var base := 0                   # 底分(地主叫的分);定地主之前为 0
var multiplier := 1
var bombs := 0                  # 本手出过的炸弹 + 王炸个数
var current_pid = null
var lead := {}                  # {} 或 {"pid", "cards", "type", "rank", "length", "count"}
var passes := 0                 # lead 之后连续不出的人数
var table := {}                 # pid -> 本圈最后的动作:{} / {"cards": [...], "type"} / {"pass": true}
var played: Array = []          # 本手已出的牌
var play_counts := {}           # pid -> 本手出牌次数(春天判定;不出不算)
var timeouts := {}              # pid -> 连续超时次数
var trustee := {}               # pid -> bool
var ending := false
var left := {}                  # pid -> true:离开的人
var last_hand := {}             # 上一手的结算摘要(hand_over 事件去掉 type);还没打完过为 {}
var end_reason := ""


# —— 开局与每一手 ——

func start(pids: Array, p_rng: RandomNumberGenerator) -> Dictionary:
	if not _valid_seats(pids):
		return _fail(ERR_INVALID_PLAYERS)
	rng = p_rng
	seat_order = pids.duplicate()
	for pid in seat_order:
		scores[pid] = 0
		timeouts[pid] = 0
		trustee[pid] = false
	phase = Phase.IDLE
	return _ok(start_hand())


func can_start_hand() -> bool:
	return (phase == Phase.IDLE or phase == Phase.BETWEEN) and not ending and seat_order.size() == PLAYERS


func start_hand() -> Array:
	if not can_start_hand():
		return []
	hand_number += 1
	first_bidder = seat_order[rng.randi_range(0, PLAYERS - 1)]
	deal_number = 0
	_deal()
	return [
		{"type": "hand_started", "hand": hand_number, "deal": deal_number, "seats": seat_order.duplicate(),
			"first_bidder": first_bidder, "hands": _hand_counts(), "bottom_count": BOTTOM_SIZE, "scores": score_rows()},
		_turn_event(),
	]


func _deal() -> void:
	deal_number += 1
	var deck := DdzHand.full_deck()
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	for k in PLAYERS:
		hands[seat_order[k]] = DdzHand.sorted(deck.slice(k * HAND_SIZE, (k + 1) * HAND_SIZE))
	bottom = DdzHand.sorted(deck.slice(PLAYERS * HAND_SIZE))
	bottom_taken = false
	bids = []
	highest_bid = 0
	highest_bidder = null
	landlord = null
	base = 0
	multiplier = 1
	bombs = 0
	lead = {}
	passes = 0
	table = {}
	played = []
	for pid in seat_order:
		play_counts[pid] = 0
	current_pid = first_bidder
	phase = Phase.BIDDING


# —— 叫分 ——

func bid(pid: int, score: Variant, timed_out := false, auto := false) -> Dictionary:
	var error := _turn_error(pid, Phase.BIDDING)
	if error == "" and (not score is int or score < 0 or score > MAX_BID or (score > 0 and score <= highest_bid)):
		error = ERR_INVALID_BID
	if error != "":
		return _fail(error)
	if not timed_out and not auto:
		timeouts[pid] = 0
	bids.append({"pid": pid, "score": score})
	var events := [{"type": "bid", "pid": pid, "score": score, "timed_out": timed_out, "auto": auto}]
	if score > 0:
		highest_bid = score
		highest_bidder = pid
	if score == MAX_BID:
		_make_landlord(pid, score, false, events)
	elif bids.size() < PLAYERS:
		current_pid = next_pid(pid)
		events.append(_turn_event())
	elif highest_bid > 0:
		_make_landlord(highest_bidder, highest_bid, false, events)
	elif deal_number >= MAX_DEALS:
		_make_landlord(first_bidder, FORCED_BASE, true, events)
	else:
		_deal()
		events.append({"type": "redeal", "hand": hand_number, "deal": deal_number, "first_bidder": first_bidder,
			"hands": _hand_counts()})
		events.append(_turn_event())
	return _ok(events)


func _make_landlord(pid: int, score: int, forced: bool, events: Array) -> void:
	landlord = pid
	base = score
	hands[pid] = DdzHand.sorted(hands[pid] + bottom)
	bottom_taken = true
	phase = Phase.PLAYING
	current_pid = pid
	lead = {}
	passes = 0
	table = {}
	events.append({"type": "landlord", "pid": pid, "base": score, "bottom": bottom.duplicate(), "forced": forced})
	events.append(_turn_event())


# —— 出牌 ——

func play(pid: int, indices: Variant, timed_out := false, auto := false) -> Dictionary:
	var error := _turn_error(pid, Phase.PLAYING)
	if error != "":
		return _fail(error)
	var hand: Array = hands[pid]
	if not _valid_indices(indices, hand.size()):
		return _fail(ERR_INVALID_PLAY)
	var cards := DdzHand.sorted(indices.map(func(i: int) -> int: return hand[i]))
	var c := DdzHand.classify(cards)
	if c.is_empty():
		return _fail(ERR_INVALID_COMBO)
	if not lead.is_empty():
		c = DdzHand.match_lead(cards, _lead_combo())
		if c.is_empty():
			return _fail(ERR_CANNOT_BEAT)
	if not timed_out and not auto:
		timeouts[pid] = 0
	for card in cards:
		hand.erase(card)
	played.append_array(cards)
	play_counts[pid] += 1
	if DdzHand.is_bomb_like(c):
		bombs += 1
		multiplier *= 2
	lead = {"pid": pid, "cards": cards, "type": c["type"], "rank": c["rank"], "length": c["length"], "count": c["count"]}
	passes = 0
	table[pid] = {"cards": cards.duplicate(), "type": c["type"]}
	var events := [{"type": "played", "pid": pid, "cards": cards.duplicate(), "combo": c["type"], "rank": c["rank"],
		"length": c["length"], "multiplier": multiplier, "remaining": hand.size(), "timed_out": timed_out, "auto": auto}]
	if hand.is_empty():
		_end_hand(pid, events)
	else:
		current_pid = next_pid(pid)
		events.append(_turn_event())
	return _ok(events)


func pass_turn(pid: int, timed_out := false, auto := false) -> Dictionary:
	var error := _turn_error(pid, Phase.PLAYING)
	if error == "" and lead.is_empty():
		error = ERR_CANNOT_PASS
	if error != "":
		return _fail(error)
	if not timed_out and not auto:
		timeouts[pid] = 0
	passes += 1
	table[pid] = {"pass": true}
	var events := [{"type": "passed", "pid": pid, "timed_out": timed_out, "auto": auto}]
	if passes >= PLAYERS - 1:
		current_pid = lead["pid"]
		lead = {}
		passes = 0
		table = {}
		events.append({"type": "trick_cleared", "pid": current_pid})
	else:
		current_pid = next_pid(pid)
	events.append(_turn_event())
	return _ok(events)


# —— 托管与超时 ——

func set_trustee(pid: int, on: Variant) -> Dictionary:
	# 牌局没结束就随时能开关(两手之间也行,跨手保留);状态没变返回成功、没有事件
	if phase == Phase.OVER:
		return _fail(ERR_SESSION_OVER)
	if not is_member(pid):
		return _fail(ERR_NOT_SEATED)
	if not on is bool:
		return _fail(ERR_INVALID_INTENT)
	if trustee[pid] == on:
		return _ok([])
	trustee[pid] = on
	timeouts[pid] = 0
	return _ok([{"type": "trustee", "pid": pid, "on": on, "auto": false}])


func timeout() -> Dictionary:
	# 当前行动者到点:托管中走托管打法;否则记一次超时(够次数先进托管),再按超时规则代打
	if phase == Phase.OVER:
		return _fail(ERR_SESSION_OVER)
	if (phase != Phase.BIDDING and phase != Phase.PLAYING) or current_pid == null:
		return _fail(ERR_NO_HAND)
	var pid: int = current_pid
	if trustee[pid]:
		return auto_action(pid)
	var events := []
	timeouts[pid] += 1
	if timeouts[pid] >= TRUSTEE_AFTER_TIMEOUTS:
		trustee[pid] = true
		timeouts[pid] = 0
		events.append({"type": "trustee", "pid": pid, "on": true, "auto": true})
	var result: Dictionary
	if phase == Phase.BIDDING:
		result = bid(pid, 0, true)
	elif not lead.is_empty():
		result = pass_turn(pid, true)
	else:
		result = play(pid, [0], true)   # 手牌升序,第一张就是最小的单张
	events.append_array(result["events"])
	return _ok(events)


func auto_action(pid: int) -> Dictionary:
	# 托管代打(也给机器人参考):叫分不叫;自由出牌出 legal_plays 第一个;跟队友不出;跟对手出最小的能压过的非炸弹
	if phase == Phase.BIDDING:
		return bid(pid, 0, false, true)
	var hand: Array = hands[pid]
	if lead.is_empty():
		return play(pid, indices_of(hand, DdzHand.legal_plays(hand, {})[0]["cards"]), false, true)
	if not is_teammate(pid, lead["pid"]):
		for p in DdzHand.legal_plays(hand, _lead_combo()):
			if not DdzHand.is_bomb_like(p):
				return play(pid, indices_of(hand, p["cards"]), false, true)
	return pass_turn(pid, false, true)


# —— 一手结束、散局、离开 ——

func _end_hand(winner: int, events: Array) -> void:
	var landlord_won: bool = winner == landlord
	var farmer_plays := 0
	for pid in seat_order:
		if pid != landlord:
			farmer_plays += play_counts[pid]
	var spring: bool = (landlord_won and farmer_plays == 0) or (not landlord_won and play_counts[landlord] == 1)
	if spring:
		multiplier *= 2
	var unit := base * multiplier
	var deltas := []
	for pid in seat_order:
		var delta := unit * (LANDLORD_SHARE if pid == landlord else -1)
		if not landlord_won:
			delta = -delta
		scores[pid] += delta
		deltas.append({"pid": pid, "delta": delta})
	var remaining := []
	for pid in seat_order:
		remaining.append({"pid": pid, "cards": hands[pid].duplicate()})
	var ev := {"type": "hand_over", "hand": hand_number, "winner": winner, "landlord": landlord,
		"landlord_won": landlord_won, "base": base, "multiplier": multiplier, "bombs": bombs, "spring": spring,
		"deltas": deltas, "scores": score_rows(), "remaining": remaining}
	events.append(ev)
	last_hand = ev.duplicate(true)
	last_hand.erase("type")
	phase = Phase.BETWEEN
	current_pid = null
	lead = {}
	passes = 0
	if ending:
		events.append(_finish(REASON_HOST))


func request_end() -> Array:
	# 房主散局:一手进行中就打完这一手再结算,否则立即结算
	if phase == Phase.OVER or ending:
		return []
	ending = true
	if phase == Phase.BIDDING or phase == Phase.PLAYING:
		return [{"type": "ending"}]
	return [_finish(REASON_HOST)]


func remove_player(pid: int) -> Array:
	# 有人离开:牌局立即结算,进行中的一手作废
	if phase == Phase.OVER or not is_member(pid):
		return []
	left[pid] = true
	var voided := phase == Phase.BIDDING or phase == Phase.PLAYING
	return [{"type": "player_left", "pid": pid, "hand_voided": voided}, _finish(REASON_PLAYER_LEFT)]


func _finish(reason: String) -> Dictionary:
	phase = Phase.OVER
	current_pid = null
	end_reason = reason
	return {"type": "session_over", "reason": reason, "results": results()}


func results() -> Array:
	# 按累计分从高到低,同分按座位;同分同名次
	var rows := []
	for pid in seat_order:
		rows.append({"pid": pid, "score": scores[pid], "left": left.has(pid)})
	var order := range(rows.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return rows[a]["score"] > rows[b]["score"] or (rows[a]["score"] == rows[b]["score"] and a < b))
	var out := order.map(func(i: int) -> Dictionary: return rows[i])
	for row in out:
		var higher := 0
		for other in out:
			if other["score"] > row["score"]:
				higher += 1
		row["place"] = higher + 1
	return out


# —— 只读访问(视图、会话、测试用)——

func is_member(pid: Variant) -> bool:
	return pid is int and seat_order.has(pid)


func phase_name() -> String:
	return PHASE_NAMES[phase]


func next_pid(pid: int) -> int:
	return seat_order[(seat_order.find(pid) + 1) % PLAYERS]


func hand_of(pid: int) -> Array:
	return hands.get(pid, []).duplicate()


func role_of(pid: int) -> String:
	if landlord == null:
		return ""
	return ROLE_LANDLORD if pid == landlord else ROLE_FARMER


func is_teammate(a: int, b: int) -> bool:
	# 两个农民是一伙;地主没有队友
	return landlord != null and a != b and a != landlord and b != landlord


func can_pass(pid: int) -> bool:
	return phase == Phase.PLAYING and current_pid == pid and not lead.is_empty()


func bid_options(pid: int) -> Array:
	# 轮到 pid 叫分时能叫的分(0 = 不叫);不轮到为 []
	if phase != Phase.BIDDING or current_pid != pid:
		return []
	var out := [0]
	for s in range(highest_bid + 1, MAX_BID + 1):
		out.append(s)
	return out


func legal_plays_for(pid: int) -> Array:
	# 轮到 pid 出牌时能出的组合(DdzHand.legal_plays,小的在前);不轮到为 []
	if phase != Phase.PLAYING or current_pid != pid:
		return []
	return DdzHand.legal_plays(hands[pid], _lead_combo())


func lead_combo() -> Dictionary:
	return _lead_combo()


func score_rows() -> Array:
	return seat_order.map(func(pid: int) -> Dictionary: return {"pid": pid, "score": scores[pid]})


func card_count() -> int:
	var total := played.size() + (0 if bottom_taken else bottom.size())
	for pid in seat_order:
		total += hands[pid].size()
	return total


static func indices_of(hand: Array, cards: Array) -> Array:
	return cards.map(func(c: int) -> int: return hand.find(c))


# —— 小工具 ——

func _turn_error(pid: int, wanted: Phase) -> String:
	if phase == Phase.OVER:
		return ERR_SESSION_OVER
	if not is_member(pid):
		return ERR_NOT_SEATED
	if phase == Phase.IDLE or phase == Phase.BETWEEN:
		return ERR_NO_HAND
	if phase != wanted:
		return ERR_NOT_BIDDING if wanted == Phase.BIDDING else ERR_NOT_PLAYING
	if current_pid != pid:
		return ERR_NOT_YOUR_TURN
	return ""


func _turn_event() -> Dictionary:
	var stage := STAGE_BID if phase == Phase.BIDDING else STAGE_PLAY
	return {"type": "turn", "pid": current_pid, "stage": stage, "free": stage == STAGE_PLAY and lead.is_empty()}


func _lead_combo() -> Dictionary:
	if lead.is_empty():
		return {}
	return DdzHand.combo(lead["type"], lead["rank"], lead["length"], lead["count"])


func _hand_counts() -> Array:
	return seat_order.map(func(pid: int) -> Dictionary: return {"pid": pid, "count": hands[pid].size()})


static func _valid_seats(pids: Array) -> bool:
	if pids.size() != PLAYERS:
		return false
	var seen := {}
	for pid in pids:
		if not pid is int or seen.has(pid):
			return false
		seen[pid] = true
	return true


static func _valid_indices(indices: Variant, size: int) -> bool:
	if not indices is Array or indices.is_empty() or indices.size() > size:
		return false
	var seen := {}
	for i in indices:
		if not i is int or i < 0 or i >= size or seen.has(i):
			return false
		seen[i] = true
	return true


static func _ok(events: Array) -> Dictionary:
	return {"ok": true, "events": events}


static func _fail(error: String) -> Dictionary:
	return {"ok": false, "error": error, "events": []}
