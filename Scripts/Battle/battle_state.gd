extends RefCounted

const Abilities = preload("res://Scripts/Battle/ability_library.gd")
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

func setup(character: Dictionary, floor_number: int = 1, seed_value: int = -1) -> void:
	hero = character.duplicate(true)
	hero["surge"] = 1
	enemy = {"id": "goblin", "name": "哥布林", "max_hp": 22 + mini(floor_number - 1, 20),
		"ac": 12, "attack": 3, "dex": 1}
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
	logs.append("先攻：洛恩 %d / 哥布林 %d。" % [h, e])
	if hero.hp <= 0:
		outcome = "defeat"

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
		_attack(hero, enemy, int(entry.die), int(entry.bonus), int(entry.get("penalty", 0)))
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

func end_turn() -> bool:
	if current_id() != "lorn": return false
	logs.append("洛恩结束回合。")
	_advance()
	return true

func enemy_turn() -> bool:
	if current_id() != "goblin": return false
	_attack(enemy, hero, 6, 1)
	_check_outcome()
	if outcome == "ongoing": _advance()
	return true

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

# 仅供规则效果调用；额外行动当回合有效，不跨回合积攒。
func grant_actions(amount: int) -> void:
	if current_id() == "lorn" and amount > 0:
		action += amount
