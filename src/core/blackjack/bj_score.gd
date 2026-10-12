class_name BjScore
# 21 点的算点(纯函数):牌用德州的编码(PokerCard,rank 2–14,A = 14)。
# J/Q/K 算 10;A 先算 11,超过 21 就逐张改成 1。还有一张 A 算 11 时是「软」点数。


static func card_value(card: int) -> int:
	# A 记 11,人头牌记 10
	var rank := PokerCard.rank(card)
	if rank == PokerCard.ACE:
		return 11
	return mini(rank, 10)


static func evaluate(cards: Array) -> Dictionary:
	# {"total", "soft"}:soft 为真 = 有一张 A 正算作 11
	var total := 0
	var aces := 0
	for card in cards:
		total += card_value(card)
		if PokerCard.rank(card) == PokerCard.ACE:
			aces += 1
	while total > BjRules.BLACKJACK and aces > 0:
		total -= 10
		aces -= 1
	return {"total": total, "soft": aces > 0}


static func total(cards: Array) -> int:
	return evaluate(cards)["total"]


static func is_bust(cards: Array) -> bool:
	return total(cards) > BjRules.BLACKJACK


static func is_natural(cards: Array) -> bool:
	# 两张牌正好 21(A + 10 点)。分牌后的手由调用方排除
	return cards.size() == 2 and total(cards) == BjRules.BLACKJACK


static func same_value(a: int, b: int) -> bool:
	# 分牌看点数:10、J、Q、K 都算 10,可以互相分
	return card_value(a) == card_value(b)


static func dealer_peeks(up_card: int) -> bool:
	# 庄家明牌是 A 或 10 点时先看暗牌有没有黑杰克
	return card_value(up_card) >= 10


static func dealer_draws(cards: Array) -> bool:
	# 庄家要牌到 17,所有 17 点(含软 17)都停
	return total(cards) < BjRules.DEALER_STANDS


static func label(cards: Array) -> String:
	# 点数的文字:「软 17」「20」「爆牌 24」「黑杰克」;没有牌为空
	if cards.is_empty():
		return ""
	var score := evaluate(cards)
	if score["total"] > BjRules.BLACKJACK:
		return "爆牌 %d" % score["total"]
	if score["soft"] and score["total"] < BjRules.BLACKJACK:
		return "软 %d" % score["total"]
	return str(score["total"])
