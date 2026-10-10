extends GutTest
# PerfBudget:性能探针按机位核对预算,超出的每项给一条中文说明(--assert-budget 据此返回非零)。

const PerfBudget := preload("res://tools/perf_budget.gd")


func test_within_budget_reports_nothing():
	var stats := {"draw_calls": 400, "frame_ms": 9.0, "cpu_ms": 0.7, "lights": 16}
	assert_eq(PerfBudget.violations("seat", stats).size(), 0)


func test_each_exceeded_limit_reports_one_message():
	var stats := {"draw_calls": 1799, "frame_ms": 11.0, "cpu_ms": 0.5, "lights": 18}   # 三项超标:draw call、帧时间、灯
	var messages := PerfBudget.violations("seat", stats)
	assert_eq(messages.size(), 3)
	assert_string_contains(messages[0] + messages[1] + messages[2], "draw_calls")


func test_menu_and_other_views_have_their_own_draw_call_limits():
	# 四个子项目全部完成后的总预算:seat 700、menu 800、其余机位 900,帧时间 10 ms、CPU 渲染线程 1 ms
	assert_eq(PerfBudget.LIMITS["seat"]["draw_calls"], 700)
	assert_eq(PerfBudget.LIMITS["menu"]["draw_calls"], 800)
	for view in ["opponent", "closeup", "gun", "bar", "window", "fireplace", "overhead", "selfshot"]:
		assert_eq(PerfBudget.LIMITS[view]["draw_calls"], 900, view)
	for view in PerfBudget.LIMITS:
		assert_eq(PerfBudget.LIMITS[view]["frame_ms"], 10.0, view)
		assert_eq(PerfBudget.LIMITS[view]["cpu_ms"], 1.0, view)


func test_missing_stats_are_not_violations():
	assert_eq(PerfBudget.violations("seat", {"draw_calls": 100}).size(), 0)


func test_unknown_view_reports_nothing():
	assert_eq(PerfBudget.violations("nowhere", {"draw_calls": 99999}).size(), 0)


func test_bomb_cat_views_have_budgets():
	# 炸弹猫 6 人桌:座位与第一人称 ≤ 700 draw call(同越肩),俯视与特写同其余机位
	assert_eq(PerfBudget.LIMITS["bomb_seat"]["draw_calls"], 700)
	assert_eq(PerfBudget.LIMITS["bomb_fp"]["draw_calls"], 700)
	assert_eq(PerfBudget.LIMITS["bomb_overview"]["draw_calls"], 900)
	assert_eq(PerfBudget.LIMITS["bomb_close"]["draw_calls"], 900)
	assert_eq(PerfBudget.violations("bomb_seat", {"draw_calls": 701}).size(), 1)


func test_celebration_views_have_budgets():
	# 结算庆祝(perf_probe --celebrate):礼炮、彩纸、音符都在场时,两个环绕机位同其余机位 ≤ 900 draw call
	for view in ["celebrate", "celebrate_table"]:
		assert_eq(PerfBudget.LIMITS[view]["draw_calls"], 900, view)


func test_liars_dice_views_have_budgets():
	# 吹牛骰子 6 人桌:座位与第一人称 ≤ 700 draw call(同越肩),俯视与特写同其余机位
	assert_eq(PerfBudget.LIMITS["dice_seat"]["draw_calls"], 700)
	assert_eq(PerfBudget.LIMITS["dice_fp"]["draw_calls"], 700)
	assert_eq(PerfBudget.LIMITS["dice_overview"]["draw_calls"], 900)
	assert_eq(PerfBudget.LIMITS["dice_close"]["draw_calls"], 900)
	assert_eq(PerfBudget.violations("dice_seat", {"draw_calls": 701}).size(), 1)


func test_dou_dizhu_views_have_budgets():
	# 斗地主 3 人小桌:座位与第一人称 ≤ 700 draw call(同越肩),俯视同其余机位
	assert_eq(PerfBudget.LIMITS["ddz_seat"]["draw_calls"], 700)
	assert_eq(PerfBudget.LIMITS["ddz_fp"]["draw_calls"], 700)
	assert_eq(PerfBudget.LIMITS["ddz_overview"]["draw_calls"], 900)
