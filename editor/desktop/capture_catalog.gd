extends RefCounted

const DEFAULT_SENSITIVITY := 100
const Analysis := preload("res://desktop/analysis.gd")
const StemCache := preload("res://desktop/stem_cache.gd")
const SOURCES := ["mix"] + StemCache.STEMS
const AGENT_ENGINES := ["native", "madmom", "essentia", "music2emo", "rmvpe"]
const AGENT_MODELS := ["default", "multifeature", "degara", "recurrent"]

# Display order, result, engine and model for the capture panel.
const ENTRIES := {
	"beat": {"label": "节拍（Beat This!）", "task": "beats", "engine": "native", "model": "default"},
	"beat-madmom": {"label": "节拍（madmom 循环节拍网络）", "task": "beats", "engine": "madmom", "model": "default"},
	"beat-essentia": {"label": "节拍（Essentia 多特征）", "task": "beats", "engine": "essentia", "model": "multifeature"},
	"beat-degara": {"label": "节拍（Essentia Degara）", "task": "beats", "engine": "essentia", "model": "degara"},
	"downbeat": {"label": "小节重拍（Beat This!）", "task": "downbeats", "engine": "native", "model": "default"},
	"downbeat-madmom": {"label": "小节重拍（madmom 循环重拍网络）", "task": "downbeats", "engine": "madmom", "model": "default"},
	"accent": {"label": "重音（内置力度筛选）", "task": "accents", "engine": "native", "model": "default"},
	"accent-superflux": {"label": "重音（SuperFlux 起音力度筛选）", "task": "accents", "engine": "essentia", "model": "multifeature"},
	"accent-cnn": {"label": "重音（madmom 卷积起音力度筛选）", "task": "accents", "engine": "madmom", "model": "default"},
	"accent-rnn": {"label": "重音（madmom 循环起音力度筛选）", "task": "accents", "engine": "madmom", "model": "recurrent"},
	"onset": {"label": "起音（Essentia SuperFlux）", "task": "onsets", "engine": "essentia", "model": "multifeature"},
	"onset-cnn": {"label": "起音（madmom 卷积起音）", "task": "onsets", "engine": "madmom", "model": "default"},
	"onset-rnn": {"label": "起音（madmom 循环起音）", "task": "onsets", "engine": "madmom", "model": "recurrent"},
	"melody": {"label": "主旋律（Essentia Melodia）", "task": "melody", "engine": "essentia", "model": "multifeature"},
	"tempo": {"label": "BPM（内置速度算法）", "task": "tempo", "engine": "native", "model": "default"},
	"tempo-madmom": {"label": "BPM（madmom 速度估计）", "task": "tempo", "engine": "madmom", "model": "default"},
	"tempo-essentia": {"label": "BPM（Essentia 多特征）", "task": "tempo", "engine": "essentia", "model": "multifeature"},
	"tempo-degara": {"label": "BPM（Essentia Degara）", "task": "tempo", "engine": "essentia", "model": "degara"},
}

static func options(id: String, sensitivity := DEFAULT_SENSITIVITY) -> Dictionary:
	var entry: Dictionary = ENTRIES[id]
	return {"capture_id": id, "engine": entry.engine, "model": entry.model, "tempo_engine": entry.engine,
		"tasks": [entry.task], "sensitivity": clampi(sensitivity, 0, 100)}

static func agent_tasks(engine: String) -> Array:
	match engine:
		"music2emo": return ["emotions"]
		"rmvpe": return ["vocal_pitch"]
	return Analysis.CAPTURE_TASKS[engine] + ["tempo"] if engine in Analysis.ENGINES else []

static func agent_options(arguments: Dictionary) -> Dictionary:
	var stem: Variant = arguments.get("stem", "mix")
	if stem not in SOURCES:
		return {"error": "采音源须为 mix、vocals、drums、bass 或 other。"}
	var sensitivity: Variant = arguments.get("sensitivity", DEFAULT_SENSITIVITY)
	if not (sensitivity is int or sensitivity is float) or not is_finite(sensitivity) or sensitivity != floorf(sensitivity) or sensitivity < 0 or sensitivity > 100:
		return {"error": "采音灵敏度须为 0–100 的整数。"}
	var preset: Variant = arguments.get("capture_id", "")
	if not preset is String or (arguments.has("capture_id") and not ENTRIES.has(preset)):
		return {"error": "未知采音项目。请使用 capture_id 指定自动采音列表中的项目。"}
	var entry: Dictionary = ENTRIES.get(preset, {})
	var engine: Variant = arguments.get("engine", entry.get("engine", "native"))
	if engine not in AGENT_ENGINES:
		return {"error": "请选择 native、madmom、essentia、music2emo 或 rmvpe。"}
	var model: Variant = arguments.get("model", entry.get("model", "default"))
	if not model is String:
		return {"error": "model 须为模型名称。"}
	model = model.to_lower()
	if model == "default" and engine == "essentia":
		model = "multifeature"
	var tasks: Variant = arguments.get("tasks", [] if entry.is_empty() else [entry.task])
	if not tasks is Array or tasks.is_empty() or tasks.size() > 6:
		return {"error": "请提供 1–6 项分析任务，或直接指定 capture_id。"}
	var allowed := agent_tasks(engine)
	var selected: Array = []
	for task: Variant in tasks:
		if task not in allowed:
			return {"error": "该引擎不支持所选任务。", "available": allowed}
		if task not in selected:
			selected.append(task)
	if not _supports_model(engine, model, selected):
		return {"error": "该引擎或任务不支持所选模型。"}
	if not entry.is_empty() and (engine != entry.engine or model != entry.model or selected != [entry.task]):
		return {"error": "capture_id 与指定的引擎、模型或任务不一致。"}
	if arguments.has("sensitivity") and entry.is_empty():
		for id: String in ENTRIES:
			var candidate: Dictionary = ENTRIES[id]
			if selected == [candidate.task] and engine == candidate.engine and model == candidate.model:
				preset = id
				break
		if preset.is_empty():
			return {"error": "灵敏度适用于单个自动采音项目。"}
	var request := {"engine": engine, "tempo_engine": engine, "model": model, "tasks": selected}
	if not preset.is_empty():
		request = options(preset, int(sensitivity))
	request["capture_stem"] = "" if stem == "mix" else stem
	return request

static func _supports_model(engine: String, model: String, tasks: Array) -> bool:
	match engine:
		"essentia":
			return model == "multifeature" or (model == "degara" and ("beats" in tasks or "tempo" in tasks))
		"madmom":
			return model == "default" or (model == "recurrent" and ("onsets" in tasks or "accents" in tasks))
	return model == "default"

static func detected_bpm(task: String, result: Dictionary) -> float:
	if task == "tempo":
		for point: Dictionary in result.get("tempo_curve", []):
			var bpm := float(point.get("bpm", 0))
			if is_finite(bpm) and bpm >= 10.0 and bpm <= 3000.0:
				return bpm
	if task == "beats":
		var reported := float(result.get("beat_bpm", 0))
		if is_finite(reported) and reported >= 10 and reported <= 3000:
			return snappedf(reported, 0.1)
		var beats: Array = Array(result.get("beats", []))
		var intervals: Array[float] = []
		for index in range(1, beats.size()):
			var gap := float(beats[index]) - float(beats[index - 1])
			if gap >= 200 and gap <= 1500:
				intervals.append(gap)
		if intervals.size() >= 3:
			intervals.sort()
			var mid := intervals.size() / 2
			var median := (intervals[mid] + intervals[(intervals.size() - 1) / 2]) * 0.5
			# Average neighboring interval lengths to remove the model frame quantization.
			var total := 0.0
			var count := 0
			for gap: float in intervals:
				if absf(gap - median) <= median * 0.08:
					total += gap
					count += 1
			if count > 0:
				return snappedf(60000.0 * count / total, 0.1)
	return 0.0

static func applied_result(options: Dictionary, result: Dictionary, previous: Dictionary,
		waveform: PackedFloat32Array, bucket_ms: float) -> Dictionary:
	var task: String = options.tasks[0]
	var series: String = Analysis.RESULT_KEYS[task]
	var merged := previous.duplicate()
	merged[series] = result[series]
	for key: String in ["engine", "tempo_engine", "duration_ms"]:
		if result.has(key):
			merged[key] = result[key]
	if task == "tempo":
		merged.erase("tempo_anchor_ms")
		if result.has("tempo_anchor_ms"):
			merged.tempo_anchor_ms = result.tempo_anchor_ms
	merged["capture_id"] = options.capture_id
	merged["capture_sensitivity"] = options.sensitivity
	merged["capture_stem"] = options.get("capture_stem", "")
	merged["mapping"] = task
	var filtered := filtered_series(options, result, waveform, bucket_ms)
	merged["capture_markers"] = [] if task == "tempo" else (
		filtered.map(func(point: Dictionary): return point.time_ms) if task == "melody" else filtered)
	if task == "accents":
		merged.accents = merged.capture_markers
		merged.accent_sensitivity = options.sensitivity
		merged["accent_filter"] = result.get("accent_filter", {})
	return merged

static func filtered_series(options: Dictionary, result: Dictionary, waveform: PackedFloat32Array, bucket_ms: float) -> Array:
	var task: String = options.tasks[0]
	var sensitivity: int = options.sensitivity
	var threshold := 1.0 - clampi(sensitivity, 0, 100) / 100.0
	match task:
		"tempo":
			return Array(result.get("tempo_curve", []))
		"melody":
			var pitched := []
			for point: Dictionary in result.get("melody", []):
				if float(point.get("hz", 0)) > 0 and float(point.get("confidence", 0)) >= threshold:
					pitched.append(point)
			return pitched
		"accents":
			var filter: Dictionary = result.get("accent_filter", {})
			if filter.has("points"):
				return Analysis.filter_accents(filter.points, sensitivity)
	# Beat and onset backends return timestamps without individual confidences.
	# Use the measured level around each detection to suppress quiet events.
	var times: Array = Array(result.get(task, []))
	if times.is_empty() or threshold <= 0.0:
		return times
	var stem_levels: Array = result.get("capture_levels", [])
	if stem_levels.size() == times.size():
		var cutoff := threshold * float(stem_levels.max())
		var markers := []
		for i in times.size():
			if float(stem_levels[i]) >= cutoff:
				markers.append(times[i])
		return markers
	if waveform.is_empty() or not options.get("capture_stem", "").is_empty():
		return times
	var levels := PackedFloat32Array()
	var peak := 0.0
	var radius := maxi(1, ceili(35.0 / maxf(bucket_ms, 0.01)))
	for time: float in times:
		var bucket := floori(time / bucket_ms)
		var level := 0.0
		for i in range(maxi(0, bucket - 1), mini(waveform.size(), bucket + radius + 1)):
			level = maxf(level, waveform[i])
		levels.append(level)
		peak = maxf(peak, level)
	var displayed := []
	for i in range(times.size()):
		if levels[i] >= threshold * peak:
			displayed.append(times[i])
	return displayed
