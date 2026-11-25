extends RefCounted

const DEFAULT_SENSITIVITY := 100

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
	var series: String = preload("res://desktop/analysis.gd").RESULT_KEYS[task]
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
	merged["mapping"] = task
	merged["capture_markers"] = _markers(task, result, options.sensitivity, waveform, bucket_ms)
	if task == "accents":
		merged.accents = merged.capture_markers
		merged.accent_sensitivity = options.sensitivity
		merged["accent_filter"] = result.get("accent_filter", {})
	return merged

static func _markers(task: String, result: Dictionary, sensitivity: int, waveform: PackedFloat32Array, bucket_ms: float) -> Array:
	var threshold := 1.0 - clampi(sensitivity, 0, 100) / 100.0
	match task:
		"tempo":
			return []
		"melody":
			var pitched := []
			for point: Dictionary in result.get("melody", []):
				if float(point.get("hz", 0)) > 0 and float(point.get("confidence", 0)) >= threshold:
					pitched.append(point.time_ms)
			return pitched
		"accents":
			var filter: Dictionary = result.get("accent_filter", {})
			if filter.has("points"):
				return preload("res://desktop/analysis.gd").filter_accents(filter.points, sensitivity)
	# Beat and onset backends return timestamps without individual confidences.
	# Use the measured level around each detection to suppress quiet events.
	var times: Array = Array(result.get(task, []))
	if times.is_empty() or waveform.is_empty() or threshold <= 0.0:
		return times
	var levels := PackedFloat32Array()
	var peak := 0.0
	var radius := maxi(1, ceili(35.0 / bucket_ms))
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
