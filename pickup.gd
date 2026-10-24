extends Node3D

# Collectable: "flask" (extra healing flask) or "mana" (mana crystal).

const Fx = preload("res://scripts/fx.gd")

var kind = "flask"
var t = 0.0
var player = null
var body

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
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mi)
    return mi

func _ready():
    player = get_tree().get_first_node_in_group("player")
    t = randf() * 6.0
    body = Node3D.new()
    body.position.y = 0.9
    add_child(body)
    var lc = Color(1.0, 0.55, 0.25)
    if kind == "flask":
        var liquid = _glow(Color(1.0, 0.45, 0.2), 3.2)
        var glass = StandardMaterial3D.new()
        glass.albedo_color = Color(0.85, 0.92, 1.0)
        glass.roughness = 0.1
        glass.emission_enabled = true
        glass.emission = Color(0.7, 0.8, 1.0)
        glass.emission_energy_multiplier = 0.6
        var s = SphereMesh.new()
        s.radius = 0.23
        s.height = 0.46
        s.radial_segments = 10
        s.rings = 6
        _part(body, s, liquid, Vector3.ZERO)
        var neck = CylinderMesh.new()
        neck.top_radius = 0.07
        neck.bottom_radius = 0.09
        neck.height = 0.24
        neck.radial_segments = 8
        _part(body, neck, glass, Vector3(0, 0.3, 0))
        var cork = BoxMesh.new()
        cork.size = Vector3(0.14, 0.09, 0.14)
        _part(body, cork, _glow(Color(0.5, 0.3, 0.15), 0.3), Vector3(0, 0.46, 0))
    else:
        lc = Color(0.35, 0.6, 1.0)
        var cm = CylinderMesh.new()
        cm.top_radius = 0.0
        cm.bottom_radius = 0.22
        cm.height = 0.38
        cm.radial_segments = 4
        cm.rings = 1
        var mat = _glow(Color(0.3, 0.6, 1.0), 3.6)
        _part(body, cm, mat, Vector3(0, 0.19, 0))
        _part(body, cm, mat, Vector3(0, -0.19, 0), Vector3(180, 0, 0))

    var lamp = OmniLight3D.new()
    lamp.light_color = lc
    lamp.light_energy = 1.6
    lamp.omni_range = 6.0
    lamp.position = Vector3(0, 1.0, 0)
    add_child(lamp)

    var tor = TorusMesh.new()
    tor.inner_radius = 0.7
    tor.outer_radius = 0.85
    tor.rings = 24
    tor.ring_segments = 4
    var rm = _part(self, tor, _glow(lc, 2.5), Vector3(0, 0.06, 0))
    rm.scale = Vector3(1, 0.2, 1)

func _physics_process(delta):
    t += delta
    body.position.y = 0.9 + sin(t * 2.5) * 0.12
    body.rotation.y += delta * 1.6
    if player == null or not is_instance_valid(player) or player.dead:
        return
    var pp = player.global_position
    if Vector2(pp.x - global_position.x, pp.z - global_position.z).length() < 1.7:
        if player.can_collect(kind):
            player.collect(kind)
            var col = Color(1.0, 0.6, 0.3) if kind == "flask" else Color(0.4, 0.7, 1.0)
            Fx.burst(get_parent(), global_position + Vector3(0, 0.9, 0), col, 14, 5.0, 0.12)
            Fx.ring(get_parent(), global_position, col, 1.8, 0.4)
            queue_free()
