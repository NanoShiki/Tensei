extends RefCounted

const Log = preload("res://Scripts/Core/game_log.gd")
const Abilities = preload("res://Scripts/Battle/ability_library.gd")
const CharacterLibrary = preload("res://Scripts/Character/character_library.gd")
const Jobs = preload("res://Scripts/Character/job_library.gd")
const Enemies = preload("res://Scripts/Battle/enemy_library.gd")
var battle_id := ""
var hero: Dictionary
var enemy: Dictionary
var ally: Dictionary = {}
var ally_guarding := false
var rng := RandomNumberGenerator.new()
var order: Array[String] = []
var cursor := 0
var round_number := 1
var action := 1
var guarding := false
var outcome := "ongoing"
var logs: Array[String] = []
var last_event: Dictionary = {}
var charging := false

func setup(character: Dictionary, floor_number: int = 1, seed_value: int = -1, captain: bool = false, companion: Dictionary = {}, enemy_kind: String = "goblin") -> void:
	battle_id = Crypto.new().generate_random_bytes(8).hex_encode()
	hero = character.duplicate(true)
	hero["surge"] = 1
	ally = companion.duplicate(true)
	if not ally.is_empty(): ally["surge"] = 1
	ally_guarding = false
	enemy = Enemies.resolve("captain" if captain else enemy_kind, floor_number)
	charging = false
	if seed_value < 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	cursor = 0
	round_number = 1
	action = 1
	guarding = false
	outcome = "ongoing"
	logs.clear()
	last_event.clear()
	var h := rng.randi_range(1, 20) + int(hero.dex)
	var e := rng.randi_range(1, 20) + int(enemy.dex)
	order.assign(["lorn", "goblin"] if h >= e else ["goblin", "lorn"])
	logs.append("先攻：洛恩 %d / %s %d。" % [h, enemy.name, e])
	if not ally.is_empty():
		var a := rng.randi_range(1, 20) + int(ally.dex)
		var initiative := [{"id": "lorn", "roll": h, "tie": 0}, {"id": "squire", "roll": a, "tie": 1}, {"id": "goblin", "roll": e, "tie": 2}]
		initiative.sort_custom(func(left: Dictionary, right: Dictionary): return left.roll > right.roll or (left.roll == right.roll and left.tie < right.tie))
		order.clear()
		for item in initiative: order.append(item.id)
		logs.append("先攻：见习卫士 %d。" % a)
	_check_outcome()
	if outcome == "ongoing" and unit(current_id()).hp <= 0: _advance()
	Log.event("battle", "start", {"seed": str(rng.seed), "order": order, "state": log_state()})

func log_state() -> Dictionary:
	return {"battle_id": battle_id, "hero": hero.duplicate(true), "enemy": enemy.duplicate(true), "round": round_number,
		"actor": current_id(), "actions": action, "guarding": guarding, "outcome": outcome, "charging": charging,
		"last_event": last_event.duplicate(true), "ally": ally.duplicate(true), "ally_guarding": ally_guarding}

func current_id() -> String:
	return order[cursor] if outcome == "ongoing" else ""

func reason(id: String) -> String:
	if outcome != "ongoing": return "战斗已结束"
	if not is_player_turn(): return "等待敌人行动"
	if not Abilities.ENTRIES.has(id): return "未知技能"
	var job_reason: String = Jobs.reason(current_unit(), id)
	if not job_reason.is_empty(): return job_reason
	if action <= 0: return "本回合行动次数已用尽"
	var entry: Dictionary = Abilities.ENTRIES[id]
	if entry.has("stock") and int(hero.get(entry.stock, 0)) <= 0: return "药水已用尽"
	if id == "surge" and current_unit().surge <= 0: return "本场回气已用尽"
	if id == "surge" and current_unit().hp == current_unit().max_hp: return "生命已满"
	if id == "potion" and not can_target("potion", "lorn") and not can_target("potion", "squire"): return "没有可治疗的存活成员"
	return ""

func hit_chance(id: String) -> int:
	var modifier := int(current_unit().attack) - int(Abilities.ENTRIES[id].get("penalty", 0))
	return clampi(21 + modifier - int(enemy.ac), 1, 19) * 5

func use_ability(id: String, target: String) -> bool:
	var before := log_state()
	var result := _use_ability(id, target)
	Log.event("battle", "use_ability", {"input": {"ability": id, "target": target}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _use_ability(id: String, target: String) -> bool:
	if not reason(id).is_empty(): return false
	var entry: Dictionary = Abilities.ENTRIES[id]
	if not can_target(id, target): return false
	var actor := current_unit()
	action -= 1
	if entry.has("stock"):
		hero[entry.stock] -= 1
		var receiver := unit(target)
		var amount: int = entry.amount
		if entry.effect == "heal":
			amount = mini(amount, int(receiver.max_hp) - int(receiver.hp))
			receiver.hp += amount
		else:
			receiver.hp = maxi(0, int(receiver.hp) - amount)
		var text := ("+%d" if entry.effect == "heal" else "−%d") % amount
		logs.append("%s → %s：%s 生命。" % [entry.name, receiver.name, text])
		last_event = {"actor": actor.id, "target": receiver.id, "text": text}
	elif entry.target == "enemy":
		_attack(actor, enemy, int(entry.die), int(entry.bonus) + (CharacterLibrary.weapon_bonus(actor) if entry.get("weapon_bonus", true) else 0), int(entry.get("penalty", 0)))
	elif id == "guard":
		if actor.id == "lorn": guarding = true
		else: ally_guarding = true
		logs.append("%s采取闪避，持续至下次自身回合开始。" % actor.name)
		last_event = {"actor": actor.id, "target": actor.id, "text": "闪避"}
	else:
		var restored := mini(8, int(actor.max_hp) - int(actor.hp))
		actor.hp += restored
		actor.surge -= 1
		logs.append("%s使用%s，恢复 %d 生命。" % [actor.name, entry.name, restored])
		last_event = {"actor": actor.id, "target": actor.id, "text": "+%d" % restored}
	_check_outcome()
	return true

func _attack(attacker: Dictionary, target: Dictionary, die: int, damage_bonus: int, penalty: int = 0, advantage: bool = false) -> void:
	var roll := rng.randi_range(1, 20)
	var rolls := [roll]
	var guarded: bool = (target.id == "lorn" and guarding) or (target.id == "squire" and ally_guarding)
	var mode := "normal"
	if advantage and not guarded:
		rolls.append(rng.randi_range(1, 20))
		roll = maxi(roll, rolls[1])
		mode = "advantage"
	elif guarded and not advantage:
		rolls.append(rng.randi_range(1, 20))
		roll = mini(roll, rolls[1])
		mode = "disadvantage"
	var modifier := int(attacker.attack) - penalty
	var hit := roll == 20 or (roll != 1 and roll + modifier >= int(target.ac))
	var damage := 0
	if hit:
		damage = rng.randi_range(1, die) + damage_bonus
		if roll == 20: damage += rng.randi_range(1, die)
		target.hp = maxi(0, int(target.hp) - damage)
	var text := ("暴击 −%d" if roll == 20 else "−%d") % damage if hit else "未命中"
	logs.append("%s：d20(%d)+%d 对 AC %d → %s" % [attacker.name, roll, modifier, target.ac, text])
	last_event = {"actor": attacker.id, "target": target.id, "text": text}
	Log.event("battle", "attack", {"battle_id": battle_id, "actor": attacker.id, "content_id": attacker.get("content_id", ""), "target": target.id, "roll": roll, "rolls": rolls, "roll_mode": mode, "advantage": advantage, "guarded": guarded, "modifier": modifier, "ac": target.ac, "hit": hit, "damage": damage, "remaining_hp": target.hp})

func end_turn() -> bool:
	var before := log_state()
	var result := _end_turn()
	Log.event("battle", "end_turn", {"input": {}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _end_turn() -> bool:
	if not is_player_turn(): return false
	logs.append("%s结束回合。" % current_unit().name)
	_advance()
	return true

func enemy_turn() -> bool:
	var before := log_state()
	var result := _enemy_turn()
	Log.event("battle", "enemy_turn", {"input": {}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _enemy_turn() -> bool:
	if current_id() != "goblin": return false
	if enemy.captain and not charging:
		charging = true
		logs.append("守关队长正在蓄力，下次行动将释放重击。")
		last_event = {"actor": "goblin", "target": "goblin", "text": "蓄力 · 下次重击"}
	else:
		var recipient := hero
		if not ally.is_empty() and ally.hp > 0 and (hero.hp <= 0 or rng.randi_range(0, 1) == 1): recipient = ally
		_attack(enemy, recipient, enemy.die, enemy.bonus, 0, enemy.advantage)
		charging = false
	_check_outcome()
	if outcome == "ongoing": _advance()
	return true

func enemy_intent() -> String:
	if enemy.get("content_id") in ["armored", "prowler"]: return "敌方意图：" + str(Enemies.ENTRIES[enemy.content_id].threat)
	if not enemy.get("captain", false): return ""
	return ("敌方意图：重击 · 随机攻击存活成员；闪避仅保护自身" if not ally.is_empty() else "敌方意图：重击 · 命中 +4 · 1d10+4；可用闪避应对") if charging else "敌方意图：蓄力 · 本次不攻击，下次行动重击"

func _advance() -> void:
	for i in range(order.size()):
		cursor += 1
		if cursor >= order.size():
			cursor = 0
			round_number += 1
		if unit(order[cursor]).hp > 0: break
	if is_player_turn():
		action = 1
		if current_id() == "lorn": guarding = false
		else: ally_guarding = false

func _check_outcome() -> void:
	if enemy.hp <= 0: outcome = "victory"
	elif hero.hp <= 0 and (ally.is_empty() or ally.hp <= 0): outcome = "defeat"

func gm_kill_enemy() -> bool:
	var before := log_state()
	var result := _gm_kill_enemy()
	Log.event("battle", "gm_kill_enemy", {"input": {}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _gm_kill_enemy() -> bool:
	if outcome != "ongoing": return false
	enemy.hp = 0
	logs.append("GM：秒杀当前敌人。")
	last_event = {"actor": "gm", "target": enemy.id, "text": "GM 秒杀"}
	_check_outcome()
	return true

# 仅供规则效果调用；额外行动当回合有效，不跨回合积攒。
func grant_actions(amount: int) -> void:
	if is_player_turn() and amount > 0:
		action += amount

func unit(id: String) -> Dictionary:
	if id == "lorn": return hero
	if id == "goblin": return enemy
	if id == "squire": return ally
	return {}

func current_unit() -> Dictionary:
	return unit(current_id()) if outcome == "ongoing" else hero

func is_player_turn() -> bool:
	return current_id() in ["lorn", "squire"]

func can_target(id: String, target_id: String) -> bool:
	if not Abilities.ENTRIES.has(id) or not is_player_turn() or not Jobs.reason(current_unit(), id).is_empty(): return false
	var receiver := unit(target_id)
	if receiver.is_empty() or receiver.hp <= 0: return false
	if id == "potion": return target_id in ["lorn", "squire"] and receiver.hp < receiver.max_hp
	return target_id == ("goblin" if Abilities.ENTRIES[id].target == "enemy" else current_id())

static func practice_companion() -> Dictionary:
	return {"id": "squire", "name": "见习卫士", "hp": 28, "max_hp": 28, "ac": 13, "attack": 4, "dex": 1, "surge": 1, "weapon": "training_sword"}
