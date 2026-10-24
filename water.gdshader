shader_type spatial;
render_mode specular_schlick_ggx;

// Dark glassy water with moving ripples. Combined with screen-space
// reflections (enabled in the level environment) it mirrors the scene.

uniform vec3 deep_color : source_color = vec3(0.01, 0.03, 0.05);
uniform vec3 sky_tint : source_color = vec3(0.1, 0.25, 0.3);
uniform float ripple = 1.0;

varying vec3 wpos;

void vertex() {
    wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float t = TIME;
    vec2 p = wpos.xz;
    vec2 g = vec2(0.0);
    g += 0.50 * cos(dot(p, vec2(0.9, 0.3)) + t * 1.1) * vec2(0.9, 0.3);
    g += 0.40 * cos(dot(p, vec2(-0.4, 1.1)) + t * 1.4) * vec2(-0.4, 1.1);
    g += 0.25 * cos(dot(p, vec2(2.1, 1.5)) + t * 2.0) * vec2(2.1, 1.5);
    g += 0.15 * cos(dot(p, vec2(-1.7, 2.6)) + t * 2.6) * vec2(-1.7, 2.6);
    g *= 0.12 * ripple;
    vec3 n_world = normalize(vec3(-g.x, 1.0, -g.y));
    NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
    ALBEDO = deep_color;
    ROUGHNESS = 0.05;
    METALLIC = 0.0;
    SPECULAR = 0.9;
    float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
    EMISSION = sky_tint * fres * 0.5;
}
