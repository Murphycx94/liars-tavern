class_name RulebookBlackjack
# 说明书的 21 点那本:按章节组织的纯数据,由 Rulebook 渲染,块类型见 RulebookContent。
# 数字(筹码、下注范围、牌副数、限时、赔率、分牌上限)都取自 BjRules / BlackjackPacing / GameMode,快捷键取 BjControls:
# 规则改动时说明书自动跟随。算点示例用 bj_hands 块(德州牌面的小牌),点数由 BjScore 现算。文案全部原创。


static func sections() -> Array[Dictionary]:
	return [_goal(), _points(), _round(), _actions(), _payout(), _session(), _controls()]


static func example_hands() -> Dictionary:
	var c := func(rank: int, suit: int) -> int: return PokerCard.make(rank, suit)
	var rows := [
		[[c.call(PokerCard.ACE, PokerCard.SPADES), c.call(PokerCard.KING, PokerCard.HEARTS)], "黑杰克", "brass",
			"头两张就是 A + 10 点:直接赢 3 赔 2(庄家也是黑杰克就平手)。"],
		[[c.call(PokerCard.ACE, PokerCard.DIAMONDS), c.call(6, PokerCard.CLUBS)], "软 17", "brass",
			"A 算 11,再要一张也不会爆:爆了 A 自动改成 1。"],
		[[c.call(PokerCard.KING, PokerCard.SPADES), c.call(6, PokerCard.HEARTS), c.call(PokerCard.ACE, PokerCard.CLUBS)],
			"17", "brass", "A 只能算 1 了(算 11 就是 27)。"],
		[[c.call(PokerCard.QUEEN, PokerCard.DIAMONDS), c.call(PokerCard.JACK, PokerCard.CLUBS), c.call(5, PokerCard.SPADES)],
			"爆牌", "lie", "超过 21 点:这一手立刻输掉,不管庄家后面怎样。"],
	]
	var items := []
	for row in rows:
		items.append({"cards": row[0], "total": row[1], "tone": row[2], "caption": row[3]})
	return {"type": "bj_hands", "items": items}


# —— 章节 ——

static func _goal() -> Dictionary:
	return {
		"id": "goal",
		"title": "怎么赢",
		"tagline": "比庄家更接近 21",
		"blocks": [
			{"type": "lead", "text": "每个人各自和酒馆庄家比:点数比庄家大、又不超过 21 点就赢。桌上的人互不相干,你赢你的,他输他的。"},
			{"type": "text", "text": "%d–%d 人一桌,一个人也能玩。庄家由房主的电脑按固定规则代打,坐在桌心的牌架后面。"
				% [GameMode.min_players(GameMode.BLACKJACK), GameMode.max_players(GameMode.BLACKJACK)]},
			{"type": "bullets", "items": [
				"入座领 %s 筹码。筹码不够最小下注时可以再领 %s,结算时扣回去。"
					% [ChipText.format(BjRules.STARTING_STACK), ChipText.format(BjRules.STARTING_STACK)],
				"一局接一局地打,没有终点;房主点「散局」后按盈亏排名结算。",
				"左上是庄家的牌和点数,左下是你自己的每一手和筹码;别人的点数写在他们头顶的铭牌上。",
			]},
		],
	}


static func _points() -> Dictionary:
	return {
		"id": "points",
		"title": "算点",
		"tagline": "A 可大可小",
		"blocks": [
			{"type": "lead", "text": "2–10 按牌面算,J、Q、K 都算 10,A 算 1 或 11(哪个对你有利就算哪个)。花色不管用。"},
			example_hands(),
			{"type": "note", "text": "有一张 A 正算作 11 时叫「软」点数,界面上写成「软 17」。用 %d 副牌洗成一个牌鞋,剩不到 %d 张时整鞋重洗。"
				% [BjRules.DECKS, BjRules.RESHUFFLE_BELOW]},
		],
	}


static func _round() -> Dictionary:
	return {
		"id": "round",
		"title": "一局怎么走",
		"tagline": "下注、发牌、决策、庄家",
		"blocks": [
			{"type": "bullets", "items": [
				"下注:所有人同时下,%s–%s,%d 的倍数;也可以「这局不玩」。限时 %d 秒,到点还没下的人这局不玩。"
					% [ChipText.format(BjRules.MIN_BET), ChipText.format(BjRules.MAX_BET), BjRules.BET_UNIT,
					int(BlackjackPacing.BET_TIMEOUT)],
				"发牌:下了注的人每人两张明牌;庄家一张明牌、一张扣着的暗牌。",
				"庄家明牌是 A 或 10 点时先偷看暗牌:是黑杰克就立刻翻开结算,大家不用再决策。",
				"按座位轮流决策,每一手限时 %d 秒,到点自动停牌。到 21 点自动停。" % int(BlackjackPacing.PLAY_TIMEOUT),
				"所有人打完,庄家翻开暗牌,不到 %d 点就一直要牌,到了 %d 点(含软 %d)就停。" % [BjRules.DEALER_STANDS,
					BjRules.DEALER_STANDS, BjRules.DEALER_STANDS],
				"最后逐手和庄家比大小、赔筹码;停一会儿自动开下一局。",
			]},
			{"type": "note", "text": "庄家没得选:他怎么要牌是写死的。所以庄家明牌小(2–6)时,他爆牌的机会更大。"},
		],
	}


static func _actions() -> Dictionary:
	return {
		"id": "actions",
		"title": "轮到你时",
		"tagline": "要牌、停牌、加倍、分牌、投降",
		"blocks": [
			{"type": "pair", "items": [
				{"title": "要牌", "tone": "brass", "body": "再来一张,可以一直要;超过 21 点就爆牌输掉。"},
				{"title": "停牌", "tone": "brass", "body": "不要了,用现在的点数和庄家比。"},
			]},
			{"type": "bullets", "items": [
				"加倍:只在头两张时能用。再押一份同样多的注,只再发一张(横着放),然后自动停牌。",
				"分牌:头两张点数一样(10、J、Q、K 都算 10)时,再押一份注,拆成两手分别打,每手先补一张。"
					+ "最多分成 %d 手;分出来的手也能加倍。" % BjRules.MAX_HANDS,
				"分 A 例外:两手各只补一张就停,也不能再分;补到 10 点只算 21,不算黑杰克。",
				"投降:只在头两张、还没分牌时能用。收回一半的注,这一手直接认输。",
			]},
			{"type": "note", "text": "筹码不够再押一份时,加倍和分牌按钮是灰的。"},
		],
	}


static func _payout() -> Dictionary:
	return {
		"id": "payout",
		"title": "赔率",
		"tagline": "黑杰克 3 赔 2",
		"blocks": [
			{"type": "pair", "items": [
				{"title": "赢", "tone": "truth", "body": "点数比庄家大,或者庄家爆牌(而你没爆)。", "result": "赔 1 倍,黑杰克赔 1.5 倍"},
				{"title": "输", "tone": "lie", "body": "爆牌,或者点数比庄家小。", "result": "押的注归庄家"},
			]},
			{"type": "bullets", "items": [
				"点数一样是平手,注原样退回。",
				"庄家是黑杰克:你也是黑杰克就平手,其余的手都输(加倍、分牌前就结算了,只输原注)。",
				"本桌不设保险,也没有边注。",
			]},
		],
	}


static func _session() -> Dictionary:
	return {
		"id": "session",
		"title": "现金局",
		"tagline": "来去自由",
		"blocks": [
			{"type": "bullets", "items": [
				"开打后新玩家也能加入:先坐着看,下一局开始时上桌下注。",
				"连续 %d 次超时(下注或决策)就从下一局起离座,点「回到牌桌」回来。" % BjRules.AWAY_AFTER_TIMEOUTS,
				"离开或断线:还没发牌的注退回;已经发了牌的手按停牌照常和庄家比,这一局结束后带着筹码离场。",
				"房主「散局」:还没发牌就立刻结算(押的注退回),打牌中就打完这一局再结算。结算按盈亏排名,第一名跳舞庆祝。",
			]},
		],
	}


static func _controls() -> Dictionary:
	return {
		"id": "controls",
		"title": "操作",
		"tagline": "鼠标与快捷键",
		"blocks": [
			{"type": "keys", "items": [
				{"action": "调下注金额(每次 %d)" % BjRules.BET_UNIT, "mouse": "「−」「+」与预设按钮", "keys": ["↑", "↓", "1–5"]},
				{"action": "下注", "mouse": "「下注」按钮", "keys": ["Enter"]},
				{"action": "按上一局的注再下", "mouse": "「同上局」按钮", "keys": ["R"]},
				{"action": "这局不玩", "mouse": "「这局不玩」按钮", "keys": ["N"]},
				{"action": "要牌", "mouse": "「要牌」按钮", "keys": ["空格", "1"]},
				{"action": "停牌", "mouse": "「停牌」按钮", "keys": ["Enter", "2"]},
				{"action": "加倍 / 分牌 / 投降", "mouse": "对应按钮", "keys": ["3", "4", "5"]},
				{"action": "转头张望", "mouse": "移动鼠标", "keys": []},
				{"action": "探头 / 缩回(脖子自动伸缩)", "mouse": "", "keys": ["W", "A", "S", "D"]},
				{"action": "切换视角(越肩 / 第一人称)", "mouse": "", "keys": ["V"]},
				RulebookContent.BANTER_KEYS[0],
				RulebookContent.BANTER_KEYS[1],
				RulebookContent.BANTER_KEYS[2],
				{"action": "翻开说明书", "mouse": "「规则」按钮", "keys": [OS.get_keycode_string(RulebookContent.HOTKEY)]},
				{"action": "说明书翻页", "mouse": "左侧目录", "keys": ["←", "→"]},
				{"action": "离开牌桌", "mouse": "", "keys": ["Esc"]},
			]},
			{"type": "note", "text": "看说明书时牌局不会暂停,计时照常进行。快捷语面板或九宫格开着时数字键只用来说话。鼠标停在桌上或左上、左下的牌上能看大图。"},
			{"type": "note", "text": RulebookContent.BANTER_NOTE},
			{"type": "note", "text": RulebookContent.SPECIES_NOTE},
		],
	}
