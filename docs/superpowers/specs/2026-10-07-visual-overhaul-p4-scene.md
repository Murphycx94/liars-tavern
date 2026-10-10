# 子项目④ 场景：墙地 shader v2、木构线脚、墙饰图集、壁炉／吧台／窗／门／角落、壁灯、地毯贴花与氛围（评审修订版）

> 子项目详细设计。总纲见 `2026-10-07-visual-overhaul-design.md`;冲突时以总纲第 3 节「已定决策」与第 4 节「裁定」为准。
> 状态:已确认(用户授权自审)。本文由设计 agent 起草、对抗性复核修正;文中「实测」数据来自 scratchpad 原型,未入库。

> 行号以 eadc745 为准，① B0 已提交的工具（476630d、180cd28：`tools/camera_views.gd`、`perf_budget.gd`、`scene_census.gd`、`image_stats.gd`、新版 `perf_probe.gd`）按当前代码引用。①②③ 会改 `tavern.gd`、`materials.gd`、`wood.gdshader`，写 ④ 的实施计划时要按当时的代码重新定位行号。

## 0 结论

**做完 ④，房间的 draw call 和帧时间都比开工前低。**

- **省下的大头是 R1**：墙地 shader 的 fbm 每像素约 80 次哈希，改成启动时用 GPU 烘焙一张可平铺噪声贴图，按 mip 采样。
- **新增几何的组织方式**：
  - 不投影的布景按材质整屋合并（§1.3 修订 ① A5.2）；
  - 投影物按区域合并；
  - 同形重复件共享网格、自动实例化：吧凳、木桶、桶箍、货箱、壁灯。
- **房间 draw call（可见 + 阴影，估算）**：seat 约 89 → 54，menu 约 110 → 69（§7）。
- **材质与灯**：
  - 唯一材质净 −2（删 5、加 3）；
  - 新增 1 个 spatial shader（`decor.gdshader`，需修订 ① 的着色器预算，见 §1.3）和 1 个只在启动时用的 canvas shader；
  - 不新增灯；
  - 壁灯去掉半透明玻璃（R12）。

### 实测要点（M3、1080p、RenderBudget；机器负载 47–140，只看同进程的相对值）

| 对比 | 结果 |
|---|---|
| v1 墙地 shader 对比纯色材质 | v1 贵 1.0–1.5 ms |
| v2 仍用 ALU fbm，对比 v1 | 再贵 2.2–2.5 ms，否决 |
| v2 改用噪声贴图，对比 v1 | 快 0.4–0.7 ms（menu 9.40→8.69、seat 9.91→9.27、selfshot 8.48→8.08） |
| 暖色 LUT + 分层 FogVolume + 12 个贴花 | ≤ +0.1 ms，在噪声范围内 |
| 墙饰图集 2048×1024 | 主线程 23–25 ms，墙钟约 68 ms，与 CardFaces 的等待帧并行 |
| GDScript 写 Packed 数组建网格 | 约 0.55 µs/顶点 |

**附带发现（交给 ①）**：`tools/perf_probe.gd:223-241` 的 `plain-shaders` 仍然改的是 `surface_override_material`，被 `MeshKit.add` 设置的 `material_override`（mesh_kit.gd:9）盖住，等于什么都没换。所以审计里「程序化 shader 只占 0.27 ms」不成立，真实成本约 1.0–1.5 ms。

---

## 1 范围、依赖与共享规则

### 1.1 范围

**做**：
- R1 墙地 shader v2
- R2 线脚与木构
- R3 墙饰图集与摆放
- R4 壁炉
- R5 吧台
- R6 窗
- R8 前墙门
- R7 角落
- R9 地毯
- R10 接地贴花
- R11 LUT 与分层雾
- **R12 壁灯**（其他子项目都没覆盖）

**不做**：
- 牌桌、吊灯、烛台、目标架、FX（③）；
- 吧台啤酒杯和泡沫自发光（③ P8、① V4）；
- 椅子与角色（①②）；
- 酒瓶 MultiMesh（① F5，④ 只在柜面加实例）；
- 不加灯、不加 ReflectionProbe、不做画质档位。

### 1.2 依赖

以实际实现为准；缺什么由 ④ 补上并配测试。

**①**：
- MeshKit 层与投影：
  - `LAYER_WORLD`：层 1，默认层，所有投影物；
  - `LAYER_MOON`：值 4，只放窗组；
  - `SHADOW_AUTO`：最大边 < 8 cm 的件不投影；
  - 吧台吊灯 spot 和壁炉 omni 的 `shadow_caster_mask = LAYER_WORLD`，月光 `= LAYER_MOON`（① A4）。
- MeshForge：
  - 接口：push/pop、primitive、quad、lathe、rounded_box、paint、commit、cached、clear_cache，`part_space` + `seed`（写入 CUSTOM0）；
  - 顶点布局：COLOR.rgb = sRGB albedo，COLOR.a = AO，UV2 = (roughness, metallic)。
- 材质：`WorldMaterials.wood(preset, part_space)`、`prop()`（`prop.gdshader`，③ 扩展了调色板）。
- 工具：`tools/scene_census.gd`、`camera_views.gd`、`perf_budget.gd`、`image_stats.gd`、`perf_probe --assert-budget`。
- 规则：① A5/A6 的硬规则。

**②**：
- `Species`（`src/core/species.gd`）：`IDS`、`LABELS`、`count()`；
- `SpeciesRecipes.get_recipe(i)` 里的 `ears.kind`、`hat.kind`、`snout.kind`；
- `patron_parts.gd` 已删除；
- loft/tube/blob 原语。

**③**：吧台啤酒杯 MultiMesh、烛台、牌桌、吊灯；prop 调色板里的黄铜、铁、蜡、陶。

**④ 需要补的接口**（若缺）：
- MeshForge：
  - `part_space_xf(xf)`：CUSTOM0.xyz = xf × 局部顶点；
  - `uv_rect(rect)`、`uv2(mode, param)`；
  - `quad(size, t, seg, curl)`；
  - `loft(..., miter := true)`。
- MeshKit：`const LAYER_SCENERY := 8`（层 4，不进任何灯的 caster mask）。

### 1.3 对 ① 共享规则的两处修订

这是 ④ 计划的第 0 步：先改共享架构文档，并请 ① 的负责人确认。

**1. A5.2 合批规则**

原规则是「按墙或按道具簇合并，包围盒对角线 ≤ 约 4 m，禁止全局合并」，依据是阴影 pass 剔除不掉大包围盒（审计实测图元 281k → 393k）。修订为：
- **投影物**（LAYER_WORLD / LAYER_MOON）：仍按区域合并，对角线 ≤ 4 m；
- **布景**（LAYER_SCENERY 且 cast_shadow=OFF）：允许按材质整屋合并，包括地板、天花板、灰泥、护墙板、线脚、木构；
- **窗组**（LAYER_MOON）：沿用 ① 的整面窗墙分段，三角形 < 2k，作为例外记录。

**2. 着色器预算**

原规则是「自定义 spatial 着色器 ≤ 4」。③ 已经加了 `soft_particle_lit`，④ 再加 `decor`，上限改为 ≤ 6。理由：
- 一份 decor 材质覆盖纸面、外景、镜面、地毯、布料、余烬六种用法；模式写在顶点上，可以跨物件合并；
- 换成 StandardMaterial3D 至少要 3 个变体，而每个变体本身也是一份要编译的着色器；
- StandardMaterial3D 做不了与分辨率无关的地毯纹样。

### 1.4 不变量

- **房间常量**：`ROOM_HALF`、`ROOM_HEIGHT`、`WALL_THICKNESS`、`WAINSCOT_HEIGHT`、`WINDOW_Z`、`WINDOW_SIZE`、`WINDOW_BOTTOM`、`SCONCES`（tavern.gd:7-23）；`SeatLayout.TABLE_TOP` / `TABLE_RADIUS`（seat_layout.gd:6-7）。
- **月光**：位置和目标的数值不变，改为由 `RoomLayout.MOON_POS = (6.6, 3.275, −0.3)`、`MOON_TARGET = (0.5, 0.2, −0.6)` 提供（同 tavern.gd:361）。
- **壁炉**：Fireplace 枢轴 (−1.5, 0, −4.4)；omni 局部 (0, 0.5, 0.75)；火星粒子局部 (0, 0.3, 0.3)（tavern.gd:251-279）。
- **节点名**：灯的父节点名 `Fireplace` / `LampPivot` / `Sconce` / `Candles` / `Bar` 不变（perf_probe 的 `_lights_under` 按前缀找灯）。
- **壁灯**：Light3D 局部位置 (0, 0.05, −0.2)、能量和 `_flickers` 参数都不变（tavern.gd:399-406）。
- **协议**：不动。② 之后是 v5，④ 是纯视觉改动。

---

## 2 实验与实测

实验在 `scratchpad/design_lab/scene/repo` 里做（git archive 副本），仓库本身没有改动。

| 实验 | 结果 | 说明 |
|---|---|---|
| `lab/shader_ab.gd`：v2 / v1 / 纯色交替，在 material_override 层替换全部 wood 和 stone 材质 | 见 §0 | 贴图版绑的是三张 NoiseTexture2D（FastNoiseLite 的 simplex fbm、value、cellular），不是本设计的 GPU 烘焙 RGBA8。「采样代替 ALU」的结论适用，烘焙路径的主线程耗时是估算。④a 必须用真实的 SurfaceNoise 复测 |
| `lab/region_stats.gd` | 基线 13.0，未调参的原型 17.2，验收线 ≥ 18 | 正式指标改用 `tools/image_stats.gd` 的 `luma_stddev` |
| `lab/atmo_ab.gd` | LUT、FogVolume、12 个贴花合计 ≤ +0.1 ms | FogVolume 为 9×1.4×9、中心 y 2.7、全局密度 0.025，没有 HearthHaze；贴花 1×0.3×1、cull_mask=1。④f 用最终参数复测 |
| `lab/atlas_proto.gd` | 主线程 23–25 ms（其中建 SystemFont 11–13 ms、回读 5 ms、mipmap 1.5 ms、上传 5–7 ms） | 只验证耗时。原型 8 张通缉令是同一个熊头，内容不代表设计 |
| `lab/forge_bench.gd` | 20 只木桶共 7.5k 顶点，4 ms | — |
| `lab/noise_time.gd` | NoiseTexture2D 约 290 ms 后才就绪 | 所以 R1 改用 GPU 烘焙 |
| `lab/headless_tavern.gd` | 无头构建 53.7 ms | 说明无头集成测试可行 |
| Godot 4.7.2 ClassDB 查询 | FogMaterial 只有 density、albedo、emission、height_falloff、edge_fade、density_texture；Light3D 有 shadow_caster_mask；Decal 有 cull_mask | — |

---

## 3 代码结构

### 3.1 新文件

每个文件都有 `class_name`，注释用中文。

**`src/world/room_layout.gd`（RoomLayout）**

纯数据和纯函数，可以 TDD。
- **布局常量**：墙段切分、`DOOR_X = −0.35`、门宽 1.2、门高 2.30、`panel_fit(length, target)`、`BEAM_Z`、`beam_support(wall, z) -> POST | CORBEL`。
- **壁炉网格**：`HALF = 0.16`、`COURSE = 0.2`、`GRID_ORIGIN = (−2.62, 0, −3.92)`。
- **`PLACEMENTS`**：每个陈设、家具、道具簇一条，字段为 `id`、`region`、`kind`、`center`、`size`、`rot_deg`、`layer`、`mount`（wall / floor / shelf）、`wall`、`offset`。这是唯一的数据源，构建器只从这里取坐标。
- **几何查询**：`focus_backdrop(angle)`、`head_silhouette(angle, count)`、`CAMERA_PATHS`、`clearance_violations(min_dist)`。
- **月光**：`MOON_POS`、`MOON_TARGET`、`moon_uv()`。

**`src/world/surface_noise.gd`（SurfaceNoise）**
- 在 SubViewport 里用 GPU 烘焙 512² 可平铺噪声，流程同 `card_faces.gd:41-80`；
- 提供 `build(host)` / `is_built()` / `texture()` / `clear()`，以及纯函数 `period_for_octave(k)`；
- 无头时返回 4×4 灰（0.5）。

**着色器**
- `src/world/shaders/surface_noise_bake.gdshader`：canvas_item，只在启动时用一次。
- `src/world/shaders/surface.gdshaderinc`：`n_lo`、`n_hi`、`n_cell`、`bump_normal`、`seg_dist`、`aa_line`。
- `src/world/shaders/decor.gdshader`：见 §4.4。

**`src/world/decor_atlas.gd`（DecorAtlas，内部类 DecorPainter）**
- 墙饰图集，流程同 CardFaces；
- 无头时回退为 8×8 羊皮纸色；
- `rect(id) -> Rect2` 是常量表；
- SystemFont 用静态变量缓存。

**构建器**：静态函数 `build(parent) -> Node3D`，坐标全部取自 PLACEMENTS。
- `src/world/room_shell.gd`（RoomShell）
- `fireplace_set.gd`（FireplaceSet）
- `bar_set.gd`（BarSet）
- `openings_set.gd`（OpeningsSet）：窗、门、外景
- `room_props.gd`（RoomProps）：墙饰、角落、钢琴、衣帽架、地毯、贴花，以及 `sconce_mesh()`

### 3.2 改动的文件

**`tavern.gd`**
- 只保留环境、灯光、闪烁、吊灯摆动；
- 新增：`_process` 里加一行钟摆摆动，加 LUT 和两个 FogVolume；
- `_build_room` / `_build_fireplace` / `_build_bar` / `_build_window` / `_build_barrels` 改为调用构建器；
- `_sconce` 改用共享网格，灯和 `_flickers` 原样保留；
- 月光改用 RoomLayout 的常量；
- ③ 负责的 `_build_table` / `_build_lamp` / `_build_candles` 和杯子不动。

**`materials.gd`**
- 新增预设 `wainscot`、`ceiling`，plaster 和 fireplace 增加 v2 参数；
- 删除 `wall`、`wall_side`；
- 新增 `decor()`、`refresh_textures()`：遍历 `_cache`，给用到 `surface_noise` 或 `atlas` 的材质重新绑定贴图；
- 新增缓存项 `lut` 和 `decal_soft`。

**其他源文件**
- `mesh_kit.gd`：新增 `LAYER_SCENERY`。
- `mesh_forge.gd`：只在 ① 缺少 §1.2 列出的接口时补充。

**`main.gd`**
- `_ready` 一开头以不 await 的方式启动 `SurfaceNoise.build(self)` 和 `DecorAtlas.build(self)`，与 `CardFaces.build`（main.gd:51）共用等待帧；
- 在 `await CardFaces.build(self)` 之后、首次 `_show_menu()`（main.gd:56）之前，await 两者 `is_built()`，再调 `WorldMaterials.refresh_textures()`；
- `_back_to_menu` 进入 `_show_menu` 时不再等待；
- `_exit_tree`（main.gd:82-88）加上 `DecorAtlas.clear()`、`SurfaceNoise.clear()`。

**工具**
- `tools/showcase.gd:5-7`、`tools/shot.gd`（不带 showcase 的路径也要）：先建噪声和图集，再 refresh，否则截图是回退色。
- `tools/camera_views.gd`：加 focus0 / 90 / 180 / 270 / 120 / 240（复刻 `table_world.gd:163-169`）、door、corner 视角。
- `tools/perf_probe.gd`：
  - 加 `room-off` 和 `decor-off`，只隐藏 ④ 建的 MeshInstance3D、MultiMesh、Decal、FogVolume，**灯一律不动**；
  - 打印 `RENDER_TEXTURE_MEM_USED`。
- `tools/perf_budget.gd`：若 LIMITS 还不是最终预算，④ 发版时改成最终值。
- 新增 `tools/startup_probe.gd`：测 ④ 的主线程份额。
- `tools/shot.gd`：加 `--flicker`，统计区域用 `image_stats.gd`。

### 3.3 无头安全与缓存释放

- MeshForge 只操作数组。
- SurfaceNoise 和 DecorAtlas 在无头时走回退，`rect()` 仍可用，几何照样生成。
- Decal、FogVolume、GradientTexture 在哑渲染器下可以创建。
- Decal 不挂在头部子树下。
- 静态缓存的释放：
  - `DecorAtlas.clear()`、`SurfaceNoise.clear()` 在 main.gd 里调用；
  - LUT 和贴花贴图走 `WorldMaterials._cached`，由 `clear_cache` 释放；
  - 共享网格走 `MeshForge.cached`，由 ① 的 `clear_cache` 释放。

---

## 4 渲染约定

### 4.1 层与投影

| 层 | 成员 | 投影 | 进哪些 caster mask |
|---|---|---|---|
| LAYER_WORLD (1) | 壁炉石体、壁炉台梁（Mantel）、柴（炉内和柴堆）、吧台台身（含台面 surface、后吧下柜）、吧凳和琴凳、木桶身、桶箍、货箱 | 开 | 吊灯、壁炉（① 不变） |
| LAYER_MOON (4) | 窗墙灰泥、窗墙护墙板、窗框（含窗台摆件 surface）、窗帘 | 开 | 月光 |
| LAYER_SCENERY (8) | 地板、天花板、三面实墙的灰泥和护墙板、线脚、木构（梁、柱、托架、斜撑、门套、门扇、衣帽架杆、后吧框架、垫木）、全部 decor 和小件 prop 网格、钢琴、外景板、壁灯 | 显式 OFF | 无 |

- 贴花 `cull_mask = LAYER_SCENERY`，只投到地板和地毯上；酒客和腿脚在层 1，投不到。
- 三盏投影灯的 caster mask 不改。

### 4.2 合批（按 §1.3）

- **整屋布景网格 6 个**：floor、ceiling、plaster（三面实墙加前墙三块）、wainscot、trim、timber。
- **区域网格**：每面墙 1 个 decor 和 1 个 prop，地面 decor 1 个；投影物各按区域合并，包围盒对角线 ≤ 4 m。
- **共享实例**：
  - 吧凳 4 只 + 琴凳 1 只；
  - 木桶 6 只 + 桶箍 6 组；
  - 货箱 3 只；
  - 壁灯 7 盏。

### 4.3 材质清单

- **删除（−5）**：
  - `wood:wall`、`wood:wall_side`（合并为 wainscot）；
  - 窗玻璃 glass（tavern.gd:349）；
  - 余烬 emissive（tavern.gd:264）；
  - 壁灯 glass（tavern.gd:396）。
- **新增（+3）**：`wood:wainscot`、`wood:ceiling`、`decor`。
- **净 −2**。啤酒面 emissive（tavern.gd:328）归 ① V4 / ③ P8，不计入 ④。
- **部件空间变体**：
  - ④ 合并网格里的木材一律用 `wood(preset, true)`；
  - floor 和 ceiling 是独立平面，用 `wood(preset)`；
  - 同一预设不得同时存在两种变体（测试检查）。
- 新材质都走 `_cached`（materials.gd:161-165）。

### 4.4 decor.gdshader

**基本设置**
- `render_mode diffuse_burley, cull_disabled`。
- 采样器：`atlas`（source_color，线性 mipmap + 各向异性）和 `surface_noise`（**不标** source_color）。
- `uniform vec4 rug_sizes[2]`，由 RoomProps 从 RoomLayout 填入。

**顶点约定**
- `UV`：图集 UV；地毯用局部米制坐标。
- `UV2.x`：模式，用 `varying flat` 传给片元。
- `UV2.y`：参数；地毯里存地毯编号。
- `COLOR.rgb`：sRGB 色调，着色器内先转线性（与 ① 的布局一致）。
- `COLOR.a`：烘焙 AO。

| 模式 | 用途 | 着色 |
|---|---|---|
| 0 纸 / 画布 | 海报、招牌、画、钟面、琴键、乐谱、箱子印字 | ALBEDO = atlas × tint × ao，夹到 ≤ 0.8；ROUGHNESS 0.88；纸纤维用 noise G 通道调 ±4% |
| 1 外景 | 窗外夜景、门外夜街、门廊地板 | ALBEDO = 0，SPECULAR = 0，EMISSION = atlas × param；不受光 |
| 2 烟熏镜 | 后吧镜面 | 底色 (0.02, 0.022, 0.025)；METALLIC 0.85；ROUGHNESS = 0.12 + 0.25 × 烟熏（noise R）；四周烟熏暗角；离边 4 cm 处画 1.5 cm 金线；EMISSION 为自下而上的暖色渐变 × 0.3 |
| 3 纳瓦霍地毯 | 两块地毯和流苏条 | 程序化图案，见 §5.9 |
| 4 布料 | 窗帘、麻袋 | tint × (0.85 + 0.3 × 织纹)，织纹用 noise G、在 uv × 60 上采样；边缘 sheen = pow(1 − NdotV, 2) × 0.35 |
| 5 余烬 | 炭床 | EMISSION = 橙红 × pow(1 − cell, 6)，随 TIME 慢速滚动并加噪声脉动，强度约 3（略超辉光阈值 1.3） |

### 4.5 部件空间与面板拟合

**护墙板**
- 用 `part_space_xf` 写入 CUSTOM0 = (u, v, depth)：u 是沿墙到墙段起点的距离，v 是离地高度。
- 每个墙段**单独**按 `panel_fit(L, 0.62)` 拉伸 u，使面板数为整数（拉伸 ≤ 15%）。墙段由角柱、墙柱、门套、壁炉、后吧、窗套分隔。
- shader 用 `panel_pitch = 0.62`，`grain_axis = 1`，`across_axis = 0`。

**竖向构件**（柱、斜撑等）：把纹理轴旋到构件的长轴上。

---

## 5 各条目设计

### 5.1 R1 墙地 shader v2（零新增 draw call，帧时间为负）

#### SurfaceNoise

512² RGBA8，可平铺：

| 通道 | 内容 | 周期 |
|---|---|---|
| R | 5 层值噪声 fbm，倍频正好 2，第 k 层格点按 16·2^k 取模，每层偏移取整数 | 一张贴图 = 16 个单位 |
| G | 2 层细值噪声 | 128 个单位 |
| B | 细胞噪声 F2−F1，12×12 格回绕 | 12 格 |
| A | 恒为 1，不存数据 | — |

- **与 noise.gdshaderinc 的关系**：那里的 fbm 倍频是 2.03、偏移不是整数，不是周期函数（noise.gdshaderinc:45-54），所以只求统计上相近，具体在 ④a 目视调参。
- **烘焙流程**：
  - SubViewport 512²，`use_hdr_2d = false`、`transparent_bg = false`、`UPDATE_ONCE`；
  - ColorRect 挂 canvas_item shader；
  - 等待帧同 card_faces.gd:41-80；
  - 回读 1 MB，`generate_mipmaps`，建 ImageTexture。
- **主线程耗时**：估计 3–5 ms，由 startup_probe 实测。

#### surface.gdshaderinc

- `n_lo(p) = R(p/16)`，`n_hi(p) = G(p/128)`，`n_cell(p) = B(p/12)`；
- 采样器：`filter_linear_mipmap_anisotropic, repeat_enable`；
- `bump_normal`：屏幕导数凹凸，不需要切线。

**规则**：凹凸只取解析形状（板缝、面板倒角、灰缝、裂缝、露砖边），不用噪声，避免 8 位量化在法线上出现色带。

#### wood v2

**基于 ① 改过的 wood.gdshader 重写**，保留 `use_part_space` 和 `part_seed`。新增 uniform，默认值保持旧行为：
- `stagger` 1、`plank_tint` 0、`bevel` 0、`nails` 0、`joist_spacing` 0.6；
- `wear_ring`、`wear_seg_a`、`wear_seg_b`（vec4）、`wear_seg_width` 0.5；
- `stains` 0、`stain_focus_a`、`stain_focus_b`（vec3：x、z、半径）；
- `pattern` 0、`panel`（stile、rail、bevel）、`panel_pitch` 0.62、`panel_height` 1.1。

**噪声来源**：
- warp 和 blotch 取 `n_lo`；
- grain 和 fibre 取 `n_hi`（G 通道）：横纹方向在 ×80 缩放下每 1.6 m 才重复一次，取 R 通道则是 0.2 m。

**木板模式**（`plank_width > 0`）：
- **逐板色差**：板号哈希驱动 ±`plank_tint` 的明度和色相，粗糙度 ±0.04。
- **板缝**：`smoothstep(0, max(0.0025, 1.2·fwidth(edge)), edge)`，暗度按 `fwidth` 在远处淡出，避免摩尔纹。
- **倒角**：h = `smoothstep(0, 0.007, edge)`，做导数凹凸。
- **钉头**：
  - 每根龙骨（每 0.6 m）每板 2 颗，板端离端头 3.5 cm 处各 2 颗；
  - 半径 4.5 mm，铁色，METALLIC 0.6，ROUGHNESS 0.35；
  - 距离淡出：`nail *= 1 − smoothstep(0.5, 1.0, fwidth(d)/0.0045)`。shots_v2tex/seat.png 里远处的钉头排成虚线，所以小于一个像素时直接淡出，不再平均成虚线。
- **磨损**：环形加两条线段，减轻木纹、提亮 30%、粗糙度 +0.12，再乘一层 `n_lo` 斑驳。
- **酒渍**：`n_lo(xz × 0.9)` 取阈值，内部暗 35%、边缘暗 30%、粗糙度 −0.3，强度乘以离 stain_focus 的远近。

**框芯模式**（`pattern == 1`）：
- 竖梃宽 0.08，横档 0.10，斜面 0.045；
- 高度层级：框 1.0 / 芯底 0.3 / 芯面 0.8；
- 横档用横纹，竖梃和芯板用竖纹；
- 每块芯板单独色差；框与芯交界压暗 0.6。

#### stone v2

**通用**：COLOR.rgb 按 sRGB 先转线性再乘。

**砌石**（`block_size > 0`）：
- 奇数行偏移半块，取代 `hash12(row)` 随机偏移（stone.gdshader:32-34）；
- `grid_origin`（vec3）：正面 u = x − x0，侧面 u = z − z0，顶面 (x − x0, z − z0)；
- 灰缝凹 6 mm；炉膛靠顶点色熏黑。

**灰泥**：
- 污渍：双尺度 `n_lo`；颗粒：`n_hi(q × 70)`，靠 mip 抗锯齿。
- 竖向变化：压条上方 0.35 m 的手印带暗 20%；离天花板 1.3 m 内的烟熏暗 45%。
- 壁灯灰晕：`halos[8]` + `halo_count`，由 RoomShell 按 `SCONCES` 填入（y + 0.05），强度 0.85。
- 露砖斑块：
  - 只出现在压条以上 0.35 m 到天花板以下 0.6 m；
  - 带外用减法 `pm = n − (1 − amount) − (1 − band) × 0.5`，不能用乘法；
  - 破口边缘提亮 12%，砖面凹 2.8 mm；砖 0.22 × 0.075 m 错缝。
- 裂缝：`n_cell` 的细胞边线，压暗 60%，凹 1.2 mm。
- 每面墙按法线方向取不同种子。

#### 预设（materials.gd:13-59, 81-95）

| 预设 | 主要参数 |
|---|---|
| floor | plank_tint 0.16、bevel 1、nails 1、stains 0.8；wear_ring (0, −0.05, 2.15, 0.35)；wear_seg_a (−0.35, 4.35, −0.3, 1.8)；wear_seg_b (−1.0, −1.85, −1.5, −3.1)；stain_focus_a (−2.6, −0.6, 1.6)；stain_focus_b (0, 0, 2.6) |
| wainscot | pattern 1、panel (0.08, 0.10, 0.045)、panel_pitch 0.62、panel_height 1.1、bevel 1、plank_tint 0.12；颜色沿用 wall |
| ceiling | 颜色沿用 beam；grain_axis 2、across_axis 0、plank_width 0.18、plank_length 1.5、stagger 0（板端落在 z = 1.5k，藏在梁下）、bevel 1 |
| plaster | color_a (0.31, 0.275, 0.23)、color_b (0.19, 0.165, 0.14)、brick_amount 0.18、crack_amount 0.5、rail_y 1.13、ceiling_y 3.4 |
| fireplace | block_size 0.2、grid_origin (−2.62, 0, −3.92)、soot 0.9 |

### 5.2 R2 建筑线脚与木构

#### 墙体

- 墙用盒子拼。
- 护墙板外凸 1.5 cm：内表面在 4.385，灰泥在 4.4。
- 前墙按门洞拆三块：左 x −4.4..−0.95、右 0.25..4.4、门楣 y 2.30..3.40。
- 窗墙沿用 tavern.gd:144-154 的四块拆法，归 LAYER_MOON。
- **后吧区段**（左墙 z −2.26..1.06）0.92 m 以上不做护墙板和压条：下柜盖住下段，镜子直接贴在灰泥上。

#### 线脚

wood:dark，部件空间，用 loft 斜接沿墙扫掠，属于布景。

| 部件 | 截面与位置 | 中断处 |
|---|---|---|
| 踢脚线 | 高 0.14、凸出 0.025，顶部倒角 | 门套脚墩、壁炉两侧、后吧下柜两端、四根角柱 |
| 墙裙压条 | 盖板顶 y 1.13、凸出 0.045，下挂 r 0.02 的四分之一圆线；替换 tavern.gd:139-141 的方条 | 门套、壁炉、整段后吧；窗下由窗台盖住 |
| 顶线 | 凹弧截面 y 3.28–3.40、深 0.10 | 后墙绕烟囱腔斜接；侧墙在每根梁两侧断开；四角断在角柱上 |

#### 木构

wood:beam，部件空间，布景。
- **梁**：5 根，改为倒角盒（r 0.015），位置不变（tavern.gd:116-118）。
- **角柱**：4 根，rounded_box r 0.012，0.16 × 0.16 × 3.4，中心 (±4.32, ±4.32)。
- **梁端**：`beam_support` 判定，禁区为壁灯 ±0.3 m、窗洞加套加窗帘 z −1.95..0.15、后吧 z −2.26..1.06、门、PLACEMENTS 里的墙饰。
  - **POST**（落地墙柱）：左墙 z 1.5、左墙 z 3.0、右墙 z −3.0、右墙 z 3.0。墙柱 0.16 × 0.12 × 3.16；每根配 1 根斜撑，在梁的竖直面内从柱上 y 2.70 斜到梁底，伸到 |x| = 3.86。
  - **CORBEL**（托架）：其余 6 处，涡卷截面挤出，y 2.86–3.16、深 0.3。
  - 10 个梁端都加铁箍（prop）。
- **壁炉台梁不进 timber**，见 R4。

#### 天花板

只靠 shader 分板，不加几何。

#### 合并结果

6 个整屋布景网格；窗组 4 个网格，见 R6。

### 5.3 R3 墙饰图集与摆放

#### 图集布局（2048×1024 RGBA8 + mipmap，约 11.2 MB）

| 区域（像素） | 内容 |
|---|---|
| (0,0)–(1536,256) | `Species.count()`（8）张通缉令，每张 192×256 |
| (1536,0) 256² | 钟面（罗马数字，指针停在 11:55） |
| (1792,0) 起 | 乐谱 128×160；印字 XXX / DYNAMITE / BEANS 各 128×64；琴键 256×32（在 (1792,224)） |
| (0,256) 512² | 窗外夜景：渐变天空、星星、月亮（在 `moon_uv()` 处，带光晕）、台地与仙人掌剪影 |
| (512,256) 512² | 门外夜街：对面的假立面建筑（HOTEL / BANK / SHERIFF）、暖光窗、拴马栏、水槽、灯笼光 |
| (1024,256)、(1344,256)、(1664,256) | 3 幅画，各 320×224：台地落日、驿站马车、野牛草原 |
| (1024,480) 512×256 | 门廊木板（月光冷灰） |
| (0,768) 1024×128 | 招牌「骗子酒馆 LIAR'S TAVERN」 |
| (1024,768) 512×128 | 「不许出老千 NO CHEATING」 |

#### 通缉令

风格是羊皮纸上的单色深褐墨线木刻。
- **文字**：WANTED + `Species.LABELS[i]` + 玩笑赏金。赏金按 id 查常量表 `BOUNTIES`，回退为「赏金：一桶啤酒」；不出现数字金额、货币符号或筹码。
- **头像**：头部椭圆，加上分别按配方 `ears.kind`、`snout.kind`、`hat.kind` 选的耳朵、吻部、帽子剪影。遇到不认识的 kind 走通用画法（圆耳 / 圆吻 / 无帽）并 push_warning。只用墨色，不读毛色，跟 ② 的调色板解耦。

#### 颜色、字体与无头

- **颜色上限**：纸色 ≤ sRGB (0.80, 0.74, 0.60)，墨色 (0.16, 0.11, 0.08)。
- **字体**：复用 `CardFaces.letter_font()` / `glyph_font()`；画之前用 `has_char` 检查，缺字改画纯拉丁文本。
- **无头**：`rect()` 照常可用。

#### 摆放

以 PLACEMENTS 为准。
- **离墙距离**：平面件 5 mm；海报 0.30 × 0.40 m，有两种卷边变体，根部 5 mm，卷边 ≤ 25 mm；钉子归 prop；招牌离檐口面 5 mm。

| 墙 | 物件与坐标 |
|---|---|
| 后墙 z −4.395 | 狐狸海报 (0.22, 1.62) 倾 −2°；熊海报 (0.62, 1.55) 倾 +3°；摆钟 x 2.30（壳 0.34 × 0.85 × 0.12，中心 y 1.72，下半开 0.20 × 0.30 的窗露出钟摆；钟面 y 1.95；钟摆枢轴 (2.30, 1.80, −4.33)，摆 ±6°）；野牛草原画 (3.82, 1.62) 0.56 × 0.40；牛骷髅见 R4 |
| 左墙 x −4.395 | 猪海报 z 2.60 y 1.62；猫海报 z 3.40 y 1.58；乌龟海报 z 3.78 y 1.66；「不许出老千」z 3.60 y 2.08，0.60 × 0.15；镜子和招牌见 R5 |
| 前墙 z 4.395 | 羊驼海报 (0.82, 1.62)；猴子海报 (1.20, 1.55)；驿站马车画 (−2.72, 1.85) 0.60 × 0.45；马蹄铁（开口朝上）(−0.35, 2.66) |
| 右墙 x 4.395 | 鳄鱼海报 z 0.55 y 1.60；台地落日画 z −2.45 y 1.62，0.60 × 0.42；套索（tube 盘绕）z −3.35 y 1.75 |

画框用 prop 鎏金；钟壳并入 timber。

#### 特写背景（`focus_backdrop`，复刻 table_world.gd:163-169）

头心取座位外移 0.10 m、高 1.27 m（patron_3d.gd:12, 22, 279-280）。头和帽在背景墙上的遮挡半宽约 0.6–0.75 m。

| 座位角 | 背景墙与中心 | 头两侧和头顶可见的陈设 |
|---|---|---|
| 0° | 前墙 x≈0.87、y≈0.62 | 画面右：弹簧门、夜街、钢琴、马车画；画面左：衣帽架；头上：马蹄铁 |
| 90° | 左墙 z≈0.87 | 猪、猫、乌龟海报与告示；镜子、酒瓶、招牌下沿 |
| 180° | 后墙 x≈−0.87 | 壁炉右半在头后；画面左：壁炉左半、柴堆、酒桶架；头上：牛骷髅；画面右：狐狸、熊海报与钟 |
| 270° | 右墙 z≈−0.87 | 窗和窗帘围着头；鳄鱼海报；台地画与套索 |
| 120° | 视线先打到吧台前脸 (−3.04, 0.84, −1.15)，再到左墙 z≈−1.49 | 吧台、吧凳；镜子、酒瓶；头上：招牌 |
| 240° | 右墙 z≈−1.49 | 窗帘与窗的一角；台地画与套索 |

### 5.4 R4 壁炉（FireplaceSet，枢轴 (−1.5, 0, −4.4)）

半块网格：宽 0.16、行高 0.2，原点 (−2.62, 0, −3.92)。

| 部件 | 尺寸与坐标（世界） |
|---|---|
| 外框 | x −2.62..−0.38（14 个半块），前脸 z −3.92 |
| 壁柱 | x −2.62..−2.14、−0.86..−0.38，y 0..1.0 |
| 炉口 | x −2.14..−0.86，y 0..1.0 |
| 过梁 | y 1.0..1.4 |
| 烟囱腔 | x −2.3..−0.7，y 1.6..3.4（顶面在 3.4，修掉 tavern.gd:259 超出的 2 cm），z −4.4..−4.08 |
| 炉膛 | 后壁 z −4.24（深 0.32，即 2 个半块）；炉膛面、壁柱内侧、过梁底面用顶点色 0.3（sRGB）熏黑并烘焙 AO；铸铁背板（prop）0.9 × 0.7，贴在 z −4.23 |
| 炉床石板 | x −2.78..−0.22，z −3.92..−3.12，y 0..0.06；炉内延伸到 z −4.24。高度不在 0.2 网格上，测试豁免：整块落在一层砖内，面上只有竖向灰缝 |

**台梁**
- Fireplace 下单独的 `Mantel` 网格：wood:beam、部件空间、倒角，x −2.78..−0.22，y 1.4..1.6，z −4.4..−3.86；**LAYER_WORLD，投影**。
- 必须投影的原因：壁炉 omni (−1.5, 0.5, −3.65) 擦过台梁前下沿，要到烟囱腔 y≈2.34 处才落下，所以 1.6–2.34 m 这条带本应在影子里。现在的台梁（tavern.gd:257）本来就投影。

**石体**：前面 1 个网格，LAYER_WORLD。

**柴**：炉内 3 根加柴堆 6 根，合成 1 个 wood:log 网格（部件空间，端面露年轮），LAYER_WORLD，投影。

**火床**
- 柴架 2 只（prop），x −1.85 / −1.15，高 0.35；
- 余烬丘：decor 模式 5，椭圆 0.42（x）× 0.14（z）× 0.12（y），位于 (−1.5, 0.06, −4.08)，z 方向范围 −4.22..−3.94；替换 tavern.gd:264 的发光扁球；
- 6 片火焰保持原位（① F7 的共享材质）。

**周边**
- 柴堆：x −3.35..−2.9，z −4.35..−3.85。
- 火具架：(−0.12, 0, −4.2)。
- 台上摆件（prop，≤ 0.35 高）：黄铜烛台 x −2.45 / −0.55（未点燃）、锡杯 2 只、扑克盒；**不放酒瓶**。
- 牛骷髅：prop 骨色，中心 (−1.5, 2.62, −4.04)，角尖 x −2.0 / −1.0，凸出到 z −3.86。

**灯与粒子**：原样保留。

### 5.5 R5 吧台（BarSet）

**台身**
- 外轮廓保持：x −3.66..−3.04、z −2.30..1.10，y 0.10..1.05；
- 客人侧用 wainscot 面板；踢脚板退进 0.04（面在 x −3.08）；
- 台身网格两个 surface：wood:wainscot 和 wood:table；后吧下柜也并进来；LAYER_WORLD。

**台面**：x −3.70..−2.96，y 1.05..1.11，z −2.36..1.16，客人侧做 r 0.03 圆鼻。

**台前**
- 黄铜脚踏：tube r 0.022，位于 (x −2.88, y 0.20)，z −2.20..1.00，4 个 L 形支架；
- 痰盂 2 只：(−2.80, 0, −1.5)、(−2.80, 0, 0.1)，r ≤ 0.11，高 ≤ 0.15。

**台上**（prop 合成 1 个网格，布景）
- 酒头：塔在 x −3.45、z 0.45，顶 ≤ 1.50；
- 收银机：(−3.42, 1.11, −1.75)，顶 ≤ 1.48；
- 烈酒杯 5 只、雪茄盒；
- **啤酒杯是 ③ 的 MultiMesh，④ 不动。**

**吧凳**：共享网格（prop，座高 0.76），4 只在 x −2.62、z −1.9 / −1.1 / −0.3 / 0.5，LAYER_WORLD。凳心离 90° 座位椅背 1.03 m。

**后吧**（框架并入 timber）
- 下柜：x −4.40..−3.95，y 0..0.92；
- 柜面：y 0.92..0.95；
- 壁柱：z −2.26..−2.14 和 0.94..1.06，y 0.95..2.62；
- 搁板：沿用 y 1.55 / 2.0 / 2.45、x −4.33..−4.03（tavern.gd:297-305），每块加托架；
- 檐口：y 2.62..2.95，前缘 x −3.95。

**镜子与招牌**（并入左墙 decor）
- 镜子：x −4.39，z −2.14..0.94，y 0.95..2.62；
- 招牌：x −3.945，z −1.8..0.6，y 2.66..2.91。

**酒瓶**：柜面加约 6 个 ① 的 MultiMesh 实例，用**独立种子 2027**，① 的搁板瓶位和 ③ 的杯子都不变。

**吧台灯**：不动。

### 5.6 R6 窗（OpeningsSet）

**洞口**：z −1.55..−0.25，y 1.15..2.40，不变。

**窗框**（wood:dark，LAYER_MOON，投影）
- 套线 0.1 宽；窗头到 y 2.52，小檐到 2.56；
- 窗台：x 4.30..4.62，y 1.11..1.15，z −1.70..−0.10；
- 窗棂 2 列 × 3 行：竖棂 z −0.9，横棂 y 1.567 和 1.983；
- 窗台摆件是窗框网格的第二个 surface（prop）：仙人掌陶盆 (4.37, 1.15, −1.2)、未点燃的油灯 (4.37, 1.15, −0.55)。它们会在月光柱里投出剪影。

**玻璃**：删除（tavern.gd:349-351）。

**窗帘**（decor 模式 4，深酒红，LAYER_MOON，投影）
- 两幅 loft，7 道褶、幅度 0.025，平面在 **x 4.24**；
- 从 y 2.60 垂到 1.05，在 y 1.55 处收束到 45%；
- A 幅顶部 z −1.95..−1.40，B 幅 −0.40..0.15；
- 帘杆：黄铜，y 2.62，x 4.24，有托架；并入右墙 prop。

**外景板**（decor 模式 1，布景，不投影）
- x 5.40，z −2.40..0.60，y 0.58..2.98，朝 −X。
- 月亮位置 `moon_uv()`：从窗心 (4.4, 1.775, −0.9) 朝 MOON_POS 方向，与 x = 5.4 交于 (5.4, 2.279, −0.851)。u = (z + 2.40)/3.0 ≈ 0.516（u 沿 +Z），v = (2.98 − y)/2.40 ≈ 0.292。只有沿窗轴看时完全对准。

**窗组**：灰泥、护墙板、窗框（2 个 surface）、窗帘，共 4 个网格、5 次 draw。

### 5.7 R8 前墙：弹簧门、夜街、钢琴、衣帽架

**门洞**：x −0.95..0.25，y 0..2.30；离 −1.7 处壁灯约 0.65 m。

**门套**：侧套 0.11、脚墩 0.13 × 0.2；门头 y 2.30..2.46，檐到 2.50；门槛 z 4.36..4.64。

**弹簧门**：
- 两扇各 0.58 × 0.95，合页侧高 1.75、中缝处 1.62、底 0.80，每扇 9 片百叶；
- 合页线 x −0.94 / 0.24，z 4.47，分别向内开 10° 和 14°；
- 静态，并入 timber。

**外景**（decor 模式 1）
- 门廊地板：x −1.6..0.9，z 4.6..5.8，y 0.003，emission 0.25；
- 夜街板：z 5.80，**x −2.80..2.10**，y −0.05..2.95，emission 0.55。加宽是因为从环绕点 (2.9, 2.05, 1.37) 穿过门洞的视线到 z 5.8 时已在 x −2.38；
- 灯笼只画在背景里，不加光源。

**钢琴**：
- 独立网格（wood:table 部件空间，布景），不和台面合并；
- 立式，x −3.45..−2.05，z 3.78..4.33，高 1.25；
- 键床 y 0.70–0.74，伸到 z 3.55；正面 2 个未点燃的黄铜烛台；
- 琴凳复用吧凳网格（y 缩放 0.68），位于 (−2.75, 0, 3.15)。

**衣帽架**：(2.55, 0, 4.12)，杆高 1.8，并入 timber；挂 2 顶帽子和 1 件风衣（prop）。

**前右角**：
- 货箱：(3.85, 0, 3.85) 0.6³；叠在上面的 (3.8, 0.6, 3.9) 0.45³；(3.15, 0, 4.0) 0.5³；
- 麻袋：(3.35, 0, 3.45)、(4.0, 0, 3.2)，decor 模式 4。

seat 视角里这些都在镜头背后，而且在壁炉 omni 的 7 m 范围外。

### 5.8 R7 角落杂物

**木桶**：
- 共享车削桶身：wood:barrel 部件空间，20 弧段、15 轮廓点，鼓肚 +0.04，带桶口凹槽和内陷桶盖；
- 共享桶箍：prop 铁色，4 道；
- 两者都在 LAYER_WORLD。

**后右角**：
- 3 只立桶沿用 tavern.gd:367 的位置和偏航；
- 躺桶沿用 (3.4, 0.27, −3.0) 和原来的旋转，下面加 2 块垫木（并入 timber）；
- 麻袋 2 只：(4.0, 0, −2.25)、(3.6, 0, −2.35)。

**后左角**：小酒桶 2 只（桶身缩放 0.55），放在架子上，x −4.22..−3.62，z −4.22..−3.70，避开角柱。

**货箱**：共享倒角盒网格；印字是 decor 小面片，并入所在区域的 decor 网格。

### 5.9 R9 纳瓦霍地毯

> 2026-10-10 已重做为动森式毛绒地毯(圆形主毯随桌放大、条纹长毯、门口小毯),见 `2026-10-08-cozy-toon-style-design.md` §9;下面是原设计。

| 地毯 | 范围 |
|---|---|
| 主毯 | x −1.9..1.9，z −1.85..1.75（覆盖 2/3/4 人局所有椅脚和掉落帽子的中心，见 patron_3d.gd:457-458） |
| 吧台长条毯 | x −2.95..−2.15，z −2.15..0.95 |

- y 0.004，厚度为 0。
- 两端各接一条 0.08 m 宽的流苏条，**流苏在模式 3 里程序绘制**，不做几何梳齿：几何梳齿远看不到一个像素宽，会闪。
- 图案：
  - 甘纳多配色：红 (0.36, 0.08, 0.05)、炭黑、奶油 (0.62, 0.55, 0.42)、灰褐；
  - 锯齿外边框宽 0.18 m；中间沿长轴排 3 个阶梯菱形；
  - 每 0.02 m 量化成织格，织格小于 2 像素时改用平滑边；
  - 织纹用 noise G；对比度和反照率控制在 0.06–0.62，图案单元 ≥ 0.25 m。
- 两块地毯合成 1 个地面 decor 网格。

### 5.10 R10 接地贴花（12 个，0 draw call）

- 纹理：径向 GradientTexture2D（中心 alpha 0.7），缓存名 `decal_soft`。
- 参数：`normal_fade` 0.5，`distance_fade` 开。
- 位置：牌桌底座、4 只木桶、货箱堆、柴堆、钢琴、衣帽架、炉床前的灰、吧台台脚（拉长）、吧凳一排（拉长）、后吧下柜。
- 全部挂在 Tavern 下的 `Decals` 节点；`cull_mask = LAYER_SCENERY`。

### 5.11 R11 暖色 LUT 与分层雾

**LUT**：`adjustment_color_correction` = 256 宽的 GradientTexture1D，缓存名 `lut`，逐通道映射。

| 输入 | 输出 (r, g, b) |
|---|---|
| 0 | (0, 0.004, 0.018) |
| 0.18 | (0.170, 0.178, 0.196) |
| 0.5 | (0.505, 0.497, 0.478) |
| 0.82 | (0.835, 0.815, 0.775) |
| 1 | (1, 0.985, 0.95) |

效果是暗部微冷、高光微暖，高光不提亮。

**雾**：
- 全局 `volumetric_fog_density` 0.05 → 0.03（tavern.gd:94）。
- 「SmokeLayer」：长方体，中心 (0, 3.0, 0)，尺寸 (8.8, 1.6, 8.8)，density 0.05，edge_fade 0.6。菜单机位（y 2.05）在烟层之下。
- 「HearthHaze」：椭球，中心 (−1.5, 1.0, −3.6)，尺寸 (1.8, 1.4, 1.2)，density 0.04，emission = Color(0.08, 0.036, 0.012)。FogMaterial 没有能量属性，强度直接写进颜色。
- 重调体积雾能量：月光 2.5 → 约 3.2，吊灯 2.2 → 约 2.6。

### 5.12 R12 壁灯

- **现状**：黄铜方板、直臂、杯、55% 半透明玻璃罩、火焰片（tavern.gd:388-406）。
- **改成黄铜蜡烛壁灯**：
  - 部件：圆润的底板（带串珠边，0.10 × 0.22）、弯臂（tube）、接蜡杯（车削，局部 y −0.10）、奶油色蜡烛（prop 蜡，局部 y −0.09..−0.01）；
  - 合成 1 个共享 prop 网格 `MeshForge.cached("sconce")`，7 盏共享，自动实例化，布景层；
  - **不要玻璃**；
  - 火焰片保留，挪到烛芯上（局部 y 0.025）；
  - Light3D、父节点名、`_flickers` 都不变。
- **效果**：少 7 次半透明 draw、少 1 个材质；壁灯本体不再进壁炉阴影。

---

## 6 镜头净空与可读性

| 镜头 | 看到的 ④ 内容 | 净空（实算） |
|---|---|---|
| seat (0.6, 2.05, 2.45) | 地板约 40%；整面后墙，画面上缘约 y 2.9；左墙 z < −0.18；右墙 z < −2.78；月光落在桌心附近 | 见下面的「可读性」 |
| 菜单环绕（中心 (0, ·, −0.2)、r 3.3、y 2.05，main.gd:139） | 全部 | 台梁角 0.58 m；x −0.55 的烛台 0.48 m；骷髅角尖 0.64 m；壁炉石角 0.78 m；酒头在下方 0.55 m；后吧檐口水平 0.65 m（三维 0.86 m）；斜撑 ≥ 1.4 m；钢琴 1.0 m；衣帽架 1.9 m；吧台上方 y 1.7–2.4 不挂任何东西 |
| 结算环绕（r 2.4、y 1.85，table_director.gd:257） | 四面墙 | 吧凳内缘在 r≈2.44、高 0.76，竖直距离 1.09 m |
| 胜者环绕（r 1.3，table_director.gd:254） | 局部 | 离吧凳 ≥ 0.84 m |
| 观战 (0, 2.3, 2.7)、等待厅 (0.95, 2.6, 2.5)、翻牌机位 (0, 1.42, 1.05) | 后墙、壁炉、吧台、地毯 | 附近没有 ④ 的物件 |

**可读性**

静止姿态下，从 seat 机位把对手的头（r 0.17）加最高帽（帽檐 r 0.25 在头心 +0.15 处，帽顶 ≤ 世界 1.65 m）投到墙上：

| 座位 | 头心投影 | 帽顶高度 | 帽檐横向范围 |
|---|---|---|---|
| 180° | 后墙约 (−0.48, 0.64) | y≈1.33 | x −0.93..−0.03 |
| 240° | — | y≈1.17 | x 1.30..2.40 |
| 270° | — | y≈0.93 | x 2.0..3.4 |
| 90° / 120° | 后左角，位置很低 | — | — |

所有墙饰都在 y ≥ 1.35，留 0.1 m 余量后没有重叠。为此狐狸海报从 x 0.15 移到了 0.22。由 `head_silhouette` 测试守住。

---

## 7 预算账本

估算，以 room-off 实测差值为准。「进场前」指 ①②③ 完成之后。

| 条目 | seat 可见 | seat 阴影 | menu 可见 | menu 阴影 | 独有三角形 | 材质 |
|---|---|---|---|---|---|---|
| R1 | 0 | 0 | 0 | 0 | 0 | 0 |
| R2 墙体、线脚、木构 | 10→6 | 0 | 14→6 | 0 | +5.5k | ±0 |
| R3 + R9 墙饰、钟摆、地毯 | +6 | 0 | +10 | 0 | +6.8k | +1 |
| R4 壁炉 | 15→10 | 16→8 | 15→10 | 16→8 | +9k | −1 |
| R5 吧台 | 9→4 | 6→4 | 9→4 | 6→4 | +11k | ±0 |
| R6 窗 | 0 | 10→5 | 9→5 | 10→5 | +4k | −1 |
| R8 前墙 | 0 | 0 | 0→2 | 0 | +8k | ±0 |
| R7 角落 | 4→3 | 6→4 | 4→3 | 6→4 | +5k | ±0 |
| R12 壁灯 | 9→4 | 4→0 | 17→8 | 4→0 | +1.5k | −1 |
| R10、R11 | 0 | 0 | 0 | 0 | 0 | 0 |
| **合计** | **47→33** | **42→21** | **68→48** | **42→21** | **约 +51k** | **−2** |

**draw call**：房间部分 seat 89 → 54，menu 110 → 69。

**三角形**：menu 渲染约 +70k（共享件按实例计）。

**帧时间**：
- R1 实测 −0.4..−0.7 ms；
- R11 + R10 ≤ +0.1 ms；
- 几何 +0.05..0.2 ms；
- 合计约 −0.1..−0.55 ms。

**其他资源**：
- 灯不变（≤ 16，投影 ≤ 3）。
- 显存：图集 11.2 MB + 噪声 1.4 MB + 网格约 5 MB，≤ 18 MB。
- 启动（④ 的份额 ≤ 60 ms）：网格 20–40 ms + 图集 23–25 ms + 噪声 3–5 ms，合计 46–70 ms。
  - 若超出，把共享件（吧凳、木桶、桶箍、货箱、壁灯、窗帘）挪进 ① 的 MeshForge 工作线程预建。
  - 全局 +200 ms 预算由四个子项目共享。

---

## 8 实施批次

按镜头曝光度排序；每批跑测试、perf_probe 和截图对比。

| 批次 | 内容 | 本批验收 |
|---|---|---|
| ④0 | 修订 §1.3 的两条共享规则；核对 ① 的 LAYER_* 和 MeshForge 接口、② 的 Species 和配方 kind、③ 的杯子 | 规则修订已合入共享架构文档 |
| ④a 表面 | SurfaceNoise、surface 着色器公共函数、wood v2、stone v2、各预设。可以单独先发 | 交替进程 A/B：seat 快 ≥ 0.2 ms；灰泥标准差 ≥ 18；无闪烁 |
| ④b 骨架 | RoomLayout（先写测试）、RoomShell、LAYER_SCENERY、decor.gdshader、DecorAtlas 基础设施 | test_room_layout、test_tavern_build 通过 |
| ④c 画面中央与下半 | 壁炉、地毯、贴花 | 砖面无细条；台梁有影子 |
| ④d 左三分之一 | 吧台 | 酒瓶和杯子位置不变 |
| ④e 特写背景与菜单 | 墙饰全量、窗、门、角落、壁灯 | 6 个特写视角里头的两侧都有陈设；月光柱有 6 格窗影 |
| ④f 氛围与签收 | LUT、FogVolume、重调雾能量，全量签收并发版 | 全部发布验收项 |

---

## 9 测试

详见 tests 列表。要点：
- **`test_room_layout`**：纯函数 TDD，核对 PLACEMENTS、面板拟合、梁端支撑、壁炉网格、特写背景、头部剪影、镜头净空、`moon_uv`。
- **`test_tavern_build`**：无头 `Tavern.new()`，用 SceneCensus 数实例、网格资源和材质，并核对层、投影和灯。
- **`test_decor_atlas`**、**`test_surface_noise`**。
- **① 的 `test_scene_budget` / `test_scene_census`**：结构检查要适配新的节点布局，意图不变，需要明确说明。

## 10 发布验收

完整清单和测量方法见 acceptance_criteria。

## 涉及文件
src/world/tavern.gd（改为调用构建器；钟摆摆动；LUT 与两个 FogVolume；_sconce 用共享网格；月光用 RoomLayout 常量；③ 负责的部分不动）
src/world/materials.gd（新增 wainscot、ceiling 预设，plaster 和 fireplace 加 v2 参数，删除 wall、wall_side；新增 decor()、refresh_textures()；缓存 lut、decal_soft）
src/world/mesh_kit.gd（新增 LAYER_SCENERY := 8）
src/world/mesh_forge.gd（仅当 ① 缺 part_space_xf、uv_rect、uv2、quad(seg, curl)、loft miter 时补充）
src/world/shaders/wood.gdshader（v2，基于 ① 改过的版本，保留 use_part_space 和 part_seed）
src/world/shaders/stone.gdshader（v2）
src/world/shaders/surface.gdshaderinc（新）
src/world/shaders/decor.gdshader（新）
src/world/shaders/surface_noise_bake.gdshader（新，canvas_item）
src/world/surface_noise.gd（新，class_name SurfaceNoise）
src/world/decor_atlas.gd（新，class_name DecorAtlas）
src/world/room_layout.gd（新，class_name RoomLayout，纯数据和纯函数，含 PLACEMENTS）
src/world/room_shell.gd（新，class_name RoomShell）
src/world/fireplace_set.gd（新，class_name FireplaceSet）
src/world/bar_set.gd（新，class_name BarSet）
src/world/openings_set.gd（新，class_name OpeningsSet：窗、门、外景）
src/world/room_props.gd（新，class_name RoomProps：墙饰、角落、钢琴、衣帽架、地毯、贴花、壁灯网格）
src/ui/main.gd（并行启动 SurfaceNoise 和 DecorAtlas 构建，首次 _show_menu 前等待并 refresh_textures；_exit_tree 释放缓存，main.gd:82-88）
tools/camera_views.gd（新增 focus0/90/180/270/120/240、door、corner 视角）
tools/shot.gd（构建图集和噪声；--flicker；统计区域）
tools/showcase.gd（构建时一并构建图集和噪声并 refresh）
tools/perf_probe.gd（新增 room-off、decor-off，只隐藏视觉节点；打印纹理显存）
tools/perf_budget.gd（④ 发版时 LIMITS 改为最终预算）
tools/startup_probe.gd（新：测 ④ 的启动主线程份额）
tests/test_room_layout.gd（新）
tests/test_tavern_build.gd（新）
tests/test_decor_atlas.gd（新）
tests/test_surface_noise.gd（新）
tests/test_scene_budget.gd 和 tests/test_scene_census.gd（① 的测试；结构检查适配新节点布局，意图不变，需明确说明）
docs/superpowers/specs/（共享架构文档：修订 A5.2 合批规则和着色器预算）

## 测试
test_room_layout：墙段切分（门洞 x −0.95..0.25、窗洞 z −1.55..−0.25、壁炉、后吧、角柱和墙柱）后，各段长度之和等于墙长，且互不重叠
test_room_layout：每个墙段 panel_fit(L, 0.62) 得到整数块数 n ≥ 1，n·pitch == L，|pitch − 0.62| ≤ 15%
test_room_layout：beam_support 只在 左 z 1.5 / 左 z 3.0 / 右 z −3.0 / 右 z 3.0 返回 POST，其余 6 个梁端返回 CORBEL
test_room_layout：壁炉各盒子相对 GRID_ORIGIN，水平方向是 0.16 的整数倍、竖直方向是 0.2 的整数倍（容差 1e-4）；炉床石板豁免并断言其高度 < 一层砖；炉膛后壁 z == −4.24；烟囱顶 == ROOM_HEIGHT
test_room_layout：PLACEMENTS 里的墙饰不与壁灯禁区（±0.3 m）、门套、窗套加窗帘、墙柱、角柱或同墙其他陈设重叠，且都在墙面范围内；平面件离墙 3–15 mm；卷边海报根部 5 mm、卷边 ≤ 25 mm；招牌离檐口面 5 mm
test_room_layout：focus_backdrop 对 0、π/2、π、3π/2、2π/3、4π/3 六个角度，同一面墙上都至少有 1 件陈设，与背景中心的横向距离在 [0.75, 2.4] m；120° 时视线先打到吧台前脸
test_room_layout：head_silhouette——2/3/4 人局每个对手（SeatLayout.seat_angle）从 seat 机位（TableWorld.THIRD_PERSON_*）投到墙上的头（r 0.17，头心在座位外移 0.10 m、高 1.27 m）加帽（帽檐 r 0.25 在头心 +0.15 处，帽顶 ≤ 1.65 m）剪影，不与任何 y ≥ 1.35 的墙饰重叠，余量 0.10 m
test_room_layout：clearance_violations 为空——PLACEMENTS 里每个 AABB 离以下镜头路径都 ≥ 0.3 m：菜单环绕（每 2° 采样）、结算环绕、每个座位的胜者环绕（2/3/4 人局）、观战 (0, 2.3, 2.7)、等待厅 (0.95, 2.6, 2.5)、翻牌机位 (0, 1.42, 1.05)、6 个特写机位
test_room_layout：moon_uv() 等于窗心 (4.4, 1.775, −0.9) 朝 MOON_POS 方向与 x = 5.4 的交点换算出的 UV，约 (0.516, 0.292)，误差 ≤ 0.005
test_tavern_build（无头 Tavern.new()）：月光的变换由 RoomLayout.MOON_POS / MOON_TARGET 得到，与 tavern.gd:361 的数值一致
test_tavern_build：对 ④ 构建的子树用 SceneCensus 统计——MeshInstance3D ≤ 60；不同网格资源 ≤ 36；吧凳 + 琴凳 5 个实例共用 1 个网格，木桶 6 个和桶箍 6 个共用 2 个网格，货箱 3 个共用 1 个，壁灯 7 个共用 1 个；房间唯一材质 ≤ 16；同一木材预设不同时存在两种部件空间变体
test_tavern_build：所有 LAYER_SCENERY 几何 cast_shadow == OFF；投影物只出现在 LAYER_WORLD 或 LAYER_MOON；窗墙灰泥、窗墙护墙板、窗框、窗帘的 layers == LAYER_MOON 且投影；Mantel、壁炉石体、柴、台身、吧凳、木桶、桶箍、货箱在 LAYER_WORLD 且投影；吧台吊灯和壁炉的 caster mask == LAYER_WORLD，月光 == LAYER_MOON
test_tavern_build：灯 ≤ 16，其中投影 ≤ 3；父节点名仍以 Fireplace / LampPivot / Sconce / Candles / Bar 开头；壁灯 Light3D 局部位置仍为 (0, 0.05, −0.2)
test_tavern_build：每个区域合并网格的全局 AABB 落在该区域 PLACEMENTS AABB 的并集内（放宽 0.02 m），防止构建器偏离数据表
test_tavern_build：Decal 只挂在 Tavern/Decals 下，cull_mask == LAYER_SCENERY；FogVolume 恰好 2 个（SmokeLayer、HearthHaze）
test_decor_atlas：无头时 texture() 非空（8×8 回退）；rect() 都在 [0,1] 内且互不重叠；通缉令格数 == Species.count()；每个 Species.IDS 都有赏金文案，文案里没有数字、货币符号或「筹码」；每个配方的 ears / hat / snout kind 都有画法，未知 kind 走回退并告警；clear() 后 is_built() 为 false
test_surface_noise：无头回退为 4×4 灰（0.5）；period_for_octave(k) == 16·2^k；clear() 复位
（仅当 ④ 补了 MeshForge 接口）test_mesh_forge：part_space_xf 写入的 CUSTOM0 == xf × 局部顶点；uv_rect 写入的 UV 落在 rect 内；uv2 写入 (mode, param)；quad(curl) 的 AABB 正确；loft miter 转角处顶点共点；法线为单位长度
回归：全部现有 GUT 通过；① 的 test_scene_budget / test_scene_census 的结构检查适配新节点布局，「地板和实墙不投影、窗墙在 LAYER_MOON」的意图不变，在计划里明确说明；GDScript 里不出现 get_mesh_arrays、surface_get_arrays、get_faces 的扫描仍通过
工具验证：shot.gd --showcase 跑 10 个原视角 + focus0/90/180/270/120/240 + door + corner；--stats 输出灰泥亮度标准差和削顶比例（image_stats.gd）；--flicker 输出 60 帧相邻帧亮度差
工具验证：perf_probe --size=1920x1080 --cases=budget --assert-budget 跑 seat / menu / opponent / overhead，每个取 3 次中位数；room-off 差值算房间子预算；打印 RENDER_TEXTURE_MEM_USED；startup_probe 取 5 次中位数

## 预算影响
④ 对 draw call 和帧时间都是负贡献。房间部分 draw call 估算：seat 约 89→54（可见 47→33，阴影 42→21），menu 约 110→69（可见 68→48，阴影 42→21）；月光阴影在 seat 也计入。帧时间约 −0.1..−0.55 ms：R1 贴图噪声实测比 v1 快 0.4–0.7 ms（实验用三张 NoiseTexture2D，④a 用真实 SurfaceNoise 复测），LUT + 雾 + 贴花 ≤ +0.1 ms，新增几何 +0.05..0.2 ms。唯一材质净 −2（删 wall、wall_side、窗玻璃、余烬 emissive、壁灯玻璃；加 wainscot、ceiling、decor；啤酒面归 ①/③，不计入）。新增 1 个 spatial shader（decor，需把共享预算修订为 ≤ 6）和 1 个启动用 canvas shader。不新增灯，壁灯去掉 7 次半透明 draw。独有三角形约 +51k，menu 渲染约 +70k。显存 ≤ +18 MB（图集 11.2 MB）。启动 ④ 份额 ≤ 60 ms（网格 20–40 + 图集 23–25 + 噪声约 3–5 ms；超出时共享件挪进工作线程预建）。若 ①②③ 之后 seat ≈ 650、menu ≈ 700，④ 之后约 615 / 660，在 700 / 800 目标内。

## 验收
draw call（M3、1080p、perf_probe 的 budget 用例、阴影每帧重画、3 次中位数）：tools/perf_budget.gd 的 LIMITS 设为最终预算（seat ≤ 700、menu ≤ 800、opponent ≤ 400、其余视角 ≤ 900，硬上限 900），--assert-budget 退出码为 0
房间子预算：用 room-off 差值计算（只隐藏 ④ 建的 MeshInstance3D、MultiMesh、Decal、FogVolume，灯不动），seat ≤ 70、menu ≤ 100，且不高于进场前同口径的数值
帧时间：seat 和 menu ≤ 10.0 ms；与上一版发布做交替进程 A/B（git worktree 取上一版标签，空闲机器、接电源，两边轮流各跑 5 轮），④ 的中位数 ≤ 上一版 + 0.05 ms；④a 单发时 seat 至少快 0.2 ms；CPU 渲染线程 ≤ 1.0 ms
材质与灯：SceneCensus 统计全场景唯一材质 ≤ 40，④ 净增量 ≤ −1（目标 −2）；新增 spatial shader 只有 decor.gdshader，且共享规则已修订；灯 ≤ 16，投影 ≤ 3；④ 不新增灯和 ReflectionProbe
资源与启动：perf_probe 打印的 RENDER_TEXTURE_MEM_USED 增量 ≤ 20 MB；startup_probe 测得 ④ 的主线程份额 ≤ 60 ms（5 次中位数）；首次 _show_menu 之前 SurfaceNoise 和 DecorAtlas 都 is_built()，画面不出现回退色
观感：灰泥亮度标准差 ≥ 18（基线 13.0），用 image_stats.luma_stddev 在 decor-off 下测 seat 视角三块只含灰泥的固定矩形（矩形常量定义在 camera_views 或 RoomLayout）；脸部削顶 ≤ 5%，全帧 ≤ 1%；墙饰区域削顶 ≤ 1%
观感：壁炉石面在 fireplace、opponent、seat 视角里没有细条；台梁上方的烟囱腔能看到台梁的影子；墙饰没有 z-fighting；shot --flicker（镜头呼吸微动 60 帧）在地板和灰泥区域的相邻帧平均亮度差不高于进场前；seat 视角里地板没有钉头排成的虚线
月光：window 视角里光柱固定矩形的平均亮度保持在进场前的 90%–110%；地上能看到 2×3 窗格影子和仙人掌剪影；外景板不投影；月亮出现在窗口上部
特写背景：focus0/90/180/270/120/240 每张截图里，头的两侧或头顶至少能看到 1 件陈设；0° 自拍特写里门和夜街在头的右侧
镜头净空：test_room_layout 的 clearance 和 head_silhouette 通过；人工看一圈菜单环绕、结算环绕、每个座位的胜者环绕、观战机位、等待厅机位，无穿模；斜着看门洞时看不到夜街板外的虚空
测试：全部 GUT 通过（新增 4 个测试；① 的结构检查已适配并说明）；无头 Tavern.new() 能完整构建；正常退出时没有 ObjectDB 泄漏告警
不变量：ROOM_*、WINDOW_*、SCONCES、TABLE_TOP / TABLE_RADIUS、月光与壁炉灯的位置、壁灯 Light3D 位置都不变；协议版本不变（② 之后为 5）；啤酒杯和酒瓶的位置与 ①/③ 的版本一致
可读性：seat 视角里对手的头和帽背后没有高对比度陈设（测试加人工签收）；地毯图案不抢桌面卡牌的视觉焦点
跨平台抽检：Mac 上用 --rendering-driver vulkan 跑一遍 perf_probe 和截图；在 Windows 导出包上确认图集中文不缺字，缺字时自动改用拉丁文本

## 决策(均按推荐默认采纳)
运行时用 SubViewport 画出来的贴图（墙饰图集、启动时 GPU 烘焙的噪声贴图）算不算「全程序化」？默认：算，允许。做法与现有卡面相同，不引入任何外部图片
前墙做双开弹簧门，门外放一块夜街背景板（门往左偏 0.35 m，让自拍特写里门出现在头的右侧）？默认：做
后吧镜子用假烟熏镜（不用 ReflectionProbe，0 ms）？默认：用假镜
月光只让窗墙、窗框、窗帘、窗台摆件投影，酒客不再投月光影子？默认：如此（① 已按此实现）
调色：保留 ACES 暖调，④ 只加一张温和的 1D LUT（暗部微冷、高光微暖、高光不提亮）；AgX 只作退路？默认：如此
墙饰的文字和内容：8 个物种各一张单色木刻风 WANTED 通缉令，中英双语，配玩笑赏金（不出现钱或筹码）；吧台招牌写「骗子酒馆 LIAR'S TAVERN」，另挂一块「不许出老千」？默认：如此
壁炉上方挂牛骷髅，不挂交叉步枪？默认：牛骷髅
前墙放钢琴和衣帽架，不加带光源的灯笼（灯笼只画在门外背景里）？默认：如此
壁灯去掉玻璃罩，改成黄铜蜡烛壁灯（火焰照旧闪烁，灯光不变）？默认：改

## 风险
测量环境：实验时机器负载很高（load average 47–140），绝对帧时间不可信；贴图版 A/B 用的是三张 NoiseTexture2D，不是 GPU 烘焙。④a 要在空闲机器上用真实 SurfaceNoise 复测，收益可能低于 0.4 ms，验收线定在 0.2 ms
共享规则修订：A5.2 的布景整屋合并和着色器预算（≤ 6）需要 ① 负责人同意。不同意的退路：布景按墙合并（seat 约多 5 次 draw）；decor 拆成 StandardMaterial3D 变体加 prop（材质净变化由 −2 变为约 0，地毯改用小尺寸最近邻贴图）
wood.gdshader 被椅子、牌桌、握把、木桶等共用：R1 之后所有木头的纹理都会轻微变化。对策：保持 uniform 语义和默认值，在 ① 版 shader 上改；④a 用截图对比检查；④a 可以单独先发
8 位噪声的量化：阈值类图案（酒渍、露砖）的边缘在放大时呈分段直线。规则是凹凸只取解析形状；④a 目视调整阈值宽度
图集用 SystemFont 画中文：Windows 上可能缺字。对策：复用 UiTheme 的字体回退列表，画之前用 has_char 检查，缺字就改用拉丁文本；在 Windows 导出包上验证
启动顺序：噪声和图集要等几帧才就绪，在那之前墙面是平的。tools/shot.gd、perf_probe 和 showcase 必须先构建并 refresh，否则截图和测量会失真
依赖接口：① 的 MeshForge 若缺 part_space_xf、uv_rect、uv2、quad(curl)、loft 斜接，由 ④ 补，要先和 ①② 的实现对齐 API；② 的配方 kind 若与 DecorPainter 的画法表不同步，会走回退画法（测试会告警）
壁炉加宽（外框 1.98→2.24 m）改变了菜单环绕的净空：最近处是 x −0.55 的烛台，0.48 m，由净空测试兜底
LAYER_WORLD 投影物增多（台梁、柴、台身、吧凳、木桶、货箱）：壁炉 omni 仍是立方体阴影，约 +10–15 次阴影 draw，在预算内；超了就把吧凳和货箱挪到 LAYER_SCENERY
启动时间：网格加图集可能略超 60 ms。退路是把共享件挪进 ① 的工作线程预建；和 ②③ 共同分配全局 +200 ms
窗外的体积雾被月光照亮，可能冲淡外景板。外景板在 x 5.4，比现在缩短了窗外雾的积分长度，影响会变小；仍需调外景板自发光和月光雾能量
陈设变多可能削弱 seat 视角的可读性：墙饰一律在 y ≥ 1.35，有头部剪影测试；地毯控制反照率和图案尺度；最后人工签收
钟摆随 _process 摆动，截图之间会有差异：shot_diff 对比时把钟摆区域排除，或在截图时暂停钟摆
贴花投到 ② 的腿脚上：腿脚在层 1，贴花 cull_mask 只含 LAYER_SCENERY，投不上去
