#!/usr/bin/env python3
"""
Weekly maintenance for the local Codex state directory.

Dry-run by default. Use --apply after closing Codex.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path


CODEX_HOME = Path(os.environ.get("CODEX_HOME", "~/.codex")).expanduser()
BACKUP_ROOT = Path("/private/tmp/codex-maintenance-backups")


def human_size(num: int) -> str:
    for unit in ("B", "K", "M", "G", "T"):
        if num < 1024 or unit == "T":
            return f"{num:.1f}{unit}" if unit != "B" else f"{num}B"
        num /= 1024
    return f"{num:.1f}T"


def tree_size(path: Path) -> int:
    if not path.exists():
        return 0
    if path.is_file():
        return path.stat().st_size
    total = 0
    for item in path.rglob("*"):
        try:
            if item.is_file():
                total += item.stat().st_size
        except OSError:
            pass
    return total


def codex_is_running() -> bool | None:
    try:
        result = subprocess.run(
            ["pgrep", "-af", "Codex|codex app-server"],
            text=True,
            check=False,
            capture_output=True,
        )
        if result.returncode == 0:
            return True
        if result.returncode not in (1,):
            return None
    except OSError:
        pass

    try:
        result = subprocess.run(
            ["ps", "-axo", "comm,args"],
            text=True,
            check=False,
            capture_output=True,
        )
    except OSError:
        return None
    if result.returncode != 0:
        return None
    haystack = result.stdout.lower()
    return "/applications/codex.app" in haystack or "codex app-server" in haystack


def backup_state() -> Path:
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = BACKUP_ROOT / f"codex-backup-{stamp}"
    backup.mkdir(parents=True, exist_ok=False)

    files = [
        "config.toml",
        ".codex-global-state.json",
        "session_index.jsonl",
        "state_5.sqlite",
        "state_5.sqlite-wal",
        "state_5.sqlite-shm",
        "logs_2.sqlite",
        "logs_2.sqlite-wal",
        "logs_2.sqlite-shm",
    ]
    dirs = ["memories", "skills", "plugins", "automations"]

    for name in files:
        src = CODEX_HOME / name
        if src.exists():
            shutil.copy2(src, backup / name)

    for name in dirs:
        src = CODEX_HOME / name
        if src.exists():
            shutil.copytree(src, backup / name, symlinks=True)

    inventory = backup / "inventory.json"
    inventory.write_text(
        json.dumps(inspect_state(), indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    return backup


def inspect_state() -> dict:
    roots = [
        "sessions",
        "archived_sessions",
        "worktrees",
        "archived_worktrees",
        "log",
        "logs",
        "plugins",
        "skills",
        "automations",
        "memories",
    ]
    sizes = {name: tree_size(CODEX_HOME / name) for name in roots}
    for name in ("state_5.sqlite", "logs_2.sqlite", "session_index.jsonl", "config.toml"):
        sizes[name] = tree_size(CODEX_HOME / name)

    sessions = sorted(
        (p for p in (CODEX_HOME / "sessions").rglob("*.jsonl") if p.is_file()),
        key=lambda p: p.stat().st_size,
        reverse=True,
    )
    worktrees = []
    for path in (CODEX_HOME / "worktrees").glob("*"):
        if path.is_dir():
            worktrees.append({"path": str(path), "bytes": tree_size(path), "mtime": path.stat().st_mtime})
    worktrees.sort(key=lambda item: item["bytes"], reverse=True)

    return {
        "codex_home": str(CODEX_HOME),
        "generated_at": dt.datetime.now().isoformat(timespec="seconds"),
        "sizes": {key: human_size(value) for key, value in sizes.items()},
        "largest_sessions": [
            {
                "path": str(path),
                "bytes": human_size(path.stat().st_size),
                "mtime": dt.datetime.fromtimestamp(path.stat().st_mtime).isoformat(timespec="seconds"),
            }
            for path in sessions[:25]
        ],
        "worktrees": [
            {
                "path": item["path"],
                "bytes": human_size(item["bytes"]),
                "mtime": dt.datetime.fromtimestamp(item["mtime"]).isoformat(timespec="seconds"),
            }
            for item in worktrees
        ],
    }


def thread_columns(conn: sqlite3.Connection) -> set[str]:
    return {row[1] for row in conn.execute("pragma table_info(threads)")}


def pinned_clause(columns: set[str]) -> str:
    for column in ("pinned", "is_pinned", "favorite", "starred"):
        if column in columns:
            return f"coalesce({column}, 0) = 0"
    return "1 = 1"


def archive_old_sessions(days: int, apply: bool) -> list[str]:
    db = CODEX_HOME / "state_5.sqlite"
    if not db.exists():
        return []

    cutoff = int((dt.datetime.now() - dt.timedelta(days=days)).timestamp())
    moved: list[str] = []
    archive_dir = CODEX_HOME / "archived_sessions"
    archive_dir.mkdir(exist_ok=True)

    conn = sqlite3.connect(db)
    try:
        columns = thread_columns(conn)
        pin_sql = pinned_clause(columns)
        rows = conn.execute(
            f"""
            select id, rollout_path
            from threads
            where archived = 0
              and updated_at < ?
              and {pin_sql}
            order by updated_at asc
            """,
            (cutoff,),
        ).fetchall()

        for thread_id, rollout_path in rows:
            src = Path(rollout_path).expanduser()
            if not src.exists():
                continue
            dest = archive_dir / src.name
            moved.append(str(src))
            if apply:
                shutil.move(str(src), str(dest))
                conn.execute(
                    "update threads set archived = 1, archived_at = ? where id = ?",
                    (int(dt.datetime.now().timestamp()), thread_id),
                )
        if apply:
            conn.commit()
    finally:
        conn.close()
    return moved


def rotate_logs(max_mb: int, apply: bool) -> list[str]:
    rotated: list[str] = []
    archive = CODEX_HOME / "archived_logs"
    threshold = max_mb * 1024 * 1024
    for path in CODEX_HOME.glob("logs*.sqlite*"):
        if path.is_file() and path.stat().st_size >= threshold:
            rotated.append(str(path))
            if apply:
                archive.mkdir(exist_ok=True)
                shutil.move(str(path), str(archive / path.name))
    for folder_name in ("log", "logs"):
        folder = CODEX_HOME / folder_name
        if not folder.exists():
            continue
        for path in folder.rglob("*"):
            if path.is_file() and path.stat().st_size >= threshold:
                rotated.append(str(path))
                if apply:
                    archive.mkdir(exist_ok=True)
                    shutil.move(str(path), str(archive / path.name))
    return rotated


def move_stale_worktrees(days: int, apply: bool) -> list[str]:
    cutoff = dt.datetime.now().timestamp() - (days * 86400)
    moved: list[str] = []
    archive = CODEX_HOME / "archived_worktrees"
    for path in (CODEX_HOME / "worktrees").glob("*"):
        if path.is_dir() and path.stat().st_mtime < cutoff:
            moved.append(str(path))
            if apply:
                archive.mkdir(exist_ok=True)
                shutil.move(str(path), str(archive / path.name))
    return moved


def prune_config_projects(apply: bool) -> list[str]:
    config = CODEX_HOME / "config.toml"
    if not config.exists():
        return []
    text = config.read_text(encoding="utf-8")
    stale: list[str] = []
    pattern = re.compile(r'(?ms)^\[projects\."([^"]+)"\]\n(?:^[^\[].*?\n)*')
    for match in list(pattern.finditer(text)):
        project = match.group(1).replace("\\\\?\\", "")
        is_temp = any(part in project for part in ("/tmp/", "/private/tmp/", "\\Temp\\", "\\tmp\\"))
        if is_temp or not Path(project).expanduser().exists():
            stale.append(match.group(1))
            if apply:
                text = text.replace(match.group(0), "")
    if apply and stale:
        config.write_text(text, encoding="utf-8")
    return stale


def verify() -> dict:
    checks: dict[str, object] = {}
    db = CODEX_HOME / "state_5.sqlite"
    if db.exists():
        conn = sqlite3.connect(db)
        try:
            checks["state_database"] = conn.execute("pragma integrity_check").fetchone()[0]
            checks["active_threads"] = conn.execute("select count(*) from threads where archived = 0").fetchone()[0]
            checks["archived_threads"] = conn.execute("select count(*) from threads where archived = 1").fetchone()[0]
        finally:
            conn.close()

    config = CODEX_HOME / "config.toml"
    if config.exists():
        try:
            import tomllib

            tomllib.loads(config.read_text(encoding="utf-8"))
            checks["config_toml"] = "ok"
        except Exception as exc:
            checks["config_toml"] = f"error: {exc}"

    bad_paths = prune_config_projects(apply=False)
    checks["bad_config_project_paths"] = bad_paths
    checks["active_session_size"] = human_size(tree_size(CODEX_HOME / "sessions"))
    checks["archived_session_size"] = human_size(tree_size(CODEX_HOME / "archived_sessions"))
    return checks


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="make changes; default is dry-run")
    parser.add_argument("--session-days", type=int, default=10)
    parser.add_argument("--worktree-days", type=int, default=14)
    parser.add_argument("--log-max-mb", type=int, default=100)
    args = parser.parse_args()

    running = codex_is_running()
    if args.apply and running is not False:
        print(
            "Refusing to apply cleanup because Codex is running or process inspection is unavailable. "
            "Close Codex and rerun from a normal Terminal.",
            file=sys.stderr,
        )
        return 2

    before = inspect_state()
    backup = backup_state()
    sessions = archive_old_sessions(args.session_days, args.apply)
    worktrees = move_stale_worktrees(args.worktree_days, args.apply)
    logs = rotate_logs(args.log_max_mb, args.apply)
    stale_projects = prune_config_projects(args.apply)
    after = inspect_state()
    checks = verify()

    report = {
        "mode": "apply" if args.apply else "dry-run",
        "codex_running": running,
        "backup": str(backup),
        "would_or_did_archive_sessions": len(sessions),
        "would_or_did_move_worktrees": worktrees,
        "would_or_did_rotate_logs": logs,
        "would_or_did_prune_config_projects": stale_projects,
        "before_sizes": before["sizes"],
        "after_sizes": after["sizes"],
        "verification": checks,
    }
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
