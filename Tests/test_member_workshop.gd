extends SceneTree

const WorkshopPanel = preload("res://Scripts/UI/equipment_panel.gd")
const Run = preload("res://Scripts/Exploration/floor_run.gd")
const State = preload("res://Scripts/Battle/battle_state.gd")
const Characters = preload("res://Scripts/Character/character_library.gd")
const Jobs = preload("res://Scripts/Character/job_library.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-member-workshop-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	await process_frame

func _run() -> void:
	create_timer(35).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("会员装备")
	await frames()
	flow.run.character.gold = 30
	flow.run.character.scrap = 10
	check(flow.city_service("forge"), "所有归属可制作基础铁剑")
	check(flow.equip_weapon("training_sword") and flow.familia_service("join_ember"), "持有铁剑未装备也保持炉心资格")
	var before: Dictionary = flow.run.character.duplicate(true)
	check(not flow.city_service("forge") and flow.run.character == before, "切回木剑不能重复制作持有的铁剑")
	current_scene.show_floor_map()
	current_scene.city_buttons.equipment.pressed.emit()
	var panel: Window
	for child in current_scene.get_children():
		if child.get_script() == WorkshopPanel: panel = child
	check(panel != null and not panel.buttons.forge_tempered_sword.disabled, "实际工坊按钮开放合法会员配方")
	current_scene._open_equipment()
	var count := 0
	for child in current_scene.get_children():
		if child.get_script() == WorkshopPanel: count += 1
	check(count == 1, "工坊窗口不重复堆叠")
	before = flow.run.character.duplicate(true)
	var stored_bytes := {}
	for suffix in [".0.save", ".1.save"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix):
			stored_bytes[suffix] = FileAccess.get_file_as_bytes(flow.progress.base_path + suffix)
			DirAccess.remove_absolute(flow.progress.base_path + suffix)
	panel.buttons.forge_tempered_sword.pressed.emit()
	check(flow.run.character == before and panel.buttons.forge_tempered_sword.disabled, "开窗后共享缺失，执行实时拒绝会员制作，不部分扣款")
	for suffix in stored_bytes:
		var file := FileAccess.open(flow.progress.base_path + suffix, FileAccess.WRITE)
		file.store_buffer(stored_bytes[suffix])
		file.close()
	panel._refresh()
	check(not panel.buttons.forge_tempered_sword.disabled, "恢复备份后同窗口可刷新资格")
	flow.run.character.familia_id = "dawn"
	before = flow.run.character.duplicate(true)
	panel.buttons.forge_tempered_sword.pressed.emit()
	check(flow.run.character == before and panel.buttons.forge_tempered_sword.disabled, "执行时重新检查当前归属，不沿用开窗会员资格")
	flow.run.character.familia_id = "ember"
	panel._refresh()
	panel.buttons.forge_tempered_sword.pressed.emit()
	check(flow.run.character.gold == 15 and flow.run.character.scrap == 3 and flow.run.character.weapon == "tempered_sword" and flow.run.character.weapons == ["training_sword", "iron_sword", "tempered_sword"], "制作扣9金币4铁片，保留旧武器并自动装备新武器")
	check(flow.progress.data.familias.ember.contribution == 2 and panel.buttons.forge_tempered_sword.disabled, "第二配方贡献一次并禁用重复制作")
	panel.buttons.equip_iron_sword.pressed.emit()
	check(flow.run.character.weapon == "iron_sword" and flow.run.character.gold == 15 and flow.run.character.scrap == 3, "实际装备按钮只切装备，不扣资源")
	panel.buttons.equip_tempered_sword.pressed.emit()
	var capture := OS.get_environment("TENSEI_EQUIPMENT_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await frames()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture) == OK, "会员工坊截图")
		panel.rows.get_parent().scroll_vertical = 100000
		await frames()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture.get_basename() + "-equipment.png") == OK, "滚动装备选择截图")
	panel.queue_free()
	await frames()
	flow.run.character.quests.hunt = "claimed"
	check(flow.familia_service("join") and flow.run.character.weapon == "tempered_sword" and flow.run.character.weapons.size() == 3, "转会保留永久个人武器及其效果")
	var record: String = flow.saves.save_record(flow.run, flow.profile, "转会后的淬火装备")
	before = flow.run.character.duplicate(true)
	check(flow.load_exploration(flow.profile.id, record), "武器持有列表与当前装备恢复")
	await frames()
	check(flow.run.character == before, "存档恢复精确个人装备")
	flow.run.depart_city(7)
	before = flow.run.character.duplicate(true)
	check(not flow.equip_weapon("training_sword") and flow.run.character == before, "探索中拒绝切装备且无副作用")
	var old := Run.new()
	old.setup(7)
	old.character.weapon = "iron_sword"
	var snapshot: Dictionary = old.save_data()
	snapshot.character.erase("weapons")
	check(Run.from_save(snapshot) != null and Run.from_save(snapshot).character.weapons == ["training_sword", "iron_sword"], "旧铁剑存档补持有列表，保留已装备铁剑")
	snapshot = flow.run.save_data()
	snapshot.character.weapons = ["training_sword", "tempered_sword"]
	check(Run.from_save(snapshot) == null, "缺基础铁剑的淬火装备拒绝")
	snapshot.character.weapons = ["training_sword", "iron_sword", "iron_sword"]
	check(Run.from_save(snapshot) == null, "重复持有列表拒绝")
	var hits := 0
	for job_id in Jobs.ENTRIES:
		for seed_value in range(20):
			var hero := Characters.resolve()
			Jobs.apply(hero, job_id)
			Characters.add_experience(hero, 10)
			hero.weapon = "iron_sword"
			var iron := State.new()
			iron.setup(hero, 1, seed_value)
			hero.weapon = "tempered_sword"
			var tempered := State.new()
			tempered.setup(hero, 1, seed_value)
			iron.cursor = iron.order.find("lorn")
			tempered.cursor = tempered.order.find("lorn")
			var skill: String = Jobs.ENTRIES[job_id].skill
			check(iron.hit_chance(skill) == tempered.hit_chance(skill), "淬火不误改命中")
			iron.use_ability(skill, "goblin")
			tempered.use_ability(skill, "goblin")
			if iron.enemy.hp < iron.enemy.max_hp:
				hits += 1
				check(tempered.enemy.hp == maxi(0, iron.enemy.hp - (0 if job_id == "mage" else 1)), "相同随机种子物理技能淬火多1，法术不加成")
	check(hits > 0, "装备效果实际覆盖命中")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix): DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("MEMBER WORKSHOP CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
