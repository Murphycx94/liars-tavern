class_name RulebookBlocks
# 说明书块渲染:把 RulebookContent 的数据块变成控件。
# 配色沿用 UiTheme 的语义:黄铜=中性,绿=真话,红=假话/危险。


const BODY_SIZE := 17
const CARD_SIZE := Vector2(66, 95)
const CARD_FAN_DEGREES := 3.0
const TONES := {"brass": UiTheme.BRASS_BRIGHT, "truth": UiTheme.TRUTH, "lie": UiTheme.LIE}
# 牌面小图上记着自己的牌值:牌面纹理生成完后按它重新取(refresh_cards)
const CARD_META := &"rulebook_card"
const BOMB_CARD_META := &"rulebook_bomb_card"   # 炸弹猫牌面小图记着牌 id(字符串)
const BOMB_CARD_SIZE := Vector2(60, 87)
const DICE_SIZE := 34.0                    # 吹牛骰子示例的 2D 骰子
const DICE_LABEL_WIDTH := 64.0

# 斗地主牌型表与大小顺序:示例小牌互相压住一半(飞机带对 10 张也放得下)
const DDZ_CARD_SIZE := Vector2(38, 55)
const DDZ_CARD_OVERLAP := -16
const DDZ_NAME_WIDTH := 230.0

# 德州牌型表
const HAND_CARD_SIZE := Vector2(40, 58)     # 规格 §6.6:示例小牌不超过 40×58
const HAND_CARD_GAP := 4
const HAND_NAME_WIDTH := 150.0
const HAND_PLACE_WIDTH := 76.0
const HAND_COLUMN_GAP := 16
const HANDS_HIGHLIGHT := UiTheme.BRASS_BRIGHT   # 长短牌名次不同的那两行


static func build(block: Dictionary) -> Control:
	match block["type"]:
		"lead":
			return _paragraph(block["text"], 21, UiTheme.PARCHMENT, UiTheme.display_font())
		"text":
			return _paragraph(block["text"], BODY_SIZE, UiTheme.PARCHMENT_DIM)
		"bullets":
			return _bullets(block["items"])
		"note":
			return _note(block["text"])
		"cards":
			return _cards(block["items"])
		"pair":
			return _pair(block["items"])
		"odds":
			return _odds(block["items"])
		"keys":
			return _keys(block["items"])
		"hands":
			return _hands(block)
		"bomb_cards":
			return _bomb_cards(block["items"])
		"dice":
			return _dice(block)
		"ddz_combos":
			return _ddz_combos(block["items"])
		"ddz_order":
			return _ddz_order(block)
	push_warning("说明书:未知的块类型 %s" % block["type"])
	return Control.new()


static func refresh_cards(root: Node) -> void:
	# 牌面纹理生成完后调用:把 root 下所有牌面小图重新取一遍纹理(生成前取到的是占位色块)
	for face in root.find_children("*", "TextureRect", true, false):
		if face.has_meta(CARD_META):
			(face as TextureRect).texture = CardFaces.texture(face.get_meta(CARD_META))
		elif face.has_meta(BOMB_CARD_META):
			(face as TextureRect).texture = BombCatFaces.texture(face.get_meta(BOMB_CARD_META))


static func _card_face(card: int, card_size: Vector2) -> TextureRect:
	var face := TextureRect.new()
	face.texture = CardFaces.texture(card)
	face.set_meta(CARD_META, card)
	face.custom_minimum_size = card_size
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # 从大纹理缩小很多倍:不用 mipmap 会出锯齿
	return face


# —— 文字 ——

static func _paragraph(text: String, font_size: int, color: Color, font: Font = null) -> Label:
	var label := UiTheme.label(text, font_size, color, font)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_constant_override("line_spacing", 5)
	return label


static func _bullets(items: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	for item in items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		box.add_child(row)
		var mark := UiTheme.label("◆", 10, UiTheme.BRASS)
		mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		mark.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		mark.custom_minimum_size.y = UiTheme.body_font().get_height(BODY_SIZE)
		row.add_child(mark)
		row.add_child(_paragraph(item, BODY_SIZE, UiTheme.PARCHMENT))
	return box


static func _note(text: String) -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.panel_box(Color(UiTheme.BRASS, 0.09), UiTheme.BRASS, 0, 4)
	style.border_width_left = 3
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var tag := UiTheme.label("提示", 15, UiTheme.BRASS, UiTheme.display_font())
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(tag)
	row.add_child(_paragraph(text, 16, UiTheme.PARCHMENT))
	return panel


# —— 牌堆:牌面 + 张数,微微扇开 ——

static func _cards(items: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	for i in items.size():
		var item: Dictionary = items[i]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		row.add_child(col)
		var face := _card_face(item["kind"], CARD_SIZE)
		face.pivot_offset = CARD_SIZE / 2.0
		face.rotation = deg_to_rad((i - (items.size() - 1) / 2.0) * CARD_FAN_DEGREES)
		col.add_child(face)
		var count := UiTheme.label("× %d" % item["count"], 22, UiTheme.BRASS_BRIGHT, UiTheme.latin_font())
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(count)
		var caption := UiTheme.label(item.get("caption", ""), 13, UiTheme.MUTED)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(caption)
	return row


# —— 炸弹猫的牌:每张一行(小牌面、名字、张数、一行说明),两列 ——

static func _bomb_cards(items: Array) -> Control:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(row)
		var face := TextureRect.new()
		face.texture = BombCatFaces.texture(item["id"])
		face.set_meta(BOMB_CARD_META, item["id"])
		face.custom_minimum_size = BOMB_CARD_SIZE
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		row.add_child(face)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(col)
		col.add_child(UiTheme.label(item["name"], 20, UiTheme.BRASS_BRIGHT, UiTheme.display_font()))
		col.add_child(_paragraph(item["text"], 15, UiTheme.PARCHMENT))
		col.add_child(_paragraph(item["count"], 13, UiTheme.MUTED))
	return grid


# —— 吹牛骰子的开盅示例:每行名字 + 一排 2D 骰子,算进去的(等于 face 或 1 点)金边高亮 ——

static func _dice(block: Dictionary) -> Control:
	var face: int = block.get("face", 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var total := 0
	for item in block.get("items", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		var name_label := UiTheme.label(str(item.get("label", "")), 17, UiTheme.PARCHMENT_DIM, UiTheme.display_font())
		name_label.custom_minimum_size = Vector2(DICE_LABEL_WIDTH, 0)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_label)
		for v in item.get("dice", []):
			var icon := DiceIcon.new(v, DICE_SIZE)
			var hit: bool = face > 0 and (v == face or v == LiarsDiceState.WILD_FACE)
			icon.set_state(hit, face > 0 and not hit)
			if hit:
				total += 1
			row.add_child(icon)
	if face > 0:
		box.add_child(UiTheme.label("数「%d」:一共 %d 个" % [face, total], 19, UiTheme.BRASS_BRIGHT, UiTheme.display_font()))
	return box


# —— 二选一对照:出牌/质疑、真话/假话 ——

static func _pair(items: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	for item in items:
		var tone: Color = TONES.get(item["tone"], UiTheme.BRASS_BRIGHT)
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := UiTheme.panel_box(Color(tone, 0.07), Color(tone, 0.55), 1, 10)
		style.border_width_top = 3
		panel.add_theme_stylebox_override("panel", style)
		row.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		panel.add_child(box)
		box.add_child(UiTheme.label(item["title"], 26, tone, UiTheme.display_font()))
		box.add_child(_paragraph(item["body"], 16, UiTheme.PARCHMENT))
		if item.has("result"):
			box.add_child(UiTheme.label("→ " + item["result"], 19, tone, UiTheme.display_font()))
	return row


# —— 左轮:每一枪的中弹概率 ——

static func _odds(items: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	var first: float = items[0]["chance"]
	for i in items.size():
		var item: Dictionary = items[i]
		var chance: float = item["chance"]
		var danger := inverse_lerp(first, 1.0, chance) if first < 1.0 else 1.0
		var tint := UiTheme.BRASS.lerp(UiTheme.BLOOD, danger)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		box.add_child(row)
		var shot := UiTheme.label("第 %d 枪" % item["shot"], 16, UiTheme.PARCHMENT_DIM)
		shot.custom_minimum_size.x = 64
		row.add_child(shot)
		var dots := ChamberDots.new(4.5)
		dots.fired = item["shot"] - 1
		dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dots)
		row.add_child(OddsBar.new(chance, tint, i))
		var text := "必中" if chance >= 1.0 else "1/%d · %d%%" % [roundi(1.0 / chance), roundi(chance * 100.0)]
		var odds := UiTheme.label(text, 16, tint.lightened(0.25), UiTheme.display_font())
		odds.custom_minimum_size.x = 96
		odds.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(odds)
	return box


class OddsBar extends Control:
	const STAGGER := 0.06
	const GROW_TIME := 0.45

	var ratio := 0.0
	var tint := Color.WHITE
	var shown := 0.0:
		set(value):
			shown = value
			queue_redraw()
	var _index := 0

	func _init(p_ratio: float, p_tint: Color, index: int) -> void:
		ratio = p_ratio
		tint = p_tint
		_index = index
		custom_minimum_size = Vector2(120, 12)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		create_tween().tween_property(self, "shown", ratio, GROW_TIME) \
			.set_delay(_index * STAGGER).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _draw() -> void:
		var radius := int(size.y / 2.0)
		UiTheme.flat(Color(0, 0, 0, 0.4), radius).draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
		if shown > 0.0:
			var fill := Rect2(Vector2.ZERO, Vector2(maxf(size.x * shown, size.y), size.y))
			UiTheme.flat(tint, radius).draw(get_canvas_item(), fill)


# —— 操作键位 ——

static func _keys(items: Array) -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 12)
	for header in ["操作", "键盘", "鼠标"]:
		grid.add_child(UiTheme.label(header, 13, UiTheme.MUTED))
	for item in items:
		var action := UiTheme.label(item["action"], BODY_SIZE, UiTheme.PARCHMENT)
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(action)
		var caps := HBoxContainer.new()
		caps.add_theme_constant_override("separation", 6)
		for key in item["keys"]:
			caps.add_child(_keycap(key))
		if item["keys"].is_empty():
			caps.add_child(UiTheme.label("—", 15, UiTheme.PARCHMENT_DIM))
		grid.add_child(caps)
		grid.add_child(UiTheme.label(item["mouse"] if item["mouse"] != "" else "—", 15, UiTheme.PARCHMENT_DIM))
	return grid


static func _keycap(text: String) -> Control:
	var panel := PanelContainer.new()
	var style := UiTheme.panel_box(Color(0.16, 0.11, 0.07), Color(UiTheme.BRASS, 0.7), 1, 5)
	style.border_width_bottom = 3
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 2
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size.x = 34
	var label := UiTheme.label(text, 15, UiTheme.BRASS_BRIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel


# —— 德州牌型表:每行牌型名、5 张示例小牌、长牌与短牌的名次 ——

static func _hands(block: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.add_child(_hands_header())
	for item in block["items"]:
		box.add_child(_hand_row(item))
	var note := _paragraph(block.get("note", ""), 14, UiTheme.PARCHMENT_DIM)
	note.add_theme_constant_override("line_spacing", 3)
	box.add_child(note)
	return box


static func _hands_header() -> Control:
	var cells := HBoxContainer.new()
	cells.add_child(_header_cell("牌型", HAND_NAME_WIDTH))
	cells.add_child(_header_cell("示例", _hand_cards_width()))
	for title in ["长牌名次", "短牌名次"]:
		var place := _header_cell(title, HAND_PLACE_WIDTH)
		place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cells.add_child(place)
	return _hands_line(cells, Color(0, 0, 0, 0), false)


static func _header_cell(text: String, width: float) -> Label:
	var label := UiTheme.label(text, 13, UiTheme.MUTED)
	label.custom_minimum_size.x = width
	return label


static func _hand_row(item: Dictionary) -> Control:
	var highlight: bool = item["highlight"]
	var cells := HBoxContainer.new()
	var names := VBoxContainer.new()
	names.custom_minimum_size.x = HAND_NAME_WIDTH
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.add_theme_constant_override("separation", 0)
	names.add_child(UiTheme.label(item["name"], 20, UiTheme.PARCHMENT, UiTheme.display_font()))
	names.add_child(UiTheme.label(item["caption"], 13, UiTheme.MUTED))
	cells.add_child(names)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", HAND_CARD_GAP)
	for card in item["cards"]:
		var face := _card_face(card, HAND_CARD_SIZE)   # 过滤方式在 _card_face 里统一设(规格 §5.3)
		# 铺满牌位:牌面生成前的占位纹理是正方形,按比例居中会画成方块,换上真牌面时大小一跳
		face.stretch_mode = TextureRect.STRETCH_SCALE
		cards.add_child(face)
	cells.add_child(cards)
	cells.add_child(_place_cell("LongPlace", str(item["long"]), UiTheme.PARCHMENT_DIM))
	# 短牌名次不同的两行:黄铜高亮并标出升降,一眼看出「同花与葫芦对调」
	var short_text := str(item["short"])
	if highlight:
		short_text += " ↑" if item["short"] < item["long"] else " ↓"
	cells.add_child(_place_cell("ShortPlace", short_text, HANDS_HIGHLIGHT if highlight else UiTheme.PARCHMENT_DIM))
	return _hands_line(cells, Color(UiTheme.BRASS, 0.13) if highlight else Color(0, 0, 0, 0.18), highlight)


static func _hands_line(cells: HBoxContainer, tint: Color, accent: bool) -> PanelContainer:
	# 表格的一行:底色条里放各列;表头与各行用同样的边距与列间距,列才对得齐
	cells.add_theme_constant_override("separation", HAND_COLUMN_GAP)
	var panel := PanelContainer.new()
	var style := UiTheme.flat(tint, 6)
	style.content_margin_left = 12
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	if accent:
		style.border_width_left = 3
		style.border_color = HANDS_HIGHLIGHT
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(cells)
	return panel


static func _place_cell(cell_name: String, text: String, color: Color) -> Label:
	var label := UiTheme.label(text, 20, color, UiTheme.latin_font())
	label.name = cell_name
	label.custom_minimum_size.x = HAND_PLACE_WIDTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


static func _hand_cards_width() -> float:
	var count := RulebookPoker.HAND_SIZE
	return HAND_CARD_SIZE.x * count + HAND_CARD_GAP * (count - 1)


# —— 斗地主:牌型表(两列,每行牌型名 + 说明 + 示例小牌)与大小顺序 ——

static func _ddz_cards_row(ids: Array) -> HBoxContainer:
	# 斗地主牌 id 的一排小牌(互相压住一半);牌面值记在 CARD_META 上,牌面生成完由 refresh_cards 重新取
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DDZ_CARD_OVERLAP)
	for id in ids:
		var face := _card_face(DdzJokerFaces.face_kind(id), DDZ_CARD_SIZE)
		face.stretch_mode = TextureRect.STRETCH_SCALE
		row.add_child(face)
	return row


static func _ddz_combos(items: Array) -> Control:
	# 一行一种:牌型名与一句说明在左(固定宽),示例小牌在右(同德州牌型表的底色条)
	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		var cells := HBoxContainer.new()
		cells.add_theme_constant_override("separation", 12)
		var names := VBoxContainer.new()
		names.custom_minimum_size.x = DDZ_NAME_WIDTH
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		names.add_theme_constant_override("separation", 0)
		names.add_child(UiTheme.label(item["name"], 19, UiTheme.BRASS_BRIGHT, UiTheme.display_font()))
		names.add_child(UiTheme.label(item["caption"], 12, UiTheme.MUTED))
		cells.add_child(names)
		var cards := _ddz_cards_row(item["cards"])
		cards.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cells.add_child(cards)
		grid.add_child(_hands_line(cells, Color(0, 0, 0, 0.18), false))
	return grid


static func _ddz_order(block: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(_ddz_cards_row(block["cards"]))
	box.add_child(_paragraph(block.get("caption", ""), 14, UiTheme.PARCHMENT_DIM))
	return box
