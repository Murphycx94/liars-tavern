class_name CardStrip
extends HBoxContainer
# 2D 小牌条(规格 §5.3、§6.1):公共牌条(固定 5 个槽位,空槽只画框)、摊牌面板里每人的两张、自己的手牌大图。
# 纹理从 256×372 的德州牌面缩小很多倍,一律 TEXTURE_FILTER_LINEAR_WITH_MIPMAPS;
# PokerFaces 在后台生成完会发 built 信号,这里重新取纹理(生成前取到的是占位素纸)。
# 牌值来自视图或事件,先过 PokerCard.is_card,不是牌的值丢掉。


const GAP := 4
const EMPTY_SLOT_ALPHA := 0.35
const DIM := Color(0.45, 0.45, 0.45)   # highlight 时其余牌压暗
const CARD_META := &"card"

var _slot_count := 0
var _card_size := Vector2(36, 50)
var _cards: Array = []


static func sanitize(cards: Variant) -> Array:
	if not cards is Array:
		return []
	return cards.filter(func(c): return PokerCard.is_card(c))


func _init(slots: int, card_size: Vector2) -> void:
	# slots 为 0 时槽位数跟着牌数走
	_slot_count = slots
	_card_size = card_size
	add_theme_constant_override("separation", GAP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in _slot_count:
		add_child(_make_slot())


func _ready() -> void:
	PokerFaces.built_signal().connect(refresh)


func set_cards(cards: Variant) -> void:
	_cards = sanitize(cards)
	if _slot_count == 0:
		_resize_slots(_cards.size())
	for i in get_child_count():
		var face := _face(i)
		if i < _cards.size():
			face.set_meta(CARD_META, _cards[i])
			face.texture = PokerFaces.texture(_cards[i])
			face.visible = true
		else:
			face.remove_meta(CARD_META)
			face.visible = false
		face.modulate = Color.WHITE
		(get_child(i) as Control).modulate.a = 1.0 if i < _cards.size() else EMPTY_SLOT_ALPHA


func cards() -> Array:
	return _cards.duplicate()


func preview_candidates(avoid := Rect2()) -> Array:
	# 悬停大图(CardPreview)的候选:每张亮着的牌一个屏幕矩形;整条不可见(如摊牌面板收起)时为空。
	# avoid:牌条所在面板的屏幕矩形,大图摆在面板外面,不挡住同一行的名字与牌型
	var out := []
	if not is_visible_in_tree():
		return out
	for i in get_child_count():
		var face := _face(i)
		if face.visible and face.has_meta(CARD_META):
			var rect := face.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, face.size)
			out.append(CardPreview.rect_candidate(rect, face.texture, i, face.get_instance_id(),
				"", "", avoid))
	return out


func highlight(cards: Variant) -> void:
	# 标出成牌的那几张(摊牌时赢家的 5 张),其余压暗;空数组恢复
	var keep := sanitize(cards)
	for i in get_child_count():
		var face := _face(i)
		face.modulate = Color.WHITE if keep.is_empty() or (face.has_meta(CARD_META) and keep.has(face.get_meta(CARD_META))) else DIM


func refresh() -> void:
	for i in get_child_count():
		var face := _face(i)
		if face.has_meta(CARD_META):
			face.texture = PokerFaces.texture(face.get_meta(CARD_META))


func _resize_slots(count: int) -> void:
	while get_child_count() > count:
		var extra := get_child(get_child_count() - 1)
		remove_child(extra)
		extra.free()
	while get_child_count() < count:
		add_child(_make_slot())


func _make_slot() -> PanelContainer:
	var slot := PanelContainer.new()
	var frame := UiTheme.panel_box(Color(0, 0, 0, 0.25), Color(UiTheme.BRASS, 0.5), 1, 4)
	frame.content_margin_left = 0
	frame.content_margin_right = 0
	frame.content_margin_top = 0
	frame.content_margin_bottom = 0
	slot.add_theme_stylebox_override("panel", frame)
	slot.custom_minimum_size = _card_size
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.modulate.a = EMPTY_SLOT_ALPHA
	var face := TextureRect.new()
	face.custom_minimum_size = _card_size
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.visible = false
	slot.add_child(face)
	return slot


func _face(index: int) -> TextureRect:
	return get_child(index).get_child(0)
