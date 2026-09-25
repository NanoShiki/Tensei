extends Control

const Terrain = preload("res://Scripts/Prototype/lab_terrain.gd")
const Prop = preload("res://Scripts/Prototype/lab_prop.gd")
const Actor = preload("res://Scripts/Prototype/rigged_actor.gd")
const Effect = preload("res://Scripts/Prototype/lab_effect.gd")
const WORLD_SIZE := Vector2i(320, 180)
const PLAYER_SPEED := 82.0

var world_viewport: SubViewport
var world: Node2D
var sorting_layer: Node2D
var camera: Camera2D
var player: Node2D
var enemy: Node2D
var info_label: Label
var enemy_label: Label
var lab_time := 0.0
var respawn_time := -1.0
var active_projectiles: Array[Node2D] = []


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	_build_world()
	_build_hud()
	grab_focus()


func _build_world() -> void:
	world_viewport = SubViewport.new()
	world_viewport.name = "PixelViewport"
	world_viewport.size = WORLD_SIZE
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_viewport.gui_disable_input = true
	add_child(world_viewport)
	var picture := TextureRect.new()
	picture.name = "PixelWorld"
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.texture = world_viewport.get_texture()
	add_child(picture)
	world = Node2D.new()
	world.name = "World"
	world_viewport.add_child(world)
	var terrain: Node2D = Terrain.new()
	terrain.name = "Terrain"
	world.add_child(terrain)
	sorting_layer = Node2D.new()
	sorting_layer.name = "DepthSortedActorsAndProps"
	sorting_layer.y_sort_enabled = true
	world.add_child(sorting_layer)
	for tree_position in [Vector2(198, 161), Vector2(227, 245), Vector2(381, 152), Vector2(420, 243), Vector2(514, 203)]:
		_make_prop("tree", tree_position, int(tree_position.x))
	for rock_position in [Vector2(174, 238), Vector2(246, 131), Vector2(389, 262), Vector2(455, 172)]:
		_make_prop("rock", rock_position)
	_make_prop("rune", Vector2(362, 196))
	_make_prop("torch", Vector2(294, 151))
	player = Actor.new()
	player.name = "PrototypeHero"
	player.configure("hero")
	player.position = Vector2(290, 206)
	sorting_layer.add_child(player)
	player.set_motion(Vector2.RIGHT)
	player.set_motion(Vector2.ZERO)
	player.action_peak.connect(_on_player_action_peak)
	enemy = Actor.new()
	enemy.name = "PrototypeGoblin"
	enemy.configure("goblin")
	enemy.position = Vector2(350, 202)
	sorting_layer.add_child(enemy)
	enemy.set_motion(Vector2.LEFT)
	camera = Camera2D.new()
	camera.name = "LabCamera"
	camera.position = player.position
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = Terrain.WORLD_SIZE.x
	camera.limit_bottom = Terrain.WORLD_SIZE.y
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	world.add_child(camera)
	camera.make_current()
	var ambient := CanvasModulate.new()
	ambient.color = Color("c9cfbd")
	world.add_child(ambient)
	var torch := PointLight2D.new()
	torch.name = "TorchLight"
	torch.position = Vector2(294, 133)
	torch.texture = _make_light_texture()
	torch.texture_scale = 2.5
	torch.energy = 0.6
	torch.color = Color("f7b979")
	world.add_child(torch)
	var spell_light := PointLight2D.new()
	spell_light.name = "HeroGlow"
	spell_light.texture = _make_light_texture()
	spell_light.texture_scale = 1.9
	spell_light.energy = 0.18
	spell_light.color = Color("65d6d7")
	player.add_child(spell_light)
	spell_light.position = Vector2(0, -15)


func _make_prop(kind: String, at: Vector2, variant: int = 0) -> void:
	var prop: Node2D = Prop.new()
	prop.name = "%s_%d" % [kind, sorting_layer.get_child_count()]
	prop.position = at
	sorting_layer.add_child(prop)
	prop.configure(kind, variant)


func _make_light_texture() -> Texture2D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var distance := Vector2(x - 31.5, y - 31.5).length() / 31.5
			image.set_pixel(x, y, Color(1, 1, 1, pow(maxf(0, 1.0 - distance), 1.9)))
	return ImageTexture.create_from_image(image)


func _build_hud() -> void:
	var top := PanelContainer.new()
	top.name = "LabHud"
	top.position = Vector2(22, 20)
	top.custom_minimum_size = Vector2(342, 0)
	top.add_theme_stylebox_override("panel", _panel_style())
	add_child(top)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	top.add_child(stack)
	var heading := _label("2.5D 动画试验场", 25, Color("f3e7c3"))
	stack.add_child(heading)
	stack.add_child(_label("像素部件  ·  骨骼动作  ·  深度排序", 14, Color("b9d7c5")))
	info_label = _label("WASD 移动 · Space 跃起 · L 投矢", 15)
	stack.add_child(info_label)
	enemy_label = _label("前方哥布林：可被挥剑和技能命中", 14, Color("d1be9a"))
	stack.add_child(enemy_label)
	var back_button := _button("← 返回主菜单", _return_to_menu)
	back_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back_button.position = Vector2(-200, 20)
	back_button.custom_minimum_size = Vector2(180, 42)
	add_child(back_button)
	resized.connect(func(): back_button.position = Vector2(size.x - 202, 20))
	back_button.position = Vector2(size.x - 202, 20)
	var actions := HBoxContainer.new()
	actions.name = "LabActions"
	actions.add_theme_constant_override("separation", 10)
	actions.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	add_child(actions)
	var attack := _button("J  挥剑", _attack)
	var skill := _button("K  星焰", _skill)
	var swap := _button("Tab  切换武器", _swap_weapon)
	for button in [attack, skill, swap]:
		button.custom_minimum_size = Vector2(156, 48)
		actions.add_child(button)
	actions.position = Vector2(22, size.y - 68)
	resized.connect(func(): actions.position = Vector2(22, size.y - 68))
	var hint := _label("动作与素材均为独立验证样张 · Esc 返回", 13, Color("f0e3c2"))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	add_child(hint)
	hint.position = Vector2(size.x - 340, size.y - 56)
	resized.connect(func(): hint.position = Vector2(size.x - 340, size.y - 56))


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172324da")
	style.border_color = Color("d6b87b")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(14)
	return style


func _label(value: String, font_size: int, color: Color = Color("f3f1df")) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.pressed.connect(callback)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", _panel_style())
	var hover := _panel_style()
	hover.bg_color = Color("3c5049e9")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_color_override("font_color", Color("f4ead4"))
	button.add_theme_font_size_override("font_size", 17)
	return button


func _physics_process(delta: float) -> void:
	lab_time += delta
	var input_direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		input_direction.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		input_direction.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		input_direction.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		input_direction.y += 1
	input_direction = input_direction.normalized()
	player.set_motion(input_direction)
	player.position += input_direction * PLAYER_SPEED * delta
	player.position.x = clampf(player.position.x, 24, Terrain.WORLD_SIZE.x - 24)
	player.position.y = clampf(player.position.y, 105, Terrain.WORLD_SIZE.y - 22)
	camera.position = player.position
	if enemy.health > 0:
		enemy.position.x = 350 + sin(lab_time * 1.3) * 7.0
		enemy.set_motion(Vector2.LEFT if enemy.position.x > player.position.x else Vector2.RIGHT)
	else:
		respawn_time -= delta
		if respawn_time <= 0:
			enemy.revive()
			enemy.position = Vector2(350, 202)
			enemy.visible = true
	for index in range(active_projectiles.size() - 1, -1, -1):
		var projectile: Node2D = active_projectiles[index]
		if not is_instance_valid(projectile):
			active_projectiles.remove_at(index)
			continue
		if enemy.health <= 0:
			continue
		var hit_radius := 11.0 if projectile.effect_kind == "arrow" else 20.0
		if projectile.position.distance_to(enemy.position + Vector2(0, -20)) < hit_radius:
			if projectile.effect_kind == "arrow":
				enemy.embed_arrow(enemy.position + Vector2(0, -20) - projectile.direction * 5.0, projectile.direction)
			_hit_enemy()
			projectile.queue_free()
			active_projectiles.remove_at(index)
	if is_instance_valid(enemy_label):
		enemy_label.text = "哥布林生命：%d / 4    |    武器：%s" % [enemy.health, "木杖" if player.equipment == "staff" else "练习剑"]


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_J:
			_attack()
		KEY_K:
			_skill()
		KEY_L:
			_shoot_arrow()
		KEY_TAB:
			_swap_weapon()
		KEY_SPACE:
			player.jump()
		KEY_ESCAPE:
			_return_to_menu()
		_:
			return
	get_viewport().set_input_as_handled()


func _attack() -> void:
	if player.play_action("slash"):
		info_label.text = "挥剑：肩、手臂、武器共享动作阶段"


func _skill() -> void:
	if player.play_action("skill"):
		info_label.text = "星焰：施法姿势、光球和命中反馈"


func _shoot_arrow() -> void:
	if player.play_action("shoot"):
		info_label.text = "投矢：命中后保留在敌人骨骼的局部坐标"


func _swap_weapon() -> void:
	player.change_weapon()
	info_label.text = "已切换%s；动作骨架继续复用" % ["木杖" if player.equipment == "staff" else "练习剑"]


func _on_player_action_peak(action_name: String) -> void:
	var aim: Vector2 = player.facing
	var hand_origin: Vector2 = player.hand.global_position
	if action_name == "slash":
		_spawn_effect("slash", hand_origin + aim * 13.0, aim)
		if enemy.health > 0 and player.position.distance_to(enemy.position) < 72:
			var toward_enemy: Vector2 = (enemy.position - player.position).normalized()
			if toward_enemy.dot(aim) > 0.18:
				_hit_enemy()
	elif action_name == "skill":
		active_projectiles.append(_spawn_effect("spell", hand_origin + aim * 8.0, aim))
	elif action_name == "shoot":
		active_projectiles.append(_spawn_effect("arrow", hand_origin + aim * 8.0, aim))


func _spawn_effect(kind: String, at: Vector2, direction: Vector2 = Vector2.RIGHT) -> Node2D:
	var effect: Node2D = Effect.new()
	effect.position = at
	world.add_child(effect)
	effect.configure(kind, direction)
	return effect


func _hit_enemy() -> void:
	enemy.take_hit()
	_spawn_effect("hit", enemy.position + Vector2(0, -23))
	if enemy.health == 0:
		enemy.visible = false
		respawn_time = 2.0


func _return_to_menu() -> void:
	get_node("/root/GameFlow").return_to_menu()
