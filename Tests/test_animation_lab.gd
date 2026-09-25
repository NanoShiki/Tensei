extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lab = load("res://Scenes/Prototype/animation_lab.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	assert(lab.world_viewport.size == Vector2i(320, 180))
	assert(lab.sorting_layer.y_sort_enabled)
	assert(lab.player.skeleton.get_bone_count() >= 6)
	assert(lab.player.facing == Vector2.RIGHT)
	assert(lab.enemy.health == 4)

	Input.action_press("ui_up")
	Input.action_press("ui_right")
	await process_frame
	await process_frame
	Input.action_release("ui_up")
	Input.action_release("ui_right")
	assert(lab.player.facing.x > 0 and lab.player.facing.y < 0)
	assert(lab.player._view == "back")
	lab.player.position = Vector2(290, 206)
	lab.player.set_motion(Vector2.RIGHT)
	lab.player.set_motion(Vector2.ZERO)
	lab.player.jump()
	await create_timer(0.1).timeout
	assert(lab.player.elevation > 0 and lab.player.skeleton.position.y < -10)
	await create_timer(0.6).timeout
	assert(is_zero_approx(lab.player.elevation))

	lab._attack()
	await create_timer(0.30).timeout
	assert(lab.enemy.health == 3, "挥剑命中阶段应使目标受击")
	await create_timer(0.25).timeout
	lab._swap_weapon()
	assert(lab.player.equipment == "staff", "切换武器后骨骼和角色实例应复用")
	lab._skill()
	await create_timer(0.65).timeout
	assert(lab.enemy.health == 2, "技能飞行特效应在触碰目标后结算")
	await create_timer(0.15).timeout
	lab._shoot_arrow()
	await create_timer(0.55).timeout
	assert(lab.enemy.health == 1, "投矢应在命中后结算")
	assert(lab.enemy.embedded_arrows.size() == 1, "箭应保留在目标骨骼上")
	assert(lab.enemy.embedded_arrows[0].get_parent() is Bone2D)
	var arrow_position: Vector2 = lab.enemy.embedded_arrows[0].global_position
	lab.enemy.hips.rotation += 0.3
	assert(lab.enemy.embedded_arrows[0].global_position.distance_to(arrow_position) > 0.5)
	print("PASS: 2.5D 世界、八向移动、骨骼复用、挥剑、技能、箭附着")
	lab.queue_free()
	await process_frame
	quit(0)
