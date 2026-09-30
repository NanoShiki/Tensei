extends SceneTree

const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Store = preload("res://Scripts/Core/expedition_save.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	await process_frame

func _run() -> void:
	var flow = root.get_node("GameFlow")
	flow.start_character("委托成长测试")
	await frames()
	current_scene.city_buttons.quests.pressed.emit()
	var board: Window
	for child in current_scene.get_children():
		if child is Window: board = child
	board.buttons.hunt.pressed.emit()
	board.buttons.materials.pressed.emit()
	board.buttons.captain.pressed.emit()
	check(flow.run.character.quests.hunt == "active" and board.buttons.hunt.disabled, "接取后未完成不可领奖")
	var capture := OS.get_environment("TENSEI_QUEST_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture) == OK, "委托窗口截图")
	board.close_requested.emit()
	await frames()
	var run: RefCounted = flow.run
	check(run.depart_city(123), "带委托出发")
	check(not run.quest_service("hunt", "claim"), "探索途中不交付")
	for i in range(40):
		if run.character.hunt_wins >= 3: break
		var id: String = run.node(run.current).next[0]
		if run.enter(id) == "battle": run.finish_battle(run.character, true)
	check(run.character.hunt_wins == 3 and run.character.experience == 0, "接取后胜利推进目标，领奖前不发经验")
	run.begin_return()
	for i in range(100):
		if run.phase == "returned": break
		run.step_return(run.return_targets()[0].key)
		if not run.pending.is_empty(): run.finish_battle(run.character, true)
	check(run.enter_city(), "回城交付")
	var hp: int = run.character.hp
	var gold: int = run.character.gold
	check(run.quest_service("hunt", "claim") and run.character.gold == gold + 6, "讨伐奖励一次加入金币")
	check(run.character.level == 2 and run.character.max_hp == 40 and run.character.hp == hp, "升级增加生命上限并保留当前生命")
	var snapshot: Dictionary = run.save_data()
	check(not run.quest_service("hunt", "claim") and run.save_data() == snapshot, "重复领奖无副作用")
	var scrap: int = run.character.scrap
	check(run.quest_service("materials", "claim") and run.character.scrap == scrap - 3 and run.character.level == 3, "材料交付原子扣除并升级")
	check(not run.quest_service("captain", "claim"), "未击败队长时不能领奖")
	run.character.captain_defeated = true
	gold = run.character.gold
	check(run.quest_service("captain", "claim") and run.character.gold == gold + 12 and run.character.level == 4, "首领目标交付并升级")
	var insufficient := Run.new()
	insufficient.setup(123)
	insufficient.phase = "city"
	insufficient.quest_service("materials", "accept")
	snapshot = insufficient.save_data()
	check(not insufficient.quest_service("materials", "claim") and insufficient.save_data() == snapshot, "缺材料不部分扣款和发奖")
	var store := Store.new()
	store.base_path = "user://test-growth-" + Crypto.new().generate_random_bytes(8).hex_encode()
	check(store.save_run(run) and store.inspect().run.character == run.character, "成长及任务完整保存恢复")
	snapshot = run.save_data()
	for key in ["experience", "level", "hunt_wins", "quests"]: snapshot.character.erase(key)
	snapshot.character.max_hp = 36
	snapshot.character.hp = mini(36, snapshot.character.hp)
	var restored = Run.from_save(snapshot)
	check(restored != null and restored.character.level == 1 and restored.character.quests.hunt == "available", "旧角色补初始成长和任务")
	snapshot = run.save_data()
	snapshot.character.quests.hunt = "invalid"
	check(Run.from_save(snapshot) == null, "无效任务状态拒绝恢复")
	check(run.depart_city(456) and run.character.quests.hunt == "claimed" and run.character.level == 4, "下一趟保留已领任务与成长")
	for suffix in [".0.save", ".1.save"]:
		if FileAccess.file_exists(store.base_path + suffix): DirAccess.remove_absolute(store.base_path + suffix)
	print("QUEST / GROWTH CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
