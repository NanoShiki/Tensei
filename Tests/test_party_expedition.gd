extends SceneTree

const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Board = preload("res://Scripts/UI/familia_board.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-party-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func frames() -> void:
	await process_frame
	await process_frame

func board() -> Window:
	for child in current_scene.get_children():
		if child.get_script() == Board: return child
	return null

func _run() -> void:
	create_timer(40).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("编队角色 A")
	await frames()
	var run: RefCounted = flow.run
	var unchanged: Dictionary = run.character.duplicate(true)
	check(not flow.familia_service("join") and run.character == unchanged, "未交付资格不能加入")
	check(run.quest_service("hunt", "accept") and run.depart_city(7), "接初次讨伐后出发")
	for i in range(40):
		if run.battles_won >= 3: break
		if run.enter(run.node(run.current).next[0]) == "battle": run.finish_battle(run.character, true)
	run.begin_return()
	for i in range(100):
		if run.phase == "returned": break
		run.step_return(run.return_targets()[0].key)
		if not run.pending.is_empty(): run.finish_battle(run.character, true)
	check(run.enter_city() and run.quest_service("hunt", "claim"), "回城交付讨伐取得资格")
	current_scene.show_floor_map()
	current_scene.city_buttons.familia.pressed.emit()
	check(board() != null and not board().buttons.join.disabled, "城市点击打开可加入的眷族菜单")
	board().buttons.join.pressed.emit()
	board().buttons.enlist.pressed.emit()
	check(run.character.party_enlisted and flow.party_companion().max_hp == 28, "点击加入和招募成功")
	var capture := OS.get_environment("TENSEI_FAMILIA_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	board().queue_free()
	await frames()
	check(flow.city_service("rest") and run.depart_city(11), "旅店休整后双人出发")
	var profile_id: String = flow.profile.id
	var initial: String = flow.saves.save_record(run, flow.profile, "双人出发前")
	check(not initial.is_empty() and run.enter("1a") == "battle", "双人入口保存后遇敌")
	current_scene.start_encounter()
	await create_timer(1.2).timeout
	check(current_scene.battle.ally.size() > 0 and current_scene.targets.size() == 3, "实际远征双人战斗有三个目标")
	current_scene.battle.ally.hp = 9
	check(current_scene.gm_kill_enemy(), "GM沿实际双人战斗结算")
	check(run.character.party_hp == 9 and run.character.growth_pending.is_empty() and flow.progress.data.familias.dawn.squire_xp == 2, "生命回写和共享成长各一次")
	check(not flow.settle_battle(run.character, flow.party_companion(), true), "重复结算不能发成长")
	check(flow.load_exploration(profile_id, initial), "读取较早双人记录")
	await frames()
	run = flow.run
	check(run.character.party_hp == 28 and flow.progress.data.familias.dawn.squire_xp == 2, "个人生命恢复旧时点，共享成长保持新值")
	check(run.enter("1a") == "battle" and flow.settle_battle(run.character, flow.party_companion(), true), "重走同一记录可正常结算战利品")
	check(flow.progress.data.familias.dawn.squire_xp == 2, "相同远征节点清理事件不复制共享成长")
	for i in range(40):
		if flow.progress.data.familias.dawn.contribution >= 5: break
		if run.enter(run.node(run.current).next[0]) == "battle":
			flow.settle_battle(run.character, flow.party_companion(), true)
	check(flow.party_companion().level == 2 and flow.party_companion().max_hp == 31 and flow.progress.guild_level() == 2, "五次参战胜利提高卫士生命上限和组织等级")
	run.character.hp = 0
	run.character.party_hp = 9
	check(run.has_living_party() and not run.save_data().is_empty(), "主角倒下但队友存活可以保存")
	check(Run.from_save(run.save_data()) != null, "倒下主角的合法队伍快照可恢复")
	check(run.begin_return(), "存活队友能够带队返程")
	for i in range(120):
		if run.phase == "returned": break
		run.step_return(run.return_targets()[0].key)
		if not run.pending.is_empty(): flow.settle_battle(run.character, flow.party_companion(), true)
	check(run.character.hp == 0 and run.enter_city(), "营地不复活倒下主角，队友可安全回城")
	current_scene.show_floor_map()
	check(not current_scene.city_buttons.rest.disabled, "队伍受伤时旅店按钮可用")
	current_scene.city_buttons.rest.pressed.emit()
	check(run.character.hp == run.character.max_hp and run.character.party_hp == flow.party_companion().max_hp, "旅店恢复全部队员")
	var grown_xp: int = flow.progress.data.familias.dawn.squire_xp
	check(flow.familia_service("dismiss") and not run.character.party_enlisted, "城市移除队友不清零共享成长")
	flow.start_character("编队角色 B")
	await frames()
	flow.run.character.quests.hunt = "claimed"
	check(flow.familia_service("join") and flow.familia_service("enlist"), "新角色达成个人资格后加入旧眷族")
	check(flow.run.character.level == 1 and flow.party_companion().experience == grown_xp and flow.party_companion().level >= 2, "新角色个人成长独立，卫士继承已有培养")
	flow.run.character.hp = 0
	flow.run.character.party_hp = 0
	check(not flow.run.has_living_party() and flow.run.save_data().is_empty() and not flow.run.depart_city(9), "全队倒下不允许保存或探索")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]: DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("PARTY EXPEDITION CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
