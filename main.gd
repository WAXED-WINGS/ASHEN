extends Node3D

# Game flow: builds the level via world.gd, spawns the swarm and boss,
# runs the orbit camera, the ASCII overlay and the HUD.

const EnemyScript = preload("res://scripts/enemy.gd")
const PlayerScript = preload("res://scripts/player.gd")
const WorldScript = preload("res://scripts/world.gd")
const AsciiShader = preload("res://shaders/ascii_post.gdshader")
const PickupScript = preload("res://scripts/pickup.gd")
const PauseScript = preload("res://scripts/pause_menu.gd")

const CAM_HEIGHT = 8.5
const CAM_DIST = 9.5

var cfg
var world
var player
var boss = null
var camera
var phase = "swarm"   # swarm -> boss -> cleared / dead / victory
var minions_alive = 0
var cam_yaw = 0.0
var lock_target = null
var lock_marker
var mana_fg
var spell_label
var toast_label
var toast_t = 0.0
var shake = 0.0
var rng = RandomNumberGenerator.new()

var hp_fg
var st_fg
var flask_label
var obj_label
var name_tag
var banner
var boss_box
var boss_fg
var banner_t = 0.0
var banner_sticky = false

func _ready():
    rng.randomize()
    cfg = GameState.current()
    world = WorldScript.new()
    add_child(world)
    world.build(GameState.level_index, cfg)
    _spawn_player()
    _spawn_swarm()
    _build_camera()
    _build_ascii_layer()
    _build_hud()
    _spawn_pickups()
    add_child(PauseScript.new())
    _show_banner(cfg["title"] + "\nSlay the swarm. Then face " + cfg["boss_name"] + ".", 4.5, false)

# ---------------------------------------------------------------- helpers
func _mat(c, emit = 0.0):
    var m = StandardMaterial3D.new()
    m.albedo_color = c
    if emit > 0.0:
        m.emission_enabled = true
        m.emission = c
        m.emission_energy_multiplier = emit
    return m

func _find_spot(min_player = 12.0):
    var zone = world.zone
    var ps = Vector2(world.player_spawn.x, world.player_spawn.z)
    var bs = Vector2(world.boss_spawn.x, world.boss_spawn.z)
    for tries in range(80):
        var p = Vector2(rng.randf_range(zone.position.x, zone.end.x), rng.randf_range(zone.position.y, zone.end.y))
        if p.distance_to(ps) < min_player:
            continue
        if p.distance_to(bs) < 5.0:
            continue
        if world.walkable(p, 1.5):
            return Vector3(p.x, 0.1, p.y)
    return Vector3(bs.x, 0.1, bs.y + 4.0)

# ---------------------------------------------------------------- actors
func _spawn_player():
    player = PlayerScript.new()
    player.position = world.player_spawn
    add_child(player)
    player.died.connect(_on_player_died)
    player.impact.connect(_on_impact)
    player.toast.connect(show_toast)

func _make_minion(pos):
    var e = EnemyScript.new()
    e.kind = cfg["minion_kind"]
    e.color = cfg["minion_color"]
    e.eye_color = cfg["accent"]
    e.scale_f = cfg["minion_scale"]
    e.max_hp = cfg["minion_hp"]
    e.speed = cfg["minion_speed"] * rng.randf_range(0.9, 1.15)
    e.damage = cfg["minion_damage"]
    e.aggro_range = 15.0
    if cfg["minion_kind"] == "imp":
        e.ranged = true
        e.attack_range = 13.0
        e.windup_time = 0.7
        e.cooldown = 2.2
    e.position = pos
    e.died.connect(_on_enemy_died)
    add_child(e)
    minions_alive += 1

func _spawn_swarm():
    for i in range(cfg["minions"]):
        _make_minion(_find_spot())

func _spawn_boss():
    phase = "boss"
    MusicManager.play_boss_music(GameState.level_index)
    var e = EnemyScript.new()
    e.is_boss = true
    e.kind = cfg["boss_kind"]
    e.color = cfg["boss_color"]
    e.eye_color = cfg["accent"]
    e.scale_f = cfg["boss_scale"]
    e.max_hp = cfg["boss_hp"]
    e.speed = cfg["boss_speed"]
    e.damage = cfg["boss_damage"]
    e.aggro_range = 500.0
    e.slam_radius = 5.2
    e.cooldown = {"warden": 1.3, "sovereign": 1.0, "dragon": 1.1}[cfg["boss_kind"]]
    e.position = world.boss_spawn
    e.died.connect(_on_enemy_died)
    e.summon_requested.connect(_on_boss_summon)
    add_child(e)
    boss = e
    lock_target = e
    _show_banner(cfg["boss_name"].to_upper() + "\nAWAKENS", 3.0, false)

func _on_boss_summon(pos):
    for i in range(3):
        var a = TAU * float(i) / 3.0
        var p = Vector3(pos.x, 0.1, pos.z) + Vector3(cos(a), 0.0, sin(a)) * 4.5
        if not world.walkable(Vector2(p.x, p.z), 0.5):
            p = _find_spot(6.0)
        _make_minion(p)
    _show_banner("THE BOSS CALLS ITS BROOD!", 2.0, false)

func _on_enemy_died(e):
    _burst(e.global_position, e.color)
    if e.is_boss:
        boss = null
        if GameState.level_index >= GameState.LEVELS.size() - 1:
            phase = "victory"
            _show_banner("ASHEN CONQUERED\nAll 3 levels cleared.\nR: play again     Esc: menu", 0.0, true)
        else:
            phase = "cleared"
            _show_banner("BOSS FELLED\nDescending deeper...", 3.0, false)
            await get_tree().create_timer(3.0).timeout
            GameState.level_index += 1
            get_tree().reload_current_scene()
    else:
        var roll = rng.randf()
        if roll < 0.07:
            _drop("flask", e.global_position)
        elif roll < 0.30:
            _drop("mana", e.global_position)
        minions_alive -= 1
        if minions_alive <= 0 and phase == "swarm":
            _spawn_boss()

func _drop(kind, pos):
    var pk = PickupScript.new()
    pk.kind = kind
    pk.position = Vector3(pos.x, 0.0, pos.z)
    add_child(pk)

func _spawn_pickups():
    var flasks = [3, 2, 2][GameState.level_index]
    for i in range(flasks):
        _drop("flask", _find_spot(6.0))
    for i in range(3):
        _drop("mana", _find_spot(6.0))

func show_toast(text):
    toast_label.text = text
    toast_label.visible = true
    toast_t = 2.0

func _on_impact(strength):
    shake = maxf(shake, strength)

func _on_player_died():
    phase = "dead"
    _show_banner("YOU DIED\nR: try again     Esc: menu", 0.0, true)

func _burst(pos, col):
    var p = CPUParticles3D.new()
    p.amount = 22
    p.lifetime = 0.8
    p.one_shot = true
    p.explosiveness = 1.0
    p.direction = Vector3.UP
    p.spread = 80.0
    p.initial_velocity_min = 3.0
    p.initial_velocity_max = 8.0
    p.gravity = Vector3(0, -12, 0)
    var bm = BoxMesh.new()
    bm.size = Vector3(0.25, 0.25, 0.25)
    bm.material = _mat(col, 2.5)
    p.mesh = bm
    add_child(p)
    p.global_position = pos + Vector3(0, 1.0, 0)
    p.emitting = true
    get_tree().create_timer(1.3).timeout.connect(p.queue_free)

# ---------------------------------------------------------------- camera + ascii overlay
func _has_lock():
    return lock_target != null and is_instance_valid(lock_target) and not lock_target.dying

func _acquire_target():
    var fwd = Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
    var best = null
    var best_score = 1000000.0
    for e in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(e) or e.dying:
            continue
        var to = e.global_position - player.global_position
        to.y = 0.0
        var d = to.length()
        if d > 32.0 or d < 0.1:
            continue
        var score = d + fwd.angle_to(to / d) * 8.0
        if score < best_score:
            best_score = score
            best = e
    return best

func _cycle_target(dir_sign):
    var fwd = Vector3(-sin(cam_yaw), 0.0, -cos(cam_yaw))
    var right = Vector3(cos(cam_yaw), 0.0, -sin(cam_yaw))
    var list = []
    for e in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(e) or e.dying:
            continue
        var to = e.global_position - player.global_position
        to.y = 0.0
        if to.length() > 32.0 or to.length() < 0.1:
            continue
        list.append([atan2(to.dot(right), to.dot(fwd)), e])
    if list.size() < 2:
        return
    list.sort_custom(func(a, b): return a[0] < b[0])
    var idx = 0
    for i in range(list.size()):
        if list[i][1] == lock_target:
            idx = i
    idx = clampi(idx + dir_sign, 0, list.size() - 1)
    lock_target = list[idx][1]

func _cam_target():
    var h = CAM_HEIGHT
    var dd = CAM_DIST
    if _has_lock():
        var tl = lock_target.global_position - player.global_position
        tl.y = 0.0
        h += clampf(tl.length() * 0.18, 0.0, 5.0)
        dd += clampf(tl.length() * 0.3, 0.0, 8.0)
    var off = Vector3(0, h, dd).rotated(Vector3.UP, cam_yaw)
    var p = player.global_position + off
    if world.bounds_kind == "rect":
        p.x = clampf(p.x, -world.bounds.x + 2.5, world.bounds.x - 2.5)
        p.z = clampf(p.z, -world.bounds.y + 2.5, world.bounds.y - 2.5)
    else:
        var v = Vector2(p.x, p.z)
        var lim = world.bounds.x - 3.0
        if v.length() > lim:
            v = v.normalized() * lim
            p.x = v.x
            p.z = v.y
    return p

func _aim_camera():
    var look = player.global_position + Vector3(0, 1.0, 0)
    if _has_lock():
        look = look.lerp(lock_target.global_position + Vector3(0, 1.5, 0), 0.4)
    var d = look - camera.global_position
    var up = Vector3.UP
    if Vector2(d.x, d.z).length() < 0.5:
        up = Vector3(0, 0, -1)
    camera.look_at(look, up)

func _build_camera():
    camera = Camera3D.new()
    camera.fov = 62.0
    camera.far = 300.0
    add_child(camera)
    camera.global_position = _cam_target()
    _aim_camera()

func _unhandled_input(event):
    if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
        cam_yaw -= event.relative.x * 0.006 * GameState.settings["mouse_sens"] * (-1.0 if GameState.settings["invert_cam"] else 1.0)

func _build_ascii_layer():
    var layer = CanvasLayer.new()
    layer.layer = 1
    add_child(layer)
    var rect = ColorRect.new()
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var sm = ShaderMaterial.new()
    sm.shader = AsciiShader
    var f = cfg["fog"]
    sm.set_shader_parameter("bg_tint", Vector3(f.r, f.g, f.b) * 0.6)
    rect.material = sm
    layer.add_child(rect)
    rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

# ---------------------------------------------------------------- HUD (plain text above the ASCII layer)
func _bar(parent, pos, size, col):
    var bg = ColorRect.new()
    bg.color = Color(0, 0, 0, 0.7)
    bg.position = pos - Vector2(3, 3)
    bg.size = size + Vector2(6, 6)
    parent.add_child(bg)
    var fg = ColorRect.new()
    fg.color = col
    fg.position = pos
    fg.size = size
    parent.add_child(fg)
    return fg

func _label(parent, text, pos, px, width = 0.0, centered = false):
    var l = Label.new()
    l.text = text
    l.position = pos
    l.add_theme_font_size_override("font_size", px)
    l.add_theme_color_override("font_color", Color.WHITE)
    l.add_theme_color_override("font_outline_color", Color.BLACK)
    l.add_theme_constant_override("outline_size", 6)
    if width > 0.0:
        l.custom_minimum_size = Vector2(width, 0)
    if centered:
        l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    parent.add_child(l)
    return l

func _build_hud():
    var hl = CanvasLayer.new()
    hl.layer = 2
    add_child(hl)
    var root = Control.new()
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hl.add_child(root)
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    hp_fg = _bar(root, Vector2(24, 24), Vector2(300, 16), Color(0.85, 0.1, 0.15))
    _label(root, "HEALTH", Vector2(334, 17), 16)
    st_fg = _bar(root, Vector2(24, 52), Vector2(300, 12), Color(0.3, 0.9, 0.4))
    _label(root, "STAMINA", Vector2(334, 44), 16)
    mana_fg = _bar(root, Vector2(24, 74), Vector2(300, 12), Color(0.25, 0.5, 1.0))
    _label(root, "MANA", Vector2(334, 66), 16)
    flask_label = _label(root, "", Vector2(24, 96), 18)
    spell_label = _label(root, "", Vector2(24, 120), 18)
    toast_label = _label(root, "", Vector2(24, 150), 20)
    toast_label.visible = false

    var top = Control.new()
    top.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(top)
    top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
    _label(top, cfg["title"], Vector2(-400, 12), 24, 800.0, true)
    obj_label = _label(top, "", Vector2(-400, 46), 20, 800.0, true)

    boss_box = Control.new()
    boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(boss_box)
    boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
    _label(boss_box, cfg["boss_name"], Vector2(-300, -118), 22, 600.0, true)
    boss_fg = _bar(boss_box, Vector2(-300, -80), Vector2(600, 16), Color(0.9, 0.7, 0.1))
    boss_box.visible = false

    var bl = Control.new()
    bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(bl)
    bl.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
    _label(bl, "WASD move   SPACE combo   H heavy   C spin   SHIFT dodge (SPACE right after = lunge)\nF flask   X cast spell   Z switch spell   TAB lock-on   Q/E camera   Esc pause", Vector2(20, -62), 15)

    name_tag = _label(root, "Wanderer", Vector2(0, 0), 16, 200.0, true)

    lock_marker = ColorRect.new()
    lock_marker.color = Color(1.0, 0.2, 0.2, 0.95)
    lock_marker.size = Vector2(14, 14)
    lock_marker.pivot_offset = Vector2(7, 7)
    lock_marker.rotation = PI / 4.0
    lock_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
    lock_marker.visible = false
    root.add_child(lock_marker)

    banner = Label.new()
    banner.add_theme_font_size_override("font_size", 52)
    banner.add_theme_color_override("font_color", Color.WHITE)
    banner.add_theme_color_override("font_outline_color", Color.BLACK)
    banner.add_theme_constant_override("outline_size", 10)
    banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(banner)
    banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    banner.visible = false

func _show_banner(text, dur, sticky):
    banner.text = text
    banner_t = dur
    banner_sticky = sticky
    banner.visible = true

# ---------------------------------------------------------------- per frame
func _process(delta):
    if Input.is_action_just_pressed("restart"):
        if phase == "victory":
            GameState.level_index = 0
        get_tree().reload_current_scene()
        return
    if Input.is_action_just_pressed("skip_level"):
        GameState.level_index = (GameState.level_index + 1) % GameState.LEVELS.size()
        get_tree().reload_current_scene()
        return

    world.tick(Time.get_ticks_msec() / 1000.0)

    var locked = _has_lock()
    if Input.is_action_just_pressed("lock_on"):
        if locked:
            lock_target = null
        else:
            lock_target = _acquire_target()
        locked = _has_lock()
    if locked:
        if Input.is_action_just_pressed("cam_left"):
            _cycle_target(-1)
        if Input.is_action_just_pressed("cam_right"):
            _cycle_target(1)
        var tl = lock_target.global_position - player.global_position
        tl.y = 0.0
        if tl.length() > 0.5:
            cam_yaw = lerp_angle(cam_yaw, atan2(-tl.x, -tl.z), clampf(7.0 * delta, 0.0, 1.0))
    else:
        lock_target = null
        if Input.is_action_pressed("cam_left"):
            cam_yaw -= 1.8 * delta * GameState.settings["cam_speed"]
        if Input.is_action_pressed("cam_right"):
            cam_yaw += 1.8 * delta * GameState.settings["cam_speed"]
    player.cam_yaw = cam_yaw
    player.lock_target = lock_target

    camera.global_position = camera.global_position.lerp(_cam_target(), clampf(8.0 * delta, 0.0, 1.0))
    _aim_camera()
    shake = move_toward(shake, 0.0, delta * 2.2)
    camera.h_offset = rng.randf_range(-1.0, 1.0) * shake * 0.5
    camera.v_offset = rng.randf_range(-1.0, 1.0) * shake * 0.5

    hp_fg.size.x = 300.0 * clampf(player.health / player.max_health, 0.0, 1.0)
    st_fg.size.x = 300.0 * clampf(player.stamina / player.max_stamina, 0.0, 1.0)
    mana_fg.size.x = 300.0 * clampf(player.mana / player.max_mana, 0.0, 1.0)
    flask_label.text = "Flasks [F]: %d / %d" % [player.flasks, player.MAX_FLASKS]
    var sp = player.SPELLS[player.spell_index]
    spell_label.text = "Spell [Z]: %s  (%d mana)  [X] cast" % [sp["name"], int(sp["cost"])]
    if toast_t > 0.0:
        toast_t -= delta
        if toast_t <= 0.0:
            toast_label.visible = false

    var tag_pos = player.global_position + Vector3(0, 2.8, 0)
    if camera.is_position_behind(tag_pos):
        name_tag.visible = false
    else:
        name_tag.visible = true
        name_tag.position = camera.unproject_position(tag_pos) - Vector2(100, 12)

    if locked and is_instance_valid(lock_target):
        var mp = lock_target.global_position + Vector3(0, lock_target.marker_height, 0)
        if camera.is_position_behind(mp):
            lock_marker.visible = false
        else:
            lock_marker.visible = true
            lock_marker.position = camera.unproject_position(mp) - Vector2(7, 7)
    else:
        lock_marker.visible = false

    if phase == "swarm":
        obj_label.text = "Swarm remaining: %d" % minions_alive
    elif phase == "boss":
        obj_label.text = "Defeat " + cfg["boss_name"]
    elif phase == "cleared":
        obj_label.text = "Level cleared!"
    elif phase == "dead":
        obj_label.text = ""

    if boss != null and is_instance_valid(boss):
        boss_box.visible = true
        boss_fg.size.x = 600.0 * clampf(boss.hp / boss.max_hp, 0.0, 1.0)
    else:
        boss_box.visible = false

    if banner_t > 0.0:
        banner_t -= delta
    banner.visible = banner_sticky or banner_t > 0.0
