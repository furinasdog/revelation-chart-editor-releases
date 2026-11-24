extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desk: Node = current_scene.desktop
	desk._onboarding._chooser.hide()
	if not desk.import_audio(args[0], false, false):
		quit(2)
		return
	desk.chart.set_audio_delay(500)
	desk._set_loop_range(Vector2(2500, 5000))
	desk.automatic._settings = {"url": args[1], "model": "mock-audio", "key": "test-only"}
	desk._set_copilot_visible(true)
	var dock: PanelContainer = desk.copilot
	for share in [false, true]:
		dock._share_art.button_pressed = share
		dock._editor.text = "带图检查选段" if share else "仅用文字检查选段"
		dock._submit()
		var deadline := Time.get_ticks_msec() + 18000
		while dock.busy and Time.get_ticks_msec() < deadline:
			await process_frame
		var expected := "选段波形和频谱已检查。" if share else "选段响度已检查。"
		if dock.busy or dock._history[-1].get("text", "") != expected:
			push_error("Audio tools did not deliver the requested text/image results.")
			quit(1)
			return
	if not desk.chart.notes.is_empty():
		push_error("Audio queries must leave the chart unchanged.")
		quit(1)
		return
	var previous_name: String = desk.chart.chart_info.chartName
	dock._editor.text = "绘制方形动画"
	dock._submit()
	var deadline := Time.get_ticks_msec() + 18000
	var approved: Array[String] = []
	while dock.busy and Time.get_ticks_msec() < deadline:
		if dock._approval.visible:
			approved.append(dock._approval_title.text)
			dock._resolve_approval(true)
		await process_frame
	var layer: Array = desk.chart.get_anim_rect_events(0)
	if (dock.busy or approved.size() != 3 or not approved[0].contains("绘制透明图形素材")
			or layer.size() < 2 or desk.chart.chart_info.chartName != "图形测试"):
		push_error("Co-pilot must approve and commit shape animation and chart metadata. " + str(dock._history[-1]))
		quit(1)
		return
	var path: String = layer[0].get("image", {}).get("path", "")
	if not FileAccess.file_exists(desk.chart.resolve_full_path(path)):
		push_error("Co-pilot shape animation must resolve the published asset.")
		quit(1)
		return
	var first: Dictionary = desk.chart.interpolate_anim_rect_state(0, 1000.0)
	var later: Dictionary = desk.chart.interpolate_anim_rect_state(0, 1600.0)
	if first.rgba.a <= 0.12 or later.rgba.a <= 0.12 or later.pos.x - first.pos.x < 30.0:
		push_error("The committed shape must move while visible in playback.")
		quit(1)
		return
	desk.chart.undo()
	if desk.chart.chart_info.chartName != previous_name or desk.chart.is_anim_rect_slot_edited(0):
		push_error("Co-pilot shape animation and metadata must undo together.")
		quit(1)
		return
	var old_audio: String = desk.chart.audio_path
	desk.chart.add_note_at_times(0, 2000, 3000, 0, 1, Vector2(850, 480))
	desk.chart.set_rhythm_analysis({"beats": [400, 800]})
	dock._editor.text = "导入指定的另一段音频并检查。"
	dock._submit()
	deadline = Time.get_ticks_msec() + 18000
	var imports := 0
	while dock.busy and Time.get_ticks_msec() < deadline:
		if dock._approval.visible:
			if "导入本机音频" in dock._approval_title.text and "清空旧分析" in dock._approval_details.text:
				imports += 1
			dock._resolve_approval(true)
		await process_frame
	if (dock.busy or imports != 1 or desk.chart.notes.size() != 1 or not desk.chart.rhythm_analysis.is_empty()
			or desk.chart.audio_path == old_audio or dock._history[-1].get("text") != "音频已导入并校验。"):
		push_error("Co-pilot should approve audio import, preserve notes, and continue with fresh project data. " + str(dock._history[-1]))
		quit(1)
		return
	var second: int = desk.chart.add_note_at_times(0, 3800, 4800, 0, 2, Vector2(1250, 620))
	dock._editor.text = "把这两个音符向右移动。"
	dock._submit()
	deadline = Time.get_ticks_msec() + 18000
	var write_approvals := 0
	while dock.busy and Time.get_ticks_msec() < deadline:
		if dock._approval.visible:
			if "调整音符位置" in dock._approval_title.text and "2 项" in dock._approval_details.text:
				write_approvals += 1
			dock._resolve_approval(true)
		await process_frame
	if dock.busy or write_approvals != 1 or desk.chart.notes[second].position.x != 1300.0:
		push_error("Co-pilot must recover from two malformed tool replies and apply a two-note batch under one approval. " + str(dock._history[-1]))
		quit(1)
		return
	desk.chart.set_bpm(120.0)
	var target: int = desk.chart.add_note_at_times(0, 11000, 12000, 0, 1, Vector2(900, 500))
	var hold: int = desk.chart.add_note_at_times(2, 11100, 13500, 12500, 3, Vector2(600, 600))
	desk.chart.set_rhythm_analysis({"accents": [12000 - roundi(desk.chart.audio_delay_ms)]})
	desk.chart.set_rt_pointer_time(12000)
	dock._editor.text = "把第25拍，12秒的普通键向右移动。"
	dock._submit()
	deadline = Time.get_ticks_msec() + 18000
	var target_confirmed := false
	while dock.busy and Time.get_ticks_msec() < deadline:
		if dock._approval.visible:
			target_confirmed = ("#%d" % target) in dock._approval_details.text and "第 25 拍 · 0:12.0" in dock._approval_details.text
			dock._resolve_approval(target_confirmed)
		await process_frame
	if dock.busy or not target_confirmed or desk.chart.notes[target].position.x != 1100 or desk.chart.notes[hold].position.x != 600:
		push_error("Ruler lookup, measured audio evidence and approval must refer to the same note.")
		quit(1)
		return
	print("AGENT_AUDIO_AND_SHAPE_SMOKE verified")
	quit()
