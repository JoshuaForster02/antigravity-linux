/*
 * wm.c — Flynn OS window manager logic
 *
 * Floating by default. Keyboard shortcuts:
 *   Super+H/L/J/K    — move focused window (64px steps)
 *   Super+F          — fullscreen toggle
 *   Super+Q          — close focused window
 *   Super+Tab        — cycle focus
 *   Super+G          — Game Mode (fullscreen, no decorations)
 *   Super+W          — Work Mode (restore floating)
 *   Super+Space      — open ANTIGRAVITY ⌘K palette
 *   Super+D          — toggle Focus Mode (dim background windows)
 *   Super+O          — Overview mode (tile all windows)
 */
#include "flynn-compositor.h"
#include <stdlib.h>
#include <string.h>
#include <linux/input-event-codes.h>

#define MOVE_STEP 64   /* px per keyboard move */

/* ── Focus a toplevel ─────────────────────────────────────────────────────── */
void wm_focus(struct flynn_server *srv, struct flynn_toplevel *top) {
    if (!top) return;

    /* Unfocus previous */
    struct wlr_surface *prev = srv->seat->keyboard_state.focused_surface;
    if (prev) {
        struct wlr_xdg_surface *xdg = wlr_xdg_surface_try_from_wlr_surface(prev);
        if (xdg && xdg->role == WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
            /* Mark previous as unfocused */
            struct flynn_toplevel *t;
            wl_list_for_each(t, &srv->toplevels, link) {
                if (t->xdg_toplevel->base == xdg) {
                    t->focused = false;
                    wlr_xdg_toplevel_set_activated(t->xdg_toplevel, false);
                    break;
                }
            }
        }
    }

    top->focused = true;
    wlr_xdg_toplevel_set_activated(top->xdg_toplevel, true);

    struct wlr_keyboard *kb = wlr_seat_get_keyboard(srv->seat);
    if (kb) {
        wlr_seat_keyboard_notify_enter(
            srv->seat,
            top->xdg_toplevel->base->surface,
            kb->keycodes, kb->num_keycodes,
            &kb->modifiers);
    }

    /* Raise to top in scene graph */
    wlr_scene_node_raise_to_top(&top->scene_tree->node);
}

/* ── Hit test: which toplevel is at (lx, ly) ─────────────────────────────── */
struct flynn_toplevel *wm_toplevel_at(struct flynn_server *srv,
                                       double lx, double ly,
                                       struct wlr_surface **surface,
                                       double *sx, double *sy) {
    struct wlr_scene_node *node =
        wlr_scene_node_at(&srv->scene->tree.node, lx, ly, sx, sy);
    if (!node || node->type != WLR_SCENE_NODE_BUFFER) return NULL;

    struct wlr_scene_buffer *sbuf = wlr_scene_buffer_from_node(node);
    struct wlr_scene_surface *ssuf = wlr_scene_surface_try_from_buffer(sbuf);
    if (!ssuf) return NULL;

    *surface = ssuf->surface;

    /* Walk up to find the xdg_toplevel */
    struct wlr_xdg_surface *xdg =
        wlr_xdg_surface_try_from_wlr_surface(*surface);
    while (xdg && xdg->role != WLR_XDG_SURFACE_ROLE_TOPLEVEL) {
        struct wlr_surface *parent = wlr_surface_get_root_surface(xdg->surface);
        xdg = wlr_xdg_surface_try_from_wlr_surface(parent);
    }
    if (!xdg) return NULL;

    struct flynn_toplevel *top;
    wl_list_for_each(top, &srv->toplevels, link) {
        if (top->xdg_toplevel == xdg->toplevel)
            return top;
    }
    return NULL;
}

/* ── Tile all windows into a grid (Overview mode) ─────────────────────────── */
void wm_tile(struct flynn_server *srv) {
    int count = wl_list_length(&srv->toplevels);
    if (count == 0) return;

    struct wlr_output *out =
        wlr_output_layout_get_center_output(srv->output_layout);
    if (!out) return;

    int sw = out->width, sh = out->height;
    int cols = (int)ceil(sqrt((double)count));
    int rows = (count + cols - 1) / cols;
    int cw   = sw / cols;
    int ch   = sh / rows;
    int pad  = 8;

    int i = 0;
    struct flynn_toplevel *top;
    wl_list_for_each(top, &srv->toplevels, link) {
        int col = i % cols;
        int row = i / cols;
        int x   = col * cw + pad;
        int y   = row * ch + pad;
        int w   = cw - pad * 2;
        int h   = ch - pad * 2;

        wlr_scene_node_set_position(&top->scene_tree->node, x, y);
        wlr_xdg_toplevel_set_size(top->xdg_toplevel, w, h);
        top->x = x;
        top->y = y;
        i++;
    }
}

/* ── Set compositor mode ─────────────────────────────────────────────────── */
void wm_set_mode(struct flynn_server *srv, ag_mode_t mode) {
    srv->ag_mode = mode;

    if (mode == AG_MODE_OVERVIEW) {
        wm_tile(srv);
    } else if (mode == AG_MODE_GAME) {
        /* Make focused window fullscreen */
        struct flynn_toplevel *top;
        wl_list_for_each(top, &srv->toplevels, link) {
            if (top->focused) {
                wlr_xdg_toplevel_set_fullscreen(top->xdg_toplevel, true);
                break;
            }
        }
    } else if (mode == AG_MODE_NORMAL) {
        /* Restore all windows */
        struct flynn_toplevel *top;
        wl_list_for_each(top, &srv->toplevels, link) {
            wlr_xdg_toplevel_set_fullscreen(top->xdg_toplevel, false);
        }
    }

    ipc_broadcast(srv, "mode_changed",
        mode == AG_MODE_FOCUS    ? "focus" :
        mode == AG_MODE_OVERVIEW ? "overview" :
        mode == AG_MODE_GAME     ? "game" : "normal");
}

/* ── Keyboard handler ────────────────────────────────────────────────────── */
bool wm_handle_keybind(struct flynn_server *srv,
                        uint32_t modifiers, xkb_keysym_t sym) {
    if (!(modifiers & WLR_MODIFIER_LOGO)) return false;  /* Super key required */

    /* Find focused toplevel */
    struct flynn_toplevel *focused = NULL;
    struct flynn_toplevel *top;
    wl_list_for_each(top, &srv->toplevels, link) {
        if (top->focused) { focused = top; break; }
    }

    switch (sym) {
    /* Move window */
    case XKB_KEY_h: case XKB_KEY_Left:
        if (focused) {
            focused->x -= MOVE_STEP;
            wlr_scene_node_set_position(&focused->scene_tree->node,
                                         focused->x, focused->y);
        }
        return true;
    case XKB_KEY_l: case XKB_KEY_Right:
        if (focused) {
            focused->x += MOVE_STEP;
            wlr_scene_node_set_position(&focused->scene_tree->node,
                                         focused->x, focused->y);
        }
        return true;
    case XKB_KEY_k: case XKB_KEY_Up:
        if (focused) {
            focused->y -= MOVE_STEP;
            wlr_scene_node_set_position(&focused->scene_tree->node,
                                         focused->x, focused->y);
        }
        return true;
    case XKB_KEY_j: case XKB_KEY_Down:
        if (focused) {
            focused->y += MOVE_STEP;
            wlr_scene_node_set_position(&focused->scene_tree->node,
                                         focused->x, focused->y);
        }
        return true;

    /* Close window */
    case XKB_KEY_q:
        if (focused)
            wlr_xdg_toplevel_send_close(focused->xdg_toplevel);
        return true;

    /* Fullscreen */
    case XKB_KEY_f:
        if (focused)
            wlr_xdg_toplevel_set_fullscreen(focused->xdg_toplevel,
                !focused->xdg_toplevel->current.fullscreen);
        return true;

    /* Cycle focus */
    case XKB_KEY_Tab: {
        struct flynn_toplevel *next = NULL;
        bool found = !focused;
        wl_list_for_each(top, &srv->toplevels, link) {
            if (found && top != focused) { next = top; break; }
            if (top == focused) found = true;
        }
        if (!next && !wl_list_empty(&srv->toplevels))
            next = wl_container_of(srv->toplevels.next, next, link);
        if (next) wm_focus(srv, next);
        return true;
    }

    /* ANTIGRAVITY modes */
    case XKB_KEY_d:
        wm_set_mode(srv, srv->ag_mode == AG_MODE_FOCUS
                        ? AG_MODE_NORMAL : AG_MODE_FOCUS);
        return true;
    case XKB_KEY_o:
        wm_set_mode(srv, srv->ag_mode == AG_MODE_OVERVIEW
                        ? AG_MODE_NORMAL : AG_MODE_OVERVIEW);
        return true;
    case XKB_KEY_g:
        wm_set_mode(srv, AG_MODE_GAME);
        return true;
    case XKB_KEY_w:
        wm_set_mode(srv, AG_MODE_NORMAL);
        return true;

    /* ⌘K Command Palette */
    case XKB_KEY_space:
        srv->palette_open = !srv->palette_open;
        ipc_broadcast(srv, "palette_toggle",
                      srv->palette_open ? "open" : "close");
        return true;
    }
    return false;
}
