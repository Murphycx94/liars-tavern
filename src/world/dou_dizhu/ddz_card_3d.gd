class_name DdzCard3D
extends Card3D
# 斗地主的 3D 牌:沿用 Card3D 的圆角薄片、飞行 / 翻面 / 高亮 / 射线拾取与德州的单张材质。
# 牌 id 是斗地主的 0–53(DdzHand);-1 = 牌背(别人的牌、扣着的底牌),两面都是德州牌背。
# 牌面值经 DdzJokerFaces.face_kind 换算(52 张 = 德州牌值,王 = 两张王的牌面值),kind 照常记着牌面值,
# 所以悬停大图(CardPreview.face_of → CardFaces.texture)不用改就认得斗地主的牌。


const BACK := -1

var card_id := BACK


func _init(id := BACK) -> void:
	super()
	set_card(id)


func set_card(id: int) -> void:
	card_id = id if DdzHand.is_card(id) else BACK
	if card_id == BACK:
		show_poker_back()
	else:
		set_kind(DdzJokerFaces.face_kind(card_id))


func is_back() -> bool:
	return card_id == BACK
