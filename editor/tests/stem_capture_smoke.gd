extends SceneTree

const Analysis := preload("res://desktop/analysis.gd")
const Cache := preload("res://desktop/stem_cache.gd")
const CaptureCatalog := preload("res://desktop/capture_catalog.gd")
const Plan := preload("res://desktop/auto_chart_plan.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, description: String) -> void:
	if not ok:
		push_error(description)
		failures += 1

func _write_clicks(path: String, bpm: float) -> void:
	var rate := 44100
	var pcm := PackedByteArray()
	pcm.resize(16 * rate * 4)
	for beat in range(ceili(15.0 * bpm / 60.0)):
		var start := roundi((0.5 + 60.0 * beat / bpm) * rate)
		for frame in range(900):
			var signal_value := roundi(22000 * sin(2.0 * PI * 1000 * frame / rate) * exp(-frame / 220.0))
			pcm.encode_s16((start + frame) * 4, signal_value)
			pcm.encode_s16((start + frame) * 4 + 2, signal_value)
	var wav := AudioStreamWAV.new()
	wav.stereo = true
	wav.mix_rate = rate
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.data = pcm
	_check(wav.save_to_wav(path) == OK, "Write click track")

func _check_levels() -> void:
	var path := "user://stem-capture-levels.f32"
	var file := FileAccess.open(path, FileAccess.WRITE)
	var samples := PackedFloat32Array()
	samples.resize(2500)
	for index in range(1810, 1870):
		samples[index] = 1.0
	file.store_buffer(samples.to_byte_array())
	file.close()
	var result := {"beats": [800.0, 1820.0], "capture_levels": Analysis._capture_levels(path, 1000, [800.0, 1820.0])}
	var original := PackedFloat32Array()
	original.resize(250)
	original[80] = 1.0
	var options := CaptureCatalog.options("beat", 50)
	options["capture_stem"] = "drums"
	var applied := CaptureCatalog.applied_result(options, result, {}, original, 10.0)
	_check(applied.capture_markers == [1820.0], "Sensitivity follows the isolated track rather than the full mix")

func _run() -> void:
	if change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	_check_levels()
	var desk: Node = current_scene.desktop
	var panel: Control = desk._analysis_panel
	var source: OptionButton = panel._source
	var chart: Node = desk.chart
	var service: Node = desk._stem_separation
	var original := "user://stem-capture-original.wav"
	var replacement := "user://stem-capture-replacement.wav"
	_write_clicks(original, 120)
	_write_clicks(replacement, 96)
	if not desk.import_audio(original, false, false):
		quit(2)
		return
	desk._open_analysis_settings()
	panel.select("tempo")
	panel._run.pressed.emit()
	if desk._analyzing:
		await desk.analysis.completed
	var mix: Dictionary = chart.rhythm_analysis.duplicate(true)
	_check(mix.get("capture_id") == "tempo" and absf(chart.bpm - 120) < 4.0 and panel._run.text == "应用", "Original audio is analyzed and cached")
	var agent: Node = desk.copilot._agent
	agent.open_tool_session(Plan.new(chart), {}, [], null, {"reanalyze": desk._analyze_for_agent})
	var unavailable: Dictionary = await agent.call_workspace_tool("analyze_audio", {"capture_id": "tempo", "stem": "drums"}, Vector2.ZERO)
	_check(unavailable.has("error") and unavailable.error.contains("分轨") and agent._analysis_requests == 0,
		"An unavailable stem is reported without substituting the full mix")
	for id: String in CaptureCatalog.ENTRIES:
		var options := CaptureCatalog.agent_options({"capture_id": id, "stem": "vocals"})
		_check(not options.has("error") and options.model == CaptureCatalog.ENTRIES[id].model and options.capture_stem == "vocals",
			"Agent exposes UI capture " + id)

	var folder: String = service._cache_dir
	DirAccess.make_dir_recursive_absolute(folder)
	for stem: String in Cache.STEMS:
		_write_clicks(folder.path_join(stem + ".wav"), 150 if stem == "drums" else 120)
	service.refresh()
	var drums_path: String = service.stem_path("drums")
	var result: Dictionary = await agent.call_workspace_tool("analyze_audio", {"capture_id": "tempo", "stem": "drums"}, Vector2.ZERO)
	_check(result.get("stem") == "drums" and absf(float(result.get("detected_bpm", 0)) - 150.0) < 4.0 and chart.rhythm_analysis == mix,
		"Agent infers actual drum tempo without changing the chart guide")
	var degara: Dictionary = await agent.call_workspace_tool("analyze_audio",
		{"engine": "essentia", "model": "Degara", "tasks": ["beats", "tempo"], "stem": "drums", "limit": 4}, Vector2.ZERO)
	_check(not degara.has("error") and degara.get("model") == "degara" and degara.get("results", {}).get("beats", {}).get("total", 0) > 4,
		"Agent can request native Essentia Degara inference with an explicit model")
	var repeated: Dictionary = await agent.call_workspace_tool("analyze_audio", {"capture_id": "beat-degara", "stem": "drums"}, Vector2.ZERO)
	_check(repeated.get("cache_hits") == ["beats"] and agent._analysis_requests == 2, "Preset and explicit model calls share the same track cache")
	var model_dir := OS.get_cmdline_user_args()
	if not model_dir.is_empty():
		desk.preferences.analysis_options["madmom_model_cache"] = model_dir[0]
		var madmom: Dictionary = await agent.call_workspace_tool("analyze_audio",
			{"capture_id": "onset-rnn", "stem": "drums"}, Vector2.ZERO)
		_check(not madmom.has("error") and madmom.get("model") == "recurrent"
			and madmom.get("results", {}).get("onsets", {}).get("total", 0) > 10,
			"Agent uses the configured madmom model directory and recurrent onset inference")
	agent.cancel()
	source.item_selected.emit(2)
	_check(panel._run.text == "应用" and chart.rhythm_analysis == mix and not panel._summary.visible,
		"Switching inputs leaves the applied result and shows independent cache state")
	chart.set_audio_delay(500.0)
	panel._run.pressed.emit()
	_check(not desk._analyzing and "已应用缓存" in panel._summary.text,
		"The capture panel can apply the cache produced by the Agent")
	if desk._analyzing:
		await desk.analysis.completed
	var drums: Dictionary = chart.rhythm_analysis.duplicate(true)
	_check(drums.get("capture_stem") == "drums" and absf(chart.bpm - 150) < 4.0 and panel._run.text == "应用",
		"Drums produce their own BPM and update the project")
	_check(chart.loaded_audio_path != drums_path and chart.monitor_audio_stream == null and chart.audio_delay_ms == 500.0,
		"Capture leaves playback and chart audio unchanged")
	source.item_selected.emit(1)
	_check(panel._run.text == "采音" and chart.rhythm_analysis == drums, "Vocals do not use the drum cache")
	source.item_selected.emit(0)
	panel._run.pressed.emit()
	_check(not desk._analyzing and not chart.rhythm_analysis.has("capture_stem") and absf(chart.bpm - 120) < 4.0,
		"Applying the original cache restores its own BPM")
	source.item_selected.emit(2)
	panel._run.pressed.emit()
	_check(not desk._analyzing and chart.rhythm_analysis == drums and "已应用缓存" in panel._summary.text,
		"Applying the drum cache performs no inference")
	chart.restore_rhythm_fields(chart.to_export_dict())
	_check(chart.rhythm_analysis.get("capture_stem") == "drums", "Applied track identity survives chart persistence")

	panel.select("beat")
	chart.has_project_bpm = false
	panel._run.pressed.emit()
	if desk._analyzing:
		await desk.analysis.completed
	var markers: Array = chart.applied_capture_markers()
	_check(not markers.is_empty() and desktop_first_marker_time(desk, chart) == roundi(markers[0] + 500),
		"Raw stem markers align with the original timeline and project audio delay")
	_check(chart.has_project_bpm and absf(chart.bpm - 150) < 4.0, "Beat capture can also fill an unset project BPM")

	_write_clicks(drums_path, 96)
	panel.select("tempo")
	panel._run.pressed.emit()
	_check(desk._analyzing, "Replacing a stem invalidates its cache even when source name and length match")
	if desk._analyzing:
		await desk.analysis.completed
	_check(absf(chart.bpm - 96) < 4.0, "A replaced track yields its own fresh BPM")
	DirAccess.remove_absolute(drums_path)
	desk._update_capture_panel()
	_check(not source.disabled, "A missing cached track keeps the source menu usable")
	source.get_popup().about_to_popup.emit()
	_check(source.selected == 0 and source.is_item_disabled(2), "Refreshing the menu disables a deleted track")
	_check(desk.import_audio(replacement, false, false) and source.selected == 0 and source.is_item_disabled(2)
			and panel._run.text == "采音", "Changing songs restores the default source and no cache leaks")
	print("STEM_CAPTURE_SMOKE failures=", failures)
	quit(1 if failures else 0)

func desktop_first_marker_time(desk: Node, chart: Node) -> int:
	var lines = desk.grid.capture_lines
	if lines.positions.is_empty():
		return -1
	var unit: int = lines.nearest_unit(chart.ms_to_beat_position(0.0))
	return lines.time_at(unit)
