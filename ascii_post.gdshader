shader_type canvas_item;

// Full-screen ASCII renderer.
// Every cell becomes a glyph picked by brightness (. : * o & 8 @ #),
// and on strong edges it switches to line glyphs (| - / \) so grass blades,
// castle walls and water ripples read like the reference video.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float cell_size = 8.0;
uniform float exposure = 1.9;
uniform float edge_threshold = 0.24;
uniform vec3 bg_tint = vec3(0.02, 0.06, 0.04);

float character(int n, vec2 uv) {
    vec2 p = floor(uv * vec2(-4.0, 4.0) + 2.5);
    if (clamp(p.x, 0.0, 4.0) == p.x && clamp(p.y, 0.0, 4.0) == p.y) {
        int a = int(round(p.x) + 5.0 * round(p.y));
        if (((n >> a) & 1) == 1) {
            return 1.0;
        }
    }
    return 0.0;
}

vec3 cell_color(vec2 cell, vec2 res) {
    return texture(screen_tex, (cell + 0.5) * cell_size / res).rgb;
}

float gray_of(vec3 c) {
    return clamp(dot(c, vec3(0.299, 0.587, 0.114)) * exposure, 0.0, 1.0);
}

void fragment() {
    vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
    vec2 pix = SCREEN_UV * res;
    vec2 cell = floor(pix / cell_size);

    vec3 col = cell_color(cell, res);
    float g = gray_of(col);

    float gl = gray_of(cell_color(cell + vec2(-1.0, 0.0), res));
    float gr = gray_of(cell_color(cell + vec2(1.0, 0.0), res));
    float gu = gray_of(cell_color(cell + vec2(0.0, -1.0), res));
    float gd = gray_of(cell_color(cell + vec2(0.0, 1.0), res));
    float gx = gr - gl;
    float gy = gd - gu;
    float mag = length(vec2(gx, gy));

    int n = 0;
    if (g > 0.08) n = 4096;      // .
    if (g > 0.2)  n = 65600;     // :
    if (g > 0.3)  n = 332772;    // *
    if (g > 0.4)  n = 15255086;  // o
    if (g > 0.5)  n = 23385164;  // &
    if (g > 0.6)  n = 15252014;  // 8
    if (g > 0.7)  n = 13199452;  // @
    if (g > 0.82) n = 11512810;  // #

    if (mag > edge_threshold && g > 0.1) {
        float ax = abs(gx);
        float ay = abs(gy);
        if (ax > ay * 2.0) {
            n = 4329604;         // |
        } else if (ay > ax * 2.0) {
            n = 31744;           // -
        } else if (gx * gy > 0.0) {
            n = 1118480;         // /
        } else {
            n = 17043521;        // backslash
        }
    }

    vec2 p = fract(pix / cell_size) * 2.0 - 1.0;
    p.y = -p.y;
    float ch = character(n, p);

    float m = max(max(col.r, col.g), col.b);
    vec3 hue = col / max(m, 0.02);
    vec3 glyph = hue * clamp(0.5 + g, 0.0, 1.45);
    vec3 bg = col * 0.14 + bg_tint;

    COLOR = vec4(bg + glyph * ch, 1.0);
}
