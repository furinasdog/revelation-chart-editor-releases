extends SceneTree

var failures := 0
var render_error := ""
var rendering := true

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desktop: Node = current_scene.desktop
	if desktop._onboarding._chooser:
		desktop._onboarding._chooser.hide()
	if not desktop.import_audio(args[0], false):
		quit(3)
		return
	var chart: Node = desktop.chart
	chart.audio_delay_ms = 150
	root.get_node("Global").hit_sound_volume = 0.5
	chart.add_note_at_times(0, 300, 550, 0, 0, Vector2(480, 360))
	chart.add_note_at_times(1, 720, 1000, 0, 1, Vector2(960, 540))
	chart.add_note_at_times(2, 1400, 1900, 1600, 2, Vector2(1440, 720), Vector2(1480, 720))
	var preview: Control = desktop.preview
	for judgement in [550, 1000, 1600]:
		preview._rt_time_ms = judgement + 65.0
		check(preview._collect_runtime_hits().size() == 1, "A judgement renders its effect at %d ms" % judgement)
	preview._rt_time_ms = 200.0
	check(preview._collect_runtime_hits().is_empty(), "A hit is absent before judgement")
	var ffmpeg: String = desktop.analysis._ffmpeg("")
	desktop._video.finished.connect(func(error: String):
		render_error = error
		rendering = false
	)
	desktop._video.render(chart, ffmpeg, args[1])
	while rendering:
		await process_frame
	check(render_error.is_empty(), "Video export completes: " + render_error)
	if render_error.is_empty():
		for time: float in [0.54, 0.99, 1.59]:
			var peak := _metric(ffmpeg, ["-ss", str(time), "-i", args[1], "-t", "0.09",
				"-vn", "-af", "volumedetect"], "max_volume: (-?[0-9.]+)")
			check(peak > -35.0, "MP4 contains the judgement sound at %.2f seconds" % time)
		var quiet := _metric(ffmpeg, ["-ss", "0.18", "-i", args[1], "-t", "0.22",
			"-vn", "-af", "volumedetect"], "max_volume: (-?[0-9.]+)")
		check(quiet < -70.0, "There is silence before the first judgement")
		for sample: Array in [[0.62, 380, 260], [1.07, 860, 440]]:
			var luma := _metric(ffmpeg, ["-ss", str(sample[0]), "-i", args[1], "-frames:v", "1", "-an", "-vf",
				"crop=200:200:%d:%d,signalstats,metadata=print:key=lavfi.signalstats.YMAX" % [sample[1], sample[2]]],
				"lavfi.signalstats.YMAX=([0-9]+)")
			check(luma > 100.0, "The exported frame displays the effect at %.2f seconds" % sample[0])
	print("VIDEO_FEEDBACK_SMOKE failures=", failures)
	quit(1 if failures else 0)

func _metric(ffmpeg: String, args: PackedStringArray, pattern: String) -> float:
	var output: Array = []
	var command := PackedStringArray(["-hide_banner"])
	command.append_array(args)
	command.append_array(["-f", "null", "-"])
	if OS.execute(ffmpeg, command, output, true) != 0:
		return NAN
	var expression := RegEx.create_from_string(pattern)
	var found := expression.search("\n".join(output))
	return float(found.get_string(1)) if found else NAN
