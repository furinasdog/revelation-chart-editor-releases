extends Control

const EditorTheme := preload("res://desktop/editor_theme.gd")

var _points: Array = []
var _duration := 0.0
var pointer_ms := 0.0

func set_data(points: Array, duration: float) -> void:
	_points = points
	_duration = duration
	queue_redraw()

func _draw() -> void:
	var area := Rect2(52, 8, maxf(1, size.x - 64), maxf(1, size.y - 30))
	draw_rect(area, EditorTheme.tone("panel"))
	var font := get_theme_default_font()
	var ticks: Array[float] = [55, 110, 220, 440, 880, 1760, 3520]
	for hz in ticks:
		var y := _pitch_y(area, hz)
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), EditorTheme.tone("line"))
		draw_string(font, Vector2(2, y + 4), "%d" % hz, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, EditorTheme.tone("ink"))
	draw_string(font, Vector2(2, area.end.y + 15), "赫兹", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, EditorTheme.tone("ink"))
	if _points.is_empty() or _duration <= 0:
		draw_string(font, area.position + Vector2(12, 22), "请在「自动抓音」中使用 Essentia 推理主旋律。",
			HORIZONTAL_ALIGNMENT_LEFT, area.size.x - 20, 13, EditorTheme.tone("ink"))
		return
	var previous := Vector2.INF
	for point: Dictionary in _points:
		var pitch := float(point.hz)
		if pitch < ticks.front() or pitch > ticks.back():
			previous = Vector2.INF
			continue
		var x := area.position.x + area.size.x * clampf(float(point.time_ms) / _duration, 0, 1)
		var position := Vector2(x, _pitch_y(area, pitch))
		var color := EditorTheme.tone("accent")
		if previous != Vector2.INF:
			draw_line(previous, position, color, 1.25, true)
		else:
			draw_circle(position, 1.4, color)
		previous = position
	for index in range(5):
		var x := area.position.x + area.size.x * (index / 4.0)
		draw_string(font, Vector2(minf(x, area.end.x - 32), area.end.y + 15), "%.1f 秒" % (_duration * index / 4000.0),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, EditorTheme.tone("ink"))
	var play_x := area.position.x + area.size.x * clampf(pointer_ms / _duration, 0, 1)
	draw_line(Vector2(play_x, area.position.y), Vector2(play_x, area.end.y), EditorTheme.tone("capture"), 1.0)

func _pitch_y(area: Rect2, hz: float) -> float:
	return area.end.y - area.size.y * log(hz / 55.0) / log(64.0)
