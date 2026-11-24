extends SceneTree

var _updates := 0
var _proper_dialog := false

func _initialize() -> void:
	_run.call_deferred()

func _wait(workspace: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 45000
	while workspace._analyzing and Time.get_ticks_msec() < deadline:
		await process_frame
	return not workspace._analyzing

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desk: Node = current_scene.desktop
	desk._onboarding._chooser.hide()
	if not desk.import_audio(args[0], false, false):
		quit(2)
		return
	desk.analysis.madmom_download_progress.connect(func(model: String, _source: String, index: int, total: int, _bytes: int, size: int):
		_updates += 1
		var dialog: Window = desk._madmom_download_dialog
		_proper_dialog = _proper_dialog or (dialog and dialog.visible and dialog.exclusive and dialog.get_parent() == desk._analysis_dialog
			and desk._madmom_download_label.text.contains(model) and index == 1 and total == 1
			and desk._madmom_download_file.max_value == size and desk._madmom_download_total.max_value == 1000))
	var options := {"engine": "madmom", "tempo_engine": "native", "tasks": ["onsets"],
		"model": "default", "madmom_model_cache": "user://download-smoke"}
	if not desk._start_analysis(options) or not await _wait(desk) or not _proper_dialog:
		push_error("A cold madmom download must report a file and aggregate progress in a modal.")
		quit(1)
		return
	if desk._madmom_download_dialog.visible or desk.chart.rhythm_analysis.get("onsets", []).is_empty():
		push_error("The verified download must close its modal and allow onset detection to finish.")
		quit(1)
		return
	desk._message.hide()
	_updates = 0
	if not desk._start_analysis(options) or not await _wait(desk) or _updates != 0:
		push_error("Reading the same verified cache must not show a download.")
		quit(1)
		return
	print("MADMOM_DOWNLOAD_SMOKE verified")
	quit()
