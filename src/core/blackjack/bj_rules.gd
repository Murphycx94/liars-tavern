class_name BjRules
# 21 点(和酒馆庄家对赌的现金局)的规则常量。说明书、界面与引擎里的数字一律取自这里(设计稿 2026-10-12-blackjack-design §2)。


const STARTING_STACK := 2000     # 入座与每次再领的筹码
const MIN_BET := 20
const MAX_BET := 1000
const BET_UNIT := 20             # 下注额都是它的倍数:黑杰克赔 3:2、投降退一半都还是整十
const CHIP_UNIT := 10
const DECKS := 6
const RESHUFFLE_BELOW := 78      # 一局开始时牌鞋剩不到这么多张(1/4)就重新洗牌
const MAX_SEATS := 7
const MIN_PLAYERS := 1
const MAX_HANDS := 4             # 分牌最多分成 4 手
const DEALER_STANDS := 17        # 庄家要牌到 17,所有 17 点都停(S17)
const BLACKJACK := 21
const AWAY_AFTER_TIMEOUTS := 2   # 连续超时这么多次(下注或决策都算),从下一局起离座

# —— 意图与事件里的动作 ——
const BET := "bet"
const SKIP := "skip"             # 这局不玩
const HIT := "hit"
const STAND := "stand"
const DOUBLE := "double"
const SPLIT := "split"
const SURRENDER := "surrender"
const REBUY := "rebuy"
const SIT_IN := "sit_in"
const PLAY_ACTIONS := [HIT, STAND, DOUBLE, SPLIT, SURRENDER]
const BET_ACTIONS := [BET, SKIP]
const SEAT_ACTIONS := [REBUY, SIT_IN]
const ACTION_NAMES := {HIT: "要牌", STAND: "停牌", DOUBLE: "加倍", SPLIT: "分牌", SURRENDER: "投降"}

# —— 玩家状态(公共视图 players[].status)——
const STATUS_WAITING := "waiting"    # 下注阶段还没决定;两局之间与刚入座的人也是它
const STATUS_BET := "bet"            # 本局已下注(下注阶段)
const STATUS_SKIP := "skip"          # 这局不玩
const STATUS_PLAYING := "playing"    # 本局发到牌(或刚结束的一局里发到了牌)
const STATUS_BUSTED := "busted"      # 筹码不够最小下注,可以再领
const STATUS_AWAY := "away"          # 挂机离座:不发牌,下注阶段不等他

# —— 每手牌的结果(settled 事件与视图的 hands[].outcome)——
const OUTCOME_BLACKJACK := "blackjack"   # 黑杰克赢 3:2
const OUTCOME_WIN := "win"
const OUTCOME_PUSH := "push"
const OUTCOME_LOSE := "lose"
const OUTCOME_BUST := "bust"             # 爆牌(输)
const OUTCOME_SURRENDER := "surrender"   # 投降(输一半)
const OUTCOME_NAMES := {
	OUTCOME_BLACKJACK: "黑杰克", OUTCOME_WIN: "赢", OUTCOME_PUSH: "平手", OUTCOME_LOSE: "输",
	OUTCOME_BUST: "爆牌", OUTCOME_SURRENDER: "投降",
}


static func is_valid_bet(amount: Variant, stack: int) -> bool:
	return amount is int and amount >= MIN_BET and amount <= MAX_BET and amount % BET_UNIT == 0 and amount <= stack


static func payout(outcome: String, bet: int) -> int:
	# 这手牌结算时退回给玩家的筹码(含本金):黑杰克 2.5 倍、赢 2 倍、平手 1 倍、投降一半、输与爆牌 0
	match outcome:
		OUTCOME_BLACKJACK:
			return bet + bet * 3 / 2
		OUTCOME_WIN:
			return bet * 2
		OUTCOME_PUSH:
			return bet
		OUTCOME_SURRENDER:
			return bet / 2
	return 0
