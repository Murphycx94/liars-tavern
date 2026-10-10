extends GutTest
# 吹牛骰子 HUD 与出价器:置灰规则与 LiarsDiceState.bid_error 逐格一致、默认值是 min_raise、↑↓ / 点数的调整、
# HUD 按钮与信号、自己的 2D 骰子、开盅面板、左上信息文案;牌桌的快捷键映射(不占 T / Q / G / V / WASD / Esc / F1);
# 结算面板的名次文案。


const ScreenScript := preload("res://src/ui/liars_dice/liars_dice_screen.gd")

var hud: LiarsDiceHud


func before_each():
	hud = LiarsDiceHud.new()
	add_child_autofree(hud)


func _totals() -> Array:
	return [2, 5, 15, 30]


func _bids() -> Array:
	return [{}, {"pid": 1, "count": 1, "face": 2}, {"pid": 1, "count": 3, "face": 5}, {"pid": 1, "count": 4, "face": 6},
		{"pid": 1, "count": 5, "face": 6}]


func test_face_greying_matches_the_rule_engine_everywhere():
	var picker := LiarsDicePicker.new()
	for total in _totals():
		for bid in _bids():
			if not bid.is_empty() and bid["count"] > total:
				continue
			for count in range(1, total + 2):
				picker.count = count
				for face in range(2, 7):
					assert_eq(picker.face_legal(face, bid, total), LiarsDiceState.bid_error(count, face, bid, total) == "",
						"%d 个 %d · 上一口 %s · 总数 %d" % [count, face, bid, total])


func test_default_is_the_minimum_raise():
	var picker := LiarsDicePicker.new()
	for total in _totals():
		for bid in _bids():
			if not bid.is_empty() and bid["count"] > total:
				continue
			picker.reset(bid, total)
			var raise := LiarsDiceState.min_raise(bid, total)
			if raise.is_empty():
				assert_eq([picker.count, picker.face], [bid["count"], bid["face"]], "加不上去:停在当前这一口")
				assert_false(picker.is_legal(bid, total))
			else:
				assert_eq([picker.count, picker.face], [raise["count"], raise["face"]])
				assert_true(picker.is_legal(bid, total))


func test_nudge_stays_in_range_and_fixes_the_face():
	var picker := LiarsDicePicker.new()
	var bid := {"pid": 2, "count": 3, "face": 5}
	picker.reset(bid, 10)
	assert_eq([picker.count, picker.face], [3, 6])
	assert_false(picker.can_dec(bid, 10), "3 个以下没有合法的点数")
	assert_false(picker.nudge(-1, bid, 10))
	assert_true(picker.nudge(1, bid, 10))
	assert_eq(picker.count, 4)
	picker.pick_face(2, bid, 10)
	assert_true(picker.is_legal(bid, 10), "4 个 2 合法")
	assert_true(picker.nudge(-1, bid, 10))
	assert_eq([picker.count, picker.face], [3, 6], "回到 3 个:2 不合法了,换成这个个数下最小的合法点数")
	for i in 20:
		picker.nudge(1, bid, 10)
	assert_eq(picker.count, 10, "不超过场上总数")
	assert_false(picker.can_inc(bid, 10))


func test_pick_face_raises_the_count_when_needed():
	var picker := LiarsDicePicker.new()
	var bid := {"pid": 2, "count": 3, "face": 5}
	picker.reset(bid, 10)
	assert_true(picker.pick_face(4, bid, 10))
	assert_eq([picker.count, picker.face], [4, 4], "3 个 4 不行:个数抬到 4")
	assert_false(picker.pick_face(1, bid, 10), "1 点万能不能喊")
	assert_false(picker.pick_face(7, bid, 10))


func test_hud_greys_illegal_faces_and_buttons():
	var face_ok := {2: false, 3: false, 4: false, 5: true, 6: true}
	hud.set_picker(3, 5, face_ok, false, true, true, true, true)
	assert_true(hud.face_buttons[2].disabled)
	assert_false(hud.face_buttons[5].disabled)
	assert_true(hud.face_icons[5].highlight, "选中的点数高亮")
	assert_true(hud.face_icons[3].dim, "不合法的褪色")
	assert_true(hud.minus_button.disabled)
	assert_false(hud.plus_button.disabled)
	assert_eq(hud.bid_button.text, "加注 3 个 5")
	assert_false(hud.bid_button.disabled)
	assert_false(hud.challenge_button.disabled)
	hud.set_picker(1, 2, {2: true, 3: true, 4: true, 5: true, 6: true}, false, true, false, false, false)
	assert_true(hud.bid_button.disabled, "不是自己的回合:加注不亮")
	assert_true(hud.challenge_button.disabled, "还没人喊 / 不是自己的回合:开! 不亮")
	for f in hud.face_buttons:
		assert_eq(hud.face_buttons[f].focus_mode, Control.FOCUS_NONE, "按钮不抢焦点(空格 / 回车留给牌桌)")


func test_hud_buttons_emit_signals():
	var got := []
	hud.count_nudged.connect(func(d): got.append(["count", d]))
	hud.face_picked.connect(func(f): got.append(["face", f]))
	hud.bid_pressed.connect(func(): got.append(["bid"]))
	hud.challenge_pressed.connect(func(): got.append(["challenge"]))
	hud.set_picker(3, 5, {2: true, 3: true, 4: true, 5: true, 6: true}, true, true, true, true, true)
	hud.plus_button.pressed.emit()
	hud.minus_button.pressed.emit()
	hud.face_buttons[4].pressed.emit()
	hud.bid_button.pressed.emit()
	hud.challenge_button.pressed.emit()
	assert_eq(got, [["count", 1], ["count", -1], ["face", 4], ["bid"], ["challenge"]])


func test_my_dice_and_reveal_panel():
	hud.set_my_dice([1, 3, 5, 5, 6], true)
	assert_eq(hud.my_dice_values(), [1, 3, 5, 5, 6])
	hud.set_my_dice([1, 3, 5, 5, 6], true, 5)
	var lit := hud.my_dice_icons.filter(func(icon: DiceIcon) -> bool: return icon.highlight)
	assert_eq(lit.size(), 3, "开盅数「5」:1 点和两颗 5 高亮")
	hud.set_my_dice([], false)
	assert_eq(hud.my_dice_values(), [], "出局后没有骰子")
	hud.show_reveal([{"name": "你", "dice": [1, 5]}, {"name": "阿狸", "dice": [2, 5, 6]}], 5, 4)
	assert_true(hud.is_reveal_open())
	hud.reveal_mark(0, 0)
	hud.reveal_mark(1, 1)
	hud.set_reveal_count(2, 4)
	assert_eq(hud.reveal_marked(), 2)
	assert_eq(hud.reveal_counter_text(), "数到 2 / 喊了 4")
	hud.reveal_mark(9, 9)   # 越界不报错
	hud.set_away_from_seat(true)
	assert_false(hud.is_reveal_open(), "镜头去环绕时收起")


func test_info_texts():
	assert_eq(LiarsDiceHud.bid_line({}, "", false), "这一轮还没人喊")
	assert_eq(LiarsDiceHud.bid_line({"pid": 2, "count": 3, "face": 5}, "阿狸", false), "阿狸 喊 3 个 5")
	assert_eq(LiarsDiceHud.bid_line({"pid": 1, "count": 3, "face": 5}, "我", true), "你 喊 3 个 5")
	var bids := []
	for c in range(1, 7):
		bids.append({"count": c, "face": 2})
	assert_eq(LiarsDiceHud.bids_line(bids.slice(0, 2)), "1 个 2 → 2 个 2")
	assert_true(LiarsDiceHud.bids_line(bids).begins_with("… → 3 个 2"), "只列最近几口")
	assert_eq(LiarsDiceHud.turn_info_text("", false, false), "")
	assert_eq(LiarsDiceHud.turn_info_text("阿狸", false, true), "轮到 阿狸")
	assert_string_contains(LiarsDiceHud.turn_info_text("我", true, true), "开")
	hud.set_info(18, {"pid": 2, "count": 3, "face": 5}, "阿狸 喊 3 个 5", "", "轮到 小熊", "你:5 颗骰子")
	assert_string_contains(hud.info_text(), "场上 18 颗骰子")


func test_key_mapping():
	assert_eq(ScreenScript.key_action(KEY_ENTER), ScreenScript.ACTION_BID)
	assert_eq(ScreenScript.key_action(KEY_KP_ENTER), ScreenScript.ACTION_BID)
	assert_eq(ScreenScript.key_action(KEY_C), ScreenScript.ACTION_CHALLENGE)
	assert_eq(ScreenScript.key_action(KEY_SPACE), ScreenScript.ACTION_CHALLENGE)
	assert_eq(ScreenScript.key_action(KEY_UP), ScreenScript.ACTION_MORE)
	assert_eq(ScreenScript.key_action(KEY_DOWN), ScreenScript.ACTION_LESS)
	for f in range(2, 7):
		assert_eq(ScreenScript.face_key(KEY_0 + f), f)
		assert_eq(ScreenScript.face_key(KEY_KP_0 + f), f)
	assert_eq(ScreenScript.face_key(KEY_1), -1, "1 点不能喊:1 键不选点数")
	for key in [KEY_T, KEY_Q, KEY_G, KEY_V, KEY_W, KEY_A, KEY_S, KEY_D, KEY_ESCAPE, KEY_F1]:
		assert_eq(ScreenScript.key_action(key), "", "不占 %s" % OS.get_keycode_string(key))
		assert_eq(ScreenScript.face_key(key), -1)


func test_settlement_rows():
	var rows := [{"pid": 2, "name": "阿狸", "place": 1, "fate": "winner", "dice": 3},
		{"pid": 1, "name": "我", "place": 2, "fate": "out", "dice": 0},
		{"pid": 3, "name": "小熊", "place": 3, "fate": "left", "dice": 0}]
	assert_eq(LiarsDiceSettlement.fate_text(rows[0]), "还剩 3 颗骰子")
	assert_eq(LiarsDiceSettlement.fate_text(rows[1]), "骰子输光")
	assert_eq(LiarsDiceSettlement.fate_text(rows[2]), "断线离开")
	var panel := LiarsDiceSettlement.new("阿狸", rows, false, true)
	add_child_autofree(panel)
	assert_eq(panel.rows(), rows)
	assert_eq(panel.default_button().text, "再来一局", "房主的默认按钮")
	var lines := panel.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_has(lines, "骰子留到最后的人")
	assert_has(lines, "第 3 名")
