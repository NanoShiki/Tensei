extends SceneTree

const LibraryTest = preload("res://Tests/test_save_library.gd")
const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Board = preload("res://Scripts/UI/familia_board.gd")
var failures := 0
var base := "user://test-library-forge-recovery-" + Crypto.new().generate_random_bytes(8).hex_encode()

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
	flow.start_character("贡献写入失败")
	await frames()
	flow.run.character.gold = 6
	flow.run.character.scrap = 3
	check(flow.progress.ensure(), "准备独立共享档案")
	DirAccess.make_dir_absolute(flow.progress.base_path + ".tmp")
	check(flow.city_service("forge"), "共享写入失败仍保留已支付并完成的制作")
	var hero: Dictionary = flow.run.character.duplicate(true)
	check(hero.weapon == "iron_sword" and hero.gold == 0 and hero.scrap == 0 and hero.forge_pending.size() == 1 and flow.progress.data.familias.ember.contribution == 0, "完整个人制作成果和待提交事件，贡献暂未提交")
	check(not flow.familia_service("join_ember") and flow.run.character == hero, "待提交贡献禁止转会")
	var profile_id: String = flow.profile.id
	var pending_record: String = flow.saves.save_record(flow.run, flow.profile, "贡献待同步")
	check(not pending_record.is_empty() and flow.load_exploration(profile_id, pending_record), "未加入角色待同步事件可保存并读档")
	await frames()
	check(flow.run.character == hero and not flow.retry_growth(), "仍不可写时读档与重试不遗失事件")
	DirAccess.remove_absolute(flow.progress.base_path + ".tmp")
	current_scene.city_buttons.familia.pressed.emit()
	var board: Window
	for child in current_scene.get_children():
		if child.get_script() == Board: board = child
	check(board != null and board.buttons.has("retry") and not board.buttons.retry.disabled, "未加入也可点击同步贡献")
	board.buttons.retry.pressed.emit()
	check(flow.run.character.forge_pending.is_empty() and flow.progress.data.familias.ember.contribution == 1, "实际按钮提交一次并清空待同步")
	check(flow.load_exploration(profile_id, pending_record), "读取旧待同步记录重试去重")
	await frames()
	check(flow.run.character.forge_pending.is_empty() and flow.progress.data.familias.ember.contribution == 1 and flow.active_character.forge_pending.is_empty(), "重复恢复不刷贡献且活动角色使用同步后状态")
	var wrong: Dictionary = flow.run.save_data()
	wrong.character.forge_pending = [flow.progress.forge_event("01234567890123456789012345678901")]
	var foreign_run = Run.from_save(wrong)
	check(foreign_run != null, "形状合法的异角色事件夹具")
	var foreign_record: String = flow.saves.save_record(foreign_run, flow.profile, "错误身份事件")
	var before: Dictionary = flow.run.log_state()
	var recent: String = flow.active_record_id
	check(not flow.load_exploration(profile_id, foreign_record) and flow.run.log_state() == before and flow.active_record_id == recent, "异角色待同步事件读档拒绝，保留当前状态与入口")
	wrong = flow.run.save_data()
	wrong.character.forge_pending = ["../outside"]
	check(Run.from_save(wrong) == null, "非法事件路径拒绝")
	wrong.character.forge_pending = [flow.progress.forge_event(profile_id), flow.progress.forge_event(profile_id)]
	check(Run.from_save(wrong) == null, "重复待同步事件拒绝")
	wrong.character.forge_pending = [flow.progress.forge_event(profile_id)]
	wrong.character.player_id = ""
	check(Run.from_save(wrong) == null, "无共享所有者的待同步拒绝")
	var bytes := {}
	for suffix in [".0.save", ".1.save"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix):
			bytes[suffix] = FileAccess.get_file_as_bytes(flow.progress.base_path + suffix)
			DirAccess.remove_absolute(flow.progress.base_path + suffix)
	before = flow.run.log_state()
	check(not flow.load_exploration(profile_id, pending_record) and flow.run.log_state() == before, "已绑定的未加入角色缺共享时拒绝读档")
	flow.run.character.weapon = "training_sword"
	flow.run.character.gold = 6
	flow.run.character.scrap = 3
	hero = flow.run.character.duplicate(true)
	check(not flow.city_service("forge") and flow.run.character == hero, "共享缺失拒绝新制作，不部分扣款或重新绑定")
	for suffix in bytes:
		var file := FileAccess.open(flow.progress.base_path + suffix, FileAccess.WRITE)
		file.store_buffer(bytes[suffix])
		file.close()
	check(flow.load_exploration(profile_id, pending_record), "恢复备份后旧待同步仍去重")
	await frames()
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix): DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("FORGE RECOVERY CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
