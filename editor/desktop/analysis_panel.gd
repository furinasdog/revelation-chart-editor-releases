extends "res://desktop/settings_scroll.gd"

const Analysis := preload("res://desktop/analysis.gd")

signal run_requested()
signal spectrum_requested()
signal audition_requested()
signal reference_requested()
signal tempo_write_requested()
signal loop_requested()
signal accent_sensitivity_changed(value: int)

const ENGINE_NAMES := {
	"native": "Beat This!（内置）",
	"madmom": "madmom（原生）",
	"essentia": "Essentia",
}
const TASK_NAMES := {
	"beats": "拍点", "downbeats": "小节重拍", "onsets": "起音",
	"accents": "力度重音", "tempo": "速度曲线", "melody": "主旋律",
}
const MODELS := {
	"native": {"default": "Beat This! Final 0"},
	"madmom": {"default": "循环节拍网络＋卷积起音", "recurrent": "循环节拍网络＋循环起音"},
	"essentia": {"multifeature": "多特征节拍", "degara": "Degara 节拍"},
}

var _engine: OptionButton
var _tempo: OptionButton
var _model: OptionButton
var _mapping: OptionButton
var _tasks := {}
var _cache_field: LineEdit
var _run: Button
var _spectrum: Button
var _summary: Label
var _accent_slider: HSlider
var _accent_value: Label
var _accent_summary: Label
var _tempo_note: Label
var _runtime_settings: VBoxContainer
var _prefs: Node
var _chart: Node
var _preset: OptionButton
var _settings_toggle: CheckButton
var _audition_button: Button
var _write_button: Button
var _reference_button: Button

func setup(preferences: Node, chart: Node) -> void:
	_prefs = preferences
	_chart = chart
	var saved: Dictionary = preferences.analysis_options
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 6)
	add_child(form)
	_preset = _choice(form, "分析目标", {"rhythm": "拍点与速度", "drums": "鼓点与起音", "melody": "主旋律"},
		str(saved.get("preset", "rhythm")))
	_settings_toggle = CheckButton.new()
	_settings_toggle.text = "分析设置"
	form.add_child(_settings_toggle)
	var advanced := VBoxContainer.new()
	form.add_child(advanced)
	advanced.hide()
	_settings_toggle.toggled.connect(func(enabled: bool): advanced.visible = enabled)
	_engine = _choice(advanced, "抓音引擎", ENGINE_NAMES, str(saved.get("engine", "native")))
	_model = _choice(advanced, "抓音模型", {}, "")
	var tempo_names := ENGINE_NAMES.duplicate()
	tempo_names["native"] = "内置速度算法"
	_tempo = _choice(advanced, "速度来源", tempo_names, str(saved.get("tempo_engine", "native")))
	_tempo_note = _text(advanced, "")
	_text(advanced, "推理内容")
	var checks := HFlowContainer.new()
	advanced.add_child(checks)
	var selected: Variant = saved.get("tasks", ["beats", "downbeats", "tempo"])
	for key: String in TASK_NAMES:
		var check := CheckBox.new()
		check.text = TASK_NAMES[key]
		check.button_pressed = selected is Array and key in selected
		check.toggled.connect(func(_enabled: bool): _save(); _refresh_actions())
		checks.add_child(check)
		_tasks[key] = check
	_mapping = _choice(form, "映射到时间轴", {
		"beats": TASK_NAMES.beats, "downbeats": TASK_NAMES.downbeats, "onsets": TASK_NAMES.onsets,
		"accents": TASK_NAMES.accents,
	}, chart.analysis_mapping)
	_mapping.item_selected.connect(func(_index: int): _chart.set_analysis_mapping(_value(_mapping)))
	_summary = _text(form, "")
	_build_accent_slider(form, int(saved.get("accent_sensitivity", Analysis.DEFAULT_ACCENT_SENSITIVITY)))
	var actions := HFlowContainer.new()
	form.add_child(actions)
	_run = Button.new()
	_run.text = "重新推理"
	_run.pressed.connect(run_requested.emit)
	actions.add_child(_run)
	_spectrum = Button.new()
	_spectrum.text = "生成频谱"
	_spectrum.pressed.connect(spectrum_requested.emit)
	actions.add_child(_spectrum)
	_audition_button = _action(actions, "试听抓取结果", audition_requested)
	_action(actions, "循环选区", loop_requested)
	_reference_button = _action(actions, "用作编辑参考", reference_requested)
	_write_button = _action(actions, "写入谱面速度", tempo_write_requested)
	_runtime_settings = VBoxContainer.new()
	advanced.add_child(_runtime_settings)
	_text(_runtime_settings, "madmom 首次推理会下载并校验所选任务的非商业许可模型。")
	_text(_runtime_settings, "madmom 模型缓存路径")
	_cache_field = LineEdit.new()
	_cache_field.placeholder_text = "使用默认缓存目录"
	_cache_field.text = str(saved.get("madmom_model_cache", ""))
	_cache_field.text_changed.connect(func(_value: String): _save())
	_runtime_settings.add_child(_cache_field)
	_engine.item_selected.connect(func(_index: int):
		_update_engine("")
		_save()
	)
	_model.item_selected.connect(func(_index: int): _save())
	_tempo.item_selected.connect(func(_index: int):
		_update_engines_note()
		_save()
	)
	_update_engine(str(saved.get("model", "")))
	_preset.item_selected.connect(_apply_preset)

func expand_settings() -> void:
	_settings_toggle.button_pressed = true

func _build_accent_slider(form: VBoxContainer, sensitivity: int) -> void:
	var row := HBoxContainer.new()
	form.add_child(row)
	_accent_value = Label.new()
	_accent_value.custom_minimum_size.x = 140
	row.add_child(_accent_value)
	_accent_slider = HSlider.new()
	_accent_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accent_slider.max_value = 100
	_accent_slider.step = 1
	_accent_slider.value = sensitivity
	_accent_slider.tooltip_text = "数值越高，保留的力度重音越多。50% 为默认值。"
	row.add_child(_accent_slider)
	_accent_summary = _text(form, "")
	_accent_slider.value_changed.connect(func(value: float):
		_update_accent_value()
		_save()
		accent_sensitivity_changed.emit(roundi(value)))

func _update_accent_value() -> void:
	_accent_value.text = "力度重音灵敏度 %d%%" % roundi(_accent_slider.value)

func _action(row: Control, text: String, requested: Signal) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(requested.emit)
	row.add_child(button)
	return button

func _apply_preset(_index: int) -> void:
	var key := _value(_preset)
	var choices := {
		"rhythm": ["native", ["beats", "downbeats", "tempo"]],
		"drums": ["madmom", ["onsets", "accents"]],
		"melody": ["essentia", ["melody"]],
	}
	var proposed: Array = choices[key]
	_select(_engine, proposed[0])
	_update_engine("")
	for task: String in _tasks:
		_tasks[task].set_pressed_no_signal(task in proposed[1])
	_save()
	_refresh_actions()

func options() -> Dictionary:
	var selected: Array = []
	for key: String in _tasks:
		if _tasks[key].button_pressed:
			selected.append(key)
	var result := {"preset": _value(_preset), "engine": _value(_engine), "tempo_engine": _value(_tempo),
		"model": _value(_model), "tasks": selected, "madmom_model_cache": _cache_field.text.strip_edges(),
		"accent_sensitivity": roundi(_accent_slider.value)}
	return result

func update_status(has_audio: bool, busy: bool, data: Dictionary, mapping: String) -> void:
	_select(_mapping, mapping)
	var count: int = data.get(mapping, []).size()
	_summary.text = "%s · %d 个标记" % [TASK_NAMES[mapping], count]
	_update_accent_status(has_audio, busy, data)
	_spectrum.disabled = not has_audio or busy
	_audition_button.disabled = not has_audio or count == 0
	_write_button.disabled = data.get("tempo_curve", []).is_empty()
	_reference_button.disabled = count == 0 and _write_button.disabled
	set_meta("available", has_audio and not busy)
	_refresh_actions()

func _update_accent_status(has_audio: bool, busy: bool, data: Dictionary) -> void:
	if not busy:
		var preferred: int = _prefs.analysis_options.get("accent_sensitivity", Analysis.DEFAULT_ACCENT_SENSITIVITY)
		_accent_slider.set_value_no_signal(data.get("accent_sensitivity", preferred))
	_update_accent_value()
	var filter: Dictionary = data.get("accent_filter", {})
	var source: String = filter.get("source", "onsets" if not data.get("onsets", []).is_empty() else "beats")
	var count: int = filter.get("candidate_count", data.get(source, []).size())
	_accent_slider.editable = has_audio and not busy and count > 0
	if not has_audio or count == 0:
		_accent_summary.text = "先分析起音、拍点或力度重音，再拖动滑块筛选。"
	else:
		_accent_summary.text = "%d 个力度重音 · 复用已有的 %d 个%s" % [data.get("accents", []).size(), count, TASK_NAMES[source]]

func _update_engine(model: String) -> void:
	var engine := _value(_engine)
	_fill(_model, MODELS[engine], model)
	for key: String in _tasks:
		var check: CheckBox = _tasks[key]
		var supported: bool = key == "tempo" or key in Analysis.CAPTURE_TASKS[engine]
		check.disabled = not supported
		if not supported:
			check.set_pressed_no_signal(false)
	_update_engines_note()
	_refresh_actions()

func _update_engines_note() -> void:
	var engine := _value(_engine)
	var tempo := _value(_tempo)
	_runtime_settings.visible = engine == "madmom" or tempo == "madmom"
	var marker_name := "拍点" if engine == "native" else "起音"
	_tempo_note.text = "力度重音从%s中筛选附近能量明显增强的位置。勾选「%s」可查看筛选前的标记。" % [marker_name, marker_name]

func _refresh_actions() -> void:
	_run.disabled = not get_meta("available", false) or options().tasks.is_empty()

func _save() -> void:
	_prefs.analysis_options = options()
	_prefs.save()

func _choice(form: VBoxContainer, caption: String, entries: Dictionary, active: String) -> OptionButton:
	_text(form, caption)
	var control := OptionButton.new()
	control.fit_to_longest_item = false
	form.add_child(control)
	_fill(control, entries, active)
	return control

func _fill(control: OptionButton, entries: Dictionary, active: String) -> void:
	control.clear()
	for key: String in entries:
		control.add_item(entries[key])
		control.set_item_metadata(control.item_count - 1, key)
	if control.item_count > 0:
		control.select(0)
		_select(control, active)

func _select(control: OptionButton, key: String) -> void:
	for index in range(control.item_count):
		if control.get_item_metadata(index) == key:
			control.select(index)
			return

func _value(control: OptionButton) -> String:
	return str(control.get_selected_metadata())

func _text(parent: Control, content: String) -> Label:
	var label := Label.new()
	label.text = content
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label
