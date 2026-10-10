class_name DdzHand
# 斗地主的牌与牌型(设计稿 §1):纯函数,不依赖节点 / 网络 / 局面。识别、比较、列出能出的组合(提示与代打用)。
#
# —— 牌 ——
# 编号 0–53:0–51 = 点数下标 × 4 + 花色,52 = 小王,53 = 大王。牌 id 从小到大就是点数从小到大。
#   点数下标 rank 0–14:0 = 3、1 = 4 … 7 = 10、8 = J、9 = Q、10 = K、11 = A、12 = 2、13 = 小王、14 = 大王。
#   花色同 PokerCard:0 ♠ 1 ♥ 2 ♦ 3 ♣(王没有花色,suit 为 -1)。poker_card() 换成德州牌面的牌值(王为 -1)。
#
# —— 牌型字典 combo ——
#   {"type": TYPE_*, "rank": int, "length": int, "count": int}
#   rank   比大小用的点数:单 / 对 / 三 / 三带 / 四带二 / 炸弹 = 主体那组的点数;顺子 / 连对 / 飞机 = 最小那组;王炸 = 14
#   length 连着的组数:顺子张数、连对对数、飞机的三张组数;其他牌型为 1
#   count  总张数
# 比较(beats):王炸最大;炸弹压一切非炸弹,炸弹之间比点数;其余必须同型、同张数(同组数)且点数更大。
#
# —— 带牌规则(落地时定下的细节)——
#   三带一:带的那张不能和三张同点(那是炸弹)。三带一对:带的对子点数不同于三张(王不成对)。
#   飞机:≥ 2 组连续三张,不含 2 和王;带单 = 同组数张任意牌(可以同点、可以是飞机某组的第 4 张),带对 = 同组数个
#   点数互不相同的对子。四带二:四张 + 两张任意牌(可以是一对);四带两对:四张 + 两个点数不同的对子。
#   带的单牌不能同时是大小王(王炸不拆开当翅膀)。
#   一组牌可能有多种读法(如 333444555666 既是 4 连飞机,也是 3 连飞机带单):analyze() 全部列出;
#   自由出牌按 TYPE_PRIORITY 取第一种(同型取点数最大的);跟牌时取能压过上家的读法里点数最大的(match_lead)。


const CARD_COUNT := 54
const SMALL_JOKER := 52
const BIG_JOKER := 53
const RANK_COUNT := 15
const RANK_ACE := 11            # 顺子 / 连对 / 飞机最高到 A
const RANK_TWO := 12
const RANK_SMALL_JOKER := 13
const RANK_BIG_JOKER := 14
const RANK_LABELS := ["3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A", "2", "小王", "大王"]
const SUIT_SYMBOLS := ["♠", "♥", "♦", "♣"]

const SINGLE := "single"
const PAIR := "pair"
const TRIPLE := "triple"
const TRIPLE_SINGLE := "triple_single"       # 三带一
const TRIPLE_PAIR := "triple_pair"           # 三带一对
const STRAIGHT := "straight"                 # 顺子
const PAIR_STRAIGHT := "pair_straight"       # 连对
const AIRPLANE := "airplane"                 # 飞机(不带)
const AIRPLANE_SINGLE := "airplane_single"   # 飞机带单
const AIRPLANE_PAIR := "airplane_pair"       # 飞机带对
const FOUR_TWO_SINGLE := "four_two_single"   # 四带二
const FOUR_TWO_PAIR := "four_two_pair"       # 四带两对
const BOMB := "bomb"
const ROCKET := "rocket"                     # 王炸

# 自由出牌时多种读法取靠前的(王炸、炸弹在最前:四张同点一定是炸弹)
const TYPE_PRIORITY := [ROCKET, BOMB, STRAIGHT, PAIR_STRAIGHT, AIRPLANE, AIRPLANE_PAIR, AIRPLANE_SINGLE,
	FOUR_TWO_PAIR, FOUR_TWO_SINGLE, TRIPLE_PAIR, TRIPLE_SINGLE, TRIPLE, PAIR, SINGLE]
const TYPE_NAMES := {
	SINGLE: "单张", PAIR: "对子", TRIPLE: "三张", TRIPLE_SINGLE: "三带一", TRIPLE_PAIR: "三带一对",
	STRAIGHT: "顺子", PAIR_STRAIGHT: "连对", AIRPLANE: "飞机", AIRPLANE_SINGLE: "飞机带单", AIRPLANE_PAIR: "飞机带对",
	FOUR_TWO_SINGLE: "四带二", FOUR_TWO_PAIR: "四带两对", BOMB: "炸弹", ROCKET: "王炸",
}

const STRAIGHT_MIN := 5         # 顺子至少 5 张
const PAIR_STRAIGHT_MIN := 3    # 连对至少 3 对
const AIRPLANE_MIN := 2         # 飞机至少 2 组


# —— 牌 ——

static func rank(card: int) -> int:
	if card == SMALL_JOKER:
		return RANK_SMALL_JOKER
	if card == BIG_JOKER:
		return RANK_BIG_JOKER
	return card >> 2


static func suit(card: int) -> int:
	return -1 if card >= SMALL_JOKER else card & 3


static func make(r: int, s: int) -> int:
	# r 0–12(3 … 2);王直接用 SMALL_JOKER / BIG_JOKER
	return r * 4 + s


static func is_card(value: Variant) -> bool:
	return value is int and value >= 0 and value < CARD_COUNT


static func is_joker(card: int) -> bool:
	return card >= SMALL_JOKER


static func full_deck() -> Array:
	return range(CARD_COUNT)


static func poker_card(card: int) -> int:
	# 换成 PokerCard 的牌值(德州牌面复用):3–A → 3–14,2 → 2;王返回 -1(阶段二补两张原创王牌面)
	if is_joker(card):
		return -1
	var r := rank(card)
	return PokerCard.make(2 if r == RANK_TWO else r + 3, suit(card))


static func label(card: int) -> String:
	if is_joker(card):
		return RANK_LABELS[rank(card)]
	return RANK_LABELS[rank(card)] + SUIT_SYMBOLS[suit(card)]


static func labels(cards: Array) -> String:
	return " ".join(cards.map(func(c: int) -> String: return label(c)))


static func type_name(type: String) -> String:
	return TYPE_NAMES.get(type, "")


static func sorted(cards: Array) -> Array:
	var out := cards.duplicate()
	out.sort()
	return out


static func rank_counts(cards: Array) -> Array:
	var counts := []
	counts.resize(RANK_COUNT)
	counts.fill(0)
	for c in cards:
		counts[rank(c)] += 1
	return counts


static func is_valid_set(cards: Variant) -> bool:
	# 一组互不相同的合法牌 id
	if not cards is Array or cards.is_empty():
		return false
	var seen := {}
	for c in cards:
		if not is_card(c) or seen.has(c):
			return false
		seen[c] = true
	return true


# —— 识别 ——

static func analyze(cards: Array) -> Array:
	# 这组牌的全部合法读法(按 TYPE_PRIORITY,同型点数大的在前);不是合法牌型返回 []
	var out := []
	if not is_valid_set(cards):
		return out
	var n := cards.size()
	var counts := rank_counts(cards)
	var used := []
	for r in RANK_COUNT:
		if counts[r] > 0:
			used.append(r)
	if n == 2 and counts[RANK_SMALL_JOKER] == 1 and counts[RANK_BIG_JOKER] == 1:
		return [combo(ROCKET, RANK_BIG_JOKER, 1, 2)]
	if used.size() == 1:
		match n:
			1:
				out.append(combo(SINGLE, used[0], 1, 1))
			2:
				out.append(combo(PAIR, used[0], 1, 2))
			3:
				out.append(combo(TRIPLE, used[0], 1, 3))
			4:
				out.append(combo(BOMB, used[0], 1, 4))
		return out
	if n >= STRAIGHT_MIN and _is_chain(counts, used, 1):
		out.append(combo(STRAIGHT, used[0], n, n))
	if n >= PAIR_STRAIGHT_MIN * 2 and _is_chain(counts, used, 2):
		out.append(combo(PAIR_STRAIGHT, used[0], n / 2, n))
	if n >= AIRPLANE_MIN * 3 and _is_chain(counts, used, 3):
		out.append(combo(AIRPLANE, used[0], n / 3, n))
	if n >= AIRPLANE_MIN * 5 and n % 5 == 0:
		out.append_array(_winged_airplanes(counts, n / 5, 2))
	if n >= AIRPLANE_MIN * 4 and n % 4 == 0:
		out.append_array(_winged_airplanes(counts, n / 4, 1))
	if n == 8 or n == 6:
		for r in range(RANK_TWO, -1, -1):
			if counts[r] == 4:
				var rest := counts.duplicate()
				rest[r] = 0
				if n == 8 and _distinct_pairs(rest):
					out.append(combo(FOUR_TWO_PAIR, r, 1, 8))
				elif n == 6 and _singles_ok(rest):
					out.append(combo(FOUR_TWO_SINGLE, r, 1, 6))
	if (n == 4 or n == 5) and used.size() == 2:
		for r in used:
			var other: int = used[0] if r == used[1] else used[1]
			if counts[r] == 3 and counts[other] == n - 3:
				out.append(combo(TRIPLE_SINGLE if n == 4 else TRIPLE_PAIR, r, 1, n))
	return out


static func classify(cards: Array) -> Dictionary:
	# 自由出牌时的读法;不是合法牌型返回 {}
	var all := analyze(cards)
	return all[0] if not all.is_empty() else {}


static func match_lead(cards: Array, lead: Dictionary) -> Dictionary:
	# 跟牌:能压过 lead 的读法里点数最大的那种;lead 为 {} 时等于 classify;压不过返回 {}
	if lead.is_empty():
		return classify(cards)
	var best := {}
	for c in analyze(cards):
		if beats(c, lead) and (best.is_empty() or _stronger(c, best)):
			best = c
	return best


static func beats(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	if a["type"] == ROCKET:
		return b["type"] != ROCKET
	if b["type"] == ROCKET:
		return false
	if a["type"] == BOMB:
		return b["type"] != BOMB or a["rank"] > b["rank"]
	if b["type"] == BOMB:
		return false
	return a["type"] == b["type"] and a["count"] == b["count"] and a["length"] == b["length"] and a["rank"] > b["rank"]


static func is_bomb_like(c: Dictionary) -> bool:
	# 炸弹与王炸:出一个倍数 ×2
	return c.get("type", "") == BOMB or c.get("type", "") == ROCKET


static func combo(type: String, r: int, length: int, count: int) -> Dictionary:
	return {"type": type, "rank": r, "length": length, "count": count}


# —— 列出能出的组合(提示按钮循环、超时托管、机器人)——

static func legal_plays(hand: Array, lead: Dictionary) -> Array:
	# 每项 = combo 字段 + "cards": [牌 id](升序)。每种「型 + 点数 + 组数」只给一个代表,带牌挑最不心疼的
	# (先用单出的点数,再拆对子、三张,最后才拆炸弹;同档点数小的先)。
	# 排序(小的在前):跟牌时同型按点数,其后炸弹按点数,王炸最后;自由出牌时非炸弹按点数、同点数张数多的先
	# (四带二排在同点数的其他组合之后,免得先拆炸弹),其后炸弹、王炸。
	var by_rank := []
	for r in RANK_COUNT:
		by_rank.append([])
	for c in sorted(hand):
		by_rank[rank(c)].append(c)
	var counts := by_rank.map(func(cards: Array) -> int: return cards.size())
	var out := []
	for r in RANK_COUNT:
		var group: Array = by_rank[r]
		if group.size() >= 1:
			_add(out, SINGLE, r, 1, group.slice(0, 1))
		if group.size() >= 2:
			_add(out, PAIR, r, 1, group.slice(0, 2))
		if group.size() >= 3:
			var body := group.slice(0, 3)
			_add(out, TRIPLE, r, 1, body)
			_add_winged(out, TRIPLE_SINGLE, r, 1, body, by_rank, counts, [r], 1, 1)
			_add_winged(out, TRIPLE_PAIR, r, 1, body, by_rank, counts, [r], 1, 2)
		if group.size() == 4:
			_add(out, BOMB, r, 1, group.duplicate())
			_add_winged(out, FOUR_TWO_SINGLE, r, 1, group, by_rank, counts, [r], 2, 1)
			_add_winged(out, FOUR_TWO_PAIR, r, 1, group, by_rank, counts, [r], 2, 2)
	if counts[RANK_SMALL_JOKER] == 1 and counts[RANK_BIG_JOKER] == 1:
		_add(out, ROCKET, RANK_BIG_JOKER, 1, [SMALL_JOKER, BIG_JOKER])
	_add_chains(out, by_rank, counts)
	if not lead.is_empty():
		out = out.filter(func(p: Dictionary) -> bool: return beats(p, lead))
	var keyed := out.map(func(p: Dictionary) -> Array: return [_sort_key(p, lead.is_empty()), p])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return _key_less(a[0], b[0]))
	return keyed.map(func(e: Array) -> Dictionary: return e[1])


static func smallest_single(hand: Array) -> int:
	# 必须出牌又超时:出点数最小的那张(手牌升序时就是第一张)
	return sorted(hand)[0]


# —— 小工具 ——

static func _is_chain(counts: Array, used: Array, width: int) -> bool:
	# used 里的点数各恰好 width 张、连续、最高不过 A
	if used[-1] > RANK_ACE or used[-1] - used[0] != used.size() - 1:
		return false
	for r in used:
		if counts[r] != width:
			return false
	return true


static func _winged_airplanes(counts: Array, k: int, wing_width: int) -> Array:
	# k 组连续三张 + k 个翅膀(wing_width 1 = 单张、2 = 对子);点数大的在前
	var out := []
	for start in range(RANK_ACE - k + 1, -1, -1):
		var ok := true
		for r in range(start, start + k):
			if counts[r] < 3:
				ok = false
				break
		if not ok:
			continue
		var rest := counts.duplicate()
		for r in range(start, start + k):
			rest[r] -= 3
		if (wing_width == 1 and _singles_ok(rest)) or (wing_width == 2 and _distinct_pairs(rest)):
			out.append(combo(AIRPLANE_SINGLE if wing_width == 1 else AIRPLANE_PAIR, start, k, k * (3 + wing_width)))
	return out


static func _singles_ok(rest: Array) -> bool:
	# 带的单牌不能同时是大小王
	return not (rest[RANK_SMALL_JOKER] > 0 and rest[RANK_BIG_JOKER] > 0)


static func _distinct_pairs(rest: Array) -> bool:
	# 剩下的每个点数要么没有、要么恰好一对(王不成对:各只有一张,自然不满足)
	for n in rest:
		if n != 0 and n != 2:
			return false
	return true


static func _stronger(a: Dictionary, b: Dictionary) -> bool:
	# 同一组牌的两种读法谁更「大」:炸弹类优先,其次点数
	if is_bomb_like(a) != is_bomb_like(b):
		return is_bomb_like(a)
	return a["rank"] > b["rank"]


static func _add(out: Array, type: String, r: int, length: int, cards: Array) -> void:
	var entry := combo(type, r, length, cards.size())
	entry["cards"] = sorted(cards)
	out.append(entry)


static func _add_winged(out: Array, type: String, r: int, length: int, body: Array, by_rank: Array, counts: Array,
		exclude: Array, wings: int, width: int) -> void:
	var picked := _pick_wings(by_rank, counts, body, exclude, wings, width)
	if picked.is_empty():
		return
	_add(out, type, r, length, body + picked)


static func _add_chains(out: Array, by_rank: Array, counts: Array) -> void:
	# 顺子 / 连对 / 飞机(含带翅膀):每个起点、每种长度一个代表
	for width in [1, 2, 3]:
		var min_len: int = [0, STRAIGHT_MIN, PAIR_STRAIGHT_MIN, AIRPLANE_MIN][width]
		for start in range(0, RANK_ACE + 1):
			var length := 0
			var body := []
			while start + length <= RANK_ACE and counts[start + length] >= width:
				body.append_array(by_rank[start + length].slice(0, width))
				length += 1
				if length < min_len:
					continue
				match width:
					1:
						_add(out, STRAIGHT, start, length, body)
					2:
						_add(out, PAIR_STRAIGHT, start, length, body)
					3:
						# 飞机的翅膀可以用机身某组的第 4 张(analyze 也认),所以不排除机身点数,只排除机身那几张
						_add(out, AIRPLANE, start, length, body)
						_add_winged(out, AIRPLANE_SINGLE, start, length, body, by_rank, counts, [], length, 1)
						_add_winged(out, AIRPLANE_PAIR, start, length, body, by_rank, counts, [], length, 2)


static func _pick_wings(by_rank: Array, counts: Array, body: Array, exclude: Array, wings: int, width: int) -> Array:
	# 挑 wings 个翅膀(width 1 = 单张、2 = 不同点数的对子),不用 body 里的牌、不碰 exclude 里的点数;凑不齐返回 []。
	# 偏好:张数正好 width 的点数(不拆组)在前,其后拆更大的组,炸弹最后;同档点数小的先
	var avail := []
	for r in RANK_COUNT:
		avail.append([] if exclude.has(r) else by_rank[r].filter(func(c: int) -> bool: return not body.has(c)))
	var ranks := []
	for r in RANK_COUNT:
		if avail[r].size() >= width:
			ranks.append(r)
	ranks.sort_custom(func(a: int, b: int) -> bool:
		var ka: int = 0 if counts[a] == width else counts[a]
		var kb: int = 0 if counts[b] == width else counts[b]
		return ka < kb or (ka == kb and a < b))
	var picked := []
	if width == 2:
		if ranks.size() < wings:
			return []
		for i in wings:
			picked.append_array(avail[ranks[i]].slice(0, 2))
		return picked
	var pool := []
	for r in ranks:
		pool.append_array(avail[r])
	for c in pool:
		if picked.size() == wings:
			break
		if c == BIG_JOKER and picked.has(SMALL_JOKER):
			continue   # 不把王炸拆开当两张翅膀
		picked.append(c)
	return picked if picked.size() == wings else []


static func _sort_key(p: Dictionary, free: bool) -> Array:
	var bomb_rank := 0
	if p["type"] == BOMB:
		bomb_rank = 1
	elif p["type"] == ROCKET:
		bomb_rank = 2
	if not free:
		return [bomb_rank, p["rank"], p["count"]]
	var four_two := 1 if p["type"] == FOUR_TWO_SINGLE or p["type"] == FOUR_TWO_PAIR else 0
	return [bomb_rank, p["rank"], four_two, -p["count"], TYPE_PRIORITY.find(p["type"])]


static func _key_less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false
