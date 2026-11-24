extends RefCounted

const TITLES := ["底图", "遮罩", "背景动画"]

static func collect(chart: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var switches := [{}, {}]
	var end_ms := roundi(chart.audio_duration_ms + chart.audio_delay_ms) if chart.audio_duration_ms > 0 else int(chart.time_unit_to_ms(roundi(chart.total_beats * 64)))
	var defaults: Array[String] = [chart.preview_bg_image_path, chart.preview_mask_image_path]
	for id: int in chart.events:
		var event = chart.events[id]
		if event.type in [0, 1] and not event.image_path.is_empty():
			switches[1 - event.type][event.start_time] = id
	for lane in range(switches.size()):
		var times: Array = switches[lane].keys()
		times.sort()
		if not defaults[lane].is_empty() and (times.is_empty() or times[0] > 0):
			var stop: int = end_ms if times.is_empty() else times[0]
			rows.append(_image_clip(lane, -1, 0, stop, defaults[lane]))
		for index in range(times.size()):
			var start: int = times[index]
			var id: int = switches[lane][start]
			var stop: int = maxi(end_ms, start + 1) if index == times.size() - 1 else times[index + 1]
			rows.append(_image_clip(lane, id, start, stop, chart.events[id].image_path))
	var mounts: Dictionary = chart.get_bg_anim_mounts()
	for group: String in mounts:
		var duration := 0
		var slot: int = chart.bg_anim_key_slot_from_group(group)
		var events: Array = chart.get_bg_anim_key_events(slot) if slot >= 0 else chart.get_preset_bg_events(group)
		for step: Dictionary in events:
			duration = maxi(duration, int(step.get("startTime", 0)) + int(step.get("duration", 0)))
		for mount: Dictionary in mounts[group]:
			var start := roundi(mount.time)
			rows.append({"key": [2, group, start], "lane": 2, "start": start,
				"end": start + maxi(duration, 1), "title": group, "group": group})
	return rows

static func _image_clip(lane: int, id: int, start: int, stop: int, path: String) -> Dictionary:
	return {"key": [lane, id], "lane": lane, "event_id": id, "start": start, "end": stop,
		"title": path.get_file(), "path": path}
