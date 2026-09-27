extends SceneTree

const Library = preload("res://Scripts/Core/save_library.gd")
const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Log = preload("res://Scripts/Core/game_log.gd")
var failures := 0
var base := "user://test-delete-" + Crypto.new().generate_random_bytes(8).hex_encode()

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
	var library := Library.new()
	library.base_path = base
	var profile := library.new_profile("删除测试")
	var run := Run.new()
	run.setup(123, 3)
	var first := library.save_record(run, profile, "A")
	var second := library.save_record(run, profile, "B")
	library.save_record(run, profile, "B2", second)
	var second_path: String = library._store(profile.id, second).base_path
	var blocker := FileAccess.open(second_path + ".delete.tmp", FileAccess.WRITE)
	blocker.close()
	DirAccess.remove_absolute(second_path + ".delete.tmp")
	DirAccess.make_dir_absolute(second_path + ".delete.tmp")
	check(not library.delete_record(profile.id, second), "无法提交删除标记时拒绝删除")
	check(not library.read_record(profile.id, second).is_empty(), "删除失败保留原档")
	DirAccess.remove_absolute(second_path + ".delete.tmp")
	check(not library.delete_record("../outside", second), "拒绝路径穿越")
	check(library.delete_record(profile.id, second), "删除两代记录")
	check(not FileAccess.file_exists(second_path + ".0.save") and not FileAccess.file_exists(second_path + ".1.save"), "两代文件同时清理")
	check(library.inspect().metadata.record_id == first, "最近记录删除后回退剩余可读记录")
	var first_path: String = library._store(profile.id, first).base_path
	var marker := FileAccess.open(first_path + ".deleted", FileAccess.WRITE)
	marker.store_string("deleted")
	marker.close()
	check(library.list_profiles().is_empty() and library.inspect().is_empty(), "中断清理的删除标记阻止旧代复活")
	DirAccess.remove_absolute(first_path + ".deleted")
	var bad := FileAccess.open(first_path + ".0.save", FileAccess.WRITE)
	bad.store_string("corrupt")
	bad.close()
	check(library.delete_record(profile.id, first), "损坏记录也可删除")
	check(library.list_profiles().is_empty() and library.inspect().is_empty(), "最后记录删除后无角色与继续入口")
	var old := library._store("legacy", "legacy")
	old.save_run(run)
	check(library.delete_record("legacy", "legacy") and library.list_profiles().is_empty(), "显式删除旧版记录")
	# 实际 UI 的取消、确认、选择清理及主菜单入口刷新。
	var flow = root.get_node("GameFlow")
	flow.saves = library
	flow.start_character("界面删除")
	await frames()
	var id: String = library.save_record(flow.run, flow.profile, "UI")
	current_scene._request_save_exit()
	var browser: Window
	for child in current_scene.get_children():
		if child is Window: browser = child
	var capture := OS.get_environment("TENSEI_DELETE_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture + "-list.png") == OK, "删除列表截图")
	browser.list_buttons[1].pressed.emit()
	browser.delete_buttons[0].pressed.emit()
	if not capture.is_empty():
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture + "-confirm.png") == OK, "删除确认截图")
	for child in browser.get_children():
		if child is ConfirmationDialog: child.canceled.emit()
	await frames()
	check(not library.read_record(flow.profile.id, id).is_empty(), "取消删除保留存档")
	browser.delete_buttons[0].pressed.emit()
	for child in browser.get_children():
		if child is ConfirmationDialog: child.confirmed.emit()
	await frames()
	check(browser.selected_id.is_empty() and browser.save_button.text.contains("新增"), "删除选中记录后恢复新增保存")
	browser.close_requested.emit()
	id = library.save_record(flow.run, flow.profile, "菜单删除")
	flow.return_to_menu()
	await frames()
	current_scene._open_saves()
	for child in current_scene.get_children():
		if child is Window: browser = child
	browser.list_buttons[0].pressed.emit()
	browser.delete_buttons[0].pressed.emit()
	for child in browser.get_children():
		if child is ConfirmationDialog: child.confirmed.emit()
	await frames()
	check(current_scene.continue_button.disabled, "删除最后记录立即禁用主菜单继续")
	browser.close_requested.emit()
	# 独立日志目录：JSON 结构、轮转、顺序、原始状态快照。
	Log.close()
	var original_directory := Log.directory
	Log.directory = base + "-logs"
	Log.session = ""
	Log.sequence = 0
	Log.part = 0
	Log.max_bytes = 400
	Log.max_files = 3
	for i in range(12): Log.event("test", "rotation", {"index": i, "text": "中文日志"})
	Log.close()
	var files := DirAccess.get_files_at(Log.directory)
	check(files.size() <= 3, "业务日志轮转限制文件数")
	files.sort()
	var last := 0
	for name in files:
		var file := FileAccess.open(Log.directory + "/" + name, FileAccess.READ)
		while not file.eof_reached():
			var line := file.get_line()
			if line.is_empty(): continue
			var row = JSON.parse_string(line)
			check(row is Dictionary and row.schema == 1 and row.sequence > last and row.data.text == "中文日志", "JSON 日志结构与递增序号")
			last = int(row.sequence)
		file.close()
		DirAccess.remove_absolute(Log.directory + "/" + name)
	DirAccess.remove_absolute(Log.directory)
	Log.directory = original_directory
	Log.session = ""
	Log.max_bytes = 2 * 1024 * 1024
	Log.max_files = 10
	for p in [profile.id, flow.profile.id]: DirAccess.remove_absolute(base + ".profiles/" + p)
	DirAccess.remove_absolute(base + ".profiles")
	DirAccess.remove_absolute(base + ".recent.cfg")
	print("LOG / DELETE CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
