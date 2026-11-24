extends FileDialog

func _init() -> void:
	access = FileDialog.ACCESS_FILESYSTEM
	use_native_dialog = true
	mode_overrides_title = false
	transient = true

func open_picker() -> void:
	if DisplayServer.get_name() == "Windows" and not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		OS.alert("当前运行环境无法打开 Windows 文件选择器。", title)
		canceled.emit()
		return
	popup_centered_ratio(0.7)

static func reveal_export(path: String) -> void:
	if DisplayServer.get_name() == "Windows":
		var target := ProjectSettings.globalize_path(path)
		if OS.shell_show_in_file_manager(target) != OK:
			OS.shell_open(target.get_base_dir())
