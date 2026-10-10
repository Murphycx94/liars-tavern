class_name LiarsDicePacing
# 吹牛骰子演出预算(秒)。房主把它加到回合计时上,保证玩家看完动画后仍有完整的 TURN_TIMEOUT。
# 阶段二的导演每段演出的实际时长必须不超过这里的预算;预算按设计稿 §3 的演出先估,导演实测后可以收紧
# (预算比动画长多少,轮到行动者时倒计时就多出多少秒)。


const INTRO := Pacing.INTRO          # 开场运镜:客户端进入牌桌先播它
const ROUND_STARTED := 2.2           # 全员双手握盅摇、哗啦哗啦、扣下,自己掀开一角偷看
const BID := 1.0                     # 头顶气泡「3 个 5」,桌心浮出大骰子图标与个数
const TURN_PASSED := 0.2             # 高亮移到下一位
const CHALLENGED := 1.2              # 拍桌大字「开!」
const REVEAL_BASE := 1.6             # 所有骰盅一起掀开 + 最后的真话 / 吹牛判定
const REVEAL_PER_MATCH := 0.25       # 点数等于 X 的骰子与 1 点逐个高亮跳一下,计数器一路数上去
const REVEAL_MATCH_CAP := 30         # 计数最多数这么多颗(6 人 × 5 颗)
const DIE_LOST := 1.2                # 输家的一颗骰子「啵」地弹飞、冒小星星
const PLAYER_OUT := 1.8              # 骰子丢光:蚊香眼加星星
const PLAYER_LEFT := 0.8             # 断线出局:淡出
const MATCH_OVER := 3.0              # 结算面板之前的谢幕

# 这些事件会让客户端在演出结束时把回合交给某人(重新起算完整回合时间)
const TURN_EVENTS := ["turn_passed", "round_started"]


static func estimate(events: Array) -> float:
	var total := 0.0
	for ev in events:
		match ev.get("type", ""):
			"round_started":
				total += ROUND_STARTED
			"bid":
				total += BID
			"turn_passed":
				total += TURN_PASSED
			"challenged":
				total += CHALLENGED
			"revealed":
				total += reveal_time(ev)
			"die_lost":
				total += DIE_LOST
			"player_out":
				total += PLAYER_OUT
			"player_left":
				total += PLAYER_LEFT
			"match_over":
				total += MATCH_OVER
	return total


static func reveal_time(ev: Dictionary) -> float:
	# 开盅随实际个数变长:计数器一颗一颗数上去
	var actual: Variant = ev.get("actual", 0)
	var matches: int = clampi(actual, 0, REVEAL_MATCH_CAP) if actual is int else 0
	return REVEAL_BASE + REVEAL_PER_MATCH * matches


static func starts_turn(events: Array) -> bool:
	for ev in events:
		if TURN_EVENTS.has(ev.get("type", "")):
			return true
	return false
