# 21 点(Blackjack)设计稿

2026-10-12 用户要求「增加一个 21 点游戏」。按用户习惯(见记忆 decide-autonomously)由 Claude 自定规则与表现,做完汇报。

## 1. 玩法定位

- 玩法 id `blackjack`,菜单名「21点」,全名「21 点」。**1–7 人**,和酒馆庄家对赌(庄家由房主电脑按固定规则代打,桌上没有庄家酒客,只有桌心的庄家牌位与牌鞋)。
- 现金局,结构照德州:入座领 2000 筹码,输到不够最小下注可以再领;开打后新玩家可以中途入座(下一局登场);房主随时「散局」,打完当前这一局按盈亏排名结算(复用德州结算面板与庆祝)。
- 一个人也能开(min 1 人):21 点本来就是和庄家对赌。第一版不做机器人、托管与 AI。

## 2. 规则(常量都在 `BjRules`)

| 项 | 取值 |
|---|---|
| 牌鞋 | 6 副 312 张;每局开始时剩不到 1/4(78 张)就重新洗牌(事件带 `shuffled`) |
| 下注 | 20 的倍数,20–1000,且不超过筹码 |
| 发牌 | 下注的人每人一张 → 庄家明牌 → 每人第二张 → 庄家暗牌(美式,有暗牌) |
| 庄家看牌 | 明牌是 A 或 10 点时先看暗牌;是 21 点就立即翻开结算(玩家 21 点则平手,其余输原注) |
| 黑杰克 | 前两张 A + 10 点,赔 3:2;分牌后的 A+10 只算 21 点 |
| 玩家动作 | 要牌、停牌、加倍(前两张时,再押一份、只再要一张)、分牌(两张点数相同,最多分成 4 手;A 只能分一次且各只补一张)、投降(原始前两张时,收回一半) |
| 分牌后 | 可以加倍;到 21 自动停牌 |
| 庄家 | 所有玩家手都结束后翻暗牌;还有没爆、没投降、不是黑杰克的手时要牌到 17,**所有 17 点都停**(S17) |
| 不设 | 保险、平赔(even money)、边注 |
| 回合限时 | 下注 15 秒(到点没下注的人这局不玩);每手决策 20 秒(到点停牌) |
| 挂机 | 连续 2 次超时(下注或决策都算)从下一局起离座,点「回到牌桌」回来 |
| 离开 / 断线 | 下注阶段已押的注退回;已发牌的手照常停牌、和庄家比,本局结束后带着筹码离场 |

## 3. 流程与事件(房主权威,`BjTable` 状态机)

阶段:`idle`(两局之间)→ `betting`(同时下注,计时 15 秒)→ `playing`(按座位轮流,每手 20 秒)→ 庄家 → 结算 → `idle`;散局后 `over`。

两局之间:房主演完这一批再停 `ROUND_GAP` 秒自动开下一局(没人能下注时等,有人再领 / 回座后再开)。

事件(都带 `type`):`round_started`{round, seats, shuffled, shoe_left}、`bet_placed`{pid, amount, stack}、`bet_skipped`{pid, timeout}、
`dealt`{order, hands{pid:[2 张]}, dealer_up}、`peek`{blackjack}、`turn`{pid, hand}、`hit`/`double`{pid, hand, card, total, soft, bust, (bet, stack)}、
`stand`{pid, hand, timeout}、`split`{pid, hand, cards:[[..],[..]], bet, stack}、`surrender`{pid, hand, refund, stack}、
`dealer_reveal`{card, cards, total, soft}、`dealer_hit`{card, total, soft, bust}、`settled`{hands:[{pid, hand, outcome, bet, payout}], stacks, dealer_total, dealer_bust}、
`round_over`{round, busted, stacks}、`rebuy`、`away`、`sit_in`、`player_joined`、`player_left`、`ending`、`session_over`{results}。

所有牌都是明牌(包括庄家明牌),只有庄家暗牌在翻开前不进任何视图或事件,所以**没有私有视图**。

意图走字典入口 `rpc_session_intent`:`{"kind": "bet", "amount": n}` / `skip` / `hit` / `stand` / `double` / `split` / `surrender` / `rebuy` / `sit_in`。

公共视图:`mode, round, phase, shoe_left, shoe_size, limits[min,max,unit], dealer{cards, hidden, total, soft}, current{pid, hand}|null, actions{...}|{}, seats, players[{pid, name, stack, status, left, buyins, net, bet, hands[{cards, bet, total, soft, done, outcome, doubled, split}], decided}], turn_time_left, ending, results`。

玩家状态:`waiting`(本局还没下注 / 两局之间)、`bet`(已下注)、`skip`(这局不玩)、`playing`(本局发到牌)、`busted`(不够最小下注)、`away`(离座)。

## 4. 表现

- 桌子:用德州那张大桌(半径 1.45),不摆烛台;桌心靠里是庄家牌位(牌朝本机斜立,同德州公共牌架的做法)、左边牌鞋、右边弃牌托盘。
- 玩家的牌平放在自己座位前的桌面上、牌面朝上(按本机视角正立),分牌后几手沿桌沿并排;每手前面一摞下注筹码;筹码堆在右手边(同德州)。
- 庄家赔付:赢的手从桌心飞来一摞筹码,再连本带利滑回筹码堆;输的手筹码滑向桌心消失;平手滑回。
- 铭牌:名字 + 筹码 + 这一局的状态(「下注 100」「19 点」「爆牌」「21点!」)。HUD 左上庄家的牌与点数,左下自己的几手牌与点数,底部中间下注 / 决策控件,右下日志。
- 21 点(黑杰克)大字宣告与金光,爆牌红字,庄家爆牌全桌欢呼。

## 5. 协议

协议升到 v12:旧客户端不认识 `blackjack` 玩法 id,不能同桌。RPC 表不变(用已有的 `rpc_session_intent`)。
