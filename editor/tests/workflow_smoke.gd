extends SceneTree

const ReferenceMode = preload("res://main/chart_data.gd").ReferenceMode

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	if not ok:
		push_error(description)
		failures += 1

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4 or change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desktop: Node = current_scene.desktop
	var chart: Node = desktop.chart
	var grid: Control = desktop.grid
	var preview: Control = desktop.preview
	root.size = Vector2i(1920, 1080)
	desktop._set_scale(1.0)
	await process_frame

	desktop._clear_chart()
	desktop.import_dropped_files(PackedStringArray([args[0], args[3]]))
	await process_frame
	check(chart.audio_duration_ms > 23000 and desktop._ask.visible, "Dropping WAV requests beat analysis")
	check(chart.preview_bg_image_path.ends_with(".jpeg"), "Dropping JPEG imports the chart background")
	desktop._ask.hide()
	var short_extent: int = grid.column_count
	var duration: int = roundi(chart.audio_duration_ms)
	var id: int = chart.add_note_at_times(0, duration - 700, duration - 100, 0, 0, Vector2(960, 540))
	await process_frame
	check(id >= 0 and grid.column_count > short_extent + 3, "A note near the track end extends the piano roll")
	check(desktop.sidebar._bpm_seg_add_beat.max_value == grid.column_count - 1, "Inspector bounds follow the timeline")

	var stationary: Dictionary = desktop.analysis.analyze_file(args[0])
	var curve: Array = stationary.get("tempo_curve", [])
	check(curve.size() > 30 and stationary.get("beats", []).size() >= 60, "Constant-tempo track produces enough observations")
	for point: Dictionary in curve:
		check(absf(point.bpm - 172) < 1.0, "172 BPM is stable throughout the song")
	chart.set_rhythm_analysis(stationary)
	check(desktop._mode_choice.item_count == 2, "Timeline offers traditional and applied capture lines")
	desktop.sidebar.set_guide_mode(ReferenceMode.BEATS)
	check(grid.capture_lines.positions.size() == stationary.beats.size(), "Legacy captured beats remain available in the roll")
	var beat_time: int = roundi(stationary.beats[4])
	var beat_x: float = chart.ms_to_beat_position(beat_time) * grid.column_width
	var beat_unit: int = grid._snap_x_to_time_line(beat_x)
	chart.set_tool_type(0)
	grid._handle_left_click(beat_unit, 1)
	var snapped_id: int = chart.get_note_at(beat_unit, 1)
	check(snapped_id >= 0 and chart.get_note_data(snapped_id).end_time == beat_time, "Placed notes use the captured timestamp exactly")
	chart.remove_note(snapped_id)
	desktop.sidebar.set_guide_mode(ReferenceMode.TRADITIONAL)
	check(grid.snap_target_label(64).is_empty(), "A missing project BPM does not create a traditional snap target")
	chart.set_bpm(120)
	check(grid.snap_target_label(64) == "整拍", "Explicit BPM enables traditional quantization")


	var changing: Dictionary = desktop.analysis.analyze_file(args[1])
	var slow := false
	var fast := false
	for point: Dictionary in changing.get("tempo_curve", []):
		slow = slow or (point.time_ms >= 2000 and point.time_ms < 6000 and absf(point.bpm - 120) < 5)
		fast = fast or (point.time_ms >= 10000 and point.time_ms < 14000 and absf(point.bpm - 180) < 5)
	check(slow and fast, "Variable-tempo track retains two tempo ranges")

	chart.select_note(id)
	var note = chart.get_note_data(id)
	var start: Vector2 = preview._game_to_preview(note.position.x, note.position.y)
	var target: Vector2 = preview._game_to_preview(1150, 682)
	chart.preview_grid_enabled = false
	check(preview._try_start_drag(start, false), "Plain preview drag starts without a modifier")
	preview._do_drag(target)
	preview._end_drag()
	check(note.position.distance_to(Vector2(1150, 682)) < 0.1, "Preview drag permits continuous positioning")
	chart.preview_grid_enabled = true
	start = preview._game_to_preview(note.position.x, note.position.y)
	var snapped: Vector2 = preview._snap_game_pos_to_grid(1311, 770)
	check(preview._try_start_drag(start, false), "Selected note is still editable in grid mode")
	preview._do_drag(preview._game_to_preview(1311, 770))
	preview._end_drag()
	check(note.position.is_equal_approx(snapped), "Preview grid snaps with grid mode enabled")

	chart.set_tool_type(-1)
	var box_a: int = chart.add_note_at_times(0, 1000, 1300, 0, 0, Vector2(960, 540))
	var box_b: int = chart.add_note_at_times(2, 1100, 2100, 1600, 1, Vector2(960, 540))
	var box_c: int = chart.add_note_at_times(0, 2500, 2900, 0, 3, Vector2(960, 540))
	var track_top: float = grid._track_y(0)
	var x0: float = chart.ms_to_beat_position(1250) * grid.column_width
	var x1: float = chart.ms_to_beat_position(1600) * grid.column_width
	var begin := Vector2(x1, track_top + grid.row_height * 2 - 1)
	var end := Vector2(x0, track_top + 1)
	var moved := InputEventMouseMotion.new()
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	grid._begin_left_box(begin, false)
	grid._handle_left_box(moved, end)
	check(grid.box_select_active, "Left drag shows the marquee")
	grid._handle_left_box(up, end)
	check(chart.is_selected(box_a) and chart.is_selected(box_b) and chart.selected_note_ids.size() == 2, "The marquee selects regular notes and intersected hold bodies")
	var other_x: float = chart.ms_to_beat_position(2900) * grid.column_width
	var other_y: float = grid._track_y(3)
	grid._begin_left_box(Vector2(other_x - 14.0, other_y), true)
	grid._handle_left_box(up, Vector2(other_x + 14.0, other_y + grid.row_height))
	check(chart.is_selected(box_c) and chart.selected_note_ids.size() == 3, "Shift-drag extends the selection")
	chart.timeline_snap_enabled = false
	var first_unit: int = chart.get_note_data(box_a).time_unit
	var hold_judge: int = chart.get_note_data(box_b).judge_time
	var unit_width: float = grid.column_width / 64.0
	var grip := Vector2(first_unit * unit_width, track_top + grid.row_height / 2)
	var selection: int = grid._pick_note_body(grip)
	check(selection == box_a, "Selection finds the painted note body")
	grid._begin_left_box(grip, false, selection)
	grid._handle_left_box(moved, grip + Vector2(8 * unit_width, 0))
	grid._handle_left_box(moved, grip + Vector2(16 * unit_width, 0))
	grid._handle_left_box(up, grip + Vector2(16 * unit_width, 0))
	check(chart.get_note_data(box_a).time_unit == first_unit + 16 and chart.get_note_data(box_b).judge_time > hold_judge, "Dragging selected notes without a modifier moves the group and hold judgement")
	var hold = chart.get_note_data(box_b)
	chart.select_note(box_b)
	var hold_start: int = hold.start_time
	var hold_duration: int = hold.end_time - hold.start_time
	var hold_anchor: int = hold.time_unit
	var mid := Vector2((hold.time_unit + hold.length * 0.62) * unit_width, grid._track_y(1) + grid.row_height / 2)
	check(grid._pick_note_body(mid) == box_b, "The inside of a hold is draggable")
	grid._begin_left_box(mid, false, grid._pick_note_body(mid))
	grid._handle_left_box(moved, mid + Vector2(unit_width * 16, grid.row_height))
	grid._handle_left_box(up, mid + Vector2(unit_width * 16, grid.row_height))
	check(hold.time_unit == hold_anchor + 16 and hold.track == 2 and hold.start_time > hold_start
		and hold.end_time - hold.start_time == hold_duration, "Dragging a hold from the middle keeps its grab offset and duration")
	chart.undo()
	check(chart.get_note_data(box_b).time_unit == hold_anchor, "Selection drag is undoable in one operation")
	chart.timeline_snap_enabled = true


	var pointer := Vector2(420, 420)
	grid._right_press = InputEventMouseButton.new()
	grid._right_press.position = pointer
	grid._process_palette(0.4)
	check(desktop._palette.visible, "A right-button hold opens the tool palette")
	var drag_tool: Vector2 = desktop._palette.position + Vector2(198, 34)
	desktop._palette_release(drag_tool)
	grid.cancel_tool_palette()
	check(chart.current_tool_type == 1, "Releasing over the slide icon changes the tool")

	chart.auto_scroll_enabled = true
	check(desktop.sidebar._auto_scroll_checkbox.button_pressed, "Playback follow switches stay synchronized")
	check(desktop.rollout.get_h_scroll_bar().custom_minimum_size.y >= 20, "Horizontal scrollbar is wide enough to grab")
	check(is_equal_approx(desktop._automatic_scale(Vector2i(3840, 2120), Vector2i(3840, 2100), 192), 2.0),
		"Maximized 4K at 192 DPI uses the system's 200% scale")
	check(is_equal_approx(desktop._automatic_scale(Vector2i(3840, 2120), Vector2i(1100, 680), 192), 1.0),
		"A smaller window on the same screen preserves usable workspace")
	var key_tab: Control = desktop._tabs.get_node("键设置")
	desktop._tabs.current_tab = key_tab.get_index()
	chart.select_note(box_b)
	var settings_scroll: ScrollContainer = key_tab.get_child(0)
	var columns: BoxContainer = settings_scroll.get_node("KeySettingsRoot/KeySettingsCols")
	var original_split: float = desktop.preferences.inspector_split
	desktop.preferences.inspector_split = 0.15
	desktop.apply_layout()
	await process_frame
	check(columns.vertical, "Narrow inspector stacks the note and movement fields")
	check(settings_scroll.get_h_scroll_bar().custom_minimum_size.y == 14, "Inspector has an accessible horizontal scrollbar")
	desktop.preferences.inspector_split = original_split
	desktop.apply_layout()

	var numeric_drag = load("res://desktop/number_drag.gd").new()
	current_scene.add_child(numeric_drag)
	var field: SpinBox = desktop.sidebar.bpm_input
	var original: float = field.value
	numeric_drag._target = field
	numeric_drag._initial = original
	var motion := InputEventMouseMotion.new()
	motion.position.x = 40
	numeric_drag._input(motion)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	numeric_drag._input(release)
	check(field.value > original and chart.bpm == field.value, "Numeric drag updates the bound chart property")
	numeric_drag.queue_free()

	desktop.import_dropped_files(PackedStringArray([args[2]]))
	await process_frame
	check(chart.notes.size() == 129 and chart.audio_duration_ms > 80000, "Dropped Revelation ZIP remains editable")

	desktop._clear_chart()
	chart.preview_place_mode = true
	chart.preview_place_multi_select = true
	chart.timeline_snap_enabled = false
	chart.set_tool_type(0)
	chart.set_rt_pointer_time(5000)
	var placed_a: Vector2 = preview._game_to_preview(680, 410)
	var placed_b: Vector2 = preview._game_to_preview(1240, 550)
	check(preview._handle_place_mode_click(placed_a) and preview._handle_place_mode_click(placed_b),
		"Preview places two notes at the current pointer")
	check(chart.selected_note_ids.size() == 2 and chart.is_multi_batch_mode() and is_equal_approx(chart.get_rt_render_time(), 5000.0),
		"Preview placement accumulates a batch without moving the pointer")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	preview._input(escape)
	check(chart.selected_note_ids.is_empty(), "Escape clears the placement batch")
	chart.preview_place_multi_select = false
	chart.set_rt_pointer_time(6000)
	preview._handle_place_mode_click(placed_a)
	preview._handle_place_mode_click(placed_b)
	check(chart.selected_note_ids.size() == 1 and not chart.preview_place_multi_active, "Placement respects disabled grouping")
	var initial_height: float = preview.size.y
	var timeline_rect: Rect2 = desktop.rollout.get_rect()
	check(not desktop._tabs.has_node("PreviewTab"), "Retired preview inspector is absent")
	var initial_tab: int = desktop._tabs.current_tab
	desktop._tabs.current_tab = desktop._tabs.get_node("动画设置").get_index()
	check(preview.size.y == initial_height and desktop.rollout.get_rect() == timeline_rect and desktop._timeline_divider.visible,
		"Switching inspector pages preserves the pane and piano roll layout")
	desktop._tabs.current_tab = initial_tab
	desktop._set_game_mode(true)
	check(preview.size.y == initial_height and desktop.rollout.get_rect() == timeline_rect,
		"Game canvas mode preserves the editor layout")
	desktop._set_game_mode(false)
	current_scene.set_preview_focus(true)
	check(preview.size.y > initial_height and not desktop._timeline_divider.visible and desktop.rollout.visible,
		"Preview focus grows the upper pane and keeps the piano roll")
	desktop._tabs.current_tab = desktop._tabs.get_node("动画设置").get_index()
	desktop._tabs.current_tab = initial_tab
	check(not desktop._timeline_divider.visible, "Changing tabs preserves manually chosen preview focus")
	current_scene.set_preview_focus(false)
	check(is_equal_approx(preview.size.y, initial_height) and desktop._timeline_divider.visible,
		"Returning to normal restores the custom pane sizes")
	check_lyrics_import(desktop, args[0])
	print("WORKFLOW_SMOKE failures=", failures)
	quit(1 if failures else 0)

func check_lyrics_import(desktop: Node, audio: String) -> void:
	desktop._clear_chart()
	var wav := "user://workflow-lyrics.wav"
	DirAccess.copy_absolute(audio, ProjectSettings.globalize_path(wav))
	var lrc := "user://workflow-lyrics.lrc"
	var file := FileAccess.open(lrc, FileAccess.WRITE)
	file.store_16(0xFEFF)
	file.store_buffer("[ar:演唱者]\n[offset:+100]\n[00:01.20][00:05.500]副歌\n[00:02.500]第二行\n[00:04.00]\n".to_utf16_buffer())
	file.close()
	check(not desktop.preferences.import_matching_lyrics, "Matching LRC import is off by default")
	check(desktop.import_audio(wav, false), "Audio with a matching LRC can be imported")
	check(desktop.chart.events.is_empty(), "Importing audio alone leaves matching lyrics untouched")
	desktop.import_dropped_files(PackedStringArray([lrc]))
	desktop._message.hide()
	var events: Array = desktop.chart.events.values()
	check(events.size() == 3, "An explicitly dropped UTF-16 LRC yields separate events for multiple timestamps")
	if events.size() != 3:
		return
	check(events[0].type == 2 and events[0].text == "副歌" and events[0].start_time == 1300 and events[0].end_time == 2599
		and events[0].pos.y == 960 and events[1].end_time == 4099 and events[2].start_time == 5600,
		"Lyric timing, offsets, blank clear cues, and bottom position are applied")
	check(desktop.import_lyrics(lrc, false) == 0, "Repeated import does not duplicate lyrics")
	desktop.preview._rt_time_ms = 1400
	check(desktop.preview._collect_runtime_texts().size() == 1, "Lyrics appear as timed text in game preview")
	desktop.chart.undo()
	check(desktop.chart.events.is_empty(), "One undo removes the imported batch")
	desktop.preferences.import_matching_lyrics = true
	check(desktop.import_audio(wav, false) and desktop.chart.events.size() == 3,
		"Users can explicitly enable matching lyrics during audio import")
	desktop.preferences.import_matching_lyrics = false
