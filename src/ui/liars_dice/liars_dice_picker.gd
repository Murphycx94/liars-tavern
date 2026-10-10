class_name LiarsDicePicker
extends RefCounted
# 出价器的选择(纯逻辑,HUD 只负责画):个数 count(−/+ 与 ↑↓)、点数 face(2–6 六个按钮与数字键)。
# 合不合法一律问规则引擎 LiarsDiceState.bid_error(count, face, 当前一口, 场上总数),出价器据此置灰;
# 默认值取 LiarsDiceState.min_raise(加不上去时停在当前这一口,只能「开!」)。
# 调个数时如果选着的点数在新个数下不合法,自动换成这个个数下最小的合法点数(没有就不动,「加注」置灰)。


var count := 1
var face := LiarsDiceState.MIN_BID_FACE


func reset(current: Dictionary, total: int) -> void:
	var raise := LiarsDiceState.min_raise(current, total)
	if not raise.is_empty():
		count = raise["count"]
		face = raise["face"]
	elif not current.is_empty():
		count = current["count"]
		face = current["face"]
	else:
		count = 1
		face = LiarsDiceState.MIN_BID_FACE


func error(current: Dictionary, total: int) -> String:
	return LiarsDiceState.bid_error(count, face, current, total)


func is_legal(current: Dictionary, total: int) -> bool:
	return error(current, total) == ""


func face_legal(f: int, current: Dictionary, total: int) -> bool:
	# 当前个数下点数 f 合不合法(点数按钮置灰用)
	return LiarsDiceState.bid_error(count, f, current, total) == ""


static func min_count(current: Dictionary) -> int:
	# 还有合法点数的最小个数:本轮第一口 1;上一口点数没到 6 就同个数,否则个数 +1
	if current.is_empty():
		return 1
	return current["count"] if current["face"] < LiarsDiceState.FACES else current["count"] + 1


func can_dec(current: Dictionary, _total: int) -> bool:
	return count - 1 >= min_count(current)


func can_inc(_current: Dictionary, total: int) -> bool:
	return count + 1 <= total


func nudge(delta: int, current: Dictionary, total: int) -> bool:
	# ↑↓ / −+:个数加减一(停在合法范围里);返回个数变了没有
	var lo := min_count(current)
	var hi := maxi(total, lo)
	var next := clampi(count + delta, mini(lo, hi), hi)
	if next == count:
		return false
	count = next
	if not face_legal(face, current, total):
		var best := first_legal_face(current, total)
		if best > 0:
			face = best
	return true


func pick_face(f: int, current: Dictionary, total: int) -> bool:
	# 选点数(2–6);选的点数在当前个数下不合法时,个数自动抬到能喊这个点数的最小个数。返回选上了没有
	if not LiarsDiceState.is_valid_face(f):
		return false
	face = f
	if not face_legal(f, current, total) and not current.is_empty():
		var need: int = current["count"] if f > current["face"] else current["count"] + 1
		if count < need and need <= total:
			count = need
	return true


func first_legal_face(current: Dictionary, total: int) -> int:
	for f in range(LiarsDiceState.MIN_BID_FACE, LiarsDiceState.FACES + 1):
		if face_legal(f, current, total):
			return f
	return -1


func legal_faces(current: Dictionary, total: int) -> Array:
	var out := []
	for f in range(LiarsDiceState.MIN_BID_FACE, LiarsDiceState.FACES + 1):
		if face_legal(f, current, total):
			out.append(f)
	return out
