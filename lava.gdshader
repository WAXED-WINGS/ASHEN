shader_type spatial;

varying vec3 wpos;

void vertex() {
    wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float t = TIME;
    vec2 p = wpos.xz;
    float n = sin(p.x * 0.8 + t * 0.6) * sin(p.y * 0.7 - t * 0.5);
    n += 0.5 * sin(p.x * 1.9 - t * 0.8 + sin(p.y * 1.3 + t));
    float v = smoothstep(-0.4, 1.0, n);
    vec3 hot = mix(vec3(0.55, 0.06, 0.0), vec3(1.0, 0.7, 0.1), v);
    ALBEDO = vec3(0.05, 0.01, 0.0);
    EMISSION = hot * 2.4;
    ROUGHNESS = 0.6;
}
