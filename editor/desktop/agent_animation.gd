extends RefCounted

const Shapes := preload("res://desktop/agent_shapes.gd")
const IMPORTED_BYTES_LIMIT := 24 * 1024 * 1024
const PALETTE := {"blue": Color("#5caeff"), "amber": Color("#f5bc60"),
	"violet": Color("#a49afa"), "teal": Color("#67c6ba"), "rose": Color("#cf8fa5"), "white": Color.WHITE}
const FIELDS := {"x": [-320.0, 2240.0], "y": [-180.0, 1260.0], "scale": [0.25, 1.8],
	"rotation": [-90.0, 90.0], "opacity": [0.0, 0.90]}
const EASINGS := ["smooth", "out", "linear"]

var layers: Dictionary = {}
var artwork: Dictionary = {}
var masks: Dictionary = {}
var mask_cues: Dictionary = {}
var artwork_cues := {}
var project_images := {}
var shapes := Shapes.new()
var imported_artwork := {}
var _imported_bytes := 0
var _used := {}
var _existing_covers := {}
var _existing_bottoms := {}
var _chart: Node
var _background_path: String
var _mask_path_at_start: String
var _duration: int
var _reveal_limit: int

func _init(chart: Node, duration: int, images: Array[Dictionary]) -> void:
	_chart = chart
	_duration = duration
	for image: Dictionary in images:
		var id := "artwork_%d" % (artwork.size() + 1)
		artwork[id] = image
	_background_path = chart.preview_bg_image_path
	_mask_path_at_start = chart.preview_mask_image_path
	_reveal_limit = clampi(64 - chart.get_anim_group_names().size(), 0, 8)
	for event in chart.events.values():
		if event.type == 0:
			_existing_covers[event.start_time] = event.image_path
		elif event.type == 1:
			_existing_bottoms[event.start_time] = event.image_path
	var placeholder: Dictionary = chart._make_create_step()
	for index in range(chart.anim_rect_slots.size()):
		var existing: Variant = chart.anim_rect_slots[index]
		if existing is Array and not existing.is_empty() and (existing.size() > 1 or existing[0] != placeholder):
			_used[index] = existing.size()

func list_layers() -> Dictionary:
	return {"existing": _used, "draft": layers.values().map(func(layer: Dictionary):
		return {"slot": layer.slot, "source": layer.source, "artwork_id": layer.get("artwork_id", ""), "keyframes": layer.get("frames", []),
			"time_ms": layer.get("time_ms", 0), "shape_id": layer.get("shape_id", "")}),
		"masks": masks.keys(), "mask_cues": mask_cues.values(), "artwork_cues": artwork_cues.values(),
		"has_visible_motion": has_visible_motion()}

func artwork_catalog() -> Array:
	return artwork.keys().map(func(id: String): return _artwork_info(id))

func get_artwork(arguments: Dictionary) -> Dictionary:
	if artwork.is_empty():
		return {"provided": false}
	var id := _artwork_id(arguments)
	if not artwork.has(id):
		return {"error": "请使用曲绘清单中的 artwork_id。", "available": artwork.keys()}
	var result := _artwork_info(id)
	result["provided"] = true
	result["artwork"] = artwork_catalog()
	return result

func _artwork_info(id: String) -> Dictionary:
	var image: Dictionary = artwork[id]
	var size: Vector2 = image.get("size", Vector2.ZERO)
	return {"artwork_id": id, "filename": image.get("filename", str(image.path).get_file()), "width": size.x, "height": size.y,
		"visibility": image.get("visibility", {})}

func register_artwork(image: Dictionary, bytes: PackedByteArray = PackedByteArray()) -> Dictionary:
	var existing := _find_artwork_by_path(image.path)
	if not existing.is_empty():
		return _artwork_info(existing)
	if artwork.size() >= 16 or _imported_bytes + bytes.size() > IMPORTED_BYTES_LIMIT:
		return {"error": "每个草稿最多登记 16 张曲绘，新导入的图片合计最多 24 MiB。"}
	var id := "artwork_%d" % (artwork.size() + 1)
	artwork[id] = image
	if not bytes.is_empty():
		imported_artwork[image.path] = bytes
		_imported_bytes += bytes.size()
	return _artwork_info(id)

func set_project_artwork(arguments: Dictionary) -> Dictionary:
	var id := _artwork_id(arguments)
	var target := str(arguments.get("target", "background"))
	if not artwork.has(id) or target not in ["background", "mask"]:
		return {"error": "请选择曲绘编号，目标为 background 或 mask。"}
	project_images[target] = artwork[id].path
	return {"artwork_id": id, "target": target}

func set_artwork_cue(arguments: Dictionary) -> Dictionary:
	var id := _artwork_id(arguments)
	var target := str(arguments.get("target", "background"))
	var raw: Variant = arguments.get("time_ms")
	if not artwork.has(id) or target not in ["background", "mask"] or not _number(raw) or raw < 0 or raw > _duration:
		return {"error": "请选择曲绘编号、歌曲范围内的时间和 background 或 mask。"}
	var time := roundi(raw)
	var kind := 1 if target == "background" else 0
	var markers := _existing_bottoms if kind == 1 else _existing_covers
	var mask: Dictionary = mask_cues.get(time, {})
	if markers.has(time) or (not mask.is_empty() and (kind == 0 or not mask.bottom_path.is_empty())):
		return {"error": "该画面轨道在此时刻已有图片事件。"}
	var key := Vector2i(time, kind)
	if not artwork_cues.has(key) and artwork_cues.size() >= 32:
		return {"error": "草稿最多添加 32 个曲绘事件。"}
	artwork_cues[key] = {"type": kind, "time_ms": time, "image_path": artwork[id].path}
	return {"artwork_id": id, "target": target, "time_ms": time}

func _artwork_id(arguments: Dictionary) -> String:
	return str(arguments.get("artwork_id", "artwork_1"))

func create_solid_mask(arguments: Dictionary) -> Dictionary:
	var hex := str(arguments.get("color", "")).strip_edges().to_lower()
	var opacity: Variant = arguments.get("opacity", 1.0)
	if not hex.begins_with("#") or hex.length() != 7 or not Color.html_is_valid(hex):
		return {"error": "颜色须为 #RRGGBB，例如 #131b2a。"}
	if not _number(opacity) or opacity < 0.0 or opacity > 1.0:
		return {"error": "opacity 须在 0–1 内；0 完全透明，1 完全遮盖。"}
	var color := Color.html(hex)
	color.a = float(opacity)
	var id := color.to_html(true)
	if not masks.has(id):
		if masks.size() >= 12:
			return {"error": "一次制作最多创建 12 种纯色蒙版，请复用已生成的素材。"}
		masks[id] = color
	return {"mask_id": id, "color": hex, "opacity": opacity, "path": _mask_path(id)}

func set_mask_cue(arguments: Dictionary) -> Dictionary:
	var raw_time: Variant = arguments.get("time_ms")
	if not _number(raw_time) or raw_time < 0 or raw_time > _duration:
		return {"error": "蒙版切换时间须在歌曲范围内。"}
	var time := roundi(raw_time)
	var mask_id := str(arguments.get("mask_id", ""))
	if mask_id.is_empty():
		mask_cues.erase(time)
		return {"time_ms": time, "removed": true}
	if not masks.has(mask_id):
		return {"error": "请先调用 create_solid_mask，再使用它返回的 mask_id。"}
	var bottom := ""
	var artwork_id := ""
	if arguments.has("artwork_id") or arguments.get("use_cover_artwork", false) == true:
		artwork_id = _artwork_id(arguments)
		if not artwork.has(artwork_id):
			return {"error": "请使用本次已授权的 artwork_id。", "available": artwork.keys()}
		bottom = artwork[artwork_id].path
	if _existing_covers.has(time) or artwork_cues.has(Vector2i(time, 0)) or (not bottom.is_empty() and
			(_existing_bottoms.has(time) or artwork_cues.has(Vector2i(time, 1)))):
		return {"error": "该时刻已有背景事件，请择附近的音乐节点。"}
	if not mask_cues.has(time) and mask_cues.size() >= 32:
		return {"error": "一次制作最多加入 32 个蒙版切换事件。"}
	var cue := {"time_ms": time, "mask_id": mask_id, "image_path": _mask_path(mask_id), "bottom_path": bottom,
		"artwork_id": artwork_id}
	mask_cues[time] = cue
	return cue

func add_mask_reveal(arguments: Dictionary) -> Dictionary:
	var time: Variant = arguments.get("time_ms")
	var duration: Variant = arguments.get("duration_ms")
	var x: Variant = arguments.get("x", 960)
	var y: Variant = arguments.get("y", 540)
	var radius: Variant = arguments.get("radius_px", 770)
	for value: Variant in [time, duration, x, y, radius]:
		if not _number(value):
			return {"error": "揭示参数须为数字。请填写 time_ms 和 duration_ms。"}
	if time < 0 or duration < 700 or duration > 12000 or time + duration > _duration:
		return {"error": "揭示持续时间须为 700–12000 毫秒，且不能越过曲尾。"}
	if x < 0 or x > 1920 or y < 0 or y > 1080 or radius < 120 or radius > 1800:
		return {"error": "揭示中心须位于画面内，半径须为 120–1800 像素。"}
	var slot := _free_slot()
	if slot < 0:
		return {"error": "没有空闲的动画键槽位。"}
	var count := 0
	for layer: Dictionary in layers.values():
		if layer.source == "reveal":
			count += 1
	if count >= _reveal_limit:
		return {"error": "当前工程还能容纳 %d 个蒙版揭示，请先调整已有草稿。" % _reveal_limit}
	layers[slot] = {"slot": slot, "source": "reveal", "time_ms": roundi(time),
		"duration_ms": roundi(duration), "x": float(x), "y": float(y), "radius": float(radius)}
	return {"slot": slot, "time_ms": roundi(time), "duration_ms": roundi(duration)}

func unused_artwork_ids() -> Array:
	var unused := artwork.keys()
	for cue: Dictionary in mask_cues.values():
		unused.erase(cue.artwork_id)
	for cue: Dictionary in artwork_cues.values():
		unused.erase(_find_artwork_by_path(cue.image_path))
	for path: String in project_images.values():
		unused.erase(_find_artwork_by_path(path))
	for layer: Dictionary in layers.values():
		if layer.source == "cover":
			unused.erase(layer.artwork_id)
		elif layer.source == "reveal":
			unused.erase(_find_artwork_by_path(_background_path))
	return unused

func _find_artwork_by_path(path: String) -> String:
	for id: String in artwork:
		if artwork[id].path == path:
			return id
	return ""

func has_changes() -> bool:
	return not (layers.is_empty() and mask_cues.is_empty() and artwork_cues.is_empty() and project_images.is_empty() and imported_artwork.is_empty())

func has_visible_motion() -> bool:
	for layer: Dictionary in layers.values():
		if layer.source == "reveal":
			var peak := int(layer.time_ms) + roundi(layer.duration_ms * 0.45)
			if _reveal_has_mask(peak, Vector2(layer.x / 1920.0, layer.y / 1080.0)):
				return true
			continue
		var frames: Array = layer.frames
		for index in range(1, frames.size()):
			var from: Dictionary = frames[index - 1]
			var to: Dictionary = frames[index]
			if maxf(from.opacity, to.opacity) < 0.12:
				continue
			if (Vector2(from.x, from.y).distance_to(Vector2(to.x, to.y)) >= 12.0
					or absf(to.scale - from.scale) >= 0.015 or absf(to.rotation - from.rotation) >= 2.0):
				return true
	return false

func _reveal_has_mask(time: int, center: Vector2) -> bool:
	var path: String = project_images.get("mask", _mask_path_at_start)
	var latest := -1
	for start: int in _existing_covers:
		if start <= time and start >= latest:
			path = _existing_covers[start]
			latest = start
	for cue: Dictionary in artwork_cues.values():
		if cue.type == 0 and cue.time_ms <= time and cue.time_ms >= latest:
			path = cue.image_path
			latest = cue.time_ms
	for start: int in mask_cues:
		if start <= time and start >= latest:
			path = mask_cues[start].image_path
			latest = start
	if mask_cues.has(latest) and mask_cues[latest].image_path == path:
		return masks[mask_cues[latest].mask_id].a >= 0.18
	var image: Image
	if imported_artwork.has(path):
		image = Image.new()
		var error := image.load_png_from_buffer(imported_artwork[path]) if path.ends_with(".png") else image.load_jpg_from_buffer(imported_artwork[path])
		if error != OK:
			return false
	else:
		image = _chart.resolve_image(path)
	if image == null or image.is_empty():
		return false
	var position := Vector2i((Vector2(image.get_size()) - Vector2.ONE) * center.clamp(Vector2.ZERO, Vector2.ONE))
	return image.get_pixelv(position).a >= 0.18

func has_assets() -> bool:
	return not (masks.is_empty() and shapes.assets.is_empty() and imported_artwork.is_empty())

func save_assets(root: String) -> Error:
	var referenced := imported_artwork.duplicate()
	for cue: Dictionary in mask_cues.values():
		referenced[_mask_path(cue.mask_id)] = _mask_image(cue.mask_id).save_png_to_buffer()
	for layer: Dictionary in layers.values():
		if layer.source == "mask":
			referenced[layer.image_path] = _mask_image(layer.mask_id).save_png_to_buffer()
		elif layer.source == "shape":
			referenced[layer.image_path] = shapes.assets[layer.shape_id].bytes
	if referenced.is_empty():
		return OK
	if root.is_empty():
		return ERR_DOES_NOT_EXIST
	var dir_error := DirAccess.make_dir_recursive_absolute(root.path_join("otherImage"))
	if dir_error != OK:
		return dir_error
	var created: Array[String] = []
	for relative: String in referenced:
		var path := root.path_join(relative)
		var bytes: PackedByteArray = referenced[relative]
		var error := OK
		if FileAccess.file_exists(path):
			var existing := FileAccess.open(path, FileAccess.READ)
			error = OK if existing and existing.get_length() == bytes.size() and existing.get_buffer(bytes.size()) == bytes else ERR_ALREADY_IN_USE
		else:
			created.append(path)
			var output := FileAccess.open(path, FileAccess.WRITE)
			error = FileAccess.get_open_error() if output == null else OK
			if output:
				output.store_buffer(bytes)
				output.flush()
				error = output.get_error()
				output.close()
		if error != OK:
			for written: String in created:
				DirAccess.remove_absolute(written)
			return error
	return OK

func preview_images() -> Dictionary:
	var images := {}
	for id: String in masks:
		images[_mask_path(id)] = _mask_image(id)
	var needed := project_images.values() + artwork_cues.values().map(func(cue: Dictionary): return cue.image_path)
	for cue: Dictionary in mask_cues.values():
		needed.append(cue.bottom_path)
	for layer: Dictionary in layers.values():
		var path: String = layer.get("image_path", "")
		if layer.source == "shape":
			var shape := Image.new()
			if shape.load_png_from_buffer(shapes.assets[layer.shape_id].bytes) == OK:
				images[path] = shape
		elif layer.source == "cover":
			needed.append(path)
	for path: String in needed:
		if not imported_artwork.has(path) or images.has(path):
			continue
		var image := Image.new()
		var error := image.load_png_from_buffer(imported_artwork[path]) if path.ends_with(".png") else image.load_jpg_from_buffer(imported_artwork[path])
		if error == OK:
			var size := Vector2(image.get_size())
			var shrink := minf(1.0, 640.0 / maxf(size.x, size.y))
			if shrink < 1.0:
				image.resize(maxi(1, roundi(size.x * shrink)), maxi(1, roundi(size.y * shrink)), Image.INTERPOLATE_LANCZOS)
			images[path] = image
	return images

func _mask_image(id: String) -> Image:
	var image := Image.create_empty(32, 18, false, Image.FORMAT_RGBA8)
	image.fill(masks[id])
	return image

func _free_slot() -> int:
	for index in range(35):
		if not _used.has(index) and not layers.has(index):
			return index
	return -1

static func _mask_path(id: String) -> String:
	return "otherImage/agent-mask-%s.png" % id

func add_layer(arguments: Dictionary) -> Dictionary:
	return _write_layer(arguments)

func update_layer(arguments: Dictionary) -> Dictionary:
	var slot: Variant = arguments.get("slot")
	if not _number(slot) or slot != int(slot) or not layers.has(int(slot)) or layers[int(slot)].source == "reveal":
		return {"error": "请选择本次制作的图像动画层。"}
	var previous: Dictionary = layers[int(slot)]
	var source: String = previous.source
	var tint := "blue"
	if source == "color":
		tint = str(PALETTE.find_key(previous.tint))
	return _write_layer({"source": source, "mask_id": previous.mask_id, "shape_id": previous.get("shape_id", ""), "color": tint, "artwork_id": previous.artwork_id,
		"width": previous.size.x, "height": previous.size.y, "keyframes": arguments.get("keyframes")}, int(slot))

func _write_layer(arguments: Dictionary, replacement := -1) -> Dictionary:
	var source: String = str(arguments.get("source", "color"))
	var tint: String = str(arguments.get("color", "blue"))
	var mask_id := str(arguments.get("mask_id", ""))
	var shape_id := str(arguments.get("shape_id", ""))
	if source not in ["cover", "color", "mask", "shape"] or not PALETTE.has(tint):
		return {"error": "图层可使用 color、mask、shape 或已授权的 cover。"}
	if source == "mask" and not masks.has(mask_id):
		return {"error": "请先创建纯色蒙版，再填写有效的 mask_id。"}
	if source == "shape" and not shapes.assets.has(shape_id):
		return {"error": "请先用 create_shape_asset 绘图，再填写有效的 shape_id。"}
	var artwork_id := _artwork_id(arguments) if source == "cover" else ""
	if source == "cover":
		if not artwork.has(artwork_id):
			return {"error": "请使用本次已授权的 artwork_id。", "available": artwork.keys()}
		if layers.values().any(func(layer: Dictionary): return layer.get("artwork_id") == artwork_id and layer.slot != replacement):
			return {"error": "此曲绘已在动画层中，可更新原图层的关键帧。"}
	var input: Variant = arguments.get("keyframes")
	var visual_count := layers.values().filter(func(layer: Dictionary): return layer.source != "reveal").size()
	if not input is Array or input.size() < 2 or input.size() > 24 or (replacement < 0 and visual_count >= 6):
		return {"error": "每层需要 2–24 个关键帧，一次制谱最多添加 6 层图像动画。"}
	var slot := replacement if replacement >= 0 else _free_slot()
	if slot < 0:
		return {"error": "没有空闲的动画键槽位。"}
	var frames: Array[Dictionary] = []
	var state := {"time_ms": 0, "x": 960.0, "y": 540.0, "scale": 1.0, "rotation": 0.0,
		"opacity": 0.50 if source == "cover" else 0.0}
	var animated := false
	var visible := false
	for keyframe: Variant in input:
		if not keyframe is Dictionary or not _number(keyframe.get("time_ms")):
			return {"error": "每个关键帧都需要 time_ms。"}
		var time := roundi(keyframe.time_ms)
		if (frames.is_empty() and time != 0) or (not frames.is_empty() and time - int(state.time_ms) < 240) or time > _duration:
			return {"error": "首帧须为 0 毫秒。后续帧至少间隔 240 毫秒，并且不能越过曲尾。"}
		state = state.duplicate()
		state.time_ms = time
		var easing := str(keyframe.get("easing", "smooth"))
		if easing not in EASINGS:
			return {"error": "缓动可选 smooth、out 或 linear。"}
		state["easing"] = easing
		for field: String in FIELDS:
			if keyframe.has(field):
				var value: Variant = keyframe[field]
				var bounds: Array = FIELDS[field]
				if not _number(value) or value < bounds[0] or value > bounds[1]:
					return {"error": "%s 范围为 %s 至 %s。" % [field, bounds[0], bounds[1]]}
				state[field] = float(value)
		if source == "color" and state.opacity > 0.38:
			return {"error": "色带透明度最多为 0.38。请让曲绘和音符保持清楚。"}
		if source == "mask" and state.opacity > 0.55:
			return {"error": "装饰性蒙版图层透明度最多为 0.55；整屏遮盖请使用 set_mask_cue。"}
		if not frames.is_empty():
			var reason := _transition_error(frames[-1], state, source == "cover")
			if not reason.is_empty():
				return {"error": reason}
			animated = animated or FIELDS.keys().any(func(field: String): return state[field] != frames[-1][field])
		visible = visible or state.opacity > 0.0
		frames.append(state)
	if not animated or not visible:
		return {"error": "动画至少需要一处可见的参数变化。"}
	var size := Vector2(540, 84)
	var image_path := ""
	if source == "cover":
		var selected: Dictionary = artwork[artwork_id]
		var original: Vector2 = selected.size
		size = original * minf(1728.0 / original.x, 972.0 / original.y)
		image_path = selected.path
	elif source == "mask":
		var width: Variant = arguments.get("width", 540.0)
		var height: Variant = arguments.get("height", 120.0)
		if not _number(width) or not _number(height) or width < 8 or width > 1920 or height < 8 or height > 1080:
			return {"error": "蒙版图层宽度须为 8–1920，高度须为 8–1080。"}
		size = Vector2(width, height)
		image_path = _mask_path(mask_id)
	elif source == "shape":
		var asset := shapes.info(shape_id)
		var longest: Variant = arguments.get("width", asset.width)
		var maximum := minf(1920.0, 1080.0 * asset.width / asset.height)
		if not _number(longest) or longest < 8 or longest > maximum:
			return {"error": "图形宽度须至少为 8 像素，按比例缩放后的尺寸须在 1920×1080 内。"}
		size = Vector2(longest, float(longest) * asset.height / asset.width)
		image_path = asset.path
	layers[slot] = {"slot": slot, "source": source, "size": size, "frames": frames,
		"tint": PALETTE[tint] if source == "color" else Color.WHITE, "image_path": image_path, "mask_id": mask_id,
		"artwork_id": artwork_id, "shape_id": shape_id}
	return {"slot": slot, "keyframes": frames.size()}

func check_cover_contrast(arguments: Dictionary) -> Dictionary:
	if artwork.is_empty():
		return {"analysis_available": false, "reason": "未提供曲绘。"}
	var requested: Variant = arguments.get("times_ms", [0])
	if not requested is Array or requested.is_empty() or requested.size() > 12:
		return {"error": "请提供 1–12 个取样时间。"}
	var bottoms := _existing_bottoms.duplicate()
	for cue: Dictionary in artwork_cues.values():
		if cue.type == 1:
			bottoms[cue.time_ms] = cue.image_path
	for cue: Dictionary in mask_cues.values():
		if not cue.bottom_path.is_empty():
			bottoms[cue.time_ms] = cue.bottom_path
	var bottom_times := bottoms.keys()
	bottom_times.sort()
	var times := mask_cues.keys()
	times.sort()
	var rows := []
	for value: Variant in requested:
		if not _number(value) or value < 0 or value > _duration:
			return {"error": "取样时间必须在歌曲范围内。"}
		var time := roundi(value)
		var bottom_index := bottom_times.bsearch(time, false) - 1
		var path: String = bottoms[bottom_times[bottom_index]] if bottom_index >= 0 else project_images.get("background", _background_path)
		var id := _find_artwork_by_path(path)
		if id.is_empty() and bottom_index < 0 and artwork.size() == 1:
			id = "artwork_1"
		var brightness := float(artwork.get(id, {}).get("visibility", {}).get("average_luminance", 0.0))
		var latest := times.bsearch(time, false) - 1
		var color := Color.TRANSPARENT
		if latest >= 0:
			var cue: Dictionary = mask_cues[times[latest]]
			color = masks.get(cue.mask_id, Color.TRANSPARENT)
		var composited := lerpf(brightness, color.get_luminance(), color.a)
		var reveal := layers.values().any(func(layer: Dictionary):
			return layer.source == "reveal" and time >= layer.time_ms and time < layer.time_ms + layer.duration_ms)
		var foreground := layers.values().any(func(layer: Dictionary): return layer.source == "cover")
		rows.append({"time_ms": time, "artwork_id": id, "estimated_center_luminance": snappedf(composited, 0.01),
			"mask_opacity": snappedf(color.a, 0.01), "active_reveal": reveal, "foreground_cover_layer": foreground,
			"review_rendered_frame": reveal or foreground or composited > 0.45})
	return {"analysis_available": true, "source": "draft_mask_and_cover_luminance_estimate", "items": rows}

func remove_layer(arguments: Dictionary) -> Dictionary:
	var slot: Variant = arguments.get("slot")
	if not _number(slot) or slot != int(slot) or not layers.has(int(slot)):
		return {"error": "只能删除此次 Agent 制作的草稿动画层。"}
	layers.erase(int(slot))
	return {"removed": int(slot)}

static func _transition_error(from: Dictionary, to: Dictionary, is_cover: bool) -> String:
	var seconds := float(to.time_ms - from.time_ms) / 1000.0
	if seconds < 0.60 and absf(to.opacity - from.opacity) > 0.30:
		return "透明度大幅变化至少需要 600 毫秒。"
	if is_cover:
		var travel := Vector2(from.x, from.y).distance_to(Vector2(to.x, to.y))
		if travel > seconds * 260.0 or absf(to.rotation - from.rotation) > seconds * 20.0 or absf(to.scale - from.scale) > seconds * 0.35:
			return "曲绘过渡太快。请减小位移、缩放或旋转，或延长过渡。"
	return ""

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
