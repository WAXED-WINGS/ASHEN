extends Node3D

# Magic orbs, fireballs and blade waves. Pillars and walls stop them.
# friendly = true makes it a player spell that damages enemies instead.

const Fx = preload("res://scripts/fx.gd")
const HazardScript = preload("res://scripts/hazard.gd")

var vel = Vector3.ZERO
var damage = 10.0
var radius = 0.45
var color = Color(1.0, 0.5, 0.2)
var homing = 0.0
var life = 5.0
var explode_radius = 0.0
var friendly = false
var target = null
var player = null

func _ready():
    player = get_tree().get_first_node_in_group("player")
    var sm = SphereMesh.new()
    sm.radius = radius
    sm.height = radius * 2.0
    sm.radial_segments = 10
    sm.rings = 6
    var m = StandardMaterial3D.new()
    m.albedo_color = color
    m.emission_enabled = true
    m.emission = color
    m.emission_energy_multiplier = 3.5
    var body = MeshInstance3D.new()
    body.mesh = sm
    body.material_override = m
    body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(body)

    var core_m = StandardMaterial3D.new()
    core_m.albedo_color = Color.WHITE
    core_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    var cm = SphereMesh.new()
    cm.radius = radius * 0.55
    cm.height = radius * 1.1
    cm.radial_segments = 8
    cm.rings = 4
    var core = MeshInstance3D.new()
    core.mesh = cm
    core.material_override = core_m
    core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(core)

    var light = OmniLight3D.new()
    light.light_color = color
    light.light_energy = 1.8
    light.omni_range = 7.0
    add_child(light)

    var trail = CPUParticles3D.new()
    trail.amount = 20
    trail.lifetime = 0.45
    trail.local_coords = false
    trail.direction = Vector3.UP
    trail.spread = 180.0
    trail.initial_velocity_min = 0.2
    trail.initial_velocity_max = 0.9
    trail.gravity = Vector3.ZERO
    var tm = SphereMesh.new()
    tm.radius = radius * 0.3
    tm.height = radius * 0.6
    tm.radial_segments = 4
    tm.rings = 2
    var tmat = StandardMaterial3D.new()
    tmat.albedo_color = color
    tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    tm.material = tmat
    trail.mesh = tm
    trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(trail)
    trail.emitting = true

func _physics_process(delta):
    life -= delta
    if life <= 0.0:
        _pop()
        return

    if homing > 0.0:
        var tgt = null
        if friendly:
            if target != null and is_instance_valid(target) and not target.dying:
                tgt = target
        elif player != null and is_instance_valid(player) and not player.dead:
            tgt = player
        if tgt != null:
            var want = (tgt.global_position + Vector3(0, 1.0, 0) - global_position).normalized()
            var spd = vel.length()
            vel = vel.normalized().lerp(want, clampf(homing * delta, 0.0, 1.0)).normalized() * spd

    var from = global_position
    var to = from + vel * delta
    var q = PhysicsRayQueryParameters3D.create(from, to, 1)
    var hit = get_world_3d().direct_space_state.intersect_ray(q)
    if not hit.is_empty():
        global_position = hit["position"]
        _pop()
        return
    global_position = to

    if friendly:
        for e in get_tree().get_nodes_in_group("enemies"):
            if not is_instance_valid(e) or e.dying:
                continue
            var ep = e.global_position
            var hd = Vector2(ep.x - global_position.x, ep.z - global_position.z).length()
            if hd < e.hit_radius + radius and global_position.y > -0.2 and global_position.y < e.marker_height:
                e.hurt(damage, global_position, 1.0)
                _pop()
                return
    elif player != null and is_instance_valid(player) and not player.dead:
        var pp = player.global_position + Vector3(0, 0.9, 0)
        if pp.distance_to(global_position) < radius + 0.55:
            if explode_radius <= 0.0:
                player.hurt(damage)
            _pop()
            return
    if global_position.y < 0.05:
        _pop()

func _pop():
    var par = get_parent()
    if explode_radius > 0.0 and not friendly:
        var h = HazardScript.new()
        h.radius = explode_radius
        h.delay = 0.05
        h.damage = damage
        h.color = color
        h.linger = 2.5
        par.add_child(h)
        h.global_position = Vector3(global_position.x, 0.0, global_position.z)
    Fx.burst(par, global_position, color, 12, 5.0, 0.2)
    queue_free()
