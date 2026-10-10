class_name LobbyModel
# 等待厅名单(仅房主持有):加入校验、准备状态、形象分配、开局条件。座位顺序 = 加入顺序。
# 形象(物种下标)先到先得、同桌不撞脸:想要的空着就给,被占时没有形象的分第一个空着的、已有的保持不变。


const HOST_ID := 1
const DEFAULT_NAME := "酒客"
const IN_GAME_REASON := "游戏已开始,请等这一局结束"
const WINDING_DOWN_REASON := "牌局正在散局,请稍后再来"

var _order: Array = []
var _members := {}  # peer_id -> {"name": String, "ready": bool, "species": int}


func add_host(host_name: String, species := Species.UNASSIGNED) -> void:
	# 房主的首选当场生效;非法值(没有偏好)回退第一个物种
	_order = []
	_members = {}
	_insert(HOST_ID, host_name, true)
	request_species(HOST_ID, species)


func check_join(version: int, in_game: bool, mode: String, accepting_late: bool) -> String:
	# 返回空串表示允许加入,否则为拒绝原因。判定顺序固定:
	# ① 版本必须最先判断:主菜单靠「版本」字样去问房主要更新,对局中、满员的房间也得先报这个;
	# ② 已开局时只有正在接受中途入座的德州牌局能进(散局中或已结算的德州另有文案);
	# ③ 人数按玩法上限,只数已完成握手、仍连着的等待厅成员
	if version != Protocol.VERSION:
		return "版本不匹配(房主 v%d / 你 v%d),请更新游戏" % [Protocol.VERSION, version]
	if in_game and not accepting_late:
		return WINDING_DOWN_REASON if GameMode.allows_late_join(mode) else IN_GAME_REASON
	var cap := GameMode.max_players(mode)
	if _members.size() >= cap:
		return "房间已满(%d/%d)" % [_members.size(), cap]
	return ""


func add_member(id: int, raw_name: String) -> void:
	_insert(id, raw_name, false)


func remove(id: int) -> bool:
	# 只释放离开者的形象,别人的都不变(撞车拿到候补形象的人不会自动换回首选)
	if id == HOST_ID or not _members.has(id):
		return false
	_members.erase(id)
	_order.erase(id)
	return true


func has(id: int) -> bool:
	return _members.has(id)


func size() -> int:
	return _members.size()


func set_ready(id: int, ready: bool) -> bool:
	if id == HOST_ID or not _members.has(id):
		return false
	_members[id]["ready"] = ready
	return true


func reset_ready() -> void:
	# 不碰形象:再来一局时形象不变
	for id in _members:
		_members[id]["ready"] = id == HOST_ID


func can_start(min_players := Protocol.MIN_PLAYERS) -> bool:
	# min_players:本房玩法的开局人数下限(GameMode.min_players,斗地主为 3;上限由 check_join 把关)
	if _members.size() < min_players:
		return false
	for id in _members:
		if not _members[id]["ready"]:
			return false
	return true


func request_species(id: int, wanted: int) -> bool:
	# 先到先得:想要的形象空着就给;被别人占了(或下标非法)时,
	# 还没有形象的分第一个空着的,已经有形象的保持不变。返回名单是否变了(变了才广播)
	if not _members.has(id):
		return false
	var current: int = _members[id]["species"]
	var taken := _taken_except(id)
	var next := current
	if Species.is_valid(wanted) and not taken.has(wanted):
		next = wanted
	elif current == Species.UNASSIGNED:
		next = Species.first_free(taken)
	if next == current:
		return false
	_members[id]["species"] = next
	return true


func assign_unassigned() -> bool:
	# 开局前兜底:还是 -1 的(形象请求没到或被丢弃)按加入顺序分第一个空着的。返回名单是否变了
	var changed := false
	for id in _order:
		if _members[id]["species"] == Species.UNASSIGNED:
			changed = request_species(id, Species.UNASSIGNED) or changed
	return changed


func species_of(id: int) -> int:
	return _members[id]["species"] if _members.has(id) else Species.UNASSIGNED


func seat_order() -> Array:
	return _order.duplicate()


func names() -> Dictionary:
	var out := {}
	for id in _order:
		out[id] = _members[id]["name"]
	return out


func view() -> Array:
	var out := []
	for id in _order:
		out.append({
			"pid": id,
			"name": _members[id]["name"],
			"ready": _members[id]["ready"],
			"is_host": id == HOST_ID,
			"species": _members[id]["species"],
		})
	return out


func _insert(id: int, raw_name: String, ready: bool) -> void:
	_members[id] = {"name": _unique_name(raw_name), "ready": ready, "species": Species.UNASSIGNED}
	_order.append(id)


func _taken_except(id: int) -> Array:
	var taken := []
	for other in _members:
		var s: int = _members[other]["species"]
		if other != id and s != Species.UNASSIGNED:
			taken.append(s)
	return taken


func _unique_name(raw_name: String) -> String:
	var base := Protocol.sanitize_name(raw_name)
	if base == "":
		base = "%s %d" % [DEFAULT_NAME, _order.size() + 1]
	var taken := {}
	for id in _members:
		taken[_members[id]["name"]] = true
	if not taken.has(base):
		return base
	var n := 2
	while taken.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]
