extends CharacterBody2D
## 俯视平面移动的玩家角色。输入解析、移动与表现分层，后续接入鼠标瞄准、技能与联机时按层扩展。
@onready var visual: Sprite2D = $Visual
@onready var body_shape: CollisionShape2D = $BodyShape

var walk_speed := 150.0
var run_speed := 300.0
var acceleration := 1800.0
var facing := "south"
var profile: Dictionary = {}


## 装载角色档案：移动参数、碰撞体积与动作资源都来自同一份数据。
func apply_profile(character_profile: Dictionary) -> void:
	profile = character_profile
	walk_speed = float(profile.get("walk_speed", walk_speed))
	run_speed = float(profile.get("run_speed", run_speed))
	acceleration = float(profile.get("acceleration", acceleration))
	var shape := body_shape.shape as CircleShape2D
	if shape != null:
		shape.radius = float(profile.get("body_radius", shape.radius))
	visual.configure(profile)
	visual.set_state("idle", facing)


func _physics_process(delta: float) -> void:
	var direction := read_input_direction()
	var running := Input.is_action_pressed("move_run")
	var speed := run_speed if running else walk_speed
	velocity = velocity.move_toward(direction * speed, acceleration * delta)
	move_and_slide()
	if direction != Vector2.ZERO:
		facing = facing_from_direction(direction)
		visual.set_state("run" if running else "walk", facing)
	else:
		visual.set_state("idle", facing)


func read_input_direction() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


## 四向表现取主导轴；斜向移动保持上一次确定的方向轴，避免抖动。
func facing_from_direction(direction: Vector2) -> String:
	if absf(direction.x) > absf(direction.y):
		return "east" if direction.x > 0.0 else "west"
	return "south" if direction.y > 0.0 else "north"
