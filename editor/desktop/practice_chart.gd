extends AcceptDialog

const Chart := preload("res://main/chart_data.gd")
const Player := preload("res://desktop/chart_audition.gd")
const Effects := preload("res://desktop/agent_animation.gd")
const Layout := preload("res://desktop/dialog_layout.gd")
const DEFAULT_END := Vector2(1320, 560)
const JUDGEMENT := 1500.0
var player := Player.new()
var lesson := OptionButton.new()
var variants := HFlowContainer.new()
var instructions := Label.new()
var endpoint := DEFAULT_END
var slide := -1
var dragging := false
var variant_buttons: Array[Button] = []

func open_lesson(step := 0) -> void:
	title = "8 拍练习谱"
	ok_button_text = "结束练习"
	exclusive = true
	var body := VBoxContainer.new()
	add_child(body)
	lesson.add_item("普通键接黄键")
	lesson.add_item("同拍对比遮罩")
	body.add_child(lesson)
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(instructions)
	body.add_child(player)
	var chart := Chart.new()
	add_child(chart)
	chart.audio_duration_ms = 4000
	chart.loaded_audio_stream = _click_track()
	chart.add_note_at_times(0, 200, 1000, 0, 0, Vector2(650, 480))
	slide = chart.add_note_at_times(1, 800, 1500, 0, 1, Vector2(720, 480))
	chart.add_note_at_times(0, 1900, 2500, 0, 2, Vector2(1160, 610))
	chart.add_note_at_times(1, 2350, 3000, 0, 3, Vector2(960, 450))
	player.configure(chart, Vector2(0,4000))
	var bg: Image = preload("res://game_preview/backGround/backImage_test.png").get_image()
	var dim := Image.create_empty(8,8,false,Image.FORMAT_RGBA8)
	dim.fill(Color(0.04,0.07,0.12,0.72))
	for i in 3:
		var scene := player.add_variant(chart)
		var snap: Node = scene.chart
		snap.preview_image_overrides = {"practice-bg": bg, "practice-mask": dim}
		snap.preview_bg_image_path = "practice-bg"
		if i > 0: snap.preview_mask_image_path = "practice-mask"
		if i == 2:
			var effect := Effects.new(snap,4000,[])
			effect.add_mask_reveal({"time_ms": 950, "duration_ms": 1300, "radius_px": 620, "x": 960, "y": 540})
			snap.apply_automatic_notes({}, {}, effect.layers.values(), [])
		player.refresh_variant(i)
	body.add_child(variants)
	for text: String in ["原画面","压暗背景","圆形揭示"]:
		var button := _button(variants, text, _compare.bind(variant_buttons.size()))
		button.toggle_mode = true
		variant_buttons.append(button)
	var actions := HFlowContainer.new()
	body.add_child(actions)
	_button(actions,"从第 1 拍重播",func(): player.select(player.active,0,true))
	_button(actions,"暂停",player.pause)
	_button(actions,"重置本步",_reset)
	lesson.item_selected.connect(func(_index: int): _reset())
	player.screen.mouse_filter = Control.MOUSE_FILTER_STOP
	player.screen.gui_input.connect(_drag)
	player.screen.draw.connect(_draw_handle)
	lesson.select(step)
	_reset()
	visibility_changed.connect(func(): if not visible: queue_free())
	Layout.present(self,Vector2i(650,460))

func _button(row: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	row.add_child(button)
	return button

func _reset() -> void:
	dragging = false
	variants.visible = lesson.selected == 1
	if lesson.selected == 0:
		_set_endpoint(DEFAULT_END)
		instructions.text = "第 3 拍点普通键，第 4 拍黄键收圈。拖动蓝色终点，松开后从第 1 拍回放。"
		player.select(0,JUDGEMENT-80)
	else:
		instructions.text = "在第 4 拍切换三种画面，对比遮罩如何引导视线。重播可观察圆形揭示的开合。"
		_compare(0)
	player.screen.queue_redraw()

func _compare(index: int) -> void:
	for i in variant_buttons.size(): variant_buttons[i].set_pressed_no_signal(i == index)
	player.select(index,JUDGEMENT)

func _set_endpoint(point: Vector2) -> void:
	endpoint = point
	for scene in player.scenes:
		var note = scene.chart.notes[slide]
		note.move = {"enabled": true,"segments":[{"time": JUDGEMENT,"end":[point.x,point.y],"type":"linear","trans":0,"ease":2}]}
	player.screen.queue_redraw()

func _scale_factor() -> float:
	return minf(player.screen.size.x / 1920.0, player.screen.size.y / 1080.0)

func _handle() -> Vector2:
	return player.screen.size*0.5 + (endpoint-Vector2(960,540))*_scale_factor()

func _draw_handle() -> void:
	if lesson.selected == 0 and (not player.playing or dragging):
		player.screen.draw_circle(_handle(),11,Color("68c8ff"),false,3,true)

func _drag(event: InputEvent) -> void:
	if lesson.selected != 0 or _scale_factor() <= 0: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.distance_to(_handle()) <= 22:
			dragging = true
			player.select(0,JUDGEMENT-30)
		elif not event.pressed and dragging:
			dragging = false
			player.select(0,0,true)
			player.screen.queue_redraw()
	elif event is InputEventMouseMotion and dragging:
		var point: Vector2 = (event.position-player.screen.size*0.5)/_scale_factor()+Vector2(960,540)
		_set_endpoint(point.clamp(Vector2.ZERO,Vector2(1920,1080)))
		player.select(0,JUDGEMENT-30)

func _click_track() -> AudioStreamWAV:
	var rate := 16000
	var bytes := PackedByteArray()
	bytes.resize(4*rate*2)
	for beat in 8:
		for i in 900:
			var pulse := sin(TAU*(880 if beat%4 == 0 else 660)*i/rate)*exp(-i/170.0)
			bytes.encode_s16(beat*rate+i*2,roundi(pulse*5800))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = bytes
	return wav
