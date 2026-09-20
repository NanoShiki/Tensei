extends Node2D
## 地图场景的通用呈现与装载逻辑：手绘地面图负责视觉，Obstacles 下的碰撞体负责可行走边界，
## Markers 提供出生点与后续出口。城市、安全楼层与地下城复用同一结构，差异体现在场景资源本身。
const PlayerScene = preload("res://Scenes/Character/player_character.tscn")
const CharacterLibrary = preload("res://Scripts/Character/character_library.gd")

@onready var ground: Sprite2D = $Ground
@onready var entities: Node2D = $Entities
@onready var player_spawn: Marker2D = $Markers/PlayerSpawn

var player: CharacterBody2D
var camera: Camera2D


func _ready() -> void:
	player = PlayerScene.instantiate()
	player.position = player_spawn.position
	entities.add_child(player)
	player.apply_profile(_resolve_profile())
	_setup_camera()


## 地图的世界矩形由地面图自身决定，同时作为相机边界。
func map_rect() -> Rect2:
	var texture_size := ground.texture.get_size() * ground.scale
	var origin := ground.position
	if ground.centered:
		origin -= texture_size * 0.5
	return Rect2(origin, texture_size)


func _resolve_profile() -> Dictionary:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null and not flow.active_character.is_empty():
		return flow.active_character
	# 单独运行本场景时直接使用预设角色，便于按 F6 检查地图。
	return CharacterLibrary.resolve()


func _setup_camera() -> void:
	var rect := map_rect()
	camera = Camera2D.new()
	camera.limit_left = int(rect.position.x)
	camera.limit_top = int(rect.position.y)
	camera.limit_right = int(rect.end.x)
	camera.limit_bottom = int(rect.end.y)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	player.add_child(camera)
	camera.make_current()


func _unhandled_key_input(event: InputEvent) -> void:
	# 暂停菜单尚未实现，Esc 暂时直接返回主菜单。
	if event.is_action_pressed("ui_cancel"):
		var flow := get_node_or_null("/root/GameFlow")
		if flow != null:
			flow.return_to_menu()
			get_viewport().set_input_as_handled()
