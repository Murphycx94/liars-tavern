extends RefCounted
# 性能预算:按机位列出各项统计的上限(四个子项目全部完成后的总预算,见 2026-10-07-visual-overhaul-design.md §4.1),
# 性能探针 --assert-budget 据此核对。tools/ 不进导出包,所以不声明 class_name,用 preload 取用。

const FRAME_MS := 10.0    # M3、1080p、游戏实际渲染配置(RenderBudget)
const CPU_MS := 1.0       # CPU 渲染线程
const MAX_LIGHTS := 16
const OTHER_VIEW_DRAW_CALLS := 900

const LIMITS := {
	"seat": {"draw_calls": 700, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"fp": {"draw_calls": 700, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},   # 第一人称:同越肩
	"menu": {"draw_calls": 800, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"opponent": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"closeup": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"gun": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"bar": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"window": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"fireplace": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"overhead": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"selfshot": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	# 炸弹猫 6 人大桌展台(perf_probe --showcase=bomb_cat):座位与第一人称同骗子酒馆的越肩预算,俯视与特写按其余机位
	"bomb_seat": {"draw_calls": 700, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"bomb_fp": {"draw_calls": 700, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"bomb_overview": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"bomb_close": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	# 吹牛骰子 6 人大桌展台(perf_probe --showcase=liars_dice):同炸弹猫,座位与第一人称 ≤ 700,俯视与特写按其余机位
	"dice_seat": {"draw_calls": 700, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"dice_fp": {"draw_calls": 700, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"dice_overview": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"dice_close": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	# 斗地主 3 人小桌展台(perf_probe --showcase=dou_dizhu):座位与第一人称同骗子酒馆的越肩预算,俯视按其余机位
	"ddz_seat": {"draw_calls": 700, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"ddz_fp": {"draw_calls": 700, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"ddz_overview": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	# 结算庆祝(perf_probe --celebrate):胜者特写环绕与整桌环绕,礼炮、彩纸、音符都在场
	"celebrate": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
	"celebrate_table": {"draw_calls": OTHER_VIEW_DRAW_CALLS, "frame_ms": FRAME_MS, "cpu_ms": CPU_MS, "lights": MAX_LIGHTS},
}


static func violations(view: String, stats: Dictionary) -> PackedStringArray:
	# 超出的每项一条说明;探针没测到的统计项不算超标,不认识的机位返回空
	var out := PackedStringArray()
	var limits: Dictionary = LIMITS.get(view, {})
	for key in limits:
		if stats.has(key) and stats[key] > limits[key]:
			out.append("%s 机位 %s = %s,超出上限 %s" % [view, key, _fmt(stats[key]), _fmt(limits[key])])
	return out


static func _fmt(value: Variant) -> String:
	return "%.2f" % value if value is float else str(value)
