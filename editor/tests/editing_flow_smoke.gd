extends SceneTree

const Exchange := preload("res://desktop/note_exchange.gd")
const Guide := preload("res://desktop/hand_guide.gd")
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1 or change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var d: Node = current_scene.desktop
	var c: Node = d.chart
	d._onboarding.close_guide()
	if d._release_dialog: d._release_dialog.hide()
	check(d.import_audio(args[0], false), "Open audio")
	c.set_chart_info_field("chartName", "")
	c.preview_bg_image_path = ""
	c.preview_mask_image_path = ""
	c.set_segment_bpm(0,120)
	c.add_bpm_node(4)
	c.set_segment_bpm(1,180)
	c.add_note_at_times(0,600,1000,0,0,Vector2(400,500))
	d._save_chart()
	var path: String = c.get_root_dir().path_join(c._root_json_name)
	check(FileAccess.file_exists(path), "Ctrl+S saves incomplete draft")
	c.add_note_at_times(0,1000,1400,0,1,Vector2(800,500))
	c.set_rt_pointer_time(12610)
	d.sidebar._on_autosave()
	check(d.sidebar._check_required_fields().contains("曲目名称"), "Formal export requires metadata")
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(doc.basic.bpm == 120 and not doc.has("tempoGrid"), "Original JSON schema")
	var zip := ProjectSettings.globalize_path("user://roundtrip.zip")
	check(c.export_zip_to(zip), "Build ZIP for round trip")
	d._clear_chart()
	check(d._continue_draft.visible and d.sidebar.restore_last_session(), "Home continuation")
	check(c.notes.size() == 2 and is_equal_approx(c.get_rt_render_time(),12610), "Autosave restores notes and playhead")
	for src: String in [path,zip,path]:
		check(d._open_chart_file(src), "Open "+src.get_extension())
		check(c.bpm_segments.size() == 2 and c.beat_position_to_ms(7) == 3000 and c.ms_to_time_unit(3000) == 7*64, "Restore tempo, ruler and snap")
	c.remove_bpm_node(1)
	check(d._open_chart_file(zip) and c.bpm_segments.size() == 1, "Deleted tempo marker persists across aliases")
	doc.tempoGrid = [{"start_beat":0,"end_beat":8,"bpm":90},{"start_beat":8,"end_beat":32,"bpm":100}]
	c.restore_rhythm_fields(doc,path)
	check(c.bpm_segments.size() == 2 and c.bpm_segments[0].bpm == 90, "Embedded legacy grid wins")
	check_cache_isolation()
	check_clipboard(c)
	check_copilot(d)
	await process_frame
	print("EDITING_FLOW failures=",failures)
	quit(1 if failures else 0)

func check_cache_isolation() -> void:
	var cache := preload("res://desktop/project_cache.gd").new()
	var hard := {"basic":{"chartName":"Cache test","difficulty":"HD"},"data":[]}
	var easy := {"basic":{"chartName":"Cache test","difficulty":"EZ"},"data":[]}
	var grid := [{"start_beat":0.0,"end_beat":16.0,"bpm":180.0}]
	cache.remember("user://test-one/chart.json",hard,grid)
	check(cache.open("user://test-two/chart.json",hard).is_empty(), "Independent JSON projects have separate tempo grids")
	check(cache.open("user://test-one/chart.json",easy).is_empty(), "Same project with a different difficulty has separate cache")
	check(cache.open("user://test-one/chart.json",hard) == grid, "Original difficulty still has its own grid")

func check_clipboard(c: Node) -> void:
	var h: int = c.add_note_at_times(2,2100,3500,2400,1,Vector2(800,600))
	var s: int = c.add_note_at_times(1,2600,3650,0,2,Vector2(360,700))
	c.notes[h].line = [[800,600],[540,270]]
	c.notes[h].bezier_points = [[550,450],[650,540]]
	c.notes[s].move = {"enabled":true, "segments":[{"time":3650,"end":[700,480],"type":"linear"}]}
	var ids: Array[int] = [s,h]
	c.set_note_selection(ids)
	var serialized := Exchange.copy(c)
	var other := preload("res://main/chart_data.gd").new()
	root.add_child(other)
	other.audio_duration_ms = 16000
	var message := Exchange.paste_json(other,8200,3,serialized)
	check(other.notes.size() == 2, message)
	if other.notes.size() == 2:
		var hold = other.notes.values()[0]
		var slide = other.notes.values()[1]
		check(hold.judge_time == 8200 and hold.track == 3 and JSON.stringify(hold.bezier_points) == JSON.stringify(JSON.parse_string(JSON.stringify(c.notes[h].bezier_points))), "Cross-project hold geometry and judgement")
		check(slide.track == 4 and slide.end_time == 9450 and slide.move.segments[0].time == 9450 and slide.position == c.notes[s].position, "Cross-project slide path and relative time")
		check(Exchange.paste_json(other,8200,3,serialized).contains("占位跳过 2"), "Collision count")
		check(Exchange.paste_json(other,10,7,serialized).contains("越界跳过 2"), "Bounds count")
		other.undo()
		check(other.notes.is_empty(), "Undo pasted group")
	other.queue_free()
	var a: int = c.add_note_at_times(0,2440,2500,0,5,Vector2(840,530))
	c.add_note_at_times(0,2450,2660,0,6,Vector2(450,360))
	var n := Guide.neighborhood(c,a)
	check(n.groups.size() == 5 and n.groups[2].held.size() == 1, "Five judgement groups including an occupied hand")

func check_copilot(d: Node) -> void:
	var c: Node = d.chart
	d.grid.time_range_selected.emit(Vector2(12000,16000))
	d._open_phrase_edit()
	var agent: Node = d.copilot
	check(d._phrase_action.visible and agent._selected_span == Vector2(12000,16000) and agent._editor.text.contains("12") and agent._editor.text.contains("16"), "Ruler selection enters assistant prompt")
	agent.busy = true
	agent._start_steps()
	agent._generation = d._document_generation
	agent._prepare_draft()
	var original: Dictionary = c._snapshot_notes().notes
	var row := {"type":"note","time_ms":14000,"lead_ms":800,"x":450,"y":500,"lane":2}
	check(agent._plan.edit("delete_notes",[original.keys()[0]]).has("error"), "Preserve existing notes")
	check(agent._plan.edit("add_notes",[row.merged({"time_ms":16100},true)]).has("error"), "Reject notes outside selection")
	check(not agent._plan.edit("add_notes",[row]).has("error"), "In-range addition")
	agent._finish(true,"区间测试")
	check(is_instance_valid(agent._comparison) and c.notes.size() == original.size(), "Draft awaits acceptance")
	if is_instance_valid(agent._comparison):
		check(agent._comparison.dialog_text.contains("新增 1") and agent._comparison.dialog_text.contains("删除 0"), "Preview edit counts")
		var player = agent._comparison.find_child("Audition", true, false)
		player.select(0,12000,true)
		player.select(1,12000,true)
		check(player.cues[1].size() == player.cues[0].size()+1 and player.position_ms == 12000 and player.playing, "A/B loops reset to same ruler position")
		agent._comparison.confirmed.emit()
		check(c.notes.size() == original.size()+1, "Commit selection")
		c.undo()
		check(c._snapshot_notes().notes == original, "Undo restores every original note")
