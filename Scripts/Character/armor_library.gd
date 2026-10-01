extends RefCounted

const ENTRIES := {
	"cloth_armor": {"name": "布衣", "bonus": 0},
	"iron_armor": {"name": "铁甲", "bonus": 1, "gold": 6, "scrap": 3},
}

static func bonus(hero: Dictionary) -> int:
	return ENTRIES.get(hero.get("armor", "cloth_armor"), ENTRIES.cloth_armor).bonus

static func name_for(hero: Dictionary) -> String:
	return ENTRIES.get(hero.get("armor", "cloth_armor"), ENTRIES.cloth_armor).name

static func reason(hero: Dictionary, id: String) -> String:
	if id != "iron_armor": return "未知护甲配方。"
	if hero.armors.has(id): return "已持有铁甲，每个角色只需制作一次。"
	if hero.gold < ENTRIES[id].gold or hero.scrap < ENTRIES[id].scrap: return "需要 6 金币、3 铁片。"
	return ""
