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
	desk.preferences.analysis_options["madmom_model_cache"] = "user://missing-models"
	desk._analysis_panel.select("onset-cnn")
	desk._analysis_panel._run.pressed.emit()
	if desk._analyzing or not desk._model_help.visible or desk._help_model != "madmom" or DirAccess.dir_exists_absolute("user://missing-models"):
		push_error("A cold madmom capture must open the Hub guide without downloading.")
		quit(1)
		return
	desk.preferences.analysis_options["madmom_model_cache"] = args[1]
	desk._model_help.get_ok_button().pressed.emit()
	await process_frame
	desk._analysis_panel._run.pressed.emit()
	var deadline := Time.get_ticks_msec() + 45000
	while desk._analyzing and Time.get_ticks_msec() < deadline:
		await process_frame
	if desk._analyzing or desk._model_help.visible or desk.chart.rhythm_analysis.get("onsets", []).is_empty():
		push_error("The same editor session must accept a valid offline model after refresh.")
		quit(1)
		return
	desk.preferences.analysis_options["madmom_model_cache"] = "user://missing-models"
	desk._analysis_panel._run.pressed.emit()
	if desk._analyzing or desk._model_help.visible or desk.chart.rhythm_analysis.get("capture_id") != "onset-cnn":
		push_error("Applying a cached capture must work without installed weights.")
		quit(1)
		return
	print("MADMOM_MODEL_MANAGER_SMOKE verified")
	quit()
