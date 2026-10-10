class_name RulebookLiarsDice
# 说明书的吹牛骰子那本:按章节组织的纯数据,由 Rulebook 渲染,块类型见 RulebookContent。
# 骰子数、点数范围、人数取 LiarsDiceState 与 GameMode,秒数取 Protocol.TURN_TIMEOUT,快捷键取牌桌的 key_action 同一套:
# 规则改动时说明书自动跟随。示例里的骰子用 dice 块(2D 骰子面 DiceIcon,算进去的那几颗金边高亮)。文案全部原创。


static func sections() -> Array[Dictionary]:
	return [_goal(), _round(), _bid(), _wild(), _challenge(), _lose(), _controls()]


static func example_reveal() -> Dictionary:
	# 「开!」的示例:三个人掀开骰盅数「5」,1 点也算
	return {"type": "dice", "face": 5, "items": [
		{"label": "阿狸", "dice": [1, 2, 5, 5, 6]},
		{"label": "小熊", "dice": [3, 3, 4, 6]},
		{"label": "你", "dice": [1, 5, 6]},
	]}


# —— 章节 ——

static func _goal() -> Dictionary:
	return {
		"id": "goal",
		"title": "怎么赢",
		"tagline": "骰子留到最后",
		"blocks": [
			{"type": "lead", "text": "每人 %d 颗骰子扣在骰盅里,摇完只有自己看得见。大家轮流往上喊「全场至少有几个几」,不信就「开!」。"
				% LiarsDiceState.DICE_PER_PLAYER},
			{"type": "text", "text": "%d–%d 人围坐一桌。每开一次总有一个人丢一颗骰子;骰子丢光就出局,最后还有骰子的人赢。"
				% [GameMode.min_players(GameMode.LIARS_DICE), GameMode.max_players(GameMode.LIARS_DICE)]},
			{"type": "bullets", "items": [
				"左上角随时显示场上还剩几颗骰子、当前这一口和本轮喊过的价、轮到谁。",
				"别人头顶的铭牌上有他还剩几颗骰子(一排小方块)和他这一轮最后喊的那一口。",
				"自己的 %d 颗骰子显示在屏幕下方;鼠标停在自己的骰盅上也能掀开盅沿偷看一眼。" % LiarsDiceState.DICE_PER_PLAYER,
			]},
			{"type": "note", "text": "一局分出胜负就结算,房主可以带大家回等待厅再来一局。开打后不能中途加入。"},
		],
	}


static func _round() -> Dictionary:
	return {
		"id": "round",
		"title": "一轮怎么走",
		"tagline": "摇、看、喊",
		"blocks": [
			{"type": "lead", "text": "每轮开始,所有人双手捧起骰盅哗啦哗啦摇,啪地扣在桌上,再掀开盅沿偷看自己的点数。"},
			{"type": "bullets", "items": [
				"第一轮由随机挑的人先喊;之后每轮由上一轮输的人先喊(他出局了就由他的下一位)。",
				"轮到你时只有两种选择:加注,或者「开!」。本轮还没人喊时只能先喊一口。",
				"每回合限时 %d 秒。超时会自动替你喊最小的合法加注;加不上去了就自动「开!」。" % int(Protocol.TURN_TIMEOUT),
				"每一轮开始所有人都重新摇,上一轮的点数作废。",
			]},
		],
	}


static func _bid() -> Dictionary:
	return {
		"id": "bid",
		"title": "喊价与加注",
		"tagline": "只能越喊越大",
		"blocks": [
			{"type": "lead", "text": "喊「N 个 X」的意思是:全场所有人的骰子加起来,至少有 N 颗是 X 点(1 点也算在里面)。"},
			{"type": "pair", "items": [
				{"title": "个数更多", "tone": "brass", "body": "上家喊「3 个 5」,你可以喊「4 个 2」「4 个 6」……点数随意。"},
				{"title": "个数相同,点数更大", "tone": "brass", "body": "上家喊「3 个 5」,你也可以喊「3 个 6」;「3 个 4」就不行。"},
			]},
			{"type": "bullets", "items": [
				"点数只能喊 %d–%d:1 点是万能的,不能喊。" % [LiarsDiceState.MIN_BID_FACE, LiarsDiceState.FACES],
				"个数至少 1,而且不能超过场上剩下的骰子总数。",
				"出价器里不合法的个数和点数会变灰,「加注」按钮上写着你要喊的那一口;默认停在最小的合法加注上。",
			]},
		],
	}


static func _wild() -> Dictionary:
	return {
		"id": "wild",
		"title": "1 点万能",
		"tagline": "小星星算什么都行",
		"blocks": [
			{"type": "lead", "text": "骰子上的 1 点画成一颗小星星:开盅数个数时,它算作被喊的那个点数。"},
			example_reveal(),
			{"type": "text", "text": "上面这一盅数「5」:三颗 5 加上两颗 1 点,一共 5 个。喊「5 个 5」及以下都是真话,喊「6 个 5」就是吹牛。"},
			{"type": "note", "text": "所以自己手里的 1 点越多,喊什么都越有底气。"},
		],
	}


static func _challenge() -> Dictionary:
	return {
		"id": "challenge",
		"title": "开!",
		"tagline": "不信就掀盅",
		"blocks": [
			{"type": "lead", "text": "觉得上家在吹牛,就拍桌喊「开!」:所有人一起掀开骰盅,点数等于 X 的骰子和 1 点一颗颗亮起来,桌心的计数器一路数上去。"},
			{"type": "pair", "items": [
				{"title": "真话", "tone": "truth", "body": "实际个数 ≥ 喊的个数(刚好相等也算)。", "result": "开的人丢一颗骰子"},
				{"title": "吹牛", "tone": "lie", "body": "实际个数 < 喊的个数。", "result": "喊的人丢一颗骰子"},
			]},
			{"type": "note", "text": "只能开上家刚喊的那一口;本轮还没人喊时「开!」按钮是灰的。开盅以后大家的点数就公开了。"},
		],
	}


static func _lose() -> Dictionary:
	return {
		"id": "lose",
		"title": "丢骰子与出局",
		"tagline": "啵!",
		"blocks": [
			{"type": "bullets", "items": [
				"输的人的一颗骰子「啵」地弹飞,下一轮少摇一颗。",
				"骰子丢光就出局:骰盅歪倒在桌上,本人转起蚊香眼、留在桌边观战(仍然可以丢番茄、说快捷语)。",
				"只剩一个人还有骰子时他获胜。名次:胜者第一,其余按出局顺序倒排。",
				"中途离开牌桌或断线视为出局,他的骰子移出游戏,这一轮作废、全员重摇;房主离开则整桌解散。",
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
				{"action": "调个数", "mouse": "「−」「+」按钮", "keys": ["↑", "↓"]},
				{"action": "选点数", "mouse": "点数按钮", "keys": ["2–6"]},
				{"action": "加注(喊出价器上的那一口)", "mouse": "「加注」按钮", "keys": ["Enter"]},
				{"action": "开!(质疑上一口)", "mouse": "「开!」按钮", "keys": ["C", "空格"]},
				{"action": "偷看自己的骰子", "mouse": "鼠标停在自己的骰盅上", "keys": []},
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
			{"type": "note", "text": "看说明书时对局不会暂停,计时照常进行。快捷语面板或九宫格开着时数字键只用来说话,不会选点数。第一人称下新一轮偷看时视线会压低凑到盅沿。"},
			{"type": "note", "text": RulebookContent.BANTER_NOTE},
			{"type": "note", "text": RulebookContent.SPECIES_NOTE},
		],
	}
