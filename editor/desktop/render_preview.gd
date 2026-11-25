extends RefCounted

const Chart := preload("res://main/chart_data.gd")

static func mount(owner: Node, chart: Node, resolution: Vector2i) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = resolution
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	owner.add_child(viewport)
	var snapshot := Chart.new()
	viewport.add_child(snapshot)
	snapshot._restore_snapshot(chart._snapshot_notes())
	snapshot.selected_note_ids.clear()
	snapshot.selected_event_ids.clear()
	snapshot.track_count = chart.track_count
	snapshot._root_dir = chart._root_dir
	snapshot.has_root_dir = chart.has_root_dir
	snapshot.restrict_imported_assets = chart.restrict_imported_assets
	snapshot.preview_bg_image_path = chart.preview_bg_image_path
	snapshot.preview_mask_image_path = chart.preview_mask_image_path
	snapshot.audio_duration_ms = chart.audio_duration_ms
	snapshot.audio_delay_ms = chart.audio_delay_ms
	snapshot.final_preview_mode = true
	var view: Control = load("res://main/preview_area.gd").new()
	view.capture_mode = true
	view.size = Vector2(resolution)
	view.set_chart_data(snapshot)
	viewport.add_child(view)
	return {"viewport": viewport, "chart": snapshot, "view": view}

static func prepare_frame(scene: Dictionary, time_ms: float) -> void:
	scene.chart.set_rt_pointer_time(time_ms)
	scene.view.refresh_from_tab()
	scene.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

static func frame(scene: Dictionary, time_ms: float) -> Image:
	prepare_frame(scene, time_ms)
	await RenderingServer.frame_post_draw
	return scene.viewport.get_texture().get_image()
