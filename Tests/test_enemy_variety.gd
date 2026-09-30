extends SceneTree

const Run = preload("res://Scripts/Exploration/floor_run.gd")
const State = preload("res://Scripts/Battle/battle_state.gd")
const Characters = preload("res://Scripts/Character/character_library.gd")
const Enemies = preload("res://Scripts/Battle/enemy_library.gd")
const Choice = preload("res://Scripts/UI/encounter_choice.gd")
const Store = preload("res://Scripts/Core/expedition_save.gd")
var failures := 0
var base := "user://test-enemies-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	var run := Run.new()
	run.setup(7)
	check(run.node("1a").enemy_kind == "goblin" and run.node("1b").enemy_kind == "prowler", "第一层两条可见路线提供普通与迅足选择")
	check(run.encounter_preview("1b").details.contains("掷两次取高") and run.encounter_preview("3a").is_empty(), "合法下一步显示威胁，远处不泄露预览")
	var unchanged: Dictionary = run.save_data()
	for i in range(3): run.encounter_preview("1b")
	check(run.save_data() == unchanged, "预览不移动、不抽怪、不改刷新")
	var store := Store.new()
	store.base_path = base
	check(store.save_run(run) and store.inspect().run.node("1b").enemy_kind == "prowler", "磁盘记录保留敌人类型")
	var snapshot: Dictionary = run.save_data()
	for items in snapshot.floors.values():
		for item in items: item.erase("enemy_kind")
	var old = Run.from_save(snapshot)
	check(old != null and old.node("1b").enemy_kind == "goblin", "旧记录沿用普通哥布林且不重新抽取新敌人")
	snapshot = run.save_data()
	snapshot.floors[1][1].enemy_kind = "unknown"
	check(Run.from_save(snapshot) == null, "未知敌人类型拒绝读取")
	snapshot = run.save_data()
	snapshot.floors[1][0].enemy_kind = "prowler"
	check(Run.from_save(snapshot) == null, "非战斗节点不能携带敌人")
	var guarded := State.new()
	guarded.setup(Characters.resolve(), 1, 7, false, {}, "prowler")
	check(guarded.enemy.max_hp == 18 and guarded.enemy.dex == 5 and guarded.enemy.advantage and guarded.enemy_intent().contains("闪避"), "迅足生命、先攻、攻击优势及预告")
	var cases := 0
	for seed_value in range(30):
		var predicted := RandomNumberGenerator.new()
		predicted.seed = seed_value
		var first := predicted.randi_range(1, 20)
		var one_state := predicted.state
		var second := predicted.randi_range(1, 20)
		if first == 20 or second == 20: continue
		var two_state := predicted.state
		for guarded_target in [false, true]:
			var state := State.new()
			state.setup(Characters.resolve(), 1, 7, false, {}, "prowler")
			state.hero.ac = 100
			state.guarding = guarded_target
			state.rng.seed = seed_value
			state.cursor = state.order.find("goblin")
			check(state.enemy_turn() and state.rng.state == (one_state if guarded_target else two_state), "实际迅足攻击无闪避用两骰，闪避抵消为单骰")
		cases += 1
	check(cases > 10, "骰子反制覆盖多种确定性结果")
	var armored := State.new()
	armored.setup(Characters.resolve(), 2, 7, false, {}, "armored")
	check(armored.enemy.ac == 15 and armored.enemy.max_hp == 27 and not armored.enemy.advantage and armored.enemy_intent().contains("高防御"), "重甲具备独立防御与预告")
	armored.cursor = armored.order.find("lorn")
	var hp: int = armored.enemy.hp
	check(armored.use_ability("fire_potion", "goblin") and armored.enemy.hp == hp - 8, "灼烧药水仍直接对重甲造成伤害")
	var flow = root.get_node("GameFlow")
	flow.run = run
	flow.profile = flow.saves.new_profile("敌人验收")
	flow.show_map = true
	flow._change_scene(flow.BATTLE_SCENE)
	await process_frame
	await process_frame
	check(current_scene.map_buttons["1b"].text.contains("迅足哥布林") and current_scene.map_buttons["3a"].text == "未到访\n未知", "地图近处显示敌名、远处保持未知")
	current_scene.map_buttons["1b"].pressed.emit()
	var choice: Window
	for child in current_scene.get_children():
		if child.get_script() == Choice: choice = child
	check(choice != null and run.steps_taken == 0, "实际节点点击只打开预览")
	var capture := OS.get_environment("TENSEI_ENEMY_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	choice.fight_button.pressed.emit()
	await process_frame
	await process_frame
	await create_timer(1.2).timeout
	check(current_scene.battle.enemy.content_id == "prowler" and current_scene.battle.enemy.name == "迅足哥布林", "确认交战采用预览同一类型")
	check(current_scene.gm_kill_enemy(), "新类型仍正常GM胜利和战利品结算")
	check(run.node("1b").enemy_kind == "prowler" and run.node("1b").respawn_in >= 3, "清理保持类型且启动移动步数刷新")
	var timer: int = run.node("1b").respawn_in
	for i in range(timer): run._advance_step()
	check(run.node("1b").enemy_active and run.node("1b").enemy_kind == "prowler", "刷新保留同种敌人")
	for suffix in [".0.save", ".1.save", ".tmp"]: DirAccess.remove_absolute(base + suffix)
	print("ENEMY VARIETY CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
