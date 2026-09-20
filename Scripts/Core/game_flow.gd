extends Node
## 场景流程单例：主菜单与地图场景之间的切换入口，并保存当前进行中的角色档案。
## 角色创建流程接入后在 start_new_game 之前产出档案；存档服务接入后由存档提供同样结构的字典。
const CharacterLibrary = preload("res://Scripts/Character/character_library.gd")
const MENU_SCENE := "res://Scenes/UI/main_menu.tscn"
const CITY_SCENE := "res://Scenes/World/city_courtyard.tscn"

var active_character: Dictionary = {}


## 以指定角色开始一段旅程。第一阶段直接进入城市庭院，后续按目标区域选择地图。
func start_new_game(character_id: String) -> void:
	active_character = CharacterLibrary.resolve(character_id)
	_change_scene(CITY_SCENE)


func return_to_menu() -> void:
	active_character = {}
	_change_scene(MENU_SCENE)


func _change_scene(path: String) -> void:
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("场景切换失败：%s（%s）" % [path, error_string(error)])
