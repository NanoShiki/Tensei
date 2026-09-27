extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		push_error(description)

func frames() -> void:
	await process_frame
	await process_frame

func _run() -> void:
	var flow = root.get_node("GameFlow")
	flow.start_character("背包测试")
	await frames()
	var run = flow.run
	var key := InputEventKey.new()
	key.keycode = KEY_B
	key.pressed = true
	current_scene._input(key)
	check(is_instance_valid(current_scene.inventory) and current_scene.inventory.use_button.disabled, "B 打开背包，满血禁止用药")
	current_scene.inventory._unhandled_key_input(key)
	await frames()
	check(not is_instance_valid(current_scene.inventory), "B 关闭背包")
	run.depart_city(123)
	run.enter("1a")
	var before: Dictionary = run.log_state()
	check(not run.use_field_potion() and run.log_state() == before, "待战斗结算时不能绕过战斗用药")
	run.finish_battle(run.character, true)
	run.character.hp = 20
	current_scene.show_floor_map()
	current_scene._open_inventory()
	var panel = current_scene.inventory
	var capture := OS.get_environment("TENSEI_INVENTORY_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture) == OK, "背包截图")
	before = run.log_state()
	panel.use_button.pressed.emit()
	check(run.character.hp == 32 and run.character.potions == before.hero.potions - 1, "实际按钮恢复12生命并消耗1瓶")
	check(run.steps_taken == before.steps and run.log_state().respawn == before.respawn, "用药不推进步数及刷新")
	panel.use_button.pressed.emit()
	check(run.character.hp == 36 and panel.use_button.disabled, "少量缺血只补至上限")
	before = run.log_state()
	check(not run.use_field_potion() and run.log_state() == before, "满血无副作用")
	run.character.hp = 20
	run.character.potions = 0
	before = run.log_state()
	check(not run.use_field_potion() and run.log_state() == before, "库存不足无副作用")
	run.character.potions = 2
	run.begin_return()
	check(run.use_field_potion(), "返程中也能用药")
	var restored = preload("res://Scripts/Exploration/floor_run.gd").from_save(run.save_data())
	check(restored.character == run.character, "存档快照保留消耗与生命")
	var store := preload("res://Scripts/Core/expedition_save.gd").new()
	store.base_path = "user://test-inventory-" + Crypto.new().generate_random_bytes(8).hex_encode()
	check(store.save_run(run) and store.inspect().run.character == run.character, "磁盘保存读取保持用药后的资源")
	DirAccess.remove_absolute(store.base_path + ".0.save")
	panel.close_requested.emit()
	await frames()
	run.character.hp = 0
	before = run.log_state()
	check(not run.use_field_potion() and run.log_state() == before, "失败角色不能背包复活")
	print("INVENTORY CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
