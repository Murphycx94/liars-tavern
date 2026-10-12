class_name AiSettings
# 机器人(德州、斗地主)接 AI 的设置(user://settings.cfg 的 [ai] 段):接口地址、API Key、模型、是否让 AI 接管机器人。
# 只存在房主本机,不会发给其他玩家;API Key 是明文存的(和浏览器记住的密码一样,别把设置文件发给别人)。
# 接口两种:OpenAI 兼容的 /chat/completions(DeepSeek、通义千问、Kimi、OpenRouter、本机 Ollama 等都是这种),
# 以及 Anthropic 的 /v1/messages(地址里带 anthropic 或以 /messages 结尾时按它发)。


const SECTION := "ai"
const KEY_URL := "url"
const KEY_API_KEY := "api_key"
const KEY_MODEL := "model"
const KEY_ENABLED := "enabled"
const KIND_OPENAI := "openai"
const KIND_ANTHROPIC := "anthropic"
const OPENAI_PATH := "/chat/completions"
const ANTHROPIC_PATH := "/messages"
const MAX_FIELD_LENGTH := 512   # 设置文件是外部数据:超长的值当没填


static func defaults() -> Dictionary:
	return {KEY_URL: "", KEY_API_KEY: "", KEY_MODEL: "", KEY_ENABLED: false}


static func load_config(path := Settings.PATH) -> Dictionary:
	# 读不出、类型不对的项回退默认值(和 Settings 一样告警,但不打印 Key 本身)
	var config := ConfigFile.new()
	var err := config.load(path)
	var out := defaults()
	if err != OK:
		if err != ERR_FILE_NOT_FOUND:
			push_warning("读取 AI 设置失败(%s):%s" % [path, error_string(err)])
		return out
	for key in out:
		var value: Variant = config.get_value(SECTION, key, out[key])
		if typeof(value) == typeof(out[key]) and (not value is String or value.length() <= MAX_FIELD_LENGTH):
			out[key] = value
		else:
			push_warning("AI 设置 %s 的值不对,改用默认值" % key)
	return out


static func save_config(values: Dictionary, path := Settings.PATH) -> Error:
	# 保留文件里的其他段(玩家设置);只写认识的键
	var config := ConfigFile.new()
	var err := config.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("设置文件 %s 无法读取(%s),将重新创建" % [path, error_string(err)])
		config = ConfigFile.new()
	var clean := sanitized(values)
	for key in clean:
		config.set_value(SECTION, key, clean[key])
	err = config.save(path)
	if err != OK:
		push_warning("保存 AI 设置失败:%s" % error_string(err))
	return err


static func sanitized(values: Dictionary) -> Dictionary:
	# 文本去掉首尾空白;开关只认 bool
	var out := defaults()
	for key in [KEY_URL, KEY_API_KEY, KEY_MODEL]:
		var value: Variant = values.get(key, "")
		out[key] = (value as String).strip_edges().substr(0, MAX_FIELD_LENGTH) if value is String else ""
	out[KEY_ENABLED] = values.get(KEY_ENABLED, false) is bool and values[KEY_ENABLED]
	return out


static func is_active(values: Dictionary) -> bool:
	# 打开了开关、填了地址与模型、地址格式对:机器人才去问 AI(本机模型可以不填 Key)
	return values.get(KEY_ENABLED, false) == true and check(values) == ""


static func check(values: Dictionary) -> String:
	# 填写有问题时返回给玩家看的说明,没问题返回 ""
	var url: String = str(values.get(KEY_URL, "")).strip_edges()
	if url == "":
		return "请填写接口地址"
	if not (url.begins_with("http://") or url.begins_with("https://")):
		return "接口地址要以 http:// 或 https:// 开头"
	if str(values.get(KEY_MODEL, "")).strip_edges() == "":
		return "请填写模型名称"
	return ""


static func kind(url: String) -> String:
	var lower := url.strip_edges().to_lower()
	if lower.contains("anthropic") or lower.trim_suffix("/").ends_with(ANTHROPIC_PATH):
		return KIND_ANTHROPIC
	return KIND_OPENAI


static func endpoint(url: String) -> String:
	# 玩家可能只填域名、填基础地址(…/v1)、也可能填完整地址:完整地址照用;只有域名时补 /v1(各家的惯例),
	# 再补上接口路径
	var base := url.strip_edges().trim_suffix("/")
	if base.ends_with(OPENAI_PATH) or base.ends_with(ANTHROPIC_PATH):
		return base
	if not _has_path(base):
		base += "/v1"
	return base + (ANTHROPIC_PATH if kind(base) == KIND_ANTHROPIC else OPENAI_PATH)


static func _has_path(url: String) -> bool:
	var scheme := url.find("://")
	return url.find("/", scheme + 3 if scheme >= 0 else 0) >= 0
