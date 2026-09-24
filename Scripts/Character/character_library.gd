extends RefCounted

static func resolve(_character_id: String = "lorn") -> Dictionary:
	return {"id": "lorn", "name": "洛恩", "hp": 36, "max_hp": 36,
		"ac": 14, "attack": 5, "dex": 2, "potions": 3, "fire_potions": 2, "surge": 1}
