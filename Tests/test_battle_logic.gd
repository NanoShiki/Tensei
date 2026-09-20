extends SceneTree

const CardLibrary = preload("res://Scripts/Battle/card_library.gd")
const CharacterLibrary = preload("res://Scripts/Character/character_library.gd")
const Combatant = preload("res://Scripts/Battle/combatant.gd")
const EnemyLibrary = preload("res://Scripts/Battle/enemy_library.gd")
const BattleState = preload("res://Scripts/Battle/battle_state.gd")

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_timeline_order_and_preview()
	_test_play_costs_and_damage()
	_test_fatigue()
	_test_guard_and_invalid_target()
	_test_charge_and_interrupt()
	_test_supply_uses()
	_test_zero_stamina_fallbacks()
	_test_outcomes()
	if _failed > 0:
		push_error("FAILED: %d checks" % _failed)
		quit(1)
		return
	print("PASS: battle logic timeline, cards, fatigue, guard, charge, supply, outcome")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed += 1
		push_error(message)


func _make_lorn() -> RefCounted:
	return Combatant.from_character(CharacterLibrary.resolve("lorn"), 0)


func _make_enemy(enemy_id: String, order: int) -> RefCounted:
	return Combatant.from_enemy(EnemyLibrary.resolve(enemy_id), order)


func _test_timeline_order_and_preview() -> void:
	var lorn := _make_lorn()
	var wolf := _make_enemy("cave_wolf", 1)
	var colossus := _make_enemy("stone_colossus", 2)
	var battle: RefCounted = BattleState.new()
	battle.setup([lorn], [wolf, colossus])
	_check(battle.current_actor() == wolf, "速度最高的洞穴狼应先行动")
	var before: float = lorn.next_act
	var preview: Array = battle.preview(4)
	_check(preview.size() == 4, "预览应返回请求的行动数")
	_check(preview[0]["actor"] == wolf, "预览首项应为洞穴狼")
	_check(lorn.next_act == before, "预览不得改变真实行动时点")
	_check(wolf.next_act == 0.0, "预览不得改变敌人行动时点")
	_check(preview[2]["actor"] == colossus and preview[2]["is_charging"], "石拳巨像的预览行动应标记蓄力")


func _test_play_costs_and_damage() -> void:
	var lorn := _make_lorn()
	var wolf := _make_enemy("cave_wolf", 1)
	wolf.next_act = 1000.0
	var battle: RefCounted = BattleState.new()
	battle.setup([lorn], [wolf])
	_check(battle.play_card(lorn, "swift_cut", wolf), "迅击应打出成功")
	_check(lorn.sp == 92, "迅击应扣除 8 点体力")
	_check(wolf.hp == 48, "迅击应对洞穴狼造成 12 点伤害")
	_check(is_equal_approx(lorn.next_act, 45.0), "迅击应按耗时 45 推进时间轴")
	lorn.next_act = 0.0
	wolf.next_act = 1000.0
	_check(battle.play_card(lorn, "flame_arrow", wolf), "火焰箭应打出成功")
	_check(lorn.mp == 28, "火焰箭应扣除 12 点魔力")
	_check(wolf.hp == 26, "火焰箭应对洞穴狼造成 22 点伤害")


func _test_fatigue() -> void:
	var lorn := _make_lorn()
	var wolf := _make_enemy("cave_wolf", 1)
	wolf.next_act = 1000.0
	lorn.sp = 19
	var battle: RefCounted = BattleState.new()
	battle.setup([lorn], [wolf])
	_check(is_equal_approx(lorn.fatigue_multiplier(), 1.25), "体力低于上限 20% 时疲劳系数应为 1.25")
	_check(battle.play_card(lorn, "basic_strike", wolf), "疲劳状态下普通攻击仍可用")
	_check(is_equal_approx(lorn.next_act, 75.0), "疲劳应立刻放大本次行动耗时")


func _test_guard_and_invalid_target() -> void:
	var lorn := _make_lorn()
	var wolf := _make_enemy("cave_wolf", 1)
	wolf.next_act = 1000.0
	var battle: RefCounted = BattleState.new()
	battle.setup([lorn], [wolf])
	_check(battle.play_card(lorn, "guard"), "防御应打出成功")
	_check(is_equal_approx(lorn.guard_ratio, 0.5), "防御后系数应为 0.5")
	_check(lorn.take_damage(10) == 5, "防御应将伤害减半")
	lorn.next_act = 0.0
	var sp_before: int = lorn.sp
	var guard_before: float = lorn.guard_ratio
	_check(not battle.play_card(lorn, "swift_cut", null), "缺少目标时出卡应失败")
	_check(lorn.sp == sp_before, "非法目标不得扣减资源")
	_check(is_equal_approx(lorn.guard_ratio, guard_before), "非法目标不得清除防御")
	_check(battle.play_card(lorn, "basic_strike", wolf), "普通攻击应清除防御并打出")
	_check(is_equal_approx(lorn.guard_ratio, 1.0), "自身行动后防御应失效")
	_check(lorn.take_damage(10) == 10, "防御失效后应受到全额伤害")


func _test_charge_and_interrupt() -> void:
	var lorn := _make_lorn()
	var colossus := _make_enemy("stone_colossus", 1)
	var battle: RefCounted = BattleState.new()
	battle.setup([lorn], [colossus])
	_check(battle.current_actor() == lorn, "对石拳巨像时应由洛恩先行动")
	_check(battle.play_card(lorn, "basic_strike", colossus), "普通攻击应为后续蓄力腾出时机")
	battle.advance_until_player_turn()
	_check(not colossus.pending_card.is_empty(), "石拳巨像第一次行动应宣告蓄力")
	_check(colossus.pending_card.get("card_id", "") == "stone_colossus_earth_shatter", "蓄力卡应为碎地重击")
	_check(battle.play_card(lorn, "interrupt_thrust", colossus), "打断突刺应打出成功")
	_check(colossus.pending_card.is_empty(), "打断后蓄力应作废")
	_check(colossus.hp == 92, "打断突刺应对石拳巨像造成 8 点伤害")


func _test_supply_uses() -> void:
	var lorn := _make_lorn()
	var wolf := _make_enemy("cave_wolf", 1)
	wolf.next_act = 1000.0
	lorn.sp = 40
	var battle: RefCounted = BattleState.new()
	battle.setup([lorn], [wolf])
	_check(battle.play_card(lorn, "ration"), "第一份干粮应可用")
	lorn.next_act = 0.0
	_check(battle.play_card(lorn, "ration"), "第二份干粮应可用")
	_check(lorn.sp == 100, "两份干粮应把体力恢复到上限")
	lorn.next_act = 0.0
	var cards: Array = battle.available_cards(lorn)
	var ration: Dictionary = {}
	for entry in cards:
		if entry["card_id"] == "ration":
			ration = entry
	_check(not ration.is_empty(), "次数耗尽后干粮仍应出现在卡牌列表中")
	_check(ration["can_play"] == false, "次数耗尽后干粮不可打出")
	_check(ration["reason"] == "次数已用尽", "干粮不可用原因应为次数已用尽")
	_check(not battle.play_card(lorn, "ration"), "次数耗尽后打出干粮应失败")


func _test_zero_stamina_fallbacks() -> void:
	var lorn := _make_lorn()
	var wolf := _make_enemy("cave_wolf", 1)
	wolf.next_act = 1000.0
	lorn.sp = 0
	lorn.mp = 0
	var battle: RefCounted = BattleState.new()
	battle.setup([lorn], [wolf])
	var cards: Array = battle.available_cards(lorn)
	var by_id := {}
	for entry in cards:
		by_id[entry["card_id"]] = entry
	_check(by_id["basic_strike"]["can_play"], "体力为 0 时普通攻击仍可用")
	_check(by_id["guard"]["can_play"], "体力为 0 时防御仍可用")
	_check(not by_id["swift_cut"]["can_play"], "体力为 0 时迅击不可用")
	_check(battle.play_card(lorn, "basic_strike", wolf), "零体力时应能打出普通攻击")
	lorn.next_act = 0.0
	_check(battle.play_card(lorn, "guard"), "零体力时应能打出防御")


func _test_outcomes() -> void:
	var lorn := _make_lorn()
	var wolf := _make_enemy("cave_wolf", 1)
	wolf.hp = 10
	wolf.next_act = 1000.0
	var victory: RefCounted = BattleState.new()
	victory.setup([lorn], [wolf])
	_check(victory.play_card(lorn, "basic_strike", wolf), "最后一击应打出成功")
	_check(victory.outcome == "victory", "敌人全灭应判定胜利")
	_check(victory.current_actor() == null, "战斗结束后当前行动者应为空")

	var doomed := _make_lorn()
	doomed.hp = 1
	var hunter := _make_enemy("cave_wolf", 1)
	var defeat: RefCounted = BattleState.new()
	defeat.setup([doomed], [hunter])
	defeat.advance_until_player_turn()
	_check(defeat.outcome == "defeat", "我方全灭应判定失败")
