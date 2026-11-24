extends RefCounted

# DeepSeek V3.2 uses function_calls; V4 and some gateways use calls or tool_calls.
const WRAPPERS := ["calls", "function_calls", "tool_calls"]
const MARKER := r'<\s*/?\s*(?:[|｜]\s*){1,2}DSML\s*(?:[|｜]\s*){1,2}'
const TOKEN := r'<\s*(/?)\s*(?:[|｜]\s*){1,2}DSML\s*(?:[|｜]\s*){1,2}(function_calls|tool_calls|calls|invoke|parameter)\b([^<>]*)>'

static func has_markup(text: String) -> bool:
	if "DSML" not in text.to_upper():
		return false
	return RegEx.create_from_string("(?i)" + MARKER).search(text) != null

static func parse_markup(text: String, limit: int) -> Array:
	var tags := RegEx.create_from_string("(?i)" + TOKEN).search_all(text)
	if tags.size() < 4 or tags.size() > 512:
		return []
	var first := tags.front() as RegExMatch
	var last := tags.back() as RegExMatch
	var wrapper := first.get_string(2).to_lower()
	if (wrapper not in WRAPPERS or not first.get_string(1).is_empty()
			or last.get_string(2).to_lower() != wrapper or last.get_string(1) != "/"
			or not first.get_string(3).strip_edges().is_empty() or not last.get_string(3).strip_edges().is_empty()
			or has_markup(text.left(first.get_start())) or has_markup(text.substr(last.get_end()))):
		return []

	var attribute_parser := RegEx.create_from_string(r'\s+([a-z_]+)\s*=\s*"([^"]*)"')
	var name_parser := RegEx.create_from_string("^[A-Za-z0-9_]{1,80}$")
	var calls: Array = []
	var name := ""
	var arguments := {}
	var parameter := ""
	var is_string := false
	var cursor := first.get_end()
	for index in range(1, tags.size() - 1):
		var token := tags[index]
		var closing := token.get_string(1) == "/"
		var tag := token.get_string(2).to_lower()
		var raw_attributes := token.get_string(3)
		var between := text.substr(cursor, token.get_start() - cursor)
		cursor = token.get_end()
		if not parameter.is_empty():
			if tag != "parameter" or not closing or not raw_attributes.strip_edges().is_empty():
				return []
			if is_string:
				arguments[parameter] = between
			else:
				var json := JSON.new()
				if json.parse(between) != OK:
					return []
				arguments[parameter] = json.data
			parameter = ""
			continue
		if not between.strip_edges().is_empty():
			return []
		if closing:
			if tag != "invoke" or name.is_empty() or not raw_attributes.strip_edges().is_empty():
				return []
			calls.append({"name": name, "arguments": arguments})
			if calls.size() > limit:
				return []
			name = ""
			arguments = {}
			continue
		var attrs := _attributes(raw_attributes, attribute_parser)
		if name_parser.search(str(attrs.get("name", ""))) == null:
			return []
		if tag == "invoke" and name.is_empty() and attrs.size() == 1:
			name = attrs.name
		elif (tag == "parameter" and not name.is_empty() and attrs.size() == 2
				and attrs.get("string") in ["true", "false"] and not arguments.has(attrs.name)):
			parameter = attrs.name
			is_string = attrs.string == "true"
		else:
			return []
	if not name.is_empty() or not text.substr(cursor, last.get_start() - cursor).strip_edges().is_empty():
		return []
	return calls

static func _attributes(text: String, pattern: RegEx) -> Dictionary:
	var result := {}
	var end := 0
	for entry: RegExMatch in pattern.search_all(text):
		if entry.get_start() != end or result.has(entry.get_string(1)):
			return {}
		result[entry.get_string(1)] = entry.get_string(2)
		end = entry.get_end()
	return result if text.substr(end).strip_edges().is_empty() else {}

static func parse_calls(value: Variant, limit: int) -> Array:
	if not value is Array or value.is_empty() or value.size() > limit:
		return []
	var actions: Array = []
	for call: Variant in value:
		if not call is Dictionary or call.get("type", "function") != "function" or not call.get("function") is Dictionary:
			return []
		var operation: Dictionary = call.function
		var name: Variant = operation.get("name")
		var arguments: Variant = operation.get("arguments", {})
		if arguments is String:
			var parser := JSON.new()
			if parser.parse(arguments) != OK:
				return []
			arguments = parser.data
		if not name is String or name.is_empty() or not arguments is Dictionary:
			return []
		actions.append({"name": name, "arguments": arguments})
	return actions
