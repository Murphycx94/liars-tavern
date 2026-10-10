class_name PatronParts
# 酒客部件:物种基本信息表(名字、主色,等待厅名单用)与各部件的共享网格。网格由 PatronBuilder 按物种外观
# (species/*.gd)生成,每个动画枢轴下一份,按「物种:部件」缓存、启动时后台预建。动画逻辑在 Patron 中。


const SPECIES := [
	{
		"id": "fox", "label": "狐狸",
		"fur": Color(0.80, 0.40, 0.14), "muzzle": Color(0.80, 0.74, 0.62), "dark": Color(0.18, 0.08, 0.04),
		"coat": Color(0.13, 0.17, 0.3), "accent": Color(0.82, 0.62, 0.25), "hat": "top", "ears": "pointy",
	},
	{
		"id": "bear", "label": "熊",
		"fur": Color(0.36, 0.21, 0.11), "muzzle": Color(0.66, 0.5, 0.34), "dark": Color(0.12, 0.07, 0.04),
		"coat": Color(0.42, 0.11, 0.09), "accent": Color(0.86, 0.76, 0.52), "hat": "bowler", "ears": "round",
	},
	{
		"id": "pig", "label": "猪",
		"fur": Color(0.76, 0.47, 0.45), "muzzle": Color(0.80, 0.55, 0.52), "dark": Color(0.45, 0.2, 0.2),
		"coat": Color(0.2, 0.3, 0.17), "accent": Color(0.85, 0.3, 0.22), "hat": "cap", "ears": "floppy",
	},
	{
		"id": "cat", "label": "猫",
		"fur": Color(0.46, 0.47, 0.52), "muzzle": Color(0.88, 0.87, 0.85), "dark": Color(0.1, 0.1, 0.12),
		"coat": Color(0.3, 0.22, 0.38), "accent": Color(0.42, 0.66, 0.72), "hat": "cowboy", "ears": "cat",
	},
	# 以下四种是子项目②新增:顺序与 Species.IDS 一致(下标随协议冻结);造型在 ②d 按物种配方重做
	{
		"id": "turtle", "label": "乌龟",
		"fur": Color(0.42, 0.55, 0.28), "muzzle": Color(0.76, 0.68, 0.42), "dark": Color(0.4, 0.33, 0.18),
		"coat": Color(0.55, 0.16, 0.12), "accent": Color(0.78, 0.62, 0.3), "hat": "bowler", "ears": "none",
	},
	{
		"id": "alpaca", "label": "羊驼",
		"fur": Color(0.78, 0.66, 0.5), "muzzle": Color(0.8, 0.74, 0.62), "dark": Color(0.35, 0.26, 0.18),
		"coat": Color(0.7, 0.16, 0.14), "accent": Color(0.25, 0.6, 0.58), "hat": "cap", "ears": "pointy",
	},
	{
		"id": "monkey", "label": "猴子",
		"fur": Color(0.42, 0.26, 0.14), "muzzle": Color(0.8, 0.62, 0.48), "dark": Color(0.16, 0.09, 0.05),
		"coat": Color(0.7, 0.12, 0.1), "accent": Color(0.82, 0.62, 0.25), "hat": "cap", "ears": "round",
	},
	{
		"id": "crocodile", "label": "鳄鱼",
		"fur": Color(0.24, 0.46, 0.22), "muzzle": Color(0.76, 0.7, 0.45), "dark": Color(0.1, 0.16, 0.08),
		"coat": Color(0.22, 0.22, 0.24), "accent": Color(0.72, 0.16, 0.12), "hat": "cowboy", "ears": "none",
	},
	# 2026-10-10 追加(协议 v10):熊猫、企鹅
	{
		"id": "panda", "label": "熊猫",
		"fur": Color(0.80, 0.79, 0.76), "muzzle": Color(0.82, 0.80, 0.76), "dark": Color(0.12, 0.11, 0.12),
		"coat": Color(0.70, 0.14, 0.12), "accent": Color(0.84, 0.64, 0.24), "hat": "douli", "ears": "round",
	},
	{
		"id": "penguin", "label": "企鹅",
		"fur": Color(0.12, 0.14, 0.2), "muzzle": Color(0.80, 0.80, 0.78), "dark": Color(0.06, 0.07, 0.1),
		"coat": Color(0.12, 0.14, 0.2), "accent": Color(0.72, 0.16, 0.14), "hat": "beanie", "ears": "none",
	},
]


static func species(index: int) -> Dictionary:
	return SPECIES[posmod(index, SPECIES.size())]


static func first_free_species(used: Array) -> int:
	# 新酒客取第一个没人用的物种,同桌不撞脸;物种全被占用(人数超过物种数)时才轮流重复
	return Species.first_free(used)


# —— 调色板:部件键 → [sRGB 颜色, 粗糙度, 金属度] ——

# 动森式粉彩(2026-10-08):物种调色板先「提亮暗色」——明度按 PASTEL_FLOOR 往上抬(色相、饱和度不变,黑帽子变深靛、
# 深棕,不出纯黑),再按最大通道等比压到 ALBEDO_CAP 以下(保持色相)。上限从写实版的 0.65 放宽到 0.72:卡通光照的暗面
# 留了 toon_shadow 的光、亮面整片是满光,整体比写实光照亮,再高(≥0.78)奶油色、白毛在烛光下就发白一片。
# 爪子在桌上离烛光最近,再压暗一档
const ALBEDO_CAP := 0.72
const PASTEL_FLOOR := 0.15
const EYE_WHITE := Color(0.74, 0.73, 0.7)   # = patron_eye.gdshader 的巩膜(奶白,略高于上限:眼白要比脸亮)
const PAW_SHADE := 0.8
const LAPEL_DARKEN := 0.35   # 翻领用压暗的外套色:浅色强调色做翻领会在胸前拼出一个突兀的「A」字
# 动森式 2 头身(2026-10-08 用户追加「搞成动森那种风格」,接在 Q 版之后):头整体(颅骨、吻、眼、帽、头部特件)按头心
# 放大 HEAD_SCALE 倍,前后方向再乘 HEAD_DEPTH(脸更平、吻更短,像软胶玩具的大圆头);物种 LOOK 里的数字不动,配方里
# 统一换算(纯数组运算,工作线程安全)。头心 (0, 0.12, 0) 不动,瞄准点、机位目标照旧。
# 耳朵、眉毛不跟着放那么大(EAR_SCALE / BROW_SCALE):动森的大头上五官和耳朵相对小,头才显得圆;
# 眼睛在头放大之上横竖再放 EYE_SCALE、前后压到 EYE_DEPTH:大而平,像画在脸上。
const HEAD_CENTER := Vector3(0, 0.12, 0)
const HEAD_SCALE := 1.95
const HEAD_DEPTH := 0.86
const EYE_SCALE := 1.05
const EYE_DEPTH := 0.42
const EAR_SCALE := 1.5
const BROW_SCALE := 1.45
# 帽子横向跟头一起放大(戴得上),竖向只放 HAT_SCALE_Y:矮胖的软胶玩具帽,礼帽顶也不碰名牌
const HAT_SCALE_Y := 1.15
# 躯干:竖向压扁(绕髋部,Body 局部 y = 0)、横向略加宽,肚子更圆;肩、领口、头枢轴跟着降低(Patron.SHOULDER / HEAD_PIVOT)
const BODY_SQUASH := 0.82
const BODY_WIDEN := 1.06
# 腿:大腿缩短、小腿垂在座面前沿,圆圆的小脚悬在半空(座面高度不变)
const FOOT_CHUBBY := 1.2
# 每个酒客的部件网格(左右手不对称,各一份;耳朵、眉毛、手臂左右共用)
const PARTS := ["body", "neck", "head", "eyes", "brow", "ear", "hat", "arm", "paw_l", "paw_r", "fist", "legs"]


static func look_of(spec: Dictionary) -> Dictionary:
	return SpeciesLooks.look(Species.index_of(spec["id"]))


static func palette(spec: Dictionary) -> Dictionary:
	# 物种调色板(sRGB,已封顶):部件键 → Color
	return SpeciesLooks.palette(look_of(spec))


static func head_scale(look: Dictionary) -> Vector3:
	# 头的放大倍数:前后方向乘 HEAD_DEPTH;长吻物种可以在 head.scale_z 里再少放一点(鳄鱼:吻尖不捅到桌心)
	return Vector3(HEAD_SCALE, HEAD_SCALE, HEAD_SCALE * look["head"].get("scale_z", HEAD_DEPTH))


static func head_point(look: Dictionary, p: Vector3) -> Vector3:
	# LOOK 里写的 Head 局部坐标 → Q 版放大后的位置(按头心缩放;眉、耳、帽枢轴和看向用)
	return HEAD_CENTER + (p - HEAD_CENTER) * head_scale(look)


static func head_xform(look: Dictionary) -> Transform3D:
	# 头部网格整体的 Q 版放大(绕头心):配方开头 push、结尾 pop
	return Transform3D(Basis.from_scale(head_scale(look)), HEAD_CENTER - HEAD_CENTER * head_scale(look))


static func pivot_scale(factor: float) -> Transform3D:
	# 挂在头上的枢轴部件(眉 BROW_SCALE、耳 EAR_SCALE)网格绕自己的原点等比放大,枢轴位置另用 head_point 换算
	return Transform3D(Basis.from_scale(Vector3.ONE * factor), Vector3.ZERO)


static func hat_scale(look: Dictionary) -> Vector3:
	# 帽子:横向跟头,前后跟头的前后倍数(戴在压扁一点的大圆头上),竖向只放 HAT_SCALE_Y
	var s := head_scale(look)
	return Vector3(s.x, HAT_SCALE_Y, s.z)


static func brow_point(look: Dictionary) -> Vector3:
	# 眉心枢轴(右侧,左侧取 x 镜像):眼睛额外放大后上沿抬高,眉毛跟着抬,不压在眼睛上
	var e: Dictionary = look["eyes"]
	var size: Vector3 = e.get("size", Vector3(0.04, 0.045, 0.02))
	var lift := size.y * HEAD_SCALE * (EYE_SCALE - 1.0) * 1.1
	return head_point(look, look["brows"]["pos"]) + Vector3(0, lift, 0.0)


static func pastel(c: Color) -> Color:
	# 提亮暗色:明度 v → PASTEL_FLOOR + (1 − PASTEL_FLOOR)·v,色相不变;越暗的颜色饱和度收一点
	# (深棕提亮后不变成橘色,深蓝不变成宝蓝),之后再 capped
	return Color.from_hsv(c.h, c.s * (1.0 - 0.3 * (1.0 - c.v)), PASTEL_FLOOR + (1.0 - PASTEL_FLOOR) * c.v, c.a)


static func capped(c: Color) -> Color:
	# 按最大通道等比缩放到 ALBEDO_CAP 以下,色相不变
	var peak := maxf(c.r, maxf(c.g, c.b))
	return c if peak <= ALBEDO_CAP else Color(c.r * ALBEDO_CAP / peak, c.g * ALBEDO_CAP / peak, c.b * ALBEDO_CAP / peak, c.a)


# —— 共享网格 ——

static func recipes(spec: Dictionary) -> Dictionary:
	# 部件名 → 配方;Patron 构建与启动预建共用这张表,缓存 key 只在 part_key 里拼
	var index := Species.index_of(spec["id"])
	var look := SpeciesLooks.look(index)
	var hooks := SpeciesLooks.script_of(index)
	var pal := SpeciesLooks.palette(look)
	return {
		"body": func(f): PatronBuilder.body(f, look, pal, hooks),
		"neck": func(f): PatronBuilder.neck(f, look, pal),
		"head": func(f): PatronHeadBuilder.head(f, look, pal, hooks),
		"eyes": func(f): PatronHeadBuilder.eyes(f, look),
		"brow": func(f): PatronHeadBuilder.brow(f, look, pal),
		"ear": func(f): PatronHeadBuilder.ear(f, look, pal),
		"hat": func(f): PatronHatBuilder.hat(f, look, pal, hooks),
		"arm": func(f): PatronBuilder.arm(f, look, pal, hooks),
		"paw_l": func(f): PatronBuilder.paw(f, look, pal, -1.0),
		"paw_r": func(f): PatronBuilder.paw(f, look, pal, 1.0),
		"fist": func(f): PatronBuilder.fist(f, look, pal),
		"legs": func(f): PatronBuilder.legs(f, look, pal, hooks),
	}


static func part_key(spec: Dictionary, part: String) -> String:
	return "patron:%s:%s" % [spec["id"], part]


static func part_material(part: String) -> Material:
	return WorldMaterials.patron_eye() if part == "eyes" else WorldMaterials.patron()


static func part_mesh(spec: Dictionary, part: String) -> ArrayMesh:
	# 酒客部件网格:按「物种:部件」缓存,所有酒客共用 WorldMaterials.patron()(眼睛用 patron_eye)
	return MeshForge.cached(part_key(spec, part), recipes(spec)[part], {&"main": part_material(part)})


static func chair_mesh() -> ArrayMesh:
	return ChairBuilder.mesh()


static func forge_jobs(first := -1) -> Array:
	# 启动时后台预建:所有物种的部件 + 椅子(材质在主线程先建好);first 指定的物种排最前面
	var jobs := [["chair", ChairBuilder.recipe, {&"main": WorldMaterials.wood("dark", true)}]]
	var order := range(SPECIES.size())
	if first >= 0 and first < SPECIES.size():
		order.erase(first)
		order.push_front(first)
	for i in order:
		var spec: Dictionary = SPECIES[i]
		var table := recipes(spec)
		for part in PARTS:
			jobs.append([part_key(spec, part), table[part], {&"main": part_material(part)}])
	return jobs
