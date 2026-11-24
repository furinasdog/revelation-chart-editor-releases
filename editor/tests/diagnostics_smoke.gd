extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1

func _run() -> void:
	if change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desktop: Node = current_scene.desktop
	var help: PopupMenu = desktop._menu.get_child(0).get_child(5).get_popup()
	var commands := []
	for index in range(help.item_count):
		commands.append(help.get_item_text(index))
	_check(commands.has("导出错误包…"), "Help includes the error package export")
	var chart: Node = desktop.chart
	chart.add_note_at_times(0, 200, 1000, 0, 0, Vector2(960, 540))
	chart.undo()
	desktop.import_audio("C:/Users/someone/Music/does-not-exist.wav", false)
	var secret := "tok-synthetic-local-test-secret"
	desktop.automatic._settings.key = secret
	var engine_log := FileAccess.open("user://logs/godot-test-diagnostic.log", FileAccess.WRITE)
	engine_log.store_string("Ordinary user content SHOULD_NOT_BE_COLLECTED\n"
		+ "ERROR: Decoder could not open C:/Users/Private/Private Song.wav\n"
		+ "   at: decoder (res://desktop/analysis.gd:42)\n"
		+ "SCRIPT ERROR: Provider refused https://sample.invalid/private?q=1 Authorization: Bearer " + secret + "\n"
		+ "   GDScript backtrace (most recent call first):\n"
		+ "       [0] _decode (res://desktop/analysis.gd:42)\n")
	engine_log.close()
	desktop.copilot._agent.request_failed.emit("http_response", {"http_status": 429, "round": 2})
	var destination := "user://diagnostics-smoke.zip"
	_check(desktop._export_diagnostic_bundle(destination) == OK, "Error package is exported from the desktop action")
	var zip := ZIPReader.new()
	if zip.open(destination) != OK:
		quit(2)
		return
	_check(zip.get_files().size() == 4 and zip.file_exists("environment.json"), "ZIP has the expected four entries")
	var operations := zip.read_file("operations.jsonl").get_string_from_utf8()
	var engine := zip.read_file("engine-errors.log").get_string_from_utf8()
	var environment: Variant = JSON.parse_string(zip.read_file("environment.json").get_string_from_utf8())
	zip.close()
	_check("note.add" in operations and "chart.undo" in operations and "audio.import" in operations
		and "copilot.http_response" in operations and "429" in operations, "Operations expose edits, import failure and HTTP status")
	_check("Decoder could not open" in engine and "res://desktop/analysis.gd:42" in engine, "Errors keep their actionable stack trace")
	for value: String in [secret, "Private Song.wav", "does-not-exist.wav", "SHOULD_NOT_BE_COLLECTED", "sample.invalid"]:
		_check(value not in engine and value not in operations, "Private diagnostic fields stay out of the ZIP")
	_check(environment is Dictionary and environment.has("application_version") and environment.has("godot"), "Error ZIP identifies the running version")
	print("DIAGNOSTICS_SMOKE failures=", failures)
	quit(1 if failures else 0)
