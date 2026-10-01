extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	create_timer(25).timeout.connect(func(): quit(1))
	var flow = root.get_node("GameFlow")
	flow.start_battle("lorn")
	await process_frame
	await process_frame
	var screen = current_scene
	for i in range(50):
		if not screen.busy: break
		await create_timer(0.1).timeout
	var before: Dictionary = screen.battle.log_state()
	var rng: int = screen.battle.rng.state
	var history: Window = screen._open_battle_history()
	check(history != null and "先攻" in history.get_meta("history_lines").text, "实际窗口包含当前先攻记录")
	check(screen._open_battle_history() == null, "禁止重复记录窗口")
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	screen._input(key)
	check(screen.battle.log_state() == before and screen.battle.rng.state == rng, "记录窗口只读且快捷键不穿透")
	var capture := OS.get_environment("TENSEI_HISTORY_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	key.keycode = KEY_ESCAPE
	history.window_input.emit(key)
	await process_frame
	await process_frame
	check(not is_instance_valid(history), "Esc关闭实际窗口")
	screen.busy = true
	check(screen._open_battle_history() == null, "动作中不能打开记录")
	screen.busy = false
	for i in range(210): screen.battle.logs.append("回顾 %d" % i)
	before = screen.battle.log_state()
	history = screen._open_battle_history()
	check(history.get_meta("history_lines").text.begins_with("回顾 10") and history.get_meta("history_lines").text.ends_with("回顾 209") and screen.battle.log_state() == before, "长战斗显示最近200条且保持原记录")
	history.queue_free()
	await process_frame
	print("BATTLE HISTORY CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
