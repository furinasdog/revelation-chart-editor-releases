extends RefCounted

const MAX_FIGURE_MS := 45000
const MAX_JPEG_BYTES := 72000

static func loudness(chart: Node, span: Vector2i, window_ms: int, offset: int, limit: int) -> Dictionary:
	if chart.audio_rms_waveform.is_empty():
		return {"error": "尚无响度数据。请先导入音频。"}
	var report := _levels(chart, span.x, span.y)
	var total := ceili(float(span.y - span.x) / window_ms)
	var windows := []
	for index in range(offset, mini(total, offset + limit)):
		var start := span.x + index * window_ms
		windows.append(_levels(chart, start, mini(span.y, start + window_ms)))
	report.merge({"items": windows, "offset": offset, "total": total, "window_ms": window_ms,
		"unit": "dBFS", "method": "Stereo RMS from the sampled audio. Waveform peak uses the mono display samples.",
		"silence_floor_dbfs": -120.0})
	if offset + windows.size() < total:
		report["next_offset"] = offset + windows.size()
	return report

static func _levels(chart: Node, start: int, end: int) -> Dictionary:
	var bucket: float = chart.audio_waveform_bucket_ms
	var first := maxi(0, floori((start - chart.audio_delay_ms) / bucket))
	var last := mini(chart.audio_rms_waveform.size(), ceili((end - chart.audio_delay_ms) / bucket))
	var energy := 0.0
	var weight := 0.0
	var peak := 0.0
	for index in range(first, last):
		var begins: float = chart.audio_delay_ms + index * bucket
		var overlap := minf(end, begins + bucket) - maxf(start, begins)
		var amplitude: float = chart.audio_rms_waveform[index]
		energy += amplitude * amplitude * overlap
		weight += overlap
		peak = maxf(peak, chart.audio_waveform[index])
	return {"time_ms": start, "end_ms": end,
		"rms_dbfs": _db(sqrt(energy / maxf(weight, 1.0))), "waveform_peak_dbfs": _db(peak)}

static func _db(amplitude: float) -> float:
	return snappedf(linear_to_db(maxf(amplitude, 0.000001)), 0.1)

static func waveform(chart: Node, span: Vector2i) -> Dictionary:
	var samples: PackedFloat32Array = chart.audio_waveform
	if samples.is_empty():
		return {"error": "尚无波形，请先导入音频。"}
	const SIZE := Vector2i(720, 224)
	var plot := Image.create_empty(SIZE.x, SIZE.y, false, Image.FORMAT_RGB8)
	plot.fill(Color("#111820"))
	for division in range(9):
		var x := roundi(division * (SIZE.x - 1) / 8.0)
		plot.fill_rect(Rect2i(x, 0, 1, SIZE.y), Color("#32414f"))
	plot.fill_rect(Rect2i(0, SIZE.y / 2, SIZE.x, 1), Color("#708497"))
	var bucket: float = chart.audio_waveform_bucket_ms
	var delay: float = chart.audio_delay_ms
	for x in range(SIZE.x):
		var start := lerpf(span.x, span.y, float(x) / SIZE.x)
		var end := lerpf(span.x, span.y, float(x + 1) / SIZE.x)
		var first := maxi(0, floori((start - delay) / bucket))
		var last := mini(samples.size(), ceili((end - delay) / bucket))
		var peak := 0.0
		for index in range(first, last):
			peak = maxf(peak, samples[index])
		var height := roundi(clampf(peak, 0.0, 1.0) * (SIZE.y / 2 - 5))
		if height > 0:
			plot.fill_rect(Rect2i(x, SIZE.y / 2 - height, 1, height * 2 + 1), Color("#73c5ff"))
	return image_result(plot, "waveform", span)

static func image_result(plot: Image, kind: String, span: Vector2i) -> Dictionary:
	var bytes := plot.save_jpg_to_buffer(0.82)
	while bytes.size() > MAX_JPEG_BYTES:
		plot.resize(maxi(1, plot.get_width() * 3 / 4), maxi(1, plot.get_height() * 3 / 4), Image.INTERPOLATE_LANCZOS)
		bytes = plot.save_jpg_to_buffer(0.76)
	if bytes.is_empty():
		return {"error": "无法编码音频图。"}
	return {"kind": kind, "from_ms": span.x, "to_ms": span.y, "image_size": [plot.get_width(), plot.get_height()],
		"axes": "Time increases left to right. The waveform is the mirrored peak-amplitude envelope." if kind == "waveform"
			else "Horizontal labels are seconds from from_ms. The vertical axis is frequency in Hz (log scale).",
		"_preview_image": "data:image/jpeg;base64," + Marshalls.raw_to_base64(bytes)}
