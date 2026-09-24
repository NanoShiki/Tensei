extends SceneTree
const State = preload("res://Scripts/Battle/battle_state.gd")
const Characters = preload("res://Scripts/Character/character_library.gd")
const Run = preload("res://Scripts/Exploration/floor_run.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func player_state(seed_value: int = 42) -> RefCounted:
	var state := State.new()
	state.setup(Characters.resolve(), 1, seed_value)
	if state.current_id() == "goblin": state.enemy_turn()
	return state

func _initialize() -> void:
	var state := player_state()
	var hp: int = state.enemy.hp
	var random_state: int = state.rng.state
	check(not state.use_ability("strike", "lorn"), "非法目标应拒绝")
	check(state.enemy.hp == hp and state.action == 1 and state.rng.state == random_state, "非法操作不得扣行动或消耗随机数")
	check(not state.use_ability("unknown", "goblin"), "未知技能拒绝")
	check(state.use_ability("strike", "goblin"), "首个行动成功")
	check(state.action == 0, "每回合只有一次行动")
	state.hero.hp = 20
	check(not state.use_ability("potion", "lorn"), "攻击后不能免费喝药")
	check(not state.use_ability("guard", "lorn"), "攻击后不能再次行动")
	state.grant_actions(1)
	check(state.action == 1 and state.use_ability("guard", "lorn"), "特殊效果增加行动")
	check(state.guarding, "闪避生效")
	state.grant_actions(2)
	state.end_turn()
	check(not state.use_ability("strike", "goblin"), "敌方回合不能行动")
	state.enemy_turn()
	check(state.action == 1 and not state.guarding, "新回合刷新一次行动并移除闪避，额外行动不累积")
	state.hero.hp = 10
	var potions: int = state.hero.potions
	check(state.use_ability("potion", "lorn"), "药水可使用")
	check(state.hero.hp == 22 and state.hero.potions == potions - 1 and state.action == 0, "药水同时消耗行动和数量")
	state = player_state()
	state.hero.hp = state.hero.max_hp
	check(not state.use_ability("potion", "lorn") and state.action == 1, "满血不可浪费药水")
	state.hero.hp = 1
	state.hero.potions = 0
	check(not state.use_ability("potion", "lorn"), "零药水不可使用")
	check(state.use_ability("surge", "lorn") and state.hero.hp == 9, "回气恢复生命并消耗行动")
	state.grant_actions(1)
	check(not state.use_ability("surge", "lorn"), "回气每场仅一次")
	check(state.hit_chance("strike") == 70 and state.hit_chance("power") == 55, "命中预览与骰点规则一致")
	state = player_state()
	var enemy_hp: int = state.enemy.hp
	var bottles: int = state.hero.fire_potions
	check(not state.use_ability("fire_potion", "lorn") and state.action == 1, "伤害药水不能选择自己")
	check(state.use_ability("fire_potion", "goblin"), "伤害药水直接选择敌人")
	check(state.enemy.hp == enemy_hp - 8 and state.hero.fire_potions == bottles - 1 and state.action == 0, "药水按自身效果伤害并消耗一次行动")
	var saw_crit := false
	var saw_miss := false
	for seed_value in range(100):
		state = player_state(seed_value)
		state.enemy.hp = 10000
		state.enemy.ac = 100
		state.use_ability("strike", "goblin")
		if state.last_event.text.begins_with("暴击"):
			saw_crit = true
			check(state.enemy.hp < 10000, "自然20无视高护甲")
		state = player_state(seed_value)
		state.enemy.ac = -100
		state.use_ability("strike", "goblin")
		if state.last_event.text == "未命中": saw_miss = true
	check(saw_crit and saw_miss, "覆盖自然20与自然1")
	for seed_value in range(20):
		state = player_state(seed_value)
		var steps := 0
		while state.outcome == "ongoing" and steps < 200:
			if state.current_id() == "goblin": state.enemy_turn()
			else:
				state.use_ability("strike", "goblin")
				state.end_turn()
			steps += 1
		check(state.outcome != "ongoing", "战斗必须有界结束")
		check(not state.use_ability("strike", "goblin") and not state.end_turn(), "结算后不得继续行动")
	state = player_state()
	state.hero.hp = 0
	state._check_outcome()
	check(state.outcome == "defeat", "败北判定")
	var run := Run.new()
	run.setup(123, 30)
	check(not run.can_enter("exit") and run.enter("exit") == "", "禁止跳节点")
	check(run.enter("1a") == "battle" and not run.can_enter("1b"), "战斗中锁定地图")
	var saved: Dictionary = run.character.duplicate(true)
	saved.hp = 17
	saved.potions = 1
	check(run.finish_battle(saved, true), "战胜完成节点")
	check(not run.finish_battle(saved, true), "重复结算不生效")
	check(run.character.hp == 17 and run.character.potions == 1, "跨战斗资源保留")
	check(run.enter("2b") == "rest" and run.character.hp == 27, "营地有限恢复")
	check(run.enter("2b") == "" and run.character.hp == 27, "节点不能重复领奖")
	for floor_number in range(1, 31):
		while run.current != "exit" and not run.completed and run.floor_number == floor_number:
			var choices: Array = run.node(run.current).next
			var id: String = choices[0]
			if run.enter(id) == "battle": run.finish_battle(run.character, true)
	check(run.completed and run.floor_number == 30, "30层都有出口且终点停止生成")
	run.setup(1)
	run.enter("1a")
	saved.hp = 0
	run.finish_battle(saved, false)
	check(not run.can_enter("1b"), "失败后不得继续探索")
	print("BATTLE / MAP CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
