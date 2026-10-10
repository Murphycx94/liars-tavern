extends Node
# 截图用展台:4 名酒客落座、发牌、出牌区与翻牌行,用于检查角色与道具外观(tools/shot.gd --showcase)。

const ShowcaseSpecies := preload("res://tools/showcase_species.gd")

var world: TableWorld


func build(tavern: Tavern) -> void:
	await CardFaces.build(self)
	Card3D.refresh_materials()
	world = TableWorld.new(tavern)
	tavern.table_root.add_child(world)
	world.arrange(ShowcaseSpecies.players([1, 2, 3, 4]), 1, true, true)
	var me: Patron = world.patrons[1]
	me.present_hand_to(world.third_person_view(1).origin)
	world.cards.attach_hand(me.fan)
	world.cards.set_target(Card.KING, false)
	await get_tree().create_timer(0.7).timeout
	var counts := {1: 5, 2: 5, 3: 4, 4: 3}
	await world.cards.deal([1, 2, 3, 4], counts, [Card.QUEEN, Card.KING, Card.JOKER, Card.ACE, Card.KING])
	await world.cards.play(2, 2, [])
	await world.cards.play(3, 1, [])
	world.cards.set_selection({1: true, 3: true}, 4)
	await world.cards.gather_for_reveal(1)
	await world.cards.flip_revealed(0, Card.ACE, false)
	world.look_all_at(Vector3(0, 1.3, 1.1))
	world.patrons[3].set_expression("angry")
	world.patrons[4].set_expression("worried")
	world.patrons[2].set_active(true)
	# 第 4 位举枪到太阳穴,检查持枪姿态
	var gun: Node3D = world.revolvers[4]
	await world.patrons[4].pick_up(gun, 0.2)
	await world.patrons[4].raise_gun_to_head(gun, 0.3)
	await get_tree().create_timer(0.6).timeout


func fire() -> void:
	# 第 4 位手里的枪开一枪(参数同 table_director._bang):枪口焰与硝烟
	var gun: Revolver3D = world.revolvers[4]
	Fx.muzzle_flash(world, gun.muzzle_transform())
	Fx.smoke_puff(world, gun.muzzle_transform().origin, 22)
