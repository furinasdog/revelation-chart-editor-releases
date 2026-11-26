extends SceneTree

const MCP := preload("res://desktop/mcp_workspace.gd")
const References := preload("res://desktop/reference_library.gd")
const VERSION := "2025-11-25"
const CLIENT := "revelation-mcp-smoke"
var _mcp: Node
var _checks := 0
var _failed := 0
var _session := ""
var _next_id := 1

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed += 1
		push_error(message)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var legacy := ConfigFile.new()
	legacy.load(MCP.CONFIG_PATH)
	legacy.set_value("mcp", "share_media", false)
	if legacy.save(MCP.CONFIG_PATH) != OK:
		quit(2)
		return
	if args.size() != 1 or change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var workspace: Node = current_scene.desktop
	workspace._onboarding._chooser.hide()
	if not workspace.import_audio(args[0], false, false):
		quit(2)
		return
	var cover := Image.create_empty(96, 54, false, Image.FORMAT_RGB8)
	cover.fill(Color("#623597"))
	_check(cover.save_png(workspace.chart.get_root_dir().path_join("mcp-project-cover.png")) == OK, "Create project artwork")
	_mcp = workspace.mcp
	_check(not _mcp._server.is_running(), "MCP starts disabled")
	_mcp.open()
	var boxes: Array[Node] = _mcp._dialog.find_children("*", "CheckBox", true, false)
	_check(boxes == [_mcp._allow_paths], "MCP settings only ask about sharing the local audio path")
	_mcp._dialog.hide()
	if not OS.get_environment("REVELATION_TEST_MCP_PORT").is_empty():
		var port := OS.get_environment("REVELATION_TEST_MCP_PORT")
		_mcp._port.value = int(port)
		_mcp._port.get_line_edit().text = port
	_mcp._path.text = "/mcp/editor"
	_mcp._client.text = CLIENT
	var interpreter := OS.get_environment("REVELATION_PYTHON")
	if interpreter.is_empty():
		_mcp._toggle_server()
	else:
		_mcp._setup_client()
		await _check_setup(interpreter)
	if not _mcp._server.is_running():
		push_error(_mcp._status.text)
		quit(1)
		return
	var server: Node = _mcp._server
	var saved := ConfigFile.new()
	_check(saved.load(MCP.CONFIG_PATH) == OK and not saved.has_section_key("mcp", "share_media"),
		"Saving connection settings retires the old disabled media preference")
	for version in ["HTTP/1.0", "HTTP/1.1"]:
		var header := "POST /mcp/editor %s\r\nHost: 127.0.0.1:%d\r\nAuthorization: Bearer %s\r\nContent-Type: application/json\r\nContent-Length: 27" % [version, server._port, _mcp._token]
		var request: Dictionary = server._parse_request(header)
		_check(request.get("method") == "POST" and request.get("length") == 27
			and request.get("headers", {}).get("content-type") == "application/json", "Parse request line and headers for " + version)
	var init := {"protocolVersion": VERSION, "capabilities": {}, "clientInfo": {"name": CLIENT, "version": "1"}}
	await _check_session_capacity(init)
	var call := await _rpc("initialize", init, ["Origin: https://example.org"])
	_check(call.code == 403, "Reject nonlocal Origin")
	call = await _rpc("initialize", init, [], "")
	_check(call.code == 401, "Require Bearer token")
	var wrong := init.duplicate(true)
	wrong.clientInfo.name = "different-client"
	call = await _rpc("initialize", wrong)
	_check(call.code == 403, "Enforce client name")
	call = await _rpc("initialize", init)
	for header: String in call.headers:
		if header.to_lower().begins_with("mcp-session-id: "):
			_session = header.get_slice(" ", 1)
	_check(not _session.is_empty() and call.result.get("protocolVersion") == VERSION, "Negotiate protocol and acquire session ID")
	var instructions: String = call.result.get("instructions", "")
	_check(call.result.get("capabilities", {}).has("prompts") and ".rpy > 单项工具" in instructions
		and "斜上方" in instructions and "scale_hold_paths" in instructions, "Initialize exposes the shared workflow and charting rules")
	if _session.is_empty():
		quit(1)
		return
	call = await _request({"jsonrpc": "2.0", "method": "notifications/initialized"})
	_check(call.code == 202, "Notifications are accepted with no body")
	call = await _rpc("prompts/list")
	_check(call.result.get("prompts", [{}])[0].get("name") == "revelation-charting", "Discover the charting prompt")
	call = await _rpc("prompts/get", {"name": "revelation-charting"})
	var prompt: String = call.result.get("messages", [{"content": {}}])[0].content.get("text", "")
	_check("沿用相对拍位" in instructions and "沿用相对拍位" in prompt, "Both MCP entry points teach variation on a repeated phrase")
	_check("chart.notes(from_ms, to_ms" in prompt and "保持判定、松开和预告时间" in prompt and "import_audio" in prompt,
		"Prompt teaches .rpy, hold geometry and audio import")
	call = await _tool("get_editing_guide", {})
	_check(call.result.get("structuredContent", {}).get("instructions") == prompt, "Clients can also fetch the guide as a tool")
	call = await _rpc("tools/list")
	var names: Array = call.result.get("tools", []).map(func(tool: Dictionary): return tool.name)
	_check(names.size() == 68 and names.has("locate_notes") and names.has("analyze_audio") and names.has("view_audio_figure") and names.has("scale_hold_paths")
		and names.has("add_mask_reveal") and names.has("get_audio_path") and names.has("create_shape_asset"),
		"Discover every Agent tool, got %s" % str(names))
	call = await _tool("query_reference_chart", {"id": "phrase-study", "section": "paths", "limit": 1})
	_check(not call.result.get("isError", true) and call.result.structuredContent.total == 2, "Read the built-in reference through MCP")
	call = await _tool("list_project_artwork", {})
	_check(call.result.structuredContent.items.any(func(item: Dictionary): return item.filename == "mcp-project-cover.png"),
		"Existing clients with media disabled can discover project artwork")
	call = await _tool("list_artwork", {})
	var matching: Array = call.result.structuredContent.items.filter(func(item: Dictionary): return item.filename == "mcp-project-cover.png")
	if not _require(matching.size() == 1, "Default artwork catalog includes the cover"):
		quit(1)
		return
	call = await _tool("get_cover", {"artwork_id": matching[0].artwork_id})
	var media: Array = call.result.get("content", [])
	var decoded := Image.new()
	_check(media.size() == 2 and media[1].type == "image" and decoded.load_jpg_from_buffer(Marshalls.base64_to_raw(media[1].data)) == OK
		and decoded.get_size() == cover.get_size(), "The initial session returns the project cover as an MCP image")
	if not OS.get_environment("REVELATION_PYTHON").is_empty():
		call = await _tool("run_rpy", {"source": "result(len(chart.notes()))"})
		_check(not call.result.get("isError", true) and call.result.structuredContent.result == 0, "Run a restricted read-only script")
		call = await _tool("run_rpy", {"source": "import os"})
		_check(call.result.get("isError", false), "Restricted scripts reject imports")
		var script := "chart.edit('add_notes', notes=[{'type':'note','time_ms':2000,'lane':1,'x':700,'y':430},{'type':'note','time_ms':2000,'lane':2,'x':702,'y':431}])\nresult({'added':2})"
		call = await _tool("run_rpy", {"source": script})
		var rejected: Dictionary = call.result.get("structuredContent", {})
		_check(call.result.get("isError", false) and rejected.get("rolled_back", false) and not rejected.has("result")
			and rejected.get("operation_count", -1) == 0 and rejected.get("conflicts", {}).get("error_count", 0) > 0,
			"Rejected scripts report the rolled-back draft and omit the script's claimed additions")
		call = await _tool("list_notes", {})
		_check(call.result.get("structuredContent", {}).get("total") == 0, "Physical conflicts still roll back a script batch")
		var slides := []
		for index in range(4):
			slides.append({"type": "drag", "time_ms": 4000 + index * 700, "lane": index,
				"x": 470 + index * 300, "y": 470, "approach_x": 320 + index * 300, "approach_y": 630})
		call = await _tool("run_rpy", {"source": "chart.edit('add_notes', notes=%s)" % JSON.stringify(slides)})
		var success: Dictionary = call.result.get("structuredContent", {})
		var summary: Dictionary = success.get("conflicts", {})
		var info: Array = call.result.get("content", [])
		_check(not call.result.get("isError", true) and summary.get("slide_directions", {}).get("diagonal") == 4
			and summary.get("edited_slide_directions", {}).get("suggested_horizontal") == 2
			and not info.is_empty() and "横向 0 个，斜向 4 个" in info[0].text,
			"A diagonal passage is staged and reports named counts in the MCP text and structured result")
		if success.get("operation_count", 0) > 0:
			_finish_when_visible.call_deferred(false)
			await _tool("finish", {"summary": "放弃滑键测试草稿"})
	call = await _tool("get_audio_loudness", {"from_ms": 400, "to_ms": 2400})
	_check(not call.result.get("isError", true) and call.result.structuredContent.items.size() == 2, "Return real selection loudness")
	call = await _tool("get_audio_path", {})
	_check(call.result.structuredContent.available and not call.result.structuredContent.has("path"), "Keep absolute audio path private by default")
	call = await _tool("view_audio_figure", {"kind": "waveform", "from_ms": 400, "to_ms": 2400})
	media = call.result.get("content", [])
	_check(media.size() == 2 and media[1].type == "image" and decoded.load_jpg_from_buffer(Marshalls.base64_to_raw(media[1].data)) == OK,
		"The waveform is readable without sharing local audio paths")
	var note := {"type": "note", "lane": 3, "time_ms": 2100, "x": 660, "y": 400}
	call = await _tool("add_notes", {"notes": [note]})
	_check(not call.result.get("isError", true) and workspace.chart.notes.is_empty(), "Writes stay in the MCP draft")
	call = await _tool("locate_notes", {"seconds": 2.1, "radius_ms": 0})
	var located: Dictionary = call.result.get("structuredContent", {})
	_check(located.get("total") == 1 and located.items[0].match == "judgement"
		and located.items[0].label == workspace.chart.ruler_position(2100).label, "Locate draft note using the same ruler label as the inspector")
	await _check_capacity_preserves_draft(init)
	_finish_when_visible.call_deferred(false)
	call = await _tool("finish", {"summary": "测试拒绝应用"})
	_check(call.result.get("isError", false) and workspace.chart.notes.is_empty(), "Rejecting the modal discards the draft")
	await _tool("add_notes", {"notes": [note]})
	_finish_when_visible.call_deferred(true)
	call = await _tool("finish", {"summary": "测试应用一个键"})
	_check(call.result.get("structuredContent", {}).get("applied", false) and workspace.chart.notes.size() == 1, "Confirm and apply the draft")
	var second_note := note.duplicate()
	second_note.time_ms = 3200
	second_note.x = 1200
	await _tool("add_notes", {"notes": [second_note]})
	workspace.chart.set_audio_delay(250)
	call = await _tool("finish", {})
	_check(call.result.get("isError", false) and workspace.chart.notes.size() == 1, "Stale drafts cannot overwrite manual changes")
	call = await _request({}, [], _mcp._token, HTTPClient.METHOD_DELETE)
	_check(call.code == 204 and _mcp._drafts.is_empty(), "DELETE closes the session")
	_session = ""
	call = await _rpc("initialize", init)
	_session = _session_id(call)
	await _tool("get_project_context", {})
	_mcp._allow_paths.button_pressed = true
	var reference_zip := OS.get_environment("REVELATION_TEST_REFERENCE")
	if not reference_zip.is_empty():
		await _check_reference_media(reference_zip)
	await _check_asset_and_edit_tools(workspace)
	await _check_audio_import(workspace, args[0])
	_mcp._toggle_server()
	_check(not _mcp._server.is_running(), "Can stop the server")
	print("MCP_WORKSPACE_SMOKE checks=", _checks, " failed=", _failed)
	quit(1 if _failed else 0)

func _check_session_capacity(init: Dictionary) -> void:
	var opened: Array[String] = []
	for _attempt in range(5):
		var call := await _rpc("initialize", init)
		opened.append(_session_id(call))
	_check(not opened[4].is_empty(), "A fifth connection recycles an abandoned session without restarting")
	for id: String in opened:
		if not id.is_empty():
			_session = id
			await _request({}, [], _mcp._token, HTTPClient.METHOD_DELETE)
	_session = ""

func _check_capacity_preserves_draft(init: Dictionary) -> void:
	var original := _session
	_session = ""
	var others: Array[String] = []
	for _attempt in range(4):
		var call := await _rpc("initialize", init)
		others.append(_session_id(call))
	_check(not others[-1].is_empty(), "Capacity recycles an idle connection even when another session has a draft")
	for id: String in others:
		if not id.is_empty():
			_session = id
			await _request({}, [], _mcp._token, HTTPClient.METHOD_DELETE)
	_session = original
	var draft := await _tool("list_notes", {})
	_check(draft.result.get("structuredContent", {}).get("total") == 1, "Recycling preserves another session's unsubmitted draft")

static func _session_id(call: Dictionary) -> String:
	for header: String in call.headers:
		if header.to_lower().begins_with("mcp-session-id: "):
			return header.get_slice(" ", 1)
	return ""

func _check_setup(interpreter: String) -> void:
	var folder := ProjectSettings.globalize_path("user://mcp_connection")
	_check(_mcp._server.is_running() and is_instance_valid(_mcp._connection_dialog)
		and FileAccess.file_exists(folder.path_join(".codex/config.toml")) and FileAccess.file_exists(folder.path_join(".mcp.json")),
		"One button creates an MCP-enabled working directory for both clients")
	if is_instance_valid(_mcp._connection_dialog):
		_mcp._connection_dialog.hide()
		await process_frame
		var old := FileAccess.open(folder.path_join("connection.json"), FileAccess.WRITE)
		old.store_string(JSON.stringify({"url": _mcp._server.endpoint(), "token": _mcp._token}))
		old.close()
		_mcp._setup_client()
		_check(_mcp._connection_dialog.visible and _mcp._server.is_running(), "One-click configuration refreshes an existing setup without stopping the server")
		_mcp._connection_dialog.hide()
	var fixture := ProjectSettings.globalize_path("res://tests/fixtures/mcp_stdio_smoke.py")
	var report := folder.path_join("bridge-smoke.txt")
	var pid := OS.create_process(interpreter, PackedStringArray([fixture, folder, CLIENT, report]), false)
	var duration := Time.get_ticks_msec() + 12000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < duration:
		await process_frame
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	_check(FileAccess.get_file_as_string(report) == "OK", "Generated Codex and Claude configurations work with the real stdio bridge")

func _check_audio_import(workspace: Node, source: String) -> void:
	var chart: Node = workspace.chart
	var count: int = chart.notes.size()
	var before: String = chart.audio_path
	var call := await _tool("import_audio", {"path": "https://example.org/track.wav"})
	_check(call.result.get("isError", false), "Audio import rejects URLs")
	call = await _tool("import_audio", {"path": source})
	_check(call.result.get("isError", false) and chart.audio_path == before, "Audio import refuses to discard pending edits")
	_finish_when_visible.call_deferred(false)
	await _tool("finish", {"summary": "丢弃测试草稿"})
	_finish_when_visible.call_deferred(false)
	call = await _tool("import_audio", {"path": source})
	_check(call.result.get("isError", false) and chart.audio_path == before, "Refused import keeps the project intact")
	chart.set_rhythm_analysis({"beats": [200, 800]})
	_finish_when_visible.call_deferred(true)
	call = await _tool("import_audio", {"path": source})
	_check(call.result.get("structuredContent", {}).get("imported", false) and chart.audio_path != before
		and chart.rhythm_analysis.is_empty() and chart.notes.size() == count, "Approved import changes audio and clears analysis while preserving notes")
	call = await _tool("get_audio_info", {})
	_check(call.result.get("structuredContent", {}).get("filename") == chart.audio_path, "MCP reads the new audio after the draft reset")

func _check_reference_media(reference_zip: String) -> void:
	var reference := References.import_local(reference_zip)
	if not reference.has("id"):
		_check(false, "Import the reference fixture")
		return
	var args := {"id": reference.id, "filename": "background.png"}
	var call := await _tool("view_reference_artwork", args)
	_check(call.result.get("isError", false), "Imported reference artwork retains the permission chosen during import")
	_check(References.import_local(reference_zip, true, false).get("id") == reference.id, "Update reference image authorization")
	call = await _tool("view_reference_artwork", args)
	var media: Array = call.result.get("content", [])
	var decoded := Image.new()
	_check(media.size() == 2 and media[1].type == "image"
		and decoded.load_jpg_from_buffer(Marshalls.base64_to_raw(media[1].data)) == OK, "Read authorized reference artwork by filename")
	call = await _tool("get_reference_media", {"id": reference.id, "category": "audio"})
	_check(call.result.get("isError", false), "The independent audio grant remains disabled")
	if DisplayServer.get_name() != "headless":
		var frame := {"id": reference.id, "time_ms": 1000}
		call = await _tool("view_reference_frame", frame)
		_check(call.result.get("isError", false), "Rendering an audio-bearing reference requires the local audio grant")
		_check(References.import_local(reference_zip, true, true).get("id") == reference.id, "Grant both reference media permissions")
		call = await _tool("view_reference_frame", frame)
		media = call.result.get("content", [])
		_check(media.size() == 2 and media[1].type == "image"
			and decoded.load_jpg_from_buffer(Marshalls.base64_to_raw(media[1].data)) == OK, "Render an approved reference in an isolated workspace")

func _check_asset_and_edit_tools(workspace: Node) -> void:
	var chart: Node = workspace.chart
	var old_background: String = chart.preview_bg_image_path
	var old_name: String = chart.chart_info.chartName
	var old_bpm: float = chart.bpm
	var call := await _tool("get_audio_path", {})
	var audio: String = call.result.structuredContent.get("path", "")
	_check(audio.is_absolute_path() and FileAccess.file_exists(audio), "Authorized client gets a usable local path")
	var artwork := Image.create_empty(96, 54, false, Image.FORMAT_RGB8)
	artwork.fill(Color("#53639d"))
	var filename := ProjectSettings.globalize_path("user://mcp-source.png")
	artwork.save_png(filename)
	_finish_when_visible.call_deferred(false)
	call = await _tool("add_artwork", {"path": filename})
	_check(call.result.isError, "A client-requested local file is not loaded when the user refuses")
	_finish_when_visible.call_deferred(true)
	call = await _tool("add_artwork", {"path": filename})
	var imported: Dictionary = call.result.structuredContent
	if not _require(not call.result.isError and imported.has("artwork_id") and imported.has("project_path"), "Local artwork loads only after explicit approval"):
		return
	var image_path: String = imported.project_path
	_check(imported.staged and not FileAccess.file_exists(chart.resolve_full_path(image_path)), "Imported artwork remains in memory before finish")
	call = await _tool("add_artwork", {"filename": "invalid.png", "data_base64": Marshalls.raw_to_base64("invalid".to_utf8_buffer())})
	_check(call.result.isError, "Reject an upload with invalid image data")
	artwork.fill(Color("#35426d"))
	call = await _tool("add_artwork", {"filename": "upload.png", "data_base64": Marshalls.raw_to_base64(artwork.save_png_to_buffer())})
	_check(not call.result.isError, "A byte upload stages a second validated image")
	var second: Dictionary = call.result.structuredContent
	call = await _tool("set_project_artwork", {"artwork_id": imported.artwork_id})
	_check(not call.result.isError and chart.preview_bg_image_path == old_background, "Initial artwork change is staged")
	call = await _tool("set_artwork_cue", {"artwork_id": second.get("artwork_id", ""), "time_ms": 3000})
	_check(not call.result.isError, "Stage a timed artwork cue")
	call = await _tool("create_shape_asset", {"width": 160, "height": 100, "shapes": [
		{"kind": "circle", "width": 0.7, "stroke": "#FFFFFFFF", "stroke_width": 0.04},
		{"kind": "square", "x": 0.18, "y": 0.35, "width": 0.2, "stroke": "#096BFF"},
		{"kind": "line", "x": 0.1, "y": 0.9, "end_x": 0.4, "end_y": 0.9, "stroke": "#A9D8FF"}
	]})
	var shape: Dictionary = call.result.structuredContent
	if not _require(not call.result.isError and shape.has("shape_id"), "Create outlined shape composition"):
		return
	call = await _tool("view_shape_asset", {"shape_id": shape.shape_id})
	var media: Array = call.result.content
	var image := Image.new()
	_check(media.size() == 2 and media[1].mimeType == "image/png"
		and image.load_png_from_buffer(Marshalls.base64_to_raw(media[1].data)) == OK
		and image.get_size() == Vector2i(160, 100) and image.get_pixel(80, 50).a == 0.0
		and image.get_pixel(115, 50).a > 0.4 and image.get_pixel(80, 15).a > 0.4,
		"Shape PNG has transparency and the ring stays circular on a rectangular canvas")
	call = await _tool("add_animation_layer", {"source": "shape", "shape_id": shape.shape_id, "keyframes": [
		{"time_ms": 0, "opacity": 0}, {"time_ms": 1000, "opacity": 0.42}, {"time_ms": 2400, "opacity": 0}]})
	_check(not call.result.isError, "Stage an animation using the generated shape")
	call = await _tool("set_chart_metadata", {"fields": {"name": "MCP 测试谱面", "composer": "模型测试"}})
	_check(not call.result.isError and chart.chart_info.chartName == old_name, "Stage metadata without changing live chart")
	call = await _tool("set_tempo_map", {"segments": [{"start_beat": 0, "bpm": 128}, {"start_beat": 8, "bpm": 140}]})
	_check(not call.result.isError and chart.bpm == old_bpm, "Stage two tempo segments")
	call = await _tool("upsert_text_event", {"text": "底部歌词", "from_ms": 1500, "to_ms": 3200})
	_check(not call.result.isError and call.result.structuredContent.get("y") == 1000, "Stage a bottom lyric")
	var lyric_id: int = call.result.structuredContent.get("id", -1)
	call = await _tool("list_text_events", {"from_ms": 2000, "to_ms": 2100})
	_check(call.result.structuredContent.total == 1, "Read a draft lyric overlapping the queried range")
	_finish_when_visible.call_deferred(true)
	call = await _tool("finish", {"summary": "测试应用曲绘和图形动画"})
	_check(call.result.structuredContent.get("applied", false) and chart.bpm_segments.size() == 2 and is_equal_approx(chart.bpm, 128.0)
		and chart.preview_bg_image_path == image_path and chart.chart_info.chartName == "MCP 测试谱面"
		and chart.events.has(lyric_id) and chart.events[lyric_id].pos.y == 1000 and FileAccess.file_exists(chart.resolve_full_path(shape.path)),
		"One approved commit applies the tempo map, artwork, text and on-disk shape")
	var packed_path := ProjectSettings.globalize_path("user://mcp-artwork-test.zip")
	var archive := ZIPReader.new()
	workspace.sidebar._on_file_selected_for_zip_export(packed_path)
	if _require(archive.open(packed_path) == OK and archive.file_exists(image_path) and archive.file_exists(shape.path),
			"Export includes the approved image and generated shape"):
		var exported: Dictionary = JSON.parse_string(archive.read_file("chart.json").get_string_from_utf8())
		_check(exported.basic.bgPath == image_path and exported.basic.chartName == "MCP 测试谱面"
			and exported.anim_rect_slots[0][0].image.path == shape.path, "Playable chart JSON references the exported assets")
	archive.close()
	chart.undo()
	_check(chart.preview_bg_image_path == old_background and chart.chart_info.chartName == old_name
		and is_equal_approx(chart.bpm, old_bpm) and not chart.events.has(lyric_id), "Undo restores all changed chart fields together")
	chart.redo()
	_check(chart.preview_bg_image_path == image_path and chart.events.has(lyric_id), "Redo restores the artwork and lyric")
	call = await _tool("list_project_artwork", {})
	_check(call.result.structuredContent.items.any(func(item: Dictionary): return item.project_path == image_path),
		"Approved image is discoverable in the project library")
	call = await _tool("add_artwork", {"project_path": image_path})
	_check(not call.result.isError and call.result.structuredContent.has("artwork_id"), "Register an existing project artwork without copying it")
	call = await _tool("delete_text_event", {"id": lyric_id})
	_check(not call.result.isError and chart.events.has(lyric_id), "Text deletion also stays in the draft")

func _require(condition: bool, message: String) -> bool:
	_check(condition, message)
	return condition

func _finish_when_visible(approve: bool) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while (not is_instance_valid(_mcp._approval) or not _mcp._approval.visible) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(is_instance_valid(_mcp._approval) and _mcp._approval.visible and _mcp._approval.exclusive, "Finish opens an exclusive approval dialog")
	if is_instance_valid(_mcp._approval):
		if approve:
			_mcp._approval.confirmed.emit()
		else:
			_mcp._approval.hide()

func _tool(name: String, arguments: Dictionary) -> Dictionary:
	return await _rpc("tools/call", {"name": name, "arguments": arguments})

func _rpc(method: String, params := {}, extra: Array[String] = [], authorization := "auto") -> Dictionary:
	_next_id += 1
	return await _request({"jsonrpc": "2.0", "id": _next_id, "method": method, "params": params},
		extra, _mcp._token if authorization == "auto" else authorization)

func _request(body: Dictionary, extra: Array[String] = [], token := "auto", method := HTTPClient.METHOD_POST) -> Dictionary:
	var client := HTTPRequest.new()
	client.timeout = 8
	root.add_child(client)
	var headers := PackedStringArray(["Content-Type: application/json", "Accept: application/json, text/event-stream"])
	headers.append_array(extra)
	if not token.is_empty():
		headers.append("Authorization: Bearer " + (_mcp._token if token == "auto" else token))
	if not _session.is_empty():
		headers.append("Mcp-Session-Id: " + _session)
		headers.append("MCP-Protocol-Version: " + VERSION)
	var started := client.request(_mcp._server.endpoint(), headers, method, JSON.stringify(body) if method == HTTPClient.METHOD_POST else "")
	if started != OK:
		client.queue_free()
		return {"code": 0, "headers": [], "result": {}}
	var response: Array = await client.request_completed
	client.queue_free()
	var decoded: Variant = JSON.parse_string(response[3].get_string_from_utf8()) if response[3].size() > 0 else {}
	return {"code": response[1], "headers": response[2], "result": decoded.get("result", {}) if decoded is Dictionary else {}}
