extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var menu = load("res://Scenes/UI/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	menu.animation_lab_button.pressed.emit()
	await process_frame
	await process_frame
	assert(current_scene != null)
	assert(current_scene.scene_file_path == "res://Scenes/Prototype/animation_lab.tscn")
	current_scene._return_to_menu()
	await process_frame
	await process_frame
	assert(current_scene != null)
	assert(current_scene.scene_file_path == "res://Scenes/UI/main_menu.tscn")
	print("PASS: 主菜单进入试验场并返回")
	quit(0)
