extends Node

var _window: Window
var _minimum: Vector2i
var _scroll: ScrollContainer
var _body: VBoxContainer
var _opening := 0

static func present(window: Window, preferred: Vector2i) -> void:
	var layout := window.get_node_or_null("DialogLayout")
	if layout == null:
		layout = new()
		layout.name = "DialogLayout"
		window.add_child(layout)
		layout.attach(window)
	layout.open(preferred)

func attach(window: Window) -> void:
	_window = window
	_minimum = window.min_size.max(Vector2i(220, 100))
	window.wrap_controls = false
	window.unresizable = false
	if window is AcceptDialog:
		_prepare_form(window)
	window.get_parent().get_viewport().size_changed.connect(_parent_resized, CONNECT_DEFERRED)

func _prepare_form(dialog: AcceptDialog) -> void:
	var controls := dialog.get_children()
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	dialog.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	# AcceptDialog normally overlays its message and its custom controls.
	var message := dialog.get_label()
	message.reparent(_body, false)
	message.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for child in controls:
		if child is Control and child != message:
			child.reparent(_body, false)
	dialog.about_to_popup.connect(func(): message.visible = not dialog.dialog_text.is_empty())
	_minimum.x = maxi(_minimum.x, ceili(dialog.get_ok_button().get_parent_control().get_combined_minimum_size().x) + 16)

func _area() -> Rect2i:
	# Embedded dialogs use logical viewport coordinates, including manual UI scaling.
	var parent := _window.get_parent()
	var area := Rect2i(parent.get_viewport().get_visible_rect()) if _window.is_embedded() else DisplayServer.screen_get_usable_rect(parent.get_window().current_screen)
	var title := _window.get_theme_constant("title_height", "Window") if _window.is_embedded() else 36
	var top := maxi(24, title) + 6
	return Rect2i(area.position + Vector2i(6, top), (area.size - Vector2i(12, top + 6)).max(Vector2i.ONE))

func _limits(area: Rect2i) -> void:
	_window.min_size = _minimum.min(area.size)
	_window.max_size = area.size

func open(preferred: Vector2i) -> void:
	var area := _area()
	_limits(area)
	var initial := preferred.clamp(_window.min_size, area.size)
	_window.popup(Rect2i(area.position + (area.size - initial) / 2, initial))
	if _window.is_embedded():
		_window.size = initial
		_window.position = area.position + (area.size - initial) / 2
	_opening += 1
	if _scroll:
		_fit_form(_opening, _window.size, _window.position)

func _fit_form(opening: int, initial: Vector2i, position: Vector2i) -> void:
	# Measure wrapped text after the form has its real width.
	await get_tree().process_frame
	await get_tree().process_frame
	if not _window.visible or opening != _opening or _window.size != initial or _window.position != position:
		return
	var frame_height := initial.y - floori(_scroll.size.y)
	var height := ceili(_body.get_combined_minimum_size().y) + frame_height + 2
	if _scroll.get_h_scroll_bar().visible:
		height += ceili(_scroll.get_h_scroll_bar().size.y)
	_window.size.y = clampi(height, _window.min_size.y, _window.max_size.y)
	_window.position.y = _area().get_center().y - _window.size.y / 2

func _parent_resized() -> void:
	if not _window.visible:
		return
	var area := _area()
	_limits(area)
	_window.size = _window.size.clamp(_window.min_size, area.size)
	_window.position = _window.position.clamp(area.position, area.end - _window.size)
