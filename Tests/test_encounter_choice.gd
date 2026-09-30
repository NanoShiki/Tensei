extends SceneTree

const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Store = preload("res://Scripts/Core/expedition_save.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	await process_frame

func dialog(screen: Node) -> Window:
	for child in screen.get_children():
		if child is Window and not child.is_queued_for_deletion(): return child
	return null

func _run() -> void:
	var run := Run.new()
	run.setup(123, 3)
	var original: Dictionary = run.save_data()
	check(run.encounter_preview("3a").is_empty(), "远处或不合法节点无预览")
	check(run.encounter_preview("1a").can_avoid and run.save_data() == original, "合法怪物预览无副作用")
	check(run.enter("1a", true) == "avoided" and run.steps_taken == 1 and run.current == "1a", "绕行抵达且只移动一步")
	check(run.character.fire_potions == 1 and run.character.gold == 0 and run.battles_won == 0 and not run.character.captain_defeated, "只消耗药水，无金币胜利与目标")
	check(run.node("1a").enemy_active and run.node("1a").visited and not run.node("1a").cleared and run.pending.is_empty(), "到访与清理独立，绕行不锁在战斗")
	original = run.save_data()
	check(run.enter("1a", true).is_empty() and run.save_data() == original, "重复绕行拒绝且无额外消耗")
	var store := Store.new()
	store.base_path = "user://test-avoid-" + Crypto.new().generate_random_bytes(8).hex_encode()
	check(store.save_run(run) and store.inspect().run.node("1a").enemy_active and store.inspect().run.current == "1a", "磁盘恢复到访与怪物仍在场")
	run.enter("2b")
	run.begin_return()
	check(run.step_return(run.node("1b").key, true) and run.phase == "returning" and run.current == "1b" and run.character.fire_potions == 0, "未走过返程分支可绕行")
	run.begin_descent()
	run.enter("2b")
	run.begin_return()
	original = run.save_data()
	check(not run.step_return(run.node("1a").key, true) and run.save_data() == original, "库存不足拒绝且不计步")
	check(run.step_return(run.node("1a").key) and run.pending == "1a", "库存不足仍可交战")
	run.finish_battle(run.character, true)
	run.begin_descent()
	run.enter("2b")
	run.begin_return()
	run.node("1a").respawn_in = 1
	run.character.fire_potions = 1
	var steps: int = run.steps_taken
	check(not run.node("1a").enemy_active and run.encounter_preview("1a").can_avoid, "剩一步在移动前预览遭遇")
	check(run.step_return(run.node("1a").key, true) and run.steps_taken == steps + 1 and run.node("1a").enemy_active and run.node("1a").respawn_in == 0, "先计步刷新再绕行，怪物保持在场")
	# 队长可绕行，但不能因此完成目标。
	run.setup(123, 4)
	for level in range(2):
		for id in ["1b", "2b", "3b", "exit"]:
			if run.enter(id) == "battle": run.finish_battle(run.character, true)
	check(run.encounter_preview("1a").name == "守关队长" and run.enter("1a", true) == "avoided" and not run.character.captain_defeated, "队长绕行不完成讨伐")
	# 城市采购原子交易。
	run.setup(123)
	run.phase = "city"
	run.character.gold = 3
	original = run.save_data()
	check(not run.city_service("fire_potion") and run.save_data() == original, "购药差一金币无副作用")
	run.character.gold = 4
	check(run.city_service("fire_potion") and run.character.gold == 0 and run.character.fire_potions == 3, "购灼烧药水正确扣款")
	var flow = root.get_node("GameFlow")
	flow.run = run
	flow.show_map = true
	flow._change_scene(flow.BATTLE_SCENE)
	await frames()
	var screen = current_scene
	screen.city_buttons.depart.pressed.emit()
	var snapshot: Dictionary = flow.run.save_data()
	screen.map_buttons["1a"].pressed.emit()
	var choice := dialog(screen)
	check(choice != null and flow.run.save_data() == snapshot, "节点点击先显示选择，尚未移动")
	var capture := OS.get_environment("TENSEI_ENCOUNTER_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture) == OK, "遭遇选择截图")
	choice.cancel_button.pressed.emit()
	await frames()
	check(flow.run.save_data() == snapshot and screen.map_visible, "取消选择保留地图与资源")
	screen.map_buttons["1a"].pressed.emit()
	choice = dialog(screen)
	choice.avoid_button.pressed.emit()
	await frames()
	check(screen.map_visible and flow.run.current == "1a" and flow.run.steps_taken == 1, "实际绕行按钮抵达地图")
	screen.map_buttons["2b"].pressed.emit()
	screen.direction_button.pressed.emit()
	flow.run.character.fire_potions = 0
	screen.map_buttons["1b"].pressed.emit()
	choice = dialog(screen)
	check(choice.avoid_button.disabled and not choice.fight_button.disabled, "无药绕行禁用、交战保留")
	choice.fight_button.pressed.emit()
	await create_timer(1.1).timeout
	check(not screen.map_visible and flow.run.pending == "1b", "实际交战按钮进入战斗")
	for suffix in [".0.save", ".1.save"]:
		if FileAccess.file_exists(store.base_path + suffix): DirAccess.remove_absolute(store.base_path + suffix)
	print("ENCOUNTER CHOICE CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
