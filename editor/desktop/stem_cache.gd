extends RefCounted

const DIRECTORY := "user://stem-cache/v1"
const STEMS := ["vocals", "drums", "bass", "other"]

# This directory is published by rename only after all four PCM files have been checked.
static func directory(audio_hash: String, model_hash: String) -> String:
	var key := (audio_hash + ":" + model_hash).sha256_text()
	return ProjectSettings.globalize_path(DIRECTORY.path_join(key))

static func complete(folder: String) -> bool:
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):
		return false
	var expected := 0
	for stem: String in STEMS:
		var count := _frames(folder.path_join(stem + ".wav"))
		if count <= 0 or (expected > 0 and count != expected):
			return false
		expected = count
	return true

static func _frames(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var file := FileAccess.open(path, FileAccess.READ)
	if not file or file.get_length() < 44 or file.get_buffer(4).get_string_from_ascii() != "RIFF":
		return 0
	var length := file.get_length()
	if file.get_32() + 8 != length or file.get_buffer(4).get_string_from_ascii() != "WAVE":
		return 0
	var stereo_pcm := false
	var frames := 0
	while file.get_position() + 8 <= length:
		var chunk := file.get_buffer(4).get_string_from_ascii()
		var size := file.get_32()
		var next := file.get_position() + size + (size % 2)
		if next > length:
			return 0
		if chunk == "fmt " and size >= 16:
			stereo_pcm = file.get_16() == 1 and file.get_16() == 2 and file.get_32() == 44100
			file.get_32()
			stereo_pcm = stereo_pcm and file.get_16() == 4 and file.get_16() == 16
		elif chunk == "data" and size % 4 == 0:
			frames = size >> 2
		file.seek(next)
	return frames if stereo_pcm else 0

static func publish(output: String, destination: String) -> bool:
	if not complete(output):
		return false
	if complete(destination):
		return true
	# A damaged cache may be left behind after manual cleanup or disk errors.
	if DirAccess.dir_exists_absolute(destination):
		var quarantine := output.get_base_dir().path_join("replaced")
		if DirAccess.rename_absolute(destination, quarantine) != OK:
			return complete(destination)
	return DirAccess.rename_absolute(output, destination) == OK or complete(destination)

static func remove_work_directory(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if not dir:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	for child: String in dir.get_directories():
		if dir.is_link(child):
			dir.remove(child)
		else:
			remove_work_directory(folder.path_join(child))
	DirAccess.remove_absolute(folder)
