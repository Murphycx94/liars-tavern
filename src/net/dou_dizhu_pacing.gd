class_name DouDizhuPacing
# 斗地主演出预算(秒)。房主把它加到回合计时与一手之间的间隔上,保证玩家看完动画后仍有完整思考时间。
# 阶段二的导演每段演出的实际时长必须不超过这里的预算;预算按设计稿 §3 的演出先估,导演实测后可以收紧。


const INTRO := Pacing.INTRO          # 开场运镜:客户端进入牌桌先播它
const HAND_STARTED := 3.0            # 洗牌、每人 17 张飞到手里、3 张底牌扣在桌心
const REDEAL := 2.4                  # 三人都不叫:收牌重洗再发
const BID := 0.6                     # 头顶气泡「1 分 / 2 分 / 3 分 / 不叫」
const LANDLORD := 2.2                # 底牌翻开飞进地主手里,戴上地主帽 / 草帽
const PLAYED := 0.7                  # 牌从手里摊到自己面前的桌面上
const PLAYED_CHAIN := 1.2            # 顺子 / 连对:一串牌像波浪一样亮起
const PLAYED_AIRPLANE := 1.6         # 飞机:小纸飞机掠过桌面
const PLAYED_BOMB := 2.0             # 炸弹:蘑菇云加「炸弹!」,倍数跳动
const PLAYED_ROCKET := 2.5           # 王炸:小火箭冲天放烟花
const PASSED := 0.4                  # 「不出」气泡
const TRICK_CLEARED := 0.4           # 桌面上的牌收掉
const TURN := 0.0                    # 高亮换人(和上一段演出并行)
const TRUSTEE := 0.0                 # 托管标记(和上一段演出并行)
const HAND_OVER := 3.0               # 亮牌、输赢分数飘字
const HAND_OVER_SPRING := 1.5        # 春天:花瓣飘落加「春天!」(另加)
const ENDING := 0.0
const PLAYER_LEFT := 0.8
const SESSION_OVER := 3.0            # 结算面板之前的谢幕

# 房主排期用,不对应事件:
const HAND_GAP := 5.0                # 一手结束演完后再停这么久(看清结算)才自动开下一手
const TRUSTEE_DELAY := 1.0           # 托管中的人轮到时,演完再等这么久由房主代打

# 这些事件会让客户端在演出结束时把回合交给某人(重新起算回合时间)
const TURN_EVENTS := ["turn"]


static func estimate(events: Array) -> float:
	var total := 0.0
	for ev in events:
		match ev.get("type", ""):
			"hand_started":
				total += HAND_STARTED
			"redeal":
				total += REDEAL
			"bid":
				total += BID
			"landlord":
				total += LANDLORD
			"played":
				total += played_time(ev.get("combo", ""))
			"passed":
				total += PASSED
			"trick_cleared":
				total += TRICK_CLEARED
			"turn":
				total += TURN
			"trustee":
				total += TRUSTEE
			"hand_over":
				total += HAND_OVER + (HAND_OVER_SPRING if ev.get("spring", false) else 0.0)
			"ending":
				total += ENDING
			"player_left":
				total += PLAYER_LEFT
			"session_over":
				total += SESSION_OVER
	return total


static func played_time(combo: String) -> float:
	match combo:
		DdzHand.ROCKET:
			return PLAYED_ROCKET
		DdzHand.BOMB:
			return PLAYED_BOMB
		DdzHand.AIRPLANE, DdzHand.AIRPLANE_SINGLE, DdzHand.AIRPLANE_PAIR:
			return PLAYED_AIRPLANE
		DdzHand.STRAIGHT, DdzHand.PAIR_STRAIGHT:
			return PLAYED_CHAIN
	return PLAYED


static func starts_turn(events: Array) -> bool:
	for ev in events:
		if TURN_EVENTS.has(ev.get("type", "")):
			return true
	return false
