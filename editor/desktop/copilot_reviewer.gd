extends HTTPRequest

signal decided(verdict: Dictionary)

const Agent := preload("res://desktop/chart_agent.gd")
const Prompts := preload("res://desktop/agent_prompts.gd")
var _pending := false

func _ready() -> void:
	timeout = 25
	body_size_limit = 65536
	max_redirects = 0
	request_completed.connect(_on_result)

func review(settings: Dictionary, proposal: Dictionary) -> Dictionary:
	var details := JSON.stringify(proposal)
	if _pending or details.to_utf8_buffer().size() > 32000:
		return {}
	var endpoint := Agent.endpoint_from_url(str(settings.get("url", "")))
	var key := str(settings.get("key", "")).strip_edges()
	var instructions := Prompts.section("reviewer", "review")
	if endpoint.is_empty() or key.is_empty() or "\n" in key or "\r" in key or instructions.is_empty():
		return {}
	var payload := {"model": settings.model, "stream": false, "messages": [
		{"role": "system", "content": instructions}, {"role": "user", "content": details}]}
	_pending = true
	var err := request(endpoint, ["Content-Type: application/json", "Authorization: Bearer " + key],
		HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_pending = false
		return {}
	var verdict: Dictionary = await decided
	return verdict

func stop() -> void:
	if _pending:
		_pending = false
		cancel_request()
		decided.emit({})

func _on_result(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _pending:
		return
	_pending = false
	var verdict := {}
	if result == RESULT_SUCCESS and code == 200:
		var data: Variant = _decode(body.get_string_from_utf8())
		if data is Dictionary and data.get("choices") is Array and not data.choices.is_empty():
			var choice: Variant = data.choices[0]
			if choice is Dictionary and choice.get("message") is Dictionary and choice.message.get("content") is String and choice.get("finish_reason", "stop") == "stop":
				var answer: Variant = _decode(choice.message.content)
				if answer is Dictionary and answer.get("decision") in ["allow", "ask", "deny"] and answer.get("reason") is String and not answer.reason.strip_edges().is_empty():
					verdict = {"decision": answer.decision, "reason": answer.reason.strip_edges().left(220)}
	decided.emit(verdict)

static func _decode(text: String) -> Variant:
	var parser := JSON.new()
	if parser.parse(text) == OK:
		return parser.data
	return null
