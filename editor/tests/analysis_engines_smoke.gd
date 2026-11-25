extends SceneTree

const Analysis := preload("res://desktop/analysis.gd")
const ReferenceMode = preload("res://main/chart_data.gd").ReferenceMode

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1

func check_capture_preferences(desktop: Node) -> void:
	var prefs: Node = desktop.preferences
	var saved: Dictionary = prefs.analysis_options
	for options: Dictionary in [{"accent_sensitivity": 0}, {"sensitivity": 0, "accent_sensitivity": 35}]:
		prefs.analysis_options = options.duplicate()
		var panel := preload("res://desktop/analysis_panel.gd").new()
		panel.setup(prefs, desktop.chart, Control.new())
		check(panel.options().sensitivity == options.get("sensitivity", 100),
			"Legacy accent filtering does not hide detections; an explicit capture sensitivity of zero is preserved")
		panel.free()
	prefs.analysis_options = saved

func check_accent_density(analyzer: Node) -> void:
	# Two sections with identical dynamics and different recording levels. The
	# strong attacks in both sections should survive alongside no weak attacks.
	var pcm := PackedFloat32Array()
	var candidates := []
	var expected := []
	for gain in [0.045, 0.5]:
		for index in range(20):
			var marker := float(pcm.size() + 90)
			var strong := index % 4 != 0
			candidates.append(marker)
			if strong:
				expected.append(marker)
			for frame in range(180):
				pcm.append(float(gain) * (1.0 if frame >= 90 else (0.5 if strong else 0.95)))
	var path := "user://accent-density.f32"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(pcm.to_byte_array())
	file.close()
	var scores: Array = analyzer._accent_scores(path, 1000, candidates)
	var detected := Analysis.filter_accents(scores, 50)
	check(detected == expected, "Accents preserve strong attacks in quiet and loud sections without imposing a quota")
	check(Analysis.filter_accents(scores, 100).size() > detected.size(), "Higher sensitivity keeps additional measured attacks")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 4 or change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desktop: Node = current_scene.desktop
	var chart: Node = desktop.chart
	var analyzer: Node = desktop.analysis
	check_accent_density(analyzer)
	var audio := args[0]
	var changing := args[1]
	var manual := args[2]
	var models := args[3]
	var madmom := {"engine": "madmom", "tempo_engine": "madmom", "model": "recurrent",
		"tasks": ["beats", "downbeats", "onsets", "accents", "tempo"], "madmom_model_cache": models}
	var essentia := {"engine": "essentia", "tempo_engine": "essentia", "model": "multifeature",
		"tasks": ["beats", "onsets", "melody", "tempo"]}
	var results := {}
	for options in [madmom, essentia]:
		var backend := str(options.engine)
		var result: Dictionary = analyzer.analyze_file(audio, "", options)
		check(not result.has("error"), backend + " returns real results: " + str(result.get("error", "")))
		check(result.get("beats", []).size() >= 44 and result.get("onsets", []).size() >= 40, backend + " captures clicks")
		var curve: Array = result.get("tempo_curve", [])
		check(not curve.is_empty() and absf(float(curve[0].bpm) - 120) < 3, backend + " reports steady tempo")
		var variable: Dictionary = analyzer.analyze_file(changing, "", options)
		var tempo_range := [INF, -INF]
		for point: Dictionary in variable.get("tempo_curve", []):
			tempo_range[0] = minf(tempo_range[0], point.bpm)
			tempo_range[1] = maxf(tempo_range[1], point.bpm)
		print(backend, " changing tempo range ", tempo_range)
		check(tempo_range[0] < 125 and tempo_range[1] > 170, backend + " preserves tempo changes")
		results[backend] = result
	check(results.madmom.get("downbeats", []).size() >= 9, "madmom detects bar downbeats")
	check(results.madmom.get("accents", []).size() >= 8
		and results.madmom.accents.size() <= results.madmom.onsets.size(), "Accents derive from observed onsets")
	var external_melody: Dictionary = analyzer.analyze_file(manual, "", essentia)
	var voiced := 0
	for point: Dictionary in external_melody.get("melody", []):
		if point.hz > 55:
			voiced += 1
	check(voiced > 100, "Essentia estimates predominant frequency on music")
	var mixed := {"engine": "madmom", "tempo_engine": "native", "model": "default", "tasks": ["onsets", "tempo"],
		"madmom_model_cache": models}
	var independent: Dictionary = analyzer.analyze_file(manual, "", mixed)
	var native_curve: Array = independent.get("tempo_curve", [])
	check(independent.get("onsets", []).size() > 100 and independent.get("beats", []).is_empty()
		and not native_curve.is_empty() and absf(float(native_curve[0].bpm) - 150) < 0.5,
		"Task selection and BPM source are independent on a manually charted song")
	var spectrum: Dictionary = analyzer.analyze_file(manual, "", {"spectrum_only": true})
	var decoded := Image.new()
	check(spectrum.has("spectrum") and decoded.load_png_from_buffer(spectrum.get("spectrum", PackedByteArray())) == OK
		and decoded.get_width() >= 1200, "Spectrogram produces a decodable frequency plot")
	chart.set_rhythm_analysis(independent)
	desktop.sidebar.set_guide_mode(ReferenceMode.BEATS)
	chart.set_analysis_mapping("onsets")
	check(desktop.grid.capture_lines.positions.size() == independent.get("onsets", []).size(), "Selected onsets are mapped to the timeline")
	chart.set_analysis_mapping("downbeats")
	check(desktop.grid.capture_lines.positions.is_empty(), "Missing mapped markers do not fall back to another task")
	chart.restore_rhythm_fields({"rhythmAnalysis": chart.rhythm_analysis})
	check(chart.analysis_mapping == "downbeats", "Chart persistence restores marker mapping")

	# Unsupported tasks and model-cache errors still leave independent tasks available to the Agent.
	var partial: Dictionary = analyzer.analyze_file(audio, "", {"engine": "essentia", "tempo_engine": "native", "tasks": ["downbeats", "tempo"]})
	check(partial.task_errors.has("downbeats") and not partial.get("tempo_curve", []).is_empty(), "Mixed engine requests report partial success")
	var bad_model: Dictionary = analyzer.analyze_file(audio, "", {"engine": "madmom", "tempo_engine": "native", "tasks": ["onsets", "tempo"], "madmom_model_cache": audio})
	check(str(bad_model.task_errors.get("onsets", "")).contains("模型缓存路径指向文件") and not bad_model.get("tempo_curve", []).is_empty(), "An invalid model directory leaves independent tempo detection usable")

	desktop.import_audio(audio, false)
	desktop._open_analysis_settings()
	var panel: Control = desktop._analysis_panel
	check_capture_preferences(desktop)
	check(desktop._tabs.current_tab == panel.get_index() and panel.selected_id == "beat", "The capture panel starts on Beat This!")
	check(not chart.has_project_bpm and panel._run.text == "采音", "A new audio chart has no confirmed BPM or cached beat capture")
	panel._run.pressed.emit()
	check(desktop._analyzing and desktop._analysis_request.tasks == ["beats"], "Only the selected task is requested")
	if desktop._analyzing:
		await analyzer.completed
	check(chart.rhythm_analysis.capture_id == "beat" and chart.rhythm_analysis.get("tempo_curve", []).is_empty(),
		"Beat capture applies beats without a separate tempo or emotion task")
	check(chart.has_project_bpm and absf(chart.bpm - 120) < 3, "Raw beat spacing fills the initial project BPM")
	check(panel._run.text == "应用" and desktop.grid.reference_mode == ReferenceMode.BEATS, "The finished result is displayed and reusable")
	check("本次采音" in panel._summary.text and "首个" in panel._summary.text,
		"The capture panel shows the result source, counts and the first marker after inference")
	var applied: Dictionary = chart.rhythm_analysis.duplicate(true)
	panel.select("beat-madmom")
	check(panel._run.text == "采音" and chart.rhythm_analysis == applied, "Beat models have independent cache status and switching preserves the timeline")
	desktop.preferences.analysis_options["madmom_model_cache"] = models
	panel.select("onset-cnn")
	panel._run.pressed.emit()
	if desktop._analyzing:
		await analyzer.completed
	check(chart.rhythm_analysis.capture_id == "onset-cnn" and panel._run.text == "应用", "A single madmom onset capture is cached")
	applied = chart.rhythm_analysis.duplicate(true)
	panel.select("onset-rnn")
	check(panel._run.text == "采音" and chart.rhythm_analysis == applied, "The recurrent model cannot use the convolutional onset cache")
	panel.select("onset-cnn")
	panel._sensitivity.value = 100
	check(chart.rhythm_analysis == applied, "Editing sensitivity leaves the applied result intact")
	var decoder: String = desktop.preferences.ffmpeg_path
	desktop.preferences.ffmpeg_path = "user://missing-ffmpeg.exe"
	panel._run.pressed.emit()
	check(not desktop._analyzing and chart.rhythm_analysis.capture_sensitivity == 100 and chart.rhythm_analysis.capture_markers == chart.rhythm_analysis.onsets, "Applying cached onsets at maximum sensitivity uses all raw detections without decoding")
	check("已应用缓存" in panel._summary.text and "首个" in panel._summary.text, "Cached results are identified next to the capture button")
	desktop.sidebar.set_guide_mode(ReferenceMode.TRADITIONAL)
	check("自动采音线" in panel._summary.text, "The result describes how to see it when traditional guides are selected")
	desktop.sidebar.set_guide_mode(ReferenceMode.BEATS)
	panel.select("beat")
	chart.set_bpm(155)
	panel._run.pressed.emit()
	check(is_equal_approx(chart.bpm, 155.0), "Applying a beat result preserves the manually entered tempo")
	var saved: Dictionary = chart.to_export_dict()
	chart.restore_rhythm_fields(saved)
	check(chart.has_project_bpm and chart.rhythm_analysis.capture_id == "beat" and chart.rhythm_analysis.capture_sensitivity == 100, "Chart persistence restores capture identity and sensitivity")
	panel.select("onset")
	panel._run.pressed.emit()
	if desktop._analyzing:
		await analyzer.completed
	check(desktop._message.visible and desktop._message.dialog_text.contains("FFmpeg") and chart.rhythm_analysis.capture_id == "beat", "A failed capture retains the previous result")
	desktop._message.hide()
	desktop.preferences.ffmpeg_path = decoder
	panel.select("tempo")
	panel._run.pressed.emit()
	if desktop._analyzing:
		await analyzer.completed
	check(chart.rhythm_analysis.capture_id == "tempo" and absf(chart.bpm - 120) < 3 and chart.rhythm_analysis.capture_markers.is_empty(), "Explicit BPM capture sets project tempo and adds no event lines")
	desktop.sidebar.set_guide_mode(ReferenceMode.TRADITIONAL)
	panel._run.pressed.emit()
	check(not desktop._analyzing and desktop.grid.reference_mode == ReferenceMode.TRADITIONAL,
		"Applying cached BPM keeps the selected traditional reference lines")
	desktop._request_spectrum()
	if desktop._analyzing:
		await analyzer.completed
	check(desktop._spectrum_image.texture != null, "The spectrum entry point still produces an image")
	desktop._message.hide()
	panel.select("melody")
	check(desktop.import_audio(manual), "Import audio with melody chosen")
	check(desktop._ask.dialog_text.contains("主旋律") and panel._run.text == "采音", "Import offers the selected task for the new audio only")
	desktop._ask.hide()
	desktop._ask.confirmed.emit()
	if desktop._analyzing:
		await analyzer.completed
	check(chart.rhythm_analysis.get("capture_id") == "melody" and not chart.rhythm_analysis.get("melody", []).is_empty()
		and chart.rhythm_analysis.get("tempo_curve", []).is_empty(), "Import analyzes only the selected melody")
	print("ANALYSIS_ENGINES_SMOKE failures=", failures)
	quit(1 if failures else 0)
