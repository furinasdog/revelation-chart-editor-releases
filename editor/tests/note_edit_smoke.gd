extends SceneTree

const POS := Vector2(405, 277)
const TARGET := Vector2(853, 437)
const FINISH := Vector2(1480, 630)
const CURVE_POINT := Vector2(1180, 290)
const TYPES: Array[String] = ["普通键", "滑键", "长按键"]

var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if not condition:
		push_error(label)
		_failures += 1

func _run() -> void:
	if change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desktop: Node = current_scene.desktop
	root.size = Vector2i(1920, 1080)
	desktop._set_scale(1.0)
	desktop._clear_chart()
	await process_frame

	for type in range(TYPES.size()):
		_exercise_note(desktop, type)
	_exercise_batch_drag(desktop)

	var chart: Node = desktop.chart
	var exported: Dictionary = JSON.parse_string(JSON.stringify(chart.to_export_dict()))
	var copy: Node = load("res://main/chart_data.gd").new()
	root.add_child(copy)
	copy.set_export_metadata(exported.basic, exported.defaultBackgroundSetting, {}, [])
	copy.import_from_json_array(exported.data)
	_check(copy.notes.size() == 3, "All three note types survive export and re-import")
	for original in chart.notes.values():
		var matching = copy.notes.values().filter(func(note): return note.type == original.type)
		if matching.size() != 1:
			_check(false, "Re-import retains the note type")
			continue
		var restored = matching[0]
		_check(restored.position.is_equal_approx(original.position), "Re-import retains note position")
		_check(restored.end_time == original.end_time and (original.type != 2 or restored.judge_time == original.judge_time), "Re-import retains judgement and end times")
		var original_segments: Array = chart.get_note_move_segments(chart.notes.find_key(original))
		var restored_segments: Array = copy.get_note_move_segments(copy.notes.find_key(restored))
		_check(original_segments.size() == restored_segments.size(), "Re-import retains the number of motion keyframes")
		for ratio in [0.0, 0.25, 0.5, 0.75, 1.0]:
			var time := lerpf(original.start_time, original.end_time, ratio)
			var expected: Vector2 = chart.get_note_move_position(chart.notes.find_key(original), time)
			var actual: Vector2 = copy.get_note_move_position(copy.notes.find_key(restored), time)
			_check(expected.distance_to(actual) < 0.05, "Re-import retains the motion path")
	copy.queue_free()
	_check_quick_edit(desktop)
	await process_frame
	print("NOTE_EDIT_SMOKE failures=", _failures)
	quit(1 if _failures else 0)

func _check_quick_edit(desktop: Node) -> void:
	var chart: Node = desktop.chart
	chart.clear_all_selections()
	_check(desktop.sidebar.desktop_note_empty.visible and not desktop.sidebar.desktop_note_fields.visible,
		"Empty inspector omits editable zeroes")
	desktop._choose_tool(1)
	desktop._canvas_place.button_pressed = true
	desktop._canvas_place.pressed.emit()
	chart.set_rt_pointer_time(12000)
	chart.preview_snap_enabled = false
	chart.timeline_snap_enabled = false
	_check(desktop.preview._place_mode_active(), "Canvas brush uses the normal placement mode")
	var point: Vector2 = desktop.preview._game_to_preview(600, 550)
	desktop.preview._handle_place_mode_click(point)
	var id: int = chart.selected_note_ids[-1]
	_check(chart.notes[id].end_time == 12000 and chart.notes[id].position.distance_to(Vector2(600,550)) < 2,
		"Canvas click sets both playhead judgement and scene coordinates")
	_check(desktop._slide_path.visible, "New yellow key exposes a path action")
	desktop._slide_path.pressed.emit()
	var curve: Dictionary = chart.get_note_move_curve_data(id)
	_check(not curve.is_empty() and curve.start.distance_to(curve.end) > 10, "One click makes distinct, draggable slide endpoints")
	chart.undo()
	_check(not chart._move_active(chart.notes[id]), "Undo removes the entire new path")
	desktop._choose_tool(302)
	_check(chart.current_event_subtype == 2 and "文本事件" in desktop._event_tools.text, "Grouped event tools preserve selection")

func _exercise_note(desktop: Node, type: int) -> void:
	var chart: Node = desktop.chart
	var grid: Control = desktop.grid
	var preview: Control = desktop.preview
	var sidebar: Control = desktop.sidebar
	var kind := TYPES[type]
	var start_ms := 1000 + type * 4000
	var initial_end := start_ms + 1000
	var judge := start_ms + 500 if type == 2 else 0
	var id: int = chart.add_note_at_times(type, start_ms, initial_end, judge, type, POS, FINISH)
	_check(id >= 0, "%s can be placed" % kind)
	if id < 0:
		return
	chart.select_note(id)
	var note = chart.get_note_data(id)
	_check(sidebar.spin_pos_x.editable and sidebar.move_fields_container.visible, "%s position and motion controls are available" % kind)

	chart.preview_grid_enabled = false
	var start: Vector2 = preview._game_to_preview(POS.x, POS.y)
	_check(preview._try_start_drag(start, false), "%s preview drag starts without a modifier" % kind)
	preview._do_drag(preview._game_to_preview(TARGET.x, TARGET.y))
	preview._end_drag()
	_check(note.position.distance_to(TARGET) < 0.05, "%s preview drag updates its position" % kind)
	_check(note.start_time == start_ms and note.end_time == initial_end, "%s preview drag keeps timing" % kind)

	chart.preview_grid_enabled = true
	var snap_target := Vector2(1120, 357)
	var snapped: Vector2 = preview._snap_game_pos_to_grid(snap_target.x, snap_target.y)
	start = preview._game_to_preview(note.position.x, note.position.y)
	_check(preview._try_start_drag(start, false), "%s can be dragged with the preview grid enabled" % kind)
	preview._do_drag(preview._game_to_preview(snap_target.x, snap_target.y))
	preview._end_drag()
	_check(note.position.distance_to(snapped) < 0.05, "%s preview drag respects the grid" % kind)
	chart.preview_grid_enabled = false

	chart.update_note_move(id, "enabled", true)
	chart.update_note_move(id, "type", "linear")
	chart.update_note_move(id, "trans", 0)
	chart.update_note_move(id, "end", FINISH)
	var middle_time := start_ms + (750 if type == 2 else 500)
	var linear_middle: Vector2 = chart.get_note_move_position(id, middle_time)
	_check(linear_middle.distance_to(note.position.lerp(FINISH, 0.5)) < 0.1, "%s linear animation interpolates" % kind)

	chart.update_note_move(id, "type", "arc")
	chart.update_note_move(id, "mid", CURVE_POINT)
	var arc_middle: Vector2 = chart.get_note_move_position(id, middle_time)
	_check(arc_middle.distance_to(linear_middle) > 20.0, "%s arc animation follows a curved path" % kind)
	_check(chart.get_note_move_position(id, initial_end).distance_to(FINISH) < 0.1, "%s animation reaches its endpoint" % kind)
	if type < 2:
		var moved_end := FINISH + Vector2(-103, 52)
		_check(preview._try_start_note_move_drag(preview._game_to_preview(FINISH.x, FINISH.y)), "%s animation handle can be dragged" % kind)
		preview._do_note_move_drag(preview._game_to_preview(moved_end.x, moved_end.y))
		preview._end_note_move_drag()
		_check(chart.get_note_move_position(id, initial_end).distance_to(moved_end) < 0.05, "%s handle drag updates the animation endpoint" % kind)
	var keyframe := middle_time - 125
	var segment_index: int = chart.get_note_move_segments(id).size() - 1
	_check(chart.add_move_keyframe(id, segment_index, keyframe) == segment_index, "%s can add a motion keyframe" % kind)
	var before: Vector2 = chart.get_note_move_position(id, keyframe)

	if type == 2:
		var moved_end := Vector2(1600, 500)
		_check(preview._try_start_drag(preview._game_to_preview(FINISH.x, FINISH.y), false), "Long hold preview endpoint can be dragged")
		_check(preview.dragging_hold_line, "Long hold drag targets the endpoint")
		preview._do_drag(preview._game_to_preview(moved_end.x, moved_end.y))
		preview._end_drag()
		_check(chart.get_hold_move_position(id, initial_end).distance_to(moved_end) < 0.1, "Long hold endpoint drag updates its animation")

	chart.timeline_snap_enabled = false
	var original_tu: int = note.time_unit
	var target_tu := original_tu + 64
	var target_track := type + 1
	var snap_width: float = grid.column_width / 64.0
	grid._start_note_drag(id, original_tu, type)
	grid._move_note_drag(Vector2(target_tu * snap_width, grid._track_y(target_track) + grid.row_height / 2.0))
	grid._commit_note_drag()
	var delta: int = chart.time_unit_to_ms(target_tu) - chart.time_unit_to_ms(original_tu)
	_check(note.track == target_track and chart.get_note_at(target_tu, target_track) == id, "%s timeline drag updates track and hit testing" % kind)
	_check(note.start_time == start_ms + delta and note.end_time == initial_end + delta, "%s timeline drag preserves duration" % kind)
	if type == 2:
		_check(note.judge_time == judge + delta, "Long hold timeline drag moves its judgement point")
	_check(is_equal_approx(float(note.move.segments[segment_index].time), float(keyframe + delta)), "%s timeline drag moves motion keyframe with the note" % kind)
	_check(chart.get_note_move_position(id, keyframe + delta).distance_to(before) < 0.1, "%s timeline drag preserves the motion at the same relative time" % kind)

	chart.final_preview_mode = true
	chart.set_rt_pointer_time(keyframe + delta)
	preview._refresh_runtime_layer()
	var sprites: Array = preview._collect_runtime_notes()
	_check(not sprites.is_empty(), "%s animation appears in the runtime preview" % kind)
	if not sprites.is_empty():
		var expected: Vector2 = chart.get_note_move_position(id, keyframe + delta)
		_check(sprites[0].center.distance_to(preview._game_to_preview(expected.x, expected.y)) < 0.05, "%s rendered animation matches the movement curve" % kind)
	chart.final_preview_mode = false
	print("NOTE_EDIT ", kind, " track=", note.track, " delta=", delta)

func _exercise_batch_drag(desktop: Node) -> void:
	var chart: Node = desktop.chart
	var grid: Control = desktop.grid
	var ids: Array[int] = []
	ids.assign(chart.notes.keys())
	if ids.size() != TYPES.size():
		return
	var original_times := {}
	var original_tracks := {}
	for id in ids:
		var note = chart.get_note_data(id)
		original_times[id] = float(note.move.segments[0].time)
		original_tracks[id] = int(note.track)
	var source = chart.get_note_data(ids[0])
	var origin: int = source.time_unit
	var track: int = source.track
	var width: float = grid.column_width / 64.0
	chart.set_note_selection(ids)
	grid._start_note_drag(ids[0], origin, track)
	grid._move_note_drag(Vector2((origin + 32) * width, grid._track_y(track + 1) + grid.row_height / 2.0))
	grid._move_note_drag(Vector2((origin + 64) * width, grid._track_y(track + 1) + grid.row_height / 2.0))
	grid._commit_note_drag()
	var delta: int = chart.time_unit_to_ms(origin + 64) - chart.time_unit_to_ms(origin)
	for id in ids:
		var note = chart.get_note_data(id)
		_check(note.track == original_tracks[id] + 1, "Batch drag moves each note by one track")
		_check(is_equal_approx(float(note.move.segments[0].time), original_times[id] + delta), "Batch drag moves each note's motion keyframes")
