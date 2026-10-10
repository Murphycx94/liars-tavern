class_name BombCatDeck
# 炸弹猫配牌(规格 §1.4):按人数 n 配功能牌,发牌后把多余的拆弹与 n − 1 张炸弹混回牌堆。
# 洗牌一律用传入的 RandomNumberGenerator(Fisher-Yates),同一种子结果可复现。牌堆数组下标 0 = 顶。


const MIN_PLAYERS := 2
const MAX_PLAYERS := 6
const HAND_SIZE := 4            # 先发 4 张,再每人补 1 张拆弹(开局手牌 5 张;原 7+1 太多,手牌条挤、一局拖长)

# 功能牌数量(不含炸弹和拆弹):[2–3 人, 4–5 人, 6 人];零食每种各这么多张
# (2026-10-10 减量约四分之一:3 人局 48 → 36 张,6 人局 71 → 58 张;炸弹与拆弹的规则不变)
const ACTION_COUNTS := {
	BombCatCard.SKIP: [3, 4, 5],
	BombCatCard.PASS_TURNS: [2, 3, 4],
	BombCatCard.PEEK: [3, 4, 5],
	BombCatCard.SHUFFLE: [2, 3, 4],
	BombCatCard.BEG: [2, 3, 3],
	BombCatCard.NOPE: [3, 4, 5],
}
const SNACK_COUNT := [3, 3, 4]


static func is_valid_count(n: int) -> bool:
	return n >= MIN_PLAYERS and n <= MAX_PLAYERS


static func tier(n: int) -> int:
	# 配牌表的列:2–3 人 0、4–5 人 1、6 人 2
	if n <= 3:
		return 0
	return 1 if n <= 5 else 2


static func action_counts(n: int) -> Dictionary:
	# 牌 id -> 张数(功能牌与零食,不含炸弹和拆弹)
	var counts := {}
	for id in ACTION_COUNTS:
		counts[id] = ACTION_COUNTS[id][tier(n)]
	for id in BombCatCard.SNACKS:
		counts[id] = SNACK_COUNT[tier(n)]
	return counts


static func defuse_total(n: int) -> int:
	return n + 1 if n >= 5 else n + 2


static func bomb_count(n: int) -> int:
	return n - 1


static func total_cards(n: int) -> int:
	var total := defuse_total(n) + bomb_count(n)
	var counts := action_counts(n)
	for id in counts:
		total += counts[id]
	return total


static func action_pile(n: int) -> Array:
	# 不洗的功能牌堆(按 BombCatCard.ALL 的顺序)
	var cards := []
	var counts := action_counts(n)
	for id in BombCatCard.ALL:
		for i in counts.get(id, 0):
			cards.append(id)
	return cards


static func shuffle(cards: Array, rng: RandomNumberGenerator) -> void:
	# 就地 Fisher-Yates
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp


static func deal(pids: Array, rng: RandomNumberGenerator) -> Dictionary:
	# 返回 {"hands": {pid: [牌 id...]}, "deck": [牌 id...](下标 0 = 顶)}。
	# 功能牌洗匀 → 按座次每人发 HAND_SIZE 张 → 每人 1 张拆弹 → 剩余拆弹与 n − 1 张炸弹混回 → 再洗
	var n := pids.size()
	var pile := action_pile(n)
	shuffle(pile, rng)
	var hands := {}
	for pid in pids:
		hands[pid] = []
	for round_i in HAND_SIZE:
		for pid in pids:
			hands[pid].append(pile.pop_front())
	for pid in pids:
		hands[pid].append(BombCatCard.DEFUSE)
	for i in defuse_total(n) - n:
		pile.append(BombCatCard.DEFUSE)
	for i in bomb_count(n):
		pile.append(BombCatCard.BOMB)
	shuffle(pile, rng)
	return {"hands": hands, "deck": pile}
