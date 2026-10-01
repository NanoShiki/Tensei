extends RefCounted

const ENTRIES := {
	"supply_order": {"name": "铁片供货订单", "gold": 5, "scrap": -2, "potions": 0, "member": false, "description": "交付2铁片，领取5金币；每角色一次，集市贡献+1。"},
	"member_bundle": {"name": "会员补给礼包", "gold": -6, "scrap": 0, "potions": 3, "member": true, "description": "集市会员：6金币购3瓶治疗（普通9金币）；每角色一次，集市贡献+1。"},
}

static func reason(hero: Dictionary, id: String, level: int = 0) -> String:
	if not ENTRIES.has(id): return "未知订单。"
	if hero.commerce_done.has(id): return "本角色已完成此订单。"
	if not hero.commerce_pending.is_empty(): return "请先同步待提交商贸贡献。"
	var order: Dictionary = ENTRIES[id]
	if order.member:
		if hero.familia_id != "harbor": return "请先加入集市眷族。"
		if level < 1: return "无法核验集市会员资格，请恢复共享备份。"
		if not hero.commerce_done.has("supply_order"): return "请先完成供货订单。"
	if hero.gold + order.gold < 0 or hero.scrap + order.scrap < 0: return "金币或铁片不足，请按订单准备。"
	return ""
