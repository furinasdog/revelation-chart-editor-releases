extends RefCounted

const Analysis := preload("res://desktop/analysis.gd")
const DIRECTORY := "user://analysis-cache"
const SCHEMA := 1
const MAX_TRACKS := 8
const MAX_BYTES := 12 * 1024 * 1024

var _last_path := ""
var _last_stamp := 0
var _last_size := -1
var _last_hash := ""
var _tracks := {}

func fingerprint(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	var size := file.get_length()
	file.close()
	var stamp := FileAccess.get_modified_time(path)
	if path != _last_path or stamp != _last_stamp or size != _last_size:
		_last_path = path
		_last_stamp = stamp
		_last_size = size
		_last_hash = FileAccess.get_sha256(path)
	return _last_hash

func lookup(id: String, options: Dictionary) -> Dictionary:
	var result := {"task_errors": {}, "cache_hits": [], "missing": []}
	var track := _load_track(id)
	for task: String in options.get("tasks", []):
		var key := _key(task, options)
		if track.has(key):
			result.merge(track[key], true)
			result.cache_hits.append(task)
		else:
			result.missing.append(task)
	return result

func store(id: String, options: Dictionary, result: Dictionary) -> void:
	if id.is_empty():
		return
	var track := _load_track(id)
	var changed := false
	for task: String in options.get("tasks", []):
		var series: String = Analysis.RESULT_KEYS.get(task, "")
		if not result.has(series) or result.get("task_errors", {}).has(task):
			continue
		var data := {series: Array(result[series])}
		for name: String in ["duration_ms", "tempo_engine", "engine", "tempo_anchor_ms", "accent_filter", "accent_sensitivity"]:
			if result.has(name) and (name in ["duration_ms", "engine", "tempo_engine"]
					or (task == "tempo" and name == "tempo_anchor_ms") or (task == "accents" and name.begins_with("accent_"))):
				data[name] = result[name]
		track[_key(task, options)] = data
		changed = true
	if not changed:
		return
	_tracks[id] = track
	var json := JSON.stringify({"schema": SCHEMA, "results": track})
	if json.to_utf8_buffer().size() > MAX_BYTES:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var target := DIRECTORY.path_join(id + ".json")
	var temporary := target + ".%d.tmp" % OS.get_process_id()
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		return
	file.store_string(json)
	file.close()
	if DirAccess.rename_absolute(temporary, target) != OK:
		DirAccess.remove_absolute(temporary)
	_prune()

func _load_track(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	if _tracks.has(id):
		return _tracks[id]
	var file := FileAccess.open(DIRECTORY.path_join(id + ".json"), FileAccess.READ)
	var data: Variant = JSON.parse_string(file.get_as_text()) if file and file.get_length() <= MAX_BYTES else null
	if _tracks.size() >= MAX_TRACKS:
		_tracks.erase(_tracks.keys()[0])
	var result: Dictionary = data.results if data is Dictionary and data.get("schema") == SCHEMA and data.get("results") is Dictionary else {}
	_tracks[id] = result
	return result

func _prune() -> void:
	var files: Array = Array(DirAccess.get_files_at(DIRECTORY))
	files = files.filter(func(name: String): return name.length() == 69 and name.ends_with(".json"))
	files.sort_custom(func(a: String, b: String): return FileAccess.get_modified_time(DIRECTORY.path_join(a)) > FileAccess.get_modified_time(DIRECTORY.path_join(b)))
	for index in range(MAX_TRACKS, files.size()):
		DirAccess.remove_absolute(DIRECTORY.path_join(files[index]))

static func _key(task: String, options: Dictionary) -> String:
	if task == "emotions":
		return "emotions:music2emo:" + str(options.get("emotion_model_id", ""))
	var engine := str(options.get("engine", "native"))
	var selected := str(options.get("tempo_engine", "native")) if task == "tempo" else engine
	var model := str(options.get("model", "default")) if selected == engine else "default"
	if selected == "native":
		model = "default"
	elif selected == "essentia" and model != "degara":
		model = "multifeature"
	var sensitivity := int(options.get("accent_sensitivity", Analysis.DEFAULT_ACCENT_SENSITIVITY)) if task == "accents" else 0
	return "%s:%s:%s:%d" % [task, selected, model, sensitivity]
