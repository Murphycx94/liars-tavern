extends GutTest
# 酒客的坐姿:身体前倾趴在牌桌上,双手搭在桌面(拿着牌也一样,不去扶牌扇挡住牌面)。
# 轮到自己时再前倾、拍桌、出牌伸手都不会把手按进桌子里;手里的牌不会插进桌面;
# 举枪时坐直;自己的牌扇仍正对越肩镜头。走与牌桌界面相同的接线:第三人称举牌 → 挂上牌扇 → 发牌对账。


const SETTLE := 1.2        # 秒:登场缩放(0.55 秒)与前倾插值都走完
const SIT_BAND := Vector2(0.03, 0.07)  # 米:掌心高出桌面的范围——低了是按进桌里/贴在桌边,高了是悬空
const ON_TABLE := 0.02     # 米:手掌至少有这么多搭在桌面以内
const LEAN_AHEAD := 0.1    # 米:前倾坐姿下,头部至少在髋部前方这么远
const SIT_UP_BACK := 0.06 * Patron.FIGURE_SCALE  # 米:举枪坐直时,头部比前倾坐着时至少往后收这么多
const REACH_PEAK := 0.27   # 秒:出牌手势前推 0.22 秒后停留 0.12 秒,在停留期间取样

var world: TableWorld
var me: Patron
var other: Patron


func before_each():
	world = TableWorld.new(null)
	add_child_autofree(world)
	world.arrange([{"pid": 1}, {"pid": 2}], 1, true, true)
	me = world.patrons[1]
	other = world.patrons[2]
	me.present_hand_to(_viewer())
	world.cards.attach_hand(me.fan)
	world.cards.sync({1: 5, 2: 5}, [Card.QUEEN, Card.KING, Card.ACE, Card.JOKER, Card.QUEEN])


# —— 坐姿与双手 ——

func test_patrons_lean_forward_over_the_table():
	await wait_seconds(SETTLE)
	for patron in [me, other]:
		assert_lt(_seat(patron, patron.head_position()).z, Patron.HIP.z - LEAN_AHEAD, "身体前倾,头在髋部前方")


func test_paws_rest_on_the_table_while_holding_cards():
	await wait_seconds(SETTLE)
	assert_eq(world.cards.held.get(2, []).size(), 5, "对手确实拿着牌")
	assert_eq(world.cards.my_cards.size(), 5, "自己确实拿着牌")
	_assert_paws_on_table(me, "自己")
	_assert_paws_on_table(other, "对手")


func test_paws_stay_on_the_table_while_leaning_in_on_their_turn():
	other.set_active(true)
	await wait_seconds(SETTLE)
	_assert_paws_on_table(other, "轮到他时")


func test_held_cards_clear_the_table():
	await wait_seconds(SETTLE)
	_assert_cards_above_table("坐着时")
	other.set_active(true)
	me.set_active(true)
	await wait_seconds(SETTLE)
	_assert_cards_above_table("轮到自己前倾时")


func test_own_fan_still_faces_the_over_shoulder_camera():
	await wait_seconds(SETTLE)
	var fan_pos := me.fan.global_position
	assert_almost_eq(_seat(me, fan_pos), Patron.HIP + Patron.SELF_FAN_POS, Vector3.ONE * 0.02, "牌扇仍在调好的位置")
	var facing := me.fan.global_basis.y.normalized().dot((_viewer() - fan_pos).normalized())
	assert_gt(facing, 0.995, "牌面正对越肩镜头")


# —— 动作 ——

func test_slam_lands_on_the_table():
	await wait_seconds(SETTLE)
	await other.slam_table()
	var paw := _seat(other, other.right_hand.global_position)
	assert_between(paw.y, SeatLayout.TABLE_TOP + SIT_BAND.x, SeatLayout.TABLE_TOP + SIT_BAND.y, "拍在桌面上,不按进桌里")


func test_reaching_lifts_the_paws_over_the_table():
	other.set_active(true)
	await wait_seconds(SETTLE)
	other.reach_toward_center()
	await wait_seconds(REACH_PEAK)
	for hand in _hands(other):
		assert_gt(_seat(other, hand.global_position).y, SeatLayout.TABLE_TOP + Patron.PAW_RADIUS, "出牌时手抬离桌面前推")


func test_paws_go_back_to_the_table_after_reaching():
	await wait_seconds(SETTLE)
	await other.reach_toward_center()
	await wait_seconds(SETTLE)
	_assert_paws_on_table(other, "出牌伸手之后")


func test_shooter_sits_up_with_the_gun_raised_then_leans_back_in():
	await wait_seconds(SETTLE)
	var gun := Node3D.new()
	world.add_child(gun)
	gun.global_position = other.global_transform * Vector3(0.3, SeatLayout.TABLE_TOP, -0.45)
	var rest := gun.global_transform
	var leaning_z := _seat(other, other.head_position()).z
	await other.pick_up(gun, 0.2)
	await other.raise_gun_to_head(gun, 0.3)
	await wait_seconds(SETTLE)
	assert_gt(_seat(other, other.head_position()).z - leaning_z, SIT_UP_BACK, "举枪时坐直")
	_assert_paw_on_table(other, _hands(other)[0], "举枪时空着的左手")
	await other.lower_gun(gun, rest, world, 0.2)
	await wait_seconds(SETTLE)
	assert_lt(_seat(other, other.head_position()).z, Patron.HIP.z - LEAN_AHEAD, "放下枪后重新前倾")
	_assert_paws_on_table(other, "放下枪后")


# —— 工具 ——

func _viewer() -> Vector3:
	return world.third_person_view(1).origin


func _seat(patron: Patron, global_point: Vector3) -> Vector3:
	# 座位局部坐标:原点在座位地面、-Z 朝牌桌中心,不受登场缩放影响
	return patron.to_local(global_point)


func _hands(patron: Patron) -> Array:
	return [patron.find_child("ArmL", true, false).get_node("Hand"), patron.right_hand]


func _assert_paws_on_table(patron: Patron, label: String) -> void:
	for hand in _hands(patron):
		_assert_paw_on_table(patron, hand, label)


func _assert_paw_on_table(patron: Patron, hand: Node3D, label: String) -> void:
	var on_table := patron.transform.orthonormalized() * _seat(patron, hand.global_position)
	var name: String = hand.get_parent().name
	assert_between(on_table.y, SeatLayout.TABLE_TOP + SIT_BAND.x, SeatLayout.TABLE_TOP + SIT_BAND.y,
		"%s 的 %s 应贴着桌面" % [label, name])
	var inner_edge := Vector2(on_table.x, on_table.z).length() - Patron.PAW_RADIUS
	assert_lt(inner_edge, SeatLayout.TABLE_RADIUS - ON_TABLE, "%s 的 %s 应搭到桌面以内" % [label, name])


func _assert_cards_above_table(label: String) -> void:
	var cards: Array = world.cards.held.get(2, []) + world.cards.my_cards
	assert_eq(cards.size(), 10)
	for card in cards:
		for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
			var point: Vector3 = card.global_transform * (corner * Vector3(Card3D.WIDTH, 0, Card3D.HEIGHT) / 2.0)
			assert_gt(point.y, SeatLayout.TABLE_TOP, "%s 手里的牌不插进桌面" % label)
