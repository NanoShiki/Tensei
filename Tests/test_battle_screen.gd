extends SceneTree

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var screen = load("res://Scenes/Battle/battle.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame

	_check(screen.timeline_row.get_child_count() == 6, "时间轴应展示未来六次行动")
	_check(screen.card_grid.get_child_count() == 8, "卡牌区按钮数量应等于洛恩持有卡数")
	_check(screen.field_row.get_child_count() == 2, "战场应包含我方与敌方两列")
	_check(screen.log_label != null, "战斗日志应已构建")
	_check(screen.resource_box.get_child_count() > 0, "资源区应已构建")

	var guard_button := _find_card_button(screen, "防御")
	_check(guard_button != null, "应能找到防御卡按钮")
	if guard_button != null:
		guard_button.pressed.emit()
		await process_frame
		_check(is_instance_valid(screen) and screen.battle.outcome == "ongoing", "点击防御后界面应继续可用")
		_check(screen.card_grid.get_child_count() == 8, "点击防御后卡牌区应重建完成")

	var lorn: RefCounted = screen.battle.allies[0]
	var start_hp: int = lorn.hp
	var start_log: String = screen.log_label.text
	_auto_play(screen, 300)
	_check(screen.battle.outcome != "ongoing", "循环出卡后战斗应结束")
	_check(screen.result_panel.visible, "战斗结束时应显示结果面板")
	_check(screen.card_grid.get_child_count() == 8, "不可用或战斗结束后卡牌仍应保留在界面中")
	_check(screen.log_label.text != start_log and screen.log_label.text != "", "日志应随出卡追加内容")
	_check(lorn.hp != start_hp or screen.battle.outcome == "victory", "资源或战局应随出卡变化")

	var disabled := 0
	for child in screen.card_grid.get_children():
		if child.disabled:
			disabled += 1
	_check(disabled == 8, "战斗结束后卡牌区应全部禁用")

	if _failed > 0:
		push_error("FAILED: %d checks" % _failed)
		quit(1)
		return
	print("PASS: battle screen layout, cards, combat loop, log and resources")
	screen.queue_free()
	await process_frame
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed += 1
		push_error(message)


func _auto_play(screen, limit: int) -> void:
	var steps := 0
	while screen.battle.outcome == "ongoing" and steps < limit:
		var actor: RefCounted = screen.battle.current_actor()
		if actor == null or actor.team != "ally":
			screen.battle.advance_until_player_turn()
			steps += 1
			continue
		var played := false
		var target := _first_alive(screen.battle.enemies)
		for card in screen.battle.available_cards(actor):
			if not card["can_play"]:
				continue
			var kind := str(card["target"])
			if kind == "enemy_single" and target != null:
				played = screen.try_play(str(card["card_id"]), target)
			elif kind != "enemy_single":
				played = screen.try_play(str(card["card_id"]))
			if played:
				break
		if not played:
			break
		steps += 1


func _find_card_button(screen, card_name: String) -> Button:
	for child in screen.card_grid.get_children():
		if child is Button and str(child.text).begins_with(card_name):
			return child
	return null


func _first_alive(units: Array) -> RefCounted:
	for unit in units:
		if unit.is_alive():
			return unit
	return null
