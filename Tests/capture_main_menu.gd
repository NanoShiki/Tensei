extends SceneTree

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var menu = load("res://Scenes/UI/main_menu.tscn").instantiate()
	root.add_child(menu)
	if OS.get_environment("TENSEI_CAPTURE_PANEL") == "settings":
		menu._open_settings()
	elif OS.get_environment("TENSEI_CAPTURE_PANEL") == "character":
		menu._open_character()
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("TENSEI_CAPTURE_PATH")
	if output.is_empty():
		output = "user://main_menu_preview.png"
	var error := root.get_texture().get_image().save_png(output)
	print("MENU_CAPTURE: ", output, " error=", error)
	quit(error)
