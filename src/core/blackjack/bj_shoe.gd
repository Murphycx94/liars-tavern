class_name BjShoe
extends RefCounted
# 21 点牌鞋:6 副德州牌(PokerCard 编码,同一张牌有 6 张)用房主 RNG 洗好,从末尾往前发。
# 一局开始时剩不到 BjRules.RESHUFFLE_BELOW 张就整鞋重洗(已发出去的牌都收回来)。


var _rng: RandomNumberGenerator
var _cards: Array = []
var rigged: Array = []   # 测试钩子:先按顺序发这些牌(用完再从牌鞋里发);不从牌鞋里扣


func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng
	shuffle()


static func size() -> int:
	return BjRules.DECKS * PokerDeck.build(false).size()


func shuffle() -> void:
	_cards = []
	for i in BjRules.DECKS:
		_cards.append_array(PokerDeck.build(false))
	for i in range(_cards.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = _cards[i]
		_cards[i] = _cards[j]
		_cards[j] = tmp


func needs_shuffle() -> bool:
	return _cards.size() < BjRules.RESHUFFLE_BELOW


func remaining() -> int:
	return _cards.size()


func draw() -> int:
	if not rigged.is_empty():
		return rigged.pop_front()
	if _cards.is_empty():
		shuffle()   # 一局里不会发到这么多张(7 人各 4 手也远不到 234 张),只是兜底
	return _cards.pop_back()
