extends SceneTree

const Plan := preload("res://desktop/auto_chart_plan.gd")
const AnimationDraft := preload("res://desktop/agent_animation.gd")
const Frames := preload("res://desktop/agent_frames.gd")
const RenderPreview := preload("res://desktop/render_preview.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures += 1
		push_error(description)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	root.size = Vector2i(1170, 820)
	var desktop: Node = current_scene.desktop
	var sidebar: Node = desktop.sidebar
	var chart: Node = desktop.chart
	desktop._onboarding._chooser.hide()
	desktop._set_scale(1.25)
	_check(desktop.import_audio(args[0], false), "Load a project with the standard transparent cover")
	var first := _image("media-test-blue.png", Color("#2249ba"))
	var next := _image("media-test-orange--long-imported-image-name-1633864.png", Color("#e47b30"))
	_check(desktop._import_image(first, true) and desktop._import_image(next, false), "Import chart pictures")

	var event: int = chart.add_event(1, 800, 800, 0)
	chart.select_event(event)
	_check(sidebar.ev_image_path is OptionButton, "Bottom image event uses a project asset dropdown")
	var picker: OptionButton = sidebar.ev_image_path
	var selected := -1
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == next.get_file():
			selected = index
	_check(selected >= 0, "Imported artwork appears by name in the event dropdown")
	if selected >= 0:
		picker.select(selected)
		picker.item_selected.emit(selected)
		_check(chart.get_event_data(event).image_path == next.get_file(), "Selecting a picture saves its project-relative path")
		_check(is_equal_approx(chart.get_rt_render_time(), 800.0) and sidebar.ev_image_preview.texture != null,
			"Picking the event image seeks to the event and displays its thumbnail")
	var bad: int = chart.add_event(1, 900, 900, 0)
	chart.update_event_image_path(bad, "missing-test-image.png")
	var mask := _image("media-test-opaque-cover.png", Color.BLACK)
	_check(desktop._import_image(mask, false), "Import an explicitly opaque graphic")
	var cover: int = chart.add_event(0, 1200, 1200, 0)
	chart.select_event(cover)
	sidebar.ev_image_import.pressed.emit()
	_check(desktop._image_file.visible and desktop._image_event_target == cover, "Event UI opens the image import picker")
	desktop._image_file.hide()
	desktop._image_file.file_selected.emit(chart.resolve_full_path(mask.get_file()))
	_check(chart.get_event_data(cover).image_path == mask.get_file(), "Importing from the event assigns the new image directly")

	desktop._open_inspector_page("动画设置")
	await process_frame
	await process_frame
	var pane: Control = desktop._tabs.get_current_tab_control()
	var play: Control = sidebar._bg_btn_play_cur
	print("MEDIA_LAYOUT width=", pane.size.x, " play_end=", play.get_global_rect().end.x - pane.global_position.x)
	_check(play.get_global_rect().end.x <= pane.get_global_rect().end.x + 1, "Animation playback buttons fit the narrow inspector")
	desktop._open_inspector_page("动画键")
	await process_frame
	await process_frame
	pane = desktop._tabs.get_current_tab_control()
	play = sidebar._anim_rect_btn_play_cur
	_check(play.get_global_rect().end.x <= pane.get_global_rect().end.x + 1 and pane.has_node("AnimationScroll"),
		"Animation keys also fit with a vertically scrollable inspector")

	if DisplayServer.get_name() != "headless":
		await _test_pixels(chart)
	await _test_masks(desktop)
	desktop._set_background_track(true)
	chart.set_rt_pointer_time(4000)
	desktop._add_background_effect(false)
	_check(desktop._background_selection.get("lane", -1) == 1, "Darkening creates and selects a native mask switch")
	chart.set_rt_pointer_time(4500)
	desktop._add_background_effect(true)
	var clip: Dictionary = desktop._background_selection
	_check(clip.get("lane", -1) == 2 and clip.end > clip.start + 500, "Reveal segment uses its real animation duration")
	desktop._loop_background_clip()
	_check(chart.rt_playing and desktop.grid.loop_enabled and desktop._loop_range.x == clip.start,
		"Selected background segment loops in game view")
	print("MEDIA_ANIMATION_SMOKE failures=", failures)
	quit(1 if failures else 0)

func _image(file: String, color: Color) -> String:
	var image := Image.create_empty(96, 54, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var path := ProjectSettings.globalize_path("user://" + file)
	image.save_png(path)
	return path

func _test_pixels(chart: Node) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 180)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var preview: Control = load("res://main/preview_area.gd").new()
	preview.capture_mode = true
	preview.size = Vector2(320, 180)
	preview.set_chart_data(chart)
	viewport.add_child(preview)
	chart.final_preview_mode = true
	await process_frame
	chart.set_rt_pointer_time(700)
	preview.refresh_from_tab()
	await RenderingServer.frame_post_draw
	var before := viewport.get_texture().get_image().get_pixel(160, 90)
	chart.set_rt_pointer_time(1000)
	preview.refresh_from_tab()
	await RenderingServer.frame_post_draw
	var after := viewport.get_texture().get_image().get_pixel(160, 90)
	print("MEDIA_PIXEL before=", before.to_html(), " after=", after.to_html())
	_check(before.b > 0.65 and after.r > 0.7 and after.b < 0.35, "Rendered game background changes after the event")
	var desktop_frame := viewport.get_texture().get_image().get_data()
	var cli_scene := RenderPreview.mount(root, chart, Vector2i(320, 180))
	await process_frame
	var cli_frame := await RenderPreview.frame(cli_scene, 1000.0)
	_check(cli_frame.get_data() == desktop_frame, "Desktop preview and CLI render the same pixels at the same chart time")
	cli_scene.viewport.queue_free()
	chart.set_rt_pointer_time(1300)
	preview.refresh_from_tab()
	await RenderingServer.frame_post_draw
	var opaque := viewport.get_texture().get_image().get_pixel(160, 90)
	_check(opaque.r < 0.01 and opaque.b < 0.01, "An explicitly opaque cover still hides the bottom image")
	chart.set_rt_pointer_time(700)
	preview.refresh_from_tab()
	await RenderingServer.frame_post_draw
	var rewound := viewport.get_texture().get_image().get_pixel(160, 90)
	_check(rewound.b > 0.65, "Seeking backward restores base artwork")
	viewport.queue_free()

func _test_masks(desktop: Node) -> void:
	var chart: Node = desktop.chart
	var plan := Plan.new(chart)
	var art := {"path": chart.preview_bg_image_path, "size": Vector2(96, 54)}
	var draft := AnimationDraft.new(chart, plan.duration_ms, [art])
	_check(draft.create_solid_mask({"color": "../x"}).has("error"), "Mask rejects invalid colors")
	var dark := draft.create_solid_mask({"color": "#131b2a", "opacity": 1.0})
	var tint := draft.create_solid_mask({"color": "#70172b", "opacity": 0.45})
	var unused := draft.create_solid_mask({"color": "#123456", "opacity": 0.5})
	_check(draft.create_solid_mask({"color": "#131B2A"}).mask_id == dark.mask_id, "Identical mask colors reuse the same asset")
	_check(draft.set_mask_cue({"mask_id": dark.mask_id, "time_ms": 1200}).has("error"), "Existing cover event remains protected")
	draft.set_mask_cue({"mask_id": dark.mask_id, "time_ms": 1500, "use_cover_artwork": true})
	draft.set_mask_cue({"mask_id": tint.mask_id, "time_ms": 5700})
	var reveal := draft.add_mask_reveal({"time_ms": 2400, "duration_ms": 2000, "radius_px": 400})
	_check(reveal.has("slot") and draft.unused_artwork_ids().is_empty(), "Cue and reveal use the authorized artwork")
	_check(not FileAccess.file_exists(chart.resolve_full_path(dark.path)), "A staged mask is not published early")
	var original_count: int = chart.events.size()
	if DisplayServer.get_name() != "headless":
		var picture := await Frames.capture(desktop, chart, plan, draft, [1900, 3400, 4600, 6100])
		_check(picture.get("columns") == 3 and picture.get("rows") == 2, "Draft renders a four-frame contact sheet in order")
		if picture.has("_preview_image"):
			var image := Image.new()
			image.load_jpg_from_buffer(Marshalls.base64_to_raw(picture._preview_image.get_slice(",", 1)))
			if not image.is_empty():
				var hidden := image.get_pixel(160, 90)
				var revealed := image.get_pixel(480, 90)
				var closed := image.get_pixel(800, 90)
				var tinted := image.get_pixel(160, 270)
				print("MASK_DRAFT_FRAMES ", [hidden.to_html(), revealed.to_html(), closed.to_html(), tinted.to_html()])
				_check(hidden.b < 0.25 and revealed.b > 0.65 and closed.b < 0.25 and tinted.b > 0.30,
					"Rendered frames show the mask closing, opening onto the artwork, and changing tint")
			else:
				_check(false, "Montage is a valid JPEG")
		_check(chart.events.size() == original_count and not FileAccess.file_exists(chart.resolve_full_path(dark.path)),
			"Draft preview leaves the live project and asset directory unchanged")
		var single := await Frames.capture(desktop, chart, plan, draft, [3400])
		_check(single.get("columns") == 1 and single.get("frame_size") == [320, 180], "A single requested frame renders without padding")
	_check(draft.save_assets(desktop._get_or_create_root()) == OK, "Referenced PNGs materialize on commit")
	_check(draft.save_assets(desktop._get_or_create_root()) == OK, "Mask output is reusable across submissions")
	_check(not FileAccess.file_exists(chart.resolve_full_path(unused.path)), "Unreferenced matte is left in the draft")
	var texture: Image = chart.resolve_image(tint.path)
	_check(texture and absf(texture.get_pixel(0, 0).a - 0.45) < 0.01, "PNG retains the requested alpha")
	chart.apply_automatic_notes({}, {}, draft.layers.values(), draft.mask_cues.values())
	var exported: Dictionary = chart.to_export_dict()
	_check(exported.data.any(func(event: Dictionary): return event.type == "setCover" and event.imagePath == dark.path),
		"Mask switches serialize as standard cover events")
	_check(exported.anim_rect_slots[reveal.slot].any(func(event: Dictionary): return event.has("bgAnim")),
		"Reveal serializes with a native background animation mount")
	desktop.sidebar._save_to_current_file()
	var zip := "user://generated-masks-smoke.zip"
	_check(chart.export_zip_to(zip), "Export a playable archive with referenced masks")
	var reader := ZIPReader.new()
	if reader.open(zip) == OK:
		_check(reader.file_exists(dark.path) and reader.file_exists(tint.path) and reader.file_exists("chart.json"),
			"Chart JSON and both PNG assets are in the archive")
		reader.close()
	else:
		_check(false, "Generated chart ZIP opens")
	chart.undo()
	_check(chart.events.size() == original_count and not chart.is_anim_rect_slot_edited(reveal.slot), "One undo removes generated cues and reveal")
