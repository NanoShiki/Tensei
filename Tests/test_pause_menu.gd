extends SceneTree

const Pause = preload("res://Scripts/UI/pause_menu.gd")
const State = preload("res://Scripts/Battle/battle_state.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-pause-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	await process_frame

func key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

func panel() -> Window:
	for child in current_scene.get_children():
		if child.get_script() == Pause and not child.is_queued_for_deletion(): return child
	return null

func wait_ready() -> void:
	for i in range(35):
		if not current_scene.busy: return
		await create_timer(0.1).timeout
	check(false, "敌人反馈应能完成")

func _run() -> void:
	create_timer(35).timeout.connect(func(): quit(1))
	var original_volume := AudioServer.get_bus_volume_linear(0)
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("暂停验收")
	await frames()
	var screen = current_scene
	var before: Dictionary = screen.pause_snapshot()
	screen.pause_button.pressed.emit()
	check(paused and panel() != null and panel().resume_button.has_focus(), "城市点击暂停并聚焦继续")
	screen._open_pause()
	var count := 0
	for child in screen.get_children():
		if child.get_script() == Pause: count += 1
	check(count == 1, "暂停不重复堆叠")
	panel().settings_path = base + "-settings.cfg"
	panel().volume.value = 25
	var config := ConfigFile.new()
	check(config.load(panel().settings_path) == OK and config.get_value("audio", "volume") == 25 and is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.25), "暂停设置即时生效并写入独立测试文件")
	panel()._fullscreen(false)
	check(config.load(panel().settings_path) == OK and config.get_value("display", "fullscreen") == false and config.get_value("audio", "volume") == 25, "两项设置共同持久化")
	var saved_bytes := FileAccess.get_file_as_bytes(panel().settings_path)
	panel().settings_path = base + "-absent/settings.cfg"
	panel().volume.value = 30
	check(panel().feedback.text.contains("保存失败") and is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.3), "设置保存失败显示原因，实际音量仍生效")
	panel().menu_button.pressed.emit()
	check(panel().confirmation.visible and paused, "回主菜单先确认并保持暂停")
	panel()._unhandled_key_input(key(KEY_ESCAPE))
	check(panel().content.visible and paused, "确认中的 Esc 取消退出，继续暂停")
	panel()._unhandled_key_input(key(KEY_ESCAPE))
	await frames()
	check(not paused and panel() == null and screen.pause_snapshot() == before, "再次 Esc 继续，城市资源和步数保持")
	flow.run.depart_city(7)
	screen.show_floor_map()
	before = screen.pause_snapshot()
	screen._input(key(KEY_ESCAPE))
	await create_timer(0.2).timeout
	check(paused and screen.pause_snapshot() == before, "地图 Esc 暂停，不推进移动或刷新")
	panel().resume_button.pressed.emit()
	await frames()
	screen._open_inventory()
	screen._open_pause()
	check(panel() == null and not paused, "背包窗口优先，不叠加暂停")
	screen.inventory.queue_free()
	await frames()
	check(flow.run.enter("1a") == "battle", "进入真实战斗")
	screen.start_encounter()
	await wait_ready()
	screen.battle = State.new()
	screen.battle.setup(flow.run.character, 1, 7, false, {}, "armored", {}, "goblin")
	screen.battle.order.assign(["lorn", "goblin", "goblin_b"])
	screen.battle.cursor = 0
	screen._refresh()
	screen._select("strike")
	screen._input(key(KEY_ESCAPE))
	check(screen.selected.is_empty() and panel() == null, "战斗第一次 Esc 取消选中技能")
	screen._input(key(KEY_ESCAPE))
	check(paused and panel() != null, "无技能选中时 Esc 暂停")
	before = screen.pause_snapshot()
	screen._input(key(KEY_SPACE))
	screen._end_turn()
	screen._select("fire_potion")
	check(not screen.gm_kill_enemy() and not screen.gm_recovery_reason("restore_party").is_empty() and screen.pause_snapshot() == before, "暂停屏蔽快捷键、直接回调和 GM 操作")
	panel().resume()
	await frames()
	screen.battle.cursor = 1
	screen._drive_enemy()
	screen._open_pause()
	before = screen.pause_snapshot()
	await create_timer(1.1).timeout
	check(paused and screen.busy and screen.pause_snapshot() == before, "暂停冻结敌人真实计时、随机数与资源")
	var capture := OS.get_environment("TENSEI_PAUSE_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	panel().resume_button.pressed.emit()
	await wait_ready()
	check(screen.battle.current_id() == "lorn" and not screen.busy, "继续后两个敌人各行动，交回原先攻下一名己方")
	screen._select("fire_potion")
	screen.targets.goblin_b.pressed.emit()
	check(screen.busy, "药水实际进入反馈动画")
	var floating: Label = screen.canvas.get_child(screen.canvas.get_child_count() - 1)
	var position: Vector2 = floating.position
	screen._open_pause()
	before = screen.pause_snapshot()
	await create_timer(0.7).timeout
	check(paused and screen.busy and screen.pause_snapshot() == before and floating.position == position, "暂停冻结真实浮字 tween 及反馈状态")
	panel().resume()
	await wait_ready()
	check(not screen.busy and screen.battle.action == 0, "继续后完成同一次反馈，不重复扣行动和药水")
	screen._open_pause()
	panel().queue_free()
	await frames()
	check(not paused, "外部释放暂停窗口恢复引擎处理")
	screen._open_pause()
	panel().menu_button.pressed.emit()
	panel().cancel_button.pressed.emit()
	check(paused and panel().content.visible, "点击取消保留暂停及原战斗")
	panel().menu_button.pressed.emit()
	panel().confirm_button.pressed.emit()
	await frames()
	check(not paused and current_scene.get_script() == preload("res://Scripts/UI/main_menu.gd"), "确认离开返回主菜单且不遗留暂停")
	check(FileAccess.get_file_as_bytes(base + "-settings.cfg") == saved_bytes, "失败写入不覆盖此前设置文件")
	AudioServer.set_bus_volume_linear(0, original_volume)
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	DirAccess.remove_absolute(base + "-settings.cfg")
	print("PAUSE MENU CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
