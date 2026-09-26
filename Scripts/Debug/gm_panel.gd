extends CanvasLayer

var toggle_button: Button
var menu: PanelContainer
var scroll: ScrollContainer
var command_list: VBoxContainer
var feedback: Label
var commands: Dictionary = {}
var rows: Dictionary = {}

func _ready() -> void:
	layer = 100
	add_to_group("gm_panel")
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	toggle_button = Button.new()
	toggle_button.text = "GM"
	toggle_button.tooltip_text = "打开测试工具"
	root.add_child(toggle_button)
	toggle_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	toggle_button.offset_left = -90
	toggle_button.offset_right = -18
	toggle_button.offset_top = 76
	toggle_button.offset_bottom = 118
	toggle_button.pressed.connect(func(): set_open(not is_open()))
	menu = PanelContainer.new()
	root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	menu.offset_left = -370
	menu.offset_right = -18
	menu.offset_top = 128
	menu.offset_bottom = 448
	var style := StyleBoxFlat.new()
	style.bg_color = Color("16242b")
	style.border_color = Color("d6b77a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	menu.add_theme_stylebox_override("panel", style)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	menu.add_child(layout)
	var heading := HBoxContainer.new()
	layout.add_child(heading)
	var title := Label.new()
	title.text = "GM 测试工具"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close := Button.new()
	close.text = "关闭"
	close.pressed.connect(func(): set_open(false))
	heading.add_child(close)
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 190)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	command_list = VBoxContainer.new()
	command_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_list.add_theme_constant_override("separation", 10)
	scroll.add_child(command_list)
	feedback = Label.new()
	feedback.text = "选择指令执行；菜单支持上下滚动。"
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(feedback)
	register_command("kill_enemy", "秒杀当前敌人", "立即获胜，并执行正常战斗结算。", _kill_enemy, _kill_reason)
	set_open(false)

func is_open() -> bool:
	return is_instance_valid(menu) and menu.visible

func set_open(value: bool) -> void:
	menu.visible = value
	toggle_button.text = "GM ×" if value else "GM"
	if value:
		refresh_commands()

func register_command(id: String, title: String, description: String, execute: Callable, reason: Callable) -> bool:
	if id.is_empty() or commands.has(id) or not execute.is_valid() or not reason.is_valid(): return false
	commands[id] = {"execute": execute, "reason": reason}
	var row := VBoxContainer.new()
	command_list.add_child(row)
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = 38
	button.pressed.connect(_execute.bind(id))
	row.add_child(button)
	var details := Label.new()
	details.text = description
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(details)
	var availability := Label.new()
	availability.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(availability)
	rows[id] = {"button": button, "availability": availability}
	refresh_commands()
	return true

func refresh_commands() -> void:
	for id in commands:
		var entry: Dictionary = commands[id]
		var reason: String = str(entry.reason.call()) if entry.reason.is_valid() and entry.execute.is_valid() else "操作已失效"
		rows[id].button.disabled = not reason.is_empty()
		rows[id].availability.text = reason if not reason.is_empty() else "可执行"

func _process(_delta: float) -> void:
	if is_open(): refresh_commands()

func _execute(id: String) -> void:
	if not commands.has(id): return
	var entry: Dictionary = commands[id]
	if not entry.execute.is_valid() or not entry.reason.is_valid(): return
	var reason := str(entry.reason.call())
	if not reason.is_empty():
		feedback.text = reason
		return
	feedback.text = "执行成功。" if entry.execute.call() else "当前无法执行。"
	refresh_commands()

func _battle_context() -> Node:
	for candidate in get_tree().get_nodes_in_group("gm_battle_context"):
		if not candidate.is_queued_for_deletion(): return candidate
	return null

func _kill_reason() -> String:
	var context := _battle_context()
	return "请先进入战斗" if context == null else context.gm_kill_reason()

func _kill_enemy() -> bool:
	var context := _battle_context()
	return context != null and context.gm_kill_enemy()

func _input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		set_open(false)
		get_viewport().set_input_as_handled()
