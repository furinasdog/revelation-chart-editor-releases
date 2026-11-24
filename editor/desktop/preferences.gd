extends Node

const DialogLayout := preload("res://desktop/dialog_layout.gd")

const EditorLabels := preload("res://desktop/editor_labels.gd")
const EditorTheme := preload("res://desktop/editor_theme.gd")

signal scale_changed(value: float)
signal import_audio_requested
signal bindings_changed
signal theme_changed
signal tool_requested(id: int)
signal startup_sound_requested()

const FILE := "user://desktop_preferences.cfg"
const ACTIONS := {
	"import_audio": ["导入音频", KEY_I | KEY_MASK_CTRL],
	"save": ["保存谱面", KEY_S | KEY_MASK_CTRL],
	"undo": ["撤销", KEY_Z | KEY_MASK_CTRL],
	"redo": ["重做", KEY_Y | KEY_MASK_CTRL],
	"copy": ["复制", KEY_C | KEY_MASK_CTRL],
	"cut": ["剪切", KEY_X | KEY_MASK_CTRL],
	"paste": ["粘贴", KEY_V | KEY_MASK_CTRL],
	"mirror_x": ["水平镜像粘贴", KEY_B | KEY_MASK_CTRL],
	"mirror_y": ["垂直镜像粘贴", KEY_N | KEY_MASK_CTRL],
	"note_type": ["转换为普通键", KEY_T | KEY_MASK_CTRL],
	"drag_type": ["转换为滑键", KEY_D | KEY_MASK_CTRL],
	"delete": ["删除所选", KEY_F12],
	"play": ["播放 / 暂停", KEY_SPACE],
	"play_here": ["跳到时间指针", KEY_SPACE | KEY_MASK_SHIFT],
	"move_left": ["向前移动", KEY_LEFT],
	"move_right": ["向后移动", KEY_RIGHT],
	"move_up": ["向上移轨", KEY_UP],
	"move_down": ["向下移轨", KEY_DOWN],
	"refresh": ["刷新谱面", KEY_F5],
	"cancel": ["取消编辑操作", KEY_ESCAPE],
	"tool_select": ["选择工具", KEY_1],
	"tool_note": ["普通键工具", KEY_2],
	"tool_slide": ["滑键工具", KEY_3],
	"tool_hold": ["长键工具", KEY_4],
}
const THEME_NAMES := {"system": "跟随系统", "light": "浅色", "dark": "深色", "gray": "工作室灰"}
const TOOL_ACTIONS := {"tool_select": -1, "tool_note": 0, "tool_slide": 1, "tool_hold": 2}

var window_scale := 1.0
var auto_window_scale := true
var analysis_options: Dictionary = {}
var audio_output_device := "Default"
var play_startup_sound := true
var import_matching_lyrics := false
var startup_sound_volume := 0.5
var inspector_split := 0.34
var upper_split := 0.60
var copilot_width := 0.28
var ffmpeg_path := ""
var emotion_models := ""
var limit_emotion_memory := false
var analyze_emotion_automatically := true
var _emotion_models_available := false
var _emotion_auto_toggle: CheckBox
var _emotion_auto_note: Label
var tutorial_experience := ""
var shortcut_scheme := "standard"
var theme_mode := "system"
var last_run_tag := ""
var has_saved_preferences := false
var bindings: Dictionary = {}
var _dialog: Window
var _pages: TabContainer
var _background: ColorRect
var _waveform_page: Control
var _audio_devices: OptionButton
var _device_status: Label
var _messages: Label
var _buttons: Dictionary = {}
var _capture := ""
var _forwarding := false
var _scheme_choice: OptionButton
var _theme_choice: OptionButton

func _ready() -> void:
	load_settings()
	AudioServer.output_device = audio_output_device if audio_output_device in AudioServer.get_output_device_list() else "Default"

func load_settings() -> void:
	var file := ConfigFile.new()
	has_saved_preferences = file.load(FILE) == OK
	last_run_tag = str(file.get_value("updates", "last_run_tag", ""))
	window_scale = clampf(float(file.get_value("display", "scale", 1.0)), 0.75, 2.5)
	auto_window_scale = bool(file.get_value("display", "automatic_scale", true))
	var audio_options: Variant = file.get_value("audio", "analysis_options", {})
	if audio_options is Dictionary:
		analysis_options = audio_options
	audio_output_device = str(file.get_value("audio", "output_device", "Default"))
	play_startup_sound = bool(file.get_value("audio", "play_startup_sound", true))
	import_matching_lyrics = bool(file.get_value("audio", "import_matching_lyrics", false))
	startup_sound_volume = clampf(float(file.get_value("audio", "startup_sound_volume", 0.5)), 0.0, 1.0)
	inspector_split = clampf(float(file.get_value("display", "inspector_split", 0.34)), 0.22, 0.66)
	upper_split = clampf(float(file.get_value("display", "upper_split", 0.60)), 0.36, 0.76)
	copilot_width = clampf(float(file.get_value("display", "copilot_width", 0.28)), 0.13, 0.57)
	ffmpeg_path = str(file.get_value("analysis", "ffmpeg", ""))
	emotion_models = str(file.get_value("analysis", "music2emo_models", ""))
	limit_emotion_memory = bool(file.get_value("analysis", "music2emo_low_memory", false))
	analyze_emotion_automatically = bool(file.get_value("analysis", "music2emo_automatic", true))
	tutorial_experience = str(file.get_value("tutorial", "experience", ""))
	shortcut_scheme = str(file.get_value("shortcuts", "scheme", "standard"))
	theme_mode = str(file.get_value("display", "theme", "dark" if has_saved_preferences else "system"))
	if theme_mode not in THEME_NAMES:
		theme_mode = "system"
	for action: String in ACTIONS:
		bindings[action] = int(file.get_value("shortcuts", action, _default_code(action)))

func save() -> void:
	var file := ConfigFile.new()
	file.set_value("display", "scale", window_scale)
	file.set_value("display", "automatic_scale", auto_window_scale)
	file.set_value("display", "theme", theme_mode)
	file.set_value("updates", "last_run_tag", last_run_tag)
	file.set_value("audio", "analysis_options", analysis_options)
	file.set_value("audio", "output_device", audio_output_device)
	file.set_value("audio", "play_startup_sound", play_startup_sound)
	file.set_value("audio", "import_matching_lyrics", import_matching_lyrics)
	file.set_value("audio", "startup_sound_volume", startup_sound_volume)
	file.set_value("display", "inspector_split", inspector_split)
	file.set_value("display", "upper_split", upper_split)
	file.set_value("display", "copilot_width", copilot_width)
	file.set_value("analysis", "ffmpeg", ffmpeg_path)
	file.set_value("analysis", "music2emo_models", emotion_models)
	file.set_value("analysis", "music2emo_low_memory", limit_emotion_memory)
	file.set_value("analysis", "music2emo_automatic", analyze_emotion_automatically)
	file.set_value("tutorial", "experience", tutorial_experience)
	file.set_value("shortcuts", "scheme", shortcut_scheme)
	for action: String in ACTIONS:
		file.set_value("shortcuts", action, bindings[action])
	file.save(FILE)

func event_for(action: String) -> InputEventKey:
	return _event_from_code(int(bindings.get(action, _default_code(action))))

func _default_code(action: String) -> int:
	if shortcut_scheme == "original" and TOOL_ACTIONS.has(action):
		return KEY_NONE
	if shortcut_scheme == "standard" and action == "play_here":
		return KEY_SPACE | KEY_MASK_CTRL
	return ACTIONS[action][1]

func set_scheme(value: String, reset := true) -> void:
	shortcut_scheme = value if value == "original" else "standard"
	if reset:
		for action: String in ACTIONS:
			bindings[action] = _default_code(action)
	if _scheme_choice:
		_scheme_choice.select(int(shortcut_scheme == "original"))
	_refresh_labels()
	bindings_changed.emit()

func set_theme_mode(value: String) -> void:
	if value not in THEME_NAMES or theme_mode == value:
		return
	theme_mode = value
	if _theme_choice:
		_theme_choice.select(THEME_NAMES.keys().find(theme_mode))
	theme_changed.emit()

func caption(action: String) -> String:
	var key := event_for(action)
	return "未绑定" if key.keycode == KEY_NONE else EditorLabels.shortcut(key)

func selection_gesture() -> String:
	return "上档键＋右键框选" if shortcut_scheme == "original" else "选择工具下左键框选"

func move_gesture() -> String:
	return "控制键＋左键拖动" if shortcut_scheme == "original" else "左键拖动音符主体"

func _event_from_code(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code & KEY_CODE_MASK
	event.ctrl_pressed = (code & KEY_MASK_CTRL) != 0
	event.alt_pressed = (code & KEY_MASK_ALT) != 0
	event.shift_pressed = (code & KEY_MASK_SHIFT) != 0
	event.meta_pressed = (code & KEY_MASK_META) != 0
	return event

func _input(event: InputEvent) -> void:
	if _forwarding or not event is InputEventKey or not event.pressed:
		return
	if _dialog and _dialog.visible:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	var code: int = event.get_keycode_with_modifiers()
	if code == KEY_NONE:
		return
	for action: String in ACTIONS:
		if bindings[action] != code:
			continue
		if action == "import_audio":
			if not event.echo:
				import_audio_requested.emit()
			get_viewport().set_input_as_handled()
		elif TOOL_ACTIONS.has(action):
			if not event.echo:
				tool_requested.emit(TOOL_ACTIONS[action])
			get_viewport().set_input_as_handled()
		elif code != ACTIONS[action][1]:
			var mapped := _event_from_code(ACTIONS[action][1])
			mapped.pressed = true
			mapped.echo = event.echo
			get_viewport().set_input_as_handled()
			_forward.call_deferred(mapped)
		return
	for action: String in ACTIONS:
		if ACTIONS[action][1] == code and bindings[action] != code:
			get_viewport().set_input_as_handled()
			return

func _forward(event: InputEventKey) -> void:
	_forwarding = true
	get_viewport().push_input(event)
	_forwarding = false

func set_waveform_page(page: Control) -> void:
	_waveform_page = page
	_waveform_page.reparent(self, false)

func open(page_name := "") -> void:
	if not _dialog:
		_build_dialog()
	if not page_name.is_empty():
		var page := _pages.get_node_or_null(page_name)
		if page:
			_pages.current_tab = page.get_index()
	_refresh_audio_devices()
	DialogLayout.present(_dialog, Vector2i(640, 540))

func apply_theme(value: Theme) -> void:
	if _dialog:
		_dialog.theme = value
		_background.color = EditorTheme.tone("base")

func _build_dialog() -> void:
	_dialog = Window.new()
	_dialog.title = "编辑器偏好设置"
	_dialog.transient = true
	_dialog.exclusive = true
	_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_PRIMARY_SCREEN
	_dialog.min_size = Vector2i(320, 230)
	_dialog.close_requested.connect(_close)
	_dialog.window_input.connect(_capture_key)
	_dialog.hide()
	add_child(_dialog)
	_background = ColorRect.new()
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog.add_child(_background)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	apply_theme(get_window().theme)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_dialog.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	_pages = TabContainer.new()
	_pages.theme_type_variation = &"DesktopInspectorTabs"
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_pages)
	_build_display_page(_add_page("界面"))
	_build_shortcuts_page(_add_page("快捷键"))
	_build_audio_page(_add_page("音频"))
	if _waveform_page:
		_waveform_page.reparent(_pages, false)
	_build_tools_page(_add_page("分析工具"))
	_pages.tab_changed.connect(func(_tab: int):
		_capture = ""
		_refresh_labels())
	var done := Button.new()
	done.text = "完成"
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.pressed.connect(_close)
	body.add_child(done)

func _add_page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	_pages.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	scroll.add_child(page)
	return page

func _build_display_page(page: VBoxContainer) -> void:
	var appearance := HBoxContainer.new()
	page.add_child(appearance)
	_add_label(appearance, "界面主题")
	_theme_choice = OptionButton.new()
	for value in THEME_NAMES.values():
		_theme_choice.add_item(value)
	_theme_choice.select(THEME_NAMES.keys().find(theme_mode))
	_theme_choice.item_selected.connect(func(index: int):
		set_theme_mode(THEME_NAMES.keys()[index])
		save())
	appearance.add_child(_theme_choice)
	var scale_row := HBoxContainer.new()
	page.add_child(scale_row)
	_add_label(scale_row, "界面缩放")
	var automatic := CheckBox.new()
	automatic.text = "自动"
	automatic.button_pressed = auto_window_scale
	scale_row.add_child(automatic)
	var scale_input := SpinBox.new()
	scale_input.min_value = 75
	scale_input.max_value = 250
	scale_input.step = 5
	scale_input.suffix = "%"
	scale_input.value = window_scale * 100
	scale_input.editable = not auto_window_scale
	scale_row.add_child(scale_input)
	automatic.toggled.connect(func(enabled: bool):
		auto_window_scale = enabled
		scale_input.editable = not enabled
		scale_changed.emit(0.0 if enabled else window_scale)
		save()
	)
	scale_input.value_changed.connect(func(value: float):
		window_scale = value / 100
		scale_changed.emit(window_scale)
		save()
	)
func _build_shortcuts_page(page: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	page.add_child(row)
	_add_label(row, "快捷键方案")
	_scheme_choice = OptionButton.new()
	_scheme_choice.add_item("标准快捷键")
	_scheme_choice.add_item("原版制谱器快捷键")
	_scheme_choice.select(int(shortcut_scheme == "original"))
	_scheme_choice.item_selected.connect(func(index: int):
		set_scheme("original" if index == 1 else "standard")
		save())
	row.add_child(_scheme_choice)
	var reset := Button.new()
	reset.text = "恢复默认快捷键"
	reset.pressed.connect(_reset_keys)
	row.add_child(reset)
	_messages = _add_label(page, "点击快捷键后按下新组合。")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("v_separation", 5)
	page.add_child(grid)
	for action: String in ACTIONS:
		var label := Label.new()
		label.text = ACTIONS[action][0]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		var button := Button.new()
		button.custom_minimum_size.x = 158
		button.pressed.connect(_begin_capture.bind(action))
		grid.add_child(button)
		_buttons[action] = button
	_refresh_labels()

func _build_audio_page(page: VBoxContainer) -> void:
	_add_label(page, "音频输出设备")
	var row := HBoxContainer.new()
	page.add_child(row)
	_audio_devices = OptionButton.new()
	_audio_devices.fit_to_longest_item = false
	_audio_devices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_audio_devices)
	_audio_devices.item_selected.connect(func(index: int):
		audio_output_device = str(_audio_devices.get_item_metadata(index))
		_refresh_audio_devices()
		save())
	var refresh := Button.new()
	refresh.text = "刷新设备"
	refresh.pressed.connect(_refresh_audio_devices)
	row.add_child(refresh)
	_device_status = _add_label(page, "")
	_device_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var startup := CheckButton.new()
	startup.name = "StartupSound"
	startup.text = "播放启动音效"
	startup.button_pressed = play_startup_sound
	startup.toggled.connect(func(enabled: bool):
		play_startup_sound = enabled
		save())
	page.add_child(startup)
	var volume_row := HBoxContainer.new()
	page.add_child(volume_row)
	_add_label(volume_row, "启动音效音量")
	var volume := SpinBox.new()
	volume.max_value = 100
	volume.suffix = "%"
	volume.value = startup_sound_volume * 100
	volume.value_changed.connect(func(value: float):
		startup_sound_volume = value / 100
		save())
	volume_row.add_child(volume)
	var sample := Button.new()
	sample.text = "试听"
	sample.pressed.connect(startup_sound_requested.emit)
	volume_row.add_child(sample)
	var lyrics := CheckButton.new()
	lyrics.text = "导入音频时同时导入同目录同名歌词"
	lyrics.button_pressed = import_matching_lyrics
	lyrics.toggled.connect(func(enabled: bool):
		import_matching_lyrics = enabled
		save())
	page.add_child(lyrics)

func _refresh_audio_devices() -> void:
	var devices := AudioServer.get_output_device_list()
	_audio_devices.clear()
	_audio_devices.add_item("跟随系统默认设备")
	_audio_devices.set_item_metadata(0, "Default")
	var selected := 0
	for device: String in devices:
		if device == "Default":
			continue
		_audio_devices.add_item(device)
		var index := _audio_devices.item_count - 1
		_audio_devices.set_item_metadata(index, device)
		if device == audio_output_device:
			selected = index
	_audio_devices.select(selected)
	var target := str(_audio_devices.get_item_metadata(selected))
	if AudioServer.output_device != target:
		AudioServer.output_device = target
	_device_status.text = "首选设备「%s」当前不可用，暂时使用系统默认设备。" % audio_output_device if target != audio_output_device else ""
	_device_status.visible = not _device_status.text.is_empty()

func _build_tools_page(page: VBoxContainer) -> void:
	_add_label(page, "音频解码工具（FFmpeg）")
	var ffmpeg := LineEdit.new()
	ffmpeg.placeholder_text = "留空时自动查找"
	ffmpeg.text = ffmpeg_path
	ffmpeg.text_changed.connect(func(path: String): ffmpeg_path = path.strip_edges())
	page.add_child(ffmpeg)
	_emotion_auto_toggle = CheckBox.new()
	_emotion_auto_toggle.text = "每次分析时生成情感标注"
	_emotion_auto_toggle.toggled.connect(func(enabled: bool):
		analyze_emotion_automatically = enabled
		save())
	page.add_child(_emotion_auto_toggle)
	var low_memory := CheckBox.new()
	low_memory.text = "低内存情绪分析"
	low_memory.tooltip_text = "分块运行 Music2Emo，保留 30 秒标注。可用内存不足时也会自动使用此模式。"
	low_memory.button_pressed = limit_emotion_memory
	low_memory.toggled.connect(func(enabled: bool):
		limit_emotion_memory = enabled
		save())
	page.add_child(low_memory)
	_emotion_auto_note = _add_label(page, "")
	_emotion_auto_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refresh_emotion_setting()

func set_emotion_models_available(available: bool) -> void:
	_emotion_models_available = available
	_refresh_emotion_setting()

func _refresh_emotion_setting() -> void:
	if not _emotion_auto_toggle:
		return
	_emotion_auto_toggle.disabled = not _emotion_models_available
	_emotion_auto_toggle.set_pressed_no_signal(_emotion_models_available and analyze_emotion_automatically)
	_emotion_auto_note.text = ("也可从「情绪分析」单独分析当前歌曲。" if _emotion_models_available
		else "安装模型后可启用。下载入口位于右上「情绪分析」。")

func _add_label(parent: Control, caption: String) -> Label:
	var label := Label.new()
	label.text = caption
	parent.add_child(label)
	return label

func _close() -> void:
	_capture = ""
	_refresh_labels()
	save()
	_dialog.hide()

func _begin_capture(action: String) -> void:
	_capture = action
	_buttons[action].release_focus()
	_refresh_labels()
	_messages.text = "按下「%s」的新快捷键。" % ACTIONS[action][0]

func _capture_key(event: InputEvent) -> void:
	if _capture.is_empty() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_NONE, KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
		return
	var code: int = event.get_keycode_with_modifiers()
	for action: String in bindings:
		if action != _capture and bindings[action] == code:
			_messages.text = "该组合已用于「%s」。" % ACTIONS[action][0]
			_dialog.set_input_as_handled()
			return
	bindings[_capture] = code
	_capture = ""
	_messages.text = "快捷键已保存。"
	_refresh_labels()
	bindings_changed.emit()
	save()
	_dialog.set_input_as_handled()

func _reset_keys() -> void:
	for action: String in ACTIONS:
		bindings[action] = _default_code(action)
	_capture = ""
	_messages.text = "已恢复默认快捷键。"
	_refresh_labels()
	bindings_changed.emit()
	save()

func _refresh_labels() -> void:
	for action: String in _buttons:
		_buttons[action].text = "按键…" if action == _capture else caption(action)
