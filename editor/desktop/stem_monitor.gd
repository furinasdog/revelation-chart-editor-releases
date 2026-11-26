extends VBoxContainer

const STEMS := ["", "vocals", "drums", "bass", "other"]
const CAPTIONS := ["预览完整音频", "预览人声分轨", "预览鼓组分轨", "预览贝斯分轨", "预览其他伴奏分轨"]

var _service: Node
var _chart: Node
var _preferences: Node
var _source := ""
var _source_stream_id := 0
var _selection := OptionButton.new()
var _progress := ProgressBar.new()
var _status := Label.new()
var _action := Button.new()

func setup(service: Node, chart: Node, preferences: Node) -> void:
	_service = service
	_chart = chart
	_preferences = preferences
	add_child(HSeparator.new())
	_selection.tooltip_text = "选择预览播放的音轨"
	for caption: String in CAPTIONS:
		_selection.add_item(caption)
	_selection.item_selected.connect(_select_track)
	_selection.get_popup().about_to_popup.connect(service.refresh)
	add_child(_selection)
	_action.pressed.connect(_run)
	add_child(_action)
	_progress.max_value = 1.0
	add_child(_progress)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	service.changed.connect(_update)
	sync_audio()
	_update()

func sync_audio() -> bool:
	var path := ""
	if not _chart.audio_path.is_empty():
		var resolved: String = _chart.resolve_audio_path(_chart.audio_path)
		if not resolved.is_empty():
			path = ProjectSettings.globalize_path(resolved).simplify_path()
	var stream_id := 0
	if _chart.loaded_audio_stream and _chart.loaded_audio_path == path:
		stream_id = _chart.loaded_audio_stream.get_instance_id()
	if _source == path and (stream_id == 0 or stream_id == _source_stream_id):
		return false
	var reloaded := _source == path
	_source = path
	_source_stream_id = stream_id
	if _chart.monitor_audio_stream == null:
		# The full-mix selection stays the same, but the player needs the new recording.
		_chart.monitor_audio_changed.emit()
	else:
		_select_track(0)
	_service.set_audio(path, reloaded)
	_update()
	return true

func _run() -> void:
	if _service.state == "running":
		_service.cancel()
	elif not _source.is_empty():
		_service.preferred_ffmpeg = _preferences.ffmpeg_path
		_service.start()

func _select_track(index: int) -> void:
	if index == 0:
		_selection.select(0)
		_chart.monitor_audio_stream = null
		return
	var path: String = _service.stem_path(STEMS[index])
	var stream: AudioStreamWAV
	if not path.is_empty() and FileAccess.file_exists(path):
		stream = AudioStreamWAV.load_from_file(path)
	if stream == null or stream.get_length() <= 0.0:
		_select_track(0)
		_service.refresh()
		_status.text = "所选分轨无法读取，请重新分轨。"
		_status.show()
		return
	_selection.select(index)
	_chart.monitor_audio_stream = stream

func _update() -> void:
	var ready: bool = _service.state == "ready"
	var running: bool = _service.state == "running"
	for index in range(1, STEMS.size()):
		_selection.set_item_disabled(index, not ready)
	if not ready and _selection.selected != 0:
		_select_track(0)
	_action.disabled = _source.is_empty() or ready
	match _service.state:
		"running": _action.text = "取消分轨"
		"error": _action.text = "重试分轨"
		_: _action.text = "分轨"
	_progress.visible = running
	_progress.value = _service.progress
	_status.text = _service.message
	_status.visible = not _source.is_empty() and not _status.text.is_empty()
