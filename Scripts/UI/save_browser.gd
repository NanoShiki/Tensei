extends Window

signal load_requested(profile_id: String, record_id: String)
signal saved(record_id: String)

var library: RefCounted
var run: RefCounted
var profile: Dictionary = {}
var selected_id := ""
var selected_name := ""
var rows: VBoxContainer
var heading: Label
var feedback: Label
var name_input: LineEdit
var save_button: Button
var back_button: Button
var list_buttons: Array[Button] = []
var _committing := false

func open(store: RefCounted, character: Dictionary = {}, expedition: RefCounted = null) -> void:
	library = store
	profile = character.duplicate(true)
	run = expedition
	title = "保存旅程" if run != null else "读取存档"
	transient = true
	exclusive = true
	unresizable = true
	close_requested.connect(queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 23)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size", 16)
	content.add_child(feedback)
	if run != null:
		name_input = LineEdit.new()
		name_input.max_length = 32
		name_input.placeholder_text = "输入存档名称（最多 32 字）"
		name_input.text = "第 %d 层 · %d 步" % [run.floor_number, run.steps_taken]
		name_input.text_changed.connect(func(_text): _update_save_button())
		content.add_child(name_input)
		save_button = _button("新增记录并退出", _request_save, content)
	back_button = _button("返回角色列表", _show_profiles, content)
	_button("取消", queue_free, content)
	if run == null: _show_profiles()
	else: _show_records(profile.id)
	popup_centered(Vector2i(680, 460))
	if name_input != null: name_input.grab_focus()
	elif not list_buttons.is_empty(): list_buttons[0].grab_focus()

func _button(text: String, callback: Callable, parent: Node) -> Button:
	var button := Button.new()
	button.text = text
	button.clip_text = true
	button.tooltip_text = text
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size", 17)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _clear_rows() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	list_buttons.clear()
	feedback.text = ""

func _show_profiles() -> void:
	_clear_rows()
	heading.text = "读取存档 · 选择角色档案"
	back_button.hide()
	for character in library.list_profiles():
		var text := "%s  ·  %d 条记录  ·  %s" % [character.name, character.count, character.id.left(6)]
		list_buttons.append(_button(text, _show_records.bind(str(character.id)), rows))
	if list_buttons.is_empty(): feedback.text = "还没有保存过的角色。开始旅程后，在地图保存即可建立档案。"

func _show_records(profile_id: String) -> void:
	_clear_rows()
	var records: Array = library.list_records(profile_id)
	var character_name: String = profile.get("name", "角色")
	if run == null:
		for character in library.list_profiles():
			if character.id == profile_id: character_name = character.name
	heading.text = character_name + (" · 保存记录" if run != null else " · 选择存档")
	back_button.visible = run == null
	if run != null:
		list_buttons.append(_button("＋ 新增存档记录", func():
			selected_id = ""
			feedback.text = "将新增一条记录，其他存档保留。"
			name_input.text = "第 %d 层 · %d 步" % [run.floor_number, run.steps_taken]
			_update_save_button(), rows))
	for record in records:
		var text: String
		var callback: Callable
		if record.has("error"):
			text = "无法读取 · %s\n%s" % [record.record_id.left(6), record.error]
			callback = func(): pass
		else:
			var meta: Dictionary = record.metadata
			var date := Time.get_datetime_string_from_unix_time(int(meta.saved_at / 1000000) + int(Time.get_time_zone_from_system().bias) * 60).replace("T", " ")
			text = "%s\n第 %d 层 · %d 步 · %s · %s" % [meta.name, record.run.floor_number, record.run.steps_taken, "返回中" if record.run.phase == "returning" else "深入中", date]
			if not record.warning.is_empty(): text += "\n" + record.warning
			if run == null:
				callback = func(): load_requested.emit(profile_id, record.record_id)
			else:
				callback = func():
					selected_id = record.record_id
					selected_name = meta.name
					name_input.text = meta.name
					feedback.text = "已选择覆盖：" + meta.name
					_update_save_button()
		var button := _button(text, callback, rows)
		button.disabled = record.has("error") or (run != null and record.record_id == "legacy")
		list_buttons.append(button)
	if records.is_empty(): feedback.text = "首次保存将建立该角色档案及第一条记录。"
	if run != null: _update_save_button()

func _update_save_button() -> void:
	save_button.text = "新增记录并退出" if selected_id.is_empty() else "覆盖所选记录并退出"
	save_button.disabled = name_input.text.strip_edges().is_empty() or _committing

func _request_save() -> void:
	if _committing or name_input.text.strip_edges().is_empty(): return
	if selected_id.is_empty():
		_commit()
		return
	var confirmation := ConfirmationDialog.new()
	confirmation.title = "覆盖存档记录？"
	confirmation.dialog_text = "角色：%s\n原记录：%s\n保存名称：%s\n只替换所选记录，其他记录保留。" % [profile.name, selected_name, name_input.text]
	confirmation.confirmed.connect(_commit)
	confirmation.confirmed.connect(confirmation.queue_free)
	confirmation.canceled.connect(confirmation.queue_free)
	add_child(confirmation)
	confirmation.popup_centered()

func _commit() -> void:
	if _committing: return
	_committing = true
	_update_save_button()
	var record_id: String = library.save_record(run, profile, name_input.text, selected_id)
	if record_id.is_empty():
		feedback.text = library.message
		_committing = false
		_update_save_button()
		return
	saved.emit(record_id)
	queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()
