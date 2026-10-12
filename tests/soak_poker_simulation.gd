extends GutTest
# 德州随机模拟的长时间浸泡(规格 §8):文件名不以 test_ 开头,全量测试(-gdir)不会跑它,只在命令行点名时跑:
#   $GODOT --headless --fixed-fps 60 --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/soak_poker_simulation.gd -gexit
# 40 个种子 × 2000 手,约一分钟。

const Sim := preload("res://tests/poker_sim.gd")
const SEEDS := 40
const FIRST_SEED := 1000
const HANDS_PER_SEED := 2000


func test_long_random_soak_keeps_every_invariant():
	for i in SEEDS:
		var error: String = Sim.new(FIRST_SEED + i, i).run(HANDS_PER_SEED)
		assert_eq(error, "", "浸泡出错")
		if error != "":
			return
