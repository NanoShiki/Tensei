extends Control

signal new_game_requested(character_id: String)

const Portrait = preload("res://Scripts/UI/menu_portrait.gd")
const INK := Color("172027")
const PAPER := Color("f4eddd")
const GOLD := Color("d8b77d")
const SETTINGS_PATH := "user://menu_settings.cfg"

var background: TextureRect
var menu_column: VBoxContainer
var caption: Label
var status: Label
var continue_button: Button
var start_button: Button
var settings_button: Button
var modal: PanelContainer
var modal_shade: ColorRect
var last_focus: Control
var settings := ConfigFile.new()
var fullscreen_toggle: CheckButton
var volume_slider: HSlider
var _settings_loading := false


func _ready() -> void:
	_build_theme()
	_build_background()
	_build_menu()
	apply_character_portrait()
	_load_settings()
	resized.connect(_layout)
	_layout()
	start_button.grab_focus()


func _build_theme() -> void:
	theme = Theme.new()
	theme.default_font_size = 20
	theme.set_color("font_color", "Label", PAPER)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1, 1, 1, 0.075) if state in ["hover", "focus"] else Color(0, 0, 0, 0)
		style.border_width_bottom = 1
		style.border_color = Color(GOLD, 0.8) if state in ["hover", "focus", "pressed"] else Color(PAPER, 0.15)
		style.content_margin_left = 18
		style.content_margin_right = 18
		theme.set_stylebox(state, "Button", style)
	theme.set_color("font_color", "Button", PAPER)
	theme.set_color("font_hover_color", "Button", GOLD)
	theme.set_color("font_focus_color", "Button", GOLD)
	theme.set_color("font_disabled_color", "Button", Color(PAPER, 0.35))


func _build_background() -> void:
	background = TextureRect.new()
	background.name = "CharacterIllustration"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.34, 0.65, 1])
	gradient.colors = PackedColorArray([Color(INK, 0.97), Color(INK, 0.88), Color(INK, 0.25), Color(INK, 0.06)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.RIGHT
	var veil := TextureRect.new()
	veil.texture = texture
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)


func _label(text: String, font_size: int, color: Color = PAPER) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, callback: Callable, parent: Node) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 48
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _build_menu() -> void:
	menu_column = VBoxContainer.new()
	menu_column.add_theme_constant_override("separation", 10)
	add_child(menu_column)
	menu_column.add_child(_label("P R O J E C T", 17, GOLD))
	var title := _label("TENSEI", 76)
	var serif := SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Times New Roman"])
	title.add_theme_font_override("font", serif)
	menu_column.add_child(title)
	menu_column.add_child(_label("每一次启程，都留下你的故事。", 17, Color(PAPER, 0.65)))
	var gap := Control.new()
	gap.custom_minimum_size.y = 28
	menu_column.add_child(gap)
	continue_button = _button("继续旅程", func(): pass, menu_column)
	continue_button.disabled = true
	continue_button.tooltip_text = "尚无可继续的旅程"
	start_button = _button("开始旅程    →", _open_character, menu_column)
	settings_button = _button("设置", _open_settings, menu_column)
	_button("退出游戏", _open_quit, menu_column)
	status = _label("序章  /  新的起点", 13, Color(PAPER, 0.5))
	add_child(status)
	caption = _label("", 16)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(caption)


func _layout() -> void:
	menu_column.position = Vector2(size.x * 0.075, maxf(24, size.y * 0.15))
	menu_column.size.x = clampf(size.x * 0.28, 280, 380)
	status.position = Vector2(size.x * 0.075, size.y - 42)
	caption.position = Vector2(size.x - 315, size.y - 65)
	caption.size = Vector2(265, 45)
	if is_instance_valid(modal):
		modal.size.x = minf(520, size.x - 48)
		modal.reset_size()
		modal.position = (size - modal.size) / 2


func apply_character_portrait(latest_character: Dictionary = {}) -> void:
	var entry := Portrait.resolve(latest_character)
	background.texture = entry["texture"]
	caption.text = "%s  /  %s" % [entry["name"], entry["stage"]]


func _open_modal(title: String) -> VBoxContainer:
	last_focus = get_viewport().gui_get_focus_owner()
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0, 0, 0, 0.62)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal_shade)
	# 隐藏菜单焦点，防止 Tab 穿透弹层。
	for child in menu_column.get_children():
		if child is Button:
			child.focus_mode = Control.FOCUS_NONE
	modal = PanelContainer.new()
	modal.custom_minimum_size.x = 500
	var style := StyleBoxFlat.new()
	style.bg_color = Color("20292e")
	style.border_color = Color(GOLD, 0.5)
	style.set_border_width_all(1)
	style.set_content_margin_all(30)
	modal.add_theme_stylebox_override("panel", style)
	add_child(modal)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	modal.add_child(content)
	content.add_child(_label(title, 28, GOLD))
	_layout.call_deferred()
	return content


func _close_modal() -> void:
	if not is_instance_valid(modal):
		return
	modal.queue_free()
	modal_shade.queue_free()
	modal = null
	for child in menu_column.get_children():
		if child is Button:
			child.focus_mode = Control.FOCUS_ALL
	if is_instance_valid(last_focus):
		last_focus.grab_focus()


func _open_character() -> void:
	var content := _open_modal("新的旅程")
	content.add_child(_label("洛恩 · 见习剑士", 23))
	var description := _label("红发、热心，带着一把练习木剑长大。\n他的冒险即将开始。", 18)
	content.add_child(description)
	content.add_child(_label("从这里进入一场横版卡牌战斗原型。", 15, Color(PAPER, 0.6)))
	new_game_requested.emit("lorn")
	_button("进入战斗    →", _start_battle, content)
	_button("返回", _close_modal, content).grab_focus()


func _start_battle() -> void:
	var flow := get_node_or_null("/root/GameFlow")
	if flow != null:
		flow.start_battle("lorn")


func _open_settings() -> void:
	var content := _open_modal("设置")
	fullscreen_toggle = CheckButton.new()
	fullscreen_toggle.text = "全屏显示"
	fullscreen_toggle.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_toggle.toggled.connect(_set_fullscreen)
	content.add_child(fullscreen_toggle)
	content.add_child(_label("主音量", 18))
	volume_slider = HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 1
	volume_slider.value = AudioServer.get_bus_volume_linear(0) * 100
	volume_slider.custom_minimum_size.y = 30
	volume_slider.value_changed.connect(_set_volume)
	content.add_child(volume_slider)
	_button("返回", _close_modal, content)
	fullscreen_toggle.grab_focus()


func _set_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	settings.set_value("display", "fullscreen", enabled)
	_save_settings()


func _set_volume(value: float) -> void:
	AudioServer.set_bus_volume_linear(0, clampf(value / 100.0, 0, 1))
	settings.set_value("audio", "volume", value)
	_save_settings()


func _load_settings() -> void:
	_settings_loading = true
	if settings.load(SETTINGS_PATH) == OK:
		_set_volume(float(settings.get_value("audio", "volume", 80)))
		_set_fullscreen(bool(settings.get_value("display", "fullscreen", false)))
	_settings_loading = false


func _save_settings() -> void:
	if not _settings_loading:
		var error := settings.save(SETTINGS_PATH)
		if error != OK:
			push_warning("菜单设置保存失败：%s" % error_string(error))


func _open_quit() -> void:
	var content := _open_modal("结束本次旅程？")
	_button("退出游戏", func(): get_tree().quit(), content)
	_button("继续停留", _close_modal, content).grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(modal):
		_close_modal()
		get_viewport().set_input_as_handled()
