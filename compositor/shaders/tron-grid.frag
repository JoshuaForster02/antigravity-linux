#version 300 es
precision highp float;

in vec2 v_uv;
out vec4 out_color;

uniform float u_time;
uniform vec2  u_resolution;

// ── TRON color palette ────────────────────────────────────────────────────────
const vec3 BG       = vec3(0.02, 0.04, 0.10);
const vec3 GRID     = vec3(0.04, 0.14, 0.22);
const vec3 ENERGY   = vec3(0.10, 0.55, 0.80);
const vec3 BRIGHT   = vec3(0.20, 0.87, 1.00);

// ── Grid ─────────────────────────────────────────────────────────────────────
float grid(vec2 uv, float step, float line_w) {
    vec2 cell = mod(uv, step);
    float lx = step(cell.x, line_w) + step(step - line_w, cell.x);
    float ly = step(cell.y, line_w) + step(step - line_w, cell.y);
    return max(lx, ly);
}

// ── Energy trace (moving pulse along a line) ──────────────────────────────────
float trace(vec2 uv, float speed, float width, float seed) {
    float phase = mod(u_time * speed + seed, 1.0);
    float dist  = abs(uv.x - phase);
    return smoothstep(width, 0.0, dist) * smoothstep(0.0, 0.02, uv.y) * smoothstep(0.02, 0.0, uv.y - 0.02);
}

void main() {
    vec2 uv = v_uv * u_resolution;

    // Main grid (40px spacing)
    float g40 = grid(uv, 40.0, 0.7);
    // Sub-grid (8px, fainter)
    float g8  = grid(uv, 8.0,  0.4) * 0.25;

    // Animated energy pulse (moves horizontally)
    float pulse = 0.5 + 0.5 * sin(u_time * 0.6);
    vec2  uv_n  = v_uv;
    float tr1   = trace(uv_n, 0.08, 0.004, 0.0) * 0.6;
    float tr2   = trace(uv_n, 0.05, 0.003, 0.37) * 0.4;
    float tr3   = trace(vec2(1.0 - uv_n.x, uv_n.y), 0.06, 0.003, 0.7) * 0.3;

    // Radial vignette (darker at edges, brighter in center)
    float vignette = 1.0 - length(v_uv - 0.5) * 0.6;
    vignette = clamp(vignette, 0.0, 1.0);

    // Compose
    vec3 color = BG;
    color = mix(color, GRID,   (g40 + g8) * 0.85 * vignette);
    color = mix(color, ENERGY, (g40 * (tr1 + tr2 + tr3)) * pulse);
    color += BRIGHT * (tr1 + tr2 + tr3) * 0.15 * vignette;

    // Subtle scanline flicker
    float scan = 0.97 + 0.03 * sin(uv.y * 2.0 + u_time * 30.0);
    color *= scan;

    out_color = vec4(color, 1.0);
}
