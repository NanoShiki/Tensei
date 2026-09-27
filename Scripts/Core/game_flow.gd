extends Node

const CharacterLibrary = preload("res://Scripts/Character/character_library.gd")
const FloorRun = preload("res://Scripts/Exploration/floor_run.gd")
const MENU_SCENE := "res://Scenes/UI/main_menu.tscn"
const BATTLE_SCENE := "res://Scenes/Battle/battle.tscn"
var active_character: Dictionary = {}
var run: RefCounted
var show_map := false
var saves := preload("res://Scripts/Core/save_library.gd").new()
var profile: Dictionary = {}
var active_record_id := ""
var _pending_scene := ""

func continue_exploration() -> bool:
	var saved: Dictionary = saves.inspect()
	if saved.is_empty(): return false
	return load_exploration(saved.metadata.profile.id, saved.metadata.record_id)

func load_exploration(profile_id: String, record_id: String) -> bool:
	var saved: Dictionary = saves.load_record(profile_id, record_id)
	if saved.is_empty(): return false
	run = saved.run
	profile = saved.metadata.profile.duplicate(true)
	active_record_id = record_id
	active_character = run.character.duplicate(true)
	show_map = true
	_change_scene(BATTLE_SCENE)
	return true

func _ready() -> void:
	var gm = preload("res://Scripts/Debug/gm_panel.gd").new()
	add_child(gm)

func start_battle(character_id: String) -> void:
	run = null
	show_map = false
	active_character = CharacterLibrary.resolve(character_id)
	_change_scene(BATTLE_SCENE)

func start_exploration(profile_name: String = "洛恩") -> void:
	run = FloorRun.new()
	run.setup(randi())
	profile = saves.new_profile(profile_name)
	active_record_id = ""
	active_character = run.character.duplicate(true)
	show_map = true
	_change_scene(BATTLE_SCENE)

func return_to_menu() -> void:
	_change_scene(MENU_SCENE)

func _change_scene(path: String) -> void:
	if not _pending_scene.is_empty(): return
	_pending_scene = path
	_commit_scene.call_deferred()

func _commit_scene() -> void:
	# 按钮可能属于 Window 视口，等当前输入事件分发结束后再移除旧场景。
	var path := _pending_scene
	_pending_scene = ""
	var error := get_tree().change_scene_to_file(path)
	if error != OK: push_error("场景切换失败：%s（%s）" % [path, error_string(error)])
