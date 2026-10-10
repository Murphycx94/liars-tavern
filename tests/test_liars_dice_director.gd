extends GutTest
# 吹牛骰子导演:每段演出的实际时长不超过 LiarsDicePacing 的预算(同 test_bomb_cat_director:把导演与 LiarsDiceCups /
# LiarsDiceFx 的节奏常量按每种事件的最坏情况加起来,每个 await 再算一帧余量),导演认得设计稿 §6.3 的每一种公共事件、
# 每种都有预算;开盅随实际个数变长,每多数一颗的时长不超过 REVEAL_PER_MATCH;另测几个纯函数(日志、计数顺序、输家)。


const FRAME := 1.0 / 30.0
const H := preload("res://tests/liars_dice_helpers.gd")
const D := preload("res://src/ui/liars_dice/liars_dice_director.gd")
const C := preload("res://src/world/liars_dice/liars_dice_cups.gd")


func _budget_ok(actual: float, awaits: int, budget: float, what: String) -> void:
	assert_lte(actual + FRAME * awaits, budget, "%s:实际 %.2f + %d 帧余量 > 预算 %.2f" % [what, actual, awaits, budget])


func test_director_handles_every_public_event_type():
	assert_eq(D.HANDLED_EVENTS.size(), H.EVENT_KEYS.size())
	for type in H.EVENT_KEYS:
		assert_has(D.HANDLED_EVENTS, type, "导演要演 %s" % type)
		assert_gt(LiarsDicePacing.estimate([{"type": type, "actual": 0}]), 0.0, "%s 有预算" % type)


func test_intro_and_round_start_fit():
	_budget_ok(D.INTRO_MOVE, 1, LiarsDicePacing.INTRO, "intro")
	# 收骰子 + 摇盅(同时等私有骰子,最多 PRIVATE_WAIT,逐帧等算两帧余量)+ 偷看 + 收尾
	var actual := C.GATHER_TIME + C.SHAKE_TOTAL + C.PEEK_TOTAL + D.ROUND_TAIL
	_budget_ok(actual, 6, LiarsDicePacing.ROUND_STARTED, "round_started")
	assert_lte(D.PRIVATE_WAIT, C.SHAKE_TOTAL, "等私有骰子藏在摇盅里,不额外占时间")
	assert_lte(D.PEEK_DIP * 2.0, C.PEEK_TOTAL + D.ROUND_TAIL + 0.2, "第一人称视线压下去再回来,和偷看差不多同时结束")
	assert_lte(C.PEEK_UP + C.PEEK_HOLD + C.PEEK_DOWN, C.PEEK_TOTAL + 0.0001)


func test_bid_turn_and_challenge_fit():
	_budget_ok(D.BID_HOLD, 1, LiarsDicePacing.BID, "bid")
	assert_lte(LiarsDiceFx.MARKER_POP, D.BID_HOLD, "桌心的大骰子在这段里弹完")
	_budget_ok(0.0, 0, LiarsDicePacing.TURN_PASSED, "turn_passed(不等)")
	_budget_ok(D.SLAM_AT + D.CHALLENGE_HOLD, 2, LiarsDicePacing.CHALLENGED, "challenged")


func test_reveal_fits_for_every_count():
	# 开盅:骰盅掀起 + 骰子排开 + 停一下 + 每颗算进去的跳一下 + 判定;每颗一个 await
	assert_lte(C.HOP_TIME, D.COUNT_STEP, "一颗跳完再数下一颗")
	assert_lte(D.COUNT_STEP + FRAME, LiarsDicePacing.REVEAL_PER_MATCH, "每多数一颗不超过每颗的预算")
	for actual in range(0, LiarsDicePacing.REVEAL_MATCH_CAP + 1):
		var budget := LiarsDicePacing.reveal_time({"actual": actual})
		_budget_ok(D.reveal_duration(actual), 2 + actual, budget, "revealed(数 %d 颗)" % actual)
	assert_lte(C.LIFT_TIME * 0.55 + C.SPREAD_TIME, D.REVEAL_OPEN + 0.0001, "骰子排好才开始数")


func test_loss_out_left_and_match_over_fit():
	_budget_ok(D.DIE_LOST_HOLD, 1, LiarsDicePacing.DIE_LOST, "die_lost")
	assert_lte(C.POP_TIME, D.DIE_LOST_HOLD, "弹飞的骰子在这段里缩没")
	_budget_ok(D.OUT_HOLD, 1, LiarsDicePacing.PLAYER_OUT, "player_out")
	assert_lte(C.TIP_TIME, D.OUT_HOLD)
	_budget_ok(D.LEFT_PAUSE, 1, LiarsDicePacing.PLAYER_LEFT, "player_left")
	_budget_ok(D.MATCH_HOLD, 1, LiarsDicePacing.MATCH_OVER, "match_over")


func test_a_whole_challenge_batch_fits_its_estimate():
	# 典型的「开!」批次:challenged + revealed + die_lost + player_out + round_started,导演实测之和不超过房主的估计
	var batch := [{"type": "challenged"}, {"type": "revealed", "actual": 7}, {"type": "die_lost"}, {"type": "player_out"},
		{"type": "round_started"}]
	var actual := D.SLAM_AT + D.CHALLENGE_HOLD + D.reveal_duration(7) + D.DIE_LOST_HOLD + D.OUT_HOLD \
		+ C.GATHER_TIME + C.SHAKE_TOTAL + C.PEEK_TOTAL + D.ROUND_TAIL
	assert_lte(actual, LiarsDicePacing.estimate(batch))


# —— 纯函数 ——

func test_logs_and_loser():
	var names := func(pid): return {1: "我", 2: "阿狸"}.get(pid, "?")
	assert_eq(D.bid_log({"pid": 2, "count": 3, "face": 5, "auto": false}, names), "阿狸 喊 3 个 5")
	assert_eq(D.bid_log({"pid": 2, "count": 3, "face": 5, "auto": true}, names), "阿狸 喊 3 个 5(超时代喊)")
	assert_eq(D.challenge_log({"pid": 1, "target": 2, "count": 3, "face": 5, "auto": false}, names), "我 开 阿狸 的「3 个 5」")
	var challenge := {"pid": 1, "target": 2}
	assert_eq(D.loser_of(challenge, true), 1, "真话:开的人输")
	assert_eq(D.loser_of(challenge, false), 2, "吹牛:喊的人输")


func test_reveal_duration_grows_with_the_count_and_caps():
	assert_gt(D.reveal_duration(5), D.reveal_duration(4))
	assert_eq(D.reveal_duration(99), D.reveal_duration(LiarsDicePacing.REVEAL_MATCH_CAP))
