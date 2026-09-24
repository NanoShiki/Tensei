extends SceneTree
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _run() -> void:
	var screen = load("res://Scenes/Battle/battle.tscn").instantiate()
	root.add_child(screen)
	await create_timer(1.1).timeout
	check(screen.buttons.size() == 6 and screen.targets.size() == 2, "技能道具和两侧目标")
	check(screen.battle.current_id() == "lorn", "敌人先攻后归还控制")
	var hp: int = screen.battle.enemy.hp
	screen.buttons.strike.pressed.emit()
	check(screen.selected == "strike" and screen.battle.enemy.hp == hp, "选技能不立即伤害")
	check(not screen.targets.goblin.disabled and screen.targets.lorn.disabled, "仅合法目标可点击")
	var cancel := InputEventKey.new()
	cancel.keycode = KEY_ESCAPE
	cancel.pressed = true
	screen._input(cancel)
	check(screen.selected.is_empty() and screen.battle.action == 1, "取消不消耗行动")
	screen.buttons.strike.pressed.emit()
	screen.targets.goblin.pressed.emit()
	await create_timer(0.5).timeout
	check(screen.battle.action == 0, "点击目标后消耗一次行动")
	for button in screen.buttons.values(): check(button.disabled, "行动用尽后所有技能和道具禁用")
	check(not screen.end_button.disabled, "结束回合仍可用")
	screen.end_button.pressed.emit()
	await create_timer(1.1).timeout
	check(screen.battle.action == 1 and screen.battle.current_id() == "lorn", "下一回合恢复一次行动")
	screen.battle.hero.hp = 15
	screen._select("potion")
	check(not screen.targets.lorn.disabled and screen.targets.goblin.disabled, "治疗选择己方")
	screen.targets.lorn.pressed.emit()
	await create_timer(0.5).timeout
	check(screen.battle.hero.hp == 27 and screen.battle.action == 0, "治疗界面操作")
	# 使用实际目标点击贯穿胜利和结算界面。
	screen.battle.enemy.hp = 1
	screen.battle.hero.hp = 1000
	for step in range(30):
		if screen.battle.outcome != "ongoing": break
		if screen.battle.action == 0:
			screen._end_turn()
			await create_timer(1.1).timeout
		screen._select("strike")
		screen._target("goblin")
		await create_timer(0.5).timeout
	check(screen.battle.outcome == "victory" and screen.result_panel.visible, "胜利面板可见")
	check(screen.end_button.disabled, "结算后禁止结束回合")
	screen.queue_free()
	await process_frame
	var flow = root.get_node("GameFlow")
	flow.run = load("res://Scripts/Exploration/floor_run.gd").new()
	flow.run.setup(123)
	flow.show_map = true
	screen = load("res://Scenes/Battle/battle.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	check(screen.map_visible, "地图入口")
	screen._enter_node("1a")
	await create_timer(1.1).timeout
	check(not screen.map_visible and flow.run.pending == "1a", "地图节点进入战斗")
	screen.battle.enemy.hp = 0
	screen.battle._check_outcome()
	screen._settle()
	screen.show_floor_map()
	check(flow.run.current == "1a" and flow.run.pending == "" and screen.map_visible, "胜利返回同层进度")
	screen.size = Vector2(960, 540)
	screen._layout()
	check(is_equal_approx(screen.canvas.scale.x, 0.75), "小窗口完整缩放")
	screen.queue_free()
	await process_frame
	print("SCREEN CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
