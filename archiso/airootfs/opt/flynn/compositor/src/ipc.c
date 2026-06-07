/*
 * ipc.c — Flynn OS Compositor IPC
 *
 * Unix socket at $XDG_RUNTIME_DIR/flynn-compositor.sock
 * JSON messages: {"event":"palette_toggle","payload":"open"}
 *
 * Clients (macOS app sync, waybar, Python scripts) can subscribe:
 *   socat - UNIX-CONNECT:/run/user/1000/flynn-compositor.sock
 *
 * The Flynn daemon also connects here to bridge with MQTT/REST.
 */
#include "flynn-compositor.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>

#define SOCKET_NAME "flynn-compositor.sock"
#define MAX_CLIENTS 16

static int server_fd = -1;
static int clients[MAX_CLIENTS];
static int client_count = 0;

static char socket_path[256];

void ipc_init(struct flynn_server *srv) {
    (void)srv;

    const char *runtime = getenv("XDG_RUNTIME_DIR");
    if (!runtime) runtime = "/run/user/1000";

    snprintf(socket_path, sizeof(socket_path), "%s/%s", runtime, SOCKET_NAME);
    unlink(socket_path);

    server_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK, 0);
    if (server_fd < 0) {
        wlr_log(WLR_ERROR, "IPC: socket() failed: %s", strerror(errno));
        return;
    }

    struct sockaddr_un addr = {0};
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0 ||
        listen(server_fd, 8) < 0) {
        wlr_log(WLR_ERROR, "IPC: bind/listen failed: %s", strerror(errno));
        close(server_fd);
        server_fd = -1;
        return;
    }

    chmod(socket_path, 0600);
    for (int i = 0; i < MAX_CLIENTS; i++) clients[i] = -1;
    wlr_log(WLR_INFO, "IPC: listening on %s", socket_path);
}

/* Return server fd so main.c can register it with the Wayland event loop */
int ipc_server_fd(void) { return server_fd; }

/* Accept new connections (call from event loop) */
void ipc_accept(void) {
    if (server_fd < 0) return;
    int fd = accept(server_fd, NULL, NULL);
    if (fd < 0) return;
    fcntl(fd, F_SETFL, O_NONBLOCK);
    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (clients[i] < 0) {
            clients[i] = fd;
            client_count++;
            wlr_log(WLR_DEBUG, "IPC: client connected (slot %d)", i);
            return;
        }
    }
    /* Full — reject */
    close(fd);
}

/* Broadcast event to all connected clients */
void ipc_broadcast(struct flynn_server *srv,
                    const char *event, const char *payload) {
    (void)srv;
    if (server_fd < 0) return;

    ipc_accept();  /* pick up any new connections first */

    char msg[512];
    int len = snprintf(msg, sizeof(msg),
        "{\"event\":\"%s\",\"payload\":\"%s\"}\n",
        event, payload ? payload : "");

    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (clients[i] < 0) continue;
        ssize_t w = write(clients[i], msg, len);
        if (w < 0) {
            close(clients[i]);
            clients[i] = -1;
            client_count--;
        }
    }

    wlr_log(WLR_DEBUG, "IPC broadcast: %s → %s", event, payload);
}

/* ── Parse and apply incoming IPC command ─────────────────────────────────── */
static void apply_command(struct flynn_server *srv,
                           const char *event, const char *payload) {
    if (!event) return;

    if (strcmp(event, "mode_changed") == 0) {
        if      (payload && strcmp(payload, "focus")    == 0) srv->ag_mode = AG_MODE_FOCUS;
        else if (payload && strcmp(payload, "game")     == 0) srv->ag_mode = AG_MODE_GAME;
        else if (payload && strcmp(payload, "overview") == 0) srv->ag_mode = AG_MODE_OVERVIEW;
        else                                                   srv->ag_mode = AG_MODE_NORMAL;
        wlr_log(WLR_INFO, "IPC: mode → %s", payload ? payload : "normal");
    }
    else if (strcmp(event, "palette_toggle") == 0) {
        srv->palette_open = payload && strcmp(payload, "open") == 0;
        wlr_log(WLR_INFO, "IPC: palette %s", srv->palette_open ? "open" : "closed");
    }
    else if (strcmp(event, "workspace_switch") == 0) {
        int ws = payload ? atoi(payload) : 1;
        if (ws >= 1 && ws <= 9) {
            srv->active_workspace = ws;
            wlr_log(WLR_INFO, "IPC: workspace → %d", ws);
        }
    }
    else if (strcmp(event, "set_mode") == 0) {
        /* From game-mode-switch.sh: {"cmd":"set_mode","mode":"game"} */
        if (payload && strcmp(payload, "game") == 0)  srv->ag_mode = AG_MODE_GAME;
        else                                           srv->ag_mode = AG_MODE_NORMAL;
    }
}

/* ── Read and dispatch incoming messages from all clients ─────────────────── */
void ipc_handle_incoming(struct flynn_server *srv) {
    ipc_accept();

    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (clients[i] < 0) continue;

        char buf[512];
        ssize_t n = read(clients[i], buf, sizeof(buf) - 1);
        if (n <= 0) {
            if (n == 0 || errno != EAGAIN) {
                close(clients[i]);
                clients[i] = -1;
                client_count--;
            }
            continue;
        }
        buf[n] = '\0';

        /* Simple JSON parse — find "event" and "payload" values */
        char event[64] = {0};
        char payload[128] = {0};

        char *ep = strstr(buf, "\"event\"");
        if (ep) {
            char *vs = strchr(ep + 7, '"');
            if (vs) {
                vs++;
                char *ve = strchr(vs, '"');
                if (ve) {
                    size_t len = (size_t)(ve - vs);
                    if (len >= sizeof(event)) len = sizeof(event) - 1;
                    strncpy(event, vs, len);
                }
            }
        }

        /* Try "payload" key first, then "mode" key */
        char *pp = strstr(buf, "\"payload\"");
        if (!pp) pp = strstr(buf, "\"mode\"");
        if (pp) {
            char *vs = strchr(pp + 9, '"');
            if (vs) {
                vs++;
                char *ve = strchr(vs, '"');
                if (ve) {
                    size_t len = (size_t)(ve - vs);
                    if (len >= sizeof(payload)) len = sizeof(payload) - 1;
                    strncpy(payload, vs, len);
                }
            }
        }

        if (event[0]) apply_command(srv, event, payload[0] ? payload : NULL);
    }
}

/* ── Clean shutdown ─────────────────────────────────────────────────────────── */
void ipc_destroy(void) {
    for (int i = 0; i < MAX_CLIENTS; i++) {
        if (clients[i] >= 0) { close(clients[i]); clients[i] = -1; }
    }
    if (server_fd >= 0) { close(server_fd); server_fd = -1; }
    if (socket_path[0]) unlink(socket_path);
}
