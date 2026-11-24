extends Node

const RenderPreview := preload("res://desktop/render_preview.gd")
const HitFeedback := preload("res://main/hit_feedback.gd")
const RESOLUTION := Vector2i(1920, 1080)
const FRAME_RATE := 60

signal progress(done: int, total: int)
signal finished(error: String)

var busy := false
var _cancel := false
var _encoder_pid := -1
var _partial_path := ""
var _hit_audio_path := ""

func cancel() -> void:
	_cancel = true

func render(chart: Node, ffmpeg: String, destination: String, from_ms := 0, to_ms := -1) -> void:
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

	busy = true
	_cancel = false
	var audio: String = ProjectSettings.globalize_path(chart.resolve_audio_path(chart.audio_path))
	var delay := float(chart.audio_delay_ms) / 1000.0
	var end_time := maxf(maxf(duration_ms / 1000.0 + delay, chart.latest_content_time_ms() / 1000.0), 1.0 / FRAME_RATE)
	var effect_tail := HitFeedback.perfect_frames().size() / HitFeedback.FRAME_RATE
	for note in chart.notes.values():
		end_time = maxf(end_time, HitFeedback.judgement_ms(note) / 1000.0 + effect_tail)
	var start_time := maxf(0.0, from_ms / 1000.0)
	var stop_time := minf(end_time, to_ms / 1000.0) if to_ms >= 0 else end_time
	if stop_time <= start_time:
		busy = false
		finished.emit("视频时间范围无效。")
		return
	var span := stop_time - start_time
	var frames := ceili(span * FRAME_RATE)
	var partial := destination.get_base_dir().path_join(".render-%d.mp4" % Time.get_ticks_usec())
	if not chart.notes.is_empty() and Global.hit_sound_volume > 0.0:
		_hit_audio_path = ProjectSettings.globalize_path("user://revelation-video-hits-%d.f32" % Time.get_ticks_usec())
		if HitFeedback.write_audio(chart.notes, span, Global.hit_sound_volume, _hit_audio_path, start_time) != OK:
			_discard_hit_audio()
			busy = false
			finished.emit("无法生成打击音效音轨。请检查用户数据目录的写入权限和剩余空间。")
			return
	var arguments := _arguments(audio, delay - start_time, span, partial, _hit_audio_path)
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

	var scene := RenderPreview.mount(self, chart, RESOLUTION)
	await get_tree().process_frame

	var error := ""
	for index in range(frames):
		if _cancel:
			break
		var image := await RenderPreview.frame(scene, start_time * 1000.0 + index * 1000.0 / FRAME_RATE)
		if image == null or image.is_empty():
			error = "无法读取预览帧。"
			break
		image.convert(Image.FORMAT_RGB8)
		if not stream.store_buffer(image.get_data()):
			error = "视频编码提前结束。请检查目标磁盘和编码程序。"
			break
		if index % 15 == 0 or index + 1 == frames:
			progress.emit(index + 1, frames)
	scene.viewport.queue_free()

	if _cancel or not error.is_empty():
		OS.kill(pid)
	stream.close()
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
		elif DirAccess.rename_absolute(partial, destination) != OK:
			error = "无法保存视频。请检查目标文件是否正被占用。"
	if FileAccess.file_exists(partial):
		DirAccess.remove_absolute(partial)
	_encoder_pid = -1
	_partial_path = ""
	_discard_hit_audio()
	busy = false
	finished.emit("已取消视频导出。" if _cancel else error)

func _exit_tree() -> void:
	if _encoder_pid > 0 and OS.is_process_running(_encoder_pid):
		OS.kill(_encoder_pid)
	if not _partial_path.is_empty() and FileAccess.file_exists(_partial_path):
		DirAccess.remove_absolute(_partial_path)
	_discard_hit_audio()

func _discard_hit_audio() -> void:
	if not _hit_audio_path.is_empty():
		DirAccess.remove_absolute(_hit_audio_path)
		_hit_audio_path = ""

func _arguments(audio: String, delay: float, duration: float, destination: String, hit_audio := "") -> PackedStringArray:
	var arguments := PackedStringArray([
		"-hide_banner", "-loglevel", "quiet", "-nostdin", "-y",
		"-f", "rawvideo", "-pixel_format", "rgb24",
		"-video_size", "%dx%d" % [RESOLUTION.x, RESOLUTION.y],
		"-framerate", str(FRAME_RATE), "-i", "pipe:0",
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
	arguments.append_array([
		"-t", str(duration), "-c:v", "libx264", "-preset", "veryfast",
		"-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "256k",
		"-movflags", "+faststart", destination,
	])
	return arguments
