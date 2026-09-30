extends RefCounted

const Characters = preload("res://Scripts/Character/character_library.gd")
const DEFINITIONS := {
	"hunt": {"name": "初次讨伐", "goal": "接取后赢得 3 场战斗", "gold": 6, "xp": 10},
	"materials": {"name": "工坊供货", "goal": "交付 3 铁片（交付时消耗）", "gold": 8, "xp": 15},
	"captain": {"name": "守关队长讨伐", "goal": "击败第三层守关队长并回城", "gold": 12, "xp": 25},
	"familia_patrol": {"name": "晨行成员巡守", "goal": "晨行眷族等级 2 后接取，编队赢得 5 场战斗", "gold": 10, "xp": 20}
}

static func ready(hero: Dictionary, id: String) -> bool:
	if not DEFINITIONS.has(id) or hero.quests.get(id) != "active": return false
	match id:
		"hunt": return hero.hunt_wins >= 3
		"materials": return hero.scrap >= 3
		"captain": return hero.captain_defeated
		"familia_patrol": return hero.familia_id == "dawn" and hero.familia_wins >= 5
	return false

static func progress(hero: Dictionary, id: String) -> String:
	match id:
		"hunt": return "%d / 3 场" % hero.hunt_wins
		"materials": return "%d / 3 铁片" % hero.scrap
		"captain": return "已击败" if hero.captain_defeated else "尚未击败"
		"familia_patrol": return "%d / 5 场编队胜利" % hero.familia_wins
	return ""

static func reason(hero: Dictionary, id: String, action: String, guild_level: int = 0) -> String:
	if not DEFINITIONS.has(id): return "未知委托。"
	if action == "accept":
		if id == "familia_patrol" and (hero.familia_id != "dawn" or guild_level < 2): return "加入晨行眷族并达到眷族等级 2 后开放。"
		return "" if hero.quests.get(id) == "available" else "委托已接取或交付。"
	if action != "claim": return "未知操作。"
	return "" if ready(hero, id) else "委托未接取、未完成或已交付。"

static func apply(hero: Dictionary, id: String, action: String, guild_level: int = 0) -> bool:
	if not reason(hero, id, action, guild_level).is_empty(): return false
	if not DEFINITIONS.has(id): return false
	if action == "accept":
		if hero.quests.get(id) != "available": return false
		hero.quests[id] = "active"
		return true
	if action != "claim" or not ready(hero, id): return false
	if id == "materials": hero.scrap -= 3
	hero.quests[id] = "claimed"
	hero.gold += DEFINITIONS[id].gold
	Characters.add_experience(hero, DEFINITIONS[id].xp)
	return true
