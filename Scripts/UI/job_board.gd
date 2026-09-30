extends Window

signal changed
const Jobs = preload("res://Scripts/Character/job_library.gd")
const Abilities = preload("res://Scripts/Battle/ability_library.gd")
var run: RefCounted
var rows: VBoxContainer
var feedback: Label
var buttons: Dictionary = {}

func open(expedition: RefCounted) -> void:
	run = expedition
	title = "基础职业与技能"
	transient = true
	exclusive = true
	unresizable = true
	close_requested.connect(queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 12)
	scroll.add_child(rows)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(feedback)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size.y = 38
	close.pressed.connect(queue_free)
	box.add_child(close)
	_refresh()
	popup_centered(Vector2i(680, 470))
	close.grab_focus()

func _text(value: String) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	rows.add_child(label)

func _button(id: String, label: String, disabled: bool) -> void:
	var button := Button.new()
	button.text = label
	button.disabled = disabled
	button.custom_minimum_size.y = 40
	button.pressed.connect(_act.bind(id))
	rows.add_child(button)
	buttons[id] = button

func _refresh() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	buttons.clear()
	var hero: Dictionary = run.character
	for id in Jobs.ENTRIES:
		var job: Dictionary = Jobs.ENTRIES[id]
		var skill: Dictionary = Abilities.ENTRIES[job.skill]
		_text("%s · %s\n防御 %d · 命中 +%d · 敏捷 +%d\n%s：%s\n技能条件：等级 %d（当前等级 %d）" % [job.name, job.role, job.ac, job.attack, job.dex, skill.name, skill.hint, job.level, hero.level])
		_button(id, "当前职业" if hero.job_id == id else "选择%s · 免费" % job.name, hero.job_id == id)
	feedback.text = "Demo 可在城市免费切换。职业仅改变命中、防御、敏捷和第二技能；等级、生命、装备、个人任务与眷族保留，选择后需手动保存。"

func _act(id: String) -> void:
	if run.job_service(id):
		_refresh()
		changed.emit()
		feedback.text = run.message
	else: feedback.text = "当前条件不满足，角色数据保留。"

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()
