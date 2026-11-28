extends Window

const Prompts := preload("res://desktop/agent_prompts.gd")
const Layout := preload("res://desktop/dialog_layout.gd")
const FilePicker := preload("res://desktop/desktop_file_dialog.gd")

var _draft := {}
var _baseline := ""
var _document := ""
var _section := ""
var _documents: OptionButton
var _sections: ItemList
var _editor: TextEdit
var _status: Label
var _save: Button

func _ready() -> void:
	title = "Agent 提示词编辑器"
	transient = true
	exclusive = true
	min_size = Vector2i(440, 290)
	close_requested.connect(hide)
	var content := VBoxContainer.new()
	add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_top = 12
	content.offset_right = -12
	content.offset_bottom = -12
	content.add_theme_constant_override("separation", 8)

	var body := HSplitContainer.new()
	body.split_offset = 28
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = 138
	body.add_child(navigation)
	_documents = OptionButton.new()
	_documents.fit_to_longest_item = false
	_documents.tooltip_text = "提示词分类"
	navigation.add_child(_documents)
	for document: String in Prompts.TITLES:
		_documents.add_item(Prompts.TITLES[document])
		_documents.set_item_metadata(_documents.item_count - 1, document)
	_documents.item_selected.connect(_open_document)
	_sections = ItemList.new()
	_sections.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sections.item_selected.connect(_open_section)
	navigation.add_child(_sections)
	_editor = TextEdit.new()
	_editor.placeholder_text = "提示词正文（Markdown）"
	_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.text_changed.connect(_text_changed)
	body.add_child(_editor)

	var actions := HFlowContainer.new()
	content.add_child(actions)
	_save = _button(actions, "保存全部", _save_changes)
	_button(actions, "恢复本节默认", _restore_section)
	_button(actions, "重新读取", _reload)
	_button(actions, "导入提示词包…", _open_pack_picker.bind(false))
	_button(actions, "导出提示词包…", _open_pack_picker.bind(true))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	_load_saved()

func open() -> void:
	if not _has_changes():
		_load_saved()
	Layout.present(self, Vector2i(850, 570))

func _button(row: Container, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	row.add_child(button)
	return button

func _has_changes() -> bool:
	return Prompts.revision(_draft) != _baseline

func _load_saved() -> void:
	_draft = Prompts.snapshot()
	_baseline = Prompts.revision(_draft)
	var index := maxi(_documents.selected, 0)
	_documents.select(index)
	_open_document(index)
	_set_status("修改会从下一次 Agent 请求开始使用。")

func _open_document(index: int) -> void:
	var previous := _section
	_document = _documents.get_item_metadata(index)
	_sections.clear()
	for id: String in _draft[_document]:
		_sections.add_item(id)
	var selected: int = maxi(_draft[_document].keys().find(previous), 0)
	_sections.select(selected)
	_open_section(selected)

func _open_section(index: int) -> void:
	_section = _sections.get_item_text(index)
	_editor.text = _draft[_document][_section]
	_editor.clear_undo_history()

func _text_changed() -> void:
	_draft[_document][_section] = _editor.text
	_set_status("有未保存的修改。" if _has_changes() else "已保存。")

func _set_status(message: String) -> void:
	_status.text = message
	_save.disabled = not _has_changes()

func _save_changes() -> void:
	var error := Prompts.save(_draft, _baseline)
	if error.is_empty():
		_baseline = Prompts.revision(_draft)
	_set_status("已保存提示词。" if error.is_empty() else error)

func _restore_section() -> void:
	_editor.text = Prompts.defaults()[_document][_section]
	_text_changed()

func _reload() -> void:
	if not _has_changes():
		_load_saved()
		return
	var confirm := ConfirmationDialog.new()
	confirm.title = "重新读取提示词"
	confirm.dialog_text = "丢弃未保存的修改并读取当前已保存的提示词？"
	confirm.ok_button_text = "重新读取"
	confirm.confirmed.connect(_load_saved)
	confirm.confirmed.connect(confirm.queue_free)
	confirm.canceled.connect(confirm.queue_free)
	add_child(confirm)
	Layout.present(confirm, Vector2i(430, 140))

func _open_pack_picker(exporting: bool) -> void:
	var picker := FilePicker.new()
	picker.title = "导出提示词包" if exporting else "导入提示词包"
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
	picker.filters = PackedStringArray(["*.json ; Revelation 提示词包"])
	if exporting:
		picker.current_file = "Revelation-Agent-Prompts.json"
	picker.file_selected.connect(func(path: String):
		if exporting:
			var error := Prompts.export_pack(path, _draft)
			_set_status("已导出当前提示词。" if error.is_empty() else error)
			if error.is_empty():
				FilePicker.reveal_export(path)
		else:
			var pack := Prompts.import_pack(path)
			if pack.has("error"):
				_set_status(pack.error)
			else:
				_confirm_import(pack.documents)
		picker.queue_free())
	picker.canceled.connect(picker.queue_free)
	add_child(picker)
	picker.open_picker()

func _confirm_import(documents: Dictionary) -> void:
	if not _has_changes():
		_stage_import(documents)
		return
	var confirm := ConfirmationDialog.new()
	confirm.title = "导入提示词包"
	confirm.dialog_text = "用提示词包替换编辑器中尚未保存的内容？"
	confirm.ok_button_text = "载入提示词包"
	confirm.confirmed.connect(_stage_import.bind(documents))
	confirm.confirmed.connect(confirm.queue_free)
	confirm.canceled.connect(confirm.queue_free)
	add_child(confirm)
	Layout.present(confirm, Vector2i(430, 140))

func _stage_import(documents: Dictionary) -> void:
	_draft = documents
	_open_document(_documents.selected)
	_set_status("已载入提示词包。保存全部后生效。")
