extends SceneTree

const WORLD_SCENE := "res://Scenes/World/city_courtyard.tscn"

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var map = load(WORLD_SCENE).instantiate()
	root.add_child(map)
	await process_frame
	var action := OS.get_environment("TENSEI_CAPTURE_ACTION")
	if action == "walk":
		Input.action_press("move_right")
	elif action == "run":
		Input.action_press("move_up")
		Input.action_press("move_run")
	for i in range(20):
		await physics_frame
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("TENSEI_CAPTURE_PATH")
	if output.is_empty():
		output = "user://city_courtyard_preview.png"
	var error := root.get_texture().get_image().save_png(output)
	print("WORLD_CAPTURE: ", output, " error=", error)
	quit(error)
