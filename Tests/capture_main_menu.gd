extends SceneTree

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var store = root.get_node("GameFlow").saves
	store.base_path = "user://capture-menu-" + str(Time.get_ticks_usec())
	var panel := OS.get_environment("TENSEI_CAPTURE_PANEL")
	if panel in ["saved", "profiles", "records", "save"]:
		var run = load("res://Scripts/Exploration/floor_run.gd").new()
		run.setup(123)
		var profile: Dictionary = store.new_profile("洛恩 · 初次远征")
		for index in range(12 if panel in ["records", "save"] else 1):
			if store.save_record(run, profile, "远征记录 %02d" % (index + 1)).is_empty():
				quit(1)
				return
		if panel == "profiles": store.save_record(run, store.new_profile("洛恩 · 第二角色"), "出发前")
		if panel == "save":
			root.get_node("GameFlow").profile = profile
			root.get_node("GameFlow").run = run
	if OS.get_environment("TENSEI_CAPTURE_SMALL") == "1": root.size = Vector2i(960, 540)
	var menu = load("res://Scenes/UI/main_menu.tscn").instantiate()
	root.add_child(menu)
	if OS.get_environment("TENSEI_CAPTURE_PANEL") == "settings":
		menu._open_settings()
	elif OS.get_environment("TENSEI_CAPTURE_PANEL") == "character":
		menu._open_character()
	elif panel in ["profiles", "records"]:
		menu._open_saves()
		if panel == "records":
			for child in menu.get_children():
				if child is Window: child.list_buttons[0].pressed.emit()
	elif panel == "save":
		var browser = load("res://Scripts/UI/save_browser.gd").new()
		menu.add_child(browser)
		browser.open(store, root.get_node("GameFlow").profile, root.get_node("GameFlow").run)
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
	var directory: String = store.base_path + ".profiles"
	if DirAccess.dir_exists_absolute(directory):
		for folder in DirAccess.get_directories_at(directory):
			for file in DirAccess.get_files_at(directory + "/" + folder): DirAccess.remove_absolute(directory + "/" + folder + "/" + file)
			DirAccess.remove_absolute(directory + "/" + folder)
		DirAccess.remove_absolute(directory)
	for suffix in [".recent.cfg", ".recent.tmp"]:
		if FileAccess.file_exists(store.base_path + suffix): DirAccess.remove_absolute(store.base_path + suffix)
	quit(error)
