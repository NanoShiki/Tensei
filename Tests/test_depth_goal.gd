extends SceneTree

const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Board = preload("res://Scripts/UI/quest_board.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-depth-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func frames() -> void:
	await process_frame
	await process_frame

func win(flow: Node) -> void:
	check(flow.settle_battle(flow.run.character, flow.party_companion(), true, flow.party_companion("scout")), "正常战斗胜利回写")

func reach(flow: Node, depth: int) -> void:
	for i in range(150):
		if flow.run.floor_number >= depth: return
		if flow.run.enter(flow.run.node(flow.run.current).next[0]) == "battle": win(flow)
	check(false, "应能到达目标层")

func city(flow: Node) -> void:
	check(flow.run.begin_return(), "自由返程")
	for i in range(250):
		if flow.run.phase == "returned": break
		flow.run.step_return(flow.run.return_targets()[0].key)
		if not flow.run.pending.is_empty(): win(flow)
	check(flow.run.enter_city(), "抵达城市")
	current_scene.show_floor_map()

func board() -> Window:
	for child in current_scene.get_children():
		if child.get_script() == Board: return child
	return null

func _run() -> void:
	create_timer(45).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("第五层完整流程")
	await frames()
	current_scene.city_buttons.quests.pressed.emit()
	check(board().buttons.depth_five.disabled and "队长" in board().buttons.depth_five.tooltip_text, "未交付队长时显示资格并锁定")
	check(not flow.run.quest_service("depth_five", "accept") and flow.run.character.depth_goal == 0, "拒绝提前接取")
	for id in ["hunt", "materials", "captain"]: board().buttons[id].pressed.emit()
	board().queue_free()
	await frames()
	flow.run.depart_city(7)
	reach(flow, 5)
	check(flow.run.character.depth_goal == 0, "接取前抵达第五层不追溯进度")
	city(flow)
	for id in ["hunt", "materials", "captain"]: check(flow.run.quest_service(id, "claim"), "入门任务真实达成并交付")
	check(flow.run.character.experience == 50 and flow.run.character.level == 4, "三入门任务累计50经验")
	check(flow.familia_service("join") and flow.familia_service("enlist"), "真实讨伐资格进入眷族编队")
	flow.city_service("rest")
	flow.run.depart_city(11)
	reach(flow, 3)
	city(flow)
	check(flow.guild_level() >= 2, "编队胜利达到组织等级2")
	check(flow.run.quest_service("familia_patrol", "accept", flow.guild_level()), "接取成员任务")
	current_scene.city_buttons.quests.pressed.emit()
	check(not board().buttons.depth_five.disabled, "队长交付后实际UI开放")
	board().buttons.depth_five.pressed.emit()
	check(flow.run.character.quests.depth_five == "active" and flow.run.character.depth_goal == 0, "城市接取不追溯旧远征最深层")
	board().queue_free()
	await frames()
	flow.city_service("rest")
	flow.run.depart_city(13)
	reach(flow, 4)
	check(flow.run.character.depth_goal == 4 and "4 / 5" in flow.run.objective_text(), "接取后实际抵达第四层与目标反馈")
	var profile_id: String = flow.profile.id
	var partial: String = flow.saves.save_record(flow.run, flow.profile, "勘察第四层")
	check(not partial.is_empty() and flow.load_exploration(profile_id, partial), "部分目标磁盘恢复")
	await frames()
	check(flow.run.character.depth_goal == 4 and flow.run.floor_number == 4, "读档保留进度且不自动完成")
	check(not flow.run.quest_service("depth_five", "claim"), "探索途中禁止领奖")
	flow.run.enter("1a")
	current_scene.start_encounter()
	await create_timer(1.5).timeout
	check(current_scene.gm_kill_enemy(), "真实GM走普通结算")
	reach(flow, 5)
	check(flow.run.character.depth_goal == 5 and "返回城市" in flow.run.objective_text(), "抵达第五层提示回城领奖")
	check(flow.run.character.experience == 50, "达成目标未提前发经验")
	city(flow)
	current_scene.city_buttons.quests.pressed.emit()
	check(not board().buttons.depth_five.disabled, "回城后实际领奖按钮开放")
	var capture := OS.get_environment("TENSEI_DEPTH_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await process_frame
		board().rows.get_parent().scroll_vertical = 1000
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	var hp: int = flow.run.character.hp
	var gold: int = flow.run.character.gold
	board().buttons.depth_five.pressed.emit()
	check(flow.run.character.gold == gold + 15 and flow.run.character.experience == 65 and board().buttons.depth_five.disabled, "勘察奖励只领一次并刷新按钮")
	board().buttons.familia_patrol.pressed.emit()
	check(flow.run.character.experience == 85 and flow.run.character.level == 5 and flow.run.character.max_hp == 52 and flow.run.character.hp == hp, "五条真实任务闭环达等级5且不自动治疗")
	board().queue_free()
	await frames()
	var snapshot: Dictionary = flow.run.save_data()
	check(not flow.run.quest_service("depth_five", "claim") and flow.run.save_data() == snapshot, "重复领奖完全无副作用")
	var finished: String = flow.saves.save_record(flow.run, flow.profile, "勘察领奖后")
	check(flow.load_exploration(profile_id, partial), "读取个人较早时点")
	await frames()
	check(flow.run.character.depth_goal == 4 and flow.run.character.experience == 50, "旧时点恢复个人进度和奖励余额")
	check(flow.load_exploration(profile_id, finished), "读取完成时点")
	await frames()
	check(flow.run.character.depth_goal == 5 and flow.run.character.level == 5 and "已交付" in flow.run.objective_text(), "完成目标与等级磁盘恢复")
	snapshot = flow.run.save_data()
	snapshot.character.erase("depth_goal")
	snapshot.character.quests.erase("depth_five")
	var old = Run.from_save(snapshot)
	check(old != null and old.character.depth_goal == 0 and old.character.quests.depth_five == "available", "旧记录补未接取勘察，不追溯")
	snapshot = flow.run.save_data()
	snapshot.character.depth_goal = 6
	check(Run.from_save(snapshot) == null, "拒绝越界深度")
	snapshot.character.depth_goal = 4
	check(Run.from_save(snapshot) == null, "拒绝未达第五层的已领奖快照")
	snapshot = flow.run.save_data()
	snapshot.character.quests.captain = "active"
	check(Run.from_save(snapshot) == null, "拒绝缺资格的高级任务")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]: DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("DEPTH GOAL CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
