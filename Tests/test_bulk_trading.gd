extends SceneTree

const TradePanel = preload("res://Scripts/UI/trade_panel.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-trade-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		push_error(description)

func frames() -> void:
	await process_frame
	await process_frame

func panel() -> Window:
	for child in current_scene.get_children():
		if child.get_script() == TradePanel: return child
	return null

func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("批量交易")
	await frames()
	flow.run.character.gold = 30
	flow.run.character.scrap = 8
	check(flow.commerce_service("supply_order"), "建立一次真实订单及共享身份")
	var shared: Dictionary = flow.progress.data.duplicate(true)
	var old_record: String = flow.saves.save_record(flow.run, flow.profile, "批量前")
	var before: Dictionary = flow.run.character.duplicate(true)
	for amount in [-1, 0, 100]:
		check(not flow.trade_service("potion", amount) and flow.run.character == before, "越界数量拒绝，资源保持")
	check(not flow.trade_service("unknown", 1) and flow.run.character == before, "未知交易拒绝")
	current_scene.show_floor_map()
	current_scene.city_buttons.trade.pressed.emit()
	check(panel() != null, "城市点击批量采购与出售入口")
	panel().quantity.value = 3
	check(panel().buttons.potion.text.contains("×3") and panel().buttons.potion.text.contains("9 金币"), "数量与总价同步展示")
	panel().buttons.potion.pressed.emit()
	check(flow.run.character.gold == 26 and flow.run.character.potions == 6, "三瓶治疗统一扣9金币")
	panel().quantity.get_line_edit().text = "2"
	panel().quantity.get_line_edit().text_changed.emit("2")
	await frames()
	check(panel().quantity.value == 2 and panel().buttons.fire_potion.text.contains("8 金币"), "直接输入数量也即时更新总价")
	panel().buttons.fire_potion.pressed.emit()
	check(flow.run.character.gold == 18 and flow.run.character.fire_potions == 4, "两瓶灼烧统一扣8金币")
	panel().quantity.value = 3
	panel().buttons.sell_scrap.pressed.emit()
	check(flow.run.character.gold == 21 and flow.run.character.scrap == 3, "出售三铁片获得3金币并消耗库存")
	check(flow.run.character.familia_id.is_empty() and flow.progress.data == shared and flow.run.character.commerce_done == before.commerce_done, "普通采购出售不绑定眷族、不计共享成长和新订单")
	panel().quantity.value = 99
	check(panel().buttons.potion.disabled and panel().buttons.sell_scrap.disabled, "余额与库存不足禁用")
	before = flow.run.character.duplicate(true)
	check(not flow.trade_service("sell_scrap", 4) and flow.run.character == before, "不足全量拒绝，不部分出售")
	panel().quantity.value = 2
	check(not panel().buttons.sell_scrap.disabled, "实时刷新允许足量出售")
	flow.run.character.scrap = 1
	before = flow.run.character.duplicate(true)
	panel().buttons.sell_scrap.pressed.emit()
	check(flow.run.character == before and panel().feedback.text.contains("不足"), "窗口旧资格执行时重查库存，不部分扣除")
	flow.run.character.scrap = 3
	panel()._refresh()
	current_scene.show_floor_map()
	var capture := OS.get_environment("TENSEI_TRADE_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	panel().queue_free()
	await frames()
	var record: String = flow.saves.save_record(flow.run, flow.profile, "批量后")
	var expected: Dictionary = flow.run.character.duplicate(true)
	check(not record.is_empty() and flow.load_exploration(flow.profile.id, record), "批量交易后磁盘读取")
	await frames()
	check(flow.run.character == expected and flow.progress.data == shared, "个人资源与订单完整恢复，共享保持")
	check(flow.load_exploration(flow.profile.id, old_record), "读取交易前个人时点")
	await frames()
	check(flow.run.character.gold == 35 and flow.run.character.scrap == 6 and flow.run.character.potions == 3 and flow.progress.data == shared, "旧记录恢复当时资源，共享贡献不倒退")
	var files := {}
	for suffix in [".0.save", ".1.save"]:
		var path: String = flow.progress.base_path + suffix
		if FileAccess.file_exists(path):
			files[path] = FileAccess.get_file_as_bytes(path)
			DirAccess.remove_absolute(path)
	check(flow.trade_service("sell_scrap", 1) and flow.trade_service("potion", 1), "普通个人交易不依赖共享文件可用性")
	check(flow.run.character.gold == 33 and flow.run.character.scrap == 5 and flow.run.character.potions == 4, "共享缺失时仍按普通总价结算，不重建共享档")
	for path in files:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(files[path])
		file.close()
	check(flow.progress.refresh() and flow.progress.data == shared, "原共享恢复后贡献没有变化")
	flow.run.depart_city(7)
	before = flow.run.character.duplicate(true)
	check(not flow.trade_service("potion", 1) and flow.run.character == before, "探索不能调用城市批量交易")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix): DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("BULK TRADING CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
