extends SceneTree

const CommerceBoard = preload("res://Scripts/UI/commerce_board.gd")
const FamiliaBoard = preload("res://Scripts/UI/familia_board.gd")
const Run = preload("res://Scripts/Exploration/floor_run.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-commerce-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	await process_frame

func window(script: Script) -> Window:
	for child in current_scene.get_children():
		if child.get_script() == script: return child
	return null

func _run() -> void:
	create_timer(35).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("集市顾客")
	await frames()
	var before: Dictionary = flow.run.character.duplicate(true)
	check(not flow.commerce_service("supply_order") and not flow.commerce_service("member_bundle") and flow.run.character == before and flow.progress.inspect().is_empty(), "不足材料或非会员不修改个人或初始化共享")
	flow.run.character.quests.hunt = "claimed"
	check(flow.familia_service("join") and flow.familia_service("enlist"), "晨行顾客可使用基础订单")
	flow.run.character.gold = 1
	flow.run.character.scrap = 2
	var profile_id: String = flow.profile.id
	var old_record: String = flow.saves.save_record(flow.run, flow.profile, "交付前")
	current_scene.show_floor_map()
	current_scene.city_buttons.commerce.pressed.emit()
	var board := window(CommerceBoard)
	check(board != null and not board.buttons.supply_order.disabled and board.buttons.member_bundle.disabled, "真实订单窗口区分基础与会员")
	board.buttons.supply_order.pressed.emit()
	check(flow.run.character.gold == 6 and flow.run.character.scrap == 0 and flow.run.character.commerce_done == ["supply_order"] and flow.progress.data.familias.harbor.contribution == 1, "实际交付消耗两铁片、发五金币且专业贡献一次")
	before = flow.run.character.duplicate(true)
	check(not flow.commerce_service("supply_order") and flow.run.character == before, "同一时点不能重复交付")
	board.queue_free()
	await frames()
	current_scene.city_buttons.familia.pressed.emit()
	var family := window(FamiliaBoard)
	family.buttons.join_harbor.pressed.emit()
	var confirm: ConfirmationDialog
	for child in family.get_children():
		if child is ConfirmationDialog: confirm = child
	check(confirm != null and flow.run.character.familia_id == "dawn", "真实商贸转会先确认")
	var shared: Dictionary = flow.progress.data.duplicate(true)
	confirm.confirmed.emit()
	await frames()
	check(flow.run.character.familia_id == "harbor" and not flow.run.character.party_enlisted and flow.progress.data == shared, "确认转会清编队但保留三组织积累")
	family.queue_free()
	await frames()
	current_scene.city_buttons.commerce.pressed.emit()
	board = window(CommerceBoard)
	check(not board.buttons.member_bundle.disabled, "合法集市会员礼包开放")
	var capture := OS.get_environment("TENSEI_COMMERCE_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await frames()
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture) == OK, "商贸窗口截图")
	board.buttons.member_bundle.pressed.emit()
	check(flow.run.character.gold == 0 and flow.run.character.potions == 6 and flow.run.character.commerce_done == ["supply_order", "member_bundle"] and flow.progress.data.familias.harbor.contribution == 2, "会员支付六金币收三药水且贡献一次")
	var member_record: String = flow.saves.save_record(flow.run, flow.profile, "集市礼包后")
	before = flow.run.character.duplicate(true)
	check(flow.load_exploration(profile_id, member_record), "商贸归属／完成记录／库存读档")
	await frames()
	check(flow.run.character == before, "恢复精确个人订单状态")
	check(flow.load_exploration(profile_id, old_record), "读取订单前的个人时点")
	await frames()
	check(flow.commerce_service("supply_order") and flow.progress.data.familias.harbor.contribution == 2, "同角色旧记录再交付不重复共享贡献")
	check(flow.familia_service("join_harbor") and flow.commerce_service("member_bundle") and flow.progress.data.familias.harbor.contribution == 2, "第二种订单也按角色与订单独立去重")
	for i in range(2):
		flow.start_character("另一顾客%d" % i)
		await frames()
		flow.run.character.scrap = 2
		check(flow.commerce_service("supply_order") and flow.run.character.familia_id.is_empty(), "未加入新角色可实际交付且不改变归属")
	check(flow.progress.data.familias.harbor.contribution == 4 and flow.progress.guild_level("harbor") == 2 and flow.progress.data.familias.dawn.contribution == 0 and flow.progress.data.familias.ember.contribution == 0, "跨角色商贸成长，其他组织保持原值")
	flow.run.depart_city(7)
	before = flow.run.character.duplicate(true)
	check(not flow.commerce_service("supply_order") and flow.run.character == before, "探索不能调用城市订单")
	var old: Dictionary = flow.run.save_data()
	old.character.erase("commerce_done")
	old.character.erase("commerce_pending")
	check(Run.from_save(old) != null and Run.from_save(old).character.commerce_done.is_empty(), "旧存档补空订单，不追溯旧材料或金币")
	var invalid: Dictionary = flow.run.save_data()
	invalid.character.commerce_done = ["member_bundle"]
	check(Run.from_save(invalid) == null, "缺入门订单的会员礼包完成状态拒绝")
	invalid.character.commerce_done = ["supply_order", "supply_order"]
	check(Run.from_save(invalid) == null, "重复订单完成记录拒绝")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix): DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("COMMERCE ORDERS CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
