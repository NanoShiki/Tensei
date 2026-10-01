extends SceneTree

const LibraryTest = preload("res://Tests/test_save_library.gd")
const Run = preload("res://Scripts/Exploration/floor_run.gd")
var failures := 0
var base := "user://test-library-forge-" + Crypto.new().generate_random_bytes(8).hex_encode()

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
	flow.start_character("未加入的工坊顾客")
	await frames()
	var before: Dictionary = flow.run.character.duplicate(true)
	check(not flow.city_service("forge") and flow.run.character == before and flow.progress.inspect().is_empty(), "不足资源不初始化共享或改变角色")
	flow.run.character.gold = 6
	flow.run.character.scrap = 3
	var profile_id: String = flow.profile.id
	var before_record: String = flow.saves.save_record(flow.run, flow.profile, "打造前")
	current_scene.show_floor_map()
	current_scene.city_buttons.forge.pressed.emit()
	check(flow.run.character.familia_id.is_empty() and not flow.run.character.player_id.is_empty(), "普通顾客绑定共享身份且不改变归属")
	check(flow.run.character.weapon == "iron_sword" and flow.run.character.gold == 0 and flow.run.character.scrap == 0 and flow.run.character.forge_pending.is_empty(), "实际打造扣款产出与同步成功")
	check(flow.progress.data.familias.ember.contribution == 1 and flow.progress.data.familias.dawn.contribution == 0, "只为服务方炉心增加一次贡献")
	var owner: String = flow.run.character.player_id
	var after_record: String = flow.saves.save_record(flow.run, flow.profile, "打造后未加入")
	check(flow.load_exploration(profile_id, after_record), "有共享身份的未加入角色可以读档")
	await frames()
	check(flow.run.character.familia_id.is_empty() and flow.run.character.player_id == owner, "读档不强制加入")
	check(flow.load_exploration(profile_id, before_record), "读取打造前的个人时点")
	await frames()
	check(flow.run.character.weapon == "training_sword" and flow.run.character.player_id.is_empty(), "个人资源与身份按旧快照恢复")
	check(flow.city_service("forge") and flow.progress.data.familias.ember.contribution == 1, "同角色同配方重复制作不刷共享贡献")
	check(flow.familia_service("join_ember") and flow.run.character.player_id == owner, "顾客身份加入炉心保持同一所有者")
	check(flow.workshop_status().contains("贡献 1"), "界面状态显示共享贡献")
	for i in range(2):
		flow.start_character("新工匠%d" % i)
		await frames()
		flow.run.character.gold = 6
		flow.run.character.scrap = 3
		if i == 1:
			flow.run.character.quests.hunt = "claimed"
			check(flow.familia_service("join"), "远征眷族成员仍可用基础打造")
		check(flow.city_service("forge") and flow.run.character.player_id == owner, "不同角色合法制作共用玩家档案")
	check(flow.progress.data.familias.ember.contribution == 3 and flow.progress.guild_level("ember") == 2 and flow.progress.data.familias.dawn.contribution == 0, "三名角色各一次贡献升炉心二级，原组织保持不变")
	current_scene.show_floor_map()
	var capture := OS.get_environment("TENSEI_FORGE_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await frames()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture) == OK, "工坊状态截图")
	before = flow.run.character.duplicate(true)
	check(not flow.city_service("forge") and flow.run.character == before, "已装备重复打造不扣资源或增加贡献")
	var old: Dictionary = flow.run.save_data()
	old.character.erase("forge_pending")
	check(Run.from_save(old) != null and Run.from_save(old).character.forge_pending.is_empty(), "旧记录在内存补空贡献待同步，不追溯旧装备")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix): DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("FORGE GROWTH CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
