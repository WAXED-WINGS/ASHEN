extends Control

# Main menu: start, level select, controls (key rebinding + camera settings), quit.

const RAIN_CHARS = ".:*o&8@#|-/=+%"

var mono
var pages = {}
var title_box
var bind_buttons = {}
var awaiting = ""
var rain = []

func _ready():
    MusicManager.play_menu_music()
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mono = SystemFont.new()
    mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Liberation Mono", "Monospace", "Courier New"])

    var bg = ColorRect.new()
    bg.color = Color(0.01, 0.03, 0.02)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_rain()

    var center = CenterContainer.new()
    add_child(center)
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var box = VBoxContainer.new()
    box.add_theme_constant_override("separation", 14)
    center.add_child(box)

    title_box = VBoxContainer.new()
    box.add_child(title_box)
    var title = _lab("ASHEN", 120, Color(0.45, 1.0, 0.65), true)
    title.add_theme_font_override("font", mono)
    title.add_theme_constant_override("outline_size", 10)
    title.add_theme_color_override("font_outline_color", Color(0, 0.1, 0.05))
    title_box.add_child(title)
    title_box.add_child(_lab("a gothic soulslike drawn in ASCII", 20, Color(0.6, 0.85, 0.7), true))

    pages["main"] = _page_main()
    pages["levels"] = _page_levels()
    pages["controls"] = _page_controls()
    for k in pages:
        box.add_child(pages[k])
    _show("main")

# ------------------------------------------------------------ helpers
func _lab(text, size, col = Color.WHITE, centered = false):
    var l = Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", col)
    if centered:
        l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    return l

func _btn(text, cb, w = 360.0):
    var b = Button.new()
    b.text = text
    b.custom_minimum_size = Vector2(w, 46)
    b.add_theme_font_size_override("font_size", 22)
    b.pressed.connect(cb)
    return b

func _page():
    var v = VBoxContainer.new()
    v.add_theme_constant_override("separation", 12)
    v.alignment = BoxContainer.ALIGNMENT_CENTER
    return v

func _show(name_):
    awaiting = ""
    for k in pages:
        pages[k].visible = (k == name_)
    title_box.visible = (name_ == "main")
    _refresh_bind_buttons()

func _build_rain():
    for i in range(48):
        var txt = ""
        for j in range(22):
            txt += RAIN_CHARS[randi() % RAIN_CHARS.length()] + "\n"
        var l = Label.new()
        l.text = txt.strip_edges()
        l.add_theme_font_override("font", mono)
        l.add_theme_font_size_override("font_size", 16)
        l.modulate = Color(0.2, 1.0, 0.5, randf_range(0.07, 0.2))
        l.mouse_filter = Control.MOUSE_FILTER_IGNORE
        l.position = Vector2(i * 27.0, randf_range(-400.0, 700.0))
        add_child(l)
        rain.append([l, randf_range(25.0, 90.0)])

func _process(delta):
    var h = get_viewport_rect().size.y
    for r in rain:
        r[0].position.y += r[1] * delta
        if r[0].position.y > h:
            r[0].position.y = -430.0

# ------------------------------------------------------------ pages
func _page_main():
    var p = _page()
    p.add_child(_btn("START GAME  (Level I)", _start_level.bind(0)))
    p.add_child(_btn("SELECT LEVEL", _show.bind("levels")))
    p.add_child(_btn("CONTROLS", _show.bind("controls")))
    p.add_child(_btn("QUIT", _quit))
    return p

func _page_levels():
    var p = _page()
    p.add_child(_lab("SELECT LEVEL", 40, Color(0.5, 1.0, 0.7), true))
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 18)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    p.add_child(row)
    for i in range(GameState.LEVELS.size()):
        var cfg = GameState.LEVELS[i]
        var panel = PanelContainer.new()
        panel.custom_minimum_size = Vector2(320, 300)
        row.add_child(panel)
        var v = VBoxContainer.new()
        v.add_theme_constant_override("separation", 8)
        panel.add_child(v)
        var t = _lab(cfg["title"], 19, cfg["accent"])
        t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        t.custom_minimum_size = Vector2(290, 0)
        v.add_child(t)
        v.add_child(_lab("Boss: " + cfg["boss_name"], 17, Color(1.0, 0.85, 0.5)))
        var d = _lab(cfg["desc"], 15, Color(0.85, 0.9, 0.9))
        d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        d.custom_minimum_size = Vector2(290, 0)
        v.add_child(d)
        v.add_child(_lab("Swarm: %d    Boss HP: %d" % [cfg["minions"], int(cfg["boss_hp"])], 15))
        v.add_child(_lab("Difficulty: " + "#".repeat(cfg["difficulty"]), 16, Color(1.0, 0.5, 0.4)))
        v.add_child(_btn("ENTER", _start_level.bind(i), 290.0))
    p.add_child(_btn("BACK", _show.bind("main")))
    return p

func _page_controls():
    var p = _page()
    p.add_child(_lab("CONTROLS", 40, Color(0.5, 1.0, 0.7), true))
    p.add_child(_lab("Click a key box, then press the new key (Esc cancels).", 15, Color(0.8, 0.9, 0.85), true))

    var scroll = ScrollContainer.new()
    scroll.custom_minimum_size = Vector2(700, 300)
    p.add_child(scroll)
    var list = VBoxContainer.new()
    list.add_theme_constant_override("separation", 6)
    scroll.add_child(list)
    for entry in GameState.ACTION_LABELS:
        var row = HBoxContainer.new()
        row.add_theme_constant_override("separation", 12)
        list.add_child(row)
        var l = _lab(entry[1], 18)
        l.custom_minimum_size = Vector2(320, 0)
        row.add_child(l)
        var b = Button.new()
        b.custom_minimum_size = Vector2(240, 36)
        b.add_theme_font_size_override("font_size", 17)
        b.pressed.connect(_begin_rebind.bind(entry[0]))
        row.add_child(b)
        bind_buttons[entry[0]] = b
    list.add_child(_lab("Fixed keys:  1 / 2 / 3 pick spell    Esc pause    R restart level    N next level", 15, Color(0.7, 0.85, 0.8)))

    p.add_child(_slider_row("Mouse camera sensitivity", 0.3, 2.5, GameState.settings["mouse_sens"], _on_mouse_sens))
    p.add_child(_slider_row("Keyboard camera speed (Q / E)", 0.5, 2.5, GameState.settings["cam_speed"], _on_cam_speed))
    var inv = CheckBox.new()
    inv.text = "Invert mouse camera drag"
    inv.button_pressed = GameState.settings["invert_cam"]
    inv.toggled.connect(_on_invert)
    p.add_child(inv)

    var btns = HBoxContainer.new()
    btns.add_theme_constant_override("separation", 14)
    btns.alignment = BoxContainer.ALIGNMENT_CENTER
    btns.add_child(_btn("RESET DEFAULTS", _reset, 240.0))
    btns.add_child(_btn("BACK", _show.bind("main"), 240.0))
    p.add_child(btns)
    return p

func _slider_row(text, lo, hi, val, cb):
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    var l = _lab(text, 18)
    l.custom_minimum_size = Vector2(320, 0)
    row.add_child(l)
    var s = HSlider.new()
    s.min_value = lo
    s.max_value = hi
    s.step = 0.05
    s.value = val
    s.custom_minimum_size = Vector2(300, 24)
    s.value_changed.connect(cb)
    row.add_child(s)
    return row

# ------------------------------------------------------------ actions
func _start_level(i):
    GameState.start_level(i)

func _quit():
    get_tree().quit()

func _on_mouse_sens(v):
    GameState.settings["mouse_sens"] = v
    GameState.save_settings()

func _on_cam_speed(v):
    GameState.settings["cam_speed"] = v
    GameState.save_settings()

func _on_invert(on):
    GameState.settings["invert_cam"] = on
    GameState.save_settings()

func _reset():
    GameState.reset_defaults()
    # rebuild the controls page so sliders show the defaults
    var old = pages["controls"]
    var parent = old.get_parent()
    var idx = old.get_index()
    parent.remove_child(old)
    old.queue_free()
    bind_buttons.clear()
    pages["controls"] = _page_controls()
    parent.add_child(pages["controls"])
    parent.move_child(pages["controls"], idx)
    _show("controls")

func _refresh_bind_buttons():
    for a in bind_buttons:
        bind_buttons[a].text = GameState.binding_text(a)

func _begin_rebind(action):
    awaiting = action
    _refresh_bind_buttons()
    bind_buttons[action].text = "Press a key..."

func _input(event):
    if awaiting == "":
        return
    if event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode != KEY_ESCAPE:
            GameState.rebind(awaiting, event)
        awaiting = ""
        _refresh_bind_buttons()
        get_viewport().set_input_as_handled()
    elif event is InputEventMouseButton and event.pressed and event.button_index != MOUSE_BUTTON_LEFT:
        GameState.rebind(awaiting, event)
        awaiting = ""
        _refresh_bind_buttons()
        get_viewport().set_input_as_handled()
