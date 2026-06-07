#!/usr/bin/env python3
"""
Flynn OS Daemon — AI brain + sync hub for the Flynn ecosystem.

  REST API  :7777  — polled by macOS Antigravity app
  MQTT      :1883  — talks to Raspberry Pi agent
  Heartbeat        — broadcasts system stats every 10s

Endpoints
  GET  /api/status           system stats (CPU, MEM, GPU, disk)
  GET  /api/notion/tasks     fetch Notion tasks (uses token from config)
  POST /api/launch/game      {app_id} → steam://rungameid/<id>
  POST /api/workload/delegate{command} → execute on Pi via MQTT
  POST /api/ai/ask           {prompt,model} → local Ollama or Pi
  GET  /api/config           read current config (no secrets)
  POST /api/config           update config
  POST /api/gamemode         {enabled:true/false} → toggle game mode
"""

import json, logging, os, signal, socket, subprocess, sys, threading, time
from pathlib import Path
from typing import Optional

import paho.mqtt.client as mqtt
import psutil
import requests
from flask import Flask, jsonify, request
from flask_cors import CORS

# ─── CONFIG ──────────────────────────────────────────────────────────────────

CONFIG_PATH = Path("/etc/flynn/daemon.conf")
DEFAULTS = {
    "mqtt_broker":        "100.74.204.71",   # Pi Tailscale IP
    "mqtt_port":          1883,
    "mqtt_prefix":        "flynn",
    "api_port":           7777,
    "notion_token":       "",
    "notion_database_id": "",
    "steam_path":         "/home/flynn/.steam/steam/steam.sh",
    "ollama_host":        "http://localhost:11434",
    "ollama_model":       "mistral",
    "pi_host":            "100.74.204.71",  # Pi Tailscale IP
    "hostname":           socket.gethostname(),
}

def load_config() -> dict:
    cfg = DEFAULTS.copy()
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH) as f:
            cfg.update(json.load(f))
    return cfg

CFG = load_config()

# ─── LOGGING ─────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="[FLYNN %(asctime)s] %(levelname)s  %(message)s",
    datefmt="%H:%M:%S",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler("/var/log/flynn-daemon.log", delay=True),
    ],
)
log = logging.getLogger("flynn")

# ─── FLASK ───────────────────────────────────────────────────────────────────

app = Flask("FlynnOS")
CORS(app)

@app.route("/api/status")
def status():
    cpu  = psutil.cpu_percent(interval=0.1)
    mem  = psutil.virtual_memory()
    disk = psutil.disk_usage("/")
    net  = psutil.net_io_counters()

    # Try to get GPU usage (nvidia-smi)
    gpu_pct = None
    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=2)
        if r.returncode == 0:
            gpu_pct = int(r.stdout.strip().split("\n")[0])
    except Exception:
        pass

    return jsonify({
        "hostname":     CFG["hostname"],
        "os":           "Flynn OS Linux",
        "cpu_pct":      cpu,
        "mem_used_pct": mem.percent,
        "mem_total_gb": round(mem.total / 1e9, 1),
        "disk_free_gb": round(disk.free  / 1e9, 1),
        "net_sent_mb":  round(net.bytes_sent / 1e6, 1),
        "net_recv_mb":  round(net.bytes_recv / 1e6, 1),
        "gpu_pct":      gpu_pct,
        "uptime_s":     int(time.time() - psutil.boot_time()),
        "timestamp":    time.time(),
    })

@app.route("/api/notion/tasks")
def notion_tasks():
    token = CFG.get("notion_token", "")
    db_id = CFG.get("notion_database_id", "")
    if not token:
        return jsonify({"error": "notion_token not set in /etc/flynn/daemon.conf"}), 503

    headers = {
        "Authorization":  f"Bearer {token}",
        "Notion-Version": "2022-06-28",
    }

    # If no database ID, search for databases
    if not db_id:
        try:
            r = requests.post(
                "https://api.notion.com/v1/search",
                headers=headers,
                json={"filter": {"value": "database", "property": "object"}},
                timeout=10)
            dbs = r.json().get("results", [])
            if dbs:
                db_id = dbs[0]["id"]
            else:
                return jsonify({"tasks": [], "note": "no databases found"}), 200
        except Exception as e:
            return jsonify({"error": str(e)}), 500

    try:
        r = requests.post(
            f"https://api.notion.com/v1/databases/{db_id}/query",
            headers=headers,
            json={},
            timeout=10)
        r.raise_for_status()
        tasks = []
        for page in r.json().get("results", []):
            props = page.get("properties", {})
            title_arr = next(
                (v.get("title", []) for v in props.values()
                 if v.get("type") == "title"), [])
            title = "".join(t.get("plain_text", "") for t in title_arr)
            status_val = next(
                (v.get("status", {}) or v.get("select", {})
                 for v in props.values()
                 if v.get("type") in ("status", "select")), {}) or {}
            tasks.append({
                "id":     page["id"],
                "title":  title or "(untitled)",
                "status": (status_val.get("name") if isinstance(status_val, dict) else ""),
                "url":    page.get("url", ""),
            })
        return jsonify({"tasks": tasks})
    except Exception as e:
        log.error(f"Notion: {e}")
        return jsonify({"error": str(e)}), 500

@app.route("/api/launch/game", methods=["POST"])
def launch_game():
    data   = request.get_json(force=True) or {}
    app_id = data.get("app_id")
    if not app_id:
        return jsonify({"error": "app_id required"}), 400
    try:
        subprocess.Popen(
            [CFG["steam_path"], f"steam://rungameid/{app_id}"],
            env={**os.environ, "ENABLE_GAMEMODE": "1"})
        _mqtt_pub("game/launched", {"app_id": app_id})
        return jsonify({"status": "launched", "app_id": app_id})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/gamemode", methods=["POST"])
def gamemode():
    data    = request.get_json(force=True) or {}
    enabled = data.get("enabled", True)
    if enabled:
        subprocess.Popen(["/usr/local/bin/flynn-gamemode", "game"])
    else:
        subprocess.Popen(["/usr/local/bin/flynn-gamemode", "work"])
    _mqtt_pub("gamemode/changed", {"enabled": enabled})
    return jsonify({"gamemode": enabled})

@app.route("/api/workload/delegate", methods=["POST"])
def delegate():
    data    = request.get_json(force=True) or {}
    command = data.get("command", "")
    if not command:
        return jsonify({"error": "command required"}), 400
    _mqtt_pub("workload/request", {
        "from":    CFG["hostname"],
        "command": command,
        "ts":      time.time(),
    })
    return jsonify({"status": "delegated"})

@app.route("/api/ai/ask", methods=["POST"])
def ai_ask():
    data   = request.get_json(force=True) or {}
    prompt = data.get("prompt", "")
    model  = data.get("model", CFG["ollama_model"])

    # Try local Ollama
    try:
        r = requests.post(
            f"{CFG['ollama_host']}/api/generate",
            json={"model": model, "prompt": prompt, "stream": False},
            timeout=30)
        if r.ok:
            return jsonify({"response": r.json().get("response", ""), "source": "local"})
    except Exception:
        pass

    # Delegate to Pi
    _mqtt_pub("ai/request", {
        "prompt":   prompt,
        "model":    model,
        "reply_to": CFG["hostname"],
    })
    return jsonify({"status": "delegated_to_pi"})

@app.route("/api/config", methods=["GET", "POST"])
def config():
    if request.method == "POST":
        updates = request.get_json(force=True) or {}
        CFG.update(updates)
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_PATH, "w") as f:
            json.dump({k: v for k, v in CFG.items() if k != "hostname"}, f, indent=2)
        return jsonify({"status": "saved"})
    return jsonify({k: ("***" if k == "notion_token" and v else v)
                    for k, v in CFG.items()})

# ─── MQTT ────────────────────────────────────────────────────────────────────

_mqtt: Optional[mqtt.Client] = None

def _mqtt_pub(subtopic: str, payload: dict):
    if _mqtt and _mqtt.is_connected():
        topic = f"{CFG['mqtt_prefix']}/{CFG['hostname']}/{subtopic}"
        _mqtt.publish(topic, json.dumps(payload))

def _on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode())
    except Exception:
        return
    t = msg.topic
    log.info(f"MQTT ← {t}")

    if "launch/game" in t:
        app_id = payload.get("app_id")
        if app_id:
            subprocess.Popen([CFG["steam_path"], f"steam://rungameid/{app_id}"])

    elif "ai/response" in t and payload.get("reply_to") == CFG["hostname"]:
        log.info(f"AI from Pi: {str(payload.get('response',''))[:80]}")

    elif "system/shutdown" in t:
        os.system("shutdown -h now")

    elif "system/reboot" in t:
        os.system("reboot")

def _start_mqtt():
    global _mqtt
    c = mqtt.Client(client_id=f"flynnos-{CFG['hostname']}")

    def on_connect(client, *a):
        p = CFG["mqtt_prefix"]
        h = CFG["hostname"]
        client.subscribe(f"{p}/+/launch/#")
        client.subscribe(f"{p}/+/ai/response")
        client.subscribe(f"{p}/{h}/system/#")
        log.info(f"MQTT connected to {CFG['mqtt_broker']}")

    c.on_connect = on_connect
    c.on_message = _on_message
    try:
        c.connect(CFG["mqtt_broker"], CFG["mqtt_port"], keepalive=60)
        c.loop_start()
        _mqtt = c
    except Exception as e:
        log.warning(f"MQTT unavailable ({e}) — Pi sync disabled")

# ─── HEARTBEAT ───────────────────────────────────────────────────────────────

def _heartbeat():
    while True:
        try:
            _mqtt_pub("heartbeat", {
                "cpu_pct": psutil.cpu_percent(interval=1),
                "mem_pct": psutil.virtual_memory().percent,
                "ts":      time.time(),
            })
        except Exception:
            pass
        time.sleep(10)

# ─── MAIN ────────────────────────────────────────────────────────────────────

def main():
    log.info("╔══════════════════════════════════╗")
    log.info("║  FLYNN OS DAEMON  v1.0  ONLINE   ║")
    log.info("╚══════════════════════════════════╝")

    _start_mqtt()
    threading.Thread(target=_heartbeat, daemon=True).start()

    def _shutdown(sig, frame):
        if _mqtt:
            _mqtt.loop_stop()
        sys.exit(0)

    signal.signal(signal.SIGINT,  _shutdown)
    signal.signal(signal.SIGTERM, _shutdown)

    log.info(f"REST API → http://0.0.0.0:{CFG['api_port']}")
    app.run(host="0.0.0.0", port=CFG["api_port"], debug=False, threaded=True)

if __name__ == "__main__":
    main()
