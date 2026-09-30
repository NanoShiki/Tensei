extends SceneTree

const Battle = preload("res://Scripts/Battle/battle_state.gd")
const Characters = preload("res://Scripts/Character/character_library.gd")
var failures := 0

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
	var state := Battle.new()
	state.setup(Characters.resolve(), 1, 42, false, Battle.practice_companion())
	check(state.order.size() == 3 and state.order.has("squire"), "三名单位拥有固定先攻顺序")
	state.cursor = state.order.find("lorn")
	state.action = 1
	state.ally.hp = 10
	var stock: int = state.hero.potions
	check(state.reason("potion").is_empty() and state.can_target("potion", "squire") and not state.can_target("potion", "lorn"), "满血洛恩仍可治疗受伤队友")
	check(state.use_ability("potion", "squire") and state.ally.hp == 22 and state.hero.potions == stock - 1 and state.action == 0, "治疗队友消耗共享药水和本回合行动")
	check(not state.use_ability("guard", "lorn"), "行动用完后不能追加闪避")
	state.cursor = state.order.find("squire")
	state.action = 1
	var before: Dictionary = state.log_state()
	var random_state: int = state.rng.state
	check(not state.use_ability("guard", "lorn") and state.log_state() == before and state.rng.state == random_state, "卫士不能为别人使用自身闪避，错误目标无副作用")
	check(state.use_ability("surge", "squire") and state.ally.hp == 28 and state.ally.surge == 0 and state.hero.surge == 1, "回气次数各自独立")
	state.grant_actions(1)
	check(state.use_ability("guard", "squire") and state.ally_guarding and not state.guarding, "闪避状态各自独立")
	state.grant_actions(1)
	check(state.hit_chance("strike") == 65 and state.use_ability("strike", "goblin") and state.last_event.actor == "squire", "卫士攻击使用自身命中与行动者标识")
	state._advance()
	for i in range(4):
		if state.current_id() == "squire": break
		if state.current_id() == "goblin": state.enemy_turn()
		else: state.end_turn()
	check(state.current_id() == "squire" and state.action == 1 and not state.ally_guarding, "卫士下一回合刷新一次行动并清除自身闪避")
	# 当前每个存活己方一轮恰好行动一次。
	state.setup(Characters.resolve(), 1, 7, false, Battle.practice_companion())
	state.enemy.max_hp = 100
	state.enemy.hp = 100
	var seen := {"lorn": 0, "squire": 0}
	for i in range(3):
		if state.current_id() == "goblin": state.enemy_turn()
		else:
			seen[state.current_id()] += 1
			check(state.action == 1, "每人自己的回合有一次行动")
			state.use_ability("guard", state.current_id())
			state.end_turn()
	check(seen.lorn == 1 and seen.squire == 1 and state.round_number == 2, "整轮包含两名己方独立回合")
	state.hero.hp = 0
	state._check_outcome()
	check(state.outcome == "ongoing", "仍有存活队友时战斗继续")
	state.cursor = state.order.find("goblin")
	state.enemy_turn()
	check(state.current_id() == "squire" and state.ally.hp > 0, "敌人攻击存活队友且先攻跳过倒下成员")
	state.ally.hp = 0
	state._check_outcome()
	check(state.outcome == "defeat" and not state.end_turn(), "全队倒下才失败且结束后拒绝行动")
	state.setup(Characters.resolve(), 1, 7)
	check(state.ally.is_empty() and state.order.size() == 2 and not state.ally_guarding, "复用对象重置为原单人战斗")
	# 实际演练入口及目标选择。
	var flow = root.get_node("GameFlow")
	flow.start_battle("lorn")
	await frames()
	await create_timer(1.1).timeout
	current_scene._toggle_practice()
	await create_timer(1.1).timeout
	var screen = current_scene
	check(screen.battle.ally.size() > 0 and screen.targets.size() == 3, "双人演练入口显示三名单位")
	check(screen.targets.lorn.position.x < screen.targets.squire.position.x and screen.targets.squire.position.x < screen.targets.goblin.position.x, "两名己方在左、敌人在右")
	screen.battle.cursor = screen.battle.order.find("lorn")
	screen.battle.action = 1
	screen.battle.ally.hp = 10
	screen._refresh()
	screen.buttons.potion.pressed.emit()
	check(not screen.targets.squire.disabled and screen.targets.lorn.disabled and screen.targets.goblin.disabled, "实际治疗按钮仅高亮受伤队友")
	var capture := OS.get_environment("TENSEI_PARTY_CAPTURE")
	if not capture.is_empty():
		root.size = Vector2i(960, 540)
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(capture) == OK, "双人战斗截图")
	screen.targets.squire.pressed.emit()
	await create_timer(0.5).timeout
	check(screen.battle.ally.hp == 22 and screen.battle.action == 0 and not screen.end_button.disabled, "实际点击目标消耗一次行动，仍需结束回合")
	screen.end_button.pressed.emit()
	await create_timer(1.1).timeout
	check(screen.battle.is_player_turn() and screen.battle.action == 1, "下名己方可继续操作")
	check(screen.gm_kill_enemy() and screen.battle.outcome == "victory", "GM 沿用双人胜利规则")
	print("PARTY COMBAT CHECKS: ", failures, " failures")
	quit(1 if failures else 0)
