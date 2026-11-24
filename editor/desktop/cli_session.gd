extends RefCounted

const Plan := preload("res://desktop/auto_chart_plan.gd")
const References := preload("res://desktop/reference_library.gd")
const RenderPreview := preload("res://desktop/render_preview.gd")
const Video := preload("res://desktop/video_export.gd")
const Agent := preload("res://desktop/chart_agent.gd")

static func run(workspace: Node, request_file: String, response_file: String) -> void:
	var request: Variant = JSON.parse_string(FileAccess.get_file_as_string(request_file))
	var response := {"error": "CLI 请求无效。"}
	if request is Dictionary:
		response = await _execute(workspace, request)
	var file := FileAccess.open(response_file, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(response))
		file.close()
	_cleanup(workspace.chart)
	workspace.get_tree().quit(1 if response.has("error") or not file else int(response.get("exit_code", 0)))

static func _execute(w: Node, request: Dictionary) -> Dictionary:
	var action := str(request.get("command", ""))
	if action == "references":
		if request.has("import"):
			return References.import_local(request["import"], request.get("allow_images", false), request.get("allow_audio", false))
		if request.has("id"):
			return Agent._reference_query(request)
		return References.list_references(str(request.get("query", "")), str(request.get("difficulty", "")), 0, 64)
	var source := str(request.get("input", ""))
	if not FileAccess.file_exists(source) or not w._open_chart_file(source):
		return {"error": "无法打开工程。"}
	var chart: Node = w.chart
	var plan := Plan.new(chart, str(chart.chart_info.get("difficulty", "HD")).to_upper().left(2))
	var target := str(request.get("output", ""))
	match action:
		"inspect":
			return {"chart": chart.chart_info, "duration_ms": plan.duration_ms, "audio_filename": chart.audio_path.get_file(),
				"note_count": plan.notes.size(), "event_count": chart.events.size(), "tempo": chart.bpm_segments, "tracks": plan.track_count}
		"validate":
			for id: int in plan.notes:
				plan.edited[id] = true
			var validation := plan.check_conflicts()
			var missing: Array[String] = []
			for asset: String in [chart.audio_path, chart.preview_bg_image_path, chart.preview_mask_image_path]:
				if asset.is_empty() or not FileAccess.file_exists(chart.resolve_full_path(asset)):
					missing.append(asset if not asset.is_empty() else "(未配置)")
			validation["missing_assets"] = missing
			validation["exit_code"] = 3 if validation.error_count > 0 or not missing.is_empty() else 0
			return validation
		"pitch":
			return await _pitch(w, request)
		"run", "export":
			if source.get_extension().to_lower() != "zip":
				return {"error": "写出工程需要 ZIP 输入，以便只打包原工程素材。"}
			if target.get_extension().to_lower() != "zip":
				return {"error": "输出须为 .zip。"}
			var edited := {}
			if action == "run":
				if request.has("source"):
					var pitch_result := await _pitch(w, request)
					if pitch_result.has("error"):
						return pitch_result
				edited = await w.scripts.run_file(str(request.get("script", "")))
				if edited.has("error"):
					return edited
			var missing: String = w.sidebar._check_required_fields()
			if not missing.is_empty():
				return {"error": missing}
			var saved := _pack(chart, target)
			saved.merge(edited, false)
			return saved
		"render":
			return await _render(w, request, target)
	return {"error": "未知 CLI 命令。"}

static func _render(w: Node, request: Dictionary, target: String) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {"error": "渲染需要可用的图形驱动。"}
	var chart: Node = w.chart
	if request.has("frame_ms"):
		var time := float(request.frame_ms)
		if (target.get_extension().to_lower() != "png" or time < 0
				or time > maxf(chart.audio_duration_ms + chart.audio_delay_ms, chart.latest_content_time_ms())):
			return {"error": "请指定工程范围内的时间和 PNG 输出文件。"}
		var scene := RenderPreview.mount(w, chart, Video.RESOLUTION)
		await w.get_tree().process_frame
		var image := await RenderPreview.frame(scene, time)
		scene.viewport.queue_free()
		if image == null or image.is_empty() or image.save_png(target) != OK:
			return {"error": "无法保存渲染帧。"}
	else:
		if target.get_extension().to_lower() != "mp4":
			return {"error": "视频输出须为 .mp4。"}
		w._video.progress.connect(func(done: int, total: int): printerr("render ", done, "/", total))
		w._video.render.call_deferred(chart, w.analysis._ffmpeg(w.preferences.ffmpeg_path), target,
			int(request.get("from_ms", 0)), int(request.get("to_ms", -1)))
		var error: String = await w._video.finished
		if not error.is_empty():
			return {"error": error}
	return {"output": target}

static func _pitch(w: Node, request: Dictionary) -> Dictionary:
	var engine := str(request.get("source", "essentia"))
	var key := "vocal_pitch" if engine == "rmvpe" else "melody"
	var result: Dictionary = await w._analyze_for_agent({"engine": engine, "tasks": [key]})
	if result.has("error") or not result.has(key):
		return {"error": str(result.get("error", result.get("task_errors", {}).get(key, "未获得音高结果。")))}
	var data: Array = result[key]
	return {"source": engine, "sample_count": data.size(), "items": data.slice(0, 64)}

static func _pack(chart: Node, target: String) -> Dictionary:
	var file := FileAccess.open(chart.get_root_dir().path_join(chart._root_json_name), FileAccess.WRITE)
	if not file or not file.store_string(JSON.stringify(chart.to_export_dict())):
		return {"error": "无法写入工作目录的谱面 JSON。"}
	file.close()
	var temporary := target.get_base_dir().path_join(".revelation-%d-%d.zip" % [OS.get_process_id(), Time.get_ticks_usec()])
	if not chart.export_zip_to(temporary) or FileAccess.file_exists(target) or DirAccess.rename_absolute(temporary, target) != OK:
		DirAccess.remove_absolute(temporary)
		return {"error": "无法写出工程压缩包。"}
	return {"output": target}

static func _cleanup(chart: Node) -> void:
	if not chart.restrict_imported_assets:
		return
	var prefix := ProjectSettings.globalize_path("user://zip_imports").simplify_path() + "/"
	var current := ProjectSettings.globalize_path(chart.get_root_dir()).simplify_path()
	if current.begins_with(prefix):
		var first := current.trim_prefix(prefix).get_slice("/", 0)
		if not first.is_empty() and first != "." and first != "..":
			chart._delete_dir_recursive_abs(prefix + first)
