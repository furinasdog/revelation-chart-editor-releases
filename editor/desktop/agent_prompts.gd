extends RefCounted

const DIRECTORY := "res://agent_prompts/"
const STORAGE := "user://agent_prompts.json"
const FORMAT := "revelation-agent-prompts"
const MAX_SECTION_BYTES := 16000
const MAX_PROMPT_BYTES := 55000
const MAX_FILE_BYTES := 384000
const Store := preload("res://desktop/project_cache.gd")
const TITLES := {"copilot": "Co-pilot", "shared": "共用制谱指南", "mcp": "MCP",
	"composition": "自动制谱", "reviewer": "审批助手"}

static var _documents := {}

static func section(document: String, id: String) -> String:
	var content: String = snapshot().get(document, {}).get(id, "")
	if content.is_empty():
		push_error("Missing agent prompt section: %s / %s" % [document, id])
	return content

static func defaults() -> Dictionary:
	if _documents.is_empty():
		for document: String in TITLES:
			_documents[document] = _read_document(DIRECTORY + document + ".md")
	return _documents.duplicate(true)

static func snapshot() -> Dictionary:
	var documents := defaults()
	var saved: Variant = _read_json(STORAGE)
	if saved is Dictionary and saved.get("documents") is Dictionary:
		for document: String in documents:
			var overrides: Variant = saved.documents.get(document)
			if not overrides is Dictionary:
				continue
			for id: String in documents[document]:
				if valid_text(overrides.get(id)):
					documents[document][id] = overrides[id]
	return documents

static func revision(documents: Dictionary) -> String:
	return JSON.stringify(documents).sha256_text()

static func valid_text(text: Variant) -> bool:
	return text is String and not text.strip_edges().is_empty() and text.to_utf8_buffer().size() <= MAX_SECTION_BYTES

static func _validate(documents: Dictionary) -> String:
	var shipped := defaults()
	var bytes := 0
	if documents.size() != shipped.size():
		return "提示词包的文档结构不匹配。"
	for document: String in shipped:
		var sections: Variant = documents.get(document)
		if not sections is Dictionary or sections.size() != shipped[document].size():
			return "提示词小节不匹配：%s。" % document
		for id: String in shipped[document]:
			var content: Variant = sections.get(id)
			if not valid_text(content):
				return "提示词不能为空或超过 %d 字节：%s / %s。" % [MAX_SECTION_BYTES, document, id]
			if document == "copilot" and id == "one-click" and "{{difficulty}}" not in content:
				return "一键制谱提示词需要保留 {{difficulty}} 难度占位符。"
			bytes += content.to_utf8_buffer().size()
	return "提示词总长度超过 %d 字节。" % MAX_PROMPT_BYTES if bytes > MAX_PROMPT_BYTES else ""

static func save(documents: Dictionary, expected_revision: String) -> String:
	var error := _validate(documents)
	if not error.is_empty():
		return error
	if revision(snapshot()) != expected_revision:
		return "已保存的提示词发生变化。请重新读取后再编辑。"
	var shipped := defaults()
	var overrides := {}
	for document: String in documents:
		var changes := {}
		for id: String in documents[document]:
			if documents[document][id] != shipped[document][id]:
				changes[id] = documents[document][id]
		if not changes.is_empty():
			overrides[document] = changes
	return "" if Store.write_json(STORAGE, {"documents": overrides}) else "无法保存提示词。"

static func import_pack(path: String) -> Dictionary:
	var pack: Variant = _read_json(path)
	if not pack is Dictionary or pack.get("format") != FORMAT or pack.get("schema") != 1 or not pack.get("documents") is Dictionary:
		return {"error": "无法读取此提示词包。"}
	var error := _validate(pack.documents)
	return {"documents": pack.documents} if error.is_empty() else {"error": error}

static func export_pack(path: String, documents: Dictionary) -> String:
	var error := _validate(documents)
	if not error.is_empty():
		return error
	return "" if Store.write_json(path, {"format": FORMAT, "schema": 1, "documents": documents}) else "无法写入提示词包。"

static func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file or file.get_length() > MAX_FILE_BYTES:
		return null
	return JSON.parse_string(file.get_as_text())

static func join(sections: PackedStringArray, separator := "\n\n") -> String:
	if sections.has(""):
		return ""
	return separator.join(sections)

static func _read_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("Cannot load agent prompts: " + path)
		return {}
	var contents := "\n" + file.get_as_text().replace("\r\n", "\n")
	var sections := {}
	for block: String in contents.split("\n## ").slice(1):
		var heading := block.split("\n", true, 1)
		var id := heading[0].strip_edges()
		if heading.size() != 2 or id.is_empty() or sections.has(id):
			push_error("Invalid or duplicate agent prompt heading in %s: %s" % [path, id])
			return {}
		sections[id] = heading[1].strip_edges()
	return sections
