extends SceneTree

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var flow = root.get_node("GameFlow")
	var gm = get_first_node_in_group("gm_panel")
	check(gm != null and not gm.is_open(), "GM常驻且默认收起")
	gm.toggle_button.pressed.emit()
	check(gm.is_open() and gm.rows.kill_enemy.button.disabled, "菜单中秒杀不可用")
	flow.run = load("res://Scripts/Exploration/floor_run.gd").new()
	flow.run.setup(123)
	flow.show_map = true
	var screen = load("res://Scenes/Battle/battle.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	gm.refresh_commands()
	check(gm.rows.kill_enemy.button.disabled, "地图中不可秒杀")
	screen._enter_node("1a")
	screen.busy = true
	gm.refresh_commands()
	check(gm.rows.kill_enemy.button.disabled and not screen.gm_kill_enemy(), "动作中拒绝秒杀以保护异步结算")
	await create_timer(1.2).timeout
	# 无敌人先攻时恢复上面测试设置的busy；有敌人先攻时异步流程已完成。
	screen.busy = false
	gm.refresh_commands()
	check(not gm.rows.kill_enemy.button.disabled, "战斗待操作时可秒杀")
	root.size = Vector2i(960, 540)
	await process_frame
	var capture := OS.get_environment("TENSEI_GM_CAPTURE_PATH")
	if not capture.is_empty():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture) == OK, "GM截图保存")
	var hero: Dictionary = screen.battle.hero.duplicate(true)
	var action: int = screen.battle.action
	var random_state: int = screen.battle.rng.state
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	screen._input(key)
	check(screen.battle.current_id() == "lorn", "GM展开时不触发战斗快捷键")
	gm.rows.kill_enemy.button.pressed.emit()
	check(screen.battle.enemy.hp == 0 and screen.battle.outcome == "victory" and screen.result_panel.visible, "点击秒杀显示正常胜利界面")
	check(screen.battle.hero == hero and screen.battle.action == action and screen.battle.rng.state == random_state, "秒杀不扣资源行动或随机数")
	check(flow.run.pending.is_empty() and flow.run.current == "1a" and flow.run.node("1a").cleared, "探索战斗正常回写节点")
	var route: Array = flow.run.route.duplicate()
	gm.rows.kill_enemy.button.pressed.emit()
	check(flow.run.route == route and not screen.gm_kill_enemy(), "重复点击不重复结算")
	screen.show_floor_map()
	gm.refresh_commands()
	check(gm.rows.kill_enemy.button.disabled and flow.run.can_enter("2b"), "回地图后禁用秒杀且路径解锁")
	screen.queue_free()
	await process_frame
	gm.refresh_commands()
	check(gm.rows.kill_enemy.button.disabled and get_nodes_in_group("gm_panel").size() == 1, "场景销毁无悬空目标且面板不重复创建")
	root.size = Vector2i(960, 540)
	await process_frame
	check(gm.menu.get_global_rect().end.x <= root.get_visible_rect().size.x and gm.menu.get_global_rect().end.y <= root.get_visible_rect().size.y, "小窗口完整容纳GM面板")
	for i in range(15):
		check(gm.register_command("test_%d" % i, "测试指令 %d" % i, "仅自动化测试用于验证滚动与扩展。", func(): return true, func(): return ""), "可注册扩展指令")
	check(not gm.register_command("kill_enemy", "重复", "", func(): return true, func(): return ""), "重复指令ID拒绝")
	await process_frame
	await process_frame
	gm.scroll.scroll_vertical = 200
	await process_frame
	check(gm.scroll.scroll_vertical > 0, "指令增加后滚动容器可向下滑动")
	key.keycode = KEY_ESCAPE
	gm._input(key)
	check(not gm.is_open(), "Esc收起GM菜单")
	print("GM PANEL CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
