extends RefCounted

const Log = preload("res://Scripts/Core/game_log.gd")
const Abilities = preload("res://Scripts/Battle/ability_library.gd")
const CharacterLibrary = preload("res://Scripts/Character/character_library.gd")
var battle_id := ""
var hero: Dictionary
var enemy: Dictionary
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

func setup(character: Dictionary, floor_number: int = 1, seed_value: int = -1, captain: bool = false) -> void:
	battle_id = Crypto.new().generate_random_bytes(8).hex_encode()
	hero = character.duplicate(true)
	hero["surge"] = 1
	enemy = {"id": "goblin", "name": "哥布林", "max_hp": 22 + mini(floor_number - 1, 20),
		"ac": 12, "attack": 3, "dex": 1}
	enemy["captain"] = captain
	charging = false
	if captain:
		enemy.merge({"name": "守关队长", "max_hp": 44, "ac": 13, "attack": 4, "dex": 1}, true)
	enemy["hp"] = enemy.max_hp
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
	if hero.hp <= 0:
		outcome = "defeat"
	Log.event("battle", "start", {"seed": str(rng.seed), "order": order, "state": log_state()})

func log_state() -> Dictionary:
	return {"battle_id": battle_id, "hero": hero.duplicate(true), "enemy": enemy.duplicate(true), "round": round_number,
		"actor": current_id(), "actions": action, "guarding": guarding, "outcome": outcome, "charging": charging,
		"last_event": last_event.duplicate(true)}

func current_id() -> String:
	return order[cursor] if outcome == "ongoing" else ""

func reason(id: String) -> String:
	if outcome != "ongoing": return "战斗已结束"
	if current_id() != "lorn": return "等待敌人行动"
	if not Abilities.ENTRIES.has(id): return "未知技能"
	if action <= 0: return "本回合行动次数已用尽"
	var entry: Dictionary = Abilities.ENTRIES[id]
	if entry.has("stock") and int(hero.get(entry.stock, 0)) <= 0: return "药水已用尽"
	if id == "surge" and hero.surge <= 0: return "本场回气已用尽"
	if id in ["potion", "surge"] and hero.hp == hero.max_hp: return "生命已满"
	return ""

func hit_chance(id: String) -> int:
	var modifier := int(hero.attack) - int(Abilities.ENTRIES[id].get("penalty", 0))
	return clampi(21 + modifier - int(enemy.ac), 1, 19) * 5

func use_ability(id: String, target: String) -> bool:
	var before := log_state()
	var result := _use_ability(id, target)
	Log.event("battle", "use_ability", {"input": {"ability": id, "target": target}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _use_ability(id: String, target: String) -> bool:
	if not reason(id).is_empty(): return false
	var entry: Dictionary = Abilities.ENTRIES[id]
	if target != ("goblin" if entry.target == "enemy" else "lorn"): return false
	action -= 1
	if entry.has("stock"):
		hero[entry.stock] -= 1
		var receiver: Dictionary = enemy if entry.target == "enemy" else hero
		var amount: int = entry.amount
		if entry.effect == "heal":
			amount = mini(amount, int(receiver.max_hp) - int(receiver.hp))
			receiver.hp += amount
		else:
			receiver.hp = maxi(0, int(receiver.hp) - amount)
		var text := ("+%d" if entry.effect == "heal" else "−%d") % amount
		logs.append("%s → %s：%s 生命。" % [entry.name, receiver.name, text])
		last_event = {"actor": "lorn", "target": receiver.id, "text": text}
	elif entry.target == "enemy":
		_attack(hero, enemy, int(entry.die), int(entry.bonus) + CharacterLibrary.weapon_bonus(hero), int(entry.get("penalty", 0)))
	elif id == "guard":
		guarding = true
		logs.append("洛恩采取闪避，持续至下次自身回合开始。")
		last_event = {"actor": "lorn", "target": "lorn", "text": "闪避"}
	else:
		var restored := mini(8, int(hero.max_hp) - int(hero.hp))
		hero.hp += restored
		hero.surge -= 1
		logs.append("洛恩使用%s，恢复 %d 生命。" % [entry.name, restored])
		last_event = {"actor": "lorn", "target": "lorn", "text": "+%d" % restored}
	_check_outcome()
	return true

func _attack(attacker: Dictionary, target: Dictionary, die: int, damage_bonus: int, penalty: int = 0) -> void:
	var roll := rng.randi_range(1, 20)
	if target.id == "lorn" and guarding:
		roll = mini(roll, rng.randi_range(1, 20))
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
	Log.event("battle", "attack", {"battle_id": battle_id, "actor": attacker.id, "target": target.id, "roll": roll, "modifier": modifier, "ac": target.ac, "hit": hit, "damage": damage, "remaining_hp": target.hp})

func end_turn() -> bool:
	var before := log_state()
	var result := _end_turn()
	Log.event("battle", "end_turn", {"input": {}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _end_turn() -> bool:
	if current_id() != "lorn": return false
	logs.append("洛恩结束回合。")
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
		_attack(enemy, hero, 10 if enemy.captain else 6, 4 if enemy.captain else 1)
		charging = false
	_check_outcome()
	if outcome == "ongoing": _advance()
	return true

func enemy_intent() -> String:
	if not enemy.get("captain", false): return ""
	return "敌方意图：重击 · 命中 +4 · 1d10+4；可用闪避应对" if charging else "敌方意图：蓄力 · 本次不攻击，下次行动重击"

func _advance() -> void:
	cursor += 1
	if cursor >= order.size():
		cursor = 0
		round_number += 1
	if current_id() == "lorn":
		action = 1
		guarding = false

func _check_outcome() -> void:
	if enemy.hp <= 0: outcome = "victory"
	elif hero.hp <= 0: outcome = "defeat"

func gm_kill_enemy() -> bool:
	var before := log_state()
	var result := _gm_kill_enemy()
	Log.event("battle", "gm_kill_enemy", {"input": {}, "success": result, "before": before, "after": log_state()}, "INFO" if result else "WARN")
	return result

func _gm_kill_enemy() -> bool:
	if outcome != "ongoing" or hero.hp <= 0: return false
	enemy.hp = 0
	logs.append("GM：秒杀当前敌人。")
	last_event = {"actor": "gm", "target": enemy.id, "text": "GM 秒杀"}
	_check_outcome()
	return true

# 仅供规则效果调用；额外行动当回合有效，不跨回合积攒。
func grant_actions(amount: int) -> void:
	if current_id() == "lorn" and amount > 0:
		action += amount
