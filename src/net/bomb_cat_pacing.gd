class_name BombCatPacing
# 炸弹猫演出预算(秒)。房主把它加到回合 / 窗口 / 塞回 / 给牌计时上,保证玩家看完动画后仍有完整的时间。
# 阶段二的导演(BombCatDirector)每段演出的实际时长必须不超过这里的预算;预算按设计稿 §3.1 的演出先估,
# 导演实测后可以收紧(预算比动画长多少,轮到行动者时倒计时就多出多少秒)。


const INTRO := Pacing.INTRO          # 开场运镜:客户端进入牌桌先播它
const ROUND_STARTED := 3.0           # 发牌:每人 8 张飞到手里,牌堆落到桌心
const PLAYED := 0.8                  # 牌从手里飞到弃牌堆、翻面,头顶气泡
const NOPED := 0.7                   # 拍桌,「不行!」盖在弃牌堆上
const WINDOW_RESOLVED := 0.3         # 窗口收起:作废的牌打个叉 / 生效的牌亮一下
const EFFECT_SKIP := 0.85           # 侧身溜走、扬尘、速度线、「嗖~」、一串小脚印(2026-10-10 道具效果加强:0.3 → 0.85)
const EFFECT_PASS_TURNS := 1.15      # 平底锅转着圈飞过去「当!」地敲在下家头上、星星、×N 徽章(0.6 → 1.15)
const EFFECT_PEEK := 1.5             # 举放大镜、牌堆顶三张浮成发光扇面(只有自己看到正面),别人看他捂嘴偷乐(1.2 → 1.5)
const EFFECT_SHUFFLE := 1.5          # 牌堆炸成小龙卷风再叠回去、弹一下(1.0 → 1.5)
const EFFECT_TRANSFER := 1.0         # 讨要:系着蝴蝶结的牌拖着小爱心飞过去,落手时爱心「啵」(0.9 → 1.0)
const EFFECT_SNACK_TRANSFER := 1.4   # 抽牌 / 点名:零食先蹦到桌上,牌再拖着金光飞向抽牌的人
const EFFECT_MISS := 0.5             # 讨要 / 抽牌 / 点名落空:摊手
const GIVE_REQUESTED := 0.8          # 「XX 向你讨要一张牌」:讨要的人双爪合十、狗狗眼、飘爱心(0.4 → 0.8)
const DREW := 0.6                    # 牌从牌堆滑到手里
const BOMB_DRAWN := 2.0              # 所有人吓一跳、炸弹翻开冒火花、心跳与镜头推近
const DEFUSED := 1.6                 # 手忙脚乱剪线,「咔嚓」
const REINSERTED := 1.0              # 炸弹猫踮着脚溜回牌堆、从侧面钻进去(看不出塞在哪)(0.8 → 1.0)
const EXPLODED := 3.5                # 轰:闪光、烟团、震屏、黑脸蚊香眼、帽子飞走
const PLAYER_LEFT := 0.8             # 断线出局:淡出
const TURN_PASSED := 0.3             # 镜头 / 高亮移到下一位
const MATCH_OVER := 3.0              # 结算面板之前的谢幕

# 这些事件会让客户端在演出结束时把回合交给某人(重新起算完整回合时间)
const TURN_EVENTS := ["turn_passed", "round_started"]


static func estimate(events: Array) -> float:
	var total := 0.0
	for ev in events:
		match ev.get("type", ""):
			"round_started":
				total += ROUND_STARTED
			"played":
				total += PLAYED
			"noped":
				total += NOPED
			"window_resolved":
				total += WINDOW_RESOLVED
			"effect":
				total += effect_time(ev)
			"give_requested":
				total += GIVE_REQUESTED
			"drew":
				total += DREW
			"bomb_drawn":
				total += BOMB_DRAWN
			"defused":
				total += DEFUSED
			"reinserted":
				total += REINSERTED
			"exploded":
				total += EXPLODED
			"player_left":
				total += PLAYER_LEFT
			"turn_passed":
				total += TURN_PASSED
			"match_over":
				total += MATCH_OVER
	return total


static func effect_time(ev: Dictionary) -> float:
	match ev.get("kind", ""):
		BombCatCard.SKIP:
			return EFFECT_SKIP
		BombCatCard.PASS_TURNS:
			return EFFECT_PASS_TURNS
		BombCatCard.PEEK:
			return EFFECT_PEEK
		BombCatCard.SHUFFLE:
			return EFFECT_SHUFFLE
		BombCatCard.BEG:
			return EFFECT_TRANSFER if ev.get("got", false) else EFFECT_MISS
		"steal", "request":
			return EFFECT_SNACK_TRANSFER if ev.get("got", false) else EFFECT_MISS
	return 0.0


static func starts_turn(events: Array) -> bool:
	for ev in events:
		if TURN_EVENTS.has(ev.get("type", "")):
			return true
	return false


static func has_event(events: Array, type: String) -> bool:
	for ev in events:
		if ev.get("type", "") == type:
			return true
	return false
