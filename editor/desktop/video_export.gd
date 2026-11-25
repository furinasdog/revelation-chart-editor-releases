extends Node

const RenderPreview := preload("res://desktop/render_preview.gd")
const HitFeedback := preload("res://main/hit_feedback.gd")
const FrameBatch := preload("res://desktop/video_frame_batch.gd")
const RESOLUTION := Vector2i(1920, 1080)
const FRAME_RATE := 60
const SIZES := [Vector2i(1280, 720), RESOLUTION, Vector2i(2560, 1440), Vector2i(3840, 2160)]
const RATES := [24, 25, 30, 50, FRAME_RATE, 120]
const QUALITIES := [23, 18, 15]

signal progress(done: int, total: int)
signal stage_changed(message: String)
signal finished(error: String)

var busy := false
var _cancel := false
var _encoder_pid := -1
var _partial_path := ""
var _hit_audio_path := ""
var _batch: FrameBatch

func cancel() -> void:
	_cancel = true
	if _encoder_pid > 0 and OS.is_process_running(_encoder_pid):
		OS.kill(_encoder_pid)

static func duration_seconds(chart: Node) -> float:
	var end := maxf((float(chart.audio_duration_ms) + chart.audio_delay_ms) / 1000.0, chart.latest_content_time_ms() / 1000.0)
	var tail := HitFeedback.perfect_frames().size() / HitFeedback.FRAME_RATE
	for note in chart.notes.values():
		end = maxf(end, HitFeedback.judgement_ms(note) / 1000.0 + tail)
	return end

func render(chart: Node, ffmpeg: String, destination: String, from_ms := 0, to_ms := -1, options := {}) -> void:
	if busy:
		return
	var duration_ms := float(chart.audio_duration_ms)
	if duration_ms <= 0:
		finished.emit("请先导入音频。")
		return
	if ffmpeg.is_empty():
		finished.emit("找不到音频解码程序。")
		return
	if DisplayServer.get_name() == "headless":
		finished.emit("视频导出需要启用图形渲染。")
		return
	var resolution: Vector2i = options.get("size", RESOLUTION)
	var fps := int(options.get("fps", FRAME_RATE))
	var quality := int(options.get("quality", 18))
	if resolution not in SIZES or fps not in RATES or quality not in QUALITIES:
		finished.emit("不支持所选的视频规格。")
		return

	busy = true
	_cancel = false
	var audio: String = ProjectSettings.globalize_path(chart.resolve_audio_path(chart.audio_path))
	var delay := float(chart.audio_delay_ms) / 1000.0
	var end_time := maxf(duration_seconds(chart), 1.0 / fps)
	var start_time := maxf(0.0, from_ms / 1000.0)
	var stop_time := minf(end_time, to_ms / 1000.0) if to_ms >= 0 else end_time
	if stop_time <= start_time:
		busy = false
		finished.emit("视频时间范围无效。")
		return
	var span := stop_time - start_time
	var frames := ceili(span * fps - 0.0000001)
	frames = maxi(frames, 1)
	var job := "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var partial := destination.get_base_dir().path_join(".render-%s.mp4" % job)
	if options.get("nvenc", false):
		stage_changed.emit("正在检测 NVIDIA 硬件编码器…")
		if not await _check_nvenc(ffmpeg, resolution, quality):
			busy = false
			finished.emit("已取消视频导出。" if _cancel else "NVENC 无法用于所选规格。请检查 NVIDIA 驱动、FFmpeg，或在渲染设置中关闭硬件编码。")
			return
	stage_changed.emit("正在准备音轨…")
	if options.get("hits", true) and not chart.notes.is_empty() and Global.hit_sound_volume > 0.0:
		_hit_audio_path = ProjectSettings.globalize_path("user://revelation-video-hits-%s.f32" % job)
		if HitFeedback.write_audio(chart.notes, span, Global.hit_sound_volume, _hit_audio_path, start_time) != OK:
			_discard_hit_audio()
			busy = false
			finished.emit("无法生成打击音效音轨。请检查用户数据目录的写入权限和剩余空间。")
			return
	var arguments := _arguments(audio, delay - start_time, span, partial, _hit_audio_path, options)
	var encoder := OS.execute_with_pipe(ffmpeg, arguments)
	if encoder.is_empty():
		_discard_hit_audio()
		busy = false
		finished.emit("无法启动视频编码。")
		return
	var stream: FileAccess = encoder.get("stdio")
	var pid := int(encoder.get("pid", -1))
	if stream == null or pid <= 0:
		if pid > 0:
			OS.kill(pid)
		_discard_hit_audio()
		busy = false
		finished.emit("无法建立视频编码通道。")
		return
	_encoder_pid = pid
	_partial_path = partial

	stage_changed.emit("正在渲染 %d × %d · %d fps" % [resolution.x, resolution.y, fps])
	var scenes := [RenderPreview.mount(self, chart, resolution)]
	var parallel := bool(options.get("parallel", false))
	if parallel and frames > 1:
		scenes.append(RenderPreview.mount(self, chart, resolution))
	await get_tree().process_frame
	var error := ""
	for index in range(0, frames, scenes.size()):
		if _cancel:
			break
		var count := mini(scenes.size(), frames - index)
		for offset in count:
			RenderPreview.prepare_frame(scenes[offset], start_time * 1000.0 + (index + offset) * 1000.0 / fps)
		await RenderingServer.frame_post_draw
		var images: Array[Image] = []
		for offset in count:
			var image: Image = scenes[offset].viewport.get_texture().get_image()
			if image == null or image.is_empty():
				error = "无法读取预览帧。"
				break
			images.append(image)
		if not error.is_empty() or _cancel:
			break
		if parallel:
			if not await _finish_batch():
				error = "视频编码提前结束。请检查目标磁盘和编码程序。"
				break
			if _cancel:
				break
			_batch = FrameBatch.new()
			_batch.start(images, stream)
		else:
			images[0].convert(Image.FORMAT_RGB8)
			if not stream.store_buffer(images[0].get_data()):
				error = "视频编码提前结束。请检查目标磁盘和编码程序。"
				break
		progress.emit(index + count, frames)
	for scene in scenes:
		scene.viewport.queue_free()

	if _cancel or not error.is_empty():
		if OS.is_process_running(pid):
			OS.kill(pid)
	if not await _finish_batch() and error.is_empty():
		error = "视频编码提前结束。请检查目标磁盘和编码程序。"
	stream.close()
	if not _cancel and error.is_empty():
		stage_changed.emit("正在写入 MP4 文件…")
	var timeout := Time.get_ticks_msec() + 30000
	while OS.is_process_running(pid) and not _cancel and Time.get_ticks_msec() < timeout:
		await get_tree().process_frame
	if OS.is_process_running(pid):
		OS.kill(pid)
		if not _cancel and error.is_empty():
			error = "视频编码未能完成。"
	elif not _cancel and error.is_empty():
		if OS.get_process_exit_code(pid) != 0 or not FileAccess.file_exists(partial):
			error = "无法完成视频编码。请检查音频和目标目录。"
		elif not options.get("replace", true) and FileAccess.file_exists(destination):
			error = "渲染期间出现了同名文件。请选择其他文件名。"
		elif DirAccess.rename_absolute(partial, destination) != OK:
			error = "无法保存视频。请检查目标文件是否正被占用。"
	if FileAccess.file_exists(partial):
		DirAccess.remove_absolute(partial)
	_encoder_pid = -1
	_partial_path = ""
	_discard_hit_audio()
	busy = false
	finished.emit("已取消视频导出。" if _cancel else error)

func _finish_batch() -> bool:
	if _batch == null:
		return true
	while _batch.pending():
		await get_tree().process_frame
	var ok := _batch.join()
	_batch = null
	return ok

func _check_nvenc(ffmpeg: String, resolution: Vector2i, quality: int) -> bool:
	var args := PackedStringArray(["-hide_banner", "-loglevel", "quiet", "-nostdin", "-f", "lavfi", "-i",
		"color=s=%dx%d" % [resolution.x, resolution.y], "-frames:v", "1"])
	args.append_array(_codec(true, quality))
	args.append_array(["-f", "null", "-"])
	_encoder_pid = OS.create_process(ffmpeg, args)
	if _encoder_pid <= 0:
		return false
	var deadline := Time.get_ticks_msec() + 20000
	while OS.is_process_running(_encoder_pid) and not _cancel and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var success := not OS.is_process_running(_encoder_pid) and OS.get_process_exit_code(_encoder_pid) == 0
	if OS.is_process_running(_encoder_pid):
		OS.kill(_encoder_pid)
	_encoder_pid = -1
	return success and not _cancel

func _exit_tree() -> void:
	if _encoder_pid > 0 and OS.is_process_running(_encoder_pid):
		OS.kill(_encoder_pid)
	if _batch:
		_batch.join()
		_batch = null
	if not _partial_path.is_empty() and FileAccess.file_exists(_partial_path):
		DirAccess.remove_absolute(_partial_path)
	_discard_hit_audio()

func _discard_hit_audio() -> void:
	if not _hit_audio_path.is_empty():
		DirAccess.remove_absolute(_hit_audio_path)
		_hit_audio_path = ""

static func _codec(nvenc: bool, quality: int) -> PackedStringArray:
	if nvenc:
		return PackedStringArray(["-c:v", "h264_nvenc", "-pix_fmt", "yuv420p", "-preset", "p4", "-rc", "vbr", "-cq", str(quality), "-b:v", "0"])
	return PackedStringArray(["-c:v", "libx264", "-preset", "veryfast", "-crf", str(quality), "-pix_fmt", "yuv420p"])

func _arguments(audio: String, delay: float, duration: float, destination: String, hit_audio := "", options := {}) -> PackedStringArray:
	var size: Vector2i = options.get("size", RESOLUTION)
	var arguments := PackedStringArray([
		"-hide_banner", "-loglevel", "quiet", "-nostdin", "-y",
		"-f", "rawvideo", "-pixel_format", "rgb24",
		"-video_size", "%dx%d" % [size.x, size.y],
		"-framerate", str(options.get("fps", FRAME_RATE)), "-i", "pipe:0",
	])
	if hit_audio.is_empty():
		if delay > 0:
			arguments.append_array(["-itsoffset", str(delay)])
		elif delay < 0:
			arguments.append_array(["-ss", str(-delay)])
	arguments.append_array(["-protocol_whitelist", "file", "-i", audio])
	if hit_audio.is_empty():
		arguments.append_array(["-map", "0:v:0", "-map", "1:a:0"])
	else:
		var rate := HitFeedback.SAMPLE_RATE
		var alignment := ""
		var shift := roundi(delay * rate)
		if shift > 0:
			alignment = ",adelay=%dS:all=1" % shift
		elif shift < 0:
			alignment = ",atrim=start_sample=%d,asetpts=PTS-STARTPTS" % -shift
		var mix := "[1:a]aresample=%d,aformat=channel_layouts=stereo%s[music];" % [rate, alignment]
		mix += "[music][2:a]amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.98:level=false:latency=true[mix]"
		arguments.append_array(["-f", "f32le", "-ar", str(rate), "-ac", "2", "-i", hit_audio,
			"-filter_complex", mix, "-map", "0:v:0", "-map", "[mix]"])
	arguments.append_array(_codec(options.get("nvenc", false), options.get("quality", 18)))
	arguments.append_array([
		"-t", str(duration), "-c:a", "aac", "-b:a", "256k",
		"-movflags", "+faststart", destination,
	])
	return arguments
