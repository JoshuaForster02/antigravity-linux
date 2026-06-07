#!/usr/bin/env python3
"""
Flynn OS — Pi Anki Push Alerts
Pollt AnkiConnect auf dem PC, sendet Push wenn Karten fällig.
Läuft auf dem Pi — auch wenn der PC aus ist werden gespeicherte
Due-Counts per ntfy.sh / macOS Shortcut gepusht.
"""
import json, time, os, logging, subprocess, urllib.request, urllib.error
from datetime import datetime
from pathlib import Path

logging.basicConfig(level=logging.INFO, format='%(asctime)s [anki-alerts] %(message)s')
log = logging.getLogger(__name__)

CFG_FILE = Path("/etc/flynnos/anki-alerts.json")
STATE_FILE = Path("/tmp/flynn-anki-state.json")

DEFAULT_CFG = {
    "anki_host": "http://100.74.204.71",   # IP des Flynn OS PCs
    "anki_port": 8765,
    "ntfy_topic": "flynnos-joshua",         # ntfy.sh topic (kostenlos, anonym)
    "ntfy_server": "https://ntfy.sh",
    "check_interval_minutes": 60,
    "alert_thresholds": [1, 10, 25, 50],   # bei diesen Due-Counts alarmieren
    "quiet_hours": {"start": 23, "end": 7},  # keine Alerts zwischen 23-7 Uhr
    "enabled": True
}

def load_cfg():
    if CFG_FILE.exists():
        with open(CFG_FILE) as f:
            return {**DEFAULT_CFG, **json.load(f)}
    return DEFAULT_CFG

def save_cfg(cfg):
    CFG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(CFG_FILE, "w") as f:
        json.dump(cfg, f, indent=2)

def anki_request(host, port, action, **params):
    payload = json.dumps({"action": action, "version": 6, "params": params}).encode()
    req = urllib.request.Request(
        f"{host}:{port}",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST"
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            result = json.loads(r.read())
            return result.get("result")
    except Exception as e:
        log.debug(f"AnkiConnect error: {e}")
        return None

def get_due_counts(host, port):
    """Get due card counts per deck."""
    decks = anki_request(host, port, "deckNames")
    if not decks:
        return None, None

    total_due = 0
    deck_stats = {}
    for deck in decks:
        if deck == "Default":
            continue
        due = anki_request(host, port, "findCards",
                           query=f'deck:"{deck}" is:due')
        count = len(due) if due else 0
        if count > 0:
            deck_stats[deck] = count
        total_due += count

    return total_due, deck_stats

def send_ntfy_push(server, topic, title, message, priority="default", tags=""):
    """Send push notification via ntfy.sh"""
    url = f"{server}/{topic}"
    headers = {
        "Title": title.encode(),
        "Message": message.encode(),
        "Priority": priority,
    }
    if tags:
        headers["Tags"] = tags
    try:
        req = urllib.request.Request(url, data=message.encode(), headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status == 200
    except Exception as e:
        log.warning(f"ntfy push failed: {e}")
        return False

def is_quiet_hours(cfg):
    now = datetime.now().hour
    start = cfg["quiet_hours"]["start"]
    end = cfg["quiet_hours"]["end"]
    if start > end:  # crosses midnight
        return now >= start or now < end
    return start <= now < end

def load_state():
    if STATE_FILE.exists():
        with open(STATE_FILE) as f:
            return json.load(f)
    return {"last_notified_count": 0, "last_check": 0, "total_reviews_today": 0}

def save_state(state):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)

def format_deck_summary(deck_stats):
    if not deck_stats:
        return ""
    lines = []
    for deck, count in sorted(deck_stats.items(), key=lambda x: -x[1])[:5]:
        lines.append(f"  {deck[:30]}: {count}")
    return "\n".join(lines)

def run_check(cfg, state):
    host = cfg["anki_host"]
    port = cfg["anki_port"]

    total_due, deck_stats = get_due_counts(host, port)

    if total_due is None:
        log.info("AnkiConnect nicht erreichbar (PC aus?)")
        # PC is off — if we have a cached count, notify anyway
        cached = state.get("last_known_due", 0)
        if cached > 0 and not is_quiet_hours(cfg):
            # Check if we already notified today
            last_date = state.get("last_notified_date", "")
            today = datetime.now().strftime("%Y-%m-%d")
            if last_date != today:
                send_ntfy_push(
                    cfg["ntfy_server"], cfg["ntfy_topic"],
                    "📚 Anki — PC ist aus",
                    f"{cached} Karten warten auf Review.\nPC einschalten: flynn-dashboard → Wake PC",
                    priority="default", tags="books"
                )
                state["last_notified_date"] = today
                save_state(state)
        return

    log.info(f"Fällige Karten: {total_due}")
    state["last_known_due"] = total_due
    state["last_check"] = time.time()

    if total_due == 0:
        save_state(state)
        return

    if is_quiet_hours(cfg):
        log.info("Quiet hours — kein Alert")
        save_state(state)
        return

    # Only alert on threshold crossings (avoid spam)
    last_count = state.get("last_notified_count", -1)
    should_notify = False

    for threshold in cfg["alert_thresholds"]:
        if total_due >= threshold and last_count < threshold:
            should_notify = True
            break

    # Also alert once per hour if >25 cards due
    last_hourly = state.get("last_hourly_alert", 0)
    if total_due >= 25 and (time.time() - last_hourly) > 3600:
        should_notify = True
        state["last_hourly_alert"] = time.time()

    if should_notify:
        deck_summary = format_deck_summary(deck_stats)
        top_decks = list(deck_stats.keys())[:3] if deck_stats else []

        priority = "urgent" if total_due >= 50 else "high" if total_due >= 25 else "default"
        tags = "rotating_light" if total_due >= 50 else "books"

        msg = f"{total_due} Karten fällig"
        if deck_summary:
            msg += f"\n\n{deck_summary}"
        msg += f"\n\nStudy Mode: Super+G (Flynn OS)"

        success = send_ntfy_push(
            cfg["ntfy_server"], cfg["ntfy_topic"],
            f"📚 Anki — {total_due} Karten fällig",
            msg, priority=priority, tags=tags
        )

        if success:
            log.info(f"Push gesendet: {total_due} fällige Karten")
            state["last_notified_count"] = total_due
        else:
            log.warning("Push fehlgeschlagen")

    save_state(state)

def main():
    cfg = load_cfg()
    if not cfg.get("enabled"):
        log.info("Anki Alerts deaktiviert")
        return

    log.info(f"Anki Push Alerts gestartet")
    log.info(f"Anki: {cfg['anki_host']}:{cfg['anki_port']}")
    log.info(f"ntfy Topic: {cfg['ntfy_server']}/{cfg['ntfy_topic']}")
    log.info(f"Interval: alle {cfg['check_interval_minutes']} Minuten")
    log.info(f"Quiet Hours: {cfg['quiet_hours']['start']}–{cfg['quiet_hours']['end']} Uhr")
    log.info("")
    log.info("📱 Auf iPhone/Mac: ntfy.sh App installieren")
    log.info(f"   Topic abonnieren: {cfg['ntfy_topic']}")

    while True:
        state = load_state()
        try:
            run_check(cfg, state)
        except Exception as e:
            log.error(f"Check-Fehler: {e}")
        time.sleep(cfg["check_interval_minutes"] * 60)

if __name__ == "__main__":
    main()
