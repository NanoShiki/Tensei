extends RefCounted

const ENTRIES := {
	"strike": {"name": "剑击", "icon": "剑", "target": "enemy", "die": 8, "bonus": 3, "hint": "1 行动 · 命中 +5 · 1d8+3 伤害"},
	"power": {"name": "强攻", "icon": "斩", "target": "enemy", "die": 12, "bonus": 3, "penalty": 3, "hint": "1 行动 · 命中 +2 · 1d12+3 伤害"},
	"guard": {"name": "闪避", "icon": "盾", "target": "self", "hint": "1 行动 · 敌人攻击处于劣势，持续至你的下回合"},
	"surge": {"name": "回气", "icon": "息", "target": "self", "hint": "1 行动 · 恢复 8 生命 · 每场战斗 1 次"},
	"potion": {"name": "治疗药水", "icon": "+", "target": "self", "effect": "heal", "amount": 12, "stock": "potions", "hint": "1 行动 · 对自己恢复 12 生命 · 消耗 1 瓶"},
	"fire_potion": {"name": "灼烧药水", "icon": "火", "target": "enemy", "effect": "damage", "amount": 8, "stock": "fire_potions", "hint": "1 行动 · 对敌人造成 8 伤害 · 直接作用 · 消耗 1 瓶"},
}
