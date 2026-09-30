extends SceneTree

const Jobs = preload("res://Scripts/Character/job_library.gd")
const Characters = preload("res://Scripts/Character/character_library.gd")
const State = preload("res://Scripts/Battle/battle_state.gd")
const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Board = preload("res://Scripts/UI/job_board.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-jobs-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func frames() -> void:
	await process_frame
	await process_frame

func _run() -> void:
	create_timer(35).timeout.connect(func(): quit(1))
	var run := Run.new()
	run.setup(7)
	var before: Dictionary = run.character.duplicate(true)
	check(not run.job_service("mage") and run.character == before, "探索途中不能切职业")
	run.phase = "city"
	check(not run.job_service("missing") and run.character == before, "未知职业拒绝且不变状态")
	for id in Jobs.ENTRIES:
		run.character = Characters.resolve()
		if id != run.character.job_id: check(run.job_service(id), "城市选择基础职业")
		var snapshot: Dictionary = run.save_data()
		check(Run.from_save(snapshot) != null and Run.from_save(snapshot).character.job_id == id, "职业与属性快照合法恢复")
		before = run.character.duplicate(true)
		check(not run.job_service(id) and run.character == before, "重复选择无副作用")
		var job: Dictionary = Jobs.ENTRIES[id]
		var state := State.new()
		state.setup(run.character, 1, 7)
		state.cursor = state.order.find("lorn")
		var rng_state: int = state.rng.state
		if job.level > 1:
			check(not state.can_target(job.skill, "goblin") and not state.use_ability(job.skill, "goblin") and state.action == 1 and state.rng.state == rng_state, "未到等级不能装备技能或消耗随机数")
		Characters.add_experience(run.character, 10)
		state.setup(run.character, 1, 7)
		state.cursor = state.order.find("lorn")
		check(state.can_target(job.skill, "goblin") and state.use_ability(job.skill, "goblin") and state.action == 0, "已达等级的职业技能合法消耗一次行动")
		state.setup(run.character, 1, 7, false, State.practice_companion())
		state.cursor = state.order.find("squire")
		check(Jobs.skills(state.current_unit())[1] == "power" and not state.use_ability("arcane_bolt", "goblin"), "主角职业不污染卫士技能")
	# 同种子隔离铁剑：法术不吃武器加值，物理技能仍吃 +2。
	var hits := 0
	for id in ["mage", "archer", "rogue"]:
		var hero := Characters.resolve()
		Jobs.apply(hero, id)
		Characters.add_experience(hero, 10)
		for seed_value in range(20):
			var wood := State.new()
			var iron := State.new()
			wood.setup(hero, 1, seed_value)
			hero.weapon = "iron_sword"
			iron.setup(hero, 1, seed_value)
			hero.weapon = "training_sword"
			wood.cursor = wood.order.find("lorn")
			iron.cursor = iron.order.find("lorn")
			var skill: String = Jobs.ENTRIES[id].skill
			check(wood.hit_chance(skill) == iron.hit_chance(skill), "装备不误改职业技能命中")
			wood.use_ability(skill, "goblin")
			iron.use_ability(skill, "goblin")
			if wood.enemy.hp < wood.enemy.max_hp:
				hits += 1
				check(iron.enemy.hp == wood.enemy.hp - (0 if id == "mage" else 2), "职业技能装备加值按法术与物理区分")
	check(hits > 0, "实际覆盖职业技能命中")
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.start_character("职业试玩")
	await frames()
	current_scene.city_buttons.job.pressed.emit()
	var window: Window
	for child in current_scene.get_children():
		if child.get_script() == Board: window = child
	check(window != null and window.buttons.size() == 4, "点击城市入口可查看四职业")
	current_scene._open_jobs()
	var windows := 0
	for child in current_scene.get_children():
		if child is Window and child.visible: windows += 1
	check(windows == 1, "职业窗口不可重复堆叠")
	window.buttons.mage.pressed.emit()
	check(flow.run.character.job_id == "mage" and flow.run.character.ac == 12 and "法师" in current_scene.city_buttons.job.text, "点击职业同步城市属性与入口")
	var capture := OS.get_environment("TENSEI_JOB_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	window.queue_free()
	await frames()
	Characters.add_experience(flow.run.character, 10)
	var profile_id: String = flow.profile.id
	var record: String = flow.saves.save_record(flow.run, flow.profile, "法师等级2")
	check(not record.is_empty() and flow.load_exploration(profile_id, record), "职业可通过角色记录读取")
	await frames()
	check(flow.run.character.job_id == "mage" and flow.run.character.level == 2, "恢复职业及技能资格")
	flow.run.depart_city(7)
	flow.run.enter("1a")
	current_scene.start_encounter()
	await create_timer(1.2).timeout
	current_scene.battle.cursor = current_scene.battle.order.find("lorn")
	current_scene.battle.action = 1
	current_scene._refresh()
	check(current_scene.buttons.has("arcane_bolt") and not current_scene.buttons.has("power"), "实际战斗第二技能随职业变化")
	current_scene.buttons.arcane_bolt.pressed.emit()
	check(current_scene.selected == "arcane_bolt" and not current_scene.targets.goblin.disabled, "职业技能仍先选择再点敌方目标")
	current_scene.targets.goblin.pressed.emit()
	await create_timer(0.6).timeout
	check(current_scene.battle.action == 0, "实际职业技能点目标消耗一次行动")
	check(current_scene.gm_kill_enemy(), "职业战斗正常走GM结算")
	var invalid: Dictionary = flow.run.save_data()
	invalid.character.job_id = "unknown"
	check(Run.from_save(invalid) == null, "拒绝未知职业内容")
	invalid = flow.run.save_data()
	invalid.character.ac = 99
	check(Run.from_save(invalid) == null, "拒绝职业与属性不一致")
	var legacy := Run.new()
	legacy.setup(9)
	var old: Dictionary = legacy.save_data()
	old.character.erase("job_id")
	check(Run.from_save(old).character.job_id == "swordsman", "旧记录默认剑士保持原属性")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	print("JOB CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
