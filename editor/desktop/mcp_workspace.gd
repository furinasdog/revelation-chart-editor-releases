extends Node

const DialogLayout := preload("res://desktop/dialog_layout.gd")

const Server := preload("res://desktop/mcp_server.gd")
const Catalog := preload("res://desktop/mcp_catalog.gd")
const Agent := preload("res://desktop/chart_agent.gd")
const Automatic := preload("res://desktop/automatic_chart.gd")
const Plan := preload("res://desktop/auto_chart_plan.gd")
const AnimationDraft := preload("res://desktop/agent_animation.gd")
const Frames := preload("res://desktop/agent_frames.gd")
const Artwork := preload("res://desktop/mcp_artwork.gd")
const AudioImport := preload("res://desktop/agent_audio_import.gd")
const Connection := preload("res://desktop/mcp_connection.gd")
const Guidance := preload("res://desktop/editor_guidance.gd")
const CONFIG_PATH := "user://mcp_server.cfg"

var _workspace: Node
var _server := Server.new()
var _tools := Catalog.tools()
var _drafts := {}
var _active_session := ""
var _share_media := false
var _share_paths := false
var _token: String
var _dialog: AcceptDialog
var _approval: ConfirmationDialog
var _approved := false
var _port: SpinBox
var _path: LineEdit
var _client: LineEdit
var _allow_images: CheckBox
var _allow_paths: CheckBox
var _status: Label
var _toggle: Button
var _copy: Button
var _connection_dialog: AcceptDialog

func setup(workspace: Node) -> void:
	_workspace = workspace
	add_child(_server)
	_server.session_closed.connect(_close_draft)
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	_token = str(config.get_value("mcp", "token", ""))
	if _token.length() != 64 or not _token.is_valid_hex_number():
		_token = Crypto.new().generate_random_bytes(32).hex_encode()
	_dialog = AcceptDialog.new()
	_dialog.title = "MCP 服务器"
	_dialog.ok_button_text = "关闭"
	_dialog.transient = true
	_dialog.exclusive = true
	workspace.host.add_child(_dialog)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	_dialog.add_child(body)
	var intro: Label = _workspace._label("让本机 MCP 客户端读取工程、分析音频及编辑草稿。应用草稿前会在编辑器内询问。")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(intro)
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = int(config.get_value("mcp", "port", 17387))
	_add_row(body, "监听端口", _port)
	_path = LineEdit.new()
	_path.max_length = 120
	_path.placeholder_text = "/mcp"
	_path.text = str(config.get_value("mcp", "path", "/mcp"))
	_add_row(body, "端点路径", _path)
	_client = LineEdit.new()
	_client.max_length = 128
	_client.placeholder_text = "留空允许持有令牌的客户端"
	_client.text = str(config.get_value("mcp", "client", ""))
	_client.tooltip_text = "匹配客户端在 MCP 初始化时上报的 clientInfo.name，区分大小写。"
	_add_row(body, "绑定客户端名称", _client)
	_allow_images = CheckBox.new()
	_allow_images.text = "允许客户端读取曲绘、预览画面和音频图"
	_allow_images.button_pressed = bool(config.get_value("mcp", "share_media", false))
	body.add_child(_allow_images)
	_allow_paths = CheckBox.new()
	_allow_paths.text = "允许客户端获取音频的本机绝对路径"
	_allow_paths.button_pressed = bool(config.get_value("mcp", "share_paths", false))
	body.add_child(_allow_paths)
	_share_media = _allow_images.button_pressed
	_share_paths = _allow_paths.button_pressed
	_allow_images.toggled.connect(_sharing_changed)
	_allow_paths.toggled.connect(_sharing_changed)
	_status = _workspace._label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)
	var buttons := HFlowContainer.new()
	body.add_child(buttons)
	_toggle = _workspace._button("启动服务器", _toggle_server)
	_copy = _workspace._button("复制连接配置", _copy_config)
	buttons.add_child(_toggle)
	buttons.add_child(_workspace._button("配置 MCP 工作目录", _setup_client))
	buttons.add_child(_copy)
	_refresh()

func open() -> void:
	_refresh()
	DialogLayout.present(_dialog, Vector2i(555, 355))

func apply_theme(theme: Theme) -> void:
	_dialog.theme = theme
	if is_instance_valid(_approval):
		_approval.theme = theme
	if is_instance_valid(_connection_dialog):
		_connection_dialog.theme = theme

func _add_row(body: VBoxContainer, caption: String, entry: Control) -> void:
	var row := HBoxContainer.new()
	var label: Label = _workspace._label(caption)
	label.custom_minimum_size.x = 125
	row.add_child(label)
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(entry)
	body.add_child(row)

func _toggle_server() -> void:
	if _server.is_running():
		_server.stop()
		_refresh()
		return
	_port.apply()
	var path := _path.text.strip_edges()
	if RegEx.create_from_string(r"^/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+$").search(path) == null:
		_status.text = "端点路径须以 / 开头，可使用英文字母、数字、连字符和下划线。"
		return
	if _token.length() != 64:
		_status.text = "无法生成连接令牌。"
		return
	var error := _server.start(int(_port.value), path, _client.text.strip_edges(), _token, _tools, _dispatch_tool, _can_reclaim_session)
	if error != OK:
		_status.text = "启动失败。请确认端口可用后重试。"
		return
	if not _save_settings():
		_server.stop()
		_refresh()
		_status.text = "无法保存 MCP 设置。请检查用户目录的写入权限。"
		return
	_workspace.diagnostics.record("mcp.start", {"port": int(_port.value), "share_media": _share_media})
	_refresh()
	if Connection.has_workspace() and not Connection.write_endpoint(_server.endpoint(), _token):
		_status.text = "服务器已启动，但未能更新工作目录的连接地址。请重新打开工作目录设置。"

func _save_settings() -> bool:
	var config := ConfigFile.new()
	config.set_value("mcp", "port", int(_port.value))
	config.set_value("mcp", "path", _path.text.strip_edges())
	config.set_value("mcp", "client", _client.text.strip_edges())
	config.set_value("mcp", "share_media", _allow_images.button_pressed)
	config.set_value("mcp", "share_paths", _allow_paths.button_pressed)
	config.set_value("mcp", "token", _token)
	return config.save(CONFIG_PATH) == OK

func _sharing_changed(_pressed: bool) -> void:
	# Changes apply immediately, including revocation if saving preferences fails.
	_share_media = _allow_images.button_pressed
	_share_paths = _allow_paths.button_pressed
	if not _save_settings():
		_status.text = "当前权限已生效，但未能保存到下次启动。"

func _refresh() -> void:
	var running := _server.is_running()
	_toggle.text = "停止服务器" if running else "启动服务器"
	_copy.disabled = not running
	_port.editable = not running
	_path.editable = not running
	_client.editable = not running
	_status.text = "正在监听 " + _server.endpoint() if running else "服务器已停止"

func _copy_config() -> void:
	if not _server.is_running():
		return
	DisplayServer.clipboard_set(JSON.stringify({"mcpServers": {"revelation": {
		"url": _server.endpoint(), "headers": {"Authorization": "Bearer " + _token}}}}, "\t"))
	_status.text = "已复制连接配置（含令牌）\n" + _server.endpoint()

func _setup_client() -> void:
	if not _server.is_running():
		_toggle_server()
	if not _server.is_running():
		return
	var config := Connection.generate(_server.endpoint(), _token)
	if config.has("error"):
		_status.text = str(config.error)
		return
	if is_instance_valid(_connection_dialog):
		_connection_dialog.queue_free()
	_connection_dialog = AcceptDialog.new()
	_connection_dialog.title = "MCP 工作目录"
	_connection_dialog.ok_button_text = "完成"
	_connection_dialog.transient = true
	_connection_dialog.exclusive = true
	_connection_dialog.theme = _dialog.theme
	_dialog.add_child(_connection_dialog)
	var body := VBoxContainer.new()
	_connection_dialog.add_child(body)
	var info: Label = _workspace._label("服务器已启动。把下面的目录作为 Codex 或 Claude Code 的项目打开，首次连接时按客户端提示信任目录或批准 Revelation。制谱时保持编辑器打开。")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(info)
	var path := LineEdit.new()
	path.editable = false
	path.text = config.folder
	_add_row(body, "项目工作目录", path)
	var buttons := HFlowContainer.new()
	body.add_child(buttons)
	buttons.add_child(_workspace._button("复制目录路径", func(): DisplayServer.clipboard_set(path.text)))
	buttons.add_child(_workspace._button("打开工作目录", func(): OS.shell_open(config.folder)))
	DialogLayout.present(_connection_dialog, Vector2i(680, 220))

func _dispatch_tool(id: String, client: String, name: String, arguments: Dictionary, live: Callable) -> Dictionary:
	if not _tools.any(func(tool: Dictionary): return tool.name == name):
		return _format_result({"error": "未知制谱工具。"})
	if name == "get_editor_help":
		return _format_result(_workspace._copilot_help(str(arguments.get("query", "")).left(150)))
	if name == "get_editing_guide":
		return _format_result({"instructions": Guidance.FULL})
	if name == "get_audio_path":
		return _format_result(_audio_path())
	if name == "list_project_artwork":
		return _format_result(_list_project_artwork(arguments))
	var uses_media := name in Catalog.IMAGE_TOOLS or name == "list_artwork"
	if uses_media and not _share_media:
		return _format_result({"error": "请在 MCP 服务器设置中授权客户端读取图片。"})
	if not _active_session.is_empty() or _workspace.copilot.busy or _workspace._video.busy or _workspace._analyzing or _workspace.scripts._active:
		return _format_result({"error": "编辑器正在处理其他任务，请稍后重试。"})
	var draft: Dictionary = _drafts.get(id, {})
	var generation: int = _workspace._document_generation
	var signature := _signature()
	if not draft.is_empty() and (draft.generation != generation or draft.signature != signature):
		var has_changes: bool = draft.agent._chat_has_changes() or draft.animation.has_assets()
		_close_draft(id)
		if has_changes:
			return _format_result({"error": "工程已切换或谱面已有编辑，旧草稿已丢弃。请重新读取工程。"})
		draft = {}
	if name == "import_audio":
		return _format_result(await _import_audio(id, client, arguments, live, generation, signature))
	if draft.is_empty():
		draft = _new_draft(id, generation, signature)
	if _share_media:
		_prepare_draft_media(draft)
	_active_session = id
	var visual_selection: Vector2 = _workspace._agent_audio_selection()
	var result: Dictionary
	if name == "add_artwork":
		result = await _add_artwork(draft, client, arguments, live)
	else:
		result = await draft.agent.call_workspace_tool(name, arguments, visual_selection)
	if uses_media and not _share_media:
		result = {"error": "客户端的媒体读取权限已关闭。"}
	elif name == "get_cover" and result.get("provided", false):
		result["_preview_image"] = draft.animation.artwork[result.artwork_id].data_url
	if result.has("finished"):
		result = await _apply_draft(draft, client, result.finished, live)
		_close_draft(id)
	elif not live.call():
		_close_draft(id)
		result = {"error": "客户端已取消请求。"}
	_active_session = ""
	if not _drafts.has(id) and is_instance_valid(draft.agent):
		draft.agent.queue_free()
	_workspace.diagnostics.record("mcp.tool", {"name": name, "success": not result.has("error")})
	return _format_result(result)

func _import_audio(id: String, client: String, arguments: Dictionary, live: Callable,
		generation: int, signature: String) -> Dictionary:
	var path := AudioImport.local_path(arguments.get("path"))
	if path.is_empty():
		return {"error": "请指定本机 WAV、MP3 或 OGG 的绝对路径。"}
	for pending: Dictionary in _drafts.values():
		if pending.agent._chat_has_changes() or pending.animation.has_assets():
			return {"error": "还有 MCP 会话持有未提交的草稿，请先提交或丢弃，再导入音频。"}
	var prior_agent: Node = _drafts.get(id, {}).get("agent")
	_active_session = id
	var allowed := await _approve_request("导入 MCP 音频", "客户端「%s」请求导入下面的文件。此操作会替换工程音频，保留已有音符并清空现有音频分析。\n\n%s"
		% [_client_caption(client), path], "导入音频", "拒绝", live)
	var result: Dictionary
	if not allowed:
		result = {"error": "音频导入已取消或被拒绝。"}
	elif generation != _workspace._document_generation or signature != _signature():
		result = {"error": "工程已发生变化，请重新确认需要导入的音频。"}
	else:
		result = AudioImport.load_into(_workspace, path)
	_active_session = ""
	if not result.has("error"):
		_close_draft(id)
	elif not _drafts.has(id) and is_instance_valid(prior_agent):
		prior_agent.queue_free()
	_workspace.diagnostics.record("mcp.tool", {"name": "import_audio", "success": not result.has("error")})
	return result

func _audio_path() -> Dictionary:
	var chart: Node = _workspace.chart
	var relative: String = chart.audio_path
	if relative.is_empty():
		return {"available": false}
	var full: String = chart.resolve_audio_path(relative)
	var result := {"available": not full.is_empty() and FileAccess.file_exists(full), "filename": relative.get_file(),
		"absolute_path_shared": _share_paths}
	if not relative.is_absolute_path():
		result["project_path"] = relative
	if _share_paths and result.available:
		result["path"] = ProjectSettings.globalize_path(full).simplify_path()
	return result

func _list_project_artwork(arguments: Dictionary) -> Dictionary:
	if not _share_media:
		return {"error": "请在 MCP 服务器设置中授权客户端读取曲绘。"}
	var first: String = _workspace.automatic._find_cover()
	var paths: Array[String] = _workspace.automatic._project_artwork(first)
	var offset := Agent._integer(arguments, "offset", 0, 0, paths.size())
	var limit := Agent._integer(arguments, "limit", 24, 1, 64)
	return {"items": paths.slice(offset, offset + limit).map(func(path: String): return {
		"project_path": path, "filename": path.get_file(), "format": path.get_extension().to_lower()}),
		"total": paths.size(), "offset": offset}

func _add_artwork(draft: Dictionary, client: String, arguments: Dictionary, live: Callable) -> Dictionary:
	var supplied := int(arguments.has("project_path")) + int(arguments.has("path")) + int(arguments.has("data_base64"))
	if supplied != 1:
		return {"error": "请提供 project_path、本机 path 或 data_base64 三种来源中的一种。"}
	var chart: Node = _workspace.chart
	if arguments.has("project_path"):
		if not _share_media:
			return {"error": "请授权读取工程曲绘。"}
		var relative := str(arguments.project_path)
		var first: String = _workspace.automatic._find_cover()
		if relative not in _workspace.automatic._project_artwork(first):
			return {"error": "请从 list_project_artwork 返回的工程图片中选择。"}
		var project_art: Dictionary = _workspace.automatic._prepare_cover(relative)
		if project_art.is_empty():
			return {"error": "无法读取工程图片。"}
		return draft.animation.register_artwork(project_art)
	var filename := ""
	var bytes := PackedByteArray()
	if arguments.has("path"):
		var path := str(arguments.path).replace("\\", "/")
		if not Artwork.local_image_path(path):
			return {"error": "请提供本机 PNG 或 JPEG 文件的绝对路径。"}
		if not await _approve_request("读取本机曲绘", "客户端「%s」请求读取并导入这张图片。\n\n%s" % [_client_caption(client), path],
				"允许读取", "拒绝", live):
			return {"error": "本机图片读取请求已取消或被拒绝。"}
		if draft.generation != _workspace._document_generation or draft.signature != _signature():
			return {"error": "工程已变化，请重新打开草稿。"}
		filename = path.get_file()
		bytes = Artwork.load_local(path)
	else:
		filename = str(arguments.get("filename", "")).replace("\\", "/").get_file()
		bytes = Artwork.from_base64(arguments.data_base64)
	var image := Artwork.prepare(chart, filename, bytes)
	if image.is_empty():
		return {"error": "图片无效或过大。请使用 PNG 或 JPEG，最多 1200 万像素，本机文件最多 16 MiB，上传最多 256 KiB。"}
	var result: Dictionary = draft.animation.register_artwork(image, bytes)
	if not result.has("error"):
		result["staged"] = draft.animation.imported_artwork.has(image.path)
		result["project_path"] = image.path
	return result

func _signature() -> String:
	var chart: Node = _workspace.chart
	# Hash the shared change signature so idle MCP sessions do not keep another copy of the entire chart.
	var signature: Dictionary = _workspace.copilot._signature()
	signature["bpm"] = chart.bpm
	signature["bpm_segments"] = chart.bpm_segments
	signature["difficulty"] = chart.chart_info.get("difficulty", "")
	return JSON.stringify(signature).sha256_text()

func _new_draft(id: String, generation: int, signature: String) -> Dictionary:
	var chart: Node = _workspace.chart
	var level := str(chart.chart_info.get("difficulty", "HD")).to_upper().left(2)
	var plan := Plan.new(chart, level)
	var animation := AnimationDraft.new(chart, plan.duration_ms, [])
	var agent := Agent.new()
	add_child(agent)
	var options := {"help": _workspace._copilot_help, "editor_view": _workspace.agent_editor_view}
	if not chart.audio_path.is_empty():
		options["reanalyze"] = _workspace._analyze_for_agent
	agent.open_tool_session(plan, Automatic.music_for_agent(chart, _workspace._cached_chart_music(), plan.duration_ms),
		_workspace.automatic._estimate_mood(), animation, options)
	var draft := {"agent": agent, "plan": plan, "animation": animation, "generation": generation, "signature": signature}
	_drafts[id] = draft
	return draft

func _prepare_draft_media(draft: Dictionary) -> void:
	if draft.get("media_available", false):
		return
	draft["media_available"] = true
	var first: String = _workspace.automatic._find_cover()
	for path: String in _workspace.automatic._project_artwork(first).slice(0, Automatic.COVER_LIMIT):
		var image: Dictionary = _workspace.automatic._prepare_cover(path)
		if not image.is_empty():
			draft.animation.register_artwork(image)
	var agent: Node = draft.agent
	var plan: RefCounted = draft.plan
	var animation: RefCounted = draft.animation
	agent._frame_capture = func(times: Array) -> Dictionary:
		return await Frames.capture(self, _workspace.chart, plan, animation, times, agent.draft_changes())
	agent._audio_spectrum = _workspace._capture_agent_spectrum

func _can_reclaim_session(id: String) -> bool:
	var draft: Dictionary = _drafts.get(id, {})
	return id != _active_session and (draft.is_empty() or (not draft.agent._chat_has_changes() and not draft.animation.has_assets()))

func _close_draft(id: String) -> void:
	if not _drafts.has(id):
		return
	var draft: Dictionary = _drafts[id]
	_drafts.erase(id)
	if id != _active_session:
		draft.agent.queue_free()

func _apply_draft(draft: Dictionary, client: String, summary: String, live: Callable) -> Dictionary:
	var edits: Dictionary = draft.agent.draft_changes()
	var caption := "客户端「%s」请求应用草稿。\n%d 项音符改动 · %d 个动画层 · %d 个图片切换 · %d 张导入曲绘\n%d 项文本改动 · %d 项谱面信息改动%s%s\n\n%s" % [
		_client_caption(client), draft.plan.edited.size(), draft.animation.layers.size(),
		draft.animation.mask_cues.size() + draft.animation.artwork_cues.size(), draft.animation.imported_artwork.size(),
		edits.get("text", {}).size(), edits.get("metadata", {}).size(),
		" · 修改初始底图或蒙版" if edits.has("images") else "",
		" · 修改速度表" if not edits.get("tempo", []).is_empty() else "", summary]
	if not await _approve_request("应用 MCP 制谱草稿", caption, "应用草稿", "丢弃草稿", live):
		return {"error": "草稿已丢弃。"}
	if draft.generation != _workspace._document_generation or draft.signature != _signature():
		return {"error": "工程已切换或谱面发生改动，草稿已丢弃。"}
	if draft.animation.has_assets() and draft.animation.save_assets(_workspace._get_or_create_root()) != OK:
		return {"error": "无法保存图像素材，草稿未写入。"}
	_workspace.chart.apply_automatic_notes(draft.plan.notes, draft.plan.edited, draft.animation.layers.values(),
		draft.animation.mask_cues.values(), {}, edits)
	return {"finished": summary, "applied": true}

func _approve_request(title: String, text: String, allow: String, deny: String, live: Callable) -> bool:
	if not live.call():
		return false
	if not is_instance_valid(_approval):
		_approval = ConfirmationDialog.new()
		_approval.dialog_autowrap = true
		_approval.transient = true
		_approval.exclusive = true
		_approval.theme = _dialog.theme
		_approval.confirmed.connect(func(): _approved = true)
		_workspace.host.add_child(_approval)
	_approved = false
	_approval.title = title
	_approval.ok_button_text = allow
	_approval.cancel_button_text = deny
	_approval.dialog_text = text
	DialogLayout.present(_approval, Vector2i(540, 195))
	while _approval.visible and not _approved and live.call():
		await get_tree().create_timer(0.12).timeout
	_approval.hide()
	return _approved and live.call()

static func _client_caption(client: String) -> String:
	return client.replace("\n", " ").replace("\r", " ")

static func _format_result(result: Dictionary) -> Dictionary:
	var image := str(result.get("_preview_image", ""))
	result.erase("_preview_image")
	var report: Dictionary = result.get("conflicts", result if result.has("slide_directions") else {})
	if report.has("slide_directions"):
		result["validation_summary"] = ("回滚前，" if result.get("rolled_back", false) else "") + Agent.Context.describe_validation(report)
	var content := [{"type": "text", "text": JSON.stringify(result, "  " if result.has("validation_summary") else "")}]
	for mime: String in ["image/jpeg", "image/png"]:
		var prefix := "data:%s;base64," % mime
		if image.begins_with(prefix):
			content.append({"type": "image", "mimeType": mime, "data": image.substr(prefix.length())})
			break
	return {"content": content, "structuredContent": result, "isError": result.has("error")}
