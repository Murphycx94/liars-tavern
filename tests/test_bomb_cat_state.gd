extends GutTest
# 炸弹猫规则引擎(设计稿 §1、§5):开局、每张牌的效果、甩锅叠加、「不行!」奇偶与窗口、炸弹拆弹与塞回、
# 零食组合、讨要、出局与胜负、断线与超时代打、公共事件不漏隐藏信息。局面用 H.rig 摆好再动手。


const H := preload("res://tests/bomb_cat_helpers.gd")
const C := preload("res://src/core/bomb_cat/bomb_cat_card.gd")
const S := BombCatState.Step

var s: BombCatState


func before_each():
	s = H.new_state([1, 2, 3])


func after_each():
	# 每个用例结束时:牌数守恒、公共事件检查在各自用例里做
	if s != null:
		assert_eq(s.card_count(), s.total_cards, "牌数守恒")


func _ok(result: Dictionary) -> Array:
	assert_true(result["ok"], "应当成功:%s" % str(result.get("error", "")))
	for ev in result["events"]:
		assert_eq(H.event_leak(ev), "", str(ev))
	return result["events"]


func _err(result: Dictionary, code: String, note := "") -> void:
	assert_false(result["ok"], note)
	assert_eq(result.get("error"), code, note)
	assert_eq(result["events"], [], "被拒没有事件")


func _play_and_resolve(pid: int, indices: Array, target = null, named = "") -> Array:
	var events := _ok(s.play(pid, indices, target, named))
	return events + _ok(s.resolve_window())


# —— 开局 ——

func test_start_deals_and_opens_the_first_turn():
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var fresh := BombCatState.new()
	var events: Array = fresh.start([5, 6, 7, 8], rng)["events"]
	assert_eq(events.size(), 1)
	var ev: Dictionary = events[0]
	assert_eq(H.event_leak(ev), "")
	assert_eq(ev["type"], "round_started")
	assert_eq(ev["seats"], [5, 6, 7, 8])
	assert_eq(ev["hands"], [{"pid": 5, "count": 5}, {"pid": 6, "count": 5}, {"pid": 7, "count": 5}, {"pid": 8, "count": 5}])
	assert_eq(ev["deck_count"], fresh.deck.size())
	assert_eq(ev["bombs"], 3)
	assert_true([5, 6, 7, 8].has(ev["current"]))
	assert_eq(ev["turns"], 1)
	assert_eq(fresh.step, S.TURN)
	assert_eq(fresh.card_count(), BombCatDeck.total_cards(4))
	assert_eq(fresh.bombs_left(), 3)


func test_start_rejects_player_counts_outside_two_to_six():
	for pids in [[1], [1, 2, 3, 4, 5, 6, 7]]:
		var fresh := BombCatState.new()
		var result := fresh.start(pids, RandomNumberGenerator.new())
		assert_eq(result["error"], BombCatState.ERR_INVALID_PLAYERS)
		assert_eq(fresh.step, S.OVER)


# —— 出牌与窗口 ——

func test_play_opens_a_window_and_blocks_the_actor():
	H.rig(s, {1: [C.SKIP, C.PEEK], 2: [C.NOPE]}, [C.SHUFFLE, C.BEG], 1)
	var events := _ok(s.play(1, [0]))
	assert_eq(events, [{"type": "played", "pid": 1, "cards": [C.SKIP], "kind": C.SKIP, "target": null, "named": "",
		"window": BombCatState.REACT_WINDOW}])
	assert_eq(s.step, S.WINDOW)
	assert_eq(s.discard_top, C.SKIP)
	assert_eq(s.hands[1], [C.PEEK])
	_err(s.play(1, [0]), BombCatState.ERR_BUSY, "窗口里不能再出牌")
	_err(s.draw(1), BombCatState.ERR_BUSY, "窗口里不能摸牌")
	_err(s.draw(2), BombCatState.ERR_NOT_YOUR_TURN)


func test_skip_ends_the_turn_without_drawing():
	H.rig(s, {1: [C.SKIP]}, [C.SHUFFLE], 1)
	var events := _play_and_resolve(1, [0])
	assert_eq(H.types(events), ["played", "window_resolved", "effect", "turn_passed"])
	assert_true(H.find(events, "window_resolved")["effective"])
	assert_eq(H.find(events, "effect"), {"type": "effect", "kind": C.SKIP, "pid": 1})
	assert_eq(H.find(events, "turn_passed"), {"type": "turn_passed", "pid": 2, "turns": 1})
	assert_eq(s.deck.size(), 1, "没摸牌")


func test_skip_under_attack_only_cancels_one_turn():
	H.rig(s, {1: [C.SKIP]}, [C.SHUFFLE], 1, 2)
	s.under_attack = true
	var events := _play_and_resolve(1, [0])
	assert_eq(H.find(events, "turn_passed"), {"type": "turn_passed", "pid": 1, "turns": 1}, "还要再走一回合")
	assert_true(s.under_attack)


func test_pass_turns_gives_the_next_player_two_turns():
	H.rig(s, {1: [C.PASS_TURNS]}, [C.SHUFFLE, C.BEG, C.PEEK], 1)
	var events := _play_and_resolve(1, [0])
	assert_eq(H.find(events, "effect"), {"type": "effect", "kind": C.PASS_TURNS, "pid": 1, "to": 2, "turns": 2})
	assert_eq(H.find(events, "turn_passed"), {"type": "turn_passed", "pid": 2, "turns": 2})
	assert_eq([s.current_pid, s.turns_left, s.under_attack], [2, 2, true])
	# 被甩的人摸两次才轮到下家,下家只有 1 回合、不算被甩
	assert_eq(H.find(_ok(s.draw(2)), "turn_passed"), {"type": "turn_passed", "pid": 2, "turns": 1})
	assert_eq(H.find(_ok(s.draw(2)), "turn_passed"), {"type": "turn_passed", "pid": 3, "turns": 1})
	assert_false(s.under_attack)


func test_pass_turns_while_under_attack_stacks_remaining_plus_two():
	H.rig(s, {1: [C.PASS_TURNS], 2: [C.PASS_TURNS], 3: [C.PASS_TURNS]}, [C.SHUFFLE, C.BEG, C.PEEK], 1)
	_play_and_resolve(1, [0])
	# 2 号被甩 2 回合,第一回合就再甩:3 号要走 2 + 2 = 4 回合
	var events := _play_and_resolve(2, [0])
	assert_eq(H.find(events, "turn_passed"), {"type": "turn_passed", "pid": 3, "turns": 4})
	# 3 号先摸一张(剩 3 回合)再甩:1 号要走 3 + 2 = 5 回合
	_ok(s.draw(3))
	events = _play_and_resolve(3, [0])
	assert_eq(H.find(events, "effect")["turns"], 5)
	assert_eq([s.current_pid, s.turns_left], [1, 5])


func test_pass_turns_on_the_last_stacked_turn_still_counts_as_under_attack():
	H.rig(s, {2: [C.PASS_TURNS]}, [C.SHUFFLE, C.BEG], 2, 2)
	s.under_attack = true
	_ok(s.draw(2))
	var events := _play_and_resolve(2, [0])
	assert_eq(H.find(events, "turn_passed"), {"type": "turn_passed", "pid": 3, "turns": 3}, "剩 1 回合 + 2")


func test_peek_shows_the_top_three_only_to_the_player():
	H.rig(s, {1: [C.PEEK]}, [C.BOMB, C.SKIP, C.BEG, C.NOPE], 1)
	var events := _play_and_resolve(1, [0])
	assert_eq(H.find(events, "effect"), {"type": "effect", "kind": C.PEEK, "pid": 1, "count": 3})
	assert_eq(s.peek_of(1)["cards"], [C.BOMB, C.SKIP, C.BEG])
	assert_eq(s.peek_of(2), {})
	assert_eq(s.current_pid, 1, "偷看不结束回合")
	assert_eq(s.step, S.TURN)
	s.draw(1)
	assert_eq(s.peek_of(1), {}, "牌堆一变偷看结果作废")


func test_peek_with_a_short_deck_sees_what_is_there():
	H.rig(s, {1: [C.PEEK]}, [C.BOMB], 1)
	var events := _play_and_resolve(1, [0])
	assert_eq(H.find(events, "effect")["count"], 1)
	assert_eq(s.peek_of(1)["cards"], [C.BOMB])


func test_shuffle_reorders_the_deck_and_voids_peeks():
	var deck := [C.BOMB, C.SKIP, C.BEG, C.NOPE, C.PEEK, C.SHUFFLE, C.DEFUSE, C.SNACK_FISH]
	H.rig(s, {1: [C.PEEK, C.SHUFFLE]}, deck, 1)
	_play_and_resolve(1, [0])
	var events := _play_and_resolve(1, [0])
	assert_eq(H.find(events, "effect"), {"type": "effect", "kind": C.SHUFFLE, "pid": 1})
	assert_eq(s.peek_of(1), {})
	var after := s.deck.duplicate()
	assert_ne(after, deck, "这个种子下顺序变了")
	after.sort()
	deck.sort()
	assert_eq(after, deck)


# —— 讨要 ——

func test_beg_asks_the_target_to_pick_a_card():
	H.rig(s, {1: [C.BEG], 2: [C.SKIP, C.DEFUSE]}, [C.SHUFFLE], 1)
	var events := _play_and_resolve(1, [0], 2)
	assert_eq(H.find(events, "played")["target"], 2)
	assert_eq(H.find(events, "give_requested"), {"type": "give_requested", "pid": 2, "to": 1, "timeout": BombCatState.GIVE_TIMEOUT})
	assert_eq(s.step, S.GIVE)
	assert_eq(s.give_info(2), {"to": 1})
	assert_eq(s.give_info(1), {})
	_err(s.draw(1), BombCatState.ERR_BUSY, "等给牌时讨要的人也不能动")
	_err(s.give(1, 0), BombCatState.ERR_NOT_WAITING)
	_err(s.give(3, 0), BombCatState.ERR_NOT_WAITING)
	_err(s.give(2, 2), BombCatState.ERR_INVALID_INDEX)
	_err(s.give(2, "0"), BombCatState.ERR_INVALID_INDEX)
	events = _ok(s.give(2, 1))
	assert_eq(events, [{"type": "effect", "kind": C.BEG, "pid": 1, "from": 2, "to": 1, "got": true}])
	assert_eq(s.hands[1], [C.DEFUSE])
	assert_eq(s.hands[2], [C.SKIP])
	assert_eq(s.transfer_of(1)["card"], C.DEFUSE)
	assert_eq([s.transfer_of(2)["from"], s.transfer_of(2)["to"]], [2, 1])
	assert_eq(s.transfer_of(3), {})
	assert_eq([s.step, s.current_pid], [S.TURN, 1], "给完回到讨要者的回合")


func test_beg_timeout_gives_a_random_card():
	H.rig(s, {1: [C.BEG], 2: [C.SNACK_YARN]}, [C.SHUFFLE], 1)
	_play_and_resolve(1, [0], 2)
	var events := _ok(s.timeout())
	assert_eq(H.find(events, "effect")["got"], true)
	assert_eq(s.hands[1], [C.SNACK_YARN])


func test_targeted_plays_validate_the_target():
	H.rig(s, {1: [C.BEG, C.SNACK_FISH, C.SNACK_FISH], 2: [C.SKIP], 3: []}, [C.SHUFFLE], 1)
	_err(s.play(1, [0]), BombCatState.ERR_INVALID_TARGET, "缺目标")
	_err(s.play(1, [0], 1), BombCatState.ERR_INVALID_TARGET, "不能讨自己")
	_err(s.play(1, [0], 99), BombCatState.ERR_INVALID_TARGET, "不在局里")
	_err(s.play(1, [0], "2"), BombCatState.ERR_INVALID_TARGET, "类型不对")
	_err(s.play(1, [0], 3), BombCatState.ERR_TARGET_EMPTY, "他没牌")
	_err(s.play(1, [1, 2], 3), BombCatState.ERR_TARGET_EMPTY)
	s.alive[2] = false
	_err(s.play(1, [0], 2), BombCatState.ERR_INVALID_TARGET, "死人不能选")
	s.alive[2] = true
	assert_eq(s.hands[1].size(), 3, "被拒不动手牌")


func test_beg_fizzles_when_the_target_empties_during_the_window():
	H.rig(s, {1: [C.BEG], 2: [C.NOPE], 3: [C.NOPE]}, [C.SHUFFLE], 1)
	_ok(s.play(1, [0], 2))
	_ok(s.nope(2))   # 2 号打出最后一张
	_ok(s.nope(3))   # 不行掉不行:讨要生效,可 2 号已经没牌
	var events := _ok(s.resolve_window())
	assert_eq(H.find(events, "effect"), {"type": "effect", "kind": C.BEG, "pid": 1, "from": 2, "to": 1, "got": false})
	assert_eq(s.step, S.TURN)


# —— 零食 ——

func test_snack_pair_steals_a_random_card():
	H.rig(s, {1: [C.SNACK_CACTUS, C.SKIP, C.SNACK_CACTUS], 3: [C.DEFUSE]}, [C.SHUFFLE], 1)
	var events := _play_and_resolve(1, [0, 2], 3)
	assert_eq(H.find(events, "played")["kind"], BombCatState.KIND_PAIR)
	assert_eq(H.find(events, "played")["cards"], [C.SNACK_CACTUS, C.SNACK_CACTUS])
	assert_eq(H.find(events, "effect"), {"type": "effect", "kind": "steal", "pid": 1, "from": 3, "to": 1, "got": true})
	assert_eq(s.hands[1], [C.SKIP, C.DEFUSE])
	assert_eq(s.hands[3], [])
	assert_eq(s.transfer_of(3)["card"], C.DEFUSE, "被抽的人知道丢了哪张")


func test_snack_triple_names_a_card():
	H.rig(s, {1: [C.SNACK_FISH, C.SNACK_FISH, C.SNACK_FISH, C.SNACK_BANANA, C.SNACK_BANANA, C.SNACK_BANANA],
		2: [C.SKIP, C.DEFUSE]}, [C.SHUFFLE], 1)
	var events := _play_and_resolve(1, [0, 1, 2], 2, C.DEFUSE)
	assert_eq(H.find(events, "played")["named"], C.DEFUSE)
	assert_eq(H.find(events, "effect"), {"type": "effect", "kind": "request", "pid": 1, "from": 2, "to": 1, "named": C.DEFUSE, "got": true})
	assert_eq(s.hands[2], [C.SKIP])
	events = _play_and_resolve(1, [0, 1, 2], 2, C.NOPE)
	assert_eq(H.find(events, "effect")["got"], false, "他没有就落空")
	assert_eq(s.hands[2], [C.SKIP])


func test_snack_triple_needs_a_nameable_card():
	H.rig(s, {1: [C.SNACK_FISH, C.SNACK_FISH, C.SNACK_FISH], 2: [C.SKIP]}, [C.SHUFFLE], 1)
	for named in ["", C.BOMB, "bogus", 3, null]:
		_err(s.play(1, [0, 1, 2], 2, named), BombCatState.ERR_INVALID_NAMED, str(named))


func test_illegal_combinations_are_rejected():
	H.rig(s, {1: [C.SNACK_FISH, C.SNACK_YARN, C.SKIP, C.SKIP, C.NOPE, C.DEFUSE, C.SNACK_FISH, C.SNACK_FISH, C.SNACK_FISH]},
		[C.SHUFFLE], 1)
	for indices in [[0, 1], [2, 3], [4], [5], [0], [0, 6, 7, 8], [], [0, 0], [99], [-1], ["0"], [0.0], "0", null, {}]:
		_err(s.play(1, indices, 2, C.SKIP), BombCatState.ERR_INVALID_PLAY, str(indices))
	assert_eq(s.hands[1].size(), 9)


# —— 「不行!」 ——

func test_one_nope_cancels_and_two_nopes_restore():
	H.rig(s, {1: [C.SKIP, C.SKIP], 2: [C.NOPE, C.NOPE], 3: [C.NOPE]}, [C.SHUFFLE, C.BEG], 1)
	_ok(s.play(1, [0]))
	var events := _ok(s.nope(2))
	assert_eq(events, [{"type": "noped", "pid": 2, "depth": 1, "window": BombCatState.REACT_WINDOW}])
	assert_eq(s.discard_top, C.NOPE)
	events = _ok(s.resolve_window())
	assert_eq(events, [{"type": "window_resolved", "pid": 1, "kind": C.SKIP, "effective": false, "nopes": 1, "aborted": false}])
	assert_eq([s.current_pid, s.step], [1, S.TURN], "溜了被取消,还是自己的回合")
	_ok(s.play(1, [0]))
	_ok(s.nope(2))
	assert_eq(_ok(s.nope(3))[0]["depth"], 2, "可以不行掉不行")
	events = _ok(s.resolve_window())
	assert_true(events[0]["effective"])
	assert_eq(s.current_pid, 2)


func test_the_player_can_nope_a_nope_against_himself():
	H.rig(s, {1: [C.SKIP, C.NOPE], 2: [C.NOPE]}, [C.SHUFFLE], 1)
	_ok(s.play(1, [0]))
	_ok(s.nope(2))
	_ok(s.nope(1))
	assert_true(_ok(s.resolve_window())[0]["effective"])


func test_nope_by_index_and_errors():
	H.rig(s, {1: [C.SKIP], 2: [C.SKIP, C.NOPE], 3: [C.SKIP]}, [C.SHUFFLE], 1)
	_err(s.nope(2), BombCatState.ERR_NO_WINDOW, "窗口外不能打")
	_ok(s.play(1, [0]))
	_err(s.nope(3), BombCatState.ERR_NO_NOPE)
	_err(s.nope(2, 0), BombCatState.ERR_NO_NOPE, "指定的那张不是不行")
	_err(s.nope(2, 5), BombCatState.ERR_INVALID_INDEX)
	_err(s.nope(2, "1"), BombCatState.ERR_INVALID_INDEX)
	_err(s.nope(42), BombCatState.ERR_NOT_SEATED)
	s.alive[3] = false
	_err(s.nope(3), BombCatState.ERR_OUT)
	s.alive[3] = true
	_ok(s.nope(2, 1))
	assert_eq(s.hands[2], [C.SKIP])
	assert_eq(s.window["nopes"], 1)


func test_resolve_outside_a_window_is_an_error():
	_err(s.resolve_window(), BombCatState.ERR_NO_WINDOW)


# —— 摸牌与炸弹 ——

func test_draw_takes_the_top_card_and_ends_the_turn():
	H.rig(s, {1: []}, [C.SKIP, C.BEG], 1)
	var events := _ok(s.draw(1))
	assert_eq(events, [{"type": "drew", "pid": 1, "deck_count": 1, "bomb": false},
		{"type": "turn_passed", "pid": 2, "turns": 1}])
	assert_eq(s.hands[1], [C.SKIP])
	assert_eq(s.last_drawn_of(1)["card"], C.SKIP)
	assert_eq(s.last_drawn_of(2), {})
	_err(s.draw(1), BombCatState.ERR_NOT_YOUR_TURN)


func test_bomb_with_defuse_goes_back_where_the_player_wants():
	H.rig(s, {1: [C.SKIP, C.DEFUSE]}, [C.BOMB, C.BEG, C.PEEK, C.NOPE], 1)
	var events := _ok(s.draw(1))
	assert_eq(H.types(events), ["drew", "bomb_drawn", "defused"])
	assert_true(events[0]["bomb"])
	assert_eq(H.find(events, "defused"), {"type": "defused", "pid": 1, "deck_count": 3, "timeout": BombCatState.REINSERT_TIMEOUT})
	assert_eq(s.step, S.REINSERT)
	assert_eq(s.hands[1], [C.SKIP], "拆弹自动用掉")
	assert_eq(s.discard_top, C.DEFUSE)
	assert_eq(s.held_bomb, C.BOMB)
	assert_eq(s.reinsert_info(1), {"deck_count": 3})
	assert_eq(s.reinsert_info(2), {})
	_err(s.reinsert(2, 0), BombCatState.ERR_NOT_WAITING)
	for pos in [-1, 4, "0", 1.0, null]:
		_err(s.reinsert(1, pos), BombCatState.ERR_INVALID_POS, str(pos))
	_err(s.draw(1), BombCatState.ERR_BUSY)
	events = _ok(s.reinsert(1, 0))
	assert_eq(events, [{"type": "reinserted", "pid": 1, "deck_count": 4}, {"type": "turn_passed", "pid": 2, "turns": 1}])
	assert_eq(s.deck[0], C.BOMB, "0 = 顶")
	assert_eq(s.held_bomb, "")
	assert_eq(s.bombs_left(), 2)


func test_reinsert_at_the_bottom():
	H.rig(s, {1: [C.DEFUSE]}, [C.BOMB, C.BEG, C.PEEK], 1)
	_ok(s.draw(1))
	_ok(s.reinsert(1, 2))
	assert_eq(s.deck, [C.BEG, C.PEEK, C.BOMB], "牌堆张数 = 底")


func test_reinsert_timeout_puts_the_bomb_somewhere():
	H.rig(s, {1: [C.DEFUSE]}, [C.BOMB, C.BEG, C.PEEK], 1)
	_ok(s.draw(1))
	var events := _ok(s.timeout())
	assert_eq(H.types(events), ["reinserted", "turn_passed"])
	assert_true(s.deck.has(C.BOMB))
	assert_eq(s.deck.size(), 3)


func test_bomb_without_defuse_explodes_and_leaves_the_game():
	H.rig(s, {1: [C.SKIP, C.NOPE], 2: [C.BEG]}, [C.BOMB, C.PEEK], 1)
	var events := _ok(s.draw(1))
	assert_eq(H.types(events), ["drew", "bomb_drawn", "exploded", "turn_passed"])
	assert_eq(H.find(events, "exploded"), {"type": "exploded", "pid": 1, "discarded": 2})
	assert_eq(H.find(events, "turn_passed")["pid"], 2)
	assert_false(s.is_alive(1))
	assert_eq(s.hands[1], [])
	assert_eq(s.removed, [C.BOMB], "炸弹移出游戏,不再塞回")
	assert_false(s.deck.has(C.BOMB))
	assert_eq(s.bombs_left(), 1)
	assert_eq(s.discard_top, "", "出局者的手牌垫在底下,不当作公开打出的牌")
	assert_eq(s.out_order, [1])


func test_eliminated_players_are_skipped():
	H.rig(s, {1: [], 2: [], 3: []}, [C.BOMB, C.SKIP, C.BEG, C.PEEK], 1)
	_ok(s.draw(1))   # 1 号炸飞
	_ok(s.draw(2))
	assert_eq(s.current_pid, 3)
	assert_eq(H.find(_ok(s.draw(3)), "turn_passed")["pid"], 2, "跳过出局的 1 号")
	_err(s.draw(1), BombCatState.ERR_OUT)


func test_last_player_standing_wins():
	s = H.new_state([1, 2])
	H.rig(s, {1: [], 2: [C.SKIP]}, [C.BOMB, C.SKIP], 1)
	var events := _ok(s.draw(1))
	assert_eq(events[-1], {"type": "match_over", "winner": 2, "ranking": [2, 1]})
	assert_eq(s.step, S.OVER)
	assert_eq(s.winner_pid, 2)
	assert_eq(s.current_pid, null)
	_err(s.draw(2), BombCatState.ERR_MATCH_OVER)
	_err(s.play(2, [0]), BombCatState.ERR_MATCH_OVER)
	_err(s.nope(2), BombCatState.ERR_MATCH_OVER)
	_err(s.timeout(), BombCatState.ERR_MATCH_OVER)


func test_ranking_lists_the_winner_then_reverse_elimination_order():
	s = H.new_state([1, 2, 3, 4])
	H.rig(s, {}, [C.BOMB, C.BOMB, C.BOMB, C.SKIP], 2)
	_ok(s.draw(2))
	_ok(s.draw(3))
	var events := _ok(s.draw(4))
	assert_eq(events[-1]["ranking"], [1, 4, 3, 2])


# —— 断线与超时 ——

func test_timeout_in_a_free_turn_draws():
	H.rig(s, {1: []}, [C.SKIP, C.BEG], 1)
	assert_eq(H.types(_ok(s.timeout())), ["drew", "turn_passed"])
	assert_eq(s.hands[1], [C.SKIP])


func test_timeout_resolves_the_window():
	H.rig(s, {1: [C.SKIP]}, [C.BEG], 1)
	_ok(s.play(1, [0]))
	assert_eq(H.types(_ok(s.timeout())), ["window_resolved", "effect", "turn_passed"])


func test_bystander_disconnect_drops_out_quietly():
	H.rig(s, {1: [C.SKIP], 2: [C.NOPE, C.DEFUSE]}, [C.BEG], 1)
	var events := _ok(s.eliminate(2))
	assert_eq(events, [{"type": "player_left", "pid": 2, "discarded": 2}])
	assert_eq(s.current_pid, 1)
	assert_eq(_ok(s.eliminate(2)), [], "再断一次没有事件")
	assert_eq(_ok(s.eliminate(77)), [], "不在局里的人")


func test_current_player_disconnect_passes_the_turn():
	H.rig(s, {1: [C.SKIP]}, [C.BEG], 1, 3)
	var events := _ok(s.eliminate(1))
	assert_eq(events, [{"type": "player_left", "pid": 1, "discarded": 1}, {"type": "turn_passed", "pid": 2, "turns": 1}])


func test_disconnect_during_own_window_aborts_it():
	H.rig(s, {1: [C.PASS_TURNS, C.SKIP]}, [C.BEG], 1)
	_ok(s.play(1, [0]))
	var events := _ok(s.eliminate(1))
	assert_eq(H.types(events), ["window_resolved", "player_left", "turn_passed"])
	assert_eq(events[0], {"type": "window_resolved", "pid": 1, "kind": C.PASS_TURNS, "effective": false, "nopes": 0, "aborted": true})
	assert_eq([s.step, s.current_pid, s.turns_left], [S.TURN, 2, 1], "甩锅作废,下家只走 1 回合")


func test_bystander_disconnect_during_a_window_keeps_it_open():
	H.rig(s, {1: [C.SKIP], 3: [C.NOPE]}, [C.BEG], 1)
	_ok(s.play(1, [0]))
	assert_eq(H.types(_ok(s.eliminate(3))), ["player_left"])
	assert_eq(s.step, S.WINDOW)


func test_disconnect_while_reinserting_puts_the_bomb_back():
	H.rig(s, {1: [C.DEFUSE, C.SKIP]}, [C.BOMB, C.BEG], 1)
	_ok(s.draw(1))
	var events := _ok(s.eliminate(1))
	assert_eq(H.types(events), ["reinserted", "player_left", "turn_passed"])
	assert_true(s.deck.has(C.BOMB))
	assert_eq(s.held_bomb, "")


func test_disconnects_during_a_give():
	H.rig(s, {1: [C.BEG, C.BEG], 2: [C.SKIP, C.NOPE]}, [C.PEEK], 1)
	_play_and_resolve(1, [0], 2)
	var events := _ok(s.eliminate(2))
	assert_eq(H.types(events), ["effect", "player_left"], "给牌的人跑了:讨要落空")
	assert_eq(events[0]["got"], false)
	assert_eq([s.step, s.current_pid], [S.TURN, 1])
	# 讨要的人自己跑了
	s = H.new_state([1, 2, 3])
	H.rig(s, {1: [C.BEG], 2: [C.SKIP]}, [C.PEEK], 1)
	_play_and_resolve(1, [0], 2)
	events = _ok(s.eliminate(1))
	assert_eq(H.types(events), ["effect", "player_left", "turn_passed"])
	assert_eq([s.step, s.current_pid], [S.TURN, 2])
	assert_eq(s.give_info(2), {})


func test_disconnect_down_to_one_player_ends_the_match():
	_ok(s.eliminate(2))
	var events := _ok(s.eliminate(3))
	assert_eq(events[-1]["type"], "match_over")
	assert_eq(events[-1]["winner"], 1)


# —— 隐藏信息 ——

func test_public_events_never_carry_hands_deck_order_or_peeks():
	H.rig(s, {1: [C.PEEK, C.BEG, C.DEFUSE, C.SNACK_FISH, C.SNACK_FISH], 2: [C.DEFUSE, C.SKIP, C.NOPE], 3: [C.SHUFFLE]},
		[C.SKIP, C.BOMB, C.BEG, C.SNACK_YARN], 1)
	var all := []
	all += _play_and_resolve(1, [0])            # 偷看
	all += _play_and_resolve(1, [0], 2)         # 讨要
	all += _ok(s.give(2, 0))                    # 2 号给出拆弹
	all += _play_and_resolve(1, [1, 2], 2)      # 零食对子抽牌
	all += _ok(s.draw(1))                       # 摸到溜了
	all += _ok(s.draw(2))                       # 摸到炸弹:有没有拆弹看抽牌结果
	if s.step == S.REINSERT:
		all += _ok(s.reinsert(2, 1))
	for ev in all:
		assert_eq(H.event_leak(ev), "", str(ev))
		assert_false(ev.has("hand") or ev.has("card") or ev.has("deck") or ev.has("peek") or ev.has("pos"), str(ev))
	var drew := all.filter(func(ev: Dictionary) -> bool: return ev["type"] == "drew")
	assert_eq(drew.size(), 2)
	assert_eq(H.event_leak({"type": "drew", "pid": 1, "deck_count": 1, "bomb": false, "card": C.SKIP}), "drew 多出键 card",
		"检查器本身能抓到夹带的牌")
