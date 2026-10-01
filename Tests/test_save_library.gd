extends SceneTree

const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Library = preload("res://Scripts/Core/save_library.gd")
const Store = preload("res://Scripts/Core/expedition_save.gd")
const Browser = preload("res://Scripts/UI/save_browser.gd")
var failures := 0
var base := "user://test-library-" + str(Time.get_ticks_usec())

func _initialize() -> void:
	var phase := OS.get_environment("TENSEI_LIBRARY_TEST_PHASE")
	if phase in ["write", "read"]:
		_restart_check(phase)
		return
	_run.call_deferred()

func _restart_check(phase: String) -> void:
	var library := Library.new()
	library.base_path = OS.get_environment("TENSEI_LIBRARY_TEST_PATH")
	assert(library.base_path.begins_with("user://test-library-"))
	if phase == "write":
		var run := Run.new()
		run.setup(123)
		var first := library.new_profile("重启角色 A")
		var initial := library.save_record(run, first, "较早记录")
		run.enter("1a")
		run.finish_battle(run.character, true)
		check(not library.save_record(run, first, "较新记录").is_empty(), "保存第二条记录")
		check(not library.save_record(run, library.new_profile("重启角色 B"), "第二角色记录").is_empty(), "保存第二角色")
		library.load_record(first.id, initial)
	else:
		var profiles := library.list_profiles()
		check(profiles.size() == 2, "独立进程恢复两个角色档案")
		var recent := library.inspect()
		check(not recent.is_empty() and recent.metadata.name == "较早记录" and recent.run.steps_taken == 0, "重启继续最近读取的较早快照")
		for profile in profiles:
			check(library.list_records(profile.id).size() == (2 if profile.name == "重启角色 A" else 1), "重启保留各角色记录数量")
		cleanup(library.base_path)
	print("LIBRARY RESTART CHECKS: ", failures, " failures")
	quit(1 if failures else 0)

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func browser() -> Window:
	for child in current_scene.get_children():
		if child.get_script() == Browser: return child
	return null

func frames() -> void:
	await process_frame
	await process_frame

func click(button: Button) -> void:
	var viewport := button.get_viewport()
	button.pressed.emit()
	check(viewport.is_inside_tree(), "按钮回调返回前不移除所属视口")
func cleanup(prefix: String) -> void:
	# 仅删除本测试的唯一前缀目录，逐文件清理，保留玩家存档。
	assert(prefix.begins_with("user://test-library-"))
	var directory := prefix + ".profiles"
	if DirAccess.dir_exists_absolute(directory):
		for folder in DirAccess.get_directories_at(directory):
			var path := directory + "/" + folder
			for file in DirAccess.get_files_at(path): DirAccess.remove_absolute(path + "/" + file)
			DirAccess.remove_absolute(path)
		DirAccess.remove_absolute(directory)
	for suffix in [".0.save", ".1.save", ".tmp", ".recent.cfg", ".recent.tmp"]:
		if FileAccess.file_exists(prefix + suffix): DirAccess.remove_absolute(prefix + suffix)

func _run() -> void:
	create_timer(30).timeout.connect(func():
		push_error("存档层级测试超时")
		quit(1))
	var library := Library.new()
	library.base_path = base
	var first := library.new_profile("洛恩")
	var second := library.new_profile("洛恩")
	check(first.id != second.id, "同名同模板角色仍有独立身份")
	var run := Run.new()
	run.setup(123, 3)
	var initial := run.save_data()
	var first_id := library.save_record(run, first, "出发前")
	check(not first_id.is_empty(), "建立角色首条记录")
	run.enter("1a")
	run.finish_battle(run.character, true)
	run.enter("2b")
	run.begin_return()
	var later := run.save_data()
	var second_id := library.save_record(run, first, "营地返程")
	check(first_id != second_id and library.list_records(first.id).size() == 2, "同角色可以新增多条记录")
	check(library.read_record(first.id, first_id).run.save_data() == initial, "新增记录不改写旧快照")
	check(library.read_record(first.id, second_id).run.save_data() == later, "第二条恢复独立时点")
	var other_id := library.save_record(run, second, "另一角色")
	check(library.list_profiles().size() == 2 and library.list_records(second.id).size() == 1, "角色列表分别统计记录")
	check(library.save_record(run, second, "错误覆盖", first_id).is_empty(), "拒绝跨角色覆盖")
	run.character.hp -= 3
	check(library.save_record(run, first, "更新营地", second_id) == second_id, "覆盖保持记录身份")
	check(library.list_records(first.id).size() == 2, "覆盖不新建多余记录")
	check(library.read_record(first.id, first_id).run.save_data() == initial and library.read_record(second.id, other_id).run.save_data() == later, "覆盖不污染其他记录和角色")
	library.load_record(first.id, first_id)
	var restarted := Library.new()
	restarted.base_path = base
	check(restarted.inspect().metadata.record_id == first_id, "继续入口跟随最近读取而非最后写入")
	check(restarted.inspect().run.save_data() == initial, "最近入口从磁盘恢复正确快照")
	check(library.read_record("../outside", first_id).is_empty(), "拒绝目录穿越标识")
	check(library.save_record(run, first, "   ").is_empty(), "拒绝空白记录名称")
	var corrupt_path: String = base + ".profiles/" + first.id + "/" + second_id + ".1.save"
	var corrupt := FileAccess.open(corrupt_path, FileAccess.WRITE)
	corrupt.store_var("broken")
	corrupt.close()
	check(library.read_record(first.id, second_id).run.save_data() == later, "单条记录损坏只恢复它自己的上一代")
	check(library.list_records(second.id)[0].run.save_data() == later, "其他角色不受损坏影响")
	library.load_record(second.id, other_id)
	var broken := FileAccess.open(base + ".profiles/" + second.id + "/" + other_id + ".0.save", FileAccess.WRITE)
	broken.store_var("broken")
	broken.close()
	check(library.inspect().is_empty(), "最近记录损坏时不自动跳到其他角色")
	check(library.list_records(second.id)[0].has("error"), "完全损坏的记录保留在列表并标明不可读")
	check(library.save_record(run, second, "覆盖损坏记录", other_id).is_empty(), "完整损坏的记录不静默覆盖")
	check(not library.load_record(first.id, first_id).is_empty(), "仍可显式读取其他完整角色记录")
	# 旧版两代文件只读挂载，继续原角色时可以另存新记录。
	var legacy := Store.new()
	legacy.base_path = base
	check(legacy.save_run(run), "准备旧版单槽存档")
	var legacy_bytes := FileAccess.get_file_as_bytes(base + ".0.save")
	var old := library.load_record("legacy", "legacy")
	check(not old.is_empty() and library.list_profiles().size() == 3, "旧档以独立角色和只读记录列出")
	var migrated: String = library.save_record(old.run, old.metadata.profile, "旧档续玩")
	check(not migrated.is_empty() and library.list_records("legacy").size() == 2, "旧角色另存后仍归入原角色")
	check(FileAccess.get_file_as_bytes(base + ".0.save") == legacy_bytes, "兼容读取和另存不触碰原文件")
	check(library.save_record(run, old.metadata.profile, "覆盖旧档", "legacy").is_empty(), "禁止覆盖兼容旧档")
	# 实际保存、分级读取与覆盖确认。
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base + "-ui"
	flow.start_exploration("界面角色")
	await frames()
	var ui_profile: Dictionary = flow.profile.duplicate(true)
	var ui_initial: Dictionary = flow.run.save_data()
	current_scene._request_save_exit()
	var window = browser()
	check(window != null and window.heading.text.contains("界面角色"), "保存窗口定位当前角色")
	window.name_input.text = "初始记录"
	await frames()
	click(window.save_button)
	await frames()
	check(not current_scene.continue_button.disabled, "成功保存退出后继续入口启用")
	current_scene.continue_button.pressed.emit()
	await frames()
	check(flow.profile.id == ui_profile.id and flow.run.save_data() == ui_initial, "继续保持角色身份与快照")
	flow.run.enter("1a")
	flow.run.finish_battle(flow.run.character, true)
	current_scene.show_floor_map()
	var ui_later: Dictionary = flow.run.save_data()
	current_scene._request_save_exit()
	window = browser()
	window.name_input.text = "战斗后"
	window.save_button.pressed.emit()
	await frames()
	current_scene.load_button.pressed.emit()
	window = browser()
	check(window.list_buttons.size() == 1, "读取先展示角色列表")
	window.list_buttons[0].pressed.emit()
	check(window.list_buttons.size() == 2, "选择角色后展示两条记录")
	for button in window.list_buttons:
		if button.text.begins_with("初始记录"): click(button)
	await frames()
	check(flow.run.save_data() == ui_initial, "点选旧记录恢复旧状态")
	current_scene._request_save_exit()
	window = browser()
	for button in window.list_buttons:
		if button.text.begins_with("战斗后"): button.pressed.emit()
	window.save_button.pressed.emit()
	var confirmation: ConfirmationDialog
	for child in window.get_children():
		if child is ConfirmationDialog: confirmation = child
	check(confirmation != null, "覆盖某一条记录前要求确认")
	confirmation.canceled.emit()
	await frames()
	check(flow.saves.read_record(ui_profile.id, window.selected_id).run.save_data() == ui_later, "取消覆盖保留该条旧状态")
	window.save_button.pressed.emit()
	for child in window.get_children():
		if child is ConfirmationDialog:
			child.confirmed.emit()
			check(child.is_inside_tree() and window.is_inside_tree(), "覆盖确认回调结束前保留两层视口")
	await frames()
	check(flow.saves.list_records(ui_profile.id).size() == 2, "确认覆盖仍只有两条记录")
	check(flow.saves.inspect().run.save_data() == ui_initial, "确认覆盖写入选定记录")
	current_scene.continue_button.pressed.emit()
	await frames()
	# 用普通文件阻塞目录创建，必须留在保存窗口并可取消。
	var blocker := FileAccess.open(base + "-blocked.profiles", FileAccess.WRITE)
	blocker.store_string("not a directory")
	blocker.close()
	flow.saves.base_path = base + "-blocked"
	current_scene._request_save_exit()
	window = browser()
	window.continue_save_button.pressed.emit()
	check(current_scene.map_visible and window.feedback.text.contains("保存失败") and not window.save_button.disabled and not window.continue_save_button.disabled, "保存继续失败留在当前地图和窗口，两种重试入口恢复")
	window.close_requested.emit()
	await frames()
	flow.saves.base_path = base + "-ui"
	for index in range(12): flow.saves.save_record(flow.run, flow.profile, "滚动记录 %02d" % index)
	current_scene._request_save_exit()
	window = browser()
	await frames()
	var scroll: ScrollContainer = window.rows.get_parent()
	check(scroll.get_v_scroll_bar().max_value > scroll.get_v_scroll_bar().page, "多条记录形成可滚动列表")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await frames()
	check(scroll.scroll_vertical > 0, "滚动可到达列表下部")
	window.close_requested.emit()
	await frames()
	DirAccess.remove_absolute(base + "-blocked.profiles")
	DirAccess.remove_absolute(base + "-ui.recent.cfg")
	DirAccess.make_dir_absolute(base + "-ui.recent.cfg")
	var retained_id: String = flow.saves.save_record(flow.run, flow.profile, "索引失败仍保存")
	check(not retained_id.is_empty() and flow.saves.message.contains("最近游玩入口未更新"), "索引提交失败不撤销有效记录")
	check(not FileAccess.file_exists(base + "-ui.recent.tmp"), "索引提交失败清理临时文件")
	check(not flow.saves.read_record(flow.profile.id, retained_id).is_empty(), "索引失败后记录仍可显式读取")
	DirAccess.remove_absolute(base + "-ui.recent.cfg")
	cleanup(base)
	cleanup(base + "-ui")
	print("SAVE LIBRARY CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
