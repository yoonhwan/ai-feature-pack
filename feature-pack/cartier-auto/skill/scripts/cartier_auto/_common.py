#!/usr/bin/env python3
"""공용 유틸리티: 경로/자격증명/상태/로깅/시간/재시도."""

from __future__ import annotations

import json
import os
import re
import subprocess
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Callable, TypeVar

KST = timezone(timedelta(hours=9), name="KST")
T = TypeVar("T")

PACKAGE_DIR = Path(__file__).resolve().parent.parent  # .../scripts
PROJECT_DIR = PACKAGE_DIR.parent                      # 스킬 루트 (SKILL.md 위치)
STATE_HOME = Path(os.environ.get("CARTIER_AUTO_STATE", Path.home() / ".local" / "state" / "cartier-auto"))
CRED_FILE = Path(os.environ.get("CARTIER_AUTO_CREDENTIALS", Path.home() / ".config" / "cartier-auto" / "credentials.env"))
JOBS_DIR = STATE_HOME / "jobs"
LOG_DIR = STATE_HOME / "logs"
RUNS_DIR = STATE_HOME / "runs"
INSTALL_FILE = STATE_HOME / "installed.json"

REQUIRED_CREDS = ("CARTIER_ID", "CARTIER_PASSWORD", "NAVER_ID", "NAVER_PASSWORD")


@dataclass
class JobSpec:
    pid: str
    name: str
    price_krw: int | None
    run_at: str            # KST ISO
    interval: float
    approved_price: int
    created_at: str
    status: str = "SCHEDULED"
    navigator: str = ""
    transitions: list | None = None

    def to_json(self) -> dict:
        return asdict(self)


def now_kst() -> datetime:
    return datetime.now(KST)


def ts() -> str:
    return now_kst().isoformat(timespec="milliseconds")


def ensure_dirs() -> None:
    for d in (STATE_HOME, JOBS_DIR, LOG_DIR, RUNS_DIR):
        d.mkdir(parents=True, exist_ok=True)


def load_job(job_id: str) -> dict | None:
    path = JOBS_DIR / f"{job_id}.json"
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def save_job(job: dict) -> None:
    ensure_dirs()
    path = JOBS_DIR / f"{job['id']}.json"
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(job, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


def log(message: str, job_id: str | None = None) -> None:
    line = f"[{ts()}] {message}"
    print(line, flush=True)
    if job_id:
        ensure_dirs()
        with open(LOG_DIR / f"{job_id}.log", "a", encoding="utf-8") as fh:
            fh.write(line + "\n")


def load_creds() -> dict:
    """자격증명 우선순위: env > credentials.env."""
    creds: dict[str, str] = {}
    if CRED_FILE.exists():
        try:
            creds.update(parse_env_file(CRED_FILE))
        except OSError:
            pass
    for name in REQUIRED_CREDS:
        if os.environ.get(name):
            creds[name] = os.environ[name]
    return creds


def unescape_env_value(value: str) -> str:
    """shell-style quoting 복원: '\'' → ' , \" → " 등."""
    value = value.replace("'\\''", "'").replace('\\"', '"').replace("\\\\", "\\")
    return value


def parse_env_file(path: Path) -> dict[str, str]:
    """credentials.env 파서: export/따옴표/인라인 #주석 지원."""
    out: dict[str, str] = {}
    text = path.read_text(encoding="utf-8")
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        line = re.sub(r"^export\s+", "", line)
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        if not key:
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        elif "#" in value:
            value = value.split("#", 1)[0].rstrip()
        decoded = unescape_env_value(value)
        if decoded:
            out[key] = decoded
    return out


def creds_ready() -> bool:
    creds = load_creds()
    return all(creds.get(k) for k in REQUIRED_CREDS)


def missing_creds() -> list[str]:
    creds = load_creds()
    return [k for k in REQUIRED_CREDS if not creds.get(k)]


def run_capture(cmd: list[str], timeout: float = 30) -> tuple[int, str]:
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, (proc.stdout or "") + (proc.stderr or "")
    except subprocess.TimeoutExpired as exc:
        return 124, str(exc) if exc else ""




def is_running(pid: int) -> bool:
    """PID 프로세스가 살아있는지."""
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def tmux_available() -> bool:
    rc, _ = run_capture(["bash", "-lc", "command -v tmux >/dev/null 2>&1 && tmux ls >/dev/null 2>&1; echo $?"])
    return rc == 0


def with_retry(operation: Callable[[], T], label: str, max_attempts: int = 5, base_delay: float = 1.0,
               max_delay: float = 30.0) -> T:
    delay = base_delay
    last_error: Exception | None = None
    for attempt in range(1, max_attempts + 1):
        try:
            return operation()
        except Exception as exc:
            last_error = exc
            text = str(exc).lower()
            rate_limited = "rate limit" in text or "too many requests" in text or "429" in text or isinstance(exc, RetryBudgetExceeded)
            if not rate_limited and not isinstance(exc, TimeoutError) and not isinstance(exc, OSError):
                raise
            log(f"{label} 실패 {attempt}/{max_attempts}: {exc} → {delay:.1f}초 후 재시도")
            time.sleep(delay)
            delay = min(delay * (2 ** attempt), max_delay)
    raise RetryBudgetExceeded(f"{label} 재시도 한도 초과") from last_error


class RetryBudgetExceeded(RuntimeError):
    pass


# ---- 설치 상태 ----

def record_install(env: dict | None = None, version: str = "1.0.0") -> dict:
    """설치 완료 상태를 installed.json에 기록하고 반환."""
    ensure_dirs()
    payload = {
        "installed": True,
        "version": version,
        "installed_at": ts(),
        "env": env or {},
    }
    tmp = INSTALL_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(INSTALL_FILE)
    return payload


def read_install_state() -> dict:
    """저장된 설치 상태를 읽는다. 없거나 installed=false면 미설치."""
    try:
        data = json.loads(INSTALL_FILE.read_text(encoding="utf-8"))
        if data.get("installed"):
            return data
    except Exception:
        pass
    return {"installed": False}


def is_installed() -> bool:
    return bool(read_install_state().get("installed"))


def install_targets() -> dict:
    """설치 목록: 경로·심볼릭링크·바이너리 존재 여부."""
    home = Path.home()
    dest = home / ".local" / "share" / "cartier-auto" / "skill"
    links = {
        "codex_skill": home / ".codex" / "skills" / "cartier-auto",
        "claude_skill": home / ".claude" / "skills" / "cartier-auto",
        "claude_command": home / ".claude" / "commands" / "cartier-auto.md",
        "bin": home / ".local" / "bin" / "cartier-auto",
    }
    out = {"skill_dir": str(dest), "exists": dest.exists()}
    for key, path in links.items():
        out[key] = {"path": str(path), "exists": path.exists(), "symlink": path.is_symlink()}
    return out
