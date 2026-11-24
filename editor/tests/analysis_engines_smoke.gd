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
	if args.size() != 4 or change_scene_to_file("res://main.tscn") != OK:
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
	check(desktop.grid._beat_positions.size() == independent.get("onsets", []).size(), "Selected onsets are mapped to the timeline")
	chart.set_analysis_mapping("downbeats")
	check(desktop.grid._beat_positions.is_empty(), "Missing mapped markers do not fall back to another task")
	chart.restore_rhythm_fields({"rhythmAnalysis": chart.rhythm_analysis})
	check(chart.analysis_mapping == "downbeats", "Chart persistence restores marker mapping")

	desktop.import_audio(audio)
	desktop._ask.hide()
	desktop._open_analysis_settings()
	var panel: Control = desktop._analysis_panel
	check(desktop._tabs.current_tab == panel.get_index(), "Analysis menu opens the inspector page")
	chart.set_rhythm_analysis({"onsets": [250.0], "duration_ms": 24000, "mapping": "onsets"})
	panel._run.pressed.emit()
	check(desktop._analyzing, "The inspector button starts the background analyzer")
	if desktop._analyzing:
		await analyzer.completed
	check(chart.rhythm_analysis.get("onsets", []) == [250.0] and not chart.rhythm_analysis.get("tempo_curve", []).is_empty(),
		"Rerunning selected tasks preserves other results")
	check(desktop._status.text.contains("成功") and desktop._status.text.contains("Beat This!"),
		"Inspector rerun displays which engine successfully produced the results")
	check(desktop._message.visible and desktop._message.title == "分析结果" and desktop._message.dialog_text.contains("使用Beat This!"),
		"A completed analysis opens a dialog naming the actual engine")
	desktop._message.hide()
	check(chart.analysis_mapping == "beats" and desktop.grid.show_rhythm_markers,
		"Freshly analyzed markers are shown instead of the previously mapped data")
	check(desktop._result.visible and desktop._status.text.contains("内置速度算法"),
		"Results open automatically and identify the independent speed source")
	var ess_request := {"engine": "essentia", "tempo_engine": "native", "model": "multifeature", "tasks": ["onsets"]}
	check(desktop._start_analysis(ess_request), "An onset-only analysis starts")
	if desktop._analyzing:
		await analyzer.completed
	check(desktop._status.text.contains("使用Essentia分析起音成功") and chart.analysis_mapping == "onsets"
		and desktop._plot_title.text.contains("此前"), "Onset-only analysis displays onsets and labels the old tempo plot")
	desktop._message.hide()
	var onsets: Array = chart.rhythm_analysis.get("onsets", []).duplicate()
	var decoder: String = desktop.preferences.ffmpeg_path
	desktop.preferences.ffmpeg_path = "user://missing-ffmpeg.exe"
	panel._accent_slider.value = 20
	var strict_count: int = chart.rhythm_analysis.get("accents", []).size()
	panel._accent_slider.value = 100
	check(not desktop._analyzing and not desktop._message.visible and chart.analysis_mapping == "accents"
		and chart.rhythm_analysis.get("accents", []).size() >= strict_count and chart.rhythm_analysis.onsets == onsets,
		"The slider refilters and maps accents immediately without a decoder or inference")
	var saved_analysis: Dictionary = JSON.parse_string(JSON.stringify(chart.rhythm_analysis))
	chart.restore_rhythm_fields({"rhythmAnalysis": saved_analysis})
	check(panel._accent_slider.value == 100 and not chart.rhythm_analysis.get("accent_filter", {}).is_empty(),
		"The analysis cache and slider value survive a chart round trip")
	desktop.preferences.ffmpeg_path = decoder
	saved_analysis.erase("accent_filter")
	chart.set_rhythm_analysis(saved_analysis)
	panel._accent_slider.value = 50
	check(desktop._analyzing and desktop._analysis_request.has("accent_input"), "A legacy chart measures strengths using its saved onsets")
	if desktop._analyzing:
		await analyzer.completed
	check(not desktop._message.visible and not chart.rhythm_analysis.get("accent_filter", {}).is_empty()
		and chart.rhythm_analysis.onsets == onsets, "Legacy refilter leaves inference results intact")
	chart.set_analysis_mapping("onsets")
	var partial_request := {"engine": "essentia", "tempo_engine": "native", "tasks": ["downbeats", "tempo"]}
	check(desktop._start_analysis(partial_request), "A request with independent results starts")
	if desktop._analyzing:
		await analyzer.completed
	check(desktop._status.text.contains("部分分析成功") and desktop._status.text.contains("不支持")
		and desktop._status.text.contains("保留了此前"), "A partial run reports the task error and retained history")
	desktop._message.hide()
	var blocked_model := {"engine": "madmom", "tempo_engine": "native", "tasks": ["onsets", "tempo"],
		"madmom_model_cache": audio}
	check(desktop._start_analysis(blocked_model), "The mixed request with an invalid model-cache path starts")
	if desktop._analyzing:
		await analyzer.completed
	check(desktop._status.text.contains("部分分析成功") and desktop._status.text.contains("模型缓存路径指向文件")
		and desktop._status.text.contains("内置速度算法分析速度曲线成功") and desktop._status.text.contains("卷帘显示此前的「起音」"),
		"A failed model job gives its actual reason while the independent speed job completes")
	desktop._message.hide()
	var saved_decoder: String = desktop.preferences.ffmpeg_path
	desktop.preferences.ffmpeg_path = "user://missing-ffmpeg.exe"
	desktop.sidebar.set_guide_mode(ReferenceMode.TRADITIONAL)
	desktop._request_analysis(true)
	if desktop._analyzing:
		await analyzer.completed
	check(desktop._status.text.contains("分析失败") and desktop._status.text.contains("无法启动 FFmpeg")
		and desktop._status.text.contains("参考模式已恢复") and desktop.grid.reference_mode == ReferenceMode.TRADITIONAL,
		"An unavailable decoder is reported and the import restores the previous reference mode")
	check(desktop._message.visible and desktop._message.dialog_text.contains("无法启动 FFmpeg"), "The failure dialog reports its cause")
	desktop._message.hide()
	desktop.preferences.ffmpeg_path = saved_decoder
	panel._spectrum.pressed.emit()
	check(desktop._analyzing, "The inspector can also start a spectrogram job")
	if desktop._analyzing:
		await analyzer.completed
	check(desktop._frequency.visible and desktop._spectrum_image.texture != null, "The spectrogram is shown in the frequency panel")
	check(desktop._frequency_feedback.text.contains("分析频谱成功"), "The spectrogram reports completion in its own results view")
	desktop._message.hide()
	panel._select(panel._preset, "melody")
	panel._apply_preset(panel._preset.selected)
	check(desktop.import_audio(manual), "Import a song with the melody-only preset selected")
	check(desktop._ask.dialog_text.contains("主旋律") and not desktop._ask.dialog_text.contains("速度曲线"),
		"Import confirmation describes only the selected analysis tasks")
	desktop._ask.hide()
	desktop._ask.confirmed.emit()
	if desktop._analyzing:
		await analyzer.completed
	check(desktop._frequency.visible and desktop._frequency_tabs.current_tab == 1
		and desktop._frequency_feedback.text.contains("使用Essentia分析主旋律成功")
		and chart.rhythm_analysis.get("tempo_curve", []).is_empty(), "Import analyzes and displays only the selected melody task")
	print("ANALYSIS_ENGINES_SMOKE failures=", failures)
	quit(1 if failures else 0)
