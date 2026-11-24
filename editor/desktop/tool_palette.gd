extends Control
const EditorTheme := preload("res://desktop/editor_theme.gd")

const CELL := Vector2(78, 58)
const GUTTER := 5.0

var entries: Array
var selected := -1
var origin := Vector2.ZERO

func show_at(pointer: Vector2, tools: Array) -> void:
	entries = tools
	origin = pointer
	size = Vector2(4, 2) * CELL + Vector2.ONE * GUTTER * 2
	var limit := (get_parent() as Control).size - size
	position = (pointer - size * 0.5).clamp(Vector2.ZERO, limit.max(Vector2.ZERO))
	mouse_filter = MOUSE_FILTER_IGNORE
	show()
	point_to(pointer)

func point_to(pointer: Vector2) -> void:
	selected = -1
	if pointer.is_finite() and pointer.distance_to(origin) > 9:
		var local := pointer - position - Vector2.ONE * GUTTER
		if Rect2(Vector2.ZERO, Vector2(4, 2) * CELL).has_point(local):
			selected = int(local.x / CELL.x) + 4 * int(local.y / CELL.y)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), EditorTheme.tone("panel"))
	draw_rect(Rect2(Vector2.ZERO, size), EditorTheme.tone("line"), false)
	var font := get_theme_default_font()
	for index in range(entries.size()):
		var start := Vector2(index % 4, index / 4) * CELL + Vector2.ONE * GUTTER
		var bounds := Rect2(start + Vector2.ONE * 2, CELL - Vector2.ONE * 4)
		var tint := EditorTheme.tone("ink")
		if selected == index:
			draw_rect(bounds, EditorTheme.tone("selected"))
		draw_string(font, start + Vector2(0, 28), entries[index][1], HORIZONTAL_ALIGNMENT_CENTER, CELL.x, 21, tint)
		draw_string(font, start + Vector2(0, 47), entries[index][2], HORIZONTAL_ALIGNMENT_CENTER, CELL.x, 12, tint)
