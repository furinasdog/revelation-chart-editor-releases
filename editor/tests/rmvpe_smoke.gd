extends SceneTree

const Analysis := preload("res://desktop/analysis.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	var analyzer := Analysis.new()
	root.add_child(analyzer)
	var options := {"engine": "rmvpe", "tasks": ["vocal_pitch"]}
	OS.unset_environment("REVELATION_RMVPE_MODEL")
	var inferred := analyzer.analyze_file(args[0], "", options)
	if inferred.get("vocal_pitch", []).is_empty():
		push_error("Expected a pitch contour from the bundled model: " + str(inferred.get("error", "empty")))
		quit(1)
		return
	OS.set_environment("REVELATION_RMVPE_MODEL", ProjectSettings.globalize_path("user://absent-model.onnx"))
	if not analyzer.analyze_file(args[0], "", options).has("error"):
		push_error("The explicitly configured model must take precedence")
		quit(1)
		return
	print("RMVPE_SMOKE points=", inferred.vocal_pitch.size())
	quit()
