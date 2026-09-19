extends RefCounted
## 主菜单只解析可信插画标识；存档系统接入后提供最新角色的展示信息。
const DEFAULT_ID := "lorn.apprentice"
const DEFAULT_PATH := "res://Docs/人物/洛恩/素材/03-初始原画.png"
const CATALOG := {
	DEFAULT_ID: {"path": DEFAULT_PATH, "name": "洛恩", "stage": "见习剑士"},
}

static func resolve(latest_character: Dictionary = {}) -> Dictionary:
	var illustration_id: String = str(latest_character.get("illustration_id", DEFAULT_ID))
	var entry: Dictionary = CATALOG.get(illustration_id, CATALOG[DEFAULT_ID]).duplicate()
	entry["texture"] = load(entry["path"]) as Texture2D
	return entry
