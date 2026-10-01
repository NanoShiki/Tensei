extends RefCounted

# 当前三把剑复用演示动作，正式武器类型和动作后续扩展。
const ENTRIES := {
	"training_sword": {"name": "练习木剑", "bonus": 0},
	"iron_sword": {"name": "铁剑", "bonus": 2, "gold": 6, "scrap": 3, "member": false},
	"tempered_sword": {"name": "淬火铁剑", "bonus": 3, "gold": 9, "scrap": 4, "member": true},
}

static func owned(hero: Dictionary) -> Array:
	return hero.get("weapons", ["training_sword", hero.get("weapon", "training_sword")])

static func reason(hero: Dictionary, id: String, ember_level: int = 0) -> String:
	if id not in ["iron_sword", "tempered_sword"]: return "未知配方。"
	if owned(hero).has(id): return "已持有此武器，每个角色只需制作一次。"
	var recipe: Dictionary = ENTRIES[id]
	if recipe.member:
		if hero.familia_id != "ember": return "炉心会员配方：请先加入炉心眷族。"
		if ember_level < 1: return "无法核验炉心会员资格，请恢复共享备份。"
		if not owned(hero).has("iron_sword"): return "请先打造铁剑。"
	if hero.gold < recipe.gold or hero.scrap < recipe.scrap: return "需要 %d 金币、%d 铁片。" % [recipe.gold, recipe.scrap]
	return ""
