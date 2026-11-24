extends SceneTree

const ChatStream := preload("res://desktop/chat_completion_stream.gd")

var _actions: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _wait(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 8000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return predicate.call()

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
	var chart: Node = desktop.chart
	chart.set_rhythm_analysis({"duration_ms": 16000, "beats": [2000, 2400, 4000, 8000],
		"downbeats": [2000, 8000], "onsets": [2000, 2400, 8000], "accents": [2000, 8000],
		"tempo_curve": [{"time_ms": 0, "bpm": 150}], "melody": [{"time_ms": 2000, "hz": 440}]})
	var copilot: Node = desktop.copilot
	desktop.automatic._settings = {"url": args[1], "model": "mock-retry", "key": "loopback-only"}
	desktop._toggle_copilot()
	copilot._agent.action_finished.connect(func(name: String, _arguments: Dictionary, accepted: bool):
		if accepted:
			_actions.append(name))
	copilot._editor.text = "测试流式中断后重试当前请求"
	copilot._submit()
	_approve_changes.call_deferred(copilot)
	for expected in ["连接中断", "连接中断", "AGIPlan 报告模型流式响应中断"]:
		var reached := await _wait(func():
			var button: Variant = copilot.get("_retry_button")
			return not copilot.busy or (button is Button and button.visible))
		if (not reached or not copilot.busy or copilot._plan.edited.size() != 1
				or not copilot._status.text.contains(expected) or not chart.notes.is_empty()
				or _actions != ["add_notes"] or copilot._agent._round != 2):
			push_error("A disconnected second request should offer retry and preserve the first round's draft. " + copilot._status.text)
			quit(1)
			return
		if expected.begins_with("AGIPlan") and not copilot._status.text.contains("tr_smoke"):
			push_error("The AGIPlan trace comment should be visible with the in-stream error.")
			quit(1)
			return
		copilot._retry_button.pressed.emit()
		if copilot._retry_button.visible:
			push_error("Retry must be unavailable while its request is in flight.")
			quit(1)
			return
	if (not await _wait(func(): return not copilot.busy) or chart.notes.size() != 2
			or _actions != ["add_notes", "add_notes", "finish"]
			or copilot._agent._request.timeout != 900.0 or ChatStream.TIMEOUT_MS != 900000):
		push_error("A complete streamed retry should commit the approved draft once. " + copilot._status.text)
		quit(1)
		return
	print("AGENT_RETRY_SMOKE verified")
	quit()

func _approve_changes(copilot: Node) -> void:
	while copilot.busy:
		if copilot._approval.visible:
			copilot._resolve_approval(true)
		await process_frame
