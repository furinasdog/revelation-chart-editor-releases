extends ScrollContainer

func _ready() -> void:
	follow_focus = true
	get_h_scroll_bar().custom_minimum_size.y = 14

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventMouseButton or not event.pressed:
		return
	var bar := get_h_scroll_bar()
	if not bar.visible or not Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
		return
	var direction := 0
	match event.button_index:
		MOUSE_BUTTON_WHEEL_LEFT:
			direction = -1
		MOUSE_BUTTON_WHEEL_RIGHT:
			direction = 1
		MOUSE_BUTTON_WHEEL_UP:
			direction = -1 if event.shift_pressed else 0
		MOUSE_BUTTON_WHEEL_DOWN:
			direction = 1 if event.shift_pressed else 0
	if direction:
		scroll_horizontal += roundi(direction * maxf(event.factor, 1.0) * 48.0)
		get_viewport().set_input_as_handled()
