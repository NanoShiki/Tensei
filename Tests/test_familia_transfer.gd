extends SceneTree

const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Board = preload("res://Scripts/UI/familia_board.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-transfer-" + Crypto.new().generate_random_bytes(8).hex_encode()

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

func confirmation() -> ConfirmationDialog:
	for child in board().get_children():
		if child is ConfirmationDialog: return child
	return null

func _run() -> void:
	create_timer(35).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("转会测试")
	await frames()
	var initial: Dictionary = flow.run.character.duplicate(true)
	check(not flow.familia_service("join_ember") and flow.run.character == initial, "未打造铁剑时拒绝炉心资格")
	flow.run.character.quests.hunt = "claimed"
	flow.run.character.gold = 6
	flow.run.character.scrap = 3
	check(flow.city_service("forge") and flow.run.character.weapon == "iron_sword", "实际工坊打造满足炉心资格")
	check(flow.familia_service("join"), "先加入晨行")
	for i in range(5): check(flow.progress.award_victory("fixture-%d" % i, flow.run.character.player_id, ["squire", "scout"]), "建立已培养成员夹具")
	check(flow.familia_service("enlist") and flow.familia_service("enlist_scout"), "招募两名成长成员")
	check(flow.quest_service("familia_patrol", "accept"), "接取成员任务后可暂停")
	flow.run.depart_city(7)
	check(not flow.familia_service("join_ember"), "探索中禁止转会")
	flow.run.enter("1a")
	flow.settle_battle(flow.run.character, flow.party_companion(), true, flow.party_companion("scout"))
	flow.run.begin_return()
	for i in range(20):
		if flow.run.phase == "returned": break
		flow.run.step_return(flow.run.return_targets()[0].key)
		if not flow.run.pending.is_empty(): flow.settle_battle(flow.run.character, flow.party_companion(), true, flow.party_companion("scout"))
	flow.run.enter_city()
	current_scene.show_floor_map()
	var profile_id: String = flow.profile.id
	var dawn_record: String = flow.saves.save_record(flow.run, flow.profile, "晨行编队")
	var shared: Dictionary = flow.progress.data.duplicate(true)
	var before: Dictionary = flow.run.character.duplicate(true)
	current_scene.city_buttons.familia.pressed.emit()
	check(not board().buttons.join_ember.disabled, "炉心UI资格开放")
	board().buttons.join_ember.pressed.emit()
	check(confirmation() != null and flow.run.character == before, "先展示转会影响，不提前修改")
	confirmation().canceled.emit()
	await frames()
	check(flow.run.character == before and confirmation() == null, "取消完全保留编队和资源")
	board().buttons.join_ember.pressed.emit()
	confirmation().close_requested.emit()
	await frames()
	check(flow.run.character == before and confirmation() == null, "关闭确认窗后可再次打开且无副作用")
	board().buttons.join_ember.pressed.emit()
	var capture := OS.get_environment("TENSEI_TRANSFER_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	confirmation().confirmed.emit()
	await frames()
	check(flow.run.character.familia_id == "ember" and not flow.run.character.party_enlisted and not flow.run.character.scout_enlisted and flow.run.character.party_hp == 0 and flow.run.character.scout_hp == 0, "确认转会清空旧编队且所有生命归属一致")
	var expected := before.duplicate(true)
	expected.familia_id = "ember"
	expected.party_enlisted = false
	expected.party_hp = 0
	expected.scout_enlisted = false
	expected.scout_hp = 0
	check(flow.run.character == expected and flow.progress.data == shared, "个人任务/装备/玩家身份和旧共享成长保留")
	check(flow.party_companion().is_empty() and not flow.familia_service("enlist") and not flow.quest_service("familia_patrol", "claim"), "炉心不能调用晨行招募或交付")
	var ember_record: String = flow.saves.save_record(flow.run, flow.profile, "炉心归属")
	check(not ember_record.is_empty() and Run.from_save(flow.run.save_data()) != null, "转会后的暂停任务可以保存和恢复")
	board().queue_free()
	await frames()
	flow.run.character.growth_pending.append({"id": "fixture-pending", "members": ["squire"]})
	before = flow.run.character.duplicate(true)
	check(not flow.familia_service("join") and flow.run.character == before, "待提交成长未同步时拒绝转会")
	check(flow.familia_service("retry") and flow.run.character.growth_pending.is_empty(), "旧组织待同步事件仍提交到原账本")
	flow.run.character.hp = 0
	before = flow.run.character.duplicate(true)
	check(not flow.familia_service("join") and flow.run.character == before, "主角倒下时拒绝转会，不产生无法行动的快照")
	flow.city_service("rest")
	check(flow.familia_service("join") and flow.familia_service("enlist") and flow.familia_service("enlist_scout"), "回晨行后重新编队")
	check(flow.party_companion().level == 2 and flow.party_companion("scout").level == 2 and flow.run.character.familia_wins == expected.familia_wins, "成员成长与暂停任务恢复原进度")
	check(flow.load_exploration(profile_id, ember_record), "读取炉心个人时点")
	await frames()
	check(flow.run.character.familia_id == "ember" and not flow.run.character.party_enlisted, "读档恢复当前归属和编队")
	check(flow.load_exploration(profile_id, dawn_record), "读取晨行个人时点")
	await frames()
	check(flow.run.character.familia_id == "dawn" and flow.run.character.scout_enlisted and flow.progress.data.familias.dawn.squire_xp >= shared.familias.dawn.squire_xp, "旧晨行时点恢复编队且共享成长不回退")
	var shape: Dictionary = flow.run.save_data()
	shape.character.familia_id = "ember"
	check(Run.from_save(shape) == null, "拒绝炉心携带晨行队友的非法快照")
	shape = flow.run.save_data()
	shape.character.familia_id = "unknown"
	check(Run.from_save(shape) == null, "拒绝未知组织")
	var retained := {}
	for suffix in [".0.save", ".1.save"]:
		var path: String = flow.progress.base_path + suffix
		if FileAccess.file_exists(path):
			retained[path] = FileAccess.get_file_as_bytes(path)
			DirAccess.remove_absolute(path)
	var current_run = flow.run
	check(not flow.load_exploration(profile_id, ember_record) and flow.run == current_run, "炉心读取也必须验证共享身份并保留当前会话")
	before = flow.run.character.duplicate(true)
	check(not flow.familia_service("join_ember") and flow.run.character == before, "共享缺失时拒绝转会")
	for path in retained:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(retained[path])
		file.close()
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]: DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("FAMILIA TRANSFER CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
