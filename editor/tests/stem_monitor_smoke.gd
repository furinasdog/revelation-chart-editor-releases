extends SceneTree

const Cache := preload("res://desktop/stem_cache.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, description: String) -> void:
	if not ok:
		push_error(description)
		failures += 1

func _write_wav(path: String, value: int) -> void:
	var pcm := PackedByteArray()
	pcm.resize(44100 * 4 * 4)
	pcm.fill(value)
	pcm.encode_u64(0, Time.get_ticks_usec())
	var stream := AudioStreamWAV.new()
	stream.stereo = true
	stream.mix_rate = 44100
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.data = pcm
	_check(stream.save_to_wav(path) == OK, "Wrote WAV fixture")

func _run() -> void:
	if change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var desk: Node = current_scene.desktop
	var chart: Node = current_scene.chart_data
	var panel: Control = desk._stem_monitor
	var service: Node = desk._stem_separation
	var picker: OptionButton = panel._selection
	var player: AudioStreamPlayer = desk.preview._rt_audio
	root.size = Vector2i(1024, 650)
	desk._set_scale(1.25)
	desk.preferences.upper_split = 0.36
	desk.apply_layout()
	await process_frame
	await process_frame
	var page: ScrollContainer = desk._analysis_panel
	page.ensure_control_visible(panel._action)
	await process_frame
	_check(page.get_global_rect().grow(1).encloses(panel._action.get_global_rect()) and page.get_global_rect().end.y <= desk._track_bar.get_global_rect().position.y, "Short inspector can scroll to separation without covering transport")
	var choices: ScrollContainer = desk._analysis_panel._choices.beat.get_parent().get_parent().get_parent()
	_check(choices.size.y >= desk._analysis_panel._choices.beat.size.y, "Capture choices retain a visible row")
	var folder := ProjectSettings.globalize_path("user://monitor-test-%s" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var original := folder.path_join("original.wav")
	var replacement := folder.path_join("replacement.wav")
	_write_wav(original, 7)
	_write_wav(replacement, 8)
	_check(picker.selected == 0 and panel._action.disabled, "Empty document defaults to full audio")
	_check(desk.import_audio(original, false, false), "Import original audio")
	_check(service.state == "idle" and picker.is_item_disabled(1) and not panel._action.disabled, "Import waits for an explicit separation request")
	_check(not is_instance_valid(desk._model_help) or not desk._model_help.visible, "Import leaves model help closed")
	if not player or service._cache_dir.is_empty():
		_check(false, "Preview audio player and source cache mounted")
		quit(1)
		return
	var installed_dir := OS.get_environment("AUTOREVELATION_HTDEMUCS_MODELS")
	OS.set_environment("AUTOREVELATION_HTDEMUCS_MODELS", folder)
	panel._action.pressed.emit()
	_check(service.state == "missing_model" and is_instance_valid(desk._model_help) and desk._model_help.visible and desk._help_model == "htdemucs", "Explicit separation opens model help for HTDemucs")
	if is_instance_valid(desk._model_help):
		desk._model_help.hide()
	OS.set_environment("AUTOREVELATION_HTDEMUCS_MODELS", installed_dir)
	var full: AudioStream = chart.loaded_audio_stream
	var cache: String = service._cache_dir
	if DirAccess.dir_exists_absolute(cache):
		_check(false, "Fixture cache directory must be new")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(cache)
	for i in Cache.STEMS.size():
		_write_wav(cache.path_join(Cache.STEMS[i] + ".wav"), 21 + i)
		picker.get_popup().about_to_popup.emit()
		for index in range(1, 5):
			_check(picker.is_item_disabled(index) == (i < 3), "Only all four valid cached streams unlock listening")
	_check(service.state == "ready" and picker.selected == 0, "Ready cache retains the full mix")
	desk._play_at(700)
	await create_timer(0.12).timeout
	_check(player.playing and player.stream == full, "Timeline plays the original stream")
	for index in range(1, 5):
		var before := player.get_playback_position()
		picker.item_selected.emit(index)
		await create_timer(0.045).timeout
		var expected := AudioStreamWAV.load_from_file(service.stem_path(Cache.STEMS[index - 1]))
		_check(player.playing and player.stream == chart.monitor_audio_stream and player.stream.data == expected.data, "Timeline plays the selected WAV " + Cache.STEMS[index - 1])
		_check(absf(player.get_playback_position() - before) < 0.3, "Live track switch keeps playback time")
	_check(chart.loaded_audio_stream == full and chart.to_export_dict().basic.music == chart.audio_path, "Monitoring leaves the saved source intact")
	var archive := folder.path_join("chart.zip")
	_check(chart.export_zip_to(archive), "Export a chart while listening to a stem")
	var reader := ZIPReader.new()
	_check(reader.open(archive) == OK and reader.read_file(chart.audio_path) == FileAccess.get_file_as_bytes(original), "ZIP includes the original audio bytes")
	for stem: String in Cache.STEMS:
		_check(stem + ".wav" not in reader.get_files(), "ZIP omits transient stem " + stem)
	reader.close()

	desk._play_button.pressed.emit()
	var paused: float = chart.rt_play_time
	picker.item_selected.emit(2)
	await create_timer(0.08).timeout
	_check(not player.playing and not chart.rt_playing and is_equal_approx(chart.rt_play_time, paused), "Changing stems while paused preserves the playhead")
	desk._play_button.pressed.emit()
	await create_timer(0.1).timeout
	_check(player.playing and absf(player.get_playback_position() - paused / 1000.0) < 0.3, "Resume continues on the selected stem")
	desk._play_button.pressed.emit()
	desk.grid._apply_pointer_from_x(desk.grid._remark_x(2100))
	desk._play_button.pressed.emit()
	await create_timer(0.09).timeout
	_check(player.stream == chart.monitor_audio_stream and absf(player.get_playback_position() - 2.1) < 0.3, "Dragging the timeline pointer seeks the selected stem")
	desk._set_loop_range(Vector2(350, 700))
	desk._loop_switch.button_pressed = true
	await create_timer(0.16).timeout
	_check(player.playing and player.stream == chart.monitor_audio_stream and player.get_playback_position() < 0.75, "Loop seeks on the selected stem")
	desk._loop_switch.button_pressed = false
	picker.item_selected.emit(0)
	_check(player.playing and player.stream == full and chart.monitor_audio_stream == null, "Reselect full audio during playback")
	chart.reset_rt_playback()

	var sidebar_player: AudioStreamPlayer = desk.sidebar._audio_player
	chart.set_rt_pointer_time(900)
	desk.sidebar._on_audio_play_from_pointer()
	await create_timer(0.08).timeout
	desk.sidebar._on_audio_play_pause()
	picker.item_selected.emit(1)
	_check(sidebar_player.stream_paused and sidebar_player.stream == chart.monitor_audio_stream, "Audio pane preserves pause across a stem change")
	desk.sidebar._on_audio_play_pause()
	await create_timer(0.08).timeout
	_check(sidebar_player.playing and absf(sidebar_player.get_playback_position() - 1.0) < 0.32, "Audio pane resumes at the previous time")
	desk.sidebar._on_audio_slider_changed(2250)
	await create_timer(0.08).timeout
	_check(absf(sidebar_player.get_playback_position() - 2.25) < 0.3, "Audio pane slider seeks on a stem")
	desk.sidebar._on_audio_play_pause()
	_check(desk.import_audio(replacement, false, false), "Replace imported song")
	_check(picker.selected == 0 and picker.is_item_disabled(1) and chart.monitor_audio_stream == null and service.state == "idle", "Changing songs clears stem selection and availability")
	desk._play_at(100)
	_check(player.stream == chart.loaded_audio_stream and player.stream != full, "The replacement song starts on its own full mix")
	chart.reset_rt_playback()
	_check(desk.import_audio(original, false, false), "Reopen original audio")
	_check(picker.selected == 0 and not picker.is_item_disabled(1), "Reopening a cached song starts on the full mix")
	picker.item_selected.emit(2)
	var song_path: String = ProjectSettings.globalize_path(chart.resolve_audio_path(chart.audio_path))
	DirAccess.copy_absolute(replacement, song_path)
	_check(desk.sidebar._load_audio_file(chart.audio_path), "Reload a changed song at the same filename")
	_check(service._cache_dir != cache and picker.selected == 0 and picker.is_item_disabled(1) and chart.monitor_audio_stream == null, "Overwriting the source invalidates its previous stems")
	desk._play_at(400)
	var replaced: AudioStream = player.stream
	DirAccess.copy_absolute(original, song_path)
	_check(desk.sidebar._load_audio_file(chart.audio_path) and service._cache_dir == cache, "Reloading original bytes resolves their own cache")
	_check(player.playing and player.stream == chart.loaded_audio_stream and player.stream != replaced, "Reload during full-mix playback switches the actual player to the new recording")
	chart.reset_rt_playback()
	picker.item_selected.emit(3)
	DirAccess.remove_absolute(cache.path_join("other.wav"))
	picker.get_popup().about_to_popup.emit()
	_check(service.state == "idle" and picker.selected == 0 and picker.is_item_disabled(1) and chart.monitor_audio_stream == null, "An incomplete cache falls back to the full mix")
	Cache.remove_work_directory(cache)
	if "--native" in OS.get_cmdline_user_args():
		await _check_separation_actions(desk, folder)
	Cache.remove_work_directory(folder)
	if not failures:
		print("STEM_MONITOR_OK")
	quit(1 if failures else 0)

func _check_separation_actions(desk: Node, folder: String) -> void:
	var panel: Control = desk._stem_monitor
	var service: Node = desk._stem_separation
	var saved_ffmpeg: String = desk.preferences.ffmpeg_path
	desk.preferences.ffmpeg_path = folder.path_join("missing.exe")
	panel._action.pressed.emit()
	_check(service.state == "running" and panel._action.text == "取消分轨" and panel._progress.visible, "Starting launches a job with progress and cancellation")
	await _wait_for_job(service)
	_check(service.state == "error" and panel._action.text == "重试分轨", "Decode failure offers a retry")
	desk.preferences.ffmpeg_path = saved_ffmpeg
	panel._action.pressed.emit()
	var work: String = service._work
	panel._action.pressed.emit()
	_check(service.state == "idle" and not panel._progress.visible and not DirAccess.dir_exists_absolute(work), "Cancel removes the private job and permits retry")
	panel._action.pressed.emit()
	await _wait_for_job(service)
	_check(service.state == "ready" and panel._selection.selected == 0 and not panel._selection.is_item_disabled(4), "A completed native job unlocks all stems and retains the original")
	if service.state == "ready":
		panel._selection.item_selected.emit(2)
		desk._play_at(300)
		await create_timer(0.08).timeout
		_check(desk.preview._rt_audio.playing and desk.preview._rt_audio.stream == desk.chart.monitor_audio_stream, "Listen to a freshly separated drum track")
		desk.chart.reset_rt_playback()
		panel._selection.item_selected.emit(0)
		Cache.remove_work_directory(service._cache_dir)

func _wait_for_job(service: Node) -> void:
	var deadline := Time.get_ticks_msec() + 90000
	while service.state == "running" and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	_check(service.state != "running", "Separation returned before the deadline")
	if service.state == "running":
		service.cancel()
