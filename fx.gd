extends RefCounted

# Shared visual effects.

static func _fade_gradient(c0, c1):
    var g = Gradient.new()
    g.set_color(0, c0)
    g.set_color(1, c1)
    return g

static func _soft_mesh(radius):
    var fm = SphereMesh.new()
    fm.radius = radius
    fm.height = radius * 2.0
    fm.radial_segments = 6
    fm.rings = 3
    var fmat = StandardMaterial3D.new()
    fmat.vertex_color_use_as_albedo = true
    fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    fm.material = fmat
    return fm

static func burst(parent, pos, col, amount = 16, speed = 6.0, size = 0.22):
    var p = CPUParticles3D.new()
    p.amount = amount
    p.lifetime = 0.7
    p.one_shot = true
    p.explosiveness = 1.0
    p.direction = Vector3.UP
    p.spread = 80.0
    p.initial_velocity_min = speed * 0.5
    p.initial_velocity_max = speed
    p.gravity = Vector3(0, -12, 0)
    var bm = BoxMesh.new()
    bm.size = Vector3(size, size, size)
    var m = StandardMaterial3D.new()
    m.albedo_color = col
    m.emission_enabled = true
    m.emission = col
    m.emission_energy_multiplier = 2.5
    bm.material = m
    p.mesh = bm
    parent.add_child(p)
    p.global_position = pos
    p.emitting = true
    parent.get_tree().create_timer(1.3).timeout.connect(p.queue_free)

# Flat glowing ring that expands and fades.
static func ring(parent, pos, col, max_r = 3.0, dur = 0.4, y = 0.15):
    var t = TorusMesh.new()
    t.inner_radius = 0.9
    t.outer_radius = 1.0
    t.rings = 40
    t.ring_segments = 4
    var m = StandardMaterial3D.new()
    m.albedo_color = Color(col.r, col.g, col.b, 0.9)
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    var mi = MeshInstance3D.new()
    mi.mesh = t
    mi.material_override = m
    mi.scale = Vector3(0.2, 0.4, 0.2)
    mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mi)
    mi.global_position = Vector3(pos.x, y, pos.z)
    var tw = mi.create_tween()
    tw.set_parallel(true)
    tw.tween_property(mi, "scale", Vector3(max_r, 0.4, max_r), dur)
    tw.tween_property(m, "albedo_color:a", 0.0, dur)
    tw.chain().tween_callback(mi.queue_free)

# Cone of fire used by the Flame Burst spell.
static func flame_burst(parent, origin, dir, col):
    var p = CPUParticles3D.new()
    p.amount = 70
    p.lifetime = 0.55
    p.one_shot = true
    p.explosiveness = 0.8
    p.local_coords = false
    p.direction = dir
    p.spread = 22.0
    p.initial_velocity_min = 11.0
    p.initial_velocity_max = 16.0
    p.gravity = Vector3(0, 1.0, 0)
    p.scale_amount_min = 0.5
    p.scale_amount_max = 1.3
    p.color_ramp = _fade_gradient(Color(1.0, 0.95, 0.5, 1.0), Color(col.r, col.g * 0.3, 0.0, 0.0))
    p.mesh = _soft_mesh(0.3)
    p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(p)
    p.global_position = origin
    p.emitting = true
    parent.get_tree().create_timer(1.3).timeout.connect(p.queue_free)

# Healing flask effect: sparkles rising around the player, a glow and rings.
static func heal(player):
    var p = CPUParticles3D.new()
    p.amount = 70
    p.lifetime = 1.2
    p.one_shot = true
    p.explosiveness = 0.1
    p.local_coords = true
    p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
    p.emission_sphere_radius = 0.9
    p.direction = Vector3.UP
    p.spread = 15.0
    p.initial_velocity_min = 1.0
    p.initial_velocity_max = 2.5
    p.gravity = Vector3(0, 0.8, 0)
    p.color_ramp = _fade_gradient(Color(0.85, 1.0, 0.55, 1.0), Color(0.3, 1.0, 0.6, 0.0))
    p.mesh = _soft_mesh(0.08)
    p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    p.position = Vector3(0, 0.6, 0)
    player.add_child(p)
    p.emitting = true
    player.get_tree().create_timer(2.2).timeout.connect(p.queue_free)

    var l = OmniLight3D.new()
    l.light_color = Color(0.5, 1.0, 0.6)
    l.light_energy = 4.0
    l.omni_range = 7.0
    l.position = Vector3(0, 1.2, 0)
    player.add_child(l)
    var tw = l.create_tween()
    tw.tween_property(l, "light_energy", 0.0, 0.9)
    tw.tween_callback(l.queue_free)

    ring(player.get_parent(), player.global_position, Color(0.5, 1.0, 0.6), 1.8, 0.7)
