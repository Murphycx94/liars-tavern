class_name AiChat
extends Node
# 向大模型发一问一答(房主本机发出,API Key 不经过局域网)。每次请求一个 HTTPRequest 子节点,回答经 answered 信号送回:
# ok 为真时 text 是模型的回答,否则是给玩家看的错误说明。请求与解析分开,解析是纯函数、可以单测。


signal answered(id: int, ok: bool, text: String)

const TIMEOUT := 18.0               # 秒:超时按失败处理(机器人回合限时 30 秒,还要留出兜底的时间)
const BODY_LIMIT := 1_000_000       # 回答体积上限:正常回答只有几百字节
const ANTHROPIC_VERSION := "2023-06-01"
const ANTHROPIC_MAX_TOKENS := 1024  # Anthropic 必须给;OpenAI 兼容接口不给(新模型不认 max_tokens,各家默认值都够用)
const ERROR_SNIPPET := 120          # 接口报错时摘录多少字给玩家看

var _next_id := 0


func ask(config: Dictionary, system: String, user: String) -> int:
	# 发出请求并返回编号;发不出去时下一帧以失败回答(调用方只需要处理 answered)
	_next_id += 1
	var id := _next_id
	var problem := AiSettings.check(config)
	if problem != "":
		_fail_later(id, problem)
		return id
	var req := build_request(config, system, user)
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	http.body_size_limit = BODY_LIMIT
	http.max_redirects = 0   # 不跟随跳转:跳转会带着同样的请求头(含 Key)发去别的地址
	add_child(http)
	http.request_completed.connect(_on_completed.bind(id, http, req["kind"]))
	var err := http.request(req["url"], req["headers"], HTTPClient.METHOD_POST, req["body"])
	if err != OK:
		http.queue_free()
		_fail_later(id, "请求发不出去(%s)" % error_string(err))
	return id


func cancel_all() -> void:
	# 离开房间 / 回等待厅:还没回来的请求都不要了(回答到了也没人收)
	for child in get_children():
		if child is HTTPRequest:
			child.cancel_request()
			child.queue_free()


func _fail_later(id: int, message: String) -> void:
	answered.emit.call_deferred(id, false, message)


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray,
		id: int, http: HTTPRequest, api_kind: String) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		answered.emit(id, false, transport_error(result))
		return
	var parsed := parse_response(api_kind, code, body.get_string_from_utf8())
	answered.emit(id, parsed["ok"], parsed["text"] if parsed["ok"] else parsed["error"])


static func build_request(config: Dictionary, system: String, user: String) -> Dictionary:
	var url: String = config.get(AiSettings.KEY_URL, "")
	var key: String = config.get(AiSettings.KEY_API_KEY, "")
	var model: String = config.get(AiSettings.KEY_MODEL, "")
	var api_kind := AiSettings.kind(url)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body: Dictionary
	if api_kind == AiSettings.KIND_ANTHROPIC:
		if key != "":
			headers.append("x-api-key: " + key)
		headers.append("anthropic-version: " + ANTHROPIC_VERSION)
		body = {"model": model, "max_tokens": ANTHROPIC_MAX_TOKENS, "system": system,
			"messages": [{"role": "user", "content": user}]}
	else:
		if key != "":
			headers.append("Authorization: Bearer " + key)
		body = {"model": model, "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]}
	return {"url": AiSettings.endpoint(url), "headers": headers, "body": JSON.stringify(body), "kind": api_kind}


static func parse_response(api_kind: String, code: int, text: String) -> Dictionary:
	# → {"ok": true, "text"} 或 {"ok": false, "error"}
	if code < 200 or code >= 300:
		return {"ok": false, "error": http_error(code, text)}
	var data: Variant = parse_json(text)
	if not data is Dictionary:
		return {"ok": false, "error": "接口返回的不是 JSON"}
	var answer := _anthropic_text(data) if api_kind == AiSettings.KIND_ANTHROPIC else _openai_text(data)
	if answer.strip_edges() == "":
		return {"ok": false, "error": "模型没有给出回答"}
	return {"ok": true, "text": answer}


static func parse_json(text: String) -> Variant:
	# 解析失败返回 null。不用 JSON.parse_string:它对坏 JSON 会往引擎日志里报错,而 AI 答错格式是常事
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


static func answer_object(text: String) -> Variant:
	# 模型回答里的 JSON 对象:容忍前后的废话与 ```json 代码块,取第一个 { 到最后一个 } 之间的部分;找不到为 null
	var start := text.find("{")
	var end := text.rfind("}")
	if start < 0 or end <= start:
		return null
	return parse_json(text.substr(start, end - start + 1))


static func _openai_text(data: Dictionary) -> String:
	var choices: Variant = data.get("choices")
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:
		return ""
	var message: Variant = choices[0].get("message")
	if not message is Dictionary:
		return ""
	var content: Variant = message.get("content")
	return content if content is String else ""


static func _anthropic_text(data: Dictionary) -> String:
	var blocks: Variant = data.get("content")
	if not blocks is Array:
		return ""
	var parts := []
	for block in blocks:
		if block is Dictionary and block.get("type") == "text" and block.get("text") is String:
			parts.append(block["text"])
	return "\n".join(parts)


static func http_error(code: int, text: String) -> String:
	var hint := ""
	match code:
		400:
			hint = "请求被拒绝,模型名称可能不对"
		401, 403:
			hint = "API Key 不对或没有权限"
		404:
			hint = "接口地址或模型名称不对"
		429:
			hint = "请求太频繁或额度用完了"
		_:
			hint = "接口出错" if code >= 500 else "接口返回异常"
	var snippet := text.strip_edges().substr(0, ERROR_SNIPPET)
	return "%s(HTTP %d)%s" % [hint, code, (":" + snippet) if snippet != "" else ""]


static func transport_error(result: int) -> String:
	match result:
		HTTPRequest.RESULT_TIMEOUT:
			return "AI 太久没回答(超过 %d 秒)" % int(TIMEOUT)
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "找不到接口地址的服务器"
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CONNECTION_ERROR:
			return "连不上接口地址"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "HTTPS 握手失败"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "接口返回的内容太大"
	return "请求失败(错误 %d)" % result
