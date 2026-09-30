extends SceneTree

const LibraryTest = preload("res://Tests/test_save_library.gd")
const Run = preload("res://Scripts/Exploration/floor_run.gd")
var failures := 0
var base := "user://test-library-team-recovery-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("三人成长恢复")
	await process_frame
	await process_frame
	flow.run.character.quests.hunt = "claimed"
	check(flow.familia_service("join") and flow.familia_service("enlist"), "建立独立编队")
	for i in range(3): check(flow.progress.award_victory("qualification-%d" % i, flow.run.character.player_id), "建立等级2测试夹具")
	check(flow.familia_service("enlist_scout"), "游侠加入")
	flow.run.depart_city(7)
	check(flow.run.enter("1a") == "battle", "进入三人遭遇")
	var event_id: String = flow.run.node(flow.run.pending).key + "/clear/1"
	flow.run.character.growth_pending.append({"id": event_id, "members": ["squire", "scout"]})
	DirAccess.make_dir_absolute(flow.progress.base_path + ".tmp")
	check(flow.settle_battle(flow.run.character, flow.party_companion(), true, flow.party_companion("scout")), "共享不可写时个人战斗仍结算")
	var queued: Array = flow.run.character.growth_pending.duplicate(true)
	check(queued.size() == 1 and queued[0].members == ["squire", "scout"] and flow.progress.data.familias.dawn.scout_xp == 0, "已有同标识时不追加重复事件，失败保留完整参战名单且不伪造成长")
	var profile_id: String = flow.profile.id
	var record: String = flow.saves.save_record(flow.run, flow.profile, "三人待同步")
	check(not record.is_empty() and flow.saves.read_record(profile_id, record).run.character.growth_pending == queued, "磁盘记录保留参战名单")
	DirAccess.remove_absolute(flow.progress.base_path + ".tmp")
	check(flow.load_exploration(profile_id, record), "恢复存储并读取")
	await process_frame
	await process_frame
	check(flow.run.character.growth_pending.is_empty() and flow.active_character.growth_pending.is_empty(), "重试后会话与角色缓存同步清空")
	check(flow.progress.data.familias.dawn.contribution == 4 and flow.progress.data.familias.dawn.squire_xp == 8 and flow.progress.data.familias.dawn.scout_xp == 2, "贡献一次且两名参战成员各经验2")
	check(flow.load_exploration(profile_id, record), "再次读取原待同步记录")
	await process_frame
	await process_frame
	check(flow.run.character.growth_pending.is_empty() and flow.progress.data.familias.dawn.scout_xp == 2, "重读旧事件不会重复成长")
	var shape: Dictionary = flow.run.save_data()
	shape.character.growth_pending = [{"id": "bad", "members": ["scout", "scout"]}]
	check(Run.from_save(shape) == null, "拒绝重复参战成员")
	shape.character.growth_pending = [{"id": "bad", "members": ["unknown"]}]
	check(Run.from_save(shape) == null, "拒绝未知参战成员")
	shape.character.growth_pending = [queued[0], queued[0]]
	check(Run.from_save(shape) == null, "拒绝重复待同步事件")
	flow.run.phase = "city"
	flow.run.character.hp = 0
	flow.run.character.party_hp = 5
	flow.run.character.scout_hp = 7
	var untouched: Dictionary = flow.run.character.duplicate(true)
	check(not flow.run.city_service("rest", 28, 0) and flow.run.character == untouched, "游侠上限不可用时不部分复活其他成员")
	check(flow.city_service("rest") and flow.run.character.hp == 36 and flow.run.character.scout_hp == 22, "恢复完整档案后全队旅店恢复")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]: DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("TEAM RECOVERY CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
