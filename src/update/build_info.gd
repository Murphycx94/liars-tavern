class_name BuildInfo
# 当前运行内容的版本信息,读自 res://build.json(装了更新包时读到的是更新包里那份)。
# build 每次发布加一;base_build 是这份内容能叠加到的最旧安装包:project.godot 改了(新增自动加载、
# 渲染设置等)就必须重装,发布脚本会检查并要求把 base_build 提到 build。


const PATH := "res://build.json"
# 互联网更新源:按平台分目录放 manifest.json / manifest.sig / pck 的静态网址(以 / 结尾);留空 = 只走局域网更新。
# 现在是 GitHub 仓库的 updates 分支(tools/publish_update.sh 推送),经 raw.githubusercontent.com 直接读取、不跳转
const FEED_URL := "https://raw.githubusercontent.com/BoAsir/liars-tavern/updates/"

static var _cache := {}


static func info() -> Dictionary:
	if _cache.is_empty():
		_cache = parse(FileAccess.get_file_as_string(PATH))
	return _cache


static func parse(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {"build": 0, "version": "dev", "base_build": 0}
	var data: Dictionary = json.data
	return {
		"build": int(data.get("build", 0)),
		"version": str(data.get("version", "dev")),
		"base_build": int(data.get("base_build", 0)),
	}


static func build() -> int:
	return info()["build"]


static func version() -> String:
	return info()["version"]


static func platform() -> String:
	# 更新包按平台分:各平台导出的 pck 不能混用
	match OS.get_name():
		"macOS":
			return "macos"
		"Windows":
			return "windows"
		_:
			return "linux"


static func engine() -> String:
	# pck 只能叠加到同一引擎版本的安装包上
	var v := Engine.get_version_info()
	return "%d.%d.%d.%s" % [v["major"], v["minor"], v["patch"], v["status"]]
