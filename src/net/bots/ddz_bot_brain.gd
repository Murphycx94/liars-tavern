class_name DdzBotBrain
# 斗地主机器人的内置策略(没接 AI、或 AI 没按时回答时用)。只看玩家能看到的东西:公共视图 + 自己的私有视图,不偷看别人的牌。
# 核心是「手数」:把手牌按 炸弹 → 飞机 → 顺子 / 连对 → 三张(带翅膀)→ 对子 / 单张 拆开,要几手才能出完(turns)。
# 叫分:王、2、炸弹记分,手数少再加分,够门槛就叫(风格调门槛)。
# 出牌:每个可出的组合都算一遍「出完以后剩下的牌值多少」(score:手数,大牌算控制权扣一点),挑最划算的;
#   能一把出完就出完;自由出牌出最省手数的小牌,对手只剩一两张时不出能被顶的单张 / 对子,队友只剩一张就喂小单张;
#   跟牌时队友的牌不压,对手的牌压得划算(或对手快走完了)才压,炸弹留给关键时刻。随机数从外面给,决策可以单测。


const STAGE_BID := "bid"
const STAGE_PLAY := "play"

# 叫分:强度 ≥ 门槛就叫这么多分(1 / 2 / 3 分),风格的 bid_bias 加在门槛上
const BID_THRESHOLDS := [3.0, 5.5, 8.0]
const ROCKET_POINTS := 8.0
const BIG_JOKER_POINTS := 4.0
const SMALL_JOKER_POINTS := 3.0
const TWO_POINTS := 2.0
const BOMB_POINTS := 6.0
const TURNS_PAR := 9                 # 17 张牌的「一般」手数:比它少一手加 TURN_POINTS
const TURN_POINTS := 0.6
const BID_JITTER := 0.5              # 强度的随机扰动(同样的牌不总是同样叫)

# 出牌估值
const CONTROL_WEIGHTS := {DdzHand.RANK_TWO: 0.6, DdzHand.RANK_SMALL_JOKER: 0.9, DdzHand.RANK_BIG_JOKER: 1.2}
const RANK_TIE := 0.01               # 同样划算时先出点数小的
const COUNT_TIE := 0.005             # 再同样时先出张数多的
const LEAD_BOMB_PENALTY := 2.5       # 自由出牌不随便扔炸弹
const FOUR_TWO_PENALTY := 2.5        # 四带二 / 四带两对把炸弹拆成普通牌型:不到最后不这么出
const DANGER_PENALTY := 3.0          # 对手只剩 1 张时出单张(对手剩 2 张时出对子)的代价,点数越大越小
const FEED_BONUS := 5.0              # 队友只剩 1 张(2 张)、下家就是他:喂最小的单张(对子)
const URGENT_CARDS := 4              # 对手剩这么几张以内:能压就压,该炸就炸
const URGENT_SLACK := 3.0
const BOMB_FINISH_TURNS := 2         # 炸完剩下的牌不超过这么多手:炸

# 风格:bid_bias 加在叫分门槛上(负数爱叫);follow_slack 是跟牌时愿意多花的代价;bomb_eager 对手不急也肯炸。
# persona 是给 AI 的人设(接了 AI 时机器人照它的性格打)
const STYLES := [
	{"id": "steady", "label": "稳健", "bid_bias": 0.0, "follow_slack": 0.3, "bomb_eager": false,
		"persona": "稳健派:牌好才叫地主,出牌按部就班,炸弹留到关键时刻。"},
	{"id": "wild", "label": "凶狠", "bid_bias": -1.5, "follow_slack": 1.0, "bomb_eager": true,
		"persona": "凶狠派:爱抢地主,见牌就压,该炸就炸,但不会乱拆好牌。"},
	{"id": "sly", "label": "狡猾", "bid_bias": -0.5, "follow_slack": 0.5, "bomb_eager": false,
		"persona": "狡猾派:会记牌、会留后手,和队友配合,关键时刻才亮大牌。"},
	{"id": "easy", "label": "随和", "bid_bias": 1.0, "follow_slack": 0.1, "bomb_eager": false,
		"persona": "随和派:不太爱抢地主,打牌顺其自然,很少主动拆牌去压人。"},
]


static func style(index: int) -> Dictionary:
	return STYLES[posmod(index, STYLES.size())]


# —— 局面 ——

static func situation(pub: Dictionary, priv: Dictionary, me: int) -> Dictionary:
	# 从公共视图与自己的私有视图提炼决策要用的东西;不轮到自己时 stage 为 ""
	var stage := ""
	if pub.get("current_pid") == me and priv.get("my_turn", false):
		match pub.get("phase"):
			"bidding":
				stage = STAGE_BID
			"playing":
				stage = STAGE_PLAY
	var hand: Array = priv.get("cards", [])
	var lead: Dictionary = pub.get("lead", {})
	var lead_combo := {}
	if not lead.is_empty():
		lead_combo = DdzHand.combo(lead.get("type", ""), int(lead.get("rank", 0)), int(lead.get("length", 1)),
			int(lead.get("count", 0)))
	var seats := []
	var counts := {}
	for row in pub.get("players", []):
		seats.append(row.get("pid"))
		counts[row.get("pid")] = int(row.get("hand_count", 0))
	var landlord: Variant = pub.get("landlord")
	var teammate: Variant = null
	var enemies := []
	for pid in seats:
		if pid == me:
			continue
		if landlord != null and landlord != me and pid != landlord:
			teammate = pid
		else:
			enemies.append(pid)
	var enemy_min := DdzState.HAND_SIZE + DdzState.BOTTOM_SIZE
	for pid in enemies:
		enemy_min = mini(enemy_min, counts[pid])
	var at := seats.find(me)
	return {
		"me": me,
		"stage": stage,
		"hand": hand,
		"legal": DdzHand.legal_plays(hand, lead_combo) if stage == STAGE_PLAY else [],
		"lead": lead,
		"lead_combo": lead_combo,
		"can_pass": priv.get("can_pass", false),
		"bid_options": priv.get("bid_options", []),
		"highest_bid": int(pub.get("highest_bid", 0)),
		"landlord": landlord,
		"teammate": teammate,
		"enemies": enemies,
		"enemy_min": enemy_min,
		"next": seats[(at + 1) % seats.size()] if at >= 0 else null,
		"counts": counts,
	}


# —— 决策 ——

static func decide(sit: Dictionary, bot_style: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	# → {"kind": "bid", "score"} / {"kind": "play", "cards": [牌 id]} / {"kind": "pass"};不轮到自己时返回 {}
	match sit["stage"]:
		STAGE_BID:
			return decide_bid(sit, bot_style, rng)
		STAGE_PLAY:
			return decide_play(sit, bot_style)
	return {}


static func decide_bid(sit: Dictionary, bot_style: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var options: Array = sit["bid_options"]
	var strength := hand_strength(sit["hand"]) + rng.randf_range(-BID_JITTER, BID_JITTER)
	var want := 0
	for i in BID_THRESHOLDS.size():
		if strength >= BID_THRESHOLDS[i] + bot_style["bid_bias"]:
			want = i + 1
	return bid(want if options.has(want) else 0)


static func decide_play(sit: Dictionary, bot_style: Dictionary) -> Dictionary:
	var hand: Array = sit["hand"]
	var legal: Array = sit["legal"]
	if legal.is_empty():
		return pass_turn() if sit["can_pass"] else {}
	for p in legal:
		if p["count"] == hand.size():
			return play(p["cards"])   # 一把出完
	var counts := DdzHand.rank_counts(hand)
	if sit["lead_combo"].is_empty():
		return _lead(sit, legal, counts)
	return _follow(sit, bot_style, legal, counts)


static func _lead(sit: Dictionary, legal: Array, counts: Array) -> Dictionary:
	# 自由出牌:出完以后剩下的牌最好打的那一手;对手快走完时不出能被顶的小单张 / 小对子,能喂队友就喂
	var danger: int = sit["enemy_min"]
	var feed := _feed_size(sit)
	var smallest := {}
	var best := {}
	var best_cost := INF
	for p in legal:
		var cost: float = score(_minus(counts, p["cards"])) + p["rank"] * RANK_TIE - p["count"] * COUNT_TIE
		if DdzHand.is_bomb_like(p):
			cost += LEAD_BOMB_PENALTY
		cost += _four_two_penalty(p)
		if (danger == 1 and p["type"] == DdzHand.SINGLE) or (danger == 2 and p["type"] == DdzHand.PAIR):
			cost += DANGER_PENALTY * (1.0 - p["rank"] / float(DdzHand.RANK_BIG_JOKER))
		if feed > 0 and p["count"] == feed and p["type"] == (DdzHand.SINGLE if feed == 1 else DdzHand.PAIR) \
				and (smallest.is_empty() or p["rank"] < smallest["rank"]):
			smallest = p
		if cost < best_cost:
			best_cost = cost
			best = p
	return play((smallest if not smallest.is_empty() else best)["cards"])


static func _feed_size(sit: Dictionary) -> int:
	# 农民:下家是队友、他只剩 1 或 2 张、地主没比他更快 → 喂他单张 / 对子(返回张数,不喂为 0)
	var mate: Variant = sit["teammate"]
	if mate == null or sit["next"] != mate:
		return 0
	var left: int = sit["counts"].get(mate, 0)
	if left > 2 or sit["enemy_min"] < left:
		return 0
	return left


static func _follow(sit: Dictionary, bot_style: Dictionary, legal: Array, counts: Array) -> Dictionary:
	# 跟牌:队友的牌不压;对手的牌,压完剩下的牌不比不压难打太多就压(对手快走完了就硬压),压不了再看炸不炸
	if sit["can_pass"] and sit["teammate"] != null and sit["lead"].get("pid") == sit["teammate"]:
		return pass_turn()
	var urgent: bool = sit["enemy_min"] <= URGENT_CARDS
	var base := score(counts)
	var best := {}
	var best_cost := INF
	var bombs := []
	for p in legal:
		if DdzHand.is_bomb_like(p):
			bombs.append(p)
			continue
		var cost: float = score(_minus(counts, p["cards"])) + p["rank"] * RANK_TIE + _four_two_penalty(p)
		if cost < best_cost:
			best_cost = cost
			best = p
	var slack: float = bot_style["follow_slack"] + (URGENT_SLACK if urgent else 0.0)
	if not best.is_empty() and best_cost <= base + slack:
		return play(best["cards"])
	for p in bombs:   # 小炸弹在前、王炸最后:只考虑最小的那个
		var rest_turns := turns(_minus(counts, p["cards"]))
		if urgent or rest_turns <= BOMB_FINISH_TURNS or (bot_style["bomb_eager"] and sit["enemy_min"] <= 2 * URGENT_CARDS):
			return play(p["cards"])
		break
	if sit["can_pass"]:
		return pass_turn()
	return play(legal[0]["cards"]) if not legal.is_empty() else {}


static func _four_two_penalty(p: Dictionary) -> float:
	return FOUR_TWO_PENALTY if p["type"] == DdzHand.FOUR_TWO_SINGLE or p["type"] == DdzHand.FOUR_TWO_PAIR else 0.0


static func bid(score_value: int) -> Dictionary:
	return {"kind": "bid", "score": score_value}


static func play(cards: Array) -> Dictionary:
	return {"kind": "play", "cards": cards.duplicate()}


static func pass_turn() -> Dictionary:
	return {"kind": "pass"}


static func fallback(sit: Dictionary) -> Dictionary:
	# 兜底(AI 答非所问又被拒的时候):和超时代打一样,叫分不叫;能不出就不出,必须出就出最小的单张
	if sit["stage"] == STAGE_BID:
		return bid(0)
	if sit["can_pass"]:
		return pass_turn()
	var hand: Array = sit["hand"]
	return play([DdzHand.smallest_single(hand)]) if not hand.is_empty() else {}


# —— 估值 ——

static func hand_strength(cards: Array) -> float:
	# 叫分用的牌力:王炸 8、大王 4、小王 3、每张 2 记 2、每个炸弹 6,再按手数加减
	var counts := DdzHand.rank_counts(cards)
	var s := 0.0
	if counts[DdzHand.RANK_SMALL_JOKER] > 0 and counts[DdzHand.RANK_BIG_JOKER] > 0:
		s += ROCKET_POINTS
	else:
		s += counts[DdzHand.RANK_BIG_JOKER] * BIG_JOKER_POINTS + counts[DdzHand.RANK_SMALL_JOKER] * SMALL_JOKER_POINTS
	s += counts[DdzHand.RANK_TWO] * TWO_POINTS
	for r in DdzHand.RANK_TWO + 1:
		if counts[r] == 4:
			s += BOMB_POINTS
	return s + (TURNS_PAR - turns(counts)) * TURN_POINTS


static func score(counts: Array) -> float:
	# 剩下的牌值多少(越小越好):要几手出完,手里的 2 和王是控制权,各抵掉一点
	var s := float(turns(counts))
	for r in CONTROL_WEIGHTS:
		s -= counts[r] * CONTROL_WEIGHTS[r]
	return s


static func turns(counts: Array) -> int:
	# 至少要几手出完(贪心拆牌,试几种拆法取最少)
	var best := 1 << 30
	for plan in [[1, 2], [2, 1], [2], []]:
		best = mini(best, _turns_with(counts.duplicate(), plan))
	return best


static func _turns_with(c: Array, chain_widths: Array) -> int:
	# 王炸 → 炸弹 → 飞机 → 按 chain_widths 的顺序拆顺子(1)/ 连对(2)→ 三张 → 剩下的单张 / 对子(三张与飞机带走一部分)
	var t := 0
	var wings := 0
	if c[DdzHand.RANK_SMALL_JOKER] > 0 and c[DdzHand.RANK_BIG_JOKER] > 0:
		c[DdzHand.RANK_SMALL_JOKER] = 0
		c[DdzHand.RANK_BIG_JOKER] = 0
		t += 1
	for r in DdzHand.RANK_TWO + 1:
		if c[r] == 4:
			c[r] = 0
			t += 1
	while true:
		var run := _longest_run(c, 3)
		if run[1] < DdzHand.AIRPLANE_MIN:
			break
		_take(c, run, 3)
		t += 1
		wings += run[1]
	for width in chain_widths:
		var min_len: int = DdzHand.STRAIGHT_MIN if width == 1 else DdzHand.PAIR_STRAIGHT_MIN
		while true:
			var run := _longest_run(c, width)
			if run[1] < min_len:
				break
			_take(c, run, width)
			t += 1
	for r in DdzHand.RANK_TWO + 1:
		if c[r] == 3:
			c[r] = 0
			t += 1
			wings += 1
	var loose := 0
	for r in DdzHand.RANK_COUNT:
		if c[r] > 0:
			loose += 1
	return t + loose - mini(wings, loose)


static func _longest_run(c: Array, width: int) -> Array:
	# 最长的一串连续点数(到 A 为止)每个至少 width 张:[起点, 长度]
	var best := [0, 0]
	var r := 0
	while r <= DdzHand.RANK_ACE:
		if c[r] < width:
			r += 1
			continue
		var e := r
		while e + 1 <= DdzHand.RANK_ACE and c[e + 1] >= width:
			e += 1
		if e - r + 1 > best[1]:
			best = [r, e - r + 1]
		r = e + 1
	return best


static func _take(c: Array, run: Array, width: int) -> void:
	for r in range(run[0], run[0] + run[1]):
		c[r] -= width


static func _minus(counts: Array, cards: Array) -> Array:
	var rest := counts.duplicate()
	for card in cards:
		rest[DdzHand.rank(card)] -= 1
	return rest
