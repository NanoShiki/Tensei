extends SceneTree

const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Board = preload("res://Scripts/UI/quest_board.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-patrol-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func frames() -> void:
	await process_frame
	await process_frame

func quest_board() -> Window:
	for child in current_scene.get_children():
		if child.get_script() == Board: return child
	return null

func win_next(flow: Node, with_party: bool = true) -> void:
	for i in range(20):
		if flow.run.enter(flow.run.node(flow.run.current).next[0]) == "battle":
			flow.settle_battle(flow.run.character, flow.party_companion() if with_party else {}, true)
			return
	check(false, "测试路线需要出现战斗")

func go_city(flow: Node) -> void:
	check(flow.run.begin_return(), "开始返程")
	for i in range(150):
		if flow.run.phase == "returned": break
		flow.run.step_return(flow.run.return_targets()[0].key)
		if not flow.run.pending.is_empty(): flow.settle_battle(flow.run.character, flow.party_companion(), true)
	check(flow.run.enter_city(), "完成自由返程入城")

func _run() -> void:
	create_timer(40).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("成员任务角色")
	await frames()
	current_scene.city_buttons.quests.pressed.emit()
	check(quest_board().buttons.familia_patrol.disabled and "眷族等级 2" in quest_board().buttons.familia_patrol.tooltip_text, "未入眷族的成员任务显示资格原因")
	quest_board().queue_free()
	await frames()
	# 加入资格已有独立完整讨伐测试，本专项夹具聚焦组织分级任务。
	flow.run.character.quests.hunt = "claimed"
	check(flow.familia_service("join") and flow.familia_service("enlist"), "建立晨行编队")
	var before: Dictionary = flow.run.character.duplicate(true)
	check(not flow.run.quest_service("familia_patrol", "accept", flow.guild_level()) and flow.run.character == before, "组织等级不足不能接任务且无副作用")
	flow.run.depart_city(7)
	for i in range(3): win_next(flow)
	check(flow.progress.guild_level() == 2 and flow.run.character.familia_wins == 0, "组织三级贡献升级，接取前胜利不追溯个人目标")
	go_city(flow)
	current_scene.show_floor_map()
	current_scene.city_buttons.quests.pressed.emit()
	check(not quest_board().buttons.familia_patrol.disabled, "等级2城市成员任务解锁")
	quest_board().buttons.familia_patrol.pressed.emit()
	check(flow.run.character.quests.familia_patrol == "active", "点击接取成员巡守")
	var capture := OS.get_environment("TENSEI_PATROL_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await process_frame
		quest_board().rows.get_parent().scroll_vertical = 100000
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	quest_board().queue_free()
	await frames()
	check(not flow.run.quest_service("familia_patrol", "claim", flow.guild_level()), "未完成不得领奖")
	flow.run.depart_city(9)
	win_next(flow, false)
	check(flow.run.character.familia_wins == 0, "没有实际队友的结算不计成员目标")
	var step_id: String = flow.run.node(flow.run.current).next[0]
	if flow.run.node(step_id).kind == "battle":
		flow.run.enter(step_id, true)
		check(flow.run.character.familia_wins == 0, "绕行不计成员巡守")
	for i in range(4): win_next(flow)
	check(flow.run.character.familia_wins == 4, "编队胜利计数明确独立")
	var profile_id: String = flow.profile.id
	var partial: String = flow.saves.save_record(flow.run, flow.profile, "成员4场")
	check(not partial.is_empty() and flow.load_exploration(profile_id, partial), "部分成员进度磁盘保存读取")
	await frames()
	check(flow.run.character.familia_wins == 4, "恢复成员计数与任务")
	for i in range(20):
		if flow.run.enter(flow.run.node(flow.run.current).next[0]) == "battle": break
	current_scene.start_encounter()
	await create_timer(1.2).timeout
	check(current_scene.gm_kill_enemy() and flow.run.character.familia_wins == 5, "实际双人GM胜利推进第五场")
	var complete: Dictionary = flow.run.character.duplicate(true)
	check(not flow.settle_battle(flow.run.character, flow.party_companion(), true) and flow.run.character == complete, "重复结算不重复推进目标")
	go_city(flow)
	current_scene.show_floor_map()
	current_scene.city_buttons.quests.pressed.emit()
	check(not quest_board().buttons.familia_patrol.disabled, "五场后回城允许领奖")
	var gold: int = flow.run.character.gold
	var xp: int = flow.run.character.experience
	quest_board().buttons.familia_patrol.pressed.emit()
	check(flow.run.character.gold == gold + 10 and flow.run.character.experience == xp + 20 and flow.run.character.quests.familia_patrol == "claimed", "个人奖励和完成状态原子提交")
	before = flow.run.character.duplicate(true)
	check(not flow.run.quest_service("familia_patrol", "claim", flow.guild_level()) and flow.run.character == before, "成员奖励每角色一次")
	quest_board().queue_free()
	await frames()
	var awarded: String = flow.saves.save_record(flow.run, flow.profile, "成员领奖后")
	check(not awarded.is_empty() and flow.saves.read_record(profile_id, awarded).run.character == before, "成员已领奖进度完整保存")
	var shared_xp: int = flow.progress.data.familias.dawn.squire_xp
	check(flow.load_exploration(profile_id, partial), "读取较早成员记录")
	await frames()
	check(flow.run.character.familia_wins == 4 and flow.run.character.quests.familia_patrol == "active" and flow.progress.data.familias.dawn.squire_xp == shared_xp, "个人任务恢复旧时点，共享成长不回退")
	var old := Run.new()
	old.setup(11)
	var legacy: Dictionary = old.save_data()
	legacy.character.erase("familia_wins")
	legacy.character.quests.erase("familia_patrol")
	check(Run.from_save(legacy).character.quests.familia_patrol == "available", "旧记录补未接取成员任务")
	legacy = flow.run.save_data()
	legacy.character.familia_wins = 6
	check(Run.from_save(legacy) == null, "拒绝成员目标越界")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]: DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("FAMILIA QUEST CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
