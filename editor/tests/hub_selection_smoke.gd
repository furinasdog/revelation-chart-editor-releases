extends SceneTree

func _initialize() -> void:
	var models: Script = load("res://desktop/managed_models.gd")
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	if not models.has_method("hub_candidates"):
		push_error("The editor cannot select its matching development Hub")
		quit(1)
		return
	var expected := args[0].replace("\\", "/").simplify_path()
	OS.unset_environment("AUTOREVELATION_HUB_EXE")
	var source: PackedStringArray = models.call("hub_candidates", true)
	var installed: PackedStringArray = models.call("hub_candidates", false)
	var ok := not source.is_empty() and source[0] == expected and FileAccess.file_exists(expected)
	ok = ok and not installed.has(expected)
	var custom := ProjectSettings.globalize_path("user://override/RevelationHub.exe")
	OS.set_environment("AUTOREVELATION_HUB_EXE", custom)
	var overridden: PackedStringArray = models.call("hub_candidates", true)
	ok = ok and overridden.size() >= 2 and overridden[0] == custom and overridden[1] == expected
	print("HUB_SELECTION_SMOKE ", "passed" if ok else "failed")
	quit(0 if ok else 1)
