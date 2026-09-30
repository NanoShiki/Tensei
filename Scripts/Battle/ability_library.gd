extends RefCounted

const ENTRIES := {
	"strike": {"name": "剑击", "icon": "剑", "target": "enemy", "die": 8, "bonus": 3, "hint": "1 行动 · 命中 +5 · 1d8+3 伤害"},
	"power": {"name": "强攻", "icon": "斩", "target": "enemy", "die": 12, "bonus": 3, "penalty": 3, "hint": "1 行动 · 命中 +2 · 1d12+3 伤害"},
	"arcane_bolt": {"name": "奥术飞弹", "icon": "术", "asset": "fire_potion", "target": "enemy", "die": 8, "bonus": 5, "weapon_bonus": false, "hint": "1 行动 · 1d8+5 伤害 · 法师等级 2 开放"},
	"aimed_shot": {"name": "瞄准射击", "icon": "准", "asset": "strike", "target": "enemy", "die": 8, "bonus": 3, "penalty": -2, "hint": "1 行动 · 命中额外 +2 · 1d8+3 · 弓箭手等级 2 开放"},
	"ambush": {"name": "伏击", "icon": "袭", "asset": "power", "target": "enemy", "die": 10, "bonus": 4, "hint": "1 行动 · 1d10+4 伤害 · 盗贼等级 2 开放"},
	"guard": {"name": "闪避", "icon": "盾", "target": "self", "hint": "1 行动 · 敌人攻击处于劣势，持续至你的下回合"},
	"surge": {"name": "回气", "icon": "息", "target": "self", "hint": "1 行动 · 恢复 8 生命 · 每场战斗 1 次"},
	"potion": {"name": "治疗药水", "icon": "+", "target": "ally", "effect": "heal", "amount": 12, "stock": "potions", "hint": "1 行动 · 对存活的受伤队友恢复 12 生命 · 消耗 1 瓶"},
	"fire_potion": {"name": "灼烧药水", "icon": "火", "target": "enemy", "effect": "damage", "amount": 8, "stock": "fire_potions", "hint": "1 行动 · 对敌人造成 8 伤害 · 直接作用 · 消耗 1 瓶"},
}
