extends Node

var _target: SpinBox
var _origin := Vector2.ZERO
var _initial := 0.0
var _dragging := false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and is_instance_valid(_target) and _dragging:
		_target.set_value_no_signal(_initial)
		_target = null
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hovered := get_viewport().gui_get_hovered_control() as LineEdit
			_target = hovered.get_parent() as SpinBox if hovered else null
			if is_instance_valid(_target) and _target.editable and _target.get_line_edit() == hovered and not event.double_click:
				_origin = event.position
				_initial = _target.value
				_dragging = false
			else:
				_target = null
		elif is_instance_valid(_target):
			var spin := _target
			_target = null
			if _dragging:
				var value := spin.value
				spin.set_value_no_signal(_initial)
				spin.value = value
				get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseMotion or not is_instance_valid(_target):
		return
	var delta: float = event.position.x - _origin.x
	if not _dragging and absf(delta) < 6:
		return
	if not _dragging:
		_dragging = true
		_target.get_line_edit().release_focus()
	var step := maxf(_target.step, _target.custom_arrow_step)
	if step <= 0:
		step = 1
	var multiplier := 0.1 if event.shift_pressed else (10.0 if event.ctrl_pressed else 1.0)
	_target.set_value_no_signal(_initial + delta * 0.35 * step * multiplier)
	get_viewport().set_input_as_handled()
