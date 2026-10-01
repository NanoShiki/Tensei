extends SceneTree

const Guide = preload("res://Scripts/UI/demo_guide.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func frames() -> void:
	await process_frame
	await process_frame

func guide() -> Window:
	for child in current_scene.get_children():
		if child.get_script() == Guide: return child
	return null

func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = "user://test-guide-" + Crypto.new().generate_random_bytes(8).hex_encode()
	flow.progress.base_path = flow.saves.base_path + "-shared"
	flow.return_to_menu()
	await frames()
	current_scene.guide_button.pressed.emit()
	check(guide() != null and guide().stage_labels.size() == 6 and "新角色" in guide().summary.text, "主菜单提供完整只读流程")
	current_scene._open_guide()
	var count := 0
	for child in current_scene.get_children():
		if child.get_script() == Guide: count += 1
	check(count == 1, "重复打开不堆叠窗口")
	var key := InputEventKey.new()
	key.keycode = KEY_F1
	key.pressed = true
	guide()._unhandled_key_input(key)
	await frames()
	check(guide() == null and current_scene.guide_button.has_focus(), "F1关闭后恢复指南入口焦点")
	flow.start_character("指南角色")
	await frames()
	var snapshot: Dictionary = flow.run.save_data()
	current_scene._open_guide()
	check(guide() != null and "未加入" in guide().stage_labels.familia.text and "城市委托" in guide().stage_labels.prepare.text, "新角色显示真实阶段状态")
	key.keycode = KEY_B
	current_scene._input(key)
	check(current_scene.inventory == null and flow.run.save_data() == snapshot, "指南阻止底层背包快捷键，保持旅程状态")
	guide().queue_free()
	await frames()
	flow.run.quest_service("hunt", "accept")
	flow.run.character.hunt_wins = 2
	snapshot = flow.run.save_data()
	current_scene._open_guide()
	check("2 / 3" in guide().stage_labels.growth.text and flow.run.save_data() == snapshot, "已接取进度按当前记录展示且不改写")
	var capture := OS.get_environment("TENSEI_GUIDE_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await frames()
		guide().scroll.scroll_vertical = 400
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	guide().queue_free()
	await frames()
	flow.run.depart_city(7)
	flow.run.enter("1a")
	current_scene.start_encounter()
	await create_timer(1.5).timeout
	current_scene._open_guide()
	check(guide() != null, "战斗待操作时可查看控制说明")
	var battle_before: Dictionary = current_scene.battle.log_state()
	var random_state: int = current_scene.battle.rng.state
	key.keycode = KEY_SPACE
	current_scene._input(key)
	key.keycode = KEY_1
	current_scene._input(key)
	check(current_scene.battle.log_state() == battle_before and current_scene.battle.rng.state == random_state and current_scene.selected.is_empty(), "指南不穿透结束回合、技能或随机数")
	guide().queue_free()
	await frames()
	current_scene.busy = true
	current_scene._open_guide()
	check(guide() == null, "异步动作中不打开窗口")
	check(not FileAccess.file_exists(flow.progress.base_path + ".0.save") and not DirAccess.dir_exists_absolute(flow.saves.base_path + ".profiles"), "查看指南不创建共享成长或个人记录")
	print("DEMO GUIDE CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
