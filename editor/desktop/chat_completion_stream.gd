extends Node

signal delta(text: String)
signal opened()
signal completed(result: int, status_code: int, headers: PackedStringArray, body: PackedByteArray)

const RESPONSE_LIMIT := 2 * 1024 * 1024
const SSE_WIRE_LIMIT := 16 * 1024 * 1024
const TIMEOUT_MS := 15 * 60 * 1000

var _client: HTTPClient
var _route := ""
var _request_headers := PackedStringArray()
var _payload := ""
var _code := 0
var _headers := PackedStringArray()
var _body := PackedByteArray()
var _pending := PackedByteArray()
var _event := PackedStringArray()
var _event_bytes := 0
var _result_bytes := 0
var _sse_size_error := false
var _event_type := ""
var _error: Dictionary = {}
var _trace := ""
var _content := ""
var _tool_calls := {}
var _usage: Variant = null
var _sse := false
var _saw_choice := false
var _saw_finish := false
var _received_headers := false
var _sent := false
var _bytes := 0
var _deadline := 0

func _ready() -> void:
	set_process(false)

func start(url: String, secret: String, payload: String) -> Error:
	cancel()
	var secure := url.begins_with("https://")
	var address := url.get_slice("://", 1)
	var authority := address.get_slice("/", 0)
	var host := authority
	var port := 443 if secure else 80
	var colon := authority.rfind(":")
	if colon >= 0 and colon > authority.rfind("]"):
		var value := authority.substr(colon + 1)
		if not value.is_valid_int() or int(value) <= 0 or int(value) > 65535:
			return ERR_INVALID_PARAMETER
		port = int(value)
		host = authority.left(colon)
	host = host.trim_prefix("[").trim_suffix("]")
	_route = address.substr(authority.length())
	_request_headers = PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + secret,
		"Accept: text/event-stream, application/json", "Connection: close"])
	_payload = payload
	_client = HTTPClient.new()
	var status := _client.connect_to_host(host, port, TLSOptions.client() if secure else null)
	if status != OK:
		cancel()
		return status
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	set_process(true)
	return OK

func cancel() -> void:
	set_process(false)
	if _client:
		_client.close()
	_client = null
	_request_headers.clear()
	_payload = ""
	_headers.clear()
	_body.clear()
	_pending.clear()
	_event.clear()
	_event_bytes = 0
	_result_bytes = 0
	_sse_size_error = false
	_event_type = ""
	_error.clear()
	_trace = ""
	_content = ""
	_tool_calls.clear()
	_usage = null
	_sse = false
	_received_headers = false
	_saw_choice = false
	_saw_finish = false
	_sent = false
	_code = 0
	_bytes = 0

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > _deadline:
		_finish(HTTPRequest.RESULT_TIMEOUT)
		return
	_client.poll()
	var state := _client.get_status()
	if state == HTTPClient.STATUS_CONNECTED and not _sent:
		if _client.request(HTTPClient.METHOD_POST, _route, _request_headers, _payload) != OK:
			_finish(HTTPRequest.RESULT_REQUEST_FAILED)
			return
		_sent = true
		_request_headers.clear()
		_payload = ""
		return
	if _client.has_response() and not _received_headers:
		_received_headers = true
		_headers = _client.get_response_headers()
		_code = _client.get_response_code()
		for header: String in _headers:
			if header.to_lower().begins_with("content-type:") and "text/event-stream" in header.to_lower():
				_sse = _code >= 200 and _code < 300
		_deadline = Time.get_ticks_msec() + TIMEOUT_MS
		if _sse:
			opened.emit()
	if state == HTTPClient.STATUS_BODY:
		for _index in range(12):
			if _client.get_status() != HTTPClient.STATUS_BODY:
				break
			var bytes := _client.read_response_body_chunk()
			if bytes.is_empty():
				break
			_deadline = Time.get_ticks_msec() + TIMEOUT_MS
			_bytes += bytes.size()
			if _bytes > (SSE_WIRE_LIMIT if _sse else RESPONSE_LIMIT):
				_finish(HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED)
				return
			if _sse:
				if _consume(bytes):
					_finish(HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED if _sse_size_error else HTTPRequest.RESULT_SUCCESS)
					return
			else:
				_body.append_array(bytes)
		state = _client.get_status()
	if _received_headers and state in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
		if _sse and (not _pending.is_empty() or not _event.is_empty()):
			_consume("\n\n".to_utf8_buffer())
		if _sse_size_error:
			_finish(HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED)
			return
		var complete := not _sse or _saw_finish or not _error.is_empty()
		_finish(HTTPRequest.RESULT_SUCCESS if complete else HTTPRequest.RESULT_CONNECTION_ERROR)
	elif state == HTTPClient.STATUS_CANT_RESOLVE:
		_finish(HTTPRequest.RESULT_CANT_RESOLVE)
	elif state in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_DISCONNECTED]:
		_finish(HTTPRequest.RESULT_CONNECTION_ERROR if _sent else HTTPRequest.RESULT_CANT_CONNECT)
	elif state == HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
		_finish(HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR)
	elif state == HTTPClient.STATUS_CONNECTION_ERROR:
		_finish(HTTPRequest.RESULT_CONNECTION_ERROR)

func _consume(bytes: PackedByteArray) -> bool:
	_pending.append_array(bytes)
	var start := 0
	while start < _pending.size():
		var end := _pending.find(10, start)
		if end < 0:
			break
		var length := end - start
		if length > RESPONSE_LIMIT:
			_sse_size_error = true
			return true
		var line := _pending.slice(start, end).get_string_from_utf8().trim_suffix("\r")
		start = end + 1
		if line.is_empty():
			if _dispatch_event():
				return true
		elif line.begins_with("data:"):
			_event_bytes += length
			if _event_bytes > RESPONSE_LIMIT:
				_sse_size_error = true
				return true
			_event.append(line.substr(5).trim_prefix(" "))
		elif line.begins_with("event:"):
			_event_type = line.substr(6).strip_edges().left(64)
		elif line.begins_with(": trace "):
			_trace = line.substr(8).strip_edges().left(96)
	_pending = _pending.slice(start)
	_sse_size_error = _pending.size() > RESPONSE_LIMIT
	return _sse_size_error

func _dispatch_event() -> bool:
	var is_error := _event_type == "error"
	_event_type = ""
	if _event.is_empty():
		return false
	var data := "\n".join(_event)
	_event.clear()
	_event_bytes = 0
	if data.strip_edges() == "[DONE]":
		_saw_finish = true
		return true
	var event: Variant = JSON.parse_string(data)
	if not event is Dictionary:
		return false
	if event.get("usage") is Dictionary:
		_usage = event.usage
	if event.get("error") is Dictionary:
		_error = event.error
		return true
	if is_error or (event.get("type") == "error" and event.has("code")):
		_error = event
		return true
	var choices: Variant = event.get("choices")
	if choices is Array and not choices.is_empty() and choices[0] is Dictionary:
		_saw_choice = true
		var reason: Variant = choices[0].get("finish_reason")
		_saw_finish = _saw_finish or (reason is String and not reason.is_empty())
		var fields: Variant = choices[0].get("delta", {})
		var piece: Variant = fields.get("content") if fields is Dictionary else null
		if fields is Dictionary and fields.get("tool_calls") is Array:
			_append_tool_calls(fields.tool_calls)
			if _sse_size_error:
				return true
		if piece is String and not piece.is_empty():
			if not _reserve_output(piece):
				return true
			_content += piece
			delta.emit(_content)
	return false

func _append_tool_calls(chunks: Array) -> void:
	for chunk: Variant in chunks:
		if not chunk is Dictionary or not chunk.get("function") is Dictionary:
			continue
		var index: Variant = chunk.get("index", 0)
		if not (index is int or index is float) or index < 0 or index >= 32 or int(index) != index:
			continue
		var call: Dictionary = _tool_calls.get(int(index), {"name": "", "arguments": ""})
		for field: String in ["name", "arguments"]:
			if chunk.function.get(field) is String:
				var piece: String = chunk.function[field]
				if not _reserve_output(piece):
					return
				call[field] += piece
		_tool_calls[int(index)] = call

func _reserve_output(piece: String) -> bool:
	_result_bytes += piece.to_utf8_buffer().size()
	_sse_size_error = _result_bytes > RESPONSE_LIMIT
	return not _sse_size_error

func _finish(result: int) -> void:
	var code := _code
	var headers := _headers.duplicate()
	var body := _body.duplicate()
	if not _trace.is_empty():
		headers.append("X-AGIPlan-Trace: " + _trace)
	if not _error.is_empty():
		body = JSON.stringify({"error": _error, "usage": _usage}).to_utf8_buffer()
	elif _sse and _saw_choice:
		var message := {"content": _content}
		if not _tool_calls.is_empty():
			var indices := _tool_calls.keys()
			indices.sort()
			message["tool_calls"] = indices.map(func(index: int): return {"type": "function", "function": _tool_calls[index]})
		body = JSON.stringify({"choices": [{"message": message}], "usage": _usage}).to_utf8_buffer()
	cancel()
	completed.emit(result, code, headers, body)
