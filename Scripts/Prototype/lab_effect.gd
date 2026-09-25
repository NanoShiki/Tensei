extends Node2D

var effect_kind := "slash"
var direction := Vector2.RIGHT
var age := 0.0
var lifetime := 0.4
var velocity := Vector2.ZERO


func configure(kind: String, aim: Vector2) -> void:
	effect_kind = kind
	direction = aim.normalized() if aim.length_squared() > 0 else Vector2.RIGHT
	lifetime = 0.70 if kind == "arrow" else (0.55 if kind == "spell" else (0.42 if kind == "slash" else 0.3))
	if kind == "spell":
		velocity = direction * 150.0
	elif kind == "arrow":
		velocity = direction * 210.0
	queue_redraw()


func _process(delta: float) -> void:
	age += delta
	position += velocity * delta
	if age >= lifetime:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var fade := 1.0 - age / lifetime
	match effect_kind:
		"slash":
			var facing_angle := direction.angle()
			var start := facing_angle - 1.0 + age * 2.5
			draw_arc(Vector2.ZERO, 24, start, start + 1.25, 13, Color(0.93, 0.96, 0.76, fade), 3)
			draw_arc(Vector2.ZERO, 19, start, start + 1.2, 13, Color(0.45, 0.80, 0.83, fade * 0.7), 2)
		"spell":
			draw_circle(Vector2.ZERO, 11 * fade + 3, Color(0.3, 0.83, 0.9, fade * 0.35))
			draw_circle(Vector2.ZERO, 5, Color(0.5, 0.95, 0.9, fade))
			draw_circle(Vector2(-1, -1), 2, Color(0.95, 1.0, 0.85, fade))
			for i in 3:
				var trail := -direction * (i * 7 + 6)
				draw_rect(Rect2(trail - Vector2.ONE, Vector2(2, 2)), Color(0.52, 0.88, 0.82, fade * (0.7 - i * 0.18)))
		"hit":
			for i in 8:
				var ray := Vector2.RIGHT.rotated(TAU * float(i) / 8.0)
				draw_line(ray * 3, ray * (5 + age * 28), Color(1, 0.83, 0.52, fade), 2)
		"arrow":
			var angle := direction.angle()
			draw_line(Vector2.ZERO, -direction * 14, Color("d3bc8c", fade), 2)
			draw_line(Vector2.ZERO, -direction * 19, Color("463c2b", fade), 1)
			var side := Vector2.RIGHT.rotated(angle + PI * 0.5)
			draw_colored_polygon(PackedVector2Array([direction * 3, side * 3 - direction * 4, -side * 3 - direction * 4]), Color("e5e8d8", fade))
