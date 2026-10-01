extends SceneTree

const FamiliaBoard = preload("res://Scripts/UI/familia_board.gd")
const Run = preload("res://Scripts/Exploration/floor_run.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-commerce-recovery-" + Crypto.new().generate_random_bytes(8).hex_encode()

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
	flow.start_character("交易恢复")
	await frames()
	flow.run.character.scrap = 2
	check(flow.progress.ensure(), "准备独立共享档案")
	DirAccess.make_dir_absolute(flow.progress.base_path + ".tmp")
	check(flow.commerce_service("supply_order"), "共享写入失败保留已完成的物资交付")
	var hero: Dictionary = flow.run.character.duplicate(true)
	check(hero.gold == 5 and hero.scrap == 0 and hero.commerce_pending.size() == 1 and flow.progress.data.familias.harbor.contribution == 0, "个人交付成果与待提交商贸事件完整保留")
	check(not flow.familia_service("join_harbor") and flow.run.character == hero, "待同步贡献禁止加入或转会")
	# 同时准备不同专业队列，重试不覆盖另一项的错误或进度。
	flow.run.character.gold = 6
	flow.run.character.scrap = 3
	check(flow.city_service("forge") and flow.run.character.forge_pending.size() == 1 and flow.run.character.commerce_pending.size() == 1, "两专业待提交事件各自保存")
	hero = flow.run.character.duplicate(true)
	var profile_id: String = flow.profile.id
	var record: String = flow.saves.save_record(flow.run, flow.profile, "两个专业待同步")
	check(flow.load_exploration(profile_id, record), "混合专业待提交事件磁盘恢复")
	await frames()
	check(flow.run.character == hero and not flow.retry_growth() and not flow.progress.message.is_empty(), "仍不可写时两项保留且显示失败原因")
	DirAccess.remove_absolute(flow.progress.base_path + ".tmp")
	current_scene.city_buttons.familia.pressed.emit()
	var family: Window
	for child in current_scene.get_children():
		if child.get_script() == FamiliaBoard: family = child
	check(family != null and not family.buttons.retry.disabled, "非成员可点击同步多个专业成果")
	family.buttons.retry.pressed.emit()
	check(flow.run.character.forge_pending.is_empty() and flow.run.character.commerce_pending.is_empty() and flow.progress.data.familias.ember.contribution == 1 and flow.progress.data.familias.harbor.contribution == 1, "实际同步分别提交正确组织并清空各队列")
	check(flow.load_exploration(profile_id, record), "旧混合待提交记录重复恢复")
	await frames()
	check(flow.run.character.forge_pending.is_empty() and flow.run.character.commerce_pending.is_empty() and flow.progress.data.familias.ember.contribution == 1 and flow.progress.data.familias.harbor.contribution == 1, "跨两专业重试都不重复奖励")
	check(flow.familia_service("join_harbor"), "同步完成后加入集市")
	flow.run.character.gold = 6
	current_scene.show_floor_map()
	current_scene.city_buttons.commerce.pressed.emit()
	var commerce: Window
	for child in current_scene.get_children():
		if child.get_script() == preload("res://Scripts/UI/commerce_board.gd"): commerce = child
	check(not commerce.buttons.member_bundle.disabled, "准备已核验的会员窗口")
	var stored := {}
	for suffix in [".0.save", ".1.save"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix):
			stored[suffix] = FileAccess.get_file_as_bytes(flow.progress.base_path + suffix)
			DirAccess.remove_absolute(flow.progress.base_path + suffix)
	hero = flow.run.character.duplicate(true)
	commerce.buttons.member_bundle.pressed.emit()
	check(flow.run.character == hero and commerce.buttons.member_bundle.disabled, "开窗后共享缺失仍拒绝礼包，不扣款或发物品")
	var current_run = flow.run
	check(not flow.load_exploration(profile_id, record) and flow.run == current_run, "缺共享拒绝商贸记录读取且保留会话")
	for suffix in stored:
		var file := FileAccess.open(flow.progress.base_path + suffix, FileAccess.WRITE)
		file.store_buffer(stored[suffix])
		file.close()
	commerce._refresh()
	DirAccess.make_dir_absolute(flow.progress.base_path + ".tmp")
	commerce.buttons.member_bundle.pressed.emit()
	check(flow.run.character.gold == 0 and flow.run.character.potions == 6 and flow.run.character.commerce_pending.size() == 1, "会员礼包贡献写入失败也保留完整个人采购")
	DirAccess.remove_absolute(flow.progress.base_path + ".tmp")
	check(flow.retry_growth() and flow.progress.data.familias.harbor.contribution == 2, "礼包重试只计一次商贸贡献")
	var wrong: Dictionary = flow.run.save_data()
	wrong.character.commerce_pending = [flow.progress.commerce_event("01234567890123456789012345678901", "supply_order")]
	var foreign_run = Run.from_save(wrong)
	check(foreign_run != null, "形状合法异角色商贸事件夹具")
	var foreign_record: String = flow.saves.save_record(foreign_run, flow.profile, "异角色商贸事件")
	hero = flow.run.character.duplicate(true)
	check(not flow.load_exploration(profile_id, foreign_record) and flow.run.character == hero, "异角色商贸待提交读档拒绝且保持状态")
	wrong.character.commerce_pending = ["../outside"]
	check(Run.from_save(wrong) == null, "非法商贸事件拒绝")
	wrong.character.commerce_pending = [flow.progress.commerce_event(profile_id, "member_bundle")]
	wrong.character.commerce_done = ["supply_order"]
	check(Run.from_save(wrong) == null, "未完成订单对应的待提交事件拒绝")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix): DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("COMMERCE RECOVERY CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
