extends Window

const Training = preload("res://Scripts/Battle/training_library.gd")
const Jobs = preload("res://Scripts/Character/job_library.gd")
const Weapons = preload("res://Scripts/Character/weapon_library.gd")
const Armors = preload("res://Scripts/Character/armor_library.gd")
var flow: Node
var choices := {}
var values := {}
var start_button: Button
var feedback: Label

func open(game_flow: Node) -> void:
	flow = game_flow
	title = "战斗演练配置"
	transient = true
	exclusive = true
	unresizable = true
	close_requested.connect(queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	var note := Label.new()
	note.text = "独立演练：每次从满血和初始补给开始，不保存个人进度、奖励或共享成长。\n相同配置与随机种子可重现先攻及相同行动的骰子。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	var config: Dictionary = flow.training_config if not flow.training_config.is_empty() else Training.DEFAULT
	_option(grid, "job", "职业", Jobs.ENTRIES, config.job)
	_number(grid, "level", "等级／队友演练等级", 1, 5, config.level)
	_option(grid, "weapon", "武器", Weapons.ENTRIES, config.weapon)
	_option(grid, "armor", "护甲", Armors.ENTRIES, config.armor)
	_option(grid, "enemy", "敌人", Training.ENCOUNTERS, config.enemy)
	_number(grid, "party", "己方人数（洛恩／卫士／游侠）", 1, 3, config.party)
	_number(grid, "floor", "敌人楼层参数", 1, 30, config.floor)
	_number(grid, "seed", "随机种子（0–2147483647）", 0, 2147483647, config.seed)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.text = "等级 1 保留真实技能门槛；队友使用独立属性和木剑。"
	box.add_child(feedback)
	start_button = Button.new()
	start_button.text = "开始新演练（替换当前演练）"
	start_button.custom_minimum_size.y = 38
	start_button.pressed.connect(_start)
	box.add_child(start_button)
	var close := Button.new()
	close.text = "取消 · Esc"
	close.custom_minimum_size.y = 34
	close.pressed.connect(queue_free)
	box.add_child(close)
	popup_centered(Vector2i(700, 485))
	close.grab_focus()

func _label(grid: GridContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)

func _option(grid: GridContainer, key: String, text: String, entries: Dictionary, current: String) -> void:
	_label(grid, text)
	var field := OptionButton.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(field)
	var ids: Array = entries.keys()
	for id in ids: field.add_item(str(entries[id].name) if entries[id] is Dictionary else str(entries[id]))
	field.select(ids.find(current))
	choices[key] = field
	values[key] = ids

func _number(grid: GridContainer, key: String, text: String, minimum: int, maximum: int, current: int) -> void:
	_label(grid, text)
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.step = 1
	field.update_on_text_changed = true
	field.value = current
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(field)
	choices[key] = field

func configuration() -> Dictionary:
	var result := {}
	for key in choices:
		result[key] = values[key][choices[key].selected] if values.has(key) else int(choices[key].value)
	return result

func _start() -> void:
	if flow.start_training(configuration()): queue_free()
	else: feedback.text = "当前无法开始演练，请等待动作结束，或从主菜单进入。"

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()
