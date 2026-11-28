extends SceneTree

const Prompts := preload("res://desktop/agent_prompts.gd")
const Tools := preload("res://desktop/agent_profile_tools.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1

func _run() -> void:
	if change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desktop: Node = current_scene.desktop
	desktop._open_prompt_editor()
	var editor: Window = desktop._prompt_editor
	await process_frame
	var pack := "user://prompt-editor-smoke.json"
	var shipped := Prompts.defaults()
	var edited := Prompts.snapshot()
	_check(editor.visible and editor._documents.item_count == 5, "Prompt editor exposes all five documents")
	editor._editor.text = "用户编辑的完整提示词\n\n## Markdown 标题"
	editor._text_changed()
	editor._open_document(1)
	editor._open_document(0)
	_check(editor._editor.text.begins_with("用户编辑"), "Switching documents preserves unsaved changes")
	editor._save_changes()
	edited.copilot.protocol = "用户编辑的完整提示词\n\n## Markdown 标题"
	_check(Prompts.snapshot() == edited, "Saved Markdown overrides are used by the runtime")
	_check(Prompts.export_pack(pack, edited).is_empty() and Prompts.import_pack(pack).get("documents") == edited,
		"Export and import round-trip every prompt section")
	editor._stage_import(shipped)
	_check(Prompts.snapshot() == edited and not editor._save.disabled, "Import stages changes before Save")
	editor._save_changes()
	_check(Prompts.snapshot() == shipped, "Saving a restored pack uses the shipped defaults")

	var read := Tools.call_tool("get_agent_prompt", {"document": "shared", "section": "charting"})
	var edit := {"document": "shared", "section": "charting", "revision": read.get("revision"), "text": "保留用户指定的节奏习惯。"}
	_check(Tools.call_tool("set_agent_prompt", edit).get("saved") == true, "A reviewed Agent edit writes the active prompt store")
	_check(Tools.call_tool("set_agent_prompt", edit).has("error"), "An edit cannot overwrite a newer prompt revision")
	var memory := {"key": "节奏偏好", "text": "优先对齐段落重音。"}
	_check(Tools.call_tool("set_agent_memory", memory).get("saved") == true
		and Tools.call_tool("list_agent_memory", {"query": "重音"}).get("keys") == ["节奏偏好"]
		and Tools.call_tool("get_agent_memory", {"key": memory.key}).get("text") == memory.text,
		"Memory persists on disk, can be searched, and can be read by key")
	_check(Tools.call_tool("delete_agent_memory", {"key": memory.key}).get("saved") == true
		and Tools.call_tool("get_agent_memory", {"key": memory.key}).has("error"), "A memory can be forgotten")
	print("AGENT_PROMPT_EDITOR_SMOKE failures=", failures)
	quit(0 if failures == 0 else 1)
