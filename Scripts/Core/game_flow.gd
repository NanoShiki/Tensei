extends Node

const CharacterLibrary = preload("res://Scripts/Character/character_library.gd")
const MENU_SCENE := "res://Scenes/UI/main_menu.tscn"
const BATTLE_SCENE := "res://Scenes/Battle/battle.tscn"

var active_character: Dictionary = {}


func start_battle(character_id: String) -> void:
	active_character = CharacterLibrary.resolve(character_id)
	_change_scene(BATTLE_SCENE)


func return_to_menu() -> void:
	_change_scene(MENU_SCENE)


func _change_scene(path: String) -> void:
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		push_error("场景切换失败：%s（%s）" % [path, error_string(error)])
