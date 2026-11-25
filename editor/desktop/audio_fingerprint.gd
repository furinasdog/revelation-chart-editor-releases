extends RefCounted

var _path := ""
var _stamp := 0
var _size := -1
var _hash := ""

func read(path: String, refresh := false) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	var size := file.get_length()
	file.close()
	var stamp := FileAccess.get_modified_time(path)
	if refresh or path != _path or stamp != _stamp or size != _size:
		_path = path
		_stamp = stamp
		_size = size
		_hash = FileAccess.get_sha256(path)
	return _hash
