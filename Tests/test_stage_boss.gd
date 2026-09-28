extends SceneTree

const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Battle = preload("res://Scripts/Battle/battle_state.gd")
const Store = preload("res://Scripts/Core/expedition_save.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var run := Run.new()
	run.setup(123, 4)
	for level in range(2):
		for id in ["1b", "2b", "3b", "exit"]:
			if run.enter(id) == "battle": run.finish_battle(run.character, true)
	check(run.floor_number == 3 and not run.character.captain_defeated, "普通战斗不完成首领目标")
	var old: Dictionary = run.save_data()
	old.character.erase("captain_defeated")
	check(not Run.from_save(old).character.captain_defeated, "旧快照补未完成目标")
	var store := Store.new()
	store.base_path = "user://test-boss-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var bytes := var_to_bytes(old)
	var file := FileAccess.open(store.base_path + ".0.save", FileAccess.WRITE)
	file.store_var({"version": 1, "content_version": "demo-city-1", "generation": 1, "payload": bytes, "checksum": store._checksum(bytes)})
	file.close()
	check(not store.inspect().is_empty(), "旧城市版本磁盘记录兼容")
	var flow = root.get_node("GameFlow")
	flow.run = run
	flow.profile = flow.saves.new_profile("首领验收")
	flow.show_map = true
	flow._change_scene(flow.BATTLE_SCENE)
	await process_frame
	await process_frame
	check(current_scene.map_buttons["1a"].text.contains("守关队长"), "靠近节点揭示首领名称")
	current_scene._enter_node("1a")
	await create_timer(1.1).timeout
	check(current_scene.battle.enemy.captain and current_scene.battle.enemy.max_hp == 44, "地图进入队长配置")
	var capture := OS.get_environment("TENSEI_BOSS_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture) == OK, "首领截图")
	check(current_scene.gm_kill_enemy(), "首领可用 GM 正常结算")
	check(run.character.captain_defeated, "首领胜利写入角色目标")
	var gold: int = run.character.gold
	check(not run.finish_battle(run.character, true) and run.character.gold == gold, "重复结算不重复发奖")
	check(store.save_run(run) and store.inspect().run.character.captain_defeated, "新版本保存读取保留目标")
	run.begin_return()
	while run.phase == "returning":
		run.step_return(run.return_targets()[0].key)
		if not run.pending.is_empty(): run.finish_battle(run.character, true)
	run.enter_city()
	check(run.character.captain_defeated, "返程入城不清除目标")
	run.depart_city(456)
	check(run.character.captain_defeated, "下一趟保留目标")
	var boss := Battle.new()
	boss.setup(run.character, 3, 11, true)
	boss.cursor = boss.order.find("goblin")
	var hp: int = boss.hero.hp
	check(boss.enemy_intent().contains("蓄力") and boss.enemy_turn() and boss.charging and boss.hero.hp == hp, "蓄力回合不攻击")
	check(boss.enemy_intent().contains("1d10+4"), "重击预告显示数值")
	check(boss.use_ability("guard", "lorn") and boss.end_turn(), "玩家可以预先闪避")
	check(boss.enemy_turn() and not boss.charging and boss.current_id() == "lorn", "重击消耗敌人一回合并清除蓄力")
	check(boss.enemy_intent().contains("蓄力"), "重击后回到蓄力预告")
	var normal := Battle.new()
	normal.setup(run.character, 3, 11)
	check(not normal.enemy.captain and normal.enemy_intent().is_empty() and normal.enemy.max_hp == 24, "普通敌人配置不变")
	for suffix in [".0.save", ".1.save"]: DirAccess.remove_absolute(store.base_path + suffix)
	print("STAGE BOSS CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
