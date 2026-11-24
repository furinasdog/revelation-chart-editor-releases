extends Control

const EditorTheme := preload("res://desktop/editor_theme.gd")

var points: Array = []
var duration_ms := 0.0
var pointer_ms := 0.0

func set_data(values: Array, duration: float) -> void:
	points = values
	duration_ms = duration
	queue_redraw()

func _draw() -> void:
	var area := Rect2(Vector2(48, 16), size - Vector2(62, 44))
	if area.size.x <= 8 or area.size.y <= 8:
		return
	draw_rect(area, EditorTheme.tone("panel"))
	if points.is_empty():
		draw_string(get_theme_default_font(), area.position + Vector2(12, 25), "分析后在这里查看速度曲线", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, EditorTheme.tone("muted"))
		return
	var floor_bpm := 300.0
	var ceiling_bpm := 0.0
	for point: Dictionary in points:
		floor_bpm = minf(floor_bpm, point.bpm)
		ceiling_bpm = maxf(ceiling_bpm, point.bpm)
	floor_bpm = floorf((floor_bpm - 5) / 10) * 10
	ceiling_bpm = ceilf((ceiling_bpm + 5) / 10) * 10
	for index in range(4):
		var fraction := float(index) / 3
		var y := area.end.y - fraction * area.size.y
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), EditorTheme.tone("line"))
		draw_string(get_theme_default_font(), Vector2(5, y + 4), "%.0f" % lerpf(floor_bpm, ceiling_bpm, fraction), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, EditorTheme.tone("muted"))
	var path := PackedVector2Array()
	for point: Dictionary in points:
		var x := area.position.x + clampf(point.time_ms / maxf(duration_ms, 1), 0, 1) * area.size.x
		var y := area.end.y - (float(point.bpm) - floor_bpm) / (ceiling_bpm - floor_bpm) * area.size.y
		path.append(Vector2(x, y))
	if path.size() > 1:
		draw_polyline(path, EditorTheme.tone("accent"), 2, true)
	else:
		draw_circle(path[0], 3, EditorTheme.tone("accent"))
	var cursor := area.position.x + clampf(pointer_ms / maxf(duration_ms, 1), 0, 1) * area.size.x
	draw_line(Vector2(cursor, area.position.y), Vector2(cursor, area.end.y), EditorTheme.tone("capture"))
	draw_string(get_theme_default_font(), area.position + Vector2(0, area.size.y + 19), "0 秒", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, EditorTheme.tone("ink"))
	draw_string(get_theme_default_font(), area.end + Vector2(-64, 19), "%.1f 秒" % (duration_ms / 1000), HORIZONTAL_ALIGNMENT_RIGHT, 64, 12, EditorTheme.tone("ink"))
