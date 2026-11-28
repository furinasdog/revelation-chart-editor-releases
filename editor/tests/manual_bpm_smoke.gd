extends SceneTree

const ReferenceMode = preload("res://main/chart_data.gd").ReferenceMode

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _type(input: LineEdit, value: String) -> void:
	input.text = value
	input.text_changed.emit(value)

func _run() -> void:
	if change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var editor: Control = current_scene
	var desktop: Node = editor.desktop
	var sidebar: Control = desktop.sidebar
	var chart: Node = desktop.chart
	desktop._onboarding._chooser.hide()
	chart.reset_loaded_chart()
	desktop._open_inspector_page("参考线量化")
	sidebar._guide_mode_buttons[ReferenceMode.BEATS].pressed.emit()
	_check(not sidebar._manual_bpm_controls.is_visible_in_tree() and not desktop._snap_division.is_visible_in_tree(),
		"Automatic capture guides hide traditional BPM and subdivision controls")
	sidebar._guide_mode_buttons[ReferenceMode.TRADITIONAL].pressed.emit()
	var input: LineEdit = sidebar._manual_bpm_input
	var apply: Button = sidebar._manual_bpm_apply
	_check(input.is_visible_in_tree() and apply.is_visible_in_tree() and input.text.is_empty()
		and desktop.grid.reference_mode == ReferenceMode.TRADITIONAL,
		"Selecting traditional guides shows the empty project's manual BPM controls")

	var undo_count: int = chart.undo_stack.size()
	for bad: String in ["", "不是数字", "nan", "inf", "132e", "132e+", "9.99", "3000.01"]:
		_type(input, bad)
		_check(apply.disabled, "Invalid BPM should disable Apply: " + bad)
		input.text_submitted.emit(bad)
	_check(not chart.has_project_bpm and chart.undo_stack.size() == undo_count,
		"Invalid BPM must not change the project or its undo state")

	_type(input, "132.75")
	_check(not apply.disabled and not chart.has_project_bpm,
		"Typing a valid BPM enables Apply without writing yet")
	apply.pressed.emit()
	_check(chart.has_project_bpm and is_equal_approx(chart.bpm, 132.75) and
		is_equal_approx(chart.to_export_dict().basic.bpm, 132.75) and
		chart.undo_stack.size() == undo_count + 1 and apply.disabled,
		"Apply writes the decimal BPM to the project and export exactly once")
	input.text_submitted.emit(input.text)
	_check(chart.undo_stack.size() == undo_count + 1, "Submitting an already applied value does not add undo entries")
	chart.undo()
	_check(not chart.has_project_bpm and input.text.is_empty(), "Undo restores an empty BPM and refreshes the field")
	chart.redo()
	_check(input.text == "132.75" and is_equal_approx(chart.bpm, 132.75), "Redo restores the committed BPM")

	var id: int = chart.add_note_at_times(0, 3100, 4000, 4000, 1, Vector2(400, 300))
	var hit: int = chart.notes[id].end_time
	chart.add_bpm_node(4)
	chart.set_segment_bpm(1, 175.0)
	var second_segment: Dictionary = chart.bpm_segments[1].duplicate()
	var previous_beat: int = chart.time_unit_to_ms(64)
	undo_count = chart.undo_stack.size()
	_type(input, "160.5")
	input.text_submitted.emit(input.text)
	_check(is_equal_approx(chart.bpm, 160.5) and is_equal_approx(chart.bpm_segments[0].bpm, 160.5)
		and chart.bpm_segments[1] == second_segment and chart.notes[id].end_time == hit
		and chart.time_unit_to_ms(64) < previous_beat and chart.undo_stack.size() == undo_count + 1,
		"Enter updates traditional grid spacing while preserving later segments and note timing")

	chart.set_bpm(180.0)
	_check(input.text == "180", "The field refreshes when another editor entry changes project BPM")
	chart.set_bpm(3000.0)
	_type(input, "2999.99")
	_check(not apply.disabled, "A change of one hundredth remains editable at the upper limit")
	apply.pressed.emit()
	_check(absf(chart.bpm - 2999.99) < 0.000001, "Apply commits the exact decimal near the upper limit")
	root.size = Vector2i(1024, 650)
	desktop._set_scale(1.25)
	desktop.preferences.inspector_split = 0.22
	desktop.preferences.upper_split = 0.36
	desktop.apply_layout()
	await process_frame
	await process_frame
	var page: Control = desktop._tabs.get_current_tab_control()
	_check(input.size.x > 0.0 and input.get_global_rect().end.x <= apply.get_global_rect().position.x
		and page.get_global_rect().end.x >= apply.get_global_rect().end.x,
		"Manual BPM input and Apply fit the narrow 125% inspector")
	chart.reset_loaded_chart()
	_check(input.text.is_empty() and apply.disabled, "Resetting to a new empty chart clears the manual BPM field")
	_check_fine_snap(desktop)
	print("MANUAL_BPM_SMOKE failures=", failures)
	quit(0 if failures == 0 else 1)

func _check_fine_snap(desktop: Node) -> void:
	var chart: Node = desktop.chart
	var grid: Control = desktop.grid
	var division: OptionButton = desktop._snap_division
	chart.set_bpm(120.0)
	_check(division.text == "1/8" and grid.time_at_playhead(65) == chart.time_unit_to_ms(8),
		"New charts snap on the eighth-beat grid")
	_check(grid._reference_grid_stride(48.0, 8) == 1 and grid._reference_grid_stride(24.0, 8) == 2
		and grid._reference_grid_stride(3.0, 8) == 32, "Zoomed-out rulers show aligned intermediate divisions")
	var fine_index: int = chart.snap_divisions.find(16)
	division.select(fine_index)
	division.item_selected.emit(fine_index)
	_check(desktop.sidebar.snap_select.selected == fine_index and grid.time_at_playhead(30) == chart.time_unit_to_ms(4),
		"The toolbar changes actual snap timing and updates the inspector")
	chart.set_export_metadata({"snapIndex": 3}, {})
	chart.force_refresh_requested.emit()
	_check(division.text == "1/4", "Opening an older chart retains its saved subdivision")
	chart.set_rhythm_analysis({"beats": [117.0, 619.0]})
	desktop.sidebar.set_guide_mode(ReferenceMode.BEATS)
	_check(grid.time_at_playhead(120) == 117, "Captured markers retain exact timestamps")
	chart.preview_grid_enabled = true
	_check(chart.preview_grid_div_x == 16 and chart.preview_grid_div_y == 12
		and desktop.preview._snap_game_pos_to_grid(125, 91) == Vector2(120, 90),
		"Preview position snapping uses the finer default grid")
