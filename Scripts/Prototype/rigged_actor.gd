extends Node2D

signal action_peak(action_name: String)

const Parts = preload("res://Scripts/Prototype/pixel_parts.gd")
const EmbeddedArrow = preload("res://Scripts/Prototype/embedded_arrow.gd")

var actor_kind := "hero"
var equipment := "sword"
var facing := Vector2.DOWN
var moving := false
var action := ""
var action_time := 0.0
var action_duration := 0.0
var elevation := 0.0
var lift_velocity := 0.0
var hurt_time := 0.0
var health := 4

var skeleton: Skeleton2D
var hips: Bone2D
var head_bone: Bone2D
var front_arm: Bone2D
var back_arm: Bone2D
var front_leg: Bone2D
var back_leg: Bone2D
var hand: Marker2D
var body_parts: Dictionary = {}
var walk_clock := 0.0
var _peak_sent := false
var _view := "front"
var embedded_arrows: Array[Node2D] = []


func _ready() -> void:
	_build_rig()
	_set_facing_visual()
	queue_redraw()


func configure(kind: String, start_equipment: String = "sword") -> void:
	actor_kind = kind
	equipment = start_equipment
	if is_node_ready():
		_refresh_parts()


func _build_rig() -> void:
	skeleton = Skeleton2D.new()
	skeleton.name = "Skeleton2D"
	skeleton.position = Vector2(0, -10)
	add_child(skeleton)
	hips = _bone("Hips", skeleton, Vector2.ZERO)
	_add_part("cape", hips, Vector2(0, -7))
	back_leg = _bone("BackLeg", hips, Vector2(-4, 0))
	_add_part("back_leg", back_leg, Vector2(0, 6), "leg")
	front_leg = _bone("FrontLeg", hips, Vector2(4, 0))
	_add_part("front_leg", front_leg, Vector2(0, 6), "leg")
	_add_part("torso", hips, Vector2(0, -9))
	back_arm = _bone("BackArm", hips, Vector2(-6, -15))
	_add_part("back_arm", back_arm, Vector2(0, 5), "arm")
	front_arm = _bone("FrontArm", hips, Vector2(6, -15))
	_add_part("front_arm", front_arm, Vector2(0, 5), "arm")
	hand = Marker2D.new()
	hand.name = "HandSocket"
	hand.position = Vector2(0, 9)
	front_arm.add_child(hand)
	_add_part("weapon", hand, Vector2(0, -3))
	head_bone = _bone("Head", hips, Vector2(0, -20))
	_add_part("head", head_bone, Vector2(0, -2))
	_refresh_parts()


func _bone(name: String, parent: Node, at: Vector2) -> Bone2D:
	var bone := Bone2D.new()
	bone.name = name
	bone.position = at
	bone.rest = bone.transform
	bone.set_autocalculate_length_and_angle(false)
	bone.set_length(12.0)
	parent.add_child(bone)
	return bone


func _add_part(name: String, parent: Node, at: Vector2, source_name: String = "") -> void:
	var sprite := Sprite2D.new()
	sprite.name = name.capitalize()
	sprite.position = at
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(sprite)
	body_parts[name] = {"sprite": sprite, "source": source_name if source_name != "" else name}


func _refresh_parts() -> void:
	for name in body_parts:
		var part: Dictionary = body_parts[name]
		var sprite: Sprite2D = part["sprite"]
		sprite.texture = Parts.get_part(actor_kind, part["source"], _view, equipment)
	body_parts["cape"]["sprite"].visible = actor_kind == "hero"
	var front := _view != "back"
	body_parts["weapon"]["sprite"].z_index = 3 if front else -2
	body_parts["front_arm"]["sprite"].z_index = 2 if front else -1
	body_parts["back_arm"]["sprite"].z_index = -1 if front else 2
	body_parts["head"]["sprite"].z_index = 2


func set_motion(direction: Vector2) -> void:
	moving = direction.length_squared() > 0.01
	if moving:
		facing = direction.normalized()
		_set_facing_visual()


func _set_facing_visual() -> void:
	var next_view := "back" if facing.y < -0.4 else ("front" if facing.y > 0.4 else "side")
	skeleton.scale.x = -1 if facing.x < -0.2 else 1
	if next_view != _view:
		_view = next_view
		_refresh_parts()


func play_action(next_action: String) -> bool:
	if action != "":
		return false
	action = next_action
	action_time = 0.0
	action_duration = 0.50 if next_action == "slash" else (0.54 if next_action == "shoot" else 0.70)
	_peak_sent = false
	return true


func change_weapon() -> void:
	equipment = "staff" if equipment == "sword" else "sword"
	_refresh_parts()


func take_hit() -> void:
	hurt_time = 0.28
	health = maxi(0, health - 1)
	queue_redraw()


func revive() -> void:
	health = 4
	hurt_time = 0
	for arrow in embedded_arrows:
		arrow.queue_free()
	embedded_arrows.clear()
	queue_redraw()


func embed_arrow(impact_position: Vector2, flight_direction: Vector2) -> void:
	var target_bone := head_bone if impact_position.y < global_position.y - 30 else hips
	var arrow: Node2D = EmbeddedArrow.new()
	target_bone.add_child(arrow)
	arrow.global_position = impact_position
	arrow.global_rotation = flight_direction.angle()
	arrow.z_index = 4
	embedded_arrows.append(arrow)


func jump() -> void:
	if elevation <= 0.1:
		lift_velocity = 95.0


func _process(delta: float) -> void:
	if elevation > 0 or lift_velocity > 0:
		elevation = maxf(0, elevation + lift_velocity * delta)
		lift_velocity -= 300.0 * delta
		if elevation <= 0:
			lift_velocity = 0
	skeleton.position.y = -10.0 - elevation
	if moving:
		walk_clock += delta * 11.0
	else:
		walk_clock += delta * 2.5
	if hurt_time > 0:
		hurt_time = maxf(0, hurt_time - delta)
		modulate = Color("ff9a82") if hurt_time > 0 else Color.WHITE
	if action != "":
		action_time += delta
		if not _peak_sent and action_time >= action_duration * 0.42:
			_peak_sent = true
			action_peak.emit(action)
		if action_time >= action_duration:
			action = ""
	var stride := sin(walk_clock) * (0.42 if moving else 0.07)
	front_leg.rotation = stride
	back_leg.rotation = -stride
	back_arm.rotation = -stride * 0.65
	front_arm.rotation = stride * 0.55
	head_bone.rotation = sin(walk_clock * 0.5) * 0.035
	hips.position.y = sin(walk_clock * (1.0 if moving else 0.6)) * (1.0 if moving else 0.35)
	if action == "slash":
		var progress := action_time / action_duration
		front_arm.rotation = lerpf(-1.15, 1.35, smoothstep(0.08, 0.76, progress))
		hips.rotation = sin(progress * PI) * 0.11
	elif action == "skill":
		var progress := action_time / action_duration
		front_arm.rotation = -1.5 + sin(progress * PI) * 0.3
		back_arm.rotation = 1.0 - sin(progress * PI) * 0.3
		hips.rotation = 0
	elif action == "shoot":
		front_arm.rotation = -0.55
		back_arm.rotation = 0.4
		hips.rotation = 0
	else:
		hips.rotation = 0
	if hurt_time > 0:
		hips.rotation += sin(hurt_time * 37.0) * 0.12
	queue_redraw()


func _draw() -> void:
	var vertices := PackedVector2Array()
	for i in 12:
		var angle := TAU * float(i) / 12.0
		vertices.append(Vector2(cos(angle) * 11.0, sin(angle) * 3.7))
	draw_colored_polygon(vertices, Color(0.08, 0.11, 0.11, 0.35 if elevation < 1 else 0.20))
	if health < 4 and actor_kind != "hero":
		draw_rect(Rect2(-10, -38, 20, 2), Color("282e28"))
		draw_rect(Rect2(-10, -38, 5 * health, 2), Color("d48568"))
