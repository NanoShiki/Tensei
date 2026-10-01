extends SceneTree

const State = preload("res://Scripts/Battle/battle_state.gd")
const Characters = preload("res://Scripts/Character/character_library.gd")
const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Store = preload("res://Scripts/Core/expedition_save.gd")
const Choice = preload("res://Scripts/UI/encounter_choice.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-enemy-parties-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frames() -> void:
	await process_frame
	await process_frame

func _run() -> void:
	create_timer(45).timeout.connect(func(): quit(1))
	for seed_value in range(12):
		var single := State.new()
		var explicit := State.new()
		single.setup(Characters.resolve(), 4, seed_value, false, State.practice_companion(), "armored")
		explicit.setup(Characters.resolve(), 4, seed_value, false, State.practice_companion(), "armored", {}, "")
		check(single.order == explicit.order and single.rng.state == explicit.rng.state and explicit.enemy_b.is_empty(), "单敌种子、先攻与随机数保持")
	var state := State.new()
	state.setup(Characters.resolve(), 4, 7, false, State.practice_companion(), "armored", {}, "prowler")
	check(state.order.size() == 4 and state.enemy_b.id == "goblin_b" and state.enemy_b.content_id == "prowler", "敌方实例 ID 独立且保持内容 ID")
	state.cursor = state.order.find("lorn")
	check(state.can_target("strike", "goblin_b") and state.hit_chance("strike", "goblin_b") > state.hit_chance("strike", "goblin"), "攻击可分别选择敌人并使用各自 AC")
	var hits := 0
	for seed_value in range(12):
		var attack := State.new()
		attack.setup(Characters.resolve(), 4, seed_value, false, {}, "armored", {}, "goblin")
		attack.cursor = attack.order.find("lorn")
		var first: Dictionary = attack.enemy.duplicate(true)
		check(attack.use_ability("strike", "goblin_b") and attack.last_event.target == "goblin_b" and attack.enemy == first, "物理攻击使用选中的第二敌人并保持第一敌人")
		if attack.enemy_b.hp < attack.enemy_b.max_hp: hits += 1
	check(hits > 0, "物理攻击第二敌人实际造成伤害")
	var old: Dictionary = state.enemy.duplicate(true)
	var hp: int = state.enemy_b.hp
	check(state.use_ability("fire_potion", "goblin_b") and state.enemy_b.hp == hp - 8 and state.enemy == old, "道具只伤害选中的第二敌人")
	state.grant_actions(1)
	state.enemy.hp = 8
	check(state.use_ability("fire_potion", "goblin") and state.enemy.hp == 0 and state.outcome == "ongoing", "击倒第一敌人不提前获胜")
	state.grant_actions(1)
	var snapshot: Dictionary = state.log_state()
	var random_state: int = state.rng.state
	check(not state.use_ability("strike", "goblin") and state.log_state() == snapshot and state.rng.state == random_state, "倒下敌人拒绝且行动、药水、随机数保持")
	check(state.end_turn(), "击倒敌人后可结束回合")
	for i in range(10):
		check(state.current_id() != "goblin", "先攻跳过倒下敌人")
		if state.is_player_turn(): state.end_turn()
		else: state.enemy_turn()
		if state.outcome != "ongoing": break
	var captain := State.new()
	captain.setup(Characters.resolve(), 3, 7, true, {}, "goblin", {}, "goblin")
	check(captain.enemy_b.is_empty() and captain.enemy.captain, "队长保持单敌蓄力机制")
	check(state.gm_kill_enemy() and state.enemy_b.hp == 0 and state.outcome == "victory", "GM 清除全部敌人")
	check(not state.gm_kill_enemy(), "胜利后重复 GM 拒绝")
	var defeat := State.new()
	defeat.setup(Characters.resolve(), 4, 7, false, State.practice_companion(), "armored", {}, "goblin")
	defeat.hero.hp = 0
	defeat._check_outcome()
	check(defeat.outcome == "ongoing", "队友存活可继续对战双敌")
	defeat.ally.hp = 0
	defeat._check_outcome()
	check(defeat.outcome == "defeat", "全队倒下才失败")
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("双敌验收")
	await frames()
	flow.run.character.quests.hunt = "claimed"
	check(flow.familia_service("join"), "建立眷族资格")
	for i in range(3): check(flow.progress.award_victory("enemy-party-fixture-%d" % i, flow.run.character.player_id), "解锁游侠")
	check(flow.familia_service("enlist") and flow.familia_service("enlist_scout"), "建立三人编队")
	flow.run.depart_city(7)
	for i in range(100):
		if flow.run.floor_number == 4: break
		var result: String = flow.run.enter(flow.run.node(flow.run.current).next[0])
		if result == "battle": check(flow.settle_battle(flow.run.character, flow.party_companion(), true, flow.party_companion("scout")), "实际推进到第四层")
	check(flow.run.floor_number == 4 and flow.run.node("1a").second_enemy_kind == "goblin", "第四层首个上方分支生成双敌")
	var run_before: Dictionary = flow.run.save_data()
	var preview: Dictionary = flow.run.encounter_preview("1a")
	check(preview.name == "双敌巡逻队" and preview.details.contains("重甲哥布林") and preview.details.contains("哥布林"), "预览包含两名敌人独立数据")
	check(flow.run.encounter_preview("3a").is_empty() and flow.run.save_data() == run_before, "远处未知、预览不推进状态")
	var record_id: String = flow.saves.save_record(flow.run, flow.profile, "双敌前")
	check(not record_id.is_empty(), "保存双敌地图")
	check(flow.load_exploration(flow.profile.id, record_id) and flow.run.node("1a").second_enemy_kind == "goblin", "磁盘读取保留完整敌方组合")
	await frames()
	var legacy: Dictionary = flow.run.save_data()
	for items in legacy.floors.values():
		for item in items: item.erase("second_enemy_kind")
	check(Run.from_save(legacy).node("1a").second_enemy_kind.is_empty(), "旧地图保持单敌，不追溯扩编")
	var legacy_store := Store.new()
	legacy_store.base_path = base + "-legacy"
	var payload := var_to_bytes(legacy)
	var file := FileAccess.open(legacy_store.base_path + ".0.save", FileAccess.WRITE)
	file.store_var({"version": Store.VERSION, "content_version": "demo-commerce-1", "generation": 1, "payload": payload, "checksum": legacy_store._checksum(payload)}, false)
	file.close()
	var bytes := FileAccess.get_file_as_bytes(legacy_store.base_path + ".0.save")
	check(not legacy_store.inspect().is_empty() and legacy_store.inspect().run.node("1a").second_enemy_kind.is_empty() and FileAccess.get_file_as_bytes(legacy_store.base_path + ".0.save") == bytes, "旧商贸内容版本读取兼容、保持单敌及原字节")
	DirAccess.remove_absolute(legacy_store.base_path + ".0.save")
	var invalid: Dictionary = flow.run.save_data()
	invalid.floors[4][1].second_enemy_kind = "unknown"
	check(Run.from_save(invalid) == null, "未知编队内容拒绝")
	invalid.floors[4][1].second_enemy_kind = "captain"
	check(Run.from_save(invalid) == null, "第二敌人不能携带队长蓄力")
	invalid = flow.run.save_data()
	invalid.floors[4][0].second_enemy_kind = "goblin"
	check(Run.from_save(invalid) == null, "非战斗节点拒绝编队")
	current_scene.show_floor_map()
	check(current_scene.map_buttons["1a"].text.contains("双敌") and current_scene.map_buttons["3a"].text.contains("未知"), "实际地图保持近处揭示范围")
	var steps: int = flow.run.steps_taken
	current_scene.map_buttons["1a"].pressed.emit()
	var choice: Window
	for child in current_scene.get_children():
		if child.get_script() == Choice: choice = child
	check(choice != null and flow.run.steps_taken == steps, "点击只打开双敌预览")
	var capture := OS.get_environment("TENSEI_ENEMY_PARTIES_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture.get_basename() + "-preview.png")
	choice.fight_button.pressed.emit()
	await frames()
	await create_timer(2.2).timeout
	var screen = current_scene
	check(screen.battle.order.size() == 5 and screen.targets.has("goblin_b") and screen.battle.enemy.content_id == "armored", "实际三人对双敌，五名先攻与两名右侧目标")
	check(not screen.busy and screen.battle.is_player_turn(), "初始连续敌人回合全部完成")
	screen._select("strike")
	check(not screen.targets.goblin.disabled and not screen.targets.goblin_b.disabled and screen.targets.goblin.tooltip_text != screen.targets.goblin_b.tooltip_text, "技能高亮两个目标且分别显示命中率")
	if not capture.is_empty():
		await frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	var first: Dictionary = screen.battle.enemy.duplicate(true)
	hp = screen.battle.enemy_b.hp
	screen._select("fire_potion")
	screen.targets.goblin_b.pressed.emit()
	await create_timer(0.6).timeout
	check(screen.battle.enemy_b.hp == hp - 8 and screen.battle.enemy == first and flow.run.pending == "1a", "真实点击第二敌人，仅扣其生命且不提前结算")
	screen.battle.order.assign(["goblin", "goblin_b", "lorn", "squire", "scout"])
	screen.battle.cursor = 0
	screen._drive_enemy()
	await create_timer(2.2).timeout
	check(not screen.busy and screen.battle.current_id() == "lorn", "相邻敌人回合自动完成，正确交回己方")
	var gold: int = flow.run.character.gold
	var scrap: int = flow.run.character.scrap
	var contribution: int = flow.progress.data.familias.dawn.contribution
	check(screen.gm_kill_enemy() and screen.battle.enemy.hp == 0 and screen.battle.enemy_b.hp == 0, "实际 GM 清场双敌")
	check(flow.run.character.gold == gold + 3 and flow.run.character.scrap == scrap + 1 and flow.progress.data.familias.dawn.contribution == contribution + 1, "多敌按一个节点结算资源及共享贡献")
	check(not screen.gm_kill_enemy() and flow.run.character.gold == gold + 3, "重复 GM 不发奖")
	check(flow.run.node("1a").second_enemy_kind == "goblin", "清理保留组合")
	var countdown: int = flow.run.node("1a").respawn_in
	for i in range(countdown): flow.run._advance_step()
	check(flow.run.node("1a").enemy_active and flow.run.node("1a").second_enemy_kind == "goblin", "刷新保留双敌组合")
	check(flow.run.begin_return() and flow.run.step_return(flow.run.node("entry").key) and flow.run.current == "entry" and flow.run.begin_descent(), "双敌清理后自由返回再深入")
	var stock: int = flow.run.character.fire_potions
	check(flow.run.enter("1a", true) == "avoided" and flow.run.character.fire_potions == stock - 1 and flow.run.node("1a").enemy_active and flow.run.character.gold == gold + 3, "双敌绕行仍一瓶、保留怪物且无奖励")
	check(not flow.saves.save_record(flow.run, flow.profile, "双敌绕行").is_empty(), "绕行后的完整组合可保存")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]:
		if FileAccess.file_exists(flow.progress.base_path + suffix): DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("ENEMY PARTIES CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
