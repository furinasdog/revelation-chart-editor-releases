extends Node

signal action_started(name: String, arguments: Dictionary)
signal action_finished(name: String, arguments: Dictionary, accepted: bool)
signal action_detail(message: String)
signal request_finished(round_index: int, elapsed_ms: int, tokens: int, ok: bool)
signal request_failed(stage: String, details: Dictionary)
signal response_streaming(round_index: int)
signal retry_available(message: String)
signal completed(success: bool, message: String, edits: Dictionary)
signal replied(message: String)
signal reply_preview(text: String)
signal tool_progress(service: String, caption: String)

const ROUND_LIMIT := 32
const ACTION_LIMIT := 24
const FORMAT_REPAIR_LIMIT := 3
const FRAME_REQUEST_LIMIT := 8
const LOCAL_ANALYSIS_LIMIT := 3
const REQUEST_BYTES := 384000
const TEXT_CONTEXT_BYTES := 96000
const TOOL_RESULT_BYTES := 3000
const ROUND_RESULT_BYTES := 32000
const References := preload("res://desktop/reference_library.gd")
const ReferenceMedia := preload("res://desktop/reference_media.gd")
const ScriptJobs := preload("res://desktop/script_jobs.gd")
const Guidance := preload("res://desktop/editor_guidance.gd")
const TRANSIENT_PROVIDER_ERRORS := ["upstream_interrupted", "upstream_busy", "all_upstreams_failed",
	"concurrency_exceeded", "rate_limited", "upstream_timeout"]
const Context := preload("res://desktop/agent_context.gd")
const ChartEdits := preload("res://desktop/agent_chart_edits.gd")
const AgentAudio := preload("res://desktop/agent_audio.gd")
const ChatStream := preload("res://desktop/chat_completion_stream.gd")
const ToolReply := preload("res://desktop/agent_tool_reply.gd")
const WRITES := ["add_notes", "move_notes", "resize_holds", "delete_notes", "set_positions", "seed_pattern",
	"set_note_lead_in", "set_hold_path", "scale_hold_paths", "create_solid_mask", "set_mask_cue", "add_mask_reveal", "add_animation_layer",
	"update_animation_layer", "remove_animation_layer", "set_project_artwork", "set_artwork_cue", "create_shape_asset"] + ChartEdits.EDIT_TOOLS
const CHAT_PROMPT := """
You are in interactive editing mode. Address the user's newest request and retain relevant earlier context. Read current project state freely. Each proposed change goes through the user's approval policy; a separate reviewer or the user decides. Present the smallest useful action, never retry a refused write in the same turn, and treat reads as read-only. A user may prefer advice only. For a question, use reply: {"message":"简明的中文回答"}; it applies no changes. If at least one write succeeded and the user wants to keep it, validate and use finish. The user sees each proposed write; report briefly what was actually changed. If all changes were refused, reply with the outcome. Use small batches when they help the user evaluate one edit. Do not assume that enabling animations means the request needs an animation. Do not request a whole-song change for a local edit. All user-facing replies should be in Chinese.
For questions about using this editor, call get_editor_help: {"query":"导出"}. Use the returned menu names in Chinese. If you already have what you need and no writes were made, you may answer as ordinary text for immediate streaming. For reply actions place name before arguments and message first within arguments so users can read the answer as it arrives. For music questions read available timing data first. Call analyze_audio for missing results or when a different engine is needed.
"""
const FRAME_PROMPT := """
Visual review tool (enabled by the user): view_rendered_frames: {"times_ms":[700,1800,3200]}. Request 1–6 chart times. It renders the current draft in game view; images are ordered left to right, then top to bottom. Inspect the result before finish. For masks compare just before the switch, during the reveal and after closing. Check that the subject is visible and the notes are readable. Request at most one montage per round, then wait for the returned image before continuing or finishing.
"""
const HUMAN_CHARTING_PROMPT := """
Charting practice observed in the human-made references (“风屿” and “Why Is My World Full Of Sadness”):
- Plan the whole song in phrases before filling it. Identify the entrance, the first clear rhythm, any sparse break, the returning motif and the last peak. Both references start noticeably sparser than their peaks; “风屿” also drops density in the middle and brings the earlier vocabulary back before its final build. Keep a few measured beats open where the music breathes. After a cut, let the return start a new gesture.
- Use a stable rhythmic or spatial motif for one or two bars, then change one element at a time: shift its register on the screen, mirror a diagonal, answer a diagonal with a straight horizontal sweep, or replace the last tap with a hold. Repeat a recognizable motif after a break. Avoid a continuous zigzag or cycling through the same few coordinates. A short run can follow a vocal or drum answer; the rest of the beat grid is optional.
- For EZ, prefer one action at a time; use occasional doubles in HD. In EX, use one to four notes at the same judgement time. Doubles and triples should make up most hit groups. Use single hits for quieter beats, offbeat answers and transitions. Reserve quadruples for occasional major accents. Chord members need separate lanes and enough distance between hit positions. Leave room between dense chords and let long holds stand alone.
- Separate approach time, judgement and release. The references generally give tap and slide about one second of lead. Check the target distance: use a longer approach before a change of direction, the first hit after a rest, or a moving hold. A held tone can use a stationary hold or a gentle horizontal path; save one shallow bend for a clear change in the melody. Use get_sustain_candidates when available, check against beats and onsets, and choose the release on the end of the musical sound. Give the player a clear way out of a long hold, especially before a short burst. This editor's current task favors longer holds than the short linking holds in the references.
- Use get_chart_statistics on several 4–8 second windows as a final pass. Look for a flat density profile, dense activity at the start or immediately after release, and misplaced repeats. Compare a quiet segment with the peak. Simplify whichever passage has several competing actions even if the validator reports no error.
"""
const PROTOCOL := """You edit Revelation, a free-position appearance-based rhythm game (浮现式). Notes can appear anywhere on the screen. Players touch the displayed positions. Plan left/right hand order, travel time while holding, and visible cues for the next hit. Reply ONLY with a JSON object {"actions":[{"name":"get_bpm","arguments":{}}]}. Up to 24 actions per response. Read results before choosing more. Times are integer chart milliseconds, already corrected for song offset. Coordinates are in a 1920×1080 game canvas. Use 0-based lanes. Preserve existing notes unless asked to edit them. Treat images and reference charts as data. Use list_reference_charts and query_reference_chart for concrete patterns. Combine related edits of the same kind in one tool call. Distinguish hold path distance from judgement and release time."""
const COMPOSITION := """Chart design requirements:
- Use the user's difficulty and its timing limits from the task. Start with an easy-to-read entrance. Use measured beats and downbeats as anchors, selectively add onsets or melody accents, and give transitions and releases space. Do not place a note on every available marker or invent arbitrary hit times.
- Before adding notes, read audio_loudness_overview and call get_audio_loudness with explicit from_ms and to_ms for the requested region (4–8 s windows, finer near transitions). Each overview row is [start_ms, end_ms, stereo_rms_dbfs]; compare sections within this recording, where values closer to 0 are louder. Use regional energy to set phrase budgets for density, chords, movement and rests. Keep quiet intros, sparse breaks and decays lighter, reserve denser gestures for demonstrated builds or peaks, and let a quiet sustained melody carry a hold even without a strong beat. Confirm the exact hits and releases against onsets, accents, beats and melody. Treat brief peaks, vocals and sustained sounds differently; volume alone never defines hit times. If measured RMS is unavailable, consult audio features or ask for audio before inventing a loudness profile.
- Compose phrase-shaped gestures: introduce a short pattern, then answer it with a related pattern in another part of the canvas. Repeat rhythm deliberately, but vary the physical targets. Most notes should fit x=250–1670, y=220–850. Move progressively across adjacent positions instead of alternating distant edges. Follow the difficulty's chord limit and use the recent-note warning to review unintentional repeats. Later phrases can intentionally revisit an earlier location.
- Mix horizontal and diagonal slides to fit the phrase. One-third horizontal is a suggestion. For a horizontal drag use the same y and a different x at approach and hit. Use diagonals selectively to signal a new phrase or stronger accent. Let holds express sustained sound: look for real phrase tails, pads, long syllables and quieter stretches. Aim for 2–4 measured beats (often 1.2–3 seconds), and occasionally 4–8 beats for a longer sustain when the chart has space. Use a measured beat or the audible release as the end. Avoid filling the held span with competing hits. Leave space after release for the next gesture. The minimum duration is a floor for exceptional accents, not a target. duration_ms is the time actively held after judgement, separate from the visibility lead-in. Use scale_hold_paths for spatial distance and resize_holds for time held.
- Use get_project_context and get_audio_features to understand the song and pick sections. Use get_emotions for available Music2Emo segments to guide mood, density and animation choices. If needed, request analyze_audio with music2emo and the emotions task. The emotion scores describe the music and do not locate hits. If detection looks inconsistent, compare native engines with analyze_audio; read its results before editing. Compose from section evidence and use direct note tools. Use get_chart_statistics to inspect density and hold phrasing, then refine and run check_conflicts before finish. Adjust flagged positions or timing instead of deleting all notes. Use list_notes or list_note_paths for specific sections when editing by ID."""
const NOTE_TOOLS := """Tools:
get_bpm, get_beats, get_melody, estimate_mood: {"from_ms":0,"to_ms":8000,"offset":0,"limit":64}. get_beats may select "kind":"beats"|"downbeats"|"onsets"|"accents". estimate_mood is an acoustic estimate, not a human emotion classification.
list_notes: same range/paging arguments, returns editable IDs.
add_notes: {"notes":[{"type":"note"|"drag"|"hold","time_ms":1600,"lane":0,"x":800,"y":450,"duration_ms":2000,"end_x":1050,"end_y":450,"approach_x":550,"approach_y":450}]}. time_ms is judgement. Duration and end coordinates apply to holds. Optional approach coordinates determine a drag's entrance; use the same y for horizontal slides.
delete_notes: {"ids":[1,2]}. move_notes: {"notes":[{"id":1,"time_ms":900,"lane":2}]}. set_positions: {"notes":[{"id":1,"x":800,"y":450}]} accepts optional end/approach coordinate pairs. resize_holds: {"notes":[{"id":1,"duration_ms":2500}]} changes the release time while keeping the judgement and path. Up to 128 changes per call.
seed_pattern: {"seed":42,"from_ms":0,"to_ms":-1}. Generates a rhythmic base at the user's difficulty; -1 means through the end. The seed changes phrase shapes, while measured markers and musical phrasing set the timing.
check_conflicts: {} finds overlaps, excessive chords, uncomfortable jumps and quick holds, and reports new_hit_chords. Use a seeded draft only when the user explicitly requests automated scaffolding. Compare get_chart_statistics over quiet and loud sections and refine density where it misses the audio dynamics before finishing. Inspect individual notes only to repair specific problems or when the user requests changes. Keep seeded chords together. For errors, query only the affected time ranges and use pagination. Finish with finish: {"summary":"Brief Chinese summary"}. A valid finish applies the draft. Avoid editing notes when edit_notes=false. Tool calls are plain JSON without Markdown fences. In Chinese replies and finish summaries you may use headings, lists, emphasis and code spans."""

const ANIMATION_PROMPT := """
Animation direction:
- When requires_visible_animation is true, deliver visible motion that follows musical phrases. A dark mask, static image swap, or uniform fade can support contrast, but cannot satisfy the animation request on its own. Add a deliberate moving or scaling graphic, an artwork pan, or an aperture that visibly opens and closes against a mask. For a full song, give the same visual motif distinct treatments at two or more genuine transitions, such as a quiet entrance and a rising section. Consult regional RMS, onsets and section cues to choose where motion starts and ends. Use list_animation_layers and check has_visible_motion before finish. If frame review is enabled, inspect the same motif before, during and after its change.
- Before authoring, get_animation_cues {"from_ms":0,"limit":18}. Use the returned phrase anchors and coarse loudness for the intro, section change, accent and release. Use the selected span if the user requested one. Leave quiet passages mostly still; one change per phrase is usually enough. Land major motions on the measured anchor, not an arbitrary offset. A hold between two similar poses is fine.
- Use solid masks and circular background reveals in the style of the “领主” chart. For full songs, plan two to four coordinated masks with different roles: an opaque or near-opaque dark opening, a tinted translucent mask for a new section, optionally a transparent release. Place them only at meaningful musical changes. Use add_mask_reveal to expand the visible artwork from a focal point and close with the phrase; stagger distinct reveals rather than flashing or flipping colors every beat. Choose muted shades already present in the artwork and reuse assets that match. If the user specifies a short span, scale the number of effects to that span.
- Design one visual idea for the song, with a recognizable focal point. When the user has supplied artwork, inspect it and set use_cover_artwork=true on a mask cue to place it below the masks, or animate it as a cover layer when the brief calls for camera motion. Keep the subject within frame, preserve the aspect ratio, and prefer a subtle pan or push-in. Favor scale 1.0–1.12, movement of roughly 24–80 px and rotation near 0°. Keep the artwork visible during a meaningful section.
- When multiple selected images are provided, identify each by its artwork_id. Use all selected artwork across meaningful sections with legible durations. Choose the order based on image content, song structure and the brief. Change backgrounds at phrase or section boundaries, and plan separate mask opacity for each image. Avoid rapid cycling or sending multiple opaque foreground layers over gameplay.
- Pale artwork can wash out white hit rings, slide markers and thin hold lines. If the artwork looks bright, get_cover reports bright_playfield=true, or rendered frames show weak contrast, put a dark low-saturation mask over the artwork as the bottom image. Start around 0.45–0.65 opacity, adjust for contrast, and avoid large unmasked reveals over dense notes or a hold release. Reserve bright reveals for quieter spans or the edges; review representative busy frames if the user enabled frame inspection. A semi-transparent cover animation above the mask can undo darkening, so use the background mask path for bright artwork.
- Keep the central play area readable. A mask asset can also be used as a moving band or shutter in a mask layer. Prefer a narrow shape near the edge and low opacity. Avoid multiple overlapping shapes, back-and-forth spins, flashing, and changing position, scale, rotation and opacity at every beat.
- Use smooth easing for camera movement, out for settling, and linear only for deliberate steady motion. Keep large shifts and opacity changes spread over at least a beat and use 3–7 intentional poses per layer unless the brief needs more. Do not create visual changes during a playable section just to fill time.
- The human references build scenes with recurring thin lines, outlined rectangles and circular accents. Layer them by function: a steady stage treatment for the current phrase, a brief direction cue from the edge, then a fade. A pair of related cues can enter a half beat or beat apart and lead the eye toward the next phrase. For a busy peak reuse a familiar geometry with a wider or stronger gesture rather than introducing unrelated layers. To reproduce the technique with available tools, use a thin low-opacity mask layer (about 8–24 px for a line) away from judgement positions, and add_mask_reveal for the occasional circle. Prefer preserving legibility over reproducing the references' dense stack of layers.
- Use check_cover_contrast at the first hit, a dense phrase, during a reveal, and at a long hold's release. If it flags a bright or occluded passage, correct the underlying mask or revise the affected image keyframes with update_animation_layer, then inspect actual frames when allowed. Compare the same time before and after a major adjustment.
- Use create_shape_asset for transparent outlined squares, rings or line accents, and add_animation_layer with source:shape and its shape_id to animate them. Draw an outline or a small set of related strokes that fit the composition. Thin outlines and fading at phrase boundaries preserve note readability. Use the radius-based mask reveal for unveiling the artwork itself."""
const ANIMATION_TOOLS := """Animation tools:
get_animation_cues: {"from_ms":0,"to_ms":12000,"limit":12}. Compact phrase anchors in chart milliseconds with an approximate intensity for each.
create_solid_mask: {"color":"#111827","opacity":1}. Creates a local solid-color PNG resource in the draft. It returns mask_id. Opacity 0 means transparent, 1 means fully masking the bottom image.
set_mask_cue: {"mask_id":"<returned ID>","time_ms":0,"artwork_id":"artwork_1"}. Switch the mask and select the specified artwork as the bottom image. Omit artwork_id and use_cover_artwork to keep the bottom image. use_cover_artwork=true is shorthand for the first image. Use an empty mask_id to remove this run's cue at that time.
add_mask_reveal: {"time_ms":400,"duration_ms":3000,"x":960,"y":540,"radius_px":900}. Expands, briefly holds, then closes a feathered aperture revealing the bottom image. Schedule while a suitably opaque mask is active. It returns a slot, removable by remove_animation_layer.
list_animation_layers: {}, get_cover: {"artwork_id":"artwork_2"} to inspect one image and list all available artwork. Omit the ID to inspect the first image. remove_animation_layer: {"slot":0} for new draft layers only.
add_animation_layer: {"source":"cover"|"color"|"mask","artwork_id":"artwork_1","mask_id":"<returned ID>","width":540,"height":120,"color":"teal"|"rose"|"blue"|"amber"|"violet"|"white","keyframes":[{"time_ms":0,"x":932,"y":540,"opacity":0},{"time_ms":1800,"opacity":0.35,"easing":"out"},{"time_ms":5200,"x":980,"scale":1.08,"easing":"smooth"}]}. Use artwork_id for cover layers, one layer per image. The mask_id, width and height apply only to mask layers. Keyframes inherit omitted positions, opacity, scale and rotation. Easing applies to the transition into each frame. The first frame is at 0, subsequent frames are at least 240 ms apart. Confirm and summarize the artistic intent briefly in Chinese.
"""

var _request: HTTPRequest
var _stream := ChatStream.new()
var _stream_disabled := false
var _stream_usage_disabled := false
var _using_stream := false
var _reply_prefix := RegEx.create_from_string(r'^\s*(?:```(?:json)?\s*)?\{\s*"actions"\s*:\s*\[\s*\{\s*"name"\s*:\s*"reply"\s*,\s*"arguments"\s*:\s*\{\s*"message"\s*:\s*"')
var _plan: RefCounted
var _animation: RefCounted
var _motion_requested := false
var _editor_edits: RefCounted
var _edit_notes := true
var _music: Dictionary
var _moods: Array
var _messages: Array[Dictionary] = []
var _compacted := 0
var _endpoint := ""
var _key := ""
var _model := ""
var _active := false
var _round := 0
var _invalid_tool_replies := 0
var _retry := 0
var _waiting_retry := false
var _run_id := 0
var _request_started_ms := 0
var _frame_capture: Callable
var _audio_spectrum: Callable
var _editor_view: Callable
var _audio_selection := Vector2(-1, -1)
var _frame_requests := 0
var _visual_message_index := -1
var _chart: Node
var _reanalyze: Callable
var _analysis_requests := 0
var _approve: Callable
var _review_commit := false
var _help: Callable
var _import_audio: Callable

func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = ChatStream.TIMEOUT_MS / 1000.0
	_request.body_size_limit = 2 * 1024 * 1024
	_request.max_redirects = 0
	_request.use_threads = true
	add_child(_request)
	_request.request_completed.connect(_on_response)
	add_child(_stream)
	_stream.delta.connect(_on_stream_delta)
	_stream.opened.connect(func(): response_streaming.emit(_round))
	_stream.completed.connect(_on_response)

static func endpoint_from_url(value: String) -> String:
	var url := value.strip_edges().trim_suffix("/")
	var is_loopback := url.begins_with("http://127.0.0.1:") or url.begins_with("http://localhost:")
	if not (url.begins_with("https://") or is_loopback) or "?" in url or "#" in url or " " in url:
		return ""
	var address := url.substr(url.find("://") + 3)
	var authority := address.get_slice("/", 0)
	if authority.is_empty() or "@" in authority or "\\" in authority:
		return ""
	if url.ends_with("/chat/completions"):
		return url
	return url + ("/chat/completions" if "/" in address else "/v1/chat/completions")

func start(plan: RefCounted, music: Dictionary, moods: Array, settings: Dictionary, brief: String,
		animation: RefCounted = null, edit_notes := true, frame_capture := Callable(),
		reanalyze := Callable(), chat := {}, audio := {}) -> void:
	_endpoint = endpoint_from_url(str(settings.url))
	_key = str(settings.key).strip_edges()
	_model = str(settings.model).strip_edges()
	if _endpoint.is_empty() or _key.is_empty() or _model.is_empty() or "\n" in _key or "\r" in _key:
		completed.emit(false, "请在 Agent 设置中填写有效的 API URL、API Key 和模型名称。", {})
		return
	_plan = plan
	_chart = plan._chart
	_editor_edits = ChartEdits.new(_chart, plan.duration_ms)
	_reanalyze = reanalyze
	_editor_view = chat.get("editor_view", Callable())
	_approve = chat.get("approve", Callable())
	_review_commit = chat.get("review_commit", false)
	_help = chat.get("help", Callable())
	_import_audio = chat.get("import_audio", Callable())
	_stream_disabled = false
	_stream_usage_disabled = false
	_analysis_requests = 0
	_animation = animation
	_motion_requested = animation != null and (not _approve.is_valid() or _requests_new_animation(brief))
	_edit_notes = edit_notes
	_frame_capture = frame_capture
	_audio_spectrum = audio.get("spectrum", Callable())
	_audio_selection = audio.get("selection", Vector2(-1, -1))
	_frame_requests = 0
	_visual_message_index = -1
	_music = music
	_moods = moods
	_round = 0
	_compacted = 0
	_invalid_tool_replies = 0
	_retry = 0
	_waiting_retry = false
	_run_id += 1
	_active = true
	var counts := {}
	for key: String in ["beats", "downbeats", "onsets", "accents", "tempo_curve", "melody", "emotions"]:
		counts[key] = music.get(key, []).size()
	var use_cover: bool = animation != null and not animation.artwork.is_empty()
	var task := JSON.stringify({"brief": brief, "from_ms": plan.start_ms, "to_ms": plan.duration_ms,
		"editor": _editor_state(), "lanes": plan.track_count, "existing_notes": plan.notes.size(), "available_analysis": counts,
		"animations": animation != null, "use_cover": use_cover, "edit_notes": edit_notes,
		"requires_visible_animation": _motion_requested, "audio_loudness_overview": _loudness_overview(),
		"artwork": animation.artwork_catalog() if use_cover else [],
		"preview_available": frame_capture.is_valid(),
		"audio_figure_available": _audio_spectrum.is_valid(),
		"selected_audio_span_ms": [roundi(_audio_selection.x), roundi(_audio_selection.y)] if _audio_selection.y > _audio_selection.x else [],
		"difficulty": plan.difficulty, "first_hit_ms": plan.start_ms + int(plan.profile.intro_ms),
		"minimum_ordinary_gap_ms": plan.profile.gap, "minimum_hold_duration_ms": plan.profile.hold_ms,
		"recent_position_window_ms": 2100, "recent_position_count": 5, "minimum_recent_position_distance_px": 100})
	if _approve.is_valid():
		task = JSON.stringify({"conversation": chat.get("history", []), "project": JSON.parse_string(task)})
	var content: Variant = task
	if use_cover:
		var visual_content := [{"type": "text", "text": task}]
		for image: Dictionary in animation.artwork_catalog():
			var id: String = image.artwork_id
			visual_content.append({"type": "text", "text": "Artwork %s (%s):" % [id, image.filename]})
			visual_content.append({"type": "image_url", "image_url": {"url": animation.artwork[id].data_url}})
		content = visual_content
	var interactive := _approve.is_valid()
	var instructions := PROTOCOL + "\n" + NOTE_TOOLS + "\n"
	if interactive:
		instructions += Guidance.EDITOR
	else:
		instructions += COMPOSITION + HUMAN_CHARTING_PROMPT + "\n" + Guidance.FULL
	if animation:
		instructions += "\n" + Guidance.MASKS + "\n" + ANIMATION_TOOLS if interactive else ANIMATION_PROMPT + ANIMATION_TOOLS
	instructions += FRAME_PROMPT if frame_capture.is_valid() else ""
	instructions += "\nAdditional editor tools available for this run (argument schemas): " + JSON.stringify(
		Context.describe(animation != null, edit_notes, reanalyze.is_valid(), _audio_spectrum.is_valid(), not interactive))
	if interactive:
		instructions += CHAT_PROMPT
	_messages.assign([{"role": "system", "content": instructions}, {"role": "user", "content": content}])
	_send()

func rebase_after_audio_import(plan: RefCounted, animation: RefCounted, music: Dictionary, moods: Array, selection: Vector2) -> void:
	_plan = plan
	_animation = animation
	_editor_edits = ChartEdits.new(_chart, plan.duration_ms)
	_music = music
	_moods = moods
	_audio_selection = selection
	_analysis_requests = 0

func open_tool_session(plan: RefCounted, music: Dictionary, moods: Array, animation: RefCounted, options: Dictionary) -> void:
	cancel()
	_plan = plan
	_chart = plan._chart
	_editor_edits = ChartEdits.new(_chart, plan.duration_ms)
	_music = music
	_moods = moods
	_animation = animation
	_edit_notes = true
	_editor_view = options.get("editor_view", Callable())
	_help = options.get("help", Callable())
	_reanalyze = options.get("reanalyze", Callable())
	_frame_capture = options.get("frames", Callable())
	_audio_spectrum = options.get("spectrum", Callable())
	_analysis_requests = 0
	_active = true

func call_workspace_tool(name: String, arguments: Dictionary, selection: Vector2) -> Dictionary:
	_audio_selection = selection
	match name:
		"reply":
			var message := str(arguments.get("message", "")).strip_edges().left(4000)
			if message.is_empty():
				return {"error": "请提供回复文字。"}
			return {"reply": message}
		"finish":
			if not _chat_has_changes():
				return {"error": "目前没有可提交的谱面修改。"}
			return _validate_finish(arguments)
		"analyze_audio":
			return await _analyze_audio(arguments, _run_id)
		"run_rpy":
			return await _run_rpy(arguments, _run_id)
		"view_rendered_frames":
			_frame_requests = 0
			return await _render_frames(arguments)
		"view_audio_figure":
			_frame_requests = 0
			return await _render_audio_figure(arguments)
		"view_shape_asset":
			_frame_requests = 0
			return _view_shape_asset(arguments)
		"view_reference_artwork", "view_reference_frame":
			_frame_requests = 0
			return await _render_reference(name, arguments, _run_id)
	return _call_tool(name, arguments)

func cancel() -> void:
	_active = false
	_run_id += 1
	_request.cancel_request()
	_stream.cancel()
	_clear_state()

func retry_request() -> void:
	if not _active or not _waiting_retry:
		return
	_waiting_retry = false
	_retry += 1
	_send(true)

func _send(retry := false) -> void:
	if not _active:
		return
	if not retry:
		_round += 1
		_retry = 0
	if _round > ROUND_LIMIT:
		_finish(false, "已达到 Agent 请求轮次上限。草稿未应用。")
		return
	_using_stream = not _stream_disabled
	action_started.emit("请求模型" if not retry else "重试模型请求", {"round": _round, "model": _model, "retry": _retry,
		"service": _endpoint.get_slice("://", 1).get_slice("/", 0), "stream": _using_stream})
	var payload := _request_payload()
	if payload.is_empty():
		_finish(false, "本轮上下文超过限制。请缩短制谱范围或减少同时查看的曲绘和预览帧。")
		return
	_request_started_ms = Time.get_ticks_msec()
	var status := _stream.start(_endpoint, _key, payload) if _using_stream else _request.request(
		_endpoint, ["Content-Type: application/json", "Authorization: Bearer " + _key], HTTPClient.METHOD_POST, payload)
	if status != OK:
		request_failed.emit("request_start", {"round": _round, "os_error": status})
		_finish(false, "无法连接 Agent API（错误 %d）。" % status)

func _request_payload() -> String:
	while true:
		var messages := _messages.duplicate()
		if _compacted > 0:
			var summary := {"omitted_exchanges": _compacted, "draft_note_count": _plan.notes.size(),
				"edited_note_count": _plan.edited.size(), "new_hit_chords": _plan.new_hit_chords(),
				"animation_layer_count": _animation.layers.size() if _animation else 0,
				"mask_cue_count": _animation.mask_cues.size() if _animation else 0}
			messages[0] = {"role": "system", "content": str(messages[0].content)
				+ "\nOlder tool exchanges were compacted. Draft changes remain applied locally. "
				+ "Use editor tools to look up existing details. Current draft: " + JSON.stringify(summary)}
		var request := {"model": _model, "messages": messages, "stream": _using_stream, "max_tokens": 8192}
		if _using_stream and not _stream_usage_disabled:
			request["stream_options"] = {"include_usage": true}
		var payload := JSON.stringify(request)
		if _text_bytes(messages) <= TEXT_CONTEXT_BYTES and payload.to_utf8_buffer().size() <= REQUEST_BYTES:
			return payload
		if not _drop_oldest_exchange():
			return ""
	return ""

func _drop_oldest_exchange() -> bool:
	# Keep the project brief and the most recent assistant/tool exchange together.
	for index in range(2, _messages.size() - 2):
		if _messages[index].role != "user":
			continue
		var removed := index - 1
		_messages = _messages.slice(0, 2) + _messages.slice(index + 1)
		if _visual_message_index > index:
			_visual_message_index -= removed
		_compacted += 1
		return true
	return false

static func _text_bytes(messages: Array[Dictionary]) -> int:
	var total := 0
	for message: Dictionary in messages:
		if message.content is String:
			total += message.content.to_utf8_buffer().size()
		elif message.content is Array:
			for part: Dictionary in message.content:
				if part.get("type") == "text":
					total += str(part.get("text", "")).to_utf8_buffer().size()
	return total

func _on_response(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _active:
		return
	var elapsed := Time.get_ticks_msec() - _request_started_ms
	var json := JSON.new()
	var document: Variant = json.data if not body.is_empty() and json.parse(body.get_string_from_utf8()) == OK else null
	var provider_error: Variant = document.get("error") if document is Dictionary else null
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300 and provider_error == null
	request_finished.emit(_round, elapsed, _usage_tokens(document), ok)
	if not ok:
		var service_code := str(provider_error.get("code", "")).left(80) if provider_error is Dictionary else ""
		var trace := _response_header(headers, "x-agiplan-trace")
		request_failed.emit("http_response", {"round": _round, "http_status": code, "transport_status": result,
			"provider_code": service_code, "trace": trace, "retry": _retry})
		if (_using_stream and not _stream_usage_disabled and code in [400, 422] and provider_error is Dictionary
				and (provider_error.get("param") == "stream_options" or "stream_options" in str(provider_error.get("message", "")))):
			_stream_usage_disabled = true
			_send.call_deferred(true)
			return
		if _using_stream and service_code not in ["upstream_rejected", "capability_unavailable"] and code in [400, 415, 422, 501]:
			_stream_disabled = true
			_send.call_deferred(true)
			return
		if _approve.is_valid() and _retry < 1 and (code in [502, 503, 504] or result == HTTPRequest.RESULT_CANT_CONNECT):
			_retry += 1
			var run_id := _run_id
			action_started.emit("等待重试", {"http_status": code, "connection_status": result})
			await get_tree().create_timer(1.0).timeout
			if run_id == _run_id:
				_send(true)
			return
		var reasons := {401: "API Key 未通过验证", 403: "当前账号没有模型权限", 404: "接口路径或模型不存在",
			413: "请求超过服务允许的大小，请缩小制谱范围",
			408: "网关等待超时", 429: "请求受限或额度不足", 502: "模型上游暂不可用",
			503: "模型服务暂不可用", 504: "网关等待模型超时"}
		var transport_reasons := {HTTPRequest.RESULT_CONNECTION_ERROR: "与模型的连接中断",
			HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH: "与模型的连接中断，响应数据不完整",
			HTTPRequest.RESULT_REQUEST_FAILED: "无法发送模型请求",
			HTTPRequest.RESULT_CANT_CONNECT: "无法连接模型服务", HTTPRequest.RESULT_CANT_RESOLVE: "无法解析模型服务地址",
			HTTPRequest.RESULT_TIMEOUT: "等待模型响应超过 15 分钟",
			HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED: "模型返回的数据超过响应大小上限"}
		var provider_reasons := {"upstream_interrupted": "AGIPlan 报告模型流式响应中断",
			"upstream_busy": "模型上游繁忙", "all_upstreams_failed": "暂时无法连接可用的模型上游",
			"concurrency_exceeded": "已达服务并发上限", "rate_limited": "服务请求过于频繁",
			"quota_exceeded": "服务额度不足", "upstream_timeout": "等待模型上游响应超时",
			"capability_unavailable": "当前模型不支持本次请求需要的能力",
			"upstream_rejected": "模型上游拒绝了本次请求"}
		if ((_animation and not _animation.artwork.is_empty()) or _visual_message_index >= 0) and code in [400, 413, 415, 422]:
			reasons[code] = "服务拒绝了含图片的请求。请选择支持图片输入的模型，或关闭图片输入后重试。"
		var reason: String = transport_reasons.get(result, provider_reasons.get(service_code, reasons.get(code, "模型请求失败")))
		var message := "第 %d 轮 · %s（HTTP %d，连接状态 %d）" % [_round, reason, code, result]
		if not trace.is_empty():
			message += " · AGIPlan 追踪号 " + trace
		var retryable := ((transport_reasons.has(result) and result != HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED)
			or service_code in TRANSIENT_PROVIDER_ERRORS
			or (service_code.is_empty() and code in [408, 429, 500, 502, 503, 504]))
		if retryable:
			_waiting_retry = true
			var retry_after := _response_header(headers, "retry-after")
			if retry_after.is_valid_int() and int(retry_after) > 0:
				message += " · 服务建议 %s 秒后重试" % retry_after
			retry_available.emit(message)
		else:
			_finish(false, message)
		return
	if _visual_message_index >= 0:
		var visual_content: Array = _messages[_visual_message_index].content
		_messages[_visual_message_index].content = visual_content[0].text
		_visual_message_index = -1
	var choices: Variant = document.get("choices", []) if document is Dictionary else []
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary or not choices[0].get("message") is Dictionary:
		request_failed.emit("response_schema", {"round": _round})
		_finish(false, "接口未返回 Chat Completions 消息。")
		return
	var message: Dictionary = choices[0].message
	var content: Variant = message.get("content", "")
	if content == null:
		content = ""
	if not content is String or content.length() > 108000:
		request_failed.emit("response_content", {"round": _round})
		_finish(false, "模型回复为空或过长。")
		return
	var provider_calls: Variant = message.get("tool_calls")
	var structured: bool = provider_calls != null and (not provider_calls is Array or not provider_calls.is_empty())
	var marked := ToolReply.has_markup(content)
	if structured or marked:
		var decoded := ToolReply.parse_calls(provider_calls, ACTION_LIMIT) if structured else ToolReply.parse_markup(content, ACTION_LIMIT)
		if decoded.is_empty():
			_repair_tool_reply()
			return
		# Keep the existing JSON action/result conversation for all compatible endpoints.
		_dispatch_reply_actions(decoded)
		return
	var first: int = content.find("{")
	var last: int = content.rfind("}")
	var parser := JSON.new()
	var parsed: Variant = parser.data if first >= 0 and last >= first and parser.parse(content.substr(first, last - first + 1)) == OK else null
	var actions: Variant = parsed.get("actions", []) if parsed is Dictionary else []
	if actions is Array and not actions.is_empty() and actions.size() <= ACTION_LIMIT:
		_dispatch_reply_actions(actions)
		return
	if _approve.is_valid() and _is_plain_reply(content) and not content.strip_edges().is_empty() and not _chat_has_changes():
		_finish_reply(content.strip_edges().left(4000))
		return
	_repair_tool_reply()

func _repair_tool_reply() -> void:
	_invalid_tool_replies += 1
	request_failed.emit("tool_call_format", {"round": _round, "consecutive": _invalid_tool_replies})
	if _invalid_tool_replies >= FORMAT_REPAIR_LIMIT:
		_invalid_tool_replies = 0
		_waiting_retry = true
		retry_available.emit("模型连续返回无法解析的工具调用。可重试本轮，已批准的草稿仍在。")
		return
	_messages.append({"role": "user", "content": "The previous tool response could not be parsed. Return one JSON object with 1–%d actions following the tool schema. Combine a small edit in one call." % ACTION_LIMIT})
	_send.call_deferred()

static func _response_header(headers: PackedStringArray, name: String) -> String:
	for header: String in headers:
		var colon := header.find(":")
		if colon >= 0 and header.left(colon).strip_edges().to_lower() == name:
			return header.substr(colon + 1).strip_edges().left(96)
	return ""

func _dispatch_reply_actions(actions: Array) -> void:
	_invalid_tool_replies = 0
	var content := JSON.stringify({"actions": actions})
	if content.to_utf8_buffer().size() > 24000:
		content = JSON.stringify({"executed_tool_batch": actions.map(func(action: Variant):
			return action.get("name", "") if action is Dictionary else ""),
			"notice": "Bulk arguments compacted. See tool results and query the draft for details."})
	_messages.append({"role": "assistant", "content": content})
	_execute_actions(actions)

static func _is_plain_reply(text: String) -> bool:
	var start := text.strip_edges()
	return (not start.begins_with("{") and not start.begins_with("[") and not start.begins_with("`")
		and not start.begins_with("<") and not ToolReply.has_markup(start))

func _on_stream_delta(text: String) -> void:
	if not _active or not _approve.is_valid() or _chat_has_changes():
		return
	# Stop before '<' even if the rest of a control marker has not arrived yet.
	var plain_preview := text.get_slice("<", 0)
	if _is_plain_reply(plain_preview):
		var trimmed := plain_preview.strip_edges()
		if not trimmed.is_empty():
			reply_preview.emit(plain_preview.left(4000))
			return
	var prefix := _reply_prefix.search(plain_preview)
	if not prefix:
		return
	var start := prefix.get_end()
	var end := start
	while end < plain_preview.length() and end - start < 8000:
		if plain_preview[end] == '"':
			break
		if plain_preview[end] == "\\":
			if end + 1 >= plain_preview.length():
				break
			var length := 6 if plain_preview[end + 1] == "u" else 2
			if end + length > plain_preview.length():
				break
			end += length
		else:
			end += 1
	var decoded: Variant = JSON.parse_string('"' + plain_preview.substr(start, end - start) + '"')
	if decoded is String and not decoded.is_empty():
		reply_preview.emit(decoded.left(4000))

func _execute_actions(actions: Array) -> void:
	var results: Array = []
	var share_budget := (ROUND_RESULT_BYTES - 2400) / maxi(actions.size(), 1)
	var rendered_image := ""
	var run_id := _run_id
	for action: Variant in actions:
		if not _active or run_id != _run_id:
			return
		if not action is Dictionary or not action.get("name") is String or action.name.length() > 80 or not action.get("arguments", {}) is Dictionary:
			results.append({"error": "动作须包含 name 与 arguments 对象。"})
			continue
		var name: String = action.name
		var arguments: Dictionary = action.get("arguments", {})
		action_started.emit(name, arguments)
		# Present each model action before executing the next one, including batches.
		await get_tree().process_frame
		if not _active or run_id != _run_id:
			return
		var response: Dictionary
		var approved := true
		if _approve.is_valid() and (name in WRITES or name == "analyze_audio" or (name == "finish" and _review_commit and _chat_has_changes())):
			approved = await _approve.call(name, arguments)
		if not approved:
			if not _active or run_id != _run_id:
				return
			response = {"error": "用户拒绝了这项修改。请遵循用户的选择。"}
		elif not _active or run_id != _run_id:
			return
		elif name == "import_audio":
			if actions.size() != 1:
				response = {"error": "请单独请求导入音频，导入后再读取工程或处理草稿。"}
			elif not _import_audio.is_valid():
				response = {"error": "当前会话无法导入音频。"}
			else:
				response = await _import_audio.call(arguments)
			if not _active or run_id != _run_id:
				return
		elif name == "reply" and not rendered_image.is_empty():
			response = {"error": "请先查看返回的画面，再回复用户。"}
		elif name in ["view_rendered_frames", "view_audio_figure", "view_shape_asset", "view_reference_artwork", "view_reference_frame"]:
			if not rendered_image.is_empty():
				response = {"error": "每轮只能查看一张图，请先查看已经生成的图。"}
			elif name == "view_audio_figure":
				response = await _render_audio_figure(arguments)
			elif name == "view_shape_asset":
				response = _view_shape_asset(arguments)
			elif name in ["view_reference_artwork", "view_reference_frame"]:
				response = await _render_reference(name, arguments, run_id)
			else:
				response = await _render_frames(arguments)
			if not _active or run_id != _run_id:
				return
			if response.has("_preview_image"):
				rendered_image = response["_preview_image"]
				response.erase("_preview_image")
		elif name == "analyze_audio":
			response = await _analyze_audio(arguments, run_id)
			if not _active or run_id != _run_id:
				return
		elif name == "run_rpy":
			if _approve.is_valid():
				response = {"error": "内置 Co-pilot 使用直接工具。请改用批量音符编辑工具。"}
			else:
				response = await _run_rpy(arguments, run_id)
			if not _active or run_id != _run_id:
				return
		elif name == "finish" and not rendered_image.is_empty():
			response = {"error": "请先查看返回的画面，再在下一轮提交。"}
		else:
			response = _call_tool(name, arguments)
		if response.has("error"):
			var detail := str(response.error)
			var report: Dictionary = response.get("conflicts", {})
			if not report.is_empty():
				detail += "\n" + Context.describe_validation(report)
				if not report.get("errors", []).is_empty():
					detail += "\n" + str(report.errors[0][0])
			action_detail.emit(detail)
		elif name == "locate_notes":
			action_detail.emit(Context.location_summary(response))
		elif name == "get_audio_features":
			action_detail.emit(Context.music_summary(response))
		elif name == "check_conflicts":
			action_detail.emit(Context.describe_validation(response))
		action_finished.emit(name, arguments, not response.has("error"))
		if response.has("finished"):
			_finish(true, str(response.finished))
			return
		if response.has("reply"):
			_finish_reply(str(response.reply))
			return
		var result_budget := mini(7000 if name == "get_editing_guide" else TOOL_RESULT_BYTES, share_budget)
		var limited := _limit_tool_result(response, result_budget)
		if JSON.stringify(limited).to_utf8_buffer().size() > result_budget:
			limited = {"notice": "Result exceeds this round's budget. Query a narrower range."}
		results.append({"name": name, "result": limited})
	var result_text := JSON.stringify({"tool_results": results})
	if rendered_image.is_empty():
		_messages.append({"role": "user", "content": result_text})
	else:
		_visual_message_index = _messages.size()
		_messages.append({"role": "user", "content": [{"type": "text", "text": result_text},
			{"type": "image_url", "image_url": {"url": rendered_image}}]})
	_send.call_deferred()

static func _limit_tool_result(result: Dictionary, budget: int = TOOL_RESULT_BYTES) -> Dictionary:
	if JSON.stringify(result).to_utf8_buffer().size() <= budget:
		return result
	var compact := result.duplicate()
	if result.get("conflicts") is Dictionary:
		compact["conflicts"] = _limit_tool_result(result.conflicts, maxi(450, budget - 300))
	if result.get("results") is Dictionary and not result.results.is_empty():
		var pages := {}
		var page_budget := maxi(400, (budget - 500) / result.results.size())
		for task: String in result.results:
			pages[task] = _limit_tool_result(result.results[task], page_budget)
		compact["results"] = pages
	for key: String in ["items", "draft", "errors", "warnings"]:
		if not compact.get(key) is Array:
			continue
		var rows: Array = compact[key]
		var shown := rows.size()
		while shown > 0 and JSON.stringify(compact).to_utf8_buffer().size() > budget:
			shown /= 2
			compact[key] = rows.slice(0, shown)
		if shown < rows.size():
			compact["notice"] = "Result shortened to fit the context. Request a smaller range or page."
			if key == "items" and shown > 0:
				compact["next_offset"] = int(result.get("offset", 0)) + shown
	if JSON.stringify(compact).to_utf8_buffer().size() > budget:
		var brief := {"notice": "Result too large. Request a smaller range or page."}
		for key: String in ["error", "ids", "total", "added", "total_notes", "error_count", "warning_count", "slide_directions", "edited_slide_directions"]:
			if result.has(key):
				brief[key] = result[key]
		return brief
	return compact

func _render_frames(arguments: Dictionary) -> Dictionary:
	if not _frame_capture.is_valid():
		return {"error": "用户未开启渲染画面查看。"}
	if _frame_requests >= FRAME_REQUEST_LIMIT:
		return {"error": "本次制谱已达到取帧次数上限。"}
	var requested: Variant = arguments.get("times_ms")
	if not requested is Array or requested.is_empty() or requested.size() > 6:
		return {"error": "times_ms 须包含 1–6 个时间点。"}
	var times: Array = []
	for value: Variant in requested:
		if not (value is int or value is float) or not is_finite(float(value)) or value < 0 or value > _plan.duration_ms:
			return {"error": "取帧时间须为歌曲范围内的毫秒数。"}
		times.append(roundi(value))
	_frame_requests += 1
	return await _frame_capture.call(times)

func _audio_span(arguments: Dictionary, max_duration := 0) -> Vector2i:
	var first := maxi(0, ceili(_chart.audio_delay_ms))
	var last := floori(_chart.audio_delay_ms + _chart.audio_duration_ms)
	if last <= first:
		return Vector2i.ZERO
	var has_selection := _audio_selection.y > _audio_selection.x
	var start := _integer(arguments, "from_ms", roundi(_audio_selection.x) if has_selection else first, first, last)
	start = clampi(start, first, last)
	var default_end := clampi(roundi(_audio_selection.y), first, last) if has_selection else last
	if not arguments.has("to_ms") and max_duration > 0:
		default_end = mini(default_end, start + max_duration)
	var end := _integer(arguments, "to_ms", default_end, first, last)
	return Vector2i(start, end)

func _loudness_overview() -> Array:
	var request := {} if _approve.is_valid() else {"from_ms": 0, "to_ms": _plan.duration_ms}
	var span := _audio_span(request)
	if span.y <= span.x:
		return []
	var window := maxi(4000, ceili(float(span.y - span.x) / 16.0))
	var report := AgentAudio.loudness(_chart, span, window, 0, 16)
	return report.get("items", []).map(func(row: Dictionary): return [row.time_ms, row.end_ms, row.rms_dbfs])

static func _requests_new_animation(brief: String) -> bool:
	var text := brief.to_lower()
	if ["不要动画", "不要制作动画", "不做动画", "不需要动画", "无需动画", "只加蒙版", "只调暗",
			"no animation", "do not animate"].any(func(phrase: String): return phrase in text):
		return false
	var action := RegEx.create_from_string(r"(制作|绘制|生成|设计|添加|加上|做|补上).{0,10}动画|动画一点都没有|(add|create|make|generate|design)\s+.{0,24}animation")
	return action.search(text) != null

func _render_audio_figure(arguments: Dictionary) -> Dictionary:
	if not _audio_spectrum.is_valid():
		return {"error": "用户未允许发送音频图。可以用 get_audio_loudness 读取数值。"}
	var kind: String = str(arguments.get("kind", "waveform"))
	if kind not in ["waveform", "spectrum"]:
		return {"error": "音频图类型应为 waveform 或 spectrum。"}
	var span := _audio_span(arguments, AgentAudio.MAX_FIGURE_MS)
	if span.y <= span.x or span.y - span.x > AgentAudio.MAX_FIGURE_MS:
		return {"error": "请选择有音频的时间范围，每张图最多 45 秒。"}
	if _frame_requests >= FRAME_REQUEST_LIMIT:
		return {"error": "本轮已达到图像查询次数上限。"}
	_frame_requests += 1
	if kind == "waveform":
		return AgentAudio.waveform(_chart, span)
	return await _audio_spectrum.call(span)

func _view_shape_asset(arguments: Dictionary) -> Dictionary:
	if not _animation or not _audio_spectrum.is_valid():
		return {"error": "请先启用图形预览授权。"}
	if _frame_requests >= FRAME_REQUEST_LIMIT:
		return {"error": "已达到图像查询次数上限。"}
	_frame_requests += 1
	return _animation.shapes.preview(str(arguments.get("shape_id", "")))

func _editor_state() -> Dictionary:
	var time := roundi(_chart.get_rt_render_time())
	var state := {"playhead_ms": time, "playhead": _chart.ruler_position(time),
		"selected_note_ids": _chart.selected_note_ids.slice(0, 128), "selected_event_ids": _chart.selected_event_ids.slice(0, 128),
		"range_ms": [roundi(_audio_selection.x), roundi(_audio_selection.y)] if _audio_selection.y > _audio_selection.x else []}
	var selection: Array[Dictionary] = []
	for id: int in _chart.selected_note_ids.slice(0, 8):
		if _plan.notes.has(id):
			var row: Dictionary = _plan.notes[id]
			selection.append({"id": id, "type": row.type, "lane": row.lane,
				"judgement": _chart.ruler_position(row.time_ms), "x": row.x, "y": row.y})
	state["selected_notes"] = selection
	if _editor_view.is_valid():
		state.merge(_editor_view.call(), true)
	return state

func _call_tool(name: String, arguments: Dictionary) -> Dictionary:
	if name == "get_editing_guide":
		return {"instructions": Guidance.EDITOR if _approve.is_valid() else Guidance.FULL}
	if not _edit_notes and name in ["add_notes", "move_notes", "resize_holds", "delete_notes", "set_positions", "seed_pattern", "set_note_lead_in", "set_hold_path", "scale_hold_paths"]:
		return {"error": "本次只制作动画。"}
	if not _animation and (name in Context.ANIMATION_TOOLS or name in ["get_animation_cues", "list_animation_layers", "get_cover", "add_animation_layer",
			"remove_animation_layer", "create_solid_mask", "set_mask_cue", "add_mask_reveal"]):
		return {"error": "本次未启用动画。"}
	var from_ms := _integer(arguments, "from_ms", 0, 0, _plan.duration_ms)
	var to_ms := _integer(arguments, "to_ms", _plan.duration_ms, from_ms, _plan.duration_ms)
	var offset := _integer(arguments, "offset", 0, 0, 60000)
	var limit := _integer(arguments, "limit", 64, 1, 128)
	var window_ms := _integer(arguments, "window_ms", 4000, 250, 16000)
	match name:
		"list_reference_charts":
			return References.list_references(str(arguments.get("query", "")).left(150), str(arguments.get("difficulty", "")).left(40), offset, mini(limit, 32))
		"query_reference_chart":
			return _reference_query(arguments)
		"get_reference_media":
			var media := References.media(str(arguments.get("id", "")), str(arguments.get("category", "")))
			if media.has("error"):
				return media
			return {"items": media.items.slice(offset, offset + limit), "offset": offset, "total": media.items.size()}
		"get_pitch":
			return _pitch_query(arguments, from_ms, to_ms, offset, mini(limit, 64))
		"scale_hold_paths":
			return _plan.scale_hold_paths(from_ms, to_ms, arguments.get("factor"), arguments.get("ids"))
		"get_editor_help":
			return _help.call(str(arguments.get("query", "")).left(150)) if _help.is_valid() else {"error": "此处没有打开软件教程。"}
		"reply":
			if not _approve.is_valid() or str(arguments.get("message", "")).strip_edges().is_empty():
				return {"error": "请指定要展示的回复。"}
			if _chat_has_changes():
				return {"error": "已有获得批准的草稿修改。请走 finish 提交，并用 summary 回复用户。"}
			return {"reply": str(arguments.message).left(4000)}
		"get_project_context": return Context.project(_chart, _plan, _music)
		"get_audio_info": return {"available": not _chart.audio_path.is_empty(), "filename": _chart.audio_path.get_file(),
			"format": _chart.audio_path.get_extension().to_lower(), "duration_ms": roundi(_chart.audio_duration_ms),
			"offset_ms": roundi(_chart.audio_delay_ms), "waveform_bucket_ms": _chart.audio_waveform_bucket_ms,
			"waveform_samples": _chart.audio_waveform.size()}
		"get_editor_state": return _editor_state()
		"locate_notes": return _plan.locate_notes(arguments)
		"get_chart_metadata": return _editor_edits.metadata()
		"set_chart_metadata": return _editor_edits.set_metadata(arguments)
		"get_tempo_map": return _editor_edits.tempo_map()
		"set_tempo_map": return _editor_edits.set_tempo_map(arguments)
		"list_text_events": return _editor_edits.text_events(from_ms, to_ms, offset, mini(limit, 32))
		"upsert_text_event": return _editor_edits.upsert_text(arguments)
		"delete_text_event": return _editor_edits.delete_text(arguments)
		"get_reference_grid": return _series(Context.reference_grid(_chart, _editor_edits.tempo_map().segments), from_ms, to_ms, offset, limit)
		"get_audio_features":
			var span := _audio_span(arguments)
			if span.y <= span.x:
				return {"error": "该时间范围没有音频。"}
			return Context.features(_chart, _music, span.x, span.y, window_ms, offset, mini(limit, 48))
		"get_audio_loudness":
			var span := _audio_span(arguments)
			if span.y <= span.x:
				return {"error": "该时间范围没有音频。"}
			return AgentAudio.loudness(_chart, span, _integer(arguments, "window_ms", 1000, 250, 16000), offset, mini(limit, 24))
		"get_sustain_candidates":
			return Context.sustain_candidates(_music.get("melody", []), from_ms, to_ms,
				_integer(arguments, "minimum_ms", int(_plan.profile.hold_ms), 500, 4000), offset, mini(limit, 48))
		"get_chart_statistics": return Context.statistics(_plan, from_ms, to_ms, window_ms, offset, mini(limit, 48))
		"list_chart_events": return _series(Context.chart_events(_chart), from_ms, to_ms, offset, limit)
		"list_note_paths": return Context.note_paths(_chart, _plan, from_ms, to_ms, offset, limit)
		"list_notes": return _plan.list_notes(from_ms, to_ms, offset, limit)
		"add_notes", "move_notes", "set_positions", "resize_holds", "set_note_lead_in", "set_hold_path":
			return _plan.edit(name, arguments.get("notes"))
		"delete_notes": return _plan.edit(name, arguments.get("ids"))
		"get_bpm":
			var report := _series(_music.get("tempo_curve", []), from_ms, to_ms, offset, limit)
			report["manual_bpm"] = _music.get("manual_bpm", 0)
			return report
		"get_melody": return _series(_music.get("melody", []), from_ms, to_ms, offset, limit)
		"get_emotions": return _emotion_series(_music.get("emotions", []), from_ms, to_ms, offset, limit)
		"estimate_mood": return _series(_moods, from_ms, to_ms, offset, limit)
		"get_beats":
			var kind: String = str(arguments.get("kind", "beats"))
			if kind not in ["beats", "downbeats", "onsets", "accents"]:
				return {"error": "kind 必须是 beats、downbeats、onsets 或 accents。"}
			return _series(_music.get(kind, []), from_ms, to_ms, offset, limit)
		"seed_pattern":
			var seed_value := _integer(arguments, "seed", 42, 0, 2147483647)
			var outcome: Dictionary = _plan.seed_pattern(_music.source, seed_value, from_ms, -1 if arguments.get("to_ms") == -1 else to_ms)
			if outcome.get("added", 0) > 0:
				var validation: Dictionary = _plan.check_conflicts()
				outcome.merge({"error_count": validation.error_count, "warning_count": validation.warning_count,
					"new_hit_chords": validation.new_hit_chords, "range_ms": [from_ms, to_ms]})
			return outcome
		"check_conflicts": return _plan.check_conflicts()
		"get_animation_cues": return _animation_cues(from_ms, to_ms, mini(limit, 24))
		"create_solid_mask": return _animation.create_solid_mask(arguments)
		"set_mask_cue": return _animation.set_mask_cue(arguments)
		"add_mask_reveal": return _animation.add_mask_reveal(arguments)
		"list_animation_layers": return _animation.list_layers()
		"get_cover": return _animation.get_artwork(arguments)
		"list_artwork": return {"items": _animation.artwork_catalog()}
		"set_project_artwork": return _animation.set_project_artwork(arguments)
		"set_artwork_cue": return _animation.set_artwork_cue(arguments)
		"create_shape_asset": return _animation.shapes.create(arguments)
		"list_shape_assets": return _animation.shapes.list_assets()
		"add_animation_layer": return _animation.add_layer(arguments)
		"update_animation_layer": return _animation.update_layer(arguments)
		"check_cover_contrast": return _animation.check_cover_contrast(arguments)
		"remove_animation_layer": return _animation.remove_layer(arguments)
		"finish":
			var chat_run := _approve.is_valid()
			if chat_run and not _chat_has_changes():
				return {"error": "没有已批准并执行的修改。请用 reply 回复。"}
			if (not chat_run and _edit_notes and _plan.edited.is_empty()) or (not _plan.edited.is_empty() and _plan.notes.is_empty()):
				return {"error": "草稿必须有实际修改，且谱面要有音符。"}
			if _animation and not chat_run:
				if not _animation.has_changes():
					return {"error": "本次已启用动画，请制作可见的动画。"}
				var unused: Array = _animation.unused_artwork_ids()
				if not unused.is_empty():
					return {"error": "请安排所有已选曲绘在合适的乐段作底图或动画图层。",
						"unused_artwork_ids": unused}
			if _animation and (_motion_requested or not chat_run) and not _animation.has_visible_motion():
				return {"error": "当前草稿只有调暗、切换图片或淡入淡出。请添加可见的图形移动、缩放、曲绘运镜或有效的蒙版揭示。"}
			return _validate_finish(arguments)
	return {"error": "未知制谱工具。"}

func _validate_finish(arguments: Dictionary) -> Dictionary:
	var report: Dictionary = _plan.check_conflicts()
	if report.error_count > 0:
		return {"error": "修正冲突后才能应用。", "conflicts": report}
	return {"finished": str(arguments.get("summary", "制谱完成。")).left(240)}

func _chat_has_changes() -> bool:
	return not _plan.edited.is_empty() or _editor_edits.has_changes() or (_animation != null and _animation.has_changes())

func _render_reference(name: String, arguments: Dictionary, run_id: int) -> Dictionary:
	if not _frame_capture.is_valid() and not _audio_spectrum.is_valid():
		return {"error": "用户未开启图片查看。"}
	if _frame_requests >= FRAME_REQUEST_LIMIT:
		return {"error": "已达到本轮图片查看次数上限。"}
	_frame_requests += 1
	var id := str(arguments.get("id", ""))
	if name == "view_reference_artwork":
		return ReferenceMedia.artwork(_chart, id, str(arguments.get("filename", "")))
	var time_ms := _integer(arguments, "time_ms", -1, -1, 86400000)
	if time_ms < 0:
		return {"error": "请提供有效的参考谱取帧时间。"}
	return await ReferenceMedia.frame(self, id, time_ms, func(): return _active and _run_id == run_id)

static func _reference_query(arguments: Dictionary) -> Dictionary:
	return References.query(str(arguments.get("id", "")).left(32), str(arguments.get("section", "summary")),
		_integer(arguments, "from_ms", 0, 0, 86400000), _integer(arguments, "to_ms", 86400000, 0, 86400000),
		_integer(arguments, "offset", 0, 0, 60000), _integer(arguments, "limit", 16, 1, 64))

func _pitch_query(arguments: Dictionary, from_ms: int, to_ms: int, offset: int, limit: int) -> Dictionary:
	var source := str(arguments.get("source", "essentia"))
	var detail := str(arguments.get("detail", "phrases"))
	if source not in ["essentia", "rmvpe"] or detail not in ["phrases", "detail"]:
		return {"error": "请选择音高来源和查询粒度。"}
	var items: Array = _music.get("vocal_pitch" if source == "rmvpe" else "melody", [])
	var result: Dictionary
	if detail == "phrases":
		result = Context.pitch_phrases(items, from_ms, to_ms, offset, limit)
		result["sustains"] = Context.sustain_candidates(items, from_ms, to_ms, 250, 0, 16).items
	else:
		result = _series(items, from_ms, to_ms, offset, limit)
	result.merge({"source": source, "detail": detail, "available": not items.is_empty()}, true)
	return result

func run_local_script(path: String) -> Dictionary:
	return await _run_rpy({}, _run_id, path)

func _run_rpy(arguments: Dictionary, run_id: int, trusted_path := "") -> Dictionary:
	var script: Variant = arguments.get("source", "")
	if trusted_path.is_empty() and (not script is String or script.is_empty() or script.to_utf8_buffer().size() > 32768):
		return {"error": "请提供不超过 32 KiB 的 .rpy 代码。"}
	var from_ms := _integer(arguments, "from_ms", 0, 0, _plan.duration_ms)
	var to_ms := _integer(arguments, "to_ms", _plan.duration_ms, from_ms, _plan.duration_ms)
	var references: Variant = arguments.get("references", [])
	if not references is Array or references.size() > 4:
		return {"error": "每次脚本至多包含四份参考查询。"}
	var documents := {}
	for query: Variant in references:
		if not query is Dictionary or not query.get("key") is String or query.key.length() > 48:
			return {"error": "每份参考查询都需要 key。"}
		documents[query.key] = _reference_query(query)
	var pitch := {}
	for source in ["essentia", "rmvpe"]:
		pitch[source] = {"phrases": _pitch_query({"source": source}, from_ms, to_ms, 0, 128).get("items", []),
			"detail": _pitch_query({"source": source, "detail": "detail"}, from_ms, to_ms, 0, 1024).get("items", [])}
	var baked_notes: Array = _plan.list_notes(from_ms, to_ms, 0, 18000).items
	var snapshot := {"notes": baked_notes, "project": Context.project(_chart, _plan, _music),
		"events": Context.chart_events(_chart), "tempo": _editor_edits.tempo_map(), "references": documents, "pitch": pitch,
		"artwork": _animation.artwork_catalog() if _animation else [],
		"animations": _animation.list_layers() if _animation else {}}
	var payload := {"mode": "restricted" if trusted_path.is_empty() else "trusted", "source": script,
		"script": trusted_path, "snapshot": snapshot}
	var result := await ScriptJobs.run(self, payload, func(): return _active and _run_id == run_id)
	if not _active or _run_id != run_id:
		return {"error": "脚本已取消。"}
	if result.has("error"):
		return result
	var actions: Variant = result.get("actions")
	if not actions is Array or actions.size() > 128:
		return {"error": "脚本操作列表无效。"}
	if actions.is_empty():
		result.erase("actions")
		return result
	var applied := _apply_script_actions(actions)
	result.erase("actions")
	if applied.has("error"):
		result.erase("result")
	result.merge(applied, true)
	return result

func _apply_script_actions(actions: Array) -> Dictionary:
	var state := {"notes": _plan.notes.duplicate(true), "edited": _plan.edited.duplicate(), "next_id": _plan.next_id}
	var fields := ["_metadata", "_tempo", "_text", "_next_event_id"]
	var visuals := ["layers", "masks", "mask_cues", "artwork_cues", "project_images"]
	var edits := _capture_fields(_editor_edits, fields)
	var animation := _capture_fields(_animation, visuals) if _animation else {}
	var shapes: Dictionary = _animation.shapes.assets.duplicate() if _animation else {}
	var results := []
	var error := ""
	var validation := {}
	for action: Variant in actions:
		if not action is Dictionary or action.get("name") not in WRITES or not action.get("arguments") is Dictionary:
			error = "脚本包含不支持的修改。"
			break
		var args: Variant = _resolve_script_refs(action.arguments, results)
		var response := _call_tool(action.name, args) if args is Dictionary else {"error": "脚本结果引用无效。"}
		if response.has("error"):
			error = str(response.error)
			break
		results.append(response)
	if error.is_empty():
		validation = _plan.check_conflicts()
		if validation.error_count == 0:
			return {"operation_count": actions.size(), "results": results, "warnings": validation.warning_count, "conflicts": validation}
		error = "脚本产生了阻止应用的谱面冲突，本批修改已回滚。"
	for field: String in state:
		_plan.set(field, state[field])
	for field: String in edits:
		_editor_edits.set(field, edits[field])
	if _animation:
		for field: String in animation:
			_animation.set(field, animation[field])
		_animation.shapes.assets = shapes
	var failure := {"error": error, "rolled_back": true, "operation_count": 0}
	if not validation.is_empty():
		failure["conflicts"] = validation
	return failure

static func _capture_fields(target: Object, fields: Array) -> Dictionary:
	var result := {}
	for field: String in fields:
		var value: Variant = target.get(field)
		result[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result

static func _resolve_script_refs(value: Variant, results: Array, depth := 0) -> Variant:
	if depth >= 24:
		return null
	if value is Dictionary:
		if value.has("$rpy_result"):
			var reference: Variant = value["$rpy_result"]
			if reference is Array and reference.size() == 2 and (reference[0] is float or reference[0] is int):
				var index := int(reference[0])
				return results[index].get(str(reference[1])) if index >= 0 and index < results.size() else null
			return null
		var result := {}
		for key: String in value:
			result[key] = _resolve_script_refs(value[key], results, depth + 1)
		return result
	if value is Array:
		return value.map(func(item: Variant): return _resolve_script_refs(item, results, depth + 1))
	return value

func draft_changes() -> Dictionary:
	var changes: Dictionary = _editor_edits.delta() if _editor_edits else {}
	if _animation:
		if not _animation.project_images.is_empty():
			changes["images"] = _animation.project_images
		if not _animation.artwork_cues.is_empty():
			changes["artwork_cues"] = _animation.artwork_cues.values()
	return changes

func _analyze_audio(arguments: Dictionary, run_id: int) -> Dictionary:
	if not _reanalyze.is_valid():
		return {"error": "当前没有可分析的音频。"}
	var engine := str(arguments.get("engine", "native"))
	var tasks: Variant = arguments.get("tasks")
	if not engine in ["native", "essentia", "music2emo", "rmvpe"] or not tasks is Array or tasks.is_empty() or tasks.size() > 6:
		return {"error": "选择 native、essentia、music2emo 或 rmvpe，并提供分析目标。"}
	var optional := {"music2emo": ["emotions"], "rmvpe": ["vocal_pitch"]}
	var allowed: Array = optional[engine] if optional.has(engine) else Context.Analysis.CAPTURE_TASKS[engine] + ["tempo"]
	var selected: Array = []
	for task: Variant in tasks:
		if not task is String or task not in allowed:
			return {"error": "该引擎不支持所选任务。", "available": allowed}
		if task not in selected:
			selected.append(task)
	var options := {"engine": engine, "tempo_engine": engine, "tasks": selected,
		"cache_only": _analysis_requests >= LOCAL_ANALYSIS_LIMIT,
		"progress": func(service: String, caption: String): tool_progress.emit(service, caption)}
	var raw: Dictionary = await _reanalyze.call(options)
	if not _active or run_id != _run_id:
		return {}
	if not raw.get("inferred_tasks", []).is_empty():
		_analysis_requests += 1
	var from_ms := _integer(arguments, "from_ms", 0, 0, _plan.duration_ms)
	var to_ms := _integer(arguments, "to_ms", _plan.duration_ms, from_ms, _plan.duration_ms)
	var offset := _integer(arguments, "offset", 0, 0, 60000)
	var limit := _integer(arguments, "limit", 32, 1, 64)
	var output := {"engine": engine, "task_errors": raw.get("task_errors", {}), "results": {}}
	if raw.has("error"):
		output["error"] = raw.error
	for task: String in selected:
		var key: String = Context.Analysis.RESULT_KEYS[task]
		if raw.has(key):
			var original := Array(raw[key])
			var shifted := _shift_analysis_series(original, roundi(_chart.audio_delay_ms))
			output.results[task] = _emotion_series(shifted, from_ms, to_ms, offset, limit) if task == "emotions" else _series(shifted, from_ms, to_ms, offset, limit)
			if not shifted.is_empty() and (_music.get(key, []).is_empty() or arguments.get("use_for_draft", false) == true):
				_music[key] = shifted
				if not _music.has("source"):
					_music["source"] = {}
				_music.source[key] = original
	return output

static func _shift_analysis_series(items: Array, delay_ms: int) -> Array:
	var shifted := []
	for item: Variant in items:
		if item is Dictionary:
			var sample: Dictionary = item.duplicate()
			sample.time_ms = roundi(sample.get("time_ms", 0)) + delay_ms
			if sample.has("end_ms"):
				sample.end_ms = roundi(sample.end_ms) + delay_ms
				sample.time_ms = maxi(sample.time_ms, 0)
				if sample.end_ms <= sample.time_ms:
					continue
			shifted.append(sample)
		else:
			shifted.append(roundi(item) + delay_ms)
	return shifted

func _emotion_series(items: Array, from_ms: int, to_ms: int, offset: int, limit: int) -> Dictionary:
	var matches := items.filter(func(item: Dictionary): return item.end_ms > from_ms and item.time_ms <= to_ms)
	return {"model": "Music2Emo", "available": not items.is_empty(), "items": matches.slice(offset, offset + limit),
		"total": matches.size(), "offset": offset}

func _animation_cues(from_ms: int, to_ms: int, limit: int) -> Dictionary:
	var markers: Array = _music.get("downbeats", [])
	var source := "小节重拍"
	if markers.is_empty():
		markers = _music.get("beats", [])
		source = "拍点"
	if markers.is_empty():
		markers = _moods.map(func(section: Dictionary): return section.time_ms)
		source = "段落响度"
	var cues: Array = []
	var next_anchor := from_ms
	for index in range(markers.bsearch(from_ms), markers.size()):
		var time := roundi(markers[index])
		if time > to_ms or cues.size() >= limit:
			break
		if time >= next_anchor:
			var cue := {"time_ms": time}
			for section: Dictionary in _moods:
				if time >= section.time_ms and time < section.to_ms:
					cue["intensity"] = section.estimate
					break
			cues.append(cue)
			next_anchor = time + 4200
	return {"anchors": cues, "first_ms": from_ms, "last_ms": to_ms, "source": source}

func _series(items: Array, from_ms: int, to_ms: int, offset: int, limit: int) -> Dictionary:
	var matches := items.filter(func(item: Variant):
		var time := float(item.get("time_ms", 0)) if item is Dictionary else float(item)
		return time >= from_ms and time <= to_ms)
	return {"items": matches.slice(offset, offset + limit), "total": matches.size(), "offset": offset}

static func _integer(arguments: Dictionary, key: String, fallback: int, minimum: int, maximum: int) -> int:
	var value: Variant = arguments.get(key, fallback)
	return roundi(clampf(float(value), minimum, maximum)) if (value is int or value is float) and is_finite(float(value)) else fallback

static func _usage_tokens(document: Variant) -> int:
	if not document is Dictionary or not document.get("usage") is Dictionary:
		return -1
	var usage: Dictionary = document.usage
	var total := _token_count(usage.get("total_tokens"))
	if total >= 0:
		return total
	var prompt := _token_count(usage.get("prompt_tokens"))
	var completion := _token_count(usage.get("completion_tokens"))
	return prompt + completion if prompt >= 0 and completion >= 0 else -1

static func _token_count(value: Variant) -> int:
	if (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 2147483647:
		return int(value)
	return -1

func _finish(success: bool, message: String) -> void:
	_active = false
	var edits := draft_changes() if success else {}
	_clear_state()
	completed.emit(success, message, edits)

func _finish_reply(message: String) -> void:
	_active = false
	_clear_state()
	replied.emit(message)

func _clear_state() -> void:
	_key = ""
	_waiting_retry = false
	_messages.clear()
	_plan = null
	_animation = null
	_motion_requested = false
	_editor_edits = null
	_chart = null
	_reanalyze = Callable()
	_approve = Callable()
	_review_commit = false
	_help = Callable()
	_import_audio = Callable()
	_frame_capture = Callable()
	_audio_spectrum = Callable()
	_audio_selection = Vector2(-1, -1)
	_visual_message_index = -1
	_music = {}
	_moods = []
