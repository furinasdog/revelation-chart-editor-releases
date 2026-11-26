extends ScrollContainer

const CaptureCatalog := preload("res://desktop/capture_catalog.gd")
const StemCache := preload("res://desktop/stem_cache.gd")
const SOURCE_LABELS := ["完整音频", "人声分轨", "鼓组分轨", "贝斯分轨", "其他伴奏"]

signal run_requested()
signal selection_changed()
signal source_menu_opened()

var selected_id := "beat"
var selected_stem := ""
var last_capture_source := ""
var showing_capture_lines := true
var _choices := {}
var _states := {}
var _run: Button
var _sensitivity: HSlider
var _percentage: Label
var _summary: Label
var _source: OptionButton
var _prefs: Node
var _chart: Node

func setup(preferences: Node, chart: Node, stem_monitor: Control) -> void:
	_prefs = preferences
	_chart = chart
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	follow_focus = true
	var content := VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	add_child(content)
	var title := Label.new()
	title.text = "采音内容"
	content.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 84
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)
	var group := ButtonGroup.new()
	for id: String in CaptureCatalog.ENTRIES:
		var row := HBoxContainer.new()
		list.add_child(row)
		var choice := CheckBox.new()
		choice.text = CaptureCatalog.ENTRIES[id].label
		choice.tooltip_text = choice.text
		choice.button_group = group
		choice.size_flags_horizontal = SIZE_EXPAND_FILL
		choice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		choice.set_pressed_no_signal(id == selected_id)
		choice.pressed.connect(select.bind(id))
		row.add_child(choice)
		_choices[id] = choice
		var state := Label.new()
		state.add_theme_font_size_override("font_size", 12)
		row.add_child(state)
		_states[id] = state

	var caption := HBoxContainer.new()
	content.add_child(caption)
	var label := Label.new()
	label.text = "灵敏度"
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	caption.add_child(label)
	_percentage = Label.new()
	caption.add_child(_percentage)
	_sensitivity = HSlider.new()
	_sensitivity.max_value = 100
	_sensitivity.step = 1
	var saved: Dictionary = _prefs.analysis_options
	# Earlier versions stored an accent-only threshold for another algorithm.
	_sensitivity.value = saved.get("sensitivity", CaptureCatalog.DEFAULT_SENSITIVITY)
	_percentage.text = "%d%%" % roundi(_sensitivity.value)
	_sensitivity.value_changed.connect(_on_sensitivity_changed)
	content.add_child(_sensitivity)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_summary)
	var source_row := HBoxContainer.new()
	content.add_child(source_row)
	var source_label := Label.new()
	source_label.text = "采音源"
	source_row.add_child(source_label)
	_source = OptionButton.new()
	_source.accessibility_name = source_label.text
	_source.tooltip_text = "选择用于采音的音轨。分轨完成后可选择各分轨。"
	_source.size_flags_horizontal = SIZE_EXPAND_FILL
	_source.fit_to_longest_item = false
	_source.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for source_name: String in SOURCE_LABELS:
		_source.add_item(source_name)
	_source.item_selected.connect(_select_source)
	_source.get_popup().about_to_popup.connect(source_menu_opened.emit)
	source_row.add_child(_source)
	set_stems_ready(false)
	_run = Button.new()
	_run.pressed.connect(run_requested.emit)
	content.add_child(_run)
	content.add_child(stem_monitor)
	update_status(false, false, {}, "")

func select(id: String) -> void:
	if not _choices.has(id):
		return
	_choices[id].button_pressed = true
	if id != selected_id:
		selected_id = id
		selection_changed.emit()

func set_stems_ready(ready: bool) -> void:
	for index in range(1, _source.item_count):
		_source.set_item_disabled(index, not ready)
	if not ready:
		reset_source()

func reset_source() -> void:
	_source.select(0)
	selected_stem = ""

func _select_source(index: int) -> void:
	if _source.disabled or index < 0 or index >= _source.item_count or _source.is_item_disabled(index):
		return
	var stem: String = StemCache.STEMS[index - 1] if index > 0 else ""
	if stem != selected_stem:
		_source.select(index)
		selected_stem = stem
		selection_changed.emit()

func _on_sensitivity_changed(value: float) -> void:
	_percentage.text = "%d%%" % roundi(value)
	_prefs.analysis_options["sensitivity"] = roundi(value)
	_prefs.save()

func options() -> Dictionary:
	var request := CaptureCatalog.options(selected_id, roundi(_sensitivity.value))
	request["madmom_model_cache"] = _prefs.analysis_options.get("madmom_model_cache", "")
	request["capture_stem"] = selected_stem
	return request

func update_status(has_audio: bool, busy: bool, cache_status: Dictionary, applied_id: String, active_capture_id := "") -> void:
	var cached: bool = cache_status.get(selected_id, false)
	for id: String in _choices:
		_choices[id].disabled = busy
		var state := ""
		if busy and id == active_capture_id:
			state = "采音中"
		elif id == applied_id:
			state = "已应用"
		elif cache_status.get(id, false):
			state = "有缓存"
		elif id == selected_id and has_audio:
			state = "待采音"
		_states[id].text = state
	var task: String = CaptureCatalog.ENTRIES[selected_id].task
	_sensitivity.editable = has_audio and not busy and task != "tempo"
	_source.disabled = not has_audio or busy
	_run.text = "采音中…" if busy and selected_id == active_capture_id else ("应用" if cached else "采音")
	_run.disabled = not has_audio or busy
	if not has_audio:
		_summary.text = "请先导入音频。"
	elif not busy and selected_id == applied_id:
		_summary.text = _applied_summary(task)
	else:
		_summary.text = ""
	_summary.visible = not _summary.text.is_empty()

func _applied_summary(task: String) -> String:
	var source: String = {"cache": "已应用缓存", "inference": "本次采音"}.get(last_capture_source, "已应用")
	var data: Dictionary = _chart.rhythm_analysis
	if task == "tempo":
		var curve: Array = data.get("tempo_curve", [])
		if curve.is_empty():
			return source + " · 未取得 BPM。"
		return "%s · %.1f BPM，共 %d 个速度采样。" % [source, curve[0].bpm, curve.size()]
	var markers: Array = data.get("capture_markers", [])
	var total: int = data.get(task, []).size()
	if task == "accents":
		total = data.get("accent_filter", {}).get("points", data.get(task, [])).size()
	var result := "%s · 保留 %d / %d 个%s。" % [source, markers.size(), total, "音高采样点" if task == "melody" else "标记"]
	if not markers.is_empty():
		var index := markers.bsearch(-float(_chart.audio_delay_ms))
		if index < markers.size():
			var first := roundi(float(markers[index]) + _chart.audio_delay_ms)
			result += "首个 %d:%02d.%02d。" % [first / 60000, (first / 1000) % 60, (first % 1000) / 10]
		if not showing_capture_lines:
			result += "切换为「自动采音线」可查看。"
	if markers.size() < total and markers.size() * 10 <= total and int(data.get("capture_sensitivity", CaptureCatalog.DEFAULT_SENSITIVITY)) < 100:
		result += "可调高灵敏度，再点「应用」。"
	if task == "beats" and not _chart.has_project_bpm:
		result += "未取得工程 BPM，请选择 BPM 并采音。"
	return result
