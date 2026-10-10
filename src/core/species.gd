class_name Species
# 酒客物种目录(纯逻辑,网络层与场景层共用)。下标就是网络上传的值,协议 v5 起冻结:
# 以后加物种只能追加到末尾,而且要升协议版本。外观在 PatronParts / 物种配方里。
# 2026-10-10 追加熊猫(8)、企鹅(9),协议升到 v10(v9 客户端不认识这两个下标)。

const IDS := ["fox", "bear", "pig", "cat", "turtle", "alpaca", "monkey", "crocodile", "panda", "penguin"]
const LABELS := ["狐狸", "熊", "猪", "猫", "乌龟", "羊驼", "猴子", "鳄鱼", "熊猫", "企鹅"]
# 角色设定(挑选面板与提示里和物种名一起显示)
const ROLES := ["老千绅士", "酒馆老板", "铁路司炉", "独行枪手", "老淘金客", "披毯客", "酒馆跑堂", "亡命徒", "竹林侠客", "南极来客"]
# 头像回退图上的单字(头像还没烘好或无头时显示;熊猫的「熊」「猫」都被占了,用它的竹子)
const GLYPHS := ["狐", "熊", "猪", "猫", "龟", "驼", "猴", "鳄", "竹", "鹅"]
const UNASSIGNED := -1


static func count() -> int:
	return IDS.size()


static func is_valid(value: Variant) -> bool:
	# 来自网络或设置文件的值不可信:必须是整数且在范围内
	return typeof(value) == TYPE_INT and value >= 0 and value < IDS.size()


static func sanitize(value: Variant) -> int:
	return value if is_valid(value) else UNASSIGNED


static func title(index: int) -> String:
	# 「狐狸 · 老千绅士」:提示与挑选面板用
	return "%s · %s" % [LABELS[index], ROLES[index]] if is_valid(index) else "还没有形象"


static func index_of(id: String) -> int:
	return IDS.find(id)


static func first_free(taken: Array) -> int:
	# 同桌不撞脸:取第一个没人用的;全被占(人数超过物种数)时才轮流重复
	for i in IDS.size():
		if not taken.has(i):
			return i
	return posmod(taken.size(), IDS.size())
