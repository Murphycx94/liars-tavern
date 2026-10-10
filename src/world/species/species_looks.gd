class_name SpeciesLooks
# 物种外观注册表:每个物种一个脚本(species_<id>.gd),里面是外观数据 LOOK 和特件钩子 extras()。
# 顺序与 Species.IDS 一致。配方在工作线程里跑,只读这些常量数据、调用静态函数,不建节点和资源。

const SCRIPTS := [
	preload("res://src/world/species/species_fox.gd"),
	preload("res://src/world/species/species_bear.gd"),
	preload("res://src/world/species/species_pig.gd"),
	preload("res://src/world/species/species_cat.gd"),
	preload("res://src/world/species/species_turtle.gd"),
	preload("res://src/world/species/species_alpaca.gd"),
	preload("res://src/world/species/species_monkey.gd"),
	preload("res://src/world/species/species_crocodile.gd"),
	preload("res://src/world/species/species_panda.gd"),
	preload("res://src/world/species/species_penguin.gd"),
]

# 调色板缺省项(物种没写就用这些);fur / muzzle / dark / coat / accent 每个物种都要写
const DEFAULTS := {
	"nose": Color(0.06, 0.05, 0.05), "pad": Color(0.22, 0.12, 0.1), "brass": Color(0.78, 0.56, 0.24),
	"silver": Color(0.72, 0.73, 0.76), "gem": Color(0.62, 0.08, 0.1), "sole": Color(0.12, 0.08, 0.06),
	"shoe": Color(0.1, 0.08, 0.07), "straw": Color(0.78, 0.66, 0.38),
}
const METAL_KEYS := ["brass", "silver", "gem"]   # 金属件不受底色上限约束(本来就暗、靠反射出亮)


static func script_of(index: int) -> GDScript:
	return SCRIPTS[posmod(index, SCRIPTS.size())]


static func look(index: int) -> Dictionary:
	return script_of(index).LOOK


static func palette(look_data: Dictionary) -> Dictionary:
	# 物种调色板(sRGB):缺省项补齐,先提亮成粉彩(PatronParts.pastel),派生色(翻领、爪子、后脑)按规则算,
	# 所有颜色按最大通道封顶,防止烛光下过曝
	var raw: Dictionary = DEFAULTS.duplicate()
	raw.merge(look_data["palette"], true)
	var pal := {}
	for key in raw:
		pal[key] = raw[key] if METAL_KEYS.has(key) else PatronParts.capped(PatronParts.pastel(raw[key]))
	if not pal.has("cream"):
		pal["cream"] = pal["muzzle"]
	if not pal.has("lapel"):
		pal["lapel"] = pal["coat"].darkened(PatronParts.LAPEL_DARKEN)
	if not pal.has("hat"):
		pal["hat"] = pal["dark"].darkened(0.4)
	if not pal.has("paw"):
		pal["paw"] = pal["fur"] * PatronParts.PAW_SHADE
	if not pal.has("fur_back"):
		pal["fur_back"] = pal["fur"].darkened(0.18)
	if not pal.has("pants"):
		pal["pants"] = pal["coat"].darkened(0.2)
	if not pal.has("band"):
		pal["band"] = pal["accent"]
	return pal
