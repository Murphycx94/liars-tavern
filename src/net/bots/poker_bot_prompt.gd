class_name PokerBotPrompt
# 接了 AI 的机器人:把局面写成提示词,把 AI 的回答解析成合法动作。纯函数,可以单测。
# AI 只看到这个机器人能看到的东西(自己的手牌、公共牌、筹码、本手的行动记录),和真人玩家一样。
# AI 的回答是不可信输入:动作不在可选范围里、金额不对时由 parse 夹取或判为无效(无效时机器人改用内置策略)。


const MAX_LOG_LINES := 60
const STREET_NAMES := {
	PokerRules.PREFLOP: "翻牌前", PokerRules.FLOP: "翻牌", PokerRules.TURN: "转牌", PokerRules.RIVER: "河牌",
	PokerRules.SHOWDOWN: "摊牌",
}
const STATUS_NAMES := {
	PokerRules.STATUS_ACTIVE: "在打", PokerRules.STATUS_ALLIN: "已全下", PokerRules.STATUS_FOLDED: "已弃牌",
	PokerRules.STATUS_WAITING: "等下一手", PokerRules.STATUS_BUSTED: "输光", PokerRules.STATUS_SPECTATING: "观战",
	PokerRules.STATUS_AWAY: "离座",
}
const BLIND_NAMES := {"sb": "小盲", "bb": "大盲"}


static func system_prompt(bot_name: String, persona: String) -> String:
	return "\n".join([
		"你在一个叫「骗子酒馆」的游戏里扮演德州扑克(无限注现金局)玩家「%s」,和真人玩家对战。" % bot_name,
		"你的性格:%s" % persona,
		"每次轮到你时,你会收到当前局面。请认真思考后做出决定,目标是长期赢更多筹码。",
		"只回答一个 JSON 对象,不要别的文字,格式:",
		'{"action": "fold|check|call|raise|allin", "amount": 加注到的总额(只有 raise 需要), "quip": 快捷对话编号或 null}',
		"规则:不欠跟注时只能 check / raise / allin(不要 fold);欠跟注时只能 fold / call / raise / allin。",
		"raise 的 amount 是本轮「加注到」的总额(含你本轮已下的),必须在给出的范围内、是 10 的倍数。",
		"quip 可选:想在牌桌上说句话时填快捷对话编号(只在有感而发时说,大多数时候填 null)。",
	])


static func user_prompt(sit: Dictionary, pub: Dictionary, names: Dictionary, log_lines: Array) -> String:
	var me: int = sit["me"]
	var legal: Dictionary = sit["legal"]
	var lines := [
		"玩法:%s,盲注 %d/%d,第 %d 手,现在是%s。" % [
			"短牌德州(36 张,同花大于葫芦)" if sit["short_deck"] else "德州扑克(52 张)",
			PokerRules.SMALL_BLIND, PokerRules.BIG_BLIND, int(pub.get("hand", 0)),
			STREET_NAMES.get(sit["street"], str(sit["street"]))],
		"你的手牌:%s" % PokerCard.labels(sit["hole"]),
		"公共牌:%s" % (PokerCard.labels(sit["board"]) if not sit["board"].is_empty() else "(还没发)"),
		"底池合计:%d(含本轮各人已下的注)" % sit["pot"],
		"",
		"牌桌(按座位顺序):",
	]
	for row in pub.get("players", []):
		lines.append("- " + _player_line(row, pub, me))
	lines.append("")
	lines.append("本手行动记录:")
	var shown := log_lines.slice(maxi(log_lines.size() - MAX_LOG_LINES, 0))
	lines.append_array(shown if not shown.is_empty() else ["(还没有)"])
	lines.append("")
	lines.append("轮到你了。" + _options(legal))
	lines.append("")
	lines.append("快捷对话编号:" + "; ".join(range(Quips.LINES.size()).map(
		func(i: int) -> String: return "%d=%s" % [i, Quips.LINES[i]])))
	return "\n".join(lines)


static func _player_line(row: Dictionary, pub: Dictionary, me: int) -> String:
	var pid: Variant = row.get("pid")
	var tags := []
	if pid == pub.get("button"):
		tags.append("庄位")
	if pid == pub.get("sb"):
		tags.append("小盲")
	if pid == pub.get("bb"):
		tags.append("大盲")
	if pid == me:
		tags.append("你")
	var text := "%s:筹码 %d,本轮已下 %d,%s" % [row.get("name", "?"), int(row.get("stack", 0)),
		int(row.get("bet", 0)), STATUS_NAMES.get(row.get("status"), str(row.get("status")))]
	var shown: Array = row.get("shown", [])
	if not shown.is_empty():
		text += ",亮出 %s" % PokerCard.labels(shown)
	return text + ("(%s)" % "、".join(tags) if not tags.is_empty() else "")


static func _options(legal: Dictionary) -> String:
	var parts := []
	if legal.get("can_check", false):
		parts.append("check(过牌)")
	else:
		parts.append("fold(弃牌)")
		parts.append("call(跟注 %d)" % int(legal.get("call_amount", 0)))
	if legal.get("can_raise", false):
		parts.append("raise(加注到 %d–%d)" % [int(legal.get("min_raise_to", 0)), int(legal.get("max_raise_to", 0))])
	if legal.get("can_allin", false):
		parts.append("allin(全下,到 %d)" % int(legal.get("max_raise_to", 0)))
	return "可选:" + "、".join(parts)


static func describe_event(ev: Dictionary, names: Dictionary) -> String:
	# 行动记录的一行;不需要记的事件返回 ""
	var who: String = names.get(ev.get("pid"), "?")
	match ev.get("type", ""):
		"blind":
			return "%s 下%s %d" % [who, BLIND_NAMES.get(ev.get("kind"), "盲注"), int(ev.get("amount", 0))]
		"street":
			return "【%s】%s" % [STREET_NAMES.get(ev.get("street"), str(ev.get("street"))),
				PokerCard.labels(ev.get("board", []))]
		"action":
			return who + " " + _action_text(ev)
	return ""


static func _action_text(ev: Dictionary) -> String:
	var all_in := " (全下)" if ev.get("all_in", false) else ""
	match ev.get("action"):
		PokerRules.FOLD:
			return "弃牌"
		PokerRules.CHECK:
			return "过牌"
		PokerRules.CALL:
			return "跟注 %d%s" % [int(ev.get("amount", 0)), all_in]
		PokerRules.BET:
			return "下注 %d%s" % [int(ev.get("bet", 0)), all_in]
		PokerRules.RAISE:
			return "加注到 %d%s" % [int(ev.get("bet", 0)), all_in]
	return str(ev.get("action"))


# —— 解析回答 ——

static func parse(text: String, legal: Dictionary) -> Dictionary:
	# → {"ok": true, "action", "amount", "quip": 编号或 -1} 或 {"ok": false, "error"}。
	# 容忍回答前后的废话与 ```json 代码块:取第一个 { 到最后一个 } 之间的部分
	var start := text.find("{")
	var end := text.rfind("}")
	if start < 0 or end <= start:
		return _bad("回答里没有 JSON")
	var data: Variant = parse_json(text.substr(start, end - start + 1))
	if not data is Dictionary:
		# 模型偶尔写出差一点的 JSON(实测 gpt-4.1:"amount": 130", 多一个引号):逐个字段捞
		data = loose_fields(text.substr(start, end - start + 1))
	if data.is_empty():
		return _bad("JSON 解析失败")
	var action: Variant = data.get("action")
	if not action is String:
		return _bad("缺少 action")
	var choice := _legal_choice((action as String).strip_edges().to_lower(), data.get("amount"), legal)
	if choice.is_empty():
		return _bad("动作不合法:%s" % action)
	var quip: Variant = data.get("quip")
	if quip is float and quip == floorf(quip):
		quip = int(quip)
	elif quip is String and quip.is_valid_int():
		quip = quip.to_int()   # 写成字符串的编号也认
	return {"ok": true, "action": choice["action"], "amount": choice["amount"],
		"quip": quip if Quips.is_valid(quip) else -1}


static func loose_fields(text: String) -> Dictionary:
	# 从坏掉的 JSON 里按字段名捞 action(字母)、amount 与 quip(数字,带不带引号都行);捞不到 action 返回 {}
	var out := {}
	var action := RegEx.create_from_string('"action"\\s*:\\s*"([A-Za-z_-]+)"').search(text)
	if action == null:
		return out
	out["action"] = action.get_string(1)
	for key in ["amount", "quip"]:
		var found := RegEx.create_from_string('"%s"\\s*:\\s*"?(\\d+)' % key).search(text)
		if found != null:
			out[key] = found.get_string(1).to_int()
	return out


static func parse_json(text: String) -> Variant:
	# 解析失败返回 null。不用 JSON.parse_string:它对坏 JSON 会往引擎日志里报错,而 AI 答错格式是常事
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


static func _legal_choice(action: String, amount: Variant, legal: Dictionary) -> Dictionary:
	# 把 AI 的动作对到合法动作:能过牌时的 fold 当过牌(不白白扔牌),欠跟注时的 check 判无效;
	# raise 的金额夹到合法范围(没给金额按最小加注),不能加注时的 raise 当跟注 / 过牌
	var can_check: bool = legal.get("can_check", false)
	match action:
		PokerRules.FOLD:
			return PokerBotBrain.pick(PokerRules.CHECK if can_check else PokerRules.FOLD)
		PokerRules.CHECK:
			return PokerBotBrain.pick(PokerRules.CHECK) if can_check else {}
		PokerRules.CALL:
			return PokerBotBrain.pick(PokerRules.CHECK if can_check else PokerRules.CALL)
		PokerRules.RAISE, PokerRules.BET:
			if not legal.get("can_raise", false):
				return PokerBotBrain.pick(PokerRules.CHECK if can_check else PokerRules.CALL)
			var to: int = legal.get("min_raise_to", 0)
			if (amount is float or amount is int) and amount > 0:
				to = int(minf(amount, legal.get("max_raise_to", to)))   # 先夹再取整:超大的浮点数转 int 会溢出
			return PokerBotBrain.clamp_raise(legal, to)
		PokerRules.ALLIN, "all_in", "all-in":
			# 不能全下(对手都已全下、筹码比跟注额多)时最激进的就是跟注
			if legal.get("can_allin", false):
				return PokerBotBrain.pick(PokerRules.ALLIN)
			return PokerBotBrain.pick(PokerRules.CHECK if can_check else PokerRules.CALL)
	return {}


static func _bad(error: String) -> Dictionary:
	return {"ok": false, "error": error}
