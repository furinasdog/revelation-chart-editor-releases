extends RefCounted

const NAMES := {"madmom": "madmom", "music2emo": "Music2Emo", "htdemucs": "HTDemucs"}
const EMOTION_FILES := ["mert.onnx", "btc.onnx", "emotion.onnx", "metadata.txt"]
const MANIFEST := preload("res://models/model-files.json")

static var _verified: Dictionary = {}
static var _lock := Mutex.new()

static func refresh() -> void:
	_lock.lock()
	_verified.clear()
	_lock.unlock()

static func directory(model: String, preferred: String = "") -> String:
	var location := preferred.strip_edges()
	if location.is_empty():
		location = OS.get_environment("AUTOREVELATION_%s_MODELS" % model.to_upper()).strip_edges()
	if location.is_empty():
		location = "user://%s-models" % model
		if model == "htdemucs":
			location = location.path_join("v1")
		elif model == "music2emo":
			var versioned := location.path_join("v1")
			if FileAccess.file_exists(versioned.path_join("mert.onnx")) or not FileAccess.file_exists(location.path_join("mert.onnx")):
				location = versioned
	return ProjectSettings.globalize_path(location)

static func _matches(path: String, file: Dictionary) -> bool:
	var handle := FileAccess.open(path, FileAccess.READ)
	if not handle or handle.get_length() != int(file.size):
		return false
	handle.close()
	var modified := FileAccess.get_modified_time(path)
	_lock.lock()
	var known: Array = _verified.get(path, [])
	if known.is_empty() or known[0] != modified or known[1] != file.sha256:
		known = [modified, file.sha256, FileAccess.get_sha256(path) == file.sha256]
		_verified[path] = known
	_lock.unlock()
	return known[2]

static func htdemucs_sha256() -> String:
	return MANIFEST.data.htdemucs[0].sha256

static func htdemucs_path() -> String:
	var file: Dictionary = MANIFEST.data.htdemucs[0]
	var path := directory("htdemucs").path_join(file.path)
	return path if _matches(path, file) else ""

static func emotion_ready(path: String) -> bool:
	if path.is_empty():
		return false
	for file: Dictionary in MANIFEST.data.music2emo:
		if file.path in EMOTION_FILES and not _matches(path.path_join(file.path), file):
			return false
	return true

static func madmom_ready(path: String, tasks: Array, model: String) -> bool:
	var prefixes: Array[String] = []
	if "beats" in tasks or "tempo" in tasks:
		prefixes.append("beats/")
	if "downbeats" in tasks:
		prefixes.append("downbeats/")
	if "onsets" in tasks or "accents" in tasks:
		prefixes.append("onsets/2013/onsets_brnn" if model == "recurrent" else "onsets/2013/onsets_cnn")
	for file: Dictionary in MANIFEST.data.madmom:
		for prefix: String in prefixes:
			if str(file.path).begins_with(prefix) and not _matches(path.path_join(file.path), file):
				return false
	return not prefixes.is_empty()

static func open_hub() -> bool:
	for path: String in hub_candidates(OS.has_feature("editor")):
		if path.is_absolute_path() and FileAccess.file_exists(path) and OS.create_process(path, ["--models"]) > 0:
			return true
	return false

static func hub_candidates(source_run: bool) -> PackedStringArray:
	var candidates := PackedStringArray()
	var override := OS.get_environment("AUTOREVELATION_HUB_EXE")
	if not override.is_empty():
		candidates.append(override)
	if source_run:
		var repository := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
		var marker := repository.path_join("更好的制谱器Hub/bin/development-hub.txt")
		if FileAccess.file_exists(marker):
			var local := FileAccess.get_file_as_string(marker).strip_edges().replace("\\", "/")
			if local.is_absolute_path() and local.get_file() == "RevelationHub.exe" and FileAccess.file_exists(local):
				candidates.append(local.simplify_path())
	candidates.append(OS.get_environment("LOCALAPPDATA").path_join("Programs/RevelationHub/RevelationHub.exe"))
	if OS.get_name() == "Windows":
		var lines: Array = []
		if OS.execute("reg.exe", ["query", "HKCU\\Software\\RevelationHub", "/v", "InstallDir"], lines) == 0:
			for line: String in "\n".join(lines).split("\n"):
				if "REG_SZ" in line:
					candidates.append(line.get_slice("REG_SZ", 1).strip_edges().path_join("RevelationHub.exe"))
	return candidates
