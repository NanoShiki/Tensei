extends RefCounted
const Weapons = preload("res://Scripts/Character/weapon_library.gd")

const ENTRIES := {
	"dawn": {"name": "晨行眷族", "specialty": "远征与讨伐", "qualification": "交付初次讨伐委托", "members": ["squire", "scout"]},
	"ember": {"name": "炉心眷族", "specialty": "锻造与工艺", "qualification": "打造并持有铁剑", "members": []},
	"harbor": {"name": "集市眷族", "specialty": "订单与补给", "qualification": "完成铁片供货订单", "members": []},
}

static func qualified(hero: Dictionary, id: String) -> bool:
	if id == "dawn": return hero.quests.get("hunt") == "claimed"
	if id == "ember": return Weapons.owned(hero).has("iron_sword")
	if id == "harbor": return hero.get("commerce_done", []).has("supply_order")
	return false

static func name_for(id: String) -> String:
	return ENTRIES[id].name if ENTRIES.has(id) else "未加入眷族"
