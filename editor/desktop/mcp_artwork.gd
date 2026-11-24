extends RefCounted

const MAX_UPLOAD_BYTES := 256 * 1024
const MAX_LOCAL_BYTES := 16 * 1024 * 1024
const MAX_PIXELS := 12 * 1024 * 1024
const Automatic := preload("res://desktop/automatic_chart.gd")
const Archive := preload("res://main/chart_archive.gd")

static func supported_extension(filename: String) -> bool:
	return filename.get_extension().to_lower() in ["png", "jpg", "jpeg"]

static func load_local(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file or file.get_length() > MAX_LOCAL_BYTES:
		return PackedByteArray()
	return file.get_buffer(file.get_length())

static func from_base64(encoded: Variant) -> PackedByteArray:
	if not encoded is String or encoded.length() > ceili(MAX_UPLOAD_BYTES / 3.0) * 4:
		return PackedByteArray()
	var bytes := Marshalls.base64_to_raw(encoded)
	return bytes if bytes.size() <= MAX_UPLOAD_BYTES else PackedByteArray()

static func prepare(chart: Node, filename: String, bytes: PackedByteArray) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_LOCAL_BYTES or not supported_extension(filename):
		return {}
	var ext := "png" if filename.get_extension().to_lower() == "png" else "jpg"
	var dimensions: Vector2i = chart._encoded_image_size(bytes, ext)
	if (dimensions.x <= 0 or dimensions.y <= 0 or dimensions.x > MAX_PIXELS or dimensions.y > MAX_PIXELS
			or dimensions.x * dimensions.y > MAX_PIXELS):
		return {}
	var image := Image.new()
	var status := image.load_png_from_buffer(bytes) if ext == "png" else image.load_jpg_from_buffer(bytes)
	if status != OK or image.get_size() != dimensions:
		return {}
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	var path := "otherImage/agent-art-%s.%s" % [hash.finish().hex_encode(), ext]
	var entry := Automatic.prepare_artwork_image(image, path)
	if not entry.is_empty():
		entry["filename"] = filename.get_file().left(160)
	return entry

static func local_image_path(path: String) -> bool:
	var normalized := path.replace("\\", "/")
	if (not normalized.is_absolute_path() or normalized.begins_with("//") or normalized.contains("://")
			or normalized.length() > 1024 or not supported_extension(normalized) or not Archive.relative_name(normalized.get_file())):
		return false
	for index in range(normalized.length()):
		if normalized.unicode_at(index) < 32:
			return false
	if OS.get_name() == "Windows":
		if normalized.length() < 4 or normalized.substr(1, 2) != ":/" or ":" in normalized.substr(3):
			return false
	return true
