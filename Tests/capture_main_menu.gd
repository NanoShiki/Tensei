extends SceneTree

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var store = root.get_node("GameFlow").saves
	store.base_path = "user://capture-menu-" + str(Time.get_ticks_usec())
	if OS.get_environment("TENSEI_CAPTURE_PANEL") == "saved":
		var run = load("res://Scripts/Exploration/floor_run.gd").new()
		run.setup(123)
		if not store.save_run(run):
			quit(1)
			return
	if OS.get_environment("TENSEI_CAPTURE_SMALL") == "1": root.size = Vector2i(960, 540)
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
	for suffix in [".0.save", ".1.save", ".tmp"]:
		if FileAccess.file_exists(store.base_path + suffix): DirAccess.remove_absolute(store.base_path + suffix)
	quit(error)
