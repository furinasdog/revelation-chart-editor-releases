extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, description: String) -> void:
	if not ok:
		push_error(description)
		failures += 1

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Expected original audio, variable-tempo WAV and Revelation ZIP")
		quit(2)
		return
	if change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var editor := current_scene
	var desktop: Node = editor.desktop
	var chart: Node = editor.chart_data
	_check(ClassDB.class_exists("RevelationRhythm"), "GDExtension registered its native class")
	_check(desktop._ask != null, "Desktop assembly initialized")
	if failures:
		quit(1)
		return

	root.size = Vector2i(1920, 1080)
	desktop._set_scale(1.0)
	await process_frame
	_check(is_equal_approx(desktop.rollout.size.x, editor.size.x), "Piano roll fills the width at 1080p")
	_check(desktop._tabs.get_tab_control(desktop._tabs.current_tab).name == &"键设置", "Key settings are the initial inspector tab")
	_check(TranslationServer.get_locale() == "zh_CN", "Application uses the Simplified Chinese locale")
	var analysis_menu: MenuButton = desktop._menu.get_child(0).get_child(3)
	_check(analysis_menu.get_popup().get_theme_font_size("font_size") == analysis_menu.get_theme_font_size("font_size"), "Top menu titles and commands use the same size")
	await _check_tutorial(desktop, args[1])
	_check(desktop._empty.visible, "Empty workspace exposes import actions")
	_check(desktop._tip_label.text.contains("拖入音频"), "Empty workspace gives an import tip")
	_check(desktop.rollout.get_rect().end.y <= desktop._tips_bar.position.y, "The tip bar leaves the timeline scrollbar accessible")
	var inspector_page: Control = desktop._tabs.get_current_tab_control()
	_check(inspector_page.position.x >= 10 and inspector_page.get_rect().end.x <= desktop._tabs.size.x - 10,
		"Inspector content has padding on both sides")
	desktop._open_about()
	var about_tabs: TabContainer = desktop._about.get_child(0)
	var version: String = ProjectSettings.get_setting("application/config/version")
	var version_info := about_tabs.get_child(0).get_child(0)
	_check(version_info.get_child(0).text.contains("v" + version), "About shows the project version")
	_check(version_info.get_child(2).text == "分支作者：短夜月", "About credits the branch author")
	for page in [1, 2]:
		var licenses: Control = about_tabs.get_child(page)
		var picker: OptionButton = licenses.get_child(0)
		for index in range(picker.item_count):
			picker.item_selected.emit(index)
			_check(licenses.get_child(1).text.length() > 180, "Bundled license is readable: " + picker.get_item_text(index))
	for about_width: int in [650, 320]:
		desktop._about.size = Vector2i(about_width, 320)
		for page in about_tabs.get_tab_count():
			about_tabs.current_tab = page
			await process_frame
			await process_frame
			var content := about_tabs.get_current_tab_control().get_global_rect()
			var panel := about_tabs.get_global_rect()
			_check(is_equal_approx(content.position.x - panel.position.x, 18.0) and is_equal_approx(panel.end.x - content.end.x, 18.0), "About page %d has equal side padding at width %d" % [page, about_width])
	desktop._about.hide()
	await _check_results_at_high_scale(desktop)

	root.size = Vector2i(3840, 2160)
	desktop._set_scale(1.5)
	await process_frame
	_check(desktop._tabs.tabs_visible and desktop._tabs.get_tab_count() >= 4, "Inspector exposes visible tabs")
	_check(is_equal_approx(desktop.rollout.position.x, 0.0) and is_equal_approx(desktop.rollout.size.x, editor.size.x), "Piano roll spans the full window width")
	_check(desktop.sidebar.position.x < desktop.preview.position.x and desktop.sidebar.get_rect().end.x <= desktop.preview.position.x, "Inspector sits left of preview")
	_check(desktop.sidebar.get_rect().end.y < desktop.rollout.position.y and desktop.preview.get_rect().end.y < desktop.rollout.position.y, "Both upper panes sit above the piano roll")
	_check(desktop._rail.get_global_rect().end.y <= desktop.rollout.get_global_rect().position.y, "Brushes are above the piano roll")
	_check(is_equal_approx(desktop._menu.size.x, editor.size.x), "Menu spans the window")
	var time_label: Label = desktop.sidebar.spin_start_time.get_parent().get_node("StartTimeLabel")
	_check(time_label.text == "开始时间", "Inspector field labels are localized")
	var area_options: OptionButton = desktop.sidebar.opt_judge_area
	_check(area_options.get_item_text(0) == "侧边" and area_options.get_item_text(1) == "中央", "Inspector option labels are localized")
	desktop._results_tabs.current_tab = 1
	_check(desktop._result.visible and not desktop.preview.visible, "Rhythm analysis opens in the upper-right pane")
	desktop._results_tabs.current_tab = 0
	_check(desktop.preview.visible and not desktop._result.visible, "Chart preview opens in the upper-right pane")
	_check(absf(editor.size.x - 2560) < 4, "150% scale gives a 2560px logical width on a 3840px window")
	print("LAYOUT ", root.size, " editor=", editor.size, " panes=", desktop.sidebar.size, " ", desktop.rollout.size, " ", desktop.preview.size)

	_check(desktop.import_audio(args[0]), "Import the source MP3")
	_check(not desktop._empty.visible, "Import leaves the entire piano roll available")
	_check(desktop._ask.visible, "Successful import opens confirmation")
	_check(chart.rhythm_analysis.is_empty() and not desktop._analyzing, "Await confirmation before analyzing")
	desktop._ask.hide()
	desktop._ask.confirmed.emit()
	_check(desktop.grid.reference_mode == 1, "Confirming automatic analysis switches to automatic tempo references")
	_check(not desktop._tip_action.visible, "Import advice waits for a completed analysis")
	var deadline := Time.get_ticks_msec() + 120000
	while desktop._analyzing and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not desktop._analyzing, "Analysis completed")
	_check(desktop._message.visible and desktop._message.dialog_text.contains("成功！"), "Import analysis shows its success dialog")
	desktop._message.hide()
	_check(desktop._tip_action.visible and desktop._tip_label.text.contains("修改抓音方式"), "Completed import analysis shows adjustable capture advice")
	desktop._tip_action.pressed.emit()
	_check(desktop._tabs.get_current_tab_control() == desktop._analysis_panel and desktop._analysis_panel._settings_toggle.button_pressed,
		"Import advice opens and expands capture settings")
	desktop._tabs.current_tab = inspector_page.get_index()
	desktop._results_tabs.current_tab = 0
	desktop._choose_tool(2)
	_check(desktop._tip_label.text.contains("起点和终点"), "The tip follows the selected brush")
	var report: Dictionary = chart.rhythm_analysis
	var beats: Array = report.get("beats", [])
	var points: Array = report.get("tempo_curve", [])
	_check(beats.size() >= 20 and points.size() >= 20, "Rendered beat and tempo data from the original audio")
	if beats.is_empty():
		print("ANALYSIS_FAILURE ", desktop._status.text, " ", desktop._message.dialog_text)
		quit(1)
		return
	var original_x: float = chart.ms_to_beat_position(beats[0]) * desktop.grid.column_width
	desktop.grid.set_desktop_zoom(10)
	var zoomed_x: float = chart.ms_to_beat_position(beats[0]) * desktop.grid.column_width
	_check(zoomed_x > original_x, "Beat position follows horizontal zoom")
	_check(chart.ms_to_beat_position(beats[0] + 350) > chart.ms_to_beat_position(beats[0]), "Timing offset maps to grid position")
	var document: Dictionary = chart.to_export_dict()
	_check(document.has("rhythmAnalysis") and not document.has("tempoGrid"), "Analyzing adds guides without changing the saved chart tempo")
	chart.set_rhythm_analysis({})
	chart.restore_rhythm_fields(JSON.parse_string(JSON.stringify(document)))
	_check(chart.rhythm_analysis.beats == beats, "Beat positions survive JSON round trip")
	print("ORIGINAL beats=", beats.size(), " downbeats=", report.downbeats.size(), " bpm_points=", points.size())

	var synth: Dictionary = desktop.analysis.analyze_file(args[1])
	var slow := false
	var fast := false
	for point: Dictionary in synth.get("tempo_curve", []):
		if point.time_ms >= 2000 and point.time_ms < 6000 and absf(point.bpm - 120) < 6:
			slow = true
		if point.time_ms >= 10000 and point.time_ms < 14000 and absf(point.bpm - 180) < 8:
			fast = true
	_check(slow and fast, "Native BPM curve distinguishes 120 and 180 BPM")
	chart.set_rhythm_analysis(synth)
	_check(chart.apply_rhythm_curve() and chart.bpm_segments.size() > 1 and not chart.to_export_dict().has("tempoGrid"), "Segmented tempo stays local while the original base BPM is exported")
	print("TEMPO_CHANGE slow=", slow, " fast=", fast, " samples=", synth.get("tempo_curve", []).size())

	desktop.sidebar._on_zip_selected(args[2])
	await process_frame
	_check(chart.notes.size() == 129 and chart.audio_duration_ms > 80000, "Existing Revelation ZIP remains editable")
	var note_id: int = chart.notes.keys()[0]
	var judgement: int = chart.notes[note_id].end_time
	chart.select_note(note_id)
	var inspector_tab: int = desktop._tabs.current_tab
	desktop._play_from_current()
	_check(chart.rt_playing and chart.desktop_game_mode and chart.final_preview_mode, "Try play enters the game view")
	chart.pause_rt_playback()
	chart.reset_rt_playback()
	_check(desktop._tabs.current_tab == inspector_tab and chart.is_selected(note_id), "Transport preserves inspector and selection")
	desktop._set_game_mode(false)
	chart.set_rhythm_analysis(report)
	_check(chart.apply_rhythm_curve() and chart.notes[note_id].end_time == judgement, "Applying tempo preserves existing judgement time")
	var default_key: int = desktop.preferences.bindings["play"]
	desktop.preferences.open("音频")
	_check(desktop.preferences._dialog.visible, "Preferences dialog opens")
	var preference_pages: TabContainer = desktop.preferences._pages
	_check(preference_pages.get_current_tab_control().name == &"音频" and preference_pages.get_tab_count() == 5,
		"Preferences groups settings into five tabs")
	_check(not desktop._tabs.has_node("波形") and preference_pages.has_node("波形"), "Waveform controls have moved to preferences")
	var startup_toggle := preference_pages.get_node("音频").find_child("StartupSound", true, false) as CheckButton
	startup_toggle.button_pressed = false
	desktop.preferences.load_settings()
	_check(not desktop.preferences.play_startup_sound and desktop.preferences._audio_devices.get_item_metadata(0) == "Default",
		"Startup audio preference persists and the device picker lists the system default")
	desktop.preferences._dialog.hide()
	desktop.preferences.bindings["play"] = KEY_F9
	_check(desktop.preferences.event_for("play").keycode == KEY_F9, "Updated shortcut is used in the editor")
	var key := InputEventKey.new()
	key.keycode = KEY_F9
	key.pressed = true
	root.push_input(key)
	await process_frame
	await process_frame
	_check(chart.rt_playing, "Remapped shortcut starts real-time playback")
	desktop.preferences.bindings["play"] = default_key
	chart.reset_rt_playback()
	await process_frame
	print("DESKTOP_SMOKE failures=", failures)
	quit(1 if failures else 0)

func _check_results_at_high_scale(desktop: Node) -> void:
	var previous_split: float = desktop.preferences.upper_split
	root.size = Vector2i(1280, 720)
	desktop._set_scale(1.3)
	desktop.preferences.upper_split = 0.36
	desktop.apply_layout()
	for tab in [1, 2]:
		desktop._results_tabs.current_tab = tab
		await process_frame
		await process_frame
		var panel: Control = desktop._result if tab == 1 else desktop._frequency
		_check(panel.get_global_rect().end.y <= desktop._timeline_divider.position.y + 1,
			"Results stay above the piano roll at 130%% scale (tab %d)" % tab)
	desktop.preferences.upper_split = previous_split
	desktop._results_tabs.current_tab = 0
	desktop.apply_layout()

func _check_tutorial(desktop: Node, practice_audio: String) -> void:
	var tutorial: Control = desktop._onboarding
	tutorial.open()
	_check(tutorial._chooser.visible, "Help opens the tutorial experience picker")
	tutorial._choose_experience("beginner")
	tutorial._show_setup(true)
	_check(tutorial._second.visible and tutorial._sample.visible, "Setup shows the real piano roll sample")
	tutorial._theme.item_selected.emit(1)
	_check(desktop.preferences.theme_mode == "light" and desktop._ui_light, "Changing theme immediately updates the editor")
	tutorial._theme.item_selected.emit(2)
	_check(not desktop._ui_light, "Dark theme also applies immediately")
	tutorial._complete_setup(false)
	_check(not tutorial._chooser.visible and tutorial._panel.visible and tutorial._steps.size() == 15, "Beginners see the expanded guide")
	for i in range(3):
		await process_frame
	_check(tutorial._panel.size.y < 300, "The guide fits its contents at desktop resolution")
	_check(tutorial._next.disabled and tutorial._task_status.text.contains("导入歌曲"), "New users see why the next action is disabled")
	tutorial._action.pressed.emit()
	_check(desktop._file.visible, "The first step opens the real audio picker")
	desktop._file.hide()
	desktop._file.file_selected.emit(practice_audio)
	_check(desktop._ask.visible, "An imported practice song offers an analysis choice")
	desktop._ask.custom_action.emit(&"settings")
	_check(not desktop._ask.visible and desktop._tabs.get_current_tab_control() == desktop._analysis_panel,
		"The import prompt opens analysis settings on request")
	tutorial._check_progress()
	_check(not tutorial._next.disabled, "Importing practice audio unlocks the next step")
	for caption in ["传统量化", "自动速度", "抓取拍点"]:
		tutorial._show_step(2 + ["传统量化", "自动速度", "抓取拍点"].find(caption))
		_check(tutorial._title.text.contains(caption), "Guide explains " + caption)
	tutorial._advance()
	tutorial._action.pressed.emit()
	_check(desktop.chart.current_tool_type == 0, "Tutorial action uses the normal brush command")
	_check(tutorial._next.disabled, "Placement requires a newly created note")
	var note: int = desktop.chart.add_note_at_times(0, 500, 1000, 0, 0, Vector2(700, 450))
	tutorial._check_progress()
	_check(not tutorial._next.disabled, "Placing a note unlocks the move step")
	tutorial._next.pressed.emit()
	desktop.chart.update_note_times(note, 1000, 1500)
	tutorial._check_progress()
	_check(not tutorial._next.disabled, "Moving the practice note unlocks the preview step")
	tutorial._next.pressed.emit()
	tutorial._next.pressed.emit()
	tutorial._action.pressed.emit()
	_check(desktop.chart.current_tool_type == 1 and tutorial._next.disabled, "Yellow-key practice selects the slide brush")
	desktop.chart.add_note_at_times(0, 1200, 2200, 0, 2, Vector2(600, 500))
	tutorial._check_progress()
	_check(tutorial._next.disabled, "A tap cannot complete slide practice")
	desktop.chart.add_note_at_times(1, 1400, 2400, 0, 1, Vector2(600, 500))
	tutorial._check_progress()
	_check(not tutorial._next.disabled, "A slide completes yellow-key practice")
	tutorial._next.pressed.emit()
	tutorial._next.pressed.emit()
	tutorial._action.pressed.emit()
	tutorial._check_progress()
	_check(not tutorial._next.disabled and desktop._exit_game_mode.visible, "Playing the chart completes the preview step")
	desktop._exit_game_mode.pressed.emit()
	_check(not desktop.chart.rt_playing and not desktop.chart.desktop_game_mode, "Returning to editing pauses gameplay preview")
	tutorial._next.pressed.emit()
	tutorial._next.pressed.emit()
	tutorial._action.pressed.emit()
	_check(desktop.automatic._settings_dialog.visible, "API key tutorial opens the actual settings dialog")
	desktop.automatic._settings_dialog.hide()
	tutorial._skip_step.pressed.emit()
	tutorial._action.pressed.emit()
	_check(desktop.copilot.visible and desktop.copilot._compose_button.is_visible_in_tree(), "Agent tutorial opens the Co-pilot composer")
	desktop._set_copilot_visible(false)
	tutorial._next.pressed.emit()
	tutorial._action.pressed.emit()
	var exporter := desktop.sidebar.get_node("ImportExportDialog") as FileDialog
	_check(exporter.visible, "The last step opens the ZIP export dialog")
	exporter.hide()
	var zip_path := ProjectSettings.globalize_path("user://tutorial-export.zip")
	exporter.file_selected.emit(zip_path)
	tutorial._check_progress()
	_check(not tutorial._next.disabled and FileAccess.file_exists(zip_path) and desktop._tip_label.text.contains("导出成功"),
		"A real ZIP export completes the beginner route and reports success in the footer")
	tutorial.close_guide()
	desktop._clear_chart()
	tutorial.open()
	tutorial._choose_experience("original")
	tutorial._show_setup(true)
	tutorial._scheme.select(1)
	tutorial._scheme.item_selected.emit(1)
	tutorial._complete_setup(false)
	_check(tutorial._panel.visible and tutorial._steps.size() == 7, "Original users get the migration tour")
	_check(desktop.grid.original_gestures and desktop.preferences.event_for("play_here").shift_pressed, "Original bindings select the original mouse gestures")
	tutorial._show_step(1)
	_check(tutorial._instruction.text.contains("原版方案") and tutorial._instruction.text.contains("保存"), "Migration tour includes current shortcuts")
	tutorial._action.pressed.emit()
	_check(desktop.preferences._pages.get_current_tab_control().name == &"快捷键", "Migration opens the real shortcut settings page")
	desktop.preferences._dialog.hide()
	tutorial.open()
	tutorial._choose_experience("branch")
	tutorial._complete_setup(true)
	_check(not tutorial._panel.visible and not tutorial._chooser.visible, "Branch users go straight to editing")
	_check(desktop.preferences.shortcut_scheme == "original" and desktop.preferences.theme_mode == "dark", "Reopening setup preserves configured preferences")
	desktop._open_inspector_page("动画键")
	desktop._open_feature_finder()
	desktop._feature_finder._filter("力度重音")
	_check(desktop._feature_finder._results.item_count > 0 and desktop._feature_finder._path.text.contains("自动抓音"), "Finder searches everyday terms")
	desktop._feature_finder._go()
	await process_frame
	await process_frame
	_check(desktop._tabs.get_current_tab_control() == desktop._analysis_panel and desktop._analysis_panel._settings_toggle.button_pressed,
		"Finder can leave the animation tab and open actual analysis controls")
	desktop._open_inspector_page("键设置")
