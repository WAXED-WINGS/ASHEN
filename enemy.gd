extends CharacterBody3D

# Swarm minions and bosses.
# Minion kinds: ghoul / drowned (melee), imp (ranged fireballs).
# Boss kinds:   warden (knight), sovereign (water mage), dragon (fire dragon).
# Bosses use a move set: windup (telegraph) -> act -> recover.

const ProjectileScript = preload("res://scripts/projectile.gd")
const HazardScript = preload("res://scripts/hazard.gd")
const Fx = preload("res://scripts/fx.gd")

# [windup, act duration, recover]
const MOVES = {
    "slam": [0.9, 0.1, 0.8],
    "charge": [0.7, 0.9, 0.9],
    "blades": [0.7, 0.2, 0.7],
    "orbs": [0.9, 0.9, 0.8],
    "beam": [1.0, 2.0, 1.1],
    "pools": [0.6, 0.2, 0.8],
    "nova": [1.0, 0.3, 1.0],
    "breath": [0.9, 2.2, 1.0],
    "fireballs": [0.8, 1.3, 0.8],
    "tail": [0.7, 0.5, 1.0],
    "meteors": [1.0, 2.6, 1.2],
    "leap": [0.9, 0.9, 1.2]
}

signal died(enemy)
signal summon_requested(pos)

var is_boss = false
var kind = "ghoul"
var max_hp = 4.0
var hp = 4.0
var speed = 3.0
var damage = 8.0
var color = Color(0.5, 0.75, 0.3)
var eye_color = Color(0.6, 1.0, 0.4)
var scale_f = 1.0
var aggro_range = 15.0
var attack_range = 1.7
var windup_time = 0.5
var cooldown = 1.3
var slam_radius = 5.0
var tail_radius = 8.5
var hit_radius = 0.5
var ranged = false
var col_radius = -1.0
var col_height = -1.0
var marker_height = 2.6

var player = null
var state = "idle"
var state_t = 0.0
var attack_cd = 0.0
var flash_t = 0.0
var knock = Vector3.ZERO
var phase2 = false
var dying = false
var lit = false
var anim_t = 0.0
var stuck_t = 0.0
var side_t = 0.0
var side_dir = 1.0
var last_pos = Vector3.ZERO
var strafe_dir = 1.0
var slow_t = 0.0

# boss move state
var move = ""
var last_move = ""
var move_t = 0.0
var move_dur = 0.0
var aim_yaw = 0.0
var charge_dir = Vector3.ZERO
var hit_done = false
var tick_t = 0.0
var fired = 0
var beam_dir = 1.0
var leap_from = Vector3.ZERO
var leap_to = Vector3.ZERO

var mat
var visual
var telegraph
var torso
var head
var leg_l
var leg_r
var arm_l
var arm_r
var orbs = null
var aura = null
var line_pivot = null
var warn_mesh = null
var beam_mesh = null
var mouth_pivot = null
var flame = null
var jaw = null
var wing_l = null
var wing_r = null
var tail = null

# ------------------------------------------------------------ building blocks
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

func _cyl(rt, rb, h, seg = 8):
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
    s.radial_segments = 8
    s.rings = 5
    return s

func _limb(parent, joint_pos, length, thick, material):
    var piv = Node3D.new()
    piv.position = joint_pos
    parent.add_child(piv)
    _part(piv, _box(thick, length, thick), material, Vector3(0, -length / 2.0, 0))
    return piv

# ------------------------------------------------------------ setup
func _ready():
    hp = max_hp
    add_to_group("enemies")
    collision_layer = 4
    collision_mask = 1 | 2 | 4
    if kind == "dragon":
        col_radius = 1.6
        col_height = 3.4

    var r = 0.4 * scale_f
    var h = 1.7 * scale_f
    if col_radius > 0.0:
        r = col_radius
        h = col_height
    hit_radius = r
    var cs = CollisionShape3D.new()
    var cap = CapsuleShape3D.new()
    cap.radius = r
    cap.height = h
    cs.shape = cap
    cs.position.y = h / 2.0
    add_child(cs)

    mat = StandardMaterial3D.new()
    mat.roughness = 0.8
    _apply_look(false)
    if kind == "dragon":
        _build_dragon()
    else:
        _build_model()

    if is_boss:
        _build_boss_effects()
        attack_cd = 1.5
    marker_height = 2.8 * scale_f
    if is_boss:
        marker_height = 7.2
    last_pos = global_position

func _build_boss_effects():
    telegraph = MeshInstance3D.new()
    var cyl = CylinderMesh.new()
    cyl.top_radius = slam_radius
    cyl.bottom_radius = slam_radius
    cyl.height = 0.05
    telegraph.mesh = cyl
    var tm = StandardMaterial3D.new()
    tm.albedo_color = Color(1.0, 0.25, 0.1, 0.45)
    tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    telegraph.material_override = tm
    telegraph.position.y = 0.08
    telegraph.visible = false
    add_child(telegraph)

    line_pivot = Node3D.new()
    var ly = 3.6
    if kind == "warden":
        ly = 0.25
    line_pivot.position.y = ly
    add_child(line_pivot)
    var wm = StandardMaterial3D.new()
    wm.albedo_color = Color(1.0, 0.2, 0.15, 0.5)
    wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    warn_mesh = _part(line_pivot, _box(0.14, 0.14, 32.0), wm, Vector3(0, 0, -16.0))
    var bmat = StandardMaterial3D.new()
    bmat.albedo_color = Color(0.8, 1.0, 1.0)
    bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    beam_mesh = _part(line_pivot, _box(0.9, 0.9, 32.0), bmat, Vector3(0, 0, -16.0))
    warn_mesh.visible = false
    beam_mesh.visible = false
    warn_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    beam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    line_pivot.visible = false

func _build_model():
    visual = Node3D.new()
    visual.scale = Vector3(scale_f, scale_f, scale_f)
    add_child(visual)

    var dark = _plain(color.darkened(0.65))
    var glow = _glow(eye_color, 3.5)

    var tall = 1.0
    var thin = 1.0
    if kind == "drowned" or kind == "sovereign":
        tall = 1.2
        thin = 0.85
    if kind == "warden":
        thin = 1.25

    var leg_len = 0.9 * tall
    leg_l = _limb(visual, Vector3(-0.22 * thin, leg_len, 0), leg_len, 0.22, dark)
    leg_r = _limb(visual, Vector3(0.22 * thin, leg_len, 0), leg_len, 0.22, dark)

    var torso_y = leg_len + 0.45 * tall
    torso = _part(visual, _box(0.8 * thin, 0.9 * tall, 0.45), mat, Vector3(0, torso_y, 0))

    var sh_y = leg_len + 0.8 * tall
    var arm_len = 0.9 * tall
    if kind == "ghoul":
        arm_len = 1.1
    arm_l = _limb(visual, Vector3(-0.55 * thin, sh_y, 0), arm_len, 0.18, mat)
    arm_r = _limb(visual, Vector3(0.55 * thin, sh_y, 0), arm_len, 0.18, mat)

    var head_y = leg_len + 1.2 * tall
    head = _part(visual, _sph(0.27), dark, Vector3(0, head_y, 0))
    _part(visual, _box(0.36, 0.07, 0.07), glow, Vector3(0, head_y + 0.02, -0.24))

    var moss = _plain(Color(0.12, 0.3, 0.12))
    var metal = _plain(Color(0.55, 0.58, 0.62), 0.4)
    var hot = _glow(Color(1.0, 0.55, 0.15), 3.0)

    match kind:
        "ghoul":
            torso.rotation_degrees.x = -14.0
            head.position.z = -0.12
            _part(visual, _cyl(0.0, 0.36, 0.55, 6), dark, Vector3(0, head_y + 0.35, 0.05))
            for i in range(3):
                _part(visual, _box(0.18, 0.5, 0.05), dark, Vector3(-0.3 + i * 0.3, leg_len + 0.15, -0.24))
        "drowned":
            for i in range(5):
                _part(visual, _box(0.05, 0.9, 0.05), _plain(Color(0.05, 0.3, 0.18)), Vector3(-0.3 + i * 0.15, leg_len + 0.7, 0.26))
            _part(visual, _box(0.2, 0.3, 0.15), dark, Vector3(0, head_y - 0.25, -0.18))
        "imp":
            for s in [-1.0, 1.0]:
                _part(visual, _cyl(0.0, 0.08, 0.4, 5), hot, Vector3(s * 0.16, head_y + 0.3, 0), Vector3(0, 0, -s * 20.0))
            for i in range(3):
                _part(visual, _box(0.1, 0.1, 0.25), dark, Vector3(0, leg_len + 0.2 + i * 0.05, 0.3 + i * 0.22))
            _part(visual, _cyl(0.0, 0.15, 0.45, 5), hot, Vector3(0, head_y + 0.5, 0))
            for s in [-1.0, 1.0]:
                _part(visual, _box(0.7, 0.04, 0.5), _glow(Color(0.6, 0.15, 0.05), 0.8), Vector3(s * 0.5, torso_y + 0.3, 0.3), Vector3(0, s * 20.0, -s * 25.0))
        "warden":
            for s in [-1.0, 1.0]:
                _part(visual, _box(0.55, 0.35, 0.65), dark, Vector3(s * 0.8, sh_y + 0.12, 0))
                _part(visual, _box(0.5, 0.12, 0.6), moss, Vector3(s * 0.8, sh_y + 0.33, 0))
                _part(visual, _cyl(0.0, 0.1, 0.55, 5), metal, Vector3(s * 0.22, head_y + 0.35, 0), Vector3(0, 0, -s * 25.0))
            _part(visual, _box(0.58, 0.5, 0.56), dark, Vector3(0, head_y, 0))
            _part(visual, _box(0.9, 1.5, 0.08), _plain(Color(0.18, 0.3, 0.14)), Vector3(0, torso_y - 0.1, 0.3))
            _part(arm_r, _box(0.2, 2.5, 0.5), metal, Vector3(0, -arm_len - 1.0, -0.1))
            _part(arm_r, _box(0.7, 0.15, 0.2), metal, Vector3(0, -arm_len - 0.05, -0.1))
            _part(arm_l, _box(0.15, 1.5, 1.1), dark, Vector3(-0.2, -arm_len * 0.5, -0.25))
            _part(arm_l, _box(0.18, 0.4, 0.4), moss, Vector3(-0.28, -arm_len * 0.5, -0.25))
        "sovereign":
            _part(visual, _cyl(0.55, 1.0, 2.0, 10), mat, Vector3(0, 1.0, 0))
            for i in range(7):
                var a = TAU * i / 7.0
                _part(visual, _cyl(0.0, 0.07, 0.55, 5), glow, Vector3(cos(a) * 0.3, head_y + 0.42, sin(a) * 0.3))
            _part(arm_r, _box(0.1, 3.4, 0.1), metal, Vector3(0, -arm_len - 1.0, -0.15))
            for i in range(3):
                _part(arm_r, _cyl(0.0, 0.07, 0.6, 5), glow, Vector3(-0.3 + i * 0.3, -arm_len - 2.9, -0.15))
            orbs = Node3D.new()
            orbs.position = Vector3(0, torso_y + 0.3, 0)
            visual.add_child(orbs)
            for i in range(3):
                var a2 = TAU * i / 3.0
                _part(orbs, _sph(0.2), glow, Vector3(cos(a2) * 1.4, 0, sin(a2) * 1.4))

func _build_dragon():
    visual = Node3D.new()
    add_child(visual)
    var dark = _plain(color.darkened(0.6), 0.7)
    var scale_mat = _plain(color.darkened(0.25), 0.6)
    var hot = _glow(Color(1.0, 0.55, 0.12), 3.5)
    var glow = _glow(eye_color, 4.0)
    var membrane = _glow(Color(0.5, 0.08, 0.04), 0.7)
    membrane.cull_mode = BaseMaterial3D.CULL_DISABLED

    # body, chest and belly
    torso = _part(visual, _box(2.2, 2.0, 4.6), mat, Vector3(0, 2.5, 0))
    _part(visual, _box(2.4, 2.2, 1.7), mat, Vector3(0, 2.6, -1.7))
    _part(visual, _box(1.7, 0.25, 4.0), scale_mat, Vector3(0, 1.55, 0))
    for i in range(6):
        _part(visual, _box(1.5, 0.08, 0.15), dark, Vector3(0, 1.43, -1.5 + i * 0.6))
    # back spikes
    for i in range(8):
        _part(visual, _cyl(0.0, 0.26 - i * 0.01, 0.9, 5), dark, Vector3(0, 3.8, -2.0 + i * 0.55))
    # lava cracks
    for i in range(6):
        _part(visual, _box(0.06, 0.05, 1.1), hot, Vector3(-0.8 + (i % 3) * 0.8, 3.52, -1.4 + int(i / 3) * 2.0), Vector3(0, (i - 2.5) * 12.0, 0))
        _part(visual, _box(0.05, 0.9, 0.05), hot, Vector3(1.12, 2.4 + (i % 3) * 0.3, -1.0 + i * 0.35), Vector3(0, 0, (i - 2.5) * 10.0))

    # neck and head
    _part(visual, _box(1.1, 1.1, 1.5), mat, Vector3(0, 3.4, -2.9), Vector3(-30, 0, 0))
    _part(visual, _box(0.95, 0.95, 1.5), mat, Vector3(0, 4.0, -3.7), Vector3(-40, 0, 0))
    _part(visual, _box(0.85, 0.85, 1.4), mat, Vector3(0, 4.6, -4.3), Vector3(-30, 0, 0))
    head = _part(visual, _box(1.2, 1.0, 1.8), mat, Vector3(0, 4.9, -5.2), Vector3(10, 0, 0))
    _part(visual, _box(0.85, 0.6, 1.2), mat, Vector3(0, 4.75, -6.3))
    for s in [-1.0, 1.0]:
        _part(visual, _box(0.2, 0.2, 0.2), glow, Vector3(s * 0.52, 5.15, -5.7))
        _part(visual, _cyl(0.0, 0.16, 1.3, 5), dark, Vector3(s * 0.42, 5.7, -4.9), Vector3(55, 0, s * -12.0))
        _part(visual, _cyl(0.0, 0.05, 0.25, 4), _plain(Color(0.9, 0.9, 0.8)), Vector3(s * 0.3, 4.45, -6.75), Vector3(180, 0, 0))
        _part(visual, _box(0.12, 0.12, 0.12), hot, Vector3(s * 0.2, 4.95, -6.88))
    jaw = Node3D.new()
    jaw.position = Vector3(0, 4.35, -5.2)
    visual.add_child(jaw)
    _part(jaw, _box(0.8, 0.25, 1.7), dark, Vector3(0, -0.1, -0.9))
    _part(jaw, _box(0.5, 0.1, 1.1), hot, Vector3(0, 0.02, -0.9))

    # legs: hind = leg_l / leg_r, forelegs = arm_l / arm_r (they rear up when attacking)
    leg_l = _limb(visual, Vector3(-1.05, 2.0, 1.4), 1.9, 0.65, dark)
    leg_r = _limb(visual, Vector3(1.05, 2.0, 1.4), 1.9, 0.65, dark)
    arm_l = _limb(visual, Vector3(-1.05, 2.3, -1.9), 2.2, 0.55, dark)
    arm_r = _limb(visual, Vector3(1.05, 2.3, -1.9), 2.2, 0.55, dark)
    for lg in [leg_l, leg_r]:
        _part(lg, _box(0.8, 0.25, 1.0), dark, Vector3(0, -1.9, -0.25))
    for ar in [arm_l, arm_r]:
        _part(ar, _box(0.7, 0.25, 0.9), dark, Vector3(0, -2.2, -0.2))
        for i in range(3):
            _part(ar, _cyl(0.0, 0.07, 0.4, 4), _plain(Color(0.9, 0.88, 0.8)), Vector3(-0.22 + i * 0.22, -2.25, -0.75), Vector3(-90, 0, 0))

    # wings
    wing_l = Node3D.new()
    wing_l.position = Vector3(-1.1, 3.7, -0.4)
    visual.add_child(wing_l)
    wing_r = Node3D.new()
    wing_r.position = Vector3(1.1, 3.7, -0.4)
    visual.add_child(wing_r)
    for s in [-1.0, 1.0]:
        var w = wing_l if s < 0.0 else wing_r
        _part(w, _box(4.2, 0.22, 0.32), dark, Vector3(s * 2.1, 0, 0))
        _part(w, _box(3.6, 0.05, 3.0), membrane, Vector3(s * 2.0, -0.08, 1.5))
        for i in range(4):
            _part(w, _box(0.1, 0.1, 3.1 - i * 0.25), dark, Vector3(s * (0.9 + i * 0.95), -0.05, 1.45), Vector3(0, s * (i * -4.0), 0))
        _part(w, _cyl(0.0, 0.1, 0.7, 4), _plain(Color(0.9, 0.88, 0.8)), Vector3(s * 4.25, 0.1, 0), Vector3(0, 0, -s * 90.0))

    # tail
    tail = Node3D.new()
    tail.position = Vector3(0, 2.3, 2.1)
    visual.add_child(tail)
    for i in range(7):
        var sz = 1.3 - i * 0.14
        _part(tail, _box(sz, sz * 0.85, 1.1), mat if i % 2 == 0 else scale_mat, Vector3(0, -i * 0.1, 0.9 + i * 1.0))
        if i % 2 == 1:
            _part(tail, _cyl(0.0, 0.14, 0.5, 4), dark, Vector3(0, sz * 0.55 - i * 0.1, 0.9 + i * 1.0))
    _part(tail, _cyl(0.0, 0.3, 1.1, 5), hot, Vector3(0, -0.7, 8.2), Vector3(90, 0, 0))

    # fire breath
    mouth_pivot = Node3D.new()
    add_child(mouth_pivot)
    flame = CPUParticles3D.new()
    flame.position = Vector3(0, 4.7, -6.5)
    flame.amount = 100
    flame.lifetime = 0.8
    flame.local_coords = false
    flame.direction = Vector3(0, -0.12, -1)
    flame.spread = 13.0
    flame.initial_velocity_min = 11.0
    flame.initial_velocity_max = 15.0
    flame.gravity = Vector3(0, 1.5, 0)
    flame.scale_amount_min = 0.6
    flame.scale_amount_max = 1.5
    var g = Gradient.new()
    g.set_color(0, Color(1.0, 0.95, 0.4, 1.0))
    g.set_color(1, Color(0.9, 0.15, 0.0, 0.0))
    flame.color_ramp = g
    var fm = SphereMesh.new()
    fm.radius = 0.35
    fm.height = 0.7
    fm.radial_segments = 6
    fm.rings = 3
    var fmat = StandardMaterial3D.new()
    fmat.vertex_color_use_as_albedo = true
    fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    fm.material = fmat
    flame.mesh = fm
    flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    flame.emitting = false
    mouth_pivot.add_child(flame)

    aura = OmniLight3D.new()
    aura.light_color = Color(1.0, 0.5, 0.15)
    aura.light_energy = 3.0
    aura.omni_range = 16.0
    aura.position = Vector3(0, 3.5, 0)
    add_child(aura)

func _apply_look(bright):
    lit = bright
    if bright:
        mat.albedo_color = Color.WHITE
        mat.emission_enabled = true
        mat.emission = Color.WHITE
        mat.emission_energy_multiplier = 1.5
    else:
        mat.albedo_color = color
        mat.emission_enabled = true
        mat.emission = color
        mat.emission_energy_multiplier = 0.5

# ------------------------------------------------------------ helpers for attacks
func _yaw_of(d):
    return atan2(-d.x, -d.z)

func _forward(yaw):
    return Vector3(-sin(yaw), 0.0, -cos(yaw))

func _mouth():
    var yaw = visual.rotation.y
    if kind == "dragon":
        return global_position + Vector3(0, 4.7, -6.5).rotated(Vector3.UP, yaw)
    var my = 1.5 * scale_f
    if kind == "warden":
        my = 1.1
    return global_position + Vector3(0, my, 0) + _forward(yaw) * (0.8 * scale_f)

func _clamp_pos(p):
    var w = get_parent().world
    if w.bounds_kind == "rect":
        p.x = clampf(p.x, -w.bounds.x + 3.0, w.bounds.x - 3.0)
        p.z = clampf(p.z, -w.bounds.y + 3.0, w.bounds.y - 3.0)
    else:
        var v = Vector2(p.x, p.z)
        var lim = w.bounds.x - 4.0
        if v.length() > lim:
            v = v.normalized() * lim
            p.x = v.x
            p.z = v.y
    return p

func _fire(origin, d, spd, dmg, col, homing = 0.0, explode = 0.0, rad = 0.45, life = 5.0):
    var p = ProjectileScript.new()
    p.vel = d.normalized() * spd
    p.damage = dmg
    p.color = col
    p.homing = homing
    p.explode_radius = explode
    p.radius = rad
    p.life = life
    get_parent().add_child(p)
    p.global_position = origin

func _hazard(pos, rad, delay, dmg, linger = 0.0):
    var h = HazardScript.new()
    h.radius = rad
    h.delay = delay
    h.damage = dmg
    h.color = color
    h.linger = linger
    get_parent().add_child(h)
    h.global_position = Vector3(pos.x, 0.0, pos.z)

func _dist_xz(p):
    return Vector2(p.x - global_position.x, p.z - global_position.z).length()

func _hurt_in_radius(r):
    if player != null and not player.dead and _dist_xz(player.global_position) <= r:
        player.hurt(damage)

func _in_beam():
    var f = _forward(aim_yaw)
    var rel = player.global_position - global_position
    rel.y = 0.0
    var along = rel.dot(f)
    var perp = absf(rel.x * f.z - rel.z * f.x)
    return along > 0.0 and along < 32.0 and perp < 1.2

func _in_cone():
    var o = _mouth()
    var rel = player.global_position - o
    rel.y = 0.0
    var d = rel.length()
    if d < 0.1 or d > 13.5:
        return false
    return _forward(aim_yaw).dot(rel / d) > 0.86

# ------------------------------------------------------------ boss move logic
func _wpick(opts):
    var total = 0.0
    for o in opts:
        var w = float(o[1])
        if o[0] == last_move:
            w *= 0.35
        total += w
    var r = randf() * total
    for o in opts:
        var w2 = float(o[1])
        if o[0] == last_move:
            w2 *= 0.35
        r -= w2
        if r <= 0.0:
            return o[0]
    return opts[0][0]

func _pick_move(dist):
    if kind == "warden":
        if dist < 6.5:
            return _wpick([["slam", 5], ["blades", 2], ["charge", 3]])
        return _wpick([["charge", 5], ["blades", 5]])
    if kind == "sovereign":
        if dist < 7.0:
            return _wpick([["nova", 4], ["pools", 3], ["beam", 3]])
        return _wpick([["orbs", 4], ["beam", 3], ["pools", 3]])
    var opts = [["fireballs", 2], ["meteors", 2], ["leap", 2]]
    if dist < 13.0:
        opts.append(["breath", 4])
    if dist < 9.5:
        opts.append(["tail", 5])
    return _wpick(opts)

func _start_move(mv):
    move = mv
    last_move = mv
    var m = MOVES[mv]
    var k = 1.0
    if phase2:
        k = 0.75
    state = "windup"
    state_t = m[0] * k
    move_dur = m[1]
    var to = player.global_position - global_position
    to.y = 0.0
    aim_yaw = _yaw_of(to.normalized())
    match mv:
        "slam":
            telegraph.scale = Vector3(1, 1, 1)
            telegraph.visible = true
        "tail":
            var s = tail_radius / slam_radius
            telegraph.scale = Vector3(s, 1, s)
            telegraph.visible = true
        "charge":
            line_pivot.visible = true
            warn_mesh.visible = true
            beam_mesh.visible = false
        "beam":
            line_pivot.visible = true
            warn_mesh.visible = true
            beam_mesh.visible = false
        "leap":
            leap_to = _clamp_pos(player.global_position)
            leap_to.y = 0.1
            _hazard(leap_to, 5.5, state_t + move_dur, damage)

func _windup_tick(delta, dir):
    var yaw_p = _yaw_of(dir)
    if move == "charge" or move == "beam":
        aim_yaw = lerp_angle(aim_yaw, yaw_p, clampf(6.0 * delta, 0.0, 1.0))
        visual.rotation.y = aim_yaw
        line_pivot.rotation.y = aim_yaw
    elif move == "leap":
        var d = leap_to - global_position
        d.y = 0.0
        if d.length() > 0.1:
            visual.rotation.y = lerp_angle(visual.rotation.y, _yaw_of(d.normalized()), clampf(8.0 * delta, 0.0, 1.0))
    else:
        visual.rotation.y = lerp_angle(visual.rotation.y, yaw_p, clampf(8.0 * delta, 0.0, 1.0))

func _begin_act(dir):
    state = "act"
    move_t = move_dur
    tick_t = 0.0
    fired = 0
    var yaw = visual.rotation.y
    match move:
        "slam":
            telegraph.visible = false
            _hurt_in_radius(slam_radius + 0.4)
            _slam_ring(slam_radius)
        "tail":
            telegraph.visible = false
            _hurt_in_radius(tail_radius)
            _slam_ring(tail_radius)
        "charge":
            charge_dir = _forward(aim_yaw)
            hit_done = false
            warn_mesh.visible = false
            line_pivot.visible = false
        "blades":
            for a in [-0.32, 0.0, 0.32]:
                var o = _mouth()
                _fire(o, _forward(yaw + a), 14.0, damage * 0.7, color, 0.0, 0.0, 0.5, 4.0)
        "pools":
            _hazard(player.global_position, 3.0, 1.0, damage)
            for i in range(4):
                var ang = randf() * TAU
                var p = player.global_position + Vector3(cos(ang), 0, sin(ang)) * randf_range(3.0, 8.0)
                _hazard(_clamp_pos(p), 3.0, 1.0 + i * 0.15, damage)
        "nova":
            for i in range(14):
                var an = TAU * float(i) / 14.0
                _fire(_mouth(), Vector3(cos(an), 0, sin(an)), 9.0, damage * 0.5, color, 0.0, 0.0, 0.45, 4.0)
        "beam":
            beam_dir = 1.0 if randf() < 0.5 else -1.0
            aim_yaw = aim_yaw - beam_dir * 0.7
            warn_mesh.visible = false
            beam_mesh.visible = true
            line_pivot.visible = true
        "breath":
            aim_yaw = yaw
            mouth_pivot.rotation.y = aim_yaw
            flame.emitting = true
        "leap":
            leap_from = global_position

func _act_tick(delta, dir, dist):
    var want = Vector3.ZERO
    var prog = 1.0 - clampf(move_t / maxf(move_dur, 0.01), 0.0, 1.0)
    match move:
        "charge":
            want = charge_dir * 15.0
            visual.rotation.y = aim_yaw
            if not hit_done and dist < hit_radius + 1.4 and not player.dead:
                hit_done = true
                player.hurt(damage)
                Fx.burst(get_parent(), player.global_position + Vector3(0, 1, 0), color, 14, 6.0, 0.2)
        "orbs":
            tick_t -= delta
            if tick_t <= 0.0 and fired < 5:
                fired += 1
                tick_t = 0.14
                var ang = visual.rotation.y + (float(fired) - 3.0) * 0.32
                _fire(_mouth(), _forward(ang), 8.5, damage * 0.55, color, 2.2, 0.0, 0.5, 6.0)
        "beam":
            aim_yaw += beam_dir * 1.4 / maxf(move_dur, 0.1) * delta
            visual.rotation.y = aim_yaw
            line_pivot.rotation.y = aim_yaw
            tick_t -= delta
            if tick_t <= 0.0:
                tick_t = 0.3
                if not player.dead and _in_beam():
                    player.hurt(damage * 0.45)
        "breath":
            var to = player.global_position - global_position
            to.y = 0.0
            if to.length() > 0.1:
                aim_yaw = lerp_angle(aim_yaw, _yaw_of(to.normalized()), clampf(0.9 * delta, 0.0, 1.0))
            visual.rotation.y = aim_yaw
            mouth_pivot.rotation.y = aim_yaw
            tick_t -= delta
            if tick_t <= 0.0:
                tick_t = 0.25
                if not player.dead and _in_cone():
                    player.hurt(damage * 0.3)
        "fireballs":
            tick_t -= delta
            if tick_t <= 0.0 and fired < 3:
                fired += 1
                tick_t = 0.45
                var o = _mouth()
                var d = player.global_position + Vector3(0, 0.8, 0) - o
                _fire(o, d, 15.0, damage * 0.8, color, 0.0, 3.2, 0.7, 4.0)
        "meteors":
            tick_t -= delta
            if tick_t <= 0.0:
                tick_t = 0.2
                var p = player.global_position
                if randf() > 0.3:
                    var a = randf() * TAU
                    p += Vector3(cos(a), 0, sin(a)) * randf_range(2.0, 13.0)
                _hazard(_clamp_pos(p), 2.8, 1.0, damage * 0.9, 3.0)
        "leap":
            var pos = leap_from.lerp(leap_to, prog)
            pos.y = 0.1 + sin(prog * PI) * 5.0
            global_position = pos
    return want

func _end_act():
    if telegraph != null:
        telegraph.visible = false
    if line_pivot != null:
        line_pivot.visible = false
        warn_mesh.visible = false
        beam_mesh.visible = false
    if flame != null:
        flame.emitting = false
    if move == "leap":
        global_position = Vector3(leap_to.x, 0.1, leap_to.z)
        velocity = Vector3.ZERO
        _slam_ring(5.5)
    var k = 1.0
    if phase2:
        k = 0.75
    var rec = 0.8
    if MOVES.has(move):
        rec = MOVES[move][2] * k
    state = "recover"
    state_t = rec
    attack_cd = cooldown
    move = ""

func _boss_want(dir, dist):
    if kind == "warden":
        if dist > 3.2:
            return dir * speed
        return Vector3.ZERO
    if kind == "sovereign":
        if dist > 11.0:
            return dir * speed
        if dist < 6.0:
            return -dir * speed * 0.7
        return dir.rotated(Vector3.UP, 1.57) * speed * 0.5 * strafe_dir
    if dist > 6.5:
        return dir * speed
    return Vector3.ZERO

# ------------------------------------------------------------ behaviour
func _physics_process(delta):
    if dying:
        return
    if player == null or not is_instance_valid(player):
        player = get_tree().get_first_node_in_group("player")
        return

    attack_cd = maxf(0.0, attack_cd - delta)
    if flash_t > 0.0:
        flash_t -= delta
    var want_lit = flash_t > 0.0 or state == "windup"
    if want_lit != lit:
        _apply_look(want_lit)

    var to = player.global_position - global_position
    to.y = 0.0
    var dist = to.length()
    var dir = Vector3.ZERO
    if dist > 0.01:
        dir = to / dist
    var want = Vector3.ZERO

    match state:
        "idle":
            if dist < aggro_range and not player.dead:
                _wake()
        "chase":
            var steer = dir
            if side_t > 0.0:
                side_t -= delta
                steer = dir.rotated(Vector3.UP, side_dir * 1.3)
            if is_boss:
                want = _boss_want(steer, dist)
                if randf() < 0.004:
                    strafe_dir = -strafe_dir
            elif ranged:
                if dist > 9.0:
                    want = steer * speed
                elif dist < 5.0:
                    want = -dir * speed * 0.6
                else:
                    want = dir.rotated(Vector3.UP, 1.57) * speed * 0.4 * strafe_dir
            else:
                want = steer * speed
            if dist > 0.01:
                visual.rotation.y = lerp_angle(visual.rotation.y, _yaw_of(dir), clampf(10.0 * delta, 0.0, 1.0))
            if is_boss:
                if attack_cd <= 0.0 and not player.dead and dist < 40.0:
                    _start_move(_pick_move(dist))
            elif dist < attack_range and attack_cd <= 0.0 and not player.dead:
                state = "windup"
                state_t = windup_time
        "windup":
            state_t -= delta
            if is_boss:
                _windup_tick(delta, dir)
                if state_t <= 0.0:
                    _begin_act(dir)
            else:
                visual.rotation.y = lerp_angle(visual.rotation.y, _yaw_of(dir), clampf(10.0 * delta, 0.0, 1.0))
                if state_t <= 0.0:
                    _strike(dist)
        "act":
            move_t -= delta
            want = _act_tick(delta, dir, dist)
            if move_t <= 0.0:
                _end_act()
        "recover":
            state_t -= delta
            if state_t <= 0.0:
                state = "chase"

    if slow_t > 0.0:
        slow_t -= delta
        want *= 0.35

    # boss mid-air leap: position is driven directly
    if state == "act" and move == "leap":
        velocity = Vector3.ZERO
        _animate(delta)
        return

    # simple obstacle escape: if barely moving while chasing, sidestep for a moment
    if state == "chase" and not ranged:
        stuck_t += delta
        if stuck_t > 0.5:
            var moved = (global_position - last_pos).length()
            if moved < speed * 0.25 and dist > attack_range + 0.5 and side_t <= 0.0:
                side_t = 1.0
                side_dir = 1.0 if randf() < 0.5 else -1.0
            last_pos = global_position
            stuck_t = 0.0

    knock = knock.move_toward(Vector3.ZERO, 25.0 * delta)
    velocity.x = want.x + knock.x
    velocity.z = want.z + knock.z
    if is_on_floor():
        velocity.y = 0.0
    else:
        velocity.y -= 25.0 * delta
    move_and_slide()
    _animate(delta)

func _animate(delta):
    var spd = Vector2(velocity.x, velocity.z).length()
    anim_t += delta * (2.0 + spd * 1.6)
    var k = clampf(spd / maxf(speed, 0.1), 0.0, 1.0)
    var sw = sin(anim_t) * 0.8 * k
    visual.position.y = absf(sin(anim_t)) * 0.06 * k
    leg_l.rotation.x = sw
    leg_r.rotation.x = -sw
    var tr = -sw * 0.7
    var tl = sw * 0.7
    var raise = -2.5
    if kind == "dragon":
        raise = -1.1
    if state == "windup":
        tr = raise
        if is_boss:
            tl = raise
    elif state == "act" and (move == "breath" or move == "meteors" or move == "nova"):
        tr = raise
        tl = raise
    elif state == "recover" and state_t > 0.25 and move == "":
        tr = 1.1 if kind != "dragon" else 0.3
        if is_boss:
            tl = tr
    var w = clampf(14.0 * delta, 0.0, 1.0)
    arm_r.rotation.x = lerpf(arm_r.rotation.x, tr, w)
    arm_l.rotation.x = lerpf(arm_l.rotation.x, tl, w)
    if orbs != null:
        orbs.rotation.y += delta * 1.6
    if aura != null:
        aura.light_energy = 3.0 + sin(anim_t * 3.0) * 0.6
    if kind == "dragon":
        var flap = sin(anim_t * 0.9) * 0.3 + 0.3
        if state == "windup" or state == "act":
            flap = 0.95
        wing_l.rotation.z = lerpf(wing_l.rotation.z, -flap, clampf(8.0 * delta, 0.0, 1.0))
        wing_r.rotation.z = lerpf(wing_r.rotation.z, flap, clampf(8.0 * delta, 0.0, 1.0))
        var jt = 0.0
        if (state == "windup" or state == "act") and (move == "breath" or move == "fireballs"):
            jt = -0.55
        jaw.rotation.x = lerpf(jaw.rotation.x, jt, clampf(10.0 * delta, 0.0, 1.0))
        var ty = sin(anim_t * 0.6) * 0.25
        if move == "tail":
            if state == "windup":
                ty = -0.9
            else:
                ty = -0.9 + (1.0 - clampf(move_t / maxf(move_dur, 0.01), 0.0, 1.0)) * TAU
        tail.rotation.y = lerpf(tail.rotation.y, ty, clampf(14.0 * delta, 0.0, 1.0)) if move != "tail" else ty

func _wake():
    if state != "idle":
        return
    state = "chase"
    for e in get_tree().get_nodes_in_group("enemies"):
        if e != self and is_instance_valid(e) and e.state == "idle":
            if e.global_position.distance_to(global_position) < 9.0:
                e.state = "chase"

func _strike(dist):
    # minion attack (melee or ranged)
    state = "recover"
    attack_cd = cooldown
    state_t = 0.5
    if ranged:
        var o = global_position + Vector3(0, 1.3 * scale_f, 0)
        var d = player.global_position + Vector3(0, 0.9, 0) - o
        _fire(o, d, 11.0, damage, color, 0.0, 0.0, 0.4, 4.0)
    elif dist <= attack_range + 0.7:
        player.hurt(damage)

func _slam_ring(r):
    var ring = MeshInstance3D.new()
    var cyl = CylinderMesh.new()
    cyl.top_radius = 1.0
    cyl.bottom_radius = 1.0
    cyl.height = 0.15
    ring.mesh = cyl
    var m = StandardMaterial3D.new()
    m.albedo_color = color
    m.emission_enabled = true
    m.emission = Color.WHITE
    m.emission_energy_multiplier = 2.0
    ring.material_override = m
    get_parent().add_child(ring)
    ring.global_position = Vector3(global_position.x, 0.1, global_position.z)
    var tw = ring.create_tween()
    tw.tween_property(ring, "scale", Vector3(r, 1.0, r), 0.25)
    tw.tween_callback(ring.queue_free)

func freeze(t):
    slow_t = maxf(slow_t, t)

func hurt(amount, from_pos, kb = 1.0):
    if dying:
        return
    hp -= amount
    flash_t = 0.12
    if state == "idle":
        _wake()
    var away = global_position - from_pos
    away.y = 0.0
    if away.length() > 0.01 and not (state == "act" and move == "leap"):
        knock = away.normalized() * (1.2 if is_boss else 7.0) * kb
    if not is_boss and state == "windup":
        state = "recover"
        state_t = 0.35
    if is_boss and not phase2 and hp <= max_hp * 0.5 and hp > 0.0:
        phase2 = true
        speed *= 1.3
        cooldown *= 0.7
        summon_requested.emit(global_position)
    if hp <= 0.0:
        dying = true
        died.emit(self)
        queue_free()
