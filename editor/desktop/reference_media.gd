extends RefCounted

const References := preload("res://desktop/reference_library.gd")
const ImageLimit := 12 * 1024 * 1024

static func artwork(chart: Node, id: String, filename: String) -> Dictionary:
	var media := References.media(id, "images")
	if media.has("error"):
		return media
	if filename not in media.items or int(media.entries[filename]) > ImageLimit:
		return {"error": "请从已授权的参考图片中选择 PNG 或 JPEG。"}
	var archive := ZIPReader.new()
	if archive.open(media.bundle) != OK:
		return {"error": "无法打开参考曲绘。"}
	var bytes := archive.read_file(filename)
	archive.close()
	var ext := filename.get_extension().to_lower()
	var size: Vector2i = chart._encoded_image_size(bytes, ext)
	if size.x <= 0 or size.y <= 0 or size.x > ImageLimit or size.y > ImageLimit or size.x * size.y > ImageLimit:
		return {"error": "参考图像尺寸超限或格式无效。"}
	var image := Image.new()
	var status := image.load_png_from_buffer(bytes) if ext == "png" else image.load_jpg_from_buffer(bytes)
	return _preview(image, id) if status == OK else {"error": "无法解码参考曲绘。"}

static func frame(host: Node, id: String, time_ms: int, live: Callable) -> Dictionary:
	var media := References.media(id, "images")
	if media.has("error"):
		return media
	# Rendering a package can also load its audio stream. Require the grant before opening it.
	if not media.entries.keys().filter(func(path: String): return path.get_extension().to_lower() in ["wav", "ogg", "mp3"]).is_empty():
		var audio := References.media(id, "audio")
		if audio.has("error"):
			return {"error": "参考谱渲染还需要该谱的本机音频读取授权。"}
	var task := ProjectSettings.globalize_path("user://reference-render-" + Crypto.new().generate_random_bytes(12).hex_encode())
	var options := {"command": "render", "input": ProjectSettings.globalize_path(media.bundle), "frame_ms": time_ms, "output": task + ".png"}
	var input := FileAccess.open(task + ".in.json", FileAccess.WRITE)
	if not input or not input.store_string(JSON.stringify(options)):
		return {"error": "无法创建参考渲染任务。"}
	input.close()
	var args := PackedStringArray(["--audio-driver", "Dummy", "--position", "-32000,-32000"])
	if OS.has_feature("editor"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])
	args.append_array(["--", "--revelation-cli", task + ".in.json", task + ".out.json"])
	var pid := OS.create_process(OS.get_executable_path(), args, false)
	var deadline := Time.get_ticks_msec() + 30000
	while pid > 0 and OS.is_process_running(pid) and live.call() and Time.get_ticks_msec() < deadline:
		await host.get_tree().process_frame
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	var image := Image.new()
	var result := _preview(image, id) if image.load(task + ".png") == OK else {"error": "参考谱渲染失败或已取消。"}
	for extension: String in [".in.json", ".out.json", ".png"]:
		DirAccess.remove_absolute(task + extension)
	if not result.has("error"):
		result["time_ms"] = time_ms
	return result

static func _preview(image: Image, id: String) -> Dictionary:
	var scale := minf(1.0, 640.0 / maxi(image.get_width(), image.get_height()))
	image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	var bytes := image.save_jpg_to_buffer(0.72)
	return {"id": id, "_preview_image": "data:image/jpeg;base64," + Marshalls.raw_to_base64(bytes)}
