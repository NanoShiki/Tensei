extends RefCounted

const DEFAULT_ID := "lorn"

const CATALOG := {
	"lorn": {
		"display_name": "洛恩",
		"max_hp": 120,
		"max_sp": 100,
		"max_mp": 40,
		"speed": 100,
		"row": "front",
		"card_ids": [
			"basic_strike",
			"guard",
			"swift_cut",
			"heavy_slash",
			"flame_arrow",
			"interrupt_thrust",
			"ration",
			"potion",
		],
	},
}


static func resolve(character_id: String = DEFAULT_ID) -> Dictionary:
	var id := character_id if CATALOG.has(character_id) else DEFAULT_ID
	var entry: Dictionary = CATALOG[id].duplicate(true)
	entry["character_id"] = id
	return entry
