extends Node

signal progress(message: String, downloaded: int, total: int, can_cancel: bool)
signal completed(path: String, message: String)

const ASSET_URL := "https://github.com/furinasdog/music2emo-native/releases/download/models-v1/Music2Emo-ONNX-v1.zip"
const PROXY_PREFIX := "https://gh-proxy.org/"
const ARCHIVE_BYTES := 159258931
const ARCHIVE_SHA256 := "3048c7ff326523812cab440f1d086f754d074f663e6cb193a0823dbe65cf6ce0"
const MODEL_ROOT := "user://music2emo-models"
const MODEL_DIRECTORY := MODEL_ROOT + "/v1"
const ENTRY_BYTES := {
	"btc.onnx": 13070783,
	"emotion.onnx": 4327016,
	"mert.onnx": 235865585,
	"metadata.txt": 514,
	"LICENSE-MERT-CC-BY-NC-4.0.txt": 19347,
	"LICENSE-Music2Emo-Apache-2.0.txt": 11358,
	"README.txt": 818,
	"SHA256SUMS.txt": 233,
}
const READY_FILE := ".archive-sha256"
const CONNECT_TIMEOUT_MS := 18000
const STALL_TIMEOUT_MS := 30000

var busy := false
var _request: HTTPRequest
var _install_thread: Thread
var _part := ""
var _staging := ""
var _suffix := ""
var _sources: PackedStringArray
var _source_index := -1
var _downloaded := 0
var _last_activity := 0
var _last_check := 0

func _ready() -> void:
	set_process(false)

func start(sources := PackedStringArray([ASSET_URL, PROXY_PREFIX + ASSET_URL])) -> void:
	if busy or sources.is_empty():
		return
	if _is_verified_install(MODEL_DIRECTORY):
		completed.emit(MODEL_DIRECTORY, "Music2Emo 模型已安装。")
		return
	var status := DirAccess.make_dir_recursive_absolute(MODEL_ROOT)
	if status != OK:
		completed.emit("", "无法创建本机模型目录（错误 %d）。" % status)
		return
	_suffix = "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_part = MODEL_ROOT.path_join(".download-" + _suffix + ".part")
	_staging = MODEL_ROOT.path_join(".install-" + _suffix)
	_sources = sources
	_source_index = 0
	busy = true
	set_process(true)
	_begin_request()

func cancel() -> void:
	if busy and not _install_thread:
		_finish("", "已取消模型下载。")

func _begin_request() -> void:
	_downloaded = 0
	_last_activity = Time.get_ticks_msec()
	_last_check = _last_activity
	var request := HTTPRequest.new()
	request.use_threads = true
	request.accept_gzip = false
	request.max_redirects = 8
	request.body_size_limit = ARCHIVE_BYTES
	request.download_file = _part
	_request = request
	add_child(request)
	request.request_completed.connect(_received.bind(request))
	progress.emit("GitHub 直连 · 正在连接" if _source_index == 0 else "GitHub 直连未完成 · 正在连接 gh-proxy.org",
		0, ARCHIVE_BYTES, true)
	var status := request.request(_sources[_source_index])
	if status != OK:
		_next_source("无法启动下载（错误 %d）。" % status)

func _process(_delta: float) -> void:
	if _install_thread:
		if _install_thread.is_alive():
			return
		var result: Dictionary = _install_thread.wait_to_finish()
		_install_thread = null
		if result.get("bad_download", false):
			_next_source(result.message)
		else:
			_finish(result.get("path", ""), result.message)
		return
	if not _request:
		return
	var now := Time.get_ticks_msec()
	if now - _last_check < 170:
		return
	_last_check = now
	var downloaded := _request.get_downloaded_bytes()
	if downloaded > _downloaded:
		_downloaded = downloaded
		_last_activity = now
		var source := "GitHub 直连" if _source_index == 0 else "gh-proxy.org"
		progress.emit("%s · 正在下载模型" % source, downloaded, ARCHIVE_BYTES, true)
	elif now - _last_activity >= (CONNECT_TIMEOUT_MS if _downloaded == 0 else STALL_TIMEOUT_MS):
		_next_source("连接超时或下载停滞。")

func _received(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, request: HTTPRequest) -> void:
	if request != _request:
		return
	_close_request()
	if result in [HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR]:
		_finish("", "模型文件写入失败。请检查用户目录权限和可用磁盘空间。")
		return
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_next_source("下载失败（HTTP %d，网络状态 %d）。" % [code, result])
		return
	progress.emit("正在校验并安装 Music2Emo 模型…", 0, 0, false)
	_install_thread = Thread.new()
	var status := _install_thread.start(_install.bind(_part, _staging, _suffix))
	if status != OK:
		_install_thread = null
		_finish("", "无法启动模型安装（错误 %d）。" % status)

func _next_source(reason: String) -> void:
	_close_request()
	DirAccess.remove_absolute(_part)
	_source_index += 1
	if _source_index < _sources.size():
		_begin_request()
		return
	_finish("", "模型下载未完成。%s 可重试或从「模型与许可」手动下载。" % reason)

func _close_request() -> void:
	if _request:
		var request := _request
		_request = null
		request.cancel_request()
		request.queue_free()

func _finish(path: String, message: String) -> void:
	_close_request()
	if not _part.is_empty():
		DirAccess.remove_absolute(_part)
	_part = ""
	_staging = ""
	busy = false
	set_process(false)
	completed.emit(path, message)

func _exit_tree() -> void:
	_close_request()
	if _install_thread:
		_install_thread.wait_to_finish()
	if not _part.is_empty():
		DirAccess.remove_absolute(_part)

static func _is_verified_install(directory: String) -> bool:
	var marker := directory.path_join(READY_FILE)
	if not FileAccess.file_exists(marker) or FileAccess.get_file_as_string(marker).strip_edges() != ARCHIVE_SHA256:
		return false
	for filename: String in ENTRY_BYTES:
		var file := FileAccess.open(directory.path_join(filename), FileAccess.READ)
		if not file or file.get_length() != ENTRY_BYTES[filename]:
			return false
	return true

static func _install(part: String, staging: String, suffix: String) -> Dictionary:
	var download := FileAccess.open(part, FileAccess.READ)
	if not download or download.get_length() != ARCHIVE_BYTES:
		return {"bad_download": true, "message": "下载的模型包大小不符。"}
	download.close()
	if FileAccess.get_sha256(part) != ARCHIVE_SHA256:
		return {"bad_download": true, "message": "模型包 SHA-256 校验失败。"}
	var archive := ZIPReader.new()
	if archive.open(part) != OK:
		return {"message": "无法打开已校验的模型包。"}
	var status := DirAccess.make_dir_absolute(staging)
	if status == OK:
		status = _extract(archive, staging)
	archive.close()
	var target := MODEL_DIRECTORY
	if status == OK:
		if _is_verified_install(target):
			_remove_staging(staging)
		else:
			if DirAccess.dir_exists_absolute(target) or FileAccess.file_exists(target):
				target += "-" + suffix
			status = DirAccess.rename_absolute(staging, target)
	if status != OK:
		_remove_staging(staging)
		return {"message": "无法安装已校验的模型包（错误 %d）。请检查磁盘空间和目录权限。" % status}
	return {"path": target, "message": "Music2Emo 模型已安装，可以开始情绪分析。"}

static func _extract(archive: ZIPReader, staging: String) -> Error:
	for filename: String in ENTRY_BYTES:
		var entry := "Music2Emo-ONNX/" + filename
		if not archive.file_exists(entry):
			return ERR_FILE_CORRUPT
		var bytes := archive.read_file(entry)
		if bytes.size() != ENTRY_BYTES[filename]:
			return ERR_FILE_CORRUPT
		var file := FileAccess.open(staging.path_join(filename), FileAccess.WRITE)
		if not file:
			return FileAccess.get_open_error()
		file.store_buffer(bytes)
		file.close()
		var written := FileAccess.open(staging.path_join(filename), FileAccess.READ)
		if not written or written.get_length() != ENTRY_BYTES[filename]:
			return ERR_FILE_CANT_WRITE
	var marker := FileAccess.open(staging.path_join(READY_FILE), FileAccess.WRITE)
	if not marker:
		return FileAccess.get_open_error()
	marker.store_line(ARCHIVE_SHA256)
	marker.close()
	return OK if _is_verified_install(staging) else ERR_FILE_CANT_WRITE

static func _remove_staging(staging: String) -> void:
	for filename: String in ENTRY_BYTES:
		DirAccess.remove_absolute(staging.path_join(filename))
	DirAccess.remove_absolute(staging.path_join(READY_FILE))
	DirAccess.remove_absolute(staging)
