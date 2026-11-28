extends Window

signal decided(accepted: bool)

const Layout := preload("res://desktop/dialog_layout.gd")
const WAIT_SECONDS := 15
var _reader: RichTextLabel
var _accept: Button
var _status: Label
var _deadline := 0

func present(text: String, confirm_caption: String, decline_caption: String) -> void:
	title = "用户使用协议"
	exclusive = true
	transient = true
	min_size = Vector2i(340, 265)
	close_requested.connect(_decide.bind(false))

	var body := VBoxContainer.new()
	add_child(body)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 13)
	_reader = RichTextLabel.new()
	_reader.text = text
	_reader.selection_enabled = true
	_reader.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_reader)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(buttons)
	var close := Button.new()
	close.text = decline_caption
	close.pressed.connect(_decide.bind(false))
	buttons.add_child(close)
	_accept = Button.new()
	_accept.text = confirm_caption
	_accept.disabled = true
	_accept.pressed.connect(_decide.bind(true))
	buttons.add_child(_accept)
	_deadline = Time.get_ticks_msec() + WAIT_SECONDS * 1000
	Layout.present(self, Vector2i(700, 435))

func _process(_delta: float) -> void:
	if is_instance_valid(_accept):
		var remaining := maxi(0, ceili((_deadline - Time.get_ticks_msec()) / 1000.0))
		var bar := _reader.get_v_scroll_bar()
		var at_end := not bar.visible or bar.value + bar.page >= bar.max_value - 1.0
		_accept.disabled = remaining > 0 or not at_end
		_status.text = "请阅读至文末，可确认还需 %d 秒。" % remaining if remaining > 0 else (
			"已到文末，可以确认。" if at_end else "请滚动到协议末尾。")

func _decide(accepted: bool) -> void:
	if accepted and _accept.disabled:
		return
	hide()
	decided.emit(accepted)
	queue_free()
