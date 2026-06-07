#!/usr/bin/env python3
"""
Flynn OS — Notion→Anki Auto-Sync
Runs permanently on the Pi. Polls Notion for new highlights/flashcard entries
and creates Anki cards automatically via AnkiConnect.

Setup:
  pip3 install requests schedule --break-system-packages
  # Anki must be running on the PC with AnkiConnect addon installed
  # AnkiConnect addon ID: 2055492159  (https://ankiweb.net/shared/info/2055492559)

Config:  /etc/flynn/daemon.conf  (same file as pi_agent)
  notion_token   = secret_xxxxx
  notion_db_id   = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx   (Flashcards database)
  anki_host      = 192.168.1.XXX   (PC local IP where Anki runs)
  anki_port      = 8765
  sync_interval  = 60              (seconds between polls)

Notion database schema expected:
  Front     (title property)   — card front / question
  Back      (rich_text)        — card back / answer
  Tags      (multi_select)     — Anki tags
  Deck      (select)           — Anki deck name (default: "Flynn::Auto")
  Synced    (checkbox)         — set to True after card created

Run:
  python3 notion_anki_sync.py daemon   # background loop
  python3 notion_anki_sync.py sync     # one-shot sync
  python3 notion_anki_sync.py status   # show stats
"""

import json
import logging
import os
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

import requests

# ── Logging ───────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s  %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("notion-anki")

# ── Config ────────────────────────────────────────────────────────────────────
CFG_FILE = Path("/etc/flynn/daemon.conf")
DEFAULT_CFG: dict = {
    "notion_token":    "",
    "notion_db_id":    "",
    "anki_host":       "localhost",
    "anki_port":       "8765",
    "sync_interval":   "60",
    "default_deck":    "Flynn::Auto",
    "default_model":   "Basic",
}


def load_config() -> dict:
    cfg = dict(DEFAULT_CFG)
    if CFG_FILE.exists():
        for line in CFG_FILE.read_text().splitlines():
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, _, v = line.partition("=")
                cfg[k.strip()] = v.strip()
    # Env overrides
    for k in cfg:
        env = f"FLYNN_{k.upper()}"
        if env in os.environ:
            cfg[k] = os.environ[env]
    return cfg


# ── Notion API client ─────────────────────────────────────────────────────────
class NotionClient:
    BASE = "https://api.notion.com/v1"

    def __init__(self, token: str):
        self.headers = {
            "Authorization": f"Bearer {token}",
            "Notion-Version": "2022-06-28",
            "Content-Type": "application/json",
        }

    def query_database(self, db_id: str, filter_obj: Optional[dict] = None) -> list:
        """Return all pages from a database matching filter."""
        url = f"{self.BASE}/databases/{db_id}/query"
        payload: dict = {"page_size": 100}
        if filter_obj:
            payload["filter"] = filter_obj

        pages = []
        while True:
            resp = requests.post(url, headers=self.headers,
                                 json=payload, timeout=15)
            resp.raise_for_status()
            data = resp.json()
            pages.extend(data.get("results", []))
            if not data.get("has_more"):
                break
            payload["start_cursor"] = data["next_cursor"]
        return pages

    def update_page(self, page_id: str, properties: dict) -> None:
        """Update page properties (e.g. mark Synced=True)."""
        url = f"{self.BASE}/pages/{page_id}"
        requests.patch(url, headers=self.headers,
                       json={"properties": properties}, timeout=10).raise_for_status()

    @staticmethod
    def extract_title(page: dict, prop_name: str = "Front") -> str:
        """Extract plain text from a title property."""
        try:
            parts = page["properties"][prop_name]["title"]
            return "".join(p["plain_text"] for p in parts).strip()
        except (KeyError, TypeError):
            return ""

    @staticmethod
    def extract_text(page: dict, prop_name: str = "Back") -> str:
        """Extract plain text from a rich_text property."""
        try:
            parts = page["properties"][prop_name]["rich_text"]
            return "".join(p["plain_text"] for p in parts).strip()
        except (KeyError, TypeError):
            return ""

    @staticmethod
    def extract_tags(page: dict, prop_name: str = "Tags") -> list[str]:
        try:
            opts = page["properties"][prop_name]["multi_select"]
            return [o["name"] for o in opts]
        except (KeyError, TypeError):
            return []

    @staticmethod
    def extract_select(page: dict, prop_name: str = "Deck") -> str:
        try:
            return page["properties"][prop_name]["select"]["name"]
        except (KeyError, TypeError):
            return ""

    @staticmethod
    def extract_checkbox(page: dict, prop_name: str = "Synced") -> bool:
        try:
            return bool(page["properties"][prop_name]["checkbox"])
        except (KeyError, TypeError):
            return False


# ── AnkiConnect client ────────────────────────────────────────────────────────
class AnkiConnect:
    def __init__(self, host: str = "localhost", port: int = 8765):
        self.url = f"http://{host}:{port}"

    def _call(self, action: str, **params) -> object:
        payload = {"action": action, "version": 6, "params": params}
        resp = requests.post(self.url, json=payload, timeout=10)
        resp.raise_for_status()
        data = resp.json()
        if data.get("error"):
            raise RuntimeError(f"AnkiConnect error: {data['error']}")
        return data.get("result")

    def is_alive(self) -> bool:
        try:
            self._call("version")
            return True
        except Exception:
            return False

    def ensure_deck(self, deck_name: str) -> None:
        self._call("createDeck", deck=deck_name)

    def note_exists(self, front: str, deck: str) -> bool:
        notes = self._call("findNotes",
                            query=f'deck:"{deck}" front:"{front}"')
        return bool(notes)

    def add_note(self, front: str, back: str,
                 deck: str, tags: list[str]) -> int:
        note_id = self._call("addNote", note={
            "deckName":  deck,
            "modelName": "Basic",
            "fields":    {"Front": front, "Back": back},
            "options":   {"allowDuplicate": False},
            "tags":      tags + ["flynn-auto"],
        })
        return int(note_id)

    def get_deck_stats(self) -> dict:
        try:
            return self._call("getDeckStats") or {}
        except Exception:
            return {}


# ── Sync logic ────────────────────────────────────────────────────────────────
@dataclass
class SyncStats:
    created: int = 0
    skipped: int = 0
    errors:  int = 0
    total:   int = 0
    new_ids: list[int] = field(default_factory=list)


def run_sync(cfg: dict) -> SyncStats:
    stats = SyncStats()

    if not cfg["notion_token"] or not cfg["notion_db_id"]:
        log.error("notion_token or notion_db_id not configured")
        return stats

    notion = NotionClient(cfg["notion_token"])
    anki_host = cfg.get("anki_host", "localhost")
    anki_port = int(cfg.get("anki_port", 8765))
    anki   = AnkiConnect(anki_host, anki_port)
    default_deck = cfg.get("default_deck", "Flynn::Auto")

    # Check Anki is reachable
    if not anki.is_alive():
        log.warning("AnkiConnect not reachable at %s:%d — is Anki running?",
                    anki_host, anki_port)
        return stats

    # Fetch unsynced cards from Notion
    try:
        pages = notion.query_database(
            cfg["notion_db_id"],
            filter_obj={"property": "Synced", "checkbox": {"equals": False}},
        )
    except requests.HTTPError as e:
        log.error("Notion API error: %s", e)
        return stats

    stats.total = len(pages)
    if not pages:
        log.debug("No new cards to sync")
        return stats

    log.info("Found %d unsynced card(s) in Notion", len(pages))

    for page in pages:
        page_id = page["id"]
        front = notion.extract_title(page, "Front") or notion.extract_title(page, "Name")
        back  = notion.extract_text(page, "Back")
        tags  = notion.extract_tags(page, "Tags")
        deck  = notion.extract_select(page, "Deck") or default_deck

        if not front or not back:
            log.warning("Skipping page %s — empty Front or Back", page_id[:8])
            stats.skipped += 1
            continue

        try:
            anki.ensure_deck(deck)
            note_id = anki.add_note(front, back, deck, tags)
            stats.created += 1
            stats.new_ids.append(note_id)
            log.info("  ✓ Created  [%s] %s", deck, front[:60])

            # Mark as synced in Notion
            notion.update_page(page_id, {
                "Synced": {"checkbox": True}
            })

        except RuntimeError as e:
            if "duplicate" in str(e).lower():
                log.debug("  = Duplicate: %s", front[:60])
                # Still mark as synced so we don't keep retrying
                try:
                    notion.update_page(page_id, {"Synced": {"checkbox": True}})
                except Exception:
                    pass
                stats.skipped += 1
            else:
                log.error("  ✗ Error for '%s': %s", front[:40], e)
                stats.errors += 1
        except Exception as e:
            log.error("  ✗ Unexpected error: %s", e)
            stats.errors += 1

    return stats


# ── Daemon loop ───────────────────────────────────────────────────────────────
def run_daemon(cfg: dict) -> None:
    interval = int(cfg.get("sync_interval", 60))
    log.info("Notion→Anki sync daemon starting (interval: %ds)", interval)
    log.info("Notion DB:  %s", cfg.get("notion_db_id", "NOT SET")[:16] + "...")
    log.info("Anki host:  %s:%s", cfg.get("anki_host"), cfg.get("anki_port"))

    while True:
        try:
            stats = run_sync(cfg)
            if stats.total > 0:
                log.info("Sync done — created:%d  skipped:%d  errors:%d",
                         stats.created, stats.skipped, stats.errors)
        except Exception as e:
            log.error("Sync loop error: %s", e)

        time.sleep(interval)


def print_status(cfg: dict) -> None:
    anki = AnkiConnect(cfg.get("anki_host", "localhost"),
                       int(cfg.get("anki_port", 8765)))

    print("\n╔══════════════════════════════════════════╗")
    print("║  Notion→Anki Sync Status                 ║")
    print("╚══════════════════════════════════════════╝\n")
    print(f"  Notion token:  {'SET' if cfg.get('notion_token') else 'NOT SET'}")
    print(f"  Notion DB:     {cfg.get('notion_db_id', 'NOT SET')[:20]}...")
    print(f"  Anki host:     {cfg.get('anki_host')}:{cfg.get('anki_port')}")
    print(f"  Anki alive:    {'YES ✓' if anki.is_alive() else 'NO ✗  (is Anki running?)'}")
    print(f"  Sync interval: {cfg.get('sync_interval')}s")
    print()


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    cfg = load_config()
    cmd = sys.argv[1] if len(sys.argv) > 1 else "daemon"

    if cmd == "daemon":
        run_daemon(cfg)
    elif cmd == "sync":
        stats = run_sync(cfg)
        print(f"Sync complete: {stats.created} created, "
              f"{stats.skipped} skipped, {stats.errors} errors")
    elif cmd == "status":
        print_status(cfg)
    else:
        print(f"Usage: {sys.argv[0]} daemon|sync|status")
        sys.exit(1)
