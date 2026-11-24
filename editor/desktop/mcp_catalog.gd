extends RefCounted

const Agent := preload("res://desktop/chart_agent.gd")
const Guidance := preload("res://desktop/editor_guidance.gd")
const Automatic := preload("res://desktop/automatic_chart.gd")
const Context := preload("res://desktop/agent_context.gd")
const Shapes := preload("res://desktop/agent_shapes.gd")
const RANGE := ["from_ms", "to_ms", "offset", "limit"]
const POSITIONS := ["x", "y", "end_x", "end_y", "mid_x", "mid_y", "approach_x", "approach_y"]
const FIGURES := ["waveform", "spectrum"]
const IMAGE_TOOLS := ["get_cover", "check_cover_contrast", "view_rendered_frames", "view_audio_figure", "view_shape_asset", "view_reference_artwork", "view_reference_frame"]
const MCP_TITLES := {"get_audio_path": "读取音频文件路径", "list_project_artwork": "列出工程图片", "add_artwork": "添加曲绘"}
const DESCRIPTIONS := {
	"get_bpm": "Read detected tempo in chart milliseconds and the tempo set in the editor.",
	"get_beats": "Read measured beat, downbeat, onset or accent timestamps.",
	"get_melody": "Read detected lead-melody pitch samples.",
	"estimate_mood": "Read an acoustic intensity estimate per section. Use get_emotions for model predictions.",
	"list_notes": "Read draft notes and their IDs. Times are judgement times in chart milliseconds. Lanes are zero-based.",
	"add_notes": "Add notes to the draft on a 1920×1080 canvas. time_ms is judgement time. duration_ms is for holds; approach_x/y set a slide's entrance.",
	"move_notes": "Move notes in time or to a different lane without changing their visual positions.",
	"set_positions": "Change note coordinates. end_x/y apply to holds and approach_x/y to slides.",
	"resize_holds": "Change hold duration after judgement without changing judgement time.",
	"delete_notes": "Remove the specified note IDs from the draft.",
	"seed_pattern": "Write a phrase-based chart draft from available detected beats using the project's difficulty. to_ms=-1 extends through the song.",
	"check_conflicts": "Report blocking overlaps, chord sizes, travel and hold timing, plus advisory warnings and named slide-direction counts. Use this to diagnose chart errors.",
	"get_animation_cues": "Read phrase anchors and coarse loudness to plan animation transitions.",
	"list_animation_layers": "Read existing slots, draft layers, masks and scheduled cues.",
	"get_cover": "Read the authorized artwork catalog and view one image by artwork_id.",
	"create_solid_mask": "Create a solid-color draft mask. Returns a mask ID to use in set_mask_cue or add_animation_layer.",
	"set_mask_cue": "Schedule a generated mask and optionally select the artwork below it. Use an empty mask_id to remove this draft cue.",
	"add_mask_reveal": "Add a feathered circular reveal centered on the given coordinates while a mask is active.",
	"add_animation_layer": "Create a draft image or color layer. Keyframes inherit omitted fields. Start at 0 and space keyframes at least 240 ms apart.",
	"remove_animation_layer": "Remove a layer created in this draft.",
	"view_rendered_frames": "Render 1 to 6 draft preview frames as a montage, ordered left to right and top to bottom.",
	"get_editor_help": "Search the editor's menus and usage instructions by a Chinese keyword. Use check_conflicts for note-validation errors and get_editing_guide for editing tools.",
	"reply": "Return a text reply through the tool result. Leaves all drafts untouched.",
	"finish": "Validate and request approval in the editor to apply this draft. Keep the editor open while waiting.",
	"get_audio_path": "Get the current project audio filename and, when enabled in MCP settings, its absolute local path. Use get_audio_info for duration and offset.",
	"list_project_artwork": "Page through the artwork filenames and relative paths in the open project. Use add_artwork with a returned project_path to register it in the draft.",
	"add_artwork": "Stage a PNG or JPEG in the draft. Choose exactly one source: project_path from list_project_artwork; path for a local absolute file after editor approval; or data_base64 and filename for an upload of at most 256 KiB. Use the returned artwork_id to set the background, a cue or an animation layer. Use finish to save the import.",
}

static func tools() -> Array:
	var entries := DESCRIPTIONS.duplicate()
	for name: String in Context.TOOLS:
		entries[name] = Context.TOOLS[name][2]
	entries["run_rpy"] += " " + Guidance.RPY
	var result := []
	for name: String in entries:
		var writes: bool = name in Agent.WRITES or name in ["finish", "add_artwork", "run_rpy", "import_audio"]
		var title: String = Automatic.ACTION_LABELS.get(name, Context.TOOLS.get(name, [MCP_TITLES.get(name, name)])[0])
		result.append({"name": name, "title": title,
			"description": entries[name] + (" This changes only the draft until finish is approved." if name in Agent.WRITES else ""),
			"inputSchema": _schema(name), "annotations": {"readOnlyHint": not writes, "destructiveHint": name in ["delete_notes", "remove_animation_layer", "delete_text_event", "set_tempo_map", "finish"],
				"openWorldHint": name == "analyze_audio"}})
	return result

static func _schema(name: String) -> Dictionary:
	match name:
		"locate_notes":
			return _object(["seconds", "ruler_beat", "radius_ms", "offset", "limit"])
		"import_audio":
			return _object([], {"path": _type("string")}, ["path"])
		"scale_hold_paths":
			return _object(["from_ms", "to_ms", "factor"], {"ids": _array(_type("integer"), 128)}, ["factor"])
		"list_reference_charts":
			return _object(["offset", "limit"], {"query": _type("string"), "difficulty": _type("string")})
		"query_reference_chart":
			return _object(RANGE, {"id": _type("string"), "section": _choice(["summary", "notes", "paths", "events", "masks", "keyframes"])}, ["id"])
		"get_reference_media":
			return _object(["offset", "limit"], {"id": _type("string"), "category": _choice(["images", "audio"])}, ["id", "category"])
		"view_reference_artwork":
			return _object([], {"id": _type("string"), "filename": _type("string")}, ["id", "filename"])
		"view_reference_frame":
			return _object(["time_ms"], {"id": _type("string")}, ["id", "time_ms"])
		"run_rpy":
			var reference := _object(RANGE, {"key": _type("string"), "id": _type("string"),
				"section": _choice(["summary", "notes", "paths", "events", "masks", "keyframes"])}, ["key", "id"])
			return _object(["from_ms", "to_ms"], {"source": _type("string"), "references": _array(reference, 4)}, ["source"])
		"get_pitch":
			return _object(RANGE, {"source": _choice(["essentia", "rmvpe"]), "detail": _choice(["phrases", "detail"])})
		"get_bpm", "get_reference_grid", "get_melody", "get_emotions", "estimate_mood", "list_notes", "list_note_paths", "list_chart_events", "get_animation_cues", "list_text_events":
			return _object(RANGE)
		"list_project_artwork":
			return _object(["offset", "limit"])
		"add_artwork":
			var result := _object([], {"project_path": _type("string"), "path": _type("string"), "filename": _type("string"), "data_base64": _type("string")})
			result["oneOf"] = [{"required": ["project_path"]}, {"required": ["path"]}, {"required": ["filename", "data_base64"]}]
			return result
		"set_project_artwork", "set_artwork_cue":
			var fields := {"artwork_id": _type("string"), "target": _choice(["background", "mask"])}
			if name == "set_artwork_cue":
				return _object(["time_ms"], fields, ["artwork_id", "time_ms"])
			return _object([], fields, ["artwork_id"])
		"set_chart_metadata":
			var fields := {}
			for key: String in Agent.ChartEdits.METADATA_LIMITS:
				fields[key] = {"type": "string", "maxLength": Agent.ChartEdits.METADATA_LIMITS[key]}
			return _object([], {"fields": _object([], fields)}, ["fields"])
		"set_tempo_map":
			return _object(["total_beats"], {"segments": _array(_object(["start_beat", "bpm"], {}, ["start_beat", "bpm"]), 128)}, ["segments"])
		"upsert_text_event":
			return _object(["id", "from_ms", "to_ms", "x", "y", "size", "fade_in_ms", "fade_out_ms"],
				{"text": _type("string"), "color": _type("string")})
		"delete_text_event":
			return _object(["id"], {}, ["id"])
		"create_shape_asset":
			var shape := _object(["x", "y", "width", "height", "end_x", "end_y", "stroke_width"],
				{"kind": _choice(Shapes.KINDS), "fill": _type("string"), "stroke": _type("string")}, ["kind"])
			return _object(["width", "height"], {"shapes": _array(shape, Shapes.MAX_PRIMITIVES)}, ["shapes"])
		"view_shape_asset":
			return _object([], {"shape_id": _type("string")}, ["shape_id"])
		"get_beats":
			return _object(RANGE, {"kind": _choice(["beats", "downbeats", "onsets", "accents"])})
		"get_audio_loudness", "get_audio_features", "get_chart_statistics":
			return _object(RANGE + ["window_ms"])
		"get_sustain_candidates":
			return _object(RANGE + ["minimum_ms"])
		"view_audio_figure":
			return _object(["from_ms", "to_ms"], {"kind": _choice(FIGURES)})
		"analyze_audio":
			return _object(RANGE, {"engine": _choice(["native", "essentia", "music2emo", "rmvpe"]),
				"tasks": _array(_choice(["beats", "downbeats", "tempo", "onsets", "accents", "melody", "emotions", "vocal_pitch"]), 6),
				"use_for_draft": _type("boolean")}, ["tasks"])
		"add_notes":
			return _notes(["time_ms", "lane", "duration_ms", "lead_ms"] + POSITIONS,
				["type", "time_ms", "lane", "x", "y"], {"type": _choice(["note", "drag", "hold"])})
		"move_notes":
			return _notes(["id", "time_ms", "lane"], ["id"])
		"set_positions":
			return _notes(["id"] + POSITIONS, ["id"])
		"resize_holds":
			return _notes(["id", "duration_ms"], ["id", "duration_ms"])
		"set_note_lead_in":
			return _notes(["id", "lead_ms"], ["id", "lead_ms"])
		"set_hold_path":
			return _notes(["id", "mid_x", "mid_y", "end_x", "end_y"], ["id", "end_x", "end_y"])
		"delete_notes":
			return _object([], {"ids": _array(_type("integer"), 128)}, ["ids"])
		"seed_pattern":
			return _object(["seed", "from_ms", "to_ms"])
		"get_cover":
			return _object([], {"artwork_id": _type("string")})
		"create_solid_mask":
			return _object(["opacity"], {"color": {"type": "string", "pattern": "^#[0-9a-fA-F]{6}$"}}, ["color"])
		"set_mask_cue":
			return _object(["time_ms"], {"mask_id": _type("string"), "artwork_id": _type("string"),
				"use_cover_artwork": _type("boolean")}, ["time_ms", "mask_id"])
		"add_mask_reveal":
			return _object(["time_ms", "duration_ms", "x", "y", "radius_px"], {}, ["time_ms", "duration_ms"])
		"view_rendered_frames", "check_cover_contrast":
			return _object([], {"times_ms": _array(_type("integer"), 6)}, ["times_ms"] if name == "view_rendered_frames" else [])
		"add_animation_layer", "update_animation_layer":
			var keyframes := _array(_object(["time_ms", "x", "y", "scale", "rotation", "opacity"],
				{"easing": _choice(["smooth", "out", "linear"])}, ["time_ms"]), 24)
			if name == "update_animation_layer":
				return _object(["slot"], {"keyframes": keyframes}, ["slot", "keyframes"])
			return _object(["width", "height"], {"keyframes": keyframes, "source": _choice(["cover", "mask", "color", "shape"]), "shape_id": _type("string"),
				"artwork_id": _type("string"), "mask_id": _type("string"),
				"color": _choice(["teal", "rose", "blue", "amber", "violet", "white"])}, ["keyframes"])
		"remove_animation_layer":
			return _object(["slot"], {}, ["slot"])
		"get_editor_help":
			return _object([], {"query": _type("string")}, ["query"])
		"reply":
			return _object([], {"message": _type("string")}, ["message"])
		"finish":
			return _object([], {"summary": _type("string")})
	return _object([])

static func _notes(numbers: Array, required: Array, fields: Dictionary = {}) -> Dictionary:
	return _object([], {"notes": _array(_object(numbers, fields, required), 128)}, ["notes"])

static func _object(numbers: Array, fields: Dictionary = {}, required: Array = []) -> Dictionary:
	var properties := fields.duplicate()
	for field: String in numbers:
		var integer := field.ends_with("_ms") or field in ["id", "lane", "slot", "seed", "offset", "limit"]
		properties[field] = _type("integer" if integer else "number")
	return {"type": "object", "properties": properties, "required": required}

static func _array(items: Dictionary, maximum: int) -> Dictionary:
	return {"type": "array", "items": items, "minItems": 1, "maxItems": maximum}

static func _type(kind: String) -> Dictionary:
	return {"type": kind}

static func _choice(choices: Array) -> Dictionary:
	return {"type": "string", "enum": choices}
