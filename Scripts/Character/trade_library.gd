extends RefCounted

const ENTRIES := {
	"potion": {"name": "治疗药水", "resource": "potions", "price": 3, "buy": true},
	"fire_potion": {"name": "灼烧药水", "resource": "fire_potions", "price": 4, "buy": true},
	"sell_scrap": {"name": "铁片", "resource": "scrap", "price": 1, "buy": false},
}

static func reason(hero: Dictionary, id: String, quantity: int) -> String:
	if not ENTRIES.has(id): return "未知交易。"
	if quantity < 1 or quantity > 99: return "每笔数量需为 1–99。"
	var trade: Dictionary = ENTRIES[id]
	if trade.buy and hero.gold < quantity * trade.price: return "金币不足。"
	if not trade.buy and hero[trade.resource] < quantity: return "持有铁片不足。"
	return ""
