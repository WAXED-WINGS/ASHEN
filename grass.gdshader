shader_type spatial;
render_mode cull_disabled;

uniform vec3 base_color : source_color = vec3(0.03, 0.14, 0.05);
uniform vec3 tip_color : source_color = vec3(0.28, 0.7, 0.25);
uniform float sway = 0.3;

varying vec3 inst_col;

void vertex() {
    inst_col = COLOR.rgb;
    float h = UV.y;
    vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float w = sin(TIME * 1.5 + wp.x * 0.6 + wp.z * 0.45) * sway * h * h;
    VERTEX.x += w;
    VERTEX.z += w * 0.6;
}

void fragment() {
    ALBEDO = mix(base_color, tip_color, UV.y) * inst_col;
    ROUGHNESS = 0.9;
    NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}
