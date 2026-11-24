extends RefCounted

const Archive := preload("res://main/chart_archive.gd")
const MAX_AUDIO_BYTES := 192 * 1024 * 1024

static func local_path(raw: Variant) -> String:
	if not raw is String or raw.length() > 1024:
		return ""
	var path: String = raw.replace("\\", "/")
	if (not path.is_absolute_path() or path.begins_with("//") or path.contains("://")
			or path.get_extension().to_lower() not in ["wav", "mp3", "ogg"]):
		return ""
	var start := 1
	if OS.get_name() == "Windows":
		if RegEx.create_from_string(r"^[A-Za-z]:/").search(path) == null:
			return ""
		start = 3
	if not Archive.relative_name(path.substr(start)):
		return ""
	return path

static func load_into(workspace: Node, path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file or file.get_length() <= 0 or file.get_length() > MAX_AUDIO_BYTES:
		return {"error": "无法读取本机音频。请选择有效的 WAV、MP3 或 OGG，文件最多 192 MiB。"}
	file.close()
	if not workspace.import_audio(path, false, false):
		return {"error": "无法导入所选音频，请检查文件内容。"}
	return {"imported": true, "filename": str(workspace.chart.audio_path).get_file(),
		"duration_ms": roundi(workspace.chart.audio_duration_ms), "analysis_reset": true}
