#pragma once
/*
 * Flynn OS Wayland Compositor — Master Header
 * Built on wlroots. Provides:
 *   - Animated TRON grid desktop (OpenGL ES shaders)
 *   - Glow borders on windows (active = bright cyan, inactive = dim)
 *   - Floating window manager with keyboard-driven movement
 *   - ANTIGRAVITY IPC protocol (for ⌘K palette, focus mode, panels)
 */

#define WLR_USE_UNSTABLE
#include <wlr/backend.h>
#include <wlr/render/wlr_renderer.h>
#include <wlr/render/allocator.h>
#include <wlr/render/egl.h>
#include <wlr/types/wlr_compositor.h>
#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <wlr/types/wlr_seat.h>
#include <wlr/types/wlr_keyboard.h>
#include <wlr/types/wlr_layer_shell_v1.h>
#include <wlr/types/wlr_screencopy_v1.h>
#include <wlr/util/log.h>
#include <wayland-server-core.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <time.h>
#include <stdbool.h>
#include <stdint.h>

/* ── TRON Color Constants ────────────────────────────────────────────────── */
#define TRON_BG_R       0.02f
#define TRON_BG_G       0.04f
#define TRON_BG_B       0.10f
#define TRON_CYAN_R     0.10f
#define TRON_CYAN_G     0.55f
#define TRON_CYAN_B     0.80f
#define TRON_BRIGHT_R   0.20f
#define TRON_BRIGHT_G   0.87f
#define TRON_BRIGHT_B   1.00f
#define TRON_DIM_R      0.04f
#define TRON_DIM_G      0.14f
#define TRON_DIM_B      0.22f

/* ── Compositor config ───────────────────────────────────────────────────── */
#define BORDER_WIDTH     2       /* px — window border thickness */
#define GLOW_RADIUS      8       /* px — outer glow spread */
#define FOCUS_SPEED      4.0f   /* glow animation speed (focused) */
#define UNFOCUS_SPEED    2.0f

/* ── ANTIGRAVITY overlay modes ───────────────────────────────────────────── */
typedef enum {
    AG_MODE_NORMAL   = 0,
    AG_MODE_FOCUS    = 1,   /* all windows except active dimmed 80% */
    AG_MODE_OVERVIEW = 2,   /* all windows tiled, bird's eye view */
    AG_MODE_GAME     = 3,   /* fullscreen, no decorations */
} ag_mode_t;

/* ── Forward declarations ────────────────────────────────────────────────── */
struct flynn_server;
struct flynn_output;
struct flynn_toplevel;

/* ── GL shader program ───────────────────────────────────────────────────── */
typedef struct {
    GLuint program;
    GLint  loc_time;
    GLint  loc_resolution;
    GLint  loc_glow;
    GLint  loc_tex;
} flynn_shader_t;

/* ── Output (monitor) ────────────────────────────────────────────────────── */
struct flynn_output {
    struct wl_list          link;
    struct flynn_server    *server;
    struct wlr_output      *wlr_output;

    /* Frame timing */
    struct timespec         last_frame;
    float                   elapsed;      /* seconds since compositor start */

    /* Listeners */
    struct wl_listener      frame;
    struct wl_listener      request_state;
    struct wl_listener      destroy;
};

/* ── Toplevel window ─────────────────────────────────────────────────────── */
struct flynn_toplevel {
    struct wl_list          link;
    struct flynn_server    *server;
    struct wlr_xdg_toplevel *xdg_toplevel;
    struct wlr_scene_tree  *scene_tree;

    /* TRON glow state */
    bool                    focused;
    float                   glow;         /* 0.0 (dim) → 1.0 (bright) */

    /* Window position (floating) */
    int                     x, y;
    bool                    moving;
    double                  grab_x, grab_y;

    /* Listeners */
    struct wl_listener      map;
    struct wl_listener      unmap;
    struct wl_listener      destroy;
    struct wl_listener      request_move;
    struct wl_listener      request_resize;
    struct wl_listener      request_fullscreen;
};

/* ── Main server ─────────────────────────────────────────────────────────── */
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

    struct wl_list              outputs;
    struct wl_list              toplevels;

    /* Shaders */
    flynn_shader_t              grid_shader;
    flynn_shader_t              glow_shader;
    GLuint                      quad_vbo;

    /* ANTIGRAVITY state */
    ag_mode_t                   ag_mode;
    bool                        palette_open;
    int                         active_workspace;   /* 1-9 */
    float                       compositor_start;   /* epoch for u_time */

    /* Listeners */
    struct wl_listener          new_output;
    struct wl_listener          new_xdg_toplevel;
    struct wl_listener          cursor_motion;
    struct wl_listener          cursor_motion_absolute;
    struct wl_listener          cursor_button;
    struct wl_listener          cursor_axis;
    struct wl_listener          new_input;
    struct wl_listener          request_cursor;
    struct wl_listener          request_set_selection;
};

/* ── Function declarations ───────────────────────────────────────────────── */
/* shader.c */
bool          shader_compile(flynn_shader_t *s,
                              const char *vert_src, const char *frag_src);
void          shader_use(const flynn_shader_t *s);

/* renderer.c */
void          renderer_draw_grid(struct flynn_output *out);
void          renderer_draw_window_glow(struct flynn_toplevel *top,
                                        struct flynn_output *out);
void          renderer_draw_overlay(struct flynn_server *srv,
                                    struct flynn_output *out);

/* wm.c */
void          wm_focus(struct flynn_server *srv, struct flynn_toplevel *top);
void          wm_tile(struct flynn_server *srv);
void          wm_set_mode(struct flynn_server *srv, ag_mode_t mode);
struct flynn_toplevel *wm_toplevel_at(struct flynn_server *srv,
                                      double lx, double ly,
                                      struct wlr_surface **surface,
                                      double *sx, double *sy);

/* ipc.c */
void          ipc_init(struct flynn_server *srv);
void          ipc_accept(void);
void          ipc_broadcast(struct flynn_server *srv,
                             const char *event, const char *payload);
void          ipc_handle_incoming(struct flynn_server *srv);
void          ipc_destroy(void);

/* renderer.c */
bool          renderer_init(struct flynn_server *srv);
