extends SceneTree

const Models := preload("res://desktop/managed_models.gd")

var notices := 0

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
	desk.preferences.emotion_models = "user://missing-models"
	desk.models_refreshed.connect(func(): notices += 1)
	desk._refresh_analysis()
	desk._emotion._hub.pressed.emit()
	if not desk._model_help.visible or desk._help_model != "music2emo" or desk._has_emotion_models():
		push_error("Missing models must lead to the Hub guide.")
		quit(1)
		return
	desk.preferences.emotion_models = args[0]
	desk._model_help.get_ok_button().pressed.emit()
	await process_frame
	if notices != 1 or not desk._has_emotion_models() or desk._emotion._hub.visible or desk._model_help.visible:
		push_error("Refreshing a verified Music2Emo install must update the results panel.")
		quit(1)
		return
	if desk._requested_audio_analysis().tasks != ["beats"]:
		push_error("Model management must preserve the selected capture.")
		quit(1)
		return
	OS.set_environment("AUTOREVELATION_HTDEMUCS_MODELS", "user://missing-models")
	desk._show_model_help("htdemucs")
	if not Models.htdemucs_path().is_empty():
		push_error("HTDemucs must require the pinned model.")
		quit(1)
		return
	OS.set_environment("AUTOREVELATION_HTDEMUCS_MODELS", args[1])
	desk._model_help.get_ok_button().pressed.emit()
	await process_frame
	if Models.htdemucs_path() != args[1].replace("\\", "/").path_join("htdemucs_fp16weights.onnx") or notices != 2 or desk._model_help.visible:
		push_error("An installed HTDemucs model must be available immediately after refreshing.")
		quit(1)
		return
	print("MODEL_MANAGER_SMOKE verified")
	quit()
