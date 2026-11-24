extends SceneTree

const ToolReply := preload("res://desktop/agent_tool_reply.gd")

var _actions: Array[String] = []
var _previews: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _wait(check: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 14000
	while not check.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return check.call()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desktop: Node = current_scene.desktop
	desktop._onboarding._chooser.hide()
	if not desktop.import_audio(args[0], false):
		quit(2)
		return
	desktop.chart.set_rhythm_analysis({"duration_ms": 16000,
		"tempo_curve": [{"time_ms": 0, "bpm": 122, "confidence": 1}],
		"emotions": [{"time_ms": 0, "end_ms": 16000, "valence": 4, "arousal": 5, "tags": [{"label": "calm", "score": 0.8}]}]})
	desktop.automatic._settings = {"url": args[1], "model": "mock-deepseek-flash", "key": "test-only"}
	desktop._set_copilot_visible(true)
	var dock: PanelContainer = desktop.copilot
	dock._agent.action_finished.connect(func(name: String, _arguments: Dictionary, accepted: bool):
		if accepted:
			_actions.append(name))
	dock._agent.reply_preview.connect(func(value: String): _previews.append(value))
	dock._editor.text = "测试 DSML 读取"
	dock._submit()
	if not await _wait(func(): return not dock.busy):
		push_error("DSML tools did not finish.")
		quit(1)
		return
	if (_actions != ["get_bpm", "get_project_context", "get_emotions", "get_audio_features", "reply"]
			or str(dock._history[-1].get("text", "")) != "工具结果显示速度 122 BPM。"
			or _previews.any(func(value: String): return "<" in value or "DSML" in value)):
		push_error("DSML calls must be executed with typed parameters; raw markup must stay out of the chat.")
		quit(1)
		return
	var steps: Array = dock._steps_list.get_children()
	if steps.size() != 7 or dock._steps_button.text != "▸ 已完成 7 个步骤" or dock._steps_list.visible:
		push_error("The activity list must retain every request and tool.")
		quit(1)
		return
	dock._steps_button.pressed.emit()
	if not dock._steps_list.visible or not dock._steps_button.text.begins_with("▾"):
		push_error("The collapsed activity can be reopened after the reply.")
		quit(1)
		return
	for card in steps:
		var style: StyleBoxFlat = card.get_theme_stylebox("panel") if card is PanelContainer else null
		var title: Label = card.get_child(0).get_child(0) if style else null
		if not style or style.border_width_left == 0 or title.text[0].is_valid_int() or "轮" in title.text:
			push_error("Activities must be outlined cards with unnumbered titles.")
			quit(1)
			return
	_actions.clear()
	dock._editor.text = "测试原生工具流"
	dock._submit()
	if not await _wait(func(): return not dock.busy) or _actions != ["get_bpm", "reply"]:
		push_error("Fragmented native tool_calls must use the same execution path.")
		quit(1)
		return
	_actions.clear()
	dock._editor.text = "测试 DSML 写入审批"
	dock._submit()
	if not await _wait(func(): return dock._approval.visible) or not desktop.chart.notes.is_empty():
		push_error("DSML changes must wait for user approval.")
		quit(1)
		return
	if dock._step_status.text != "待批准":
		push_error("The pending activity card must show its approval state.")
		quit(1)
		return
	dock._resolve_approval(false)
	if not await _wait(func(): return not dock.busy) or not desktop.chart.notes.is_empty():
		push_error("Declining a DSML write must leave the chart unchanged.")
		quit(1)
		return
	_actions.clear()
	dock._editor.text = "测试不完整调用"
	dock._submit()
	if not await _wait(func(): return dock._retry_button.visible) or not _actions.is_empty() or not desktop.chart.notes.is_empty():
		push_error("Repeated incomplete DSML calls must pause for retry without executing any action.")
		quit(1)
		return
	dock._retry_button.pressed.emit()
	if not await _wait(func(): return not dock.busy) or _actions != ["reply"] or dock._history[-1].text != "已恢复。":
		push_error("Retrying a malformed tool response must resume the pending request.")
		quit(1)
		return
	if ToolReply.parse_markup('<｜DSML｜function_calls><｜DSML｜invoke name="get_bpm"></｜DSML｜invoke></｜DSML｜function_calls>', 1).size() != 1:
		push_error("The official V3.2 spelling must also parse.")
		quit(1)
		return
	dock._editor.text = "尚未发送的草稿"
	dock._compose_button.pressed.emit()
	dock._compose_dialog.canceled.emit()
	dock._compose_dialog.hide()
	if dock.busy or dock._editor.text != "尚未发送的草稿":
		push_error("Canceling the preset must preserve the composer and avoid a request")
		quit(1)
		return
	dock._compose_button.pressed.emit()
	dock._compose_level.select(2)
	dock._compose_brief.text = "保留主歌"
	var old_level: String = desktop.chart.chart_info.difficulty
	dock._compose_dialog.confirmed.emit()
	if not await _wait(func(): return dock._approval.visible) or desktop.chart.chart_info.difficulty != old_level:
		push_error("The requested difficulty and notes must remain staged until approved")
		quit(1)
		return
	dock._resolve_approval(true)
	if not await _wait(func(): return not dock.busy) or desktop.chart.notes.size() != 1 or desktop.chart.chart_info.difficulty != "EX":
		push_error("Preset confirmation must submit the user's brief and apply the selected difficulty")
		quit(1)
		return
	desktop.chart.undo()
	if not desktop.chart.notes.is_empty() or desktop.chart.chart_info.difficulty != old_level:
		push_error("Undo must restore the notes and difficulty together")
		quit(1)
		return
	if dock._auto_approve.button_pressed:
		push_error("Automatic review must be opt-in")
		quit(1)
		return
	dock._auto_approve.button_pressed = true
	for brief in ["审批测试：只读，查看速度。", "审批测试：服务异常，在4.2秒补一个键。", "审批测试：在4.2秒补一个键。"]:
		dock._send_prompt(brief)
		if "服务异常" in brief:
			if not await _wait(func(): return dock._approval.visible) or not desktop.chart.notes.is_empty():
				push_error("Unavailable reviewer must fall back to the manual approval card")
				quit(1)
				return
			dock._resolve_approval(false)
		if not await _wait(func(): return not dock.busy) or desktop.chart.notes.size() != int(brief == "审批测试：在4.2秒补一个键。"):
			push_error("Independent reviewer failed to enforce: " + brief)
			quit(1)
			return
	var bubble: RichTextLabel = dock._append("助手", "## 结果\n- **已补充** `4.2s`\n[b]保留字面文本[/b]")
	if bubble.get_parsed_text() != "结果\n• 已补充 4.2s\n[b]保留字面文本[/b]":
		push_error("Markdown should be readable and BBCode must stay literal")
		quit(1)
		return
	print("COPILOT_TOOL_REPLY_SMOKE verified")
	quit()
