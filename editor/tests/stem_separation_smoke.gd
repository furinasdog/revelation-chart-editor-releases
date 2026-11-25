extends SceneTree

const Separation := preload("res://desktop/stem_separation.gd")
const Cache := preload("res://desktop/stem_cache.gd")

var failures := 0
var prompts := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	if not ok:
		push_error(description)
		failures += 1

func wait_for_job(service: Node) -> void:
	var deadline := Time.get_ticks_msec() + 180000
	while service.state == "running" and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	check(service.state != "running", "Native process completed within the test deadline")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	var source := args[0]
	var fixture := ProjectSettings.globalize_path("user://stem-fixture.wav")
	DirAccess.copy_absolute(source, fixture)
	var service := Separation.new()
	root.add_child(service)
	service.model_required.connect(func(): prompts += 1)
	OS.set_environment("AUTOREVELATION_HTDEMUCS_MODELS", ProjectSettings.globalize_path("user://absent"))
	service.set_audio(source)
	check(service.state == "idle" and prompts == 0, "Opening audio does not start the separator or open a modal")
	service.start()
	check(service.state == "missing_model" and prompts == 1, "Explicit separation guides the user to Hub")
	OS.set_environment("AUTOREVELATION_HTDEMUCS_MODELS", args[1])
	service.refresh()
	check(service.state == "idle", "Model installed during this session is recognized")
	service.start()
	check(service.state == "running", "Starting a new separation launches the process")
	service.cancel()
	check(service.state == "idle" and service.stem_path("drums").is_empty(), "Cancellation never exposes partial stems")
	service.preferred_ffmpeg = ProjectSettings.globalize_path("user://missing-decoder.exe")
	service.start()
	await wait_for_job(service)
	check(service.state == "error" and service.stem_path("vocals").is_empty(), "Decoder failure keeps stems unavailable")
	service.preferred_ffmpeg = ""
	service.start()
	await wait_for_job(service)
	check(service.state == "ready" and service.progress == 1.0, "Retry after failure completes actual native inference: " + service.message)
	if service.state == "ready":
		var drums := service.stem_path("drums")
		for stem: String in Cache.STEMS:
			check(FileAccess.file_exists(service.stem_path(stem)), "All four stems are published: " + stem)
		service.set_audio("")
		check(service.state == "idle" and service.stem_path("drums").is_empty(), "Changing song clears playback eligibility")
		OS.set_environment("AUTOREVELATION_HTDEMUCS_MODELS", ProjectSettings.globalize_path("user://absent"))
		service.set_audio(fixture)
		check(service.state == "ready" and service.stem_path("drums") == drums, "Identical bytes at a new path reuse the completed cache")
		var truncated := FileAccess.open(drums, FileAccess.READ_WRITE)
		truncated.resize(truncated.get_length() - 4)
		truncated.close()
		service.refresh()
		check(service.state == "idle" and service.stem_path("other").is_empty(), "A truncated WAV invalidates the four-track set")
		OS.set_environment("AUTOREVELATION_HTDEMUCS_MODELS", args[1])
		service.start()
		await wait_for_job(service)
		check(service.state == "ready", "A damaged cache can be rebuilt")
	service.queue_free()
	print("STEM_SEPARATION_SMOKE failures=", failures)
	quit(0 if failures == 0 else 1)
