extends SceneTree

const ThemePalette := preload("res://desktop/editor_theme.gd")
const Notes := preload("res://desktop/release_notes.gd")
const Archive := preload("res://main/chart_archive.gd")

func _initialize() -> void:
	_run.call_deferred()

func _require(condition: bool, explanation: String) -> bool:
	if not condition:
		push_error(explanation)
		quit(1)
	return condition

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desktop: Node = current_scene.desktop
	var chart: Node = desktop.chart
	var wizard: Control = desktop._onboarding
	wizard.open()
	var theme_index: int = desktop.preferences.THEME_NAMES.keys().find("gray")
	wizard._theme.select(theme_index)
	wizard._theme.item_selected.emit(theme_index)
	if not _require(ThemePalette.gray and not ThemePalette.light and ThemePalette.tone("panel") == Color("#2d2d2d"),
			"Studio gray should apply from first-run settings"):
		return
	wizard._experience = "branch"
	wizard._complete_setup(false)
	desktop.preferences.load_settings()
	if not _require(desktop.preferences.theme_mode == "gray", "The theme selected at first launch must persist"):
		return
	desktop.preferences.set_theme_mode("light")
	desktop.preferences.open("界面")
	var tabs: TabBar = desktop.preferences._pages.get_tab_bar()
	var hover_text := tabs.get_theme_color("font_hovered_color")
	var hover_style := tabs.get_theme_stylebox("tab_hovered") as StyleBoxFlat
	var contrast := _contrast(hover_text, hover_style.bg_color)
	if not _require(contrast >= 4.5, "Light preferences tab hover text contrast: %.2f:1" % contrast):
		return
	print("LIGHT_TAB_HOVER_CONTRAST %.2f:1" % contrast)
	desktop.preferences._dialog.hide()
	desktop.preferences.set_theme_mode("gray")
	desktop._set_copilot_visible(true)
	var divider: Control = desktop._copilot_divider
	var prior_width: float = desktop.preferences.copilot_width
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(-48, 0)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	divider.gui_input.emit(drag)
	if not _require(desktop.preferences.copilot_width == prior_width,
			"A left-button drag crossing into the divider must keep the original width"):
		return
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	divider.gui_input.emit(press)
	divider.gui_input.emit(drag)
	var resized: float = desktop.preferences.copilot_width
	press.pressed = false
	divider.gui_input.emit(press)
	divider.gui_input.emit(drag)
	if not _require(resized > prior_width and desktop.preferences.copilot_width == resized,
			"Only a left drag started on the divider may resize the Co-pilot"):
		return
	desktop._set_copilot_visible(false)
	var current: String = desktop._current_release_tag()
	desktop.preferences.last_run_tag = "v0.3"
	await desktop._check_release_notice()
	if not _require(desktop._release_dialog.visible and desktop._release_dialog.dialog_text.contains(current)
			and desktop.preferences.last_run_tag == current and not Notes.should_show(current, current, true)
			and not Notes.should_show("v0.4.0", "v0.4.1", true), "An upgrade shows the current notes exactly once"):
		return
	desktop._release_dialog.hide()
	await desktop._check_release_notice()
	if not _require(not desktop._release_dialog.visible, "An unchanged tag must not show again"):
		return
	var entries := Archive.inspect(args[1])
	if not _require(not entries.is_empty() and not Archive.relative_name("CON.png") and not Archive.relative_name("E:/audio.wav"),
			"Archive preflight accepts the package and rejects invalid entry names"):
		return
	var previous_audio: AudioStream
	var used: Array[int] = []
	for index in range(4):
		if not _require(desktop.import_audio(args[0], false, false), "Import long synthetic WAV"):
			return
		var preview: Control = desktop.preview
		if not _require(preview._ensure_rt_audio_stream() and preview._rt_audio_stream == chart.loaded_audio_stream,
				"Preview should reuse the same decoded audio stream"):
			return
		if previous_audio and not _require(previous_audio != chart.loaded_audio_stream, "Reimport refreshes the audio stream"):
			return
		previous_audio = chart.loaded_audio_stream
		await process_frame
		used.append(int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	previous_audio = null
	var unpacked: String = chart.extract_zip_import(args[1])
	if not _require(not unpacked.is_empty(), "Normal chart ZIP extracts after preflight"):
		return
	if not _require(used[-1] <= used[1] + 48 * 1024 * 1024, "Memory should settle after repeated imports"):
		return
	print("RELEASE_READINESS_SMOKE imports=", used.size(), " allocator_bytes=", used)
	quit()

func _contrast(foreground: Color, background: Color) -> float:
	var foreground_luminance := foreground.srgb_to_linear().get_luminance()
	var background_luminance := background.srgb_to_linear().get_luminance()
	return (maxf(foreground_luminance, background_luminance) + 0.05) / (minf(foreground_luminance, background_luminance) + 0.05)
