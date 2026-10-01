extends SceneTree

const Equipment = preload("res://Scripts/UI/equipment_panel.gd")
const Jobs = preload("res://Scripts/Character/job_library.gd")
const Run = preload("res://Scripts/Exploration/floor_run.gd")
const State = preload("res://Scripts/Battle/battle_state.gd")
const Store = preload("res://Scripts/Core/expedition_save.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-armor-" + Crypto.new().generate_random_bytes(8).hex_encode()

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
	create_timer(30).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("护甲验收")
	await frames()
	flow.run.character.gold = 30
	flow.run.character.scrap = 12
	var before_record: String = flow.saves.save_record(flow.run, flow.profile, "铁甲前")
	current_scene.show_floor_map()
	current_scene.city_buttons.equipment.pressed.emit()
	var equipment: Window
	for child in current_scene.get_children():
		if child.get_script() == Equipment: equipment = child
	check(equipment != null and not equipment.buttons.forge_iron_armor.disabled, "真实工坊包含基础铁甲")
	equipment.buttons.forge_iron_armor.pressed.emit()
	check(flow.run.character.gold == 24 and flow.run.character.scrap == 9 and flow.run.character.armor == "iron_armor" and flow.run.character.armors == ["cloth_armor", "iron_armor"] and flow.run.character.ac == 15, "打造扣6金币3铁片、保留布衣、铁甲独立增加AC")
	check(flow.run.character.weapon == "training_sword" and flow.progress.data.familias.ember.contribution == 1 and flow.run.character.familia_id.is_empty(), "护甲不改武器或归属，为服务方贡献一次")
	var gold: int = flow.run.character.gold
	equipment.buttons.armor_cloth_armor.pressed.emit()
	check(flow.run.character.ac == 14 and flow.run.character.gold == gold and equipment.buttons.forge_iron_armor.disabled, "切布衣只恢复基础AC，仍禁止重复制作铁甲")
	equipment.buttons.armor_iron_armor.pressed.emit()
	for id in Jobs.ENTRIES:
		check(flow.run.job_service(id) or flow.run.character.job_id == id, "四职业可选择")
		check(flow.run.character.ac == Jobs.ENTRIES[id].ac + 1 and flow.run.character.attack == Jobs.ENTRIES[id].attack and flow.run.character.dex == Jobs.ENTRIES[id].dex, "职业切换保留铁甲加值且不改变其他加值")
	flow.run.job_service("swordsman")
	equipment._refresh()
	var capture := OS.get_environment("TENSEI_ARMOR_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await frames()
		equipment.rows.get_parent().scroll_vertical = 10000
		await frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	equipment.queue_free()
	await frames()
	var after_record: String = flow.saves.save_record(flow.run, flow.profile, "铁甲后")
	check(flow.load_exploration(flow.profile.id, after_record), "磁盘恢复护甲装备")
	await frames()
	check(flow.run.character.armor == "iron_armor" and flow.run.character.ac == 15, "当前护甲及持有列表恢复")
	var iron: Dictionary = flow.run.character.duplicate(true)
	check(flow.equip_armor("cloth_armor"), "切布衣用于可控命中比较")
	var cloth: Dictionary = flow.run.character.duplicate(true)
	var seed_value := -1
	for i in range(1000):
		var random := RandomNumberGenerator.new()
		random.seed = i
		if random.randi_range(1, 20) == 11:
			seed_value = i
			break
	check(seed_value >= 0, "找到边界攻击骰")
	var unarmored := State.new()
	var armored := State.new()
	unarmored.setup(cloth, 1, 7)
	armored.setup(iron, 1, 7)
	for battle in [unarmored, armored]:
		battle.cursor = battle.order.find("goblin")
		battle.rng.seed = seed_value
		check(battle.enemy_turn(), "同一攻击种子执行敌方行动")
	check(unarmored.hero.hp < armored.hero.hp and armored.hero.hp == iron.hp, "同骰命中14布衣、未命中15铁甲，实际防御发挥作用")
	check(flow.load_exploration(flow.profile.id, before_record), "读取打造前记录")
	await frames()
	check(flow.run.character.armor == "cloth_armor" and flow.city_service("forge_armor") and flow.progress.data.familias.ember.contribution == 1, "旧个人记录重新支付制作，护甲共享事件去重")
	check(flow.equip_armor("cloth_armor"), "准备旧记录布衣数据")
	var legacy: Dictionary = flow.run.save_data()
	legacy.character.erase("armor")
	legacy.character.erase("armors")
	check(Run.from_save(legacy) != null and Run.from_save(legacy).character.armor == "cloth_armor", "旧缺护甲字段补布衣，不追溯铁甲")
	var store := Store.new()
	store.base_path = base + "-legacy"
	var payload := var_to_bytes(legacy)
	var file := FileAccess.open(store.base_path + ".0.save", FileAccess.WRITE)
	file.store_var({"version": Store.VERSION, "content_version": "demo-enemyteams-1", "generation": 1, "payload": payload, "checksum": store._checksum(payload)}, false)
	file.close()
	var bytes := FileAccess.get_file_as_bytes(store.base_path + ".0.save")
	check(not store.inspect().is_empty() and store.inspect().run.character.armor == "cloth_armor" and FileAccess.get_file_as_bytes(store.base_path + ".0.save") == bytes, "旧版本磁盘读取及原字节保留")
	DirAccess.remove_absolute(store.base_path + ".0.save")
	var invalid: Dictionary = flow.run.save_data()
	invalid.character.armors = ["cloth_armor", "cloth_armor"]
	check(Run.from_save(invalid) == null, "重复护甲列表拒绝")
	invalid = flow.run.save_data()
	invalid.character.armor = "unknown"
	check(Run.from_save(invalid) == null, "未知护甲拒绝")
	invalid = flow.run.save_data()
	invalid.character.armor = "iron_armor"
	invalid.character.armors = ["cloth_armor"]
	invalid.character.ac = 15
	check(Run.from_save(invalid) == null, "未持有的当前护甲拒绝")
	invalid = flow.run.save_data()
	invalid.character.ac = 99
	check(Run.from_save(invalid) == null, "防御与职业、护甲不一致拒绝")
	flow.run.depart_city(7)
	var before: Dictionary = flow.run.character.duplicate(true)
	check(not flow.equip_armor("iron_armor") and flow.run.character == before, "探索不能切换护甲")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix): DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("ARMOR EQUIPMENT CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
