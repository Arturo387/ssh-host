#!/usr/bin/env python3
"""List explicitly configured SSH aliases and report their control state."""

import glob
import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path


CONFIG_PATH = Path.home() / ".ssh" / "config"
CONTROL_DIR = Path.home() / ".ssh" / "control"
CONTROL_PATH = str(CONTROL_DIR / "%C")
SSH = shutil.which("ssh")


def configured_aliases(config_path):
    """Return concrete aliases from the config and its Include files."""
    aliases = []
    visited = set()
    pending = [Path(config_path)]

    while pending:
        path = pending.pop()
        try:
            resolved = path.resolve()
            if resolved in visited:
                continue
            visited.add(resolved)
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue

        for raw_line in lines:
            try:
                parts = shlex.split(raw_line, comments=True)
            except ValueError:
                continue
            if not parts:
                continue
            key = parts[0].lower()
            if key == "host":
                for alias in parts[1:]:
                    if alias and not alias.startswith("!") and not any(ch in alias for ch in "*?[]"):
                        if alias not in aliases:
                            aliases.append(alias)
            elif key == "include":
                for pattern in parts[1:]:
                    expanded = os.path.expanduser(os.path.expandvars(pattern))
                    expanded = expanded.replace("%d", str(Path.home()))
                    include_pattern = Path(expanded)
                    if not include_pattern.is_absolute():
                        include_pattern = Path.home() / ".ssh" / include_pattern
                    pending.extend(Path(match) for match in sorted(glob.glob(str(include_pattern))))

    return sorted(aliases)


def ssh_output(arguments, timeout=3):
    if not SSH:
        return None
    try:
        return subprocess.run(
            [SSH, *arguments],
            capture_output=True,
            text=True,
            check=False,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def local_forwards(alias):
    proc = ssh_output([
        "-G",
        "-F", str(CONFIG_PATH),
        "-o", f"ControlPath={CONTROL_PATH}",
        alias,
    ])
    if proc is None or proc.returncode != 0:
        return []

    forwards = []
    for line in proc.stdout.splitlines():
        try:
            parts = shlex.split(line)
        except ValueError:
            continue
        if len(parts) < 2 or parts[0].lower() != "localforward":
            continue
        endpoint = parts[1]
        port_text = endpoint.rsplit(":", 1)[-1]
        if port_text.isdigit():
            forwards.append(int(port_text))
    return forwards


def is_connected(alias):
    proc = ssh_output([
        "-F", str(CONFIG_PATH),
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=1",
        "-o", f"ControlPath={CONTROL_PATH}",
        "-O", "check",
        alias,
    ], timeout=2)
    return proc is not None and proc.returncode == 0


def list_state():
    hosts = configured_aliases(CONFIG_PATH)
    state = {}
    for host in hosts:
        connected = is_connected(host)
        state[host] = {
            "connected": connected,
            "forwards": local_forwards(host),
        }
    return {"hosts": hosts, "state": state}


def connect(alias):
    if not SSH:
        return 127
    CONTROL_DIR.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.execv(SSH, [
        SSH,
        "-N",
        "-o", "BatchMode=yes",
        "-o", "ExitOnForwardFailure=yes",
        "-o", "ControlMaster=auto",
        "-o", f"ControlPath={CONTROL_PATH}",
        "-o", "ControlPersist=30m",
        alias,
    ])
    return 0


def disconnect(alias):
    proc = ssh_output([
        "-F", str(CONFIG_PATH),
        "-o", "BatchMode=yes",
        "-o", "ConnectTimeout=1",
        "-o", f"ControlPath={CONTROL_PATH}",
        "-O", "exit",
        alias,
    ], timeout=3)
    return proc.returncode if proc is not None else 1


def main(argv):
    if len(argv) == 3 and argv[1] == "connect":
        return connect(argv[2])
    if len(argv) == 3 and argv[1] == "disconnect":
        return disconnect(argv[2])
    print(json.dumps(list_state(), separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
