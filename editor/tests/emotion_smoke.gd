extends SceneTree

const Agent := preload("res://desktop/chart_agent.gd")
const Automatic := preload("res://desktop/automatic_chart.gd")
const Plan := preload("res://desktop/auto_chart_plan.gd")

var _failures := 0
var _model_progress := false

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		push_error(description)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [2, 3] or change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desk: Node = current_scene.desktop
	desk._onboarding._chooser.hide()
	desk.preferences.emotion_models = args[1]
	desk.preferences.limit_emotion_memory = "--low-memory" in args
	_check(desk.import_audio(args[0], false), "Load the multiple-window WAV fixture")
	desk.analysis.progress.connect(func(_stage: String, _done: int, total: int):
		_model_progress = _model_progress or total == 2)
	desk._request_emotion()
	_check(desk._analysis_dialog.visible and desk._analysis_dialog.exclusive, "Visible analysis blocks other editor controls")
	var deadline := Time.get_ticks_msec() + 90000
	while desk._analyzing and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(not desk._analyzing and not desk._analysis_dialog.visible, "Result replaces the inference modal")
	var chart: Node = desk.chart
	var segments: Array = chart.rhythm_analysis.get("emotions", [])
	_check(_model_progress and desk._results_tabs.current_tab == 3 and segments.size() == 2,
		"Native Music2Emo reports segment progress and populates both result rows")
	if segments.size() == 2:
		_check(segments[0].end_ms == 30000 and segments[1].time_ms == 30000 and segments[1].end_ms > 30000,
			"Emotion segments retain precise audio times")
		chart.set_audio_delay(250)
		var draft := Plan.new(chart)
		var agent := Agent.new()
		root.add_child(agent)
		agent._plan = draft
		agent._music = Automatic.music_for_agent(chart, desk._cached_chart_music(), draft.duration_ms)
		var result := agent._call_tool("get_emotions", {"from_ms": 32000, "to_ms": 33000})
		_check(result.total == 1 and result.items[0].time_ms == 30250 and result.items[0].tags.size() == 3,
			"Agent can query a time inside a segment and receives tags in chart time")
		var cached: Dictionary = await desk._analyze_for_agent({"engine": "music2emo", "tasks": ["emotions"]})
		_check(cached.get("cache_hits", []) == ["emotions"] and not desk._analyzing, "Emotion inference is cached")
	print("EMOTION_SMOKE segments=", segments.size(), " failures=", _failures)
	quit(1 if _failures else 0)
