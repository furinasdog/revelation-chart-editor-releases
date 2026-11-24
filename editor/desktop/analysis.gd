extends Node

signal completed(audio_path: String, result: Dictionary)
signal progress(stage: String, completed_windows: int, total_windows: int)
signal madmom_download_progress(model: String, source: String, index: int, total: int, downloaded: int, size: int)
signal madmom_download_finished()

const MODEL := "res://models/beat-this-final0.onnx"
const COEFFICIENTS := "res://models/beat-this-frontend.bin"
const PCM_RATE := 22050
const EXTERNAL_RATE := 44100
const MUSIC2EMO_RATE := 24000
const DEFAULT_ACCENT_SENSITIVITY := 50
const MARKER_KEYS := ["beats", "downbeats", "onsets", "accents"]
const ENGINES := ["native", "madmom", "essentia"]
const CAPTURE_TASKS := {
	"native": ["beats", "downbeats", "accents"],
	"madmom": ["beats", "downbeats", "onsets", "accents"],
	"essentia": ["beats", "onsets", "accents", "melody"],
}
const RESULT_KEYS := {
	"beats": "beats", "downbeats": "downbeats", "onsets": "onsets", "accents": "accents",
	"tempo": "tempo_curve", "melody": "melody", "vocal_pitch": "vocal_pitch",
	"emotions": "emotions",
}

var _worker: Thread
var _engine: RefCounted
var _progress_file := ""
var _progress_refresh := 0.0
var _last_progress := ""
var _madmom_download_file := ""
var _madmom_progress_line := ""
var _madmom_refresh := 0.0

func start(audio_path: String, preferred_ffmpeg: String = "", options: Dictionary = {}) -> bool:
	if _worker:
		return false
	_worker = Thread.new()
	var status := _worker.start(_analyze.bind(audio_path, preferred_ffmpeg, options.duplicate(true)))
	if status != OK:
		_worker = null
		return false
	set_process(true)
	return true

func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	if _worker.is_alive():
		_madmom_refresh += delta
		if not _madmom_download_file.is_empty() and _madmom_refresh >= 0.10:
			_madmom_refresh = 0.0
			_read_madmom_download()
		_progress_refresh += delta
		if not _progress_file.is_empty() and _progress_refresh >= 0.16:
			_progress_refresh = 0
			if FileAccess.file_exists(_progress_file):
				var line := FileAccess.get_file_as_string(_progress_file).strip_edges()
				var items := line.split(" ", false)
				if line != _last_progress and items.size() == 2 and items[0].is_valid_int() and items[1].is_valid_int():
					_last_progress = line
					progress.emit("Music2Emo · 推理分段情绪", int(items[0]), int(items[1]))
		return
	var finished: Array = _worker.wait_to_finish()
	_worker = null
	if not _madmom_download_file.is_empty():
		_finish_madmom_track(_madmom_download_file)
	_progress_file = ""
	set_process(false)
	completed.emit(finished[0], finished[1])

func _exit_tree() -> void:
	if _worker and _worker.is_started():
		_worker.wait_to_finish()

func _analyze(audio_path: String, preferred_ffmpeg: String, options: Dictionary) -> Array:
	return [audio_path, analyze_file(audio_path, preferred_ffmpeg, options)]

func analyze_file(audio_path: String, preferred_ffmpeg: String = "", options: Dictionary = {}) -> Dictionary:
	var tasks: Array = options.get("tasks", [])
	if options.get("engine") == "rmvpe" and tasks == ["vocal_pitch"]:
		return _analyze_vocal_pitch(audio_path, preferred_ffmpeg)
	if "emotions" not in tasks:
		return _analyze_rhythm(audio_path, preferred_ffmpeg, options)
	var rhythm_tasks := tasks.filter(func(task: String): return task != "emotions")
	var rhythm_options := options.duplicate()
	rhythm_options.tasks = rhythm_tasks
	var result := {} if rhythm_tasks.is_empty() else _analyze_rhythm(audio_path, preferred_ffmpeg, rhythm_options)
	var emotion := _analyze_emotion(audio_path, preferred_ffmpeg, str(options.get("emotion_models", "")),
		bool(options.get("emotion_low_memory", false)))
	var task_errors: Dictionary = result.get("task_errors", {})
	if emotion.has("error"):
		task_errors["emotions"] = emotion.error
		if rhythm_tasks.is_empty():
			result["error"] = emotion.error
	else:
		result.erase("error")
		result["emotions"] = emotion.emotions
		result["duration_ms"] = maxf(result.get("duration_ms", 0), emotion.duration_ms)
	result["task_errors"] = task_errors
	return result

func _analyze_vocal_pitch(audio_path: String, preferred_ffmpeg: String) -> Dictionary:
	var executable := _engine_executable("rmvpe")
	var model := OS.get_environment("REVELATION_RMVPE_MODEL")
	if model.is_empty():
		model = OS.get_executable_path().get_base_dir().path_join("models/rmvpe.onnx")
	if executable.is_empty() or not FileAccess.file_exists(model):
		return {"error": "安装目录缺少 RMVPE 原生程序或模型。"}
	var base := "user://rmvpe-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var pcm := ProjectSettings.globalize_path(base + ".f32")
	var output := ProjectSettings.globalize_path(base + ".json")
	var failure := _decode(audio_path, _ffmpeg(preferred_ffmpeg), pcm, 16000)
	if not failure.is_empty():
		DirAccess.remove_absolute(pcm)
		return {"error": failure}
	_emit_progress.call_deferred("推理人声音高 · RMVPE")
	var messages := []
	var code := OS.execute(executable, [pcm, output, model], messages, true)
	var file := FileAccess.open(output, FileAccess.READ) if code == 0 else null
	var data: Variant = JSON.parse_string(file.get_as_text()) if file and file.get_length() < 8 * 1024 * 1024 else null
	if file:
		file.close()
	DirAccess.remove_absolute(pcm)
	DirAccess.remove_absolute(output)
	if not data is Dictionary or data.get("source") != "rmvpe" or not data.get("vocal_pitch") is Array:
		printerr("RMVPE: ", "\n".join(messages).left(800))
		return {"error": "RMVPE 推理失败（退出码 %d）。" % code}
	return {"engine": "rmvpe", "vocal_pitch": data.vocal_pitch}

func _analyze_emotion(audio_path: String, preferred_ffmpeg: String, models: String, low_memory: bool) -> Dictionary:
	if not emotion_models_ready(models):
		return {"error": "尚未配置 Music2Emo 的 ONNX 模型。请在「情绪分析」里选择模型目录。"}
	var executable := _engine_executable("music2emo")
	if executable.is_empty():
		return {"error": "安装目录缺少 Music2Emo 原生程序。"}
	var ffmpeg := _ffmpeg(preferred_ffmpeg)
	if ffmpeg.is_empty():
		return {"error": "找不到 FFmpeg。请在偏好设置的「分析工具」配置。"}
	var base := "user://revelation-emotion-%d" % Time.get_ticks_usec()
	var pcm := ProjectSettings.globalize_path(base + ".f32")
	var output := ProjectSettings.globalize_path(base + ".json")
	var progress_path := ProjectSettings.globalize_path(base + ".progress")
	_emit_progress.call_deferred("解码音频 · Music2Emo")
	var failure := _decode(audio_path, ffmpeg, pcm, MUSIC2EMO_RATE)
	if not failure.is_empty():
		DirAccess.remove_absolute(pcm)
		return {"error": failure}
	var messages: Array = []
	_track_emotion.call_deferred(progress_path)
	var arguments := PackedStringArray([pcm, output, ProjectSettings.globalize_path(models), progress_path])
	if low_memory:
		arguments.append("--low-memory")
	var status := OS.execute(executable, arguments, messages, true)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(output)) if status == 0 and FileAccess.file_exists(output) else null
	DirAccess.remove_absolute(pcm)
	DirAccess.remove_absolute(output)
	DirAccess.remove_absolute(progress_path)
	if not parsed is Dictionary or parsed.get("model") != "Music2Emo" or not parsed.get("segments") is Array or parsed.segments.is_empty():
		push_warning("Music2Emo " + "\n".join(messages).strip_edges().left(1000))
		return {"error": "Music2Emo 分析失败（退出码 %d）。请检查模型文件，详细错误见运行日志。" % status}
	return {"emotions": parsed.segments, "duration_ms": parsed.segments.back().end_ms}

func _emit_progress(stage: String) -> void:
	if _worker:
		progress.emit(stage, 0, 0)

func _track_emotion(path: String) -> void:
	if _worker:
		_progress_file = path
		_last_progress = ""
		_progress_refresh = 0.0
		_emit_progress("Music2Emo · 加载模型")

func _track_madmom_download(path: String) -> void:
	if not _worker:
		return
	_madmom_download_file = path
	_madmom_progress_line = ""
	_madmom_refresh = 0.0
	_read_madmom_download()

func _read_madmom_download() -> void:
	if not FileAccess.file_exists(_madmom_download_file):
		return
	var line := FileAccess.get_file_as_string(_madmom_download_file)
	if line == _madmom_progress_line or not line.ends_with("\n"):
		return
	var parts := line.strip_edges().split("\t")
	if parts.size() != 6 or parts[0] not in ["direct", "proxy", "done"]:
		return
	for index in range(1, 5):
		if not parts[index].is_valid_int():
			return
	_madmom_progress_line = line
	if parts[0] == "done":
		madmom_download_finished.emit()
	else:
		madmom_download_progress.emit(parts[5].get_file(), parts[0], int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]))

func _finish_madmom_track(path: String) -> void:
	if _madmom_download_file == path:
		_madmom_download_file = ""
		madmom_download_finished.emit()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

static func emotion_models_ready(path: String) -> bool:
	if path.is_empty():
		return false
	for file: String in ["mert.onnx", "btc.onnx", "emotion.onnx", "metadata.txt"]:
		if not FileAccess.file_exists(path.path_join(file)):
			return false
	return true

func _analyze_rhythm(audio_path: String, preferred_ffmpeg: String, options: Dictionary) -> Dictionary:
	var ffmpeg := _ffmpeg(preferred_ffmpeg)
	var prefix := "user://revelation-analysis-%d" % Time.get_ticks_usec()
	if options.get("spectrum_only", false):
		return _spectrum(audio_path, ffmpeg, prefix + ".png", options.get("figure_span", Vector2i(-1, -1)))
	if options.has("accent_input"):
		return _score_existing_markers(audio_path, ffmpeg, prefix, options.accent_input)
	var engine: String = options.get("engine", "native")
	var tempo_engine: String = options.get("tempo_engine", "native")
	var tasks: Array = options.get("tasks", ["beats", "downbeats", "tempo"])
	var model: String = options.get("model", "default")
	if engine not in ENGINES or tempo_engine not in ENGINES or tasks.is_empty():
		return {"error": "请选择有效的分析引擎与推理内容。"}
	var plans := {}
	var task_errors := {}
	var event_tasks := []
	for task: String in tasks:
		if task == "tempo":
			continue
		if task in CAPTURE_TASKS[engine]:
			event_tasks.append(task)
		else:
			task_errors[task] = "所选引擎不支持这一项。"
	if event_tasks.has("accents"):
		event_tasks.erase("accents")
		var accent_input := "beats" if engine == "native" else "onsets"
		if accent_input not in event_tasks:
			event_tasks.append(accent_input)
	if not event_tasks.is_empty():
		plans[engine] = event_tasks
	if "tempo" in tasks:
		if not plans.has(tempo_engine):
			plans[tempo_engine] = []
		plans[tempo_engine].append("tempo")
	var results := {}
	var duration := 0.0
	var accent_filter := {}
	var accent_source := "beats" if engine == "native" else "onsets"
	for backend: String in plans:
		var rate := PCM_RATE if backend == "native" else EXTERNAL_RATE
		var pcm_path := prefix + "-" + backend + ".f32"
		var error := _decode(audio_path, ffmpeg, pcm_path, rate)
		var result := {}
		if not error.is_empty():
			result = {"error": error}
		else:
			_emit_progress.call_deferred("推理音频 · " + {"native": "Beat This! / 内置速度算法",
				"madmom": "madmom", "essentia": "Essentia"}.get(backend, backend))
			var file := FileAccess.open(pcm_path, FileAccess.READ)
			var count := int(file.get_length() / 4.0) if file else 0
			if file:
				file.close()
			if count < rate * 2 or count > rate * 900:
				result = {"error": "请使用两秒至十五分钟的音频。"}
			elif backend == "native":
				result = _native(FileAccess.get_file_as_bytes(pcm_path).to_float32_array())
			else:
				result = _external(backend, pcm_path, rate, plans[backend], model if backend == engine else "", options)
			duration = maxf(duration, count * 1000.0 / rate)
			if backend == engine and ("accents" in tasks or accent_source in tasks) and not result.has("error"):
				accent_filter = _measure_accent_filter(pcm_path, rate, accent_source, result.get(accent_source, []))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pcm_path))
		results[backend] = result
	var combined := {"duration_ms": duration, "task_errors": task_errors}
	var captured: Dictionary = results.get(engine, {})
	for key: String in MARKER_KEYS + ["melody"]:
		if key not in tasks or task_errors.has(key):
			continue
		if captured.has("error"):
			task_errors[key] = captured.error
		else:
			combined[key] = captured.get(key, [])
			combined["engine"] = engine
	if not accent_filter.is_empty():
		combined["accent_filter"] = accent_filter
	if combined.has("accents"):
		var sensitivity := int(options.get("accent_sensitivity", DEFAULT_ACCENT_SENSITIVITY))
		combined["accents"] = filter_accents(accent_filter.get("points", []), sensitivity)
		combined["accent_sensitivity"] = sensitivity
	if "tempo" in tasks:
		var tempo: Dictionary = results[tempo_engine]
		if tempo.has("error"):
			task_errors["tempo"] = tempo.error
		else:
			combined["tempo_engine"] = tempo_engine
			combined["tempo_curve"] = tempo.get("tempo_curve", []) if tempo_engine == "native" else _external_tempo(tempo, duration)
			var beats: Variant = tempo.get("beats", [])
			if tempo.has("tempo_anchor_ms"):
				combined["tempo_anchor_ms"] = tempo.tempo_anchor_ms
			elif not beats.is_empty():
				combined["tempo_anchor_ms"] = beats[0]
	if task_errors.size() == tasks.size():
		combined["error"] = str(task_errors.values()[0])
	return combined

func _decode(audio_path: String, ffmpeg: String, pcm_path: String, rate: int) -> String:
	if rate != MUSIC2EMO_RATE:
		_emit_progress.call_deferred("解码音频")
	var physical_pcm := ProjectSettings.globalize_path(pcm_path)
	var messages: Array = []
	var exit_code := OS.execute(ffmpeg, [
		"-hide_banner", "-loglevel", "error", "-nostdin", "-y",
		"-protocol_whitelist", "file", "-i", ProjectSettings.globalize_path(audio_path),
		"-map", "0:a:0", "-t", "901", "-ac", "1", "-ar", str(rate),
		"-f", "f32le", physical_pcm,
	], messages, true)
	if exit_code != 0:
		push_warning("\n".join(messages).strip_edges())
		if exit_code < 0:
			return "无法启动 FFmpeg。请检查偏好设置中的解码工具路径。"
		return "FFmpeg 无法解码此文件（退出码 %d）。请检查音频是否完整且含有音轨。" % exit_code
	return ""

func _native(samples: PackedFloat32Array) -> Dictionary:
	if not ClassDB.class_exists("RevelationRhythm"):
		return {"error": "未载入节奏分析组件。请检查安装目录中的运行库。"}
	if not FileAccess.file_exists(MODEL) or not FileAccess.file_exists(COEFFICIENTS):
		return {"error": "找不到随软件分发的节拍模型或频谱参数。"}
	if not _engine:
		var engine: RefCounted = ClassDB.instantiate("RevelationRhythm")
		var error: String = engine.load_model(FileAccess.get_file_as_bytes(MODEL))
		if not error.is_empty():
			push_warning(error)
			return {"error": "无法加载节拍模型。请检查软件文件是否完整。"}
		_engine = engine
	var coefficients := FileAccess.get_file_as_bytes(COEFFICIENTS).to_float32_array()
	var result: Dictionary = _engine.analyze(samples, coefficients)
	if result.has("error"):
		push_warning(str(result.error))
		return {"error": "节奏分析失败。请重试或更换音频。"}
	return result

func _external(engine: String, pcm: String, rate: int, tasks: Array, model: String, options: Dictionary) -> Dictionary:
	var is_madmom := engine == "madmom"
	var response := pcm + ".json"
	var name := "madmom" if is_madmom else "Essentia"
	var executable := _engine_executable(engine)
	if executable.is_empty():
		return {"error": "安装目录中找不到 %s 原生分析程序。请检查安装包是否完整。" % name}
	if not is_madmom and model not in ["multifeature", "degara"]:
		model = "multifeature"
	if model.is_empty():
		model = "default"
	var arguments := PackedStringArray([ProjectSettings.globalize_path(pcm),
		ProjectSettings.globalize_path(response), str(rate), ",".join(tasks), model])
	var download_path := ""
	if is_madmom:
		var cache: String = options.get("madmom_model_cache", "")
		if cache.is_empty():
			cache = OS.get_environment("AUTOREVELATION_MADMOM_MODELS")
		if cache.is_empty():
			cache = "user://madmom-models"
		if FileAccess.file_exists(cache):
			return {"error": "madmom 的模型缓存路径指向文件。请在分析设置中选择文件夹。"}
		arguments.append(ProjectSettings.globalize_path(cache))
		download_path = ProjectSettings.globalize_path(response + ".download")
		arguments.append(download_path)
		_track_madmom_download.call_deferred(download_path)
	var output: Array = []
	var status := OS.execute(executable, arguments, output, true)
	if not download_path.is_empty():
		_finish_madmom_track.call_deferred(download_path)
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(response)) if status == 0 and FileAccess.file_exists(response) else null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(response))
	if status != 0 or not result is Dictionary:
		var details := "\n".join(output).strip_edges()
		push_warning(name + " " + details)
		var lower := details.to_lower()
		if status < 0:
			return {"error": "无法启动 %s 原生分析程序。请检查运行库与文件权限。" % name}
		if is_madmom and "sha-256" in lower:
			return {"error": "下载的 madmom 模型未通过 SHA-256 校验。请重新推理以重试下载。"}
		if is_madmom and "cache" in lower:
			return {"error": "madmom 无法写入模型缓存。请检查缓存路径和写入权限。"}
		if is_madmom and ("http" in lower or "model host" in lower or "model download" in lower):
			return {"error": "madmom 直连 GitHub 和通过 gh-proxy.org 下载均失败。请检查网络，或使用已有的模型缓存。"}
		if status == 0:
			return {"error": "%s 没有返回可读取的分析结果。" % name}
		return {"error": "%s 原生分析程序退出（退出码 %d）。详细错误见运行日志。" % [name, status]}
	return result

func _engine_executable(engine: String) -> String:
	var file := "revelation-%s.exe" % engine
	var source := ProjectSettings.globalize_path("res://bin/" + file)
	if FileAccess.file_exists(source):
		return source
	var installed := OS.get_executable_path().get_base_dir().path_join(file)
	return installed if FileAccess.file_exists(installed) else ""

func _external_tempo(result: Dictionary, duration: float) -> Array:
	var beats: Array = result.get("beats", [])
	var global_bpm := float(result.get("bpm", 0))
	var confidence := float(result.get("confidence", 0))
	var samples: Array[float] = []
	var local_points: Array = []
	for index in range(1, beats.size()):
		var interval := float(beats[index]) - float(beats[index - 1])
		if interval >= 200 and interval <= 1500:
			samples.append(60000.0 / interval)
			local_points.append(float(beats[index - 1]))
	if samples.size() >= 8:
		var smoothed: Array[float] = []
		for index in range(samples.size()):
			var window := samples.slice(maxi(0, index - 3), mini(samples.size(), index + 4))
			window.sort()
			smoothed.append(window[window.size() / 2])
		var sorted := smoothed.duplicate()
		sorted.sort()
		var low: float = sorted[int((sorted.size() - 1) * 0.15)]
		var high: float = sorted[int((sorted.size() - 1) * 0.85)]
		if high > low * 1.055:
			var curve := [{"time_ms": 0.0, "bpm": smoothed[0], "confidence": confidence}]
			for index in range(1, smoothed.size()):
				if local_points[index] > 0.0 and absf(smoothed[index] - float(curve.back().bpm)) > 1.5:
					curve.append({"time_ms": local_points[index], "bpm": smoothed[index], "confidence": confidence})
			return curve
		var interval_bpm: float = sorted[sorted.size() / 2]
		if global_bpm <= 0 or absf(global_bpm / interval_bpm - 0.5) < 0.04 or absf(global_bpm / interval_bpm - 2.0) < 0.08:
			global_bpm = interval_bpm
	if global_bpm <= 0 or not is_finite(global_bpm):
		return []
	return [{"time_ms": 0.0, "bpm": global_bpm, "confidence": confidence},
		{"time_ms": duration, "bpm": global_bpm, "confidence": confidence}]

func _score_existing_markers(audio_path: String, ffmpeg: String, prefix: String, input: Dictionary) -> Dictionary:
	var source: String = input.source
	var rate := PCM_RATE if source == "beats" else EXTERNAL_RATE
	var pcm := prefix + "-accent.f32"
	var error := _decode(audio_path, ffmpeg, pcm, rate)
	var result := {"error": error} if not error.is_empty() else {"accent_filter": _measure_accent_filter(pcm, rate, source, input.markers)}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pcm))
	return result

func _measure_accent_filter(pcm: String, rate: int, source: String, markers: Variant) -> Dictionary:
	return {"source": source, "candidate_count": markers.size(), "points": _accent_scores(pcm, rate, markers)}

static func filter_accents(scores: Array, sensitivity: int) -> Array:
	var threshold := 1.0 - clampi(sensitivity, 0, 100) / 100.0
	var markers: Array = []
	for point: Array in scores:
		if float(point[1]) >= threshold:
			markers.append(point[0])
	return markers

func _accent_scores(pcm: String, rate: int, markers: Variant) -> Array:
	var source := FileAccess.open(pcm, FileAccess.READ)
	if not source or markers.is_empty():
		return []
	var times := PackedFloat64Array()
	var levels := PackedVector2Array()
	var frame_count := int(source.get_length() / 4.0)
	var lead := roundi(rate * 0.045)
	var trail := roundi(rate * 0.09)
	for time: float in markers:
		var anchor := roundi(time * rate / 1000.0)
		if anchor < 0 or anchor >= frame_count:
			continue
		var offset := maxi(0, anchor - lead)
		var before_frames := anchor - offset
		var after_frames := mini(trail, frame_count - anchor)
		if after_frames < roundi(rate * 0.02):
			continue
		source.seek(offset * 4)
		var frames := source.get_buffer((before_frames + after_frames) * 4).to_float32_array()
		var before := 0.0
		var after := 0.0
		for i in range(frames.size()):
			if i < before_frames:
				before += frames[i] * frames[i]
			else:
				after += frames[i] * frames[i]
		times.append(time)
		levels.append(Vector2(sqrt(before / maxi(before_frames, 1)), sqrt(after / after_frames)))
	source.close()
	# Engines provide ordered timestamps. Use the surrounding five seconds to judge
	# energy growth so a loud section cannot suppress accents in a quiet one.
	var scores: Array = []
	var left := 0
	var right := 0
	var local_total := 0.0
	for i in range(times.size()):
		while right < times.size() and times[right] <= times[i] + 2500.0:
			local_total += levels[right].y
			right += 1
		while times[left] < times[i] - 2500.0:
			local_total -= levels[left].y
			left += 1
		var level := levels[i]
		var local_level := minf(local_total / (right - left), level.y * 3.0)
		var rise := level.y - level.x
		var strength := -1.0
		if rise >= 0.0001:
			# At 50%, these ranges require a 25% increase and 8% of local RMS.
			var relative_rise := rise / maxf(level.x, 0.000001)
			var local_rise := rise / maxf(local_level, 0.000001)
			strength = clampf(minf((relative_rise - 0.04) / 0.42, (local_rise - 0.02) / 0.12), -1.0, 1.0)
		scores.append([times[i], strength])
	return scores

func _spectrum(audio: String, ffmpeg: String, path: String, span := Vector2i(-1, -1)) -> Dictionary:
	_emit_progress.call_deferred("FFmpeg · 生成频谱")
	var output: Array = []
	var physical := ProjectSettings.globalize_path(path)
	var cropped := span.x >= 0 and span.y > span.x
	var args := PackedStringArray(["-hide_banner", "-loglevel", "error", "-nostdin", "-y", "-protocol_whitelist", "file"])
	if cropped:
		args.append_array(PackedStringArray(["-ss", "%.3f" % (span.x / 1000.0)]))
	var duration := (span.y - span.x) / 1000.0 if cropped else 900.0
	var filter := "[0:a:0]atrim=duration=%.3f,asetpts=PTS-STARTPTS,showspectrumpic=s=%s:legend=1:scale=log:fscale=log:orientation=vertical:color=intensity[spectrum]" % [
		duration, "720x250" if cropped else "1200x380"]
	args.append_array(PackedStringArray(["-i", ProjectSettings.globalize_path(audio),
		"-filter_complex", filter, "-map", "[spectrum]", "-frames:v", "1", "-update", "1", physical]))
	var status := OS.execute(ffmpeg, args, output, true)
	var bytes := FileAccess.get_file_as_bytes(path) if status == 0 else PackedByteArray()
	DirAccess.remove_absolute(physical)
	if bytes.is_empty():
		push_warning("\n".join(output).strip_edges())
		var error := "无法启动 FFmpeg。请检查偏好设置中的解码工具路径。" if status < 0 else "FFmpeg 无法从该音频生成频谱。请检查文件是否完整且含有音轨。"
		return {"error": error, "spectrum_request": true}
	return {"spectrum": bytes, "spectrum_request": true}

func _ffmpeg(preferred: String) -> String:
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
