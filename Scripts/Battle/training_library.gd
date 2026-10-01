extends RefCounted

const Characters = preload("res://Scripts/Character/character_library.gd")
const Jobs = preload("res://Scripts/Character/job_library.gd")
const Weapons = preload("res://Scripts/Character/weapon_library.gd")
const Armors = preload("res://Scripts/Character/armor_library.gd")
const Progress = preload("res://Scripts/Core/player_progress.gd")
const DEFAULT := {"job": "swordsman", "level": 1, "weapon": "training_sword", "armor": "cloth_armor", "enemy": "goblin", "party": 1, "floor": 1, "seed": 7}
const ENCOUNTERS := {"goblin": "普通哥布林", "armored": "重甲哥布林", "prowler": "迅足哥布林", "pair": "双敌：重甲＋普通", "captain": "守关队长"}

static func valid(config: Variant) -> bool:
	if not config is Dictionary or config.size() != DEFAULT.size(): return false
	for key in DEFAULT:
		if not config.has(key) or typeof(config[key]) != typeof(DEFAULT[key]): return false
	return Jobs.ENTRIES.has(config.job) and Weapons.ENTRIES.has(config.weapon) and Armors.ENTRIES.has(config.armor) and ENCOUNTERS.has(config.enemy) and config.level in range(1, 6) and config.party in range(1, 4) and config.floor in range(1, 31) and config.seed >= 0 and config.seed <= 2147483647

static func hero(config: Dictionary) -> Dictionary:
	var result := Characters.resolve()
	result.experience = [0, 10, 25, 50, 85][config.level - 1]
	Characters.add_experience(result, 0)
	result.hp = result.max_hp
	result.weapon = config.weapon
	if config.weapon != "training_sword": result.weapons.append(config.weapon)
	result.armor = config.armor
	if config.armor != "cloth_armor": result.armors.append(config.armor)
	Jobs.apply(result, config.job)
	return result

static func companion(config: Dictionary, id: String) -> Dictionary:
	if config.party < (2 if id == "squire" else 3): return {}
	var result: Dictionary = Progress.MEMBERS[id].duplicate(true)
	result.id = id
	result.level = config.level
	result.max_hp = result.base_hp + 3 * (config.level - 1)
	result.hp = result.max_hp
	result.weapon = "training_sword"
	result.surge = 1
	return result
