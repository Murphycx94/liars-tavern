class_name BlackjackPacing
# 21 点演出预算(秒)。房主把它加到回合计时与两局之间的间隔上,保证玩家看完动画后仍有完整的下注 / 决策时间。
# BlackjackDirector 每段演出的实际时长必须不超过这里的预算(test_blackjack_director 读取导演的节奏常量来检查)。


const INTRO := Pacing.INTRO
const ROUND_STARTED := 1.3           # 收上一局的牌与筹码、按新座位表重排、宣告「第 N 局 · 请下注」
const SHUFFLE := 1.2                 # 牌鞋重洗(round_started 带 shuffled 时另加)
const BET_PLACED := 0.45             # 筹码从筹码堆滑到下注位
const DEAL_BASE := 0.3               # 发牌:基础 + 每张
const DEAL_PER_CARD := 0.2
const PEEK := 0.9                    # 庄家掀起暗牌一角看一眼
const HIT := 0.55
const STAND := 0.35
const DOUBLE := 0.85                 # 再押一份 + 横着发一张
const SPLIT := 1.0                   # 两张拆开、再押一份、各补一张
const SURRENDER := 0.6
const DEALER_REVEAL := 0.8
const DEALER_HIT := 0.6
const SETTLED := 1.8                 # 各手同时结算:赢的从桌心飞来筹码、输的筹码滑走,再一起收回筹码堆
const ROUND_OVER := 0.4
const REBUY := 0.6
const PLAYER_LEFT := 0.8
const SESSION_OVER := 3.0            # 结算面板之前的谢幕
# 房主排期用,不对应事件:两局之间演完这一批再停这么久开下一局(看一眼结果);下注与决策的限时
const ROUND_GAP := 2.0
const BET_TIMEOUT := 15.0
const PLAY_TIMEOUT := 20.0
# bet_skipped / player_joined / away / sit_in / ending 不占演出时间


static func estimate(events: Array) -> float:
	var total := 0.0
	for ev in events:
		match ev.get("type", ""):
			"round_started":
				total += ROUND_STARTED + (SHUFFLE if Untrusted.flag(ev.get("shuffled")) else 0.0)
			"bet_placed":
				total += BET_PLACED
			"dealt":
				var order: Array = ev["order"] if ev.get("order") is Array else []
				total += DEAL_BASE + DEAL_PER_CARD * (2 * order.size() + 2)
			"peek":
				total += PEEK
			"hit":
				total += HIT
			"stand":
				total += STAND
			"double":
				total += DOUBLE
			"split":
				total += SPLIT
			"surrender":
				total += SURRENDER
			"dealer_reveal":
				total += DEALER_REVEAL
			"dealer_hit":
				total += DEALER_HIT
			"settled":
				total += SETTLED
			"round_over":
				total += ROUND_OVER
			"rebuy":
				total += REBUY
			"player_left":
				total += 0.0 if ev.get("offstage", false) else PLAYER_LEFT
			"session_over":
				total += SESSION_OVER
	return total


static func timer_after(events: Array, pending: float, time_left: float, betting: bool) -> float:
	# 交出回合的批次(下注阶段开始、轮到某一手)演完后给满限时;否则(旁人下注、离开、再领)保留剩余时间,只补上本批演出。
	# betting:这一批之后桌上是下注阶段
	for ev in events:
		match ev.get("type", ""):
			"turn":
				return pending + PLAY_TIMEOUT
			"round_started":
				return pending + BET_TIMEOUT
	if time_left <= 0.0:
		return pending + (BET_TIMEOUT if betting else PLAY_TIMEOUT)
	return time_left + estimate(events)
