extends CanvasLayer

# Esc pauses the game. Works while the tree is paused.

var panel

func _ready():
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 5
    visible = false

    panel = Control.new()
    add_child(panel)
    panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var dim = ColorRect.new()
    dim.color = Color(0, 0, 0, 0.65)
    panel.add_child(dim)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    var center = CenterContainer.new()
    panel.add_child(center)
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var box = VBoxContainer.new()
    box.add_theme_constant_override("separation", 12)
    center.add_child(box)

    var title = Label.new()
    title.text = "PAUSED"
    title.add_theme_font_size_override("font_size", 56)
    title.add_theme_color_override("font_color", Color(0.5, 1.0, 0.7))
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(title)

    box.add_child(_btn("RESUME", _toggle))
    box.add_child(_btn("RESTART LEVEL", _restart))
    box.add_child(_btn("MAIN MENU", _to_menu))

    var info = Label.new()
    info.text = "Change keys in  Main Menu > Controls"
    info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    info.add_theme_font_size_override("font_size", 16)
    box.add_child(info)

func _btn(text, cb):
    var b = Button.new()
    b.text = text
    b.custom_minimum_size = Vector2(320, 46)
    b.add_theme_font_size_override("font_size", 22)
    b.pressed.connect(cb)
    return b

func _unhandled_input(event):
    if event.is_action_pressed("pause"):
        _toggle()
        get_viewport().set_input_as_handled()

func _toggle():
    visible = not visible
    get_tree().paused = visible

func _restart():
    get_tree().paused = false
    get_tree().reload_current_scene()

func _to_menu():
    get_tree().paused = false
    get_tree().change_scene_to_file("res://menu.tscn")
