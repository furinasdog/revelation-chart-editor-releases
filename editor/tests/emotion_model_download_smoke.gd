extends SceneTree

const Download := preload("res://desktop/emotion_model_download.gd")
const Analysis := preload("res://desktop/analysis.gd")

var _result: Array = []
var _stages: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desk: Node = current_scene.desktop
	desk._onboarding._chooser.hide()
	desk._results_tabs.current_tab = 3
	desk.preferences.open("分析工具")
	var toggle: CheckBox = desk.preferences._emotion_auto_toggle
	if not toggle.disabled or toggle.button_pressed or "emotions" in desk._requested_audio_analysis().tasks:
		push_error("Automatic emotion analysis must be off before installing the models.")
		quit(1)
		return
	desk.preferences._dialog.hide()
	var downloader: Node = desk._emotion_download
	downloader.progress.connect(func(message: String, _downloaded: int, _total: int, _cancel: bool): _stages.append(message))
	downloader.completed.connect(func(path: String, message: String): _result = [path, message])
	if not desk._emotion._download.visible or desk._has_emotion_models():
		push_error("Use a fresh profile with the Download Model button available.")
		quit(1)
		return
	downloader.start(PackedStringArray([args[0], args[1]]))
	if not desk._emotion_download_dialog.visible or not desk._emotion_download_dialog.exclusive:
		push_error("Model download must immediately show a modal progress window.")
		quit(1)
		return
	var deadline := Time.get_ticks_msec() + 45000
	while _result.is_empty() and Time.get_ticks_msec() < deadline:
		await process_frame
	if (_result.is_empty() or _stages.is_empty() or not _stages[0].begins_with("GitHub 直连")
			or not _stages.any(func(stage: String): return stage.contains("正在连接 gh-proxy.org"))):
		push_error("Direct failure must lead to the fallback attempt.")
		quit(1)
		return
	if args[2] == "ok":
		var path: String = _result[0]
		if (not Analysis.emotion_models_ready(path) or not Download._is_verified_install(path)
				or path != desk.preferences.emotion_models or desk._emotion._download.visible):
			push_error("The verified archive must be installed and selected automatically. " + str(_result[1]))
			quit(1)
			return
		if desk._emotion_download_dialog.visible or toggle.disabled or not toggle.button_pressed:
			push_error("A completed install must close the progress dialog and enable the setting.")
			quit(1)
			return
		toggle.button_pressed = false
		desk.preferences.load_settings()
		if "emotions" in desk._requested_audio_analysis().tasks or desk.preferences.analyze_emotion_automatically:
			push_error("Turning off the preference must remove emotion from regular analysis and persist.")
			quit(1)
			return
		_result.clear()
		downloader.start(PackedStringArray([args[0]]))
		if _result.is_empty() or _result[0] != path or downloader.busy:
			push_error("An existing verified install must be reused.")
			quit(1)
			return
	elif not str(_result[0]).is_empty() or desk._has_emotion_models() or not str(_result[1]).contains("SHA-256"):
		push_error("A same-length archive with the wrong digest must be rejected. " + str(_result[1]))
		quit(1)
		return
	if not DirAccess.get_files_at(Download.MODEL_ROOT).is_empty():
		push_error("Download temporaries must be removed.")
		quit(1)
		return
	print("MODEL_DOWNLOAD_SMOKE ", args[2], " verified")
	quit()
