extends Node2D

const WORLD_SIZE := Vector2i(640, 400)


func _hash(x: int, y: int) -> int:
	var value := (x * 374761393 + y * 668265263 + 1987) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return value ^ (value >> 16)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, WORLD_SIZE), Color("3d4939"))
	for ty in 25:
		for tx in 40:
			var h := _hash(tx, ty)
			var x := tx * 16
			var y := ty * 16
			var clearing := Vector2((x - 320.0) / 235.0, (y - 200.0) / 155.0).length() < 1.0
			var base := Color("5c6849") if clearing else Color("485540")
			if h % 8 == 0:
				base = base.lightened(0.07)
			elif h % 6 == 0:
				base = base.darkened(0.08)
			draw_rect(Rect2(x, y, 16, 16), base)
			if h % 5 == 0:
				draw_rect(Rect2(x + h % 9, y + (h >> 3) % 9, 2, 4), Color("879467", 0.8))
			if h % 7 == 0:
				draw_rect(Rect2(x + 3, y + 12, 5, 1), Color("354838"))
			if h % 11 == 0:
				draw_rect(Rect2(x + 10, y + 3, 3, 2), Color("7a7760"))
	# 踩踏形成的道路用稳定的颜色块连接，不使用外部场景图片。
	for x in range(0, 640, 8):
		var center_y := 205 + int(sin(float(x) * 0.018) * 11.0)
		var h := _hash(x, center_y)
		for lane in range(-2, 3):
			var value := h + lane * 19
			if value % 4 != 0:
				draw_rect(Rect2(x, center_y + lane * 8, 8, 8), Color("77775b") if value % 6 == 0 else Color("6d7255"))
	# 浮起一层石阶，阴影让地表有可读的高度。
	draw_rect(Rect2(235, 84, 105, 6), Color("303a35"))
	draw_rect(Rect2(235, 78, 105, 8), Color("7c8266"))
	for x in range(239, 338, 13):
		draw_rect(Rect2(x, 78, 1, 6), Color("495848"))
	draw_rect(Rect2(278, 86, 20, 4), Color("a49a6d"))
	draw_rect(Rect2(280, 90, 16, 4), Color("5c624a"))
	draw_rect(Rect2(282, 94, 12, 4), Color("8a8464"))
	# 河湾与卵石提升场景层次，保持可重现的程序化布局。
	for y in range(300, 400, 5):
		var shore_x := int(480 + sin(float(y) * 0.027) * 15.0)
		draw_rect(Rect2(shore_x, y, 640 - shore_x, 5), Color("426570"))
		draw_rect(Rect2(shore_x - 3, y, 3, 5), Color("a5a486"))
		if y % 15 == 0:
			draw_rect(Rect2(shore_x + 30, y + 1, 16, 1), Color("7d9b9a", 0.55))
