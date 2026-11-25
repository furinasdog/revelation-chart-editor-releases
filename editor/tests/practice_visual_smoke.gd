extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if change_scene_to_file("res://main/main.tscn") != OK:
		quit(2)
		return
	await scene_changed
	await process_frame
	var d: Node = current_scene.desktop
	d._onboarding.close_guide()
	if d._release_dialog: d._release_dialog.hide()
	d._open_practice(1)
	var practice: Window
	for child in d.host.get_children():
		if child is Window and child.title == "8 拍练习谱": practice = child
	var images: Array[Image] = []
	for i in 3:
		practice._compare(i)
		await RenderingServer.frame_post_draw
		var image: Image = practice.player.scenes[i].viewport.get_texture().get_image()
		images.append(image)
	var total := [0.0,0.0]
	var center := [0.0,0.0,0.0]
	var edge := [0.0,0.0,0.0]
	for y in range(10,350,8):
		for x in range(10,630,8):
			var r := Vector2(x-320,y-180).length()
			for i in 3:
				var luminance := images[i].get_pixel(x,y).get_luminance()
				if r < 85: center[i] += luminance
				if r > 260: edge[i] += luminance
				if i > 0: total[i-1] += absf(luminance-images[i-1].get_pixel(x,y).get_luminance())
	print("PRACTICE_IMAGES differences=",total," center=",center," edge=",edge)
	var ok: bool = total[0] > 10 and total[1] > 5 and center[0] > center[1] and center[2] > center[1] and absf(edge[2]-edge[1]) < absf(center[2]-center[1])
	quit(0 if ok else 1)
