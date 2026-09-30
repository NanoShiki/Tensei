extends SceneTree

const LibraryTest = preload("res://Tests/test_save_library.gd")
const Progress = preload("res://Scripts/Core/player_progress.gd")
var failures := 0
var base := "user://test-library-family-recovery-" + Crypto.new().generate_random_bytes(8).hex_encode()

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
	flow.start_character("成长恢复角色")
	await frames()
	flow.run.character.quests.hunt = "claimed"
	check(flow.familia_service("join") and flow.familia_service("enlist"), "建立独立共享档案和编队")
	flow.run.depart_city(7)
	var run: RefCounted = flow.run
	var owner: String = run.character.player_id
	var profile_id: String = flow.profile.id
	var initial: String = flow.saves.save_record(run, flow.profile, "起点")
	DirAccess.make_dir_absolute(flow.progress.base_path + ".tmp")
	check(run.enter("1a") == "battle" and flow.settle_battle(run.character, flow.party_companion(), true), "共享不可写仍完成个人战斗结算")
	check(run.character.growth_pending.size() == 1 and run.character.gold == 3 and flow.progress.data.familias.dawn.squire_xp == 0, "共享提交失败保留待重试事件，不伪造成功")
	var queued: String = flow.saves.save_record(run, flow.profile, "待同步")
	check(not queued.is_empty() and flow.saves.read_record(profile_id, queued).run.character.growth_pending.size() == 1, "个人记录持久化待同步事件")
	DirAccess.remove_absolute(flow.progress.base_path + ".tmp")
	check(flow.load_exploration(profile_id, queued), "存储恢复后读档并重试成长")
	await frames()
	check(flow.run.character.growth_pending.is_empty() and flow.progress.data.familias.dawn.squire_xp == 2, "恢复后共享贡献只提交一次")
	check(flow.load_exploration(profile_id, queued), "重复读取仍含事件的旧记录")
	await frames()
	check(flow.progress.data.familias.dawn.squire_xp == 2 and flow.run.character.growth_pending.is_empty(), "已提交事件从个人待同步列表清除，不再次奖励")
	var retained: Dictionary = {}
	for suffix in [".0.save", ".1.save"]:
		var path: String = flow.progress.base_path + suffix
		retained[path] = FileAccess.get_file_as_bytes(path)
		DirAccess.remove_absolute(path)
	var current_run = flow.run
	var recent: PackedByteArray = FileAccess.get_file_as_bytes(base + ".recent.cfg")
	check(not flow.load_exploration(profile_id, initial) and flow.run == current_run and "共享" in flow.saves.message, "缺少共享档案时拒绝读档并保留当前会话")
	check(FileAccess.get_file_as_bytes(base + ".recent.cfg") == recent, "拒绝读取不更改最近记录入口")
	for path in retained:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(retained[path])
		file.close()
	check(flow.load_exploration(profile_id, initial), "恢复共享备份可继续读取个人记录")
	await frames()
	check(flow.run.character.player_id == owner and flow.progress.data.familias.dawn.squire_xp == 2, "个人旧档不回退玩家共享成长")
	var wrong := Progress.initial()
	check(flow.progress._commit(wrong, flow.progress.inspect()), "故障夹具写入另一玩家的共享档案")
	current_run = flow.run
	check(not flow.load_exploration(profile_id, queued) and flow.run == current_run, "共享归属不符时拒绝替换当前角色")
	var shape: Dictionary = current_run.save_data()
	shape.character.party_hp = 41
	check(load("res://Scripts/Exploration/floor_run.gd").from_save(shape) == null, "拒绝越界队友生命")
	shape = current_run.save_data()
	shape.character.player_id = "foreign"
	check(load("res://Scripts/Exploration/floor_run.gd").from_save(shape) == null, "拒绝无效共享所有者标识")
	var malformed := Progress.initial()
	malformed.familias.dawn.events["event"] = 1
	malformed.familias.dawn.contribution = 1
	malformed.familias.dawn.squire_xp = 2
	check(not Progress.valid(malformed), "贡献账本必须严格布尔类型")
	current_run.phase = "city"
	current_run.character.hp = 0
	current_run.character.party_hp = 9
	current_scene.show_floor_map()
	var untouched: Dictionary = current_run.character.duplicate(true)
	current_scene.city_buttons.rest.pressed.emit()
	check("共享档案不可用" in current_run.message and current_run.character == untouched, "旅店无法确认队友时显示原因且不部分恢复")
	current_scene.city_buttons.familia.pressed.emit()
	var windows := 0
	for child in current_scene.get_children():
		if child is Window and child.visible: windows += 1
	current_scene._open_familia()
	current_scene._open_jobs()
	var after_windows := 0
	for child in current_scene.get_children():
		if child is Window and child.visible: after_windows += 1
	check(windows == 1 and after_windows == 1, "已有城市窗口时不重复打开眷族或职业窗口")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]: DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("FAMILIA RECOVERY CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
