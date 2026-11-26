extends Node

signal models_refreshed

const DialogLayout := preload("res://desktop/dialog_layout.gd")

const DesktopFileDialog := preload("res://desktop/desktop_file_dialog.gd")
const Preferences := preload("res://desktop/preferences.gd")
const Analysis := preload("res://desktop/analysis.gd")
const AgentAudio := preload("res://desktop/agent_audio.gd")
const AgentAnimation := preload("res://desktop/agent_animation.gd")
const BackgroundTimeline := preload("res://desktop/background_timeline.gd")
const AudioCache := preload("res://desktop/audio_analysis_cache.gd")
const CaptureCatalog := preload("res://desktop/capture_catalog.gd")
const EmotionResults := preload("res://desktop/emotion_results.gd")
const ManagedModels := preload("res://desktop/managed_models.gd")
const TempoPlot := preload("res://desktop/tempo_plot.gd")
const EditorLabels := preload("res://desktop/editor_labels.gd")
const ReferenceMode = preload("res://main/chart_data.gd").ReferenceMode
const ToolPalette := preload("res://desktop/tool_palette.gd")
const NumberDrag := preload("res://desktop/number_drag.gd")
const VideoExport := preload("res://desktop/video_export.gd")
const VideoExportDialog := preload("res://desktop/video_export_dialog.gd")
const Onboarding := preload("res://desktop/onboarding.gd")
const AnalysisPanel := preload("res://desktop/analysis_panel.gd")
const StemSeparation := preload("res://desktop/stem_separation.gd")
const StemMonitor := preload("res://desktop/stem_monitor.gd")
const MelodyPlot := preload("res://desktop/melody_plot.gd")
const EditorTheme := preload("res://desktop/editor_theme.gd")
const About := preload("res://desktop/about.gd")
const SpectrumTheme := preload("res://desktop/spectrum_theme.gdshader")
const LrcLyrics := preload("res://desktop/lrc_lyrics.gd")
const FeatureFinder := preload("res://desktop/feature_finder.gd")
const AutomaticChart := preload("res://desktop/automatic_chart.gd")
const Diagnostics := preload("res://desktop/diagnostics.gd")
const CoPilot := preload("res://desktop/revelation_copilot.gd")
const McpWorkspace := preload("res://desktop/mcp_workspace.gd")
const ScriptWorkspace := preload("res://desktop/script_workspace.gd")
const ChartStorage := preload("res://desktop/chart_storage.gd")
const STARTUP_SOUND := preload("res://desktop/startup.wav")
const BAR := 32.0
const SECTION := 36.0
const TIP_BAR_HEIGHT := 36.0
const GAP := 5.0
const TIMELINE_TOOLBAR_MARGIN := 8.0
const PANE := Color("#202734")
const MUTED := Color("#a9b6c9")

const BRUSH_TIPS := {
	0: "在卷帘轨道内单击，放置普通键。",
	1: "单击放置黄键（滑键）。选中后可在「移动路径与缓动」设置滑动终点。",
	2: "在同一轨道依次点击起点和终点，放置长键。",
	300: "在事件轨上单击，放置更换封面的事件。",
	301: "在事件轨上单击，放置更换底图的事件。",
	302: "在事件轨上单击，放置文本事件。",
	303: "在事件轨上单击，放置重置累计的事件。",
}

var host: Control
var chart: Node
var sidebar: Control
var preview: Control
var grid: Control
var rollout: ScrollContainer
var preferences: Node
var automatic: Node
var copilot: PanelContainer
var mcp := McpWorkspace.new()
var background_mode := false
var scripts := ScriptWorkspace.new()
var _copilot_menu: PopupMenu
var _copilot_item := -1
var _copilot_divider: ColorRect
var _dragging_splitter: ColorRect
var diagnostics := Diagnostics.new()
var _last_diagnostic_edit := -1000
var analysis: Node
var _audio_cache := AudioCache.new()
var _stem_fingerprint := preload("res://desktop/audio_fingerprint.gd").new()
var _capture_stems_ready := false
var _analysis_audio_id := ""
var _analysis_capture_input := {}
var _analysis_dialog: Window
var _analysis_progress_stage: Label
var _analysis_progress_meter: ProgressBar
var _chart_analysis_id := ""
var _chart_analysis_generation := -1
var _tabs: TabContainer
var _results_tabs: TabBar
var _menu: PanelContainer
var _menu_commands := {}
var _inspector_heading: PanelContainer
var _track_bar: PanelContainer
var _result_heading: PanelContainer
var _rail: PanelContainer
var _result: PanelContainer
var _frequency: PanelContainer
var _emotion_panel: PanelContainer
var _emotion: VBoxContainer
var _emotion_feedback := ""
var _model_help: ConfirmationDialog
var _help_model := ""
var _spectrum_image: TextureRect
var _spectrum_caption: Label
var _spectrum_button: Button
var _spectrum_audio := ""
var _melody_plot: Control
var _frequency_tabs: TabContainer
var _analysis_panel: Control
var _stem_separation := StemSeparation.new()
var _stem_monitor := StemMonitor.new()
var _status: Label
var _plot_title: Label
var _frequency_feedback: Label
var _time_display: Label
var _audio_label: Label
var _zoom: HSlider
var _plot: Control
var _apply_bpm: Button
var _analyze: Button
var _tools: Dictionary = {}
var _event_tools: MenuButton
var _tool_entries: Array
var _palette: Control
var _video: Node
var _video_settings: VideoExportDialog
var _video_progress: AcceptDialog
var _video_meter: ProgressBar
var _onboarding: Control
var _inspector_divider: ColorRect
var _timeline_divider: ColorRect
var _file: DesktopFileDialog
var _lyrics_file: DesktopFileDialog
var _image_file: DesktopFileDialog
var _image_event_target := -1
var _image_event_generation := -1
var _background_image_request := {}
var _ask: ConfirmationDialog
var _message: AcceptDialog
var _analyzing := false
var _document_generation := 0
var _analysis_generation := 0
var _analysis_request := {}
var _analysis_title := ""
var _analysis_details := ""
var _analysis_tip_context := ""
var _latest_tempo := false
var _screen_poll := 0.0
var _screen_pixels := Vector2i.ZERO
var _screen_dpi := 96
var _about: Window
var _release_dialog: AcceptDialog
var _feature_finder: Window
var _empty: CenterContainer
var _continue_draft: Button
var _chart_file: DesktopFileDialog
var _save_folder: DesktopFileDialog
var _save_folder_generation := -1
var _inspector_title: Label
var _mode_choice: OptionButton
var _time_snap: CheckButton
var _position_snap: CheckButton
var _canvas_place: Button
var _slide_path: Button
var _background_toggle: Button
var _background_page: VBoxContainer
var _background_status: Label
var _background_assets: Label
var _background_loop: Button
var _background_edit: Button
var _background_selection := {}
var _exit_game_mode: Button
var _preview_controls: MenuButton
var _play_button: Button
var _transport_status: Label
var _tips_bar: PanelContainer
var _tip_label: Label
var _file_feedback := ""
var _file_feedback_until := 0
var _loop_switch: CheckButton
var _loop_range := Vector2(-1, -1)
var _phrase_action: Button
var _loop_seek := false
var _audition := false
var _audition_last_ms := -1.0
var _metronome: Array[AudioStreamPlayer] = []
var _ui_light := false
var _ui_theme: Theme
var _startup_player: AudioStreamPlayer

func _ready() -> void:
	set_process(false)

func attach(editor: Control) -> void:
	host = editor
	# Embedded windows already render at display resolution. Keep their glyphs intact
	# when compositing, while the workspace and preview keep their normal filtering.
	host.get_window().canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	host.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	chart = host.chart_data
	sidebar = host.left_panel
	preview = host.preview_area
	grid = host.grid_canvas
	rollout = host.get_node("ScrollContainer")
	preferences = Preferences.new()
	analysis = Analysis.new()
	automatic = AutomaticChart.new()
	_onboarding = Onboarding.new()
	add_child(preferences)
	add_child(analysis)
	add_child(automatic)
	automatic.setup(self)
	copilot = CoPilot.new()
	host.add_child(copilot)
	copilot.setup(self)
	add_child(mcp)
	mcp.setup(self)
	add_child(scripts)
	scripts.setup(self)
	copilot.visibility_requested.connect(_set_copilot_visible)
	diagnostics.record("editor.open", {"version": ProjectSettings.get_setting("application/config/version")})
	chart.note_added.connect(_record_chart_edit.bind("note.add"))
	chart.note_updated.connect(_record_chart_edit.bind("note.update"))
	chart.note_removed.connect(_record_chart_edit.bind("note.remove"))
	chart.event_added.connect(_record_chart_edit.bind("event.add"))
	chart.event_updated.connect(_record_chart_edit.bind("event.update"))
	chart.event_removed.connect(_record_chart_edit.bind("event.remove"))
	chart.history_navigated.connect(func(action: String): diagnostics.record("chart." + action))
	chart.rt_playback_changed.connect(func(action: String):
		diagnostics.record("preview.playback", {"action": action, "time_ms": roundi(chart.rt_play_time)}))
	analysis.completed.connect(_on_analysis_complete)
	analysis.progress.connect(_show_analysis_stage)
	preferences.import_audio_requested.connect(_open_audio_dialog)
	preferences.scale_changed.connect(_set_scale)
	preferences.bindings_changed.connect(_update_menu_shortcuts)
	preferences.theme_changed.connect(_apply_theme)
	preferences.tool_requested.connect(_choose_tool)
	preferences.startup_sound_requested.connect(_play_startup_sound)
	_build_menu()
	_build_inspector()
	_build_track_bar()
	_build_results()
	_build_dialogs()
	_build_empty()
	_build_tips()
	_setup_input()
	_inspector_divider = _splitter(false)
	_timeline_divider = _splitter(true)
	_copilot_divider = _splitter(false, true)
	host.get_window().focus_exited.connect(_finish_splitter_drag)
	chart.audio_changed.connect(func():
		_emotion_feedback = ""
		_file_feedback = ""
		_clear_analysis_feedback()
		_refresh_audio()
		_refresh_analysis())
	chart.settings_changed.connect(_refresh_tool)
	chart.rhythm_analysis_changed.connect(_refresh_analysis)
	chart.preview_time_changed.connect(_refresh_plot_pointer)
	chart.note_selected.connect(_refresh_inspector)
	chart.note_updated.connect(_refresh_inspector)
	chart.note_removed.connect(_refresh_inspector)
	chart.selection_cleared.connect(_refresh_inspector)
	chart.note_added.connect(_refresh_empty)
	chart.note_removed.connect(_refresh_empty)
	chart.force_refresh_requested.connect(_refresh_empty)
	chart.force_refresh_requested.connect(_refresh_background_selection)
	chart.event_added.connect(_refresh_background_selection)
	chart.event_removed.connect(_refresh_background_selection)
	chart.event_updated.connect(_refresh_background_selection)
	chart.animation_rect_data_changed.connect(_refresh_background_selection)
	chart.background_animations_changed.connect(_refresh_background_selection)
	chart.rt_playback_changed.connect(_play_state_changed)
	grid.time_range_selected.connect(_set_loop_range)
	grid.notes_menu_requested.connect(_open_note_menu)
	grid.background_clip_selected.connect(_select_background_clip)
	preview.resolve_place_time = grid.time_at_playhead
	host.resized.connect(apply_layout)
	_fit_initial_window()
	host.get_window().size_changed.connect(_refresh_scale)
	set_process(DisplayServer.get_name() != "headless")
	_refresh_audio()
	_refresh_analysis()
	_refresh_tool()
	_refresh_inspector()
	_refresh_scale()
	apply_layout()
	host.add_child(_onboarding)
	_onboarding.attach(self)
	_update_menu_shortcuts()
	_apply_theme()
	if not background_mode and DisplayServer.get_name() != "headless":
		_check_release_notice.call_deferred()
	if not background_mode and preferences.play_startup_sound and DisplayServer.get_name() != "headless":
		_play_startup_sound()

func _play_startup_sound() -> void:
	if not _startup_player:
		_startup_player = AudioStreamPlayer.new()
		_startup_player.stream = STARTUP_SOUND
		add_child(_startup_player)
	_startup_player.volume_db = linear_to_db(maxf(0.0001, preferences.startup_sound_volume))
	_startup_player.play()

func _box(name: String, color: Color = PANE) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = name
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	panel.set_meta("theme_surface", color)
	host.add_child(panel)
	return panel

func _label(label: String, size: int = 14) -> Label:
	var node := Label.new()
	node.text = label
	node.add_theme_font_size_override("font_size", size)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func _button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	return button

func _add_menu(row: HBoxContainer, label: String, items: Array) -> PopupMenu:
	var button := MenuButton.new()
	button.theme_type_variation = &"DesktopTopMenu"
	button.text = label
	button.flat = true
	button.switch_on_hover = true
	row.add_child(button)
	var popup := button.get_popup()
	popup.theme_type_variation = &"DesktopCommandPopup"
	for item: Array in items:
		var id := popup.item_count
		if item.is_empty():
			popup.add_separator()
			continue
		popup.add_item(item[0], id)
		if item.size() == 3:
			_menu_commands[item[2]] = [popup, id, item[0]]
	popup.id_pressed.connect(func(id: int):
		var action: Callable = items[id][1]
		diagnostics.record("menu", {"group": label, "command": items[id][0]})
		action.call()
	)
	return popup

func _build_menu() -> void:
	_menu = _box("DesktopMenu", Color("#171d28"))
	var bar_style := _menu.get_theme_stylebox("panel") as StyleBoxFlat
	bar_style.content_margin_top = 2
	bar_style.content_margin_bottom = 2
	var row := HBoxContainer.new()
	_menu.add_child(row)
	_add_menu(row, "文件", [
		["新建谱面", _new_chart], ["打开已有谱面…", _open_chart_dialog], ["恢复上次编辑", _restore_previous_session], [],
		["导入音频…", _open_audio_dialog, "import_audio"], ["导入歌词…", _open_lyrics_dialog],
		["导入背景图片…", _open_background_dialog], ["打开谱面目录…", sidebar._on_set_root_dir], [],
		["保存谱面", _save_chart, "save"], ["另存到目录…", _choose_chart_save_folder], ["导出谱面压缩包…", sidebar._on_export_zip],
		["导出谱面文件…", sidebar._on_export_json], ["渲染视频…", _choose_video_path],
	])
	_add_menu(row, "编辑", [
		["撤销", chart.undo, "undo"], ["重做", chart.redo, "redo"], [],
		["取消选择", chart.clear_all_selections],
		["编辑器偏好设置…", preferences.open],
	])
	_add_menu(row, "视图", [
		["界面缩放…", preferences.open.bind("界面")], ["波形设置…", preferences.open.bind("波形")], ["时间轴适应歌曲", _fit_timeline],
		["普通布局", host.set_preview_focus.bind(false)], ["聚焦预览", host.set_preview_focus.bind(true)],
		["切换自动滚屏", func(): chart.auto_scroll_enabled = not chart.auto_scroll_enabled],
		["刷新谱面", chart.force_refresh, "refresh"],
		["切换边缘滚动", func(): grid.edge_scroll_enabled = not grid.edge_scroll_enabled],
		["手序与引导预览…", _open_hand_guide],
	])
	_add_menu(row, "分析", [
		["自动采音设置", _open_analysis_settings],
		["分析 RMVPE 人声音高", _analyze_vocal_pitch],
		["按当前设置分析", _request_analysis], ["写入谱面速度", _apply_curve],
		["试听采音标记", _audition_analysis],
	])
	_copilot_menu = _add_menu(row, "工具", [
		[CoPilot.TITLE, _toggle_copilot], ["MCP 服务器…", mcp.open], ["Agent 设置…", automatic.open_settings], [],
		["导入参考谱…", scripts.open_reference_import], ["运行 .rpy…", scripts.open_script],
	])
	_copilot_item = 0
	_copilot_menu.set_item_as_checkable(_copilot_item, true)
	_add_menu(row, "帮助", [["功能速查…", _open_feature_finder], ["首次设置…", _onboarding.open],
		["首次制谱教程…", _onboarding.open_beginner], ["原版迁移引导…", _onboarding.open_migration],
		[], ["版本更新公告…", _open_release_notes], ["导出错误包…", _open_diagnostic_export], ["关于更好的制谱器…", _open_about]])
	_audio_label = _label("未导入音频", 13)
	_audio_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_audio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_audio_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_audio_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_audio_label)
	row.add_child(VSeparator.new())
	_time_display = _label("00:00.0")
	_time_display.custom_minimum_size.x = 70
	_time_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_display.tooltip_text = "当前谱面时间（分:秒）"
	_time_display.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_time_display)
	_update_menu_shortcuts()

func _toggle_copilot() -> void:
	_set_copilot_visible(not copilot.visible)

func _current_release_tag() -> String:
	return "v" + str(ProjectSettings.get_setting("application/config/version", ""))

func _check_release_notice() -> void:
	const Notes := preload("res://desktop/release_notes.gd")
	var current := _current_release_tag()
	var previous: String = preferences.last_run_tag
	if current == previous:
		return
	var has_previous: bool = preferences.has_saved_preferences
	if not Notes.should_show(current, previous, has_previous):
		preferences.last_run_tag = current
		preferences.save()
		return
	if _onboarding._chooser.visible:
		await _onboarding._chooser.visibility_changed
	_open_release_notes()
	preferences.last_run_tag = current
	preferences.save()

func _open_release_notes() -> void:
	const Notes := preload("res://desktop/release_notes.gd")
	if not is_instance_valid(_release_dialog):
		_release_dialog = AcceptDialog.new()
		_release_dialog.title = "版本更新公告"
		_release_dialog.ok_button_text = "知道了"
		_release_dialog.dialog_autowrap = true
		_release_dialog.theme = _ui_theme
		_release_dialog.transient = true
		_release_dialog.exclusive = true
		_release_dialog.hide()
		host.add_child(_release_dialog)
	var current := _current_release_tag()
	var lines := PackedStringArray(Notes.ENTRIES.get(current, ["当前版本没有更新公告。"]))
	_release_dialog.dialog_text = current + "\n\n• " + "\n\n• ".join(lines)
	DialogLayout.present(_release_dialog, Vector2i(540, 375))

func _set_copilot_visible(enabled: bool) -> void:
	if not enabled:
		copilot.cancel()
	copilot.visible = enabled
	_copilot_menu.set_item_checked(_copilot_item, enabled)
	apply_layout()

func _record_chart_edit(id: int, action: String) -> void:
	var now := Time.get_ticks_msec()
	if action.ends_with(".update"):
		if now - _last_diagnostic_edit < 300:
			return
		_last_diagnostic_edit = now
	diagnostics.record(action, {"id": id})

func _open_diagnostic_export() -> void:
	var dialog := _create_path_dialog("导出错误包", FileDialog.FILE_MODE_SAVE_FILE, ["*.zip ; 错误包"])
	dialog.current_file = "制谱器-错误包-%s.zip" % Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
	dialog.theme = _ui_theme
	dialog.file_selected.connect(func(path: String):
		dialog.queue_free()
		if _export_diagnostic_bundle(path) == OK:
			DesktopFileDialog.reveal_export(path if path.get_extension().to_lower() == "zip" else path + ".zip"))
	dialog.canceled.connect(dialog.queue_free)
	host.add_child(dialog)
	dialog.open_picker()

func _export_diagnostic_bundle(path: String) -> Error:
	var target := path if path.get_extension().to_lower() == "zip" else path + ".zip"
	var environment := {"application_version": ProjectSettings.get_setting("application/config/version"),
		"godot": Engine.get_version_info().get("string", ""), "platform": OS.get_name(),
		"os_version": OS.get_version(), "renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "window_px": [get_window().size.x, get_window().size.y],
		"dpi": DisplayServer.screen_get_dpi(), "note_count": chart.notes.size(), "event_count": chart.events.size(),
		"audio_duration_ms": roundi(chart.audio_duration_ms)}
	var secrets := PackedStringArray([str(automatic._effective_settings().key), OS.get_environment("OPENAI_API_KEY")])
	diagnostics.record("diagnostics.export")
	var status := diagnostics.export_zip(target, environment, secrets)
	if status != OK:
		diagnostics.record("diagnostics.export", {"error": error_string(status)}, "error")
	_notify("错误包已导出。请检查后随反馈发送。" if status == OK else "错误包导出失败（%s）。" % error_string(status))
	return status

func _open_note_menu(time_ms: int, lane: int, note_id: int) -> void:
	if note_id >= 0 and note_id not in chart.selected_note_ids: chart.select_note(note_id)
	var menu := PopupMenu.new()
	host.add_child(menu)
	for caption in ["复制", "粘贴", "复制为 JSON（跨工程）", "粘贴 JSON（跨工程）", "让助手修改此段", "删除此音符", "手序与引导预览"]:
		menu.add_item(caption)
	for index in [0, 2]: menu.set_item_disabled(index, chart.selected_note_ids.is_empty())
	menu.set_item_disabled(5, note_id < 0)
	menu.set_item_disabled(6, chart.selected_note_ids.is_empty())
	menu.set_item_disabled(1, chart.clipboard_notes.is_empty())
	menu.set_item_disabled(4, _loop_range.y <= _loop_range.x)
	menu.index_pressed.connect(_note_menu_action.bind(time_ms, lane, note_id))
	menu.popup_hide.connect(menu.queue_free)
	menu.position = Vector2i(host.get_viewport().get_mouse_position())
	menu.popup()

func _note_menu_action(index: int, time_ms: int, lane: int, note_id: int) -> void:
	var exchange := preload("res://desktop/note_exchange.gd")
	match index:
		0: chart.clip_copy_selected()
		1, 3: _notify(exchange.paste(chart, time_ms, lane, index == 3))
		2:
			DisplayServer.clipboard_set(exchange.copy(chart))
			_notify("已将音符 JSON 复制到系统剪贴板。")
		4: _open_phrase_edit()
		5: chart.remove_note(note_id)
		6: _open_hand_guide()

func _open_phrase_edit() -> void:
	_set_copilot_visible(true)
	copilot.prepare_selection(_loop_range)

func _open_hand_guide() -> void:
	if chart.selected_note_ids.is_empty():
		_notify("先选中要检查的音符。")
		return
	var guide := preload("res://desktop/hand_guide.gd").new()
	host.add_child(guide)
	guide.open_for(chart, chart.selected_note_id)

func _restore_previous_session() -> void:
	if sidebar.restore_last_session():
		_document_generation += 1
		_fit_timeline()
	else:
		_notify("暂无可恢复的编辑记录。")

func _update_menu_shortcuts() -> void:
	for action: String in _menu_commands:
		var item: Array = _menu_commands[action]
		item[0].set_item_text(item[1], "%s　%s" % [item[2], preferences.caption(action)])
	grid.original_gestures = preferences.shortcut_scheme == "original"
	preview.original_gestures = grid.original_gestures
	for action: String in preferences.TOOL_ACTIONS:
		var id: int = preferences.TOOL_ACTIONS[action]
		if _tools.has(id):
			var hint: String = preferences.selection_gesture() + "；" + preferences.move_gesture() if id == -1 else BRUSH_TIPS.get(id, _tools[id].text)
			_tools[id].tooltip_text = "%s　%s" % [hint, preferences.caption(action)]
	if _play_button:
		_play_button.tooltip_text = "播放或暂停　" + preferences.caption("play")
	if _transport_status:
		_transport_status.tooltip_text = "%s播放／暂停，%s跳到指针。%s。" % [
			preferences.caption("play"), preferences.caption("play_here"), preferences.selection_gesture()]
	if _onboarding:
		_onboarding.refresh_bindings()
	_refresh_tip()

func _build_inspector() -> void:
	sidebar.get_node("编辑器工具").hide()
	sidebar.get_node("editAreaControl").hide()
	_tabs = sidebar.get_node("EditTabs")
	_tabs.theme_type_variation = &"DesktopInspectorTabs"
	_tabs.tabs_visible = true
	_tabs.tab_alignment = TabBar.ALIGNMENT_LEFT
	_tabs.clip_tabs = true
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tabs.offset_left = 6
	_tabs.offset_right = -6
	_tabs.offset_top = SECTION
	var waveform_page := _tabs.get_node_or_null("波形") as Control
	if waveform_page:
		preferences.set_waveform_page(waveform_page)
	_mount_preview_tools()
	_build_background_inspector()
	_analysis_panel = AnalysisPanel.new()
	_analysis_panel.name = "自动采音"
	_tabs.add_child(_analysis_panel)
	_tabs.move_child(_analysis_panel, 0)
	_analysis_panel.setup(preferences, chart, _stem_monitor)
	add_child(_stem_separation)
	_stem_monitor.setup(_stem_separation, chart, preferences)
	_stem_separation.model_required.connect(_show_model_help.bind("htdemucs"))
	_stem_separation.changed.connect(_refresh_capture_sources)
	models_refreshed.connect(_stem_separation.refresh)
	_analysis_panel.source_menu_opened.connect(_refresh_capture_source_menu)
	_analysis_panel.run_requested.connect(_request_analysis)
	_analysis_panel.selection_changed.connect(_refresh_analysis)
	sidebar.capture_page_requested.connect(func(target: String):
		_open_analysis_settings()
		_analysis_panel.select(target))
	_inspector_heading = _box("InspectorHeader")
	var heading := HBoxContainer.new()
	_inspector_heading.add_child(heading)
	_inspector_title = _label("检查器")
	_inspector_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(_inspector_title)
	var page_menu := MenuButton.new()
	page_menu.text = "全部页签"
	page_menu.tooltip_text = "查看检查器中的所有设置页"
	heading.add_child(page_menu)
	var pages := page_menu.get_popup()
	pages.theme_type_variation = &"DesktopMenuPopup"
	for i in range(_tabs.get_tab_count()):
		pages.add_radio_check_item(_tabs.get_tab_title(i), i)
	pages.about_to_popup.connect(func():
		for i in range(pages.item_count):
			pages.set_item_checked(i, i == _tabs.current_tab))
	pages.id_pressed.connect(func(index: int): sidebar.open_settings_tab(index))
	_tabs.current_tab = _analysis_panel.get_index()
	_tabs.tab_changed.connect(func(_index: int): _refresh_tip())
	_tabs.tab_changed.connect(func(_index: int):
		var active := _tabs.get_current_tab_control() == _background_page
		preview.background_track_preview = active
		preview.refresh_from_tab()
		if active:
			if _background_toggle and not grid.background_track_visible:
				_background_toggle.set_pressed_no_signal(true)
				grid.set_background_track_visible(true)
				_refresh_empty()
			_refresh_background_selection())

func _open_inspector_page(page_name: String) -> void:
	var page := _tabs.get_node_or_null(NodePath(page_name))
	if page:
		sidebar.open_settings_tab(page.get_index())

func _build_background_inspector() -> void:
	_background_page = VBoxContainer.new()
	_background_page.name = "背景与遮罩"
	_background_page.add_theme_constant_override("separation", 8)
	_tabs.add_child(_background_page)
	_background_status = _label("", 15)
	_background_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_background_page.add_child(_background_status)
	_background_assets = _label("", 13)
	_background_assets.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_background_page.add_child(_background_assets)
	var edits := HFlowContainer.new()
	_background_page.add_child(edits)
	edits.add_child(_button("切换底图", _choose_background_image.bind(1)))
	edits.add_child(_button("切换遮罩图", _choose_background_image.bind(0)))
	edits.add_child(_button("压暗背景", _add_background_effect.bind(false)))
	edits.add_child(_button("添加圆形揭示", _add_background_effect.bind(true)))
	var selection := HFlowContainer.new()
	_background_page.add_child(selection)
	_background_loop = _button("循环预览此段", _loop_background_clip)
	selection.add_child(_background_loop)
	_background_edit = _button("编辑片段", _edit_background_clip)
	selection.add_child(_background_edit)
	_refresh_background_selection()

func _set_background_track(enabled: bool) -> void:
	_background_toggle.set_pressed_no_signal(enabled)
	if enabled:
		_open_inspector_page("背景与遮罩")
	elif _tabs.get_current_tab_control() == _background_page:
		_open_inspector_page("键设置")
	grid.set_background_track_visible(enabled)
	_refresh_background_selection()
	_refresh_empty()

func _select_background_clip(clip: Dictionary, time_ms: int) -> void:
	_background_selection = clip
	var target := time_ms if clip.is_empty() else clampi(time_ms, clip.start, clip.end - 1)
	if chart.rt_playing:
		chart.pause_rt_playback()
	_set_game_mode(false)
	_open_inspector_page("背景与遮罩")
	chart.set_rt_pointer_time(target)
	_refresh_background_selection()

func _refresh_background_selection(_id := -1) -> void:
	if not grid.background_track_visible and _tabs.get_current_tab_control() != _background_page:
		return
	var assets := ["未设置", "未设置"]
	var time := roundi(chart.get_rt_render_time())
	var selected := {}
	for clip: Dictionary in grid.background_clips():
		if clip.key == grid.background_clip_key:
			selected = clip
		if clip.lane < 2 and time >= clip.start and time < clip.end:
			assets[clip.lane] = clip.title
	_background_selection = selected
	_background_assets.text = "底图  %s\n遮罩  %s" % assets
	_background_status.text = "在时间轴定位，或选中片段查看效果。" if selected.is_empty() else \
		"%s · %s\n%d–%d 毫秒" % [BackgroundTimeline.TITLES[selected.lane], selected.title, selected.start, selected.end]
	_background_loop.disabled = selected.is_empty()
	_background_edit.disabled = selected.is_empty() or (not selected.has("group") and selected.event_id < 0)

func _background_edit_time() -> int:
	return grid.time_at_playhead(chart.get_rt_render_time())

func _choose_background_image(kind: int) -> void:
	_background_image_request = {"kind": kind, "time": _background_edit_time(), "generation": _document_generation}
	_image_event_target = -1
	_image_file.title = "选择底图" if kind == 1 else "选择遮罩图"
	_image_file.open_picker()

func _add_background_effect(reveal: bool) -> void:
	var start := _background_edit_time()
	var duration: int = roundi(chart.audio_duration_ms + chart.audio_delay_ms) if chart.audio_duration_ms > 0 else chart.time_unit_to_ms(chart.total_beats * 64)
	if start >= duration:
		_notify("请在歌曲结束前放置背景事件。")
		return
	var effects := AgentAnimation.new(chart, duration, [])
	var outcome: Dictionary
	if reveal:
		var beat: float = chart.ms_to_beat_position(start)
		var span: int = chart.time_unit_to_ms(roundi((beat + 2.0) * 64.0)) - start
		outcome = effects.add_mask_reveal({"time_ms": start, "duration_ms": mini(maxi(span, 700), duration - start)})
	else:
		var mask := effects.create_solid_mask({"color": "#18202C", "opacity": 0.75})
		outcome = effects.set_mask_cue({"mask_id": mask.mask_id, "time_ms": start})
	if outcome.has("error"):
		_notify(outcome.error)
		return
	if not reveal:
		var root := _get_or_create_root()
		if root.is_empty() or effects.save_assets(root) != OK:
			_notify("无法保存遮罩图片。")
			return
	chart.apply_automatic_notes({}, {}, effects.layers.values(), effects.mask_cues.values())
	for clip: Dictionary in grid.background_clips():
		if clip.start == start and ((reveal and clip.has("group") and clip.title.begins_with("蒙版揭示")) \
		or (not reveal and clip.get("path", "") == outcome.get("image_path", ""))):
			grid.background_clip_key = clip.key
			_select_background_clip(clip, start)
			break

func _loop_background_clip() -> void:
	if _background_selection.is_empty():
		return
	var start: float = _background_selection.start
	var stop: float = _background_selection.end
	if chart.audio_duration_ms > 0.0:
		stop = minf(stop, chart.audio_duration_ms + chart.audio_delay_ms)
	if stop <= start:
		_notify("此片段位于歌曲结束之后。")
		return
	_set_game_mode(true)
	_set_loop_range(Vector2(start, stop))
	_loop_switch.set_pressed_no_signal(true)
	grid.loop_enabled = true
	_play_at(start)

func _edit_background_clip() -> void:
	if _background_selection.has("group"):
		var group: String = _background_selection.group
		_open_inspector_page("动画设置")
		if chart.is_bg_anim_key_group(group):
			sidebar._set_bg_edit_mode("key")
			chart.select_bg_anim_key_slot(chart.bg_anim_key_slot_from_group(group))
		else:
			sidebar._set_bg_edit_mode("group")
			chart.select_anim_group(group)
	elif _background_selection.get("event_id", -1) >= 0:
		_open_inspector_page("事件")
		chart.select_event(_background_selection.event_id)

func _open_feature_finder() -> void:
	_get_feature_finder().open()

func _get_feature_finder() -> Window:
	if not _feature_finder:
		_feature_finder = FeatureFinder.new()
		_feature_finder.hide()
		host.add_child(_feature_finder)
		_feature_finder.setup(self)
	_feature_finder.apply_theme(_ui_theme)
	return _feature_finder

func _copilot_help(query: String) -> Dictionary:
	return _get_feature_finder().help_topics(query)

func _refresh_inspector(_id := -1) -> void:
	var count: int = chart.selected_note_ids.size()
	var summary: Label = sidebar.desktop_note_summary
	summary.visible = count == 1
	sidebar.desktop_note_empty.visible = count == 0
	sidebar.desktop_note_fields.visible = count > 0
	_refresh_preview_buttons()
	if count == 0:
		_inspector_title.text = "检查器"
		return
	var types: Array[int] = []
	for id: int in chart.selected_note_ids:
		var note = chart.get_note_data(id)
		if note and note.type not in types:
			types.append(note.type)
	var label := "音符"
	if types.size() == 1 and types[0] in [0, 1, 2]:
		label = ["普通键", "滑键", "长键"][types[0]]
	_inspector_title.text = "%s · 已选 %d 个" % [label, count]
	if count == 1:
		var note = chart.get_note_data(chart.selected_note_ids[0])
		if note:
			var judge: int = note.judge_time if note.type == 2 else note.end_time
			summary.text = "#%d · %s\n判定 %d 毫秒    时长 %d 毫秒\n位置  %.0f，%.0f" % [
				chart.selected_note_ids[0], chart.ruler_position(judge).label, judge,
				note.end_time - note.start_time, note.position.x, note.position.y]

func _open_about() -> void:
	if not _about:
		_about = About.new()
		host.add_child(_about)
	_about.theme = host.theme
	DialogLayout.present(_about, Vector2i(650, 460))

func _mount_preview_tools() -> void:
	var tools: VBoxContainer = sidebar.get_node("编辑器工具/辅助工具栏")
	var page := ScrollContainer.new()
	page.name = "预览工具"
	page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(page)
	tools.reparent(page, false)
	tools.custom_minimum_size.x = 0
	tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for row: Node in tools.get_children():
		if not row is HBoxContainer:
			continue
		var index := row.get_index()
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 6)
		tools.add_child(flow)
		tools.move_child(flow, index)
		for item: Node in row.get_children():
			item.reparent(flow, false)
		tools.remove_child(row)
		row.queue_free()

func _build_tool_rail(row: Container) -> void:
	_rail = _box("BrushRail", Color("#1b222e"))
	_rail.reparent(row, false)
	var style: StyleBoxFlat = _rail.get_theme_stylebox("panel").duplicate()
	style.content_margin_left = 4
	style.content_margin_right = 4
	_rail.add_theme_stylebox_override("panel", style)
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 4)
	_rail.add_child(tools)
	var label := _label("画笔", 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tools.add_child(label)
	_tool_entries = [
		[-1, "↖", "选择", sidebar._on_clear_pressed],
		[0, "●", "普通键", sidebar._on_tool_pressed.bind(0, null)],
		[1, "◇", "滑键", sidebar._on_tool_pressed.bind(1, null)],
		[2, "━", "长键", sidebar._on_tool_pressed.bind(2, null)],
		[300, "▣", "更换封面", sidebar._on_event_sub_pressed.bind(0)],
		[301, "▧", "更换底图", sidebar._on_event_sub_pressed.bind(1)],
		[302, "文", "文本事件", sidebar._on_event_sub_pressed.bind(2)],
		[303, "⊘", "重置累计", sidebar._on_event_sub_pressed.bind(3)],
	]
	for entry: Array in _tool_entries:
		if entry[0] >= 300:
			continue
		var tool := _button("%s %s" % [entry[1], entry[2]], entry[3])
		tool.theme_type_variation = &"TimelineBrush"
		tool.toggle_mode = true
		tool.custom_minimum_size.x = 26
		tool.tooltip_text = entry[2]
		tool.pressed.connect(_refresh_tool)
		tools.add_child(tool)
		_tools[entry[0]] = tool
	_event_tools = MenuButton.new()
	_event_tools.text = "事件"
	_event_tools.switch_on_hover = false
	_event_tools.get_popup().theme_type_variation = &"DesktopMenuPopup"
	for entry: Array in _tool_entries:
		if entry[0] >= 300:
			_event_tools.get_popup().add_radio_check_item(entry[2], entry[0])
	_event_tools.get_popup().id_pressed.connect(_choose_tool)
	tools.add_child(_event_tools)
	_background_toggle = _button("背景与遮罩", func(): _set_background_track(_background_toggle.button_pressed))
	_background_toggle.toggle_mode = true
	_background_toggle.tooltip_text = "显示与音符共用拍尺的底图、遮罩和背景动画轨"
	tools.add_child(_background_toggle)
	_phrase_action = _button("让助手修改此段", _open_phrase_edit)
	tools.add_child(_phrase_action)
	_phrase_action.hide()

func _choose_tool(id: int) -> void:
	if _tools.has(id):
		_tools[id].pressed.emit()
	elif id >= 300 and id <= 303:
		sidebar._on_event_sub_pressed(id - 300)
		_refresh_tool()

func _build_track_bar() -> void:
	_track_bar = _box("TimelineHeader")
	var rows := VBoxContainer.new()
	_track_bar.add_child(rows)
	_build_tool_rail(rows)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 7)
	rows.add_child(row)
	row.add_child(_label("参考线", 12))
	_mode_choice = OptionButton.new()
	_mode_choice.tooltip_text = "参考模式"
	_mode_choice.add_item("传统参考线", ReferenceMode.TRADITIONAL)
	_mode_choice.add_item("自动采音线", ReferenceMode.BEATS)
	_mode_choice.set_item_tooltip(0, "按工程 BPM、变速节点和拍内细分对齐")
	_mode_choice.set_item_tooltip(1, "显示上一次采音或应用的结果")
	_mode_choice.item_selected.connect(func(index: int): sidebar.set_guide_mode(_mode_choice.get_item_id(index)))
	row.add_child(_mode_choice)
	_time_snap = CheckButton.new()
	_time_snap.text = "时间吸附"
	_time_snap.tooltip_text = "将放键和拖动对齐到当前参考线"
	_time_snap.button_pressed = chart.timeline_snap_enabled
	_time_snap.toggled.connect(func(enabled: bool): sidebar._timeline_snap_checkbox.button_pressed = enabled)
	sidebar._timeline_snap_checkbox.toggled.connect(func(enabled: bool):
		_time_snap.set_pressed_no_signal(enabled)
		_refresh_tip())
	row.add_child(_time_snap)
	row.add_child(VSeparator.new())
	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 2)
	row.add_child(transport)
	_play_button = _button("播放", sidebar._on_rt_play_pause_toggle)
	transport.add_child(_play_button)
	transport.add_child(_button("停止", chart.reset_rt_playback))
	var follow := CheckButton.new()
	follow.text = "自动滚屏"
	follow.tooltip_text = "播放时让时间轴跟随播放指针"
	follow.button_pressed = chart.auto_scroll_enabled
	follow.toggled.connect(func(on: bool): chart.auto_scroll_enabled = on)
	chart.auto_scroll_changed.connect(follow.set_pressed_no_signal)
	chart.auto_scroll_changed.connect(sidebar._auto_scroll_checkbox.set_pressed_no_signal)
	row.add_child(follow)
	_transport_status = _label("已停止", 12)
	_transport_status.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_transport_status)
	row.add_child(VSeparator.new())
	_zoom = HSlider.new()
	_zoom.min_value = log(grid.min_zoom) / log(2.0)
	_zoom.max_value = log(grid.max_zoom) / log(2.0)
	_zoom.step = 0.025
	_zoom.value = log(grid.current_zoom) / log(2.0)
	_zoom.custom_minimum_size.x = 96
	_zoom.tooltip_text = "按住控制键滚动滚轮，可围绕鼠标位置缩放时间轴"
	_zoom.value_changed.connect(func(value: float): grid.set_desktop_zoom(pow(2.0, value)))
	grid.desktop_zoom_changed.connect(func(value: float): _zoom.set_value_no_signal(log(value) / log(2.0)))
	row.add_child(_zoom)
	var fit := _button("适应歌曲", _fit_timeline)
	fit.tooltip_text = "缩放时间轴以显示整首歌"
	row.add_child(fit)
	_track_bar.minimum_size_changed.connect(func(): apply_layout.call_deferred())

func _build_results() -> void:
	_result_heading = _box("PreviewHeader")
	var heading := HBoxContainer.new()
	_result_heading.add_child(heading)
	_results_tabs = TabBar.new()
	_results_tabs.add_tab("谱面预览")
	_results_tabs.add_tab("节奏分析")
	_results_tabs.add_tab("频率显示")
	_results_tabs.add_tab("情绪分析")
	_results_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_results_tabs)
	_canvas_place = _button("在画面放键", _toggle_canvas_place)
	_canvas_place.toggle_mode = true
	_canvas_place.tooltip_text = "播放头决定判定时间，点击处决定画面位置"
	heading.add_child(_canvas_place)
	_slide_path = _button("添加滑动路径", _add_slide_path)
	_slide_path.tooltip_text = "启用黄键的移动路径，然后在预览中拖动终点"
	heading.add_child(_slide_path)
	_preview_controls = MenuButton.new()
	_preview_controls.text = "预览控制"
	var commands := _preview_controls.get_popup()
	commands.theme_type_variation = &"DesktopMenuPopup"
	commands.add_item("从当前拍试玩", 0)
	commands.add_check_item("循环预览选区", 1)
	commands.add_check_item("游戏画面", 2)
	commands.add_check_item("位置吸附", 3)
	commands.add_check_item("在画面放键", 4)
	commands.about_to_popup.connect(func():
		commands.set_item_checked(1, _loop_switch.button_pressed)
		commands.set_item_checked(2, chart.desktop_game_mode)
		commands.set_item_checked(3, chart.preview_grid_enabled)
		commands.set_item_checked(4, chart.preview_place_mode))
	sidebar._preview_place_mode_cb.toggled.connect(func(_pressed: bool): _refresh_preview_buttons())
	_tabs.tab_changed.connect(func(_index: int): _refresh_preview_buttons())
	commands.id_pressed.connect(_preview_command)
	heading.add_child(_preview_controls)
	_loop_switch = CheckButton.new()
	_loop_switch.toggled.connect(_toggle_loop)
	host.add_child(_loop_switch)
	_loop_switch.hide()
	_position_snap = CheckButton.new()
	_position_snap.text = "位置吸附"
	_position_snap.tooltip_text = "拖动预览中的音符时，对齐画面网格"
	_position_snap.button_pressed = chart.preview_grid_enabled
	_position_snap.toggled.connect(func(enabled: bool): sidebar._grid_tool_enabled_cb.button_pressed = enabled)
	chart.preview_grid_changed.connect(func(): _position_snap.set_pressed_no_signal(chart.preview_grid_enabled))
	heading.add_child(_position_snap)
	_exit_game_mode = _button("返回编辑", _set_game_mode.bind(false))
	_exit_game_mode.tooltip_text = "退出游戏画面，继续编辑预览中的音符"
	heading.add_child(_exit_game_mode)
	_result = _box("AnalysisResults")
	var scroll := _result_scroll(_result)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 6)
	scroll.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var title := _label("分析结果")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	_analyze = _button("分析音频", _request_analysis)
	row.add_child(_analyze)
	_status = _label("", 12)
	_status.add_theme_color_override("font_color", MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_plot_title = _label("速度曲线", 12)
	column.add_child(_plot_title)
	_plot = TempoPlot.new()
	_plot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_plot.custom_minimum_size.y = 120
	_plot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_plot)
	var bottom := HBoxContainer.new()
	column.add_child(bottom)
	bottom.add_child(_button("打开自动采音", _open_analysis_settings))
	_apply_bpm = _button("写入谱面速度", _apply_curve)
	bottom.add_child(_apply_bpm)
	_build_frequency_panel()
	_emotion_panel = _box("EmotionResults")
	_emotion = EmotionResults.new()
	_emotion.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_emotion.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_scroll(_emotion_panel).add_child(_emotion)
	_emotion.setup()
	_emotion.analyze_requested.connect(_request_emotion)
	_emotion.models_requested.connect(_open_emotion_models)
	_emotion.hub_requested.connect(_show_model_help.bind("music2emo"))
	_emotion.segment_chosen.connect(func(time: int):
		chart.set_rt_pointer_time(time)
		grid._auto_scroll_to_ms(time))
	_results_tabs.tab_changed.connect(_set_result_tab)
	_set_result_tab(0)

func _preview_command(id: int) -> void:
	match id:
		0: _play_from_current()
		1: _loop_switch.button_pressed = not _loop_switch.button_pressed
		2: _set_game_mode(not chart.desktop_game_mode)
		3: sidebar._grid_tool_enabled_cb.button_pressed = not chart.preview_grid_enabled
		4:
			_canvas_place.set_pressed_no_signal(not chart.preview_place_mode)
			_toggle_canvas_place()

func _set_result_tab(index: int) -> void:
	preview.visible = index == 0
	_result.visible = index == 1
	_frequency.visible = index == 2
	_emotion_panel.visible = index == 3
	_position_snap.visible = index == 0 and not chart.desktop_game_mode
	_exit_game_mode.visible = index == 0 and chart.desktop_game_mode
	_refresh_preview_buttons()
	_refresh_tip()

func _refresh_preview_buttons() -> void:
	if not _canvas_place or not _slide_path:
		return
	var editing: bool = preview.visible and not chart.desktop_game_mode
	_canvas_place.visible = editing
	_canvas_place.set_pressed_no_signal(chart.preview_place_mode and not preview.background_track_preview)
	var note = chart.get_note_data(chart.selected_note_id)
	_slide_path.visible = editing and not preview.background_track_preview and not chart.rt_playing and chart.selected_note_ids.size() == 1 \
		and note != null and note.type == 1 and not chart._move_active(note)

func _toggle_canvas_place() -> void:
	var enabled := _canvas_place.button_pressed
	preview.cancel_canvas_placement()
	if enabled:
		_set_game_mode(false)
		_open_inspector_page("键设置")
		if chart.current_tool_type not in [0, 1, 2]:
			_choose_tool(0)
	sidebar._preview_place_mode_cb.button_pressed = enabled
	_refresh_preview_buttons()

func _add_slide_path() -> void:
	preview.cancel_canvas_placement()
	chart.set_tool_type(-1)
	_open_inspector_page("键设置")
	sidebar.add_slide_path()

func _result_scroll(panel: PanelContainer) -> ScrollContainer:
	# Keep the content's minimum size from expanding the pane across the divider.
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	return scroll

func _build_frequency_panel() -> void:
	_frequency = _box("FrequencyResults")
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_scroll(_frequency).add_child(column)
	_frequency_feedback = _label("", 12)
	_frequency_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_frequency_feedback.hide()
	column.add_child(_frequency_feedback)
	_frequency_tabs = TabContainer.new()
	_frequency_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_frequency_tabs)
	var spectrum := VBoxContainer.new()
	spectrum.name = "频谱"
	_frequency_tabs.add_child(spectrum)
	var row := HBoxContainer.new()
	spectrum.add_child(row)
	_spectrum_caption = _label("横轴为时间，纵轴为频率（赫兹）。颜色越亮，能量越强。", 12)
	_spectrum_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_spectrum_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_spectrum_caption)
	_spectrum_button = _button("生成频谱", _request_spectrum)
	row.add_child(_spectrum_button)
	_spectrum_image = TextureRect.new()
	var spectrum_material := ShaderMaterial.new()
	spectrum_material.shader = SpectrumTheme
	_spectrum_image.material = spectrum_material
	_spectrum_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spectrum_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_spectrum_image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spectrum.add_child(_spectrum_image)
	_melody_plot = MelodyPlot.new()
	_melody_plot.name = "主旋律"
	_frequency_tabs.add_child(_melody_plot)

func _create_path_dialog(title: String, mode: FileDialog.FileMode, filters: PackedStringArray = []) -> DesktopFileDialog:
	var dialog := DesktopFileDialog.new()
	dialog.file_mode = mode
	dialog.title = title
	dialog.filters = filters
	return dialog

func _build_dialogs() -> void:
	_file = _create_path_dialog("导入音频", FileDialog.FILE_MODE_OPEN_FILE, ["*.wav, *.mp3, *.ogg ; 音频文件"])
	_file.file_selected.connect(import_audio)
	host.add_child(_file)
	_lyrics_file = _create_path_dialog("导入歌词", FileDialog.FILE_MODE_OPEN_FILE, ["*.lrc ; LRC 歌词"])
	_lyrics_file.file_selected.connect(import_lyrics)
	host.add_child(_lyrics_file)
	_image_file = _create_path_dialog("导入背景图片", FileDialog.FILE_MODE_OPEN_FILE, ["*.png, *.jpg, *.jpeg ; 背景图片"])
	_image_file.file_selected.connect(_on_image_file_selected)
	_image_file.canceled.connect(func():
		_image_event_target = -1
		_background_image_request.clear())
	sidebar.event_image_import_requested.connect(_open_event_image_dialog)
	host.add_child(_image_file)
	_chart_file = _create_path_dialog("打开已有谱面", FileDialog.FILE_MODE_OPEN_FILE, ["*.zip, *.json ; 谱面压缩包或谱面文件"])
	_chart_file.file_selected.connect(_open_chart_file)
	host.add_child(_chart_file)
	_save_folder = _create_path_dialog("选择谱面保存目录", FileDialog.FILE_MODE_OPEN_DIR)
	_save_folder.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	_save_folder.dir_selected.connect(_on_chart_save_folder_selected)
	_save_folder.canceled.connect(func(): _save_folder_generation = -1)
	host.add_child(_save_folder)
	_ask = ConfirmationDialog.new()
	_ask.title = "分析音频"
	_ask.ok_button_text = "自动分析"
	_ask.cancel_button_text = "暂不分析"
	_ask.about_to_popup.connect(_describe_import_analysis)
	_ask.confirmed.connect(_request_analysis)
	_ask.add_button("调整分析设置", true, "settings")
	_ask.custom_action.connect(func(_action: StringName):
		_ask.hide()
		_open_analysis_settings())
	host.add_child(_ask)
	_message = AcceptDialog.new()
	host.add_child(_message)

func _build_empty() -> void:
	_empty = CenterContainer.new()
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := _box("EmptyProject")
	card.reparent(_empty, false)
	card.custom_minimum_size.x = 330
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	var start := HBoxContainer.new()
	start.alignment = BoxContainer.ALIGNMENT_CENTER
	start.add_theme_constant_override("separation", 8)
	column.add_child(start)
	start.add_child(_button("从音频开始制谱", _open_audio_dialog))
	start.add_child(_button("打开已有谱面", _open_chart_dialog))
	_continue_draft = _button("继续上次编辑", _restore_previous_session)
	column.add_child(_continue_draft)
	host.add_child(_empty)
	_refresh_empty()

func _refresh_empty(_id := -1) -> void:
	if _empty:
		_empty.visible = not grid.background_track_visible and chart.audio_path.is_empty() and chart.notes.is_empty() and chart.events.is_empty()
		if _empty.visible:
			_continue_draft.visible = sidebar.has_saved_session()
	_refresh_tip()

func _build_tips() -> void:
	_tips_bar = _box("WorkspaceTips", Color("#171d28"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_tips_bar.add_child(row)
	_tip_label = _label("", 13)
	_tip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_tip_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_tip_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_tip_label)
	_tips_bar.minimum_size_changed.connect(func(): apply_layout.call_deferred())

func _refresh_tip() -> void:
	if not _tip_label:
		return
	var context := _context_tip()
	if context != _analysis_tip_context:
		_analysis_tip_context = ""
	_tip_label.text = context if _analysis_tip_context.is_empty() else _analysis_title
	if not _file_feedback.is_empty() and not _analyzing:
		_tip_label.text = _file_feedback
	_tip_label.tooltip_text = _tip_label.text
	if not _analysis_tip_context.is_empty() and not _analysis_details.is_empty():
		_tip_label.tooltip_text += "\n" + _analysis_details

func show_file_feedback(message: String) -> void:
	if not _tip_label:
		return
	_file_feedback = message
	_file_feedback_until = Time.get_ticks_msec() + 6000
	_refresh_tip()

func _context_tip() -> String:
	if _analyzing:
		return "正在分析音频。完成后可试听抓取结果。"
	if _empty.visible:
		return "拖入音频开始制谱，或拖入已有谱面继续编辑。"
	if _tabs.current_tab == _analysis_panel.get_index():
		return "选择采音内容和模型，再点「采音」或「应用」。"
	match _results_tabs.current_tab:
		1: return "在「自动采音」选择时间轴上要显示的结果。「写入谱面速度」可保存速度变化。"
		2: return "在「频谱」查看各频率的能量，也可切换到「主旋律」。"
	if chart.desktop_game_mode:
		return "点击预览右上的「返回编辑」，继续调整音符。"
	if chart.rt_playing:
		return "开启「自动滚屏」，卷帘会跟随播放指针。"
	var tool: int = chart.current_tool_type
	if tool == 3:
		return BRUSH_TIPS.get(300 + int(chart.current_event_subtype), "在事件轨上单击，放置当前事件。")
	var tip: String = BRUSH_TIPS.get(tool, "%s。用%s移动音符。" % [
		preferences.selection_gesture(), preferences.move_gesture()])
	if chart.timeline_snap_enabled:
		match grid.reference_mode:
			ReferenceMode.TRADITIONAL: tip += " 时间吸附对齐手动速度网格。"
			ReferenceMode.BEATS: tip += " 时间吸附对齐抓取的标记。"
	return tip

func _open_chart_dialog() -> void:
	_chart_file.open_picker()

func _open_chart_folder(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if not dir:
		_notify("无法打开所选目录。")
		return
	var charts: Array[String] = []
	for name: String in dir.get_files():
		if name.get_extension().to_lower() == "json":
			charts.append(name)
	if charts.has("chart.json"):
		_open_chart_file(folder.path_join("chart.json"))
	elif charts.size() == 1:
		_open_chart_file(folder.path_join(charts[0]))
	elif charts.is_empty():
		_notify("所选目录没有谱面文件。首次保存请使用「文件 → 保存谱面」。")
	else:
		_chart_file.current_dir = folder
		_open_chart_dialog()

func _open_chart_file(path: String) -> bool:
	var loaded: bool = sidebar._on_zip_selected(path) if path.get_extension().to_lower() == "zip" else sidebar._on_file_selected_for_import(path)
	diagnostics.record("chart.open", {"format": path.get_extension().to_lower(), "loaded": loaded}, "info" if loaded else "error")
	if not loaded:
		_notify("无法读取该谱面。请检查文件或压缩包内容。")
		return false
	_document_generation += 1
	_refresh_audio()
	_fit_timeline()
	_set_loop_range(Vector2(-1, -1))
	return true

func _splitter(horizontal: bool, co_pilot := false) -> ColorRect:
	var splitter := ColorRect.new()
	splitter.color = EditorTheme.tone("line")
	splitter.mouse_default_cursor_shape = Control.CURSOR_VSIZE if horizontal else Control.CURSOR_HSIZE
	splitter.tooltip_text = "拖动调整对话栏宽度" if co_pilot else ("拖动调整钢琴卷帘高度" if horizontal else "拖动调整检查器宽度")
	splitter.mouse_filter = Control.MOUSE_FILTER_STOP
	splitter.mouse_entered.connect(func(): splitter.color = EditorTheme.tone("accent"))
	splitter.mouse_exited.connect(func(): splitter.color = EditorTheme.tone("line"))
	splitter.visibility_changed.connect(func():
		if _dragging_splitter == splitter and not splitter.is_visible_in_tree():
			_finish_splitter_drag())
	splitter.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging_splitter = splitter
			elif _dragging_splitter == splitter:
				_finish_splitter_drag()
			return
		if not event is InputEventMouseMotion or _dragging_splitter != splitter:
			return
		if not event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_finish_splitter_drag()
			return
		if co_pilot:
			var width: float = host.size.x - splitter.position.x - event.relative.x
			preferences.copilot_width = clampf(width / maxf(host.size.x, 1.0), 0.13, 0.57)
		elif horizontal:
			var available := maxf(host.size.y - BAR - GAP - TIMELINE_TOOLBAR_MARGIN, 1)
			preferences.upper_split = clampf((splitter.position.y + event.relative.y - BAR) / available, 0.36, 0.76)
		else:
			preferences.inspector_split = clampf((splitter.position.x + event.relative.x) / maxf(rollout.size.x - GAP, 1), 0.22, 0.66)
		apply_layout()
	)
	host.add_child(splitter)
	return splitter

func _finish_splitter_drag() -> void:
	if _dragging_splitter:
		_dragging_splitter = null
		preferences.save()

func _place(control: Control, rect: Rect2) -> void:
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size

func apply_layout() -> void:
	if not _copilot_divider:
		return
	var full_width := host.size.x
	var dock_width := clampf(full_width * preferences.copilot_width, 250.0, maxf(250.0, full_width - 560.0)) if copilot.visible else 0.0
	var w := maxf(full_width - dock_width, 1.0)
	_copilot_divider.visible = copilot.visible
	var h := host.size.y
	var focus: bool = host._layout_mode == "preview_focus"
	var upper_height := maxf(h - BAR - GAP - TIMELINE_TOOLBAR_MARGIN, 1) * (0.83 if focus else float(preferences.upper_split))
	var inspector_width := maxf(w - GAP, 1) * (0.24 if focus else float(preferences.inspector_split))
	_inspector_divider.visible = not focus
	_timeline_divider.visible = not focus
	var right_x := inspector_width + GAP
	var right_width := maxf(w - right_x, 0)
	var divider_y := BAR + upper_height
	var timeline_y := divider_y + GAP + TIMELINE_TOOLBAR_MARGIN
	_place(_menu, Rect2(0, 0, full_width, BAR))
	_place(sidebar, Rect2(0, BAR, inspector_width, upper_height))
	_place(_inspector_heading, Rect2(0, BAR, inspector_width, SECTION))
	_place(_inspector_divider, Rect2(inspector_width, BAR, GAP, upper_height))
	_place(_result_heading, Rect2(right_x, BAR, right_width, SECTION))
	var right_content := Rect2(right_x, BAR + SECTION, right_width, maxf(upper_height - SECTION, 0))
	_place(preview, right_content)
	_place(_result, right_content)
	_place(_frequency, right_content)
	_place(_emotion_panel, right_content)
	_place(_timeline_divider, Rect2(0, divider_y, w, GAP))
	var track_height := maxf(SECTION * 2, _track_bar.get_combined_minimum_size().y)
	_place(_track_bar, Rect2(0, timeline_y, w, track_height))
	var slots_y := timeline_y + track_height
	if host._anim_rect_slot_panel and host._anim_rect_slot_panel.visible:
		_place(host._anim_rect_slot_panel, Rect2(0, slots_y, w, 40))
		slots_y += 40
	if host._anim_layout_btn:
		# The right preview is already independent of the animation tracks.
		host._anim_layout_btn.hide()
	var tips_height := maxf(TIP_BAR_HEIGHT, _tips_bar.get_combined_minimum_size().y)
	var timeline_bottom := maxf(h - tips_height, 0)
	_place(rollout, Rect2(0, slots_y, w, maxf(timeline_bottom - slots_y, 0)))
	_place(_tips_bar, Rect2(0, timeline_bottom, full_width, tips_height))
	if copilot.visible:
		_place(_copilot_divider, Rect2(w, BAR, GAP, maxf(timeline_bottom - BAR, 0.0)))
		_place(copilot, Rect2(w + GAP, BAR, maxf(dock_width - GAP, 0.0), maxf(timeline_bottom - BAR, 0.0)))
	if _empty:
		var roll_area := Rect2(0, slots_y, w, maxf(timeline_bottom - slots_y, 0))
		var card: Control = _empty.get_child(0)
		_place(_empty, roll_area if roll_area.size.y >= card.get_combined_minimum_size().y else right_content)
	host._schedule_layout_refresh()

func _fit_initial_window() -> void:
	var window := host.get_window()
	if window.mode != Window.MODE_WINDOWED or DisplayServer.get_name() == "headless":
		return
	var area := DisplayServer.screen_get_usable_rect(window.current_screen)
	if not area.has_area():
		return
	var frame := window.get_size_with_decorations() - window.size
	var available := (area.size - frame).max(Vector2i.ONE)
	if window.size.x > available.x or window.size.y > available.y:
		window.size = window.size.min(available)
		var inset := window.position - window.get_position_with_decorations()
		window.position = area.position + (available - window.size) / 2 + inset

func _refresh_scale() -> void:
	var window := host.get_window()
	var screen := window.current_screen
	_screen_pixels = DisplayServer.screen_get_usable_rect(screen).size
	_screen_dpi = DisplayServer.screen_get_dpi(screen)
	var scale: float = preferences.window_scale
	if preferences.auto_window_scale:
		scale = _automatic_scale(_screen_pixels, window.size, _screen_dpi)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if window.content_scale_size != window.size:
		window.content_scale_size = window.size
	if not is_equal_approx(window.content_scale_factor, scale):
		window.content_scale_factor = scale

func _process(delta: float) -> void:
	_update_transport_status()
	if not _file_feedback.is_empty() and Time.get_ticks_msec() >= _file_feedback_until:
		_file_feedback = ""
		_refresh_tip()
	_screen_poll += delta
	if _screen_poll < 0.5:
		return
	_screen_poll = 0.0
	if _ui_light != EditorTheme.use_light(preferences.theme_mode):
		_apply_theme()
	if preferences.auto_window_scale:
		var screen := host.get_window().current_screen
		if DisplayServer.screen_get_usable_rect(screen).size != _screen_pixels or DisplayServer.screen_get_dpi(screen) != _screen_dpi:
			_refresh_scale()

func _automatic_scale(screen: Vector2i, viewport: Vector2i, dpi := 96) -> float:
	var width := mini(screen.x, viewport.x) if screen.x > 0 else viewport.x
	var height := mini(screen.y, viewport.y) if screen.y > 0 else viewport.y
	var room_scale := minf(width / 1100.0, height / 680.0)
	var dpi_scale := maxf(1.0, dpi / 96.0)
	return clampf(floorf(minf(dpi_scale, room_scale) * 20.0 + 0.001) / 20.0, 0.75, 2.5)

func _set_scale(value: float) -> void:
	preferences.auto_window_scale = value <= 0.0
	if value > 0.0:
		preferences.window_scale = value
	_refresh_scale()
	apply_layout()

func _activate_preview() -> void:
	_results_tabs.current_tab = 0
	_set_result_tab(0)
	sidebar._on_rt_play_pause_toggle()

func _apply_theme() -> void:
	_ui_light = EditorTheme.use_light(preferences.theme_mode)
	EditorTheme.light = _ui_light
	EditorTheme.gray = preferences.theme_mode == "gray"
	_ui_theme = EditorTheme.make()
	host.theme = _ui_theme
	host.get_window().theme = _ui_theme
	var background := host.get_node_or_null("AppBg") as ColorRect
	if background:
		background.color = EditorTheme.tone("base")
	var inspector_background := sidebar.get_node_or_null("PanelBg") as ColorRect
	if inspector_background:
		inspector_background.color = EditorTheme.tone("panel")
	_retheme_sidebar(sidebar)
	_spectrum_image.material.set_shader_parameter("light_theme", _ui_light)
	_inspector_divider.color = EditorTheme.tone("line")
	_timeline_divider.color = EditorTheme.tone("line")
	_copilot_divider.color = EditorTheme.tone("line")
	_menu.get_theme_stylebox("panel").bg_color = EditorTheme.tone("menu")
	for heading: Control in [_inspector_heading, _result_heading]:
		var header_style := heading.get_theme_stylebox("panel") as StyleBoxFlat
		header_style.bg_color = EditorTheme.tone("heading")
	for panel: Control in [_track_bar, _rail, _result, _frequency, _emotion_panel, _tips_bar,
			_empty.get_child(0)]:
		var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
		style.bg_color = EditorTheme.surface(panel.get_meta("theme_surface"))
	_audio_label.add_theme_color_override("font_color", EditorTheme.tone("muted"))
	_time_display.add_theme_color_override("font_color", EditorTheme.tone("accent"))
	_status.add_theme_color_override("font_color", EditorTheme.tone("muted"))
	_tip_label.add_theme_color_override("font_color", EditorTheme.tone("muted"))
	preferences.apply_theme(_ui_theme)
	automatic.apply_theme(_ui_theme)
	copilot.apply_theme()
	mcp.apply_theme(_ui_theme)
	_onboarding.apply_theme(_ui_theme)
	for dialog: Window in [_about, _file, _lyrics_file, _image_file, _chart_file, _ask, _message, _video_settings, _video_progress, _release_dialog]:
		if dialog:
			dialog.theme = _ui_theme
	if _feature_finder:
		_feature_finder.apply_theme(_ui_theme)
	_style_scrollbar()
	for control: Control in [grid, _plot, _melody_plot, _palette]:
		control.queue_redraw()

func _retheme_sidebar(node: Node) -> void:
	if node is Control and node.has_theme_color_override("font_color"):
		if not node.has_meta("desktop_dark_ink"):
			node.set_meta("desktop_dark_ink", node.get_theme_color("font_color"))
		var original: Color = node.get_meta("desktop_dark_ink")
		node.add_theme_color_override("font_color", EditorTheme.tone("ink") if _ui_light or EditorTheme.gray else original)
	for child: Node in node.get_children():
		_retheme_sidebar(child)

func _play_state_changed(action: String) -> void:
	if action in ["stop", "reset", "pause"] and not _loop_seek:
		_audition = false
		chart.audition_markers = false
	_play_button.text = "暂停" if chart.rt_playing else "播放"
	_refresh_preview_buttons()
	_update_transport_status()
	_refresh_tip()

func _update_transport_status() -> void:
	var tenths := floori(chart.get_rt_render_time() / 100.0)
	_time_display.text = "%02d:%02d.%d" % [floori(tenths / 600.0), floori(tenths / 10.0) % 60, tenths % 10]
	var state := "播放中" if chart.rt_playing else ("已暂停" if chart.rt_play_active else "已停止")
	var target: String = grid.snap_target_label(grid._snap_target) if grid._snap_target >= 0 and grid.is_dragging_note() else ""
	_transport_status.text = "%s%s" % [state, " / " + target if not target.is_empty() else ""]

func _set_game_mode(enabled: bool) -> void:
	if not enabled and chart.desktop_game_mode and chart.rt_playing:
		chart.pause_rt_playback()
	chart.desktop_game_mode = enabled
	chart.final_preview_mode = enabled
	_position_snap.disabled = enabled
	preview.refresh_from_tab()
	_results_tabs.current_tab = 0
	_set_result_tab(0)

func _play_from_current() -> void:
	_audition = false
	chart.audition_markers = false
	_set_game_mode(true)
	var time: float = chart.get_rt_render_time()
	_play_at(time)

func _play_at(time: float) -> void:
	_loop_seek = true
	chart.set_rt_pointer_time(time)
	chart.start_rt_playback()
	_loop_seek = false

func _set_loop_range(value: Vector2) -> void:
	_loop_range = value
	if _phrase_action: _phrase_action.visible = value.y > value.x
	grid.loop_range_ms = value
	grid.queue_redraw()

func _toggle_loop(enabled: bool) -> void:
	if enabled and _loop_range.y <= _loop_range.x:
		var first := INF
		var last := 0.0
		for id: int in chart.selected_note_ids:
			var note = chart.get_note_data(id)
			if note:
				first = minf(first, note.start_time)
				last = maxf(last, note.end_time)
		if last > first:
			_set_loop_range(Vector2(first, last))
		else:
			_loop_switch.set_pressed_no_signal(false)
			_notify("先在钢琴卷帘中框选要循环的时间范围。")
			return
	grid.loop_enabled = enabled
	grid.queue_redraw()
	if enabled and chart.rt_playing and (chart.rt_play_time < _loop_range.x or chart.rt_play_time >= _loop_range.y):
		_play_at(_loop_range.x)

func _audition_analysis() -> void:
	if _audition:
		chart.pause_rt_playback()
		return
	if chart.applied_capture_markers().is_empty():
		_notify("当前标记没有分析结果。请先完成推理。")
		return
	if _metronome.is_empty():
		for hz in [620.0, 1180.0]:
			var voice := AudioStreamPlayer.new()
			var sound := AudioStreamWAV.new()
			sound.format = AudioStreamWAV.FORMAT_16_BITS
			sound.mix_rate = 22050
			var samples := PackedByteArray()
			samples.resize(1320 * 2)
			for i in range(1320):
				samples.encode_s16(i * 2, roundi(sin(TAU * hz * i / 22050.0) * exp(-i / 200.0) * 12500))
			sound.data = samples
			voice.stream = sound
			voice.max_polyphony = 4
			add_child(voice)
			_metronome.append(voice)
	_audition = true
	chart.audition_markers = true
	var start: float = _loop_range.x if _loop_switch.button_pressed else chart.get_rt_render_time()
	_audition_last_ms = start - chart.audio_delay_ms - 0.01
	_play_at(start)

func _fit_timeline() -> void:
	var beats: float = chart.ms_to_beat_position(float(chart.audio_duration_ms) + float(chart.audio_delay_ms))
	if beats > 0:
		grid.set_desktop_zoom((rollout.size.x - 30) / (beats * grid.base_column_width), true)

func _refresh_tool() -> void:
	var tool: int = chart.current_tool_type
	if tool == 3:
		tool = 300 + int(chart.current_event_subtype)
	for identifier: int in _tools:
		_tools[identifier].set_pressed_no_signal(identifier == tool)
	if _event_tools:
		var popup := _event_tools.get_popup()
		for index in range(popup.item_count):
			popup.set_item_checked(index, popup.get_item_id(index) == tool)
		_event_tools.text = "事件 · " + popup.get_item_text(popup.get_item_index(tool)) if tool >= 300 else "事件"
	if tool != 2:
		preview.cancel_canvas_placement()
	_refresh_tip()

func _refresh_audio() -> void:
	var name: String = chart.audio_path.get_file()
	if _audio_label:
		_audio_label.text = "未导入音频" if name.is_empty() else name
		_audio_label.tooltip_text = chart.audio_path
	if _analyze:
		_analyze.disabled = name.is_empty() or _analyzing
	if _spectrum_button:
		_spectrum_button.disabled = name.is_empty() or _analyzing
		var resolved: String = chart.resolve_audio_path(chart.audio_path) if not name.is_empty() else ""
		if _spectrum_audio != resolved:
			_spectrum_image.texture = null
			_spectrum_audio = ""
	if _analysis_panel:
		if _stem_monitor.sync_audio():
			_analysis_panel.reset_source()
			_analysis_panel.last_capture_source = ""
		_update_capture_panel()
	_refresh_empty()

func _refresh_analysis() -> void:
	if not _plot:
		return
	var data: Dictionary = chart.rhythm_analysis
	var points: Array = data.get("tempo_curve", [])
	_plot.set_data(points, float(data.get("duration_ms", chart.audio_duration_ms)))
	_melody_plot.set_data(data.get("melody", []), float(data.get("duration_ms", chart.audio_duration_ms)))
	var emotion_ready := _has_emotion_models()
	_emotion.refresh(chart, emotion_ready, _analyzing, _emotion_feedback)
	_update_capture_panel()
	_apply_bpm.disabled = points.is_empty()
	var feedback := _analysis_title
	if not _analysis_details.is_empty():
		feedback += "\n" + _analysis_details
	_frequency_feedback.text = feedback
	_frequency_feedback.visible = not feedback.is_empty()
	_plot.visible = _analysis_title.is_empty() or not points.is_empty()
	_plot_title.visible = _plot.visible
	_plot_title.text = "此前的速度曲线" if not _analysis_title.is_empty() and not _latest_tempo else "速度曲线"
	if _analyzing:
		_status.text = "正在分析音频…"
	elif not feedback.is_empty():
		_status.text = feedback
	elif data.is_empty():
		_status.text = "导入音频后可识别节拍。"
	else:
		_status.text = "%d 拍 · %d 个小节重拍 · %d 次起音 · %d 个力度重音 · %d 个速度采样点" % [
			data.get("beats", []).size(), data.get("downbeats", []).size(), data.get("onsets", []).size(),
			data.get("accents", []).size(), points.size()]
	grid.queue_redraw()
	_refresh_tip()

func _refresh_plot_pointer() -> void:
	_plot.pointer_ms = float(chart.rt_play_time) - float(chart.audio_delay_ms)
	_plot.queue_redraw()
	_melody_plot.pointer_ms = _plot.pointer_ms
	_melody_plot.queue_redraw()
	if not chart.rt_playing and _tabs.get_current_tab_control() == _background_page:
		_refresh_background_selection()
	if _loop_seek or not chart.rt_playing:
		return
	if _loop_switch.button_pressed and chart.rt_play_time >= _loop_range.y:
		_audition_last_ms = _loop_range.x - chart.audio_delay_ms - 0.01
		_play_at(_loop_range.x)
		return
	if _audition:
		var current: float = _plot.pointer_ms
		var hits: Array = chart.applied_capture_markers()
		var downbeats: Array = chart.rhythm_analysis.get("downbeats", [])
		var first := hits.bsearch(_audition_last_ms, false)
		var last := hits.bsearch(current, false)
		for index in range(first, last):
			var is_downbeat: bool = chart.analysis_mapping == "downbeats" or downbeats.has(hits[index])
			_metronome[int(is_downbeat)].play()
		_audition_last_ms = current

func _on_guide_mode_changed(mode: int) -> void:
	grid.set_reference_mode(mode)
	_mode_choice.select(_mode_choice.get_item_index(mode))
	_update_capture_panel()
	_refresh_tip()

func _style_scrollbar() -> void:
	var scroll := rollout.get_h_scroll_bar()
	scroll.custom_minimum_size.y = 20
	for name in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = EditorTheme.tone("panel") if name == "scroll" else EditorTheme.tone("line")
		if name == "grabber_highlight" or name == "grabber_pressed":
			style.bg_color = EditorTheme.tone("accent")
		style.set_corner_radius_all(4)
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		if name != "scroll":
			style.content_margin_left = 14
			style.content_margin_right = 14
		scroll.add_theme_stylebox_override(name, style)

func _setup_input() -> void:
	_palette = ToolPalette.new()
	_palette.z_index = 50
	_palette.hide()
	host.add_child(_palette)
	grid.tool_palette_requested.connect(func(point: Vector2): _palette.show_at(point, _tool_entries))
	grid.tool_palette_moved.connect(_palette.point_to)
	grid.tool_palette_released.connect(_palette_release)
	sidebar.guide_mode_changed.connect(_on_guide_mode_changed)
	sidebar.set_guide_mode(sidebar.guide_mode)
	grid.timeline_extent_changed.connect(sidebar.update_timeline_extent)
	sidebar.update_timeline_extent(grid.column_count)
	chart.rhythm_analysis_changed.connect(sidebar._update_snap_info_label)
	host.get_window().focus_exited.connect(grid.cancel_tool_palette)
	host.get_window().focus_exited.connect(grid.cancel_left_box)
	host.get_window().focus_exited.connect(grid.cancel_right_box)
	host.add_child(NumberDrag.new())
	host.get_window().files_dropped.connect(import_dropped_files)

	_video = VideoExport.new()
	add_child(_video)
	_video.stage_changed.connect(func(message: String):
		if is_instance_valid(_video_progress):
			_video_progress.dialog_text = message)
	_video.progress.connect(func(done: int, total: int):
		if is_instance_valid(_video_meter):
			_video_meter.max_value = total
			_video_meter.value = done)
	_video.finished.connect(func(error: String):
		diagnostics.record("video.result", {"error": error}, "info" if error.is_empty() else "error")
		if is_instance_valid(_video_progress):
			_video_progress.hide()
		_notify("视频已导出。" if error.is_empty() else error))

func _palette_release(point: Vector2) -> void:
	_palette.point_to(point)
	var index: int = _palette.selected
	_palette.hide()
	if index >= 0:
		var action: Callable = _tool_entries[index][3]
		action.call()
		_refresh_tool()

func _choose_video_path() -> void:
	if _video.busy:
		return
	if chart.audio_duration_ms <= 0:
		_notify("请先导入音频。")
		return
	if not is_instance_valid(_video_settings):
		_video_settings = VideoExportDialog.new()
		_video_settings.theme = _ui_theme
		host.add_child(_video_settings)
		_video_settings.requested.connect(_start_video_export)
	_video_settings.open_for(chart)

func _start_video_export(path: String, from_ms := 0, to_ms := -1, options := {}) -> void:
	if _video.busy:
		return
	diagnostics.record("video.render")
	if not is_instance_valid(_video_progress):
		_video_progress = AcceptDialog.new()
		_video_progress.title = "正在渲染视频"
		_video_progress.theme = _ui_theme
		_video_progress.ok_button_text = "取消渲染"
		_video_progress.exclusive = true
		_video_progress.confirmed.connect(_video.cancel)
		_video_progress.canceled.connect(_video.cancel)
		_video_meter = ProgressBar.new()
		_video_meter.custom_minimum_size.x = 300
		_video_progress.add_child(_video_meter)
		host.add_child(_video_progress)
	_video_meter.value = 0
	_video_progress.dialog_text = "正在准备渲染…"
	DialogLayout.present(_video_progress, Vector2i(420, 115))
	_video.finished.connect(func(error: String):
		if error.is_empty():
			DesktopFileDialog.reveal_export(path), CONNECT_ONE_SHOT)
	_video.render(chart, analysis._ffmpeg(preferences.ffmpeg_path), path, from_ms, to_ms, options)

func import_dropped_files(paths: PackedStringArray) -> void:
	var zip_path := ""
	var json_path := ""
	var audio_path := ""
	var images := PackedStringArray()
	var lyrics := PackedStringArray()
	for path in paths:
		match path.get_extension().to_lower():
			"zip":
				if zip_path.is_empty():
					zip_path = path
			"json":
				if json_path.is_empty():
					json_path = path
			"wav", "mp3", "ogg":
				if audio_path.is_empty():
					audio_path = path
			"png", "jpg", "jpeg":
				images.append(path)
			"lrc":
				lyrics.append(path)
	if not zip_path.is_empty():
		_document_generation += 1
		if not sidebar._on_zip_selected(zip_path):
			_notify("无法导入该谱面压缩包。")
			return
	elif not json_path.is_empty() and not _open_chart_file(json_path):
		return
	var loaded_audio := false
	if not audio_path.is_empty():
		loaded_audio = import_audio(audio_path, false, lyrics.is_empty())
		if not loaded_audio:
			return
	var background_set := false
	for path in images:
		if _import_image(path, not background_set):
			background_set = true
	for path in lyrics:
		import_lyrics(path, not loaded_audio)
	if loaded_audio:
		DialogLayout.present(_ask, Vector2i(490, 160))
	elif zip_path.is_empty() and json_path.is_empty() and images.is_empty() and lyrics.is_empty():
		_notify("请拖入谱面、音频、LRC 歌词或图片。")

func _get_or_create_root() -> String:
	if not chart.has_root_dir:
		var workspace := "user://charts/%s-%d" % [Time.get_datetime_string_from_system().replace(":", "-"), Time.get_ticks_usec()]
		var absolute := ProjectSettings.globalize_path(workspace)
		if DirAccess.make_dir_recursive_absolute(absolute) != OK:
			_notify("无法创建谱面目录。")
			return ""
		chart.set_root_dir_quiet(workspace)
		chart._root_json_name = "chart.json"
	return ProjectSettings.globalize_path(chart._root_dir)

func _save_chart() -> void:
	if not chart.has_root_dir:
		_choose_chart_save_folder()
	else:
		sidebar._save_to_current_file()

func _choose_chart_save_folder() -> void:
	if chart.has_root_dir and not ChartStorage.is_working_folder(chart.get_root_dir()):
		_save_folder.current_dir = ProjectSettings.globalize_path(chart.get_root_dir()).get_base_dir()
	_save_folder_generation = _document_generation
	_save_folder.open_picker()

func _on_chart_save_folder_selected(folder: String) -> void:
	var current := _save_folder_generation == _document_generation
	_save_folder_generation = -1
	if current:
		_save_chart_in_folder(folder)

func _save_chart_in_folder(folder: String) -> bool:
	var result := ChartStorage.save_copy(chart, folder)
	if result.has("error"):
		sidebar._show_ie_status(str(result.error), Color.RED)
		return false
	var file: String = result.path
	ChartStorage.move_live_references(chart, result.replacements)
	chart.set_root_dir_quiet(file.get_base_dir())
	chart._root_json_name = file.get_file()
	sidebar.imported_file_path = file
	chart.project_cache.remember(file, chart.to_export_dict(), chart.bpm_segments)
	sidebar._save_session_state("import")
	chart.settings_changed.emit()
	chart.force_refresh()
	sidebar._show_ie_status("谱面已保存到 %s" % file, Color.GREEN)
	return true

func _import_image(path: String, use_as_background: bool) -> bool:
	var image: Image = chart.read_image_file(path)
	if image == null or image.is_empty():
		_notify("无法读取图片「%s」。" % path.get_file())
		return false
	var name := _copy_chart_image(path)
	if name.is_empty():
		_notify("无法将图片复制到谱面目录。")
		return false
	if use_as_background:
		chart.preview_bg_image_path = name
	chart.force_refresh()
	return true

func _copy_chart_image(path: String) -> String:
	var root := _get_or_create_root()
	if root.is_empty():
		return ""
	var source := ProjectSettings.globalize_path(path).simplify_path()
	var name := source.get_file()
	var destination := root.path_join(name)
	if source != destination.simplify_path():
		if FileAccess.file_exists(destination):
			name = "%s-%d.%s" % [name.get_basename(), Time.get_ticks_usec(), name.get_extension()]
			destination = root.path_join(name)
		if DirAccess.copy_absolute(source, destination) != OK:
			return ""
	return name

func _open_audio_dialog() -> void:
	if not chart.audio_path.is_empty():
		var absolute: String = chart.resolve_audio_path(chart.audio_path)
		_file.current_dir = ProjectSettings.globalize_path(absolute).get_base_dir()
	_file.open_picker()

func _open_lyrics_dialog() -> void:
	_lyrics_file.open_picker()

func _open_background_dialog() -> void:
	_background_image_request.clear()
	_image_event_target = -1
	_image_file.title = "导入背景图片"
	_image_file.open_picker()

func _open_event_image_dialog(event_id: int) -> void:
	_background_image_request.clear()
	_image_event_target = event_id
	_image_event_generation = _document_generation
	_image_file.title = "导入事件图片"
	if chart.has_root_dir:
		_image_file.current_dir = ProjectSettings.globalize_path(chart.get_root_dir())
	_image_file.open_picker()

func _on_image_file_selected(path: String) -> void:
	if not _background_image_request.is_empty():
		var request := _background_image_request
		_background_image_request = {}
		if request.generation == _document_generation:
			_apply_background_image(path, request.kind, request.time)
		return
	var event_id := _image_event_target
	_image_event_target = -1
	if event_id < 0:
		_import_image(path, true)
		return
	if _image_event_generation != _document_generation or not chart.get_event_data(event_id):
		return
	var image := Image.load_from_file(path)
	var asset := _copy_chart_image(path) if image and not image.is_empty() else ""
	if asset.is_empty():
		_notify("无法读取或导入事件图片。")
		return
	sidebar.set_event_picture(event_id, asset)

func _apply_background_image(path: String, kind: int, time_ms: int) -> void:
	var image: Image = chart.read_image_file(path)
	var asset := _copy_chart_image(path) if image and not image.is_empty() else ""
	if asset.is_empty():
		_notify("无法读取或导入背景图片。")
		return
	var event_id := -1
	for id: int in chart.events:
		var event = chart.get_event_data(id)
		if event.type == kind and event.start_time == time_ms:
			event_id = id
	if event_id >= 0:
		chart.update_event_image_path(event_id, asset)
	else:
		event_id = chart.add_event(kind, time_ms, 0, 0, asset)
	grid.background_clip_key = [1 - kind, event_id]
	_refresh_background_selection()
	_select_background_clip(_background_selection, time_ms)

func import_lyrics(path: String, announce := true) -> int:
	var cues := LrcLyrics.load_cues(path, roundi(chart.audio_duration_ms))
	if cues.is_empty():
		diagnostics.record("lyrics.import", {"reason": "没有有效的 LRC 时间标签或编码不受支持"}, "error")
		if announce:
			_notify("未找到可导入的歌词。请检查 LRC 时间标签，并使用 UTF-8 或 UTF-16 编码。")
		return 0
	if _get_or_create_root().is_empty():
		return 0
	var added: int = chart.add_lyrics(cues)
	diagnostics.record("lyrics.import", {"added": added, "cues": cues.size()})
	if announce:
		_notify("已导入 %d 条底部歌词。" % added if added > 0 else "这些歌词已经在谱面里了。")
	return added

func import_audio(path: String, ask: bool = true, find_lyrics := true) -> bool:
	diagnostics.record("audio.import", {"format": path.get_extension().to_lower()})
	if not FileAccess.file_exists(path):
		diagnostics.record("audio.import", {"reason": "文件不存在"}, "error")
		_notify("音频文件不存在。")
		return false
	var root := _get_or_create_root()
	if root.is_empty():
		return false
	var source := ProjectSettings.globalize_path(path).simplify_path()
	var name := source.get_file()
	var destination := root.path_join(name)
	if source != destination:
		if FileAccess.file_exists(destination):
			name = "%s-%d.%s" % [name.get_basename(), Time.get_ticks_usec(), name.get_extension()]
			destination = root.path_join(name)
		if DirAccess.copy_absolute(source, destination) != OK:
			diagnostics.record("audio.import", {"reason": "复制到谱面目录失败"}, "error")
			_notify("无法将音频复制到谱面目录。")
			return false
	if not sidebar._load_audio_file(name):
		if source != destination:
			DirAccess.remove_absolute(destination)
		diagnostics.record("audio.import", {"reason": "音频解码失败"}, "error")
		_notify("无法读取所选音频。请检查文件格式和内容。")
		return false
	_document_generation += 1
	chart.set_rhythm_analysis({})
	_set_loop_range(Vector2(-1, -1))
	chart.set_audio_path(name)
	diagnostics.record("audio.imported", {"duration_ms": roundi(chart.audio_duration_ms)})
	if chart.chart_info.get("chartName", "").is_empty():
		chart.set_chart_info_field("chartName", path.get_file().get_basename())
	_ensure_default_images()
	var sidecar := source.get_basename() + ".lrc"
	if find_lyrics and preferences.import_matching_lyrics and FileAccess.file_exists(sidecar):
		import_lyrics(sidecar, false)
	chart.force_refresh()
	if ask:
		DialogLayout.present(_ask, Vector2i(490, 160))
	return true

func _ensure_default_images() -> void:
	if chart.preview_bg_image_path.is_empty():
		var image := Image.create_empty(256, 144, false, Image.FORMAT_RGB8)
		image.fill(Color("#192433"))
		if image.save_png(chart._root_dir.path_join("background.png")) == OK:
			chart.preview_bg_image_path = "background.png"
	if chart.preview_mask_image_path.is_empty():
		var mask := Image.create_empty(64, 36, false, Image.FORMAT_RGBA8)
		mask.fill(Color(0, 0, 0, 0))
		if mask.save_png(chart._root_dir.path_join("black_cover.png")) == OK:
			chart.preview_mask_image_path = "black_cover.png"

func _describe_import_analysis() -> void:
	var item := _requested_audio_analysis()
	var input := _capture_input(item.capture_stem)
	var cached := _audio_cache.has_task(input.get("id", ""), item.tasks[0], item)
	_ask.ok_button_text = "应用" if cached else "采音"
	_ask.dialog_text = "%s「%s」？" % [_ask.ok_button_text, CaptureCatalog.ENTRIES[item.capture_id].label]

func _requested_audio_analysis() -> Dictionary:
	return _analysis_panel.options()

func _capture_input(stem: String, refresh := false) -> Dictionary:
	var path: String = chart.resolve_audio_path(chart.audio_path) if not chart.audio_path.is_empty() else ""
	var original_id := _audio_cache.fingerprint(path, refresh)
	if original_id.is_empty():
		return {}
	if stem.is_empty():
		return {"path": path, "id": original_id, "original_id": original_id}
	var stem_path := _stem_separation.stem_path(stem, original_id)
	if stem_path.is_empty():
		return {}
	var stem_hash := _stem_fingerprint.read(stem_path, refresh)
	if stem_hash.is_empty():
		return {}
	# Include the separation model, original recording and track identity even when PCM bytes match.
	var cache_key := stem_path.get_base_dir().get_file()
	var id := ("%s:%s:%s" % [cache_key, stem, stem_hash]).sha256_text()
	return {"path": stem_path, "id": id, "original_id": original_id}

func _capture_cache_status(fingerprint: String) -> Dictionary:
	var hits := {}
	if fingerprint.is_empty():
		return hits
	for id: String in CaptureCatalog.ENTRIES:
		var item := CaptureCatalog.options(id)
		hits[id] = _audio_cache.has_task(fingerprint, item.tasks[0], item)
	return hits

func _refresh_capture_sources() -> void:
	var ready := _stem_separation.state == "ready"
	if ready == _capture_stems_ready:
		return
	_capture_stems_ready = ready
	_analysis_panel.set_stems_ready(ready)
	_update_capture_panel()

func _refresh_capture_source_menu() -> void:
	var path: String = chart.resolve_audio_path(chart.audio_path) if not chart.audio_path.is_empty() else ""
	_stem_separation.set_audio(path)
	_stem_separation.refresh()
	_update_capture_panel()

func _update_capture_panel() -> void:
	var stem: String = _analysis_panel.selected_stem
	var input := _capture_input(stem)
	var applied_id := ""
	if str(chart.rhythm_analysis.get("capture_stem", "")) == stem:
		applied_id = str(chart.rhythm_analysis.get("capture_id", ""))
	_analysis_panel.showing_capture_lines = sidebar.guide_mode == ReferenceMode.BEATS
	_analysis_panel.update_status(not chart.audio_path.is_empty(), _analyzing, _capture_cache_status(input.get("id", "")),
		applied_id, str(_analysis_request.get("capture_id", "")) if _analyzing else "")

func _request_analysis() -> void:
	if _analyzing or chart.audio_path.is_empty():
		return
	var options := _requested_audio_analysis()
	var input := _capture_input(options.capture_stem, true)
	if input.is_empty():
		if not options.capture_stem.is_empty():
			_stem_separation.set_audio(chart.resolve_audio_path(chart.audio_path), true)
			_stem_separation.refresh()
			_update_capture_panel()
			_notify("无法读取所选分轨，请重新分轨或切换采音音源。")
		else:
			_notify("无法读取当前工程的音频。")
		return
	var cached := _audio_cache.lookup(input.id, options)
	if cached.missing.is_empty():
		_apply_capture(options, cached, input.original_id, true)
		return
	if options.engine == "madmom" and not ManagedModels.madmom_ready(
			ManagedModels.directory("madmom", options.get("madmom_model_cache", "")), options.tasks, options.model):
		_show_model_help("madmom")
		return
	_start_analysis(options, input)

func _apply_capture(options: Dictionary, result: Dictionary, original_id: String, from_cache := false) -> void:
	var task: String = options.tasks[0]
	var series: String = Analysis.RESULT_KEYS[task]
	var failure: String = result.get("task_errors", {}).get(task, result.get("error", ""))
	if not failure.is_empty() or not result.has(series):
		_show_analysis_feedback("采音失败", failure if not failure.is_empty() else "引擎未返回所选项目。")
		return
	var merged := CaptureCatalog.applied_result(options, result, _chart_music_at(original_id),
		chart.audio_rms_waveform, chart.audio_waveform_bucket_ms)
	_chart_analysis_id = original_id
	var bpm := CaptureCatalog.detected_bpm(task, result)
	if bpm > 0 and (not chart.has_project_bpm or (task == "tempo" and not is_equal_approx(chart.bpm, bpm))):
		chart.set_bpm(bpm)
	_clear_analysis_feedback()
	_latest_tempo = task == "tempo" and bpm > 0
	var label: String = CaptureCatalog.ENTRIES[options.capture_id].label
	_analysis_title = "%s · %.1f BPM" % [label, bpm] if _latest_tempo else "%s · %d 个标记" % [label, merged.capture_markers.size()]
	if not chart.has_project_bpm:
		_analysis_details = "工程缺少 BPM，请在「自动采音」选择 BPM 并采音。"
	_analysis_panel.last_capture_source = "cache" if from_cache else "inference"
	diagnostics.record("analysis.apply", {"capture_id": options.capture_id, "source": _analysis_panel.last_capture_source,
		"stem": options.get("capture_stem", ""), "raw": result[series].size(),
		"markers": merged.capture_markers.size(), "sensitivity": options.sensitivity})
	chart.set_rhythm_analysis(merged)
	_refresh_analysis()

func _emotion_model_path() -> String:
	return ManagedModels.directory("music2emo", preferences.emotion_models)

func _has_emotion_models() -> bool:
	return Analysis.emotion_models_ready(_emotion_model_path())

func _emotion_options(options: Dictionary) -> void:
	if "emotions" not in options.get("tasks", []):
		return
	var path := _emotion_model_path()
	options["emotion_models"] = path
	var metadata := PackedStringArray([path])
	if preferences.limit_emotion_memory:
		options["emotion_low_memory"] = true
		metadata.append("low-memory")
	for file: String in ["mert.onnx", "btc.onnx", "emotion.onnx", "metadata.txt"]:
		metadata.append(str(FileAccess.get_modified_time(path.path_join(file))))
	options["emotion_model_id"] = "|".join(metadata).sha256_text()

func _show_model_help(model: String) -> void:
	_help_model = model
	if not is_instance_valid(_model_help):
		_model_help = ConfirmationDialog.new()
		_model_help.ok_button_text = "刷新"
		_model_help.cancel_button_text = "关闭"
		_model_help.add_button("打开 Hub", true, "hub")
		_model_help.custom_action.connect(func(action: StringName):
			if action == &"hub" and not ManagedModels.open_hub():
				_model_help.dialog_text = "未找到更好的制谱器 Hub。安装或从开始菜单打开 Hub，进入「下载 → 模型管理」补齐 %s，再点击刷新。" % ManagedModels.NAMES[_help_model])
		_model_help.confirmed.connect(_refresh_managed_models)
		host.add_child(_model_help)
	_model_help.title = "%s 模型" % ManagedModels.NAMES[model]
	_model_help.dialog_text = "请在 Hub 的「下载 → 模型管理」下载或补齐 %s，完成后返回此处刷新。" % ManagedModels.NAMES[model]
	_model_help.theme = _ui_theme
	DialogLayout.present(_model_help, Vector2i(480, 190))

func _refresh_managed_models() -> void:
	ManagedModels.refresh()
	_emotion_feedback = ""
	_refresh_analysis()
	models_refreshed.emit()
	var ready := false
	match _help_model:
		"madmom":
			var options := _requested_audio_analysis()
			var path := ManagedModels.directory("madmom", options.get("madmom_model_cache", ""))
			ready = ManagedModels.madmom_ready(path, options.tasks, options.model)
		"music2emo":
			ready = _has_emotion_models()
		"htdemucs":
			ready = not ManagedModels.htdemucs_path().is_empty()
	if not ready:
		_show_model_help.call_deferred(_help_model)
		_model_help.set_deferred("dialog_text", "尚未检测到完整的 %s 模型。请在 Hub 中校验模型文件再刷新。" % ManagedModels.NAMES[_help_model])

func _open_emotion_models() -> void:
	var dialog := _create_path_dialog("选择 Music2Emo ONNX 模型目录", FileDialog.FILE_MODE_OPEN_DIR)
	dialog.theme = _ui_theme
	dialog.dir_selected.connect(func(path: String):
		if Analysis.emotion_models_ready(path):
			preferences.emotion_models = path
			preferences.save()
			_emotion_feedback = ""
			_refresh_analysis()
		else:
			_emotion_feedback = "未找到完整的 Music2Emo 文件。请在 Hub 中校验，或选择包含完整模型的目录。"
			_refresh_analysis()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	host.add_child(dialog)
	dialog.open_picker()

func _request_emotion() -> void:
	_results_tabs.current_tab = 3
	if not _has_emotion_models():
		_show_model_help("music2emo")
		return
	var options := {"engine": "music2emo", "tasks": ["emotions"]}
	_emotion_options(options)
	var id := _audio_cache.fingerprint(chart.resolve_audio_path(chart.audio_path))
	var cached := _audio_cache.lookup(id, options)
	if cached.has("emotions"):
		_analysis_audio_id = id
		_apply_emotion_result(cached)
	else:
		_start_analysis(options)

func _open_analysis_settings() -> void:
	_open_inspector_page("自动采音")

func _request_spectrum() -> void:
	_results_tabs.current_tab = 2
	_frequency_tabs.current_tab = 0
	_start_analysis({"spectrum_only": true})

func _analyze_for_agent(options: Dictionary) -> Dictionary:
	options = options.duplicate()
	_emotion_options(options)
	var generation := _document_generation
	var path: String = chart.resolve_audio_path(chart.audio_path)
	var id := _audio_cache.fingerprint(path)
	if id.is_empty():
		return {"error": "当前没有可分析的音频。"}
	var progress: Callable = options.get("progress", Callable())
	var result := _audio_cache.lookup(id, options)
	var missing: Array = result.missing
	result.erase("missing")
	var service := _analysis_service(str(options.get("engine", "native")))
	if not result.cache_hits.is_empty() and progress.is_valid():
		progress.call("本地分析缓存", _analysis_targets(result.cache_hits))
	if missing.is_empty():
		return result
	if options.get("cache_only", false):
		result.error = "本轮分析次数已达上限，未找到剩余项目的缓存。"
		return result
	if progress.is_valid():
		progress.call(service, _analysis_targets(missing))
	var request := options.duplicate()
	request.erase("progress")
	request["agent_cross_analysis"] = true
	request["tasks"] = missing
	request.erase("cache_only")
	if not _start_analysis(request):
		return {"error": "未能启动本地分析。"}
	var finished: Array = await analysis.completed
	if generation != _document_generation or id != _audio_cache.fingerprint(path):
		return {"error": "分析期间音频或工程已切换。"}
	result.merge(finished[1], true)
	result["inferred_tasks"] = missing
	return result

func _analyze_vocal_pitch() -> void:
	var result := await _analyze_for_agent({"engine": "rmvpe", "tasks": ["vocal_pitch"], "visible_progress": true})
	_notify(str(result.error) if result.has("error") else "RMVPE 完成，检测到 %d 个有声音高帧。" % result.get("vocal_pitch", []).size())

func agent_editor_view() -> Dictionary:
	var rect: Rect2 = grid._grid_viewport_rect()
	var left: int = chart.time_unit_to_ms(roundi(rect.position.x * 64.0 / grid.column_width))
	var right: int = chart.time_unit_to_ms(roundi(rect.end.x * 64.0 / grid.column_width))
	return {"visible_ruler": [chart.ruler_position(left), chart.ruler_position(right)],
		"reference_mode": _mode_choice.get_item_text(_mode_choice.selected),
		"time_snap": chart.timeline_snap_enabled, "inspector": str(_tabs.get_current_tab_control().name)}

func _agent_audio_selection() -> Vector2:
	if _loop_range.y > _loop_range.x:
		return _loop_range
	var first := INF
	var last := 0.0
	for id: int in chart.selected_note_ids:
		var note = chart.get_note_data(id)
		if note:
			first = minf(first, note.start_time)
			last = maxf(last, note.end_time)
	return Vector2(first, last) if last > first else Vector2(-1, -1)

func _capture_agent_spectrum(span: Vector2i) -> Dictionary:
	var generation := _document_generation
	var delay: int = roundi(chart.audio_delay_ms)
	var audio_span := Vector2i(maxi(0, span.x - delay), maxi(0, span.y - delay))
	if not _start_analysis({"spectrum_only": true, "figure_span": audio_span, "agent_cross_analysis": true}):
		return {"error": "当前无法启动频谱分析。"}
	var finished: Array = await analysis.completed
	if generation != _document_generation:
		return {"error": "分析期间音频或工程已切换。"}
	var result: Dictionary = finished[1]
	if result.has("error"):
		return {"error": result.error}
	var plot := Image.new()
	if plot.load_png_from_buffer(result.get("spectrum", PackedByteArray())) != OK:
		return {"error": "无法读取生成的频谱图。"}
	return AgentAudio.image_result(plot, "spectrum", span)

func _cached_chart_music() -> Dictionary:
	if chart.audio_path.is_empty():
		return {}
	var id := _audio_cache.fingerprint(chart.resolve_audio_path(chart.audio_path))
	var music := _chart_music_at(id)
	for options: Dictionary in [{"engine": "native", "tasks": ["beats", "downbeats", "tempo"]},
			{"engine": "essentia", "tasks": ["onsets", "accents", "melody"]}, {"engine": "music2emo", "tasks": ["emotions"]},
			{"engine": "rmvpe", "tasks": ["vocal_pitch"]}]:
		_emotion_options(options)
		var cached := _audio_cache.lookup(id, options)
		for key: String in Analysis.RESULT_KEYS.values():
			if music.get(key, []).is_empty() and cached.has(key):
				music[key] = cached[key]
	return music

func _chart_music_at(id: String) -> Dictionary:
	if _chart_analysis_generation != _document_generation or _chart_analysis_id.is_empty():
		_chart_analysis_generation = _document_generation
		_chart_analysis_id = id
	return chart.rhythm_analysis.duplicate(true) if id == _chart_analysis_id else {}

static func _analysis_service(engine: String) -> String:
	return {"native": "Beat This! / 内置速度算法", "essentia": "Essentia", "madmom": "madmom",
		"music2emo": "Music2Emo（ONNX Runtime）", "rmvpe": "RMVPE（ONNX Runtime）"}.get(engine, "本地音频分析")

static func _analysis_targets(tasks: Array) -> String:
	var captions := {"beats": "拍点", "downbeats": "小节重拍", "tempo": "速度曲线", "onsets": "起音", "accents": "力度重音", "melody": "主旋律", "emotions": "分段情绪"}
	return "、".join(tasks.map(func(task: String): return captions.get(task, task)))

func _start_analysis(options: Dictionary, capture_input := {}) -> bool:
	_emotion_options(options)
	var details := {"engine": options.get("engine", "native"), "tempo_engine": options.get("tempo_engine", "native"),
		"tasks": options.get("tasks", []), "spectrum": options.get("spectrum_only", false),
		"capture_id": options.get("capture_id", "")}
	if _analyzing:
		diagnostics.record("analysis.start", {"reason": "已有分析任务运行"}, "warning")
		_notify("正在分析音频，请等待当前任务完成后重试。")
		return false
	if chart.audio_path.is_empty():
		_open_audio_dialog()
		return false
	var path: String = capture_input.path if not capture_input.is_empty() else chart.resolve_audio_path(chart.audio_path)
	_analysis_audio_id = capture_input.id if not capture_input.is_empty() else (
		_audio_cache.fingerprint(path) if options.has("tasks") else "")
	if not analysis.start(path, preferences.ffmpeg_path, options):
		diagnostics.record("analysis.start", {"reason": "无法启动分析线程"}, "error")
		_notify("无法启动音频分析。请重试，或关闭制谱器后重新打开。")
		return false
	_analyzing = true
	if "emotions" in options.get("tasks", []):
		_emotion_feedback = "正在使用 Music2Emo 分析分段情绪…"
	diagnostics.record("analysis.start", details)
	_analysis_request = options.duplicate(true)
	_analysis_capture_input = capture_input
	_clear_analysis_feedback()
	_analysis_generation = _document_generation
	if not options.get("agent_cross_analysis", false) or options.get("visible_progress", false):
		_open_analysis_progress(options)
	_refresh_audio()
	_refresh_analysis()
	return true

func _on_analysis_complete(path: String, result: Dictionary) -> void:
	var request := _analysis_request
	var capture_input := _analysis_capture_input
	_analysis_request = {}
	_analysis_capture_input = {}
	_analyzing = false
	if is_instance_valid(_analysis_dialog):
		_analysis_dialog.hide()
	_refresh_audio()
	_refresh_analysis()
	if _analysis_generation != _document_generation or chart.audio_path.is_empty():
		diagnostics.record("analysis.discard", {"reason": "音频或工程已切换"}, "warning")
		return
	if request.has("capture_id"):
		if capture_input != _capture_input(request.get("capture_stem", ""), true):
			_notify("采音期间所选音源已更换，请重新采音。")
			return
		_audio_cache.store(capture_input.id, request, result)
	elif path != chart.resolve_audio_path(chart.audio_path):
		diagnostics.record("analysis.discard", {"reason": "音频或工程已切换"}, "warning")
		return
	elif not _analysis_audio_id.is_empty() and _analysis_audio_id == _audio_cache.fingerprint(path):
		_audio_cache.store(_analysis_audio_id, request, result)
	var counts := {}
	for key: String in Analysis.RESULT_KEYS.values():
		if result.get(key) is Array or result.get(key) is PackedFloat32Array:
			counts[key] = result[key].size()
	var task_errors: Dictionary = result.get("task_errors", {})
	diagnostics.record("analysis.result", {"engine": result.get("engine", request.get("engine", "native")),
		"counts": counts, "error": result.get("error", ""), "task_errors": task_errors},
		"error" if result.has("error") else ("warning" if not task_errors.is_empty() else "info"))
	if request.get("agent_cross_analysis", false):
		_emotion_feedback = ""
		_refresh_analysis()
		return
	if request.has("capture_id"):
		_apply_capture(request, result, capture_input.original_id)
		return
	if result.get("spectrum_request", false):
		_apply_spectrum_result(path, result)
		return
	if "emotions" in request.get("tasks", []):
		_apply_emotion_result(result)

func _open_analysis_progress(options: Dictionary) -> void:
	if not is_instance_valid(_analysis_dialog):
		var controls := _create_progress_window("正在分析音频")
		_analysis_dialog = controls[0]
		_analysis_progress_stage = controls[2]
		_analysis_progress_meter = controls[3]
	_analysis_dialog.theme = _ui_theme
	var targets := _analysis_targets(options.get("tasks", []))
	_show_analysis_stage("准备分析 " + targets if not targets.is_empty() else "准备分析音频", 0, 0)
	DialogLayout.present(_analysis_dialog, Vector2i(450, 110))

func _create_progress_window(title: String) -> Array:
	var window := Window.new()
	window.title = title
	window.visible = false
	window.transient = true
	window.exclusive = true
	window.min_size = Vector2i(260, 100)
	host.add_child(window)
	var scroll := ScrollContainer.new()
	window.add_child(scroll)
	scroll.follow_focus = true
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	scroll.add_child(margin)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["top", "bottom", "left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	margin.add_child(body)
	var stage := _label("", 14)
	stage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(stage)
	var meter := ProgressBar.new()
	meter.custom_minimum_size.y = 18
	body.add_child(meter)
	return [window, body, stage, meter]

func _show_analysis_stage(stage: String, completed: int, total: int) -> void:
	if not is_instance_valid(_analysis_dialog):
		return
	_analysis_progress_stage.text = ("%s（%d / %d 段）" % [stage, completed, total]) if total > 0 else stage
	_set_progress_meter(_analysis_progress_meter, completed, total)

static func _set_progress_meter(meter: ProgressBar, completed: int, total: int) -> void:
	meter.indeterminate = total <= 0
	meter.show_percentage = total > 0
	meter.max_value = maxi(total, 1)
	meter.value = completed

func _clear_analysis_feedback() -> void:
	_analysis_title = ""
	_analysis_details = ""
	_analysis_tip_context = ""
	_latest_tempo = false

func _show_analysis_feedback(title: String, details: String) -> void:
	_analysis_title = title
	_analysis_details = details
	_analysis_tip_context = _context_tip()
	_refresh_analysis()
	_message.title = "分析结果"
	_message.dialog_text = title if details.is_empty() else title + "\n\n" + details
	_message.dialog_autowrap = true
	_message.get_ok_button().text = "确定"
	DialogLayout.present(_message, Vector2i(560, 160))

func _apply_spectrum_result(path: String, result: Dictionary) -> void:
	_results_tabs.current_tab = 2
	_frequency_tabs.current_tab = 0
	var reason: String = result.get("error", "")
	if reason.is_empty():
		var image := Image.new()
		if image.load_png_from_buffer(result.spectrum) == OK:
			_spectrum_image.texture = ImageTexture.create_from_image(image)
			_spectrum_audio = path
			_show_analysis_feedback("使用 FFmpeg 分析频谱成功！", "")
			return
		reason = "无法读取生成的频谱图像。"
	if _spectrum_audio == path and _spectrum_image.texture:
		reason += " 现有图像来自上次分析。"
	_show_analysis_feedback("频谱生成失败", reason)

func _apply_emotion_result(result: Dictionary) -> void:
	var segments: Array = result.get("emotions", [])
	_results_tabs.current_tab = 3
	_emotion_feedback = str(result.get("task_errors", {}).get("emotions", result.get("error", "")))
	if not segments.is_empty():
		var merged := _chart_music_at(_analysis_audio_id)
		_chart_analysis_id = _analysis_audio_id
		merged["emotions"] = segments
		merged["duration_ms"] = maxf(merged.get("duration_ms", 0), result.get("duration_ms", 0))
		chart.set_rhythm_analysis(merged)
		_show_analysis_feedback("分段情绪分析完成", "%d 个情绪片段" % segments.size())
	else:
		_show_analysis_feedback("分段情绪分析失败", _emotion_feedback if not _emotion_feedback.is_empty() else "没有检测到有效片段。")

func _apply_curve() -> void:
	if not chart.apply_rhythm_curve():
		_notify("请先分析音频，获得速度曲线。")

func _new_chart() -> void:
	if not chart.notes.is_empty() or not chart.events.is_empty():
		var dialog := ConfirmationDialog.new()
		dialog.title = "新建谱面"
		dialog.dialog_text = "新建谱面会关闭当前编辑。请先保存需要保留的改动。"
		dialog.confirmed.connect(_clear_chart)
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		host.add_child(dialog)
		DialogLayout.present(dialog, Vector2i(440, 145))
	else:
		_clear_chart()

func _clear_chart() -> void:
	_document_generation += 1
	_file_feedback = ""
	_clear_analysis_feedback()
	_loop_switch.set_pressed_no_signal(false)
	grid.loop_enabled = false
	_set_loop_range(Vector2(-1, -1))
	grid.background_clip_key = []
	chart.reset_loaded_chart()
	sidebar.set_guide_mode(ReferenceMode.BEATS)
	chart.close_root_dir()
	sidebar.imported_file_path = ""
	if sidebar._audio_player:
		sidebar._audio_player.stop()
		sidebar._audio_player.stream = null
	_refresh_audio()
	_refresh_analysis()
	chart.force_refresh()

func _notify(text: String) -> void:
	if background_mode:
		printerr(text)
		return
	_message.title = "更好的制谱器"
	_message.dialog_text = text
	DialogLayout.present(_message, Vector2i(480, 150))
