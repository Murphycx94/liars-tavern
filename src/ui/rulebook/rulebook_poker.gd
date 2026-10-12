class_name RulebookPoker
# 说明书的德州扑克那本(长牌、短牌共用):按章节组织的纯数据,由 Rulebook 渲染,块类型见 RulebookContent。
# 规则数字全部取自 PokerRules 与 Protocol.TURN_TIMEOUT,规则改动时说明书自动跟随;
# 例子里的金额按大盲的倍数算,改了盲注也自洽。下面两个常量在规则引擎(任务 1)里才有归宿,
# 这里的副本必须与之相同,引擎合并后改用引擎的:
#   HAND_SIZE     = HandEvaluator.HAND_SIZE
#   AWAY_TIMEOUTS = PokerRules.AWAY_AFTER_TIMEOUTS
# 界面字体里没有花色字形(规格 §6.1):文案不写花色符号,具体的牌由 hands 块画成小牌。


const HAND_SIZE := 5                       # 牌型由 5 张牌组成:示例每行 5 张,顺子是 5 个相连的点数
const AWAY_TIMEOUTS := 2                   # 连续这么多次超时就离座(规格 §2.8)
# 例子里的金额(以大盲计,不是规则)
const RAISE_EXAMPLE_BLINDS := 3            # 翻牌前有人加注到 3 个大盲
const REFUND_EXAMPLE_BLINDS := [15, 5]     # 你下注 15 个大盲,对手全下只跟了 5 个

# 牌型表每行牌型名下面的一句说明
const HAND_CAPTIONS := {
	PokerRules.Category.STRAIGHT_FLUSH: "同一花色的顺子",
	PokerRules.Category.FOUR_OF_A_KIND: "四张同点",
	PokerRules.Category.FULL_HOUSE: "三条加一对",
	PokerRules.Category.FLUSH: "五张同一花色",
	PokerRules.Category.STRAIGHT: "五张点数相连",
	PokerRules.Category.THREE_OF_A_KIND: "三张同点",
	PokerRules.Category.TWO_PAIR: "两个对子",
	PokerRules.Category.ONE_PAIR: "两张同点",
	PokerRules.Category.HIGH_CARD: "什么都不成,比单张",
}


static func sections() -> Array[Dictionary]:
	return [_play(), _hand(), _hands(), _betting(), _pots(), _session(), _controls()]


static func hands_block() -> Dictionary:
	# 牌型表:按长牌从大到小 9 行,每行带长牌、短牌的名次(1 最大);两种牌堆名次不同的行高亮
	var order := PokerRules.category_order(false)
	var items := []
	for i in range(order.size() - 1, -1, -1):
		var category: int = order[i]
		var long_place := _place(category, false)
		var short_place := _place(category, true)
		items.append({
			"category": category,
			"name": PokerRules.CATEGORY_NAMES[category],
			"caption": HAND_CAPTIONS[category],
			"cards": _example_cards(category),
			"long": long_place,
			"short": short_place,
			"highlight": long_place != short_place,
		})
	var note := "A 可以当最小的牌接顺子:长牌最小的顺子是 %s,短牌是 %s,同花顺也一样。A 高的同花顺叫%s。" % [
		_lowest_straight(false), _lowest_straight(true), PokerRules.ROYAL_FLUSH_NAME]
	return {"type": "hands", "items": items, "note": note}


# —— 章节 ——

static func _play() -> Dictionary:
	return {
		"id": "play",
		"title": "怎么玩",
		"tagline": "无限注现金局",
		"blocks": [
			{"type": "lead", "text": "每人两张只有自己看得见的底牌,桌心五张公共牌大家共用。凑出最大的五张牌,或者下注把别人都逼得弃牌,就能赢走底池。"},
			{"type": "text", "text": "%d–%d 人围坐一桌,入座领 %d 筹码;盲注 %d/%d,整场不升。下注没有上限,最多可以押上面前的全部筹码。"
				% [PokerRules.MIN_PLAYERS, PokerRules.MAX_SEATS, PokerRules.STARTING_STACK,
					PokerRules.SMALL_BLIND, PokerRules.BIG_BLIND]},
			{"type": "pair", "items": [
				{"title": "长牌", "tone": "brass",
					"body": "整副 %d 张,%s 四种花色都有。" % [PokerRules.deck_size(false), _rank_span(PokerCard.RANK_MIN)]},
				{"title": "短牌", "tone": "brass",
					"body": "去掉 %s–%s,只用 %d 张 %s。同花大于葫芦,其余牌型的大小与长牌相同。" % [
						PokerCard.rank_label(PokerCard.RANK_MIN), PokerCard.rank_label(PokerRules.SHORT_DECK_MIN_RANK - 1),
						PokerRules.deck_size(true), _rank_span(PokerRules.SHORT_DECK_MIN_RANK)]},
			]},
			{"type": "bullets", "items": [
				"现金局,没有淘汰:筹码输光可以再领 %d,次数不限;也可以留在桌边观战。" % PokerRules.STARTING_STACK,
				"开打后新玩家照样能入座:先旁观正在打的这一手,下一手开始发牌。",
				"房主随时可以「散局」:打完这一手就结算,按「筹码 − 领取总额」排出输赢。",
			]},
			{"type": "note", "text": "玩法在开房时选定,开房后不能改;想换玩法就重新开一桌。"},
		],
	}


static func _hand() -> Dictionary:
	return {
		"id": "hand",
		"title": "一手牌",
		"tagline": "从发牌到摊牌",
		"blocks": [
			{"type": "lead", "text": "每一手最多四轮下注,公共牌一轮一轮亮出来:"},
			{"type": "bullets", "items": [
				"发牌:按钮(D)每手顺时针挪一位,它的下一位下小盲 %d,再下一位下大盲 %d;然后每人发 %d 张底牌。"
					% [PokerRules.SMALL_BLIND, PokerRules.BIG_BLIND, PokerRules.HOLE_CARDS],
				"翻牌前:从大盲的下一位开始,顺时针轮流行动。",
				"翻牌亮出 %d 张公共牌,转牌、河牌各再亮 1 张;这三轮都从按钮的下一位开始行动。" % PokerRules.FLOP_CARDS,
				"河牌下完注,还没弃牌的人自动亮牌比大小(摊牌),牌最大的赢走底池。",
				"只剩一个人没弃牌时,他直接赢下底池,不用亮牌。",
			]},
			{"type": "text", "text": "只有两人(单挑)时按钮下小盲:翻牌前按钮先行动,翻牌后大盲先行动。新入座的人不用补盲,轮到谁下盲就是谁。"},
			{"type": "note", "text": "屏幕左上随时显示公共牌与底池,左下是你的底牌和当前最大的牌型。"},
		],
	}


static func _hands() -> Dictionary:
	return {
		"id": "hands",
		"title": "牌型",
		"tagline": "从大到小 · 短牌只换一处",
		"blocks": [
			hands_block(),
			{"type": "bullets", "items": [
				"七选五:%d 张底牌加 %d 张公共牌,取最大的五张;可以一张底牌都不用。"
					% [PokerRules.HOLE_CARDS, PokerRules.BOARD_CARDS],
				"牌型相同时,先比成牌部分的点数(如对子的大小),再依次比剩下的单张;五张点数完全一样就平分。花色不分大小。",
			]},
			{"type": "note", "text": "短牌只有一处不同:同花大于葫芦(%d 张牌里同花更难凑)。顺子仍然大于三条,和长牌一样。"
				% PokerRules.deck_size(true)},
		],
	}


static func _betting() -> Dictionary:
	var raise_to := PokerRules.BIG_BLIND * RAISE_EXAMPLE_BLINDS
	var increment := raise_to - PokerRules.BIG_BLIND
	return {
		"id": "betting",
		"title": "下注",
		"tagline": "无限注,上不封顶",
		"blocks": [
			{"type": "lead", "text": "轮到你时,按局面选一种动作:"},
			{"type": "bullets", "items": [
				"「弃牌」放弃这一手,已经下的注留在底池里。",
				"「过牌」本轮没人下注(或你已经跟平)时,不加钱,把行动交给下一位。",
				"「跟注」补到当前最高的下注;筹码不够就全下跟注。",
				"「下注 / 加注」至少加一个最小加注额,上不封顶。",
				"「全下」把面前的筹码全部推进去。",
			]},
			{"type": "text", "text": "最小加注额:每轮开始时等于大盲 %d,之后等于本轮上一次完整加注加了多少。例:翻牌前有人加注到 %d(比大盲多 %d),下一位要加注就至少加到 %d。"
				% [PokerRules.BIG_BLIND, raise_to, increment, raise_to + increment]},
			{"type": "bullets", "items": [
				"不完整加注:全下的金额凑不够一个最小加注额,不算完整加注,不会重新开放加注:已经行动过的人只能跟注或弃牌。几次不完整加注累计够一个最小加注额,才重新开放。",
				"其他人都已全下时,你只能跟注或弃牌:再加注也没有人能跟。",
				"每次行动限时 %d 秒,超时自动过牌;不能过牌就弃牌。" % int(Protocol.TURN_TIMEOUT),
			]},
			{"type": "note", "text": "下注控件上的预设(快捷键 1–5)一键选好金额:最小、½ 池、¾ 池、1 池、全下。"},
		],
	}


static func _pots() -> Dictionary:
	var bet: int = PokerRules.BIG_BLIND * REFUND_EXAMPLE_BLINDS[0]
	var called: int = PokerRules.BIG_BLIND * REFUND_EXAMPLE_BLINDS[1]
	return {
		"id": "pots",
		"title": "底池",
		"tagline": "边池、退回与平分",
		"blocks": [
			{"type": "lead", "text": "有人全下、其他人还在加注时,底池会分层:"},
			{"type": "bullets", "items": [
				"主池:每人按全下者的额度投入的那部分,所有没弃牌的人都有份。",
				"边池:超出的部分另成一池,只有投够这一层的人能赢;全下的人赢不到他没跟上的那几层。",
				"弃牌的人投进去的筹码留在池里,但他不能再赢;没全下就离开牌桌的人算弃牌。",
			]},
			{"type": "text", "text": "没人跟到的那部分会退回:比如你下注 %d,对手全下只跟了 %d,多出的 %d 在这一轮结束时退给你。"
				% [bet, called, bet - called]},
			{"type": "text", "text": "摊牌时从最后一个边池到主池依次分配,每个池由有资格的人里牌最大的赢。平局就平分,按 %d 为单位分,分不开的零头从按钮之后的第一位赢家起,依次每人多拿 %d。"
				% [PokerRules.CHIP_UNIT, PokerRules.CHIP_UNIT]},
			{"type": "note", "text": "全下之后没人还能下注时,所有没弃牌的人先亮牌,再把剩下的公共牌发完。"},
		],
	}


static func _session() -> Dictionary:
	var stack := PokerRules.STARTING_STACK
	return {
		"id": "session",
		"title": "筹码与散局",
		"tagline": "输光、入座、离开、结算",
		"blocks": [
			{"type": "lead", "text": "输光不出局,随时可以回到牌桌。"},
			{"type": "bullets", "items": [
				"一手结束时筹码输光:屏幕下方出现「再领 %d」和「观战」。不选也不会卡住牌局,只是不发牌给你。" % stack,
				"再领:每次 %d,次数不限,下一手开始发牌。观战时也可以随时「领取 %d 上桌」。" % [stack, stack],
				"中途加入的人同样领 %d:先旁观正在打的这一手,下一手入座发牌。" % stack,
				"连续 %d 次超时(中间自己没出过手)就离座:从下一手起不发牌、不下盲注,筹码保留;点屏幕下方的「回到牌桌」,下一手接着发牌。"
					% AWAY_TIMEOUTS,
				"离开牌桌或断线:还在这一手里就自动弃牌;已经全下的照常摊牌,赢了也算。房主离开则整桌解散。",
			]},
			{"type": "text", "text": "房主点「散局」后,正在打的这一手结束就结算:每人的盈亏 = 筹码 − 领取次数 × %d(入座领的那次也算),按盈亏从高到低排名。所有人的盈亏加起来正好是 0。"
				% stack},
			{"type": "note", "text": "结算后房主可以带所有人回等待厅,再开一局。"},
		],
	}


static func _controls() -> Dictionary:
	return {
		"id": "controls",
		"title": "操作",
		"tagline": "鼠标与快捷键",
		"blocks": [
			{"type": "keys", "items": [
				{"action": "弃牌", "mouse": "「弃牌」按钮", "keys": ["F"]},
				{"action": "过牌 / 跟注(默认动作)", "mouse": "「过牌」「跟注」按钮", "keys": ["C", "空格", "Enter"]},
				{"action": "按选好的金额下注 / 加注", "mouse": "「下注」「加注到」按钮", "keys": ["R"]},
				{"action": "金额加减一个大盲", "mouse": "拖动滑条", "keys": ["↑", "↓"]},
				{"action": "选金额预设", "mouse": "预设按钮", "keys": ["1–5"]},
				{"action": "全下", "mouse": "「全下」按钮", "keys": []},
				{"action": "输光时选观战", "mouse": "「观战」按钮", "keys": ["Esc"]},
				{"action": "托管(自动替你出手)", "mouse": "左下「托管」按钮", "keys": []},
				{"action": "散局(仅房主)", "mouse": "「散局」按钮", "keys": []},
				{"action": "转头张望", "mouse": "移动鼠标", "keys": []},
				{"action": "探头 / 缩回(脖子自动伸缩)", "mouse": "", "keys": ["W", "A", "S", "D"]},
				{"action": "切换视角(越肩 / 第一人称)", "mouse": "", "keys": ["V"]},
				RulebookContent.BANTER_KEYS[0],
				RulebookContent.BANTER_KEYS[1],
				RulebookContent.BANTER_KEYS[2],
				{"action": "翻开说明书", "mouse": "「规则」按钮", "keys": [OS.get_keycode_string(RulebookContent.HOTKEY)]},
				{"action": "说明书翻页", "mouse": "左侧目录", "keys": ["←", "→"]},
				{"action": "离开牌桌 / 合上", "mouse": "", "keys": ["Esc"]},
			]},
			{"type": "note", "text": "能免费过牌时按 F 不会弃牌,只提示「可以免费过牌」,点「弃牌」按钮也要再确认一次。看说明书时牌局不会暂停,计时照常进行。"},
			{"type": "note", "text": RulebookContent.BANTER_NOTE},
			{"type": "note", "text": RulebookContent.SPECIES_NOTE},
		],
	}


# —— 牌型表的数据 ——

static func _place(category: int, short_deck: bool) -> int:
	# 名次:1 最大
	return PokerRules.category_order(short_deck).size() - PokerRules.strength(category, short_deck)


static func _example_cards(category: int) -> Array:
	# 每种牌型一手示例,按展示顺序(成组的在前,踢脚从大到小,顺子从大到小)。
	# 只用 6–A:短牌里也有这些牌,长短牌下都是同一种牌型
	var s := PokerCard.SPADES
	var h := PokerCard.HEARTS
	var d := PokerCard.DIAMONDS
	var c := PokerCard.CLUBS
	var j := PokerCard.JACK
	var q := PokerCard.QUEEN
	var k := PokerCard.KING
	var a := PokerCard.ACE
	var hands := {
		PokerRules.Category.STRAIGHT_FLUSH: [[j, d], [10, d], [9, d], [8, d], [7, d]],
		PokerRules.Category.FOUR_OF_A_KIND: [[q, s], [q, h], [q, d], [q, c], [9, s]],
		PokerRules.Category.FULL_HOUSE: [[k, h], [k, c], [k, s], [7, d], [7, h]],
		PokerRules.Category.FLUSH: [[a, c], [j, c], [9, c], [8, c], [6, c]],
		PokerRules.Category.STRAIGHT: [[q, h], [j, s], [10, d], [9, c], [8, h]],
		PokerRules.Category.THREE_OF_A_KIND: [[9, s], [9, d], [9, c], [a, h], [7, s]],
		PokerRules.Category.TWO_PAIR: [[a, s], [a, d], [8, h], [8, c], [k, c]],
		PokerRules.Category.ONE_PAIR: [[j, h], [j, c], [a, d], [9, s], [7, h]],
		PokerRules.Category.HIGH_CARD: [[a, h], [q, c], [10, s], [8, d], [7, c]],
	}
	return hands[category].map(func(pair: Array) -> int: return PokerCard.make(pair[0], pair[1]))


static func _lowest_straight(short_deck: bool) -> String:
	# A 当最小牌的顺子:A 接这副牌最小的四个点数,如 A-2-3-4-5
	var low := PokerRules.min_rank(short_deck)
	var labels := [PokerCard.rank_label(PokerCard.ACE)]
	for r in range(low, low + HAND_SIZE - 1):
		labels.append(PokerCard.rank_label(r))
	return "-".join(labels)


static func _rank_span(low: int) -> String:
	# 点数范围,如「6–A」
	return "%s–%s" % [PokerCard.rank_label(low), PokerCard.rank_label(PokerCard.ACE)]
