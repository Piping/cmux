#!/usr/bin/env python3
"""
Regression: shell integrations must retry cwd reports for the same PWD.

A transient socket miss can happen while a terminal is starting or the app is
restoring surfaces. If the shell marks a PWD as reported before the app records
it, terminal file clicks resolve relative names against a stale workspace cwd
forever. The prompt hook should periodically re-emit report_pwd even when PWD
has not changed.
"""

from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHELL_DIR = ROOT / "Resources" / "shell-integration"


def _run_shell(shell: str, shell_args: list[str], integration_path: Path, log_path: Path) -> tuple[int, str]:
    env = dict(os.environ)
    env.update(
        {
            "CMUX_SOCKET_PATH": str(log_path.parent / "cmux.sock"),
            "CMUX_TAB_ID": "11111111-1111-1111-1111-111111111111",
            "CMUX_PANEL_ID": "22222222-2222-2222-2222-222222222222",
            "CMUX_PWD_REPORT_INTERVAL": "1",
            "CMUX_TEST_LOG": str(log_path),
        }
    )
    prompt_hook = "_cmux_precmd" if shell == "zsh" else "_cmux_prompt_command"
    command = f"""
source "{integration_path}"
_cmux_send() {{ printf '%s\\n' "$1" >> "$CMUX_TEST_LOG"; }}
_cmux_send_bg() {{ _cmux_send "$1"; }}
_cmux_socket_is_unix() {{ return 0; }}
_cmux_has_port_scan_transport() {{ return 0; }}
_cmux_spawn_detached() {{ "$@"; }}
_cmux_spawn_detached_capture_pid() {{ return 1; }}
_cmux_report_tty_once() {{ :; }}
_cmux_report_shell_activity_state() {{ :; }}
_cmux_ports_kick() {{ :; }}
_cmux_probe_git_branch() {{ :; }}
_cmux_start_pr_poll_loop() {{ :; }}
_cmux_stop_pr_poll_loop() {{ :; }}
_cmux_emit_pr_command_hint() {{ :; }}
_cmux_clear_pr_for_panel() {{ :; }}
_cmux_pr_cache_clear() {{ :; }}
_cmux_now() {{ printf '%s\\n' "$CMUX_TEST_NOW"; }}
: > "$CMUX_TEST_LOG"
CMUX_TEST_NOW=10
{prompt_hook}
CMUX_TEST_NOW=10
{prompt_hook}
CMUX_TEST_NOW=11
{prompt_hook}
grep -c '^report_pwd ' "$CMUX_TEST_LOG"
""".strip()
    result = subprocess.run(
        [shell, *shell_args, command],
        env=env,
        capture_output=True,
        text=True,
        timeout=8,
        check=False,
    )
    return result.returncode, ((result.stdout or "") + (result.stderr or "")).strip()


def main() -> int:
    failures: list[str] = []
    with tempfile.TemporaryDirectory(prefix="cmux-pwd-report-retry-") as td:
        tmp = Path(td)
        cases = [
            ("zsh", ["-f", "-c"], SHELL_DIR / "cmux-zsh-integration.zsh"),
            ("bash", ["--noprofile", "--norc", "-c"], SHELL_DIR / "cmux-bash-integration.bash"),
        ]
        for shell, shell_args, script in cases:
            code, output = _run_shell(shell, shell_args, script, tmp / f"{shell}.log")
            if code != 0:
                failures.append(f"{shell} exited {code}: {output}")
                continue
            if output != "2":
                failures.append(f"{shell} expected two cwd reports across the retry interval, got {output!r}")

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}")
        return 1

    print("PASS: shell integrations retry same-PWD cwd reports")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
