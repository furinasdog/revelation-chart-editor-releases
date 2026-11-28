extends Control

const DialogLayout := preload("res://desktop/dialog_layout.gd")

const EditorTheme := preload("res://desktop/editor_theme.gd")
const Chart := preload("res://main/chart_data.gd")
const Grid := preload("res://main/grid_canvas.gd")
const GAP := 12.0

var _workspace: Node
var _chooser: Window
var _setup_surface: ColorRect
var _remember_choice := false
var _panel: PanelContainer
var _progress: Label
var _title: Label
var _instruction: Label
var _task_status: Label
var _action: Button
var _back: Button
var _next: Button
var _skip_step: Button
var _steps: Array[Dictionary] = []
var _index := 0
var _highlight := Rect2()
var _first: VBoxContainer
var _second: VBoxContainer
var _scheme: OptionButton
var _theme: OptionButton
var _setup_next: Button
var _setup_back: Button
var _experience := "beginner"
var _original_theme := "system"
var _scheme_explicit := false
var _sample: Control
var _comparison: Label
var _guide_kind := ""
var _original_capture := ""
var _original_reference := Chart.ReferenceMode.TRADITIONAL
var _original_background_track := false
var _heard := false
var _exported := false
var _active_task := ""
var _practice_note_placed := false
var _practice_note_moved := false
var _note_positions := {}

func attach(workspace: Node) -> void:
	_workspace = workspace
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90
	_build_chooser()
	_build_panel()
	_workspace.sidebar.playable_chart_exported.connect(func(_path: String): _exported = true)
	_workspace.chart.note_added.connect(func(id: int):
		var kind: int = _workspace.chart.notes[id].type
		if (_active_task == "place" and kind == 0) or (_active_task == "slide" and kind == 1):
			_practice_note_placed = true)
	_workspace.chart.note_updated.connect(_check_practice_move)
	set_process(false)

func _maybe_prompt() -> void:
	if not _workspace.background_mode and DisplayServer.get_name() != "headless" and _workspace.preferences.tutorial_experience.is_empty():
		open(true)

func open(remember := false) -> void:
	close_guide()
	_remember_choice = remember
	_original_theme = _workspace.preferences.theme_mode
	_theme.select(_workspace.preferences.THEME_NAMES.keys().find(_original_theme))
	_choose_experience("branch" if _workspace.preferences.has_saved_preferences else "beginner")
	_show_setup(false)
	DialogLayout.present(_chooser, Vector2i(700, 264))

func _build_chooser() -> void:
	_chooser = Window.new()
	_chooser.title = "欢迎使用更好的制谱器"
	_chooser.transient = true
	_chooser.exclusive = true
	_chooser.hide()
	add_child(_chooser)
	_setup_surface = ColorRect.new()
	_setup_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chooser.add_child(_setup_surface)
	_setup_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_chooser.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	scroll.add_child(body)
	_first = VBoxContainer.new()
	body.add_child(_first)
	_add_caption(_first, "你之前用过哪款制谱器？", 19)
	var group := ButtonGroup.new()
	for pair in [["第一次制谱", "beginner"], ["用过原版制谱器", "original"], ["用过这个分支", "branch"]]:
		var option := _button(pair[0], _choose_experience.bind(pair[1]))
		option.toggle_mode = true
		option.button_group = group
		option.set_meta("experience", pair[1])
		_first.add_child(option)
	_second = VBoxContainer.new()
	_second.add_theme_constant_override("separation", 6)
	body.add_child(_second)
	var settings := GridContainer.new()
	settings.columns = 2
	settings.add_theme_constant_override("h_separation", 12)
	_second.add_child(settings)
	var scheme_label := _add_caption(settings, "快捷键方案")
	scheme_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_scheme = OptionButton.new()
	_scheme.add_item("标准快捷键")
	_scheme.add_item("原版制谱器")
	_scheme.item_selected.connect(func(_index: int):
		_scheme_explicit = true
		_update_setup_comparison())
	settings.add_child(_scheme)
	var theme_label := _add_caption(settings, "界面主题")
	theme_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_theme = OptionButton.new()
	for name in _workspace.preferences.THEME_NAMES.values():
		_theme.add_item(name)
	_theme.item_selected.connect(func(index: int):
		_workspace.preferences.set_theme_mode(_workspace.preferences.THEME_NAMES.keys()[index]))
	settings.add_child(_theme)
	_comparison = _add_caption(_second, "")
	_comparison.add_theme_color_override("font_color", EditorTheme.tone("muted"))
	_build_setup_sample()
	var actions := HFlowContainer.new()
	body.add_child(actions)
	_setup_back = _button("返回", _show_setup.bind(false))
	actions.add_child(_setup_back)
	actions.add_child(_button("使用推荐设置并开始", _complete_setup.bind(true)))
	_setup_next = _button("下一步", func():
		if _first.visible:
			_show_setup(true)
		else:
			_complete_setup(false))
	actions.add_child(_setup_next)
	_chooser.window_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_chooser.close_requested.emit())
	_chooser.close_requested.connect(func():
		_workspace.preferences.set_theme_mode(_original_theme)
		if _remember_choice:
			_workspace.preferences.tutorial_experience = "branch"
			_workspace.preferences.save()
		_chooser.hide())

func _add_caption(parent: Control, value: String, font_size := 14) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _build_setup_sample() -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 158
	_second.add_child(row)
	var inspector := VBoxContainer.new()
	inspector.custom_minimum_size.x = 150
	row.add_child(inspector)
	var tabs := TabBar.new()
	tabs.add_tab("键设置")
	inspector.add_child(tabs)
	_add_caption(inspector, "普通键 · 已选 1 个")
	_add_caption(inspector, "判定时间")
	var timing := SpinBox.new()
	timing.max_value = 10000
	timing.value = 1000
	timing.suffix = "毫秒"
	timing.focus_mode = Control.FOCUS_NONE
	timing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timing.get_line_edit().mouse_filter = Control.MOUSE_FILTER_IGNORE
	timing.get_line_edit().focus_mode = Control.FOCUS_NONE
	inspector.add_child(timing)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(scroll)
	var wrapper := Container.new()
	scroll.add_child(wrapper)
	var sample_chart := Chart.new()
	wrapper.add_child(sample_chart)
	sample_chart.track_count = 3
	sample_chart.audio_duration_ms = 4800
	sample_chart.audio_waveform.resize(480)
	for i in range(480):
		sample_chart.audio_waveform[i] = (0.15 + 0.85 * absf(sin(i * 0.69))) * exp(-float(i % 50) / 27.0)
	var key: int = sample_chart.add_note_at_times(0, 600, 1000, 0, 0, Vector2(960, 540))
	sample_chart.add_note_at_times(1, 1050, 1500, 0, 1, Vector2(960, 540))
	sample_chart.add_note_at_times(2, 1450, 2350, 1850, 2, Vector2(900, 400))
	sample_chart.select_note(key)
	_sample = Grid.new()
	_sample.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(_sample)
	_sample.set_chart_data(sample_chart)
	_sample.set_process_input(false)
	_sample.set_process(false)
	_sample.column_width = 100.0
	_sample.update_grid_size()

func apply_theme(value: Theme) -> void:
	if _chooser:
		_chooser.theme = value
		_setup_surface.color = EditorTheme.tone("surface")
	if _panel:
		var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
		style.bg_color = EditorTheme.tone("surface")
		style.border_color = EditorTheme.tone("accent")
		_progress.modulate = Color.WHITE
	if _sample:
		_sample.queue_redraw()
		_comparison.add_theme_color_override("font_color", EditorTheme.tone("muted"))

func _show_setup(settings: bool) -> void:
	_first.visible = not settings
	_second.visible = settings
	_setup_back.visible = settings
	var next := {"beginner": "开始制谱教程", "original": "查看新版变化", "branch": "进入工作区"}
	_setup_next.text = next[_experience] if settings else "下一步"
	if _chooser.visible:
		var previous_size := _chooser.size
		_chooser.size.y = clampi(400 if settings else 264, 230, _chooser.max_size.y)
		_chooser.position -= Vector2i(Vector2(_chooser.size - previous_size) * 0.5)

func _choose_experience(experience: String) -> void:
	_experience = experience
	_scheme_explicit = false
	for button in _first.get_children():
		if button is Button:
			button.set_pressed_no_signal(button.get_meta("experience") == experience)
	var pref = _workspace.preferences
	var recommended: String = pref.shortcut_scheme if pref.has_saved_preferences or experience == "branch" else ("original" if experience == "original" else "standard")
	_scheme.select(int(recommended == "original"))
	_update_setup_comparison()

func _update_setup_comparison() -> void:
	var pref = _workspace.preferences
	_comparison.text = "标准　左键框选和移动 · 数字键切换工具 · 控制键＋空格跳到指针\n原版　上档键＋右键框选 · 控制键＋左键移动 · 上档键＋空格跳到指针\n两套方案都支持长按右键切换工具。当前播放键 %s。" % pref.caption("play")

func _complete_setup(recommended: bool) -> void:
	var pref = _workspace.preferences
	if recommended:
		pref.set_theme_mode(_original_theme)
		_choose_experience(_experience)
	var chosen := "original" if _scheme.selected == 1 else "standard"
	if _scheme_explicit or not pref.has_saved_preferences:
		pref.set_scheme(chosen)
	_chooser.hide()
	pref.tutorial_experience = _experience
	pref.has_saved_preferences = true
	pref.save()
	_remember_choice = false
	match _experience:
		"beginner":
			open_beginner()
		"original":
			open_migration()

func open_beginner() -> void:
	_guide_kind = "beginner"
	_heard = false
	_exported = false
	_start(_beginner_steps())

func open_migration() -> void:
	_guide_kind = "original"
	_start(_original_steps())

func refresh_bindings() -> void:
	if _panel and _panel.visible:
		_steps = _beginner_steps() if _guide_kind == "beginner" else _original_steps()
		_show_step(_index)
	if _comparison:
		_update_setup_comparison()

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.hide()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#202734")
	style.border_color = Color("#648ec6")
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = GAP
	style.content_margin_top = GAP
	style.content_margin_right = GAP
	style.content_margin_bottom = GAP
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	_panel.add_child(content)
	_progress = Label.new()
	_progress.modulate = Color("#b1c0d8")
	content.add_child(_progress)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_title)
	_instruction = Label.new()
	_instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_instruction)
	_task_status = Label.new()
	_task_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_task_status)
	var buttons := HFlowContainer.new()
	content.add_child(buttons)
	_action = _button("", _run_action)
	buttons.add_child(_action)
	_back = _button("上一步", func(): _show_step(_index - 1))
	buttons.add_child(_back)
	_next = _button("下一步", _advance)
	buttons.add_child(_next)
	_skip_step = _button("跳过本步", _advance)
	buttons.add_child(_skip_step)
	buttons.add_child(_button("结束引导", close_guide))

func _button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(callback)
	return button

func _beginner_steps() -> Array[Dictionary]:
	var steps: Array[Dictionary] = [
		_step("导入你的第一首歌",
			"点「导入音频」选一首歌，也可把 MP3、WAV 或 OGG 拖进来。导入后就能开始放键。",
			_file_menu(), "导入音频", _workspace._open_audio_dialog, "audio", "导入歌曲后可继续。"),
		_step("认识卷帘和检查器",
			"下方卷帘从左到右是时间，一行是一条轨道。左上检查器修改音符属性，页签找不到时点「全部页签」。右上是预览。",
			_workspace._inspector_heading, "打开键设置", _workspace._open_inspector_page.bind("键设置")),
		_step("单选节拍并采音",
			"打开「自动采音」，选中「节拍（Beat This!）」。在「采音」按钮上方选择音源，默认使用完整音频。完成分轨后，可以改选鼓组等分轨。点「采音」查看节拍，有缓存时点「应用」。",
			_workspace._analysis_panel, "选择节拍", _select_capture.bind("beat"), "capture_beat", "在自动采音页采音或应用节拍后继续。"),
		_step("按灵敏度应用缓存",
			"先试着选「主旋律」，卷帘会保留上次的节拍。再选回刚才的节拍，调节灵敏度，点「应用」更新标记。各音源和模型分别缓存。想看主旋律时可以单独采音。",
			_workspace._analysis_panel, "选择主旋律", _select_capture.bind("melody")),
		_step("检查工程 BPM",
			"节拍采音取得速度时会自动填入空缺的工程 BPM。若 BPM 仍为空，在「自动采音」单选 BPM 项，再点底部「采音」或「应用」。",
			_workspace._analysis_panel, "选择 BPM", _select_capture.bind("tempo")),
		_step("传统参考线",
			"到「参考线量化」选择「传统参考线」。填写手动 BPM 并点「应用」即可更新谱面速度。网格也会使用工程的变速节点和拍内细分。打开卷帘上沿的「时间吸附」后可沿网格放键。",
			_workspace._mode_choice, "显示传统参考线", _show_reference.bind(Chart.ReferenceMode.TRADITIONAL)),
		_step("自动采音线",
			"在同一页切换为「自动采音线」，对照刚才已应用的节拍放键。想换一组标记时，返回「自动采音」选另一行，再点「采音」或「应用」。",
			_workspace._mode_choice, "显示自动采音线", _show_reference.bind(Chart.ReferenceMode.BEATS)),
		_step("放置第一个键",
			"选「普通键」，在波形下方的空白轨道单击。放长键时，在同一轨道依次点起点和终点。",
			_workspace._tools[0], "选择普通键", _workspace._choose_tool.bind(0), "place", "在卷帘里放下一个键后继续。"),
		_step("选中并移动",
			"切到「选择」，用%s改变音符的时间或轨道。%s可以批量选中。" % [_workspace.preferences.move_gesture(), _workspace.preferences.selection_gesture()],
			_workspace._tools[-1], "切到选择工具", _workspace._choose_tool.bind(-1), "move", "把任意一个音符移到另一拍或轨道后继续。"),
		_step("调整画面位置",
			"选中音符后，在右上预览用%s改它在画面中的位置。「位置吸附」只影响画面网格。也能在「键设置」直接填写坐标。" % _workspace.preferences.move_gesture(),
			_workspace._result_heading, "显示谱面预览", _show_preview),
		_step("放一个黄键（滑键）",
			"点「选择滑键」，在想让黄键收圈的那一拍单击空轨。这个时刻就是判定时间。试着把它接在普通键后面，作为下一拍的落点。",
			_workspace._tools[1], "选择滑键", _workspace._choose_tool.bind(1), "slide", "在空轨放下一个滑键后继续。"),
		_step("给黄键画一段滑动路径",
			"选中刚放下的黄键，点击预览上方的「添加滑动路径」，拖动「终点 · 判定」。从前一拍回放，观察黄键在终点收圈。",
			_workspace._result_heading, "显示谱面预览", _show_preview),
		_step("试听谱面",
			"在标尺上定位，点击「播放」或按当前播放键 %s。右上「预览控制」可以试玩或循环选区，试玩后点「返回编辑」。" % _shortcut("play"),
			_workspace._result_heading, "从当前拍试玩", _workspace._play_from_current, "play", "试听一次后继续。"),
		_step("按需添加歌词或背景",
			"从「文件」导入曲绘或歌词。展开「背景与遮罩」，在副歌前压暗背景，再在第一拍添加圆形揭示。点片段可循环预览。",
			_workspace._background_toggle, "打开背景与遮罩", _workspace._set_background_track.bind(true)),
		_step("连接你的制谱 Agent",
			"打开「工具 → Agent 设置」。填写服务地址、API Key 和模型名称并保存。DeepSeek 的地址是 https://api.deepseek.com，模型可填 deepseek-flash。密钥只填在设置里；想先手工制谱可跳过此步。",
			_workspace._copilot_menu.get_parent(), "填写 API Key", _workspace.automatic.open_settings, "agent_config", "保存有效格式的设置后继续，或点「跳过本步」。"),
		_step("让 Agent 补一段谱",
			"打开「工具 → Revelation Co-pilot」，试试「只补 20–24 秒，保留已有音符」，或点「一键制谱」选择难度。默认由你批准改动；勾选「自动审批」后，独立审查助手会按本轮要求核对操作，有疑问时请你决定。读取直接执行，写入后可整轮撤销。",
			_workspace._copilot_menu.get_parent(), "打开 Co-pilot", _workspace._set_copilot_visible.bind(true)),
		_step("导出可玩的谱面",
			"「文件 → 保存谱面」用于继续编辑。「导出谱面压缩包」会把谱面、歌曲和图片打成可玩的 ZIP。之后可从「帮助 → 功能速查」查入口。",
			_file_menu(), "导出谱面压缩包", _workspace.sidebar._on_export_zip, "export", "完成一次 ZIP 导出即可结束。"),
	]
	if not _workspace.features_enabled():
		steps = steps.filter(func(step: Dictionary): return step.target != _workspace._analysis_panel and step.title not in [
			"自动采音线", "连接你的制谱 Agent", "让 Agent 补一段谱"])
	return steps

func _original_steps() -> Array[Dictionary]:
	var steps: Array[Dictionary] = [
		_step("打开原有谱面",
			"「文件 → 打开已有谱面」同时支持原版 ZIP 和 JSON。「导入导出」页还在检查器，左上点「全部页签」即可找到。导入音频键位为 %s。" % _shortcut("import_audio"),
			_file_menu(), "打开文件菜单", _file_menu().show_popup),
		_step("查看当前键位",
			"当前为%s方案。保存 %s，撤销 %s，播放或暂停 %s，跳到指针 %s。可切回原版方案，也可单独改键。" %
				["原版" if _workspace.preferences.shortcut_scheme == "original" else "标准", _shortcut("save"), _shortcut("undo"), _shortcut("play"), _shortcut("play_here")],
			_workspace._menu.get_child(0).get_child(1), "打开快捷键设置", _workspace.preferences.open.bind("快捷键")),
		_step("画笔、框选和移动",
			"工具移到卷帘上沿。当前方案用%s移动，用%s。单独长按右键可切换工具。" % [_workspace.preferences.move_gesture(), _workspace.preferences.selection_gesture()],
			_workspace._rail, "切到选择工具", _workspace._choose_tool.bind(-1)),
		_step("时间轴参考线与吸附",
			"在「参考线量化」设置工程 BPM，再到卷帘上方调整拍内细分和时间吸附。",
			_workspace._track_bar, "打开参考线量化", _workspace._open_inspector_page.bind("参考线量化")),
		_step("画面位置与试玩",
			"在预览区用%s改位置，右上的「位置吸附」独立于时间吸附。「预览控制」里可循环或试玩，试玩后点「返回编辑」。" % _workspace.preferences.move_gesture(),
			_workspace._result_heading, "显示谱面预览", _show_preview),
		_step("自动采音与缓存",
			"在「自动采音」单选一项。首次点「采音」，有缓存时调整灵敏度后点「应用」。仅换选项会保留卷帘上的结果。",
			_workspace._inspector_heading, "打开自动采音", _workspace._open_inspector_page.bind("自动采音")),
		_step("查找导出和其他入口",
			"从「文件」保存或导出 ZIP，渲染视频也在同一菜单。以后可在右下角打开「功能速查」，搜索歌词、动画、吸附或旧功能名称。",
			_file_menu(), "打开功能速查", _workspace._open_feature_finder),
	]
	if not _workspace.features_enabled():
		steps = steps.filter(func(step: Dictionary): return step.title != "自动采音与缓存")
	return steps

func _select_capture(id: String) -> void:
	_workspace._open_inspector_page("自动采音")
	_workspace._analysis_panel.select(id)

func _show_reference(mode: int) -> void:
	_workspace._open_inspector_page("参考线量化")
	_workspace.sidebar.set_guide_mode(mode)

func _show_preview() -> void:
	_workspace._set_game_mode(false)

func _file_menu() -> MenuButton:
	return _workspace._menu.get_child(0).get_child(0)

func _shortcut(name: String) -> String:
	return _workspace.preferences.caption(name)

func _step(title: String, instruction: String, target: Control, action_text := "", action := Callable(),
		task := "", hint := "") -> Dictionary:
	return {"title": title, "instruction": instruction, "target": target, "action_text": action_text,
		"action": action, "task": task, "hint": hint}

func _start(steps: Array[Dictionary]) -> void:
	if _steps.is_empty():
		_original_capture = _workspace._analysis_panel.selected_id
		_original_reference = _workspace.sidebar.guide_mode
		_original_background_track = _workspace.grid.background_track_visible
	_steps = steps
	_active_task = ""
	_show_step(0)

func _show_step(index: int) -> void:
	_index = clampi(index, 0, _steps.size() - 1)
	var step: Dictionary = _steps[_index]
	if _active_task != step.task:
		_active_task = step.task
		_practice_note_placed = false
		_practice_note_moved = false
		_note_positions.clear()
		if _active_task == "move":
			for id: int in _workspace.chart.notes:
				var note = _workspace.chart.notes[id]
				_note_positions[id] = Vector2i(note.time_unit, note.track)
	_progress.text = "第 %d 步，共 %d 步" % [_index + 1, _steps.size()]
	_title.text = step.title
	_instruction.text = step.instruction
	_back.disabled = _index == 0
	_next.text = "完成" if _index + 1 == _steps.size() else "下一步"
	_action.text = step.action_text
	_action.visible = not _action.text.is_empty()
	_panel.show()
	_skip_step.visible = not _active_task.is_empty()
	_check_progress()
	set_process(true)
	_reposition()

func _advance() -> void:
	if _index + 1 == _steps.size():
		close_guide()
	else:
		_show_step(_index + 1)

func _run_action() -> void:
	var action: Callable = _steps[_index].action
	if action.is_valid():
		action.call()

func close_guide() -> void:
	_panel.hide()
	_highlight = Rect2()
	if not _steps.is_empty():
		_workspace._analysis_panel.select(_original_capture)
		_workspace.sidebar.set_guide_mode(_original_reference)
		if _workspace.grid.background_track_visible != _original_background_track:
			_workspace._set_background_track(_original_background_track)
	_steps.clear()
	_active_task = ""
	_note_positions.clear()
	set_process(false)
	queue_redraw()

func _process(_delta: float) -> void:
	_check_progress()
	_reposition()

func _check_progress() -> void:
	var chart = _workspace.chart
	var ready := true
	match _active_task:
		"audio": ready = not chart.audio_path.is_empty()
		"capture_beat": ready = chart.rhythm_analysis.get("capture_id", "") == "beat"
		"place", "slide": ready = _practice_note_placed
		"move": ready = _practice_note_moved
		"play":
			_heard = _heard or chart.rt_playing
			ready = _heard
		"export": ready = _exported
		"agent_config": ready = _workspace.automatic._valid_settings(_workspace.automatic._effective_settings())
	_next.disabled = not ready
	_task_status.visible = not _active_task.is_empty()
	_task_status.text = "本步已完成，可以继续。" if ready else _steps[_index].hint

func _check_practice_move(id: int) -> void:
	if _active_task != "move" or not _note_positions.has(id):
		return
	var note = _workspace.chart.notes.get(id)
	if note and Vector2i(note.time_unit, note.track) != _note_positions[id]:
		_practice_note_moved = true

func _reposition() -> void:
	var width := minf(440.0, maxf(size.x - GAP * 2, 1))
	if not is_equal_approx(_panel.custom_minimum_size.x, width):
		_panel.custom_minimum_size.x = width
	var fitted := _panel.get_combined_minimum_size().max(Vector2(width, 0))
	if not _panel.size.is_equal_approx(fitted):
		_panel.size = fitted
	var target: Control = _steps[_index].target
	var local_transform := get_global_transform().affine_inverse()
	var area := local_transform * target.get_global_rect() if target.is_visible_in_tree() else Rect2()
	if area != _highlight:
		_highlight = area
		queue_redraw()
	var needs_grid := _active_task in ["place", "move", "slide"]
	if needs_grid:
		var timeline: Rect2 = _workspace._track_bar.get_global_rect().merge(_workspace.rollout.get_global_rect())
		area = local_transform * timeline
	var upper := area.position.y - _panel.size.y - GAP
	var lower := area.end.y + GAP
	var y := lower if lower + _panel.size.y <= size.y - GAP else upper
	var x := area.position.x
	if area.end.x + GAP * 2 + _panel.size.x <= size.x:
		x = area.end.x + GAP
		y = area.position.y
	var limit := (size - _panel.size - Vector2.ONE * GAP).max(Vector2.ONE * GAP)
	var pos := Vector2(x, y).clamp(Vector2.ONE * GAP, limit)
	if needs_grid and Rect2(pos, fitted).intersects(_highlight.grow(3)):
		pos.x = clampf(_highlight.end.x + GAP, GAP, limit.x)
	_panel.position = pos

func _draw() -> void:
	if _highlight.has_area():
		draw_rect(_highlight.grow(3.0), EditorTheme.tone("accent"), false, 2.0)
