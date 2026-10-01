extends RefCounted
const Weapons = preload("res://Scripts/Character/weapon_library.gd")
const Armors = preload("res://Scripts/Character/armor_library.gd")

static func resolve(_character_id: String = "lorn") -> Dictionary:
	return {"id": "lorn", "name": "洛恩", "hp": 36, "max_hp": 36,
		"ac": 14, "attack": 5, "dex": 2, "potions": 3, "fire_potions": 2, "surge": 1,
		"gold": 0, "scrap": 0, "weapon": "training_sword", "weapons": ["training_sword"], "armor": "cloth_armor", "armors": ["cloth_armor"], "captain_defeated": false, "experience": 0, "level": 1, "hunt_wins": 0,
		"quests": {"hunt": "available", "materials": "available", "captain": "available", "familia_patrol": "available", "depth_five": "available"}, "familia_wins": 0, "depth_goal": 0,
		"familia_id": "", "player_id": "", "party_enlisted": false, "party_hp": 0, "scout_enlisted": false, "scout_hp": 0, "growth_pending": [], "forge_pending": [], "commerce_done": [], "commerce_pending": [], "job_id": "swordsman"}

static func weapon_name(hero: Dictionary) -> String:
	return Weapons.ENTRIES.get(hero.get("weapon", "training_sword"), Weapons.ENTRIES.training_sword).name

static func weapon_bonus(hero: Dictionary) -> int:
	return Weapons.ENTRIES.get(hero.get("weapon", "training_sword"), Weapons.ENTRIES.training_sword).bonus

static func armor_name(hero: Dictionary) -> String:
	return Armors.name_for(hero)

static func level_for(experience: int) -> int:
	var result := 1
	for threshold in [10, 25, 50, 85]:
		if experience >= threshold: result += 1
	return result

static func add_experience(hero: Dictionary, amount: int) -> void:
	hero.experience += maxi(0, amount)
	hero.level = level_for(hero.experience)
	hero.max_hp = 36 + 4 * (hero.level - 1)
