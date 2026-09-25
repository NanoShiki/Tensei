extends SceneTree


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	if OS.get_environment("TENSEI_CAPTURE_SMALL") == "1":
		root.size = Vector2i(960, 540)
	var scene = load("res://Scenes/Prototype/animation_lab.tscn").instantiate()
	root.add_child(scene)
	await create_timer(0.3).timeout
	match OS.get_environment("TENSEI_CAPTURE_MODE"):
		"slash":
			scene._attack()
			await create_timer(0.23).timeout
		"skill":
			scene._skill()
			await create_timer(0.36).timeout
		"swap":
			scene._swap_weapon()
		"arrow":
			scene._shoot_arrow()
			await create_timer(0.55).timeout
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("TENSEI_CAPTURE_PATH")
	if output.is_empty():
		output = "user://animation_lab_preview.png"
	var error := root.get_texture().get_image().save_png(output)
	print("ANIMATION_LAB_CAPTURE: ", output, " error=", error)
	quit(error)
