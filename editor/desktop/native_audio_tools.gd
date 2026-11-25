extends RefCounted

static func executable(engine: String) -> String:
	var file := "revelation-%s.exe" % engine
	var source := ProjectSettings.globalize_path("res://bin/" + file)
	if FileAccess.file_exists(source):
		return source
	var installed := OS.get_executable_path().get_base_dir().path_join(file)
	return installed if FileAccess.file_exists(installed) else ""

static func ffmpeg(preferred: String) -> String:
	if not preferred.is_empty():
		return preferred
	var custom := OS.get_environment("AUTOREVELATION_FFMPEG")
	if not custom.is_empty():
		return custom
	if OS.get_name() == "Windows":
		var bundled := OS.get_executable_path().get_base_dir().path_join("tools/ffmpeg.exe")
		if FileAccess.file_exists(bundled):
			return bundled
		var source_root := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
		for directory: String in [source_root, source_root.get_base_dir()]:
			var installed := directory.path_join(".conda/Library/bin/ffmpeg.exe")
			if FileAccess.file_exists(installed):
				return installed
	return "ffmpeg"
