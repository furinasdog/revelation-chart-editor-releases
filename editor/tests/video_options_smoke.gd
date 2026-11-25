extends SceneTree

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desktop: Node = current_scene.desktop
	desktop._onboarding.close_guide()
	if desktop._release_dialog: desktop._release_dialog.hide()
	check(desktop.import_audio(args[0], false), "Audio import")
	desktop.chart.add_note_at_times(0, 0, 300, 0, 0, Vector2(640, 360))
	desktop.chart.add_note_at_times(1, 400, 700, 0, 1, Vector2(1400, 640))
	desktop._choose_video_path()
	var form: Window = desktop._video_settings
	check(form.visible and form._picker.use_native_dialog, "Render form and native picker")
	form._folder.text = args[1]
	form._filename.text = "CON.mp4"
	form._confirm_settings()
	check(form._error.visible and form.visible, "Invalid name keeps form open")
	var existing := str(args[1]).path_join("existing.mp4")
	var original := FileAccess.open(existing, FileAccess.WRITE)
	original.store_string("keep")
	original.close()
	form._filename.text = "existing.mp4"
	form._confirm_settings()
	check(form._overwrite.visible, "Existing output requires confirmation")
	form._overwrite.hide()
	form.hide()
	var video: Node = desktop._video
	var ffmpeg: String = desktop.analysis._ffmpeg("")
	for mode in ["serial", "parallel", "nvenc"]:
		if mode == "nvenc" and "nvenc" not in args: continue
		var target := str(args[1]).path_join(mode + ".mp4")
		var settings := {"size": Vector2i(1280,720), "fps": 30, "parallel": mode != "serial", "nvenc": mode == "nvenc"}
		video.render.call_deferred(desktop.chart, ffmpeg, target, 100, 1060, settings)
		var error: String = await video.finished
		check(error.is_empty() and FileAccess.file_exists(target), mode + ": " + error)
	var cancel_after_frame := func(_done: int, _total: int): video.cancel()
	video.progress.connect(cancel_after_frame, CONNECT_ONE_SHOT)
	video.render.call_deferred(desktop.chart, ffmpeg, existing, 0, 1300, {"parallel": true})
	var canceled: String = await video.finished
	check(canceled.contains("取消") and FileAccess.get_file_as_string(existing) == "keep", "Cancel preserves old output")
	print("VIDEO_OPTIONS_SMOKE failures=", failures)
	quit(1 if failures else 0)
