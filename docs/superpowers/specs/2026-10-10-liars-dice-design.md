# 吹牛骰子(第五种玩法)设计(2026-10-10 用户追加)

> 用户原话:「那你做吹牛筛子和斗地主吧」。设计由协调者按惯例直接定;规则采用常见的「大话骰 / Perudo」骰盅吹牛,
> 美术沿用本作的动森式温馨卡通,所有骰盅、骰子、效果全部程序化原创。

## 1. 规则

- 2–6 人。每人 5 颗骰子扣在骰盅里,摇完只有自己能看。
- 本轮第一个人喊一个数「N 个 X」,意思是「全场至少有 N 颗点数为 X 的骰子」,X 取 2–6。
  - **1 点是万能**:算作任何点数,所以不能喊 1。
- 轮到你时二选一:
  - **加注**:喊得比上家大。要么个数更多(点数随意),要么个数相同、点数更大。
  - **开!**:质疑上家。所有人掀开骰盅数一数,1 点算作 X。
    - 实际个数 ≥ N:上家说的是真话,开的人输。
    - 实际个数 < N:上家吹牛,上家输。
- 输的人**丢掉一颗骰子**;骰子丢光就出局,变成观战者。最后还有骰子的人赢。
- 输的人先开下一轮;他出局了就由下一位活着的人开。每轮开始所有人重新摇。
- 第一口喊的个数至少 1;每一口都不能超过场上剩余骰子的总数。
- 回合限时沿用 `Protocol.TURN_TIMEOUT`。超时代打:能加注就按最小合法加注,否则「开!」。
- 断线视为出局,他的骰子移出游戏。不支持中途加入。

## 2. 架构(和炸弹猫同一套分层)

- `src/core/liars_dice/`:纯规则。
  - `liars_dice_state.gd`:骰子、出价、轮次、判定、出局、胜负,传入 RNG 可复现。
  - 每个方法返回 `{"ok", "error"?, "events"}`。
  - 公共事件不含别人的点数,开盅那一刻才把全场点数放进 `revealed` 事件。
  - 事件 schema 写在文件头。
- `src/net/liars_dice_session.gd`(extends GameSession)。
  - 意图 `{"kind":"bid","count":int,"face":int}`、`{"kind":"challenge"}`,走现有的 `rpc_session_intent` / `Net.submit_session_intent`。
  - 私有视图:自己的骰子。
  - 实现 `estimate` / `turn_timer_after` / `on_turn_timeout`。
- `GameMode`:加 `LIARS_DICE := "liars_dice"`,标签「吹牛骰子」,2–6 人,不允许中途加入。
  - 主菜单玩法按钮变成 6 个(骗子酒馆、炸弹猫、吹牛骰子、斗地主、德州长牌、德州短牌),要重新排版:两行或下拉,版面要好看,两边的阶段一都要处理。
- 协议升到 **v8**:新玩法 id 旧版本不认识,不能同桌。只由吹牛骰子的阶段一升。

## 3. 表现

- 桌子:≤4 人用小桌,5–6 人用大桌,同炸弹猫的 `table_radius_for(mode, players)`。不摆目标牌立牌,烛台照常。
- 道具:每人面前一个可爱的皮革骰盅(动森风,圆胖,带一圈缝线和小徽章,颜色跟着物种主色)和 5 颗圆角骰子。
  - 骰子奶油色,点是彩色小圆点;1 点画成一颗小星星,表示万能。
  - 网格缓存、MultiMesh 或合批。
- 演出:
  - **摇盅**:酒客双手握盅摇,哗啦哗啦声,扣下。
  - **偷看**:自己掀开盅边一角看点数;第一人称下视线压低看盅里;别人只看到他偷瞄。
  - **出价**:头顶气泡「3 个 5」,桌心浮出那个点数的大骰子图标加个数。
  - **开!**:拍桌大字「开!」,所有骰盅一起掀开。点数等于 X 的骰子和 1 点逐个高亮跳一下,桌心计数器一路数上去。最后真话 / 吹牛判定,配表情。
  - **丢骰子**:输家的一颗骰子「啵」地弹飞,冒小星星;骰子丢光时出局表演沿用 PatronAntics(蚊香眼加星星)。
  - **胜利**:沿用结算庆祝(跳舞、礼炮)。
- HUD:
  - 左上:场上骰子总数、当前出价、轮到谁。
  - 底部:自己的 5 颗骰子(2D),出价器(个数 ±、点数 2–6 六个按钮,不合法的置灰),「加注」「开!」按钮。
  - 快捷键:↑↓ 调个数,2–6 选点数,回车加注,C 或空格开。T/Q/G/V/WASD/Esc/F1 照旧。
- 说明书新增「吹牛骰子」一本;丢番茄、快捷语、九宫格对话、V 视角都要能用。

## 4. 机器人、冒烟、展台、测试

- debug_flags 机器人能玩:合理随机地出价和开。
- `lan_smoke.sh` 加一局吹牛骰子,3 端打到 MATCH_OVER、胜者一致。
- `tools/shot.gd --liars-dice-showcase`,机位 dice_seat / dice_overview / dice_fp,状态有出价中、开盅计数、丢骰子。
- 测试:
  - 加注合法性。
  - 1 点万能计数。
  - 判定双方向。
  - 出局与胜负。
  - 超时代打。
  - 断线。
  - 隐藏信息不进公共事件。
  - 随机自对局守恒:骰子总数只会因为输了才减少。
  - 会话意图校验。
  - 界面出价器的置灰规则。
  - 预算:seat ≤ 700 draw call。

## 5. 约束

- 不改 `project.godot`。
- 不在 `src/` 运行时读网格数组,不 duplicate ShaderMaterial,新静态缓存在 `main.gd` `_exit_tree` 释放。
- 其他玩法行为零变化。
- 提交身份用 BoAsir(仓库本地配置的 noreply 邮箱)。

## 6. 实施记录(阶段一:规则引擎 + 房主会话 + 网络 + 玩法登记,2026-10-10)

阶段一不含任何表现(牌桌屏幕、HUD、3D 骰盅与骰子、导演、说明书、机器人、冒烟、展台);阶段二在下面这些接口上搭。
本节是阶段二的接口契约:事件、视图、意图的字段**只增不改**。

### 6.1 文件

- 规则引擎(纯逻辑,不依赖网络与场景):`src/core/liars_dice/liars_dice_state.gd`(class `LiarsDiceState`)。**文件头的注释就是事件字典的权威说明**。
  规则常量 `DICE_PER_PLAYER` 5、`FACES` 6、`WILD_FACE` 1、`MIN_BID_FACE` 2、`MIN_PLAYERS` 2、`MAX_PLAYERS` 6。
  给出价器与机器人用的静态函数:`bid_error(count, face, 当前出价, 总数)`(合法为 "",否则错误码)、`is_higher`、`min_raise(当前出价, 总数)`、`is_valid_face`。
- 会话与网络:
  - `src/net/liars_dice_session.gd`(class `LiarsDiceSession` extends `GameSession`):意图校验与分派、计时、视图;`state()` 给测试与机器人只读访问引擎。
  - `src/net/liars_dice_views.gd`(class `LiarsDiceViews`):公共 / 私有视图。
  - `src/net/liars_dice_pacing.gd`(class `LiarsDicePacing`):演出预算。
  - `src/net/game_session.gd`:新增虚函数 `validate_intent(intent) -> String`(默认 `"invalid_intent"`),`BombCatSession` 与 `LiarsDiceSession` 覆盖它。
  - `src/net/network_manager.gd`:`_new_session` 加吹牛骰子;`_handle_session_rpc` 不再写死「只有炸弹猫」,改成 `_session.validate_intent(intent)`。
- 测试(全部无头):`test_liars_dice_state` / `test_liars_dice_session` / `test_net_liars_dice` / `test_liars_dice_fuzz`,
  共用 `tests/liars_dice_helpers.gd`(摆局面 `rig`、公共事件 / 视图的漏信息检查器 `event_leak` / `view_leak`)。
  自对弈:400 局固定种子(2–6 人随机),随机合法喊价 / 「开!」+ 随机超时 + 偶尔断线 + 夹杂的垃圾意图,约 2.6 万步;每步查:
  骰子总数只因输了「开!」(恰好 −1)或断线(−他剩下的)而减少、每人骰子数从不增加、「开!」与开盅成对且开盅点数就是开之前那一盅、
  实际个数与真话 / 吹牛判定属实、丢骰子的是输家、出价严格递增且不超过总数、公共事件与视图不漏点数、私有视图与引擎一致、计时为正、
  当前玩家在场;每局必须结束且恰好一个胜者、名次包含每人一次;并断言每种事件、真话与吹牛、超时代打的加注与「开!」、2–6 人局都走到过。

### 6.2 规则落地时定下的细节

- 步骤 `step` 只有两个:`bid`(当前玩家喊价或「开!」)· `over`。没有单独的「开盅」等待步骤:「开!」、开盅、丢骰子、
  出局、下一轮重摇在**同一批事件**里完成,开盅与计数的演出时间算在这一批的演出预算里。
- 第一轮先喊的人由房主 RNG 随机挑。骰子每轮重摇后按点数从小到大排(私有视图与开盅里都是这个顺序)。
- 出价:`face` ∈ 2..6 的整数,`count` ≥ 1 的整数且 ≤ 场上骰子总数;加注 = 个数更多(点数随意)或个数相同点数更大。
  校验顺序:轮到谁 → 个数类型与下限 → 点数 → 不超过总数 → 比上一口大。
- 「开!」只能质疑本轮的上一口(本轮还没人喊时 `no_bid`)。实际个数 = 全场 `face` 点 + 1 点;实际 ≥ 喊的个数(含相等)= 真话,开的人输;否则上家输。
- 输的人丢一颗骰子(`die_lost.left` = 还剩几颗);丢光紧跟 `player_out`。下一轮由输的人开,他出局了由他之后(座位顺序)的下一位存活者开。
- 只剩一人有骰子:`match_over`,胜者保留他这一轮的骰子(不再重摇,私有视图里还看得到);名次第 1 名是胜者,其后按出局顺序倒排。
- 超时代打:还没人喊 → 「1 个 2」;点数没到 6 → 同个数点数 +1;点数是 6 且个数没到总数 → 个数 +1、点数 2;否则「开!」。代打的事件 `auto: true`。
- 断线 = 出局,他的骰子移出游戏(`player_left.removed`)。对局没结束就**作废本轮、全员重摇**(本轮出价是按旧的总数喊的,
  继续下去可能出现超过总数的出价),由当前玩家开;断线的正是当前玩家时由他之后的下一位存活者开。已出局的观战者断线、不在局里的 pid 都是空批次。
- 不收中途加入(`accepts_late_join` 为假,`GameMode.allows_late_join` 只对德州为真)。

### 6.3 公共事件(广播全员;开盅前不含任何人的点数)

所有事件有 `type`。**只有 `revealed` 带点数**,且只在「开!」时出现。

| type | 字段 | 说明 |
|---|---|---|
| `round_started` | `round`, `starter`, `seats: [pid]`, `counts: [{pid, count}]`, `total` | 新一轮、全员重摇(开局第一轮也是它)。`counts` 按座位,出局者 0;`total` = 场上骰子总数 |
| `bid` | `pid`, `count`, `face`, `auto` | 喊「count 个 face」;`auto` = 超时代打 |
| `turn_passed` | `pid` | 轮到 `pid`(每口喊价之后都发;新一轮的先喊者看 `round_started.starter`) |
| `challenged` | `pid`, `target`, `count`, `face`, `auto` | `pid` 开 `target` 喊的「count 个 face」 |
| `revealed` | `dice: [{pid, dice: [点数]}]`, `face`, `count`, `actual`, `truthful` | 开盅:全场存活者的点数(座位顺序)、实际个数(含 1 点)、上家是否说了真话 |
| `die_lost` | `pid`, `left` | 输家丢一颗,还剩 `left` 颗 |
| `player_out` | `pid` | 骰子丢光出局 |
| `player_left` | `pid`, `removed` | 断线出局,`removed` 颗骰子移出游戏 |
| `match_over` | `winner`, `ranking: [pid]` | |

典型批次(一个意图 / 一次超时 / 一次断线 = 一批):开局 `[round_started]`;喊价 `[bid, turn_passed]`;
「开!」`[challenged, revealed, die_lost, player_out?, round_started | match_over]`;断线 `[player_left, round_started | match_over]`。

### 6.4 公共视图(`rpc_state_public`,每批之后)

```
{
  "mode": "liars_dice", "step": "bid" | "over",
  "round": int, "starter_pid": pid 或 null, "current_pid": pid 或 null,   # over 时 current_pid 为 null
  "bid": {} 或 {"pid", "count", "face"},          # 本轮当前最高的一口
  "bids": [{"pid", "count", "face"}],             # 本轮出价记录(新一轮清空)
  "total_dice": int,
  "players": [{"pid", "name", "alive", "dice_count"}],   # 座位顺序
  "last_reveal": {} 或 {"dice", "face", "count", "actual", "truthful"},   # 最近一次开盅(同 revealed 事件,不含 type;已公开)
  "out_order": [pid], "winner": pid 或 null,
  "ranking": [] 或 [{"pid", "name", "place"}],    # 只在 over 时有
  "turn_time_left": float                         # 房主计时器剩余,含要先播完的演出;over 时 0
}
```

### 6.5 私有视图(`rpc_state_private`,每批之后发给每个座位,含出局者)

```
{
  "dice": [点数],    # 自己本轮的骰子(从小到大);出局为 []
  "alive": bool,
  "round": int       # 与 round_started.round 对得上:界面据此判断这是新摇的一盅(私有视图比开盅演出先到,要等演到 round_started 再换)
}
```

### 6.6 意图与错误码

客户端:`Net.submit_session_intent(intent)`(房主本机直接处理;客人发现有的 `rpc_session_intent`)。
房主校验顺序:发送者在名单里(否则 `not_seated`)→ `_session.validate_intent`(= `LiarsDiceSession.check_intent`:字典、kind 认识、
**不允许多余的键**、`count` / `face` 是整数)→ 引擎规则。被拒走现有的 `intent_rejected(code)`。

| 意图 | 谁、何时 |
|---|---|
| `{"kind": "bid", "count": int, "face": int}` | 当前玩家,`bid` 步骤 |
| `{"kind": "challenge"}` | 当前玩家,`bid` 步骤,本轮已有人喊 |

错误码(`LiarsDiceState.ERR_*`,中文提示在 `LiarsDiceState.ERROR_MESSAGES`,阶段二的牌桌屏幕 toast 用它):
`match_over` 对局已结束 · `not_seated` 不在这一局 · `out` 已出局 · `not_your_turn` · `invalid_count`(不是整数或 < 1)·
`invalid_face`(不是 2..6 的整数;1 点万能不能喊)· `bid_too_low`(没比上一口大)· `bid_too_high`(超过场上骰子总数)·
`no_bid`(本轮还没人喊,没得开)· `invalid_intent`(结构不对、有多余的键,或不是吹牛骰子房间)。

喊价、「开!」、超时代打的 `turn_action` 都为真(行动者那端的演出欠账清零)。

### 6.7 计时语义(沿用 NetworkManager 唯一的回合计时器)

只有一种等待:当前玩家喊价或「开!」。`has_turn()` 在没结束时恒为真。
`turn_timer_after(events, pending, time_left)`:本批有 `turn_passed` 或 `round_started`(引擎每批都有)→ `pending + TURN_TIMEOUT`(30 秒);
否则保留剩余并补上本批演出(计时器没在走时给满)。`pending` 含本批演出,所以「开!」那一批的开盅、计数、丢骰子、重摇都演完才开始计 30 秒。
到点 `on_turn_timeout()` → 最小合法加注或「开!」(见 6.2)。

`LiarsDicePacing` 的预算按 §3 的演出先估:摇盅(每轮开始)2.2、喊价 1.0、轮到下一位 0.2、「开!」1.2、开盅 1.6 + 每颗计数 0.25(最多数 30 颗)、
丢骰子 1.2、出局 1.8、断线 0.8、结算 3.0;导演实测后可以收紧,导演每段演出不得超过预算。

### 6.8 GameMode、主菜单与其他按玩法分支的地方

- `GameMode.LIARS_DICE = "liars_dice"`,label / short_label「吹牛骰子」,2–6 人(`LIARS_DICE_MAX_PLAYERS`,测试核对等于 `LiarsDiceState.MAX_PLAYERS`),
  `allows_late_join` 为假,`is_liars_dice(mode)`。`ALL = [LIARS, BOMB_CAT, LIARS_DICE, HOLDEM, SHORT_DECK]`。`LIARS_DICE_ENABLED := true`(同 `BOMB_CAT_ENABLED`,只管开房菜单)。
- **斗地主占位**:`GameMode.DOU_DIZHU = "dou_dizhu"`、label「斗地主」、`DOU_DIZHU_PLAYERS` 3(`min_players` = `max_players` = 3,`summary` 写成「斗地主 · 3 人」)。
  **它不在 `ALL` 里**,所以本分支 `is_valid("dou_dizhu")` 为假、不会建出错的会话;斗地主分支登记时把它加进 `ALL` 并加 `is_dou_dizhu` 与会话,
  菜单格子就自动亮起来。合并时 `DOU_DIZHU` 常量、标签、人数三处两边写法相同,冲突只在 `ALL` 那一行(两边各加一个 id)。
- 主菜单:新常量 `GameMode.MENU_ORDER = [LIARS, BOMB_CAT, LIARS_DICE, DOU_DIZHU, HOLDEM, SHORT_DECK]` 决定格子顺序;
  `menu_modes()` = `MENU_ORDER` 里合法且没被开关关掉的。`ModePicker.build` 返回三列两行的 `GridContainer`:
  第一行骗子酒馆、炸弹猫、吹牛骰子,第二行斗地主、德州·长牌、德州·短牌;按钮横向铺满等宽,上下内边距 4 → 3、行距 4。
  `menu_modes()` 之外的格子照样占位,画成灰掉的按钮(提示「…· 还在布置中」,不能预选),所以 `*_ENABLED` 改成 false 现在是「灰掉」而不是「藏起来」。
  格子放在「开一桌」标题右边(这一行不再画分隔线);多出来的一行按钮高度由「局域网房间」把搜索状态收进它的标题行抵掉
  (定宽 170 右对齐;端口被占用的提示缩成「广播端口被占用,请用 IP 直连」,完整说明放悬停提示)。
  1280×720 下面板最小高度 671 ≤ 侧栏可见高度 672,不用滚动;宽度仍 ≤ 480(`test_main_menu_species` 两项都查)。
- 默认房名「X 的骰子局」;斗地主「X 的斗地主」也先写好了。等待厅人数上限、局域网发现报文的 cap、房间列表都走 `GameMode.max_players`,自动是 6。
- `SeatLayout.table_radius_for(mode, players)`:吹牛骰子同炸弹猫,≤ 4 人小桌、≥ 5 人(`LIARS_DICE_BIG_TABLE_FROM`)德州大桌、人数未知(传 0)小桌。
  `main.apply_table_mode` 不用改:吹牛骰子照常摆烛台、不摆目标牌立牌。**阶段二进牌桌时要按本局人数再摆一次桌**。
- 说明书 `RulebookContent.book_for_mode` 对吹牛骰子暂时回退骗子酒馆那本(阶段二加「吹牛骰子」一本)。

### 6.9 网络与协议

- 开局:`start_game` → `_new_session(game_mode)` → `LiarsDiceSession`;其他玩法不变。没有新 RPC,意图走现有的 `rpc_session_intent`(RPC 表不变,`test_net_rpc_order` 照过)。
- 协议升到 **v9**:设计稿写的是 v8,但 v8 已经被 0.9.1(德州「开始下一手」与牌局记录)用掉了。旧版本不认识 `liars_dice` / `dou_dizhu`
  (会按骗子酒馆摆桌),不能同桌,所以必须再升一号。**斗地主分支不再另升**,两个新玩法共用 v9。

### 6.10 临时路由(阶段二要替换)

`main._show_table`:吹牛骰子房间暂时进 `_liars_dice_placeholder()`——居中一块「吹牛骰子的桌子还在布置中」+「离开房间」按钮,不会崩。
规则与网络照常跑,每步到点由房主代打(最小加注或「开!」),一局会自己打完,但没有结算界面。阶段二把这一分支换成吹牛骰子的牌桌屏幕并删掉占位函数
(代码里有 `TODO(吹牛骰子阶段二)`)。

### 6.11 阶段二要做的

1. 牌桌屏幕:接 `Net.game_events` / `state_public_updated` / `state_private_updated` / `intent_rejected`(toast `LiarsDiceState.ERROR_MESSAGES`),
   出手一律 `Net.submit_session_intent(...)`;替换 `main._show_table` 的占位分支;进牌桌时按本局人数 `SeatLayout.table_radius_for(mode, 人数)` 摆桌。
   私有视图比「开!」那一批的演出先到:按 `round` 等演到对应的 `round_started` 再把新点数换上(开盅演出要用 `revealed.dice`,不要用私有视图)。
2. 导演:按 6.3 的事件演出,每段时长不超过 `LiarsDicePacing` 的预算(参照 `test_bomb_cat_director` 加检查);开盅时长随 `revealed.actual` 变。
3. HUD:左上 `total_dice` / `bid` / `current_pid`;出价器的置灰直接用 `LiarsDiceState.bid_error(count, face, view.bid, view.total_dice)`,
   「开!」按钮亮起条件 = 轮到自己且 `bid` 非空;默认值可以取 `LiarsDiceState.min_raise`。快捷键见 §3。
4. 3D 骰盅与骰子(网格缓存 / MultiMesh,静态缓存在 `main._exit_tree` 释放)、说明书「吹牛骰子」一本。
5. 机器人(`debug_flags.gd`)与 `tools/lan_smoke.sh` 的吹牛骰子一局;`tools/shot.gd --liars-dice-showcase`。挑合法意图可以照抄 `tests/test_liars_dice_fuzz.gd` 的 `_random_step`。

## 7. 实施记录(阶段二:牌桌、HUD、导演、3D 骰盅与骰子、音效、说明书、机器人、冒烟与展台,2026-10-10)

阶段一的事件 / 视图 / 意图契约(§6)一个字段没改,协议仍是 v9;`project.godot` 没动;其他玩法的行为不变
(共享文件只做了局部追加:`main._show_table` 的路由、`Patron` 两个新动作、`Sfx` 六个新音效、`debug_flags` 的机器人与截图标记、
`lan_smoke.sh` 一局、说明书页签、`shot.gd` / `perf_probe.gd` / `perf_budget.gd` / `camera_views.gd` 的吹牛骰子入口)。

### 7.1 文件

- 界面 `src/ui/liars_dice/`:
  - `liars_dice_screen.gd`(牌桌控制器,`main._show_table` 进它,占位屏已删):接 `Net.game_events` / `state_public_updated` /
    `state_private_updated` / `intent_rejected`(toast `LiarsDiceState.ERROR_MESSAGES`),事件排队交给导演,演完按视图对账;
    进牌桌时按本局人数 `SeatLayout.table_radius_for(mode, n)` 摆桌(烛台照常、不摆立牌);铭牌、视线与 WASD(SeatGaze)、
    V 视角(SeatCamera)、九宫格快捷对话、丢番茄与快捷语、Esc 离开确认、出局转观战、结算面板 + 结算庆祝都同其他牌桌。
    按钮、快捷键、机器人共用一套入口:`nudge_count` / `pick_face` / `set_pick` / `submit_bid` / `submit_challenge`。
  - `liars_dice_screen_state.gd`(纯逻辑本地状态):影子行按事件推进;**自己的骰子按轮次缓存**——私有视图来了只记
    `_dice_by_round[round]`,导演演到那一轮的 `round_started` 才 `take_round_dice` 换到屏幕上;开盅一律用 `revealed.dice`;
    别人的点数只在 `last_reveal` 里出现。另有计数顺序 `count_order`、判定文案、结算名次 `ranking_rows`(fate:winner / out / left)。
  - `liars_dice_picker.gd`(出价器的选择,纯逻辑):置灰逐格问 `LiarsDiceState.bid_error(count, face, 视图的 bid, total_dice)`,
    默认值 `min_raise`(加不上去时停在当前这一口);调个数时选着的点数不合法就换成这个个数下最小的合法点数,选点数时个数不够自动抬。
  - `liars_dice_hud.gd`:左上(场上骰子总数、当前这一口 + 小骰子图标、本轮出价记录、轮到谁、自己的状态)、右上「对话」「规则」、
    底部自己的 5 颗 2D 骰子 + 出价器(个数 −/+、点数 2–6 六个骰子按钮、「加注 N 个 X」「开!」)、回合横幅与环形倒计时、
    开盅面板(画面上方:每人的名字和点数,算进去的随 3D 计数一颗颗亮)、日志、大字宣告、观战横幅。按钮全部 `FOCUS_NONE`。
  - `dice_icon.gd`(2D 骰子面,HUD / 出价器 / 结算 / 说明书共用)、`liars_dice_nameplate.gd`(名字 + 一排小骰子 + 这一轮最后喊的一口)、
    `liars_dice_settlement.gd`(「骰子留到最后的人」,第 1 名写还剩几颗)、`liars_dice_bot.gd`、`liars_dice_director.gd`。
- 3D `src/world/liars_dice/`:
  - `liars_dice_props.gd`:骰盅(鼓肚子的车削皮盅,口沿深色皮带缝奶油针脚、肩上一圈装饰缝线、顶上小皮扣、侧面黄铜星星徽章,
    盅里深棕;皮色 = 物种主色往暖皮革色里调 38%,每个物种一份网格)与骰子(奶油色圆角立方体,彩色小圆点,1 点是一颗胖星星;
    计数高亮用同形的发光网格)。全部 `MeshForge.cached`、共用 `WorldMaterials.prop()`、一个 surface;**没有新的静态缓存**
    (`MeshForge.clear_cache` 已在 `main._exit_tree` 里),也没有运行时读网格数组、没有复制 ShaderMaterial。
  - `liars_dice_layout.gd`:骰盅摆在主人右手边(越肩镜头从右肩后面正好看到;离烛台不够远时换到左手边;大桌再往右挪),
    盅底下 2×2 平铺 + 第五颗叠在中间上面,开盅后翻过来口朝上放回主人那边、骰子往桌心排成一行;摇盅点在下巴前下方
    (再高会戳进动森式大头);偷看 / 特写机位。
  - `liars_dice_cups.gd`(挂 `poker_root`,拆台时一并释放):骰盅状态 down / open / tipped / held;**别人的骰子在开盅之前根本不建**;
    动作:`gather`(上一轮的骰子蹦回盅里)、`shake`(双手捧盅哗啦哗啦摇,`Patron.hold_paws` 每帧扶着盅,翻过来扣下)、`peek`、
    鼠标悬停偷看 `set_hover_peek`、`reveal`(全体翻盅、骰子滑出排成一行)、`hop`(计数跳一下 + 金色光圈)、`pop_die`、`tip`。
  - `liars_dice_fx.gd`(继承 `BombCatFx`,复用它的漫画字 / 星星 / 冲击波 / 闪光):桌心出价标记(那个点数朝着镜头的大骰子 +「×N」,
    浮着慢慢晃,下一口顶掉它)、开盅计数器「数到 n / 喊了 m」、「开!」大字、真话 / 吹牛判定字、丢骰子的「啵!」与星星。
- 共享:`Patron.hold_paws / release_paws`;`Sfx` 新增 `dice_shake`(皮盅里五颗骰子随甩动一阵阵磕碰 + 皮革摩擦)、`cup_slam`、
  `dice_clack`、`die_pop`、`count_tick`、`dice_peek`;说明书 `RulebookLiarsDice`(怎么赢、一轮怎么走、喊价与加注、1 点万能、开!、
  丢骰子与出局、操作)+ 新块类型 `dice`(开盅示例),`book_for_mode` 接上。
- 工具:`tools/liars_dice_showcase.gd`(`shot.gd --liars-dice-showcase`,机位 dice_seat / dice_overview / dice_fp / dice_close /
  dice_peek,状态 bidding / shaking / peek / counting / lost / out / settlement);`perf_probe --showcase=liars_dice [--dice-state=counting]`;
  `perf_budget` 加 dice_seat / dice_fp ≤ 700、dice_overview / dice_close ≤ 900;`lan_smoke.sh` 加一局吹牛骰子(`SKIP_LIARS_DICE=1` 跳过)。

### 7.2 表现上定下的细节

- 新一轮:上一轮排开的骰子蹦回各自口朝上的盅 → 全员捧起骰盅摇(摇的同时等自己的私有骰子,不额外占时间)→ 翻过来啪地扣下
  (自己的骰盅底下换成新点数,2D 骰子一颗颗弹一下)→ 每人掀开盅沿偷看、捂嘴偷乐;第一人称时自己的视线压低凑到盅沿(MODE_PEEK,马上回座)。
- 喊价:头顶气泡「3 个 5」、伸手、桌心大骰子 +「×3」弹出来(冲击波一圈、「啵」);喊得很大时表情得意。
- 「开!」:开的人拍桌,砸到桌面那一刻桌心大字「开!」+ 冲击波 + 星星、镜头一震、吊灯一晃、其余人吓一跳;被开的人担心脸。
  开盅:全体翻盅、骰子排开,按座位、每人从左到右,等于 X 的和 1 点一颗颗跳起来换发光网格、底下一圈金光,桌心计数器与开盅面板同步数;
  数完判定字「真话!」/「吹牛!」(配宣告与日志),赢的一方得意捂嘴笑、输的一方吓一跳。
- 丢骰子:输家一行最右边的一颗弹飞、打着转缩没,「啵!」+ 一圈星星,输家头被敲扁一下(`Patron.bonk`);自己丢时宣告还剩几颗。
- 出局:骰盅歪倒,酒客 `die()`(蚊香眼转几圈定格成 × 、头顶星星——PatronAntics);自己出局后转观战俯视。断线同样歪倒、清掉出价标记。
- 胜利:同其他玩法的结算庆祝(胜者跳舞、旁人鼓掌、出局的倒着、礼炮彩纸,`hash(["liars_dice", winner, ranking])` 挑舞),环绕胜者,结算面板在右边。
- 快捷键:`↑` `↓` 个数(按住连发)、`2`–`6` 点数、`Enter` 加注、`C` / `空格` 开;快捷语面板或九宫格开着时数字键归面板;
  `T` / `Q` / `G` / `V` / `WASD` / `Esc` / `F1` 一个都不占。鼠标停在自己扣着的骰盅上掀开盅沿看一眼(只在本机)。

### 7.3 演出预算(`LiarsDicePacing` 的数没改,导演实测都在预算里,`test_liars_dice_director` 核对)

| 事件 | 预算 | 导演实测(不含帧余量) |
|---|---|---|
| round_started | 2.2 | 收骰子 0.25 + 摇盅 1.1 + 偷看 0.48 + 0.05 = 1.88 |
| bid | 1.0 | 0.72 |
| turn_passed | 0.2 | 0(不等) |
| challenged | 1.2 | 拍桌 0.28 + 0.78 = 1.06 |
| revealed | 1.6 + 0.25 × 实际个数 | 翻盅排开 0.41 + 0.1 + 0.2 × 实际个数 + 判定 0.78 |
| die_lost | 1.2 | 0.85 |
| player_out | 1.8 | 1.35 |
| player_left | 0.8 | 0.7 |
| match_over | 3.0 | 2.2 |

另有一条实速测试:真的演一批「开!」(challenged、revealed、die_lost、player_out、round_started),每段从开始到下一段开始都不超过预算。

### 7.4 验证

- 测试 148 → 155 个脚本、1622 → 1681 个用例全过;新增 `test_liars_dice_screen_state` / `_hud` / `_director` / `_world` / `_screen_flow`、
  `test_rulebook_liars_dice`、`test_sfx_liars_dice`,`test_perf_budget` 加吹牛骰子机位,`test_rulebook_content` 页签改成四本。
  - 隐藏信息:整局流程里每次喊价 / 开之前桌上别人的骰子节点数都是 0;本地状态开盅前拿不到别人的点数;公共视图通过漏点数检查器。
  - 按轮次缓存:开盅时屏幕与盅底下是这一轮的点数(下一轮的私有视图已经先到),演到 round_started 才换。
  - 出价器的置灰与 `bid_error` 在 4 种总数 × 5 种上一口 × 每个个数 × 每个点数上逐格一致;默认值等于 `min_raise`。
- `tools/lan_smoke.sh`:骗子酒馆、炸弹猫、吹牛骰子三局都过,吹牛骰子 3 端打到 MATCH_OVER、胜者一致、快捷对话都收到。
- 性能(M3、1920×1080、游戏渲染配置):dice_seat 382 draw call(开盅计数 27 颗骰子排开时 391)、dice_fp 362 / 371、
  dice_overview 394、dice_close 278,预算 700 / 900 内;帧时间 8.8 ms 左右(炸弹猫展台 bomb_seat 378 作对照)。

### 7.5 已知问题与后续

- 机器人的 WASD 小动作(`--bot` 的 fidget,其他玩法同样有)会把头探出去很远,真机截图里自己的大头常挡住桌心;展台截图不受影响。
- 大桌越肩机位离对面的骰子行较远,单看 3D 骰子不容易数清,所以开盅时另有画面上方的开盅面板同步计数。
- 第一人称下自己的骰盅在画面最下方、被出价器挡住大半,偷看靠新一轮的视线压低和底部的 2D 骰子。
