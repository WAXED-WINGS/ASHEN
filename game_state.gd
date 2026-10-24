extends Node

# Global data: levels, saved settings and (re-bindable) key bindings.
# The arenas themselves are built in world.gd.

const SETTINGS_PATH = "user://ashen_settings.cfg"

# [action, label shown in the Controls menu]
const ACTION_LABELS = [
    ["move_forward", "Move forward"],
    ["move_back", "Move back"],
    ["move_left", "Move left"],
    ["move_right", "Move right"],
    ["attack", "Light attack / combo"],
    ["heavy_attack", "Heavy attack"],
    ["spin_attack", "Spin attack"],
    ["dodge", "Dodge roll"],
    ["heal", "Use healing flask"],
    ["magic_cast", "Cast spell"],
    ["spell_cycle", "Switch spell"],
    ["lock_on", "Lock-on target"],
    ["cam_left", "Camera left / previous target"],
    ["cam_right", "Camera right / next target"]
]

var level_index = 0
var settings = {"mouse_sens": 1.0, "cam_speed": 1.0, "invert_cam": false}
var bindings = {}

var LEVELS = [
    {
        "title": "LEVEL I - THE OVERGROWN COURTYARD",
        "boss_name": "The Hollow Warden",
        "desc": "A ruined castle courtyard drowned in tall grass. Dark ponds, fireflies and a hollow knight guarding the gate.",
        "difficulty": 1,
        "ambient": Color(0.2, 0.36, 0.26), "fog": Color(0.04, 0.12, 0.08),
        "light": Color(0.7, 0.95, 0.8), "accent": Color(0.55, 1.0, 0.45),
        "minion_kind": "ghoul", "boss_kind": "warden",
        "minion_color": Color(0.5, 0.75, 0.3), "boss_color": Color(0.85, 0.85, 0.35),
        "minion_scale": 1.0, "boss_scale": 2.4,
        "minions": 6, "minion_hp": 4.0, "minion_speed": 3.0, "minion_damage": 8.0,
        "boss_hp": 30.0, "boss_speed": 2.4, "boss_damage": 20.0
    },
    {
        "title": "LEVEL II - THE SUNKEN VAULT",
        "boss_name": "The Drowned Sovereign",
        "desc": "A flooded crypt hall of colonnades and glowing crystals. Something drowned waits on the altar.",
        "difficulty": 2,
        "ambient": Color(0.14, 0.3, 0.46), "fog": Color(0.02, 0.07, 0.14),
        "light": Color(0.6, 0.85, 1.0), "accent": Color(0.25, 0.85, 1.0),
        "minion_kind": "drowned", "boss_kind": "sovereign",
        "minion_color": Color(0.5, 0.85, 0.85), "boss_color": Color(0.6, 0.5, 1.0),
        "minion_scale": 1.1, "boss_scale": 2.4,
        "minions": 10, "minion_hp": 6.0, "minion_speed": 3.8, "minion_damage": 10.0,
        "boss_hp": 50.0, "boss_speed": 3.0, "boss_damage": 25.0
    },
    {
        "title": "LEVEL III - THE ABYSSAL CORE",
        "boss_name": "Ashfang, the Ember Dragon",
        "desc": "A circular obsidian cathedral ringed with lava. An ember dragon nests at the throne.",
        "difficulty": 3,
        "ambient": Color(0.42, 0.17, 0.12), "fog": Color(0.13, 0.03, 0.02),
        "light": Color(1.0, 0.65, 0.45), "accent": Color(1.0, 0.45, 0.1),
        "minion_kind": "imp", "boss_kind": "dragon",
        "minion_color": Color(0.9, 0.4, 0.15), "boss_color": Color(0.8, 0.2, 0.1),
        "minion_scale": 0.85, "boss_scale": 1.0,
        "minions": 15, "minion_hp": 8.0, "minion_speed": 4.4, "minion_damage": 12.0,
        "boss_hp": 90.0, "boss_speed": 3.6, "boss_damage": 28.0
    }
]

func _k(code):
    return {"t": "k", "c": code}

func _m(btn):
    return {"t": "m", "c": btn}

func _defaults():
    return {
        "move_forward": [_k(KEY_W), _k(KEY_UP)],
        "move_back": [_k(KEY_S), _k(KEY_DOWN)],
        "move_left": [_k(KEY_A), _k(KEY_LEFT)],
        "move_right": [_k(KEY_D), _k(KEY_RIGHT)],
        "attack": [_k(KEY_SPACE), _k(KEY_J), _m(MOUSE_BUTTON_LEFT)],
        "heavy_attack": [_k(KEY_H)],
        "spin_attack": [_k(KEY_C)],
        "dodge": [_k(KEY_SHIFT), _k(KEY_K)],
        "heal": [_k(KEY_F)],
        "magic_cast": [_k(KEY_X)],
        "spell_cycle": [_k(KEY_Z)],
        "lock_on": [_k(KEY_TAB), _m(MOUSE_BUTTON_MIDDLE)],
        "cam_left": [_k(KEY_Q)],
        "cam_right": [_k(KEY_E)],
        "restart": [_k(KEY_R)],
        "skip_level": [_k(KEY_N)],
        "pause": [_k(KEY_ESCAPE)],
        "spell_1": [_k(KEY_1)],
        "spell_2": [_k(KEY_2)],
        "spell_3": [_k(KEY_3)]
    }

func _ready():
    bindings = _defaults()
    _load_settings()
    _apply_all()

func _make_event(entry):
    if entry["t"] == "k":
        var ev = InputEventKey.new()
        ev.physical_keycode = int(entry["c"])
        return ev
    var mb = InputEventMouseButton.new()
    mb.button_index = int(entry["c"])
    return mb

func _apply_all():
    for action in bindings:
        if not InputMap.has_action(action):
            InputMap.add_action(action)
        InputMap.action_erase_events(action)
        for entry in bindings[action]:
            InputMap.action_add_event(action, _make_event(entry))

func _entry_name(entry):
    if entry["t"] == "k":
        return OS.get_keycode_string(int(entry["c"]))
    var names = {1: "Left Click", 2: "Right Click", 3: "Middle Click"}
    var b = int(entry["c"])
    if names.has(b):
        return names[b]
    return "Mouse " + str(b)

func binding_text(action):
    var parts = PackedStringArray()
    for entry in bindings[action]:
        parts.append(_entry_name(entry))
    return " / ".join(parts)

func rebind(action, event):
    var entry = null
    if event is InputEventKey:
        entry = _k(event.physical_keycode)
    elif event is InputEventMouseButton:
        entry = _m(event.button_index)
    if entry == null:
        return
    var old_primary = null
    if bindings[action].size() > 0:
        old_primary = bindings[action][0]
    # if another action already uses this input, give it our old binding (swap)
    for other in bindings.keys():
        if other == action:
            continue
        var found = null
        for e in bindings[other]:
            if e["t"] == entry["t"] and int(e["c"]) == int(entry["c"]):
                found = e
        if found != null:
            bindings[other].erase(found)
            if old_primary != null:
                bindings[other].append(old_primary)
    bindings[action] = [entry]
    _apply_all()
    save_settings()

func reset_defaults():
    bindings = _defaults()
    settings = {"mouse_sens": 1.0, "cam_speed": 1.0, "invert_cam": false}
    _apply_all()
    save_settings()

func save_settings():
    var cf = ConfigFile.new()
    for k in settings:
        cf.set_value("settings", k, settings[k])
    for a in bindings:
        cf.set_value("bindings", a, bindings[a])
    cf.save(SETTINGS_PATH)

func _load_settings():
    var cf = ConfigFile.new()
    if cf.load(SETTINGS_PATH) != OK:
        return
    for k in settings.keys():
        settings[k] = cf.get_value("settings", k, settings[k])
    for a in bindings.keys():
        var v = cf.get_value("bindings", a, null)
        if v is Array and v.size() > 0:
            var ok = true
            for e in v:
                if not (e is Dictionary and e.has("t") and e.has("c")):
                    ok = false
            if ok:
                bindings[a] = v

func current():
    return LEVELS[level_index]

func start_level(i):
    level_index = i
    get_tree().paused = false
    get_tree().change_scene_to_file("res://main.tscn")

func go_menu():
    get_tree().paused = false
    get_tree().change_scene_to_file("res://menu.tscn")
