extends SceneTree

const LibraryTest = preload("res://Tests/test_save_library.gd")
const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Board = preload("res://Scripts/UI/familia_board.gd")
var failures := 0
var base := "user://test-library-armor-recovery-" + Crypto.new().generate_random_bytes(8).hex_encode()

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
	create_timer(35).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("护甲待同步")
	await frames()
	flow.run.character.gold = 30
	flow.run.character.scrap = 12
	flow.run.character.quests.hunt = "claimed"
	flow.run.character.hunt_wins = 3
	check(flow.city_service("forge") and flow.familia_service("join_ember") and flow.city_service("forge_tempered"), "准备两种武器与炉心会员")
	check(flow.progress.data.familias.ember.contribution == 2, "两种配方独立贡献")
	DirAccess.make_dir_absolute(flow.progress.base_path + ".tmp")
	check(flow.city_service("forge_armor"), "共享写入失败保留完整护甲制作")
	check(flow.run.character.gold == 9 and flow.run.character.scrap == 2 and flow.run.character.ac == 15 and flow.run.character.armor == "iron_armor" and flow.run.character.forge_pending.size() == 1 and flow.progress.data.familias.ember.contribution == 2, "扣款、持有与防御一次完成，护甲贡献留待同步")
	check(flow.equip_armor("cloth_armor"), "待同步时仍可换回布衣")
	var pending: Dictionary = flow.run.save_data()
	pending.character.forge_pending = []
	for recipe in ["iron_sword", "tempered_sword", "iron_armor"]:
		pending.character.forge_pending.append(flow.progress.forge_event(flow.profile.id, recipe))
	var mixed = Run.from_save(pending)
	check(mixed != null, "持有三件成品的三配方待同步快照合法")
	var profile_id: String = flow.profile.id
	var record: String = flow.saves.save_record(mixed, flow.profile, "三配方待同步")
	check(not record.is_empty() and flow.load_exploration(profile_id, record), "磁盘恢复混合锻造队列")
	await frames()
	check(flow.run.character.armor == "cloth_armor" and flow.run.character.ac == 14 and flow.run.character.armors.has("iron_armor") and flow.run.character.forge_pending.size() == 1 and flow.run.character.forge_pending[0].ends_with("iron_armor"), "已提交武器去重清理，失败护甲事件与旧装备保留")
	var before: Dictionary = flow.run.character.duplicate(true)
	check(not flow.familia_service("join_dawn") and flow.run.character == before, "护甲待同步阻止转会，无部分变化")
	DirAccess.remove_absolute(flow.progress.base_path + ".tmp")
	current_scene.city_buttons.familia.pressed.emit()
	var board: Window
	for child in current_scene.get_children():
		if child.get_script() == Board: board = child
	check(board != null and not board.buttons.retry.disabled, "真实眷族面板允许重试护甲贡献")
	board.buttons.retry.pressed.emit()
	check(flow.progress.data.familias.ember.contribution == 3 and flow.progress.guild_level("ember") == 2 and flow.run.character.forge_pending.is_empty(), "恢复后只增加护甲贡献并达到炉心二级")
	check(flow.load_exploration(profile_id, record), "再次读取旧混合待同步记录")
	await frames()
	check(flow.progress.data.familias.ember.contribution == 3 and flow.run.character.forge_pending.is_empty() and flow.run.character.gold == 9 and flow.run.character.armor == "cloth_armor", "三配方不重奖、不重扣，当前装备独立恢复")
	var wrong: Dictionary = flow.run.save_data()
	wrong.character.forge_pending = [flow.progress.forge_event("01234567890123456789012345678901", "iron_armor")]
	var foreign = Run.from_save(wrong)
	check(foreign != null, "合法形状的异角色护甲事件")
	var foreign_record: String = flow.saves.save_record(foreign, flow.profile, "异角色护甲事件")
	var state: Dictionary = flow.run.log_state()
	var recent: String = flow.active_record_id
	check(not flow.load_exploration(profile_id, foreign_record) and flow.run.log_state() == state and flow.active_record_id == recent, "异角色护甲队列拒绝且保留当前记录")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix): DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("ARMOR RECOVERY CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
