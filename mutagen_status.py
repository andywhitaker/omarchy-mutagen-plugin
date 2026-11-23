#!/usr/bin/env python3
"""Read-only status collector for the Omarchy Mutagen bar widget.

Probes the Mutagen daemon Unix socket directly before invoking the CLI so
checking status never auto-starts a stopped daemon.
"""

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys


def resolve_data_directory():
    raw = os.environ.get("MUTAGEN_DATA_DIRECTORY", "").strip()
    if raw:
        return os.path.expanduser(raw)
    return os.path.expanduser("~/.mutagen")


def is_daemon_running():
    data_dir = resolve_data_directory()
    sock_path = os.path.join(data_dir, "daemon", "daemon.sock")
    if not os.path.exists(sock_path):
        return False

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        sock.settimeout(0.5)
        sock.connect(sock_path)
        return True
    except OSError:
        return False
    finally:
        try:
            sock.close()
        except OSError:
            pass


def run_command(args, timeout=5):
    try:
        proc = subprocess.run(
            args,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return 124, "", f"Command timed out: {' '.join(args)}"
    except OSError as exc:
        return 127, "", str(exc)
    return proc.returncode, proc.stdout, proc.stderr


def fetch_json_list(mutagen_bin, subcommand, timeout=5):
    code, stdout, stderr = run_command(
        [mutagen_bin, subcommand, "list", "--template", "{{json .}}"],
        timeout=timeout,
    )
    if code != 0:
        detail = (stderr or stdout).strip() or f"mutagen {subcommand} list failed (exit {code})"
        return None, detail

    text = stdout.strip()
    if not text or text == "null":
        return [], ""

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError as exc:
        return None, f"Failed to parse mutagen {subcommand} JSON: {exc}"

    if parsed is None:
        return [], ""
    if not isinstance(parsed, list):
        return None, f"Unexpected mutagen {subcommand} JSON payload"
    return parsed, ""


def fetch_version(mutagen_bin, syncs):
    code, stdout, _ = run_command([mutagen_bin, "version"], timeout=3)
    if code == 0:
        line = stdout.strip().splitlines()[0].strip() if stdout.strip() else ""
        if line:
            return line
    for item in syncs or []:
        if isinstance(item, dict) and item.get("creatingVersion"):
            return str(item["creatingVersion"])
    return ""


def emit(payload):
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")


def main():
    parser = argparse.ArgumentParser(description="Emit Mutagen daemon and session status as JSON.")
    parser.add_argument(
        "--forwards",
        action="store_true",
        help="Also query network forwarding sessions.",
    )
    args = parser.parse_args()

    mutagen_bin = shutil.which("mutagen")
    if not mutagen_bin:
        emit({
            "installed": False,
            "daemonRunning": False,
            "version": "",
            "syncs": [],
            "forwards": [],
            "error": "",
        })
        return 0

    if not is_daemon_running():
        emit({
            "installed": True,
            "daemonRunning": False,
            "version": "",
            "syncs": [],
            "forwards": [],
            "error": "",
        })
        return 0

    errors = []

    syncs, sync_err = fetch_json_list(mutagen_bin, "sync", timeout=5)
    if sync_err:
        errors.append(sync_err)
        syncs = []

    forwards = []
    if args.forwards:
        fetched_forwards, fwd_err = fetch_json_list(mutagen_bin, "forward", timeout=5)
        if fwd_err:
            errors.append(fwd_err)
        else:
            forwards = fetched_forwards

    version = fetch_version(mutagen_bin, syncs)

    emit({
        "installed": True,
        "daemonRunning": True,
        "version": version,
        "syncs": syncs,
        "forwards": forwards,
        "error": "; ".join(errors),
    })
    return 0


if __name__ == "__main__":
    sys.exit(main())
