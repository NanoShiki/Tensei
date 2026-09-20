extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var flow := root.get_node_or_null("GameFlow")
	assert(flow != null)
	assert(flow.active_character.is_empty())

	# 开始旅程：装载角色档案并切换到城市庭院。
	flow.start_new_game("lorn")
	await process_frame
	await process_frame
	assert(flow.active_character["character_id"] == "lorn")
	assert(flow.active_character["display_name"] == "洛恩")
	assert(current_scene != null)
	assert(current_scene.name == "CityCourtyard")
	assert(current_scene.player != null)

	# 未登记的角色标识回退到预设角色，避免地图装载中断。
	flow.return_to_menu()
	await process_frame
	await process_frame
	assert(flow.active_character.is_empty())
	assert(current_scene.name == "MainMenu")
	flow.start_new_game("unknown.character")
	await process_frame
	await process_frame
	assert(flow.active_character["character_id"] == "lorn")

	print("PASS: 单例装载、角色档案、地图切换、返回主菜单、未知角色回退")
	quit(0)
