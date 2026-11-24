extends RefCounted

const Archive := preload("res://main/chart_archive.gd")
const ROOT := "user://reference_charts"
const BUILTIN := "res://references/phrase_study.json"
const LIMIT := 8 * 1024 * 1024
const MAX_REFERENCES := 64
const NOTE_TYPES := ["note", "drag", "hold"]
const SECTIONS := ["notes", "paths", "events", "masks", "keyframes"]

static func import_local(path: String, allow_images := false, allow_audio := false) -> Dictionary:
	var raw := _read(path)
	if raw.is_empty():
		return {"error": "未找到受支持的参考谱数据。请使用谱面 JSON 或 ZIP，谱面 JSON 须在 8 MiB 以内。"}
	# The library stores chart data only. Asset names remain usable as design references.
	var doc := _data_only(raw, path.get_file().get_basename())
	var media := {"images": allow_images, "audio": allow_audio}
	if (allow_images or allow_audio) and path.get_extension().to_lower() != "zip":
		return {"error": "含素材的参考谱须为 ZIP。"}
	var bytes := JSON.stringify(doc).to_utf8_buffer()
	if bytes.size() > LIMIT:
		return {"error": "参考谱超过大小限制。"}
	var id := bytes.get_string_from_utf8().sha256_text().left(24)
	if DirAccess.make_dir_recursive_absolute(ROOT) != OK:
		return {"error": "无法创建参考谱目录。"}
	var filename := ROOT.path_join(id + ".json")
	if not FileAccess.file_exists(filename):
		if _local_files().size() >= MAX_REFERENCES:
			return {"error": "参考谱库最多保存 64 份本地参考谱。"}
		var file := FileAccess.open(filename, FileAccess.WRITE)
		if not file or not file.store_buffer(bytes):
			return {"error": "无法保存参考谱。"}
		file.close()
	if allow_images or allow_audio:
		var bundle := ROOT.path_join(id + ".zip")
		if DirAccess.copy_absolute(path, bundle) != OK:
			return {"error": "无法保存已授权的参考谱素材。"}
	var grants := FileAccess.open(ROOT.path_join(id + ".media"), FileAccess.WRITE)
	if not grants or not grants.store_string(JSON.stringify(media)):
		return {"error": "无法保存参考谱授权。"}
	grants.close()
	return _summary(id, doc)

static func list_references(query: String, difficulty: String, offset: int, limit: int) -> Dictionary:
	var rows := []
	for location: String in [BUILTIN] + _local_files().map(func(name: String): return ROOT.path_join(name)):
		var doc := _read(location)
		if doc.is_empty():
			continue
		var id := "phrase-study" if location == BUILTIN else location.get_file().get_basename()
		var row := _summary(id, doc)
		if (query.is_empty() or query.to_lower() in str(row.title).to_lower() or query == id) and (
				difficulty.is_empty() or difficulty.to_lower() in str(row.difficulty).to_lower()):
			rows.append(row)
	return {"items": rows.slice(offset, offset + limit), "total": rows.size(), "offset": offset}

static func _local_files() -> Array:
	return Array(DirAccess.get_files_at(ROOT)).filter(func(name: String): return name.length() == 29 and name.ends_with(".json"))

static func media(id: String, category: String) -> Dictionary:
	if id.length() != 24 or not id.is_valid_hex_number(false) or category not in ["images", "audio"]:
		return {"error": "该参考谱没有对应素材授权。"}
	var grants := FileAccess.open(ROOT.path_join(id + ".media"), FileAccess.READ)
	var access: Variant = JSON.parse_string(grants.get_as_text()) if grants and grants.get_length() <= 256 else null
	if not access is Dictionary or access.get(category) != true:
		return {"error": "该参考谱没有对应素材授权。"}
	var bundle := ROOT.path_join(id + ".zip")
	var entries := Archive.inspect(bundle)
	if entries.is_empty():
		return {"error": "无法读取参考谱素材包。"}
	var formats := ["png", "jpg", "jpeg"] if category == "images" else ["wav", "mp3", "ogg"]
	var names := entries.keys().filter(func(path: String): return path.get_extension().to_lower() in formats)
	names.sort()
	return {"bundle": bundle, "entries": entries, "items": names}

static func query(id: String, section: String, from_ms: int, to_ms: int, offset: int, limit: int) -> Dictionary:
	if id != "phrase-study" and (id.length() != 24 or not id.is_valid_hex_number(false)):
		return {"error": "请提供参考谱的 ID。"}
	var doc := _read(BUILTIN if id == "phrase-study" else ROOT.path_join(id + ".json"))
	if doc.is_empty():
		return {"error": "找不到该参考谱。"}
	var summary := _summary(id, doc)
	if section == "summary":
		return summary
	if section not in SECTIONS or to_ms < from_ms:
		return {"error": "请选择有效的参考类别和时间。"}
	var rows := []
	if section == "keyframes":
		for field: String in ["anim_rect_slots", "bgAnimKeySlots"]:
			var slots: Variant = doc.get(field, [])
			if not slots is Array:
				continue
			for index in range(slots.size()):
				if slots[index] is Array:
					_append_frames(rows, slots[index], field, str(index), from_ms, to_ms)
		for field: String in ["animationRectData", "defaultBackgroundSetting"]:
			var slots: Variant = doc.get(field, {})
			if not slots is Dictionary:
				continue
			for name: String in slots:
				if slots[name] is Array:
					_append_frames(rows, slots[name], field, name, from_ms, to_ms)
	else:
		for entry: Variant in _items(doc):
			if not entry is Dictionary:
				continue
			var kind := str(entry.get("type", ""))
			var note := _is_note(kind)
			if (section == "notes" and not note) or (section == "paths" and not (kind.begins_with("hold") or kind.begins_with("drag"))):
				continue
			if (section == "events" and note) or (section == "masks" and kind not in ["setCover", "setBottomBg", "animationRect"]):
				continue
			var first := _timestamp(entry.get("judgeTime", entry.get("endTime", 0)) if note else entry.get("startTime", 0))
			var last := _timestamp(entry.get("endTime", first))
			if first > to_ms or maxi(first, last) < from_ms:
				continue
			var row := {"type": kind, "time_ms": first, "end_ms": maxi(first, last)}
			if note:
				row["appear_ms"] = _timestamp(entry.get("startTime", first))
				row["position"] = entry.get("position", [])
				var editor: Variant = entry.get("chartEditor", {})
				row["lane"] = editor.get("track", 0) if editor is Dictionary else 0
			if section == "paths":
				for field: String in ["line", "move", "bezierPoint", "useBezierCurve"]:
					if entry.has(field):
						row[field] = entry[field]
			elif not note:
				row["image_name"] = str(entry.get("imagePath", "")).replace("\\", "/").get_file()
				row["animation"] = str(entry.get("animation", "")).left(120)
				if kind == "text":
					row["text"] = str(entry.get("text", "")).left(300)
			rows.append(row)
		if section == "masks":
			var presets: Variant = doc.get("defaultBackgroundSetting", {})
			if presets is Dictionary:
				for group: String in presets:
					if presets[group] is Array:
						_append_frames(rows, presets[group], "defaultBackgroundSetting", group, from_ms, to_ms)
	rows.sort_custom(func(a: Dictionary, b: Dictionary): return a.time_ms < b.time_ms)
	return {"id": id, "section": section, "items": rows.slice(offset, offset + limit),
		"total": rows.size(), "offset": offset}

static func _append_frames(rows: Array, frames: Array, source: String, slot: String, from_ms: int, to_ms: int) -> void:
	for frame: Variant in frames:
		if not frame is Dictionary:
			continue
		var time := _timestamp(frame.get("startTime", frame.get("delayTime", 0)))
		if time <= to_ms and time + _timestamp(frame.get("duration", 0)) >= from_ms:
			rows.append({"time_ms": time, "source": source, "slot": slot, "properties": frame})

static func _summary(id: String, doc: Dictionary) -> Dictionary:
	var basic: Variant = doc.get("basic", {})
	if not basic is Dictionary:
		basic = {}
	var counts := {"notes": 0, "holds": 0, "events": 0, "masks": 0}
	var length := 0
	for row: Variant in _items(doc):
		if not row is Dictionary:
			continue
		var kind := str(row.get("type", ""))
		var is_note := _is_note(kind)
		counts["notes" if is_note else "events"] += 1
		counts.holds += int(kind.begins_with("hold"))
		counts.masks += int(kind in ["setCover", "setBottomBg"])
		length = maxi(length, maxi(_timestamp(row.get("startTime", 0)), _timestamp(row.get("endTime", 0))))
	return {"id": id, "title": str(basic.get("chartName", id)).left(150),
		"difficulty": str(basic.get("difficulty", "")).left(40), "duration_ms": length,
		"counts": counts, "bundled": id == "phrase-study", "sections": SECTIONS}

static func _data_only(doc: Dictionary, fallback: String) -> Dictionary:
	var meta: Variant = doc.get("basic", {})
	var title: String = str(meta.get("chartName", fallback)) if meta is Dictionary else fallback
	var difficulty: String = str(meta.get("difficulty", "")) if meta is Dictionary else ""
	var result := {"basic": {"chartName": title.left(150), "difficulty": difficulty.left(40)}, "data": _items(doc)}
	for field: String in ["anim_rect_slots", "bgAnimKeySlots", "animationRectData", "defaultBackgroundSetting"]:
		if doc.has(field):
			result[field] = doc[field]
	return result

static func _read(path: String) -> Dictionary:
	var bytes := PackedByteArray()
	if path.get_extension().to_lower() == "zip":
		var entries := Archive.inspect(path)
		var filename := ""
		for candidate: String in entries:
			if candidate.get_extension().to_lower() == "json" and int(entries[candidate]) <= LIMIT:
				if filename.is_empty() or candidate.get_file().to_lower() == "chart.json":
					filename = candidate
		var reader := ZIPReader.new()
		if filename.is_empty() or reader.open(path) != OK:
			return {}
		bytes = reader.read_file(filename)
		reader.close()
		if bytes.size() != int(entries[filename]):
			return {}
	else:
		var file := FileAccess.open(path, FileAccess.READ)
		if not file or file.get_length() > LIMIT:
			return {}
		bytes = file.get_buffer(file.get_length())
	var decoded: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if decoded is Array and not decoded.is_empty():
		return {"data": decoded}
	if decoded is Dictionary and (decoded.get("data", decoded.get("items")) is Array):
		return decoded
	return {}

static func _items(doc: Dictionary) -> Array:
	var values: Variant = doc.get("data", doc.get("items", []))
	return values if values is Array else []

static func _is_note(kind: String) -> bool:
	return NOTE_TYPES.any(func(prefix: String): return kind.begins_with(prefix))

static func _timestamp(value: Variant) -> int:
	return roundi(clampf(float(value), 0, 86400000)) if (value is int or value is float) and is_finite(float(value)) else 0
