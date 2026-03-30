#!/usr/bin/env python3
"""Single experiment runner — one command, one JSON output.

Usage: uv run run_experiment.py

Contract:
    - Input: none (code changes already committed)
    - Output: exactly 1 JSON line on stdout (last line)
    - Exit 0: experiment completed (agent judges keep/discard by score)
    - Exit 1: crash (agent should revert)

Customize RUN_CMD and parse_result() for your project.
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

AUTORESEARCH_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = AUTORESEARCH_DIR.parent
RESULTS_TSV = AUTORESEARCH_DIR / "results.tsv"
RUN_LOG = AUTORESEARCH_DIR / "run.log"

# === CUSTOMIZE THESE FOR YOUR PROJECT ===

# Command to run one experiment (relative to PROJECT_ROOT)
RUN_CMD = ["uv", "run", "train.py"]  # ML example
# RUN_CMD = ["python3", "autoresearch/e2e_test.py", "--baseline", "--json"]  # Web E2E example

# Timeout per experiment (seconds)
TIMEOUT = 300  # 5 minutes default

# TSV header — customize columns for your metrics
TSV_HEADER = "commit\tscore\tduration_s\tstatus\tverdict\tdescription\n"


def parse_result(stdout: str, stderr: str, exit_code: int, duration: float) -> dict[str, object]:
    """Parse experiment output into standardized JSON.

    Customize this for your project's output format.

    Must return dict with at least: score, status, duration_s
    """
    # Example: parse last line as "val_bpb: 0.9832"
    score = None
    for line in reversed(stdout.strip().split("\n")):
        if "val_bpb" in line:
            try:
                score = float(line.split(":")[-1].strip())
            except ValueError:
                pass
            break

    if exit_code != 0 and score is None:
        return {
            "score": None,
            "status": "crash",
            "reason": stderr[-500:] if stderr else "unknown",
            "duration_s": duration,
        }

    return {
        "score": score,
        "status": "ok" if score is not None else "crash",
        "duration_s": duration,
    }


# === END CUSTOMIZATION ===


def get_git_info() -> tuple[str, str]:
    try:
        sha = subprocess.run(
            "git rev-parse --short HEAD", shell=True,
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
        msg = subprocess.run(
            "git log -1 --format=%s", shell=True,
            capture_output=True, text=True, timeout=5,
        ).stdout.strip()
        return sha, msg
    except Exception:
        return "unknown", "unknown"


def append_results_tsv(data: dict[str, object], commit: str, description: str) -> None:
    if not RESULTS_TSV.exists():
        RESULTS_TSV.write_text(TSV_HEADER)

    row = "\t".join([
        commit,
        str(data.get("score", "")),
        str(data.get("duration_s", "")),
        str(data.get("status", "")),
        "",  # verdict — agent fills this later
        description,
    ])
    with open(RESULTS_TSV, "a") as f:
        f.write(row + "\n")


def main() -> None:
    start = time.time()

    result = subprocess.run(
        RUN_CMD,
        capture_output=True, text=True, timeout=TIMEOUT,
        cwd=str(PROJECT_ROOT),
    )

    duration = round(time.time() - start, 1)

    # Save full output to run.log
    with open(RUN_LOG, "w") as f:
        f.write(f"=== run_experiment.py — {datetime.now(timezone.utc).isoformat()} ===\n")
        f.write(f"cmd: {' '.join(RUN_CMD)}\n")
        f.write(f"exit_code: {result.returncode}\nduration: {duration}s\n\n")
        f.write("--- stdout ---\n" + result.stdout)
        f.write("\n--- stderr ---\n" + result.stderr)

    data = parse_result(result.stdout, result.stderr, result.returncode, duration)

    commit, description = get_git_info()
    append_results_tsv(data, commit, description)

    print(json.dumps(data))
    sys.exit(0 if data.get("status") == "ok" else 1)


if __name__ == "__main__":
    main()
