extends RefCounted
# 展台换人:tools/shot.gd(与 perf_probe)命令行带 --species=panda,penguin,… 时,各玩法展台按座位号顺序给前几位换成这些形象,
# 其余座位照旧(默认形象或先到先得补空着的物种,同桌不撞脸)。不写就和原来一样。
# 例:--showcase --species=panda,penguin --views=seat,opponent;--poker-showcase --species=panda,penguin


static func wanted() -> Array:
	# 命令行里点名的形象下标(不认识的 id 跳过)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--species="):
			var out := []
			for id in arg.trim_prefix("--species=").split(",", false):
				var index := Species.index_of(id)
				if index != Species.UNASSIGNED and not out.has(index):
					out.append(index)
			return out
	return []


static func players(pids: Array, defaults := {}) -> Array:
	# pids → TableWorld.arrange 的名单:点名的形象按顺序给前几位,其余用 defaults[pid](被点名占了就补第一个空着的)
	var picks := wanted()
	if picks.is_empty() and defaults.is_empty():
		return pids.map(func(pid): return {"pid": pid})
	var taken := picks.duplicate()
	var out := []
	for i in pids.size():
		var row := {"pid": pids[i]}
		if i < picks.size():
			row["species"] = picks[i]
		elif defaults.has(pids[i]) and not taken.has(defaults[pids[i]]):
			row["species"] = defaults[pids[i]]
			taken.append(defaults[pids[i]])
		else:
			row["species"] = Species.first_free(taken)
			taken.append(row["species"])
		out.append(row)
	return out
