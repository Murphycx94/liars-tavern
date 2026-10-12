class_name BjNameplate
extends PokerNameplate
# 21 点铭牌:外观同德州铭牌(≤ 150×64,名字 + 一行信息),第二行是「筹码 · 这一局的状态」
# (下注 100 / 这局不玩 / 19 / 软 17 / 爆牌 24 / 黑杰克;分牌时几手用 / 隔开)。正在决策的人铜色高亮;
# 这局不玩、离座、已离开的人变暗。状态文字由牌桌用 BjScreenState.plate_status 算好传进来。


const DIM_STATUSES := ["这局不玩", "离座", "已离开"]


func _init(display_name: String) -> void:
	super(display_name, false)


func set_plate(stack: int, status: String, active: bool) -> void:
	_badge.visible = false
	_info.text = ChipText.format(stack) + (" · " + status if status != "" else "")
	var info_width := ceilf(UiTheme.body_font().get_string_size(_info.text, HORIZONTAL_ALIGNMENT_LEFT, -1, INFO_FONT).x)
	_info.custom_minimum_size.x = minf(info_width, MAX_SIZE.x - 2.0 * PADDING.x)
	_style.border_color = UiTheme.BRASS_BRIGHT if active else Color(UiTheme.BRASS, 0.45)
	_style.set_border_width_all(2 if active else 1)
	_style.bg_color = ACTIVE_BG if active else UiTheme.PANEL_SOFT
	modulate = DIMMED if DIM_STATUSES.has(status) else Color.WHITE


func info_text() -> String:
	return _info.text
