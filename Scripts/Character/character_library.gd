extends RefCounted
## 角色运行时档案目录。角色创建与存档接入后由对应服务提供同样结构的字典，本目录保留预设角色。
## 动作图规格见 Docs/人物/俯视角色动作资产规范.md：1024×1024，4 行×4 列，单格 256×256，地面锚点 (128,224)。
const WALK_SHEET := "res://Assets/Characters/Lorn/07-俯视行走.png"
const RUN_SHEET := "res://Assets/Characters/Lorn/08-俯视跑步.png"
const DEFAULT_ID := "lorn"

const CATALOG := {
	DEFAULT_ID: {
		"display_name": "洛恩",
		"illustration_id": "lorn.apprentice",
		"visual_scale": 0.9,
		"body_radius": 30.0,
		"walk_speed": 150.0,
		"run_speed": 300.0,
		"acceleration": 1800.0,
		"cell_size": Vector2(256, 256),
		"ground_anchor": Vector2(128, 224),
		# 待机素材（06-四向待机）尚未制作，暂取行走序列首帧占位。
		"actions": {
			"idle": {"sheet": WALK_SHEET, "columns": 1, "fps": 0.0},
			"walk": {"sheet": WALK_SHEET, "columns": 4, "fps": 6.0},
			"run": {"sheet": RUN_SHEET, "columns": 4, "fps": 8.0},
		},
	},
}


static func resolve(character_id: String = DEFAULT_ID) -> Dictionary:
	var id := character_id if CATALOG.has(character_id) else DEFAULT_ID
	var profile: Dictionary = CATALOG[id].duplicate(true)
	profile["character_id"] = id
	return profile
