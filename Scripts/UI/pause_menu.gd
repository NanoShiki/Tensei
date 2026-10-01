extends Window

signal menu_requested
const Log = preload("res://Scripts/Core/game_log.gd")
var snapshot: Callable
var before: Dictionary = {}
var owned_pause := false
var settings_path := "user://menu_settings.cfg"
var settings := ConfigFile.new()
var volume: HSlider
var fullscreen: CheckButton
var resume_button: Button
var menu_button: Button
var confirm_button: Button
var cancel_button: Button
var content: VBoxContainer
var confirmation: VBoxContainer
var feedback: Label

func open(read_state: Callable) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	snapshot = read_state
	before = snapshot.call()
	title = "旅程已暂停"
	transient = true
	exclusive = true
	unresizable = true
	close_requested.connect(resume)
	settings.load(settings_path)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var description := Label.new()
	description.text = "敌人行动和反馈动画已停止。继续后从原位置恢复。\n角色进度需在城市或地图安全点手动保存。"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description)
	resume_button = _button(content, "继续旅程 · Esc", resume)
	fullscreen = CheckButton.new()
	fullscreen.text = "全屏显示"
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.toggled.connect(_fullscreen)
	content.add_child(fullscreen)
	var label := Label.new()
	label.text = "主音量"
	content.add_child(label)
	volume = HSlider.new()
	volume.min_value = 0
	volume.max_value = 100
	volume.step = 1
	volume.value = AudioServer.get_bus_volume_linear(0) * 100
	volume.custom_minimum_size.y = 32
	volume.value_changed.connect(_volume)
	content.add_child(volume)
	feedback = Label.new()
	feedback.text = "设置即时生效，与主菜单共用。"
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(feedback)
	menu_button = _button(content, "回到主菜单（未保存）", _ask_menu)
	confirmation = VBoxContainer.new()
	confirmation.add_theme_constant_override("separation", 14)
	margin.add_child(confirmation)
	var warning := Label.new()
	warning.text = "回到主菜单？\n未保存的个人进度会丢失，共享组织成果保留。\n取消后仍保持暂停；点击继续可回到旅程。"
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirmation.add_child(warning)
	confirm_button = _button(confirmation, "确认回到主菜单", _leave)
	cancel_button = _button(confirmation, "取消 · 保持暂停", _cancel_menu)
	confirmation.hide()
	get_tree().paused = true
	owned_pause = true
	Log.event("pause", "open", {"state": before})
	popup_centered(Vector2i(570, 430))
	resume_button.grab_focus()

func _button(box: VBoxContainer, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.pressed.connect(callback)
	box.add_child(button)
	return button

func _volume(value: float) -> void:
	AudioServer.set_bus_volume_linear(0, clampf(value / 100.0, 0, 1))
	settings.set_value("audio", "volume", value)
	_save_settings("volume", value)

func _fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
	settings.set_value("display", "fullscreen", enabled)
	_save_settings("fullscreen", enabled)

func _save_settings(key: String, value: Variant) -> void:
	var result := settings.save(settings_path)
	feedback.text = "设置已保存。" if result == OK else "设置已生效，保存失败：" + error_string(result)
	Log.event("pause", "settings", {"key": key, "value": value, "success": result == OK, "reason": feedback.text}, "INFO" if result == OK else "WARN")

func _ask_menu() -> void:
	content.hide()
	confirmation.show()
	cancel_button.grab_focus()

func _cancel_menu() -> void:
	confirmation.hide()
	content.show()
	menu_button.grab_focus()

func resume() -> void:
	_finish("resume")
	queue_free()

func _leave() -> void:
	_finish("menu")
	menu_requested.emit()
	queue_free()

func _finish(action: String) -> void:
	if not owned_pause: return
	var after: Dictionary = snapshot.call() if snapshot.is_valid() else before
	Log.event("pause", action, {"before": before, "after": after})
	owned_pause = false
	get_tree().paused = false

func _exit_tree() -> void:
	if owned_pause: _finish("closed")

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		if confirmation.visible: _cancel_menu()
		else: resume()
