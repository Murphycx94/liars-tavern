extends GutTest
# 斗地主导演:每段演出的实际时长不超过 DouDizhuPacing 的预算(同 test_bomb_cat_director:把导演、DdzCards 与 DdzFx 的节奏常量
# 按每种事件的最坏情况加起来,每个 await 再算一帧余量);导演认得 §6.3 的每一种公共事件、每种都有预算;
# 牌型 → 特效的对应(炸弹烟云、王炸火箭、飞机、顺子连对的波浪),以及日志 / 赢家等纯函数。


const FRAME := 1.0 / 30.0
const H := preload("res://tests/ddz_helpers.gd")
const D := preload("res://src/ui/dou_dizhu/ddz_director.gd")
const P := preload("res://src/net/dou_dizhu_pacing.gd")


func _budget_ok(actual: float, awaits: int, budget: float, what: String) -> void:
	assert_lte(actual + FRAME * awaits, budget, "%s:实际 %.2f + %d 帧余量 > 预算 %.2f" % [what, actual, awaits, budget])


func test_director_handles_every_public_event_type():
	assert_eq(D.HANDLED_EVENTS.size(), H.EVENT_KEYS.size())
	for type in H.EVENT_KEYS:
		assert_has(D.HANDLED_EVENTS, type, "导演要演 %s" % type)


func test_intro_deal_and_redeal_fit():
	_budget_ok(D.INTRO_MOVE, 1, P.INTRO, "intro")
	var cards := DdzState.HAND_SIZE * DdzState.PLAYERS + DdzState.BOTTOM_SIZE
	# 收上一手的牌与等私有手牌同时进行(取较长的),再发牌
	_budget_ok(maxf(DdzCards.SWEEP_FLIGHT, D.PRIVATE_WAIT) + DdzCards.deal_duration(cards), 4, P.HAND_STARTED, "hand_started")
	_budget_ok(maxf(DdzCards.SWEEP_FLIGHT, D.REDEAL_PRIVATE_WAIT) + DdzCards.deal_duration(cards, DdzCards.REDEAL_SPAN), 4, P.REDEAL, "redeal")
	assert_lt(DdzCards.deal_duration(cards), DdzCards.DEAL_SPAN + DdzCards.DEAL_FLIGHT + 0.06, "54 张在发牌时长上限里发完")


func test_bid_and_landlord_fit():
	_budget_ok(D.BID_HOLD, 1, P.BID, "bid")
	_budget_ok(DdzCards.BOTTOM_FLIP + DdzCards.BOTTOM_HOLD + DdzCards.BOTTOM_FLIGHT + D.LANDLORD_TAIL, 4, P.LANDLORD, "landlord")
	assert_lte(DdzHats.POP_TIME, DdzCards.BOTTOM_FLIP + DdzCards.BOTTOM_HOLD + DdzCards.BOTTOM_FLIGHT, "帽子在底牌进手之前戴好")
	assert_lte(DdzFx.SPOT_POP, P.LANDLORD)


func test_every_combo_fits_its_budget():
	# 每种牌型取最多的张数(出牌行里每张错开 PLAY_STAGGER 出手)
	var worst := {DdzHand.SINGLE: 1, DdzHand.PAIR: 2, DdzHand.TRIPLE: 3, DdzHand.TRIPLE_SINGLE: 4, DdzHand.TRIPLE_PAIR: 5,
		DdzHand.STRAIGHT: 12, DdzHand.PAIR_STRAIGHT: 20, DdzHand.AIRPLANE: 18, DdzHand.AIRPLANE_SINGLE: 20, DdzHand.AIRPLANE_PAIR: 20,
		DdzHand.FOUR_TWO_SINGLE: 6, DdzHand.FOUR_TWO_PAIR: 8, DdzHand.BOMB: 4, DdzHand.ROCKET: 2}
	assert_eq(worst.size(), DdzHand.TYPE_NAMES.size(), "每种牌型都核对到")
	for combo in worst:
		var awaits := 3 if D.effect_for(combo) == "rocket" else 2
		_budget_ok(D.played_time(combo, worst[combo]), awaits, P.played_time(combo), "出 %s(%d 张)" % [DdzHand.type_name(combo), worst[combo]])


func test_effects_land_inside_their_beat():
	assert_lte(DdzFx.ROCKET_RISE + DdzFx.FIREWORK_STAGGER * (DdzFx.FIREWORK_BURSTS - 1), DdzFx.ROCKET_TIME, "最后一簇烟花在导演等的时间里炸开")
	assert_lte(DdzCards.WAVE_TIME, P.PLAYED_CHAIN, "波浪亮完")
	assert_lte(D.PLANE_DELAY + DdzFx.PLANE_TIME, P.PLAYED_AIRPLANE, "纸飞机飞完")
	assert_lte(DdzFx.BOMB_TIME, P.PLAYED_BOMB)


func test_pass_trick_hand_over_and_session_fit():
	_budget_ok(D.PASS_HOLD, 1, P.PASSED, "passed")
	_budget_ok(DdzCards.TRICK_SWEEP, 1, P.TRICK_CLEARED, "trick_cleared")
	_budget_ok(DdzCards.REVEAL_FLIGHT + D.HAND_OVER_HOLD, 2, P.HAND_OVER, "hand_over")
	_budget_ok(DdzCards.REVEAL_FLIGHT + D.HAND_OVER_HOLD + DdzFx.SPRING_TIME, 3, P.HAND_OVER + P.HAND_OVER_SPRING, "hand_over(春天)")
	_budget_ok(D.LEFT_PAUSE, 1, P.PLAYER_LEFT, "player_left")
	_budget_ok(D.SESSION_OVER_HOLD, 1, P.SESSION_OVER, "session_over")
	assert_eq(P.TURN, 0.0, "换人和上一段并行")
	assert_eq(P.TRUSTEE, 0.0)


func test_effect_mapping():
	assert_eq(D.effect_for(DdzHand.BOMB), "bomb")
	assert_eq(D.effect_for(DdzHand.ROCKET), "rocket")
	for c in [DdzHand.AIRPLANE, DdzHand.AIRPLANE_SINGLE, DdzHand.AIRPLANE_PAIR]:
		assert_eq(D.effect_for(c), "plane", c)
	for c in [DdzHand.STRAIGHT, DdzHand.PAIR_STRAIGHT]:
		assert_eq(D.effect_for(c), "chain", c)
	for c in [DdzHand.SINGLE, DdzHand.PAIR, DdzHand.TRIPLE_PAIR, DdzHand.FOUR_TWO_SINGLE]:
		assert_eq(D.effect_for(c), "", c)


func test_texts_and_winners():
	var names := func(pid): return {1: "我", 2: "阿狸", 3: "小熊"}.get(pid, "?")
	var ev := {"type": "played", "pid": 2, "cards": H.cards("3 4 5 6 7"), "combo": DdzHand.STRAIGHT, "auto": false, "timed_out": false}
	assert_eq(D.played_text(ev, names), "阿狸 出了 顺子 · 5 张:7 6 5 4 3")
	ev["auto"] = true
	assert_string_ends_with(D.played_text(ev, names), "(托管)")
	assert_eq(D.played_text({"pid": 3, "cards": H.cards("SJ BJ"), "combo": DdzHand.ROCKET}, names), "小熊 出了 王炸")
	assert_eq(D.winners_of({"landlord": 2, "landlord_won": true}, [1, 2, 3]), [2])
	assert_eq(D.winners_of({"landlord": 2, "landlord_won": false}, [1, 2, 3]), [1, 3])


func test_fx_effects_spawn_and_free_themselves():
	# 每种特效都建出自己的根节点,演完自己释放(根节点数回到只剩常驻的报警 / 「不出」)
	var world := TableWorld.new(null)
	add_child_autofree(world)
	world.arrange([{"pid": 1}, {"pid": 2}, {"pid": 3}], 1, true, false)
	var fx := DdzFx.new(world)
	world.poker_root.add_child(fx)
	var kinds := []
	fx.spawned.connect(func(kind: String): kinds.append(kind))
	var at := world.to_global(Vector3(0, SeatLayout.TABLE_TOP, 0))
	fx.bomb(at, 4)
	fx.rocket(at)
	fx.plane(at + Vector3(-0.3, 0, 0), at + Vector3(0.3, 0, -0.3))
	fx.spring(at)
	fx.spotlight_on(2, 0.5)
	fx.set_alarm(3, 2)
	fx.pass_mark(2, at)
	for kind in ["bomb", "rocket", "plane", "spring", "spot", "alarm", "pass", "text"]:
		assert_has(kinds, kind, "特效 %s 建出来了" % kind)
	assert_eq(fx.alarm_count(3), 2)
	assert_true(fx.has_pass(2))
	fx.set_alarm(3, 5)
	assert_eq(fx.alarm_count(3), 0, "3 张以上不报警")
	fx.clear_pass(2)
	var scale := Engine.time_scale
	Engine.time_scale = 8.0
	await wait_until(func(): return fx.active_count() == 0, 4.0, "特效都释放了")
	Engine.time_scale = scale
	assert_eq(fx.active_count(), 0)
	assert_has(kinds, "firework", "小火箭到顶炸成烟花")
	assert_has(kinds, "sparks", "烟花的火星")
