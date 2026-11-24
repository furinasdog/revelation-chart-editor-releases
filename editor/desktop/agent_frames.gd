extends RefCounted

const FRAME_SIZE := Vector2i(320, 180)
const MAX_FRAMES := 6
const RenderPreview := preload("res://desktop/render_preview.gd")

static func capture(host: Node, chart: Node, plan: RefCounted, animation: RefCounted, times: Array,
		edits: Dictionary = {}) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {"error": "当前运行环境没有图形渲染，无法取帧。"}
	var scene := RenderPreview.mount(host, chart, FRAME_SIZE)
	var viewport: SubViewport = scene.viewport
	var snapshot: Node = scene.chart
	snapshot.preview_image_overrides = animation.preview_images() if animation else {}
	snapshot.apply_automatic_notes(plan.notes, plan.edited, animation.layers.values() if animation else [],
		animation.mask_cues.values() if animation else [], {}, edits)
	var columns := mini(times.size(), 3)
	var rows := ceili(float(times.size()) / columns)
	var montage := Image.create_empty(FRAME_SIZE.x * columns, FRAME_SIZE.y * rows, false, Image.FORMAT_RGB8)
	await host.get_tree().process_frame
	for index in range(times.size()):
		var frame := await RenderPreview.frame(scene, float(times[index]))
		if frame == null or frame.is_empty():
			viewport.queue_free()
			return {"error": "未取得渲染帧。"}
		frame.convert(Image.FORMAT_RGB8)
		montage.blit_rect(frame, Rect2i(Vector2i.ZERO, FRAME_SIZE),
			Vector2i(index % columns, floori(float(index) / columns)) * FRAME_SIZE)
	viewport.queue_free()
	var frame_size := FRAME_SIZE
	var jpeg := montage.save_jpg_to_buffer(0.75)
	while jpeg.size() > 78000:
		frame_size = Vector2i(maxi(1, frame_size.x * 3 / 4), maxi(1, frame_size.y * 3 / 4))
		montage.resize(frame_size.x * columns, frame_size.y * rows, Image.INTERPOLATE_LANCZOS)
		jpeg = montage.save_jpg_to_buffer(0.70)
	return {"times_ms": times, "columns": columns, "rows": rows, "frame_size": [frame_size.x, frame_size.y],
		"_preview_image": "data:image/jpeg;base64," + Marshalls.raw_to_base64(jpeg)}
