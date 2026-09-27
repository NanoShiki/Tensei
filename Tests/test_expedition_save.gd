extends SceneTree

const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Store = preload("res://Scripts/Core/expedition_save.gd")
var failures := 0
var base := "user://test-save-" + str(Time.get_ticks_usec())

func _initialize() -> void:
	var phase := OS.get_environment("TENSEI_SAVE_TEST_PHASE")
	if phase in ["write", "read"]:
		var store := Store.new()
		store.base_path = OS.get_environment("TENSEI_SAVE_TEST_PATH")
		var run := Run.new()
		run.setup(123, 3, "restart-test")
		run.enter("1a")
		run.finish_battle(run.character, true)
		run.enter("2b")
		run.begin_return()
		if phase == "write": check(store.save_run(run), "独立进程写档")
		else:
			var saved := store.inspect()
			check(not saved.is_empty() and saved.run.save_data() == run.save_data(), "重新启动进程恢复完整安全点")
			for suffix in [".0.save", ".1.save"]:
				if FileAccess.file_exists(store.base_path + suffix): DirAccess.remove_absolute(store.base_path + suffix)
		print("RESTART CHECKS: ", failures, " failures")
		quit(1 if failures else 0)
		return
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func write_data(path: String, data: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_var(data, false)
	file.close()

func _run() -> void:
	var store := Store.new()
	store.base_path = base
	check(store.inspect().is_empty(), "空存档没有继续入口")
	var run := Run.new()
	run.setup(123, 3)
	for i in range(2):
		for id in ["1a", "2b", "3a", "exit"]:
			if run.enter(id) == "battle": run.finish_battle(run.character, true)
	run.begin_return()
	run.step_return(run.node_key(2, "exit"))
	run.character.hp -= 7
	var expected := run.save_data()
	check(store.save_run(run), "跨层返程保存成功")
	var fresh_store := Store.new()
	fresh_store.base_path = base
	var result := fresh_store.inspect()
	check(not result.is_empty(), "新存档服务实例可以读磁盘")
	if result.is_empty():
		quit(1)
		return
	check(result.run.save_data() == expected, "完整恢复地图、身份、角色、方向、历史和刷新数值")
	result.run.character.hp -= 1
	check(fresh_store.inspect().run.character.hp == run.character.hp, "读档互相隔离")
	var restored: RefCounted = fresh_store.inspect().run
	run.begin_descent()
	restored.begin_descent()
	run.descend_floor(2)
	restored.descend_floor(2)
	check(run.save_data() == restored.save_data(), "恢复后移动不改变随机或跨层结果")
	check(store.save_run(run), "第二代保存成功")
	var file := FileAccess.open(base + ".1.save", FileAccess.READ)
	var envelope: Dictionary = file.get_var(false)
	file.close()
	envelope.payload[0] = envelope.payload[0] ^ 1
	write_data(base + ".1.save", envelope)
	result = store.inspect()
	check(result.run.save_data() == expected and not store.message.is_empty(), "损坏最新代时明确提示并恢复完整旧代")
	check(store.save_run(restored), "恢复后可以重新保存")
	var invalid := expected.duplicate(true)
	invalid.floors[1][1].next = ["missing"]
	check(Run.from_save(invalid) == null, "错误地图连线拒绝读取")
	invalid = expected.duplicate(true)
	invalid.character.erase("hp")
	check(Run.from_save(invalid) == null, "缺失角色数据拒绝读取")
	write_data(base + ".tmp", "interrupted write")
	check(store.inspect().run.save_data() == restored.save_data(), "中断临时文件不影响完整存档")
	var blocked := Store.new()
	blocked.base_path = base + "/missing/expedition"
	check(not blocked.save_run(restored), "不可写目录报告失败")
	check(store.inspect().run.save_data() == restored.save_data(), "写入失败不影响原档")
	write_data(base + ".1.save", {"version": 99, "content_version": Store.CONTENT_VERSION})
	check(store.inspect().is_empty() and store.message.contains("不兼容"), "新版本存档不降级读取")
	check(not store.save_run(restored), "不兼容存档拒绝覆盖")
	DirAccess.remove_absolute(base + ".1.save")
	run = Run.new()
	run.setup(123)
	run.enter("1a")
	check(not store.save_run(run), "战斗未结算不允许保存")
	run.finish_battle(run.character, false)
	check(not store.save_run(run), "失败状态不覆盖安全点")
	# 真实界面闭环，独立测试路径不触碰玩家存档。
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base + "-ui"
	flow.start_exploration()
	await process_frame
	await process_frame
	flow.run.enter("1a")
	flow.run.finish_battle(flow.run.character, true)
	flow.run.enter("2b")
	flow.run.begin_return()
	var checkpoint: Dictionary = flow.run.save_data()
	current_scene._save_exit()
	await process_frame
	await process_frame
	check(not current_scene.continue_button.disabled, "保存退出后菜单继续按钮启用")
	# 清空会话引用，确保继续旅程真正从磁盘读入。
	flow.run = null
	current_scene.continue_button.pressed.emit()
	await process_frame
	await process_frame
	check(flow.run.save_data() == checkpoint and current_scene.map_visible, "继续按钮恢复地图与全部状态")
	check(current_scene.map_buttons["1a"].text.contains("已到访") and current_scene.map_buttons["3a"].text.contains("未知"), "恢复后保留到访和未知区域显示")
	flow.run.setup(321)
	current_scene.show_floor_map()
	current_scene._request_save_exit()
	var confirmation: ConfirmationDialog
	for child in current_scene.get_children():
		if child is ConfirmationDialog: confirmation = child
	check(confirmation != null, "新远征替换存档前确认")
	if confirmation != null: confirmation.canceled.emit()
	check(flow.saves.inspect().run.save_data() == checkpoint, "取消替换保留旧旅程")
	await process_frame
	var replacement: Dictionary = flow.run.save_data()
	current_scene._request_save_exit()
	for child in current_scene.get_children():
		if child is ConfirmationDialog: child.confirmed.emit()
	await process_frame
	await process_frame
	check(flow.saves.inspect().run.save_data() == replacement, "确认替换保存新旅程")
	current_scene.continue_button.pressed.emit()
	await process_frame
	await process_frame
	flow.saves.base_path = base + "/missing/ui"
	current_scene._save_exit()
	check(current_scene.map_visible and flow.run.message.contains("保存失败"), "保存失败留在地图并显示原因")
	for prefix in [base, base + "-ui"]:
		for suffix in [".0.save", ".1.save", ".tmp"]:
			if FileAccess.file_exists(prefix + suffix): DirAccess.remove_absolute(prefix + suffix)
	print("SAVE CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
