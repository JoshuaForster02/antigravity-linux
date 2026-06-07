#!/usr/bin/env python3
"""
Flynn Pi Agent — runs permanently on the Raspberry Pi.
Acts as:
  • MQTT broker hub for the whole Flynn ecosystem
  • Wake-on-LAN trigger for the Flynn OS PC
  • AI backend (Ollama) when the PC is off
  • Heavy-workload runner
  • Sync relay between Flynn OS ↔ macOS app

Install:  sudo bash setup-pi.sh
Run:      python3 pi_agent.py [daemon|status|wake|shutdown-pc]
"""

import json, logging, os, socket, subprocess, sys, threading, time
from datetime import datetime
from pathlib import Path
from typing import Optional

# pip3 install paho-mqtt requests wakeonlan flask --break-system-packages
import paho.mqtt.client as mqtt
import requests
from flask import Flask, jsonify, request as flask_request
from wakeonlan import send_magic_packet

# ─── CONFIG ──────────────────────────────────────────────────────────────────

CFG_PATH = Path("/etc/flynn/pi-agent.conf")
CFG: dict = {
    "mqtt_port":    1883,
    "mqtt_prefix":  "flynn",
    "ollama_host":  "http://localhost:11434",
    "ollama_model": "mistral",
    # Fill these in:
    "pc_mac":       "AA:BB:CC:DD:EE:FF",  # lshw -class network | grep serial
    "pc_host":      "flynnpc.local",
    "pc_api_port":  7777,
    "mac_host":     "joshuas-macbook-pro.local",
    "mac_api_port": 7778,
    # Tailscale: Pi is at 100.74.204.71
    # Use Tailscale IPs for cross-network access
}
if CFG_PATH.exists():
    with open(CFG_PATH) as f:
        CFG.update(json.load(f))

logging.basicConfig(
    level=logging.INFO,
    format="[PI %(asctime)s] %(levelname)s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("pi-agent")

# ─── WoL / PC CONTROL ────────────────────────────────────────────────────────

def pc_online() -> bool:
    try:
        r = requests.get(
            f"http://{CFG['pc_host']}:{CFG['pc_api_port']}/api/status",
            timeout=3)
        return r.ok
    except Exception:
        return False

def wake_pc():
    log.info(f"WoL → {CFG['pc_mac']}")
    send_magic_packet(CFG["pc_mac"])

def boot_pc(timeout: int = 120) -> bool:
    if pc_online():
        log.info("PC already online")
        return True
    wake_pc()
    deadline = time.time() + timeout
    while time.time() < deadline:
        if pc_online():
            log.info("PC online ✓")
            return True
        time.sleep(5)
    log.warning("PC did not come online within timeout")
    return False

# ─── MQTT ────────────────────────────────────────────────────────────────────

_mqtt: Optional[mqtt.Client] = None

def mqtt_pub(target: str, subtopic: str, payload: dict):
    if _mqtt:
        topic = f"{CFG['mqtt_prefix']}/{target}/{subtopic}"
        _mqtt.publish(topic, json.dumps(payload))

def on_connect(client, *a):
    p = CFG["mqtt_prefix"]
    client.subscribe(f"{p}/+/#")
    log.info(f"MQTT broker ready on :{CFG['mqtt_port']}")

def on_message(client, userdata, msg):
    topic = msg.topic
    try:
        payload = json.loads(msg.payload.decode())
    except Exception:
        return
    log.info(f"MQTT ← {topic}")

    if "workload/request" in topic:
        cmd = payload.get("command", "")
        src = payload.get("from", "flynnpc")
        threading.Thread(target=_run_workload, args=(cmd, src), daemon=True).start()

    elif "ai/request" in topic:
        threading.Thread(
            target=_ai_respond,
            args=(payload.get("prompt", ""),
                  payload.get("model", CFG["ollama_model"]),
                  payload.get("reply_to", "flynnpc")),
            daemon=True
        ).start()

    elif "system/wake_pc" in topic:
        threading.Thread(target=boot_pc, daemon=True).start()

    elif "heartbeat" in topic:
        cpu = payload.get("cpu_pct", 0)
        if cpu > 85:
            log.warning(f"PC high CPU: {cpu}%")
            # Could send a push notification to macOS here

def _run_workload(cmd: str, requester: str):
    log.info(f"Workload for {requester}: {cmd[:60]}")
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True,
                           text=True, timeout=300)
        mqtt_pub(requester, "workload/result", {
            "command":    cmd[:60],
            "stdout":     r.stdout[-2000:],
            "stderr":     r.stderr[-500:],
            "returncode": r.returncode,
        })
    except subprocess.TimeoutExpired:
        mqtt_pub(requester, "workload/result", {"error": "timeout"})
    except Exception as e:
        mqtt_pub(requester, "workload/result", {"error": str(e)})

def _ai_respond(prompt: str, model: str, reply_host: str):
    log.info(f"AI → {reply_host}: {prompt[:50]}")
    try:
        r = requests.post(
            f"{CFG['ollama_host']}/api/generate",
            json={"model": model, "prompt": prompt, "stream": False},
            timeout=120)
        response = r.json().get("response", "") if r.ok else "AI unavailable on Pi"
    except Exception as e:
        response = f"Error: {e}"
    mqtt_pub(reply_host, "ai/response", {
        "response": response,
        "reply_to": reply_host,
        "model":    model,
    })

# ─── PRESENCE DETECTION ──────────────────────────────────────────────────────

_presence: dict = {"present": False, "device": None, "rssi": None, "timestamp": 0.0}
_notion_anki_cfg: dict = {}

def _bluetooth_scan_loop():
    """Continuously scan for configured Bluetooth devices (iPhone MAC)."""
    target_macs: list[str] = CFG.get("presence_macs", [])
    if not target_macs:
        log.info("No presence_macs configured — presence detection disabled")
        return
    log.info(f"Bluetooth presence scanner running for {len(target_macs)} device(s)")
    while True:
        found = False
        for mac in target_macs:
            try:
                # hcitool name returns device name if in range, empty if not
                result = subprocess.run(
                    ["hcitool", "name", mac],
                    capture_output=True, text=True, timeout=8
                )
                name = result.stdout.strip()
                if name:
                    _presence.update({
                        "present": True,
                        "device": name,
                        "rssi": None,
                        "timestamp": time.time(),
                    })
                    found = True
                    break
            except Exception:
                pass
        if not found and _presence["present"]:
            # Was present, now gone
            _presence.update({
                "present": False,
                "device": None,
                "rssi": None,
                "timestamp": time.time(),
            })
            log.info("Presence: device left")
        elif found and not _presence.get("_was_present"):
            log.info(f"Presence: {_presence['device']} detected")
        _presence["_was_present"] = found
        time.sleep(15)

# ─── NOTION → ANKI SYNC ──────────────────────────────────────────────────────

def _run_notion_anki_sync() -> dict:
    """Run notion_anki_sync.py and return result."""
    script = Path(__file__).parent / "notion_anki_sync.py"
    if not script.exists():
        return {"error": "notion_anki_sync.py not found"}
    try:
        r = subprocess.run(
            ["python3", str(script)],
            capture_output=True, text=True, timeout=120,
            env={**os.environ, **{
                k: str(v) for k, v in _notion_anki_cfg.items()
            }}
        )
        lines = r.stdout.strip().splitlines()
        created = sum(1 for l in lines if "created" in l.lower())
        return {"created": created, "output": r.stdout[-1000:], "ok": r.returncode == 0}
    except Exception as e:
        return {"error": str(e)}

def _notion_anki_scheduler():
    """Run Notion→Anki sync on configured interval."""
    while True:
        interval_h = _notion_anki_cfg.get("interval_hours", 6)
        time.sleep(interval_h * 3600)
        log.info("Notion→Anki scheduled sync running...")
        result = _run_notion_anki_sync()
        log.info(f"Sync result: {result.get('created', 0)} cards created")

# ─── HTTP API (Flask) ─────────────────────────────────────────────────────────

app = Flask("pi-agent")

@app.route("/status")
def api_status():
    return jsonify({
        "agent":   "Flynn Pi Agent v2.0",
        "pc":      pc_online(),
        "time":    datetime.now().isoformat(),
        "presence": _presence,
    })

@app.route("/wakepc", methods=["POST", "GET"])
def api_wake():
    threading.Thread(target=boot_pc, daemon=True).start()
    return jsonify({"ok": True, "msg": "WoL sent"})

@app.route("/presence")
def api_presence():
    return jsonify({**_presence, "timestamp": _presence.get("timestamp", 0)})

@app.route("/ai/ask", methods=["POST"])
def api_ai():
    data = flask_request.json or {}
    prompt = data.get("prompt", "")
    model  = data.get("model", CFG.get("ollama_model", "mistral"))
    try:
        r = requests.post(
            f"{CFG['ollama_host']}/api/generate",
            json={"model": model, "prompt": prompt, "stream": False},
            timeout=120
        )
        return jsonify({"response": r.json().get("response", ""), "model": model})
    except Exception as e:
        return jsonify({"error": str(e)}), 503

@app.route("/notion-anki/config", methods=["POST"])
def api_notion_anki_config():
    global _notion_anki_cfg
    _notion_anki_cfg = flask_request.json or {}
    # Persist to file
    cfg_file = Path("/etc/flynn/notion-anki.json")
    cfg_file.parent.mkdir(parents=True, exist_ok=True)
    cfg_file.write_text(json.dumps(_notion_anki_cfg, indent=2))
    log.info("Notion→Anki config updated")
    return jsonify({"ok": True})

@app.route("/notion-anki/sync", methods=["POST"])
def api_notion_anki_sync():
    result = _run_notion_anki_sync()
    return jsonify(result)

def start_http_api(port: int = 8765):
    """Start Flask HTTP API in a background thread."""
    # Load persisted Notion-Anki config
    global _notion_anki_cfg
    cfg_file = Path("/etc/flynn/notion-anki.json")
    if cfg_file.exists():
        try:
            _notion_anki_cfg = json.loads(cfg_file.read_text())
        except Exception:
            pass
    t = threading.Thread(
        target=lambda: app.run(host="0.0.0.0", port=port, debug=False, use_reloader=False),
        daemon=True
    )
    t.start()
    log.info(f"HTTP API listening on :{port}")

def start_mqtt():
    global _mqtt
    # Ensure Mosquitto is running
    subprocess.run(["pgrep", "-x", "mosquitto"], capture_output=True) or \
        subprocess.Popen(["mosquitto", "-d", "-p", str(CFG["mqtt_port"])])
    time.sleep(0.5)

    c = mqtt.Client(client_id="flynn-pi")
    c.on_connect = on_connect
    c.on_message = on_message
    c.connect("localhost", CFG["mqtt_port"], keepalive=60)
    _mqtt = c
    return c

# ─── CLI ─────────────────────────────────────────────────────────────────────

def cmd_status():
    online = pc_online()
    print(f"""
╔═══════════════════════════════════╗
║    FLYNN PI AGENT  v1.0           ║
╠═══════════════════════════════════╣
║ PC (Flynn OS):  {"ONLINE ✓" if online else "OFFLINE  ✗"}          ║
║ PC MAC:         {CFG['pc_mac'][:17]}  ║
║ MQTT:           :{CFG['mqtt_port']}                  ║
║ Ollama:         {CFG['ollama_model']:<18}  ║
╚═══════════════════════════════════╝
""")

# ─── MAIN ────────────────────────────────────────────────────────────────────

def main():
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("cmd", nargs="?", default="daemon",
                   choices=["daemon", "status", "wake", "shutdown-pc"])
    args = p.parse_args()

    if args.cmd == "status":
        cmd_status(); return
    if args.cmd == "wake":
        ok = boot_pc(); print("PC online ✓" if ok else "PC did not respond ✗"); return
    if args.cmd == "shutdown-pc":
        start_mqtt(); mqtt_pub("flynnpc", "system/shutdown", {"from": "pi"}); return

    # Daemon mode
    log.info("╔══════════════════════════════════════╗")
    log.info("║  FLYNN PI AGENT  v2.0  — ONLINE      ║")
    log.info("╚══════════════════════════════════════╝")

    # Start HTTP API (Flask) — macOS app talks to this
    api_port = CFG.get("api_port", 8765)
    start_http_api(port=api_port)

    # Start Bluetooth presence scanner
    threading.Thread(target=_bluetooth_scan_loop, daemon=True).start()

    # Start Notion→Anki scheduler
    threading.Thread(target=_notion_anki_scheduler, daemon=True).start()

    # Start MQTT broker + loop
    c = start_mqtt()
    try:
        c.loop_forever()
    except KeyboardInterrupt:
        log.info("Pi agent stopped.")

if __name__ == "__main__":
    main()
