extends RefCounted

const ENTRIES := {
	"dawn": {"name": "晨行眷族", "specialty": "远征与讨伐", "qualification": "交付初次讨伐委托", "members": ["squire", "scout"]},
	"ember": {"name": "炉心眷族", "specialty": "锻造与工艺", "qualification": "打造并装备铁剑", "members": []},
}

static func qualified(hero: Dictionary, id: String) -> bool:
	if id == "dawn": return hero.quests.get("hunt") == "claimed"
	if id == "ember": return hero.weapon == "iron_sword"
	return false

static func name_for(id: String) -> String:
	return ENTRIES[id].name if ENTRIES.has(id) else "未加入眷族"
