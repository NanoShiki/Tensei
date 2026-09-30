extends RefCounted

const ENTRIES := {
	"goblin": {"name": "哥布林", "hp": 22, "ac": 12, "attack": 3, "dex": 1, "die": 6, "bonus": 1, "advantage": false, "tint": "ffffff", "threat": "普通攻击 · 命中 +3 · 1d6+1"},
	"armored": {"name": "重甲哥布林", "hp": 26, "ac": 15, "attack": 2, "dex": 0, "die": 6, "bonus": 1, "advantage": false, "tint": "a4b0c0", "threat": "高防御、慢先攻 · 灼烧药水直接造成伤害"},
	"prowler": {"name": "迅足哥布林", "hp": 18, "ac": 11, "attack": 4, "dex": 5, "die": 6, "bonus": 1, "advantage": true, "tint": "d7bd8c", "threat": "迅击掷两次取高；自身闪避可抵消此优势"},
	"captain": {"name": "守关队长", "hp": 44, "ac": 13, "attack": 4, "dex": 1, "die": 10, "bonus": 4, "advantage": false, "tint": "ffffff", "threat": "蓄力一回合后重击 · 1d10+4"},
}

static func resolve(id: String, floor_number: int = 1) -> Dictionary:
	var kind: String = id if ENTRIES.has(id) else "goblin"
	var entry: Dictionary = ENTRIES[kind]
	var hp: int = entry.hp + (0 if kind == "captain" else mini(maxi(0, floor_number - 1), 20))
	return {"id": "goblin", "content_id": kind, "name": entry.name, "hp": hp, "max_hp": hp,
		"ac": entry.ac, "attack": entry.attack, "dex": entry.dex, "die": entry.die, "bonus": entry.bonus,
		"advantage": entry.advantage, "captain": kind == "captain", "tint": entry.tint}

static func preview(id: String, floor_number: int) -> String:
	var enemy := resolve(id, floor_number)
	return "生命 %d · 防御 AC %d · 命中 +%d · 敏捷 +%d\n%s" % [enemy.max_hp, enemy.ac, enemy.attack, enemy.dex, ENTRIES[enemy.content_id].threat]
