extends VBoxContainer

const Renderer := preload("res://desktop/render_preview.gd")
const Feedback := preload("res://main/hit_feedback.gd")
var screen := TextureRect.new()
var caption := Label.new()
var music := AudioStreamPlayer.new()
var hits: Array[AudioStreamPlayer] = []
var scenes: Array[Dictionary] = []
var cues: Array = []
var span := Vector2.ZERO
var position_ms := 0.0
var active := 0
var playing := false
var _delay := 0.0
var _next_hit := 0
var _hit_voice := 0
var _song_started := false
var _start_ticks := 0
@onready var _settings: Node = get_node("/root/Global")

func configure(chart: Node, bounds: Vector2) -> void:
	span = bounds
	_delay = chart.audio_delay_ms
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	screen.custom_minimum_size.y = 210
	add_child(screen)
	add_child(caption)
	add_child(music)
	music.stream = chart.loaded_audio_stream
	for i in 4:
		var player := AudioStreamPlayer.new()
		add_child(player)
		hits.append(player)
	visibility_changed.connect(func(): if not is_visible_in_tree(): pause())
	set_process(false)

func add_variant(chart: Node) -> Dictionary:
	var scene := Renderer.mount(self, chart, Vector2i(640, 360))
	scenes.append(scene)
	cues.append([])
	return scene

func refresh_variant(index: int) -> void:
	var rows: Array = []
	for n in scenes[index].chart.notes.values():
		rows.append(Vector2i(Feedback.judgement_ms(n), n.type))
	rows.sort()
	cues[index] = rows

func select(index: int, time: float, replay := false) -> void:
	pause()
	active = index
	screen.texture = scenes[index].viewport.get_texture()
	position_ms = clampf(time, span.x, span.y)
	_next_hit = 0
	while _next_hit < cues[active].size() and cues[active][_next_hit].x < position_ms: _next_hit += 1
	_draw_at(position_ms)
	if replay:
		_start_ticks = Time.get_ticks_usec() - roundi((position_ms - span.x) * 1000.0)
		playing = true
		set_process(true)

func _draw_at(time: float) -> void:
	Renderer.prepare_frame(scenes[active], time)
	caption.text = scenes[active].chart.ruler_position(roundi(time)).label

func pause() -> void:
	playing = false
	screen.queue_redraw()
	set_process(false)
	music.stop()
	_song_started = false
	for player in hits: player.stop()

func _process(_delta: float) -> void:
	position_ms = span.x + (Time.get_ticks_usec() - _start_ticks) / 1000.0
	if position_ms >= span.y:
		select(active, span.x, true)
		return
	if not _song_started and music.stream and position_ms >= _delay:
		_song_started = true
		var seconds := (position_ms - _delay) / 1000.0
		if seconds < music.stream.get_length(): music.play(seconds)
	while _next_hit < cues[active].size() and cues[active][_next_hit].x <= position_ms:
		var cue: Vector2i = cues[active][_next_hit]
		if _settings.hit_sound_volume > 0:
			var player := hits[_hit_voice % hits.size()]
			_hit_voice += 1
			player.volume_db = linear_to_db(_settings.hit_sound_volume)
			player.stream = Feedback.DRAG if cue.y == 1 else Feedback.TAP
			player.play()
		_next_hit += 1
	_draw_at(position_ms)
