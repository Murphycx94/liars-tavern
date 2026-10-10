# 炸弹猫(第三种玩法)设计(2026-10-09 用户追加)

> 用户原话:「再加一个炸弹猫的游戏,不用问我,直接给我写好,然后发包,我明天来验收」。
> 设计由协调者按惯例直接定;玩法机制参照「摸到炸弹就出局、最后活着的人赢」这一类派对卡牌游戏,
> **卡名、卡面、文案全部原创**(不使用任何商业游戏的卡名、插画、商标文字),画风沿用本作的动森式温馨卡通。

## 1. 玩法规则

### 1.1 概要
- 2–6 人。牌堆里藏着若干张**炸弹**,轮流行动,每回合最后摸一张牌;摸到炸弹又没有**拆弹**就炸飞出局。最后活着的人赢。
- 每回合:可以先打出任意张功能牌(0 张也行),最后从牌堆顶摸 1 张结束回合;某些牌能让你不摸牌就结束回合。
- 没有分数、没有多局:一局分出胜负就结算,回到等待厅可以再来。不支持中途加入(和骗子酒馆一样)。

### 1.2 牌(原创命名;数量按人数配,见 1.4)

| id | 名字 | 作用 |
|---|---|---|
| `bomb` | 炸弹 | 摸到时:有「拆弹」必须拆(自动打出),然后把炸弹**秘密**塞回牌堆任意位置;没有就爆炸出局。不能主动打出 |
| `defuse` | 拆弹 | 只在摸到炸弹时使用。开局每人发 1 张 |
| `skip` | 溜了 | 结束本回合且不摸牌(被「甩锅」时只抵掉 1 个回合) |
| `pass_turns` | 甩锅 | 结束本回合且不摸牌,下家要连续行动 2 个回合;若你本身在还「被甩」的回合里,剩余回合数 + 2 一起甩给下家 |
| `peek` | 偷看 | 私下看牌堆顶 3 张(只有自己看到) |
| `shuffle` | 洗牌 | 把牌堆洗乱 |
| `beg` | 讨要 | 选一位玩家,他从手牌里**自己挑**一张给你 |
| `nope` | 不行! | 任何时候打出,取消别人(或自己)刚打出的一张功能牌或一组对子;可以「不行」掉「不行」。不能取消炸弹和拆弹 |
| `snack_*` | 零食牌(5 种:鱼干 `snack_fish`、毛线球 `snack_yarn`、胡萝卜 `snack_carrot`、香蕉 `snack_banana`、仙人掌 `snack_cactus`) | 单张没用;**两张同样的**一起打出:从选定的玩家手里随机抽 1 张;**三张同样的**:点名一种牌,对方有就必须给你 |

### 1.3 回合流程与「不行!」窗口
- 当前玩家打出功能牌(或零食组合)后,进入**反应窗口**(`REACT_WINDOW` = 3.0 秒):所有还活着的玩家(包括打出者)都可以打「不行!」。
  - 每打出一张「不行!」窗口重新计时;窗口结束时,按「不行!」张数的奇偶决定原牌生效或作废。
  - 窗口期间当前玩家不能再出别的牌、不能摸牌;窗口内房主的回合计时暂停,窗口结束后恢复剩余时间。
- 摸牌不需要窗口。摸到炸弹:有拆弹 → 自动拆弹,进入**塞回**步骤(当前玩家选择位置 0..牌堆张数,0 = 顶,`REINSERT_TIMEOUT` = 15 秒,超时随机);没有拆弹 → 爆炸出局。
- 出局的人的手牌全部弃掉,炸弹本身移出游戏(不再塞回);他变成观战者。
- 回合计时:沿用 `Protocol.TURN_TIMEOUT`;超时代打 = 直接摸牌(若在塞回步骤则随机位置;若在「讨要」等待给牌的一方超时,则随机给一张)。
- 「讨要」:目标玩家要在 `GIVE_TIMEOUT` = 15 秒内选一张给出,超时随机给;期间其他人都在等。
- 断线:等同出局(手牌弃掉,不触发爆炸动画以外的东西)。

### 1.4 配牌(按人数 n)
- 先从牌库里拿掉炸弹和拆弹,洗匀,每人发 4 张,再每人发 1 张拆弹(手牌 5 张;2026-10-10 由 7+1 减为 4+1)。
- 剩余的拆弹放回牌堆:总拆弹数 = n + 2(n ≥ 5 时 n + 1),放回 = 总数 − n。
- 炸弹数 = n − 1,混入牌堆后洗匀。
- 功能牌数量(不含炸弹和拆弹):

  | 牌 | 2–3 人 | 4–5 人 | 6 人 |
  |---|---|---|---|
  | 溜了 | 3 | 4 | 5 |
  | 甩锅 | 2 | 3 | 4 |
  | 偷看 | 3 | 4 | 5 |
  | 洗牌 | 2 | 3 | 4 |
  | 讨要 | 2 | 3 | 3 |
  | 不行! | 3 | 4 | 5 |
  | 每种零食 | 3 | 3 | 4 |

  (2026-10-10 用户觉得牌太多,整体减量约四分之一:3 人局 48 → 37 张,6 人局 69 → 58 张。)

- 规则引擎里把这张表写成常量,测试覆盖每种人数下的总张数与开局手牌。

## 2. 架构(沿用现有分层)

- `src/core/bomb_cat/`:纯规则引擎,不依赖网络和场景。
  - `bomb_cat_card.gd`:牌 id 常量、显示名、可否主动打出、是否零食。
  - `bomb_cat_deck.gd`:按人数配牌、洗牌(传入 RandomNumberGenerator,可复现)。
  - `bomb_cat_state.gd`:局面(牌堆、弃牌、手牌、存活、当前玩家、待行动回合数、反应窗口、待塞回、待给牌、胜者),
    以及 `play(pid, cards, target?, named?)`、`nope(pid, card_index)`、`draw(pid)`、`reinsert(pid, pos)`、`give(pid, card_index)`、
    `resolve_window()`、`timeout()`、`eliminate(pid)`;每个方法返回 `{"ok", "error"?, "events": [...]}`。
  - 事件(广播给全员的公共事件,**不含任何隐藏信息**):
    - `round_started`:开局,含座次、每人手牌张数、牌堆张数。
    - `played`:pid、cards(公开)、target、window_until。
    - `noped`:pid、depth。
    - `window_resolved`:effective。
    - `effect`:kind、具体结果(公开部分,如讨要「谁给了谁一张牌」,但不含是哪张)。
    - `drew`:pid、牌堆剩余张数;不含是哪张,炸弹除外。
    - `bomb_drawn`:pid。
    - `defused`:pid。
    - `reinserted`:pid;不含位置。
    - `exploded`:pid。
    - `turn_passed`:下一个 pid、待行动回合数。
    - `match_over`:winner。
  - 私有信息走私有视图:自己的手牌、自己刚摸到的那张牌(`last_drawn`)、偷看结果(`peek`,只给打出者)、
    塞回时的牌堆张数(选位置用)、给牌请求。
- `src/net/bomb_cat_session.gd`(extends GameSession):包装状态机。
  - 意图字典:
    - `{"kind": "play", "cards": [手牌下标...], "target": pid?, "named": 牌id?}`
    - `{"kind": "nope"}`
    - `{"kind": "draw"}`
    - `{"kind": "reinsert", "pos": int}`
    - `{"kind": "give", "index": int}`
  - 所有字段按不可信输入校验(类型、范围、是否轮到他、是否在窗口里等)。
  - 反应窗口、塞回、给牌这三种等待:用 `has_turn()` + `turn_timer_after()` 给出对应时长,让 NetworkManager 现有的回合计时器
    到点时调 `on_turn_timeout()` 去结算窗口或代打。不新增计时器;窗口暂停回合计时的语义在会话里自己记剩余时间。
  - `estimate(events)` 给演出时长(参考 Pacing / PokerPacing)。
- `GameMode` 加 `BOMB_CAT := "bomb_cat"`,label「炸弹猫」,2–6 人,不允许中途加入。
  - `ALL` 的顺序决定主菜单玩法切换的按钮顺序:骗子酒馆、炸弹猫、德州长牌、德州短牌,或放在最后。
  - 按主菜单 mode_picker 的版面决定;四段放不下就改成两行或下拉,版面要好看。
- NetworkManager:
  - 开局时按玩法建会话:`BombCatSession`。
  - 客户端意图:新 RPC `rpc_bomb_cat_intent(intent: Dictionary)`(reliable,房主校验发送者在座位里),
    或把现有意图入口泛化成按玩法分发,二选一,保持 NetworkManager 的 RPC 表可测(更新 `test_net_rpc_order`)。
  - 协议号仍为 5(0.7.0 未发布,三个玩法一起发)。不改 `project.godot`。

## 3. 表现

### 3.1 牌桌与 3D
- 用骗子酒馆大小的桌子:≤4 人时用现在的桌;5–6 人时用 `SeatLayout` 现有的更大半径,参考德州的 `set_table_radius`。
  - 不摆目标牌立牌。烛台照常(德州那套 `set_table_decor_visible` 的逻辑可复用)。
  - 座位分布与德州 8 人桌的取法一致。
- 桌心:**牌堆**(厚厚一摞牌背朝上,张数变化时高度跟着变,用一个按张数缩放的盒子 + 顶面一张牌就够,不要 50 个网格)
  和**弃牌堆**(最上面一张正面朝上,稍乱地叠几张)。
- 卡面:程序绘制,参考 `CardFaces` / `PokerFacePainter` 的 SubViewport 烘焙做法。
  - 原创插画、动森式明快配色,每种牌一个大图标 + 名字 + 一行小字说明。
  - 牌背:深红底 + 金色导火索圆章。
  - 卡面用 Texture2DArray,所有牌共用一份材质(card.gdshader v2 已支持 faces 数组)。
- 手牌:
  - 别人:酒客手里举着牌扇,张数随手牌变化。超过 10 张时扇面压缩,不加网格。
  - 自己:
    - 越肩视角下用 3D 牌扇;第一人称用 `present_hand_first_person` 那一套。
    - 同时屏幕底部有一条 2D 手牌条,可点选、可多选零食组合;参考德州的 `CardStrip`。2D 条是操作主入口,3D 扇是看着好看。
- 动作演出(Director,参考 TableDirector / PokerDirector):
  - **出牌**:牌从出牌人手里飞到弃牌堆、翻面,出牌人头顶冒「甩锅!」「偷看」这类气泡。
  - **不行!**:打出者拍桌,一张牌「啪」地盖在弃牌堆上,头顶大字「不行!」。
  - **偷看**:只有自己看到 3 张牌浮到眼前(私有),别人只看到他捂嘴偷看的小动作。
  - **洗牌**:牌堆抖一抖、哗哗声。
  - **摸牌**:牌从牌堆滑到手里。
  - **摸到炸弹**:
    - 所有人吓一跳。
    - 炸弹牌翻开,导火索冒火花(粒子),短暂的心跳声和镜头推近。
    - 有拆弹:酒客手忙脚乱剪线(手部动作 + 冒汗),「咔嚓」,松一口气。
    - 没拆弹:**轰**:闪光、烟团(复用枪口火光与烟的那套 fx)、镜头震动。酒客被炸得脸上一片黑灰(patron shader 的一个 instance 参数或一块贴片)、
      头顶冒烟、蚊香眼 → ×眼加星星(复用 PatronAntics 的出局表演),帽子飞走。
  - **讨要 / 抽牌**:一张牌从一人手里飞到另一人手里(牌背朝外,只有当事人看得到正面)。
  - **胜利**:沿用 celebrate 与结算环绕镜头。
- 音效:程序合成,加进 Sfx。包括导火索嘶嘶声、爆炸(比枪声更闷更大)、剪线咔嚓、「不行!」拍桌、洗牌。

### 3.2 界面(HUD)
- 左上:本局信息,包括牌堆剩余张数、场上剩余炸弹数(公开信息:开局炸弹数 − 已爆炸数)、当前玩家与他还要行动几个回合。
- 底部:
  - 自己的 2D 手牌条。
  - 按钮:「出牌」(选中合法组合时可按)、「摸牌」(结束回合);
    选目标的牌(讨要、零食组合)出牌后在 3D 场景里点一位酒客,或用浮出的玩家名单选。
  - 「不行!」大按钮:手里有「不行!」并且在反应窗口里时亮起,快捷键 N;窗口倒计时条。
  - 塞回炸弹:弹出一个滑块(0 = 顶 … 底),显示「放在第 k 张」,确认或超时随机。
  - 给牌:被讨要时弹出提示「XX 向你讨要一张牌」,点自己的一张牌给出。
- 快捷键(不冲突:T、Q、V、WASD、Esc、F1 已占):
  - 1–9:选第几张手牌。
  - 回车:出牌。
  - 空格或 D:摸牌。
  - N:不行!
  - Q 面板打开时数字键归面板(BanterView 已处理)。
- 说明书:新增「炸弹猫」一页(参考 `rulebook_poker.gd`),写清规则、每张牌、快捷键;主菜单玩法按钮的提示用 `GameMode.summary`。
- 出局者:变观战,镜头用观战机位;仍能丢番茄、说快捷语。
- 结算:沿用现有结算界面风格,显示名次(按出局顺序倒排)。

### 3.3 与已有功能的配合
- 丢番茄、快捷语、V 切换视角在炸弹猫里都要能用(BanterView 是全局层;V 用共享的 `SeatCamera`)。
- 自选形象、名牌、眼神同步照常。
- 第一人称下自己的牌扇和 2D 手牌条都不挡关键信息。

## 4. 机器人与冒烟

- `debug_flags.gd` 的机器人支持炸弹猫:能出牌(随机合法)、偶尔「不行!」、摸牌、塞回、给牌,一局能自动打完。
- `tools/lan_smoke.sh` 增加炸弹猫一局:3 端打到 MATCH_OVER,核对胜者一致;原有骗子酒馆冒烟不变。
- 展台:`tools/shot.gd` 支持 `--bomb-cat-showcase`,机位 `bomb_seat`、`bomb_overview`、`bomb_fp`;可摆出「反应窗口」「摸到炸弹」「爆炸后」几个状态。

## 5. 测试

- 规则引擎:
  - 配牌(每种人数的总数与手牌)。
  - 每张牌的效果。
  - 甩锅叠加(含被甩时再甩)、溜了抵一个回合。
  - 「不行!」奇偶与可以不行掉不行、窗口重开计时。
  - 炸弹:拆弹与塞回位置(0 和底)、没拆弹出局、炸弹移出游戏。
  - 零食:两张抽一张、三张点名有或没有。
  - 讨要:给牌与超时。
  - 出局后跳过他;只剩 1 人胜利。
  - 断线出局;超时代打。
  - 隐藏信息不进公共事件(断言公共事件里没有手牌内容和牌堆顺序)。
- 会话与网络:非法意图(不是你的回合、窗口外打不行、下标越界、目标是死人或自己、类型不对)全部拒绝;合法意图事件广播一致;计时器在窗口、塞回、给牌时的时长正确。
- 界面:快捷键映射;Q 面板开着时数字键不选牌;手牌条多选合法性提示。
- 预算:炸弹猫 6 人桌 seat 视角 draw call ≤ 700(`tools/perf_probe.gd` 加 bomb 视角);`test_scene_budget` 照过。

## 6. 约束

- 不改 `project.godot`;协议号 5;不在 `src/` 运行时读网格数组;不 duplicate ShaderMaterial;新静态缓存在 `main.gd` `_exit_tree` 释放。
- 卡名、卡面、文案原创;不出现任何商业游戏名称或商标。
- 骗子酒馆和德州的行为零变化(全量测试与冒烟照过)。

## 7. 实施记录(阶段一:规则引擎 + 房主会话 + 网络 + 玩法登记,2026-10-09)

阶段一不含任何表现(牌桌屏幕、HUD、3D、导演、说明书、机器人、冒烟);阶段二在下面这些接口上搭。
本节是阶段二的接口契约:事件、视图、意图的字段**只增不改**。

### 7.1 文件

- 规则引擎(纯逻辑,不依赖网络与场景):
  - `src/core/bomb_cat/bomb_cat_card.gd`(class `BombCatCard`):牌 id 常量(字符串)、`ALL`(画卡面与说明书的顺序)、`SNACKS`、`ACTIONS`;
    `display_name(id)`、`description(id)`(一行原创说明)、`is_snack`、`is_playable`(自己回合可单张打出)、`needs_target`、`can_be_named`。
  - `src/core/bomb_cat/bomb_cat_deck.gd`(class `BombCatDeck`):§1.4 的配牌表写成常量 `ACTION_COUNTS` / `SNACK_COUNT`;
    `action_counts(n)`、`defuse_total(n)`、`bomb_count(n)`、`total_cards(n)`、`deal(pids, rng)`(7 张 + 1 张拆弹,剩余拆弹与炸弹混回再洗)、
    `shuffle(cards, rng)`(就地 Fisher-Yates,同种子可复现)。`MIN_PLAYERS` 2、`MAX_PLAYERS` 6。
  - `src/core/bomb_cat/bomb_cat_state.gd`(class `BombCatState`):完整状态机。**文件头的注释就是事件字典的权威说明**。
- 会话与网络:
  - `src/net/bomb_cat_session.gd`(class `BombCatSession` extends `GameSession`):意图校验与分派、计时语义、视图。`state()` 给测试与机器人只读访问引擎。
  - `src/net/bomb_cat_views.gd`(class `BombCatViews`):公共 / 私有视图。
  - `src/net/bomb_cat_pacing.gd`(class `BombCatPacing`):演出预算。
  - `src/net/network_manager.gd`:`_new_session(mode)` 按玩法建会话;新 RPC `rpc_session_intent(intent)` 与 `submit_session_intent(intent)`。
- 测试(全部无头):`test_bomb_cat_deck` / `test_bomb_cat_state` / `test_bomb_cat_session` / `test_net_bomb_cat` / `test_bomb_cat_fuzz`,
  共用 `tests/bomb_cat_helpers.gd`(摆局面 `rig`、公共事件 / 视图的漏信息检查器 `event_leak` / `view_leak`)。
  自对弈:300 局固定种子(2–6 人随机),随机合法意图 + 随机超时 + 偶尔断线 + 夹杂的垃圾意图,约 2.2 万步;
  每步查牌数守恒、公共事件与视图不漏信息、私有视图与引擎一致、偷看属实、场上炸弹 ≥ 存活 − 1、计时时长为正,
  每局必须结束且恰好一个胜者;并断言每种事件与每种 effect 都走到过。

### 7.2 规则落地时定下的细节

- 状态机步骤 `step`:`turn`(当前玩家自由行动)· `window`(反应窗口)· `reinsert`(拆弹后塞回)· `give`(被讨要的人挑牌)· `over`。
- 先手由房主 RNG 随机挑。`turns_left` 含正在进行的这一回合(平时 1)。摸牌、溜了、塞回完成各消耗 1 个;
  用完轮到下一位存活者(1 回合,不算被甩)。
- **甩锅**:当前玩家剩余回合作废;下家行动 2 回合。若当前玩家本身在「被甩」的回合里(`under_attack`,被甩来的回合用完之前一直为真),
  下家行动 `turns_left + 2`。例:被甩 2 回合时第一回合就甩 → 下家 4;先摸一张(剩 1)再甩 → 下家 3。溜了在被甩时只抵 1 回合。
- **不行!**:只在反应窗口里打;任何存活玩家都能打,包括出牌者自己(可以不行掉别人对自己的不行);每张都让窗口重新计时。
  窗口结算时张数为偶数则原牌生效。牌(含被取消的)都留在弃牌堆。不行! 不能在自由行动时单独打出。
- 只有零食能组合:2 张同种零食 = 对子(`pair`,随机抽 1 张),3 张同种零食 = 三条(`triple`,点名一种牌;对方有就给他手里第一张)。
  点名可以是除炸弹外的任何牌 id。讨要 / 对子 / 三条的目标必须是在场、不是自己、**出牌时手里有牌**的人;
  窗口期间目标出局或把牌打光则落空(`got: false`)。
- 讨要生效进入 `give` 步骤,目标自己挑一张(`give` 意图);讨要者和其他人都在等。
- 摸到炸弹:有拆弹自动打出(进弃牌堆顶),炸弹拿在手上(`held_bomb`)进入 `reinsert`;塞回位置 `0..牌堆张数`(0 = 顶,牌堆张数 = 底)。
  塞回完成才算这一回合结束(被甩时继续自己的下一回合)。没有拆弹:炸飞,炸弹移出游戏(`removed`),手牌全部弃掉。
- 出局者的手牌垫到弃牌堆**最底下**,`discard_top` 只记公开打出的牌(出牌、不行!、拆弹),所以弃牌堆顶永远不会露出出局者的手牌。
- 断线 = 出局(`player_left`,没有爆炸)。他卡着的步骤先收尾:自己的窗口作废(`window_resolved.aborted`)、
  塞回中的炸弹随机塞回(`reinserted`)、讨要落空(`effect beg got:false`,不论他是给牌的还是讨要的)。断线不移除炸弹,
  所以「场上炸弹 ≥ 存活人数 − 1」始终成立,自由行动时牌堆不会空(引擎仍有兜底:空牌堆摸牌 = 直接结束回合)。
- 牌数守恒:`deck + discard + 各手牌 + removed + held_bomb = total_cards`(`card_count()`)。
- 名次:第 1 名是胜者,其后按出局顺序倒排(最后出局的第 2)。

### 7.3 公共事件(广播全员,不含任何隐藏信息)

所有事件有 `type`。带牌 id 的只有 `played.cards`、各 `kind` 字段与 `effect.named`(都是本来就公开的)。

| type | 字段 | 说明 |
|---|---|---|
| `round_started` | `seats: [pid]`, `hands: [{pid, count}]`, `deck_count`, `bombs`, `current`, `turns` | 开局(唯一一次)。`bombs` = 炸弹总数 n − 1 |
| `played` | `pid`, `cards: [牌 id]`, `kind`, `target: pid 或 null`, `named: 牌 id 或 ""`, `window: 秒` | 打出并打开窗口。`kind` ∈ `skip` `pass_turns` `peek` `shuffle` `beg` `pair` `triple` |
| `noped` | `pid`, `depth`, `window: 秒` | 本窗口第 `depth` 张不行!,窗口重新计时 |
| `window_resolved` | `pid`, `kind`, `effective`, `nopes`, `aborted` | `pid` / `kind` 是原出牌;`aborted` = 出牌者断线 |
| `effect` | `kind`, `pid`(出牌者)+ 按 kind 见下 | 原牌生效的公开结果 |
| `give_requested` | `pid`(要给牌的人), `to`(讨要者), `timeout: 秒` | 进入 `give` 步骤 |
| `drew` | `pid`, `deck_count`, `bomb: bool` | 不含是哪张;`bomb` 为真时紧跟 `bomb_drawn` |
| `bomb_drawn` | `pid` | |
| `defused` | `pid`, `deck_count`, `timeout: 秒` | 进入 `reinsert` 步骤,可选位置 `0..deck_count` |
| `reinserted` | `pid`, `deck_count` | 不含位置 |
| `exploded` | `pid`, `discarded` | 炸飞出局,弃掉 `discarded` 张手牌 |
| `player_left` | `pid`, `discarded` | 断线出局 |
| `turn_passed` | `pid`, `turns` | 轮到 `pid`,要行动 `turns` 回合;同一人连走下一回合也发 |
| `match_over` | `winner`, `ranking: [pid]` | |

`effect` 按 `kind`:`skip {pid}` · `pass_turns {pid, to, turns}` · `peek {pid, count}` · `shuffle {pid}` ·
`beg {pid, from, to, got}`(给牌结束或落空)· `steal {pid, from, to, got}`(对子)· `request {pid, from, to, named, got}`(三条)。

典型批次(一个意图 / 一次超时 / 一次断线 = 一批):
出牌 `[played]` → 窗口到点 `[window_resolved, effect…, turn_passed?]` 或 `[window_resolved, give_requested]` →
给牌 `[effect beg]`;摸牌 `[drew, turn_passed]` / `[drew, bomb_drawn, defused]` → `[reinserted, turn_passed]` /
`[drew, bomb_drawn, exploded, turn_passed 或 match_over]`。

### 7.4 公共视图(`rpc_state_public`,每批之后)

```
{
  "mode": "bomb_cat", "step": "turn" | "window" | "reinsert" | "give" | "over",
  "current_pid": pid 或 null, "turns": int,
  "deck_count": int, "discard_count": int, "discard_top": 牌 id 或 "",
  "bombs_left": int, "bombs_total": int,          # 场上剩余炸弹 = 总数 − 已炸飞(公开信息)
  "window": {} 或 {"pid", "cards", "kind", "target", "named", "nopes"},
  "give": {} 或 {"from", "to"},
  "reinsert": {} 或 {"pid"},
  "players": [{"pid", "name", "alive", "hand_count"}],   # 座位顺序
  "out_order": [pid], "winner": pid 或 null,
  "ranking": [] 或 [{"pid", "name", "place"}],            # 只在 over 时有
  "turn_time_left": float,      # 房主计时器剩余(当前步骤的:回合 / 窗口 / 塞回 / 给牌),含要先播完的演出;over 时 0
  "paused_turn_left": float     # window / give 期间暂停保存的回合剩余,其他时候 0
}
```

### 7.5 私有视图(`rpc_state_private`,每批之后发给每个座位,含出局者)

```
{
  "hand": [牌 id],                               # 自己的手牌(顺序 = 意图里的下标;新牌追加在末尾)
  "alive": bool,
  "last_drawn": 牌 id 或 "", "draw_seq": int,     # 自己最近摸到的那张(炸弹也算);seq 变了 = 新摸的
  "peek": [牌 id], "peek_seq": int,              # 偷看结果(顶 → 下),只给打出者;牌堆一变(摸牌 / 洗牌 / 塞回)就清空
  "reinsert": {} 或 {"deck_count": int},         # 轮到自己塞回时
  "give": {} 或 {"to": pid},                     # 自己被讨要、要挑一张时
  "transfer": {} 或 {"card", "from", "to", "seq"}  # 最近一次涉及自己的转手(讨要 / 对子 / 三条),双方都看得到是哪张
}
```

各种 `seq` 共用一个递增计数,界面据此判断「这是新的一次」(同一份私有视图每批都会重发)。

### 7.6 意图与错误码

客户端:`Net.submit_session_intent(intent)`(房主本机直接处理;客人发 `rpc_session_intent`)。
房主校验顺序:发送者在名单里(否则 `not_seated`)→ 本房是炸弹猫(否则 `invalid_intent`)→
`BombCatSession.check_intent`(字典、≤ 4 个键、kind 认识、字段类型)→ 引擎规则。被拒走现有的 `intent_rejected(code)`。

| 意图 | 字段 | 谁、何时 |
|---|---|---|
| `{"kind": "play", "cards": [下标…], "target"?: pid, "named"?: 牌 id}` | 1–3 个互不相同的手牌下标 | 当前玩家,`turn` 步骤 |
| `{"kind": "nope"}` | 打出手里第一张不行! | 任何存活玩家,`window` 步骤 |
| `{"kind": "draw"}` | | 当前玩家,`turn` 步骤 |
| `{"kind": "reinsert", "pos": int}` | `0..deck_count` | 当前玩家,`reinsert` 步骤 |
| `{"kind": "give", "index": int}` | 手牌下标 | 被讨要的人,`give` 步骤 |

错误码(`BombCatState.ERR_*`,中文提示在 `BombCatState.ERROR_MESSAGES`,阶段二的牌桌屏幕 toast 用它):
`match_over` 对局已结束 · `not_seated` 不在这一局 · `out` 已出局 · `not_your_turn` · `busy`(当前玩家在窗口 / 塞回 / 给牌期间想出牌或摸牌)·
`invalid_play`(下标或组合不对)· `invalid_target` · `target_empty` · `invalid_named` · `no_window`(窗口外打不行)· `no_nope` ·
`not_waiting`(不是在等你塞回 / 给牌)· `invalid_pos` · `invalid_index` · `invalid_intent`(结构不对或不是炸弹猫房间)。

`turn_action`(行动者那端的演出欠账清零):出牌、摸牌、塞回、给牌、超时代打为真;**不行! 为假**——谁都能打,
窗口要从排队演出播完算起。

### 7.7 计时语义(沿用 NetworkManager 唯一的回合计时器,不新增计时器)

`has_turn()` 在没结束时恒为真(总有人在计时)。`turn_timer_after(events, pending, time_left)` 按本批之后的步骤给时长
(`pending` = 含本批在内客户端还要演多久,所以都从演出播完算起):

| 本批之后 | 时长 |
|---|---|
| `turn`,本批有 `turn_passed` / `round_started` | `pending + TURN_TIMEOUT`(30 秒) |
| `window`,本批有 `played` | `pending + REACT_WINDOW`(3 秒);同时把出牌那一刻的回合剩余存进 `paused_turn_left` |
| `window`,本批有 `noped` | `pending + REACT_WINDOW`(重新计) |
| `reinsert` 刚进入 | `pending + REINSERT_TIMEOUT`(15 秒) |
| `give` 刚进入 | `pending + GIVE_TIMEOUT`(15 秒) |
| 从 `window` / `give` 回到 `turn`(没换人) | `pending + max(暂停的剩余, RESUME_MIN = 3 秒)` |
| 其他(旁人断线等,步骤没变) | `time_left + 本批演出`(计时器没在走时给满) |

到点 `on_turn_timeout()`:`window` → 结算窗口;`reinsert` → 随机位置;`give` → 随机给一张;`turn` → 直接摸牌。

`BombCatPacing` 的预算是按 §3.1 的演出先估的(出牌 0.8、不行 0.7、偷看 1.2、洗牌 1.0、转手 0.9、摸牌 0.6、
炸弹翻开 2.0、拆弹 1.6、塞回 0.8、爆炸 3.5、结算 3.0 …),导演实测后可以收紧;导演每段演出不得超过预算。

### 7.8 GameMode 与其他按玩法分支的地方

- `GameMode.BOMB_CAT = "bomb_cat"`,label / short_label「炸弹猫」,2–6 人(`BOMB_CAT_MAX_PLAYERS`,测试核对等于 `BombCatDeck.MAX_PLAYERS`),
  `allows_late_join` 为假,`is_bomb_cat(mode)`。
- `ALL = [LIARS, BOMB_CAT, HOLDEM, SHORT_DECK]`:主菜单按钮顺序骗子酒馆、炸弹猫、德州·长牌、德州·短牌。
- `BOMB_CAT_ENABLED := true` 与 `menu_modes()`:**只管主菜单开房能不能选**;id 照样合法(认得别人开的房间、网络与测试照常)。
  阶段二按时完成就一直是 true;万一发版时牌桌没就绪,改成 false 即可从开房菜单藏起来(上次选的是炸弹猫时菜单回退默认玩法)。
- 主菜单玩法切换:四个按钮挤在「开一桌」标题行,按钮间距 10 → 6、左右内边距 10 → 9,面板最小宽度不超过 480
  (`test_main_menu_species` 新增检查;改之前是 488)。阶段二可以再打磨。
- `SeatLayout.table_radius_for(mode, players := 0)`:炸弹猫 ≤ 4 人用骗子酒馆的桌(`TABLE_RADIUS`),≥ 5 人(`BOMB_CAT_BIG_TABLE_FROM`)
  用德州的大桌;人数未知(主菜单 / 等待厅,传 0)用小桌。**阶段二进牌桌时要按本局人数再摆一次桌**。
- `main.apply_table_mode`:炸弹猫照常摆烛台,不摆目标牌立牌(立牌只在骗子酒馆)。
- 默认房名「X 的猫窝」;等待厅人数上限、局域网发现报文的 cap、房间列表都走 `GameMode.max_players`,自动是 6(房间行写成「3/6」)。
- 说明书 `RulebookContent.book_for_mode` 对炸弹猫暂时回退骗子酒馆那本(阶段二加「炸弹猫」一本)。

### 7.9 网络

- 开局:`start_game` → `_new_session(game_mode)` → `BombCatSession`;骗子酒馆与德州不变。
- 新 RPC `rpc_session_intent(intent)`(any_peer、reliable、参数不加类型)。没有叫 `rpc_bomb_cat_intent`:Godot 按方法名排序给 RPC 编号,
  `rpc_b…` 会排到最前、挤动握手消息的编号,旧版本就收不到「版本不匹配」。`rpc_session_intent` 排在 `rpc_join_request` 之后,
  `test_rpc_order` / `test_net_rpc_order` 照过(后者的 v5 列表加了它)。这个入口在骗子酒馆与德州房间里一律拒绝(`invalid_intent`),那两个玩法仍走各自的 RPC。
- 协议号仍为 5;`project.godot` 没动。
- 每批之后 `_sync_all` 照旧:公共视图全员、私有视图发给 `viewers()`(全座位),偷看结果、塞回、给牌请求、转手都在私有视图里随批下发。

### 7.10 临时路由(阶段二要替换)

`main._show_table`:炸弹猫房间暂时进 `_bomb_cat_placeholder()`——居中一块「炸弹猫的牌桌还在布置中」+「离开房间」按钮,不会崩。
规则与网络照常跑,每步到点由房主代打,一局会自己打完,但没有结算界面。阶段二把这一分支换成 `BombCatScreen.new(self)` 并删掉占位函数
(代码里有 `TODO(炸弹猫阶段二)`)。

### 7.11 阶段二要做的

1. 牌桌屏幕 `BombCatScreen`:接 `Net.game_events` / `state_public_updated` / `state_private_updated` / `intent_rejected`,
   出手一律 `Net.submit_session_intent(...)`;替换 `main._show_table` 的占位分支;进牌桌时按本局人数 `SeatLayout.table_radius_for(mode, 人数)` 摆桌。
2. 导演:按 7.3 的事件演出,每段时长不超过 `BombCatPacing` 的预算(参照 `test_poker_director_pacing` 加检查)。
3. HUD:`step` / `turn_time_left` / `paused_turn_left` / `window.nopes` / `bombs_left` / `turns` 都在公共视图里;
   不行! 按钮亮起条件 = `step == "window"`、自己活着且手里有 `nope`;塞回滑块范围 = 私有视图 `reinsert.deck_count`;给牌提示看私有视图 `give`。
4. 说明书「炸弹猫」一本(牌名与一行说明取 `BombCatCard.display_name` / `description`,数量取 `BombCatDeck.action_counts`)。
5. 机器人(`debug_flags.gd`)与 `tools/lan_smoke.sh` 的炸弹猫一局;`tools/shot.gd` 展台。可以直接复用 `tests/test_bomb_cat_fuzz.gd` 里挑合法意图的写法。

## 8. 实施记录(阶段二:牌桌、HUD、导演、3D、牌面、音效、说明书、机器人、冒烟与展台,2026-10-09)

阶段一的事件 / 视图 / 意图字段一个没改,阶段二全部搭在 §7 的接口上;规则引擎没有改动(没发现引擎的 bug)。

### 8.1 文件

- 牌桌(`src/ui/bomb_cat/`):
  - `bomb_cat_screen.gd`(不声明 class_name,同德州牌桌,由 main 预载):接 `game_events` / 视图 / `intent_rejected`(toast `BombCatState.ERROR_MESSAGES`);
    进牌桌先 `apply_table_mode` 再按 `SeatLayout.table_radius_for(mode, 人数)` 摆桌(5–6 人大桌);事件排队交给导演,演完用视图对账。
    出手入口(按钮、快捷键、机器人共用):`toggle_card` / `submit_play` / `choose_target` / `choose_named` / `submit_draw` / `submit_nope` /
    `submit_reinsert` / `submit_give`;`intent_sink` 是测试钩子(不走 Net,直接交给本地会话)。
  - `bomb_cat_screen_state.gd`(`BombCatScreenState`):视图 + 按事件推进的影子行(张数、存活、牌堆、炸弹、当前玩家与回合数、步骤、窗口、最近的弃牌),
    屏幕上的自己的手牌 `shown_hand`(出牌按提交的下标拿走、摸到 / 拿到的牌等私有视图到了再追加,演完以私有视图为准),出手规则与结算名次。
  - `bomb_cat_hud.gd`(`BombCatHud`)、`bomb_cat_hand_strip.gd`(`BombCatHandStrip`,2D 手牌条)、`bomb_cat_nameplate.gd`、
    `bomb_cat_settlement.gd`(版式照搬骗子酒馆的 `Settlement`,但只发 `lobby_pressed` / `leave_pressed` 信号、不直接调 Net,截图展台也能用)、
    `bomb_cat_director.gd`(`BombCatDirector`)、`bomb_cat_bot.gd`(`BombCatBot`)。
- 3D 与牌面(`src/world/bomb_cat/`):`bomb_cat_faces.gd`(`BombCatFaces`:14 层数组纹理 + 烫金遮罩 + 一份共享 `ShaderMaterial` + 牌堆侧面材质)、
  `bomb_cat_face_painter.gd`、`bomb_card_3d.gd`(`BombCard3D extends Card3D`)、`bomb_cat_layout.gd`(纯函数)、`bomb_cat_cards.gd`(`BombCatCards`,挂在 `TableWorld.poker_root` 下)。
- 共用件的增补(骗子酒馆 / 德州行为不变):`Fx.fuse_sparks / explosion / head_smoke`;`patron.gdshader` 新实例参数 `soot`(默认 0);
  `Patron.cover_mouth / snip_wires / set_soot`;`PatronAntics.sweat / giggle`;`Sfx` 的 `fuse` `boom` `snip` `nope_slap` `riffle`;
  说明书 `RulebookBombCat` 与块类型 `bomb_cards`;`main` 的 `_exit_tree` 加 `BombCatFaces.clear()`;等待厅选了炸弹猫就后台生成牌面。
- 工具:`tools/bomb_cat_showcase.gd`、`tools/shot.gd --bomb-cat-showcase`、`tools/perf_probe.gd --showcase=bomb_cat`、`tools/perf_budget.gd` 的 bomb_* 机位、
  `tools/bomb_cat_faces_sheet.gd`(牌面验收图)、`tools/lan_smoke.sh` 的炸弹猫一局、`DebugFlags --mode=`。

### 8.2 表现上定下的细节

- 牌桌布局(本机座位在 +Z):牌堆在桌心左、弃牌堆在右,桌上的牌放大 1.8 倍。牌堆 = 一块按张数缩放的纸边盒子(`BoxMesh`,三平面贴纸页线)+ 顶上一张牌背;
  弃牌堆 = 纸边盒子 + 顶上最多 5 张正面朝上、按全局序号确定性稍乱的牌(各端一致,后压上的牌不挪动前面的)。出局者的手牌飞进弃牌堆底(看不到是哪张)。
- 卡面 320×462(与 Card3D 同比例),层序 `[牌背, BombCatCard.ALL…]`;card.gdshader v2 照用,所有炸弹猫的牌共用 `BombCatFaces.material()` 一份(实例参数 `face`)。
  每张牌:主色横幅 + 首字小圆章(牌扇里只露左边也认得出)+ 金边圆盘里的大图标 + 底部一行 `BombCatCard.description`。牌背:深红斜格 + 金色圆章里的「炸弹猫」剪影与火花。
- 牌扇:≤ 10 张每张间隔 4.5 cm;超过 10 张保持 10 张的总宽、挤得更近(每张仍是一张牌,不加网格);整扇最多转 36°。
  自己的牌扇:小桌按骗子酒馆的举牌位置、大桌按德州的位置,都再抬高 10–13 cm、缩小到 0.82(底部 HUD 比骗子酒馆高);第一人称拿在镜头右下方。
- 摸到炸弹:炸弹牌从牌堆顶翻起来,立在摸牌人面前偏右、牌面朝桌心,导火索冒火花(世界坐标粒子);镜头推近到 `BombCatLayout.bomb_view`(从桌心斜上方看他的脸)。
  拆弹:双手在胸前来回比划 + 冒冷汗,拆弹牌飞进弃牌堆,「咔嚓」后松一口气;塞回:炸弹翻成背面插进牌堆中间(不暴露位置)。
  爆炸:闪光 + 火核 + 四散火花 + 深浅两团烟、震屏、灯晃,`die()`(蚊香眼 → ×、星星、帽子飞走)+ `set_soot(1.0)` 黑灰脸 + 两缕头顶黑烟;自己被炸就转观战俯视。
- 偷看:自己打的偷看,三张牌浮在镜头前(挂在相机下,只在本机),同时画面上方一块小的 2D 浮层(从上到下第 1–3 张,炸弹标红)。点「知道了」、点牌、Esc,
  或牌堆一变(私有视图的 peek 清空)就收起。别人只看到他捂嘴偷乐。
- 转手(讨要 / 两张零食 / 三张零食):一张牌从一人牌扇飞到另一人牌扇;只有当事人(私有视图的 `transfer`)看到正面,其余人看到牌背。
- HUD 底部:「出牌」· 2D 手牌条 ·「摸牌」并排一行(不叠高),其上依次是回合横幅 + 环形倒计时、选目标 / 点名 / 塞回 / 给牌的临时面板、反应窗口条。
  反应窗口条:「谁打出了什么 → 谁 · 被不行几次(作废 / 又生效)」+ 倒计时条(房主剩余 / 3 秒)+ 大「不行!」按钮(活着才显示,手里有才按得动)。
  环形倒计时的满格按步骤取:回合 30 秒、窗口 3 秒、塞回 15 秒、给牌 15 秒。左上:牌堆张数、剩余炸弹(小炸弹图标)、轮到谁(被甩时写还要走几回合)、自己的手牌 / 拆弹 / 不行! 数。
- 选牌:单张功能牌只能单选;零食可以选两三张一样的;点别的牌就换成选那张。选目标:3D 里点酒客(头的屏幕投影 ≤ 140 像素)或点弹出的名单,Esc 取消;三张零食接着点名(除炸弹外 12 种)。
- 快捷键:1–9 选牌(被讨要时就是给牌)、Enter 出牌(塞回时是确认)、空格摸牌、N 不行!、←→ 微调塞回位置。**D 不用来摸牌**(它是探头键,按住会伸脖子)。
  快捷语面板开着时数字键一律归面板:BanterView 先拦 1–8,牌桌对 9 也不响应。
- 回执:任何一批事件到达都算房主处理过了,解除「等回执」;「不行!」单独记着,等自己的 `noped` 或被拒。
- 机位:常驻两种(座位越肩 / 第一人称,共用 `SeatCamera`;出局后观战俯视),特写一种(摸到炸弹),胜利环绕胜者。

### 8.3 演出预算

导演每段演出都在 `BombCatPacing` 的预算之内(`test_bomb_cat_director` 按最坏情况加上每个 await 一帧余量核对),阶段一的预算没有收紧
(收紧会让窗口 / 塞回的计时更紧,先保持;实测余量:出牌约 0.2 秒、爆炸约 0.6 秒、发牌 6 人约 0.25 秒)。

| 事件 | 实际(秒) | 预算 |
|---|---|---|
| 发牌(6 人 48 张) | 0.4 等私有手牌 + 2.25 | 3.0 |
| 出牌(三张零食) | 0.63 | 0.8 |
| 不行! | 0.44 | 0.7 |
| 偷看 | 0.95 | 1.2 |
| 洗牌 | 0.85 | 1.0 |
| 转手 | 0.65 | 0.9 |
| 摸牌 | 0.45 | 0.6 |
| 摸到炸弹 | 1.75 | 2.0 |
| 拆弹 | 1.3 | 1.6 |
| 塞回 | 0.55 | 0.8 |
| 爆炸 | 2.8 | 3.5 |
| 结算谢幕 | 2.2 | 3.0 |

### 8.4 验证

- 测试(全部无头):`test_bomb_cat_screen_state`(与真实会话逐批核对影子行)、`test_bomb_cat_screen`(快捷键、出手路径、回执、塞回范围、给牌)、
  `test_bomb_cat_hud`、`test_bomb_cat_world`(数组纹理层数、共享材质、牌扇压缩、对账、偷看浮牌、拆台)、`test_bomb_cat_director`、`test_rulebook_bomb_cat`、
  `test_bomb_cat_screen_flow`(真的牌桌 + 导演 + 会话,3 人与 6 人各打完一整局到结算;真的 BanterView 压在牌桌上拦数字键),以及 perf_budget / debug_flags 的新条目。
- `tools/lan_smoke.sh`:骗子酒馆那局照旧,之后炸弹猫一局(房主 + 发现 + 直连,机器人走牌桌真实入口),三端都打到 MATCH_OVER、胜者一致、无脚本错误。
- 性能(M3,`perf_probe --showcase=bomb_cat --cases=budget`):6 人桌 bomb_seat 379 draw call(可见 147 + 阴影 232)、bomb_fp 360、bomb_overview 392,
  都在 700 / 900 之内。帧时间在这台机器上当时约 30 ms,同一时刻骗子酒馆 4 人 seat 也是 30 ms、德州 8 人 31 ms(机器整体变慢,不是炸弹猫的开销;
  炸弹猫约为骗子酒馆的 1.1 倍)。

### 8.5 已知问题与后续

- 摸到炸弹的特写机位是固定公式(从桌心斜上方看摸牌人),小桌上烛台偶尔挡住一角。
- 观战俯视时自己的(倒下的)酒客仍在画面下方;骗子酒馆也是这样,没有藏。
- 2D 手牌条超过 9 张时第 10 张起没有数字键(只能点)。
- 帧时间预算(10 ms)在当前机器状态下所有玩法都超,需要在机器空闲时复测。

## 9. 道具效果加强(2026-10-10)

> 用户原话:「炸弹猫里各种道具设计地萌一点,动森风,道具效果也精彩点」。规则、协议、事件字段一个没改;只动表现层与演出预算。

### 9.1 文件

- `src/world/bomb_cat/bomb_cat_props.gd`(`BombCatProps`):全部程序生成的小道具,每种一份 `MeshForge.cached` 网格。
  - 实心道具走道具共享材质 `WorldMaterials.prop()`:平底锅、炸弹猫(身子 / 大眼睛 / 导火索三件)、放大镜、大剪刀(两片)、
    五种零食(鱼干、毛线球、胡萝卜、香蕉、仙人掌)、爱心、蝴蝶结、星星、「不行!」印章。
  - 零食与炸弹猫都有小脸:深棕豆豆眼 + 两颗高光 + 腮红 + ω 嘴。平底锅的锅底也画一张笑脸。
  - 配色照新牌面的插画配色(动森风格设计文档 §10.4),亮度按道具色板惯例等比压到 albedo 0.8 以内。
  - 会淡出的薄片(冲击波圈、速度线、脚印、印章印、聚光柱、「?」气泡、×N 徽章、闪光十字)用新着色器 `bomb_fx.gdshader`。
    它不打光、双面、透明,共两份材质(平放 / 公告板),淡出与变色走实例参数 `alpha` / `tint`。
  - 卡通烟团粒子是一个低面数 `SphereMesh` 配一份 toon 材质,颜色来自粒子颜色(`vertex_color_is_srgb`)。
  - 材质缓存由 `main._exit_tree` 的 `BombCatProps.clear_cache()` 释放,网格在 MeshForge 的缓存里。
- `src/world/bomb_cat/bomb_cat_fx.gd`(`BombCatFx`):效果层,由牌桌建在 `TableWorld.poker_root` 下,拆台时 `clear_poker` 一并收走。
  - 每个效果是它下面的一个根节点,补间都挂在根上,演完自己 `queue_free`。`active_count()` 回到 0 = 没有泄漏。
  - 入口都不阻塞;导演按这里的节奏常量去等。
  - 跟着人走的件(徽章、星圈、炸焦的头发、拖尾)由 `_process` 每帧对齐锚点。锚点只记弱引用,牌半路被对账收走也不报错。
  - 效果件一律不投影,每个效果同时活着的粒子 ≤ `MAX_PARTICLES`(300)。
  - 音效走 `sfx` 信号交给 `Sfx.play`(静音照常生效)。
- `Patron` 新增 `sneak` / `bonk` / `plead` / `peek_with_glass`,`PatronAntics` 新增 `bonked` / `plead`。
  - `patron_eye.gdshader` 新实例参数 `plead`(狗狗眼:瞳孔放大、眼睑全开、多两颗高光、下沿一弯泪光,默认 0)。
  - 骗子酒馆与德州的行为不变;`reset_pose` 顺手把头的缩放复原。
- `BombCatCards`:
  - 洗牌改成龙卷风(临时牌,不改张数),之后牌堆一弹。
  - 新增 `peek_rise` / `peek_sink`:偷看时牌堆顶三张浮成发光扇面。
  - 新增 `jiggle`:桌上的牌一震。
  - `transfer` 加 `on_card` 回调(挂拖尾用),`reveal_bomb` 可以不放牌上的火花(交给炸弹猫)。
- `BombCatNameplate.pulse()`:轮到他时铭牌放大一下,外圈泛起暖金光晕,之后留一圈淡光直到换人。
- `Sfx` 新增 9 种程序音效:`bonk`(平底锅「当~」)、`boing`(弹簧)、`stamp`(盖章)、`tornado`(洗牌风声)、`sparkle`(叮铃)、
  `pop`(小气泡)、`sneak`(滑哨「嗖」)、`tiptoe`(踮脚碎步)、`sigh`(松一口气)。

### 9.2 每张牌的演出

导演 `BombCatDirector` 的事件 → 效果:

| 事件 | 效果 |
|---|---|
| `effect skip` | 出牌人往一侧一缩、踮脚溜走:身边扬起奶白烟团,身侧几道速度线,头顶「嗖~」;桌上一串蓝灰小脚印跑向下家。被甩锅时溜了只抵一回合、还是自己走,就不画脚印 |
| `effect pass_turns` | 一口珊瑚红平底锅(锅底一张笑脸)转着圈画弧飞过去,「当!」地扣在下家头顶:冲击波圈、一圈星星、头被拍扁再弹回、蚊香眼晕一下;头顶偏右冒出「×N」徽章。被敲的是自己时镜头一震 |
| `effect peek` | 偷看的人一爪举起大放大镜凑到眼前(镜片一闪),一爪捂嘴偷乐。牌堆顶三张浮成发金光的扇面,正面朝着他。只有偷看的人自己的端传私有视图里的三张,别人看到的一律是牌背。第一人称时放大镜举在镜头左下方 |
| `effect shuffle` | 牌堆炸成一股小龙卷风:十来张牌背旋出来、绕圈升高再旋回去,三圈半透明风环叠成漏斗,星星绕着转;牌堆被压扁后「噗」地弹回 |
| `give_requested` | 讨要的人双爪合十、水汪汪的狗狗眼、歪头,头顶飘出一串莓粉爱心 |
| `effect beg`(给到了) | 那张牌系着蝴蝶结、拖着一串小爱心飞过去,落手时一颗大爱心「啵」地炸成一圈小爱心。牌面只有当事两人看得到(沿用 `transfer`) |
| `played triple` | 目标头上一束暖黄聚光,头顶一个大「?」气泡,写着点名的牌。窗口作废或交牌之后收起 |
| `effect steal` / `request`(给到了) | 打出的零食(2 或 3 份,带小脸)从弃牌堆蹦到桌上、落地压扁再弹两下;然后那张牌拖着金光飞向抽牌的人,零食「噗」地缩没 |
| `noped` | 一枚巨大的红色圆印章(顶上奶白爪印)悬在弃牌堆上方,和那张「不行!」同时拍下:冲击波圈、奶白烟团、桌上的牌一震、镜头一震、「砰!」。弃牌堆上留下圆框 + 爪印 + 「不行!」的印子。连环不行! 一枚比一枚大(每张大 30%,最多 2.2 倍),偶数张换薄荷绿的「不行不行!」。窗口结束时印子淡掉 |
| `bomb_drawn` | 炸弹牌立起来时,一只圆滚滚的炭灰紫炸弹猫「啵嘤」地从牌里弹出来:粉耳朵、亮晶晶的大眼睛、银引信座、导火索嘶嘶冒火花,冒一小撮星星。倒计时期间越晃越凶,跟着三声心跳一鼓一鼓;镜头推近之后再往脸前蹭 18% |
| `defused` | 一把浅银蓝刃、珊瑚粉圆环把的大剪刀从旁边飞进来张开,空剪两下,摸牌人剪线那一刻「咔嚓!」剪断导火索。火花熄灭,剪下的一截打着转掉下去,剩下半截耷拉;炸弹猫眯眼、身子一鼓,长出一口气(「呼~」一小团白烟),撒一小把彩纸 |
| `reinserted` | 炸弹猫缩小一点,从牌前蹦到桌上,踮着脚一蹦一蹦溜到牌堆侧面,横着压扁从侧边钻进去,冒一小团烟;炸弹牌同时翻成背面插进去。钻进去的位置永远是牌堆中间,看不出塞在哪 |
| `exploded` | 卡通「轰!」:一层层圆滚滚的奶黄 / 橘 / 蜜桃烟团,外面一圈薰衣草灰的大烟团(不是写实的火)。乱飞的胖星星、贴桌的大冲击波圈、短暂的暖光、桌上的牌一震、大字「轰!」。炸弹猫先鼓成一个球再消失在烟里。被炸的人照旧黑脸、×眼星星、帽子飞走,头顶另冒一撮炭灰色的炸焦卷毛,一缕缕冒烟 5 秒 |
| `turn_passed` | 换人时一串粉色小爪印从上一位面前沿桌面跑到下一位面前,他的铭牌亮一下。×N 徽章跟着还欠的回合数走(≤ 1 回合、出局、结算时收起) |

- 文字一律是 `Label3D` 漫画字:弹出来、往上飘、淡掉,不做深度测试,第一人称也看得见。
- 第一人称:挂在「头顶」的效果用 `Patron.speech_anchor`(眼前上方)。自己的 ×N 徽章缩到 0.4,平底锅扣到镜头前。

### 9.3 演出预算(`BombCatPacing`,导演 / 预算一致性测试照过)

| 事件 | 原预算 | 新预算 | 导演实际(+ 每个 await 一帧余量) |
|---|---|---|---|
| 溜了 | 0.3 | 0.85 | 0.7 |
| 甩锅 | 0.6 | 1.15 | 1.0 |
| 偷看 | 1.2 | 1.5 | 1.3 |
| 洗牌 | 1.0 | 1.5 | 1.15 + 0.16 + 0.05 |
| 讨要转手 | 0.9 | 1.0 | 0.1 + 0.5 + 0.2 |
| 零食抽牌 / 点名(新 `EFFECT_SNACK_TRANSFER`) | 0.9 | 1.4 | 0.1 + 0.42 + 0.5 + 0.15 |
| 讨要请求 | 0.4 | 0.8 | 0.7 |
| 塞回 | 0.8 | 1.0 | 0.85 + 0.05 |
| 不行! / 摸到炸弹 / 拆弹 / 爆炸 | 不变 | 不变 | 0.54 / 1.75 / 1.4 / 2.8 |

效果的尾巴(烟团散开、徽章、印子、炸焦的头发)不在导演等的时间里,不影响计时。

### 9.4 验证

- `tests/test_bomb_cat_fx.gd`:
  - 网格缓存与材质共享;每个效果入口都建出根节点并演完释放。
  - 效果件不投影、粒子不超上限;×N 徽章跟着欠的回合数走。
  - 偷看浮牌只在给了牌面时亮面;转手的牌只有接牌的自己看得到正面;洗牌龙卷风是临时的;拆台全部收走。
- `test_bomb_cat_screen_flow` 新增三项:
  - 真的牌桌 + 导演逐种事件对上效果,演完 `active_count() == 0`。
  - 偷看扇面在别人的端是牌背、在自己的端是私有视图的三张。
  - 整局打完效果层不留节点。
- `test_bomb_cat_director`:新节奏常量的预算核对,以及效果关键一拍落在导演等的时间里(印章与那张不行! 同时落下、炸弹猫在心跳前弹完、剪刀先到位再咔嚓、炸弹牌在炸弹猫钻进去之前插好)。
- 性能:`perf_probe --showcase=bomb_cat --cases=budget` 下 bomb_seat 381 draw call(之前 379)。效果播放中逐帧采样,座位越肩最高 387,特写约 300–320,都远低于 700。
  帧时间仍是 8.5 节说的机器状态问题,与本改动无关。
