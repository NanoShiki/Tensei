extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var menu = load("res://Scenes/UI/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	assert(menu.background.texture != null)
	assert(menu.continue_button.disabled)
	assert(menu.start_button.has_focus())
	assert(menu.animation_lab_button.text.contains("2.5D"))
	menu.apply_character_portrait({"illustration_id": "unknown.character"})
	assert(menu.caption.text.contains("洛恩"))
	menu._open_character()
	await process_frame
	assert(is_instance_valid(menu.modal))
	assert(menu.start_button.focus_mode == Control.FOCUS_NONE)
	menu._close_modal()
	await process_frame
	assert(menu.start_button.has_focus())
	menu._open_settings()
	await process_frame
	assert(menu.fullscreen_toggle.has_focus())
	menu._settings_loading = true
	var original_volume: float = AudioServer.get_bus_volume_linear(0)
	menu._set_volume(25)
	assert(is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.25))
	AudioServer.set_bus_volume_linear(0, original_volume)
	menu._close_modal()
	await process_frame
	menu._open_quit()
	await process_frame
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	menu._unhandled_key_input(escape)
	assert(menu.modal == null)
	print("PASS: portrait fallback, no-save state, dialogs, focus, volume, Escape")
	menu.queue_free()
	await process_frame
	quit(0)
