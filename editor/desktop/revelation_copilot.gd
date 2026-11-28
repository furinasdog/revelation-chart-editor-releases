extends PanelContainer

const DialogLayout := preload("res://desktop/dialog_layout.gd")
const OfficialAccess := preload("res://desktop/official_access.gd")

signal visibility_requested(enabled: bool)
signal approval_resolved(approved: bool)

const TITLE := "Revelation Co-pilot"
const HISTORY_BYTES := 12000
const Agent := preload("res://desktop/chart_agent.gd")
const Prompts := preload("res://desktop/agent_prompts.gd")
const Reviewer := preload("res://desktop/copilot_reviewer.gd")
const Markdown := preload("res://desktop/copilot_markdown.gd")
const AudioImport := preload("res://desktop/agent_audio_import.gd")
const Plan := preload("res://desktop/auto_chart_plan.gd")
const AnimationDraft := preload("res://desktop/agent_animation.gd")
const Automatic := preload("res://desktop/automatic_chart.gd")
const Frames := preload("res://desktop/agent_frames.gd")
const EditorTheme := preload("res://desktop/editor_theme.gd")
const EDITABLE_STATE := ["notes", "events", "next_note_id", "next_event_id", "anim_rect_slots", "bg_anim_key_slots",
	"preset_bg_anim_groups", "bpm_segments", "total_beats", "bpm_val", "has_project_bpm", "remarks"]
const FIELD_NAMES := {
	"factor": "滑动距离倍率",
	"notes": "音符", "ids": "音符编号", "id": "编号", "type": "类型", "time_ms": "时间（毫秒）", "lane": "轨道（从 0 开始）",
	"duration_ms": "持续时间（毫秒）", "lead_ms": "预告时间（毫秒）", "x": "横坐标", "y": "纵坐标",
	"end_x": "终点横坐标", "end_y": "终点纵坐标", "mid_x": "弧线中间横坐标", "mid_y": "弧线中间纵坐标",
	"approach_x": "进场横坐标", "approach_y": "进场纵坐标", "seed": "随机种子", "from_ms": "起始时间（毫秒）",
	"to_ms": "结束时间（毫秒）", "mask_id": "蒙版编号", "color": "颜色", "opacity": "不透明度", "radius_px": "半径（像素）",
	"use_cover_artwork": "曲绘作底图", "artwork_id": "曲绘编号", "slot": "图层槽位", "source": "素材", "width": "宽度", "height": "高度",
	"keyframes": "关键帧", "rotation": "旋转角度", "scale": "缩放", "easing": "缓动",
	"shapes": "图形", "kind": "图形类型", "shape_id": "图形编号", "stroke": "描边颜色", "stroke_width": "描边宽度",
	"fill": "填充", "target": "图像轨道", "fields": "谱面字段", "segments": "速度分段", "start_beat": "起始拍",
	"total_beats": "总拍数", "text": "文本", "size": "字号", "fade_in_ms": "淡入（毫秒）", "fade_out_ms": "淡出（毫秒）",
	"name": "谱面名称", "difficulty": "难度", "composer": "作曲者", "description": "说明", "tips": "提示", "bpm": "速度",
	"capture_id": "采音项目", "engine": "分析引擎", "model": "模型", "tasks": "分析任务", "stem": "采音源",
	"sensitivity": "灵敏度", "use_for_draft": "替换草稿中已有分析结果",
}
const VALUE_NAMES := {"note": "普通键", "drag": "滑键", "hold": "长键", "cover": "曲绘", "color": "纯色",
	"mask": "蒙版", "background": "底图", "shape": "图形", "square": "正方形", "rectangle": "矩形",
	"circle": "圆形", "ellipse": "椭圆", "line": "线段", "none": "无", "linear": "线性", "smooth": "平滑", "out": "缓出", "teal": "青色", "rose": "玫瑰红",
	"blue": "蓝色", "amber": "琥珀色", "violet": "紫色", "white": "白色"}

var busy := false
var _workspace: Node
var _selected_span := Vector2(-1, -1)
var _span_generation := -1
var _preserve := CheckBox.new()
var _original_rows := {}
var _comparison: ConfirmationDialog
var _agent := Agent.new()
var _scroll: ScrollContainer
var _transcript: VBoxContainer
var _status: Label
var _editor: TextEdit
var _send_button: Button
var _compose_button: Button
var _compose_dialog: ConfirmationDialog
var _compose_level: OptionButton
var _compose_brief: TextEdit
var _compose_hint: Label
var _compose_generation := -1
var _requested_difficulty := ""
var _stop_button: Button
var _retry_button: Button
var _retry_message := ""
var _auto_approve: CheckBox
var _reviewer := Reviewer.new()
var _review_turn := 0
var _review_scope := {}
var _review_settings := {}
var _accepted_operations: Array = []
var _refused_operations := {}
var _approval: PanelContainer
var _approval_title: Label
var _approval_details: TextEdit
var _history: Array[Dictionary] = []
var _history_generation := -1
var _generation := -1
var _project_signature := {}
var _original_chart := {}
var _conflict: ConfirmationDialog
var _pending_summary := ""
var _plan: RefCounted
var _animation: RefCounted
var _steps_button: Button
var _steps_list: VBoxContainer
var _completed_steps := 0
var _step: PanelContainer
var _step_status: Label
var _step_detail: Label
var _stream_text: RichTextLabel
var _last_edit: Button

func setup(workspace: Node) -> void:
	_workspace = workspace
	hide()
	clip_contents = true
	add_child(_agent)
	_agent.action_started.connect(_on_action)
	_agent.action_finished.connect(_on_action_result)
	_agent.action_detail.connect(_show_action_detail)
	_agent.request_finished.connect(func(_round: int, _elapsed: int, _tokens: int, success: bool):
		_end_step("已完成" if success else "请求失败", success))
	_agent.reply_preview.connect(_preview_reply)
	_agent.tool_progress.connect(_substep)
	_agent.request_failed.connect(func(stage: String, details: Dictionary):
		_workspace.diagnostics.record("copilot." + stage, details, "error"))
	_agent.retry_available.connect(_offer_retry)
	_agent.completed.connect(_finish)
	_agent.replied.connect(func(message: String): _complete(message))
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	margin.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var title := Label.new()
	title.text = TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_make_button(header, "关闭", func(): visibility_requested.emit(false))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_scroll)
	_transcript = VBoxContainer.new()
	_transcript.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_transcript.add_theme_constant_override("separation", 9)
	_scroll.add_child(_transcript)
	_status = Label.new()
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.hide()
	body.add_child(_status)
	_build_approval(body)
	_auto_approve = CheckBox.new()
	_auto_approve.text = "自动审批"
	_auto_approve.tooltip_text = "读取直接执行。使用当前模型独立审查其他操作，超出要求时拒绝，不确定时请你确认。每次审查会调用一次模型。"
	_auto_approve.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(_auto_approve)
	add_child(_reviewer)
	_preserve.text = "仅新增，保留已有音符"
	_preserve.hide()
	body.add_child(_preserve)
	_editor = TextEdit.new()
	_editor.placeholder_text = "例如：把选中的长键延长半拍"
	_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_editor.custom_minimum_size.y = 68
	_editor.text_changed.connect(_refresh_controls)
	_editor.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
			_editor.accept_event()
			_submit())
	body.add_child(_editor)
	var footer := HFlowContainer.new()
	footer.alignment = FlowContainer.ALIGNMENT_END
	body.add_child(footer)
	_compose_button = _make_button(footer, "一键制谱", open_compose)
	_compose_button.tooltip_text = "选择难度，填写制谱要求并交给助手"
	_make_button(footer, "设置", func(): _workspace.automatic.open_settings())
	_stop_button = _make_button(footer, "停止", cancel)
	_retry_button = _make_button(footer, "重试本轮", _retry_request)
	_retry_button.tooltip_text = "重新发送本轮请求。服务可能重新计费。"
	_send_button = _make_button(footer, "发送", _submit)
	_send_button.tooltip_text = "发送（Ctrl+Enter）"
	_reset_transcript()
	_refresh_controls()

func apply_theme() -> void:
	if is_instance_valid(_compose_dialog):
		_compose_dialog.theme = _workspace._ui_theme
	var surface := StyleBoxFlat.new()
	surface.bg_color = EditorTheme.tone("panel")
	surface.border_color = EditorTheme.tone("line")
	surface.border_width_left = 1
	add_theme_stylebox_override("panel", surface)
	_status.add_theme_color_override("font_color", EditorTheme.tone("muted"))
	for item in _transcript.find_children("*", "PanelContainer", true, false):
		if item.has_meta("bubble"):
			_style_bubble(item, bool(item.get_meta("bubble")))
		elif item.has_meta("tool_step"):
			_style_step(item)

func _build_approval(body: VBoxContainer) -> void:
	_approval = PanelContainer.new()
	_approval.hide()
	body.add_child(_approval)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_approval.add_child(row)
	_approval_title = Label.new()
	_approval_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_approval_title)
	_approval_details = TextEdit.new()
	_approval_details.editable = false
	_approval_details.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_approval_details.custom_minimum_size.y = 94
	row.add_child(_approval_details)
	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(controls)
	_make_button(controls, "拒绝", _resolve_approval.bind(false))
	_make_button(controls, "批准", _resolve_approval.bind(true))

func _make_button(row: Container, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	row.add_child(button)
	return button

func _reset_transcript() -> void:
	_history.clear()
	for child: Node in _transcript.get_children():
		_transcript.remove_child(child)
		child.queue_free()
	_append("助手", "可以询问当前谱面，也可以指定要编辑的段落或选中的音符。勾选「自动审批」可让审查助手按本轮要求判断改动。")

func _append(speaker: String, message: String) -> RichTextLabel:
	var row := HBoxContainer.new()
	var user := speaker == "你"
	_transcript.add_child(row)
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 24
	row.add_child(spacer)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.set_meta("bubble", user)
	row.add_child(panel)
	if not user:
		row.move_child(panel, 0)
	_style_bubble(panel, user)
	var item := VBoxContainer.new()
	item.add_theme_constant_override("separation", 3)
	panel.add_child(item)
	if user:
		if is_instance_valid(_last_edit):
			_last_edit.hide()
		_last_edit = _make_button(item, "修改请求", func():
			if not busy:
				_editor.text = message
				_editor.grab_focus())
		_last_edit.flat = true
		_last_edit.size_flags_horizontal = Control.SIZE_SHRINK_END
	var content := RichTextLabel.new()
	content.fit_content = true
	content.scroll_active = false
	content.selection_enabled = true
	if user:
		content.text = message
	else:
		Markdown.render(content, message)
	item.add_child(content)
	_scroll_to.call_deferred(row)
	return content

func _style_bubble(panel: PanelContainer, user: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = EditorTheme.tone("selected" if user else "surface")
	style.set_corner_radius_all(9)
	for side: int in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_content_margin(side, 9)
	panel.add_theme_stylebox_override("panel", style)

func _start_steps() -> void:
	_completed_steps = 0
	_step = null
	var card := VBoxContainer.new()
	_transcript.add_child(card)
	_steps_button = Button.new()
	_steps_button.text = "正在处理"
	card.add_child(_steps_button)
	_steps_button.flat = true
	_steps_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_steps_list = VBoxContainer.new()
	_steps_list.add_theme_constant_override("separation", 5)
	card.add_child(_steps_list)
	# Old activity cards keep their own details when a new turn begins.
	var list := _steps_list
	var toggle := _steps_button
	toggle.tooltip_text = "展开或折叠本轮过程"
	toggle.pressed.connect(func():
		list.visible = not list.visible
		toggle.text = ("▾ " if list.visible else "▸ ") + toggle.text.substr(2))
	_refresh_steps()

func _begin_step(caption: String) -> void:
	_step = PanelContainer.new()
	_step.set_meta("tool_step", true)
	_steps_list.add_child(_step)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	_step.add_child(body)
	var title := Label.new()
	title.text = caption
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(title)
	_step_detail = Label.new()
	_step_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_step_detail.hide()
	body.add_child(_step_detail)
	_step_status = Label.new()
	_step_status.text = "进行中"
	body.add_child(_step_status)
	_style_step(_step)
	_refresh_steps()
	_scroll_to.call_deferred(_step)

func _style_step(panel: PanelContainer) -> void:
	var active := panel == _step
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = EditorTheme.tone("accent" if active else "line")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	for side: int in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		style.set_content_margin(side, 8 if side in [SIDE_LEFT, SIDE_RIGHT] else 5)
	panel.add_theme_stylebox_override("panel", style)
	var body := panel.get_child(0)
	for index: int in [1, 2]:
		var label := body.get_child(index) as Label
		label.add_theme_color_override("font_color", EditorTheme.tone("muted"))

func _scroll_to(control: Control) -> void:
	if is_instance_valid(control) and _scroll.is_ancestor_of(control):
		_scroll.ensure_control_visible(control)

func _substep(service: String, caption: String) -> void:
	if is_instance_valid(_step):
		_step_detail.text = "%s · %s" % [service, caption]
		_step_detail.show()

func _end_step(status: String, success: bool) -> void:
	if not is_instance_valid(_step):
		return
	_step_status.text = status
	var panel := _step
	_step = null
	_style_step(panel)
	_completed_steps += int(success)
	_refresh_steps()

func _refresh_steps() -> void:
	_steps_button.text = "%s 已完成 %d 个步骤%s" % ["▾" if _steps_list.visible else "▸", _completed_steps,
		" · 1 项待确认" if _approval.visible else (" · 进行中" if is_instance_valid(_step) else "")]

func _preview_reply(text: String) -> void:
	if not busy:
		return
	if not is_instance_valid(_stream_text):
		_stream_text = _append("助手", text)
	else:
		var bar := _scroll.get_v_scroll_bar()
		var follow := bar.max_value - bar.page - bar.value < 18.0
		Markdown.render(_stream_text, text)
		if follow:
			_scroll_to.call_deferred(_stream_text)

func open_compose() -> void:
	if busy:
		return
	if _workspace.chart.audio_path.is_empty():
		_workspace._notify("请先导入歌曲，或打开带音频的谱面。")
		return
	if not _workspace.automatic._valid_settings(_workspace.automatic._effective_settings()):
		_workspace.automatic.open_settings()
		_workspace.automatic._settings_dialog.confirmed.connect(func():
			if _workspace.automatic._valid_settings(_workspace.automatic._effective_settings()):
				open_compose.call_deferred(), CONNECT_ONE_SHOT)
		return
	if not is_instance_valid(_compose_dialog):
		_compose_dialog = ConfirmationDialog.new()
		_compose_dialog.title = "一键制谱"
		_compose_dialog.ok_button_text = "发送给 Agent"
		_compose_dialog.cancel_button_text = "取消"
		_compose_dialog.dialog_hide_on_ok = false
		_compose_dialog.transient = true
		_compose_dialog.exclusive = true
		_workspace.host.add_child(_compose_dialog)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 8)
		_compose_dialog.add_child(body)
		body.add_child(_workspace._label("谱面难度"))
		_compose_level = OptionButton.new()
		for level in Plan.DIFFICULTIES:
			_compose_level.add_item(level)
		body.add_child(_compose_level)
		body.add_child(_workspace._label("制谱要求（可选）"))
		_compose_brief = TextEdit.new()
		_compose_brief.placeholder_text = "例如：副歌跟随鼓点；只补 20–24 秒的空缺，保留已有音符。"
		_compose_brief.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		_compose_brief.custom_minimum_size.y = 88
		body.add_child(_compose_brief)
		_compose_hint = _workspace._label("")
		_compose_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(_compose_hint)
		_compose_brief.text_changed.connect(_validate_compose)
		_compose_dialog.confirmed.connect(_confirm_compose)
	if _compose_generation != _workspace._document_generation:
		_compose_generation = _workspace._document_generation
		_compose_brief.clear()
		var current := str(_workspace.chart.chart_info.get("difficulty", "HD")).to_upper()
		_compose_level.select(Plan.DIFFICULTIES.keys().find(current if current in Plan.DIFFICULTIES else "HD"))
	_validate_compose()
	_compose_dialog.theme = _workspace._ui_theme
	DialogLayout.present(_compose_dialog, Vector2i(500, 280))

func _validate_compose() -> void:
	var too_long := _compose_brief.text.length() > 3000
	_compose_dialog.get_ok_button().disabled = too_long
	_compose_hint.text = "请将要求缩短到 3000 字以内。" if too_long else "留空时按整首歌曲制谱。助手会提交修改供你确认。"

func _confirm_compose() -> void:
	if _compose_generation != _workspace._document_generation:
		_compose_dialog.hide()
		_workspace._notify("已切换谱面，请重新选择制谱范围和难度。")
		return
	if _compose_brief.text.length() > 3000:
		return
	var level := _compose_level.get_item_text(_compose_level.selected)
	var template := Prompts.section("copilot", "one-click")
	if not template.contains("{{difficulty}}"):
		_workspace._notify("无法加载一键制谱模板。请检查提示词文件中的难度占位符。")
		return
	var prompt := template.replace("{{difficulty}}", level)
	var brief := _compose_brief.text.strip_edges()
	if not brief.is_empty():
		prompt += "\n谱师要求：" + brief
	if _send_prompt(prompt, level):
		_compose_dialog.hide()

func _submit() -> void:
	_send_prompt(_editor.text.strip_edges())

func prepare_selection(bounds: Vector2) -> void:
	if busy or bounds.y <= bounds.x: return
	_selected_span = bounds
	_span_generation = _workspace._document_generation
	_preserve.button_pressed = true
	_preserve.show()
	_editor.text = "请修改 %s–%s 秒的选区。" % [String.num(bounds.x/1000.0), String.num(bounds.y/1000.0)]
	_editor.grab_focus()
	_editor.select_all()

func _send_prompt(text: String, difficulty := "") -> bool:
	if busy or text.is_empty() or not OfficialAccess.features_enabled():
		return false
	if _span_generation != _workspace._document_generation or not difficulty.is_empty():
		_selected_span = Vector2(-1,-1)
		_preserve.hide()
	if _selected_span.y > _selected_span.x:
		text += "\n卷帘选区：%d–%d 毫秒，出现、判定和长键结束均须落在此段内，判定不含结束边界。" % [_selected_span.x, _selected_span.y]
		if _preserve.button_pressed: text += " 只允许新增音符。"
	if _workspace._analyzing or _workspace._video.busy:
		_status.text = "请等待当前任务结束。"
		_status.show()
		if not difficulty.is_empty():
			_compose_hint.text = _status.text
		return false
	var local_topics := _local_help(text) if difficulty.is_empty() else []
	var settings: Dictionary = _workspace.automatic._effective_settings()
	if local_topics.is_empty() and not _workspace.automatic._valid_settings(settings):
		_status.text = "请先配置模型和 API Key。"
		_status.show()
		_workspace.automatic.open_settings()
		return false
	var chart: Node = _workspace.chart
	_generation = _workspace._document_generation
	if _history_generation != _generation:
		_history_generation = _generation
		_reset_transcript()
	var history := _recent_history()
	_history.append({"role": "user", "text": text.left(4000)})
	if _history.size() > 30:
		_history.pop_front()
	_append("你", text.left(4000))
	if difficulty.is_empty():
		_editor.clear()
	_requested_difficulty = difficulty
	busy = true
	_review_turn += 1
	_review_scope = {"user_request": text, "selected_note_ids": chart.selected_note_ids.duplicate(),
		"selected_span_ms": [_workspace._loop_range.x, _workspace._loop_range.y],
		"playhead_ms": chart.preview_anim_time, "editor": _workspace.agent_editor_view()}
	_review_settings = settings.duplicate()
	_accepted_operations.clear()
	_refused_operations.clear()
	_status.hide()
	_start_steps()
	_refresh_controls()
	if not local_topics.is_empty():
		_begin_step("软件内置教程 · 查找功能入口")
		_end_step("已找到", true)
		var lines := PackedStringArray()
		for topic: Dictionary in local_topics:
			lines.append("「%s」\n%s" % [topic.menu, topic.instructions])
		_complete("\n\n".join(lines))
		return true
	_prepare_draft()
	var music := Automatic.music_for_agent(chart, _workspace._cached_chart_music(), _plan.duration_ms)
	_workspace.diagnostics.record("copilot.start", {"artwork_count": _animation.artwork.size()})
	_agent.start(_plan, music, _workspace.automatic._estimate_mood(), settings, text.left(4000), _animation, true,
		_capture, _workspace._analyze_for_agent,
		{"approve": _request_approval, "review_commit": _auto_approve.button_pressed, "history": history, "help": _workspace._copilot_help,
			"editor_view": _workspace.agent_editor_view, "import_audio": _import_audio},
		{"selection": _workspace._agent_audio_selection(),
			"spectrum": _workspace._capture_agent_spectrum})
	return true

func _prepare_draft() -> void:
	var chart: Node = _workspace.chart
	_original_chart = chart._snapshot_notes()
	_project_signature = _signature(_original_chart)
	var difficulty := _requested_difficulty if not _requested_difficulty.is_empty() else str(chart.chart_info.get("difficulty", "HD")).to_upper()
	_plan = Plan.new(chart, difficulty)
	if _selected_span.y > _selected_span.x:
		_original_rows = _plan.notes.duplicate(true)
		_plan.edit_span = _selected_span
		_plan.additions_only = _preserve.button_pressed
	_animation = AnimationDraft.new(chart, _plan.duration_ms, _workspace.automatic.prepare_project_artwork())

func _import_audio(arguments: Dictionary) -> Dictionary:
	if not OfficialAccess.features_enabled():
		return {"error": OfficialAccess.LOCKED}
	var path := AudioImport.local_path(arguments.get("path"))
	if path.is_empty():
		return {"error": "请指定本机 WAV、MP3 或 OGG 的绝对路径。"}
	if _agent._chat_has_changes() or _animation.has_assets():
		return {"error": "本轮存在待提交的修改，请先处理草稿，再导入音频。"}
	if not await _request_approval("import_audio", {"path": path}):
		return {"error": "音频导入已取消或被拒绝。"}
	if not busy or _generation != _workspace._document_generation or _project_signature != _signature():
		return {"error": "工程已发生变化，请重新确认需要导入的音频。"}
	var result := AudioImport.load_into(_workspace, path)
	if not result.has("error"):
		_generation = _workspace._document_generation
		_history_generation = _generation
		_prepare_draft()
		_agent.rebase_after_audio_import(_plan, _animation,
			Automatic.music_for_agent(_workspace.chart, _workspace._cached_chart_music(), _plan.duration_ms),
			_workspace.automatic._estimate_mood(), _workspace._agent_audio_selection())
	return result

func _recent_history() -> Array[Dictionary]:
	var prior: Array[Dictionary] = []
	var size := 0
	for index in range(_history.size() - 1, maxi(-1, _history.size() - 11), -1):
		var message := _history[index]
		size += JSON.stringify(message).to_utf8_buffer().size()
		if size > HISTORY_BYTES:
			break
		prior.push_front(message)
	return prior

func _local_help(text: String) -> Array:
	var question := text.to_lower()
	if not ("在哪" in question or "哪里" in question or "入口" in question or "怎么" in question or "如何" in question):
		return []
	var query := ""
	if "错误包" in question or "日志" in question:
		query = "导出错误包"
	elif "视频" in question or "mp4" in question:
		query = "渲染 mp4"
	elif "json" in question or "谱面文件" in question:
		query = "导出谱面文件"
	elif "导出" in question:
		query = "保存或导出谱面"
	elif "教程" in question:
		query = "查看新手教程"
	return _workspace._copilot_help(query).topics if not query.is_empty() else []

func _capture(times: Array) -> Dictionary:
	if _generation != _workspace._document_generation:
		return {"error": "当前工程已切换。"}
	return await Frames.capture(self, _workspace.chart, _plan, _animation, times, _agent.draft_changes())

func _on_action(name: String, arguments: Dictionary) -> void:
	if busy:
		if name in ["请求模型", "重试模型请求"]:
			var caption := "纯文字重试" if name == "重试模型请求" and arguments.get("text_only", false) else name
			_begin_step("%s · %s · %s" % [caption, arguments.service, arguments.model])
		elif name != "等待重试":
			var caption: String = _workspace.automatic._action_caption(name, "执行工具")
			if name == "get_editor_help":
				caption = "软件内置教程 · " + str(arguments.get("query", "查看入口")).left(60)
			elif name == "reply":
				caption = "整理回复"
			elif name == "get_emotions":
				caption = "Music2Emo · 读取已有分段情绪"
			elif name == "get_beats":
				caption += " · " + {"beats": "拍点", "downbeats": "小节重拍", "onsets": "起音", "accents": "力度重音"}.get(arguments.get("kind", "beats"), "节奏标记")
			if name in ["get_bpm", "get_beats", "get_melody", "get_sustain_candidates"]:
				caption = "当前音频已有分析 · " + caption
			_begin_step(caption)

func _on_action_result(name: String, _arguments: Dictionary, accepted: bool) -> void:
	if accepted and _auto_approve.button_pressed and name in Agent.WRITES:
		_accepted_operations.append({"tool": name, "arguments": _arguments.duplicate(true)})
	var status := "已完成" if accepted else ("已拒绝" if is_instance_valid(_step) and _step_status.text == "已拒绝" else "执行失败")
	_end_step(status, accepted)
	_workspace.diagnostics.record("copilot.tool", {"action": _workspace.automatic._action_caption(name), "success": accepted},
		"info" if accepted else "warning")

func _show_action_detail(message: String) -> void:
	if is_instance_valid(_step) and not message.is_empty():
		var review := str(_step.get_meta("review_note", ""))
		_step_detail.text = (review + "\n" + message if not review.is_empty() else message).left(660)
		_step_detail.show()

func _offer_retry(message: String) -> void:
	if not busy:
		return
	_retry_message = message
	_status.text = message
	_status.tooltip_text = message
	_status.show()
	_refresh_controls()

func _retry_request() -> void:
	_retry_message = ""
	_status.hide()
	_refresh_controls()
	_agent.retry_request()

func _request_approval(name: String, arguments: Dictionary) -> bool:
	if not busy or _generation != _workspace._document_generation:
		return false
	var profile_write := name in Agent.ProfileTools.WRITES
	if _selected_span.y > _selected_span.x and name not in ["finish", "add_notes", "move_notes", "delete_notes", "set_positions", "set_note_lead_in", "resize_holds", "set_hold_path"]:
		return false
	if _selected_span.y > _selected_span.x and _preserve.button_pressed and name not in ["finish", "add_notes"]:
		return false
	var operation_key := name + JSON.stringify(arguments)
	if _refused_operations.has(operation_key):
		_step_status.text = "已拒绝"
		return false
	var review_note := ""
	if _auto_approve.button_pressed and not profile_write:
		var turn := _review_turn
		var proposal := _review_scope.duplicate()
		proposal["tool"] = name
		proposal["arguments"] = arguments
		proposal["song_duration_ms"] = _plan.duration_ms
		proposal["selected_event_ids"] = _workspace.chart.selected_event_ids.duplicate()
		if Agent.Context.TOOLS.has(name):
			proposal["tool_description"] = Agent.Context.TOOLS[name][2]
		var ids: Array = arguments.ids.duplicate() if arguments.get("ids") is Array else []
		for field in ["notes", "positions", "moves", "holds"]:
			if arguments.get(field) is Array:
				for entry: Variant in arguments[field]:
					if entry is Dictionary and entry.has("id"):
						ids.append(entry.id)
		var targets := {}
		for id: Variant in ids:
			if (id is int or id is float) and _plan and _plan.notes.has(int(id)):
				targets[int(id)] = _plan.notes[int(id)]
		proposal["current_targets"] = targets
		if name == "finish":
			proposal["accepted_operations"] = _accepted_operations
		_step_status.text = "审查中"
		var verdict := await _reviewer.review(_review_settings, proposal)
		if not busy or turn != _review_turn or _generation != _workspace._document_generation:
			return false
		review_note = str(verdict.get("reason", "审查服务未给出有效结论，请手动确认。"))
		_step.set_meta("review_note", "自动审批 · " + review_note)
		_step_detail.text = "自动审批 · " + review_note
		_step_detail.show()
		match verdict.get("decision", "ask"):
			"allow":
				return true
			"deny":
				_step_status.text = "已拒绝"
				_refused_operations[operation_key] = true
				return false
	_approval_title.text = "等待批准 · " + _workspace.automatic._action_caption(name)
	if profile_write:
		_approval_details.text = Agent.ProfileTools.approval_text(name, arguments)
	elif name == "import_audio":
		_approval_details.text = "确认后立即导入音频，保留现有音符并清空旧分析。\n" + str(arguments.path)
	elif name == "finish":
		_approval_details.text = "将本轮已批准的草稿写入当前谱面。\n" + _describe(arguments)
	elif name == "analyze_audio":
		_approval_details.text = "在本机分析指定音轨，结果供助手制谱使用。\n" + _describe(arguments)
	else:
		_approval_details.text = "应用到当前草稿，完成后将一次性写入谱面。\n" + _describe(arguments)
		if _plan:
			var positions := PackedStringArray()
			var ids: Array = arguments.ids.duplicate() if arguments.get("ids") is Array else []
			if arguments.get("notes") is Array:
				for row: Variant in arguments.notes:
					if row is Dictionary and row.has("id"):
						ids.append(row.id)
			for id in ids.slice(0, 12):
				if (id is int or id is float) and _plan.notes.has(int(id)):
					var location: Dictionary = _workspace.chart.ruler_position(_plan.notes[int(id)].time_ms)
					positions.append("#%d  %s" % [id, location.label])
			if not positions.is_empty():
				_approval_details.text = "目标音符\n" + "\n".join(positions) + "\n\n" + _approval_details.text
	if not review_note.is_empty():
		_approval_details.text = review_note + "\n\n" + _approval_details.text
	_approval_details.scroll_vertical = 0
	_approval.show()
	_step_status.text = "待批准"
	_refresh_steps()
	var approved: bool = await approval_resolved
	if busy and not approved:
		_refused_operations[operation_key] = true
	return approved

func _resolve_approval(approved: bool) -> void:
	if not _approval.visible:
		return
	_approval.hide()
	_step_status.text = "进行中" if approved else "已拒绝"
	_refresh_steps()
	approval_resolved.emit(approved)

func _signature(snapshot: Dictionary = {}) -> Dictionary:
	var chart: Node = _workspace.chart
	if snapshot.is_empty():
		snapshot = chart._snapshot_notes()
	var state := {"audio": chart.audio_path, "audio_duration": chart.audio_duration_ms, "audio_delay": chart.audio_delay_ms,
		"tracks": chart.track_count, "background": chart.preview_bg_image_path, "mask": chart.preview_mask_image_path,
		"metadata": chart.chart_info.duplicate()}
	for key: String in EDITABLE_STATE:
		state[key] = snapshot.get(key)
	var notes: Dictionary = snapshot.get("notes", {}).duplicate(true)
	for note: Dictionary in notes.values():
		note.erase("time_unit")
		note.erase("length")
	state.notes = notes
	return state

var _pending_edits := {}

func _finish(success: bool, message: String, edits: Dictionary = {}) -> void:
	if not busy:
		return
	_pending_edits = edits
	if success and not _requested_difficulty.is_empty() and not _plan.edited.is_empty():
		var metadata: Dictionary = _pending_edits.get("metadata", {}).duplicate()
		metadata["difficulty"] = _requested_difficulty
		_pending_edits["metadata"] = metadata
	if success and _generation != _workspace._document_generation:
		_apply_result(false, "当前工程已经切换。请在新工程中重新发送请求。")
	elif success and _selected_span.y > _selected_span.x:
		_review_segment(message)
	elif success and _signature() != _project_signature:
		_ask_conflict(message)
	else:
		_apply_result(success, message)

func _review_segment(summary: String) -> void:
	var added := 0
	var changed := 0
	var removed := 0
	for id in _plan.edited:
		var before: Dictionary = _original_rows.get(id, {})
		var after: Dictionary = _plan.notes.get(id, {})
		if before == after: continue
		for entry in [before, after]:
			if not entry.is_empty() and (entry.time_ms - entry.lead_ms < _selected_span.x or entry.time_ms >= _selected_span.y or entry.time_ms + entry.duration_ms > _selected_span.y):
				_apply_result(false, "草稿包含超出选区的判定或长键，已保留原谱。")
				return
		if not before.is_empty() and _preserve.button_pressed:
			_apply_result(false, "草稿改动了要求保留的音符，已保留原谱。")
			return
		if before.is_empty(): added += 1
		elif after.is_empty(): removed += 1
		else: changed += 1
	if not _pending_edits.is_empty() or _animation.has_assets() or not _animation.layers.is_empty() or not _animation.mask_cues.is_empty() or _signature() != _project_signature:
		_apply_result(false, "选区或工程内容已变化，请重新提交此段。")
		return
	_comparison = ConfirmationDialog.new()
	_comparison.title = "选区改谱对比"
	_comparison.ok_button_text = "接受草稿"
	_comparison.cancel_button_text = "丢弃"
	_comparison.exclusive = true
	_workspace.host.add_child(_comparison)
	var player := preload("res://desktop/chart_audition.gd").new()
	player.name = "Audition"
	_comparison.add_child(player)
	var chart: Node = _workspace.chart
	player.configure(chart, _selected_span)
	chart.pause_rt_playback()
	player.add_variant(chart)
	var draft := player.add_variant(chart)
	draft.chart.apply_automatic_notes(_plan.notes, _plan.edited, [], [], {}, {})
	player.refresh_variant(0)
	player.refresh_variant(1)
	player.select(0, _selected_span.x)
	var controls := HFlowContainer.new()
	player.add_child(controls)
	_make_button(controls, "循环试听原谱", player.select.bind(0, _selected_span.x, true))
	_make_button(controls, "循环试听草稿", player.select.bind(1, _selected_span.x, true))
	_make_button(controls, "暂停", player.pause)
	_comparison.dialog_text = "%s – %s　新增 %d · 移动或调整 %d · 删除 %d" % [chart.ruler_clock(_selected_span.x),chart.ruler_clock(_selected_span.y),added,changed,removed]
	_comparison.confirmed.connect(func():
		if _generation == _workspace._document_generation and _signature() == _project_signature: _apply_result(true, summary)
		else: _apply_result(false, "试听期间工程已变化，已保留当前谱面。"))
	_comparison.canceled.connect(func(): _apply_result(false, "已丢弃选区草稿。"))
	DialogLayout.present(_comparison, Vector2i(640,440))

func _ask_conflict(message: String) -> void:
	if not is_instance_valid(_conflict):
		_conflict = ConfirmationDialog.new()
		_conflict.title = "谱面已有手动编辑"
		_conflict.dialog_text = "等待期间谱面发生了改动。你可以恢复本轮开始时的谱面并应用助手草稿，也可以保留当前编辑并丢弃草稿。覆盖后可撤销。"
		_conflict.dialog_autowrap = true
		_conflict.ok_button_text = "覆盖并应用草稿"
		_conflict.cancel_button_text = "丢弃草稿"
		_conflict.exclusive = true
		_conflict.transient = true
		_conflict.confirmed.connect(_resolve_conflict.bind(true))
		_conflict.canceled.connect(_resolve_conflict.bind(false))
		_workspace.host.add_child(_conflict)
	_pending_summary = message
	DialogLayout.present(_conflict, Vector2i(530, 175))

func _resolve_conflict(overwrite: bool) -> void:
	_conflict.hide()
	if not busy:
		return
	if overwrite and _generation == _workspace._document_generation:
		_apply_result(true, _pending_summary, _original_chart)
	else:
		_apply_result(false, "已保留当前谱面，草稿已丢弃。")

func _apply_result(success: bool, message: String, restore_before: Dictionary = {}) -> void:
	var center_ranges: Array = []
	if success and not OfficialAccess.features_enabled():
		success = false
		message = OfficialAccess.LOCKED
	if success and _animation.has_assets():
		var root: String = _workspace._get_or_create_root()
		if root.is_empty() or _animation.save_assets(root) != OK:
			success = false
			message = "无法保存图像素材，本轮草稿未写入。"
	if success:
		if not _plan.edited.is_empty():
			center_ranges = _plan.check_conflicts().get("center_ranges", [])
		_workspace.chart.apply_automatic_notes(_plan.notes, _plan.edited, _animation.layers.values(),
			_animation.mask_cues.values(), restore_before, _pending_edits)
		message += "\n已写入谱面，可用一次撤销恢复。"
	_workspace.diagnostics.record("copilot.finish", {"success": success, "note_changes": _plan.edited.size()},
		"info" if success else "warning")
	_complete(message)
	for span: Dictionary in center_ranges.slice(0, 4):
		var caption := "落点集中 · %s–%s" % [_workspace.chart.ruler_clock(span.from_ms), _workspace.chart.ruler_clock(span.to_ms)]
		var button := _make_button(_transcript, caption, _review_phrase.bind(span, _generation))
		button.tooltip_text = "定位到这段谱面，查看落点分布"
		button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

func _review_phrase(span: Dictionary, generation: int) -> void:
	if generation != _workspace._document_generation:
		return
	var chart: Node = _workspace.chart
	var ids: Array[int] = []
	for id: int in chart.notes:
		var note = chart.notes[id]
		var hit: int = note.judge_time if note.type == 2 else note.end_time
		if hit >= span.from_ms and hit <= span.to_ms:
			ids.append(id)
	_workspace._set_game_mode(false)
	_workspace._open_inspector_page("键设置")
	chart.set_note_selection(ids)
	chart.set_rt_pointer_time(span.from_ms)
	_workspace.grid._auto_scroll_to_ms(span.from_ms)
	_workspace._set_loop_range(Vector2(span.from_ms, span.to_ms))

func _complete(message: String) -> void:
	_end_step("已结束", false)
	if is_instance_valid(_stream_text):
		Markdown.render(_stream_text, message)
	else:
		_append("助手", message)
	_history.append({"role": "assistant", "text": message.left(4000)})
	_clear_turn()

func cancel() -> void:
	if not busy:
		return
	_agent.cancel()
	_review_turn += 1
	_reviewer.stop()
	if is_instance_valid(_conflict):
		_conflict.hide()
	if _approval.visible:
		_approval.hide()
		approval_resolved.emit(false)
	_workspace.diagnostics.record("copilot.cancel")
	_end_step("已停止", false)
	_append("助手", "本轮已停止，草稿已丢弃。")
	_clear_turn()

func _clear_turn() -> void:
	if is_instance_valid(_comparison):
		_comparison.hide()
		_comparison.queue_free()
		_comparison = null
	_original_rows.clear()
	_selected_span = Vector2(-1, -1)
	_preserve.hide()
	_preserve.disabled = false
	_review_scope.clear()
	_review_settings.clear()
	_accepted_operations.clear()
	_refused_operations.clear()
	_requested_difficulty = ""
	busy = false
	_retry_message = ""
	_steps_list.hide()
	_refresh_steps()
	_plan = null
	_animation = null
	_project_signature.clear()
	_original_chart = {}
	_pending_summary = ""
	_pending_edits = {}
	_stream_text = null
	_status.text = ""
	_status.hide()
	_refresh_controls()

func _refresh_controls() -> void:
	_preserve.disabled = busy
	_compose_button.disabled = busy
	_send_button.disabled = busy or _editor.text.strip_edges().is_empty()
	_stop_button.visible = busy
	_retry_button.visible = busy and not _retry_message.is_empty()
	_auto_approve.disabled = busy
	if is_instance_valid(_last_edit):
		_last_edit.disabled = busy

static func _describe(arguments: Dictionary, indentation := "") -> String:
	var lines := PackedStringArray()
	for key: String in arguments:
		if not FIELD_NAMES.has(key):
			continue
		var value: Variant = arguments[key]
		var label: String = FIELD_NAMES[key]
		if value is Array:
			lines.append("%s%s（%d 项）" % [indentation, label, value.size()])
			for index in range(value.size()):
				var item: Variant = value[index]
				var detail := _describe(item, indentation + "    ") if item is Dictionary else _display_value(item)
				lines.append("%s  %d. %s" % [indentation, index + 1, detail.strip_edges()])
		else:
			lines.append("%s%s　%s" % [indentation, label, _display_value(value)])
	return "\n".join(lines) if not lines.is_empty() else "无参数"

static func _display_value(value: Variant) -> String:
	if value is bool:
		return "是" if value else "否"
	return str(VALUE_NAMES.get(str(value), value)).left(100)
