extends ConfirmationDialog

const Video := preload("res://desktop/video_export.gd")
const Layout := preload("res://desktop/dialog_layout.gd")
const FolderPicker := preload("res://desktop/desktop_file_dialog.gd")

signal requested(path: String, from_ms: int, to_ms: int, options: Dictionary)

var _folder := LineEdit.new()
var _filename := LineEdit.new()
var _size := OptionButton.new()
var _fps := OptionButton.new()
var _quality := OptionButton.new()
var _parallel := CheckBox.new()
var _nvenc := CheckBox.new()
var _hits := CheckBox.new()
var _clip := CheckBox.new()
var _times := HBoxContainer.new()
var _start := SpinBox.new()
var _end := SpinBox.new()
var _error := Label.new()
var _picker := FolderPicker.new()
var _overwrite := ConfirmationDialog.new()
var _source := ""
var _pending := {}

func _ready() -> void:
	title = "渲染视频"
	exclusive = true
	dialog_hide_on_ok = false
	ok_button_text = "开始渲染"
	cancel_button_text = "取消"
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 8)
	add_child(form)
	var directory := HBoxContainer.new()
	_folder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	directory.add_child(_folder)
	var browse := Button.new()
	browse.text = "浏览…"
	browse.pressed.connect(_browse)
	directory.add_child(browse)
	_row(form, "保存到", directory)
	_row(form, "文件名", _filename)
	for resolution: Vector2i in Video.SIZES:
		_size.add_item("%d × %d" % [resolution.x, resolution.y])
	_size.select(Video.SIZES.find(Video.RESOLUTION))
	_row(form, "分辨率", _size)
	for rate: int in Video.RATES:
		_fps.add_item("%d fps" % rate, rate)
	_fps.select(Video.RATES.find(Video.FRAME_RATE))
	_row(form, "帧率", _fps)
	for quality: String in ["标准", "高", "极高"]:
		_quality.add_item(quality)
	_quality.select(1)
	_row(form, "画质", _quality)
	_hits.text = "混入打击音效"
	_hits.button_pressed = true
	_hits.tooltip_text = "使用编辑器当前的打击音量。歌曲音轨始终保留。"
	form.add_child(_hits)
	_parallel.text = "多线程并行渲染"
	_parallel.tooltip_text = "同时准备两帧画面，在后台转换并按时间顺序写入编码器。会占用更多内存和显存。"
	form.add_child(_parallel)
	_nvenc.text = "NVIDIA 硬件编码（NVENC）"
	_nvenc.tooltip_text = "使用显卡的视频编码器输出 H.264。需要支持 NVENC 的显卡和驱动。"
	form.add_child(_nvenc)
	_clip.text = "仅导出指定时段"
	form.add_child(_clip)
	for field: SpinBox in [_start, _end]:
		field.step = 0.001
		field.suffix = "秒"
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if field == _end:
			var to := Label.new()
			to.text = "至"
			_times.add_child(to)
		_times.add_child(field)
	form.add_child(_times)
	_times.hide()
	_clip.toggled.connect(_times.set_visible)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.hide()
	form.add_child(_error)
	_picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_picker.title = "选择视频保存目录"
	_picker.dir_selected.connect(func(path: String): _folder.text = path)
	add_child(_picker)
	_overwrite.title = "替换已有视频"
	_overwrite.ok_button_text = "替换并渲染"
	_overwrite.cancel_button_text = "返回设置"
	_overwrite.exclusive = true
	_overwrite.confirmed.connect(_submit.bind(true))
	add_child(_overwrite)
	confirmed.connect(_confirm_settings)

func _row(parent: Container, caption: String, field: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = caption
	label.custom_minimum_size.x = 68
	row.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	parent.add_child(row)

func open_for(chart: Node) -> void:
	if _folder.text.is_empty():
		_folder.text = OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)
		if not DirAccess.dir_exists_absolute(_folder.text):
			_folder.text = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	var source := str(chart.resolve_audio_path(chart.audio_path))
	if source != _source or _filename.text.is_empty():
		_source = source
		_filename.text = source.get_file().get_basename().validate_filename() + ".mp4"
		_clip.button_pressed = false
		_start.value = 0
	var duration := ceilf(Video.duration_seconds(chart) * 1000.0) / 1000.0
	_start.max_value = duration
	_end.max_value = duration
	_end.value = duration
	_error.hide()
	Layout.present(self, Vector2i(530, 440))

func _browse() -> void:
	if DirAccess.dir_exists_absolute(_folder.text):
		_picker.current_dir = _folder.text
	_picker.open_picker()

func _invalid(message: String, field: Control) -> void:
	_error.text = message
	_error.show()
	field.grab_focus()

func _confirm_settings() -> void:
	var directory := _folder.text.strip_edges().replace("\\", "/")
	if not directory.is_absolute_path() or not DirAccess.dir_exists_absolute(directory):
		_invalid("请选择已存在的保存目录。", _folder)
		return
	var name_text := _filename.text.strip_edges()
	var stem := name_text.left(-4) if name_text.to_lower().ends_with(".mp4") else name_text
	var device := stem.get_slice(".", 0).to_upper()
	if stem.is_empty() or not stem.is_valid_filename() or stem.ends_with(".") or stem.ends_with(" ") or device in ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"] or RegEx.create_from_string("^(COM|LPT)[1-9¹²³]$").search(device) != null:
		_invalid("请输入有效的视频文件名。保存目录请在上方选择。", _filename)
		return
	var path := directory.path_join(stem + ".mp4")
	if DirAccess.dir_exists_absolute(path):
		_invalid("保存目录内有同名文件夹，请更换文件名。", _filename)
		return
	var from_ms := roundi(_start.value * 1000.0) if _clip.button_pressed else 0
	var to_ms := roundi(_end.value * 1000.0) if _clip.button_pressed else -1
	if _clip.button_pressed and to_ms <= from_ms:
		_invalid("结束时间须晚于开始时间。", _end.get_line_edit())
		return
	_pending = {"path": path, "from_ms": from_ms, "to_ms": to_ms, "options": {
		"size": Video.SIZES[_size.selected], "fps": _fps.get_selected_id(), "quality": Video.QUALITIES[_quality.selected],
		"parallel": _parallel.button_pressed, "nvenc": _nvenc.button_pressed, "hits": _hits.button_pressed}}
	_error.hide()
	if FileAccess.file_exists(path):
		_overwrite.dialog_text = "渲染成功后将替换以下视频：\n" + path
		Layout.present(_overwrite, Vector2i(450, 140))
	else:
		_submit(false)

func _submit(replace: bool) -> void:
	_pending.options["replace"] = replace
	hide()
	requested.emit(_pending.path, _pending.from_ms, _pending.to_ms, _pending.options)
