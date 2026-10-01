extends SceneTree

const Run = preload("res://Scripts/Exploration/floor_run.gd")
const State = preload("res://Scripts/Battle/battle_state.gd")
const Store = preload("res://Scripts/Core/expedition_save.gd")
var failures := 0
var base := "user://test-city-" + Crypto.new().generate_random_bytes(8).hex_encode()

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
	create_timer(30).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("城市角色")
	await frames()
	var run: RefCounted = flow.run
	var profile_id: String = flow.profile.id
	check(run.phase == "city" and current_scene.city_buttons.has("depart"), "新角色先进入城市")
	check(current_scene.city_buttons.forge.disabled and current_scene.city_buttons.potion.disabled, "材料与金币不足时服务不可用")
	var before: Dictionary = run.character.duplicate(true)
	check(not run.city_service("forge") and not run.city_service("potion") and run.character == before, "无资源交易不部分扣款")
	var old_id: String = run.run_id
	current_scene.city_buttons.depart.pressed.emit()
	check(run.phase == "descending" and run.run_id != old_id and run.floor_number == 1, "出发创建新远征")
	check(not run.city_service("rest"), "探索途中不能调用城市服务")
	for i in range(30):
		if run.battles_won >= 3: break
		var id: String = run.node(run.current).next[0]
		if run.enter(id) == "battle":
			run.finish_battle(run.character, true)
			var wallet: Dictionary = run.character.duplicate(true)
			check(not run.finish_battle(run.character, true) and run.character == wallet, "重复战斗结算不重复掉落")
	check(run.character.gold == 9 and run.character.scrap == 3, "三次胜利各获得3金币和1铁片")
	run.begin_return()
	for i in range(80):
		if run.phase == "returned": break
		run.step_return(run.return_targets()[0].key)
		if not run.pending.is_empty(): run.finish_battle(run.character, true)
	check(run.phase == "returned", "可带战利品正常返程")
	var gold: int = run.character.gold
	var scrap: int = run.character.scrap
	current_scene.show_floor_map()
	current_scene.city_buttons.enter.pressed.emit()
	check(run.phase == "city" and run.character.gold == gold and run.character.scrap == scrap, "进入城市不重复发奖")
	check(not run.enter_city(), "重复入城不触发结算")
	run.character.hp = 11
	current_scene.show_floor_map()
	current_scene.city_buttons.rest.pressed.emit()
	check(run.character.hp == run.character.max_hp, "旅店恢复生命")
	var potions: int = run.character.potions
	current_scene.city_buttons.potion.pressed.emit()
	check(run.character.gold == gold - 3 and run.character.potions == potions + 1, "药水购买扣款与产出一致")
	current_scene.city_buttons.forge.pressed.emit()
	check(run.character.gold == gold - 9 and run.character.scrap == scrap - 3 and run.character.weapon == "iron_sword", "打造扣除配方并装备铁剑")
	before = run.character.duplicate(true)
	check(not run.city_service("forge") and run.character == before, "已打造时重复操作不扣资源")
	var record_id: String = flow.saves.save_record(run, flow.profile, "城市打造后")
	check(not record_id.is_empty(), "城市状态可沿用原存档记录保存")
	check(flow.load_exploration(profile_id, record_id), "城市存档可读取")
	await frames()
	run = flow.run
	check(run.phase == "city" and run.character == before and current_scene.city_buttons.forge.disabled, "读取恢复城市、余额、补给与武器")
	old_id = run.run_id
	current_scene.city_buttons.depart.pressed.emit()
	check(run.run_id != old_id and run.character == before and run.steps_taken == 0 and flow.profile.id == profile_id, "下一趟保留同角色装备资产并重建地图")
	check(flow.saves.read_record(profile_id, record_id).run.character == before, "新远征不改写旧快照")
	# 同一随机种子隔离装备效果：仅剑技伤害+2，命中率保持一致。
	var hits := 0
	for seed_value in range(20):
		var wood := State.new()
		var iron := State.new()
		var wooden_hero := before.duplicate(true)
		wooden_hero.weapon = "training_sword"
		wood.setup(wooden_hero, 1, seed_value)
		iron.setup(before, 1, seed_value)
		wood.cursor = wood.order.find("lorn")
		iron.cursor = iron.order.find("lorn")
		check(wood.hit_chance("strike") == iron.hit_chance("strike"), "打造不误改命中加值")
		wood.use_ability("strike", "goblin")
		iron.use_ability("strike", "goblin")
		if wood.enemy.hp < wood.enemy.max_hp:
			hits += 1
			check(iron.enemy.hp == wood.enemy.hp - 2, "铁剑在相同命中和骰子下多造成2伤害")
	check(hits > 0, "装备效果测试实际覆盖命中")
	var legacy: Dictionary = run.save_data()
	for key in ["gold", "scrap", "weapon"]: legacy.character.erase(key)
	var store := Store.new()
	store.base_path = base + "-legacy"
	var payload := var_to_bytes(legacy)
	var file := FileAccess.open(store.base_path + ".0.save", FileAccess.WRITE)
	file.store_var({"version": 1, "content_version": "demo-map-1", "generation": 1, "payload": payload, "checksum": store._checksum(payload)})
	file.close()
	var restored: Dictionary = store.inspect()
	check(not restored.is_empty() and restored.run.character.gold == 0 and restored.run.character.scrap == 0 and restored.run.character.weapon == "training_sword", "旧地图记录兼容零余额及木剑")
	for suffix in [".0.save", ".1.save", ".tmp", ".recent.cfg"]:
		if FileAccess.file_exists(base + suffix): DirAccess.remove_absolute(base + suffix)
	DirAccess.remove_absolute(store.base_path + ".0.save")
	for suffix in [".0.save", ".1.save", ".tmp"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix): DirAccess.remove_absolute(flow.progress.base_path + suffix)
	var directory := base + ".profiles/" + profile_id
	for name in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory + "/" + name)
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(base + ".profiles")
	print("CITY LOOP CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
