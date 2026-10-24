extends Node3D

# Ground attack: shows a telegraph circle that fills up, then detonates.
# With linger > 0 it leaves a burning pool that keeps damaging.

const Fx = preload("res://scripts/fx.gd")

var radius = 3.0
var delay = 1.0
var damage = 20.0
var color = Color(1.0, 0.3, 0.1)
var linger = 0.0
var player = null
var t = 0.0
var detonated = false
var inner
var outer
var pool_t = 0.0
var tick = 0.0

func _disc_mat(a):
    var m = StandardMaterial3D.new()
    m.albedo_color = Color(color.r, color.g, color.b, a)
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    return m

func _make_disc(a, y):
    var cyl = CylinderMesh.new()
    cyl.top_radius = radius
    cyl.bottom_radius = radius
    cyl.height = 0.04
    cyl.radial_segments = 28
    cyl.rings = 1
    var mi = MeshInstance3D.new()
    mi.mesh = cyl
    mi.material_override = _disc_mat(a)
    mi.position.y = y
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mi)
    return mi

func _ready():
    player = get_tree().get_first_node_in_group("player")
    outer = _make_disc(0.25, 0.07)
    inner = _make_disc(0.6, 0.09)
    inner.scale = Vector3(0.01, 1.0, 0.01)

func _dist_to_player():
    var pp = player.global_position
    return Vector2(pp.x - global_position.x, pp.z - global_position.z).length()

func _physics_process(delta):
    t += delta
    if not detonated:
        var k = clampf(t / maxf(delay, 0.01), 0.01, 1.0)
        inner.scale = Vector3(k, 1.0, k)
        if t >= delay:
            _detonate()
    else:
        pool_t -= delta
        tick -= delta
        if tick <= 0.0:
            tick = 0.5
            if player != null and is_instance_valid(player) and not player.dead and _dist_to_player() < radius * 0.9:
                player.hurt(damage * 0.25)
        if pool_t <= 0.0:
            queue_free()

func _detonate():
    detonated = true
    if player != null and is_instance_valid(player) and not player.dead:
        if _dist_to_player() < radius and player.global_position.y < 3.0:
            player.hurt(damage)
    Fx.burst(get_parent(), global_position + Vector3(0, 0.3, 0), color, 20, 7.0, 0.25)
    if linger > 0.0:
        var fire = StandardMaterial3D.new()
        fire.albedo_color = color
        fire.emission_enabled = true
        fire.emission = color
        fire.emission_energy_multiplier = 2.5
        fire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        fire.albedo_color.a = 0.7
        inner.material_override = fire
        outer.visible = false
        var l = OmniLight3D.new()
        l.light_color = color
        l.light_energy = 2.0
        l.omni_range = radius * 3.0
        l.position.y = 1.0
        add_child(l)
        pool_t = linger
        tick = 0.5
    else:
        pool_t = 0.0
        queue_free()
