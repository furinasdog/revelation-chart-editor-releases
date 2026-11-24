extends RefCounted

const ROOT := "user://mcp_connection"
const PRIVATE_ROOT := "user://mcp_private"
const ENDPOINT := PRIVATE_ROOT + "/connection.json"
const CODEX_START := "# BEGIN Revelation MCP"
const CODEX_END := "# END Revelation MCP"

static func has_workspace() -> bool:
	return FileAccess.file_exists(ROOT + "/.codex/config.toml") and FileAccess.file_exists(ROOT + "/.mcp.json")

static func write_endpoint(endpoint: String, token: String) -> bool:
	return DirAccess.make_dir_recursive_absolute(PRIVATE_ROOT) == OK and _write(ProjectSettings.globalize_path(ENDPOINT),
		JSON.stringify({"url": endpoint, "token": token}))

static func generate(endpoint: String, token: String) -> Dictionary:
	var app := OS.get_executable_path().get_base_dir()
	var python := app.path_join("tools/python/python.exe")
	var bridge := app.path_join("runtime/mcp_stdio.py")
	if OS.has_feature("editor"):
		var source := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
		python = OS.get_environment("REVELATION_PYTHON")
		bridge = source.path_join("runtime/mcp_stdio.py")
	return generate_with_runtime(endpoint, token, python, bridge)

static func generate_with_runtime(endpoint: String, token: String, python: String, bridge: String) -> Dictionary:
	if python.is_empty() or not FileAccess.file_exists(python) or not FileAccess.file_exists(bridge):
		return {"error": "找不到 MCP 客户端桥接程序。源码运行时可设置 REVELATION_PYTHON。"}
	var folder := ProjectSettings.globalize_path(ROOT)
	if DirAccess.make_dir_recursive_absolute(folder.path_join(".codex")) != OK:
		return {"error": "无法创建本机 MCP 配置目录。"}
	var connection := ProjectSettings.globalize_path(ENDPOINT)
	var args := ["-I", "-B", bridge, connection]
	var claude := folder.path_join(".mcp.json")
	var codex := folder.path_join(".codex/config.toml")
	var codex_config := _codex_config(codex, python, args)
	var claude_config := _claude_config(claude, python, args)
	if codex_config.is_empty() or claude_config.is_empty():
		return {"error": "工作目录已有无法合并的 Revelation 配置。请检查 .codex/config.toml 或 .mcp.json。"}
	if not write_endpoint(endpoint, token) or not _write(codex, codex_config) or not _write(claude, claude_config):
		return {"error": "无法写入工作目录的 MCP 配置。"}
	var legacy := folder.path_join("connection.json")
	if FileAccess.file_exists(legacy):
		var old: Variant = JSON.parse_string(FileAccess.get_file_as_string(legacy))
		if old is Dictionary and old.get("token") == token and not _write(legacy, JSON.stringify({"config": connection})):
			return {"error": "已写入工作目录配置，但无法迁移旧版连接文件。"}
	return {"folder": folder}

static func _codex_config(path: String, python: String, args: Array) -> String:
	var existing := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var block := "%s\n[mcp_servers.revelation]\ncommand = %s\nargs = %s\ntool_timeout_sec = 240\n%s" % [
		CODEX_START, JSON.stringify(python), JSON.stringify(args), CODEX_END]
	var first := existing.find(CODEX_START)
	var last := existing.find(CODEX_END)
	if first >= 0 and last > first:
		return existing.left(first) + block + existing.substr(last + CODEX_END.length())
	if first >= 0 or last >= 0 or RegEx.create_from_string(r"(?m)^\s*(?:\[\s*mcp_servers\s*\.\s*[\x22\x27]?revelation\b|mcp_servers\s*=)").search(existing):
		return ""
	return (existing + "\n" if not existing.is_empty() else "") + block + "\n"

static func _claude_config(path: String, python: String, args: Array) -> String:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	if not data is Dictionary or not data.get("mcpServers", {}) is Dictionary:
		return ""
	var servers: Dictionary = data.get("mcpServers", {})
	if servers.has("revelation"):
		var previous: Variant = servers.revelation
		if not previous is Dictionary or not previous.get("args") is Array or previous.args.size() != 4 or previous.args[-1] != args[-1]:
			return ""
	servers["revelation"] = {"type": "stdio", "command": python, "args": args}
	data["mcpServers"] = servers
	return JSON.stringify(data, "  ") + "\n"

static func _write(path: String, content: String) -> bool:
	var temporary := "%s.%d-%d.tmp" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if not file:
		return false
	var written := file.store_string(content)
	file.close()
	if written and DirAccess.rename_absolute(temporary, path) == OK:
		return true
	DirAccess.remove_absolute(temporary)
	return false
