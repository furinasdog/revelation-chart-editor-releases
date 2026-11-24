extends RefCounted

const TYPES := ["note", "drag", "hold"]
const LIMIT := 18000
const MAX_HOLD_DURATION_MS := 12000
const DIFFICULTIES := {
	"EZ": {"subdivisions": 1, "gap": 300, "lead_ms": 1300, "min_lead_ms": 850, "intro_ms": 1150, "hold_ms": 1100, "travel": 1.7, "chord_limit": 2},
	"HD": {"subdivisions": 2, "gap": 205, "lead_ms": 1150, "min_lead_ms": 600, "intro_ms": 1000, "hold_ms": 1000, "travel": 2.1, "chord_limit": 2},
	"EX": {"subdivisions": 4, "gap": 140, "lead_ms": 1000, "min_lead_ms": 550, "intro_ms": 850, "hold_ms": 900, "travel": 2.6, "chord_limit": 4},
}
const POSITION_WINDOW_MS := 2100
const POSITION_WINDOW_NOTES := 5
const REPEAT_RADIUS := 100.0
const CENTER_REGION := Rect2(576, 324, 768, 432)
const CENTER_RUN_MIN := 8
const PHRASE_PATHS := [
	[Vector2(540, 460), Vector2(760, 460), Vector2(980, 460), Vector2(1200, 460),
		Vector2(1400, 570), Vector2(1180, 700), Vector2(930, 700), Vector2(700, 650)],
	[Vector2(610, 620), Vector2(840, 540), Vector2(1040, 420), Vector2(1260, 420),
		Vector2(1430, 490), Vector2(1250, 660), Vector2(1000, 730), Vector2(760, 730)],
	[Vector2(580, 510), Vector2(770, 365), Vector2(1020, 365), Vector2(1260, 470),
		Vector2(1360, 690), Vector2(1110, 690), Vector2(870, 680), Vector2(620, 730)],
]

var notes := {}
var edited := {}
var next_id: int
var duration_ms: int
var start_ms: int
var track_count: int
var difficulty: String
var profile: Dictionary
var _chart: Node

func _init(chart: Node, level := "HD") -> void:
	_chart = chart
	difficulty = level if DIFFICULTIES.has(level) else "HD"
	profile = DIFFICULTIES[difficulty]
	next_id = chart.next_note_id
	track_count = maxi(chart.track_count, 1)
	start_ms = maxi(0, roundi(chart.audio_delay_ms))
	duration_ms = maxi(0, roundi(chart.audio_duration_ms + chart.audio_delay_ms))
	for id: int in chart.notes:
		var note = chart.notes[id]
		var ending: Vector2 = chart.get_hold_move_position(id, note.end_time) if note.type == 2 else note.position
		notes[id] = {"id": id, "type": TYPES[note.type], "lane": note.track,
			"time_ms": note.judge_time if note.type == 2 else note.end_time,
			"duration_ms": note.end_time - note.judge_time if note.type == 2 else 0,
			"lead_ms": (note.judge_time if note.type == 2 else note.end_time) - note.start_time,
			"x": note.position.x, "y": note.position.y, "end_x": ending.x, "end_y": ending.y}
		if note.type == 1 and note.move.get("enabled", false):
			var hit: Vector2 = chart.get_note_move_position(id, note.end_time)
			notes[id].merge({"x": hit.x, "y": hit.y, "approach_x": note.position.x,
				"approach_y": note.position.y, "keep_path": true}, true)
		elif note.type == 2 and note.line.size() >= 3:
			notes[id]["mid_x"] = note.line[2][0]
			notes[id]["mid_y"] = note.line[2][1]

func list_notes(from_ms: int, to_ms: int, offset: int, limit: int) -> Dictionary:
	var rows := _sorted_notes().filter(func(row: Dictionary): return row.time_ms >= from_ms and row.time_ms <= to_ms)
	return {"items": rows.slice(offset, offset + limit), "total": rows.size(), "offset": offset}

func locate_notes(args: Dictionary) -> Dictionary:
	for field: String in ["radius_ms", "offset", "limit"]:
		if args.has(field) and not _number(args[field]):
			return {"error": "%s 须为数字。" % field}
	var time := roundi(_chart.get_rt_render_time())
	var beat: Variant = args.get("ruler_beat")
	if beat != null:
		if not _number(beat) or beat < 1 or beat > 1000000:
			return {"error": "标尺拍号从 1 开始。"}
		time = _chart.beat_position_to_ms(beat - 1.0)
	if args.has("seconds"):
		var seconds: Variant = args.seconds
		if not _number(seconds) or seconds < 0 or seconds > 86400:
			return {"error": "请使用 0–86400 之间的秒数，例如 12 或 12.35。"}
		var requested := roundi(seconds * 1000.0)
		if beat != null and absi(time - requested) > 50:
			return {"error": "给出的拍号与时码指向不同位置。", "beat_location": _chart.ruler_position(time),
				"time_location": _chart.ruler_position(requested)}
		if beat == null:
			time = requested
	var location: Dictionary = _chart.ruler_position(time)
	var radius := clampi(int(args.get("radius_ms", 250)), 0, 4000)
	var matches: Array[Dictionary] = []
	var nearest := {}
	var nearest_distance := 2147483647
	for row: Dictionary in notes.values():
		var hit: int = row.time_ms
		var end: int = hit + row.duration_ms
		var lead: int = maxi(0, hit - row.lead_ms)
		var delta := absi(hit - time)
		var inside: bool = row.type == "hold" and time >= lead and time <= end
		if delta > radius and not inside:
			if delta < nearest_distance:
				nearest_distance = delta
				nearest = {"id": row.id, "judgement": _chart.ruler_position(hit)}
			continue
		var relation := "judgement" if delta == 0 else ("hold_span" if inside else "nearby")
		matches.append({"id": row.id, "type": row.type, "lane": row.lane, "time_ms": hit,
			"label": _chart.ruler_position(hit).label, "delta_ms": hit - time, "match": relation,
			"start_ms": lead, "end_ms": end, "x": row.x, "y": row.y,
			"selected": row.id in _chart.selected_note_ids})
	matches.sort_custom(func(a: Dictionary, b: Dictionary):
		if absi(a.delta_ms) != absi(b.delta_ms):
			return absi(a.delta_ms) < absi(b.delta_ms)
		return a.id < b.id)
	var offset := clampi(int(args.get("offset", 0)), 0, matches.size())
	var limit := clampi(int(args.get("limit", 8)), 1, 32)
	var result := {"location": location, "radius_ms": radius, "total": matches.size(), "offset": offset,
		"items": matches.slice(offset, offset + limit)}
	if matches.is_empty() and not nearest.is_empty():
		result["nearest_outside_window"] = nearest
	if offset + limit < matches.size():
		result["next_offset"] = offset + limit
	return result

func edit(action: String, rows: Variant) -> Dictionary:
	if not rows is Array or rows.is_empty() or rows.size() > 128:
		return {"error": "提供 1–128 个对象。删除时提供一组整数 ID。"}
	if action == "add_notes" and notes.size() + rows.size() > LIMIT:
		return {"error": "音符数量超限。"}
	var pending := {}
	for row: Variant in rows:
		if action == "delete_notes":
			if not _number(row) or float(row) != floorf(row) or not notes.has(int(row)):
				return {"error": "删除时必须使用已有音符 ID。"}
			pending[int(row)] = null
			continue
		if not row is Dictionary:
			return {"error": "每一项须为 JSON 对象。"}
		var id := next_id + pending.size()
		var candidate: Dictionary = row.duplicate()
		if action != "add_notes":
			var ref: Variant = row.get("id")
			if not _number(ref) or float(ref) != floorf(ref) or not notes.has(int(ref)):
				return {"error": "修改时必须使用已有音符 ID。"}
			id = int(ref)
			candidate = pending.get(id, notes[id]).duplicate()
			if candidate.has("geometry_scale") and action in ["set_positions", "set_hold_path"]:
				return {"error": "请先应用长键路径缩放，再单独设置新的路径坐标。"}
			var fields := ["time_ms", "lane"] if action == "move_notes" else ["x", "y", "end_x", "end_y", "approach_x", "approach_y"]
			if action == "resize_holds":
				if candidate.type != "hold" or not row.has("duration_ms"):
					return {"error": "调整长键时长须提供长键 ID 和 duration_ms。"}
				fields = ["duration_ms"]
				candidate["hold_duration_changed"] = true
			elif action == "set_note_lead_in":
				if not row.has("lead_ms"):
					return {"error": "调整预告时间需要音符 ID 和 lead_ms。"}
				fields = ["lead_ms"]
				candidate["lead_changed"] = true
			elif action == "set_hold_path":
				if candidate.type != "hold" or not row.has("end_x") or not row.has("end_y"):
					return {"error": "设置长键路径需要长键 ID、end_x 和 end_y。"}
				if _chart.notes.has(id) and _chart.notes[id].move.get("enabled", false):
					return {"error": "此长键有自定义移动关键帧，请保留已有路径。"}
				candidate.erase("mid_x")
				candidate.erase("mid_y")
				fields = ["end_x", "end_y", "mid_x", "mid_y"]
				candidate["hold_path_changed"] = true
			for key: String in fields:
				if row.has(key):
					candidate[key] = row[key]
			if action == "set_positions":
				candidate["position_changed"] = true
				candidate["endpoint_changed"] = candidate.get("endpoint_changed", false) or row.has("end_x") or row.has("end_y")
		var clean := _validate_note(candidate, id)
		if clean.has("error"):
			return clean
		pending[id] = clean
	for id: int in pending:
		if pending[id] == null:
			notes.erase(id)
		else:
			notes[id] = pending[id]
		edited[id] = true
	if action == "add_notes":
		next_id += pending.size()
	return {"ids": pending.keys(), "total_notes": notes.size()}

func _validate_note(row: Dictionary, id: int) -> Dictionary:
	var kind: Variant = row.get("type")
	if kind not in TYPES:
		return {"error": "音符类型必须为 note、drag 或 hold。"}
	for key: String in ["time_ms", "lane", "x", "y"]:
		if not _number(row.get(key)):
			return {"error": "缺少有效的 %s。" % key}
	var time := roundi(row.time_ms)
	var lane := int(row.lane)
	if row.lane != lane or lane < 0 or lane >= track_count or time < start_ms or time > duration_ms:
		return {"error": "时间或轨道超出范围。"}
	var is_new: bool = not _chart.notes.has(id)
	if is_new and time < start_ms + int(profile.intro_ms):
		return {"error": "本难度的首个新键应至少留出 %d 毫秒反应时间。" % profile.intro_ms}
	var length: Variant = row.get("duration_ms", 0)
	var duration_changed: bool = row.get("hold_duration_changed", false)
	if kind == "hold":
		var min_hold: int = profile.hold_ms if is_new or duration_changed else 1
		var max_hold: int = MAX_HOLD_DURATION_MS if is_new or duration_changed else duration_ms
		if not _number(length) or length < min_hold or length > max_hold or time + length > duration_ms:
			return {"error": "长键从判定到松开的时间须为 %d–%d 毫秒且不能越过曲尾。" % [min_hold, max_hold]}
	var clean := {"id": id, "type": kind, "time_ms": time, "lane": lane, "x": float(row.x), "y": float(row.y),
		"duration_ms": roundi(length) if kind == "hold" else 0}
	if row.get("lead_changed", false):
		var lead: Variant = row.get("lead_ms")
		if not _number(lead) or lead < profile.min_lead_ms or lead > 3500 or lead > time:
			return {"error": "预告时间须为 %d–3500 毫秒，且音符不能在曲首之前出现。" % profile.min_lead_ms}
		clean["lead_ms"] = roundi(lead)
		clean["lead_changed"] = true
	else:
		clean["lead_ms"] = row.get("lead_ms", profile.lead_ms if is_new else 0)
	if duration_changed:
		clean["hold_duration_changed"] = true
	if row.get("hold_path_changed", false):
		clean["hold_path_changed"] = true
	if notes.has(id) and row.get("keep_path", false):
		clean["keep_path"] = true
	if row.get("position_changed", false):
		clean["position_changed"] = true
		clean["endpoint_changed"] = row.get("endpoint_changed", false)
	if row.has("geometry_scale"):
		clean["geometry_scale"] = row.geometry_scale
	for pair: Array in [["x", "y"], ["end_x", "end_y"], ["approach_x", "approach_y"], ["mid_x", "mid_y"]]:
		if not row.has(pair[0]) and not row.has(pair[1]):
			continue
		if not _number(row.get(pair[0])) or not _number(row.get(pair[1])) or not Rect2(0, 0, 1921, 1081).has_point(Vector2(row[pair[0]], row[pair[1]])):
			return {"error": "坐标须成对填写并位于画面内。"}
		clean[pair[0]] = float(row[pair[0]])
		clean[pair[1]] = float(row[pair[1]])
	if clean.get("hold_path_changed", false) and clean.has("mid_x"):
		var origin := Vector2(clean.x, clean.y)
		var release := Vector2(clean.end_x, clean.end_y)
		var midpoint := Vector2(clean.mid_x, clean.mid_y)
		var axis := release - origin
		var max_bend := minf(axis.length() * 0.45, 160.0)
		var bend := midpoint.distance_to(Geometry2D.get_closest_point_to_segment(midpoint, origin, release))
		if (axis.length_squared() < 1.0 or (midpoint - origin).dot(axis) <= 0.0
				or (midpoint - release).dot(axis) >= 0.0 or bend > max_bend):
			return {"error": "弧线中间点应在起终点之间，且不要偏离直线太远。"}
	return clean

func scale_hold_paths(from_ms: int, to_ms: int, factor: Variant, ids: Variant = null) -> Dictionary:
	if not _number(factor) or factor < 0.1 or factor > 4 or from_ms > to_ms:
		return {"error": "长键路径倍率须为 0.1–4。"}
	var selected := {}
	if ids != null:
		if not ids is Array or ids.is_empty() or ids.size() > 128:
			return {"error": "请指定 1–128 个长键编号。"}
		for value: Variant in ids:
			if not _number(value) or value < 0 or value > 2147483647 or float(value) != floorf(value):
				return {"error": "指定编号必须属于草稿里的长键。"}
			var id := int(value)
			if not notes.has(id) or notes[id].type != "hold":
				return {"error": "指定编号必须属于草稿里的长键。"}
			selected[id] = true
	var pending := {}
	for id: int in notes:
		var row: Dictionary = notes[id]
		if row.type != "hold" or row.time_ms < from_ms or row.time_ms > to_ms or (ids != null and not selected.has(id)):
			continue
		if not _chart.notes.has(id) or row.get("hold_path_changed", false) or row.get("position_changed", false):
			return {"error": "请对已保存且本轮未重新定位的长键缩放路径。", "id": id}
		var scale := float(row.get("geometry_scale", 1.0)) * float(factor)
		if _chart.scaled_hold_geometry(id, scale).is_empty():
			return {"error": "该长键路径不能缩放到画面内。", "id": id}
		var candidate := row.duplicate()
		candidate["geometry_scale"] = scale
		for pair: Array in [["end_x", "end_y"], ["mid_x", "mid_y"]]:
			if candidate.has(pair[0]) and candidate.has(pair[1]):
				candidate[pair[0]] = row.x + (row[pair[0]] - row.x) * factor
				candidate[pair[1]] = row.y + (row[pair[1]] - row.y) * factor
		pending[id] = candidate
	for id: int in pending:
		notes[id] = pending[id]
		edited[id] = true
	return {"count": pending.size(), "range_ms": [from_ms, to_ms], "factor": factor}

func check_conflicts() -> Dictionary:
	var errors: Array = []
	var warnings: Array = []
	var lanes := {}
	var recent: Array = []
	var recent_positions: Array = []
	var held: Array = []
	var previous := {}
	var center_run := 0
	var center_start_id := 0
	var center_edited := false
	var center_reported := false
	var center_ranges: Array[Dictionary] = []
	var directions := {"horizontal": 0, "diagonal": 0, "vertical": 0, "stationary_or_short": 0}
	var edited_directions := directions.duplicate()
	for row: Dictionary in _sorted_notes():
		var time: int = row.time_ms
		if not lanes.has(row.lane):
			lanes[row.lane] = []
		lanes[row.lane].append({"row": row, "first": _occupied_start(row), "last": _occupied_end(row)})
		while not recent.is_empty() and time - int(recent[0].time_ms) > 55:
			recent.pop_front()
		var position := Vector2(row.x, row.y)
		if not CENTER_REGION.has_point(position) or (not previous.is_empty() and time - previous.time_ms > POSITION_WINDOW_MS):
			center_run = 0
		if CENTER_REGION.has_point(position):
			if center_run == 0:
				center_start_id = row.id
				center_edited = false
				center_reported = false
			center_run += 1
			center_edited = center_edited or edited.has(row.id)
			if center_run >= CENTER_RUN_MIN and center_edited and not center_reported:
				warnings.push_front(["落点连续集中在画面中央，可在下一乐句向两侧或上下展开", center_start_id, row.id])
				center_ranges.append({"from_ms": notes[center_start_id].time_ms, "to_ms": time})
				center_reported = true
			elif center_reported:
				center_ranges[-1].to_ms = time
		for other: Dictionary in recent:
			if _touches_edit(other, row) and position.distance_to(Vector2(other.x, other.y)) < 110:
				errors.append(["同时击打位置过近", other.id, row.id])
		if recent.size() >= int(profile.chord_limit) and (edited.has(row.id) or recent.any(func(item: Dictionary): return edited.has(item.id))):
			errors.append(["55 毫秒内超过 %d 个击打" % profile.chord_limit, recent[0].id, row.id])
		held = held.filter(func(item: Dictionary): return item.time_ms + item.duration_ms > time)
		var occupied_hands := held.size()
		for other: Dictionary in recent:
			if not held.has(other):
				occupied_hands += 1
		if not held.is_empty() and occupied_hands >= 2 and (edited.has(row.id) or held.any(func(item: Dictionary): return edited.has(item.id))):
			errors.append(["长键占用期间需要超过两处同时操作", held[0].id, row.id])
		if not previous.is_empty() and _touches_edit(previous, row):
			if _unsafe_transition(previous, row):
				errors.append(["反应时间不足或跳位过大", previous.id, row.id])
		while not recent_positions.is_empty() and time - int(recent_positions[0].time_ms) > POSITION_WINDOW_MS:
			recent_positions.pop_front()
		for other: Dictionary in recent_positions:
			if _touches_edit(other, row) and position.distance_to(Vector2(other.x, other.y)) < REPEAT_RADIUS:
				if time - int(other.time_ms) > 55:
					warnings.append(["近期落点重复，可检查是否为有意编排", other.id, row.id])
				break
		recent_positions.append(row)
		if recent_positions.size() > POSITION_WINDOW_NOTES:
			recent_positions.pop_front()
		if edited.has(row.id) and row.type == "hold" and row.has("end_x"):
			var distance := position.distance_to(Vector2(row.end_x, row.end_y))
			if distance > 300 and distance * 1000.0 / maxf(row.duration_ms, 1) > 1800:
				warnings.append(["长键滑动过快", row.id])
		if row.type == "drag":
			var direction := _slide_direction(row, position)
			directions[direction] += 1
			if edited.has(row.id):
				edited_directions[direction] += 1
		if row.type == "hold":
			held.append(row)
		recent.append(row)
		previous = row
	for entries: Array in lanes.values():
		entries.sort_custom(func(first: Dictionary, second: Dictionary): return first.first < second.first)
		var active: Array = []
		for entry: Dictionary in entries:
			active = active.filter(func(item: Dictionary): return item.last >= entry.first)
			for item: Dictionary in active:
				if _touches_edit(item.row, entry.row):
					errors.append(["同轨键重叠", item.row.id, entry.row.id])
			active.append(entry)
	_count_slides(directions)
	_count_slides(edited_directions)
	if edited_directions.moving >= 4:
		var suggested := ceili(float(edited_directions.moving) / 3.0)
		edited_directions["suggested_horizontal"] = suggested
		if edited_directions.horizontal < suggested:
			warnings.append(["本轮滑键横向比例偏低（横向 %d 个，有轨迹 %d 个，建议横向至少 %d 个）" % [
				edited_directions.horizontal, edited_directions.moving, suggested]])
	return {"error_count": errors.size(), "warning_count": warnings.size(), "errors": errors.slice(0, 32),
		"warnings": warnings.slice(0, 24), "center_ranges": center_ranges.slice(0, 24), "new_hit_chords": new_hit_chords(),
		"slide_directions": directions, "edited_slide_directions": edited_directions}

static func _slide_direction(row: Dictionary, hit: Vector2) -> String:
	if not row.has("approach_x"):
		return "stationary_or_short"
	var delta := (hit - Vector2(row.approach_x, row.approach_y)).abs()
	if delta.length() < 64.0:
		return "stationary_or_short"
	if delta.x >= 64.0 and delta.y <= 12.0:
		return "horizontal"
	if delta.y >= 64.0 and delta.x <= 12.0:
		return "vertical"
	return "diagonal"

static func _count_slides(directions: Dictionary) -> void:
	directions["moving"] = directions.horizontal + directions.vertical + directions.diagonal
	directions["total"] = directions.moving + directions.stationary_or_short

func new_hit_chords() -> Dictionary:
	var counts := {}
	var new_times := {}
	for row: Dictionary in notes.values():
		var time: int = row.time_ms
		counts[time] = int(counts.get(time, 0)) + 1
		if row.type != "hold" and edited.has(row.id) and not _chart.notes.has(row.id):
			new_times[time] = true
	var times := new_times.keys()
	times.sort()
	var sizes := {}
	var singles := []
	for time: int in times:
		var count: int = counts[time]
		sizes[count] = int(sizes.get(count, 0)) + 1
		if count == 1 and singles.size() < 16:
			singles.append(time)
	return {"groups": sizes, "single_count": sizes.get(1, 0), "single_times_ms": singles}

func seed_pattern(music: Dictionary, seed_value: int, from_ms := 0, to_ms := -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var beats: Array = music.get("beats", [])
	if beats.is_empty():
		return {"error": "没有可用的拍点。"}
	var peaks: Array = music.get("onsets", [])
	var accents: Array = music.get("accents", [])
	var downbeats: Array = music.get("downbeats", [])
	var offset := roundi(_chart.audio_delay_ms)
	var earliest := maxi(start_ms + int(profile.intro_ms), from_ms)
	var latest := mini(duration_ms, to_ms) if to_ms >= 0 else duration_ms
	var last_time := -10000
	var last_hold_time := -10000
	var last_quad_time := -10000
	var rest_until := earliest
	var total := 0
	var slots := {}
	var timeline := _sorted_notes()
	var existing_holds := timeline.filter(func(row: Dictionary): return row.type == "hold")
	for row: Dictionary in notes.values():
		_index_note(slots, row)
	var waveform: PackedFloat32Array = _chart.audio_waveform
	var bucket_ms := maxf(_chart.audio_waveform_bucket_ms, 1)
	var phrase_start := 0
	var phrase_variant := -1
	var path_offset := 0
	var phrase_shift := Vector2.ZERO
	var mirror := false
	var slide_count := 0
	for index in range(beats.size()):
		var beat := roundi(beats[index]) + offset
		if beat >= latest:
			break
		var downbeat := _near(downbeats, beat - offset, 72) if not downbeats.is_empty() else index % 4 == 0
		if phrase_variant < 0 or index - phrase_start >= 8 or (downbeat and index - phrase_start >= 6):
			phrase_start = index
			phrase_variant = (phrase_variant + 1 + rng.randi_range(0, PHRASE_PATHS.size() - 2)) % PHRASE_PATHS.size()
			path_offset = rng.randi_range(0, 7)
			phrase_shift = Vector2(rng.randi_range(-2, 2) * 24, rng.randi_range(-2, 2) * 18)
			mirror = not mirror
		var phase := index - phrase_start
		var accented := _near(accents, beat - offset, 64)
		var interval := roundi(float(beats[index + 1]) - float(beats[index])) if index + 1 < beats.size() else 0
		for subdivision in range(profile.subdivisions):
			if subdivision > 0 and (interval < 220 or interval > 1150):
				break
			var time := beat + roundi(float(subdivision * interval) / profile.subdivisions)
			if time < rest_until or time < last_time + int(profile.gap) or time >= latest:
				continue
			var onset := _near(peaks, time - offset, 55)
			var offbeat := subdivision * 2 == int(profile.subdivisions) and phase in [1, 3, 5]
			if subdivision > 0 and not onset and not offbeat:
				continue
			var bucket := roundi(float(time - offset) / bucket_ms)
			if bucket >= 0 and bucket < waveform.size() and waveform[bucket] < 0.008:
				continue
			var insertion := timeline.bsearch_custom({"time_ms": time}, _by_time)
			var neighbors := timeline.slice(maxi(0, insertion - POSITION_WINDOW_NOTES), insertion + POSITION_WINDOW_NOTES)
			if neighbors.any(func(other: Dictionary): return absi(time - int(other.time_ms)) < int(profile.gap)):
				continue
			var path: Array = PHRASE_PATHS[phrase_variant]
			var step := (phase + subdivision * 2 + path_offset) % path.size()
			var position := _choose_position(path, step, mirror, phrase_shift, time, neighbors)
			if position == Vector2.INF:
				continue
			var length := 0
			# Hold through a musical accent or phrase opening, then leave room to release.
			var direction := -1.0 if mirror else 1.0
			var ending := Vector2(clampf(position.x + direction * 180.0, 250.0, 1670.0),
				position.y + (70.0 if accented and phase == 4 else 0.0))
			var hold_spacing := 5200 if difficulty == "EX" else (4400 if difficulty == "HD" else 3800)
			if subdivision == 0 and phase in [0, 4] and (downbeat or accented) and time - last_hold_time >= hold_spacing:
				var max_beats := 4 if phase == 0 and downbeat else 3
				var span := {"time_ms": time, "x": position.x, "y": position.y, "end_x": ending.x, "end_y": ending.y}
				for beat_count in range(max_beats, 1, -1):
					if index + beat_count >= beats.size():
						continue
					var release := roundi(beats[index + beat_count]) + offset
					var hold_ms := release - time
					if release > latest or hold_ms < int(profile.hold_ms) or hold_ms > MAX_HOLD_DURATION_MS:
						continue
					span["duration_ms"] = hold_ms
					if _hold_fits(timeline, insertion, span):
						length = hold_ms
						break
			var kind := "hold" if length > 0 else "note"
			if kind == "note" and (subdivision > 0 or phase in ([2, 6] if difficulty == "EZ" else [1, 3, 6])):
				kind = "drag"
			var row := {"id": next_id, "type": kind, "time_ms": time, "x": position.x, "y": position.y,
				"duration_ms": length, "lead_ms": profile.lead_ms}
			if kind == "drag":
				var tilt := 0.0 if slide_count % 3 != 2 else (115.0 if slide_count % 2 == 0 else -115.0)
				row["approach_x"] = position.x - direction * (175.0 if difficulty == "EZ" else 240.0)
				row["approach_y"] = position.y - tilt
			elif kind == "hold":
				row["end_x"] = ending.x
				row["end_y"] = ending.y
			var first_lane := (index + subdivision * 2) % track_count
			if not _place_in_lane(slots, row, first_lane):
				continue
			var group: Array[Dictionary] = [row]
			if difficulty == "EX" and track_count >= 2 and kind != "hold":
				if existing_holds.any(func(hold: Dictionary): return hold.time_ms <= time and time < hold.time_ms + hold.duration_ms):
					continue
				var target := 2
				if (subdivision > 0 and not onset) or (subdivision == 0 and not downbeat and phase in [1, 5]):
					target = 1
				elif subdivision == 0 and (downbeat or (accented and phase in [2, 4, 6])):
					target = 3
					if downbeat and phase in [0, 4] and time - last_quad_time >= 4200:
						target = 4
				_add_chord_hits(group, slots, neighbors, mini(target, track_count), first_lane, mirror)
				if group.size() == 4:
					last_quad_time = time
			if kind == "hold":
				last_hold_time = time
				rest_until = time + length + int(profile.gap)
			elif kind == "drag":
				slide_count += 1
			for member: Dictionary in group:
				notes[next_id] = member
				edited[next_id] = true
				next_id += 1
				_index_note(slots, member)
				timeline.insert(insertion, member)
				insertion += 1
			last_time = time
			total += group.size()
			if notes.size() >= LIMIT:
				return {"added": total}
	return {"added": total}

func _add_chord_hits(group: Array[Dictionary], slots: Dictionary, neighbors: Array, target: int, lane: int, mirror: bool) -> void:
	var lead := group[0]
	var candidates: Array = []
	var direction := -1.0 if mirror else 1.0
	for y: float in [0.0, -155.0, 155.0, -310.0, 310.0]:
		for x: float in [200.0, -200.0, 0.0, 400.0, -400.0]:
			var point := Vector2(clampf(lead.x + direction * x, 300.0, 1620.0), clampf(lead.y + y, 260.0, 820.0))
			candidates.append(point)
	var nearby := neighbors.duplicate()
	nearby.append(lead)
	var used_lanes := [lead.lane]
	while group.size() < target and notes.size() + group.size() < LIMIT:
		var position := _choose_position(candidates, 0, false, Vector2.ZERO, lead.time_ms, nearby)
		if position == Vector2.INF:
			break
		var hit := {"id": next_id + group.size(), "type": "note", "time_ms": lead.time_ms,
			"x": position.x, "y": position.y, "duration_ms": 0, "lead_ms": profile.lead_ms}
		if not _place_in_lane(slots, hit, lane + group.size(), used_lanes):
			break
		group.append(hit)
		nearby.append(hit)
		used_lanes.append(hit.lane)

func _choose_position(path: Array, start: int, mirror: bool, shift: Vector2, time: int, neighbors: Array) -> Vector2:
	for index in range(path.size()):
		var position: Vector2 = path[(start + index) % path.size()]
		if mirror:
			position.x = 1920.0 - position.x
		position += shift
		var candidate := {"x": position.x, "y": position.y, "time_ms": time, "duration_ms": 0}
		var acceptable := true
		for other: Dictionary in neighbors:
			var gap := absi(time - int(other.time_ms))
			var minimum := 110.0 if gap <= 55 else REPEAT_RADIUS
			if gap <= POSITION_WINDOW_MS and position.distance_to(Vector2(other.x, other.y)) < minimum:
				acceptable = false
				break
			var prior: Dictionary = other if other.time_ms < time else candidate
			var next: Dictionary = candidate if other.time_ms < time else other
			if _unsafe_transition(prior, next):
				acceptable = false
				break
		if acceptable:
			return position
	return Vector2.INF

func _unsafe_transition(first: Dictionary, second: Dictionary) -> bool:
	var gap: int = second.time_ms - first.time_ms
	if gap <= 55:
		return false
	if gap < int(profile.gap):
		return true
	var origin := Vector2(first.x, first.y)
	if first.duration_ms > 0 and gap >= first.duration_ms:
		gap -= int(first.duration_ms)
		origin = Vector2(first.get("end_x", first.x), first.get("end_y", first.y))
	var distance := origin.distance_to(Vector2(second.x, second.y))
	return gap < 450 and distance > 230.0 + gap * float(profile.travel)

func _hold_fits(timeline: Array, insertion: int, hold: Dictionary) -> bool:
	var time: int = hold.time_ms
	if insertion < timeline.size():
		var next: Dictionary = timeline[insertion]
		if next.time_ms < time + int(hold.duration_ms) + int(profile.gap) or _unsafe_transition(hold, next):
			return false
	for index in range(insertion - 1, -1, -1):
		var previous: Dictionary = timeline[index]
		if previous.time_ms + previous.duration_ms > time:
			return false
	return true

func _place_in_lane(slots: Dictionary, row: Dictionary, first_lane: int, used_lanes: Array = []) -> bool:
	for index in range(track_count):
		row["lane"] = (first_lane + index) % track_count
		if row.lane not in used_lanes and not _occupied(slots, row):
			return true
	return false

func _occupied_start(row: Dictionary) -> int:
	var original = _chart.notes.get(row.id)
	var lead: int = original.judge_time - original.start_time if original else row.get("lead_ms", profile.lead_ms)
	return _chart.ms_to_time_unit(maxi(row.time_ms - lead if row.type == "hold" else row.time_ms, 0))

func _occupied_end(row: Dictionary) -> int:
	var ending: int = _chart.ms_to_time_unit(row.time_ms + row.duration_ms)
	return maxi(ending, _occupied_start(row) + 1) if row.type == "hold" else ending

func _index_note(slots: Dictionary, row: Dictionary) -> void:
	if not slots.has(row.lane):
		slots[row.lane] = []
	slots[row.lane].append(Vector2i(_occupied_start(row), _occupied_end(row)))

func _occupied(slots: Dictionary, row: Dictionary) -> bool:
	var first := _occupied_start(row)
	var last := _occupied_end(row)
	for range_value: Vector2i in slots.get(row.lane, []):
		if first <= range_value.y and last >= range_value.x:
			return true
	return false

func _touches_edit(first: Dictionary, second: Dictionary) -> bool:
	return edited.has(first.id) or edited.has(second.id)

func _sorted_notes() -> Array:
	var rows := notes.values()
	rows.sort_custom(_by_time)
	return rows

static func _by_time(first: Dictionary, second: Dictionary) -> bool:
	if first.time_ms == second.time_ms:
		return int(first.get("id", -1)) < int(second.get("id", -1))
	return first.time_ms < second.time_ms

static func _near(times: Array, time: float, radius: float) -> bool:
	var index := times.bsearch(time - radius)
	return index < times.size() and float(times[index]) <= time + radius

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))
