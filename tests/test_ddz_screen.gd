extends GutTest
# 斗地主牌桌控制器里不依赖 3D 的部分(屏幕不入树,只配一个 HUD,意图交给 intent_sink 记下来):
# 快捷键映射(Enter 出牌、空格 / P 不出、H 提示、R 重选,叫分 0–3;不占 T / Q / G / V / WASD / Esc / F1;
# 快捷语面板或九宫格开着时一律不抢)、多选与拖选、提示循环、按钮置灰、演出中与等回执时不能出手、托管开关。


const ScreenScript := preload("res://src/ui/dou_dizhu/dou_dizhu_screen.gd")
const H := preload("res://tests/ddz_helpers.gd")
const ME := 1


class FakeBanterView:
	extends Node
	var open := false

	func is_panel_open() -> bool:
		return open


class StubApp:
	extends Node
	var toasts: Array = []
	var banter_view: FakeBanterView

	func toast(text: String, _color := Color.WHITE) -> void:
		toasts.append(text)

	func is_modal_open() -> bool:
		return false

	func is_rules_open() -> bool:
		return false


var app: StubApp
var screen: Node
var sent: Array = []


func before_each():
	app = StubApp.new()
	add_child_autofree(app)
	app.banter_view = FakeBanterView.new()
	app.add_child(app.banter_view)
	screen = autofree(ScreenScript.new(app))
	screen.my_pid = ME
	screen.state.my_pid = ME
	screen.state.set_seats([{"pid": 1, "name": "我"}, {"pid": 2, "name": "乙"}, {"pid": 3, "name": "丙"}])
	screen.hud = DdzHud.new()
	add_child_autofree(screen.hud)
	screen.intent_sink = func(intent: Dictionary) -> void: sent.append(intent)
	sent = []


func _view(phase: String, cards: Array, overrides := {}, priv_overrides := {}) -> void:
	var pub := {"mode": GameMode.DOU_DIZHU, "hand": 1, "phase": phase, "deal": 1, "current_pid": ME, "landlord": ME if phase == "playing" else null,
		"base": 1, "multiplier": 1, "bottom": [], "lead": {}, "bids": [], "ending": false, "last_hand": {}, "results": [],
		"players": [{"pid": 1, "name": "我", "hand_count": cards.size(), "score": 0, "role": "", "trustee": false, "table": [], "passed": false},
			{"pid": 2, "name": "乙", "hand_count": 17, "score": 0, "role": "", "trustee": false, "table": [], "passed": false},
			{"pid": 3, "name": "丙", "hand_count": 17, "score": 0, "role": "", "trustee": false, "table": [], "passed": false}],
		"turn_time_left": 30.0}
	pub.merge(overrides, true)
	var priv := {"hand": 1, "cards": cards, "role": "", "trustee": false, "my_turn": pub["current_pid"] == ME, "can_pass": false,
		"bid_options": [0, 1, 2, 3] if phase == "bidding" else [], "hints": []}
	priv.merge(priv_overrides, true)
	screen.state.apply_public(pub)
	screen.state.apply_private(priv)
	screen.state.sync_from_view()
	screen.animating = false
	screen.refresh_actions()


func _play_view(cards: Array, lead := {}, hints := [], can_pass := false) -> void:
	_view("playing", cards, {"lead": lead}, {"hints": hints, "can_pass": can_pass})


# —— 快捷键 ——

func test_key_mapping_avoids_the_shared_keys():
	assert_eq(ScreenScript.key_action(KEY_ENTER), ScreenScript.ACTION_PLAY)
	assert_eq(ScreenScript.key_action(KEY_KP_ENTER), ScreenScript.ACTION_PLAY)
	assert_eq(ScreenScript.key_action(KEY_SPACE), ScreenScript.ACTION_PASS)
	assert_eq(ScreenScript.key_action(KEY_P), ScreenScript.ACTION_PASS)
	assert_eq(ScreenScript.key_action(KEY_H), ScreenScript.ACTION_HINT)
	assert_eq(ScreenScript.key_action(KEY_R), ScreenScript.ACTION_RESET)
	for key in [KEY_T, KEY_Q, KEY_G, KEY_V, KEY_W, KEY_A, KEY_S, KEY_D, KEY_ESCAPE, KEY_F1, KEY_1]:
		assert_eq(ScreenScript.key_action(key), "", "%s 不归斗地主的牌桌" % OS.get_keycode_string(key))
	assert_eq(ScreenScript.bid_key(KEY_0), 0)
	assert_eq(ScreenScript.bid_key(KEY_3), 3)
	assert_eq(ScreenScript.bid_key(KEY_KP_2), 2)
	assert_eq(ScreenScript.bid_key(KEY_4), -1)
	assert_eq(ScreenScript.bid_key(KEY_T), -1)


func test_bidding_keys_and_buttons():
	_view("bidding", H.cards("3 4 5"), {"phase": "bidding"}, {"bid_options": [0, 2, 3]})
	assert_eq(screen.hud.action_mode, DdzHud.ACTION_BID)
	assert_true(screen.hud.bid_buttons[1].disabled, "叫不了 1 分(已有人叫 1 分)")
	assert_false(screen.hud.bid_buttons[2].disabled)
	assert_false(screen.handle_key(KEY_ENTER) and not sent.is_empty(), "叫分时回车不出牌")
	sent = []
	assert_true(screen.handle_key(KEY_1), "数字键被用掉")
	assert_eq(sent, [], "叫不了的分不发")
	assert_true(screen.handle_key(KEY_2))
	assert_eq(sent, [{"kind": "bid", "score": 2}])
	screen._on_events([])
	sent = []
	screen.handle_key(KEY_SPACE)
	assert_eq(sent, [{"kind": "bid", "score": 0}], "空格 = 不叫")


func test_chat_panels_take_the_keys():
	_view("bidding", H.cards("3 4 5"))
	app.banter_view.open = true
	assert_false(screen.handle_key(KEY_1), "快捷语面板开着:数字键归面板")
	assert_false(screen.handle_key(KEY_SPACE))
	assert_eq(sent, [])
	app.banter_view.open = false
	assert_true(screen.handle_key(KEY_1))
	assert_eq(sent, [{"kind": "bid", "score": 1}])


# —— 选牌、提示、出牌 ——

func test_toggle_drag_and_reset():
	_play_view(H.cards("3 4 5 6 7 8"))
	screen.toggle_card(0)
	screen.toggle_card(2)
	assert_eq(screen.selected_indices(), [0, 2])
	screen.toggle_card(0)
	assert_eq(screen.selected_indices(), [2])
	screen.toggle_card(99)
	assert_eq(screen.selected_indices(), [2], "越界的下标不理")
	# 手牌条里大的在左:显示位置 d 对应下标 n-1-d;从显示位置 1 拖到 3 = 下标 4、3、2 全选上
	var dragged := DdzHandStrip.drag_selection(screen.selection(), 1, 3, true, 6)
	screen.set_selection(dragged)
	assert_eq(screen.selected_indices(), [2, 3, 4])
	var back := DdzHandStrip.drag_selection(dragged, 3, 2, false, 6)
	assert_eq(back.keys().size(), 1, "往回拖取消扫过的两张")
	screen.reset_selection()
	assert_eq(screen.selected_indices(), [])
	assert_eq(screen.hud.strip.ids(), screen.state.shown_hand)


func test_strip_drag_emits_selection_and_groups_ranks():
	var strip := DdzHandStrip.new()
	add_child_autofree(strip)
	var got := []
	strip.selection_changed.connect(func(sel: Dictionary): got.append(sel.keys()))
	var ids := H.cards("3 3 4 5 5 5")
	strip.set_hand(ids, {}, true)
	strip.begin_drag(0)    # 显示位置 0 = 最大的那张(下标 5)
	strip.drag_to(2)
	strip.end_drag()
	assert_eq(got.size(), 2)
	var last: Array = got[-1]
	last.sort()
	assert_eq(last, [3, 4, 5], "拖过三张 5")
	var xs := DdzHandStrip.layout_xs(ids)
	assert_gt(xs[3] - xs[2], xs[2] - xs[1], "不同点数之间多一道缝")
	assert_lte(DdzHandStrip.strip_width(range(20).map(func(i): return i * 2)), DdzHandStrip.MAX_WIDTH + 0.5, "20 张也不超宽")


func test_hint_cycles_and_play_submits_indices():
	var hints := [{"indices": [0], "type": "single"}, {"indices": [1], "type": "single"}, {"indices": [0, 1, 2, 3, 4], "type": "straight"}]
	_play_view(H.cards("3 4 5 6 7 9"), {}, hints)
	assert_eq(screen.hud.action_mode, DdzHud.ACTION_PLAY)
	assert_true(screen.hud.play_button.disabled, "没选牌不能出")
	assert_false(screen.hud.hint_button.disabled)
	assert_false(screen.hud.pass_button.visible, "自由出牌没有「不出」")
	screen.handle_key(KEY_H)
	assert_eq(screen.selected_indices(), [0])
	screen.handle_key(KEY_H)
	assert_eq(screen.selected_indices(), [1])
	screen.handle_key(KEY_H)
	assert_eq(screen.selected_indices(), [0, 1, 2, 3, 4])
	assert_false(screen.hud.play_button.disabled)
	screen.handle_key(KEY_H)
	assert_eq(screen.selected_indices(), [0], "循环回第一个")
	screen.handle_key(KEY_R)
	assert_eq(screen.selected_indices(), [])
	screen.toggle_card(0)
	screen.toggle_card(5)
	assert_true(screen.hud.play_button.disabled, "3 和 9 不成牌型")
	assert_false(screen.submit_play())
	assert_true(app.toasts.has("不成牌型"))
	screen.reset_selection()
	for i in 5:
		screen.toggle_card(i)
	assert_true(screen.handle_key(KEY_ENTER))
	assert_eq(sent, [{"kind": "play", "cards": [0, 1, 2, 3, 4]}])
	assert_false(screen.is_my_turn(), "等回执期间不能再出")
	assert_false(screen.submit_play())
	assert_eq(sent.size(), 1)


func test_follow_pass_and_no_hint():
	var lead := {"pid": 2, "type": DdzHand.PAIR, "rank": 10, "length": 1, "count": 2}
	_play_view(H.cards("3 4 9 9"), lead, [], true)
	assert_true(screen.hud.pass_button.visible, "有上家可以不出")
	assert_true(screen.hud.hint_button.disabled, "没有能压过的")
	assert_false(screen.cycle_hint())
	assert_true(app.toasts.back().begins_with("没有能压过"))
	screen.toggle_card(2)
	screen.toggle_card(3)
	assert_true(screen.hud.play_button.disabled, "一对 9 压不过一对 K")
	assert_true(screen.handle_key(KEY_P))
	assert_eq(sent, [{"kind": "pass"}])


func test_no_actions_while_animating_or_not_my_turn():
	_play_view(H.cards("3 4 5"), {}, [{"indices": [0], "type": "single"}])
	screen.animating = true
	screen.refresh_actions()
	assert_false(screen.is_my_turn())
	assert_false(screen.submit_play())
	assert_eq(screen.hud.action_mode, DdzHud.ACTION_NONE)
	screen.animating = false
	_view("playing", H.cards("3 4 5"), {"current_pid": 2}, {"my_turn": false})
	assert_false(screen.is_my_turn())
	screen.toggle_card(1)
	assert_eq(screen.selected_indices(), [1], "不是自己时也能先选牌")
	assert_eq(screen.hud.turn_label(), "等待 乙 出牌…")


func test_trustee_toggle_and_rejection():
	_play_view(H.cards("3 4 5"))
	assert_true(screen.toggle_trustee())
	assert_eq(sent, [{"kind": "trustee", "on": true}])
	assert_false(screen.toggle_trustee(), "等回执期间不重复发")
	screen._on_rejected(DdzState.ERR_NOT_YOUR_TURN)
	assert_eq(app.toasts.back(), DdzState.ERROR_MESSAGES[DdzState.ERR_NOT_YOUR_TURN], "被拒 toast 中文")
	_play_view(H.cards("3 4 5"), {}, [], false)
	screen.state.priv["trustee"] = true
	assert_true(screen.toggle_trustee())
	assert_eq(sent.back(), {"kind": "trustee", "on": false}, "托管中再点就是取消")
