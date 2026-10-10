class_name DdzBot
extends RefCounted
# 斗地主的机器人(调试开关 --bot 与无头流程测试共用):每次 act() 走一步,只通过牌桌的公开入口出手
# (submit_bid / cycle_hint / toggle_card / submit_play / submit_pass),和真人点按钮、按快捷键是同一条路径。
# 叫分随机(多半不叫,偶尔叫个比现在高的分);出牌按「提示」:多半出第一个提示(最小的能出的组合),
# 偶尔多按几下提示挑后面的;能不出时偶尔不出;偶尔先点几张牌再重选,走一遍点选的路径。


const BID_CHANCE := 0.4        # 能叫分时叫分(而不是不叫)的概率
const PASS_CHANCE := 0.2       # 能不出时不出的概率
const LATER_HINT_CHANCE := 0.15
const FIDDLE_CHANCE := 0.1     # 先随手点一张牌再重选

var rng := RandomNumberGenerator.new()


func _init(seed_value := 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func act(screen: Node) -> bool:
	# 走一步;这一刻没什么可做时返回 false
	if screen.settlement() != null:
		return false
	var state: DdzScreenState = screen.state
	if screen.is_bidding_turn():
		var options := state.bid_options()
		var raise := options.filter(func(s: int) -> bool: return s > 0)
		if not raise.is_empty() and rng.randf() < BID_CHANCE:
			return screen.submit_bid(raise[rng.randi_range(0, raise.size() - 1)])
		return screen.submit_bid(0)
	if not screen.is_playing_turn():
		return false
	if state.can_pass() and rng.randf() < PASS_CHANCE:
		return screen.submit_pass()
	if rng.randf() < FIDDLE_CHANCE and not state.shown_hand.is_empty():
		screen.toggle_card(rng.randi_range(0, state.shown_hand.size() - 1))
		screen.reset_selection()
	var hints := state.hints()
	if hints.is_empty():
		return screen.submit_pass()
	var presses := 1
	if rng.randf() < LATER_HINT_CHANCE:
		presses += rng.randi_range(1, mini(hints.size() - 1, 3))
	for i in presses:
		screen.cycle_hint()
	if screen.submit_play():
		return true
	return state.can_pass() and screen.submit_pass()
