extends RefCounted

const FORMAT := "revelation.notes.v1"

static func copy(chart: Node) -> String:
	if not chart.clip_copy_selected(): return ""
	return JSON.stringify({"format": FORMAT, "notes": chart.clipboard_notes})

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and absf(value) <= 1000000000

static func _point(value: Variant) -> bool:
	return value is Array and value.size() >= 2 and _number(value[0]) and _number(value[1])

static func _movement(move: Dictionary) -> bool:
	for key in ["start", "mid", "end"]:
		if move.has(key) and not _point(move[key]): return false
	return not move.has("time") or _number(move.time)

static func _valid(row: Variant) -> bool:
	if not row is Dictionary: return false
	for key in ["type", "track", "start_time", "end_time", "judge_time", "position_x", "position_y", "max_alpha", "use_bezier_curve", "bg_anim_move_with_chart"]:
		if not _number(row.get(key)): return false
	if row.type != int(row.type) or int(row.type) not in [0, 1, 2] or row.track != int(row.track): return false
	if row.end_time < row.start_time or not row.get("judge_area") is String or not row.get("animation") is String: return false
	if not row.get("move") is Dictionary or not row.get("line") is Array or not row.get("bezier_points") is Array: return false
	if row.type == 2 and (row.judge_time < row.start_time or row.judge_time > row.end_time): return false
	if not _movement(row.move) or not row.move.get("segments", []) is Array: return false
	for seg in row.move.get("segments", []):
		if not seg is Dictionary or not _number(seg.get("time")) or not _movement(seg): return false
	for points in [row.line, row.bezier_points]:
		for p in points:
			if not _point(p): return false
	return true

static func _hit(row: Dictionary) -> int:
	return int(row.judge_time if row.type == 2 else row.end_time)

static func paste(chart: Node, at_ms: int, lane: int, system := false) -> String:
	if system:
		return paste_json(chart, at_ms, lane, DisplayServer.clipboard_get())
	return _place(chart, at_ms, lane, chart.clipboard_notes.duplicate(true))

static func paste_json(chart: Node, at_ms: int, lane: int, text: String) -> String:
	if text.to_utf8_buffer().size() > 4194304: return "剪贴板内容超过 4 MB。"
	var doc: Variant = JSON.parse_string(text)
	if not doc is Dictionary or doc.get("format") != FORMAT or not doc.get("notes") is Array:
		return "剪贴板中没有可识别的跨工程音符 JSON。"
	return _place(chart, at_ms, lane, doc.notes)

static func _place(chart: Node, at_ms: int, lane: int, rows: Array) -> String:
	if rows.is_empty() or rows.size() > 4096: return "请选择 1 至 4096 个音符进行复制。"
	for row in rows:
		if not _valid(row): return "音符 JSON 格式有误，未写入谱面。"
	rows.sort_custom(func(a: Dictionary, b: Dictionary): return _hit(a) < _hit(b) or (_hit(a) == _hit(b) and a.track < b.track))
	var delta := at_ms - _hit(rows[0])
	var shift := lane - int(rows[0].track)
	var occupied := {}
	for n in chart.notes.values():
		if not occupied.has(n.track): occupied[n.track] = []
		occupied[n.track].append(Vector2i(n.time_unit, n.time_unit + (n.length - 1 if n.type == 2 else 0)))
	var outside := 0
	var conflicts := 0
	var ids: Array[int] = []
	var limit := maxi(roundi(chart.audio_duration_ms + chart.audio_delay_ms), ceili(chart.latest_content_time_ms()))
	if limit <= 0: limit = chart.time_unit_to_ms(roundi(chart.total_beats * 64))
	for row: Dictionary in rows:
		row.track = int(row.track) + shift
		row.start_time = int(row.start_time) + delta
		row.end_time = int(row.end_time) + delta
		if row.type == 2: row.judge_time = int(row.judge_time) + delta
		if row.track < 0 or row.track >= chart.track_count or row.start_time < 0 or row.end_time > limit:
			outside += 1
			continue
		var start: int = chart.ms_to_time_unit(row.start_time)
		var end: int = chart.ms_to_time_unit(row.end_time)
		row.time_unit = start if row.type == 2 else end
		row.length = maxi(1, end - start)
		var span := Vector2i(row.time_unit, end - 1 if row.type == 2 and end > start else row.time_unit)
		if not occupied.has(row.track): occupied[row.track] = []
		if occupied[row.track].any(func(other: Vector2i): return span.x <= other.y and other.x <= span.y):
			conflicts += 1
			continue
		for seg in row.move.get("segments", []): seg.time += delta
		if row.move.has("time") and _number(row.move.time): row.move.time += delta
		if ids.is_empty(): chart.push_undo()
		var id: int = chart.next_note_id
		chart.next_note_id += 1
		chart.notes[id] = chart._dict_to_note(row)
		chart.notes_by_pos[Vector2i(row.time_unit, row.track)] = id
		occupied[row.track].append(span)
		ids.append(id)
		chart.note_added.emit(id)
	if not ids.is_empty():
		chart.set_note_selection(ids)
		chart.force_refresh()
	return "已粘贴 %d 颗。占位跳过 %d 颗，越界跳过 %d 颗。" % [ids.size(), conflicts, outside]
