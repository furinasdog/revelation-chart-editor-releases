extends RefCounted

const MAX_INPUT := 8 * 1024 * 1024
const MAX_OUTPUT := 131072

static func run(host: Node, payload: Dictionary, live: Callable) -> Dictionary:
	var app_dir := OS.get_executable_path().get_base_dir()
	var python := app_dir.path_join("tools/python/python.exe")
	var worker := app_dir.path_join("runtime/worker.py")
	if OS.has_feature("editor"):
		worker = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("runtime/worker.py")
		python = OS.get_environment("REVELATION_PYTHON")
	if python.is_empty() or not FileAccess.file_exists(worker) or not FileAccess.file_exists(python):
		return {"error": "找不到随包 CPython，源码运行时可设置 REVELATION_PYTHON 指向解释器。"}
	var request := JSON.stringify(payload).to_utf8_buffer()
	if request.size() > MAX_INPUT:
		return {"error": "脚本工程快照超过 8 MiB，请缩小范围。"}
	var jobs := ProjectSettings.globalize_path("user://script_jobs")
	if DirAccess.make_dir_recursive_absolute(jobs) != OK:
		return {"error": "无法创建脚本任务目录。"}
	var task := "script-%s" % Crypto.new().generate_random_bytes(12).hex_encode()
	var input := jobs.path_join(task + ".in.json")
	var output := jobs.path_join(task + ".out.json")
	var file := FileAccess.open(input, FileAccess.WRITE)
	if not file or not file.store_buffer(request):
		if file:
			file.close()
		DirAccess.remove_absolute(input)
		return {"error": "无法创建脚本任务文件。"}
	file.close()
	var pid := OS.create_process(python, PackedStringArray(["-I", "-B", worker, input, output]), false)
	var trusted: bool = payload.mode == "trusted"
	var deadline := Time.get_ticks_msec() + (120000 if trusted else 8000)
	while pid > 0 and OS.is_process_running(pid) and live.call() and Time.get_ticks_msec() < deadline:
		await host.get_tree().process_frame
	var result := {"error": "脚本执行失败。"}
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
		result = {"error": "脚本已取消或超过执行时限。"}
	elif pid > 0 and OS.get_process_exit_code(pid) == 0 and FileAccess.file_exists(output):
		file = FileAccess.open(output, FileAccess.READ)
		if file and file.get_length() <= MAX_OUTPUT:
			var value: Variant = JSON.parse_string(file.get_as_text())
			if value is Dictionary:
				result = value
		if file:
			file.close()
	DirAccess.remove_absolute(input)
	DirAccess.remove_absolute(output)
	return result
