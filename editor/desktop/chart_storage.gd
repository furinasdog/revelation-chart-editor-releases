extends RefCounted

const Archive := preload("res://main/chart_archive.gd")
const ASSET_EXTENSIONS := ["mp3", "ogg", "wav", "png", "jpg", "jpeg", "webp", "lrc"]

static func is_working_folder(path: String) -> bool:
	if path.is_empty():
		return true
	var target := _absolute(path)
	for prefix: String in ["user://charts", "user://zip_imports"]:
		var working := _absolute(prefix)
		if OS.get_name() == "Windows":
			working = working.to_lower()
			target = target.to_lower()
		if target == working or target.begins_with(working + "/"):
			return true
	return false

static func save_copy(chart: Node, selected: String) -> Dictionary:
	var parent := _absolute(selected)
	if selected.is_empty() or not DirAccess.dir_exists_absolute(parent) or is_working_folder(parent):
		return {"error": "请选择一个可写入的谱面保存目录。"}
	var document: Dictionary = chart.to_export_dict().duplicate(true)
	var files := {}
	var replacements := {}
	if chart.has_root_dir and is_working_folder(chart.get_root_dir()):
		_add_working_assets(chart.get_root_dir(), files)
	for reference: Dictionary in _references(document):
		var original: String = reference.owner[reference.key]
		if original.is_empty():
			continue
		var relative := original.replace("\\", "/")
		var resolved: String = chart.resolve_full_path(original)
		if resolved.is_empty() or not FileAccess.file_exists(resolved):
			return {"error": "找不到谱面引用的素材「%s」，请检查素材路径。" % original.get_file()}
		if relative.is_absolute_path() or not Archive.relative_name(relative):
			var name := relative.get_file().validate_filename().left(120)
			relative = "素材/%s-%s" % [original.sha256_text().left(12), name]
		files[relative] = _absolute(resolved)
		if relative != original:
			replacements[original.replace("\\", "/")] = relative
			reference.owner[reference.key] = relative
	var project := _destination(parent, str(chart.chart_info.get("chartName", "")))
	if project.is_empty():
		return {"error": "无法创建谱面目录，请检查写入权限。"}
	var folder: String = project.path
	var created_files: Array[String] = []
	var created_dirs: Array[String] = []
	if project.created:
		created_dirs.append(folder)
	for relative: String in files:
		var target := folder.path_join(relative)
		if not _make_subdirectories(folder, relative, created_dirs) or FileAccess.file_exists(target) or DirAccess.dir_exists_absolute(target):
			return _rollback(created_files, created_dirs, "无法写入素材「%s」。" % relative.get_file())
		if DirAccess.copy_absolute(files[relative], target) != OK:
			DirAccess.remove_absolute(target)
			return _rollback(created_files, created_dirs, "无法复制素材「%s」。" % relative.get_file())
		created_files.append(target)
	var json_path := folder.path_join("chart.json")
	if FileAccess.file_exists(json_path) or DirAccess.dir_exists_absolute(json_path):
		return _rollback(created_files, created_dirs, "保存目录已存在谱面文件，请重新选择目录。")
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if not file:
		return _rollback(created_files, created_dirs, "无法写入谱面文件。")
	var written := file.store_string(JSON.stringify(document, "  ", false))
	file.close()
	if not written:
		created_files.append(json_path)
		return _rollback(created_files, created_dirs, "谱面文件写入未完成，请检查磁盘空间。")
	return {"path": json_path, "replacements": replacements}

static func move_live_references(chart: Node, paths: Dictionary) -> void:
	if paths.is_empty():
		return
	for field: String in ["audio_path", "preview_bg_image_path", "preview_mask_image_path"]:
		var original: String = chart.get(field)
		chart.set(field, paths.get(original.replace("\\", "/"), original))
	for event: Variant in chart.events.values():
		event.image_path = paths.get(event.image_path.replace("\\", "/"), event.image_path)
	for section: Variant in [chart.anim_rect_slots, chart.bg_anim_key_slots, chart.stored_animation_rect_data,
			chart.preset_bg_anim_groups, chart._passthrough_items]:
		var fields: Array[Dictionary] = []
		_collect_image_fields(section, fields)
		for reference: Dictionary in fields:
			var original: String = reference.owner[reference.key]
			reference.owner[reference.key] = paths.get(original.replace("\\", "/"), original)

static func _references(document: Dictionary) -> Array[Dictionary]:
	var refs: Array[Dictionary] = []
	for key: String in ["music", "bgPath", "maskPath"]:
		if document.basic.get(key) is String:
			refs.append({"owner": document.basic, "key": key})
	for key: String in ["data", "anim_rect_slots", "bgAnimKeySlots", "animationRectData", "defaultBackgroundSetting"]:
		_collect_image_fields(document.get(key), refs)
	return refs

static func _collect_image_fields(value: Variant, refs: Array[Dictionary]) -> void:
	if value is Array:
		for item: Variant in value:
			_collect_image_fields(item, refs)
	elif value is Dictionary:
		if value.get("imagePath") is String:
			refs.append({"owner": value, "key": "imagePath"})
		if value.get("image") is Dictionary and value.image.get("path") is String:
			refs.append({"owner": value.image, "key": "path"})
		for item: Variant in value.values():
			if item is Array or item is Dictionary:
				_collect_image_fields(item, refs)

static func _add_working_assets(root: String, files: Dictionary) -> void:
	for folder: String in ["", "otherImage", "素材"]:
		var dir := DirAccess.open(root if folder.is_empty() else root.path_join(folder))
		if not dir:
			continue
		for name: String in dir.get_files():
			var relative := name if folder.is_empty() else folder.path_join(name)
			if name.get_extension().to_lower() in ASSET_EXTENSIONS and Archive.relative_name(relative):
				files[relative] = _absolute(root.path_join(relative))

static func _destination(parent: String, title: String) -> Dictionary:
	var dir := DirAccess.open(parent)
	if not dir:
		return {}
	dir.include_hidden = true
	if dir.get_files().is_empty() and dir.get_directories().is_empty():
		return {"path": parent, "created": false}
	var name := title.strip_edges().validate_filename().left(100).strip_edges().trim_suffix(".")
	if not Archive.relative_name(name):
		name = "谱面"
	var child := parent.path_join(name)
	if DirAccess.dir_exists_absolute(child) or FileAccess.file_exists(child):
		child = "%s-%d" % [child, Time.get_ticks_usec()]
	return {"path": child, "created": true} if DirAccess.make_dir_absolute(child) == OK else {}

static func _make_subdirectories(root: String, file: String, created: Array[String]) -> bool:
	var folder := root
	for part: String in file.get_base_dir().split("/", false):
		folder = folder.path_join(part)
		if created.has(folder):
			continue
		if DirAccess.make_dir_absolute(folder) != OK:
			return false
		created.append(folder)
	return true

static func _rollback(files: Array[String], dirs: Array[String], message: String) -> Dictionary:
	for path: String in files:
		DirAccess.remove_absolute(path)
	dirs.reverse()
	for path: String in dirs:
		DirAccess.remove_absolute(path)
	return {"error": message}

static func _absolute(path: String) -> String:
	return ProjectSettings.globalize_path(path.replace("\\", "/")).simplify_path()
