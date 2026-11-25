extends RefCounted

const DIRECTORY := "user://tempo_cache"
var identity := ""
var difficulty := ""

static func write_json(path: String, value: Variant) -> bool:
	var target := ProjectSettings.globalize_path(path)
	var temporary := "%s.%d-%d.tmp" % [target, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		return false
	var written := file.store_string(JSON.stringify(value, "", false))
	file.close()
	if written and DirAccess.rename_absolute(temporary, target) == OK:
		return true
	DirAccess.remove_absolute(temporary)
	return false

func _key(path: String, level: String) -> String:
	var full := ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()
	return JSON.stringify([full.to_lower() if OS.get_name() == "Windows" else full, level]).sha256_text()

func _content(document: Dictionary) -> String:
	# Match the same chart JSON after ZIP extraction, irrespective of the temporary directory.
	var normalized: Variant = JSON.parse_string(JSON.stringify([document.get("basic", {}), document.get("data", [])]))
	return JSON.stringify(normalized).sha256_text()

func _alias(key: String) -> String:
	var path := DIRECTORY.path_join(key + ".id")
	if FileAccess.file_exists(path):
		var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if stored is String and stored.length() == 64 and stored.is_valid_hex_number():
			return stored
	return ""

func open(path: String, document: Dictionary) -> Array:
	difficulty = str(document.get("basic", {}).get("difficulty", ""))
	var key := _key(path, difficulty)
	identity = _alias(key)
	if identity.is_empty():
		var content := _content(document)
		identity = _alias(content if path.get_extension().to_lower() == "zip" else "archive-" + content)
	if identity.is_empty():
		identity = key
	var file := DIRECTORY.path_join(identity + ".json")
	if FileAccess.file_exists(file):
		var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		if rows is Array: return rows
	return []

func remember(path: String, document: Dictionary, grid: Array) -> void:
	if path.is_empty(): return
	var level := str(document.get("basic", {}).get("difficulty", ""))
	var key := _key(path, level)
	if identity.is_empty() or level != difficulty:
		identity = key
		difficulty = level
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY)) != OK: return
	if write_json(DIRECTORY.path_join(identity + ".json"), grid):
		write_json(DIRECTORY.path_join(key + ".id"), identity)
		write_json(DIRECTORY.path_join(_content(document) + ".id"), identity)
		if path.get_extension().to_lower() == "zip":
			write_json(DIRECTORY.path_join("archive-" + _content(document) + ".id"), identity)

func update(grid: Array, level: String) -> void:
	if not identity.is_empty() and level == difficulty and DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIRECTORY)):
		write_json(DIRECTORY.path_join(identity + ".json"), grid)
