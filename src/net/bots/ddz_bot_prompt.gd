class_name DdzBotPrompt
# 接了 AI 的斗地主机器人:把局面写成提示词,把 AI 的回答解析成合法动作。纯函数,可以单测。
# AI 只看到这个机器人能看到的东西(自己的手牌、底牌、各家剩几张、本手出过的牌),和真人玩家一样;
# 「外面还有的牌」是从这些公开信息算出来的(记牌),不偷看别人的手牌。
# 牌用点数写(3 … 10 J Q K A 2 小王 大王),斗地主不看花色:AI 说出点数,这里从手牌里挑对应的牌。
# AI 的回答是不可信输入:手里没有的牌、不成牌型、压不过、该出牌时说不出都判无效(机器人改用内置策略)。


const MAX_LOG_LINES := 60
const MAX_OPTIONS := 40
const ERROR_SNIPPET := 40      # 报错里摘录 AI 回答的长度
const ROLE_NAMES := {DdzState.ROLE_LANDLORD: "地主", DdzState.ROLE_FARMER: "农民"}
# 回答里点数的别名(先去掉花色符号、转大写再查)
const RANK_ALIASES := {
	"3": 0, "4": 1, "5": 2, "6": 3, "7": 4, "8": 5, "9": 6, "10": 7, "T": 7, "J": 8, "Q": 9, "K": 10, "A": 11,
	"2": 12, "小王": 13, "小鬼": 13, "SJ": 13, "大王": 14, "大鬼": 14, "BJ": 14,
}
const MULTI_CHAR_TOKENS := ["小王", "小鬼", "大王", "大鬼", "10", "SJ", "BJ"]
const SUIT_CHARS := "♠♥♦♣♤♡♢♧"


static func system_prompt(bot_name: String, persona: String) -> String:
	return "\n".join([
		"你在一个叫「骗子酒馆」的游戏里扮演斗地主玩家「%s」,和真人玩家对战(三人、叫分制、连续打很多手、分数累计)。" % bot_name,
		"你的性格:%s" % persona,
		"规则:每人 17 张,留 3 张底牌;叫分 1–3 分,只能比前面叫得高,叫 3 分或一圈后最高的当地主,拿走底牌先出。",
		"两个农民是一伙,谁先出完谁那一方赢。出牌要压过上家同牌型同张数的更大牌,或者不出;连续两家不出由最后出牌的人重新自由出牌。",
		"牌型:单张、对子、三张、三带一、三带一对、顺子(≥5 张连续,到 A 为止)、连对(≥3 对)、飞机(≥2 组连续三张,可带同组数的单张或对子)、"
			+ "四带二、四带两对、炸弹(四张同点)、王炸(大小王)。点数 3<4<…<10<J<Q<K<A<2<小王<大王;2 和王不能进顺子、连对、飞机。",
		"炸弹压一切非炸弹,王炸最大;每个炸弹 / 王炸让本手倍数翻倍。",
		"每次轮到你时,你会收到当前局面。请认真思考后做出决定,目标是长期赢更多分。",
		"只回答一个 JSON 对象,不要别的文字。格式:",
		'叫分阶段:{"action": "bid", "score": 0 到 3(0 = 不叫), "quip": 快捷对话编号或 null}',
		'出牌阶段:{"action": "play", "cards": ["3", "3", "3", "J"], "quip": …} 或 {"action": "pass", "quip": …}(不出)',
		"cards 只写点数(3 4 5 6 7 8 9 10 J Q K A 2 小王 大王),不写花色,必须是你手里有的牌;自由出牌时不能 pass。",
		"quip 可选:想在牌桌上说句话时填快捷对话编号(只在有感而发时说,大多数时候填 null)。",
	])


static func user_prompt(sit: Dictionary, pub: Dictionary, names: Dictionary, log_lines: Array, played: Array) -> String:
	var me: int = sit["me"]
	var lines := [
		"第 %d 手,%s。底分 %d,当前倍数 %d。" % [int(pub.get("hand", 0)),
			"叫分阶段" if sit["stage"] == DdzBotBrain.STAGE_BID else "出牌阶段",
			int(pub.get("base", 0)), int(pub.get("multiplier", 1))],
		"你的身份:%s" % _role_text(sit, names),
		"你的手牌(%d 张):%s" % [sit["hand"].size(), rank_labels(sit["hand"])],
	]
	var bottom: Array = pub.get("bottom", [])
	if not bottom.is_empty():
		lines.append("底牌(已亮出,归地主):%s" % rank_labels(bottom))
	lines.append("")
	lines.append("牌桌(按出牌顺序):")
	for row in pub.get("players", []):
		lines.append("- " + _player_line(row, sit, me))
	if sit["stage"] == DdzBotBrain.STAGE_PLAY:
		lines.append("")
		lines.append("外面还有的牌(别人手里的,由已出的牌和你的手牌算出):%s" % _unseen_text(sit["hand"], played))
	lines.append("")
	lines.append("本手记录:")
	var shown := log_lines.slice(maxi(log_lines.size() - MAX_LOG_LINES, 0))
	lines.append_array(shown if not shown.is_empty() else ["(还没有)"])
	lines.append("")
	lines.append("轮到你了。" + _options(sit, names))
	lines.append("")
	lines.append("快捷对话编号:" + "; ".join(range(Quips.LINES.size()).map(
		func(i: int) -> String: return "%d=%s" % [i, Quips.LINES[i]])))
	return "\n".join(lines)


static func _role_text(sit: Dictionary, names: Dictionary) -> String:
	var landlord: Variant = sit["landlord"]
	if landlord == null:
		return "还没定地主"
	if landlord == sit["me"]:
		return "地主(两个农民一伙对付你)"
	return "农民(地主是 %s,队友是 %s)" % [names.get(landlord, "?"), names.get(sit["teammate"], "?")]


static func _player_line(row: Dictionary, sit: Dictionary, me: int) -> String:
	var pid: Variant = row.get("pid")
	var tags := []
	if pid == me:
		tags.append("你")
	elif pid == sit["next"]:
		tags.append("你的下家")
	else:
		tags.append("你的上家")
	var text := "%s:%s剩 %d 张" % [row.get("name", "?"),
		(ROLE_NAMES[row["role"]] + ",") if ROLE_NAMES.has(row.get("role", "")) else "", int(row.get("hand_count", 0))]
	var table: Array = row.get("table", [])
	if not table.is_empty():
		text += ",本圈出了 %s" % rank_labels(table)
	elif row.get("passed", false):
		text += ",本圈不出"
	return text + "(%s)" % "、".join(tags)


static func _options(sit: Dictionary, names: Dictionary) -> String:
	if sit["stage"] == DdzBotBrain.STAGE_BID:
		var options: Array = sit["bid_options"]
		return "可叫:" + "、".join(options.map(func(s: int) -> String: return "不叫(0)" if s == 0 else "%d 分" % s))
	var legal: Array = sit["legal"]
	var head := ""
	if sit["lead_combo"].is_empty():
		head = "你是自由出牌(必须出,任意合法牌型都行)。"
	else:
		var lead: Dictionary = sit["lead"]
		head = "要压的牌:%s 出的%s %s。压不过或不想压就 pass。" % [names.get(lead.get("pid"), "?"),
			DdzHand.type_name(lead.get("type", "")), rank_labels(lead.get("cards", []))]
	if legal.is_empty():
		return head + "你没有压得过的牌,只能 pass。"
	var shown := legal.slice(0, MAX_OPTIONS).map(func(p: Dictionary) -> String:
		return "%s %s" % [DdzHand.type_name(p["type"]), rank_labels(p["cards"])])
	var tail := "(只列出一部分,其他合法出法也可以)" if legal.size() > MAX_OPTIONS else ""
	return head + "\n可以出的例子%s:%s" % [tail, ";".join(shown)]


static func _unseen_text(hand: Array, played: Array) -> String:
	var counts := DdzHand.rank_counts(DdzHand.full_deck())
	for card in hand + played:
		counts[DdzHand.rank(card)] -= 1
	var parts := []
	for r in range(DdzHand.RANK_COUNT - 1, -1, -1):
		if counts[r] > 0:
			parts.append(DdzHand.RANK_LABELS[r] + ("×%d" % counts[r] if counts[r] > 1 else ""))
	return " ".join(parts) if not parts.is_empty() else "(没有了)"


static func rank_labels(cards: Array) -> String:
	return " ".join(DdzHand.sorted(cards).map(func(c: int) -> String: return DdzHand.RANK_LABELS[DdzHand.rank(c)]))


static func describe_event(ev: Dictionary, names: Dictionary) -> String:
	# 本手记录的一行;不需要记的事件返回 ""
	var who: String = names.get(ev.get("pid"), "?")
	match ev.get("type", ""):
		"bid":
			return who + (" 不叫" if int(ev.get("score", 0)) == 0 else " 叫 %d 分" % int(ev.get("score", 0)))
		"redeal":
			return "三家都不叫,重新发牌"
		"landlord":
			return "%s 当地主(底分 %d),底牌 %s" % [who, int(ev.get("base", 0)), rank_labels(ev.get("bottom", []))]
		"played":
			var text := "%s 出 %s %s(剩 %d 张)" % [who, DdzHand.type_name(ev.get("combo", "")),
				rank_labels(ev.get("cards", [])), int(ev.get("remaining", 0))]
			if ev.get("combo", "") == DdzHand.BOMB or ev.get("combo", "") == DdzHand.ROCKET:
				text += ",倍数变成 %d" % int(ev.get("multiplier", 1))
			return text
		"passed":
			return who + " 不出"
		"trick_cleared":
			return "—— 两家不出,%s 重新自由出牌 ——" % who
	return ""


# —— 解析回答 ——

static func parse(text: String, sit: Dictionary) -> Dictionary:
	# → {"ok": true, "choice": DdzBotBrain 的出手字典, "quip": 编号或 -1} 或 {"ok": false, "error"}
	var data: Variant = AiChat.answer_object(text)
	if data == null:
		return _bad("回答里没有 JSON")
	if not data is Dictionary:
		return _bad("JSON 不是对象")
	var action: Variant = data.get("action")
	if not action is String:
		return _bad("缺少 action")
	var choice := {}
	var error := ""
	var kind := (action as String).strip_edges().to_lower()
	if sit["stage"] == DdzBotBrain.STAGE_BID:
		var result := _bid_choice(kind, data.get("score"), sit["bid_options"])
		choice = result[0]
		error = result[1]
	elif sit["stage"] == DdzBotBrain.STAGE_PLAY:
		var result := _play_choice(kind, data.get("cards"), sit)
		choice = result[0]
		error = result[1]
	else:
		error = "还没轮到它"
	if choice.is_empty():
		return _bad(error)
	var quip: Variant = data.get("quip")
	if quip is float and quip == floorf(quip):
		quip = int(quip)
	return {"ok": true, "choice": choice, "quip": quip if Quips.is_valid(quip) else -1}


static func _bid_choice(kind: String, score: Variant, options: Array) -> Array:
	# 叫分时说 pass / 不叫 都当 0 分;叫的分不在可选范围里(没比前面高)判无效
	if kind == "pass" or kind == "不叫":
		return [DdzBotBrain.bid(0), ""]
	if kind != "bid":
		return [{}, "叫分阶段只能 bid"]
	if score is float and score == floorf(score):
		score = int(score)
	if not score is int or not options.has(score):
		return [{}, "叫分不合法:%s" % str(score).substr(0, ERROR_SNIPPET)]
	return [DdzBotBrain.bid(score), ""]


static func _play_choice(kind: String, raw: Variant, sit: Dictionary) -> Array:
	match kind:
		"pass", "不出":
			if not sit["can_pass"]:
				return [{}, "自由出牌不能不出"]
			return [DdzBotBrain.pass_turn(), ""]
		"play":
			var cards := pick_cards(sit["hand"], raw)
			if cards.is_empty():
				return [{}, "手里没有这些牌:%s" % str(raw).substr(0, ERROR_SNIPPET)]
			var lead: Dictionary = sit["lead_combo"]
			var c := DdzHand.classify(cards) if lead.is_empty() else DdzHand.match_lead(cards, lead)
			if c.is_empty():
				return [{}, ("不成牌型:%s" if lead.is_empty() else "压不过上家:%s") % rank_labels(cards)]
			return [DdzBotBrain.play(cards), ""]
	return [{}, "动作不合法:%s" % kind.substr(0, ERROR_SNIPPET)]


static func pick_cards(hand: Array, raw: Variant) -> Array:
	# 把 AI 说的点数换成手里的牌(同点数依次取);说不清或手里不够返回 []
	var ranks := parse_ranks(raw)
	if ranks.is_empty():
		return []
	var left := hand.duplicate()
	var out := []
	for r in ranks:
		var found := -1
		for card in left:
			if DdzHand.rank(card) == r:
				found = card
				break
		if found < 0:
			return []
		left.erase(found)
		out.append(found)
	return DdzHand.sorted(out)


static func parse_ranks(raw: Variant) -> Array:
	# ["3", "3", "10", "小王"]、"3 3 10 小王"、"3310" 都行;认不出的记号让整个回答无效(返回 [])
	var tokens := []
	if raw is String:
		tokens = [raw]
	elif raw is Array:
		tokens = raw
	else:
		return []
	var out := []
	for tok in tokens:
		if tok is float and tok == floorf(tok):
			tok = str(int(tok))
		if not tok is String:
			return []
		var ranks := _ranks_in(tok)
		if ranks.is_empty():
			return []
		out.append_array(ranks)
	return out


static func _ranks_in(token: String) -> Array:
	# 一个记号里可能连着写了好几张(如 "3310"、"JJ"):逐个认,先认多字的(10、小王…)
	var s := token.strip_edges().to_upper()
	for ch in SUIT_CHARS:
		s = s.replace(ch, "")
	for sep in [" ", ",", ",", "、", "+"]:
		s = s.replace(sep, "")
	if s == "":
		return []
	if RANK_ALIASES.has(s):
		return [RANK_ALIASES[s]]
	var out := []
	var i := 0
	while i < s.length():
		var matched := ""
		for multi in MULTI_CHAR_TOKENS:
			if s.substr(i, multi.length()) == multi:
				matched = multi
				break
		if matched == "":
			matched = s[i]
		if not RANK_ALIASES.has(matched):
			return []
		out.append(RANK_ALIASES[matched])
		i += matched.length()
	return out


static func _bad(error: String) -> Dictionary:
	return {"ok": false, "error": error}
