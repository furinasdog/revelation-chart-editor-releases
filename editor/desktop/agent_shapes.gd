extends RefCounted

const KINDS := ["rectangle", "square", "ellipse", "circle", "line"]
const MAX_ASSETS := 12
const MAX_PRIMITIVES := 16
const MAX_SIDE := 1024
var assets := {}

func create(arguments: Dictionary) -> Dictionary:
	var width: Variant = arguments.get("width", 512)
	var height: Variant = arguments.get("height", 512)
	if not _bounded(width, 8, MAX_SIDE) or not _bounded(height, 8, MAX_SIDE):
		return {"error": "画布宽高须为 8–1024 像素。"}
	var primitives: Variant = arguments.get("shapes")
	if not primitives is Array or primitives.is_empty() or primitives.size() > MAX_PRIMITIVES:
		return {"error": "每张图需提供 1–16 个图形。"}
	var dimensions := Vector2i(roundi(width), roundi(height))
	var elements := PackedStringArray()
	for shape: Variant in primitives:
		var element := _element(shape, dimensions)
		if element.is_empty():
			return {"error": "图形参数无效。请使用 0–1 的归一化坐标、有效尺寸和 #RRGGBB 或 #RRGGBBAA 颜色。"}
		elements.append(element)
	var definition := "%d:%d:%s" % [dimensions.x, dimensions.y, "".join(elements)]
	var id := "shape_" + definition.sha256_text().left(24)
	if not assets.has(id):
		if assets.size() >= MAX_ASSETS:
			return {"error": "草稿最多保留 12 个不同的图形素材。"}
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">%s</svg>' % [
			dimensions.x, dimensions.y, "".join(elements)]
		var image := Image.new()
		if image.load_svg_from_string(svg) != OK:
			return {"error": "无法绘制图形。"}
		var bytes := image.save_png_to_buffer()
		if bytes.is_empty():
			return {"error": "无法编码图形素材。"}
		assets[id] = {"shape_id": id, "path": "otherImage/agent-%s.png" % id,
			"width": dimensions.x, "height": dimensions.y, "shape_count": primitives.size(), "bytes": bytes}
	return info(id)

func info(id: String) -> Dictionary:
	var result: Dictionary = assets.get(id, {}).duplicate()
	result.erase("bytes")
	return result

func list_assets() -> Dictionary:
	return {"items": assets.keys().map(func(id: String): return info(id))}

func preview(id: String) -> Dictionary:
	var result := info(id)
	if result.is_empty():
		return {"error": "找不到草稿图形编号。"}
	var png: PackedByteArray = assets[id].bytes
	if png.size() > 68000:
		var image := Image.new()
		if image.load_png_from_buffer(png) != OK:
			return {"error": "无法读取草稿图形。"}
		while png.size() > 68000:
			image.resize(maxi(1, roundi(image.get_width() * 0.7)), maxi(1, roundi(image.get_height() * 0.7)), Image.INTERPOLATE_LANCZOS)
			png = image.save_png_to_buffer()
	if png.is_empty():
		return {"error": "无法生成图形预览。"}
	result["_preview_image"] = "data:image/png;base64," + Marshalls.raw_to_base64(png)
	return result

static func _element(shape: Variant, canvas: Vector2i) -> String:
	if not shape is Dictionary or not shape.get("kind") in KINDS:
		return ""
	var kind: String = shape.kind
	var x: Variant = shape.get("x", 0.5)
	var y: Variant = shape.get("y", 0.5)
	var width: Variant = shape.get("width", 0.7)
	var height: Variant = shape.get("height", 0.7)
	var stroke_width: Variant = shape.get("stroke_width", 0.018)
	var stroke := _paint(shape.get("stroke", "#FFFFFF"))
	var fill := _paint(shape.get("fill", "none"))
	if not _bounded(x, 0, 1) or not _bounded(y, 0, 1) or not _bounded(stroke_width, 0.001, 0.25) or stroke.is_empty() or fill.is_empty() or (stroke[0] == "none" and fill[0] == "none"):
		return ""
	var unit := mini(canvas.x, canvas.y)
	var style := 'fill="%s" fill-opacity="%s" stroke="%s" stroke-opacity="%s" stroke-width="%.5f" stroke-linecap="round" stroke-linejoin="round"' % [
		fill[0], fill[1], stroke[0], stroke[1], stroke_width * unit]
	if kind == "line":
		var end_x: Variant = shape.get("end_x")
		var end_y: Variant = shape.get("end_y")
		if not _bounded(end_x, 0, 1) or not _bounded(end_y, 0, 1) or (x == end_x and y == end_y) or stroke[0] == "none":
			return ""
		return '<line x1="%.5f" y1="%.5f" x2="%.5f" y2="%.5f" %s/>' % [x * canvas.x, y * canvas.y, end_x * canvas.x, end_y * canvas.y, style]
	var uniform := kind in ["square", "circle"]
	if not _bounded(width, 0.005, 1) or (not uniform and not _bounded(height, 0.005, 1)):
		return ""
	x *= canvas.x
	y *= canvas.y
	height = width * unit if uniform else height * canvas.y
	width *= unit if uniform else canvas.x
	if kind in ["ellipse", "circle"]:
		return '<ellipse cx="%.5f" cy="%.5f" rx="%.5f" ry="%.5f" %s/>' % [x, y, width * 0.5, height * 0.5, style]
	return '<rect x="%.5f" y="%.5f" width="%.5f" height="%.5f" %s/>' % [
		x - width * 0.5, y - height * 0.5, width, height, style]

static func _paint(value: Variant) -> PackedStringArray:
	if value == "none":
		return PackedStringArray(["none", "1"])
	if not value is String or not value.begins_with("#") or value.length() not in [7, 9] or not Color.html_is_valid(value):
		return PackedStringArray()
	return PackedStringArray([value.left(7).to_lower(), "%.4f" % Color.html(value).a])

static func _bounded(value: Variant, lower: float, upper: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and value >= lower and value <= upper
