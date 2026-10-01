extends RefCounted
const Armors = preload("res://Scripts/Character/armor_library.gd")

const ENTRIES := {
	"swordsman": {"name": "剑士", "ac": 14, "attack": 5, "dex": 2, "skill": "power", "level": 1, "role": "稳健攻防 · 强攻以命中换伤害"},
	"mage": {"name": "法师", "ac": 12, "attack": 5, "dex": 1, "skill": "arcane_bolt", "level": 2, "role": "奥术输出 · 飞弹不受铁剑加成"},
	"archer": {"name": "弓箭手", "ac": 13, "attack": 6, "dex": 3, "skill": "aimed_shot", "level": 2, "role": "精准命中 · 瞄准命中额外 +2"},
	"rogue": {"name": "盗贼", "ac": 13, "attack": 5, "dex": 4, "skill": "ambush", "level": 2, "role": "敏捷先攻 · 伏击提供较高伤害"},
}

static func resolve(hero: Dictionary) -> Dictionary:
	var job: Dictionary = ENTRIES.get(hero.get("job_id", "swordsman"), ENTRIES.swordsman).duplicate(true)
	job.ac += Armors.bonus(hero)
	return job

static func apply(hero: Dictionary, id: String) -> void:
	hero.job_id = id
	for key in ["ac", "attack", "dex"]: hero[key] = resolve(hero)[key]

static func skills(hero: Dictionary) -> Array:
	return ["strike", resolve(hero).skill, "guard", "surge"]

static func reason(hero: Dictionary, id: String) -> String:
	if id in ["strike", "guard", "surge", "potion", "fire_potion"]: return ""
	var job := resolve(hero)
	if id != job.skill: return "当前职业未装备此技能。"
	if hero.get("level", 1) < job.level: return "达到等级 %d 后开放。" % job.level
	return ""
