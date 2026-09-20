extends SceneTree

const WORLD_SCENE := "res://Scenes/World/city_courtyard.tscn"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var map = load(WORLD_SCENE).instantiate()
	root.add_child(map)
	await process_frame

	var player = map.player
	assert(player != null)
	assert(player.position == map.player_spawn.position)
	assert(player.visual.action == "idle")
	assert(player.visual.texture.get_size() == Vector2(1024, 1024))
	assert(map.map_rect() == Rect2(0, 0, 2048, 2048))
	assert(map.camera.limit_right == 2048 and map.camera.limit_bottom == 2048)

	# 行走：按住 D 向东移动，朝向与动作同步切换。
	var start_x: float = player.position.x
	Input.action_press("move_right")
	for i in range(20):
		await physics_frame
	assert(player.position.x > start_x)
	assert(player.facing == "east")
	assert(player.visual.action == "walk")
	assert(absf(player.velocity.length() - player.walk_speed) < 5.0)
	assert(player.visual.region_rect.position.y == 256.0)

	# 疾跑：按住 Shift 后速度提升并切换到跑步动作。
	Input.action_press("move_run")
	for i in range(20):
		await physics_frame
	assert(player.visual.action == "run")
	assert(absf(player.velocity.length() - player.run_speed) < 5.0)
	Input.action_release("move_run")

	# 朝向：向北移动时取第 2 行素材。
	Input.action_release("move_right")
	Input.action_press("move_up")
	for i in range(10):
		await physics_frame
	assert(player.facing == "north")
	assert(player.visual.region_rect.position.y == 512.0)

	# 停止后回到待机，速度归零并保持最后朝向。
	Input.action_release("move_up")
	for i in range(20):
		await physics_frame
	assert(player.visual.action == "idle")
	assert(player.velocity.length() < 1.0)
	assert(player.facing == "north")

	# 动作时间轴：行走 6 FPS，推进一帧时长后切到下一列。
	player.visual.set_state("walk", "south")
	assert(player.visual.frame_index == 0)
	player.visual.advance(1.0 / 6.0 + 0.001)
	assert(player.visual.frame_index == 1)
	assert(player.visual.region_rect.position == Vector2(256, 0))

	# 碰撞：向东推进不会越过东侧围墙。
	player.position = Vector2(1600, 1100)
	Input.action_press("move_right")
	for i in range(60):
		await physics_frame
	Input.action_release("move_right")
	assert(player.position.x < 1690.0)

	print("PASS: 出生点、四向朝向、行走与疾跑速度、待机回退、动作时间轴、围墙碰撞、相机边界")
	map.queue_free()
	await process_frame
	quit(0)
