#!/usr/bin/env python3
"""Limit League of Legends to N games per day on macOS.

Runs as a background watcher (see install.sh). It polls running processes:
  - When a match (LeagueofLegends) ends after MIN_GAME_SECONDS, it counts as a game.
  - Once today's limit is reached, the League client is closed whenever it opens,
    and any new match that starts is closed immediately.

Usage:
  league_limit.py watch     run the watcher loop (used by launchd)
  league_limit.py status    show today's usage
  league_limit.py json      today's usage as JSON (used by the menu bar app)
  league_limit.py bonus     allow 1 more game today
"""

import fcntl
import json
import os
import signal
import subprocess
import sys
import time
from datetime import datetime, timedelta

GAMES_PER_DAY = 1
# The "day" rolls over at this local hour, so a 1am game counts toward the previous day.
RESET_HOUR = 4
# Matches shorter than this (e.g. remakes) don't count.
MIN_GAME_SECONDS = 5 * 60
# Time allowed in the post-game lobby after your last game before the client is closed.
POST_GAME_GRACE_SECONDS = 90
POLL_SECONDS = 5

GAME_PROCESSES = ["LeagueofLegends"]
CLIENT_PROCESSES = [
    "LeagueClient",
    "LeagueClientUx",
    "LeagueClientUx Helper",
    "LeagueClientUx Helper (GPU)",
    "LeagueClientUx Helper (Renderer)",
]

STATE_DIR = os.path.expanduser("~/Library/Application Support/league-limit")
STATE_FILE = os.path.join(STATE_DIR, "state.json")
LOCK_FILE = os.path.join(STATE_DIR, "state.lock")


def day_key(ts):
    return (datetime.fromtimestamp(ts) - timedelta(hours=RESET_HOUR)).strftime("%Y-%m-%d")


def load_state():
    try:
        with open(STATE_FILE) as f:
            state = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        state = {}
    state.setdefault("games", {})
    state.setdefault("bonus", {})
    state.setdefault("current_game_start", None)
    state.setdefault("last_game_end", None)
    return state


def save_state(state):
    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, STATE_FILE)


def state_lock():
    """Exclusive lock so the watcher and `bonus` don't overwrite each other's changes."""
    os.makedirs(STATE_DIR, exist_ok=True)
    f = open(LOCK_FILE, "w")
    fcntl.flock(f, fcntl.LOCK_EX)
    return f


def is_running(names):
    for name in names:
        if subprocess.run(["pgrep", "-x", name], capture_output=True).returncode == 0:
            return True
    return False


def kill(names):
    for name in names:
        subprocess.run(["pkill", "-x", name], capture_output=True)
    time.sleep(2)
    for name in names:
        subprocess.run(["pkill", "-KILL", "-x", name], capture_output=True)


def notify(message):
    print(f"[{datetime.now():%Y-%m-%d %H:%M:%S}] {message}", flush=True)
    script = f'display notification {json.dumps(message)} with title "League limit"'
    subprocess.run(["osascript", "-e", script], capture_output=True)


def games_today(state, now):
    return state["games"].get(day_key(now), 0)


def limit_today(state, now):
    return GAMES_PER_DAY + state["bonus"].get(day_key(now), 0)


def tick(state, now, game_running, client_running):
    """Advance the state machine one step. Returns (actions, changed).

    actions is a list of ("kill_game" | "kill_client", message) tuples.
    """
    actions = []
    changed = False
    start = state["current_game_start"]
    limit_reached = games_today(state, now) >= limit_today(state, now)

    if game_running and start is None:
        if limit_reached:
            actions.append(("kill_game", "You've already played your game today. See you tomorrow."))
        else:
            state["current_game_start"] = now
            changed = True
    elif not game_running and start is not None:
        state["current_game_start"] = None
        if now - start >= MIN_GAME_SECONDS:
            key = day_key(start)
            state["games"][key] = state["games"].get(key, 0) + 1
            state["last_game_end"] = now
            limit_reached = games_today(state, now) >= limit_today(state, now)
        changed = True

    if limit_reached and client_running and not game_running and state["current_game_start"] is None:
        last_end = state["last_game_end"] or 0
        if now - last_end >= POST_GAME_GRACE_SECONDS:
            actions.append(("kill_client", "Daily League limit reached. Client closed. See you tomorrow."))

    return actions, changed


def watch():
    print(f"league-limit watching (limit {GAMES_PER_DAY}/day, reset {RESET_HOUR}:00)", flush=True)
    last_notice = 0
    while True:
        game_running = is_running(GAME_PROCESSES)
        client_running = is_running(CLIENT_PROCESSES)
        with state_lock():
            state = load_state()
            now = time.time()
            actions, changed = tick(state, now, game_running, client_running)
            if changed:
                save_state(state)
        for action, message in actions:
            kill(GAME_PROCESSES + CLIENT_PROCESSES if action == "kill_game" else CLIENT_PROCESSES)
            if now - last_notice > 30:
                notify(message)
                last_notice = now
        time.sleep(POLL_SECONDS)


def status():
    state = load_state()
    now = time.time()
    played = games_today(state, now)
    limit = limit_today(state, now)
    print(f"Today ({day_key(now)}): {played}/{limit} games played")
    if state["current_game_start"]:
        mins = int((now - state["current_game_start"]) // 60)
        print(f"In a game right now ({mins} min)")
    elif played >= limit:
        print(f"Limit reached. Resets at {RESET_HOUR}:00.")
    recent = sorted(state["games"].items())[-7:]
    if recent:
        print("Last days:", ", ".join(f"{d}: {n}" for d, n in recent))


def status_json():
    state = load_state()
    now = time.time()
    start = state["current_game_start"]
    print(json.dumps({
        "day": day_key(now),
        "played": games_today(state, now),
        "limit": limit_today(state, now),
        "bonus": state["bonus"].get(day_key(now), 0),
        "reset_hour": RESET_HOUR,
        "in_game_minutes": int((now - start) // 60) if start else None,
        "history": dict(sorted(state["games"].items())[-7:]),
    }))


def add_bonus():
    with state_lock():
        state = load_state()
        key = day_key(time.time())
        state["bonus"][key] = state["bonus"].get(key, 0) + 1
        save_state(state)
    print(f"1 more game allowed today. Limit is now {limit_today(state, time.time())}.")


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "watch":
        watch()
    elif cmd == "status":
        status()
    elif cmd == "json":
        status_json()
    elif cmd == "bonus":
        add_bonus()
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
