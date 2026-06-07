/*
 * main.c — Flynn OS Wayland Compositor entry point
 *
 * Architecture:
 *   - wlroots backend (DRM/KMS on real hardware, X11/Wayland for testing)
 *   - Scene graph for window compositing
 *   - Custom OpenGL ES rendering layer (TRON grid + glow borders)
 *   - Floating window manager with Super+key shortcuts
 *   - ANTIGRAVITY IPC socket for cross-process control
 *
 * Build:
 *   meson setup build && ninja -C build
 *
 * Run:
 *   ./build/flynn-compositor
 *   (or via systemd: systemctl --user start flynn-compositor)
 */

#define WLR_USE_UNSTABLE
#include "flynn-compositor.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <xkbcommon/xkbcommon.h>

/* ── IPC fd callback — called by Wayland event loop when IPC socket readable ─ */
static int ipc_fd_cb(int fd, uint32_t mask, void *data) {
    (void)fd; (void)mask;
    ipc_handle_incoming((struct flynn_server *)data);
    return 0;
}

/* Exposed so ipc.c can hand back the server fd for registration */
extern int ipc_server_fd(void);

/* ── Keyboard input handler ───────────────────────────────────────────────── */
static void keyboard_handle_key(struct wl_listener *listener, void *data) {
    struct wlr_keyboard_key_event *event = data;
    struct wlr_seat *seat =
        ((struct wlr_keyboard*)listener->link.prev)->base.data;
    struct flynn_server *srv = seat->data;

    struct wlr_keyboard *kb = wlr_seat_get_keyboard(seat);
    if (!kb) return;

    xkb_keysym_t sym = xkb_state_key_get_one_sym(kb->xkb_state,
                                                   event->keycode + 8);
    uint32_t mods = wlr_keyboard_get_modifiers(kb);

    if (event->state == WL_KEYBOARD_KEY_STATE_PRESSED) {
        if (wm_handle_keybind(srv, mods, sym)) return;
    }

    /* Pass through to focused client */
    wlr_seat_keyboard_notify_key(seat, event->time_msec,
                                  event->keycode, event->state);
}

/* ── New keyboard device ─────────────────────────────────────────────────── */
static void server_new_keyboard(struct flynn_server *srv,
                                  struct wlr_input_device *device) {
    struct wlr_keyboard *kb = wlr_keyboard_from_input_device(device);

    /* US layout, no compose */
    struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_keymap  *map = xkb_keymap_new_from_names(ctx, NULL,
                                 XKB_KEYMAP_COMPILE_NO_FLAGS);
    wlr_keyboard_set_keymap(kb, map);
    xkb_keymap_unref(map);
    xkb_context_unref(ctx);
    wlr_keyboard_set_repeat_info(kb, 25, 600);

    static struct wl_listener key_listener;
    key_listener.notify = keyboard_handle_key;
    wl_signal_add(&kb->events.key, &key_listener);

    kb->base.data = srv;   /* back-pointer */
    wlr_seat_set_keyboard(srv->seat, kb);
}

/* ── New input device ────────────────────────────────────────────────────── */
static void server_new_input(struct wl_listener *listener, void *data) {
    struct flynn_server *srv =
        wl_container_of(listener, srv, new_input);
    struct wlr_input_device *device = data;

    switch (device->type) {
    case WLR_INPUT_DEVICE_KEYBOARD:
        server_new_keyboard(srv, device);
        break;
    case WLR_INPUT_DEVICE_POINTER:
        wlr_cursor_attach_input_device(srv->cursor, device);
        break;
    default:
        break;
    }

    uint32_t caps = WL_SEAT_CAPABILITY_POINTER;
    if (!wl_list_empty(&srv->seat->keyboards))
        caps |= WL_SEAT_CAPABILITY_KEYBOARD;
    wlr_seat_set_capabilities(srv->seat, caps);
}

/* ── Cursor motion ───────────────────────────────────────────────────────── */
static void server_cursor_motion(struct wl_listener *listener, void *data) {
    struct flynn_server *srv =
        wl_container_of(listener, srv, cursor_motion);
    struct wlr_pointer_motion_event *event = data;

    wlr_cursor_move(srv->cursor, &event->pointer->base,
                    event->delta_x, event->delta_y);

    /* Hit test + pointer focus */
    double sx, sy;
    struct wlr_surface *surface = NULL;
    struct flynn_toplevel *top =
        wm_toplevel_at(srv, srv->cursor->x, srv->cursor->y, &surface, &sx, &sy);

    if (!top) {
        wlr_cursor_set_xcursor(srv->cursor, srv->cursor_mgr, "default");
        wlr_seat_pointer_clear_focus(srv->seat);
    } else {
        wlr_seat_pointer_notify_enter(srv->seat, surface, sx, sy);
        wlr_seat_pointer_notify_motion(srv->seat, event->time_msec, sx, sy);
    }
}

/* ── Cursor button ───────────────────────────────────────────────────────── */
static void server_cursor_button(struct wl_listener *listener, void *data) {
    struct flynn_server *srv =
        wl_container_of(listener, srv, cursor_button);
    struct wlr_pointer_button_event *event = data;

    wlr_seat_pointer_notify_button(srv->seat, event->time_msec,
                                    event->button, event->state);

    if (event->state == WL_POINTER_BUTTON_STATE_PRESSED) {
        double sx, sy;
        struct wlr_surface *surface = NULL;
        struct flynn_toplevel *top =
            wm_toplevel_at(srv, srv->cursor->x, srv->cursor->y,
                           &surface, &sx, &sy);
        if (top) wm_focus(srv, top);
    }
}

/* ── Frame render callback ───────────────────────────────────────────────── */
static void output_handle_frame(struct wl_listener *listener, void *data) {
    struct flynn_output *out = wl_container_of(listener, out, frame);

    struct wlr_scene_output *scene_out =
        wlr_scene_get_scene_output(out->server->scene, out->wlr_output);

    /* Update elapsed time */
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    double dt = (now.tv_sec  - out->last_frame.tv_sec) +
                (now.tv_nsec - out->last_frame.tv_nsec) * 1e-9;
    out->elapsed += (float)dt;
    out->last_frame = now;

    /* 1. Draw animated TRON grid background */
    renderer_draw_grid(out);

    /* 2. Composite windows (via wlroots scene graph) */
    wlr_scene_output_commit(scene_out, NULL);

    /* 3. Draw glow borders on top */
    struct flynn_toplevel *top;
    wl_list_for_each(top, &out->server->toplevels, link)
        renderer_draw_window_glow(top, out);

    /* 4. ANTIGRAVITY overlay */
    renderer_draw_overlay(out->server, out);

    out->wlr_output->frame_pending = false;
}

/* ── New monitor ─────────────────────────────────────────────────────────── */
static void server_new_output(struct wl_listener *listener, void *data) {
    struct flynn_server *srv =
        wl_container_of(listener, srv, new_output);
    struct wlr_output *wlr_out = data;

    wlr_output_init_render(wlr_out, srv->allocator, srv->renderer);

    struct wlr_output_state state;
    wlr_output_state_init(&state);
    wlr_output_state_set_enabled(&state, true);

    struct wlr_output_mode *mode = wlr_output_preferred_mode(wlr_out);
    if (mode) wlr_output_state_set_mode(&state, mode);
    wlr_output_commit_state(wlr_out, &state);
    wlr_output_state_finish(&state);

    struct flynn_output *out = calloc(1, sizeof(*out));
    out->server     = srv;
    out->wlr_output = wlr_out;
    clock_gettime(CLOCK_MONOTONIC, &out->last_frame);

    out->frame.notify = output_handle_frame;
    wl_signal_add(&wlr_out->events.frame, &out->frame);
    wl_list_insert(&srv->outputs, &out->link);

    struct wlr_output_layout_output *lo =
        wlr_output_layout_add_auto(srv->output_layout, wlr_out);
    struct wlr_scene_output *so = wlr_scene_output_create(srv->scene, wlr_out);
    wlr_scene_output_layout_add_output(
        wlr_scene_get_scene_output_layout(srv->scene), lo, so);

    wlr_log(WLR_INFO, "New output: %s (%dx%d)",
            wlr_out->name, wlr_out->width, wlr_out->height);
}

/* ── XDG window map / unmap ──────────────────────────────────────────────── */
static void toplevel_handle_map(struct wl_listener *listener, void *data) {
    (void)data;
    struct flynn_toplevel *top =
        wl_container_of(listener, top, map);
    wm_focus(top->server, top);
}

static void toplevel_handle_unmap(struct wl_listener *listener, void *data) {
    (void)data;
    struct flynn_toplevel *top =
        wl_container_of(listener, top, unmap);
    top->focused = false;
}

static void toplevel_handle_destroy(struct wl_listener *listener, void *data) {
    (void)data;
    struct flynn_toplevel *top =
        wl_container_of(listener, top, destroy);
    wl_list_remove(&top->map.link);
    wl_list_remove(&top->unmap.link);
    wl_list_remove(&top->destroy.link);
    wl_list_remove(&top->link);
    free(top);
}

/* ── New XDG toplevel ────────────────────────────────────────────────────── */
static void server_new_xdg_toplevel(struct wl_listener *listener, void *data) {
    struct flynn_server *srv =
        wl_container_of(listener, srv, new_xdg_toplevel);
    struct wlr_xdg_toplevel *xdg_top = data;

    struct flynn_toplevel *top = calloc(1, sizeof(*top));
    top->server       = srv;
    top->xdg_toplevel = xdg_top;
    top->glow         = 0.25f;

    /* Place new window with slight cascade offset */
    int n = wl_list_length(&srv->toplevels);
    top->x = 80 + n * 30;
    top->y = 60 + n * 30;

    top->scene_tree = wlr_scene_xdg_surface_create(
        &srv->scene->tree, xdg_top->base);
    top->scene_tree->node.data = top;
    xdg_top->base->data        = top->scene_tree;

    wlr_scene_node_set_position(&top->scene_tree->node, top->x, top->y);

    top->map.notify     = toplevel_handle_map;
    top->unmap.notify   = toplevel_handle_unmap;
    top->destroy.notify = toplevel_handle_destroy;
    wl_signal_add(&xdg_top->base->surface->events.map,    &top->map);
    wl_signal_add(&xdg_top->base->surface->events.unmap,  &top->unmap);
    wl_signal_add(&xdg_top->events.destroy,               &top->destroy);

    wl_list_insert(&srv->toplevels, &top->link);
}

/* ── main ────────────────────────────────────────────────────────────────── */
int main(int argc, char *argv[]) {
    wlr_log_init(WLR_INFO, NULL);
    wlr_log(WLR_INFO, "Flynn OS Compositor starting...");

    struct flynn_server srv = {0};
    wl_list_init(&srv.outputs);
    wl_list_init(&srv.toplevels);
    srv.ag_mode = AG_MODE_NORMAL;

    srv.display   = wl_display_create();
    srv.backend   = wlr_backend_autocreate(
        wl_display_get_event_loop(srv.display), NULL);
    srv.renderer  = wlr_renderer_autocreate(srv.backend);
    srv.allocator = wlr_allocator_autocreate(srv.backend, srv.renderer);

    wlr_renderer_init_wl_display(srv.renderer, srv.display);
    wlr_compositor_create(srv.display, 5, srv.renderer);

    srv.scene         = wlr_scene_create();
    srv.output_layout = wlr_output_layout_create(srv.display);
    wlr_scene_attach_output_layout(srv.scene, srv.output_layout);

    srv.xdg_shell = wlr_xdg_shell_create(srv.display, 3);
    srv.cursor    = wlr_cursor_create();
    wlr_cursor_attach_output_layout(srv.cursor, srv.output_layout);
    srv.cursor_mgr = wlr_xcursor_manager_create(NULL, 24);
    wlr_xcursor_manager_load(srv.cursor_mgr, 1.0f);

    srv.seat = wlr_seat_create(srv.display, "seat0");
    srv.seat->data = &srv;

    /* Wire up signals */
    srv.new_output.notify        = server_new_output;
    srv.new_xdg_toplevel.notify  = server_new_xdg_toplevel;
    srv.new_input.notify         = server_new_input;
    srv.cursor_motion.notify     = server_cursor_motion;
    srv.cursor_button.notify     = server_cursor_button;
    wl_signal_add(&srv.backend->events.new_output,            &srv.new_output);
    wl_signal_add(&srv.xdg_shell->events.new_toplevel,        &srv.new_xdg_toplevel);
    wl_signal_add(&srv.backend->events.new_input,             &srv.new_input);
    wl_signal_add(&srv.cursor->events.motion,                 &srv.cursor_motion);
    wl_signal_add(&srv.cursor->events.button,                 &srv.cursor_button);

    /* GL shaders */
    if (!renderer_init(&srv)) {
        wlr_log(WLR_ERROR, "Renderer init failed — is OpenGL ES 3.0 available?");
        /* Non-fatal: fall back to plain wlroots rendering */
    }

    /* IPC socket — add to Wayland event loop so we get callbacks */
    ipc_init(&srv);

    /* Register IPC server fd with Wayland event loop — no polling needed */
    struct wl_event_loop *ev = wl_display_get_event_loop(srv.display);
    struct wl_event_source *ipc_source = NULL;
    int ipc_fd = ipc_server_fd();
    if (ipc_fd >= 0) {
        ipc_source = wl_event_loop_add_fd(
            ev, ipc_fd,
            WL_EVENT_READABLE,
            ipc_fd_cb, &srv);
    }

    srv.active_workspace = 1;

    const char *sock = wl_display_add_socket_auto(srv.display);
    if (!sock) {
        wlr_log(WLR_ERROR, "Failed to create Wayland socket");
        return 1;
    }

    setenv("WAYLAND_DISPLAY", sock, 1);
    wlr_log(WLR_INFO, "╔══════════════════════════════════════╗");
    wlr_log(WLR_INFO, "║   F L Y N N   O S   Compositor      ║");
    wlr_log(WLR_INFO, "║   WAYLAND_DISPLAY=%-18s  ║", sock);
    wlr_log(WLR_INFO, "║   IPC: $XDG_RUNTIME_DIR/flynn-compositor.sock ║");
    wlr_log(WLR_INFO, "╚══════════════════════════════════════╝");

    wlr_backend_start(srv.backend);
    wl_display_run(srv.display);   /* blocks until compositor exits */

    /* Cleanup */
    if (ipc_source) wl_event_source_remove(ipc_source);
    ipc_destroy();
    wl_display_destroy_clients(srv.display);
    wlr_scene_node_destroy(&srv.scene->tree.node);
    wlr_xcursor_manager_destroy(srv.cursor_mgr);
    wlr_cursor_destroy(srv.cursor);
    wlr_output_layout_destroy(srv.output_layout);
    wlr_backend_destroy(srv.backend);
    wl_display_destroy(srv.display);
    wlr_log(WLR_INFO, "Flynn compositor shutdown cleanly.");
    return 0;
}
