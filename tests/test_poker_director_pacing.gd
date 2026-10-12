extends GutTest
# 德州导演的实际时长不超过 PokerPacing 的预算(规格 §4.7):把导演与资产类(PokerChips / PokerCards / TableWorld)
# 的节奏常量按每种事件的最坏情况加起来,再加余量(每个 await 一帧,至少 4 帧,计划任务 7),仍要 ≤ 预算。
# 导演或资产改了节奏,这里会跟着变。另测导演的几个纯函数(日志文案、高亮的牌、分池宣告)。


const FRAME := 1.0 / 30.0   # 每个 await 可能晚一帧(按 30 fps 估)
const MIN_SLACK_FRAMES := 4
const MAX_PLAYERS := GameMode.POKER_MAX_PLAYERS
const H := preload("res://tests/poker_helpers.gd")


func _budget_ok(actual: float, awaits: int, budget: float, what: String) -> void:
	var frames := maxi(awaits, MIN_SLACK_FRAMES)
	assert_lte(actual + FRAME * frames, budget, "%s:实际 %.2f + %d 帧余量 > 预算 %.2f" % [what, actual, frames, budget])


func test_hand_started_waits_for_sweep_button_seat_move_and_camera_in_parallel():
	# 收牌、按钮、换座、运镜同时进行,导演只等 HAND_START_SETTLE:它要盖住每一项
	var longest := maxf(maxf(PokerCards.SWEEP_FLIGHT + PokerCards.SWEEP_JITTER, PokerChips.BUTTON_MOVE),
		maxf(TableWorld.SEAT_MOVE, PokerDirector.CAMERA_MOVE))
	assert_lte(longest, PokerDirector.HAND_START_SETTLE, "有一项比等待时间长")
	_budget_ok(PokerDirector.HAND_START_SETTLE, 1, PokerPacing.HAND_STARTED, "hand_started")


func test_blind_fits():
	_budget_ok(PokerChips.BET_SLIDE, 1, PokerPacing.BLIND, "blind")


func test_hole_cards_fit_for_every_table_size():
	for players in range(PokerRules.MIN_PLAYERS, MAX_PLAYERS + 1):
		var cards := players * PokerRules.HOLE_CARDS
		# 等牌面与等私有手牌正常情况下不等待(各一个 await),发牌一个 await
		_budget_ok(PokerCards.deal_duration(cards), 3, PokerPacing.HOLE_BASE + PokerPacing.HOLE_PER_CARD * cards, "发 %d 人" % players)


func test_actions_fit():
	_budget_ok(PokerCards.FOLD_FLIGHT, 1, PokerPacing.ACTION, "弃牌")
	_budget_ok(PokerDirector.CHECK_PAUSE, 1, PokerPacing.ACTION, "过牌")
	_budget_ok(PokerChips.BET_SLIDE, 1, PokerPacing.ACTION, "跟注 / 加注")
	_budget_ok(PokerChips.BET_SLIDE + PokerDirector.ALLIN_HOLD, 2, PokerPacing.ACTION_ALLIN, "全下")


func test_bets_collected_fits_refund_plus_collect():
	_budget_ok(PokerChips.REFUND_SLIDE + PokerChips.COLLECT_SLIDE, 2, PokerPacing.BETS_COLLECTED, "bets_collected")


func test_streets_fit():
	for cards in [1, PokerRules.FLOP_CARDS]:
		_budget_ok(PokerCards.board_duration(cards), 1, PokerPacing.STREET_BASE + PokerPacing.STREET_PER_CARD * cards, "发 %d 张公共牌" % cards)


func test_reveal_fits_for_every_number_of_hands():
	for hands in range(1, MAX_PLAYERS + 1):
		_budget_ok(hands * PokerCards.REVEAL_FLIGHT, hands, PokerPacing.REVEAL_BASE + PokerPacing.REVEAL_PER_HAND * hands, "%d 人亮牌" % hands)


func test_pot_won_hand_over_rebuy_left_and_session_over_fit():
	_budget_ok(PokerChips.AWARD_SLIDE + PokerDirector.POT_HOLD, 2, PokerPacing.POT_WON, "pot_won")
	_budget_ok(PokerDirector.HAND_OVER_PAUSE, 1, PokerPacing.HAND_OVER, "hand_over")
	_budget_ok(PokerChips.REBUY_DROP, 1, PokerPacing.REBUY, "rebuy")
	_budget_ok(PokerCards.FOLD_FLIGHT + PokerDirector.LEFT_PAUSE, 2, PokerPacing.PLAYER_LEFT, "player_left(弃牌离开)")
	_budget_ok(PokerDirector.SESSION_OVER_HOLD, 1, PokerPacing.SESSION_OVER, "session_over")


func test_intro_stays_within_the_hosts_intro_budget():
	_budget_ok(PokerDirector.INTRO_MOVE, 1, PokerPacing.INTRO, "intro")


# —— 纯函数 ——

func test_action_text():
	assert_eq(PokerDirector.action_text({"action": "fold", "amount": 0, "bet": 0, "all_in": false}), "弃牌")
	assert_eq(PokerDirector.action_text({"action": "check", "amount": 0, "bet": 0, "all_in": false}), "过牌")
	assert_eq(PokerDirector.action_text({"action": "call", "amount": 20, "bet": 20, "all_in": false}), "跟注 20")
	assert_eq(PokerDirector.action_text({"action": "bet", "amount": 40, "bet": 40, "all_in": false}), "下注 40")
	assert_eq(PokerDirector.action_text({"action": "raise", "amount": 60, "bet": 1240, "all_in": false}), "加注到 1,240")
	assert_eq(PokerDirector.action_text({"action": "raise", "amount": 960, "bet": 980, "all_in": true}), "全下 980")
	assert_eq(PokerDirector.action_text({"action": "fold", "amount": 0, "bet": 0, "all_in": false, "timeout": true}), "弃牌(超时)")
	assert_eq(PokerDirector.action_text({"action": "call", "amount": 20, "bet": 20, "all_in": false, "ai": true}), "跟注 20(ai)",
		"机器人按 AI 出手标「(ai)」")
	assert_eq(PokerDirector.action_text({"action": 7}), "7", "坏字段不崩")


func test_best_cards_union_and_pot_won_text():
	var ev := {"index": 0, "amount": 1240, "winners": [2, 3], "shares": {2: 620, 3: 620}, "hand_name": "葫芦 · Q 带 7",
		"best": {2: H.cards("Qh Qd Qc 7s 7h"), 3: H.cards("Qh Qd Qs 7s 7h")}, "uncontested": false}
	var lit := PokerDirector.best_cards(ev)
	assert_eq(lit.size(), 6, "并集去重")
	var names := func(pid: int) -> String: return {2: "乙", 3: "丙"}[pid]
	assert_eq(PokerDirector.pot_won_text(ev, names), {"title": "乙、丙 平分 1,240", "sub": "葫芦 · Q 带 7"})
	var walk := {"index": 0, "amount": 30, "winners": [2], "shares": {2: 30}, "hand_name": "", "best": {}, "uncontested": true}
	assert_eq(PokerDirector.pot_won_text(walk, names), {"title": "乙 赢得 30", "sub": "无人跟注"})
	assert_eq(PokerDirector.best_cards(walk), [])
	assert_eq(PokerDirector.best_cards({"best": {2: "junk"}}), [])
