extends SceneTree

func _initialize() -> void:
	_capture.call_deferred()

func _capture() -> void:
	var mode := OS.get_environment("TENSEI_CAPTURE_MODE")
	if mode in ["map", "return", "returned"]:
		var flow = root.get_node("GameFlow")
		flow.run = load("res://Scripts/Exploration/floor_run.gd").new()
		flow.run.setup(123)
		if mode in ["return", "returned"]:
			flow.run.enter("1a")
			flow.run.finish_battle(flow.run.character, true)
			flow.run.enter("2b")
			flow.run.begin_return()
			if mode == "returned":
				while flow.run.phase == "returning":
					flow.run.step_return(flow.run.return_targets()[0].key)
					if not flow.run.pending.is_empty(): flow.run.finish_battle(flow.run.character, true)
		flow.show_map = true
	if OS.get_environment("TENSEI_CAPTURE_SMALL") == "1":
		root.size = Vector2i(960, 540)
	var screen = load("res://Scenes/Battle/battle.tscn").instantiate()
	root.add_child(screen)
	await create_timer(1.2).timeout
	if OS.get_environment("TENSEI_CAPTURE_MODE") == "target": screen._select("fire_potion")
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
