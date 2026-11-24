extends SceneTree

const Automatic := preload("res://desktop/automatic_chart.gd")
const Plan := preload("res://desktop/auto_chart_plan.gd")
const DraftAnimation := preload("res://desktop/agent_animation.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1

func _wait(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
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
	var chart: Node = desktop.chart
	var dock: PanelContainer = desktop.copilot
	desktop._onboarding._chooser.hide()
	root.size = Vector2i(1600, 900)
	desktop._set_scale(1.0)
	await process_frame
	var menu: PopupMenu = desktop._copilot_menu
	var index: int = desktop._copilot_item
	_check(not dock.visible and menu.is_item_checkable(index) and menu.get_item_text(index) == "Revelation Co-pilot",
		"Co-pilot checkbox starts closed and uses the requested name")
	var full_width: float = desktop.rollout.size.x
	menu.id_pressed.emit(index)
	_check(dock.visible and menu.is_item_checked(index) and desktop.rollout.size.x < full_width
		and is_equal_approx(desktop.rollout.size.x, desktop._copilot_divider.position.x), "Opening Co-pilot shifts the workspace aside")
	var initial_width := dock.size.x
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(-70, 0)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	desktop._copilot_divider.gui_input.emit(press)
	desktop._copilot_divider.gui_input.emit(drag)
	press.pressed = false
	desktop._copilot_divider.gui_input.emit(press)
	await process_frame
	_check(dock.size.x > initial_width and not desktop.rollout.get_rect().intersects(dock.get_rect()),
		"Dragging the divider resizes the sidebar without overlaying the timeline")
	dock._editor.text = "在哪里导出谱面？"
	dock._submit()
	_check(not dock.busy and str(dock._history[-1].text).contains("导出谱面压缩包"), "Built-in help answers with the actual export menu")
	desktop.automatic.open_settings()
	var settings: Window = desktop.automatic._settings_dialog
	var fields := settings.find_children("*", "LineEdit", true, false)
	fields[0].text = args[1]
	fields[1].text = "synthetic-local-copilot-key"
	fields[2].text = "mock-model"
	settings.confirmed.emit()
	settings.hide()
	var stored := ConfigFile.new()
	_check(stored.load(Automatic.CONFIG_PATH) == OK and stored.get_value("agent", "key", "") == "synthetic-local-copilot-key",
		"Agent settings persist the masked input in the user profile")
	_check(desktop.import_audio(args[0], false), "Fixture loads")
	dock._editor.text = "请添加两个键，第二项由我选择是否批准。"
	dock._submit()
	if not await _wait(func(): return dock._approval.visible):
		push_error("First tool proposal timed out. " + str(dock._history))
		quit(2)
		return
	_check(dock._approval_title.text.contains("写入音符") and dock._approval_details.text.contains("普通键")
		and chart.notes.is_empty() and dock._plan.notes.is_empty(), "Read action was automatic; the first Chinese write proposal is pending")
	dock._resolve_approval(true)
	if not await _wait(func(): return dock._approval.visible):
		push_error("Second tool proposal timed out.")
		quit(2)
		return
	_check(dock._plan.notes.size() == 1 and chart.notes.is_empty(), "Approval only changes the staged draft")
	dock._resolve_approval(false)
	_check(await _wait(func(): return not dock.busy), "Agent finishes after the second action is refused")
	_check(chart.notes.size() == 1 and chart.notes.values()[0].end_time == 4500, "Only the approved write reaches the live scene")
	dock._editor.text = "现在有几个键？"
	dock._submit()
	_check(await _wait(func(): return is_instance_valid(dock._stream_text) or not dock.busy),
		"The model stream starts displaying content")
	_check(dock.busy and is_instance_valid(dock._stream_text) and not dock._stream_text.text.begins_with("{"),
		"Partial user-facing reply arrives before the endpoint finishes")
	_check(await _wait(func(): return not dock.busy or dock._approval.visible), "Follow-up finishes")
	_check(not dock._approval.visible and str(dock._history[-1].text).contains("一个"), "Reading the score needs no approval and responds in the conversation")
	dock._editor.text = "停在第三个提议，随后取消。"
	dock._submit()
	_check(await _wait(func(): return dock._approval.visible), "A pending write can be cancelled")
	desktop._set_copilot_visible(false)
	_check(not dock.busy and not dock.visible and chart.notes.size() == 1
		and is_equal_approx(desktop.rollout.size.x, full_width), "Closing cancels the draft and restores the layout")
	chart.undo()
	_check(chart.notes.is_empty(), "A Co-pilot editing turn is one undo")
	desktop._set_copilot_visible(true)
	_prepare_conflicting_turn(desktop, dock)
	dock._finish(true, "应用草稿")
	_check(dock.busy and dock._conflict.visible and chart.notes.values()[0].end_time == 3000,
		"An intervening edit opens a modal decision and leaves the chart intact")
	dock._resolve_conflict(false)
	_check(not dock.busy and chart.notes.values()[0].end_time == 3000, "Discard preserves the manual edit")
	chart.undo()
	_prepare_conflicting_turn(desktop, dock)
	dock._finish(true, "应用草稿")
	dock._resolve_conflict(true)
	_check(chart.notes.size() == 1 and chart.notes.values()[0].end_time == 6000, "Selecting overwrite applies the draft")
	chart.undo()
	_check(chart.notes.size() == 1 and chart.notes.values()[0].end_time == 3000, "Undo restores the manually edited chart")
	_check(not desktop.grid._edge_drag_active(), "Idle pointers at either timeline edge are ineligible for edge scroll")
	_check(change_scene_to_file("res://main/main.tscn") == OK, "Reload the editor scene")
	await scene_changed
	await process_frame
	_check(current_scene.desktop.automatic._settings.key == "synthetic-local-copilot-key"
		and not current_scene.desktop.copilot.visible, "A new editor reloads the key and starts with the sidebar closed")
	print("COPILOT_SMOKE failures=", failures)
	quit(1 if failures else 0)

func _prepare_conflicting_turn(desktop: Node, dock: PanelContainer) -> void:
	var chart: Node = desktop.chart
	dock._generation = desktop._document_generation
	dock._original_chart = chart._snapshot_notes()
	dock._project_signature = dock._signature(dock._original_chart)
	dock._plan = Plan.new(chart)
	dock._animation = DraftAnimation.new(chart, 16000, [])
	dock._plan.edit("add_notes", [{"type": "note", "time_ms": 6000, "lane": 0, "x": 850, "y": 480}])
	dock.busy = true
	chart.add_note_at_times(0, 2200, 3000, 0, 1, Vector2(850, 480))
