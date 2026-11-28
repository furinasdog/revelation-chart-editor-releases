extends Node

const DialogLayout := preload("res://desktop/dialog_layout.gd")

const Agent := preload("res://desktop/chart_agent.gd")
const AgentContext := preload("res://desktop/agent_context.gd")
const CONFIG_PATH := "user://chart_agent.cfg"
const SERIES := ["beats", "downbeats", "onsets", "accents", "tempo_curve", "melody", "vocal_pitch", "emotions"]
const COVER_LIMIT := 6
const COVER_PREVIEW_BYTES := 21000
const ACTION_LABELS := {
	"get_bpm": "读取 BPM", "get_beats": "读取节奏标记", "get_melody": "读取主旋律", "estimate_mood": "读取段落强度",
	"get_emotions": "读取 Music2Emo 分段情绪",
	"list_notes": "读取已有音符", "add_notes": "写入音符", "delete_notes": "删除音符",
	"move_notes": "移动音符", "set_positions": "调整音符位置", "seed_pattern": "生成节奏底稿",
	"resize_holds": "调整长键时长",
	"check_conflicts": "检查制谱冲突", "get_animation_cues": "读取动画段落参考",
	"list_animation_layers": "读取动画层", "get_cover": "读取曲绘",
	"create_solid_mask": "生成纯色蒙版", "set_mask_cue": "安排蒙版切换", "add_mask_reveal": "添加曲绘揭示",
	"view_rendered_frames": "查看草稿渲染画面",
	"add_animation_layer": "写入动画层", "remove_animation_layer": "移除动画层", "finish": "提交草稿",
}

var _workspace: Node
var _settings := {"url": "", "key": "", "model": ""}
var _settings_dialog: ConfirmationDialog

func setup(workspace: Node) -> void:
	_workspace = workspace
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)
	_settings.url = str(config.get_value("agent", "url", ""))
	_settings.key = str(config.get_value("agent", "key", ""))
	_settings.model = str(config.get_value("agent", "model", ""))

func apply_theme(theme: Theme) -> void:
	if is_instance_valid(_settings_dialog):
		_settings_dialog.theme = theme

func open_settings() -> void:
	if not _workspace.features_enabled():
		return
	if is_instance_valid(_settings_dialog):
		_settings_dialog.queue_free()
	_settings_dialog = _dialog("Agent 设置", "保存设置")
	var body := VBoxContainer.new()
	_settings_dialog.add_child(body)
	var url := _field(body, "API URL", _settings.url, "https://服务地址/v1")
	var key := _field(body, "API Key", _settings.key, "输入 API Key")
	key.secret = true
	var model := _field(body, "模型名称", _settings.model, "输入服务端提供的模型名称")
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "DeepSeek 示例：地址 https://api.deepseek.com，模型 deepseek-flash。也可填写其他兼容服务。API Key 保存在本机用户目录，清空并保存可删除。"
	body.add_child(hint)
	_settings_dialog.get_ok_button().disabled = true
	var validate := func(_value: String):
		_settings_dialog.get_ok_button().disabled = (Agent.endpoint_from_url(url.text).is_empty()
			or model.text.strip_edges().is_empty() or "\n" in key.text or "\r" in key.text)
	url.text_changed.connect(validate)
	key.text_changed.connect(validate)
	model.text_changed.connect(validate)
	validate.call("")
	_settings_dialog.confirmed.connect(func():
		_settings = {"url": url.text.strip_edges(), "key": key.text.strip_edges(), "model": model.text.strip_edges()}
		var config := ConfigFile.new()
		config.set_value("agent", "url", _settings.url)
		config.set_value("agent", "model", _settings.model)
		if not _settings.key.is_empty():
			config.set_value("agent", "key", _settings.key)
		if config.save(CONFIG_PATH) != OK:
			_workspace._notify.call_deferred("无法保存 Agent 设置。本次运行仍可使用。"))
	DialogLayout.present(_settings_dialog, Vector2i(620, 305))

func _find_cover() -> String:
	var chart: Node = _workspace.chart
	var path: String = chart.preview_bg_image_path
	var image: Image = chart.resolve_image(path)
	if image == null or image.is_empty():
		return ""
	if path == "background.png" and image.get_size() == Vector2i(256, 144):
		var blank := Image.create_empty(256, 144, false, Image.FORMAT_RGB8)
		blank.fill(Color("#192433"))
		image.convert(Image.FORMAT_RGB8)
		if image.get_data() == blank.get_data():
			return ""
	return path

func _project_artwork(default_cover: String) -> Array[String]:
	var paths: Array[String] = []
	if not default_cover.is_empty():
		paths.append(default_cover)
	var chart: Node = _workspace.chart
	if not chart.has_root_dir:
		return paths
	for folder: String in ["", "otherImage"]:
		var directory: String = chart.get_root_dir().path_join(folder)
		if not DirAccess.dir_exists_absolute(directory):
			continue
		for filename: String in DirAccess.get_files_at(directory):
			var path := folder.path_join(filename)
			if (filename.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp"]
					and path not in paths and filename not in ["background.png", "black_cover.png"]
					and not filename.begins_with("agent-mask-") and not filename.begins_with("agent-shape_")):
				paths.append(path)
	return paths

func prepare_project_artwork() -> Array[Dictionary]:
	var images: Array[Dictionary] = []
	for path: String in _project_artwork(_find_cover()).slice(0, COVER_LIMIT):
		var image := _prepare_cover(path)
		if not image.is_empty():
			images.append(image)
	return images

func _prepare_cover(path: String) -> Dictionary:
	var image: Image = _workspace.chart.resolve_image(path)
	if image == null or image.is_empty() or path.is_absolute_path():
		return {}
	return prepare_artwork_image(image, path)

static func prepare_artwork_image(image: Image, path: String) -> Dictionary:
	var original := Vector2(image.get_size())
	var scale := minf(1.0, 640.0 / maxf(original.x, original.y))
	if scale < 1.0:
		image.resize(maxi(roundi(original.x * scale), 1), maxi(roundi(original.y * scale), 1), Image.INTERPOLATE_LANCZOS)
	var visibility := _cover_visibility(image)
	image.convert(Image.FORMAT_RGB8)
	var jpeg := image.save_jpg_to_buffer(0.78)
	while jpeg.size() > COVER_PREVIEW_BYTES:
		image.resize(maxi(1, roundi(image.get_width() * 0.75)), maxi(1, roundi(image.get_height() * 0.75)), Image.INTERPOLATE_LANCZOS)
		jpeg = image.save_jpg_to_buffer(0.72)
	if jpeg.is_empty():
		return {}
	return {"path": path, "size": original, "visibility": visibility,
		"data_url": "data:image/jpeg;base64," + Marshalls.raw_to_base64(jpeg)}

static func _cover_visibility(image: Image) -> Dictionary:
	var samples := 0
	var bright := 0
	var sum := 0.0
	for row in range(9):
		for column in range(13):
			var x := roundi(lerpf(0.15, 0.85, column / 12.0) * (image.get_width() - 1))
			var y := roundi(lerpf(0.17, 0.83, row / 8.0) * (image.get_height() - 1))
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.25:
				continue
			var luminance := pixel.get_luminance()
			samples += 1
			sum += luminance
			bright += int(luminance >= 0.68)
	var ratio := float(bright) / maxi(samples, 1)
	var average := sum / maxi(samples, 1)
	return {"bright_playfield": ratio >= 0.24 or average >= 0.59,
		"bright_fraction": snappedf(ratio, 0.01), "average_luminance": snappedf(average, 0.01)}

static func music_for_agent(chart: Node, raw: Dictionary, duration_ms: int) -> Dictionary:
	var offset := roundi(chart.audio_delay_ms)
	var music := {"manual_bpm": chart.bpm, "source": raw.duplicate()}
	for key: String in SERIES:
		var series := []
		for value: Variant in raw.get(key, []):
			var time := roundi(value.time_ms if value is Dictionary else value) + offset
			if key == "emotions" and value is Dictionary:
				var end := clampi(roundi(value.end_ms) + offset, 0, duration_ms)
				if end > maxi(time, 0):
					var segment: Dictionary = value.duplicate()
					segment.time_ms = maxi(time, 0)
					segment.end_ms = end
					series.append(segment)
				continue
			if time < 0 or time > duration_ms:
				continue
			if value is Dictionary:
				var shifted: Dictionary = value.duplicate()
				shifted.time_ms = time
				series.append(shifted)
			else:
				series.append(time)
		music[key] = series
	return music

func _estimate_mood() -> Array:
	var chart: Node = _workspace.chart
	var waveform: PackedFloat32Array = chart.audio_waveform
	var bucket_ms := maxf(chart.audio_waveform_bucket_ms, 1.0)
	var offset := roundi(chart.audio_delay_ms)
	var sample_count := maxi(roundi(12000.0 / bucket_ms), 1)
	var sections: Array[Dictionary] = []
	var peak := 0.0
	for start in range(0, waveform.size(), sample_count):
		var stop := mini(start + sample_count, waveform.size())
		var energy := 0.0
		for index in range(start, stop):
			energy += waveform[index] * waveform[index]
		energy = sqrt(energy / (stop - start))
		peak = maxf(energy, peak)
		sections.append({"time_ms": maxi(0, roundi(start * bucket_ms) + offset),
			"to_ms": maxi(0, roundi(stop * bucket_ms) + offset), "energy": energy})
	for section: Dictionary in sections:
		var intensity: float = section.energy / maxf(peak, 0.01)
		section["relative_intensity"] = snappedf(intensity, 0.01)
		section["estimate"] = "强烈" if intensity >= 0.72 else ("平稳" if intensity >= 0.38 else "舒缓")
		section["source"] = "相对响度估计"
	return sections

func _action_caption(name: String, fallback := "未知动作") -> String:
	if AgentContext.TOOLS.has(name):
		return AgentContext.TOOLS[name][0]
	if Agent.ProfileTools.TOOLS.has(name):
		return Agent.ProfileTools.TOOLS[name][0]
	return ACTION_LABELS.get(name, fallback)

func _effective_settings() -> Dictionary:
	var result := _settings.duplicate()
	for pair: Array in [["url", "LLM_API_URL"], ["key", "LLM_API_KEY"], ["model", "LLM_MODEL"]]:
		if str(result[pair[0]]).is_empty():
			result[pair[0]] = OS.get_environment(pair[1])
	return result

func _valid_settings(values: Dictionary) -> bool:
	return not Agent.endpoint_from_url(str(values.url)).is_empty() and not str(values.key).strip_edges().is_empty() \
		and not str(values.model).strip_edges().is_empty()

func _dialog(title: String, confirm: String) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.ok_button_text = confirm
	dialog.cancel_button_text = "取消"
	dialog.theme = _workspace._ui_theme
	add_child(dialog)
	return dialog

func _field(body: VBoxContainer, label_text: String, value: String, placeholder: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	body.add_child(label)
	var field := LineEdit.new()
	field.text = value
	field.placeholder_text = placeholder
	body.add_child(field)
	return field
