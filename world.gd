extends Node3D

# Procedural world builder. Builds a full detailed arena for each level:
#   0 = Overgrown Courtyard (ruined castle, tall grass, dark pond)
#   1 = Sunken Vault (flooded crypt hall, colonnades, crystals)
#   2 = Abyssal Core (circular obsidian cathedral, lava pools)

const GrassShader = preload("res://shaders/grass.gdshader")
const WaterShader = preload("res://shaders/water.gdshader")
const LavaShader = preload("res://shaders/lava.gdshader")

var cfg
var rng = RandomNumberGenerator.new()
var circles = []     # [Vector2 pos, radius]  solid obstacles
var rects = []       # [Vector2 center, Vector2 half]  solid obstacles
var bounds_kind = "rect"
var bounds = Vector2(30, 30)
var zone = Rect2(-20, -20, 40, 40)
var player_spawn = Vector3(0, 0.1, 20)
var boss_spawn = Vector3(0, 0.1, -20)
var flickers = []
var env
var water_mat
var lava_mat
var vc_mat
var metal
var moss = 0.0

# ================================================================ entry
func build(idx, c):
    cfg = c
    rng.seed = 4242 + idx * 101
    vc_mat = _vc_mat()
    metal = _mat(Color(0.12, 0.12, 0.15), 0.0, 0.5)
    water_mat = ShaderMaterial.new()
    water_mat.shader = WaterShader
    lava_mat = ShaderMaterial.new()
    lava_mat.shader = LavaShader
    _make_env(idx)
    if idx == 0:
        _level1()
    elif idx == 1:
        _level2()
    else:
        _level3()

func tick(t):
    for f in flickers:
        f[0].light_energy = f[1] * (0.85 + 0.15 * sin(t * 9.0 + f[2]) + 0.1 * sin(t * 23.0 + f[2] * 2.0))

func walkable(p, margin = 1.5):
    if bounds_kind == "rect":
        if absf(p.x) > bounds.x - 3.0 or absf(p.y) > bounds.y - 3.0:
            return false
    else:
        if p.length() > bounds.x - 3.0:
            return false
    for c in circles:
        if p.distance_to(c[0]) < c[1] + margin:
            return false
    for r in rects:
        var d = (p - r[0]).abs()
        if d.x < r[1].x + margin and d.y < r[1].y + margin:
            return false
    return true

# ================================================================ environment
func _make_env(idx):
    env = Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = cfg["fog"]
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = cfg["ambient"]
    env.ambient_light_energy = 1.0
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.fog_enabled = true
    env.fog_light_color = cfg["fog"]
    env.fog_density = 0.008
    env.glow_enabled = true
    env.glow_intensity = 0.8
    env.glow_bloom = 0.05
    env.ssao_enabled = true
    env.ssr_enabled = idx < 2
    env.volumetric_fog_enabled = true
    env.volumetric_fog_density = 0.012
    env.volumetric_fog_albedo = cfg["fog"].lightened(0.35)
    env.volumetric_fog_length = 60.0
    var we = WorldEnvironment.new()
    we.environment = env
    add_child(we)

    var sun = DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
    sun.light_color = cfg["light"]
    sun.light_energy = [1.0, 0.55, 0.45][idx]
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 90.0
    add_child(sun)

# ================================================================ small helpers
func _mat(c, emit = 0.0, rough = 0.9):
    var m = StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = rough
    if emit > 0.0:
        m.emission_enabled = true
        m.emission = c
        m.emission_energy_multiplier = emit
    return m

func _vc_mat(rough = 0.95):
    var m = StandardMaterial3D.new()
    m.vertex_color_use_as_albedo = true
    m.albedo_color = Color.WHITE
    m.roughness = rough
    return m

func _unshaded(c):
    var m = StandardMaterial3D.new()
    m.albedo_color = c
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    return m

func _bm(size):
    var b = BoxMesh.new()
    b.size = size
    return b

func _cm(rt, rb, h, seg = 12):
    var c = CylinderMesh.new()
    c.top_radius = rt
    c.bottom_radius = rb
    c.height = h
    c.radial_segments = seg
    c.rings = 1
    return c

func _sm(r, seg = 8, rings = 5):
    var s = SphereMesh.new()
    s.radius = r
    s.height = r * 2.0
    s.radial_segments = seg
    s.rings = rings
    return s

func _mesh(parent, mesh, material, pos, rot = Vector3.ZERO, shadow = true):
    var mi = MeshInstance3D.new()
    mi.mesh = mesh
    mi.material_override = material
    mi.position = pos
    mi.rotation_degrees = rot
    if not shadow:
        mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(mi)
    return mi

func _static_box(parent, pos, size, rot_y = 0.0):
    var body = StaticBody3D.new()
    body.collision_layer = 1
    body.position = pos
    body.rotation_degrees.y = rot_y
    var cs = CollisionShape3D.new()
    var sh = BoxShape3D.new()
    sh.size = size
    cs.shape = sh
    body.add_child(cs)
    parent.add_child(body)
    return body

func _static_cyl(parent, pos, radius, height):
    var body = StaticBody3D.new()
    body.collision_layer = 1
    body.position = pos
    var cs = CollisionShape3D.new()
    var sh = CylinderShape3D.new()
    sh.radius = radius
    sh.height = height
    cs.shape = sh
    body.add_child(cs)
    parent.add_child(body)
    return body

func _block_rect(pos, size, rot_y):
    var ry = fposmod(absf(rot_y), 180.0)
    if ry < 1.0 or ry > 179.0:
        rects.append([Vector2(pos.x, pos.z), Vector2(size.x, size.z) / 2.0])
    elif absf(ry - 90.0) < 1.0:
        rects.append([Vector2(pos.x, pos.z), Vector2(size.z, size.x) / 2.0])
    else:
        circles.append([Vector2(pos.x, pos.z), maxf(size.x, size.z) / 2.0])

func _solid_box(pos, size, material, rot_y = 0.0, block = true):
    var body = _static_box(self, pos, size, rot_y)
    _mesh(body, _bm(size), material, Vector3.ZERO)
    if block:
        _block_rect(pos, size, rot_y)
    return body

func _multi(mesh, xforms, cols, material, cast_shadow = true):
    if xforms.size() == 0:
        return null
    var mm = MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.use_colors = cols.size() > 0
    mm.mesh = mesh
    mm.instance_count = xforms.size()
    for i in range(xforms.size()):
        mm.set_instance_transform(i, xforms[i])
        if cols.size() > 0:
            mm.set_instance_color(i, cols[i])
    var mmi = MultiMeshInstance3D.new()
    mmi.multimesh = mm
    mmi.material_override = material
    if not cast_shadow:
        mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(mmi)
    return mmi

func _lamp(pos, color, energy = 2.0, rng_range = 14.0, flicker = true):
    var l = OmniLight3D.new()
    l.position = pos
    l.light_color = color
    l.light_energy = energy
    l.omni_range = rng_range
    add_child(l)
    if flicker:
        flickers.append([l, energy, rng.randf() * 10.0])
    return l

func _particles(center, extents, amount, color, size, vmin, vmax, grav = Vector3.ZERO, life = 10.0):
    var p = CPUParticles3D.new()
    p.amount = amount
    p.lifetime = life
    p.preprocess = life
    p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
    p.emission_box_extents = extents
    p.direction = Vector3.UP
    p.spread = 180.0
    p.initial_velocity_min = vmin
    p.initial_velocity_max = vmax
    p.gravity = grav
    p.local_coords = false
    var m = _sm(size, 4, 2)
    m.material = _unshaded(color)
    p.mesh = m
    p.position = center
    p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(p)
    p.emitting = true

# ================================================================ structures
# A wall of individual bricks (MultiMesh) around a solid core. 'ruin' knocks
# bricks out near the top, 'crenel' adds battlements.
func _brick_wall(a, b, height, thick, color, ruin = 0.0, crenel = false):
    var d = b - a
    d.y = 0.0
    var L = d.length()
    if L < 0.5:
        return
    var dir = d / L
    var yaw = atan2(-dir.z, dir.x)
    var nrm = Vector3(-dir.z, 0.0, dir.x)
    var mid = (a + b) * 0.5

    var ch = maxf(1.0, height - 0.8)
    var csize = Vector3(L, ch, thick - 0.5)
    var body = _static_box(self, Vector3(mid.x, a.y + ch / 2.0, mid.z), csize, rad_to_deg(yaw))
    _mesh(body, _bm(csize), _mat(color.darkened(0.3)), Vector3.ZERO)

    var xf = []
    var cols = []
    var brick_l = 1.4
    var brick_h = 0.5
    var rows = int(height / brick_h)
    var basis = Basis(Vector3.UP, yaw)
    var n = int(L / brick_l) + 1
    for side in [-1.0, 1.0]:
        var off = nrm * side * (thick / 2.0 - 0.2)
        for r in range(rows):
            var frac = float(r) / float(rows)
            var shift = 0.0
            if r % 2 == 1:
                shift = brick_l * 0.5
            for i in range(n):
                var u = -L / 2.0 + brick_l * (float(i) + 0.5) + shift - brick_l * 0.5
                if absf(u) > L / 2.0 - 0.2:
                    continue
                if ruin > 0.0 and rng.randf() < ruin * frac * frac * 1.6:
                    continue
                var k = rng.randf_range(0.7, 1.15)
                var c = Color(color.r * k, color.g * k, color.b * k)
                if moss > 0.0 and r < 4:
                    c = c.lerp(Color(0.12, 0.3, 0.12), moss)
                var pos = Vector3(mid.x, a.y + brick_h * (float(r) + 0.5), mid.z) + dir * u + off
                xf.append(Transform3D(basis, pos))
                cols.append(c)
    _multi(_bm(Vector3(brick_l - 0.06, brick_h - 0.05, 0.5)), xf, cols, vc_mat, false)

    if crenel:
        var mxf = []
        var mcols = []
        var m = 0
        var u2 = -L / 2.0 + 1.0
        while u2 < L / 2.0 - 0.5:
            if rng.randf() > ruin * 0.8:
                var k2 = rng.randf_range(0.75, 1.1)
                mxf.append(Transform3D(basis, Vector3(mid.x, a.y + height + 0.5, mid.z) + dir * u2))
                mcols.append(Color(color.r * k2, color.g * k2, color.b * k2))
            u2 += 2.4
            m += 1
        _multi(_bm(Vector3(1.2, 1.0, thick - 0.2)), mxf, mcols, vc_mat, false)

func _tower(c, size, h, color, ruin):
    var hs = size / 2.0
    var corners = [Vector3(-hs, 0, -hs), Vector3(hs, 0, -hs), Vector3(hs, 0, hs), Vector3(-hs, 0, hs)]
    for i in range(4):
        _brick_wall(c + corners[i], c + corners[(i + 1) % 4], h, 2.2, color, ruin, true)
    _solid_box(c + Vector3(0, h + 0.3, 0), Vector3(size, 0.6, size), _mat(color.darkened(0.3)), 0.0, false)
    circles.append([Vector2(c.x, c.z), size * 0.8])
    var warm = _mat(Color(1.0, 0.65, 0.3), 2.8)
    for s in [-1.0, 1.0]:
        _mesh(self, _bm(Vector3(0.5, 1.5, 0.3)), warm, c + Vector3(s * 1.5, h * 0.55, hs + 0.2), Vector3.ZERO, false)
        _mesh(self, _bm(Vector3(0.5, 1.5, 0.3)), warm, c + Vector3(s * 1.5, h * 0.85, hs + 0.2), Vector3.ZERO, false)

# Gothic arch in the local XY plane (width along X). Optional ruin removes stones.
func _arch(pos, width, h_straight, depth, thick, material, yaw_deg = 0.0, collide = true, ruin = 0.0):
    var piv = Node3D.new()
    piv.position = pos
    piv.rotation_degrees.y = yaw_deg
    add_child(piv)
    var px = width / 2.0 + thick / 2.0
    for s in [-1.0, 1.0]:
        var size = Vector3(thick, h_straight, depth)
        if collide:
            var body = _static_box(piv, Vector3(s * px, h_straight / 2.0, 0), size)
            _mesh(body, _bm(size), material, Vector3.ZERO)
        else:
            _mesh(piv, _bm(size), material, Vector3(s * px, h_straight / 2.0, 0), Vector3.ZERO, false)
    var n = 11
    var rm = width / 2.0 + thick / 2.0
    var arc = PI * rm / float(n)
    for i in range(n):
        if ruin > 0.0 and rng.randf() < ruin and i > 1 and i < n - 2:
            continue
        var ang = PI * (float(i) + 0.5) / float(n)
        var p = Vector3(cos(ang) * rm, h_straight + sin(ang) * rm, 0)
        _mesh(piv, _bm(Vector3(thick, arc * 1.04, depth)), material, p, Vector3(0, 0, rad_to_deg(ang)), false)
    return piv

func _rubble(pos, radius, count, material):
    for i in range(count):
        var s = rng.randf_range(0.2, 0.7)
        var a = rng.randf() * TAU
        var rr = rng.randf() * radius
        _mesh(self, _bm(Vector3(s, s * rng.randf_range(0.5, 1.0), s * rng.randf_range(0.6, 1.2))), material,
            Vector3(pos.x + cos(a) * rr, s * 0.3, pos.z + sin(a) * rr), Vector3(rng.randf_range(-20, 20), rng.randf() * 360.0, rng.randf_range(-20, 20)), false)

func _pillar(pos, h, r, material, broken = false):
    var body = StaticBody3D.new()
    body.collision_layer = 1
    body.position = pos
    add_child(body)
    var cs = CollisionShape3D.new()
    var sh = CylinderShape3D.new()
    sh.radius = r
    sh.height = h
    cs.shape = sh
    cs.position.y = h / 2.0
    body.add_child(cs)
    _mesh(body, _bm(Vector3(r * 2.7, 0.5, r * 2.7)), material, Vector3(0, 0.25, 0))
    var sh_h = h
    if broken:
        sh_h = h * rng.randf_range(0.4, 0.7)
    _mesh(body, _cm(r * 0.88, r, sh_h, 12), material, Vector3(0, 0.5 + sh_h / 2.0, 0))
    if not broken:
        _mesh(body, _bm(Vector3(r * 2.5, 0.5, r * 2.5)), material, Vector3(0, h + 0.75, 0))
        _mesh(body, _bm(Vector3(r * 3.0, 0.3, r * 3.0)), material, Vector3(0, h + 1.15, 0))
    else:
        _mesh(self, _cm(r * 0.88, r * 0.9, h * 0.35, 10), material,
            pos + Vector3(r * 2.4, r * 0.9, r * 1.4), Vector3(0, rng.randf() * 360.0, 90))
        _rubble(pos, r * 3.0, 9, material)
    circles.append([Vector2(pos.x, pos.z), r * 1.4])

func _tree(pos, s, leaf_color, dead = false):
    var body = _static_cyl(self, pos + Vector3(0, 2.0 * s, 0), 0.5 * s, 4.0 * s)
    var bark = _mat(Color(0.14, 0.1, 0.07))
    _mesh(body, _cm(0.35 * s, 0.6 * s, 5.0 * s, 7), bark, Vector3(0, 0.5 * s, 0))
    if dead:
        for i in range(5):
            var a = rng.randf() * 360.0
            _mesh(self, _cm(0.05 * s, 0.18 * s, 3.0 * s, 5), bark,
                pos + Vector3(0, rng.randf_range(3.0, 5.0) * s, 0), Vector3(rng.randf_range(30, 60), a, 0), false)
    else:
        for i in range(6):
            var k = rng.randf_range(0.75, 1.2)
            var lc = Color(leaf_color.r * k, leaf_color.g * k, leaf_color.b * k)
            var lp = pos + Vector3(rng.randf_range(-1.6, 1.6) * s, rng.randf_range(4.2, 6.8) * s, rng.randf_range(-1.6, 1.6) * s)
            _mesh(self, _sm(rng.randf_range(1.6, 2.6) * s, 7, 4), _mat(lc), lp, Vector3.ZERO, false)
    circles.append([Vector2(pos.x, pos.z), 0.9 * s])

func _statue(pos, yaw, material):
    var body = _static_box(self, pos + Vector3(0, 0.5, 0), Vector3(1.8, 1.0, 1.8), yaw)
    _mesh(body, _bm(Vector3(1.8, 1.0, 1.8)), material, Vector3.ZERO)
    var piv = Node3D.new()
    piv.position = pos + Vector3(0, 1.0, 0)
    piv.rotation_degrees.y = yaw
    add_child(piv)
    _mesh(piv, _cm(0.5, 0.78, 1.5, 8), material, Vector3(0, 0.75, 0), Vector3.ZERO, false)
    _mesh(piv, _bm(Vector3(1.05, 0.35, 0.5)), material, Vector3(0, 1.65, 0), Vector3.ZERO, false)
    _mesh(piv, _sm(0.28, 6, 4), material, Vector3(0, 2.1, 0), Vector3.ZERO, false)
    _mesh(piv, _cm(0.0, 0.3, 0.55, 6), material, Vector3(0, 2.45, 0), Vector3.ZERO, false)
    _mesh(piv, _bm(Vector3(0.12, 2.3, 0.12)), metal, Vector3(0.55, 1.15, -0.45), Vector3.ZERO, false)
    _mesh(piv, _bm(Vector3(0.6, 0.12, 0.12)), metal, Vector3(0.55, 2.2, -0.45), Vector3.ZERO, false)
    circles.append([Vector2(pos.x, pos.z), 1.3])

func _grave(pos, yaw, material):
    var body = _static_box(self, pos + Vector3(0, 0.65, 0), Vector3(0.9, 1.3, 0.3), yaw)
    _mesh(body, _bm(Vector3(0.9, 1.3, 0.3)), material, Vector3.ZERO, Vector3.ZERO, false)
    _mesh(body, _cm(0.45, 0.45, 0.3, 8), material, Vector3(0, 0.65, 0), Vector3(90, 0, 0), false)
    circles.append([Vector2(pos.x, pos.z), 0.8])

func _sarcophagus(pos, yaw, material):
    var size = Vector3(2.4, 1.0, 1.2)
    var body = _static_box(self, pos + Vector3(0, 0.5, 0), size, yaw)
    _mesh(body, _bm(size), material, Vector3.ZERO)
    _mesh(body, _bm(Vector3(2.6, 0.3, 1.4)), material, Vector3(0, 0.65, 0))
    _block_rect(pos, size, yaw)

func _lantern_post(pos, color):
    var body = _static_cyl(self, pos + Vector3(0, 1.6, 0), 0.2, 3.2)
    _mesh(body, _bm(Vector3(0.16, 3.2, 0.16)), metal, Vector3.ZERO, Vector3.ZERO, false)
    _mesh(body, _bm(Vector3(0.7, 0.1, 0.1)), metal, Vector3(0, 1.5, 0), Vector3.ZERO, false)
    _mesh(body, _bm(Vector3(0.4, 0.55, 0.4)), _mat(color, 3.5), Vector3(0, 1.3, 0), Vector3.ZERO, false)
    _lamp(pos + Vector3(0, 3.1, 0), color, 2.2, 12.0)
    circles.append([Vector2(pos.x, pos.z), 0.5])

func _brazier(pos, color, energy = 3.0):
    _solid_box(pos + Vector3(0, 0.6, 0), Vector3(1.0, 1.2, 1.0), _mat(Color(0.12, 0.1, 0.1)))
    var fl = _mesh(self, _cm(0.0, 0.5, 1.2, 6), _mat(color, 4.0), pos + Vector3(0, 1.8, 0), Vector3.ZERO, false)
    _mesh(self, _bm(Vector3(1.2, 0.15, 1.2)), metal, pos + Vector3(0, 1.25, 0), Vector3.ZERO, false)
    _lamp(pos + Vector3(0, 2.6, 0), color, energy, 18.0)

func _crystals(pos, color, count):
    var m = _mat(color, 3.0, 0.2)
    for i in range(count):
        var h = rng.randf_range(1.2, 3.4)
        _mesh(self, _cm(0.0, rng.randf_range(0.25, 0.5), h, 5), m,
            pos + Vector3(rng.randf_range(-0.9, 0.9), h / 2.0, rng.randf_range(-0.9, 0.9)),
            Vector3(rng.randf_range(-18, 18), rng.randf() * 360.0, rng.randf_range(-18, 18)), false)
    _lamp(pos + Vector3(0, 2.0, 0), color, 2.4, 13.0, false)
    circles.append([Vector2(pos.x, pos.z), 1.5])

func _chandelier(pos):
    _mesh(self, _cm(0.04, 0.04, 3.0, 4), metal, pos + Vector3(0, 1.5, 0), Vector3.ZERO, false)
    var t = TorusMesh.new()
    t.inner_radius = 1.3
    t.outer_radius = 1.55
    var ring = _mesh(self, t, metal, pos, Vector3.ZERO, false)
    for i in range(8):
        var a = TAU * i / 8.0
        _mesh(self, _bm(Vector3(0.12, 0.35, 0.12)), _mat(Color(1.0, 0.8, 0.4), 4.0),
            pos + Vector3(cos(a) * 1.4, 0.25, sin(a) * 1.4), Vector3.ZERO, false)
    _lamp(pos + Vector3(0, -0.3, 0), Color(1.0, 0.75, 0.4), 3.2, 17.0)

func _flat_ring(r, color, y = 0.03, width = 0.2):
    var t = TorusMesh.new()
    t.inner_radius = r - width
    t.outer_radius = r + width
    t.rings = 64
    t.ring_segments = 4
    var mi = _mesh(self, t, _mat(color, 2.5), Vector3(0, y, 0), Vector3.ZERO, false)
    mi.scale = Vector3(1, 0.1, 1)

# ---------------------------------------------------------------- grass / water / lava
func _blade(st, ang, ox, oz, lean, w):
    var b = Basis(Vector3.UP, ang)
    var pts = [Vector3(-w, 0, 0), Vector3(w, 0, 0), Vector3(-w * 0.7, 0.5, lean * 0.3), Vector3(w * 0.7, 0.5, lean * 0.3), Vector3(0, 1.0, lean)]
    var uvy = [0.0, 0.0, 0.5, 0.5, 1.0]
    var tris = [[0, 1, 2], [1, 3, 2], [2, 3, 4]]
    for t in tris:
        for idx in t:
            st.set_normal(Vector3.UP)
            st.set_uv(Vector2(0.5, uvy[idx]))
            st.add_vertex(b * pts[idx] + Vector3(ox, 0, oz))

func _grass_mesh():
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in range(4):
        _blade(st, 0.8 * i + rng.randf() * 0.3, rng.randf_range(-0.18, 0.18), rng.randf_range(-0.18, 0.18), rng.randf_range(-0.25, 0.25), 0.07)
    return st.commit()

func _grass(rect, count, exclude, hmin = 0.8, hmax = 1.7, base = Color(0.03, 0.14, 0.05), tip = Color(0.28, 0.7, 0.25)):
    var xf = []
    var cols = []
    var tries = 0
    while xf.size() < count and tries < count * 4:
        tries += 1
        var p = Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
        if exclude.call(p):
            continue
        var s = rng.randf_range(hmin, hmax)
        var b = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(0.8, 1.3), s, rng.randf_range(0.8, 1.3)))
        xf.append(Transform3D(b, Vector3(p.x, 0.0, p.y)))
        var k = rng.randf_range(0.7, 1.25)
        cols.append(Color(k, k, k))
    var gm = ShaderMaterial.new()
    gm.shader = GrassShader
    gm.set_shader_parameter("base_color", base)
    gm.set_shader_parameter("tip_color", tip)
    _multi(_grass_mesh(), xf, cols, gm, false)

func _specks(rect, count, exclude, color, hmin, hmax, size = 0.07):
    var xf = []
    var tries = 0
    while xf.size() < count and tries < count * 4:
        tries += 1
        var p = Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
        if exclude.call(p):
            continue
        xf.append(Transform3D(Basis.IDENTITY, Vector3(p.x, rng.randf_range(hmin, hmax), p.y)))
    _multi(_sm(size, 4, 2), xf, [], _unshaded(color), false)

func _water_disc(c, r, y = 0.06):
    _mesh(self, _cm(r, r, 0.04, 40), water_mat, Vector3(c.x, y, c.z), Vector3.ZERO, false)

func _water_rect(c, size, y = 0.05):
    var pm = PlaneMesh.new()
    pm.size = size
    _mesh(self, pm, water_mat, Vector3(c.x, y, c.z), Vector3.ZERO, false)

func _pool_rect(c, size, kerb_mat):
    _water_rect(c, size)
    var hx = size.x / 2.0
    var hz = size.y / 2.0
    _solid_box(Vector3(c.x, 0.4, c.z - hz - 0.25), Vector3(size.x + 1.0, 0.8, 0.5), kerb_mat, 0.0, false)
    _solid_box(Vector3(c.x, 0.4, c.z + hz + 0.25), Vector3(size.x + 1.0, 0.8, 0.5), kerb_mat, 0.0, false)
    _solid_box(Vector3(c.x - hx - 0.25, 0.4, c.z), Vector3(0.5, 0.8, size.y), kerb_mat, 0.0, false)
    _solid_box(Vector3(c.x + hx + 0.25, 0.4, c.z), Vector3(0.5, 0.8, size.y), kerb_mat, 0.0, false)
    rects.append([Vector2(c.x, c.z), size / 2.0 + Vector2(0.6, 0.6)])

func _lava_pool(c, r):
    _mesh(self, _cm(r, r, 0.04, 36), lava_mat, Vector3(c.x, 0.05, c.z), Vector3.ZERO, false)
    _static_cyl(self, Vector3(c.x, 0.5, c.z), r, 1.0)
    circles.append([Vector2(c.x, c.z), r])
    var rock = _mat(Color(0.1, 0.05, 0.06), 0.0, 0.5)
    var n = int(r * 3.5)
    for i in range(n):
        var a = TAU * float(i) / float(n)
        var s = rng.randf_range(0.4, 0.9)
        var m = _mesh(self, _sm(s, 6, 4), rock, Vector3(c.x + cos(a) * (r + 0.3), s * 0.3, c.z + sin(a) * (r + 0.3)), Vector3.ZERO, false)
        m.scale = Vector3(1.0, 0.6, 1.0)
    _lamp(Vector3(c.x, 2.5, c.z), Color(1.0, 0.45, 0.1), 4.0, 17.0)

func _pond(c, r, rock_mat):
    _water_disc(c, r)
    _static_cyl(self, Vector3(c.x, 0.5, c.z), r - 0.2, 1.0)
    circles.append([Vector2(c.x, c.z), r])
    var n = int(r * 3.0)
    for i in range(n):
        var a = TAU * float(i) / float(n) + rng.randf_range(-0.1, 0.1)
        var rr = r + rng.randf_range(0.0, 0.9)
        var s = rng.randf_range(0.5, 1.2)
        var m = _mesh(self, _sm(s, 6, 4), rock_mat, Vector3(c.x + cos(a) * rr, s * 0.3, c.z + sin(a) * rr), Vector3(0, rng.randf() * 360.0, 0), false)
        m.scale = Vector3(1.2, 0.6, 1.0)
    var rxf = []
    var rcols = []
    for i in range(int(r * 9.0)):
        var a2 = rng.randf() * TAU
        var rr2 = r + rng.randf_range(-0.6, 1.3)
        var sy = rng.randf_range(0.6, 1.5)
        rxf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1, sy, 1)), Vector3(c.x + cos(a2) * rr2, 0.9 * sy, c.z + sin(a2) * rr2)))
        var k = rng.randf_range(0.6, 1.1)
        rcols.append(Color(0.2 * k, 0.5 * k, 0.4 * k))
    _multi(_bm(Vector3(0.05, 1.8, 0.05)), rxf, rcols, vc_mat, false)
    var lxf = []
    for i in range(int(r * 2.5)):
        var a3 = rng.randf() * TAU
        var rr3 = rng.randf() * (r - 1.0)
        lxf.append(Transform3D(Basis.IDENTITY, Vector3(c.x + cos(a3) * rr3, 0.09, c.z + sin(a3) * rr3)))
    _multi(_cm(0.5, 0.5, 0.03, 10), lxf, [], _mat(Color(0.1, 0.4, 0.15)), false)

# ================================================================ LEVEL 1
func _ex_l1(p):
    if absf(p.x) < 3.4 and p.y > -26.0:
        return true
    if p.y < -27.0:
        return true
    for c in circles:
        if p.distance_to(c[0]) < c[1] + 0.3:
            return true
    for r in rects:
        var d = (p - r[0]).abs()
        if d.x < r[1].x + 0.3 and d.y < r[1].y + 0.3:
            return true
    return false

func _level1():
    bounds_kind = "rect"
    bounds = Vector2(32, 30)
    zone = Rect2(-24, -17, 48, 34)
    player_spawn = Vector3(0, 0.1, 22)
    boss_spawn = Vector3(0, 0.1, -19)
    moss = 0.35
    var stone = Color(0.42, 0.47, 0.5)
    var stone_mat = _mat(stone)
    var rock_mat = _mat(Color(0.3, 0.34, 0.34))
    var dirt_mat = _mat(Color(0.2, 0.15, 0.1))

    # ground + invisible boundaries
    _solid_box(Vector3(0, -0.5, 0), Vector3(70, 1, 66), _mat(Color(0.06, 0.14, 0.07)), 0.0, false)
    _static_box(self, Vector3(34, 3, 0), Vector3(4, 6, 70))
    _static_box(self, Vector3(-34, 3, 0), Vector3(4, 6, 70))
    _static_box(self, Vector3(0, 3, 32), Vector3(70, 6, 4))
    _static_box(self, Vector3(0, 3, -32), Vector3(22, 6, 3))

    # ---- ruined castle wall with a grand arched gate (north)
    _brick_wall(Vector3(-33, 0, -30), Vector3(-16, 0, -30), 10.0, 3.0, stone, 0.55, true)
    _brick_wall(Vector3(16, 0, -30), Vector3(33, 0, -30), 10.0, 3.0, stone, 0.45, true)
    _tower(Vector3(-12.5, 0, -29), 7.0, 15.0, stone, 0.5)
    _tower(Vector3(12.5, 0, -29), 7.0, 15.0, stone, 0.4)
    _arch(Vector3(0, 0, -30), 8.0, 5.0, 3.2, 1.4, stone_mat, 0.0, true)
    _brick_wall(Vector3(-9.0, 0, -30), Vector3(-5.4, 0, -30), 12.0, 3.0, stone, 0.3, true)
    _brick_wall(Vector3(5.4, 0, -30), Vector3(9.0, 0, -30), 12.0, 3.0, stone, 0.3, true)
    _brick_wall(Vector3(-5.4, 9.7, -30), Vector3(5.4, 9.7, -30), 3.5, 3.0, stone, 0.2, true)
    _mesh(self, _bm(Vector3(14, 12, 1)), _mat(Color(0.004, 0.004, 0.008)), Vector3(0, 6, -34), Vector3.ZERO, false)
    for s in [-1.0, 1.0]:
        _mesh(self, _bm(Vector3(0.4, 0.2, 0.2)), _mat(Color(1.0, 0.15, 0.1), 5.0), Vector3(s * 0.9, 3.2, -33.2), Vector3.ZERO, false)
    for i in range(9):
        _mesh(self, _bm(Vector3(0.12, 3.2, 0.12)), metal, Vector3(-3.6 + i * 0.9, 6.2, -29.6), Vector3.ZERO, false)

    # broken wall fragments inside the courtyard
    _brick_wall(Vector3(-24, 0, -11), Vector3(-17, 0, -13), 4.0, 1.6, stone, 0.8, false)
    _brick_wall(Vector3(19, 0, -15), Vector3(26, 0, -14), 5.0, 1.6, stone, 0.8, false)
    _brick_wall(Vector3(-28, 0, 9), Vector3(-28, 0, 19), 4.0, 1.6, stone, 0.7, false)
    _brick_wall(Vector3(27, 0, 14), Vector3(27, 0, 24), 3.5, 1.6, stone, 0.85, false)

    # dirt path + stepping stones
    _mesh(self, _bm(Vector3(6, 0.04, 56)), dirt_mat, Vector3(0, 0.02, 0), Vector3.ZERO, false)
    for i in range(16):
        var sz = 26.0 - i * 3.2
        _mesh(self, _bm(Vector3(rng.randf_range(1.2, 2.2), 0.08, rng.randf_range(0.9, 1.4))), stone_mat,
            Vector3(rng.randf_range(-1.6, 1.6), 0.05, sz), Vector3(0, rng.randf_range(-20, 20), 0), false)

    # columns lining the path (some broken)
    for z in [18.0, 6.0, -6.0, -15.0]:
        for sx in [-1.0, 1.0]:
            _pillar(Vector3(sx * 8.5, 0, z), 7.0, 0.9, stone_mat, rng.randf() < 0.45)

    # statues flanking the gate
    _statue(Vector3(-15.5, 0, -24.5), 10.0, stone_mat)
    _statue(Vector3(15.5, 0, -24.5), -10.0, stone_mat)

    # graveyard
    for i in range(10):
        _grave(Vector3(20.0 + (i % 5) * 2.6 + rng.randf_range(-0.4, 0.4), 0, -8.0 + int(i / 5) * 3.2), rng.randf_range(-12, 12), stone_mat)

    # ponds (the dark reflective water from the reference)
    water_mat.set_shader_parameter("deep_color", Color(0.008, 0.025, 0.045))
    water_mat.set_shader_parameter("sky_tint", Color(0.12, 0.28, 0.32))
    _pond(Vector3(14, 0, 12), 8.5, rock_mat)
    _pond(Vector3(-19, 0, -4), 5.0, rock_mat)

    # trees: dense tree line around the courtyard, autumn trees near the wall
    var leaf = Color(0.08, 0.28, 0.1)
    for i in range(14):
        _tree(Vector3(-31.0 + rng.randf_range(-1, 1), 0, -26.0 + i * 4.0), rng.randf_range(1.2, 1.8), leaf)
        _tree(Vector3(31.0 + rng.randf_range(-1, 1), 0, -26.0 + i * 4.0), rng.randf_range(1.2, 1.8), leaf)
    for i in range(14):
        var tx = -28.0 + i * 4.3
        if absf(tx) > 5.0:
            _tree(Vector3(tx, 0, 30.0 + rng.randf_range(-1, 0.5)), rng.randf_range(1.2, 1.8), leaf)
    var orange = Color(0.85, 0.4, 0.08)
    _tree(Vector3(-17, 0, -23), 1.5, orange)
    _tree(Vector3(18, 0, -21), 1.4, orange)
    _tree(Vector3(-27, 0, -8), 1.3, orange)
    _tree(Vector3(24, 0, 2), 1.3, orange)

    # lantern posts along the path
    for z in [20.0, 8.0, -4.0, -14.0]:
        for sx in [-1.0, 1.0]:
            _lantern_post(Vector3(sx * 4.4, 0, z), Color(1.0, 0.7, 0.35))

    # hanging banners and vines on the castle wall
    for x in [-26.0, -21.0, 21.0, 26.0]:
        _mesh(self, _bm(Vector3(1.7, 4.2, 0.1)), _mat(Color(0.8, 0.33, 0.08), 0.6), Vector3(x, 6.0, -28.15), Vector3.ZERO, false)
    var vxf = []
    var vcols = []
    for i in range(170):
        var vx = rng.randf_range(-31.0, 31.0)
        if absf(vx) < 9.5:
            continue
        var vh = rng.randf_range(1.5, 4.5)
        vxf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1, vh, 1)), Vector3(vx, rng.randf_range(4.0, 9.0), -28.2)))
        var k = rng.randf_range(0.6, 1.1)
        vcols.append(Color(0.08 * k, 0.3 * k, 0.1 * k))
    _multi(_bm(Vector3(0.1, 1.0, 0.1)), vxf, vcols, vc_mat, false)

    # tall grass, grass flowers and fireflies
    var grass_rect = Rect2(-31, -27, 62, 57)
    _grass(grass_rect, 18000, _ex_l1, 0.8, 1.7)
    _specks(grass_rect, 700, _ex_l1, Color(1.0, 1.0, 0.9), 0.4, 1.5)
    _specks(grass_rect, 120, _ex_l1, Color(1.0, 0.85, 0.3), 0.3, 1.0, 0.09)
    _particles(Vector3(0, 2.5, 0), Vector3(30, 2.5, 28), 260, Color(0.9, 1.0, 0.7), 0.07, 0.1, 0.45)

# ================================================================ LEVEL 2
func _level2():
    bounds_kind = "rect"
    bounds = Vector2(35, 22)
    zone = Rect2(-12, -14, 24, 31)
    player_spawn = Vector3(0, 0.1, 18)
    boss_spawn = Vector3(0, 0.1, -9)
    var stone = Color(0.28, 0.36, 0.42)
    var stone_mat = _mat(stone)
    var kerb_mat = _mat(Color(0.2, 0.28, 0.33))
    var accent = cfg["accent"]

    _solid_box(Vector3(0, -0.5, 0), Vector3(78, 1, 50), _mat(Color(0.07, 0.11, 0.15)), 0.0, false)
    var line_mat = _mat(Color(0.03, 0.05, 0.07))
    var lx = []
    var lz = []
    for i in range(-9, 10):
        lx.append(Transform3D(Basis.IDENTITY, Vector3(i * 4.0, 0.02, 0)))
    for i in range(-5, 6):
        lz.append(Transform3D(Basis.IDENTITY, Vector3(0, 0.02, i * 4.0)))
    _multi(_bm(Vector3(0.14, 0.03, 46)), lx, [], line_mat, false)
    _multi(_bm(Vector3(76, 0.03, 0.14)), lz, [], line_mat, false)

    # hall walls (open to the dark sky)
    _brick_wall(Vector3(-38, 0, -24), Vector3(38, 0, -24), 14.0, 3.0, stone, 0.1, false)
    _brick_wall(Vector3(-38, 0, 24), Vector3(38, 0, 24), 14.0, 3.0, stone, 0.1, false)
    _brick_wall(Vector3(-37.5, 0, -24), Vector3(-37.5, 0, 24), 14.0, 3.0, stone, 0.1, false)
    _brick_wall(Vector3(37.5, 0, -24), Vector3(37.5, 0, 24), 14.0, 3.0, stone, 0.1, false)

    # colonnades with lintels and rib-vault arches spanning the nave
    for sx in [-1.0, 1.0]:
        for z in [-18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 18.0]:
            _pillar(Vector3(sx * 13.0, 0, z), 10.5, 1.1, stone_mat, false)
        _solid_box(Vector3(sx * 13.0, 12.6, 0), Vector3(1.4, 0.8, 38), stone_mat, 0.0, false)
    for z in [-15.0, -5.0, 5.0, 15.0]:
        _arch(Vector3(0, 13.0, z), 24.0, 0.5, 1.2, 0.9, stone_mat, 0.0, false, 0.12)

    # flooded pools: two in the nave, two big ones in the side aisles
    water_mat.set_shader_parameter("deep_color", Color(0.0, 0.05, 0.09))
    water_mat.set_shader_parameter("sky_tint", Color(accent.r * 0.4, accent.g * 0.4, accent.b * 0.4))
    _pool_rect(Vector3(-8, 0, 2), Vector2(7, 14), kerb_mat)
    _pool_rect(Vector3(8, 0, 2), Vector2(7, 14), kerb_mat)
    _pool_rect(Vector3(-26, 0, 0), Vector2(18, 40), kerb_mat)
    _pool_rect(Vector3(26, 0, 0), Vector2(18, 40), kerb_mat)

    # islands with statues and glowing crystals in the aisle pools
    var isl = [[-24, -12], [-28, 0], [-24, 12], [24, -12], [28, 0], [24, 12]]
    for i in range(isl.size()):
        var ix = float(isl[i][0])
        var iz = float(isl[i][1])
        _solid_box(Vector3(ix, 0.3, iz), Vector3(5, 0.6, 5), stone_mat, 0.0, false)
        if i % 2 == 0:
            _statue(Vector3(ix, 0.6, iz), 0.0, stone_mat)
        else:
            _crystals(Vector3(ix, 0.6, iz), accent, 6)
    for sx in [-1.0, 1.0]:
        _crystals(Vector3(sx * 32.0, 0.0, 18.0), accent, 5)
        _crystals(Vector3(sx * 32.0, 0.0, -18.0), accent, 5)
    for i in range(10):
        var px = rng.randf_range(18.0, 33.0) * (1.0 if i % 2 == 0 else -1.0)
        _pillar(Vector3(px, 0, rng.randf_range(-17.0, 17.0)), 4.0, 0.7, stone_mat, true)

    # dais, altar and the glowing rune ring behind the boss
    _solid_box(Vector3(0, 0.4, -18), Vector3(16, 0.8, 8), stone_mat)
    _solid_box(Vector3(0, 1.2, -19.5), Vector3(11, 0.8, 5), stone_mat)
    _solid_box(Vector3(0, 0.15, -13.6), Vector3(10, 0.3, 1.2), stone_mat)
    _solid_box(Vector3(0, 2.2, -20.5), Vector3(4, 1.2, 2), _mat(Color(0.1, 0.14, 0.18)))
    var tor = TorusMesh.new()
    tor.inner_radius = 3.7
    tor.outer_radius = 4.3
    _mesh(self, tor, _mat(accent, 3.2), Vector3(0, 8.0, -21.7), Vector3(90, 0, 0), false)
    _mesh(self, _cm(3.7, 3.7, 0.1, 32), _mat(accent, 0.7), Vector3(0, 8.0, -21.9), Vector3(90, 0, 0), false)
    _lamp(Vector3(0, 8.0, -19.0), accent, 3.5, 20.0, false)

    # sarcophagi, colonnade statues, chandeliers
    _sarcophagus(Vector3(-10, 0, -16), 15.0, stone_mat)
    _sarcophagus(Vector3(10, 0, -16), -15.0, stone_mat)
    for sx in [-1.0, 1.0]:
        _statue(Vector3(sx * 11.0, 0, -12.0), sx * -90.0, stone_mat)
        _statue(Vector3(sx * 11.0, 0, 12.0), sx * -90.0, stone_mat)
    for z in [-8.0, 2.0, 12.0]:
        _chandelier(Vector3(0, 9.0, z))

    # hanging banners
    for z in [-14.0, -4.0, 6.0, 16.0]:
        for sx in [-1.0, 1.0]:
            _mesh(self, _bm(Vector3(0.1, 5.0, 1.8)), _mat(Color(0.05, 0.25, 0.35), 0.4), Vector3(sx * 35.9, 8.0, z), Vector3.ZERO, false)

    _particles(Vector3(0, 5.0, 0), Vector3(34, 5, 21), 240, Color(0.4, 1.0, 0.9), 0.07, 0.1, 0.4)

# ================================================================ LEVEL 3
func _level3():
    bounds_kind = "circle"
    bounds = Vector2(34, 0)
    zone = Rect2(-24, -24, 48, 48)
    player_spawn = Vector3(0, 0.1, 26)
    boss_spawn = Vector3(0, 0.1, -19)
    var obs = Color(0.17, 0.09, 0.1)
    var obs_mat = _mat(obs, 0.0, 0.5)
    var ember = Color(1.0, 0.45, 0.1)

    # circular obsidian floor with glowing inlay rings
    var fb = _static_cyl(self, Vector3(0, -0.5, 0), 38.0, 1.0)
    _mesh(fb, _cm(38.0, 38.0, 1.0, 48), obs_mat, Vector3.ZERO)
    for r in [6.0, 12.5, 24.5]:
        _flat_ring(r, ember)

    # outer cathedral wall (ring of brick segments) with buttress columns
    var N = 32
    for i in range(N):
        var a0 = TAU * float(i) / float(N)
        var a1 = TAU * float(i + 1) / float(N)
        _brick_wall(Vector3(cos(a0) * 37.0, 0, sin(a0) * 37.0), Vector3(cos(a1) * 37.0, 0, sin(a1) * 37.0), 16.0, 3.0, obs.lightened(0.15), 0.2, false)
    for i in range(16):
        var ab = TAU * float(i) / 16.0
        _pillar(Vector3(cos(ab) * 34.4, 0, sin(ab) * 34.4), 15.0, 1.3, obs_mat, false)

    # tall gothic windows glowing like stained glass
    var glass = _mat(Color(1.0, 0.5, 0.15), 2.6)
    for i in range(12):
        var aw = TAU * (float(i) + 0.5) / 12.0
        var wp = Vector3(cos(aw) * 35.0, 0, sin(aw) * 35.0)
        var yaw = rad_to_deg(atan2(-cos(aw), -sin(aw)))
        _arch(Vector3(wp.x * 0.99, 4.0, wp.z * 0.99), 3.0, 5.0, 0.8, 0.7, obs_mat, yaw, false)
        _mesh(self, _bm(Vector3(3.0, 11.0, 0.15)), glass, Vector3(wp.x, 8.0, wp.z), Vector3(0, yaw, 0), false)

    # lava pools (impassable) ringed with obsidian
    for i in range(6):
        var al = deg_to_rad(60.0 * float(i))
        _lava_pool(Vector3(cos(al) * 17.5, 0, sin(al) * 17.5), 4.5)

    # burnt cathedral columns, obsidian spires, braziers
    for i in range(6):
        var ac = deg_to_rad(30.0 + 60.0 * float(i))
        _pillar(Vector3(cos(ac) * 11.0, 0, sin(ac) * 11.0), 11.0, 1.0, obs_mat, i % 3 == 1)
    var spire_mat = _mat(Color(0.05, 0.02, 0.04), 0.0, 0.25)
    for i in range(8):
        var asp = deg_to_rad(15.0 + 45.0 * float(i))
        var sp = Vector3(cos(asp) * 27.0, 0, sin(asp) * 27.0)
        var sh = rng.randf_range(7.0, 11.0)
        var body = _static_cyl(self, sp + Vector3(0, sh / 2.0, 0), 1.0, sh)
        _mesh(body, _cm(0.0, 1.5, sh, 5), spire_mat, Vector3.ZERO)
        circles.append([Vector2(sp.x, sp.z), 1.6])
    for i in range(8):
        var abz = deg_to_rad(22.5 + 45.0 * float(i))
        _brazier(Vector3(cos(abz) * 29.5, 0, sin(abz) * 29.5), ember, 3.4)

    # skull throne behind the boss arena
    _solid_box(Vector3(0, 0.6, -28), Vector3(4, 1.2, 3.5), obs_mat)
    _solid_box(Vector3(0, 4.5, -30.2), Vector3(4.6, 9.0, 1.0), obs_mat)
    for i in range(5):
        _mesh(self, _cm(0.0, 0.4, 2.4, 5), obs_mat, Vector3(-2.0 + i, 10.0, -30.2), Vector3.ZERO, false)
    _mesh(self, _cm(1.0, 1.0, 0.1, 20), _mat(ember, 3.0), Vector3(0, 6.5, -29.6), Vector3(90, 0, 0), false)
    _lamp(Vector3(0, 6.5, -27.5), ember, 3.5, 16.0)

    # glowing floor cracks
    var cxf = []
    var tries = 0
    while cxf.size() < 150 and tries < 800:
        tries += 1
        var cp = Vector2(rng.randf_range(-30, 30), rng.randf_range(-30, 30))
        if not walkable(cp, 0.5):
            continue
        cxf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(0.6, 2.0), 1, 1)), Vector3(cp.x, 0.025, cp.y)))
    _multi(_bm(Vector3(2.5, 0.03, 0.08)), cxf, [], _mat(ember, 2.4), false)

    # rising embers and falling ash
    _particles(Vector3(0, 6.0, 0), Vector3(30, 6, 30), 320, Color(1.0, 0.5, 0.15), 0.08, 0.2, 0.8, Vector3(0, 1.3, 0), 9.0)
    _particles(Vector3(0, 12.0, 0), Vector3(30, 8, 30), 200, Color(0.55, 0.45, 0.45), 0.06, 0.1, 0.3, Vector3(0, -0.7, 0), 14.0)
