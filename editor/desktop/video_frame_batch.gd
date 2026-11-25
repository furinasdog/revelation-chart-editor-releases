extends RefCounted

# Only detached CPU images cross threads. Viewports and chart nodes stay on the main thread.
var images: Array[Image]
var stream: FileAccess
var written := false
var _conversion := -1
var _writer := -1

func start(frames: Array[Image], pipe: FileAccess) -> void:
	images = frames
	stream = pipe
	_conversion = WorkerThreadPool.add_group_task(_convert, images.size(), images.size())
	_writer = WorkerThreadPool.add_task(_write)

func _convert(index: int) -> void:
	images[index].convert(Image.FORMAT_RGB8)

func _write() -> void:
	WorkerThreadPool.wait_for_group_task_completion(_conversion)
	for image in images:
		if not stream.store_buffer(image.get_data()):
			return
	written = true

func pending() -> bool:
	return not WorkerThreadPool.is_task_completed(_writer)

func join() -> bool:
	WorkerThreadPool.wait_for_task_completion(_writer)
	return written
