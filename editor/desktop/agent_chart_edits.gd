extends RefCounted

const METADATA := {"name": "chartName", "difficulty": "difficulty", "composer": "composer",
	"description": "description", "tips": "tips/other"}
const METADATA_LIMITS := {"name": 160, "difficulty": 40, "composer": 160, "description": 2000, "tips": 500}
const EDIT_TOOLS := ["set_chart_metadata", "set_tempo_map", "upsert_text_event", "delete_text_event"]

var _chart: Node
var _duration: int
var _next_event_id: int
var _metadata := {}
var _tempo := []
var _text := {}

func _init(chart: Node, duration: int) -> void:
	_chart = chart
	_duration = duration
	_next_event_id = chart.next_event_id

func has_changes() -> bool:
	return not (_metadata.is_empty() and _tempo.is_empty() and _text.is_empty())

func delta() -> Dictionary:
	return {"metadata": _metadata, "tempo": _tempo, "text": _text} if has_changes() else {}

func metadata() -> Dictionary:
	var result := {}
	for field: String in METADATA:
		var key: String = METADATA[field]
		result[field] = _metadata.get(key, _chart.chart_info.get(key, ""))
	return result

func set_metadata(arguments: Dictionary) -> Dictionary:
	var values: Variant = arguments.get("fields")
	if not values is Dictionary or values.is_empty():
		return {"error": "请提供需要修改的谱面信息 fields。"}
	var pending := {}
	for field: Variant in values:
		if not METADATA.has(field) or not values[field] is String or values[field].length() > METADATA_LIMITS[field]:
			return {"error": "谱面字段无效，或文本超过长度限制。", "limits": METADATA_LIMITS}
		pending[METADATA[field]] = values[field]
	_metadata.merge(pending, true)
	return metadata()

func tempo_map() -> Dictionary:
	var rows: Array = _tempo if not _tempo.is_empty() else _chart.bpm_segments
	return {"segments": rows, "total_beats": rows[-1].end_beat if not rows.is_empty() else _chart.total_beats}

func set_tempo_map(arguments: Dictionary) -> Dictionary:
	var input: Variant = arguments.get("segments")
	if not input is Array or input.is_empty() or input.size() > 128:
		return {"error": "请输入 1–128 个由 start_beat 和 bpm 组成的速度段。"}
	var rows := []
	var previous := -1.0
	var elapsed := 0.0
	for item: Variant in input:
		if (not item is Dictionary or not _number(item.get("start_beat"), 0, 100000)
				or not _number(item.get("bpm"), 10, 3000)):
			return {"error": "拍号须为 0–100000，速度须为 10–3000 BPM。"}
		var start := float(item.start_beat)
		if start <= previous or (rows.is_empty() and start != 0.0):
			return {"error": "首段从第 0 拍开始，其余分段起点须严格递增。"}
		if not rows.is_empty():
			rows[-1].end_beat = start
			elapsed += (start - previous) * 60000.0 / float(rows[-1].bpm)
		rows.append({"start_beat": start, "end_beat": start, "bpm": float(item.bpm)})
		previous = start
	var minimum_end := maxf(previous + 1, ceil(previous + maxf(_duration - elapsed, 0) * rows[-1].bpm / 60000.0))
	var end: Variant = arguments.get("total_beats", maxf(_chart.total_beats, minimum_end))
	if not _number(end, minimum_end, 100001):
		return {"error": "总拍数须覆盖音频时长和最后一个速度段。", "minimum_total_beats": minimum_end}
	rows[-1].end_beat = float(end)
	_tempo = rows
	return tempo_map()

func text_events(from_ms: int, to_ms: int, offset: int, limit: int) -> Dictionary:
	var rows := []
	for id: int in _chart.events:
		if not _text.has(id) and _chart.events[id].type == 2:
			_append_text(rows, id, _chart._event_to_dict(_chart.events[id]), from_ms, to_ms)
	for id: int in _text:
		if _text[id] != null:
			_append_text(rows, id, _text[id], from_ms, to_ms)
	rows.sort_custom(func(a: Dictionary, b: Dictionary): return a.from_ms < b.from_ms or (a.from_ms == b.from_ms and a.id < b.id))
	return {"items": rows.slice(offset, offset + limit), "offset": offset, "total": rows.size()}

func upsert_text(arguments: Dictionary) -> Dictionary:
	var id: Variant = arguments.get("id", _next_event_id)
	if not _number(id, 0, 2147483647) or float(id) != floorf(id):
		return {"error": "文本事件编号须为整数。"}
	id = int(id)
	var previous := _text_record(id)
	var is_new := not arguments.has("id")
	if (not is_new and previous.is_empty()) or (not _text.has(id) and _text.size() >= 256):
		return {"error": "找不到该文本事件，或草稿已达到 256 项修改上限。"}
	var text: Variant = arguments.get("text", previous.get("text", ""))
	var start: Variant = arguments.get("from_ms", previous.get("start_time", 0))
	var end: Variant = arguments.get("to_ms", previous.get("end_time", mini(roundi(start) + 2000, _duration) if _number(start, 0, _duration) else 0))
	var x: Variant = arguments.get("x", previous.get("pos_x", 960))
	var y: Variant = arguments.get("y", previous.get("pos_y", 1000))
	var size: Variant = arguments.get("size", previous.get("size", 36))
	var fade_in: Variant = arguments.get("fade_in_ms", previous.get("fade_in_duration", 150))
	var fade_out: Variant = arguments.get("fade_out_ms", previous.get("fade_out_duration", 150))
	if (not text is String or text.strip_edges().is_empty() or text.length() > 500
			or not _number(start, 0, _duration) or not _number(end, float(start), _duration) or roundi(start) >= roundi(end)
			or not _number(x, 0, 1920) or not _number(y, 0, 1080) or not _number(size, 8, 200)
			or not _number(fade_in, 0, 10000) or not _number(fade_out, 0, 10000)):
		return {"error": "文本需包含 1–500 字、有效时间范围、坐标、字号和淡入淡出时长。"}
	var rgba: Array = previous.get("color", [1.0, 1.0, 1.0, 1.0])
	if arguments.has("color"):
		var color: Variant = arguments.color
		if not color is String or not color.begins_with("#") or color.length() not in [7, 9] or not Color.html_is_valid(color):
			return {"error": "颜色须为 #RRGGBB 或 #RRGGBBAA。"}
		var paint := Color.html(color)
		rgba = [paint.r, paint.g, paint.b, paint.a]
	_text[id] = {"type": 2, "start_time": roundi(start), "end_time": roundi(end), "text": text,
		"pos_x": x, "pos_y": y, "size": roundi(size), "color": rgba, "track": previous.get("track", 0),
		"fade_in_duration": roundi(fade_in), "fade_out_duration": roundi(fade_out)}
	if is_new:
		_next_event_id += 1
	return _text_row(id, _text[id])

func delete_text(arguments: Dictionary) -> Dictionary:
	var id: Variant = arguments.get("id")
	if not _number(id, 0, 2147483647) or float(id) != floorf(id) or _text_record(int(id)).is_empty():
		return {"error": "找不到该文本事件。"}
	if not _text.has(int(id)) and _text.size() >= 256:
		return {"error": "草稿已达到 256 项文本修改上限。"}
	if _chart.events.has(int(id)):
		_text[int(id)] = null
	else:
		_text.erase(int(id))
	return {"removed": int(id)}

func _text_record(id: int) -> Dictionary:
	if _text.has(id):
		return _text[id] if _text[id] != null else {}
	return _chart._event_to_dict(_chart.events[id]) if _chart.events.has(id) and _chart.events[id].type == 2 else {}

static func _append_text(rows: Array, id: int, event: Dictionary, from_ms: int, to_ms: int) -> void:
	if event.start_time <= to_ms and event.end_time >= from_ms:
		rows.append(_text_row(id, event))

static func _text_row(id: int, event: Dictionary) -> Dictionary:
	return {"id": id, "from_ms": event.start_time, "to_ms": event.end_time, "text": event.text,
		"x": event.pos_x, "y": event.pos_y, "size": event.size, "color_rgba": event.color,
		"fade_in_ms": event.fade_in_duration, "fade_out_ms": event.fade_out_duration}

static func _number(value: Variant, lower: float, upper: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= lower and value <= upper
