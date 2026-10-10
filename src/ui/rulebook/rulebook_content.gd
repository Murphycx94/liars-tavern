class_name RulebookContent
# 说明书内容:分五本书(骗子酒馆 / 炸弹猫 / 吹牛骰子 / 斗地主 / 德州扑克),每本按章节组织成纯数据,由 Rulebook 渲染。
# 本文件是骗子酒馆那本;德州那本在 RulebookPoker(长牌、短牌共用一本),炸弹猫那本在 RulebookBombCat,吹牛骰子那本在 RulebookLiarsDice,斗地主那本在 RulebookDouDizhu。
# 文案中的数字全部取自规则常量(牌堆、手牌、出牌张数、左轮、限时),规则改动时说明书自动跟随。
# 块类型:lead 引言 / text 正文 / bullets 要点 / note 提示条 / cards 牌堆 / pair 二选一对照 /
#        odds 左轮中弹概率 / keys 操作键位 / hands 德州牌型表 / bomb_cards 炸弹猫的牌(小牌面 + 名字 + 张数 + 说明) /
#        dice 吹牛骰子的开盅示例(每行一个名字 + 一排 2D 骰子,等于 face 或 1 点的金边高亮) /
#        ddz_combos 斗地主牌型表(牌型名 + 说明 + 示例小牌) / ddz_order 斗地主大小顺序(一排小牌)。pair 的 tone 取 brass / truth / lie。


const BLOCK_TYPES := ["lead", "text", "bullets", "note", "cards", "pair", "odds", "keys", "hands", "bomb_cards", "dice", "ddz_combos",
	"ddz_order"]
# 两本书的「操作」章都有这条:自选形象(子项目② §3.7)
const SPECIES_NOTE := "主菜单名号旁的头像处挑选你的动物形象;同桌不撞脸,先选先得,被占时房主给你一个空着的;等待厅里点自己的头像还能换。"
# 三本书的「操作」章都有这几条:丢番茄与快捷语(等待厅和牌局里都能用,出局、观战也行)、九宫格快捷对话(牌局里)
const BANTER_KEYS := [
	{"action": "朝光标所指的人丢番茄", "mouse": "右键", "keys": ["G"]},
	{"action": "快捷语(按数字说出)", "mouse": "「Q」圆牌", "keys": ["Q", "1–8"]},
	{"action": "九宫格快捷对话(按数字选)", "mouse": "「对话」按钮", "keys": ["T", "1–9"]},
]
const BANTER_NOTE := "丢番茄(每人 3 秒一个)和快捷语纯属逗乐,不影响胜负和计时;你的动物会用自己的叫声把话念出来,头顶冒出气泡。快捷语面板和九宫格快捷对话一次只开一个,开着时数字键只用来说话。"
# 翻开说明书的快捷键。放在纯数据模块里,HUD 等引用它时不会把 Rulebook 依赖的自动加载单例拖进来
const HOTKEY := KEY_F1

const BOOK_LIARS := "liars"
const BOOK_POKER := "poker"
const BOOK_BOMB_CAT := "bomb_cat"
const BOOK_LIARS_DICE := "liars_dice"
const BOOK_DOU_DIZHU := "dou_dizhu"
const BOOKS := [BOOK_LIARS, BOOK_BOMB_CAT, BOOK_LIARS_DICE, BOOK_DOU_DIZHU, BOOK_POKER]   # 页签顺序(同主菜单的玩法顺序)
const BOOK_TITLES := {BOOK_LIARS: "骗子酒馆", BOOK_POKER: "德州扑克", BOOK_BOMB_CAT: "炸弹猫", BOOK_LIARS_DICE: "吹牛骰子",
	BOOK_DOU_DIZHU: "斗地主"}


static func sections(book := BOOK_LIARS) -> Array[Dictionary]:
	if book == BOOK_POKER:
		return RulebookPoker.sections()
	if book == BOOK_BOMB_CAT:
		return RulebookBombCat.sections()
	if book == BOOK_DOU_DIZHU:
		return RulebookDouDizhu.sections()
	if book == BOOK_LIARS_DICE:
		return RulebookLiarsDice.sections()
	return [_goal(), _deck(), _turn(), _reveal(), _revolver(), _rounds(), _controls()]


static func find(section_id: String, book := BOOK_LIARS) -> Dictionary:
	for section in sections(book):
		if section["id"] == section_id:
			return section
	return {}


static func book_title(book: String) -> String:
	return BOOK_TITLES.get(book, BOOK_TITLES[BOOK_LIARS])


static func book_for_mode(mode: String) -> String:
	# 德州长牌与短牌共用一本(牌型表里并列两种名次);炸弹猫、吹牛骰子各一本;未知玩法回退骗子酒馆那本
	if GameMode.is_bomb_cat(mode):
		return BOOK_BOMB_CAT
	if GameMode.is_dou_dizhu(mode):
		return BOOK_DOU_DIZHU
	if GameMode.is_liars_dice(mode):
		return BOOK_LIARS_DICE
	return BOOK_POKER if GameMode.is_poker(mode) else BOOK_LIARS


static func hit_chance(shots_fired: int) -> float:
	# 已空响 shots_fired 次后,下一枪中弹的概率
	return 1.0 / maxi(Revolver.CHAMBERS - shots_fired, 1)


# —— 章节 ——

static func _goal() -> Dictionary:
	return {
		"id": "goal",
		"title": "怎么赢",
		"tagline": "活到最后的人赢",
		"blocks": [
			{"type": "lead", "text": "轮流把牌盖着打出,声称它们全是本局的目标牌——可以说真话,也可以吹牛。"},
			# 人数取骗子酒馆自己的上限:Protocol.MAX_PLAYERS 是所有玩法的绝对上限
			{"type": "text", "text": "%d–%d 人围坐一桌。下家不信你,就翻牌验证:你说谎被抓,你对自己扣一次左轮扳机;冤枉了你,扣扳机的就是他。"
				% [GameMode.min_players(GameMode.LIARS), GameMode.max_players(GameMode.LIARS)]},
			{"type": "bullets", "items": [
				"中弹即出局,最后一个活着的人获胜。",
				"每次开枪后重新洗牌发牌,开始新的一局。",
				"左轮整场只装一发子弹:扣得越多,下一枪越危险。",
			]},
		],
	}


static func _deck() -> Dictionary:
	var items := []
	for kind in Deck.COMPOSITION:
		items.append({
			"kind": kind,
			"count": Deck.COMPOSITION[kind],
			"caption": "万能牌" if kind == Card.JOKER else "",
		})
	return {
		"id": "deck",
		"title": "牌堆",
		"tagline": "%d 张牌,一个目标" % Deck.build().size(),
		"blocks": [
			{"type": "cards", "items": items},
			{"type": "text", "text": "牌堆共 %d 张。每局开始时洗牌,给每位存活玩家发 %d 张。"
				% [Deck.build().size(), Deck.HAND_SIZE]},
			{"type": "bullets", "items": [
				"每局从 %s 中随机抽一种作为目标牌,立在桌心,也显示在屏幕左上角。" % _target_names(),
				"鬼牌是万能牌:翻牌验证时视同任何目标牌。",
			]},
			{"type": "note", "text": "手牌只有你自己看得见,别人只知道你还剩几张。"},
		],
	}


static func _turn() -> Dictionary:
	return {
		"id": "turn",
		"title": "轮到你时",
		"tagline": "出牌,或者质疑",
		"blocks": [
			{"type": "lead", "text": "轮到你时,二选一:"},
			{"type": "pair", "items": [
				{"title": "出牌", "tone": "brass",
					"body": "选 %d–%d 张手牌盖着打出,等于宣称「这些全是目标牌」。牌可以是真的,也可以是假的。"
						% [Rules.MIN_PLAY, Rules.MAX_PLAY]},
				{"title": "质疑!", "tone": "lie",
					"body": "只能翻上家刚打出的那一组,不信就当场验证。每局的第一手没有牌可质疑,只能出牌。"},
			]},
			{"type": "bullets", "items": [
				"出牌后轮到下一位还有手牌的玩家;手牌打光的人本局不再行动。",
				"每回合限时 %d 秒,超时会自动替你打出第一张手牌。" % int(Protocol.TURN_TIMEOUT),
			]},
			{"type": "note", "text": "不是你的回合时也可以先点选手牌,轮到你时直接出牌。"},
		],
	}


static func _reveal() -> Dictionary:
	return {
		"id": "reveal",
		"title": "翻牌验证",
		"tagline": "谁说谎,谁扣扳机",
		"blocks": [
			{"type": "lead", "text": "质疑时当众翻开上家那组牌:"},
			{"type": "pair", "items": [
				{"title": "真话", "tone": "truth",
					"body": "翻开的牌全是目标牌或鬼牌。", "result": "质疑者扣扳机"},
				{"title": "假话", "tone": "lie",
					"body": "只要有一张不是目标牌。", "result": "出牌者扣扳机"},
			]},
			{"type": "note", "text": "鬼牌也算目标牌:一组牌里混着鬼牌,甚至全是鬼牌,都是真话。"},
		],
	}


static func _revolver() -> Dictionary:
	var odds := []
	for fired in Revolver.CHAMBERS:
		odds.append({"shot": fired + 1, "chance": hit_chance(fired)})
	return {
		"id": "revolver",
		"title": "左轮",
		"tagline": "越往后越危险",
		"blocks": [
			{"type": "text", "text": "每人面前一把 %d 膛左轮,整场只装一发子弹,膛位随机。每次空响,弹巢就转到下一格;子弹不会重装,扣过的次数会一直带到终局:"
				% Revolver.CHAMBERS},
			{"type": "odds", "items": odds},
			{"type": "bullets", "items": ["中弹即出局;空响则活下来,继续游戏。"]},
			{"type": "note", "text": "屏幕左下角是你的弹巢:暗掉的圆点是已经空响过的膛位。"},
		],
	}


static func _rounds() -> Dictionary:
	return {
		"id": "rounds",
		"title": "新一局与特殊情况",
		"tagline": "开枪之后",
		"blocks": [
			{"type": "lead", "text": "每次翻牌之后,不论有没有人中弹,都会收走所有牌、抽新的目标牌,开始新的一局。"},
			{"type": "bullets", "items": [
				"新一局由刚才扣扳机的人先出牌;他若中弹出局,由他的下家先出。",
				"只剩一个人还有手牌时,他打出的牌会被系统强制翻开验证:说谎由他扣扳机;说真话则无人开枪,直接开新一局。",
				"中途离开牌桌或断线视为出局;房主离开则整桌解散。",
				"出局后可以留在桌边观战到终局。",
			]},
			{"type": "note", "text": "对局结束后,房主可以带所有人回等待厅,再来一局。"},
		],
	}


static func _controls() -> Dictionary:
	return {
		"id": "controls",
		"title": "操作",
		"tagline": "鼠标与快捷键",
		"blocks": [
			{"type": "keys", "items": [
				{"action": "选牌(最多 %d 张)" % Rules.MAX_PLAY, "mouse": "点击手牌",
					"keys": ["1–%d" % Deck.HAND_SIZE]},
				{"action": "出牌", "mouse": "「出牌」按钮", "keys": ["Enter"]},
				{"action": "质疑上家", "mouse": "「质疑!」按钮", "keys": ["C", "空格"]},
				{"action": "转头张望", "mouse": "移动鼠标", "keys": []},
				{"action": "探头 / 缩回(脖子自动伸缩)", "mouse": "", "keys": ["W", "A", "S", "D"]},
				{"action": "切换视角(越肩 / 第一人称)", "mouse": "", "keys": ["V"]},
				BANTER_KEYS[0],
				BANTER_KEYS[1],
				BANTER_KEYS[2],
				{"action": "翻开说明书", "mouse": "「规则」按钮", "keys": [OS.get_keycode_string(HOTKEY)]},
				{"action": "说明书翻页", "mouse": "左侧目录", "keys": ["←", "→"]},
				{"action": "离开 / 合上", "mouse": "", "keys": ["Esc"]},
			]},
			{"type": "note", "text": "看说明书时对局不会暂停,回合计时照常进行;轮到你时屏幕上方会有提示。"},
			{"type": "note", "text": BANTER_NOTE},
			{"type": "note", "text": SPECIES_NOTE},
		],
	}


static func _target_names() -> String:
	return " / ".join(Deck.TARGETS.map(func(kind): return Card.NAMES[kind]))
