class_name PokerNameplate
extends PanelContainer
# 德州铭牌(规格 §6.3,≤ 150×64):两行——名字(超长省略号)+ D/小盲/大盲徽记;筹码 + 状态。
# AI 接管的机器人名字旁有蓝色「AI」小标。行动者铜色高亮;弃牌、观战、已离开的人变暗。挂点由牌桌用 TableWorld.nameplate_anchor 给 WorldLabels。
# 文案只写数字与状态,不出现花色符号。两行各自按文字宽度给足最小宽度(带省略号的 Label 最小宽度只剩「…」),
# 整体宽度由较长的那行决定,再夹到 150;名字短、第二行长时第二行不会被截成「2,65」。


const MAX_SIZE := Vector2(150, 64)
const PADDING := Vector2(10, 4)
const NAME_FONT := 16
const INFO_FONT := 13
const BADGE_FONT := 12
const BADGE_ROOM := 44.0   # 给「D·小盲」徽记留的宽度
const AI_ROOM := 24.0      # AI 机器人的「AI」小标
const AI_TAG := "AI"
const AI_COLOR := Color(0.55, 0.85, 0.95)
const ACTIVE_BG := Color(0.25, 0.15, 0.06, 0.85)
const DIMMED := Color(0.6, 0.6, 0.6, 0.75)
const STATUS_TEXT := {
	PokerRules.STATUS_FOLDED: "弃牌",
	PokerRules.STATUS_ALLIN: "全下",
	PokerRules.STATUS_SPECTATING: "观战",
	PokerRules.STATUS_WAITING: "等待下一手",
	PokerRules.STATUS_BUSTED: "输光",
	PokerRules.STATUS_AWAY: "离座",
	PokerRules.STATUS_LEFT: "已离开",
}
const CONFIRMED_TEXT := "已准备"
const DIMMED_STATUSES := [PokerRules.STATUS_FOLDED, PokerRules.STATUS_SPECTATING]

var _name: Label
var _badge: Label
var _info: Label
var _style: StyleBoxFlat


static func status_text(player: Dictionary) -> String:
	# 已离开优先(全下后离开的人 status 仍是 allin);在本手中的人显示本轮下注
	if has_left(player):
		return STATUS_TEXT[PokerRules.STATUS_LEFT]
	if player.get("confirmed") is bool and player["confirmed"]:
		return CONFIRMED_TEXT   # 两手之间点了「开始下一手」
	var status: Variant = player.get("status")
	if not status is String:
		return ""
	if status == PokerRules.STATUS_ACTIVE:
		var bet: Variant = player.get("bet", 0)
		return "下注 %s" % ChipText.format(bet) if bet is int and bet > 0 else ""
	return STATUS_TEXT.get(status, "")


static func badge_for(pid: Variant, pub: Dictionary) -> String:
	var parts := []
	if pub.get("button") == pid:
		parts.append("D")
	if pub.get("sb") == pid:
		parts.append("小盲")
	elif pub.get("bb") == pid:
		parts.append("大盲")
	return "·".join(parts)


static func is_dimmed(player: Dictionary) -> bool:
	return has_left(player) or DIMMED_STATUSES.has(player.get("status"))


static func has_left(player: Dictionary) -> bool:
	# 视图不可信:left 不是 bool 时当没离开(String == bool 是脚本错误,不能直接比)
	var left: Variant = player.get("left", false)
	return left is bool and left


static func shown_name(display_name: String, ai: bool) -> String:
	# AI 机器人:「机器人·」前缀让位给「AI」小标(铭牌只有 150 宽,前缀加小标会把名字挤成省略号)
	return display_name.trim_prefix(PokerBots.NAME_PREFIX) if ai else display_name


func _init(display_name: String, ai := false) -> void:
	display_name = shown_name(display_name, ai)
	_style = UiTheme.panel_box(UiTheme.PANEL_SOFT, Color(UiTheme.BRASS, 0.45), 1, 10)
	_style.content_margin_left = PADDING.x
	_style.content_margin_right = PADDING.x
	_style.content_margin_top = PADDING.y
	_style.content_margin_bottom = PADDING.y
	add_theme_stylebox_override("panel", _style)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var font := UiTheme.display_font()
	_name = UiTheme.label(display_name, NAME_FONT, UiTheme.PARCHMENT, font)
	# 带省略号的 Label 最小宽度只剩「…」:按文字宽度给足,超长昵称才截断
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var text_width := ceilf(font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_FONT).x)
	_name.custom_minimum_size.x = minf(text_width, MAX_SIZE.x - 2.0 * PADDING.x - BADGE_ROOM - (AI_ROOM if ai else 0.0))
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name)
	if ai:
		var tag := UiTheme.label(AI_TAG, BADGE_FONT, AI_COLOR, UiTheme.body_font())
		tag.name = "AiTag"
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(tag)
	_badge = UiTheme.label("", BADGE_FONT, UiTheme.BRASS_BRIGHT, UiTheme.body_font())
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_badge)
	_info = UiTheme.label("", INFO_FONT, UiTheme.PARCHMENT_DIM, UiTheme.body_font())
	_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_info)


func set_info(player: Dictionary, badge: String, active: bool) -> void:
	_badge.text = badge
	_badge.visible = badge != ""
	var stack: Variant = player.get("stack", 0)
	var status := status_text(player)
	_info.text = ChipText.format(stack if stack is int else 0) + (" · " + status if status != "" else "")
	var info_width := ceilf(UiTheme.body_font().get_string_size(_info.text, HORIZONTAL_ALIGNMENT_LEFT, -1, INFO_FONT).x)
	_info.custom_minimum_size.x = minf(info_width, MAX_SIZE.x - 2.0 * PADDING.x)
	_style.border_color = UiTheme.BRASS_BRIGHT if active else Color(UiTheme.BRASS, 0.45)
	_style.set_border_width_all(2 if active else 1)
	_style.bg_color = ACTIVE_BG if active else UiTheme.PANEL_SOFT
	modulate = DIMMED if is_dimmed(player) else Color.WHITE
