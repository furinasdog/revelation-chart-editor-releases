extends RefCounted

const Prompts := preload("res://desktop/agent_prompts.gd")
const PROMPT_NAME := "revelation-charting"

static func quick() -> String:
	return Prompts.join([
		Prompts.section("mcp", "tool-priority"),
		Prompts.section("shared", "workflow"),
		Prompts.section("shared", "charting"),
		Prompts.section("shared", "spacing"),
		masks(),
		Prompts.section("shared", "audio"),
		Prompts.section("mcp", "connection"),
	], "\n")

static func full() -> String:
	return Prompts.join([
		Prompts.section("mcp", "tool-priority"),
		Prompts.section("shared", "workflow"),
		rpy(),
		Prompts.section("shared", "charting"),
		Prompts.section("shared", "spacing"),
		masks(),
		Prompts.section("shared", "audio"),
	])

static func editor() -> String:
	return Prompts.join([
		Prompts.section("copilot", "direct-tools"),
		Prompts.section("shared", "workflow"),
		Prompts.section("shared", "charting"),
		Prompts.section("shared", "spacing"),
		Prompts.section("shared", "audio"),
	])

static func masks() -> String:
	return Prompts.section("shared", "masks")

static func rpy() -> String:
	return Prompts.section("mcp", "rpy")

static func prompt_list() -> Dictionary:
	return {"prompts": [{"name": PROMPT_NAME, "title": "Revelation 制谱与 .rpy",
		"description": "制谱工作流、脚本 API 示例、空间走位、长键路径、音频导入与草稿提交。"}]}

static func prompt_get() -> Dictionary:
	return {"description": "Revelation 制谱与 .rpy", "messages": [{"role": "user",
		"content": {"type": "text", "text": full()}}]}
