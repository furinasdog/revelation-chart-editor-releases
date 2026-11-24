extends SceneTree

const Plan := preload("res://desktop/auto_chart_plan.gd")
const Agent := preload("res://desktop/chart_agent.gd")
const AnimationDraft := preload("res://desktop/agent_animation.gd")
const Context := preload("res://desktop/agent_context.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desktop: Node = current_scene.desktop
	var chart: Node = desktop.chart
	var automatic: Node = desktop.automatic
	desktop._onboarding._chooser.hide()
	var menu: MenuButton = desktop._menu.get_child(0).get_child(4)
	_check(menu.text == "工具" and menu.get_popup().get_item_text(0) == "Revelation Co-pilot"
		and menu.get_popup().get_item_text(1) == "MCP 服务器…", "Tools menu leads with Co-pilot and MCP")
	_check(desktop.import_audio(args[0]), "Load WAV")
	desktop._ask.hide()
	await process_frame
	var initial: int = chart.add_note_at_times(0, 900, 1600, 0, 7, Vector2(900, 475))
	var rhythm: Dictionary = await desktop._analyze_for_agent({"engine": "native", "tasks": ["beats", "tempo"]})
	var plan := Plan.new(chart, "EX")
	var music: Dictionary = automatic.music_for_agent(chart, rhythm, plan.duration_ms)
	_check(not plan.seed_pattern(music, 71).has("error"), "Retained pattern tool drafts an EX section")
	chart.apply_automatic_notes(plan.notes, plan.edited)
	_check(chart.notes.size() >= 25 and chart.notes.has(initial), "Pattern tool preserves existing notes")
	var diagonal := 0
	var horizontal := 0
	var holds := 0
	var longer_lead := false
	var generated: Array = chart.to_json_array()
	_check_ex_chords(generated, [1600])
	for note: Dictionary in generated:
		if note.startTime > 0 and note.endTime - note.startTime >= 1000:
			longer_lead = true
		if note.type == "hold":
			holds += 1
			_check(note.endTime - note.judgeTime >= Plan.DIFFICULTIES.EX.hold_ms, "Holds sustain for the picked difficulty")
		if note.type == "drag" and note.get("move", {}).get("enabled", false):
			if note.move.end[0] != note.position[0]:
				if note.move.end[1] == note.position[1]:
					horizontal += 1
				else:
					diagonal += 1
	_check(diagonal > 0 and horizontal > diagonal, "Generated slide directions mix horizontal and diagonal")
	_check(holds > 0 and longer_lead, "Generated notes include sustained holds and longer visibility")
	var total: int = chart.notes.size()
	chart.undo()
	_check(chart.notes.size() == 1, "A single undo only removes generated edits")
	chart.redo()
	_check(chart.notes.size() == total, "A single redo restores the full chart")

	var draft := Plan.new(chart)
	_check_context_budget(automatic._workspace.copilot._agent, draft)
	var state: Dictionary = draft.notes[initial].duplicate()
	var colliding := {"type": "note", "time_ms": state.time_ms, "lane": 6, "x": state.x, "y": state.y}
	_check(draft.edit("add_notes", [colliding, {}]).has("error") and draft.notes.size() == total, "Invalid batch is atomic")
	var addition := draft.edit("add_notes", [colliding])
	var added: int = addition.ids[0]
	_check(draft.check_conflicts().error_count > 0, "Conflict check catches simultaneous notes close together")
	_check(not draft.edit("delete_notes", [added]).has("error"), "Model can delete by stable ID")
	_check(not draft.edit("move_notes", [{"id": initial, "time_ms": 1900, "lane": 7}]).has("error"), "Model can move by time and lane")
	_check(not draft.edit("set_positions", [{"id": initial, "x": 880, "y": 555}]).has("error"), "Model can change position")
	_check(chart.notes[initial].end_time == 1600 and draft.notes[initial].x == 880, "Draft remains isolated until committed")

	_check(Agent.endpoint_from_url("https://example.org") == "https://example.org/v1/chat/completions", "Bare host uses the API version path")
	_check(Agent.endpoint_from_url("http://localhost:8080/v1") == "http://localhost:8080/v1/chat/completions", "Local service can use HTTP")
	_check(Agent.endpoint_from_url("http://example.org/v1").is_empty(), "Remote service requires TLS")
	desktop._message.hide()
	_check_animation(automatic, chart, draft)
	_check_playability(chart)
	_check_native_tools(automatic, chart)
	_check_animation_finish(automatic, chart)
	await _check_cross_analysis(automatic, chart)
	print("AUTOMATIC_CHART notes=", total, " horizontal=", horizontal, " diagonal=", diagonal, " holds=", holds, " failures=", failures)
	quit(1 if failures else 0)

func _check_animation(automatic: Node, chart: Node, draft: RefCounted) -> void:
	var cover := _fixture_cover(automatic)
	var art: Dictionary = automatic._prepare_cover(cover)
	_check(str(art.get("data_url", "")).begins_with("data:image/jpeg;base64,"), "Cover becomes a bounded vision input")
	var animations := AnimationDraft.new(chart, draft.duration_ms, [art])
	_check(animations.add_layer({"source": "cover", "keyframes": [{"time_ms": 0}, {"time_ms": 10}]}).has("error"), "Animation validation rejects rapid changes")
	_check(animations.add_layer({"source": "cover", "keyframes": [
		{"time_ms": 0, "rotation": 0.0}, {"time_ms": 500, "rotation": 60.0}]}).has("error"),
		"Cover animation rejects abrupt camera rotation")
	var added := animations.add_layer({"source": "cover", "keyframes": [
		{"time_ms": 0, "opacity": 0.0}, {"time_ms": 1000, "x": 1100, "scale": 1.12, "rotation": 5, "opacity": 0.78, "easing": "out"}]})
	_check(added.has("slot"), "Cover animation can be drafted")
	if not added.has("slot"):
		return
	chart.apply_automatic_notes({}, {}, animations.layers.values())
	var state: Dictionary = chart.interpolate_anim_rect_state(added.slot, 1500)
	_check(is_equal_approx(state.pos.x, 1100.0) and is_equal_approx(state.rgba.a, 0.78), "Editor interpolates a readable cover layer")
	var exported: Array = chart.to_export_dict().anim_rect_slots[added.slot]
	_check(exported.size() >= 3 and exported[0].image.path == cover, "Export keeps the original image and editable animation steps")
	_check(exported.any(func(item: Dictionary): return item.get("pos", {}).get("ease") == Tween.EASE_OUT),
		"Export retains the requested easing")
	chart.undo()
	_check(not chart.is_anim_rect_slot_edited(added.slot) and chart.get_anim_rect_events(added.slot)[0].image.path.is_empty(),
		"Animation is undone in one action")

func _check_playability(chart: Node) -> void:
	var draft := Plan.new(chart, "EZ")
	draft.notes.clear()
	_check(draft.edit("add_notes", [{"type": "note", "time_ms": 600, "lane": 0, "x": 820, "y": 460}]).has("error"),
		"Easy preserves initial reaction time")
	_check(draft.edit("add_notes", [{"type": "hold", "time_ms": 3500, "duration_ms": 300,
		"lane": 0, "x": 820, "y": 460}]).has("error"), "Easy disallows undersized holds")
	var hits := draft.edit("add_notes", [{"type": "note", "time_ms": 3500, "lane": 0, "x": 820, "y": 460},
		{"type": "drag", "time_ms": 4100, "lane": 1, "x": 850, "y": 465}])
	var repeats := draft.check_conflicts()
	_check(repeats.error_count == 0 and repeats.warnings.any(func(warning: Array): return warning[0].contains("落点重复")),
		"Intentional nearby targets across different beats produce an advisory warning")
	if hits.has("ids"):
		draft.edit("set_positions", [{"id": hits.ids[1], "x": 1120, "y": 470}])
		_check(draft.check_conflicts().error_count == 0, "A position edit can resolve the repeat")
	draft.notes.clear()
	var center_hits := []
	for index in range(8):
		center_hits.append({"type": "note", "time_ms": 3000 + index * 750, "lane": index % 4,
			"x": 670 + (index % 4) * 155, "y": 410 + floori(index / 4.0) * 205})
	var cluster := draft.edit("add_notes", center_hits)
	var centered := draft.check_conflicts()
	_check(cluster.has("ids") and centered.error_count == 0 and centered.warnings.any(
		func(w: Array): return w[0].contains("画面中央")), "A centered phrase yields a nonblocking spatial warning")
	draft.notes.clear()
	var drags := []
	for index in range(4):
		drags.append({"type": "drag", "time_ms": 4000 + index * 700, "lane": index,
			"x": 470 + index * 300, "y": 470, "approach_x": 320 + index * 300, "approach_y": 630})
	var slides := draft.edit("add_notes", drags)
	var report := draft.check_conflicts()
	var directions: Dictionary = report.get("slide_directions", {})
	_check(report.error_count == 0 and report.warning_count == 1 and directions.get("diagonal") == 4 and directions.get("horizontal") == 0,
		"An all-diagonal passage reports the direction counts without blocking edits")
	if slides.has("ids"):
		draft.edit("set_positions", [{"id": slides.ids[0], "approach_y": 470}, {"id": slides.ids[1], "approach_y": 470}])
		_check(draft.check_conflicts().error_count == 0, "A mix of horizontal and diagonal slides passes")

func _check_native_tools(automatic: Node, chart: Node) -> void:
	var agent: Node = automatic._workspace.copilot._agent
	agent.open_tool_session(Plan.new(chart, "HD"), {}, [], null, {})
	var new_hold: Dictionary = agent._call_tool("add_notes", {"notes": [{"type": "hold", "time_ms": 8000,
		"lane": 0, "x": 780, "y": 480, "duration_ms": 1800}]})
	_check(new_hold.has("ids"), "Agent can draft a sustained hold")
	if not new_hold.has("ids"):
		return
	var id: int = new_hold.ids[0]
	_check(not agent._call_tool("resize_holds", {"notes": [{"id": id, "duration_ms": 2400}]}).has("error"), "Agent can revise the held span")
	_check(not agent._call_tool("set_note_lead_in", {"notes": [{"id": id, "lead_ms": 1450}]}).has("error"), "Agent can adjust visibility independently")
	_check(not agent._call_tool("set_hold_path", {"notes": [{"id": id, "end_x": 1050, "end_y": 480, "mid_x": 890, "mid_y": 440}]}).has("error"),
		"Agent can draft a native curved hold path")
	chart.apply_automatic_notes(agent._plan.notes, {id: true})
	_check(chart.notes[id].start_time == 6550 and chart.notes[id].judge_time == 8000
		and chart.notes[id].end_time == 10400 and chart.notes[id].line == [[780.0, 480.0], [1050.0, 480.0], [890.0, 440.0]],
		"Lead-in, judgement, release and path survive draft commit")
	var curve_point: Vector2 = chart.get_hold_move_position(id, 9200)
	_check(curve_point.y < 479, "Preview follows the native curved hold")
	var second := Plan.new(chart, "HD")
	second.edit("resize_holds", [{"id": id, "duration_ms": 3200}])
	chart.apply_automatic_notes(second.notes, second.edited)
	_check(chart.notes[id].end_time == 11200 and chart.notes[id].line.size() == 3, "Resizing a committed hold preserves its curve")
	agent._plan = Plan.new(chart, "HD")
	var scaled: Dictionary = agent._call_tool("scale_hold_paths", {"ids": [id], "factor": 1.2})
	var scaled_hold: Dictionary = agent._plan.notes[id]
	_check(scaled.get("count") == 1 and is_equal_approx(scaled_hold.end_x, 1104.0)
		and scaled_hold.time_ms == 8000 and scaled_hold.duration_ms == 3200 and scaled_hold.lead_ms == 1450,
		"Direct hold tool scales selected spatial geometry independently of all timing")
	var pitch := []
	for time in range(1000, 2501, 100):
		pitch.append({"time_ms": time, "hz": 440.0})
	agent._music = {"melody": pitch, "beats": [1000, 1500, 2000, 2500]}
	var sustain: Dictionary = agent._call_tool("get_sustain_candidates", {"minimum_ms": 1200})
	var features: Dictionary = agent._call_tool("get_audio_features", {"from_ms": 1000, "to_ms": 3000, "window_ms": 2000})
	var stats: Dictionary = agent._call_tool("get_chart_statistics", {"from_ms": 7900, "to_ms": 8500})
	_check(sustain.total == 1 and sustain.items[0].duration_ms == 1500 and features.items[0].beats_count == 4
		and features.items[0].melody_hz == [440.0, 440.0] and stats.items[0].hold > 0,
		"Agent receives bounded and useful musical and density detail")
	_check(agent._call_tool("get_reference_grid", {}).total > 0
		and agent._call_tool("get_project_context", {}).available_results.beats == 4
		and Context.describe(false, false, false).size() < Context.describe(true, true, true).size(),
		"Editor context reflects chart data and tool permissions")
	var bright := Image.create_empty(12, 12, false, Image.FORMAT_RGB8)
	bright.fill(Color("#fff8ec"))
	var cover_visibility: Dictionary = automatic._cover_visibility(bright)
	var animation := AnimationDraft.new(chart, 12000, [{"visibility": cover_visibility, "path": "cover.png"}])
	var before := animation.check_cover_contrast({"times_ms": [1000]})
	var mask := animation.create_solid_mask({"color": "#111827", "opacity": 0.62})
	animation.set_mask_cue({"time_ms": 0, "mask_id": mask.mask_id, "use_cover_artwork": true})
	var after := animation.check_cover_contrast({"times_ms": [1000]})
	_check(cover_visibility.bright_playfield and before.items[0].review_rendered_frame
		and not after.items[0].review_rendered_frame, "Bright cover contrast check responds to the actual mask")
	var layer := animation.add_layer({"keyframes": [{"time_ms": 0}, {"time_ms": 1200, "opacity": 0.25}]})
	if layer.has("slot"):
		var revised := animation.update_layer({"slot": layer.slot, "keyframes": [{"time_ms": 0}, {"time_ms": 1600, "opacity": 0.35}]})
		_check(revised.has("slot") and animation.layers[layer.slot].frames[-1].time_ms == 1600, "Draft animations can be revised in place")
	agent._clear_state()
	chart.undo()
	chart.undo()

func _check_animation_finish(automatic: Node, chart: Node) -> void:
	var agent: Node = automatic._workspace.copilot._agent
	var animation := AnimationDraft.new(chart, 16000, [])
	agent.open_tool_session(Plan.new(chart, "HD"), {}, [], animation, {})
	agent._edit_notes = false
	var mask := animation.create_solid_mask({"color": "#111827", "opacity": 0.62})
	animation.set_mask_cue({"time_ms": 2000, "mask_id": mask.mask_id})
	_check(agent._call_tool("finish", {}).has("error"), "A static dark mask cannot fulfill an animation request")
	animation.add_layer({"keyframes": [{"time_ms": 0, "opacity": 0.0}, {"time_ms": 1500, "opacity": 0.27}]})
	_check(agent._call_tool("finish", {}).has("error"), "A flat tint fade alone cannot fulfill an animation request")
	animation.add_layer({"keyframes": [{"time_ms": 0, "opacity": 0.15, "x": 700},
		{"time_ms": 1500, "opacity": 0.30, "x": 960}]})
	_check(agent._call_tool("finish", {}).has("finished"), "A visible moving animation may finish")
	agent.cancel()
	var reveal := AnimationDraft.new(chart, 16000, [])
	var clear := reveal.create_solid_mask({"color": "#111827", "opacity": 0.0})
	reveal.set_mask_cue({"time_ms": 800, "mask_id": clear.mask_id})
	reveal.add_mask_reveal({"time_ms": 2000, "duration_ms": 2400, "radius_px": 600})
	_check(not reveal.has_visible_motion(), "An aperture with a transparent mask has no visible effect")
	var dark := reveal.create_solid_mask({"color": "#111827", "opacity": 0.65})
	reveal.set_mask_cue({"time_ms": 1600, "mask_id": dark.mask_id})
	_check(reveal.has_visible_motion(), "An aperture visibly opens through an active dark mask")

func _check_cross_analysis(automatic: Node, chart: Node) -> void:
	var agent: Node = automatic._workspace.copilot._agent
	var prior: Dictionary = chart.rhythm_analysis.duplicate(true)
	agent.open_tool_session(Plan.new(chart), {}, [], null, {"reanalyze": automatic._workspace._analyze_for_agent})
	var result: Dictionary = await agent._analyze_audio({"engine": "native", "tasks": ["beats", "tempo"], "limit": 5}, agent._run_id)
	var beats: Dictionary = result.get("results", {}).get("beats", {})
	_check(not result.has("error") and beats.get("total", 0) > 5 and beats.get("items", []).size() == 5
		and agent._music.get("beats", []).size() > 5 and chart.rhythm_analysis == prior,
		"Agent uses the real native analyzer without overwriting the editing reference")
	var workspace: Node = automatic._workspace
	var request := {"engine": "native", "tasks": ["beats", "tempo"]}
	var reused: Dictionary = await workspace._analyze_for_agent(request)
	_check(reused.cache_hits == ["beats", "tempo"] and not reused.has("inferred_tasks") and not workspace._analyzing,
		"Repeated cross-analysis reuses the existing results instead of re-running inference")
	var cached: Dictionary = workspace._cached_chart_music()
	_check(not cached.get("beats", []).is_empty() and not cached.get("tempo_curve", []).is_empty(),
		"Co-pilot and MCP share the audio cache")
	agent.cancel()

func _fixture_cover(automatic: Node) -> String:
	var image := Image.create_empty(900, 550, false, Image.FORMAT_RGB8)
	image.fill(Color("#365fae"))
	image.fill_rect(Rect2i(610, 100, 200, 280), Color("#fecf5e"))
	var temporary := ProjectSettings.globalize_path("user://agent-art-test.png")
	image.save_png(temporary)
	return temporary.get_file() if automatic._workspace._import_image(temporary, false) else ""

func _check_ex_chords(rows: Array, ignored: Array) -> void:
	var groups := {}
	for note: Dictionary in rows:
		if note.type == "hold" or note.endTime in ignored:
			continue
		groups[note.endTime] = int(groups.get(note.endTime, 0)) + 1
	var sizes := groups.values()
	var doubles_and_triples := sizes.count(2) + sizes.count(3)
	_check(not sizes.is_empty() and sizes.all(func(size: int): return size >= 1 and size <= 4)
		and 1 in sizes and 2 in sizes and 3 in sizes and 4 in sizes
		and doubles_and_triples * 2 > sizes.size() and sizes.count(4) * 5 <= sizes.size(),
		"EX mainly uses doubles and triples with singles and occasional quadruples: " + str(sizes))

func _check_context_budget(agent: Node, draft: RefCounted) -> void:
	agent._plan = draft
	agent._messages.assign([{"role": "system", "content": "instructions"}, {"role": "user", "content": "original brief"}])
	for index in range(18):
		agent._messages.append({"role": "assistant", "content": "..." + str(index)})
		agent._messages.append({"role": "user", "content": ("节拍数据".repeat(1000)) + str(index)})
	var wire: String = agent._request_payload()
	var body: Variant = JSON.parse_string(wire)
	var messages: Array[Dictionary] = []
	if body is Dictionary:
		messages.assign(body.messages)
	_check(body is Dictionary and wire.to_utf8_buffer().size() <= Agent.REQUEST_BYTES
		and agent._text_bytes(messages) <= Agent.TEXT_CONTEXT_BYTES and agent._compacted > 0
		and body.messages[0].content.contains("draft_note_count") and body.messages[1].content == "original brief"
		and body.messages[-1].content.ends_with("17") and agent._request_payload() == wire,
		"Long UTF-8 requests compact old pairs, retain the latest results and retry the identical payload")
	agent._clear_state()
	agent._compacted = 0
