extends RefCounted

# 小尺寸源图由颜色块组合；角色部件和调色板可独立替换。
static var _cache: Dictionary = {}


static func get_part(kind: String, part: String, view: String, weapon: String = "sword") -> Texture2D:
	var key := "%s/%s/%s/%s" % [kind, part, view, weapon]
	if _cache.has(key):
		return _cache[key]
	var image := Image.create(20, 24, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var outline := Color("222a29")
	var skin := Color("ddb88a") if kind == "hero" else Color("9cb37a")
	var skin_dark := Color("a97958") if kind == "hero" else Color("63865f")
	var cloth := Color("ae5147") if kind == "hero" else Color("706c45")
	var cloth_light := Color("d17e60") if kind == "hero" else Color("a1a06a")
	var cloth_dark := Color("643c3c") if kind == "hero" else Color("3f5142")
	var hair := Color("9a4836") if kind == "hero" else Color("384f36")
	var metal := Color("d8d5ba")
	match part:
		"cape":
			if kind == "hero":
				_rect(image, 2, 0, 16, 21, outline)
				_rect(image, 3, 0, 14, 18, cloth_dark)
				_rect(image, 4, 2, 3, 17, Color("834448"))
				_rect(image, 11, 3, 4, 17, Color("502c36"))
				_rect(image, 5, 19, 3, 2, cloth_dark)
				_rect(image, 12, 18, 4, 3, cloth_dark)
		"torso":
			_rect(image, 2, 1, 16, 22, outline)
			_rect(image, 3, 2, 14, 17, cloth)
			_rect(image, 5, 2, 8, 4, cloth_light)
			_rect(image, 3, 16, 14, 4, cloth_dark)
			_rect(image, 4, 18, 12, 2, metal if kind == "hero" else cloth_light)
			if view != "back":
				_rect(image, 9, 5, 2, 11, metal if kind == "hero" else cloth_dark)
				_rect(image, 6, 7, 8, 2, cloth_dark)
			else:
				_rect(image, 8, 3, 4, 12, cloth_dark)
			if view == "side":
				_rect(image, 14, 5, 2, 12, cloth_dark)
		"head":
			_rect(image, 3, 3, 14, 17, outline)
			_rect(image, 4, 5, 12, 13, skin)
			_rect(image, 4, 3, 12, 6, hair)
			_rect(image, 5, 4, 3, 7, hair)
			_rect(image, 13, 4, 2, 5, hair)
			if view == "front":
				_rect(image, 6, 12, 2, 2, outline)
				_rect(image, 12, 12, 2, 2, outline)
				_rect(image, 8, 16, 4, 1, skin_dark)
			elif view == "side":
				_rect(image, 12, 12, 2, 2, outline)
				_rect(image, 15, 10, 2, 3, skin_dark)
			else:
				_rect(image, 5, 8, 9, 8, hair)
				_rect(image, 7, 16, 6, 3, skin_dark)
		"arm":
			_rect(image, 6, 1, 8, 17, outline)
			_rect(image, 7, 2, 6, 10, cloth)
			_rect(image, 8, 3, 3, 6, cloth_light)
			_rect(image, 7, 12, 6, 4, skin)
			_rect(image, 8, 16, 4, 3, skin_dark)
		"leg":
			_rect(image, 6, 0, 8, 22, outline)
			_rect(image, 7, 1, 6, 12, cloth_dark)
			_rect(image, 8, 2, 3, 8, cloth)
			_rect(image, 6, 13, 8, 8, Color("584b3e") if kind == "hero" else Color("3d4636"))
			_rect(image, 5, 20, 10, 2, outline)
		"weapon":
			if weapon == "staff":
				_rect(image, 9, 2, 3, 20, outline)
				_rect(image, 10, 3, 1, 18, Color("987049"))
				_rect(image, 7, 0, 7, 7, Color("44a7b0"))
				_rect(image, 9, 1, 3, 4, Color("bbf5db"))
			else:
				_rect(image, 9, 1, 3, 17, outline)
				_rect(image, 10, 2, 1, 14, metal)
				_rect(image, 7, 15, 7, 2, Color("e6c783"))
				_rect(image, 9, 17, 3, 6, Color("664a35"))
	_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]


static func _rect(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	image.fill_rect(Rect2i(x, y, width, height), color)
