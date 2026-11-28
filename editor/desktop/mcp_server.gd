extends Node

signal session_closed(id: String)

const Guidance := preload("res://desktop/editor_guidance.gd")
const PROTOCOLS := ["2025-11-25", "2025-06-18", "2025-03-26"]
const MAX_HEADER := 8192
const MAX_BODY := 384000
const MAX_CONNECTIONS := 12
const MAX_SESSIONS := 4
const IDLE_MS := 30 * 60 * 1000
const CHUNK_BYTES := 32768
const STATUSES := {200: "OK", 202: "Accepted", 204: "No Content", 400: "Bad Request",
	401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed",
	408: "Request Timeout", 413: "Content Too Large", 415: "Unsupported Media Type",
	431: "Request Header Fields Too Large", 503: "Service Unavailable"}

var _listener := TCPServer.new()
var _connections: Array[Dictionary] = []
var _sessions := {}
var _port: int
var _path: String
var _client_name: String
var _token: String
var _tools: Array
var _call_tool: Callable
var _reclaimable: Callable

func _ready() -> void:
	set_process(false)

func start(port: int, path: String, allowed_client: String, token: String, tools: Array, dispatch: Callable,
		reclaimable: Callable) -> Error:
	var error := _listener.listen(port, "127.0.0.1")
	if error != OK:
		return error
	_port = _listener.get_local_port()
	_path = path
	_client_name = allowed_client
	_token = token
	_tools = tools
	_call_tool = dispatch
	_reclaimable = reclaimable
	set_process(true)
	return OK

func stop() -> void:
	set_process(false)
	_listener.stop()
	for connection: Dictionary in _connections:
		var peer: StreamPeerTCP = connection.peer
		peer.disconnect_from_host()
	_connections.clear()
	for id: String in _sessions.keys():
		_close_session(id)

func is_running() -> bool:
	return _listener.is_listening()

func endpoint() -> String:
	return "http://127.0.0.1:%d%s" % [_port, _path]

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	while _connections.size() < MAX_CONNECTIONS and _listener.is_connection_available():
		var peer := _listener.take_connection()
		_connections.append({"peer": peer, "input": PackedByteArray(), "output": PackedByteArray(),
			"sent": 0, "deadline": now + 10000, "header_end": -1, "request": {}, "waiting": false, "cancelled": false})
	for index in range(_connections.size() - 1, -1, -1):
		var connection := _connections[index]
		if not _poll(connection, now):
			connection.cancelled = true
			connection.peer.disconnect_from_host()
			_connections.remove_at(index)
	for id: String in _sessions.keys():
		if now - int(_sessions[id].last_seen) >= IDLE_MS and not _has_pending_call(id):
			_close_session(id)

func _poll(connection: Dictionary, now: int) -> bool:
	var peer: StreamPeerTCP = connection.peer
	if peer.poll() != OK or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	var output: PackedByteArray = connection.output
	if now >= int(connection.deadline):
		if not output.is_empty():
			return false
		connection.cancelled = true
		_respond(connection, 408)
		return true
	if not output.is_empty():
		var position: int = connection.sent
		var written := peer.put_partial_data(output.slice(position, position + CHUNK_BYTES))
		if written[0] != OK:
			return false
		connection.sent += written[1]
		return connection.sent < output.size()
	if connection.waiting:
		return true
	var available := mini(peer.get_available_bytes(), CHUNK_BYTES)
	if available <= 0:
		return true
	var read := peer.get_partial_data(available)
	if read[0] != OK:
		return false
	var start := maxi(0, connection.input.size() - 3)
	connection.input.append_array(read[1])
	if connection.header_end < 0:
		var input: PackedByteArray = connection.input
		for index in range(start, mini(input.size() - 3, MAX_HEADER)):
			if input.decode_u32(index) == 0x0a0d0a0d:
				connection.header_end = index + 4
				break
		if connection.header_end < 0:
			if input.size() >= MAX_HEADER:
				_respond(connection, 431)
			return true
		connection.request = _parse_request(input.slice(0, connection.header_end - 4).get_string_from_utf8())
		if connection.request.has("status"):
			_respond(connection, connection.request.status)
			return true
	var end: int = connection.header_end + connection.request.length
	if connection.input.size() >= end:
		var body: String = connection.input.slice(connection.header_end, end).get_string_from_utf8()
		connection.input = PackedByteArray()
		connection.waiting = true
		connection.deadline = now + 240000
		_dispatch(connection, body)
	return true

func _parse_request(text: String) -> Dictionary:
	var lines := text.split("\r\n")
	var request_line := lines[0]
	if request_line.get_slice_count(" ") != 3 or request_line.get_slice(" ", 2) not in ["HTTP/1.1", "HTTP/1.0"]:
		return {"status": 400}
	var method := request_line.get_slice(" ", 0)
	var target := request_line.get_slice(" ", 1)
	var headers := {}
	for index in range(1, lines.size()):
		var line := lines[index]
		var colon := line.find(":")
		if colon <= 0:
			return {"status": 400}
		var key := line.left(colon).to_lower()
		if headers.has(key) or key != key.strip_edges():
			return {"status": 400}
		headers[key] = line.substr(colon + 1).strip_edges()
	if headers.get("host", "") not in ["127.0.0.1:%d" % _port, "localhost:%d" % _port]:
		return {"status": 403}
	if headers.has("origin") and headers.origin not in ["http://127.0.0.1:%d" % _port, "http://localhost:%d" % _port]:
		return {"status": 403}
	if not _is_authorized(headers.get("authorization", "")):
		return {"status": 401}
	if target != _path:
		return {"status": 404}
	if method not in ["POST", "GET", "DELETE"]:
		return {"status": 405}
	var length: String = headers.get("content-length", "0")
	if headers.has("transfer-encoding") or not length.is_valid_int() or int(length) < 0:
		return {"status": 400}
	if int(length) > MAX_BODY:
		return {"status": 413}
	if method == "POST" and not str(headers.get("content-type", "")).to_lower().begins_with("application/json"):
		return {"status": 415}
	return {"method": method, "length": int(length), "headers": headers}

func _is_authorized(header: String) -> bool:
	if not header.begins_with("Bearer ") or header.length() != _token.length() + 7:
		return false
	var mismatch := 0
	for index in range(_token.length()):
		mismatch |= header.unicode_at(index + 7) ^ _token.unicode_at(index)
	return mismatch == 0

func _dispatch(connection: Dictionary, body: String) -> void:
	var request: Dictionary = connection.request
	var headers: Dictionary = request.headers
	var session_id: String = headers.get("mcp-session-id", "")
	var version: String = headers.get("mcp-protocol-version", "")
	var parsed: Variant
	if request.method == "POST":
		var json := JSON.new()
		if json.parse(body) != OK:
			_rpc_error(connection, null, -32700, "无效的 JSON 请求。")
			return
		parsed = json.data
		if not parsed is Dictionary or parsed.get("jsonrpc") != "2.0":
			_rpc_error(connection, null, -32600, "无效的 JSON-RPC 请求。")
			return
		if parsed.get("method") == "initialize" and parsed.has("id") and not headers.has("mcp-session-id"):
			_initialize(connection, parsed)
			return
		if parsed.get("method") == "server/discover" and parsed.has("id") and not headers.has("mcp-session-id"):
			_rpc_error(connection, _request_id(parsed.id), -32601, "请使用 initialize 建立会话。")
			return
	if not version.is_empty() and version not in PROTOCOLS:
		_respond(connection, 400)
		return
	if not _sessions.has(session_id):
		_respond(connection, 404 if headers.has("mcp-session-id") else 400)
		return
	var session: Dictionary = _sessions[session_id]
	if not version.is_empty() and version != session.version:
		_respond(connection, 400)
		return
	session.last_seen = Time.get_ticks_msec()
	match request.method:
		"DELETE":
			_close_session(session_id)
			_respond(connection, 204)
			return
		"GET":
			_respond(connection, 405)
			return
	var id: Variant = _request_id(parsed.get("id"))
	var method: Variant = parsed.get("method")
	if not parsed.has("id") and method is String and method.begins_with("notifications/"):
		if method == "notifications/cancelled" and parsed.get("params") is Dictionary:
			for pending: Dictionary in _connections:
				if pending.get("rpc_session", "") == session_id and pending.get("rpc_id") == _request_id(parsed.params.get("requestId")):
					pending.cancelled = true
		_respond(connection, 202)
		return
	if method == null and parsed.has("id") and (parsed.has("result") or parsed.has("error")):
		_respond(connection, 202)
		return
	if id == null or not method is String:
		_rpc_error(connection, null, -32600, "请求须包含方法和有效的 ID。")
		return
	match method:
		"ping":
			_result(connection, id, {})
		"tools/list":
			_result(connection, id, {"tools": _tools})
		"prompts/list":
			_result(connection, id, Guidance.prompt_list())
		"prompts/get":
			var params: Variant = parsed.get("params")
			if params is Dictionary and params.get("name") == Guidance.PROMPT_NAME:
				_result(connection, id, Guidance.prompt_get())
			else:
				_rpc_error(connection, id, -32602, "未知的制谱提示模板。")
		"tools/call":
			var params: Variant = parsed.get("params")
			if not params is Dictionary or not params.get("name") is String or not params.get("arguments", {}) is Dictionary:
				_rpc_error(connection, id, -32602, "请提供工具名称和参数对象。")
				return
			connection.rpc_id = id
			connection.rpc_session = session_id
			var live := func() -> bool:
				return not connection.cancelled and _sessions.has(session_id) and connection.peer.poll() == OK and connection.peer.get_status() == StreamPeerTCP.STATUS_CONNECTED
			var result: Dictionary = await _call_tool.call(session_id, session.client, params.name, params.get("arguments", {}), live)
			if live.call():
				_result(connection, id, result)
			elif connection.cancelled and connection.output.is_empty() and _connections.has(connection):
				_rpc_error(connection, id, -32800, "工具调用已取消。")
		_:
			_rpc_error(connection, id, -32601, "未知的 MCP 方法。")

func _initialize(connection: Dictionary, message: Dictionary) -> void:
	var id: Variant = _request_id(message.id)
	var params: Variant = message.get("params")
	if id == null or not params is Dictionary or not params.get("protocolVersion") is String or not params.get("clientInfo") is Dictionary:
		_rpc_error(connection, null, -32602, "缺少协议版本或客户端信息。")
		return
	var client: Variant = params.clientInfo.get("name")
	if not client is String or client.strip_edges().is_empty() or client.length() > 128:
		_rpc_error(connection, id, -32602, "客户端名称无效。")
		return
	if not _client_name.is_empty() and _client_name != client:
		_respond(connection, 403, {"jsonrpc": "2.0", "id": id,
			"error": {"code": -32000, "message": "客户端名称与编辑器设置不匹配。"}})
		return
	if _sessions.size() >= MAX_SESSIONS and not _reclaim_idle_session():
		_respond(connection, 503, {"jsonrpc": "2.0", "id": id, "error": {"code": -32000,
			"message": "现有 MCP 会话均有正在运行的请求或待提交草稿。请在原会话完成或放弃草稿后再试。"}})
		return
	var version: String = params.protocolVersion if params.protocolVersion in PROTOCOLS else PROTOCOLS[0]
	var session_id := Crypto.new().generate_random_bytes(24).hex_encode()
	_sessions[session_id] = {"version": version, "client": client, "last_seen": Time.get_ticks_msec()}
	_result(connection, id, {"protocolVersion": version, "capabilities": {"tools": {}, "prompts": {}},
		"serverInfo": {"name": "revelation-chart-editor", "version": str(ProjectSettings.get_setting("application/config/version"))},
		"instructions": Guidance.quick()},
		"Mcp-Session-Id: " + session_id + "\r\n")

func _reclaim_idle_session() -> bool:
	var oldest := ""
	for id: String in _sessions:
		if _has_pending_call(id) or not _reclaimable.call(id):
			continue
		if oldest.is_empty() or _sessions[id].last_seen < _sessions[oldest].last_seen:
			oldest = id
	if oldest.is_empty():
		return false
	_close_session(oldest)
	return true

func _has_pending_call(id: String) -> bool:
	return _connections.any(func(connection: Dictionary) -> bool:
		return connection.get("rpc_session", "") == id and not connection.cancelled and connection.output.is_empty())

func _close_session(id: String) -> void:
	_sessions.erase(id)
	for pending: Dictionary in _connections:
		if pending.get("rpc_session", "") == id:
			pending.cancelled = true
	session_closed.emit(id)

static func _request_id(value: Variant) -> Variant:
	if value is int or value is String:
		return value
	# JSON.parse stores numbers as floats. MCP clients require IDs to be strings or integers.
	if value is float and absf(value) <= 9007199254740991.0 and floorf(value) == value:
		return int(value)
	return null

func _result(connection: Dictionary, id: Variant, value: Dictionary, extra := "") -> void:
	_respond(connection, 200, {"jsonrpc": "2.0", "id": id, "result": value}, extra)

func _rpc_error(connection: Dictionary, id: Variant, code: int, message: String) -> void:
	_respond(connection, 200, {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})

func _respond(connection: Dictionary, status: int, value: Dictionary = {}, extra := "") -> void:
	var body := JSON.stringify(value).to_utf8_buffer() if not value.is_empty() else PackedByteArray()
	var header := "HTTP/1.1 %d %s\r\nConnection: close\r\nCache-Control: no-store\r\nContent-Length: %d\r\n" % [status, STATUSES[status], body.size()]
	if not body.is_empty():
		header += "Content-Type: application/json; charset=utf-8\r\n"
	if status == 401:
		header += "WWW-Authenticate: Bearer\r\n"
	if status == 405:
		header += "Allow: POST, DELETE\r\n"
	connection.output = (header + extra + "\r\n").to_utf8_buffer()
	connection.output.append_array(body)
	connection.deadline = Time.get_ticks_msec() + 10000
