extends Window

signal decided(avoid: bool)
var fight_button: Button
var avoid_button: Button
var cancel_button: Button

func open(preview: Dictionary) -> void:
	title = "前方遭遇"
	transient = true
	exclusive = true
	unresizable = true
	close_requested.connect(queue_free)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var text := Label.new()
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 19)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.text = "前方：%s\n\n交战：胜利获得战利品并清理节点。\n绕行：消耗灼烧药水 ×1（持有 %d），怪物保留，无战利品，不完成讨伐。\n\n确认后移动 1 步；取消不移动、不消耗。" % [preview.name, preview.stock]
	box.add_child(text)
	fight_button = _button(box, "进入交战", func(): _decide(false))
	avoid_button = _button(box, "消耗灼烧药水 ×1 · 掩护绕行", func(): _decide(true))
	avoid_button.disabled = not preview.can_avoid
	avoid_button.tooltip_text = "灼烧药水不足，可交战或取消。" if avoid_button.disabled else "怪物保留；再次经过还会遭遇。"
	cancel_button = _button(box, "取消", queue_free)
	popup_centered(Vector2i(640, 390))
	cancel_button.grab_focus()

func _button(box: VBoxContainer, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.pressed.connect(callback)
	box.add_child(button)
	return button

func _decide(avoid: bool) -> void:
	# 关闭窗口后由父场景延迟移动，保留本次输入的视口生命周期。
	fight_button.disabled = true
	avoid_button.disabled = true
	cancel_button.disabled = true
	decided.emit(avoid)
	queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()
