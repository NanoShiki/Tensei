extends Node

const CharacterLibrary = preload("res://Scripts/Character/character_library.gd")
const FloorRun = preload("res://Scripts/Exploration/floor_run.gd")
const MENU_SCENE := "res://Scenes/UI/main_menu.tscn"
const BATTLE_SCENE := "res://Scenes/Battle/battle.tscn"
const ANIMATION_LAB_SCENE := "res://Scenes/Prototype/animation_lab.tscn"
var active_character: Dictionary = {}
var run: RefCounted
var show_map := false

func start_battle(character_id: String) -> void:
	run = null
	show_map = false
	active_character = CharacterLibrary.resolve(character_id)
	_change_scene(BATTLE_SCENE)

func start_exploration() -> void:
	run = FloorRun.new()
	run.setup(randi())
	active_character = run.character.duplicate(true)
	show_map = true
	_change_scene(BATTLE_SCENE)

func return_to_menu() -> void:
	_change_scene(MENU_SCENE)

func start_animation_lab() -> void:
	_change_scene(ANIMATION_LAB_SCENE)

func _change_scene(path: String) -> void:
	var error := get_tree().change_scene_to_file(path)
	if error != OK: push_error("场景切换失败：%s（%s）" % [path, error_string(error)])
