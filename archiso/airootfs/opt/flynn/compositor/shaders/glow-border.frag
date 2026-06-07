#version 300 es
precision highp float;

in vec2 v_uv;
out vec4 out_color;

uniform sampler2D u_tex;
uniform float     u_glow;    // 0.0 = inactive, 1.0 = focused
uniform float     u_time;

// ── Multi-layer glow on window borders ───────────────────────────────────────
// UV (0,0) = top-left corner of the bordered region
// Border width is handled in the compositor by rendering a slightly
// larger rect under each window.

const vec3 CYAN_DIM    = vec3(0.05, 0.30, 0.45);
const vec3 CYAN_MID    = vec3(0.10, 0.55, 0.75);
const vec3 CYAN_BRIGHT = vec3(0.20, 0.87, 1.00);
const vec3 WHITE       = vec3(1.00, 1.00, 1.00);

void main() {
    // Distance from edge (0 = edge, 1 = center)
    float edge = min(min(v_uv.x, v_uv.y),
                     min(1.0 - v_uv.x, 1.0 - v_uv.y));
    float border = 1.0 - smoothstep(0.0, 0.015, edge);

    // Pulse animation for focused window
    float pulse = 0.8 + 0.2 * sin(u_time * 3.0);

    // Layer 1: wide outer glow
    float outer = 1.0 - smoothstep(0.0, 0.04, edge);
    // Layer 2: sharp inner border
    float inner = 1.0 - smoothstep(0.0, 0.008, edge);

    vec3 glow_color = mix(CYAN_DIM, CYAN_BRIGHT, u_glow);
    vec3 color = vec3(0.0);
    color += glow_color * outer * 0.35 * u_glow;
    color += glow_color * inner * 0.80;
    color += WHITE      * inner * 0.20 * u_glow * pulse;

    float alpha = (outer * 0.35 + inner * 0.80) * mix(0.4, 1.0, u_glow);
    out_color = vec4(color, clamp(alpha, 0.0, 1.0));
}
