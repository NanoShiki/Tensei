extends RefCounted

static func resolve(_character_id: String = "lorn") -> Dictionary:
	return {"id": "lorn", "name": "洛恩", "hp": 36, "max_hp": 36,
		"ac": 14, "attack": 5, "dex": 2, "potions": 3, "fire_potions": 2, "surge": 1,
		"gold": 0, "scrap": 0, "weapon": "training_sword", "captain_defeated": false, "experience": 0, "level": 1, "hunt_wins": 0,
		"quests": {"hunt": "available", "materials": "available", "captain": "available", "familia_patrol": "available", "depth_five": "available"}, "familia_wins": 0, "depth_goal": 0,
		"familia_id": "", "player_id": "", "party_enlisted": false, "party_hp": 0, "scout_enlisted": false, "scout_hp": 0, "growth_pending": [], "forge_pending": [], "job_id": "swordsman"}

static func weapon_name(hero: Dictionary) -> String:
	return "铁剑" if hero.get("weapon", "training_sword") == "iron_sword" else "练习木剑"

static func weapon_bonus(hero: Dictionary) -> int:
	return 2 if hero.get("weapon", "training_sword") == "iron_sword" else 0

static func level_for(experience: int) -> int:
	var result := 1
	for threshold in [10, 25, 50, 85]:
		if experience >= threshold: result += 1
	return result

static func add_experience(hero: Dictionary, amount: int) -> void:
	hero.experience += maxi(0, amount)
	hero.level = level_for(hero.experience)
	hero.max_hp = 36 + 4 * (hero.level - 1)
