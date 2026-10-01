extends SceneTree

const Browser = preload("res://Scripts/UI/save_browser.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-save-continue-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	await process_frame

func browser() -> Window:
	for child in current_scene.get_children():
		if child.get_script() == Browser: return child
	return null

func confirmation(window: Window) -> ConfirmationDialog:
	for child in window.get_children():
		if child is ConfirmationDialog: return child
	return null

func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("保存并继续")
	await frames()
	var profile_id: String = flow.profile.id
	var screen = current_scene
	var city: Dictionary = flow.run.save_data()
	screen._request_save_exit()
	var window := browser()
	window.name_input.text = "城市准备"
	window.continue_save_button.pressed.emit()
	await frames()
	var first: String = flow.active_record_id
	check(current_scene == screen and browser() == null and flow.run.save_data() == city and not first.is_empty(), "城市保存并继续保持同一场景和全部玩法状态")
	check(flow.saves.inspect().metadata.record_id == first and flow.saves.read_record(profile_id, first).run.save_data() == city, "成功后最近入口与个人磁盘更新")
	flow.run.depart_city(7)
	flow.run.enter("1a")
	flow.run.finish_battle(flow.run.character, true)
	screen.show_floor_map()
	var map: Dictionary = flow.run.save_data()
	screen._request_save_exit()
	window = browser()
	window.name_input.text = "战斗后地图"
	var capture := OS.get_environment("TENSEI_SAVE_CONTINUE_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	window.continue_save_button.pressed.emit()
	await frames()
	var second: String = flow.active_record_id
	check(current_scene == screen and flow.run.save_data() == map and second != first and flow.saves.list_records(profile_id).size() == 2, "地图新增时点后原地继续，步数、奖励、刷新不变")
	screen._request_save_exit()
	window = browser()
	for button in window.list_buttons:
		if button.text.begins_with("城市准备"): button.pressed.emit()
	window.continue_save_button.pressed.emit()
	check(confirmation(window) != null, "继续游玩模式覆盖也需要确认")
	confirmation(window).canceled.emit()
	await frames()
	check(flow.saves.read_record(profile_id, first).run.save_data() == city and flow.active_record_id == second and current_scene == screen, "取消覆盖保留旧记录和当前入口")
	window.continue_save_button.pressed.emit()
	confirmation(window).confirmed.emit()
	await frames()
	check(current_scene == screen and flow.run.save_data() == map and flow.active_record_id == first and flow.saves.list_records(profile_id).size() == 2 and flow.saves.read_record(profile_id, first).run.save_data() == map, "确认覆盖后继续，无额外记录或游戏移动")
	screen._request_save_exit()
	window = browser()
	window.name_input.text = "退出时点"
	window.save_button.pressed.emit()
	await frames()
	check(current_scene != screen and not current_scene.continue_button.disabled, "保存并退出仍返回菜单")
	current_scene.continue_button.pressed.emit()
	await frames()
	check(flow.run.save_data() == map, "退出后继续恢复准确安全点")
	for node in ["2b", "3a"]:
		if flow.run.enter(node) == "battle": break
	if flow.run.pending.is_empty():
		flow.run.enter("exit")
		flow.run.descend_floor(2)
		flow.run.enter("1a")
	check(not flow.run.pending.is_empty(), "准备待结算战斗边界")
	current_scene._request_save_exit()
	check(browser() == null, "待结算战斗不能打开保存窗口")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	print("SAVE AND CONTINUE CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
