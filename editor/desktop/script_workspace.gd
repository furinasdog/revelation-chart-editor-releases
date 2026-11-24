extends Node

const DialogLayout := preload("res://desktop/dialog_layout.gd")

const Agent := preload("res://desktop/chart_agent.gd")
const Plan := preload("res://desktop/auto_chart_plan.gd")
const AnimationDraft := preload("res://desktop/agent_animation.gd")
const Automatic := preload("res://desktop/automatic_chart.gd")
const References := preload("res://desktop/reference_library.gd")

var _workspace: Node
var _approval: ConfirmationDialog
var _active := false
var _path := ""

func setup(workspace: Node) -> void:
	_workspace = workspace

func open_reference_import() -> void:
	_open_picker("导入参考谱", PackedStringArray(["*.zip, *.json ; Revelation 谱面"]), _import_reference)

func open_script() -> void:
	_open_picker("选择本机制谱脚本", PackedStringArray(["*.rpy ; Revelation 脚本"]), _confirm_script)

func _open_picker(title: String, filters: PackedStringArray, selected: Callable) -> void:
	var picker = _workspace._create_path_dialog(title, FileDialog.FILE_MODE_OPEN_FILE, filters)
	picker.theme = _workspace._ui_theme
	picker.canceled.connect(picker.queue_free)
	picker.file_selected.connect(func(path: String):
		picker.queue_free()
		selected.call(path))
	_workspace.host.add_child(picker)
	picker.open_picker()

func _import_reference(path: String) -> void:
	if path.get_extension().to_lower() != "zip":
		_save_reference(path, false, false)
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "导入参考谱"
	dialog.dialog_text = "默认只添加谱面数据。如果你有相应授权，可以另外保留下列素材。"
	dialog.dialog_autowrap = true
	dialog.ok_button_text = "导入"
	dialog.exclusive = true
	dialog.theme = _workspace._ui_theme
	var options := VBoxContainer.new()
	var images := CheckBox.new()
	images.text = "允许查阅曲绘和渲染画面"
	var audio := CheckBox.new()
	audio.text = "允许在本机读取参考音频"
	options.add_child(images)
	options.add_child(audio)
	dialog.add_child(options)
	dialog.confirmed.connect(func():
		_save_reference(path, images.button_pressed, audio.button_pressed)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	_workspace.host.add_child(dialog)
	DialogLayout.present(dialog, Vector2i(520, 230))

func _save_reference(path: String, images: bool, audio: bool) -> void:
	var result := References.import_local(path, images, audio)
	_workspace._notify(str(result.error) if result.has("error") else "参考谱「%s」已加入本机参考谱库。" % result.title)

func _confirm_script(path: String) -> void:
	if _active or _workspace.copilot.busy or _workspace._video.busy or _workspace._analyzing:
		_workspace._notify("请先完成当前任务。")
		return
	_path = path
	if not is_instance_valid(_approval):
		_approval = ConfirmationDialog.new()
		_approval.title = "运行本机 .rpy"
		_approval.ok_button_text = "运行脚本"
		_approval.dialog_autowrap = true
		_approval.exclusive = true
		_approval.confirmed.connect(_run_selected)
		_workspace.host.add_child(_approval)
	_approval.theme = _workspace._ui_theme
	_approval.dialog_text = "请确认你信任这个脚本。它将以当前用户权限运行。\n\n" + path
	DialogLayout.present(_approval, Vector2i(560, 180))

func _run_selected() -> void:
	if _active:
		return
	_active = true
	var result := await run_file(_path)
	_active = false
	var message := str(result.get("error", "脚本完成。已应用 %d 项修改。" % result.get("operation_count", 0)))
	if result.get("result") != null:
		message += "\n" + JSON.stringify(result.result).left(700)
	if not str(result.get("log", "")).is_empty():
		message += "\n" + str(result.log).left(700)
	_workspace._notify(message)

func run_file(path: String) -> Dictionary:
	if path.get_extension().to_lower() != "rpy" or not FileAccess.file_exists(path):
		return {"error": "请选择有效的 .rpy 脚本。"}
	var chart: Node = _workspace.chart
	var generation: int = _workspace._document_generation
	var original: Dictionary = _workspace.copilot._signature()
	var plan := Plan.new(chart, str(chart.chart_info.get("difficulty", "HD")).to_upper().left(2))
	var data := Automatic.music_for_agent(chart, _workspace._cached_chart_music(), plan.duration_ms)
	var pictures: Array[Dictionary] = []
	for path_in_chart: String in _workspace.automatic._project_artwork(_workspace.automatic._find_cover()).slice(0, 16):
		var picture: Dictionary = _workspace.automatic._prepare_cover(path_in_chart)
		if not picture.is_empty():
			pictures.append(picture)
	var visuals := AnimationDraft.new(chart, plan.duration_ms, pictures)
	var agent := Agent.new()
	add_child(agent)
	agent.open_tool_session(plan, data, [], visuals, {})
	var result := await agent.run_local_script(path)
	if not result.has("error") and result.get("operation_count", 0) > 0:
		if generation != _workspace._document_generation or original != _workspace.copilot._signature():
			result = {"error": "脚本执行期间工程已有改动，草稿已丢弃。"}
		elif visuals.has_assets() and visuals.save_assets(_workspace._get_or_create_root()) != OK:
			result = {"error": "无法保存脚本生成的图像素材。"}
		else:
			chart.apply_automatic_notes(plan.notes, plan.edited, visuals.layers.values(), visuals.mask_cues.values(), {}, agent.draft_changes())
	agent.queue_free()
	return result
