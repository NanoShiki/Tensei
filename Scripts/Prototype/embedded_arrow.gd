extends Node2D

# 命中后作为 Bone2D 子节点保存局部坐标和角度。
func _draw() -> void:
	draw_line(Vector2(-16, 0), Vector2(-1, 0), Color("3e362d"), 3)
	draw_line(Vector2(-16, 0), Vector2(-1, 0), Color("b79865"), 1)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(-5, -3), Vector2(-5, 3)]), Color("d9dbcf"))
	draw_line(Vector2(-15, 0), Vector2(-19, -3), Color("b8c9b0"), 1)
	draw_line(Vector2(-15, 0), Vector2(-19, 3), Color("b8c9b0"), 1)
