extends AcceptDialog

const Feedback := preload("res://main/hit_feedback.gd")
const Layout := preload("res://desktop/dialog_layout.gd")
const Palette := preload("res://desktop/editor_theme.gd")

static func neighborhood(chart: Node, selected: int) -> Dictionary:
	var by_time := {}
	var holds: Array = []
	for id: int in chart.notes:
		var note = chart.notes[id]
		var t := Feedback.judgement_ms(note)
		if not by_time.has(t): by_time[t] = []
		var pos: Vector2 = chart.get_hold_move_position(id, t) if note.type == 2 else chart.get_note_move_position(id, t)
		by_time[t].append({"id": id, "point": pos, "type": note.type})
		if note.type == 2: holds.append({"id": id, "start": t, "end": note.end_time})
	if not chart.notes.has(selected): return {}
	var focus := Feedback.judgement_ms(chart.notes[selected])
	var times := by_time.keys()
	times.sort()
	var center := times.find(focus)
	var groups: Array = []
	var warnings := PackedStringArray()
	var positions: Array[Vector2] = []
	for i in range(maxi(0, center-2), mini(times.size(), center+3)):
		var t: int = times[i]
		var held: Array = []
		for hold in holds:
			if hold.start < t and hold.end > t:
				held.append({"id": hold.id, "point": chart.get_hold_move_position(hold.id, t)})
		var gap: int = t - int(times[i-1]) if i > 0 else 0
		for row in by_time[t]:
			positions.append(row.point)
			if i > 0 and gap < 250:
				var nearest := INF
				for previous in by_time[times[i-1]]: nearest = minf(nearest, row.point.distance_to(previous.point))
				if nearest > 800 and not warnings.has("相邻判定跨屏较快，可检查换手或提前引导。"):
					warnings.append("相邻判定跨屏较快，可检查换手或提前引导。")
		groups.append({"offset": i-center, "time": t, "gap": gap, "notes": by_time[t], "held": held})
	if positions.size() >= 3:
		var area := Rect2(positions[0], Vector2.ZERO)
		for p in positions: area = area.expand(p)
		if area.size.length() < 240: warnings.append("这几拍的落点较集中，可保留编排或增加位置变化。")
	return {"groups": groups, "warnings": warnings}

func open_for(chart: Node, selected: int) -> void:
	var data := neighborhood(chart, selected)
	if data.is_empty():
		queue_free()
		return
	title = "手序与引导预览"
	ok_button_text = "关闭"
	var body := VBoxContainer.new()
	add_child(body)
	var map := Control.new()
	map.custom_minimum_size.y = 205
	body.add_child(map)
	map.draw.connect(func(): _draw_map(map, data.groups))
	for group in data.groups:
		var points := PackedStringArray()
		for n in group.notes: points.append("(%d, %d)" % [n.point.x, n.point.y])
		var held := PackedStringArray()
		for n in group.held: held.append("#%d (%d, %d)" % [n.id, n.point.x, n.point.y])
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = "%s · %s · %s" % [_name(group.offset), chart.ruler_position(group.time).label, "、".join(points)]
		if group.gap: label.text += "　距上次 %d ms" % group.gap
		if not held.is_empty(): label.text += "　长键占手：" + "、".join(held)
		body.add_child(label)
	for tip in data.warnings:
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = tip
		body.add_child(label)
	visibility_changed.connect(func(): if not visible: queue_free())
	Layout.present(self, Vector2i(650, 440))

static func _name(offset: int) -> String:
	return "当前" if offset == 0 else ("前 %d" % -offset if offset < 0 else "后 %d" % offset)

func _draw_map(map: Control, groups: Array) -> void:
	var scale_factor := minf((map.size.x-24)/1920.0, (map.size.y-24)/1080.0)
	var rect := Rect2((map.size - Vector2(1920,1080)*scale_factor)*0.5, Vector2(1920,1080)*scale_factor)
	map.draw_rect(rect, Palette.tone("surface"))
	map.draw_rect(rect, Palette.tone("line"), false)
	var font := map.get_theme_default_font()
	for group in groups:
		for held in group.held:
			map.draw_circle(rect.position+held.point*scale_factor, 11, Palette.tone("capture"), false, 2, true)
		for note in group.notes:
			var at: Vector2 = rect.position+note.point*scale_factor
			var color := Palette.tone("accent" if group.offset == 0 else "muted")
			map.draw_circle(at, 5, color, true, -1, true)
			map.draw_string(font, at+Vector2(7,-3), _name(group.offset), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
