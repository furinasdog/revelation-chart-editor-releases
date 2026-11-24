extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desktop: Node = current_scene.desktop
	var display := Vector2i(1366, 728)
	var scale: float = desktop._automatic_scale(display, display)
	var font_size: int = desktop._ui_theme.default_font_size
	var actual_pixels := roundi(font_size * scale)
	print("DISPLAY_1366 ", scale, " scale, ", actual_pixels, " physical px")
	var passed := scale == 1.0 and actual_pixels >= 14
	var large := Vector2i(3840, 2160)
	var hi_dpi: float = desktop._automatic_scale(large, large, 192)
	var same_size_standard: float = desktop._automatic_scale(large, large, 96)
	var hdpi: float = desktop._automatic_scale(Vector2i(1920, 1050), Vector2i(1920, 1020), 144)
	passed = passed and hi_dpi == 2.0 and same_size_standard == 1.0 and hdpi == 1.5
	root.size = Vector2i(1600, 900)
	desktop._set_scale(1.25)
	await process_frame
	var logical: Vector2 = current_scene.size
	passed = passed and is_equal_approx(root.content_scale_factor, 1.25) and absf(logical.x - 1280.0) < 2
	var grid: Control = desktop.grid
	var stride: int = grid._reference_beat_stride(2.5)
	passed = passed and stride == 4 and grid._reference_beat_stride(40.0) == 1
	print("DISPLAY_4K ", hi_dpi, " high DPI, ", same_size_standard, " standard DPI; ",
		"MANUAL_LOGICAL ", logical, "; DENSE_GRID_STRIDE ", stride, "; passed=", passed)
	for window_size in [Vector2i(1440, 900), Vector2i(1024, 650)]:
		root.size = window_size
		desktop._set_scale(1.0 if window_size.x == 1440 else 1.25)
		desktop.preferences.inspector_split = 0.27
		desktop.preferences.upper_split = 0.62 if window_size.x == 1440 else 0.36
		desktop.apply_layout()
		var forms_ok := await _check_inspector_forms(desktop)
		passed = forms_ok and passed
		var layout_ok := await _check_inspector_and_guide(desktop)
		passed = layout_ok and passed
	if not passed:
		push_error("Display scaling, inspector layout or tutorial interaction failed.")
	quit(0 if passed else 1)

func _check_inspector_forms(desktop: Node) -> bool:
	var sidebar: Control = desktop.sidebar
	desktop._open_inspector_page("事件")
	if sidebar.ev_image_row.visible or sidebar.ev_text_fields.visible:
		push_error("An empty event inspector exposes conflicting editors")
		return false
	desktop._open_inspector_page("谱面信息")
	desktop.chart.set_chart_info_field("tips/other", "谱面导入提示")
	await process_frame
	if sidebar._chart_info_fields["tips/other"].text != "谱面导入提示":
		push_error("Chart metadata changed without updating its form")
		return false
	desktop._open_inspector_page("动画键")
	var list: Control = sidebar._anim_rect_step_list
	desktop._open_inspector_page("预览工具")
	await process_frame
	desktop._open_inspector_page("动画键")
	return is_instance_valid(list) and list == sidebar._anim_rect_step_list

func _check_inspector_and_guide(desktop: Node) -> bool:
	desktop._open_inspector_page("音频")
	desktop.chart.set_audio_duration(240000)
	desktop.chart.audio_path = "Beyond - 海阔天空（现场录音及长文件名测试）.mp3"
	desktop.sidebar._refresh_audio_path_options()
	await process_frame
	await process_frame
	var sidebar: Control = desktop.sidebar
	var audio: Control = desktop._tabs.get_current_tab_control()
	var play: Button = audio.find_child("BtnPlayPause", true, false)
	var seek: HSlider = sidebar._audio_time_slider
	if audio is ScrollContainer:
		audio.ensure_control_visible(seek)
		await process_frame
	var area := seek.get_global_rect()
	var gap := area.position.y - play.get_global_rect().end.y
	var passed := gap >= 0 and gap < 65
	if not passed:
		push_error("Seek control separated from transport by %.1f px" % gap)
	if sidebar._audio_path_option.get_global_rect().end.x > audio.get_global_rect().end.x:
		push_error("Long audio filename overflows its inspector")
		passed = false
	var thumb_width := seek.get_theme_icon("grabber").get_width()
	for fraction in [0.25, 0.75]:
		var point := Vector2(area.position.x + thumb_width * 0.5 + fraction * (area.size.x - thumb_width), area.get_center().y)
		_click(point)
		var ratio: float = desktop.chart.audio_playback_position / desktop.chart.audio_duration_ms
		if absf(ratio - fraction) > 0.02:
			push_error("Seek at %.2f reached %.2f" % [fraction, ratio])
			passed = false
	var tutorial: Control = desktop._onboarding
	tutorial.open_beginner()
	for pair in [[5, 0], [6, -1], [8, 1]]:
		tutorial._show_step(pair[0])
		await process_frame
		await process_frame
		var card: Rect2 = tutorial._panel.get_global_rect()
		var button: Rect2 = desktop._tools[pair[1]].get_global_rect()
		if card.intersects(button) or card.intersects(desktop.rollout.get_global_rect()) or not tutorial.get_global_rect().encloses(card):
			push_error("Tutorial step %d covers its tool or practice grid, or exceeds the viewport" % (pair[0] + 1))
			passed = false
		desktop._choose_tool(2)
		_click(button.get_center())
		if desktop.chart.current_tool_type != pair[1]:
			push_error("Tutorial step %d intercepted the brush click" % (pair[0] + 1))
			passed = false
	tutorial.close_guide()
	return passed

func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = point
		root.push_input(click, true)
