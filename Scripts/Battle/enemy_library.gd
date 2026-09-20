extends RefCounted

const CATALOG := {
	"cave_wolf": {
		"display_name": "洞穴狼",
		"max_hp": 60,
		"speed": 120,
		"row": "front",
		"card_ids": ["cave_wolf_strike"],
	},
	"stone_colossus": {
		"display_name": "石拳巨像",
		"max_hp": 110,
		"speed": 70,
		"row": "front",
		"card_ids": ["stone_colossus_strike"],
		"charge_card_id": "stone_colossus_earth_shatter",
	},
}


static func resolve(enemy_id: String) -> Dictionary:
	if not CATALOG.has(enemy_id):
		return {}
	var entry: Dictionary = CATALOG[enemy_id].duplicate(true)
	entry["enemy_id"] = enemy_id
	return entry
