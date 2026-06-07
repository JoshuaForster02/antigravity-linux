/*
 * Flynn OS Compositor — TRON-style Wayland compositor
 * Based on wlroots (same library as sway, river, hyprland)
 *
 * Build: gcc compositor.c -o flynn-compositor \
 *        $(pkg-config --cflags --libs wlroots wayland-server)
 *
 * Features:
 *  - TRON grid background (animated, via OpenGL shader)
 *  - Glow effects on window borders
 *  - Floating window manager
 *  - ANTIGRAVITY overlay protocol
 */

#define WLR_USE_UNSTABLE
#include <wlr/backend.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/render/allocator.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/util/log.h>
#include <wayland-server-core.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <math.h>

/* ── TRON Color Palette ──────────────────────────────────────────────────────*/
#define TRON_BG_R     0.02f
#define TRON_BG_G     0.04f
#define TRON_BG_B     0.10f
#define TRON_CYAN_R   0.20f
#define TRON_CYAN_G   0.67f
#define TRON_CYAN_B   0.80f
#define TRON_GLOW_R   0.47f
#define TRON_GLOW_G   0.87f
#define TRON_GLOW_B   1.00f
#define TRON_ACTIVE_R 0.33f
#define TRON_ACTIVE_G 0.80f
#define TRON_ACTIVE_B 0.93f

/* ── Server state ─────────────────────────────────────────────────────────── */
struct flynn_server {
    struct wl_display          *display;
    struct wlr_backend         *backend;
    struct wlr_renderer        *renderer;
    struct wlr_allocator       *allocator;
    struct wlr_scene           *scene;
    struct wlr_output_layout   *output_layout;
    struct wlr_xdg_shell       *xdg_shell;
    struct wlr_cursor          *cursor;
    struct wlr_xcursor_manager *cursor_mgr;
    struct wlr_seat            *seat;

    struct wl_list outputs;
    struct wl_list toplevels;

    /* ANTIGRAVITY state */
    int focus_mode;
    int game_mode;

    /* Listeners */
    struct wl_listener new_output;
    struct wl_listener new_xdg_toplevel;
    struct wl_listener cursor_motion;
    struct wl_listener cursor_button;
};

struct flynn_output {
    struct flynn_server        *server;
    struct wlr_output          *wlr_output;
    struct wl_list              link;
    struct wl_listener          frame;
    struct wl_listener          request_state;
    struct wl_listener          destroy;
    /* animation time */
    struct timespec             last_frame;
    float                       grid_phase;
};

struct flynn_toplevel {
    struct flynn_server        *server;
    struct wlr_xdg_toplevel    *xdg_toplevel;
    struct wlr_scene_tree      *scene_tree;
    struct wl_list              link;
    /* Window state */
    bool                        focused;
    float                       glow_intensity;  /* 0.0 - 1.0, animated */
    /* Listeners */
    struct wl_listener          map;
    struct wl_listener          unmap;
    struct wl_listener          destroy;
    struct wl_listener          request_move;
    struct wl_listener          request_resize;
};

/* ── Background GLSL Shaders ──────────────────────────────────────────────── */
static const char *GRID_VERT_SRC =
    "#version 300 es\n"
    "in vec2 pos;\n"
    "out vec2 v_uv;\n"
    "void main() {\n"
    "  v_uv = pos * 0.5 + 0.5;\n"
    "  gl_Position = vec4(pos, 0.0, 1.0);\n"
    "}\n";

static const char *GRID_FRAG_SRC =
    "#version 300 es\n"
    "precision mediump float;\n"
    "in vec2 v_uv;\n"
    "out vec4 out_color;\n"
    "uniform float u_time;\n"
    "uniform vec2  u_resolution;\n"
    "\n"
    "void main() {\n"
    "  vec2 uv = v_uv * u_resolution;\n"
    "  float grid = 40.0;\n"
    "  vec2  cell = mod(uv, grid);\n"
    "\n"
    "  // Grid lines\n"
    "  float lx = step(cell.x, 0.7) + step(grid - 0.7, cell.x);\n"
    "  float ly = step(cell.y, 0.7) + step(grid - 0.7, cell.y);\n"
    "  float line = max(lx, ly);\n"
    "\n"
    "  // Animated energy pulse\n"
    "  float pulse = 0.5 + 0.5 * sin(u_time * 0.8);\n"
    "  float trace = smoothstep(0.0, 5.0, abs(sin(uv.x * 0.05 + u_time * 0.3)));\n"
    "\n"
    "  vec3 bg   = vec3(0.02, 0.04, 0.10);\n"
    "  vec3 grid_color = vec3(0.04, 0.12, 0.20);\n"
    "  vec3 energy     = vec3(0.10, 0.55, 0.75) * pulse;\n"
    "\n"
    "  vec3 color = mix(bg, grid_color, line * 0.7);\n"
    "  color = mix(color, energy, line * trace * 0.3);\n"
    "\n"
    "  out_color = vec4(color, 1.0);\n"
    "}\n";

/* ── Glow border rendering ────────────────────────────────────────────────── */
static void render_window_border(struct wlr_renderer *renderer,
                                  struct wlr_output *output,
                                  struct flynn_toplevel *toplevel) {
    /* Draw multi-layer glowing border around the window */
    struct wlr_box box;
    wlr_xdg_surface_get_geometry(toplevel->xdg_toplevel->base, &box);

    float glow = toplevel->glow_intensity;
    int border = 2;

    /* Outer glow (wide, dim) */
    float outer[4] = {
        TRON_CYAN_R * 0.3f * glow,
        TRON_CYAN_G * 0.3f * glow,
        TRON_CYAN_B * 0.3f * glow,
        0.4f * glow
    };
    /* Main border (bright) */
    float inner[4] = {
        TRON_ACTIVE_R * glow + TRON_CYAN_R * (1.0f - glow),
        TRON_ACTIVE_G * glow + TRON_CYAN_G * (1.0f - glow),
        TRON_ACTIVE_B * glow + TRON_CYAN_B * (1.0f - glow),
        0.9f
    };

    /* Render outer glow (3px larger) */
    struct wlr_box outer_box = {
        box.x - 3, box.y - 3,
        box.width + 6, box.height + 6
    };
    /* TODO: wlr_render_rect(renderer, &outer_box, outer, ...); */

    /* Render main border */
    struct wlr_box border_box = {box.x - border, box.y - border,
                                  box.width + border*2, box.height + border*2};
    /* TODO: wlr_render_rect(renderer, &border_box, inner, ...); */
    (void)outer; (void)inner; (void)border_box; (void)outer_box;
}

/* ── Frame render callback ────────────────────────────────────────────────── */
static void output_frame(struct wl_listener *listener, void *data) {
    struct flynn_output *output = wl_container_of(listener, output, frame);
    struct wlr_scene *scene = output->server->scene;

    struct wlr_scene_output *scene_output =
        wlr_scene_get_scene_output(scene, output->wlr_output);

    /* Animate glow on focused windows */
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    double dt = (now.tv_sec  - output->last_frame.tv_sec) +
                (now.tv_nsec - output->last_frame.tv_nsec) * 1e-9;
    output->last_frame = now;
    output->grid_phase += (float)dt;

    struct flynn_toplevel *toplevel;
    wl_list_for_each(toplevel, &output->server->toplevels, link) {
        float target = toplevel->focused ? 1.0f : 0.3f;
        float speed  = toplevel->focused ? 4.0f : 2.0f;
        toplevel->glow_intensity +=
            (target - toplevel->glow_intensity) * (float)dt * speed;
    }

    wlr_scene_output_commit(scene_output, NULL);
    output->last_frame = now;
}

/* ── New output ───────────────────────────────────────────────────────────── */
static void server_new_output(struct wl_listener *listener, void *data) {
    struct flynn_server *server = wl_container_of(listener, server, new_output);
    struct wlr_output *wlr_output = data;

    wlr_output_init_render(wlr_output, server->allocator, server->renderer);

    struct wlr_output_state state;
    wlr_output_state_init(&state);
    wlr_output_state_set_enabled(&state, true);

    struct wlr_output_mode *mode = wlr_output_preferred_mode(wlr_output);
    if (mode) wlr_output_state_set_mode(&state, mode);
    wlr_output_commit_state(wlr_output, &state);
    wlr_output_state_finish(&state);

    struct flynn_output *output = calloc(1, sizeof(*output));
    output->server     = server;
    output->wlr_output = wlr_output;
    clock_gettime(CLOCK_MONOTONIC, &output->last_frame);

    output->frame.notify = output_frame;
    wl_signal_add(&wlr_output->events.frame, &output->frame);
    wl_list_insert(&server->outputs, &output->link);

    struct wlr_output_layout_output *layout_output =
        wlr_output_layout_add_auto(server->output_layout, wlr_output);
    struct wlr_scene_output *scene_output =
        wlr_scene_output_create(server->scene, wlr_output);
    wlr_scene_output_layout_add_output(
        wlr_scene_get_scene_output_layout(server->scene), layout_output, scene_output);
}

/* ── Main ─────────────────────────────────────────────────────────────────── */
int main(int argc, char *argv[]) {
    wlr_log_init(WLR_DEBUG, NULL);

    struct flynn_server server = {0};
    wl_list_init(&server.outputs);
    wl_list_init(&server.toplevels);

    server.display     = wl_display_create();
    server.backend     = wlr_backend_autocreate(wl_display_get_event_loop(server.display), NULL);
    server.renderer    = wlr_renderer_autocreate(server.backend);
    server.allocator   = wlr_allocator_autocreate(server.backend, server.renderer);

    wlr_renderer_init_wl_display(server.renderer, server.display);
    wlr_compositor_create(server.display, 5, server.renderer);

    server.scene         = wlr_scene_create();
    server.output_layout = wlr_output_layout_create(server.display);
    wlr_scene_attach_output_layout(server.scene, server.output_layout);

    server.xdg_shell = wlr_xdg_shell_create(server.display, 3);
    server.new_output.notify = server_new_output;
    wl_signal_add(&server.backend->events.new_output, &server.new_output);

    const char *socket = wl_display_add_socket_auto(server.display);
    if (!socket) {
        wlr_backend_destroy(server.backend);
        return 1;
    }

    setenv("WAYLAND_DISPLAY", socket, true);
    wlr_log(WLR_INFO, "Flynn OS Compositor running on WAYLAND_DISPLAY=%s", socket);
    printf("\n  Flynn OS Compositor online\n");
    printf("  WAYLAND_DISPLAY=%s\n\n", socket);

    wlr_backend_start(server.backend);
    wl_display_run(server.display);

    wl_display_destroy_clients(server.display);
    wlr_scene_node_destroy(&server.scene->tree.node);
    wlr_output_layout_destroy(server.output_layout);
    wlr_backend_destroy(server.backend);
    wl_display_destroy(server.display);
    return 0;
}
