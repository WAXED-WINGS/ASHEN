extends CharacterBody3D

signal died
signal impact(strength)
signal toast(text)

const Fx = preload("res://scripts/fx.gd")
const ProjectileScript = preload("res://scripts/projectile.gd")

const SPEED = 7.0
const GRAVITY = 25.0
const DASH_SPEED = 18.0
const DASH_TIME = 0.22
const ATTACK_RANGE = 3.2
const MAX_FLASKS = 5

# sword moves: timings, damage, reach, arc (dot), stamina cost, knockback, lunge speed, move slowdown
const MOVES = {
    "light1": {"wind": 0.12, "act": 0.10, "rec": 0.24, "dmg": 2.0, "range": 3.2, "dot": 0.2, "cost": 10.0, "kb": 1.0, "lunge": 0.0, "slow": 0.35},
    "light2": {"wind": 0.10, "act": 0.10, "rec": 0.24, "dmg": 2.0, "range": 3.2, "dot": 0.2, "cost": 10.0, "kb": 1.0, "lunge": 0.0, "slow": 0.35},
    "light3": {"wind": 0.20, "act": 0.12, "rec": 0.40, "dmg": 3.5, "range": 3.5, "dot": 0.2, "cost": 14.0, "kb": 1.8, "lunge": 7.0, "slow": 0.2},
    "heavy": {"wind": 0.55, "act": 0.12, "rec": 0.50, "dmg": 6.0, "range": 3.8, "dot": 0.0, "cost": 30.0, "kb": 2.5, "lunge": 3.0, "slow": 0.2},
    "spin": {"wind": 0.15, "act": 0.55, "rec": 0.35, "dmg": 2.5, "range": 3.6, "dot": -1.0, "cost": 35.0, "kb": 1.5, "lunge": 0.0, "slow": 0.5},
    "lunge": {"wind": 0.12, "act": 0.12, "rec": 0.35, "dmg": 3.5, "range": 4.6, "dot": 0.6, "cost": 15.0, "kb": 1.4, "lunge": 14.0, "slow": 0.2}
}

# body poses [arm pitch, body twist, lean, forward offset]: wind-up, strike, end
const POSES = {
    "light1": [[0.4, -0.9, 0.0, 0.0], [0.1, 0.9, -0.1, 0.0], [0.0, 0.0, 0.0, 0.0]],
    "light2": [[0.4, 0.9, 0.0, 0.0], [0.1, -0.9, -0.1, 0.0], [0.0, 0.0, 0.0, 0.0]],
    "light3": [[-2.4, 0.0, 0.2, 0.0], [1.3, 0.0, -0.5, -0.3], [0.0, 0.0, 0.0, 0.0]],
    "heavy": [[-2.9, 0.0, 0.35, 0.1], [1.5, 0.0, -0.6, -0.4], [0.0, 0.0, 0.0, 0.0]],
    "spin": [[0.6, -0.4, -0.1, 0.0], [0.6, 6.28, -0.15, 0.0], [0.0, 6.28, 0.0, 0.0]],
    "lunge": [[0.3, 0.0, 0.1, 0.2], [0.0, 0.0, -0.55, -0.7], [0.0, 0.0, 0.0, 0.0]]
}

var SPELLS = [
    {"name": "Arcane Bolt", "cost": 15.0, "color": Color(0.35, 0.65, 1.0)},
    {"name": "Flame Burst", "cost": 25.0, "color": Color(1.0, 0.5, 0.12)},
    {"name": "Frost Nova", "cost": 35.0, "color": Color(0.65, 0.92, 1.0)}
]

var max_health = 100.0
var health = 100.0
var max_stamina = 100.0
var stamina = 100.0
var flasks = 3
var damage = 2.0
var dead = false
var facing = Vector3(0, 0, -1)
var cam_yaw = 0.0
var attack_cd = 0.0
var dash_t = 0.0
var dash_dir = Vector3.ZERO
var invuln = 0.0
var flash_t = 0.0
var slash_t = 0.0
var swing_t = 0.0
var anim_t = 0.0
var base_color = Color(0.5, 0.05, 0.09)
var pivot
var visual
var arm_r
var arm_l
var cloak
var mat
var slash
var sword_tip
var sword_light
var lock_target = null
var ring_fx
var thrust_fx
var mana = 100.0
var max_mana = 100.0
var spell_index = 0
var cast_cd = 0.0
var cast_t = 0.0
var mana_delay = 0.0
var drink_t = 0.0
var heal_flash_t = 0.0
var atk = ""
var atk_t = 0.0
var atk_dir = Vector3(0, 0, -1)
var next_hit = 0
var hit_times = []
var combo = 0
var combo_t = 0.0
var post_dash_t = 0.0

func _plain(c, rough = 0.9):
    var m = StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = rough
    return m

func _glow(c, e = 3.0):
    var m = StandardMaterial3D.new()
    m.albedo_color = c
    m.emission_enabled = true
    m.emission = c
    m.emission_energy_multiplier = e
    return m

func _part(parent, mesh, material, pos, rot = Vector3.ZERO):
    var mi = MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = material
    mi.position = pos
    mi.rotation_degrees = rot
    parent.add_child(mi)
    return mi

func _box(x, y, z):
    var b = BoxMesh.new()
    b.size = Vector3(x, y, z)
    return b

func _cyl(rt, rb, h, seg = 10):
    var c = CylinderMesh.new()
    c.top_radius = rt
    c.bottom_radius = rb
    c.height = h
    c.radial_segments = seg
    c.rings = 1
    return c

func _sph(r):
    var s = SphereMesh.new()
    s.radius = r
    s.height = r * 2.0
    s.radial_segments = 10
    s.rings = 6
    return s

func _ready():
    add_to_group("player")
    collision_layer = 2
    collision_mask = 1 | 4

    var cs = CollisionShape3D.new()
    var cap = CapsuleShape3D.new()
    cap.radius = 0.45
    cap.height = 1.8
    cs.shape = cap
    cs.position.y = 0.9
    add_child(cs)

    mat = _plain(base_color, 0.8)
    mat.emission_enabled = true
    mat.emission = base_color
    mat.emission_energy_multiplier = 0.5
    var dark = _plain(Color(0.07, 0.03, 0.05))
    var steel = _glow(Color(0.9, 0.92, 1.0), 2.0)
    var eyes = _glow(Color(1.0, 0.3, 0.2), 4.0)

    pivot = Node3D.new()
    add_child(pivot)
    visual = Node3D.new()
    pivot.add_child(visual)

    # hooded cloak
    cloak = _part(visual, _cyl(0.26, 0.62, 1.55, 12), mat, Vector3(0, 0.78, 0))
    _part(visual, _cyl(0.63, 0.66, 0.1, 12), _glow(Color(0.9, 0.1, 0.15), 1.6), Vector3(0, 0.07, 0))
    _part(visual, _cyl(0.28, 0.3, 0.12, 10), dark, Vector3(0, 1.45, 0))
    _part(visual, _sph(0.3), dark, Vector3(0, 1.68, 0.02))
    _part(visual, _cyl(0.0, 0.34, 0.55, 8), dark, Vector3(0, 1.98, 0.14), Vector3(18, 0, 0))
    _part(visual, _box(0.26, 0.07, 0.06), eyes, Vector3(0, 1.68, -0.27))
    _part(visual, _box(0.7, 1.2, 0.08), dark, Vector3(0, 0.95, 0.34))

    # arms: right holds the sword, left holds a lantern
    arm_r = Node3D.new()
    arm_r.position = Vector3(0.38, 1.35, 0)
    visual.add_child(arm_r)
    _part(arm_r, _box(0.16, 0.7, 0.16), mat, Vector3(0, -0.35, 0))
    _build_sword(arm_r)

    arm_l = Node3D.new()
    arm_l.position = Vector3(-0.38, 1.35, 0)
    visual.add_child(arm_l)
    _part(arm_l, _box(0.16, 0.7, 0.16), mat, Vector3(0, -0.35, 0))
    _part(arm_l, _box(0.22, 0.28, 0.22), _glow(Color(1.0, 0.6, 0.25), 3.5), Vector3(0, -0.8, -0.2))

    slash = MeshInstance3D.new()
    var slm = BoxMesh.new()
    slm.size = Vector3(3.2, 0.08, 2.2)
    slash.mesh = slm
    slash.material_override = steel
    slash.position = Vector3(0, 0.9, -1.7)
    slash.visible = false
    pivot.add_child(slash)

    var ring_t = TorusMesh.new()
    ring_t.inner_radius = 2.9
    ring_t.outer_radius = 3.4
    ring_t.rings = 40
    ring_t.ring_segments = 4
    ring_fx = MeshInstance3D.new()
    ring_fx.mesh = ring_t
    ring_fx.material_override = steel
    ring_fx.position = Vector3(0, 0.9, 0)
    ring_fx.scale = Vector3(1, 0.25, 1)
    ring_fx.visible = false
    pivot.add_child(ring_fx)

    thrust_fx = MeshInstance3D.new()
    var thm = BoxMesh.new()
    thm.size = Vector3(0.3, 0.3, 4.6)
    thrust_fx.mesh = thm
    thrust_fx.material_override = steel
    thrust_fx.position = Vector3(0, 1.0, -2.6)
    thrust_fx.visible = false
    pivot.add_child(thrust_fx)

    var torch = OmniLight3D.new()
    torch.omni_range = 12.0
    torch.light_energy = 1.7
    torch.light_color = Color(1.0, 0.75, 0.5)
    torch.position = Vector3(0, 2.6, 0)
    add_child(torch)

func _build_sword(arm):
    var sw = Node3D.new()
    sw.position = Vector3(0, -0.7, -0.05)
    arm.add_child(sw)
    var steel = StandardMaterial3D.new()
    steel.albedo_color = Color(0.82, 0.86, 0.93)
    steel.metallic = 0.9
    steel.roughness = 0.25
    steel.emission_enabled = true
    steel.emission = Color(0.5, 0.6, 0.8)
    steel.emission_energy_multiplier = 0.45
    var edge = _glow(Color(1.0, 1.0, 1.0), 1.3)
    var gold = StandardMaterial3D.new()
    gold.albedo_color = Color(0.95, 0.72, 0.25)
    gold.metallic = 0.9
    gold.roughness = 0.35
    gold.emission_enabled = true
    gold.emission = Color(0.9, 0.6, 0.15)
    gold.emission_energy_multiplier = 0.4
    var leather = _plain(Color(0.14, 0.06, 0.05))
    var dark_steel = _plain(Color(0.2, 0.22, 0.28), 0.5)
    var rune = _glow(Color(1.0, 0.25, 0.2), 4.5)

    # grip with leather wraps and a glowing pommel
    _part(sw, _cyl(0.04, 0.04, 0.34, 8), leather, Vector3(0, 0, 0.0), Vector3(90, 0, 0))
    for i in range(5):
        _part(sw, _cyl(0.052, 0.052, 0.022, 8), dark_steel, Vector3(0, 0, 0.12 - i * 0.06), Vector3(90, 0, 0))
    _part(sw, _sph(0.075), gold, Vector3(0, 0, 0.21))
    _part(sw, _sph(0.036), rune, Vector3(0, 0, 0.26))

    # ornate crossguard: swept wings, tip spheres and a jewel
    _part(sw, _box(0.5, 0.07, 0.07), gold, Vector3(0, 0, -0.2))
    for s in [-1.0, 1.0]:
        _part(sw, _box(0.16, 0.06, 0.07), gold, Vector3(s * 0.3, 0, -0.17), Vector3(0, s * 28.0, 0))
        _part(sw, _sph(0.045), gold, Vector3(s * 0.38, 0, -0.14))
        _part(sw, _box(0.05, 0.16, 0.05), dark_steel, Vector3(s * 0.12, 0, -0.2))
    _part(sw, _box(0.09, 0.1, 0.05), rune, Vector3(0, 0, -0.235))

    # ricasso and blade with bevelled edges, fuller groove, runes and nicks
    _part(sw, _box(0.12, 0.05, 0.12), dark_steel, Vector3(0, 0, -0.3))
    _part(sw, _box(0.13, 0.035, 1.1), steel, Vector3(0, 0, -0.9))
    for s in [-1.0, 1.0]:
        _part(sw, _box(0.024, 0.04, 1.1), edge, Vector3(s * 0.0725, 0, -0.9))
    _part(sw, _box(0.04, 0.04, 0.85), dark_steel, Vector3(0, 0.003, -0.86))
    for i in range(6):
        _part(sw, _box(0.05, 0.047, 0.03), rune, Vector3(0, 0, -0.55 - i * 0.14))
    for i in range(4):
        _part(sw, _box(0.03, 0.045, 0.04), dark_steel, Vector3(0.068, 0, -0.7 - i * 0.22))
    for i in range(3):
        _part(sw, _box(0.03, 0.045, 0.04), dark_steel, Vector3(-0.068, 0, -0.62 - i * 0.28))
    var tip = _part(sw, _cyl(0.0, 0.092, 0.3, 4), steel, Vector3(0, 0, -1.6), Vector3(-90, 0, 0))
    tip.scale = Vector3(1.0, 1.0, 0.38)

    sword_light = OmniLight3D.new()
    sword_light.light_color = Color(1.0, 0.35, 0.25)
    sword_light.light_energy = 0.8
    sword_light.omni_range = 4.0
    sword_light.position = Vector3(0, 0.2, -0.9)
    sw.add_child(sword_light)

    sword_tip = Node3D.new()
    sword_tip.position = Vector3(0, 0, -1.75)
    sw.add_child(sword_tip)

func _physics_process(delta):
    if dead:
        velocity.x = 0.0
        velocity.z = 0.0
        velocity.y -= GRAVITY * delta
        move_and_slide()
        return

    invuln = maxf(0.0, invuln - delta)
    combo_t = maxf(0.0, combo_t - delta)
    cast_cd = maxf(0.0, cast_cd - delta)
    cast_t = maxf(0.0, cast_t - delta)
    post_dash_t = maxf(0.0, post_dash_t - delta)
    mana_delay = maxf(0.0, mana_delay - delta)
    heal_flash_t = maxf(0.0, heal_flash_t - delta)
    if mana_delay <= 0.0:
        mana = minf(max_mana, mana + 7.0 * delta)

    if slash_t > 0.0:
        slash_t -= delta
        if slash_t <= 0.0:
            slash.visible = false
            ring_fx.visible = false
            thrust_fx.visible = false

    if flash_t > 0.0:
        flash_t -= delta
        mat.albedo_color = Color.WHITE
    elif heal_flash_t > 0.0:
        mat.albedo_color = Color(0.6, 1.0, 0.7)
    else:
        mat.albedo_color = base_color

    if drink_t > 0.0:
        drink_t -= delta
        if drink_t <= 0.0:
            health = minf(max_health, health + 45.0)
            Fx.ring(get_parent(), global_position, Color(0.5, 1.0, 0.6), 2.6, 0.6)
            Fx.burst(get_parent(), global_position + Vector3(0, 1.0, 0), Color(0.7, 1.0, 0.6), 24, 5.0, 0.14)

    var input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
    var dir = Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, cam_yaw)

    var locked = lock_target != null and is_instance_valid(lock_target) and not lock_target.dying
    if locked:
        var tl = lock_target.global_position - global_position
        tl.y = 0.0
        if tl.length() > 0.1:
            facing = tl.normalized()

    var m = null
    if atk != "":
        m = MOVES[atk]

    if dash_t > 0.0:
        dash_t -= delta
        velocity.x = dash_dir.x * DASH_SPEED
        velocity.z = dash_dir.z * DASH_SPEED
        if dash_t <= 0.0:
            collision_mask = 1 | 4
            post_dash_t = 0.4
    else:
        if atk == "" and drink_t <= 0.0:
            stamina = minf(max_stamina, stamina + 24.0 * delta)
        var moving = dir.length() > 0.1
        if moving:
            dir = dir.normalized()
            if not locked and atk == "":
                facing = dir
        var spd = SPEED
        if m != null:
            spd *= m["slow"]
        if drink_t > 0.0:
            spd *= 0.5
        velocity.x = dir.x * spd
        velocity.z = dir.z * spd
        if m != null and m["lunge"] > 0.0:
            if atk_t >= m["wind"] * 0.6 and atk_t < m["wind"] + m["act"] + 0.1:
                velocity.x = atk_dir.x * m["lunge"]
                velocity.z = atk_dir.z * m["lunge"]
        _handle_actions(dir, moving, locked)

    _attack_tick(delta)

    if is_on_floor():
        velocity.y = 0.0
    else:
        velocity.y -= GRAVITY * delta

    move_and_slide()
    pivot.rotation.y = atan2(-facing.x, -facing.z)
    _animate(delta)

func _in_recovery():
    if atk == "":
        return false
    var m = MOVES[atk]
    return atk_t >= m["wind"] + m["act"]

func _peek_light():
    if combo_t <= 0.0:
        combo = 0
    return "light" + str(combo + 1)

func _handle_actions(dir, moving, locked):
    if drink_t > 0.0:
        return
    var free = atk == ""
    var rec = _in_recovery()

    if Input.is_action_just_pressed("dodge") and stamina >= 25.0 and (free or rec):
        stamina -= 25.0
        atk = ""
        if moving:
            dash_dir = dir
        elif locked:
            dash_dir = -facing
        else:
            dash_dir = facing
        dash_t = DASH_TIME
        invuln = DASH_TIME + 0.1
        collision_mask = 1
        return

    if Input.is_action_just_pressed("attack"):
        if post_dash_t > 0.0 and free and stamina >= MOVES["lunge"]["cost"]:
            _start_attack("lunge")
        elif free or (rec and (atk == "light1" or atk == "light2")):
            var k = _peek_light()
            if stamina >= MOVES[k]["cost"]:
                _start_attack(k)
    elif Input.is_action_just_pressed("heavy_attack") and free and stamina >= MOVES["heavy"]["cost"]:
        _start_attack("heavy")
    elif Input.is_action_just_pressed("spin_attack") and free and stamina >= MOVES["spin"]["cost"]:
        _start_attack("spin")
    elif Input.is_action_just_pressed("heal") and free:
        _use_flask()
    elif Input.is_action_just_pressed("magic_cast") and (free or rec):
        _cast()

    if Input.is_action_just_pressed("spell_cycle"):
        spell_index = (spell_index + 1) % SPELLS.size()
    if Input.is_action_just_pressed("spell_1"):
        spell_index = 0
    if Input.is_action_just_pressed("spell_2"):
        spell_index = 1
    if Input.is_action_just_pressed("spell_3"):
        spell_index = 2

# ------------------------------------------------------------ sword moves
func _start_attack(kind):
    var m = MOVES[kind]
    atk = kind
    atk_t = 0.0
    next_hit = 0
    atk_dir = facing
    stamina -= m["cost"]
    var total = m["wind"] + m["act"] + m["rec"]
    if kind.begins_with("light"):
        combo = int(kind.substr(5, 1)) % 3
        combo_t = total + 0.35
    else:
        combo_t = 0.0
    hit_times = [m["wind"]]
    if kind == "spin":
        hit_times = [m["wind"] + m["act"] * 0.2, m["wind"] + m["act"] * 0.65]

func _attack_tick(delta):
    if atk == "":
        return
    var m = MOVES[atk]
    atk_t += delta
    while next_hit < hit_times.size() and atk_t >= hit_times[next_hit]:
        _deal(m)
        next_hit += 1
    if atk_t >= m["wind"] + m["act"] + m["rec"]:
        atk = ""

func _deal(m):
    var hit_any = false
    for e in get_tree().get_nodes_in_group("enemies"):
        if not is_instance_valid(e) or e.dying:
            continue
        var to = e.global_position - global_position
        to.y = 0.0
        var dist = to.length()
        if dist > m["range"] + e.hit_radius:
            continue
        if m["dot"] <= -0.99 or dist < 1.0 or facing.dot(to / dist) > m["dot"]:
            e.hurt(m["dmg"], global_position, m["kb"])
            hit_any = true
            Fx.burst(get_parent(), e.global_position + Vector3(0, 1.2, 0), Color(1.0, 0.85, 0.6), 8, 5.0, 0.1)
    _show_swing()
    if hit_any:
        impact.emit(0.12 + m["dmg"] * 0.04)
    elif atk == "heavy":
        impact.emit(0.2)

func _show_swing():
    var par = get_parent()
    match atk:
        "light1":
            slash.rotation_degrees = Vector3(0, 28, 0)
            slash.scale = Vector3.ONE
            slash.visible = true
            slash_t = 0.12
        "light2":
            slash.rotation_degrees = Vector3(0, -28, 0)
            slash.scale = Vector3.ONE
            slash.visible = true
            slash_t = 0.12
        "light3":
            slash.rotation_degrees = Vector3(-30, 0, 0)
            slash.scale = Vector3(1.2, 1.0, 1.3)
            slash.visible = true
            slash_t = 0.15
        "spin":
            ring_fx.visible = true
            slash_t = 0.25
        "lunge":
            thrust_fx.visible = true
            slash_t = 0.15
        "heavy":
            Fx.ring(par, global_position + atk_dir * 2.4, Color(1.0, 0.85, 0.5), 4.2, 0.4)
            Fx.burst(par, global_position + atk_dir * 2.4 + Vector3(0, 0.3, 0), Color(1.0, 0.7, 0.3), 22, 7.0, 0.18)
    Fx.burst(par, sword_tip.global_position, Color(1.0, 0.8, 0.5), 10, 4.5, 0.12)

func _lerp_pose(a, b, k):
    var out = []
    for i in range(4):
        out.append(lerpf(a[i], b[i], k))
    return out

func _attack_pose():
    var m = MOVES[atk]
    var ps = POSES[atk]
    var w = m["wind"]
    var a = m["act"]
    var r = m["rec"]
    var neutral = [0.0, 0.0, 0.0, 0.0]
    if atk_t < w:
        return _lerp_pose(neutral, ps[0], smoothstep(0.0, 1.0, atk_t / w))
    if atk_t < w + a:
        return _lerp_pose(ps[0], ps[1], smoothstep(0.0, 1.0, (atk_t - w) / a))
    return _lerp_pose(ps[1], ps[2], smoothstep(0.0, 1.0, clampf((atk_t - w - a) / r, 0.0, 1.0)))

# ------------------------------------------------------------ flask and magic
func can_collect(kind):
    if kind == "flask":
        return flasks < MAX_FLASKS
    if kind == "mana":
        return mana < max_mana - 1.0
    return false

func collect(kind):
    if kind == "flask":
        flasks += 1
        toast.emit("+1 Flask  (%d)" % flasks)
    elif kind == "mana":
        mana = minf(max_mana, mana + 35.0)
        toast.emit("+ Mana")

func _use_flask():
    if flasks > 0 and health < max_health and drink_t <= 0.0:
        flasks -= 1
        drink_t = 0.5
        heal_flash_t = 0.9
        Fx.heal(self)

func _cast():
    var sp = SPELLS[spell_index]
    if mana < sp["cost"] or cast_cd > 0.0:
        return
    mana -= sp["cost"]
    mana_delay = 1.4
    cast_cd = 0.45
    cast_t = 0.3
    var par = get_parent()
    var origin = global_position + Vector3(0, 1.3, 0) + facing * 0.9
    var locked = lock_target != null and is_instance_valid(lock_target) and not lock_target.dying
    if spell_index == 0:
        var p = ProjectileScript.new()
        var d = facing
        if locked:
            d = (lock_target.global_position + Vector3(0, 1.2, 0) - origin).normalized()
        p.vel = d.normalized() * 22.0
        p.damage = 4.0
        p.color = sp["color"]
        p.friendly = true
        p.radius = 0.35
        p.life = 3.0
        if locked:
            p.homing = 4.0
            p.target = lock_target
        par.add_child(p)
        p.global_position = origin
    elif spell_index == 1:
        Fx.flame_burst(par, origin, facing, sp["color"])
        for e in get_tree().get_nodes_in_group("enemies"):
            if not is_instance_valid(e) or e.dying:
                continue
            var to = e.global_position - global_position
            to.y = 0.0
            var dist = to.length()
            if dist <= 7.5 + e.hit_radius and (dist < 1.2 or facing.dot(to / dist) > 0.55):
                e.hurt(3.5, global_position, 1.2)
        impact.emit(0.15)
    else:
        Fx.ring(par, global_position, sp["color"], 8.5, 0.5)
        Fx.burst(par, global_position + Vector3(0, 0.6, 0), sp["color"], 36, 9.0, 0.18)
        for e in get_tree().get_nodes_in_group("enemies"):
            if not is_instance_valid(e) or e.dying:
                continue
            var to2 = e.global_position - global_position
            to2.y = 0.0
            if to2.length() <= 8.5 + e.hit_radius:
                e.hurt(3.0, global_position, 2.2)
                e.freeze(2.5)
        impact.emit(0.25)

# ------------------------------------------------------------ animation
func _animate(delta):
    var spd = Vector2(velocity.x, velocity.z).length()
    anim_t += delta * (2.0 + spd * 1.5)
    var k = clampf(spd / SPEED, 0.0, 1.0)
    visual.position.y = absf(sin(anim_t)) * 0.07 * k
    cloak.rotation.z = sin(anim_t * 0.5) * 0.04 * k
    var swing = sin(anim_t) * 0.6 * k
    var tr = -swing
    var tl = swing
    var w = clampf(14.0 * delta, 0.0, 1.0)
    if drink_t > 0.0:
        tl = 2.1
    elif cast_t > 0.0:
        tl = 1.5
    if atk != "":
        var pose = _attack_pose()
        arm_r.rotation.x = pose[0]
        visual.rotation.y = pose[1]
        visual.rotation.x = pose[2]
        visual.position.z = pose[3]
        tl = -0.4
        if atk == "heavy" and atk_t < MOVES["heavy"]["wind"]:
            sword_light.light_energy = 3.0
        else:
            sword_light.light_energy = 0.8
    else:
        visual.rotation.y = lerp_angle(visual.rotation.y, 0.0, w)
        visual.rotation.x = lerpf(visual.rotation.x, 0.0, w)
        visual.position.z = lerpf(visual.position.z, 0.0, w)
        arm_r.rotation.x = lerpf(arm_r.rotation.x, tr, w)
        sword_light.light_energy = 0.8
    arm_l.rotation.x = lerpf(arm_l.rotation.x, tl, w)

func hurt(amount):
    if dead or invuln > 0.0:
        return
    health -= amount
    invuln = 0.4
    flash_t = 0.15
    impact.emit(0.35)
    if health <= 0.0:
        health = 0.0
        dead = true
        visual.rotation_degrees.x = -80.0
        visual.position.y = 0.4
        died.emit()
