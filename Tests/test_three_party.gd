extends SceneTree

const State = preload("res://Scripts/Battle/battle_state.gd")
const Characters = preload("res://Scripts/Character/character_library.gd")
const Progress = preload("res://Scripts/Core/player_progress.gd")
const Run = preload("res://Scripts/Exploration/floor_run.gd")
const Board = preload("res://Scripts/UI/familia_board.gd")
const LibraryTest = preload("res://Tests/test_save_library.gd")
var failures := 0
var base := "user://test-library-three-party-" + Crypto.new().generate_random_bytes(8).hex_encode()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)

func frames() -> void:
	await process_frame
	await process_frame

func _run() -> void:
	create_timer(40).timeout.connect(func(): quit(1))
	var source := Progress.new()
	source.data = Progress.initial()
	var scout: Dictionary = source.companion("scout")
	var state := State.new()
	state.setup(Characters.resolve(), 1, 7, false, State.practice_companion(), "goblin", scout)
	check(state.order.size() == 4 and state.friends().size() == 3 and state.unit("scout").id == "scout", "三己方独立进入先攻和目标注册")
	state.enemy.hp = 100
	state.enemy.max_hp = 100
	var seen := {"lorn": 0, "squire": 0, "scout": 0}
	for i in range(4):
		if state.current_id() == "goblin": state.enemy_turn()
		else:
			seen[state.current_id()] += 1
			check(state.action == 1, "每名己方在自己的回合得到一次行动")
			check(state.use_ability("guard", state.current_id()) and state.action == 0, "三成员闪避各自消耗行动")
			state.end_turn()
	check(seen.lorn == 1 and seen.squire == 1 and seen.scout == 1 and state.round_number == 2, "整轮每位存活己方恰好行动一次")
	state.setup(Characters.resolve(), 1, 7, false, State.practice_companion(), "goblin", scout)
	state.cursor = state.order.find("scout")
	check(state.use_ability("guard", "scout") and state.scout_guarding and not state.guarding and not state.ally_guarding, "游侠闪避不影响其他成员")
	state.action = 1
	state.scout.hp = 8
	var untouched: Dictionary = state.ally.duplicate(true)
	check(state.use_ability("surge", "scout") and state.scout.hp == 16 and state.scout.surge == 0 and state.ally == untouched and state.hero.surge == 1, "游侠回气独立恢复和次数")
	state.action = 1
	var bottles: int = state.hero.potions
	check(state.can_target("potion", "scout") and state.use_ability("potion", "scout") and state.scout.hp == 22 and state.hero.potions == bottles - 1, "共享药水可治疗第三名存活队友")
	state.scout.hp = 0
	state.action = 1
	var rng_state: int = state.rng.state
	check(not state.use_ability("potion", "scout") and state.action == 1 and state.rng.state == rng_state, "倒下游侠不能复活、不扣行动和随机数")
	state.hero.hp = 0
	state.ally.hp = 0
	state.scout.hp = 22
	state._check_outcome()
	check(state.outcome == "ongoing", "仅第三名成员存活时仍继续")
	state.cursor = state.order.find("goblin")
	check(state.enemy_turn() and state.last_event.target == "scout" and state.current_id() == "scout", "敌人只攻击存活游侠且先攻跳过倒下者")
	state.scout.hp = 0
	state._check_outcome()
	check(state.outcome == "defeat", "三人全倒下才失败")
	state.setup(Characters.resolve(), 1, 7)
	check(state.order.size() == 2 and state.scout.is_empty() and not state.scout_guarding, "复用状态切回单人清空第三成员")
	var targets_seen := {}
	for seed_value in range(30):
		state.setup(Characters.resolve(), 1, seed_value, false, State.practice_companion(), "goblin", scout)
		state.cursor = state.order.find("goblin")
		state.enemy_turn()
		targets_seen[state.last_event.target] = true
	check(targets_seen.has("lorn") and targets_seen.has("squire") and targets_seen.has("scout"), "随机攻击可覆盖三位存活成员")
	var flow = root.get_node("GameFlow")
	flow.saves.base_path = base
	flow.progress.base_path = base + "-shared"
	flow.start_character("三人角色")
	await frames()
	flow.run.character.quests.hunt = "claimed"
	check(flow.familia_service("join") and flow.familia_service("enlist"), "建立晨行卫士编队")
	check(not flow.familia_service("enlist_scout"), "等级1拒绝游侠招募")
	flow.run.depart_city(7)
	for i in range(40):
		if flow.progress.guild_level() >= 2: break
		if flow.run.enter(flow.run.node(flow.run.current).next[0]) == "battle": flow.settle_battle(flow.run.character, flow.party_companion(), true)
	flow.run.begin_return()
	for i in range(120):
		if flow.run.phase == "returned": break
		flow.run.step_return(flow.run.return_targets()[0].key)
		if not flow.run.pending.is_empty(): flow.settle_battle(flow.run.character, flow.party_companion(), true)
	flow.run.enter_city()
	current_scene.show_floor_map()
	current_scene.city_buttons.familia.pressed.emit()
	var board: Window
	for child in current_scene.get_children():
		if child.get_script() == Board: board = child
	check(board != null and not board.buttons.enlist_scout.disabled, "等级2城市菜单允许第二队友")
	board.buttons.enlist_scout.pressed.emit()
	check(flow.run.character.scout_enlisted and flow.party_companion("scout").max_hp == 22 and flow.progress.data.familias.dawn.scout_xp == 0, "新游侠从自身成长起点加入")
	var city_capture := OS.get_environment("TENSEI_THREE_CITY_CAPTURE")
	if not city_capture.is_empty():
		root.size = Vector2i(960, 540)
		await process_frame
		board.rows.get_parent().scroll_vertical = 1000
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(city_capture)
	board.queue_free()
	await frames()
	flow.city_service("rest")
	flow.run.depart_city(9)
	var profile_id: String = flow.profile.id
	var start: String = flow.saves.save_record(flow.run, flow.profile, "三人出发")
	flow.run.enter("1a")
	current_scene.start_encounter()
	await create_timer(1.2).timeout
	check(current_scene.targets.size() == 4 and current_scene.battle.order.size() == 4, "实际三人战斗显示四单位与先攻")
	check(current_scene.targets.lorn.position.x < current_scene.targets.squire.position.x and current_scene.targets.squire.position.x < current_scene.targets.scout.position.x and current_scene.targets.scout.position.x < current_scene.targets.goblin.position.x, "三己方左侧排列、敌人在右")
	current_scene.battle.cursor = current_scene.battle.order.find("scout")
	current_scene.battle.action = 1
	current_scene.battle.scout.hp = 10
	current_scene._refresh()
	current_scene.buttons.potion.pressed.emit()
	check(not current_scene.targets.scout.disabled, "实际药水按钮可选游侠")
	var capture := OS.get_environment("TENSEI_THREE_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	current_scene.targets.scout.pressed.emit()
	await create_timer(0.6).timeout
	check(current_scene.battle.scout.hp == 22 and current_scene.battle.action == 0, "第三成员治疗实际反馈和行动")
	var old_contribution: int = flow.progress.data.familias.dawn.contribution
	var old_squire: int = flow.progress.data.familias.dawn.squire_xp
	check(current_scene.gm_kill_enemy(), "三人GM正常结算")
	check(flow.progress.data.familias.dawn.contribution == old_contribution + 1 and flow.progress.data.familias.dawn.squire_xp == old_squire + 2 and flow.progress.data.familias.dawn.scout_xp == 2, "三人胜利贡献一次、每个参战队友经验各一次")
	check(flow.load_exploration(profile_id, start), "三人个人记录恢复")
	await frames()
	check(flow.run.character.scout_enlisted and flow.party_companion("scout").experience == 2, "三人编队恢复，共享游侠经验保持")
	flow.run.character.hp = 0
	flow.run.character.party_hp = 0
	flow.run.character.scout_hp = 9
	check(flow.run.has_living_party() and Run.from_save(flow.run.save_data()) != null, "仅游侠存活可以保存恢复与返程")
	flow.run.begin_return()
	flow.run.step_return(flow.run.return_target().key)
	flow.run.enter_city()
	check(flow.city_service("rest") and flow.run.character.hp == 36 and flow.run.character.party_hp == flow.party_companion().max_hp and flow.run.character.scout_hp == 22, "旅店原子恢复三人包括倒下者")
	check(flow.familia_service("dismiss") and flow.run.character.scout_enlisted, "卫士留城时游侠仍可独立随队")
	check(flow.run.quest_service("familia_patrol", "accept", flow.guild_level()), "游侠单队友也能接成员任务")
	flow.run.depart_city(11)
	flow.run.enter("1a")
	check(flow.settle_battle(flow.run.character, {}, true, flow.party_companion("scout")) and flow.run.character.familia_wins == 1, "仅游侠实际参战推进成员巡守")
	check(flow.progress.data.familias.dawn.squire_xp == old_squire + 2 and flow.progress.data.familias.dawn.scout_xp == 4, "留城卫士不获得游侠场次经验")
	var legacy: Dictionary = flow.run.save_data()
	legacy.character.growth_pending = ["legacy-pending"]
	var migrated = Run.from_save(legacy)
	check(migrated.character.growth_pending[0] == {"id": "legacy-pending", "members": ["squire"]}, "旧待同步字符串转为原卫士参战事件")
	legacy = flow.run.save_data()
	legacy.character.scout_hp = 35
	check(Run.from_save(legacy) == null, "拒绝游侠越界生命")
	var cleanup = LibraryTest.new()
	cleanup.cleanup(base)
	cleanup.free()
	for suffix in [".0.save", ".1.save", ".tmp"]: DirAccess.remove_absolute(flow.progress.base_path + suffix)
	print("THREE PARTY CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
