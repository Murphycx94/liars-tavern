# 子项目② 角色:8 物种按配方程序化重塑 + 共享车削椅子 + 自选形象 + 协议 v5

> 子项目详细设计。总纲见 `2026-10-07-visual-overhaul-design.md`;冲突时以总纲第 3 节「已定决策」与第 4 节「裁定」为准。
> 状态:已确认(用户授权自审)。本文由设计 agent 起草、对抗性复核修正;文中「实测」数据来自 scratchpad 原型,未入库。

> 只读设计,仓库没有改动。原型实验在 `scratchpad/design_lab/p2/`,复核实验在 `scratchpad/design_lab/p2_review3/`。实测都在 Apple M3(8 核)上做,当时机器负载很重,耗时取多次里的最小值,中位数只作参考。本节就是 `docs/superpowers/specs/2026-10-07-visual-overhaul-design.md` §7 的正文。

## 0. 范围、依赖、交付拆分

**② 交付的内容**
- 8 个物种:狐狸、熊、猪、猫,加新的乌龟、羊驼、猴子、鳄鱼。全部按「物种配方 → 构建器 → 每个动画枢轴一个网格」重新生成。
- 着色器眼睛、腿和鞋、尾巴、能握枪的拳头。
- **共享车削椅子(C6)**。① 只把旧椅子的 13 件原样合并成 1 份网格(① §6.3「共享椅子」),车削重塑没有排进任何子项目;① §2 又把椅子和酒客写在一起(「8 种酒客与椅子」),所以由 ② 负责。
- MeshForge 的有机原语。① §6.3 只交付骨架。
- 物种网格按物种缓存,启动时在后台线程预建。
- 主菜单和等待厅可以自选形象,协议升到 v5。

**依赖 ① 交付的东西**(以 ① 设计 §6 为准,② 不重做)
- MeshForge 骨架:`push/pop`、`primitive`、`commit`、`cached`、`clear_cache`(① §6.3)。`rounded_box/lathe/loft/tube/extrude/blob/displace/paint/bake_ao` 在 ① §5.2 只是 API 草案,① 不实现。② 按 ① 草案的签名实现其中需要的部分(见 §1.4);如果 ① 提前实现了某一个,② 直接复用。
- `patron.gdshader`(`instance uniform fade`、rim)和 `WorldMaterials.patron()`。
- ① 合并好的旧椅子网格,以及「主菜单放 4 把空椅子」(① §6.4)。② 换成新椅子后,空椅子自动用同一份网格。
- F2 阴影策略:小于 8 cm 的件不投影,月光只让窗墙投影。
- V1 曝光和 albedo 上限;V4 已经把眼睛高光改成不发光。
- B0 的 `perf_probe`(可见/阴影拆分、阴影重画模式、`--assert-budget`)和 `shot.gd --stats`。

**② 对 ① 接口的改动**

这是 ② 实施计划的第一步。如果 ① 还没实现,应该在 ① 的计划里直接按这张表落地。

| 项 | ① 设计 | ② 改为 | 理由 / 兼容性 |
|---|---|---|---|
| 顶点色 | `color` 存线性值 → `COLOR.rgb`(① §5.2) | 新增 `var vertex_format`;取 `PATRON_FORMAT` 时 `COLOR.rgb` 存 **sRGB**,在 `patron.gdshader` 里转线性 | 实测 COLOR 每通道只有 8 位:0.01 存回来是 0.0078(`p2_review3/probe1.gd`),存线性值暗部会出色带。只有酒客网格用 `patron.gdshader`,② 发版时酒客网格全部换新;椅子(木纹)和道具不受影响 |
| CUSTOM0 | `RGBA_FLOAT`:木纹局部坐标 + 种子 | 按 surface 选格式:`PATRON_FORMAT` 用 `RGBA8_UNORM`(材质类 / 摆动权重 / 种子 / 透光),其余 surface 仍用 ① 的 float | 格式是每个 surface 自己的属性,两种可以并存 |
| `lathe` | `(profile, seg := 24, creases, radial)` | 末尾加可选参数 `bands := []` | 只加尾部参数,① 的调用不变 |
| `loft` | `(path, section, scales, closed := true)` | 末尾加可选参数 `caps := Vector2i(1, 1)`、`bands := []`。② 要的椭圆截面 = 单位圆 `section` + 每圈 `scales`(rx, rz) | 同上 |
| `tube` | `(path, radii: PackedFloat32Array, sides := 8)` | 不变;粗细一致时传常量数组 | — |
| `commit` | `commit(shadow_mesh := false)` | 不变。另加实例方法 `arrays() -> Array`(任意线程可调)和静态方法 `commit_arrays(arrays: Array, format: int) -> ArrayMesh`(只在主线程调) | 线程边界见 §1.9 |

**交给 ③ 的东西**
- 右手的握拳网格 `PawFist`。
- 握枪锚点 `HOLD_OFFSET` 由 ③ 重调。
- ② 发版时用的还是 ① 的三节点旧左轮,所以拳头按旧握把(握把在原点 6 cm 以内)来调。

**内部批次**:各批单独提交,整个 ② 只发一次版。
- ②a 管线:`Species`、配方 schema、MeshForge 有机原语和 `PATRON_FORMAT`、`PatronBuilder`、`ChairBuilder`、`SpeciesCache`、两个着色器、重写 `Patron`、结构/预算/几何测试。狐狸作为参考物种在这一批做完,并用**真实构建器**(含 paint、AO、displace、UV 写入)复测单物种耗时,作为 §1.9 的门槛。
- ②b 自选形象和协议 v5(可以和 ②c 并行)。
- ②c 熊、猪、猫。
- ②d 乌龟、羊驼、猴子、鳄鱼。
- ②e 截图调参、性能验收、联机冒烟、发版。

提交信息示例:
- `feat: 酒客改为按物种配方程序化建模(有机体素、着色器眼睛、每枢轴一个网格)`
- `feat: 椅子改为共享车削温莎椅`
- `feat: 自选形象(主菜单挑选、等待厅可换、房主先到先得;协议 v5)`
- `feat: 新增乌龟、羊驼、猴子、鳄鱼`

---

## 1. 角色构建

### 1.1 节点与网格布局(每个动画枢轴一个网格)

动画节点的名字、父子关系、静止变换全部不变,只是每个枢轴下面的零件合成一个 MeshInstance3D。耳朵和眉毛的 MeshInstance3D 本身就当枢轴用。

```
Patron(座位地面,面朝 -Z)
├─ Chair        ChairBuilder 共享网格(§1.6),木纹材质              投影;不参与褪灰
├─ Legs         腿 + 鞋 + 尾巴(座位坐标,静态)                     投影;每帧 position.y = maxf(body.position.y - HIP.y, 0.0)
│               尾巴摆动在顶点着色器里做,不用单独枢轴
└─ Body (HIP, rot.x = -lean)
   ├─ BodyMesh  躯干 + 服装 + 毛领 + 物种特件(龟壳)                投影
   ├─ Neck (_neck_base,每帧由 _fit_neck 写变换)
   │   └─ NeckMesh  y 从 0 到 1 的单位高车削体                       投影;上面不挂任何东西
   ├─ Head (HEAD_PIVOT)
   │   ├─ HeadMesh  颅骨 + 口鼻 + 花纹 + 嘴 + 牙 + 胡须/胡子/眼镜/卷毛   投影
   │   ├─ Eyes      两只眼一个网格,材质 patron_eye                   不投影
   │   ├─ BrowL / BrowR                                              不投影
   │   ├─ EarL / EarR(原点在耳根;乌龟和鳄鱼没有)                  投影
   │   └─ Hat (Node3D "Hat") └─ HatMesh                              投影
   ├─ ArmL / ArmR (SHOULDER 镜像)
   │   ├─ SleeveMesh  从 0 放样到 z −0.35(袖口压住爪腕),肘部弯曲只在网格内部   投影
   │   └─ Hand (0, 0, -0.4)
   │       ├─ PawOpen                                                投影
   │       └─ PawFist(只有右手有,默认隐藏)                          投影
   └─ Fan
```

**实例数**
- 可见 15 个:Chair、Legs、BodyMesh、NeckMesh、HeadMesh、Eyes、BrowL/R、EarL/R、HatMesh、SleeveL/R、PawL/R。
- 乌龟和鳄鱼没有耳朵,是 13 个。
- 投影的 12 个:Chair、Legs、Body、Neck、Head、Hat、两只耳朵、两条袖子、两只爪。
- 不投影:眼睛、眉毛。
- 符合预算:≤16 个可见实例,其中 ≤12 个投影。Fan 子树(手牌)不计入。

| 约束 | 怎么保住 | 守护测试 |
|---|---|---|
| 单段手臂 IK:SHOULDER 全物种共用,ARM_LENGTH,Hand 是直接子节点 | `_build_arm`(patron_3d.gd:169-177)只换网格。袖子放样从 0 到 z −0.35:袖口半径 0.056 压住爪腕,爪掌 blob 以 Hand 为中心,向后到 z≈−0.34。弯曲是向外下方 2–3 cm 的平面弧。物种差异只做在肩以下;袖山半径 ≤0.08,所以右肩 x ≤0.29 | test_table_world.gd:36-39,test_patron_arms.gd:124,test_patron_species |
| 爪贴桌:爪底 = Hand.y − 0.0464,`SIT_BAND` 0.03–0.07,爪顶 < 桌面 +0.095 | PAW_RADIUS、PAW_SCALE 常量保留,作为接触契约(patron_3d.gd:10-11、319)。张开的爪烘焙 +27° 俯仰。在静止坐姿(手臂俯 ≈27°)下按**座位坐标**量:最低顶点 = Hand.y − 0.0464 ±4 mm,最高 ≤ Hand.y + 0.045 | test_patron_arms 全部;test_patron_species 顶点级用例 |
| 弹簧脖子:单位高网格,顶端离头枢轴 ≤5 mm | NeckMesh 的 AABB 是 y∈[0,1],父节点只有 Neck;毛领放在 BodyMesh 里 | test_patron_neck(参数化加入羊驼、鳄鱼) |
| 头心:Head 局部 (0, 0.12, 0) | 每个物种配方的 `head.skull[0]` 中心都放在这里(patron_3d.gd:279-280 不改) | test_patron_species:检查配方 skull[0],以及 HeadMesh 在 x 方向对称 |
| 4 人同时探头不相撞 | NECK_REACH 0.85(patron_3d.gd:15)只考虑了头球。新增 `FRONT_REACH_MAX := 1.15`,每个物种 `neck_reach = minf(NECK_REACH, FRONT_REACH_MAX − front_extent)`。`front_extent` 是头部子树静止时向 −Z 伸出最远的距离(含吻、鼻、帽檐),由构建器输出。静态 `clamp_neck` 不改 | test_patron_species 两两对坐;test_patron_neck(鳄鱼用 `neck_reach()`) |
| 手牌可见性 ≤5% | 头部子树的几何离头心向后 ≤0.22 m;测试改为 8 个物种都跑,用三角形精确求交(§4) | test_hand_visibility |
| 眨眼、看向、抖耳、表情 | 眨眼和看向改成眼睛着色器的实例参数,时序不变(0.06 s 闭、0.08 s 睁)。抖耳仍是 `rotation:x` 减 0.3(patron_3d.gd:230-235)。欧拉顺序 YXZ 下抖耳不改变耳朵的 x 坐标。眉毛仍补间 `rotation:z` 和 `position:y`,基准高度取配方的眉位,不再写死 0.222(patron_3d.gd:299) | test_patron_species 动画用例 |
| 死亡:身体和头转动、帽子打飞恰好 1 个碎片、1.4 s 褪灰 | `die()` 改成对 `_meshes`(含帽子,不含 Chair)和 Eyes 用 `tween_method` 设 `fade`;每次设之前检查 `is_instance_valid`,因为帽子可能已被 `_clear_debris` 释放。Eyes 再设 `dead=1`;Legs 设 `tail.z`(尾巴下垂)。`_knock_hat_off` 不改(patron_3d.gd:454-468)。乌龟可以覆盖死亡姿势(§2) | test_table_world.gd:101-114;test_patron_species |
| 呼吸、蹦跳:复位后 `body.position.y == HIP.y` | 不改。Legs 跟随蹦跳,但不低于地面(relief 下沉 3 cm 时腿不入地,patron_3d.gd:425) | test_table_world.gd:84;test_patron_species |
| 尾巴摆动和下垂不穿椅子、不入地 | 摆动权重只给悬空段(`tail.sway_range`);下垂在着色器里夹到地面以上(§1.7) | test_patron_species:±摆幅、下垂=1 两种状态 |
| 握枪挂点 (0, −0.01, −0.02) | 不改。`pick_up` 挂好枪后显示拳头;`lower_gun`、`die`、`reset_pose` 恢复张开的爪 | test_patron_species |

### 1.2 顶点格式与共享材质

所有酒客网格(眼睛除外)用同一种顶点格式 `MeshForge.PATRON_FORMAT`,构建时强制写满下面全部通道,即使值是 0。格式一致,某个物种第一次出现时就不会编译新的管线。这是 ② 对 ① 约定的改动,见 §0。

| 通道 | 内容 |
|---|---|
| VERTEX、NORMAL | — |
| COLOR | rgb = **sRGB** albedo(COLOR 只有 8 位),着色器里转线性;a = 烘焙 AO |
| UV | 花纹坐标,单位是米。放样取周长和长度,blob 取 θ·r 和 φ·r,车削取角度·r 和轮廓弧长,保证各部件花纹密度一致 |
| UV2 | (roughness, metallic):黄铜扣、银扣、金牙靠它保住金属感 |
| CUSTOM0(RGBA8_UNORM) | r = 材质类 / 255(0 毛、1 布、2 皮革、3 金属、4 鳞、5 甲、6 格纹、7 草编、8 针织、9 光滑皮毛;着色器用 `round(r * 255.0)` 取回);g = 尾巴摆动权重;b = 部件随机种子;a = 薄片透光(耳朵) |

**材质**:每个酒客 2 个共享材质,加上椅子的木纹材质。
- `WorldMaterials.patron()`:① 提供,② 扩展。
- `WorldMaterials.patron_eye()`:新增,走 `_cached`(materials.gd:161-165),`clear_cache` 自动覆盖。

### 1.3 物种配方 schema

物种的协议级定义放在 **`src/core/species.gd`**(`class_name Species`,纯逻辑,网络层和场景层共用):
- `IDS = ["fox","bear","pig","cat","turtle","alpaca","monkey","crocodile"]`
- `LABELS = ["狐狸","熊","猪","猫","乌龟","羊驼","猴子","鳄鱼"]`
- `UNASSIGNED = -1`
- `count()`、`is_valid(v: Variant)`(要求是 int 且在范围内)、`sanitize(v) -> int`、`index_of(id)`
- `first_free(taken: Array) -> int`:按目录顺序取第一个没人用的;全被占时轮流重复,沿用原 `first_free_species` 的语义(patron_parts.gd:33-38)。

**下标就是网络上传的值,顺序在 v5 里冻结。** 以后加物种只能追加到末尾,而且要升协议版本。

外观配方是每个物种一个文件:`src/world/species/species_<id>.gd`(`class_name SpeciesFox` 等),里面只有一个 `const RECIPE := {...}`,纯数据,不放 lambda。`SpeciesRecipes.get_recipe(i)` 按 `Species.IDS` 的顺序返回配方,测试核对两边的 id 一一对应。

`patron_parts.gd` 删掉:`SPECIES` 表并进配方,`build_chair` 迁到 `ChairBuilder`(§1.6)。

字段如下。所有颜色都是 sRGB,任一通道 ≤0.80;Head 局部坐标里头心是 (0, 0.12, 0)。

```gdscript
class_name SpeciesFox
# 狐狸「老千绅士」:礼帽夹在两耳之间、燕尾服、蓬松大尾巴
const RECIPE := {
	"id": "fox", "label": "狐狸", "role": "老千绅士",
	"palette": {"fur": Color(0.80, 0.40, 0.14), "cream": Color(0.80, 0.74, 0.62), "dark": Color(0.18, 0.08, 0.04),
		"coat": Color(0.13, 0.17, 0.30), "vest": Color(0.70, 0.52, 0.22), "cravat": Color(0.78, 0.74, 0.64),
		"hat": Color(0.10, 0.08, 0.08), "band": Color(0.62, 0.16, 0.14), "brass": Color(0.78, 0.62, 0.30),
		"nose": Color(0.06, 0.05, 0.05), "pad": Color(0.22, 0.10, 0.08)},
	"head": {
		"skull": [[Vector3(0, 0.12, 0), Vector3(0.165, 0.15, 0.16), "fur"],          # 主颅骨,中心必须在头心
			[Vector3(0.09, 0.06, -0.04), Vector3(0.08, 0.055, 0.07), "cream", "mirror"],  # 腮
			[Vector3(0, 0.08, -0.17), Vector3(0.05, 0.045, 0.12), "cream"]],          # 吻根
		"blend": 0.04,
		"snout": {"kind": "tapered", "tip": Vector3(0, 0.085, -0.28), "tip_radius": 0.018, "upturn": 0.01},
		"nose": {"kind": "ball", "radius": 0.022, "color": "nose", "rough": 0.2},
		"mouth": {"kind": "smirk", "width": 0.07},
		"markings": [{"mask": "cheeks_bib", "color": "cream", "soft": 0.02}, {"mask": "nape", "color": "dark", "amount": 0.25}],
		"tufts": {"where": "cheeks", "count": 3, "length": 0.03},
		"extras": [],
	},
	"eyes": {"pos": Vector3(0.062, 0.165, -0.13), "size": Vector3(0.04, 0.045, 0.02), "iris": Color(0.80, 0.52, 0.12),
		"pupil": "round", "lid_rest": 0.15, "lashes": false},
	"brows": {"pos": Vector3(0.064, 0.222, -0.14), "style": "tuft", "color": "dark"},
	"ears": {"kind": "pointy", "pivot": Vector3(0.135, 0.21, 0.0), "rot": Vector3(0, 0, -28),
		"size": Vector3(0.05, 0.15, 0.02), "inner": "cream", "tip": "dark"},
	"hat": {"kind": "top", "pivot": Vector3(0, 0.255, -0.01), "rot": Vector3(-6, 0, 3), "ear_mode": "between",
		"crown": [0.082, 0.21], "brim": 0.118, "curl": 0.02, "band": "band", "extra": "ace_card"},
	"neck": {"base": Vector3(0, 0.55, -0.02), "radius": 0.075, "color": "fur"},
	"body": {"build": "slim", "outfit": "tailcoat", "vest": "vest", "neckwear": "cravat", "chain": true, "ruff": "cream"},
	"arms": {"sleeve": "coat", "cuff": "cravat", "radius": [0.062, 0.05, 0.056]},
	"paws": {"fingers": 4, "length": 0.03, "color": "dark", "pads": "pad", "claws": ""},
	"legs": {"pants": "coat", "foot": "oxford_spats", "spats": "cream"},
	"tail": {"kind": "brush", "route": "side_left", "radius": 0.075, "length": 0.62, "tip": "cream",
		"sway": 0.12, "sway_range": [0.35, 1.0]},
	"special": {},
	"anim": {"look_pitch_min": -0.45, "blink_speed": 1.0},
}
```

- `"special"` 放物种特件,例如乌龟的 `{"shell": {...}}`。
- `"anim"` 可以带 `die_body_rot`,覆盖死亡姿势。
- `neck_reach` 不写进配方,由构建器输出的 `front_extent` 推导(§1.1)。
- `tail.sway_range` 是沿尾长的参数区间 [t0, t1]。区间外的摆动权重为 0,区间内从 0 平滑升到 1。贴着椅子或地面的段必须落在区间外。
- 默认值都定义在 `PatronBuilder.DEFAULTS` 里,配方只写和默认不同的字段。

### 1.4 MeshForge 有机原语(② 实现;签名与 ① §5.2 草案兼容)

所有原语都是纯数组运算:不碰节点、RenderingServer、静态缓存,可以在线程里跑,也能无头跑。

```gdscript
const PATRON_FORMAT := ...     # VERTEX|NORMAL|COLOR|TEX_UV|TEX_UV2|CUSTOM0(RGBA8_UNORM)|INDEX
var vertex_format := 0         # 0 = ① 的默认格式(COLOR 线性、CUSTOM0 float);PATRON_FORMAT 时 COLOR 存 sRGB,并写满 UV/UV2/CUSTOM0
var material_class := 0        # → CUSTOM0.r
var sway := 0.0                # → CUSTOM0.g;loft 在 sway_range 内按参数自动递增
func blob(center: Vector3, shapes: Array, seg := 40, rings := 24, k := 0.03) -> MeshForge
	# 星形射线行进:各椭球远交点的最大值作下界 t0(平滑并集只会往外鼓,幅度 ≤k),
	# 在 [t0, t0+k] 里二分 7 次;法线取 SDF 前向差分;顶点色按 smin 权重在形状色之间混合
func loft(path: PackedVector3Array, section: PackedVector2Array, scales: PackedVector2Array, closed := true,
		caps := Vector2i(1, 1), bands := []) -> MeshForge          # bands:[[t, 颜色键]...],在色带边界复制一圈顶点,得到硬边色带
func loft_c(path: PackedVector3Array, width: PackedFloat32Array, cup := 0.6) -> MeshForge   # C 形截面:耳朵、帽檐卷边、领子
func tube(path: PackedVector3Array, radii: PackedFloat32Array, sides := 8) -> MeshForge    # 胡须、表链、嘴线、眼镜、颏绳、马刺
func lathe(profile: PackedVector2Array, seg := 24, creases := PackedInt32Array(), radial := Callable(),
		bands := []) -> MeshForge                                    # radial(angle, y):帽檐卷边、压痕、耳洞
func mark() -> int
func displace(fn: Callable) -> MeshForge          # 毛簇、卷毛团、羊驼绒、甲片凹槽
func paint(mask: Callable, c: Color, soft := 0.0) -> MeshForge
func project_to(shapes: Array, k: float, p: Vector3, lift := 0.002) -> Vector3   # 把点贴到颅骨表面:眉毛、眼窝、胡子
func bake_ao(occluders: Array, strength := 1.0) -> MeshForge   # [[中心, 半径]...] 解析球遮挡:腋下、领口、帽檐下
func arrays() -> Array                                          # 任意线程
static func commit_arrays(arrays: Array, format: int) -> ArrayMesh   # 只在主线程调用
```

`commit(shadow_mesh := false)` 保持 ① 的签名,内部调用 `arrays()` 和 `commit_arrays()`。

**实测**(原型 `design_lab/p2/forge_proto.gd`;只生成几何)
- 最初的写法(12 步粗扫 + 10 次二分):一个头 50 ms 左右。改成解析下界后,40×24、4 个形状的颅骨最小 17 ms。
- 一个满细节物种的全部部件:狐狸、鳄鱼、乌龟最小分别是 25 / 21 / 31 ms,负载下中位数 26–74 ms。
- 原型不含 paint、AO、displace、UV/UV2/CUSTOM0 写入。复核实测(`p2_review3/probe4.gd`):paint 每遍 0.16 µs/顶点,4 个遮挡球的 bake_ao 0.67 µs/顶点。一个物种约 1 万顶点,估计还要再加 15–25 ms。②a 用真实狐狸构建器复测,门槛是 M3 单线程最小值 ≤60 ms,超出就降 blob 分辨率或合并 paint 遍数。
- 原型的「8 物种并行墙钟 167–208 ms / 串行 317–537 ms」是低优先级任务测的,实际只用了 2 个线程(§1.9)。
- 提交成 ArrayMesh:每个物种 0.4–1.0 ms(原型格式);PATRON_FORMAT 通道更多,②a 复测。

### 1.5 PatronBuilder 各部件要点

文件划分,每个文件 ≤400 行:
- `src/world/patron_builder.gd`:编排、躯干和服装、腿和尾巴。
- `patron_head_builder.gd`:头、眼、耳、眉。
- `patron_hat_builder.gd`:帽子。
- `patron_limb_builder.gd`:袖子、爪、拳头、鞋。

入口是 `static func build(recipe: Dictionary) -> Dictionary`,纯函数,任意线程可跑。返回值:
- `"parts"`:{部件名: surface arrays},部件名为 `body neck head eyes brow_l brow_r ear_l ear_r hat sleeve_l sleeve_r paw_l paw_r fist legs`;
- `"front_extent"`:float;
- `"tail_root"`:Vector3。

- **随机性**:随机数种子 = `hash(recipe.id)`,保证可复现。

- **头**:
  - 颅骨用 blob。口鼻:短吻并进 blob;长吻(狐狸、鳄鱼、羊驼)另做一段 loft,根部埋进颅骨 ≥2 cm。
  - 花纹用 paint,遮罩是方向和高度上的 smoothstep:狐狸白颊和围嘴、猫额头 M 纹和颊纹、猴心形脸罩、猪腮红和煤灰、鳄鱼背部深色。
  - 嘴线用 tube;牙用小车削体;鼻孔用 displace 压出凹坑。
  - 后脑加深色渐变和一簇颈毛,解决「自己的后脑勺是发光橙球」的问题。
  - 吻尖上限见 §2。

- **眼**:
  - 眼心先沿头心射线投到颅骨表面,再往里收 40%,所以向外凸出 ≤8 mm,侧面不鼓出来。
  - 眼睛是扁椭球帽,UV 按正面平面投影:左眼 u∈[0, 0.5),右眼 u∈[0.5, 1]。

- **眉**:5 圈椭圆沿额头弧线放样,用 `project_to` 贴在颅骨上方 2 mm,内端粗、外端细。

- **耳**:
  - 用 C 形截面放样,网格原点在耳根。
  - 薄片透光标记 a=1,被壁炉逆光照时耳廓发红。
  - 狐狸耳尖、耳背用深色。

- **帽**:车削轮廓,`radial` 回调做卷边、压痕和耳洞;帽带的硬边色带靠 `bands` 复制轮廓点。
  - 礼帽:收腰帽冠,两侧檐卷起。
  - 圆顶礼帽:檐边卷边。
  - 牛仔帽:顶部压痕、前捏、两侧上卷,右侧卷得更高。
  - 司机帽:8 瓣蓬冠加短帽舌。
  - 药盒帽:配颏带。
  - 宽松帽:檐前后下垂。
  - 迷你草帽:草编材质类。
  - 亡命徒平檐帽:配银扣。
  - 构建器同时导出 `hat_profile(recipe)`(轮廓加同一个 radial 函数)和耳洞椭圆,给耳帽间隙测试用。

- **脖子**:车削出单位高的圆柱,用光滑皮毛材质类(9),表面没有颗粒花纹,拉长 8.6 倍也不会出现条纹。

- **躯干和服装**:
  - 椭圆截面放样(28 段 × 约 18 圈),按体型查表(纤瘦 / 圆肚 / 大肚 / 龟甲 / 绒团)。
  - 外套是同一路径偏移 6–10 mm 的第二层放样,前襟开口。
  - 翻领、口袋盖用 `extrude` 投影到外套上;扣子是小车削体;表链是悬链线 tube。
  - 毛领贴在领口一圈(① 的 NECK_BASE,或羊驼的 neck_base),遮住脖子接缝。
  - 胸前和领饰在胸口高度(身体局部 Y 0.35–0.55)保持 Z ≥ −0.24,让出对手牌扇(patron_3d.gd:40)。
  - 骨盆和衣摆一直伸进座面以下,蹦 8 cm 也看不到缝。

- **袖子**:
  - 半径 0.064 → 肘部 0.05 → 袖口前 0.056,肘内侧有 2–3 道褶。路径止于 z −0.35。
  - 熊、猪是卷到小臂的衬衫袖,下面露出皮毛小臂;羊驼是绒袖。

- **爪和拳头**:
  - 掌心是 blob,中心在 Hand;4 根手指(猴子手指长,猪是 3 根粗指)和一根拇指用 loft。
  - 肉垫、爪尖用 paint 和小车削体。
  - 张开的爪烘焙 +27° 俯仰。
  - 拳头是圆的(手指卷起),只有右手生成,按 ① 旧左轮的握把位置调。

- **腿和鞋**(Legs,座位坐标):
  - 大腿沿座面伸到 z −0.12,膝高约 0.5(< 桌面 −0.1 = 0.68)。
  - 小腿落地,两腿 x ±0.1,外缘 ≤0.175,让开前椅腿(±0.2, z −0.04)。
  - 鞋子按配方:鞋罩牛津鞋、光脚肉垫、工靴、牛仔靴配马刺、补丁旧靴、两趾软蹄、长趾光脚、三爪光脚。

- **尾巴**:放样路径写在配方里,单位是座位坐标;摆动权重只在 `sway_range` 内从 0 升到 1。
  - 粗尾(狐狸、鳄鱼)从左侧翻过座面边缘(x −0.24)。
  - 细尾(猫、猴)走座面和靠背之间的缝(y 0.475–0.53)。
  - 小尾(猪的螺旋尾、熊的短尾、乌龟的尖尾、羊驼的绒尾)贴在骨盆后面,摆幅 ≤0.05。
  - Legs 实例设 `extra_cull_margin = 0.12`,因为顶点摆动会超出包围盒。

### 1.6 共享车削椅子 ChairBuilder(C6,新增)

- **文件**:`src/world/chair_builder.gd`(`class_name ChairBuilder`)。
- **网格**:`static func mesh() -> ArrayMesh` 走 `MeshForge.cached("chair", ...)`,材质用 `WorldMaterials.wood("dark")`,CUSTOM0 按 ① 的木纹局部坐标写。4 把椅子共享一份网格(自动实例化),三角形 ≤1.3k。
- **造型**:
  - 车削的腿和靠背柱:收腰、圆头。
  - 座面圆角,前缘下卷。
  - 3 根纺锤靠背杆,加弧形顶梁。
  - 不加扶手(`die` 姿势会撞上)。
- **布局尺寸沿用旧椅子**(patron_parts.gd:41-51),作为常量公开给测试和尾巴路径:
  - `SEAT_Y := Vector2(0.425, 0.475)`,`SEAT_HALF_X := 0.24`,`SEAT_Z := Vector2(-0.08, 0.36)`;
  - 前腿 (±0.20, z −0.04),后腿 (±0.20, z 0.32),`LEG_RADIUS` ≤0.022;
  - 靠背柱 (±0.20, z 0.34);
  - 靠背杆底端 `BACK_GAP_TOP` ≥0.53,座面和靠背之间留 ≥5.5 cm 的缝;
  - 顶 ≤1.1。
- **测试接口**:`static func solids() -> Array` 返回座面盒、腿和柱的圆柱、靠背杆盒,给「不穿椅子」判定用。
- **迁移**:
  - 删除 patron_parts.gd 之前,先把 `build_chair`(或 ① 放置椅子构建的地方)迁到这里。
  - ① 的主菜单空椅子改调 `ChairBuilder.mesh()`。
  - Chair 仍挂在 Patron 下,跟着登场缩放;换形象时椅子也会随新 Patron 冒烟重建,由烟雾遮住。

### 1.7 着色器

**`patron.gdshader`(在 ① 基础上加)**
- 实例参数(共 3 个):
  - `instance uniform vec4 tail`:x 相位,y 摆幅(弧度),z 下垂(0–1,出局时用)。
  - `instance uniform vec3 tail_root`:尾根位置。
  - `fade`(① 已有)。
- vertex():
  - 当 `w = CUSTOM0.g > 0` 时,顶点绕 `tail_root` 的竖轴转 `sin(TIME*1.3 + tail.x) * tail.y * w² * (1 - tail.z)`。
  - 下垂:`float d = tail.z * w * w * 0.08; VERTEX.y = max(VERTEX.y - d, min(VERTEX.y, 0.01));`,不会压到地面以下(Legs 原点在地面)。
  - 阴影 pass 跑同一个顶点着色器,影子会跟着动。
- fragment():
  - `albedo = srgb→linear(COLOR.rgb)`,`AO = COLOR.a`,`ROUGHNESS / METALLIC = UV2`;材质类 `round(CUSTOM0.r * 255.0)`。
  - 按材质类叠加花纹:
    - 毛:纹理顺着 UV.y 拉长,亮度 ±5%;
    - 布:细织纹,sheen 用加大的 `RIM`/`RIM_TINT` 近似(Godot spatial shader 没有 SHEEN 输出,不写 light());
    - 皮革:有斑块,粗糙度低一些;
    - 鳞:voronoi 格,格缝压暗 25%;
    - 甲:生长环;
    - 格纹:两种(猪的红格衬衫、乌龟的红黑格法兰绒);
    - 另有草编、针织。
  - 花纹都用 `fwidth` 抗锯齿。
  - a=1 的薄片输出 `BACKLIGHT = albedo * 0.3`。
  - 现有卡通边光 rim 0.3 / tint 0.5 保留。
  - 不加描边,不做色阶(cel)。
- 性能:目标是 seat 视角 ≤0.15 ms,由 perf_probe 的 `patron-flat` A/B 用例实测(§5)。

**`patron_eye.gdshader`(新增)**
- 实例参数共 10 个,上限是 16:
  - `vec4 look`:左右瞳孔偏移,单位是眼 UV;
  - `float lid`(眨眼)、`lid_rest`(物种默认眼睑:乌龟 0.35,狐狸 0.15)、`lid_tilt`(生气为正、担心为负);
  - `dead`、`fade`;
  - `vec3 iris_color`、`vec3 lid_color`(取皮毛色);
  - `float pupil_shape`:0 圆、1 竖缝(猫、鳄鱼)、2 横椭圆(羊驼);
  - `lashes`。
- 画法:
  - 巩膜米白 0.80,虹膜半径 0.55,瞳孔偏移夹到 0.35。
  - 高光是画上去的,不自发光;眼面 roughness 0.15,灯光还会给出真高光。
  - 上眼睑线按 `max(lid, lid_rest) + lid_tilt * side * x` 填皮毛色。
  - `dead` 时画 X(两条到对角线的距离),隐藏虹膜。
  - 全部用 `fwidth` 平滑。

### 1.8 `Patron` 改动(src/world/patron_3d.gd)

- **常量**:
  - 8-36 行的常量全部保留,NECK_BASE 作为默认值。
  - 删掉 `LAPEL_DARKEN`(52)。
  - 新增 `DIE_BODY_ROT := Vector3(0.55, 0.15, -0.5)`、`DIE_HEAD_ROT`、`FRONT_REACH_MAX := 1.15`。

- **成员**:
  - `_eyes` 字典数组(63)换成 `_eye: MeshInstance3D` 加 `_look := Vector4.ZERO`。
  - `_materials`(67)换成 `_meshes: Array[GeometryInstance3D]`,不含 Chair。
  - 新增 `_legs`、`_fist`、`_paw_r`、`_neck_base`、`_neck_reach`、`_brow_y`、`_anim`。

- **`_build`(103-144)**:
  - 先取 `var recipe := SpeciesRecipes.get_recipe(species_index)` 和 `var built := SpeciesCache.meshes(species_index)`。
  - 按 §1.1 的顺序建节点,酒客网格材质统一用 `WorldMaterials.patron()`,Chair 用 `ChairBuilder.mesh()`。
  - 节点名照旧:Body、Neck、Head、Hat、ArmL、ArmR、Hand、Fan。
  - `_neck_base = recipe.neck.base`;132 行的枢轴位置和 `_fit_neck`(267-271,含 270 行的粗细基准)改用 `_neck_base`。
  - `_neck_reach = minf(NECK_REACH, FRONT_REACH_MAX - built.front_extent)`。

- **重写**:`_build_head`(147-166)和 `_build_arm`(169-177)只建节点、挂网格;`_mat`(180-189)删掉。

- **眼睛实例参数**:Eyes 在构建时显式设好 `iris_color / lid_color / pupil_shape / lid_rest / lashes`,不依赖默认值。

- **`_animate_idle`(194-220)**:
  - 俯仰下限改用 `_anim.look_pitch_min`(205 行)。
  - 瞳孔插值(211-216)改成算左右两眼的偏移,写进 `look`;变化超过 0.002 才写。
  - 加一行:`_legs.position.y = maxf(body.position.y - HIP.y, 0.0)`。

- **`_blink`(223-229)**:用 `tween_method` 设 `lid`,0→1 用 0.06 s,1→0 用 0.08 s,再除以 `blink_speed`。抖耳(230-235)不改。

- **`set_neck_target`(240-241)**:`_neck_target = clamp_neck(seat_offset).limit_length(_neck_reach)`。静态 `clamp_neck` 不变(table_screen.gd:148、test_cursor_look.gd:42 依赖它)。新增 `func neck_reach() -> float`。

- **`set_expression`(292-299)**:`position:y` 改成补间到 `_brow_y + lift`;同时并行补间眼睛的 `lid_tilt`(angry +0.25,worried −0.2,其余 0),顺带做完 C9。

- **握枪**:`pick_up`(387-396)在 reparent 之后调 `_set_fist(true)`;`lower_gun`(410-419)在枪放回桌面后调 `_set_fist(false)`。

- **`die`(431-451)**:
  - 设 `dead = 1`。
  - 死亡姿势取 `_anim.get("die_body_rot", DIE_BODY_ROT)`。
  - 褪色:`fall.tween_method(_set_fade, 0.0, 1.0, 1.4)`,作用在 `_meshes` 和 `_eye` 上;帽子打飞后仍在列表里,照样褪。`_set_fade` 对每个实例先检查 `is_instance_valid`。
  - Legs 的 `tail.z` 补间到 1。
  - 带枪死亡时调 `_set_fist(false)`。

- **`reset_pose`(488-500)**:恢复张开的爪,`lid_tilt` 归 0。

- **新增**:`func species_id() -> String`;静态 `func build_portrait_head(index) -> Node3D`,只建头部子树,给头像图集用。

### 1.9 缓存、预建、生成成本

`src/world/species_cache.gd`(`class_name SpeciesCache`,全部静态):

```gdscript
static func prebuild(first: int) -> void      # 主线程:先在主线程取好 8 份配方 Dictionary(加上椅子),
                                              # 再 WorkerThreadPool.add_task(task, true) 高优先级入队,first 排第一
static func poll() -> void                    # main._process:QUEUED 的任务 is_task_completed 为真时才 wait(恰好一次)→ BUILT;
                                              # 每帧最多提交一个物种(commit_arrays,约 1–2 ms)→ COMMITTED
static func is_ready(index: int) -> bool
static func meshes(index: int) -> Dictionary  # COMMITTED → 直接返回;QUEUED → wait(恰好一次)再提交;NONE → 同步构建(测试、工具走这条)
static func clear() -> void                   # main._exit_tree:把所有 QUEUED 的任务 wait 完再清空
```

- **状态机**:`NONE → QUEUED → BUILT → COMMITTED`。task id 只在 QUEUED 状态下保存,wait 之后立刻移除,所以 `poll` 和 `meshes` 不会对同一个 task 重复 wait。
- **高优先级**:复核实测(`p2_review3/probe2.gd`、`probe3.gd`)Godot 4.7 默认 `low_priority_thread_ratio = 0.3`。
  - 8 核上低优先级任务只有 2 个线程:8 个 100 ms 任务墙钟 411 ms,高优先级 105 ms。4 核机器上低优先级就是串行。
  - 主线程等一个排在队尾、还没开始的低优先级任务,要等完整个队列:412 ms 对比 103 ms。
  - 所以预建一律用高优先级。高优先级下,M3 上的预建墙钟约等于最慢那个物种的耗时;②a 实测,并用 `threading/worker_pool/max_threads=4` 的 override.cfg 模拟 4 核复测。
- **线程边界**:
  - 工作线程只读传进来的配方 Dictionary,只产出 Packed 数组;不加载脚本,不碰节点、RenderingServer、静态缓存。
  - 结果写进 `_arrays`,用 `Mutex` 保护。
  - `ArrayMesh` 只在主线程创建。
- **测试**:无头测试里同步构建。静态缓存在一次 GUT 运行中复用,第一次构建一个物种约 40–80 ms,之后几乎为 0。
- **新物种首次出现不卡**:同一个着色器、同一种顶点格式,不会触发新管线。新着色器的首次编译由主菜单的预览酒客(§3.1)和头像烘焙在启动阶段完成;首次运行(没有着色器磁盘缓存)的编译耗时计入 §5 的启动验收。
- **生成成本**:`Patron.new(i)` 在已缓存时只建约 20 个节点、设实例参数,实测无头 0.04 ms。真实渲染下由 perf_probe 的 `spawn` 用例验收(≤16 ms 帧)。所以 `revive_all` 和 `arrange`(table_world.gd:76、105)都不会卡帧。
- **主线程启动开销**:9 次提交(8 个物种 + 椅子)约 1–2 ms 一次,加上头像回读,目标 ≤60 ms,由 `--timing` 实测。
- **备选方案**:如果低端 CPU 实测后台预建超过 1 s,再加一层磁盘缓存 `user://cache/species_<build>_<配方哈希>.res`。默认不做。

---

## 2. 八个物种的造型

**统一的「圆润暖卡通」语言**
- 大头:头和身体大约 1:1.6。
- 所有轮廓都用平滑并集(k 0.03–0.045),不留基础体接缝。
- 圆角 ≥6 mm,尖端半径 ≥4 mm,爪尖钝。
- 双色毛:背深、腹和脸浅,渐变柔和。
- 大眼:约 0.04×0.045,虹膜大,高光画上去。
- 布料厚实:有滚边、缝线,黄铜件是真金属。
- 颜色饱和但不刺眼:所有颜色任一通道 ≤0.80(sRGB);皮毛和脸的**线性**亮度(`srgb_to_linear().get_luminance()`)≤0.62。

**全物种都要满足的硬约束**(由 test_patron_species 守护)
- **高度**:帽顶和耳尖在 Head 局部 y ≤0.51,对应静止时座位高度 ≤1.65 m。
- **后伸**:头部子树离头心向后 ≤0.22 m。
- **枪管净空**:帽檐在 |x| ≥0.15 处 y ≥0.20,让开太阳穴的枪管。
- **耳帽间隙**:按帽子滚转、俯仰之后的**左右两侧**分别算,并在 0、−0.15、−0.3 三个抖耳角下都成立:
  - 耳朵在帽檐之下时,帽檐在耳朵所在 x 处的最低点 ≥ 耳顶 + 4 mm;
  - 耳朵在帽檐外侧时,耳内缘在檐高处 |x| ≥ 檐半径 + 4 mm;
  - 猫的耳洞区域按「洞椭圆 + 4 mm」豁免;
  - 帽子实体用构建器导出的轮廓和 radial 函数采样。
- **猪耳离眼**:三个抖耳角下都 ≥5 cm。
- **鳄鱼眼包**:不和帽子相交。
- **胸前**:Z ≥ −0.24(身体局部 Y 0.35–0.55)。
- **肩、爪**:袖山 x ≤0.29;在静止坐姿下按座位坐标量,爪底 Hand.y −0.0464 ±4 mm,爪顶 ≤ Hand.y +0.045。
- **腿脚**:膝 ≤0.6;脚在 z −0.04 ±0.03 处 |x| ≤0.17;腿在 relief 下沉时不入地。
- **头部前伸**:`neck_reach + front_extent ≤ FRONT_REACH_MAX (1.15)`。吻尖在 Head 局部:狐狸 z ≥ −0.28,羊驼 ≥ −0.27,鳄鱼 ≥ −0.38,其余物种 ≥ −0.22。
  - 推导:都坐着时头心伸到最远离桌心 0.3625 m;轮到自己时 lean 0.31,头心再前移 9.6 cm,离桌心 0.266 m。
  - 满足这条约束时,两人对坐、其中一方前倾的最坏情况下,吻尖仍互留 2.85 cm。
- **尾巴**:静止、±摆幅、下垂=1 三种状态都不穿 `ChairBuilder.solids()`,也不低于地面 5 mm;只能走缝或从侧面翻过。

| 物种 | 角色 | 头雕 | 耳朵和帽子 | 服装 | 尾巴(走向) | 腿脚 | 标志细节 | 主色(sRGB) | 估算三角形(含椅子 1.3k) |
|---|---|---|---|---|---|---|---|---|---|
| 狐狸 | 老千绅士 | 窄额、长尖吻(吻尖 z −0.28)、腮毛三簇、白颊连到胸前成围嘴、小黑亮鼻、坏笑嘴 | 尖叶耳移到 (±0.135, 0.21),外倾 28°。小礼帽(冠 r0.082 高 0.21,檐 r0.118 两侧上卷,滚转 ≤3°)夹在两耳之间,两侧间隙 1.6 / 2.5 cm | 藏青燕尾服(燕尾垂在座面两侧、椅腿外)、金锦缎背心、奶油领巾加红宝石别针、怀表链 | 蓬松大尾 r0.075 长 0.62,从左侧翻过座面垂到椅腿外,尾尖白;摆动只给垂下段 | 藏青长裤、白鞋罩、黑牛津鞋 | 帽带上插一张 A 牌 | fur .80/.40/.14,cream .80/.74/.62,coat .13/.17/.30 | ~13.0k |
| 熊 | 酒馆老板 | 宽扁头、短圆吻(棕褐)、圆三角鼻 | 圆杯耳移到 (±0.14, 0.18),在帽檐下方,耳顶 0.23。圆顶礼帽檐 r0.14 有卷边,檐底 ≥0.248,滚转 ≤4°(低侧檐底 0.238,间隙 8 mm) | 酒红丝绒背心、奶油衬衫卷袖加红袖箍、深棕蝴蝶结、表链、大圆肚 | 短圆尾,藏在后摆里 | 格纹裤卷边、光脚(肉垫脚趾豆) | 左肩搭一条红条纹吧台毛巾 | fur .36/.21/.11,muzzle .66/.50/.34,vest .42/.11/.09 | ~12.4k |
| 猪 | 铁路司炉 | 圆脸带腮肉、上翘圆角鼻盘、凹陷椭圆鼻孔、腮红 | 软三角耳从 (±0.12, 0.215) 向前下折,耳尖在帽舌之下、眼睛外侧,三个抖耳角下离眼都 ≥5 cm。蓝白条纹司机帽 | 牛仔背带工装裤(胸兜、铜扣)、红格衬衫卷袖、红领巾 | 小螺旋尾,在座面和靠背的缝里 | 工装裤腿、厚底系带工靴 | 脸颊一抹煤灰 | skin .76/.47/.45(原值 .93 过曝),snout .80/.55/.52,denim .20/.30/.48 | ~12.5k |
| 猫 | 独行枪手 | 灰虎斑:额头 M 纹、白吻白胸、w 形嘴、tube 胡须、粉三角鼻 | 三角猫耳(±0.10, 0.25)从帽子的耳洞穿出:椭圆孔加缝线皮圈,孔沿 Z 方向放宽 ±1 cm,覆盖抖耳弧度。牛仔帽:顶部压痕、前捏、两侧上卷,右侧更高 | 皮背心、浅蓝衬衫、青色方巾、枪带和右胯枪套 | 细长虎斑尾,从缝里穿出垂在椅后,尾尖勾成问号;摆动只给垂下段 | 牛仔裤、皮护腿、尖头靴配马刺 | 马刺和枪套 | fur .46/.47/.52,stripe .22/.22/.26,bandana .20/.52/.58 | ~13.2k |
| 乌龟 | 老淘金客 | 光秃圆头、短钝喙、厚眼睑(lid_rest 0.35)、白色海象胡、黄铜圆眼镜 | 没有耳朵。软毡宽松帽,檐前后下垂 | 背甲橄榄棕(盾片中心浅、有环纹),米黄腹甲代替衬衫前襟,红黑格法兰绒袖,棕背带 | 小尖尾,藏在甲缘下 | 卡其裤、补丁旧靴 | 胡子、眼镜;眨眼慢 1.6 倍 | skin .42/.55/.28,shell .40/.33/.18,plastron .76/.68/.42 | ~14.4k(余量最小,0.6k) |
| 羊驼 | 披毯客 | 小颅骨(r0.13)、长脸、前伸的吻(吻尖 z −0.27)带分开的上唇和下排门牙、头顶一大团卷毛、大眼长睫毛 | 香蕉耳从卷毛里 (±0.10, 0.25) 竖起,外倾 12°,尖端内弯(弯的部分高于帽顶)。迷你草帽(冠 r0.05、檐 r0.07,檐高约 0.30)用颏绳戴在卷毛顶上,夹在两耳之间,间隙 2 cm | 卷绒躯干(毛团凸起)、左肩斜披条纹毯(红/芥黄/青/奶油,下摆流苏)、绿松石波洛领绳 | 短绒尾 | 绒腿、两趾软蹄 | 长脖子(见下) | fleece .78/.66/.50,face .80/.74/.62,毯红 .70/.16/.14 | ~12.8k |
| 猴子 | 酒馆跑堂 | 圆头、桃色心形脸罩、宽嘴笑 | 大圆侧耳 (±0.165, 0.13),C 形碗配桃色内耳,和帽子不冲突。红色药盒帽带金箍和颏带,斜戴 | 红色短门童夹克(金穗边、双排 8 颗铜扣)、黑裤金侧条 | 长卷尾从缝里穿出,绕左后**椅腿**(−0.20, z 0.32)1.5 圈(见下) | 裤长到小腿、光脚长趾 | 绕腿的尾巴、长手指 | fur .42/.26/.14,face .80/.62/.48,jacket .70/.12/.10 | ~12.9k |
| 鳄鱼 | 亡命徒 | 长圆吻(吻尖 z −0.38)分上下两段、两排圆钝牙加一颗金牙、头顶两个眼包、鼻孔包、颈背一排圆疙瘩 | 没有耳朵。黑色平檐低冠帽带银扣,向后推(rot.x +12°)露出眼包 | 炭灰衬衫敞胸露米黄腹鳞、红色强盗方巾、交叉两条子弹带(铜弹头是 loft 上 displace 出来的凸起) | 粗鳞尾从左侧翻过座面落地,沿地面向后弯;落地段摆动权重 0 | 破边深色裤、光脚三爪 | 金牙、子弹带 | scale .24/.46/.22,belly .76/.70/.45,bandana .72/.16/.12 | ~13.6k |

**三角形预算(各部件上限;耳、眼、眉、袖、爪都按一对合计)**
- 头 2.6k(鳄鱼 3.2k)
- 眼 0.4k,眉 0.16k,耳 0.4k
- 帽 1.0–1.2k
- 脖子 0.1k
- 躯干 3.0k(乌龟 3.8k)
- 袖子 1.1k,爪 1.3k(隐藏的拳头 0.55k 不计)
- 腿 + 鞋 + 尾 2.4k
- 椅子 1.3k
- 合计:一般物种 13.96k;乌龟(无耳、躯干 3.8k)14.36k;鳄鱼(无耳、头 3.2k)14.16k。都 ≤15k。

原型实测(不含椅子):狐狸 11.7k、鳄鱼 12.5k(吻 −0.44 的版本)、乌龟 13.1k。加上椅子,乌龟 14.4k,余量最小。

**新物种的专项约束**
- **鳄鱼的长吻**
  - 吻尖 z ≥ −0.38,`front_extent` ≈0.40,所以 `neck_reach` ≈0.75,比别人少约 0.1 m。
  - 两人对坐、一方前倾、都伸到最远平视时,吻尖与对面的狐狸互留 ≥2.5 cm;3 人局、4 人局的相邻座间隙更大。由两两对坐测试守护。
  - 低头下限 `look_pitch_min` 从 −0.45 改为 −0.30。这样吻底在自己牌扇上方仍有 ≥0.02 m;牌扇顶约在座位高度 1.05。
  - 越肩镜头下,吻朝前,远离身后的自己牌扇。偏头 0.78 rad 时,旋转后的 AABB 会伸到后方约 0.23 m,AABB 判定会误报,所以 hand_visibility 测试改成三角形精确判定。
  - 特写机位离头 1.06 m,吻尖离机位 ≥0.6 m,比近裁面 0.03 m 远得多。
- **羊驼的长脖子**
  - 头心不能动(用户已定),所以只把它的 `neck_base` 降到身体局部 (0, 0.44, −0.04)。静止时脖子露出约 0.21 m,其他物种约 0.05 m。
  - 伸到最远时脖子长 0.88 m,粗细比例夹在 0.55,伸长的脖子正好像羊驼。
  - 帽顶和耳尖在 Head 局部 ≤0.48:静止时座位高度 ≤1.62 m,欢呼蹦起时 ≤1.70 m,都低于名牌的 1.82 m。
  - 脖子用光滑皮毛材质类,只有前浅后深的渐变,拉长后不出条纹。
- **乌龟的龟壳**(数值来自 python 姿势计算)
  - 背甲后表面在身体局部 z ≤0.20。z=0.21 时,坐直姿势会在 y 0.57 处插进靠背柱(前缘 z 0.318)约 5 mm;≤0.20 时坐着、前倾、坐直都碰不到。
  - 默认死亡姿势 (0.55, 0.15, −0.5) 会让龟壳插进椅背 0.25 m。现在所有物种倒下时躯干本来就会穿椅背,龟壳只会更明显。
  - 所以乌龟用 `die_body_rot = Vector3(-0.05, 0.25, -0.85)`:向右侧歪倒,穿插为 0。头心落在 (0.55, 1.01, −0.07),在桌沿(z −0.30)外面,也高于毡面。
- **猴子的尾巴**
  - 半径 ≤0.02,从座面顶 0.475 到靠背杆底 0.53 之间那条 5.5 cm 的缝穿出。
  - 在座面后缘之后(z ≥0.40)下行,绕左后**椅腿**(−0.20, z 0.32,腿半径 ≤0.022)1.5 圈:离腿轴 0.055,y 从 0.38 降到 0.12,尾尖上卷。y ≤0.38 是为了让开座面底 0.425(留出尾半径加 2.5 cm)。
  - 绕腿段落在 `sway_range` 外,摆动权重为 0;只有缝到腿之间的悬空段轻微摆动(摆幅 ≤0.04)。
  - 尾巴在 Legs 里(座位坐标),前倾和倒下时尾巴不动,尾根被衣摆盖住。

---

## 3. 自选形象

### 3.1 主菜单(src/ui/main_menu/main_menu.gd)

**名号一行**:`_build_identity`(115-121)里,「你的名号」这一行改成 `HBoxContainer`:左边是 `SpeciesChip`(56 px 头像按钮,tooltip 写「挑选形象:狐狸 · 老千绅士」),右边是原来的昵称 LineEdit(EXPAND_FILL)。

**挑选面板**
- 点头像,在这一行下面原地展开 `SpeciesPicker`:4×2 网格,每格 88×112,72 px 头像加「狐狸 / 老千绅士」。
- 面板在滚动侧栏里,展开不会把下面的内容裁掉。
- 支持纯键盘:方向键移动,Enter 选,Esc 收起并把焦点还给头像。

**选中之后**
- 写进 `Settings.KEY_SPECIES`(存物种 id 字符串),收起面板。
- 调 `app.world.show_menu_preview(i)`:3D 预览酒客原地冒烟换人(`vanish` / `appear`),做一个 `smug` 表情。

**3D 预览**
- 前提是 ① 的「主菜单放 4 把空椅子」。自己的形象坐在 0 号椅上,0 号空椅隐藏,环绕镜头里一直能看到。
- 可选(②b 时间紧可以不做):面板展开时镜头 `move_to(world.menu_preview_view(), 1.0)`,从桌心斜上方看 0 号座,人物落在画面右侧,左侧给木牌面板;收起时调 `app.resume_menu_orbit()`(从 main.gd:138-139 抽出来)。
- 预览酒客的物种如果还没预建好,TableWorld 在 `_process` 里等 `SpeciesCache.is_ready(i)` 再登场,不阻塞主线程。

**建房和加入**
- 建房:`_on_host_pressed` 改成 `Net.host_game(pname, room_name, 0, _species)`(main_menu.gd:306)。
- 加入:`_join` 改成 `Net.join_game(pname, address, _species)`(main_menu.gd:331)。

**头像图集**:`src/world/species_portraits.gd`(`class_name SpeciesPortraits`),沿用 CardFaces 的做法(card_faces.gd:41-80)。
- 等 8 个物种都预建好,用一个 SubViewport 放 8 个 `Patron.build_portrait_head(i)`:1536×192,own_world_3d,透明背景,主光、补光、轮廓光,正交相机。
- 这个视口配一份自己的 `Environment`,tonemap 和曝光复制酒馆的设置(不开雾、辉光、SSAO),否则头像颜色会和游戏里不一样。
- `UPDATE_ONCE` 渲染一帧,读回成 8 个 AtlasTexture。
- 菜单显示出来以后才在后台启动,不阻塞启动。
- 无头,或者还没烘好时,显示物种色圆片加汉字首字(狐/熊/猪/猫/龟/驼/猴/鳄)。`SpeciesChip` 在 `_process` 里检查 `is_built()`,烘好后换上头像并停止轮询。

### 3.2 等待厅(src/ui/lobby/lobby.gd)

- **名单行**:`_player_row`(218-246)里,第 232 行的物种文字标签改成 32 px 的 `SpeciesChip`。`species == -1` 时显示「挑选中…」。
- **换形象**:自己那一行的头像是按钮,点开后在名单下面原地展开 `SpeciesPicker`,面板宽 440,放得下 4×96。
  - `taken` 由静态函数 `SpeciesPicker.taken_map(players, my_pid)` 算出:{物种下标 → 占用者名字},不含自己,忽略 −1。
  - 被占用的格子:头像压灰,下面用小字写占用者名字,按钮禁用。
  - 自己当前的格子:黄铜边框。
- **点选**:
  - 调 `Net.request_species(i)`,记下挂起的请求,面板收起,0.3 s 内不能再点。
  - 收到下一份名单(房主拒绝时也会单独回一份)时结算:
    - 自己的形象等于请求的 → 写进本机设置;
    - 是别人拿着 → 提示「「熊」刚被 阿杰 选走了」;
    - 都不是 → 静默。
- **其他行为**:准备之后也能换,换形象不会取消准备。对局中没有挑选入口。
- **删除**:`_species_of`(249-252)删掉,直接读 `player["species"]`。3D 酒客和铭牌仍走 `_refresh` 里的 `arrange`(159);`_track_nameplate` 每次刷新都会重新绑定到新的 Patron。

### 3.3 设置

`src/ui/settings.gd`:
- 新增 `const KEY_SPECIES := "species"`,存 id 字符串而不是下标,以后调整内部顺序也不会选错。
- 新增 `static func get_species(path := PATH) -> int`:id 不认识或类型不对时告警,返回 `Species.UNASSIGNED`。
- **首次启动**:在 `main._ready` 里、调 prebuild 之前解析。没有这个设置时随机选一个并立刻保存(待确认的默认值,见下)。
- 调试开关 `--species` 只覆盖本次运行,不写设置。

### 3.4 房主分配算法(src/net/lobby_model.gd)

```gdscript
func add_host(host_name: String, species := Species.UNASSIGNED) -> void:   # 12-15 行加参数
	... _insert(HOST_ID, host_name, true); request_species(HOST_ID, species)

func request_species(id: int, wanted: int) -> bool:
	# 先到先得:想要的形象空着就给;被别人占了(或下标非法)时,
	# 还没有形象的分第一个空着的,已经有形象的保持不变。返回名单是否变了(变了才广播)
	if not _members.has(id):
		return false
	var current: int = _members[id]["species"]
	var taken := _taken_except(id)   # Array
	var next := current
	if Species.is_valid(wanted) and not taken.has(wanted):
		next = wanted
	elif current == Species.UNASSIGNED:
		next = Species.first_free(taken)
	if next == current:
		return false
	_members[id]["species"] = next
	return true

func assign_unassigned() -> void    # 开局前兜底:还是 -1 的按加入顺序分第一个空着的
func species_of(id: int) -> int
```

**规则**
- `_insert`(93-95)把新成员的 species 设成 −1;`view()`(81-90)带上 `"species"`。
- 有人离开(`remove`)时只释放他的形象,别人的都不变。
- 原来因为撞车分到候补形象的人,不会因为有人离开就自动换回首选,可以在等待厅里自己换(待确认的默认值)。
- `reset_ready` 不碰形象,所以再来一局时形象不变。
- 离开后再加入算新成员,首选还空着就拿回来。
- 最多 4 人、8 个物种,一定有空着的。

**为什么握手之后才发形象**
- `rpc_join_request(pname, version)` 的签名和编号都不改(network_manager.gd:232-256),否则新旧版本互连时拿不到明确的拒绝原因。
- 形象在握手通过后用 `rpc_lobby_species` 单独发。在这一个往返里成员的形象是 −1,等待厅不建他的角色,名单显示「挑选中…」。
- 这样避免了「先给临时形象再改」的抢占问题:临时形象会挡住后来者的真实首选;把它改成可以被抢,又会让别人的角色中途变身。

### 3.5 一致性

- **所有端只渲染房主分配的形象**:等待厅名单和开局座位都带 `species`。
- **TableWorld**(src/world/table_world.gd):
  - `arrange`(39-65)读 `Species.sanitize(p["species"])`:
    - 合法值 → 用它;
    - −1 或非法值,在等待厅里(`with_revolvers == false`)→ 不建角色;
    - −1 或非法值,在对局里(`with_revolvers == true`)→ 按座位顺序在本地用 `Species.first_free` 补齐并 `push_warning`。各端拿到的是同一份 seats,补出来的结果一致。table_screen.gd:60 和 table_director.gd:95/119/138/236/250/304 都直接下标访问角色,缺角色会崩溃。
    - 只有离线工具和测试传 `{"pid"}`、不带 species 键时,才走原来的本地「第一个空着的」,保住原测试的意图。
  - `_place_patron`(68-81):
    - 角色已在、物种相同 → 按原来的逻辑平移;
    - 物种变了 → 在同一位置建新的 `Patron(species)` 并 `appear()`,旧的 `vanish()`,烟雾盖住交接;同一帧里多次变化只换最后一次。
  - `species_of`(83-87)改成 `species_index_of(pid) -> int`。
  - 新增 `show_menu_preview`、`clear_menu_preview`、`menu_preview_view`;`clear`(114-123)和 `arrange` 会自动收走预览。
- **本地分配的分歧随之消失**:原来 75-76 行按本地已有的角色挑物种,中途有人离开再有人加入时,各端顺序不同,会分出不同的物种。
- **防坏数据**:客户端也用 `Species.sanitize` 处理房主发来的值,规则同上。
- **刷屏**:房主对没有变化的请求不广播;每个对端有 0.25 s 冷却,冷却内的请求按「被拒」处理。客户端换物种时角色走缓存。

### 3.6 协议 v5

- **版本号**:`Protocol.VERSION := 5`(protocol.gd:5),注释写「v5:等待厅自选形象(lobby_species 意图;lobby_state、game_started 每位玩家带 species 下标)」。

- **Net 改动**(src/net/network_manager.gd):
  - 新增 `var player_species := Species.UNASSIGNED`,放在 23-31 行一带;`request_species` 成功时同步更新它。
  - `host_game(pname, room_name, preferred_port := 0, species := Species.UNASSIGNED)`(67-87):把 species 传给 `add_host`。
  - `join_game(pname, address_text, species := Species.UNASSIGNED)`(90-105)。
  - `rpc_join_accepted`(264-270)在 `joined_lobby.emit()` 之前加一行 `rpc_id(HOST_ID, "rpc_lobby_species", player_species)`。
  - 从 `_broadcast_lobby`(306-315)抽出 `_lobby_meta()`。
  - 新增两个函数:
    ```gdscript
    func request_species(index: int) -> void   # 等待厅换形象;房主直接改名单并广播,客人发给房主
    @rpc("any_peer", "call_remote", "reliable")
    func rpc_lobby_species(index: int) -> void:
    	# 来自不可信的对端:只认等待厅成员、只在开局前;参数类型由 RPC 签名把关;
    	# 越界下标交给 LobbyModel 当「没有偏好」处理
    	if not is_host or in_game or _lobby == null:
    		return
    	var id := multiplayer.get_remote_sender_id()
    	if not _lobby.has(id):
    		return
    	if not _cooling_down(id) and _lobby.request_species(id, index):
    		_broadcast_lobby()
    	elif _is_connected(id):
    		rpc_id(id, "rpc_lobby_state", _lobby.view(), _lobby_meta())   # 被拒也回一份,请求者据此结算
    ```
  - `start_game`(354-373)先调 `_lobby.assign_unassigned()`,`seats` 每项变成 `{"pid", "name", "species"}`。
  - 504-506 行的注释补充:`rpc_lobby_species` 按名字排在 `rpc_join_*` 之后。

- **握手编号为什么不变**:实测 `Script.get_rpc_config()` 可用,RPC 编号按方法名排序。v5 的完整顺序:`rpc_game_events, rpc_game_started, rpc_intent_challenge, rpc_intent_play, rpc_intent_rejected, rpc_join_accepted, rpc_join_denied, rpc_join_request, rpc_kicked, rpc_lobby_ready, rpc_lobby_species, rpc_lobby_state, rpc_look, rpc_look_relay, rpc_returned_to_lobby, rpc_state_private, rpc_state_public`。前 8 个(到 `rpc_join_request` 为止)和 v1 时的集合相同,所以:
  - 旧客户端连新房主,会收到「版本不匹配(房主 v5 / 你 v4)」;
  - 新客户端连旧房主,会收到「版本不匹配(房主 v4 / 你 v5)」;
  - 被拒后照样触发 main_menu.gd:338-342,去问房主有没有更新;
  - 两端方法表不同,引擎可能打印「rpc node checksum failed」这条错误,只是告警,不影响拒绝消息。

- **对房间发现和在线更新的影响**:
  - 发现报文格式不变;版本号不同的房间被标成 `compatible = false`(room_list.gd:40)。房主比自己新、同平台、开了更新服务时显示「更新后加入」,否则显示「版本不同」(main_menu.gd:249-266)。
  - ② 只改脚本、着色器和资源,`project.godot` 不动,也没有新的 autoload(全是 class_name 静态类),所以 `base_build` 不变,可以走在线更新。新增的 class_name 随更新包载入(update_boot.gd:3)。

### 3.7 其余改动

- `src/ui/main.gd`:
  - `_ready`(27-58)在 `await CardFaces.build`(51)之前:先解析本机形象(首次启动随机一个并保存),再调 `SpeciesCache.prebuild(species)`。
  - `_show_menu()` 之后启动 `SpeciesPortraits.build(self)`,不 await。
  - 新增 `_process`,里面调 `SpeciesCache.poll()`。
  - `_exit_tree`(82-88)加 `SpeciesCache.clear()` 和 `SpeciesPortraits.clear()`。
  - 新增 `resume_menu_orbit()`(可选项)。
- `src/ui/table/table_screen.gd`:`next_neck_input(current, held, delta, reach := Patron.NECK_REACH)`(144-148),调用时传 `me.neck_reach()`。默认参数让 test_cursor_look.gd:42 不变。
- `src/ui/debug_flags.gd`(77-97):
  - 新增 `--species=<id>`,传给 host/join,不写设置。
  - 每次名单更新和开局时打印 `[debug] species {pid: id}`。
  - 新增 `--timing`:打印 `[debug] timing menu_ready=… species_ready=… portraits_ready=…`(`Time.get_ticks_msec()`)。
- `tools/lan_smoke.sh`:三个进程都带 `--species=crocodile`。通过条件加上:三个日志里最后一条 `[debug] species` 完全一致,房主是 crocodile,另外两人各不相同且不是 crocodile。
- `tools/net_probe.gd`:同样支持 species。
- `tools/perf_probe.gd`(① 的工具,② 加用例):
  - `patron-flat`:把酒客着色器换成不带花纹的版本,做 A/B;
  - `spawn`:已缓存物种在等待厅换形象那一帧的最长帧时间。
- `tools/showcase.gd` 和 `tools/shot.gd`:
  - `--species=fox,bear,...` 指定 4 个座位的物种。
  - `--lineup`:8 个物种一字排开,配 `lineup_front`、`lineup_back` 两个机位。
  - `--neck=0.85`:截一张脖子伸长的图。
  - `--stats` 按每个可见酒客的 `head_position` 投影取脸部区域,分别报告削顶比例。
- **文档**:
  - 说明书(rulebook_content.gd 的 controls 章节)加一个 note:「主菜单名号旁的头像处挑选你的动物形象;同桌不撞脸,先选先得,被占时房主给你一个空着的;等待厅里点自己的头像还能换。」
  - README:在功能列表里**新增**一条「八种卡通动物酒客(狐狸、熊、猪、猫、乌龟、羊驼、猴子、鳄鱼)任选…」,不替换第 5 行;「联机」第 1 步加「在名号旁挑一个形象」;注明协议 v5 起与旧版不能同桌。
  - 总设计文档 2026-08-14:§4.2 的消息表加 `lobby_species`(形象下标);`lobby_state` 加「形象」一列;`game_started` 的座位带 species;§5.2 的酒客描述改成 8 种可选。
  - 本节写进 2026-10-07 设计文档 §7;§10 约束表里的「手牌可见性」改成三角形判定,并加「头部前伸」一行。

---

## 4. 测试要点(GUT,无头)

每条测试的调整都保留原意图,逐条列在 tests 字段里。

**新增测试文件**
- test_species
- test_patron_species(结构、预算、几何约束、两两对坐、尾巴极值、动画参数)
- test_chair_builder
- test_species_cache
- test_species_picker
- test_net_rpc_order
- test_mesh_forge_organic

**修改**
- test_lobby_model:加分配规则用例,另做一个随机加入、离开、请求序列的性质测试。
- test_table_world:物种相关用例改成「使用房主分配的物种」,加对局补齐用例。
- test_hand_visibility:8 个物种都跑,改用三角形精确判定。实测 ArrayMesh 的 `generate_triangle_mesh().intersect_segment` 在 4.7 无头下可用(`p2_review3/probe1.gd`);AABB 留作预筛;每个网格的 TriangleMesh 只生成一次;5% 阈值不变;用 `Engine.time_scale = 4` 把耗时压在 30 s 内。
- test_patron_neck:参数化,加入羊驼和鳄鱼。
- test_settings:加 species 键。

**迁移**
- test_patron_parts 迁到 test_species,断言原样保留。

## 5. 发版验收

见 acceptance_criteria 字段:数值、截图检查、联机冒烟(自动和手动)、跨版本检查。

## 涉及文件
src/core/species.gd (new)
src/world/species/species_recipes.gd (new)
src/world/species/species_fox.gd (new)
src/world/species/species_bear.gd (new)
src/world/species/species_pig.gd (new)
src/world/species/species_cat.gd (new)
src/world/species/species_turtle.gd (new)
src/world/species/species_alpaca.gd (new)
src/world/species/species_monkey.gd (new)
src/world/species/species_crocodile.gd (new)
src/world/patron_builder.gd (new)
src/world/patron_head_builder.gd (new)
src/world/patron_hat_builder.gd (new)
src/world/patron_limb_builder.gd (new)
src/world/chair_builder.gd (new; shared lathe chair C6, layout constants, solids())
src/world/species_cache.gd (new)
src/world/species_portraits.gd (new)
src/world/shaders/patron_eye.gdshader (new)
src/ui/widgets/species_picker.gd (new)
src/ui/widgets/species_chip.gd (new)
src/world/mesh_forge.gd (from ①: add vertex_format/PATRON_FORMAT, blob/loft(+caps,bands)/loft_c/tube/lathe(+bands)/displace/paint/project_to/bake_ao, arrays()/commit_arrays(); ① signatures kept)
src/world/shaders/patron.gdshader (from ①: sRGB→linear, material-class patterns, tail sway + floor-clamped droop, backlight)
src/world/materials.gd (patron_eye() via _cached)
src/world/patron_3d.gd (rewrite build; eyes/fist/legs/tail; per-species neck_base, neck_reach, pitch clamp, die override; fade guard)
src/world/patron_parts.gd (deleted after moving build_chair to chair_builder.gd; SPECIES moved to recipes)
src/world/table_world.gd (arrange uses assigned species, in-game fallback, species swap, menu preview)
src/net/protocol.gd (VERSION 5)
src/net/lobby_model.gd (species per member, request_species, assign_unassigned)
src/net/network_manager.gd (player_species, request_species, rpc_lobby_species with reject reply and cooldown, _lobby_meta, seats carry species)
src/ui/settings.gd (KEY_SPECIES, get_species)
src/ui/main.gd (resolve species, prebuild/poll/clear caches, portraits, resume_menu_orbit)
src/ui/main_menu/main_menu.gd (species chip next to name, picker, preview, pass species to host/join)
src/ui/lobby/lobby.gd (portrait chips, own-row picker with taken markers and pending-request resolution, remove _species_of)
src/ui/table/table_screen.gd (next_neck_input takes per-species reach)
src/ui/debug_flags.gd (--species, --timing, species map print)
src/ui/rulebook/rulebook_content.gd (controls note about species)
tools/lan_smoke.sh (species flags and cross-process species-map assertion)
tools/perf_probe.gd (patron-flat and spawn cases)
tools/showcase.gd (--species, --lineup)
tools/shot.gd (lineup views, --neck, per-head --stats)
tools/net_probe.gd (species option)
README.md (new 8-species bullet, picker step, protocol v5)
docs/superpowers/specs/2026-08-14-liars-tavern-design.md (§4.2 messages, §5.2 patrons)
docs/superpowers/specs/2026-10-07-visual-overhaul-design.md (§7 filled with this section; §10 constraint rows updated)
tests/test_species.gd (new; replaces tests/test_patron_parts.gd)
tests/test_patron_species.gd (new)
tests/test_chair_builder.gd (new)
tests/test_species_cache.gd (new)
tests/test_species_picker.gd (new)
tests/test_net_rpc_order.gd (new)
tests/test_mesh_forge_organic.gd (new)
tests/test_lobby_model.gd
tests/test_table_world.gd
tests/test_hand_visibility.gd
tests/test_patron_neck.gd
tests/test_settings.gd
tests/test_patron_parts.gd (deleted, assertions moved)
build.json (build +1, version 0.7.0 at release)

## 测试
test_species.gd(新,纯逻辑):IDS 和 LABELS 都是 8 项,id 唯一;index_of 与 IDS 互为往返;is_valid 拒绝 -1、8、999、2.0、"fox"、null;sanitize 把非法值变成 UNASSIGNED;first_free([])==0;first_free([0,2])==1;first_free([1,0,3])==2;全被占时轮流重复(first_free(range(8))==0,加一个 0 后==1)。原 test_patron_parts 的三条断言原样迁入,意图不变。
test_lobby_model.gd(扩展):房主拿到首选;非法首选回退为 0;新成员加入时 species==-1;请求空着的形象就分配;请求被占的形象时,还没有形象的分第一个空着的,已有形象的保持不变并返回 false;越界下标同样处理;请求和当前相同时返回 false(不广播);remove 释放形象且别人不变;reset_ready 后形象不变(再来一局稳定);assign_unassigned 补齐所有 -1;view() 带 species 且是拷贝。性质测试:固定种子随机做 500 步加入/离开/请求,每一步名单内形象都不重复、取值合法,已分配的不会被别人的请求改掉。
test_net_rpc_order.gd(新):load network_manager.gd 后取 get_rpc_config(),键排序后与 §3.6 列出的 17 个方法完全相等;前 8 个正好是 v1 握手前缀 [rpc_game_events … rpc_join_request],保住新旧版本互连时的「版本不匹配」提示;rpc_lobby_species 的模式是 any_peer、call_remote、reliable;rpc_join_request 仍是 2 个参数;Protocol.VERSION == 5。
test_table_world.gd(改写物种用例,保留「按人稳定、同桌不撞脸」的意图并逐条说明):arrange 传了 species 时,角色用的正是该物种;同一 pid 物种变化时换成新实例且位置不变,旧实例 vanish;等待厅里 species=-1 时不建角色,收到分配后再建;非法值(99、'x')在等待厅里当 -1;对局(with_revolvers=true)里 -1 或非法值仍会建角色,按座位顺序补第一个空着的、不和已分配的重复,且两次调用结果一致;revive_all 保持物种;不带 species 键(离线工具和测试)时仍按本地第一个空着的分配,原两条物种测试改走这条兜底路径;species_index_of 取代 species_of;菜单预览在 arrange 和 clear 时被收走。
test_patron_species.gd(新,8 个物种逐个参数化,无头,结构与几何):节点结构 Body、Body/Neck、Body/Head、Head 下恰好一个 Hat、ArmL/Hand、ArmR/Hand、Fan 都在;可见 MeshInstance3D ≤16(Fan 子树除外),投影的 ≤12;酒客材质 ≤2(patron + eye)加椅子木纹;可见三角形总数 ≤15000(含椅子,一对的部件合计计入);Neck 只有一个子网格,AABB 的 y 是 [0,1];配方 skull[0] 中心在 (0,0.12,0),HeadMesh 在 x 方向对称(|min.x+max.x| ≤5 mm);坐姿下帽顶和耳尖 ≤1.65 m;头部子树离头心向后 ≤0.22 m;耳帽间隙:左右两侧、三个抖耳角下都 ≥4 mm(帽子实体按构建器导出的轮廓和 radial 采样,猫的耳洞按「洞椭圆 + 4 mm」豁免);猪耳在三个抖耳角下离眼 ≥5 cm;鳄鱼眼包不和帽子相交;帽檐在 |x|≥0.15 处 y≥0.20;胸前 Z≥-0.24;袖子末端 z∈[-0.37,-0.33];静止坐姿下按座位坐标,张开的爪最低顶点 = Hand.y -0.0464±0.004、最高 ≤ Hand.y +0.045;膝 ≤0.6;脚让开椅腿;relief 期间 Legs.position.y ≥0;neck_reach + front_extent ≤1.15;尾巴在静止、±摆幅(用和着色器同一个公式在 CPU 上复算)、下垂=1 三种状态下都不穿 ChairBuilder.solids(),也不低于地面 5 mm;乌龟龟壳在坐、前倾、坐直和死亡覆盖姿势下都在靠背柱前缘之前;鳄鱼吻尖 z ≥ -0.38;配方颜色任一通道 ≤0.80,皮毛和脸的线性亮度 ≤0.62;同一配方构建两次,顶点数和哈希都相同。
test_patron_species.gd(两两对坐,新):2 人、3 人、4 人布局里,鳄鱼对狐狸、鳄鱼对羊驼、狐狸对羊驼,所有人都把脖子伸向桌心到上限、其中一人 set_active(true)、平视对面头部,等稳定后用对方头部网格的 TriangleMesh 检查:己方头心到己方吻部顶点的线段不与对方头部相交;吻尖间隙 ≥5 mm。
test_patron_species.gd(动画部分,异步):眨眼时 Eyes 的 lid 实例参数到 1 再回 0;look 跟着 look_at_point 变化并夹在范围内;set_expression('angry') 让眉毛 rotation.z 和 lid_tilt 变号,position.y = 配方眉位 + lift;pick_up 后显示 PawFist、隐藏 PawOpen,lower_gun 后恢复;die 后 dead==1,1.4 s 后所有网格和被打飞的帽子 fade≈1,尾巴下垂参数 tail.z≈1,Chair 不在 _meshes 里;die 后 0.5 s 内 world.clear(),之后补间继续跑也不报错;静止 1.2 s 后每只爪的最低顶点在毡面 ±4 mm 内(顶点级的爪贴桌检查)。
test_chair_builder.gd(新):座面顶 0.475±0.005,座面底 0.425;后腿 z 0.32、靠背柱 z 0.34;靠背杆底 ≥0.53(缝 ≥5.5 cm);整体 |x| ≤0.26(不加扶手),顶 ≤1.1;三角形 ≤1300;两次 mesh() 返回同一个 ArrayMesh;solids() 覆盖座面、4 条腿、2 根柱、靠背杆。
test_hand_visibility.gd(调整,意图不变):me 依次换成 8 个物种;判定从「头部网格 AABB 与射线相交」改为「AABB 预筛,再用每个网格缓存的 TriangleMesh.intersect_segment(线段转到网格局部)精确求交」;阈值 MAX_BLOCKED 5%、每张牌中心可见、7 个脖子偏移和 2 种姿势都不变;用 Engine.time_scale=4 把耗时压在 30 s 内。
test_patron_neck.gd(调整):全部用例对狐狸、羊驼、鳄鱼各跑一遍(羊驼的 neck_base 更低,鳄鱼的 neck_reach 更短):脖子顶端离头枢轴 ≤5 mm、头平移、不往后探、不过冲都照原断言;test_reach_is_limited 对狐狸仍断言 Patron.NECK_REACH(±0.03),对鳄鱼断言 patron.neck_reach()。
test_species_cache.gd(新):同一物种多次 meshes(i) 返回同一批 ArrayMesh 实例;8 个物种都能同步构建;所有酒客部件的 surface_get_format 完全一致(同一管线);prebuild 之后立刻 meshes(最后一个) 能返回,接着连续 poll 不报「重复 wait」或 task 无效的错误;clear() 后清空并能重建;已缓存时 Patron.new(i) ≤4 ms、4 个角色 arrange ≤16 ms(无头计时);每个物种首次构建耗时只打印、不断言。
test_mesh_forge_organic.gd(新):blob、loft、lathe、tube 生成的法线都是单位长度,AABB 正确;blob 的半径不小于各椭球硬并集的远交点;loft、lathe 的 bands 产生硬边(色带边界成对复制顶点);vertex_format=PATRON_FORMAT 时写满 COLOR、UV、UV2、CUSTOM0,COLOR 存的是 sRGB;vertex_format 默认值下仍按 ① 的约定写(COLOR 线性、CUSTOM0 float),且 ① 签名的调用(lathe 4 参数、loft 4 参数、tube radii 数组、commit())照常可用;arrays() 能在 WorkerThreadPool 任务里跑完。
test_species_picker.gd(新):SpeciesPicker.taken_map(players, my_pid) 排除自己、忽略 -1、映射为 下标→名字;所有格子都被占时仍保留自己的格子可选;无头下 SpeciesPortraits.build 之后 is_built() 为真,texture(i) 返回色圆片回退。
test_settings.gd(扩展):KEY_SPECIES 往返(存 'crocodile' 读回下标 7);未知 id 或类型不对时 get_species 回退 UNASSIGNED 并告警。
全量回归必须一直通过:test_patron_arms、test_table_world、test_cursor_look(静态 clamp_neck 与 next_neck_input 默认参数不变)、test_gaze_sync、test_seat_layout、test_pacing、test_render_budget、test_post_fx、test_protocol、test_room_list、test_rulebook_content(新 note 块类型已知)、test_lobby_roster、test_main_menu_rooms。

## 预算影响
相对 ① 完成后的状态(酒客是原样合并的旧几何,每人约 19 个网格、约 11k 三角形、已共享材质;椅子 628 面):
- 每人可见实例降到 15 个(乌龟、鳄鱼 13),投影 12 个,眼睛和眉毛不投影。
- seat 视角 4 名酒客约 4×(15 可见 + 12×约 2.5 阴影)≈180 dc;① 约 224(19 个网格,其中 15 个投影),估计净省约 40。实际以「不高于 ① 发版值」验收。月光不投酒客影子,按 ① 的默认假设。
- 主菜单多一个预览酒客,约 +45 dc;① 的 menu 约 700,加上后仍 ≤800。
- 三角形:每人 12.4–14.4k(含 1.3k 新椅子,≤15k;乌龟余量最小,0.6k),比 ① 多约 3k。可见图元 +13k,阴影图元约 +30k,seat 合计约 290k,上限 400k。
- 唯一材质:净 +1(patron_eye;自发光眼睛高光在 ① V4 就已去掉,不再重复扣)。新增自定义 spatial shader +1,计入 ≤4 的上限。灯光不变。
- 着色器:花纹、摆尾加眼睛着色器,目标是 seat 视角 ≤0.15 ms,由 perf_probe 的 patron-flat A/B 实测;seat 帧时间预计 ≤9.85 ms(预算 10.0)。CPU 渲染线程略降,因为实例少了。
- 启动:主线程目标 ≤60 ms(9 次提交约 1–2 ms 一次,加头像回读),首次运行的着色器编译另计,由 --timing 实测,计入四个子项目共享的 +200 ms。
- 后台预建:改成高优先级任务后,M3 上墙钟约等于最慢的单个物种(真实构建器估计 40–60 ms,②a 门槛 ≤60 ms);4 核机器约 2 批,并且要慢 1.5–2 倍。原型的 167–208 ms 是低优先级 2 线程的数字。
- 生成:已缓存物种的生成约 0.04 ms(无头实测),真实渲染下用 perf_probe spawn 用例验收 ≤16 ms 帧。
- 显存约 +5 MB(8 个物种的网格)+0.5 MB(头像图集)。
- 包体:只多几十 KB 脚本。

## 验收
性能(M3、1080p、RenderBudget 配置,用 ① 的 perf_probe 阴影重画模式,3 次 × 300 帧取中位数):seat dc ≤700(硬上限 900),而且不高于 ① 发版时的值;opponent ≤400;menu(含预览酒客)≤800;seat 帧时间 ≤10.0 ms;CPU 渲染线程 ≤1.0 ms;唯一材质 ≤40;灯 ≤16 盏、投影 ≤3 盏(不变)。
着色器开销:perf_probe --cases=budget,patron-flat 在 seat 和 closeup 视角下,花纹着色器比不带花纹的版本帧时间多 ≤0.15 ms;用 --rendering-driver vulkan(MoltenVK)跑一次 seat,dc 和 CPU 渲染线程仍在预算内,并记录数字,作为集显的参考。
每个物种(8 个,test_patron_species 强制):可见 MeshInstance3D ≤16(预期 15,乌龟和鳄鱼 13);投影 ≤12;酒客材质 ≤2 加椅子木纹;三角形 ≤15000(含椅子,预期 12.4–14.4k);新椅子 ≤1.3k 面,4 把共享一份网格。
启动和生成(DebugFlags --timing,3 次取中位数,与 ① 发版的构建同机对比):主线程到主菜单可操作比 ① 多 ≤60 ms(总启动增量仍 ≤200 ms);菜单出现后 ≤1.0 s 内 8 个物种全部就绪(M3);用 max_threads=4 的 override.cfg 模拟 4 核时 ≤1.5 s;头像图集 ≤1.5 s 就绪;②a 用真实狐狸构建器测的单线程构建时间 ≤60 ms(M3 最小值);perf_probe spawn 用例里已缓存物种换形象那一帧 ≤16 ms;对局中 revive_all 不卡帧。
观感指标(shot.gd --stats,按每个可见酒客的头部区域统计):用 --species 轮换,让 8 个物种都在 opponent 座位出现一次,并拍 closeup 和 lineup_front;每个物种脸部削顶都 ≤5%,全帧 ≤1%(猪原来是 63–84%)。
截图检查(shot.gd --showcase --species=fox,bear,pig,cat 和 --species=turtle,alpaca,monkey,crocodile,视角 seat、menu、opponent、closeup、gun、overhead、window、selfshot;另加 --lineup 的 lineup_front 和 lineup_back,以及 --neck=0.85):耳朵不穿帽子(seat、overhead、window、lineup);帽子和耳尖不碰名牌(等待厅截图里的狐狸和羊驼);脖子接缝被毛领盖住,羊驼伸长的脖子干净、没有条纹;爪有手指和肉垫,落在毡面上(seat);举枪的那只手是拳头(gun);眼睛有虹膜和画上去的高光、没有泛光亮点,死亡时是 X;尾巴在 menu 和 lineup_back 里看得到,不穿座面和靠背,猴尾绕在椅腿上,摆动时不扫进椅腿,出局下垂后不入地;腿和鞋在 menu、overhead 里看得到,不穿椅腿;鳄鱼低头时吻不切进自己的牌扇(鳄鱼坐 3 号位的 opponent 视角);鳄鱼和狐狸对坐、都伸到最远时吻不互穿(--neck=0.85);龟壳不穿椅背,乌龟侧倒的死亡姿势干净;脸上没有基础体接缝;死亡褪灰覆盖所有部件,包括被打飞的帽子和眼睛,椅子不褪。
自选形象界面:主菜单名号旁有头像按钮,展开后是 8 格带头像的网格,支持纯键盘操作;选中后 3D 预览冒烟换人(如果做了镜头推近,收起后恢复环绕);重启游戏后选择还在;首次启动时随机得到一个形象并被保存;等待厅每行显示头像,自己那行可以换,被占的格子压灰并写占用者名字;两人同时点同一个形象时,后到的一方看到「已被 X 选走」,本机偏好不被改写;无头或头像还没烘好时显示色圆片加首字。
自动联机冒烟:tools/lan_smoke.sh 通过,三个进程都带 --species=crocodile;原有条件(MATCH_OVER、GAZE peers=2 necks=2、无 SCRIPT ERROR)之外,三个日志最后一条 [debug] species 完全一致,房主是 crocodile,另外两人各不相同且不是 crocodile。
手动联机冒烟(同一台机器 4 个实例:--autohost 一个、--autojoin 三个,都带 --species=crocodile):房主拿到鳄鱼,其余三人按请求到达顺序拿到狐狸、熊、猪;4 个进程打印的 [debug] species 映射完全一致;一位客人在等待厅换成羊驼,4 端同步;他离开后羊驼被释放,别人的形象不变;他从主菜单界面重新加入(不带 --species,本机偏好已是羊驼)时拿回羊驼;打完一局再来一局,形象不变;开局后各端牌桌上的物种和等待厅一致。
跨版本:v4 客户端 IP 直连 v5 房主,提示「版本不匹配(房主 v5 / 你 v4)」并去问房主要更新;v5 客户端直连 v4 房主,提示「版本不匹配(房主 v4 / 你 v5)」;房间列表里 v4 和 v5 的房间显示「版本不同」或「更新后加入」;日志里引擎的「rpc node checksum failed」告警可以忽略。
测试:GUT 全量通过,测试脚本数核对一致(release-update skill);新增和调整的测试在 PR 说明里逐条写明保留了什么意图。
发版:project.godot 没有改动,base_build 不变,走在线更新 pck;build.json 的 build 加一、version 改为 0.7.0;README、说明书、总设计文档、2026-10-07 设计文档 §7 同步更新到协议 v5 和 8 种形象。

## 决策(均按推荐默认采纳)
首次启动(还没有保存过形象)默认用哪个:建议随机选一个并立刻保存,让新物种更常出现;另一个选项是固定狐狸,和现在一致。
有人离开、空出一个形象时,原来因撞车拿到候补形象的玩家要不要自动换回首选:建议不自动换,保持稳定,玩家在等待厅点一下就能换。
等待厅里换形象是否同时覆盖本机保存的偏好:建议覆盖,但要等房主确认之后才写,把玩家最后一次成功的选择当作偏好。
8 个角色的设定是否认可(狐狸老千绅士、熊酒馆老板、猪铁路司炉、猫独行枪手、乌龟老淘金客带胡子和眼镜、羊驼披毯客戴卷毛上的迷你草帽、猴子酒馆跑堂、鳄鱼亡命徒带金牙和子弹带):建议按此执行,子弹带和金牙都做卡通化处理。
耳朵和帽子的处理:只有猫的牛仔帽用卡通惯例的「耳洞」,其余物种的帽子夹在两耳之间,或者耳朵放到帽檐下,乌龟和鳄鱼没有耳朵;为此狐狸礼帽的歪戴角从 9° 减到 ≤3°,熊的圆顶礼帽 ≤4°:建议按此执行。
乌龟单独用侧倒的死亡姿势(龟壳不穿椅背),其他物种保持现有姿势:建议采用。
鳄鱼的物种差异:低头下限从 -0.45 改为 -0.30(长吻不切进自己的牌扇);吻缩短到 0.38 m;伸脖子上限按「头部伸出 + 吻长 ≤1.15 m」自动缩短到约 0.75 m(别人 0.85),保证 4 人同时探向桌心时吻不互穿。另一个选项是吻缩到和狐狸差不多长、伸脖子不变:建议采用前者。
椅子车削重塑(C6)归 ② 负责:① 只做原样合并,其他子项目没有安排;布局尺寸不变。建议采用。
主菜单让自己选的形象坐在 0 号椅上(挑选时镜头推过去算可选项)。这依赖尚未确认的「主菜单放空椅子」:建议采用,镜头推近视进度决定。
挑选面板的头像用运行时 SubViewport 烘焙图集,无头时用色圆片加首字。这依赖尚未确认的「运行时绘制贴图算程序化」:建议采用。
配色按尚未确认的「保留 ACES、降曝光、albedo 上限 0.8(sRGB)」来调;如果最后改用 AgX,② 要多一轮配色调整:建议保留 ACES。
测试调整授权:test_patron_parts 迁到 test_species;test_table_world 的物种用例改成「使用房主分配的物种」,加本地兜底和对局补齐;test_hand_visibility 扩到 8 个物种,改为三角形精确判定(阈值不变);test_patron_neck 加入羊驼和鳄鱼(鳄鱼断言自己的 neck_reach):建议批准。

## 风险
在 GDScript 里构建 8 个高细节物种很贵:原型只生成几何,单物种 21–34 ms;加上 paint、AO、displace、UV 写入,估计 40–60 ms;低端 Windows CPU 可能再慢 1.5–2 倍。缓解:高优先级后台预建,首选物种排第一,主菜单预览不阻塞;②a 设 ≤60 ms 门槛;实测超过 1 s 时再加磁盘缓存(user://,键是 build 号加配方哈希)。
WorkerThreadPool:低优先级任务在 8 核上只有 2 个线程,4 核上串行;主线程等排队的任务会被卡住整个队列(实测 412 ms)。必须用高优先级,并用状态机保证每个 task 只 wait 一次,否则退出时告警或泄漏。
线程安全:ArrayMesh 和 RenderingServer 只能在主线程碰;配方在主线程取好再传给工作线程,避免在线程里触发脚本加载。
管线编译卡顿:所有酒客部件的顶点格式必须完全一致(PATRON_FORMAT 强制写满),否则某个物种首次登场时会编译新管线;由 test_species_cache 守护。没有着色器磁盘缓存的首次运行,新着色器的编译耗时落在启动阶段,计入 --timing 验收。
接口:② 修改 ① 的 MeshForge 约定(只加尾部参数、新增 vertex_format)和 patron.gdshader 的颜色空间。如果 ① 已经按旧约定实现,② 的第一步要先改 ① 的代码,并保证 ① 的椅子、左轮、酒瓶调用不受影响(test_mesh_forge_organic 守护)。
依赖 ①:patron.gdshader 的 fade、阴影层约定、曝光和 albedo 上限、主菜单空椅子的实现位置。① 有变化时,② 的配色、ChairBuilder 接入点和测试要跟着调。
依赖 ③:左轮加粗 1.2–1.3 倍、HOLD_OFFSET 重调之后,拳头和牛仔帽右檐的余量要复核;② 发版时拳头按 ① 的旧左轮调。
手牌可见性改用 TriangleMesh 精确判定(实测无头可用),每个网格的 TriangleMesh 要缓存,否则 8 个物种 × 14 种姿态的测试会很慢。
协议:物种下标顺序在 v5 冻结,以后加物种只能追加并升协议版本;握手 RPC 的签名和排序必须保持(test_net_rpc_order 守护),否则新旧版本互连时会超时,拿不到明确的拒绝原因。
握手后到形象请求到达之间(一个往返),成员的形象是 -1:等待厅显示「挑选中…」、不建角色;恶意或异常客户端一直不发,开局时由 assign_unassigned 兜底;对局数据异常时,TableWorld 在本地补齐,不会崩溃。
频繁切换形象会让各端反复生成角色和烟雾:房主端 0.25 s 冷却,同一帧多次变化只换最后一次,客户端点选后禁用 0.3 s。
顶点色只有 8 位:存线性值暗部会出色带,所以酒客存 sRGB、在着色器里转线性;花纹细节靠着色器(格纹、鳞、织纹),不靠顶点色。
工作量大:8 个物种 × 约 12 个部件的配方,加上新椅子,都要逐个截图调参,这是 ② 最大的进度风险。缓解:②a 先用狐狸和椅子把管线跑通,②c、②d 只写配方数据;靠 lineup 截图批量检查;主菜单镜头推近列为可选项。
乌龟专用死亡姿势和鳄鱼的俯仰、伸脖子差异是逐物种的动画差异;其余物种的旧穿模问题(倒下时躯干穿椅背)不在本子项目范围内。
启动预算是四个子项目共享的 200 ms;② 只占主线程 ≤60 ms。如果 ③ 和 ④ 的贴图烘焙也挤在启动期,需要统一排队。

## Q 版与搞笑表演(2026-10-08 用户追加)

用户反馈「这些角色可以 Q 一点、搞笑一点」,选了「中度 Q 版 + 搞笑动作」:座位高度、牌桌、机位都不动,只改角色比例与表演。

### 比例(PatronParts 常量,配方里统一换算)

| 常量 | 值 | 作用 |
|---|---|---|
| `HEAD_SCALE` | 1.3 | 整颗头(颅骨、吻、眼、眉、耳、帽、头部特件)绕头心 (0, 0.12, 0) 放大。物种 LOOK 的数字不动,头配方开头 `push(head_xform)`;眉、耳网格绕枢轴原点放大,枢轴位置用 `head_point()` 换算。头心不动,瞄准点、机位目标照旧 |
| `EYE_SCALE` | 1.2 | 眼珠在头放大之上再放大、更鼓;眉毛按眼睛上沿的抬高量一起抬(`brow_point()`) |
| `HAT_SCALE_Y` | 1.15 | 帽子横向跟头放大 1.3(戴得上),竖向只放 1.15:矮胖的 Q 版帽,礼帽也不至于顶到德州铭牌。帽檐卷边的 displace 按原尺寸写,所以帽子先按原尺寸建好再整体缩放 |
| `BODY_SQUASH` | 0.93 | 躯干连衣片竖向压扁(绕髋部);肚子椭球再放大 (1.1, 1.05, 1.14)、前挪 1.8 cm(`PatronBuilder.BELLY_*`) |
| `PAW_CHUBBY` / `FIST_CHUBBY` / `FOOT_CHUBBY` | 1.2 / 1.12 / 1.15 | 胖爪(绕掌底着桌点放大,掌底高度不变)、胖拳、胖脚(绕鞋底中心,鞋底仍贴地) |

鳄鱼的头前后只放 `head.scale_z` 0.85 倍(吻尖不捅到桌心)。随之改动的 Patron 常量:`SHOULDER` (0.21, 0.52) → (0.205, 0.485)、`HEAD_PIVOT` y 0.65 → 0.615(脖子更短)、脖子根 × BODY_SQUASH、`NAMEPLATE_HEIGHT` 1.82 → 1.92、`HAND_GUN_HEAD` 按③的求解重算 (0.4393, 0.8066, -0.0613);8 个物种的 `gun_clearance` 写进 LOOK(按举枪流程实测最小净空、含抖耳,再留 ≥4 mm:熊 0.229、猴子 0.234、其余 0.221),③的兜底表删掉。新增 `FRONT_REACH_MAX` 1.15 落地(§1.1):`neck_reach = min(NECK_REACH, 物种上限, 1.15 − front_extent())`,`front_extent` 取头、帽网格包围盒(不读顶点),狐狸 0.77、羊驼 0.81、鳄鱼 0.74,其余 0.85。头像烘焙格子 0.62 → 0.8 m、对准高度 1.34 → 1.37。

### 约束值的变化(意图不变)

- 帽顶 / 耳尖(Head 局部)`HEAD_TOP` 0.51 → 0.12 + 0.39 × 1.3 ≈ 0.627,羊驼 0.48 → ≈0.588;静止时帽顶 ≤1.66 m(狐狸礼帽),坐直 ≈1.70 m,名牌抬到 1.92 m。
- 头往后伸 `BEHIND` 0.22 → 0.22 × 1.3 ≈ 0.286(猫的宽檐帽 0.282)。test_hand_visibility 改成碰到包围盒后逐三角形判定(§8 已批准)、阈值 5% 不变,并加了 8 个物种前倾探头的用例:越肩镜头不用改。
- 枪口到头心 0.172–0.20 → × head_scale(③已按 `Patron.head_scale()` 写好)。
- 新测:吻尖下限(放大前狐狸 -0.30、羊驼 -0.27、鳄鱼 -0.38、其余 -0.22,乘以放大倍数)与「伸脖子 + 前伸 ≤ 1.15」。
- 三角形、可见网格、材质预算不变(特效平时隐藏,汗珠和星星是 MultiMesh)。
- 已知妥协:德州铭牌 `TableWorld.NAMEPLATE_HEIGHT` 仍是 1.62(抬到 1.64 以上,越肩机位下 7、8 号铭牌就重叠),狐狸礼帽尖(≈1.66 m)和羊驼耳尖(≈1.62–1.66 m)会被铭牌下沿盖住几厘米。

### 搞笑表演(src/world/patron_antics.gd,PatronAntics)

Patron 的子节点,Patron 每帧调 `tick`;Patron 只加钩子(`relief` / `die` / `celebrate` / `reset_pose` 各一行、新增 `startle()`、`head_add` 叠进头部目标角并受③的 `_steady` 屏住),举枪 / 放枪函数不碰——「枪口对着自己」按「坐直且右手是拳头」判断。

- 枪口抵头:冒冷汗(一个 MultiMesh,三滴汗从额角滑到腮边)、眼睛 `shock`(眼睑全开、瞳孔缩成针尖)、发抖(整个 Body 连头带举枪的手一起抖 4 mm,头与枪不相对漂移)、左耳乱颤、尾巴摆幅 ×2.6。
- 空枪:`joy` 眯眼(^ ^)、吐舌头、耳朵耷拉。
- 出局:`dizzy` 蚊香眼 1.3 s 后定格成 ×;头顶 5 颗不受光、不投影的星星一直转(MultiMesh,复位时隐藏);舌头吐在嘴角并跟着褪灰。
- 赢了:眯眼笑,再挑三下眉、左右晃脑袋。
- 吓一跳 `startle()`:蹦 5 cm、shock 眼、帽子弹起、耳朵炸开、尾巴甩急。牌桌导演在拍桌喊骗子、有人中枪时让其他人吓一跳,被抓包的骗子也一蹦。
- 待机:每 4–9 秒一个小动作(东张西望、歪头、抖耳、甩尾、小蹦、挑眉),按物种播种,互不同步。
- 眼睛着色器同时改成 Q 版大眼:虹膜 0.6、瞳孔 0.33、高光加大,物种默认眼睑 ×0.6;实例参数新增 `shock` / `joy` / `dizzy`。
- 便宜为先:不加灯、特效不投影、补间为主;逐帧只在发抖、冒汗、转星星时写几个变换;场景树暂停(`--freeze`)时全停,跟随 `Engine.time_scale`。共享网格与材质在 main.gd 退出时 `PatronAntics.clear_cache()`。

## 新形象:熊猫与企鹅(2026-10-10)

用户:「再加一个熊猫的形象(给他配竹子的道具)、企鹅的形象」。两个都按现有物种的架构做(LOOK 数据 + `extras()` 特件钩子,
共享构建器只加了两个小参数),动森式、纯色、圆润,和原来 8 个站在一排不违和。

### 目录与协议

- `Species.IDS` 末尾追加 `"panda"`(下标 8)、`"penguin"`(9);前 8 个下标不动。`LABELS` 熊猫 / 企鹅,`ROLES`「竹林侠客」/「南极来客」,
  `GLYPHS`「竹」/「鹅」(熊猫的「熊」「猫」都被占了,用它的竹子;测试加了单字不重复)。
- **协议 v10**:v9 客户端的 `Species.is_valid` 不认下标 8、9(名单里显示「还没有形象」、本地补成别的物种,各端画面不一致),不能同桌。RPC 表不变。
- 先到先得、德州 8 人桌照旧:10 个物种比座位多,同桌永远不撞脸。

### 熊猫「竹林侠客」(`species_panda.gd`)

| 部位 | 做法 |
|---|---|
| 头 | 白毛主颅骨 + 胖腮 + 短圆吻 + 黑鼻头;后脑压暗一点(越肩镜头里不是发光白球);腮红是露出一小片的颅骨小椭球 |
| 眼斑 | **贴片**(`Kit.panel`,离颅骨 1.4 mm,不带侧壁):以眼心为中心、在眼睛朝向的切平面里画极坐标泪滴(半径 0.05 × 0.056,往外下方 −62° 拉长 55%),再射线投到颅骨上,边缘干脆(颅骨形体的颜色混合有 2 cm 的晕,做不出黑白分明的眼斑) |
| 眼睛 | 新增 LOOK `eyes.lid`(眼皮颜色用哪个调色板键,熊猫 `patch`:眨眼时是黑眼皮)与 `eyes.lift`(眼面离颅骨的最小高度,熊猫 0.005 m:抬到贴片之上) |
| 耳 | 黑色圆杯耳 (±0.132, 0.218),内耳深灰 |
| 帽 | 竹编小斗笠(`hat.kind = "douli"`,共享帽子构建器不认识,在 `extras("hat")` 里车削):半径 0.108、高 0.086 的浅圆锥,帽面略鼓,檐口深色竹篾包边,顶上红珠(预先竖向拉长,帽子竖向只放 1.15 倍后仍是圆的);扣在两只黑耳朵中间 |
| **竹子** | 左嘴角(−x)斜叼一根两节嫩竹枝,伸向左腮外上方,竹节一圈略鼓的深绿,末端三片柳叶形竹叶。在头部网格里:头像、对手视角、特写都看得到,第一人称跟着头一起藏。放在左边是因为右手举枪抵右太阳穴、舌头从右嘴角吐出来;测试守住全部竹枝 / 叶子顶点 x < 0 |
| 衣服 | 红色短夹棉坎肩:对襟两片(上面在胸口合拢、下摆圆角往两边分开,露出圆滚滚的白肚子)、外侧开袖窿露出黑肩膀,后片压暗;金色滚边(前襟 + 下摆)、红立领配金边、三对金盘扣 |
| 四肢 | 黑胳膊(皮毛材质)、黑圆手团、黑腿、黑光脚;白色短圆尾 |
| 待机 | LOOK `anim.fidget = "chew"`:嚼竹枝——往竹枝那边歪一点,头微微一抬一落四下(竹枝跟着头动,只是补间,不加网格) |

### 企鹅「南极来客」(`species_penguin.gd`)

| 部位 | 做法 |
|---|---|
| 头 | 藏青主颅骨 + 胖腮,光滑皮毛材质类(9,羽毛短顺);没有耳朵(和乌龟、鳄鱼一样 13 个可见网格) |
| 白脸 | 心形贴片:两瓣圆(绕眼,半径 0.066)+ 下脸大椭圆,极坐标轮廓按「从里往外第一次走出去」算,**正面平行投影**(从脑后远处往前打射线,轮廓不随脸的曲面变形),离颅骨 1.6 mm;眼皮 `lid = "face"`、`lift` 0.0055 |
| 腮红 | 白脸上两片扁圆粉色小贴片(颅骨里的腮红会被白脸盖住) |
| 喙 | 上下两片放样:上喙橙色、往前收尖略下勾(尖端 z −0.212,前伸上限 −0.22 × 头前后倍数之内),下喙深一档;上喙根一对小鼻孔;嘴线是上下喙之间一道深橙笑线(舌头照旧从右嘴角吐出) |
| 帽 | 红色毛线球帽(`hat.kind = "beanie"`,`extras("hat")` 车削):深红翻边 → 红帽身中间一道奶油条纹 → 奶油色大绒球(表面鼓几个小包),针织材质类 |
| 衣服 | 白肚皮贴片(正面蛋形,18 × 24 格:格子太粗时躯干平滑并集的顶点会从贴片里戳出来,出一片三角斑点);红色粗毛线围巾:绕脖子三圈车削(中间奶油条纹)、左前方打结,一头贴着胸口垂下、一头绕过左肩甩到背后,按长度画奶油条纹、末端 5 根流苏 |
| 四肢 | 藏青鳍状短胳膊、圆手团(同一套手部骨架,照样拿牌、握枪);新增脚型 `foot = "webbed"`:扁扁的橙色蹼脚,脚跟一团、往前摊开、前缘三个圆趾头;短小尾巴 |
| 待机 | `anim.fidget = "waddle"`:左右晃三下脑袋,像在冰上踱步 |

### 共享代码的改动(都向后兼容,旧物种外观逐顶点不变,`ddz_hat_fit` 重跑旧 8 个物种的贴合表一字不差)

- `Patron._build_head`:眼皮颜色 `eyes.get("lid", "fur")`。
- `PatronHeadBuilder.eyes`:眼面最小高度 `eyes.get("lift", 0.0015)`。
- `PatronBuilder._shoe_shape`:新脚型 `webbed`。
- `PatronAntics`:待机小动作表拆成 `fidget_kinds()` / `play_fidget(kind)`,物种 LOOK `anim.fidget` 加自己的一种(抽中机会 ×2)。
- `SpeciesPicker`:4×2 → **5×2** 格,每格宽 88 → 82、间距 8 → 6,面板 ≈470 像素宽(主菜单在侧栏右边 544–1014,德州等待厅在面板左边,都在 1280×720 内)。
- 头像烘焙台按 `Species.count()` 排开(1920 像素宽的一排);回退圆片熊猫竹青、企鹅冰蓝(黑白 / 藏青的头在自己毛色的圆片上不显)。
- 通缉令:第一行只放得下 8 张(1536 像素后是钟面),熊猫、企鹅的两张放在图集右下的空位(`DecorAtlas.EXTRA_POSTERS`);各自的木刻头像
  (泪滴眼斑、嘴角竹枝、小斗笠 / 心形白脸、尖喙、毛线球帽)与玩笑赏金(一捆嫩竹子 / 一桶冰鲜鱼);墙上 `poster_panda` 挂后墙钟左边、
  `poster_penguin` 挂右墙鳄鱼旁边(避开壁灯 ±0.3 m)。
- 叫声:熊猫软软带快颤音的「咩嘤」(f0 260)、企鹅鼻音很重的「嘎嘎」(f0 155,脆起音、喉颤),两两之间基频或过零率仍差 ≥15%。
- 工具:`tools/shot.gd --lineup` 间距 0.78 → 0.7、`lineup_front / back` 竖直视角 80°、`lineup_heads` 76°,左右半排机位挪到 x ±1.75;
  各玩法展台(骗子酒馆 / 德州 / 炸弹猫 / 吹牛骰子 / 斗地主)和 `perf_probe` 认 `--species=panda,penguin,…`(`tools/showcase_species.gd`,
  按座位号顺序换人,其余照旧);`tools/lan_smoke.sh` 三端都要企鹅(新下标过网络)。

### 约束实测(`test_patron_species` 的同一套量法)

| | 熊猫 | 企鹅 | 上限 |
|---|---|---|---|
| 三角形(含椅子 1284) | 13 984 | 13 590 | 15 000 |
| 可见网格 | 15 | 13(无耳) | 16 |
| 帽顶 / 耳尖(Head 局部) | 0.524 | 0.616(绒球) | 0.66 |
| 头往后伸 | 0.288 | 0.289 | 0.37 |
| 吻尖 / 喙尖 z | −0.342 | −0.359 | −0.22 × 1.95 × 0.86 = −0.369 |
| 胸前 z(身体局部 y 0.35–0.55) | −0.161 | −0.161 | ≥ −0.24 |
| 持枪净空 `gun_clearance` | 0.336(举枪流程实测最小 0.325,含抖耳) | 0.326(实测最小 0.315) | — |
| 斗地主帽 `DdzHats.FIT` | 瓜皮帽 s 2.365 / 草帽 s 2.665(坐在圆耳朵上,不开洞) | 2.259 / 2.545 | 帽口离头 ≤ 2.5 cm、帽顶 ≤ 0.7 |

材质仍是每人 2 个(`patron` + `patron_eye`)。持枪净空的量法:按 `test_gun_hold` 的举枪流程,净空从 0.24 每 5 mm 往上试,
枪口、准星与枪管表面一圈 8 条母线不进头部任何网格(抖耳 0 / −0.15 / −0.3 三档)的最小值,再加 ≈1 cm(和狐狸 0.320 → 0.331、
猫 0.305 → 0.316 的余量一致)。

### 测试与验收

- 新增 `tests/test_species_panda_penguin.gd`(5 个):目录末尾两项、竹枝与叶子都在左边、眼皮颜色跟着眼斑 / 白脸、企鹅无耳有帽、
  两种待机小动作能播完复位。
- 改动的旧测试(意图不变):`test_species`(10 个、下标 8/9 合法、单字不重复)、`test_species_picker`(5 列回绕、面板宽 ≤480)、
  `test_lobby_model`(非法下标改成 10;德州 8 人都要鳄鱼时分到前 8 个物种)、`test_banter_net` / `test_net_rpc_order`(协议 v10)。
  其余按 `Species.count()` 遍历的测试(结构预算、脖子、手牌遮挡、举枪、穿模、斗地主帽、叫声、通缉令、舞蹈)自动覆盖新物种。
- 截图:10 个物种一排(正面 / 半排 / 背面 / 头像机位)、两种身份帽、各自特写、骗子酒馆越肩 / 对手特写 / 举枪、德州 8 人桌、
  搞笑表演(吐舌头、吓一跳、煤灰 + 番茄、蚊香眼与星星)、5×2 挑选面板与头像条。
- 性能:骗子酒馆 4 人展台换上熊猫、企鹅后越肩机位 314 draw call(原来 322,企鹅少两只耳朵),帧耗时不变,预算通过。
