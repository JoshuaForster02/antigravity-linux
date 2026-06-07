/*
 * renderer.c — TRON visual rendering
 *
 * Draws:
 *   1. Animated grid background (GLSL shader)
 *   2. Glow borders around each window
 *   3. ANTIGRAVITY overlay (focus dim, palette backdrop)
 */
#include "flynn-compositor.h"
#include <math.h>
#include <string.h>

/* Full-screen quad: two triangles covering NDC [-1,1] */
static const float QUAD[] = {
    -1.0f, -1.0f,
     1.0f, -1.0f,
    -1.0f,  1.0f,
     1.0f,  1.0f,
};

/* ── Load shader source from disk ─────────────────────────────────────────── */
static char *load_file(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    rewind(f);
    char *buf = malloc(sz + 1);
    if (!buf) { fclose(f); return NULL; }
    fread(buf, 1, sz, f);
    buf[sz] = '\0';
    fclose(f);
    return buf;
}

/* ── Init GL resources ────────────────────────────────────────────────────── */
bool renderer_init(struct flynn_server *srv) {
    /* Quad VBO */
    glGenBuffers(1, &srv->quad_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, srv->quad_vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(QUAD), QUAD, GL_STATIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);

    /* Grid shader */
    char *vert = load_file(SHADER_DIR "/tron-grid.vert");
    char *frag = load_file(SHADER_DIR "/tron-grid.frag");
    bool ok = (vert && frag) &&
              shader_compile(&srv->grid_shader, vert, frag);
    free(vert); free(frag);
    if (!ok) {
        wlr_log(WLR_ERROR, "Failed to compile grid shader");
        return false;
    }

    /* Glow border shader */
    char *gv = load_file(SHADER_DIR "/tron-grid.vert");   /* reuse vert */
    char *gf = load_file(SHADER_DIR "/glow-border.frag");
    ok = (gv && gf) && shader_compile(&srv->glow_shader, gv, gf);
    free(gv); free(gf);
    if (!ok) {
        wlr_log(WLR_ERROR, "Failed to compile glow shader");
        return false;
    }

    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    srv->compositor_start = (float)t.tv_sec + t.tv_nsec * 1e-9f;

    wlr_log(WLR_INFO, "Flynn renderer initialized");
    return true;
}

/* ── Current time (seconds since compositor start) ───────────────────────── */
static float now(struct flynn_server *srv) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    float cur = (float)t.tv_sec + t.tv_nsec * 1e-9f;
    return cur - srv->compositor_start;
}

/* ── Draw animated TRON grid background ──────────────────────────────────── */
void renderer_draw_grid(struct flynn_output *out) {
    struct flynn_server *srv = out->server;
    int w = out->wlr_output->width;
    int h = out->wlr_output->height;

    shader_use(&srv->grid_shader);

    glUniform1f(srv->grid_shader.loc_time,       now(srv));
    glUniform2f(srv->grid_shader.loc_resolution, (float)w, (float)h);

    glBindBuffer(GL_ARRAY_BUFFER, srv->quad_vbo);
    GLint pos_loc = glGetAttribLocation(srv->grid_shader.program, "pos");
    glEnableVertexAttribArray(pos_loc);
    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 0, NULL);

    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    glDisableVertexAttribArray(pos_loc);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

/* ── Draw glow border around a window ────────────────────────────────────── */
void renderer_draw_window_glow(struct flynn_toplevel *top,
                                struct flynn_output *out) {
    struct flynn_server *srv = out->server;

    /* Animate glow toward target */
    float target = top->focused ? 1.0f : 0.25f;
    float speed  = top->focused ? FOCUS_SPEED : UNFOCUS_SPEED;
    float dt     = (float)(out->elapsed - 0.0);  /* simplified */
    top->glow   += (target - top->glow) * 0.1f;  /* lerp */

    /* Get window geometry */
    struct wlr_box box;
    wlr_xdg_surface_get_geometry(top->xdg_toplevel->base, &box);

    /* Expand box by BORDER_WIDTH + GLOW_RADIUS for the glow rect */
    int pad = BORDER_WIDTH + GLOW_RADIUS;
    float ox = (float)(box.x - pad);
    float oy = (float)(box.y - pad);
    float ow = (float)(box.width  + pad * 2);
    float oh = (float)(box.height + pad * 2);

    int sw = out->wlr_output->width;
    int sh = out->wlr_output->height;

    /* Convert to NDC */
    float nx = (ox / sw) * 2.0f - 1.0f;
    float ny = 1.0f - ((oy + oh) / sh) * 2.0f;
    float nw = (ow / sw) * 2.0f;
    float nh = (oh / sh) * 2.0f;

    float verts[] = {
        nx,      ny,
        nx + nw, ny,
        nx,      ny + nh,
        nx + nw, ny + nh,
    };

    shader_use(&srv->glow_shader);
    glUniform1f(srv->glow_shader.loc_glow, top->glow);
    glUniform1f(srv->glow_shader.loc_time, now(srv));

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glBindBuffer(GL_ARRAY_BUFFER, srv->quad_vbo);
    /* Upload per-window quad */
    glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof(verts), verts);

    GLint pos_loc = glGetAttribLocation(srv->glow_shader.program, "pos");
    glEnableVertexAttribArray(pos_loc);
    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 0, NULL);

    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    glDisableVertexAttribArray(pos_loc);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glDisable(GL_BLEND);
}

/* ── Draw ANTIGRAVITY overlay (focus dim / palette) ──────────────────────── */
void renderer_draw_overlay(struct flynn_server *srv,
                            struct flynn_output *out) {
    if (srv->ag_mode == AG_MODE_NORMAL && !srv->palette_open) return;

    /* Semi-transparent dark overlay */
    float alpha = srv->palette_open ? 0.55f :
                  (srv->ag_mode == AG_MODE_FOCUS ? 0.40f : 0.0f);
    if (alpha <= 0.0f) return;

    /* Use the grid shader with zero energy to get a dark tinted rect */
    /* Simpler: just render a solid dark quad using glClear-like approach */
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    /* We use the glow shader with glow=0 as a simple colored quad */
    shader_use(&srv->glow_shader);
    glUniform1f(srv->glow_shader.loc_glow, 0.0f);

    glBindBuffer(GL_ARRAY_BUFFER, srv->quad_vbo);
    glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof(QUAD), QUAD);

    GLint pos_loc = glGetAttribLocation(srv->glow_shader.program, "pos");
    glEnableVertexAttribArray(pos_loc);
    glVertexAttribPointer(pos_loc, 2, GL_FLOAT, GL_FALSE, 0, NULL);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glDisableVertexAttribArray(pos_loc);
    glBindBuffer(GL_ARRAY_BUFFER, 0);

    glDisable(GL_BLEND);
}
