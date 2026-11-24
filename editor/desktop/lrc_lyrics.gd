extends RefCounted

static func load_cues(path: String, duration_ms: int) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file or file.get_length() > 1024 * 1024:
		return []
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if bytes.size() < 2:
		return []
	var content := ""
	if bytes[0] == 0xFF and bytes[1] == 0xFE:
		content = bytes.slice(2).get_string_from_utf16()
	elif bytes[0] == 0xFE and bytes[1] == 0xFF:
		for i in range(2, bytes.size() - 1, 2):
			var first := bytes[i]
			bytes[i] = bytes[i + 1]
			bytes[i + 1] = first
		content = bytes.slice(2).get_string_from_utf16()
	else:
		content = bytes.get_string_from_utf8().trim_prefix("\uFEFF")
	return _parse(content, duration_ms)

static func _parse(content: String, duration_ms: int) -> Array:
	var stamp := RegEx.create_from_string("^\\[(\\d{1,4}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]")
	var offset_tag := RegEx.create_from_string("(?im)^\\s*\\[offset\\s*:\\s*([+-]?\\d+)\\s*\\]")
	var metadata := offset_tag.search(content)
	var offset := int(metadata.get_string(1)) if metadata else 0
	var lines := {}
	for raw: String in content.split("\n"):
		var lyric := raw.strip_edges()
		var times := PackedInt64Array()
		var tag := stamp.search(lyric)
		while tag:
			var seconds := int(tag.get_string(2))
			if seconds < 60:
				var fraction := (tag.get_string(3) + "000").left(3)
				var ms := (int(tag.get_string(1)) * 60 + seconds) * 1000 + int(fraction) + offset
				if duration_ms <= 0 or ms < duration_ms:
					times.append(maxi(0, ms))
			lyric = lyric.substr(tag.get_end()).strip_edges()
			tag = stamp.search(lyric)
		for time: int in times:
			if not lines.has(time):
				lines[time] = PackedStringArray()
			if not lyric.is_empty() and lyric not in lines[time]:
				lines[time].append(lyric)
	var timeline := lines.keys()
	timeline.sort()
	var cues: Array = []
	for i in range(timeline.size()):
		var time: int = timeline[i]
		var lyric := "　".join(lines[time])
		if lyric.is_empty():
			continue
		var end: int = timeline[i + 1] - 1 if i + 1 < timeline.size() else time + 4000
		if duration_ms > 0:
			end = mini(end, duration_ms)
		cues.append({"time": time, "end": end, "text": lyric})
	return cues
