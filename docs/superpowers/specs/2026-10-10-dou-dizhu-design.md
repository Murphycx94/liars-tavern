# 斗地主(第六种玩法)设计(2026-10-10 用户追加)

> 用户原话:「那你做吹牛筛子和斗地主吧」。设计由协调者按惯例直接定;规则采用最常见的三人斗地主(叫分制),
> 牌面沿用德州那套动森风扑克牌,再补大小王。

## 1. 规则

- **人数**:正好 3 人;等待厅不满 3 人不能开局。用 54 张牌(含大王、小王),每人 17 张,留 3 张底牌。
- **叫分**:
  - 从随机一人开始,每人依次叫 1 / 2 / 3 分或不叫,只能比前面的人叫得高。
  - 有人叫 3 分立即成为地主;一圈后叫分最高的人当地主。
  - 三人都不叫就重新发牌,连续 3 次都不叫,就让第一个人当 1 分地主。
- **地主**:拿走 3 张底牌,底牌对所有人亮出,手里 20 张,先出牌;另外两人是农民,一伙。
- **出牌**:
  - 轮流出牌,必须出同牌型、同张数且更大的牌,或者「不出」。
  - 两家都不出时,最后出牌的人重新自由出牌。
- **牌型**,大小 3 < 4 < … < K < A < 2 < 小王 < 大王:
  - 单张;对子;三张。
  - 三带一,三带一对。
  - 顺子:5 张及以上连续单张,不能含 2 和王。
  - 连对:3 对及以上连续对子,不能含 2 和王。
  - 飞机:2 个及以上连续三张,可带同数量单张或同数量对子,不能含 2。
  - 四带二:四张带两张单牌或两对。
  - 炸弹:四张相同,能压任何非炸弹牌型;炸弹之间比点数。
  - 王炸:大小王,最大。
- **结束**:任何一人出完牌这一手结束。地主出完地主赢,农民任何一人出完农民赢。
- **计分**:底分 = 叫的分。倍数从 1 开始:
  - 每出一个炸弹或王炸 ×2。
  - 春天 ×2:地主出完时农民一张没出过;或者农民赢、而地主只出过第一手。
  - 地主赢:地主 +2 × 底分 × 倍数,两个农民各 − 底分 × 倍数;地主输则反过来。三人总和为 0。
- **牌局**:像德州一样连续打很多手,分数累计;房主可以随时「散局」,打完当前这一手后按累计分数排名结算。
  每手结束后自动开下一手,中间有间隔,和德州的 `hand_gap` 一样。不支持中途加入,有人离开就提前结算。
- **超时代打**:叫分阶段不叫;出牌阶段能不出就不出,必须出时出最小的单张。
  - 连续 2 次超时进入托管,自动代打,点「取消托管」恢复。

## 2. 架构

- `src/core/dou_dizhu/`:
  - 牌型识别与比较:`ddz_hand.gd`,纯函数,覆盖全部牌型和带牌组合。
  - 状态机:`ddz_state.gd`,发牌、叫分、出牌、结算、累计分。
  - 牌用 0–53 编号,52 / 53 是小王 / 大王。
  - 每个方法返回 `{"ok","error"?,"events"}`;公共事件不含别人手牌,底牌在定地主时公开。
- `src/net/dou_dizhu_session.gd`(extends GameSession)。
  - 意图:`{"kind":"bid","score":0..3}`(0 = 不叫);`{"kind":"play","cards":[手牌下标...]}`;`{"kind":"pass"}`;`{"kind":"trustee","on":bool}`。
  - 走现有的 `rpc_session_intent`。
  - 私有视图:自己的手牌、可出的提示组合(提示按钮用)。
  - `next_hand_ready` / `hand_gap` / `start_next_hand` / `request_end` 仿照德州。
- `GameMode`:加 `DOU_DIZHU := "dou_dizhu"`,标签「斗地主」,`min_players = max_players = 3`,不允许中途加入。
  - 6 个玩法按钮的排版和协议 v8 由吹牛骰子的阶段一负责;两边都改 GameMode 时合并要小心。

## 3. 表现

- 桌子:3 人用小桌,座位均匀分布。
- 牌:
  - 复用德州的 52 张动森风牌面,补**大王 / 小王**两张原创插画,比如戴王冠的大熊猫国王和小浣熊;画风同 J/Q/K。
  - 牌背沿用德州牌背。
  - 悬停看大牌照常可用。
- 地主标识:地主头顶戴一顶可爱的小地主帽(瓜皮帽),农民戴草帽;名牌显示「地主 / 农民」和当前分数。
- 桌面:
  - 底牌三张先扣在桌心,定地主时翻开飞到地主手里。
  - 每人出的牌摊在自己面前的桌面上,下一圈清掉。
  - 炸弹、王炸、飞机、顺子、春天各有一段短特效。
    - 炸弹:卡通炸开的蘑菇云加「炸弹!」,可以复用炸弹猫的爆炸云。
    - 王炸:一枚小火箭冲天放烟花。
    - 飞机:一架小纸飞机掠过桌面。
    - 顺子 / 连对:一串牌像波浪一样亮起。
    - 春天:花瓣飘落加「春天!」。
  - 倍数变化时左上角数字跳动。
- HUD:
  - 自己 17–20 张手牌的 2D 手牌条,点选或拖动连选,点数相同的叠放可选。
  - 按钮:「出牌」「不出」「提示」(循环可出组合)「重选」;叫分阶段换成「不叫 / 1 分 / 2 分 / 3 分」;「托管」切换。
  - 快捷键:回车出牌,空格或 P 不出,H 提示,R 重选。T/Q/G/V/WASD/Esc/F1 照旧。
  - 左上:底分、倍数、底牌、地主是谁、剩余手牌张数警报(只剩 1–2 张时报警)。
- 散局结算:沿用德州散局的排名面板风格,加胜者庆祝。
- 说明书新增「斗地主」一本,含全部牌型图示;丢番茄、快捷语、九宫格对话、V 视角都要能用。

## 4. 机器人、冒烟、展台、测试

- 机器人:叫分随机,出牌出最小的合法组合,能跟就跟、偶尔不出,保证一局能打完。
- 冒烟:`lan_smoke.sh` 加一局斗地主,正好 3 端,房主 `--hands=N` 打 N 手后散局。核对三端结算一致、分数总和为 0。
- 展台:`tools/shot.gd --dou-dizhu-showcase`,机位 ddz_seat / ddz_overview / ddz_fp,状态有叫分、出牌中、炸弹、结算。
- 测试:
  - 牌型识别全集,含各种带牌与非法组合。
  - 比较规则:同型比较、炸弹与王炸。
  - 叫分流程,含重发与连续不叫。
  - 春天判定。
  - 计分总和为 0。
  - 超时与托管。
  - 隐藏信息。
  - 随机自对局守恒:54 张牌只在手牌、桌面、已出之间流转。
  - 会话意图校验。
  - 界面:多选、提示循环、按钮置灰。
  - 预算:seat ≤ 700 draw call。

## 5. 约束

- 同吹牛骰子:不改 `project.godot`,其他玩法行为零变化,提交身份用 BoAsir。

## 6. 实施记录(阶段一:规则引擎 + 房主会话 + 网络 + 玩法登记,2026-10-10)

阶段一不含任何表现(牌桌屏幕、HUD、3D、导演、大小王牌面、说明书、机器人、冒烟、展台);阶段二在下面这些接口上搭。
本节是阶段二的接口契约:事件、视图、意图的字段**只增不改**。

### 6.1 文件

- 规则引擎(纯逻辑,不依赖网络与场景):
  - `src/core/dou_dizhu/ddz_hand.gd`(class `DdzHand`):牌编号、牌型识别 `analyze` / `classify`、跟牌 `match_lead`、比较 `beats`、
    能出的组合 `legal_plays(hand, lead)`(提示按钮与托管 / 机器人用)、`smallest_single`、`poker_card`(换德州牌面)、`label(s)`、`type_name`。
  - `src/core/dou_dizhu/ddz_state.gd`(class `DdzState`):完整状态机。**文件头的注释就是事件字典的权威说明**。
- 会话与网络:
  - `src/net/dou_dizhu_session.gd`(class `DouDizhuSession` extends `GameSession`):意图校验(`check_intent` / `validate_intent`)与分派、计时语义、
    连续多手。`state()` 给测试与机器人只读访问引擎。
  - `src/net/dou_dizhu_views.gd`(class `DouDizhuViews`):公共 / 私有视图。
  - `src/net/dou_dizhu_pacing.gd`(class `DouDizhuPacing`):演出预算、`HAND_GAP`、`TRUSTEE_DELAY`。
- 测试(全部无头):`test_ddz_hand` / `test_ddz_state` / `test_dou_dizhu_session` / `test_net_dou_dizhu` / `test_dou_dizhu_fuzz`,
  共用 `tests/ddz_helpers.gd`(按点数写牌 `cards("3 3 SJ")`、直接进出牌阶段 `rig_play`、事件 / 视图的键白名单与「只含已公开的牌」检查)。
  - 牌型:全部牌型表、非法组合表、多读法、比较;另有穷举核对——随机 120 手 6–11 张的手牌 × 9 种上家牌,枚举每个子集的全部读法,
    断言 `legal_plays` 恰好覆盖每种能压过的「型 + 点数 + 组数」、且每项都能出。
  - 自对局:250 个固定种子牌局(约 440 手、2.5 万步),随机叫分 / 挑提示出牌 / 不出 / 超时 / 开关托管 / 垃圾意图 / 偶尔散局或断线;
    每步查 54 张守恒、事件与公共视图不漏没公开的牌、私有视图与引擎一致、被拒不改局面、提示都能出、零和;每个牌局必须结算,
    并断言每种事件、主要牌型、春天、强制地主、自动托管、手中途断线都走到过。

### 6.2 规则落地时定下的细节

- **牌编号**:0–51 = 点数下标 × 4 + 花色,52 小王、53 大王。点数下标 0 = 3 … 11 = A、12 = 2、13 小王、14 大王;花色同 `PokerCard`(0 ♠ 1 ♥ 2 ♦ 3 ♣)。
  牌 id 从小到大就是点数从小到大,手牌永远升序存放,**意图里的下标就是私有视图 `cards` 的下标**。`DdzHand.poker_card(c)` 给德州牌面的牌值,王返回 -1。
- **牌型字典** `{"type", "rank", "length", "count"}`:`type` ∈ `single` `pair` `triple` `triple_single` `triple_pair` `straight` `pair_straight`
  `airplane` `airplane_single` `airplane_pair` `four_two_single` `four_two_pair` `bomb` `rocket`(中文名 `DdzHand.TYPE_NAMES`);
  `rank` = 主体那组的点数(顺子 / 连对 / 飞机取最小那组,王炸 14);`length` = 顺子张数 / 连对对数 / 飞机组数,其他 1。
- **带牌**:三带一的单牌不能和三张同点(那是炸弹);带对的对子点数不同于主体、多个对子点数互不相同(王不成对);
  飞机带单的翅膀可以同点、也可以是机身某组的第 4 张;四带二的两张可以是一对;**带的单牌不能同时是大小王**。顺子、连对、飞机最高到 A。
- **多种读法**:如 333444555666 既是 4 连飞机又是 3 连飞机带单。`analyze` 全列出;自由出牌按 `TYPE_PRIORITY`(王炸、炸弹、顺子、连对、飞机、
  飞机带对、飞机带单、四带两对、四带二、三带一对、三带一、三张、对子、单张)取第一种;跟牌时取能压过上家的读法里点数最大的。
- **比较**:王炸最大;炸弹压一切非炸弹,炸弹之间比点数;其余必须同型、同张数、同组数且点数更大。
- **`legal_plays` 的顺序**(提示循环、托管、机器人取第一个):跟牌时同型按点数从小到大,然后炸弹按点数,王炸最后;
  自由出牌时非炸弹按点数从小到大、同点数张数多的先(四带二排在同点数其他组合之后),然后炸弹、王炸。每种「型 + 点数 + 组数」只给一个代表,
  带牌挑最不心疼的(先用单出的点数,再拆对子、三张,最后才拆炸弹)。私有视图最多给 `MAX_HINTS` = 40 个。
- **叫分**:每手开始时房主 RNG 挑 `first_bidder`,重发时**不换人**(所以「连续 3 次都不叫,让第一个人当 1 分地主」没有歧义)。
  第 3 次发牌(`MAX_DEALS`)还是都不叫:用这一副牌,`first_bidder` 当 1 分地主(`landlord.forced` 为真)。叫 3 立即结束;叫分不能等于之前的最高分。
- **春天**:地主出完时两个农民出牌次数都是 0;或农民赢而地主只出过 1 次(第一手)。「不出」不算出牌。
- **计分**:单位 = 底分 × 倍数(炸弹 / 王炸各 ×2、春天 ×2);地主 ±2 单位、农民各 ∓1 单位,三人总和恒为 0。
- **亮牌**:一手结束时 `hand_over.remaining` 公开三家剩下的牌(这时已不是秘密,结算面板可以摊牌)。
- **超时**:叫分 → 不叫;出牌 → 有上家就不出,自由出牌就出最小的单张。同一人连续 2 次超时进入托管:那次超时先发 `trustee{auto:true}` 再发代打的动作。
  托管中轮到他时房主很快代打(`auto: true`,不再计超时):叫分不叫;自由出牌出 `legal_plays` 第一个;上家是队友(两个农民)就不出;
  否则出最小的能压过的**非炸弹**组合,没有就不出。本人亲自出手清零连续超时;托管跨手保留,开关清零连续超时。托管中本人照样能亲自出手。
- **散局**:两手之间立即结算;一手进行中先发 `ending`,打完这一手再在同一批里发 `hand_over` + `session_over`。
- **离开**:任何人断线 → `player_left{hand_voided}` + `session_over{reason: "player_left"}`,进行中的一手作废不计分,按已有累计分排名。
- **名次**:按累计分从高到低,同分同名次(`place` = 比他高的人数 + 1),同分按座位排。

### 6.3 公共事件(广播全员,不含任何隐藏信息)

所有事件有 `type`。带牌 id 的只有 `landlord.bottom`、`played.cards`、`hand_over.remaining`,都是这时已公开的牌。

| type | 字段 | 说明 |
|---|---|---|
| `hand_started` | `hand`, `deal`(1), `seats: [pid]`, `first_bidder`, `hands: [{pid, count}]`, `bottom_count`(3), `scores: [{pid, score}]` | 新的一手,紧跟 `turn` |
| `redeal` | `hand`, `deal`, `first_bidder`, `hands: [{pid, count}]` | 三人都不叫,重新发牌(`deal` = 第几次发牌) |
| `turn` | `pid`, `stage: "bid" \| "play"`, `free: bool` | 轮到 `pid`;`free` = 自由出牌(叫分时 false) |
| `bid` | `pid`, `score`(0 = 不叫), `timed_out`, `auto` | |
| `landlord` | `pid`, `base`, `bottom: [3 张]`, `forced` | 定地主,底牌亮出并进他手里(20 张),紧跟 `turn{free:true}` |
| `played` | `pid`, `cards`, `combo`(牌型), `rank`, `length`, `multiplier`(出完之后的倍数), `remaining`(他还剩几张), `timed_out`, `auto` | |
| `passed` | `pid`, `timed_out`, `auto` | 不出 |
| `trick_cleared` | `pid` | 两家不出:桌面清掉,`pid` 重新自由出牌 |
| `trustee` | `pid`, `on`, `auto` | 托管开关;`auto` = 连续超时自动进入 |
| `hand_over` | `hand`, `winner`, `landlord`, `landlord_won`, `base`, `multiplier`(含春天), `bombs`, `spring`, `deltas: [{pid, delta}]`, `scores: [{pid, score}]`, `remaining: [{pid, cards}]` | 一手结束 |
| `ending` | — | 房主散局,打完这一手再结算 |
| `player_left` | `pid`, `hand_voided` | 有人离开,紧跟 `session_over` |
| `session_over` | `reason: "host" \| "player_left"`, `results: [{pid, name, score, place, left}]` | 牌局结算(`name` 由会话补) |

典型批次(一个意图 / 一次超时 / 一次断线 / 一次开下一手 = 一批):
开局 / 下一手 `[hand_started, turn]`;叫分 `[bid, turn]` / `[bid, landlord, turn]` / `[bid, redeal, turn]`;
出牌 `[played, turn]` / `[played, hand_over]` / `[played, hand_over, session_over]`;不出 `[passed, turn]` / `[passed, trick_cleared, turn]`;
超时进托管 `[trustee, bid|passed|played, …]`;托管开关 `[trustee]`(状态没变时为空批);散局 `[ending]` 或 `[session_over]`;断线 `[player_left, session_over]`。

### 6.4 公共视图(`rpc_state_public`,每批之后)

```
{
  "mode": "dou_dizhu", "hand": int(第几手), "phase": "idle" | "bidding" | "playing" | "between" | "over",
  "deal": int(本手第几次发牌), "first_bidder": pid, "bids": [{pid, score}](本次发牌), "highest_bid": int,
  "current_pid": pid 或 null, "landlord": pid 或 null, "base": int(定地主前 0), "multiplier": int, "bombs": int,
  "bottom": [] 或 [3 张],    # 定地主后公开;两手之间仍是上一手的
  "lead": {} 或 {"pid", "cards", "type", "rank", "length", "count"},   # 本圈要压的牌;自由出牌时 {}
  "passes": int,
  "players": [{"pid", "name", "hand_count", "score"(累计), "role": "" | "landlord" | "farmer", "trustee",
               "table": [本圈他最后出的牌], "passed": bool(本圈他最后是不出), "plays"(本手出牌次数), "left"}],   # 座位顺序
  "turn_time_left": float,   # 房主计时器剩余(含要先播完的演出);没人行动时 0
  "ending": bool,            # 房主已点散局
  "last_hand": {} 或 hand_over 事件去掉 type(上一手的结算摘要,两手之间画结算用),
  "results": [] 或 [{pid, name, score, place, left}](over 时),
  "end_reason": "" | "host" | "player_left"
}
```

### 6.5 私有视图(`rpc_state_private`,每批之后发给每个没离开的座位)

```
{
  "hand": int,                 # 第几手(界面据此判断换了一副牌)
  "cards": [牌 id](升序),     # 意图 play 的下标就是它
  "role": "" | "landlord" | "farmer", "trustee": bool, "my_turn": bool,
  "can_pass": bool,            # 轮到自己出牌且有上家
  "bid_options": [0, …] 或 [], # 轮到自己叫分时能叫的分(0 = 不叫)
  "hints": [{"indices": [下标], "type": 牌型}]   # 轮到自己出牌时能出的组合(legal_plays 顺序,最多 40);其他时候 []
}
```

### 6.6 意图与错误码

客户端:`Net.submit_session_intent(intent)`(房主本机直接处理;客人发 `rpc_session_intent`)。房主校验顺序:发送者在名单里(否则 `not_seated`)→
`DouDizhuSession.validate_intent`(字典、≤ 2 个键、kind 认识、字段类型)→ 引擎规则。被拒走现有的 `intent_rejected(code)`。

| 意图 | 字段 | 谁、何时 | `turn_action` |
|---|---|---|---|
| `{"kind": "bid", "score": 0..3}` | 0 = 不叫;1–3 要比之前最高的高 | 当前叫分者 | 真 |
| `{"kind": "play", "cards": [下标…]}` | 1–20 个互不相同的手牌下标 | 当前出牌者 | 真 |
| `{"kind": "pass"}` | | 当前出牌者,有上家时 | 真 |
| `{"kind": "trustee", "on": bool}` | | 任何座位,牌局没结束就行(两手之间也行) | 假 |

错误码(`DdzState.ERR_*`,中文提示在 `DdzState.ERROR_MESSAGES`,阶段二 toast 用它):
`session_over` 牌局已结束 · `not_seated` · `no_hand`(两手之间)· `not_your_turn` · `not_bidding`(出牌阶段叫分)· `not_playing`(叫分阶段出牌 / 不出)·
`invalid_bid` · `invalid_play`(下标越界 / 重复 / 空)· `invalid_combo`(不成牌型)· `cannot_beat`(压不过上家)· `cannot_pass`(自由出牌不能不出)·
`invalid_intent`(结构不对、多余的键,或不是斗地主房间)· `invalid_players`(开局不是 3 人,只在引擎层)。

散局:房主调 `Net.end_poker_session()`(名字是德州留下的,实际调 `_session.request_end()`,斗地主同样适用)。

### 6.7 计时语义(沿用 NetworkManager 唯一的回合计时器与两手之间的计时器,不新增计时器)

`has_turn()` = 叫分或出牌阶段且有当前行动者。`turn_timer_after(events, pending, time_left)`(`pending` 含本批演出):

| 情形 | 时长 |
|---|---|
| 当前行动者在托管中 | `pending + TRUSTEE_DELAY`(1 秒) |
| 本批有 `turn`,或计时器没在走,或当前行动者刚取消托管 | `pending + 一个回合`:叫分 `BID_TIMEOUT` 15 秒,出牌 `Protocol.TURN_TIMEOUT` 30 秒 |
| 其他(旁人开关托管等) | `time_left + 本批演出` |

到点 `on_turn_timeout()` → `DdzState.timeout()`(超时规则或托管打法,见 6.2)。
两手之间:`next_hand_ready()` 在 `between` 阶段为真,`hand_gap()` = `DouDizhuPacing.HAND_GAP`(5 秒,演完结算再停这么久,不用等谁确认),
`_on_hand_timer` → `start_next_hand()`。散局或结算后 `next_hand_ready()` 为假,计时器停。

`DouDizhuPacing` 的预算按 §3 先估:发牌 3.0、重发 2.4、叫分 0.6、定地主 2.2、出牌 0.7(顺子 / 连对 1.2、飞机 1.6、炸弹 2.0、王炸 2.5)、
不出 0.4、清桌 0.4、换人 / 托管 0(并行)、一手结束 3.0(春天另加 1.5)、散局提示 0、断线 0.8、结算 3.0;导演实测后可以收紧,每段演出不得超过预算。

### 6.8 GameMode 与其他按玩法分支的地方

- 吹牛骰子分支已定下 `GameMode.DOU_DIZHU = "dou_dizhu"`、label「斗地主」、`DOU_DIZHU_PLAYERS` 3(`min_players` = `max_players` = 3,`summary`「斗地主 · 3 人」)
  和 `MENU_ORDER` 里的格子;本分支把它加进 `ALL = [LIARS, BOMB_CAT, LIARS_DICE, DOU_DIZHU, HOLDEM, SHORT_DECK]` 并加 `is_dou_dizhu(mode)`,
  **主菜单格子随之亮起**(选了会进占位牌桌,见 6.10)。`allows_late_join` 为假。
- 开局人数:`LobbyModel.can_start(min_players := Protocol.MIN_PLAYERS)` 新增参数,`NetworkManager.can_start()` 传 `GameMode.min_players(game_mode)`;
  等待厅状态行「至少 N 人才能开局」也按玩法(`lobby.gd`)。上限照旧由 `check_join` 按 `GameMode.max_players` 把关(第 4 人「房间已满(3/3)」)。
- 桌子:`SeatLayout.table_radius_for` 不用改,斗地主落在默认分支 = 骗子酒馆的桌子(`TABLE_RADIUS`);`main.apply_table_mode` 照常摆烛台、不摆目标牌立牌。
- 默认房名「X 的斗地主」(吹牛骰子分支已写)。说明书 `RulebookContent.book_for_mode` 暂时回退骗子酒馆那本(阶段二加「斗地主」一本)。

### 6.9 网络

- 开局:`start_game` → `_new_session(game_mode)` → `DouDizhuSession`(分支放在吹牛骰子旁边)。没有新 RPC,意图走现有的 `rpc_session_intent`,
  `_handle_session_rpc` 通用地调 `_session.validate_intent`(没有按玩法的分支)。
- 协议号仍为 **v9**(吹牛骰子分支升的,两个新玩法共用;§2 写的 v8 已过时),本分支没动;`project.godot` 没动。
- 每批之后 `_sync_all` 照旧:公共视图全员、私有视图发给 `viewers()`(没离开的座位)。

### 6.10 临时路由(阶段二要替换)

`main._show_table`:斗地主房间暂时进 `_dou_dizhu_placeholder()`——居中一块「斗地主的牌桌还在布置中」+「离开房间」按钮,不会崩。
规则与网络照常跑:每步到点由房主代打,连续超时进托管,一手打完 5 秒后自动开下一手,一直打到有人离开(没有散局按钮与结算界面)。
阶段二把这一分支换成 `DouDizhuScreen.new(self)` 并删掉占位函数(代码里有 `TODO(斗地主阶段二)`)。

### 6.11 阶段二要做的

1. 牌桌屏幕 `DouDizhuScreen`:接 `Net.game_events` / `state_public_updated` / `state_private_updated` / `intent_rejected`(toast `DdzState.ERROR_MESSAGES`),
   出手一律 `Net.submit_session_intent(...)`,房主「散局」按钮调 `Net.end_poker_session()`;替换 `main._show_table` 的占位分支。
2. 导演:按 6.3 的事件演出(底牌翻开飞进地主手里、出牌摊在面前、`trick_cleared` 清桌、炸弹 / 王炸 / 飞机 / 顺子连对 / 春天特效、倍数跳动),
   每段时长不超过 `DouDizhuPacing` 的预算(参照 `test_poker_director_pacing` / `test_bomb_cat_director` 加检查)。
   私有视图比演出先到:按 `hand` 等演到对应的 `hand_started` / `landlord` 再换手牌。
3. HUD:手牌条(下标 = 私有视图 `cards`)、点选 / 拖动连选;「出牌」「不出」(`can_pass`)「提示」(循环 `hints`)「重选」;叫分按钮按 `bid_options` 置灰;
   「托管 / 取消托管」(`trustee` 意图,状态看私有视图 `trustee`);左上底分 `base`、倍数 `multiplier`、底牌 `bottom`、地主 `landlord`、
   剩 1–2 张报警(`players[].hand_count`);倒计时 `turn_time_left`;两手之间画 `last_hand`,结算画 `results`。快捷键见 §3。
4. 牌面:52 张用 `DdzHand.poker_card(c)` 换德州牌面,补大王 / 小王两张原创插画;地主帽 / 草帽;说明书「斗地主」一本(牌型名取 `DdzHand.TYPE_NAMES`)。
5. 机器人(`debug_flags.gd`:叫分随机、出 `hints[0]`,能跟就跟、偶尔不出)与 `tools/lan_smoke.sh` 的斗地主一局(正好 3 端,房主 `--hands=N`,
   核对三端结算一致、总和为 0);`tools/shot.gd --dou-dizhu-showcase`。挑合法意图可以照抄 `tests/test_dou_dizhu_fuzz.gd` 的 `_step`。

## 7. 实施记录(阶段二:表现层,2026-10-10)

阶段二只加表现,没改规则引擎、会话、视图与协议(仍是 v9),没动 `project.godot`。§6 的事件 / 视图 / 意图字段原样使用。

### 7.1 文件

- 3D(`src/world/dou_dizhu/`):
  - `ddz_joker_painter.gd`(`DdzJokerPainter`,继承德州的 `PokerFacePainter`)与 `ddz_joker_faces.gd`(`DdzJokerFaces`):两张王的牌面。
  - `ddz_card_3d.gd`(`DdzCard3D`,继承 `Card3D`):斗地主牌 id 的 3D 牌,-1 = 德州牌背。
  - `ddz_layout.gd`(`DdzLayout`):底牌、出牌行、「不出」牌子、牌扇顺序、越肩机位与自己牌扇的摆法(纯函数)。
  - `ddz_cards.gd`(`DdzCards`):牌层的全部动画与对账。
  - `ddz_hats.gd`(`DdzHats`)与 `ddz_props.gd`(`DdzProps`):身份帽、小火箭、纸飞机、花瓣、报警徽章的程序网格。
  - `ddz_fx.gd`(`DdzFx`,继承 `BombCatFx`):特效层。
- 界面(`src/ui/dou_dizhu/`):`dou_dizhu_screen.gd`(main 里 preload 成 `DouDizhuScreen`)、`ddz_director.gd`、`ddz_hud.gd`、
  `ddz_hand_strip.gd`、`ddz_nameplate.gd`、`ddz_settlement.gd`、`ddz_screen_state.gd`(纯逻辑)、`ddz_bot.gd`。
- 说明书:`src/ui/rulebook/rulebook_dou_dizhu.gd` + 新块类型 `ddz_combos` / `ddz_order`(`rulebook_blocks.gd`)。
- 工具:`tools/dou_dizhu_showcase.gd`(`DouDizhuShowcase`)、`tools/ddz_faces_sheet.gd`;`shot.gd --dou-dizhu-showcase`、
  `perf_probe.gd --showcase=dou_dizhu`、`perf_budget.gd` 的 `ddz_seat` / `ddz_fp` / `ddz_overview`、`camera_views.gd` 的 `ddz_fp`。
- 共享文件里的小改动(都只在斗地主时生效):
  - `main.gd`:路由换成 `DouDizhuScreen`、删掉占位函数;`_exit_tree` 释放 `DdzJokerFaces` / `DdzProps`;翻到斗地主那本说明书时后台生成牌面。
  - `lobby.gd`:斗地主等待厅后台生成牌面。
  - `card_faces.gd` / `card_3d.gd`:认得两张王的牌面值。
  - `table_world.gd`:新增 `third_person_override`(见 7.3),`clear_poker` 复原。
  - `debug_flags.gd`:斗地主机器人、截图标记、`--hands`、`DDZ_HAND_OVER` / `DDZ_RESULTS` 日志行。
  - `tools/lan_smoke.sh`:斗地主一局。`sfx.gd`:8 个音效。`rulebook_content.gd`:斗地主那本(合并吹牛骰子阶段二后是第五本;页签放不下时标题旁的英文副标题省略)。

### 7.2 两张王

- 牌面值 `DdzJokerFaces.SMALL = 60`、`BIG = 61`,落在德州(8–59)与骗子酒馆(-1–3)之外。`face_kind(c)`:王 → 这两个值,其余 → `DdzHand.poker_card(c)`。
  `CardFaces.texture` 与 `Card3D.material_for` 认得它们(德州的单张材质、背面德州牌背),3D 牌的 `kind` 就是牌面值,所以悬停大图不用改。
- 大王:戴五齿大金冠(红宝石 + 青绿宝石 + 白貂毛边)的大熊猫国王,莓红长袍、白貂毛领,举着顶端一颗星的金权杖,背后一圈放射光;
  小王:歪戴三齿小金冠的小浣熊王子,黑眼罩、白眉毛、白吻部,藏青小礼服、金腰带、小领结,一圈一圈的大尾巴,举星星小魔杖。
  纸、内框、描边、眼睛、腮红、金冠都用德州 J/Q/K 的画法与颜色。
- 角标是竖排的「大 / 王」「小 / 王」:**自己画的圆头粗笔画**(`glyph_strokes`),不用字体——离屏视口里系统字体的中文字形不可靠(第一版画出了豆腐块),
  德州的点数也是同样的理由自己画。大王莓红、小王藏青墨,下面一颗小星,右下角绕牌心转 180°。
- 尺寸、MSAA、出血底、mipmap 都同德州(`PokerFaces.SIZE` 320×465);两张一批画完,只在斗地主的等待厅、牌桌、说明书里生成;
  无头模式退化成每种一份的纯色小纹理(缓存,不每次新建)。验收图 `tools/ddz_faces_sheet.gd`(全尺寸 + 66×96 手牌条 + 38×55 说明书尺寸)。

### 7.3 牌桌、机位与布局

- 骗子酒馆的小桌、3 个座位均匀分布、点烛台、不摆目标牌立牌(`apply_table_mode` 本来就这样)。
- **越肩机位**:骗子酒馆的越肩机位里,自己的头(加上帽子)正好挡住桌面偏左那一块——左边那位对手面前的出牌行整个看不见。
  斗地主把 `TableWorld.third_person_override` 设成 `DdzLayout.THIRD_PERSON = (右移 0.95, 高 2.45, 座位外 1.05)`(骗子酒馆是 0.72 / 2.2 / 1.2),
  自己落在画面左下,三行牌都露出来。只影响本机、只在斗地主牌桌上,拆台时复原;第一人称不受影响。
- 出牌行:对手的在各自面前(离桌心 0.36,再往桌子里侧挪 0.1),本机的在 (0.11, 0.29);一行最宽 0.5 米(超了就挤紧)、牌放大 1.25 倍,
  **牌顶翘起 24°** 朝向本机(平躺在远处的牌看不清点数),牌底边贴着桌布。摆放顺序:同点数张数多的在前(三带一的三张、飞机机身先摆),同张数大的在前。
- 发牌处 / 三张底牌在 (0.07, 0.02)(往右挪,避开自己的头);底牌扣着,定地主时原地翻开(同样翘起)亮 0.35 秒再飞进地主手里——
  进了别人手里又翻回牌背。
- 牌扇:别人的用炸弹猫的扇形(10 张以上压缩);自己的大的在左(手牌按 id 升序存放,第 i 张摆在第 n-1-i 个位置,同手牌条)。
  越肩时自己的牌扇缩到 0.55、往右下挪(20 张的扇子不挡桌面,2D 手牌条才是主入口),第一人称拿在镜头右侧偏下(`FP_FAN_CAM`)。

### 7.4 身份帽

- 定地主时所有人一起「啵」地戴上(从小弹大、往下落):地主是藏青缎面的小瓜皮帽(六道金帽缝、红绒结、金边、正前方翠绿帽正),
  农民是宽檐草帽(深一档的草编纹、红帽带、别一朵小雏菊)。新的一手开始时摘掉,酒客自己的帽子放回。
- 挂在酒客帽子的枢轴(`Head/Hat`)下:跳舞抛帽也带着它;原来的 `HatMesh` 只是藏起来。帽口贴着颅骨上部一圈,按 `Patron.skull_ellipsoid()` 的半轴缩放
  (网格按颅骨半径 0.122 建),八个物种都戴得正。挂在头下面,所以第一人称藏头时只投影不渲染(戴帽时头已经藏着也会被 `node_added` 接住)。
- 对账时按视图的身份补戴 / 摘掉(不弹),退场时全部摘掉。

### 7.5 导演与节奏(每段都在 `DouDizhuPacing` 的预算里,`test_ddz_director` 核对,每个 await 算一帧余量)

| 事件 | 演出 | 实际(最坏) | 预算 |
|---|---|---|---|
| `hand_started` | 摘帽复位、收上一手的牌(和等私有手牌同时)、洗牌声、3 张底牌扣到桌心、每人 17 张轮流发 | 0.4 + 2.05 | 3.0 |
| `redeal` | 「重新发牌」、收牌、再发(更快) | 0.4 + 1.7 | 2.4 |
| `bid` | 头顶气泡「1 分 / 不叫」、木鱼「笃」或敲桌、叫分的人伸手 | 0.45 | 0.6 |
| `landlord` | 聚光灯、所有人看向地主、帽子、底牌翻开亮一下再飞进手里 | 1.1 + 0.3 | 2.2 |
| `played` | 牌飞到出牌行(每张错开 8 毫秒)、拍牌声、气泡写点数或牌型 | ≤ 0.48 + 0.1 | 0.7 |
| 顺子 / 连对 | + 一串牌从左到右跳一下亮一下、「顺子!」 | ≤ 0.55 + 0.55 | 1.2 |
| 飞机 | 0.2 秒后小纸飞机起飞,从出牌的人那边掠过桌子远端 | 0.2 + 1.05 + 0.1 | 1.6 |
| 炸弹 | + 烟云、星星、冲击波、「炸弹!」「×N」、闪光、震屏、出牌的人拍桌 | 0.42 + 1.2 | 2.0 |
| 王炸 | + 小火箭冲上去(0.55)炸成三簇烟花(火星用礼炮的加色软圆点,泛光晕开)、「王炸!」 | 0.41 + 1.42 | 2.5 |
| `passed` | 气泡「不出」、敲桌两下、他面前上一手收走、立「不出」牌子 | 0.3 | 0.4 |
| `trick_cleared` | 三行牌收向桌心缩没、「不出」牌子收起 | 0.32 | 0.4 |
| `hand_over` | 别人的剩牌摊开(0.5)、宣告输赢与「底分 × 倍数」、头顶飘分、赢家欢呼、地主输了生气 / 农民输了发愁、右侧结算摘要 | 2.7 | 3.0 |
| 春天 | + 花瓣飘落、「春天!」、风铃、倍数跳动 | + 1.4 | + 1.5 |
| `player_left` | 日志、气泡「……」、收铭牌 | 0.6 | 0.8 |
| `session_over` | 第一名(并列都算)跳舞、旁人鼓掌、礼炮彩纸,镜头环绕他;之后弹结算面板 | 2.4 | 3.0 |

`turn` / `trustee` / `ending` 不等(和上一段并行)。第一次发牌前最多等 10 秒牌面生成(德州同样的豁免;等待厅里通常早已生成完)。
倍数的数字由导演在炸弹 / 王炸 / 春天那一拍跳动(HUD 平时只改数字不跳)。只剩 1–2 张时头顶报警徽章(一闪一闪,写「剩 N 张」)+ 铭牌张数变红闪烁 + 日志。

### 7.6 私有视图快照

私有视图比演出先到,而重发时 `hand` 不变。`DdzScreenState.apply_private` 在公共视图是叫分阶段时按 `"第几手:第几次发牌"` 记一份手牌快照
(公共视图总是先到,`deal` 取自它),`hand_started` / `redeal` 的发牌按快照亮面;定地主时自己的底牌直接并进手牌;出牌按事件里的牌 id 拿走。
演完以私有视图为准。

### 7.7 HUD 与操作

- 左上:「斗地主 · 第 N 手」、底分、倍数、地主是谁、3 张底牌小图(叫分时是牌背,定地主后亮面,可悬停放大)、一行状态。
- 底部:手牌条(66×96,大的在左,不同点数之间多一道 7 像素的缝,20 张最宽 780);点一下选中 / 取消,按住拖过一串按第一张的新状态一起选上或取消
  (拖回来恢复),右键清空;3D 牌扇里的牌也能点。按钮行:出牌阶段「不出」(有上家才出现)「重选」「提示」「出牌」+ 选中那手的判定
  (「顺子 · 5 张」绿 /「压不过上家的『对子』」红);叫分阶段「不叫 / 1 分 / 2 分 / 3 分」按 `bid_options` 置灰;不是自己时是「等待 X 出牌…」横幅;
  右边倒计时环(叫分按 15 秒、出牌按 30 秒画)。左下自己的身份签、累计分、张数与「托管 / 取消托管」,托管中按钮行上方一条横幅。
- 「提示」按 `hints` 顺序循环(提示列表变了就从头数);出牌前本地先用 `DdzHand.classify` / `match_lead` 核对,不成牌型或压不过就 toast,不发意图。
- 快捷键:Enter 出牌、空格或 P 不出(叫分时 = 不叫)、H 提示、R 重选、叫分时 0–3。不占 T / Q / G / V / WASD / Esc / F1;
  **快捷语面板或九宫格开着时斗地主的快捷键一律不抢**(不只数字键)。Esc 确认离开;房主「散局」确认后走 `Net.end_poker_session()`。
- 一手打完右侧显示这一手的结算(谁赢了、底分 × 倍数 = 一份、炸弹几个、春天,每人得失与累计),下一手开始时收起。
- 结算面板 `DdzSettlement`:德州散局面板的版式(右侧停靠、左边留给跳舞的第一名),三列名次(同分同名次)/ 名字(离开的标「已离开」)/ 累计分,
  标题「散局结算」或「牌局提前结束」,一行写打了几手、为什么结束;房主「回到等待厅」,其他人「离开房间」。

### 7.8 音效(`Sfx`,全部程序合成)

`card_slap` 拍牌、`knock` 不出 / 不叫时敲桌两下、`bid` 叫分的木鱼、`rocket` 火箭升空、`firework` 烟花、`plane` 纸飞机、`chime` 春天风铃、`alarm` 报警;
炸弹沿用炸弹猫的 `boom`,发牌、翻牌、收牌沿用已有的。

### 7.9 机器人与冒烟

- `DdzBot`(`--bot` 与无头流程测试共用):叫分多半不叫、偶尔叫个更高的;出牌多半按一下「提示」出最小的,偶尔多按几下;能不出时 20% 不出;
  偶尔先点一张再重选。全部走牌桌的公开入口。
- `debug_flags`:轮到自己想 0.6–1.6 秒再出手;房主 `--hands=N` 在第 N 手开始时散局;每手打完打印 `DDZ_HAND_OVER`,结算时打印
  `DDZ_RESULTS {pid: 分, …} sum=…`(按 pid 排序)。
- `lan_smoke.sh` 的斗地主一局:正好 3 端(房主 + 发现 + 直连),`--hands=3`;核对三端都正常退出、没有脚本错误、都收到另外两人的快捷对话、
  房主打完 3 手、三端的 `DDZ_RESULTS` 完全一致且总和为 0。`SKIP_DOU_DIZHU=1` 跳过。

### 7.10 测试(全部无头)

`test_ddz_screen_state`(事件 / 视图推进、快照、提示与叫分选项校验、选中判定、排名、摘要、结算面板)、
`test_ddz_screen`(快捷键与面板抢键、点选 / 拖选 / 重选、提示循环、按钮置灰、等回执、托管)、
`test_ddz_director`(每种事件与每种牌型的预算、特效映射、特效建出来且演完自释放)、
`test_ddz_world`(两张王的牌面值 / 尺寸 / mipmap / 材质 / 悬停大图、帽子戴摘与按颅骨缩放与第一人称、牌层只亮已公开的牌、布局)、
`test_rulebook_dou_dizhu`(每组示例真的是那种牌型)、`test_ddz_screen_flow`(真会话打 3 手散局:牌数、隐藏信息、帽子、结算一致),
另在 `test_perf_budget` / `test_debug_flags` / `test_rulebook_content` 补了斗地主的条目。

### 7.11 偏差与取舍

- 越肩机位为斗地主单独抬高、右移(7.3),这是唯一改到共享机位函数的地方(加了一个默认为空的覆盖字段)。
- 2D 手牌条与牌扇大的在左(和多数斗地主一致);意图里的下标照旧是私有视图的升序下标,只是显示反过来。
- 叫分阶段左上就画 3 张牌背(提示底牌还扣着),定地主后换成亮面。
- 没有给斗地主做观战机位(不支持中途加入,也没有出局观战)。
