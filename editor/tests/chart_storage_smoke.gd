extends SceneTree

const Storage := preload("res://desktop/chart_storage.gd")

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	if not ok:
		push_error(description)
		failures += 1

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 or change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desktop: Node = current_scene.desktop
	var chart: Node = desktop.chart
	var sidebar: Node = desktop.sidebar
	var scratch: String = args[2]
	var first := scratch.path_join("first")
	var second := scratch.path_join("existing")
	var empty := scratch.path_join("empty")
	var save_as := scratch.path_join("copy")
	for dir: String in [first, second, empty, save_as]:
		if DirAccess.make_dir_recursive_absolute(dir) != OK:
			quit(2)
			return

	for dialog: FileDialog in [desktop._file, desktop._lyrics_file, desktop._image_file, desktop._chart_file,
			desktop._save_folder, sidebar.get_node("ImportExportDialog")]:
		check(dialog.use_native_dialog and dialog.access == FileDialog.ACCESS_FILESYSTEM, "Path selectors request native filesystem dialogs")
	check(desktop._save_folder.file_mode == FileDialog.FILE_MODE_OPEN_DIR, "Saving chooses a folder")

	desktop._clear_chart()
	check(desktop.import_audio(args[0], false, false), "Import an audio fixture into an unsaved chart")
	var temp_root: String = chart.get_root_dir()
	check(Storage.is_working_folder(temp_root), "A new chart starts in temporary storage")
	var id: int = chart.add_note_at_times(0, 250, 650, 0, 0, Vector2(960, 540))
	var art := ProjectSettings.globalize_path("user://external-art.png")
	check(Image.create_empty(16, 16, false, Image.FORMAT_RGB8).save_png(art) == OK, "Create an external image fixture")
	var event: int = chart.add_event(1, 1000, 1000, 0)
	chart.update_event_image_path(event, art)

	sidebar._save_to_current_file(true)
	var session := ConfigFile.new()
	check(session.load(sidebar.SESSION_CFG_PATH) == OK and session.get_value("session", "root_dir", "") == temp_root,
		"Autosave records the temporary project for recovery")
	sidebar._on_root_dir_selected(empty)
	desktop._message.hide()
	check(chart.get_root_dir() == temp_root, "Opening an empty folder does not change the project root")

	desktop._save_chart()
	check(desktop._save_folder_generation == desktop._document_generation, "First explicit save asks for a folder even after autosaving")
	desktop._save_folder.hide()
	desktop._save_folder.canceled.emit()
	check(chart.get_root_dir() == temp_root and desktop._save_folder_generation == -1, "Cancelling leaves the project where it was")

	desktop._save_chart()
	desktop._save_folder.hide()
	desktop._save_folder.dir_selected.emit(first)
	var path := first.path_join("chart.json")
	check(chart.get_root_dir() == first and FileAccess.file_exists(path), "The selected empty directory becomes the project location")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		quit(1)
		return
	for field: String in ["music", "bgPath", "maskPath"]:
		check(FileAccess.file_exists(first.path_join(data.basic[field])), "Saved project contains its " + field)
	var image: String = chart.events[event].image_path
	check(image.begins_with("素材/") and FileAccess.file_exists(first.path_join(image)), "External event art is copied and the reference is made portable")
	check(session.load(sidebar.SESSION_CFG_PATH) == OK and session.get_value("session", "import_path", "") == path,
		"Recovery points at the saved chart")
	chart.update_note_position(id, Vector2(800, 540))
	desktop._save_chart()
	check(desktop._save_folder_generation == -1, "Saving an existing project does not show the picker")
	sidebar._on_root_dir_selected(first)
	check(chart.notes.size() == 1 and chart.notes.values()[0].position == Vector2(800, 540),
		"Opening the saved directory restores the last edit")
	check(chart.events.size() == 1 and not chart.resolve_file_bytes(chart.events.values()[0].image_path).is_empty(),
		"Reopening also restores the copied event art")

	desktop._choose_chart_save_folder()
	desktop._save_folder.hide()
	desktop._save_folder.dir_selected.emit(save_as)
	check(chart.get_root_dir() == save_as and FileAccess.file_exists(save_as.path_join("chart.json")),
		"Save As moves subsequent edits to the new location")
	check(FileAccess.file_exists(path), "Save As keeps the previous copy")

	check(desktop._open_chart_file(args[1]) and Storage.is_working_folder(chart.get_root_dir()), "ZIP input is edited in temporary storage")
	desktop._save_chart()
	check(desktop._save_folder_generation == desktop._document_generation, "First save of a ZIP import also opens the folder picker")
	var sentinel := FileAccess.open(second.path_join("keep.txt"), FileAccess.WRITE)
	sentinel.store_string("existing data")
	sentinel.close()
	desktop._save_folder.hide()
	desktop._save_folder.dir_selected.emit(second)
	var copy: String = chart.get_root_dir()
	check(copy.get_base_dir() == second and FileAccess.file_exists(copy.path_join("chart.json")), "A nonempty folder receives a new project subfolder")
	check(FileAccess.get_file_as_string(second.path_join("keep.txt")) == "existing data", "Existing files are preserved")
	var exported := scratch.path_join("playable.zip")
	sidebar._on_file_selected_for_zip_export(exported)
	var package := ZIPReader.new()
	if package.open(exported) == OK:
		check(package.get_files().size() >= 4, "ZIP export still contains the chart and core assets")
		package.close()
	else:
		check(false, "Project can still export a playable ZIP")
	var audio: String = chart.audio_path
	chart.audio_path = "missing.wav"
	check(not desktop._save_chart_in_folder(empty) and chart.get_root_dir() == copy and DirAccess.get_files_at(empty).is_empty(),
		"Save failure leaves the current project and selected target intact")
	chart.audio_path = audio
	quit(0 if failures == 0 else 1)
