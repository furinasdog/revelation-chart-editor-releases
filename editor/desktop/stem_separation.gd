extends Node

signal changed
signal model_required

const Cache := preload("res://desktop/stem_cache.gd")
const Fingerprint := preload("res://desktop/audio_fingerprint.gd")
const AudioTools := preload("res://desktop/native_audio_tools.gd")
const Models := preload("res://desktop/managed_models.gd")

var state := "idle"
var progress := 0.0
var message := ""
var preferred_ffmpeg := ""
var _audio := ""
var _audio_hash := ""
var _cache_dir := ""
var _work := ""
var _pid := -1
var _elapsed := 0.0
var _fingerprints := Fingerprint.new()

func _ready() -> void:
	set_process(false)

func set_audio(path: String, refresh_hash := false) -> void:
	var absolute := ProjectSettings.globalize_path(path) if not path.is_empty() else ""
	var digest := _fingerprints.read(absolute, refresh_hash) if not absolute.is_empty() else ""
	var folder := Cache.directory(digest, Models.htdemucs_sha256()) if not digest.is_empty() else ""
	if _audio == absolute and _cache_dir == folder:
		return
	_stop_job()
	_audio = absolute
	_audio_hash = digest
	_cache_dir = folder
	refresh()

func refresh() -> void:
	if _pid <= 0:
		if Cache.complete(_cache_dir):
			_update("ready", "", 1.0)
		elif state == "missing_model" and Models.htdemucs_path().is_empty():
			changed.emit()
		else:
			_update("idle")

func stem_path(stem: String) -> String:
	if state != "ready" or stem not in Cache.STEMS:
		return ""
	return _cache_dir.path_join(stem + ".wav")

func start() -> void:
	if _pid > 0:
		return
	set_audio(_audio)
	if _cache_dir.is_empty():
		_update("error", "请先导入音频。")
		return
	if Cache.complete(_cache_dir):
		_update("ready", "", 1.0)
		return
	var model := Models.htdemucs_path()
	if model.is_empty():
		_update("missing_model", "请前往 Hub 安装 HTDemucs 模型。")
		model_required.emit()
		return
	var executable := AudioTools.executable("stems")
	if executable.is_empty():
		_update("error", "安装目录缺少 HTDemucs 原生程序。")
		return
	_work = _cache_dir.get_base_dir().path_join("job-" + Crypto.new().generate_random_bytes(12).hex_encode())
	if DirAccess.make_dir_recursive_absolute(_work) != OK:
		_work = ""
		_update("error", "无法创建分轨缓存目录。")
		return
	_pid = OS.create_process(executable, ["--input", _audio, "--ffmpeg", AudioTools.ffmpeg(preferred_ffmpeg),
		"--model", model, "--output", _work.path_join("output"), "--progress", _work.path_join("progress")])
	if _pid <= 0:
		_stop_job()
		_update("error", "无法启动 HTDemucs。请检查安装目录和运行库。")
		return
	_elapsed = 0.0
	_update("running", "正在加载模型和解码音频…")
	set_process(true)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.12 or _pid <= 0:
		return
	_elapsed = 0
	if OS.is_process_running(_pid):
		var path := _work.path_join("progress")
		if FileAccess.file_exists(path):
			var counts := FileAccess.get_file_as_string(path).strip_edges().split(" ", false)
			if counts.size() == 2 and counts[0].is_valid_int() and counts[1].is_valid_int() and int(counts[1]) > 0:
				var fraction := clampf(float(counts[0]) / float(counts[1]), 0.0, 1.0)
				if fraction != progress:
					_update("running", "分轨中，已完成 %s / %s 段" % [counts[0], counts[1]], fraction)
		return
	var code := OS.get_process_exit_code(_pid)
	_pid = -1
	if code == 0 and _fingerprints.read(_audio, true) != _audio_hash:
		_stop_job()
		set_audio(_audio)
		_update("error", "分轨期间原曲已更改，请重新分轨。")
		return
	var published := code == 0 and Cache.publish(_work.path_join("output"), _cache_dir)
	_stop_job()
	if published:
		_update("ready", "", 1.0)
	else:
		_update("error", "分轨未完成（退出码 %d）。请检查可用磁盘空间和音频后重试。" % code)

func cancel() -> void:
	if _pid > 0:
		_stop_job()
		_update("idle", "已取消分轨。")

func _stop_job() -> void:
	set_process(false)
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
	_pid = -1
	if not _work.is_empty():
		Cache.remove_work_directory(_work)
		_work = ""

func _update(next: String, detail := "", fraction := 0.0) -> void:
	state = next
	message = detail
	progress = fraction
	changed.emit()

func _exit_tree() -> void:
	_stop_job()
