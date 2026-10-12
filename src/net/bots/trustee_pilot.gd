class_name TrusteePilot
# 本机玩家托管(PokerPilot / DdzPilot)共用的小工具。托管在玩家自己的电脑上跑:用的是本机的 AI 设置
# (客人用客人自己的,绝不用房主的),没开 AI 或 AI 没接上就用机器人的内置策略;意图和手动出牌一样发给房主,
# 只多带一个来源 by(trustee / trustee_ai),房主标在出手事件上,各端记录据此写「(托管·AI)」「(托管)」。


const PERSONA := "你在替玩家「%s」托管(代打):理性、稳健地打,目标是长期赢得更多。"


static func source(asked: bool, by_ai: bool) -> String:
	# 托管的出手一律标来源:AI 出的是 trustee_ai,其余(没开 AI、AI 没接上)是 trustee
	return BotDriver.SOURCE_TRUSTEE_AI if asked and by_ai else BotDriver.SOURCE_TRUSTEE


static func with_source(intent: Dictionary, from: String) -> Dictionary:
	return intent.merged({"by": from}, true) if from != "" else intent


static func client_anim(pub: Dictionary, full_turn: float) -> float:
	# 客户端还要演多久:房主给的回合剩余时间 = 待演出 + 完整回合时长(新回合),减掉完整回合就是待演出
	var left: Variant = pub.get("turn_time_left", 0.0)
	var seconds := float(left) if left is float or left is int else 0.0
	return maxf(seconds - full_turn, 0.0)


static func turn_left(pub: Dictionary) -> float:
	# 房主给的回合剩余秒数(收到视图那一刻;含待演出)
	var left: Variant = pub.get("turn_time_left", 0.0)
	return float(left) if left is float or left is int else 0.0


static func flag(value: Variant) -> bool:
	return value is bool and value
