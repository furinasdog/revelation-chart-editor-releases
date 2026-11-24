extends RefCounted

const LOG_DIR := "user://logs"
const OPERATIONS := LOG_DIR + "/editor-operations.jsonl"
const PREVIOUS := LOG_DIR + "/editor-operations.previous.jsonl"
const LIMIT := 384 * 1024

var _session := "%d-%d" % [OS.get_process_id(), Time.get_ticks_msec()]
var _recent: Array[String] = []
var _auth := RegEx.create_from_string(r"(?i)\b(?:bearer\s+|(?:api[_ -]?key|authorization|x-api-key)[\x22']?\s*[:=]\s*[\x22']?)(?:bearer\s+)?[^\s\x22',;]+")
var _remote := RegEx.create_from_string(r"(?i)https?://[^\s\x22'<>]+|data:[^\s\x22'<>]+")
var _filesystem := RegEx.create_from_string(r"(?i)(?:\b[A-Z]:[\\/]|\\\\|/(?:Users|home|private|tmp)/)[^\r\n\x22<>|)]+")

func record(operation: String, details: Dictionary = {}, level := "info") -> void:
	var line := JSON.stringify({"utc": Time.get_datetime_string_from_system(true) + "Z",
		"session": _session, "operation": operation, "details": _clean(details), "level": level})
	var path := ProjectSettings.globalize_path(OPERATIONS)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(OPERATIONS, FileAccess.READ_WRITE)
	if file and file.get_length() >= LIMIT:
		file.close()
		DirAccess.rename_absolute(path, ProjectSettings.globalize_path(PREVIOUS))
		file = FileAccess.open(OPERATIONS, FileAccess.READ_WRITE)
	if not file and not FileAccess.file_exists(OPERATIONS):
		file = FileAccess.open(OPERATIONS, FileAccess.WRITE)
	if file and file.get_length() < LIMIT:
		file.seek_end()
		file.store_line(line)
		file.flush()
		return
	_recent.append(line)
	if _recent.size() > 100:
		_recent.pop_front()

func export_zip(path: String, environment: Dictionary, secrets := PackedStringArray()) -> Error:
	var target := ProjectSettings.globalize_path(path)
	var temporary := target.get_base_dir().path_join(".diagnostics-%s-%d.zip" % [_session, Time.get_ticks_usec()])
	var operations := _tail(PREVIOUS, LIMIT + 4096) + _tail(OPERATIONS, LIMIT + 4096) + "\n".join(_recent)
	for secret: String in secrets:
		if not secret.is_empty():
			operations = operations.replace(JSON.stringify(secret).substr(1, JSON.stringify(secret).length() - 2), "[已隐藏]")
	var entries := {
		"说明.txt": "更好的制谱器 · 错误包\noperations.jsonl 记录近期编辑操作、分析和 Agent 动作，以及失败原因。engine-errors.log 保留引擎错误、警告和堆栈。environment.json 记录运行环境。\n时间为 UTC。请先检查包内内容，再随错误反馈手动发送此文件。\n",
		"environment.json": JSON.stringify(_clean(environment), "  "),
		"operations.jsonl": operations,
		"engine-errors.log": _engine_errors(secrets),
	}
	var zip := ZIPPacker.new()
	var status := zip.open(temporary)
	if status != OK:
		return status
	for entry: String in entries:
		status = zip.start_file(entry)
		if status != OK:
			break
		var written := zip.write_file(entries[entry].to_utf8_buffer())
		var closed := zip.close_file()
		status = written if written != OK else closed
		if status != OK:
			break
	var closed := zip.close()
	if status == OK:
		status = closed
	if status == OK:
		status = DirAccess.rename_absolute(temporary, target)
	if status != OK:
		DirAccess.remove_absolute(temporary)
	return status

func _clean(value: Variant, depth := 0) -> Variant:
	if depth > 4:
		return null
	if value is Dictionary:
		var result := {}
		for key: Variant in value.keys().slice(0, 24):
			result[str(key).left(80)] = _clean(value[key], depth + 1)
		return result
	if value is Array or value is PackedStringArray:
		var entries := []
		for item: Variant in value.slice(0, 24):
			entries.append(_clean(item, depth + 1))
		return entries
	if value is String:
		return _redact(value).left(600)
	return value if typeof(value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_NIL] else null

func _redact(value: String, secrets := PackedStringArray()) -> String:
	for secret: String in secrets:
		if not secret.is_empty():
			value = value.replace(secret, "[已隐藏]")
	value = _auth.sub(value, "[凭据已隐藏]", true)
	value = _remote.sub(value, "[地址已隐藏]", true)
	return _filesystem.sub(value, "[路径已隐藏]", true)

func _engine_errors(secrets: PackedStringArray) -> String:
	var paths: Array[String] = []
	for file: String in DirAccess.get_files_at(LOG_DIR):
		if file.begins_with("godot") and file.ends_with(".log"):
			paths.append(LOG_DIR.path_join(file))
	paths.sort_custom(func(a: String, b: String) -> bool:
		if a == LOG_DIR + "/godot.log" or b == LOG_DIR + "/godot.log":
			return a == LOG_DIR + "/godot.log" and a != b
		return FileAccess.get_modified_time(a) > FileAccess.get_modified_time(b))
	var errors := PackedStringArray()
	for index in range(mini(paths.size(), 5)):
		var active := false
		for raw: String in _tail(paths[index], 256 * 1024).split("\n"):
			var line := raw.strip_edges()
			if line.begins_with("SCRIPT ERROR:") or line.begins_with("ERROR:") or line.begins_with("WARNING:"):
				active = true
				errors.append("[%d] %s" % [index + 1, _redact(line, secrets).left(1000)])
			elif active and raw != raw.lstrip(" \t") and (line.begins_with("at:") or line.begins_with("[") or line.begins_with("GDScript backtrace")):
				errors.append("    " + _redact(line, secrets).left(1000))
			else:
				active = false
	return "\n".join(errors) if not errors.is_empty() else "近期引擎日志没有记录错误或警告。\n"

static func _tail(path: String, limit: int) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	var length := file.get_length()
	var truncated := length > limit
	file.seek(maxi(0, length - limit))
	var bytes := file.get_buffer(mini(length, limit))
	if truncated:
		var newline := bytes.find(10)
		if newline < 0:
			return ""
		bytes = bytes.slice(newline + 1)
	return bytes.get_string_from_utf8()
