class_name RulebookDouDizhu
# 说明书的斗地主那本:按章节组织的纯数据,由 Rulebook 渲染,块类型见 RulebookContent。
# 牌型名取 DdzHand.TYPE_NAMES,人数、张数、叫分、倍数、计时取 DdzState / DdzHand / DouDizhuSession / DouDizhuPacing / Protocol:
# 规则改动时说明书自动跟随。牌型表(ddz_combos 块)每行一组示例小牌(德州牌面 + 两张原创王),牌值写成斗地主的牌 id。


const T := {"3": 0, "4": 1, "5": 2, "6": 3, "7": 4, "8": 5, "9": 6, "10": 7, "J": 8, "Q": 9, "K": 10, "A": 11, "2": 12}

# 牌型表:[牌型, 一句说明, 示例(按点数写,SJ / BJ 是小王 / 大王)]
const COMBO_ROWS := [
	[DdzHand.SINGLE, "任意一张", "K"],
	[DdzHand.PAIR, "两张同点", "8 8"],
	[DdzHand.TRIPLE, "三张同点", "5 5 5"],
	[DdzHand.TRIPLE_SINGLE, "三张 + 任意一张", "9 9 9 4"],
	[DdzHand.TRIPLE_PAIR, "三张 + 一对", "J J J 6 6"],
	[DdzHand.STRAIGHT, "5 张及以上连续单张,最多到 A", "3 4 5 6 7"],
	[DdzHand.PAIR_STRAIGHT, "3 对及以上连续对子", "6 6 7 7 8 8"],
	[DdzHand.AIRPLANE, "2 组及以上连续三张", "4 4 4 5 5 5"],
	[DdzHand.AIRPLANE_SINGLE, "飞机 + 同样多的单张", "7 7 7 8 8 8 3 K"],
	[DdzHand.AIRPLANE_PAIR, "飞机 + 同样多的对子", "Q Q Q K K K 4 4 9 9"],
	[DdzHand.FOUR_TWO_SINGLE, "四张 + 两张单牌", "10 10 10 10 3 6"],
	[DdzHand.FOUR_TWO_PAIR, "四张 + 两个对子", "6 6 6 6 3 3 9 9"],
	[DdzHand.BOMB, "四张同点,压一切非炸弹", "2 2 2 2"],
	[DdzHand.ROCKET, "大王 + 小王,天下第一", "SJ BJ"],
]


static func sections() -> Array[Dictionary]:
	return [_goal(), _bidding(), _play(), _combos(), _scoring(), _session(), _controls()]


static func cards(text: String) -> Array:
	# "3 3 4 SJ BJ" → 斗地主牌 id(同点数依次用 ♠ ♥ ♦ ♣)
	var used := {}
	var out := []
	for tok in text.split(" ", false):
		if tok == "SJ":
			out.append(DdzHand.SMALL_JOKER)
		elif tok == "BJ":
			out.append(DdzHand.BIG_JOKER)
		else:
			var r: int = T[tok]
			var s: int = used.get(r, 0)
			used[r] = s + 1
			out.append(DdzHand.make(r, s % 4))
	return out


static func combos_block() -> Dictionary:
	var items := []
	for row in COMBO_ROWS:
		items.append({"type": row[0], "name": DdzHand.type_name(row[0]), "caption": row[1], "cards": cards(row[2])})
	return {"type": "ddz_combos", "items": items}


static func order_cards() -> Array:
	# 大小顺序示例:3 4 … K A 2 小王 大王(一种点数一张)
	var out := []
	for r in range(0, DdzHand.RANK_TWO + 1):
		out.append(DdzHand.make(r, r % 4))
	out.append(DdzHand.SMALL_JOKER)
	out.append(DdzHand.BIG_JOKER)
	return out


# —— 章节 ——

static func _goal() -> Dictionary:
	return {
		"id": "goal",
		"title": "怎么玩",
		"tagline": "一个地主,两个农民",
		"blocks": [
			{"type": "lead", "text": "正好 %d 人。先叫分抢地主,地主一个人对付两个农民——谁先把手里的牌出完,谁那一边就赢。"
				% GameMode.min_players(GameMode.DOU_DIZHU)},
			{"type": "text", "text": "一副 %d 张牌(含大王、小王)。每人 %d 张,剩下 %d 张底牌扣在桌心;当上地主的人拿走底牌,手里 %d 张,先出牌。"
				% [DdzHand.CARD_COUNT, DdzState.HAND_SIZE, DdzState.BOTTOM_SIZE, DdzState.HAND_SIZE + DdzState.BOTTOM_SIZE]},
			{"type": "bullets", "items": [
				"地主出完牌,地主赢;两个农民里任何一个出完,农民一起赢。",
				"连续打很多手,分数一直累计;房主随时可以「散局」,按累计分排名。",
				"定了地主之后,地主头上戴一顶小瓜皮帽,农民戴草帽,一眼就分得清。",
			]},
			{"type": "note", "text": "斗地主只能正好 %d 人开局,开打后不能中途加入。" % GameMode.min_players(GameMode.DOU_DIZHU)},
		],
	}


static func _bidding() -> Dictionary:
	return {
		"id": "bidding",
		"title": "叫分",
		"tagline": "1 分、2 分、3 分,或者不叫",
		"blocks": [
			{"type": "lead", "text": "每手先叫分:从随机一人开始,每人轮流叫一次。"},
			{"type": "bullets", "items": [
				"可以叫 1 / 2 / 3 分,或者「不叫」;要叫就得比前面的人叫得高。",
				"有人叫 %d 分立即成为地主;一圈下来叫分最高的人当地主,叫的分就是这一手的底分。" % DdzState.MAX_BID,
				"三人都不叫就重新发牌;连续 %d 次都没人叫,就由第一个叫分的人当 %d 分地主。" % [DdzState.MAX_DEALS, DdzState.FORCED_BASE],
				"定地主时 3 张底牌翻开给所有人看,再飞进地主手里。左上角会一直显示底牌。",
				"叫分限时 %d 秒,超时算不叫。" % int(DouDizhuSession.BID_TIMEOUT),
			]},
			{"type": "note", "text": "牌好(大王小王、2、炸弹多)再叫高分:分越高,赢得越多,输得也越多。"},
		],
	}


static func _play() -> Dictionary:
	return {
		"id": "play",
		"title": "出牌",
		"tagline": "压过上家,或者不出",
		"blocks": [
			{"type": "lead", "text": "地主先出。之后轮流:要么出同样牌型、同样张数、更大的牌压过去,要么「不出」。"},
			{"type": "ddz_order", "cards": order_cards(), "caption": "从小到大:3 < 4 < … < K < A < 2 < 小王 < 大王(花色不分大小)"},
			{"type": "bullets", "items": [
				"炸弹能压任何不是炸弹的牌;炸弹之间比点数;王炸最大。",
				"另外两家都不出时,桌面清掉,最后出牌的人重新随便出。自由出牌时不能不出。",
				"每人出的牌摊在自己面前的桌上,下一圈清掉;「不出」的人面前立一块小牌子。",
				"出牌限时 %d 秒;超时有上家就不出,自己先出就出最小的一张。" % int(Protocol.TURN_TIMEOUT),
				"谁只剩 1–2 张牌,头顶会冒出闪烁的红色报警牌。",
			]},
		],
	}


static func _combos() -> Dictionary:
	return {
		"id": "combos",
		"title": "牌型",
		"tagline": "%d 种牌型" % COMBO_ROWS.size(),
		"blocks": [
			combos_block(),
			{"type": "bullets", "items": [
				"顺子、连对、飞机都不能带 2 和王,最大到 A。",
				"三带一的那张不能和三张同点(那是炸弹);带对子时对子不能是王。",
				"飞机带的单张或对子要和飞机的组数一样多;四带二的两张可以是一对。",
			]},
			{"type": "note", "text": "不知道出什么就按「提示」(H):按从小到大轮流选出能出的组合,炸弹和王炸排在最后。"},
		],
	}


static func _scoring() -> Dictionary:
	var unit := 2 * 4
	return {
		"id": "scoring",
		"title": "计分",
		"tagline": "底分 × 倍数",
		"blocks": [
			{"type": "lead", "text": "每手的一份 = 底分 × 倍数。倍数从 1 开始:"},
			{"type": "bullets", "items": [
				"每打出一个炸弹或王炸,倍数 ×2(左上角的倍数会跳一下)。",
				"春天 ×2:地主出完牌时两个农民一张都没出过;或者农民赢了,而地主只出过第一手。",
			]},
			{"type": "pair", "items": [
				{"title": "地主赢", "tone": "truth", "body": "地主 +%d 份,两个农民各 −1 份。" % DdzState.LANDLORD_SHARE},
				{"title": "农民赢", "tone": "lie", "body": "地主 −%d 份,两个农民各 +1 份。" % DdzState.LANDLORD_SHARE},
			]},
			{"type": "text", "text": "例:叫 2 分当地主,打出过一个炸弹(倍数 ×2)又打成春天(再 ×2),一份 = 2 × 4 = %d 分:地主 +%d,两个农民各 −%d。三人加起来永远是 0。"
				% [unit, unit * DdzState.LANDLORD_SHARE, unit]},
		],
	}


static func _session() -> Dictionary:
	return {
		"id": "session",
		"title": "牌局与托管",
		"tagline": "一手接一手",
		"blocks": [
			{"type": "bullets", "items": [
				"一手打完会亮出三家剩下的牌,右边显示这一手的输赢;停 %d 秒左右自动开下一手。" % int(DouDizhuPacing.HAND_GAP),
				"房主点右上「散局」:打完这一手就按累计分排名结算(同分同名次),第一名在桌边跳舞。",
				"有人离开,牌局立即结算,正在打的这一手作废不计分。",
			]},
			{"type": "pair", "items": [
				{"title": "托管", "tone": "brass", "body": "点左下「托管」,轮到你时由系统很快替你出:叫分不叫,能跟就出最小的能压过的牌,队友的牌不压。"},
				{"title": "自动托管", "tone": "lie", "body": "连续 %d 次超时会自动进入托管;点「取消托管」接回来。托管中也可以自己出牌。"
					% DdzState.TRUSTEE_AFTER_TIMEOUTS},
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
				{"action": "选牌(可以先选好,轮到你再出)", "mouse": "点击手牌 / 按住拖过一串", "keys": []},
				{"action": "出牌", "mouse": "「出牌」按钮", "keys": ["Enter"]},
				{"action": "不出(叫分时:不叫)", "mouse": "「不出」按钮", "keys": ["空格", "P"]},
				{"action": "提示(按一下换一组)", "mouse": "「提示」按钮", "keys": ["H"]},
				{"action": "重选", "mouse": "「重选」按钮 / 右键手牌", "keys": ["R"]},
				{"action": "叫分", "mouse": "「不叫 / 1 分 / 2 分 / 3 分」", "keys": ["0", "1", "2", "3"]},
				{"action": "托管 / 取消托管", "mouse": "左下「托管」按钮", "keys": []},
				{"action": "转头张望", "mouse": "移动鼠标", "keys": []},
				{"action": "探头 / 缩回", "mouse": "", "keys": ["W", "A", "S", "D"]},
				{"action": "切换视角(越肩 / 第一人称)", "mouse": "", "keys": ["V"]},
				RulebookContent.BANTER_KEYS[0],
				RulebookContent.BANTER_KEYS[1],
				RulebookContent.BANTER_KEYS[2],
				{"action": "翻开说明书", "mouse": "「规则」按钮", "keys": [OS.get_keycode_string(RulebookContent.HOTKEY)]},
				{"action": "说明书翻页", "mouse": "左侧目录", "keys": ["←", "→"]},
				{"action": "离开 / 合上", "mouse": "", "keys": ["Esc"]},
			]},
			{"type": "note", "text": "快捷语面板或九宫格快捷对话开着时,数字键和出牌快捷键都先让给它们。看说明书时对局不会暂停。"},
			{"type": "note", "text": RulebookContent.BANTER_NOTE},
			{"type": "note", "text": RulebookContent.SPECIES_NOTE},
		],
	}
