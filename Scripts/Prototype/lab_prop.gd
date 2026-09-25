extends Node2D

var kind := "tree"
var variant := 0


func configure(prop_kind: String, appearance: int = 0) -> void:
	kind = prop_kind
	variant = appearance
	queue_redraw()


func _draw() -> void:
	match kind:
		"tree":
			_draw_tree()
		"rock":
			draw_rect(Rect2(-12, -2, 25, 5), Color(0.1, 0.16, 0.15, 0.28))
			draw_colored_polygon(PackedVector2Array([Vector2(-10, -3), Vector2(-7, -11), Vector2(1, -15), Vector2(10, -9), Vector2(12, -3)]), Color("353e3b"))
			draw_colored_polygon(PackedVector2Array([Vector2(-7, -11), Vector2(1, -15), Vector2(8, -10), Vector2(1, -7)]), Color("818777"))
			draw_rect(Rect2(-6, -7, 7, 2), Color("a0a187"))
		"torch":
			draw_rect(Rect2(-4, -1, 10, 3), Color(0.1, 0.13, 0.12, 0.3))
			draw_rect(Rect2(-2, -20, 5, 20), Color("4c3a31"))
			draw_rect(Rect2(-4, -22, 9, 4), Color("a86f3d"))
			draw_rect(Rect2(-2, -28, 5, 8), Color("e9a950"))
			draw_rect(Rect2(-1, -27, 3, 5), Color("ffe7a4"))
		"rune":
			draw_arc(Vector2.ZERO, 17, 0, TAU, 24, Color("a0c5b2", 0.55), 1)
			for i in 8:
				var point := Vector2.RIGHT.rotated(TAU * float(i) / 8.0) * 17.0
				draw_rect(Rect2(point - Vector2.ONE, Vector2(2, 2)), Color("e4d6a5"))


func _draw_tree() -> void:
	var shift := (variant % 3) * 2
	draw_rect(Rect2(-18, -4, 35, 6), Color(0.08, 0.13, 0.10, 0.27))
	draw_rect(Rect2(-4, -33, 8, 34), Color("383a31"))
	draw_rect(Rect2(-2, -33, 3, 30), Color("80755b"))
	draw_colored_polygon(PackedVector2Array([Vector2(-20, -31), Vector2(-20, -52), Vector2(-10, -65), Vector2(8, -69), Vector2(22, -55), Vector2(20, -34), Vector2(10, -25), Vector2(-11, -27)]), Color("263d33"))
	draw_rect(Rect2(-18, -48, 25, 12), Color("426046"))
	draw_rect(Rect2(-11, -61, 20, 12), Color("567353"))
	draw_rect(Rect2(6 + shift, -55, 12, 17), Color("395541"))
	draw_rect(Rect2(-17, -34, 12, 5), Color("2e4836"))
	draw_rect(Rect2(-6, -62, 8, 4), Color("769069"))
