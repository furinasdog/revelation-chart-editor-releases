extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	change_scene_to_file("res://main/main.tscn")
	await scene_changed
	await process_frame
	var desktop: Node = current_scene.desktop
	var passed := not root.unresizable
	if DisplayServer.get_name() != "headless" and root.mode == Window.MODE_WINDOWED:
		var work_area := DisplayServer.screen_get_usable_rect(root.current_screen)
		var decorated := Rect2i(root.get_position_with_decorations(), root.get_size_with_decorations())
		print("Desktop window=", decorated, " work area=", work_area)
		passed = passed and decorated.size.x <= work_area.size.x and decorated.size.y <= work_area.size.y
	for child in root.find_children("*", "Window", true, false):
		if child.visible:
			child.hide()
	root.size = Vector2i(800, 560)
	desktop._set_scale(0.0)
	await process_frame
	passed = passed and is_equal_approx(root.content_scale_factor, 0.75)
	for scale: float in [1.0, 1.5, 2.0]:
		root.size = Vector2i(1280, 800)
		desktop._set_scale(scale)
		await process_frame
		desktop.automatic.open_settings()
		var dialog: ConfirmationDialog = desktop.automatic._settings_dialog
		for frame in 4:
			await process_frame
		var area := Rect2i(root.get_visible_rect())
		var opened := dialog.size
		var footer := dialog.get_ok_button().get_global_rect()
		print("Agent scale=", scale, " area=", area.size, " dialog=", opened, " at=", dialog.position, " footer=", footer.end.y)
		passed = passed and area.encloses(Rect2i(dialog.position, dialog.size)) and opened.y >= 185 and opened.y <= 360 and opened.x >= 540
		var corner := Vector2(dialog.position + dialog.size) + Vector2.ONE
		var target := corner + Vector2(Vector2i(350, 180) - opened)
		_drag_corner(corner, target)
		for frame in 3:
			await process_frame
		print("Shrink size=", dialog.size, " locked=", dialog.unresizable)
		passed = passed and not dialog.unresizable and dialog.size.y <= 190 and dialog.size.x <= 360
		passed = passed and dialog.get_ok_button().get_global_rect().end.y <= dialog.size.y
		var scroll: ScrollContainer
		var forms := dialog.find_children("*", "ScrollContainer", true, false)
		if not forms.is_empty():
			scroll = forms[0]
		passed = passed and scroll != null and scroll.get_v_scroll_bar().visible
		if scroll:
			var edits := dialog.find_children("*", "LineEdit", true, false)
			passed = passed and edits.size() == 3
			scroll.ensure_control_visible(edits.back())
			await process_frame
			passed = passed and scroll.scroll_vertical > 0
		dialog.hide()
	desktop.automatic._settings = {"url":"https://example.invalid/v1", "model":"fixture", "key":"fixture"}
	desktop.chart.audio_path = "fixture.wav"
	desktop.background_mode = false
	var easer := preload("res://main/easing_editor.gd").new()
	easer.hide()
	current_scene.add_child(easer)
	for open_window: Callable in [desktop.mcp.open, desktop.preferences.open, desktop._open_about,
			desktop._open_release_notes, desktop._open_feature_finder, desktop._onboarding.open,
			desktop.copilot.open_compose, desktop.copilot._ask_conflict.bind("fixture"),
			desktop._notify.bind("较长的分析说明".repeat(100)), easer.popup_editor]:
		root.size = Vector2i(1280, 800)
		desktop._set_scale(1.5)
		open_window.call()
		for frame in 4:
			await process_frame
		var active: Window = null
		for child in root.find_children("*", "Window", true, false):
			if child.visible and child.has_node("DialogLayout"):
				active = child
				break
		if active == null:
			push_error("Window did not open from its normal entry: " + str(open_window))
			passed = false
			continue
		root.size = Vector2i(820, 530)
		desktop._set_scale(2.0)
		for frame in 4:
			await process_frame
		var inside := Rect2i(root.get_visible_rect()).encloses(Rect2i(active.position, active.size))
		if active is AcceptDialog:
			var button := (active as AcceptDialog).get_ok_button()
			inside = inside and Rect2(Vector2.ZERO, active.size).encloses(button.get_global_rect())
		print("DIALOG ", active.title, " ", active.size, " contained=", inside)
		passed = passed and inside and not active.unresizable
		active.hide()
	if not passed:
		push_error("Dialog bounds, footer or manual shrinking failed.")
	print("DIALOG_SIZING passed=", passed)
	quit(0 if passed else 1)

func _drag_corner(corner: Vector2, target: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = corner
	press.pressed = true
	root.push_input(press, true)
	var motion := InputEventMouseMotion.new()
	motion.position = target
	motion.relative = target - corner
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = target
	root.push_input(release, true)
