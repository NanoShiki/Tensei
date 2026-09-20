extends SceneTree

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var screen = load("res://Scenes/Battle/battle.tscn").instantiate()
	root.add_child(screen)
	for i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_environment("TENSEI_CAPTURE_PATH")
	if output.is_empty():
		output = "user://battle_preview.png"
	var image := root.get_texture().get_image()
	if image == null:
		push_error("战斗截图失败：视口图像为空")
		quit(1)
		return
	var error := image.save_png(output)
	print("BATTLE_CAPTURE: ", output, " absolute=", ProjectSettings.globalize_path(output), " error=", error)
	quit(error)
