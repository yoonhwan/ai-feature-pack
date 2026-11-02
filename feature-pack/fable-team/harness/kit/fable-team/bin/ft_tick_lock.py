"""r1309 — 루트 틱 잠금 경로 3개(FT_TICK_PIDFILE·FT_TICK_STATE_DIR·FT_TICK_STAMP_PREFIX) 판정.

왜 필요: ft-tick.sh 의 기본값(/tmp/ft-tick.pid · /tmp/ft-tick-state · /tmp/ft-tick-)은 «BYZ 메인 틱 하나» 전제다.
루트 틱이 같은 값을 쓰면 둘 중 하나가 standby 무한 대기(§3-5 · DA① 반례 2). 값이 없는 옛 plist 는 이 기본값으로 «돈다» 고 본다.
env: FT_ROOTS_TSV(기계 루트 명부). 파일은 일반 파일(하드 룰 19) · 외부 명령 0.
"""
from __future__ import annotations

import os
import plistlib
from pathlib import Path
from typing import Any

from ft_team_attach_lib import AttachError

LOCK_ENVS = ("FT_TICK_PIDFILE", "FT_TICK_STATE_DIR", "FT_TICK_STAMP_PREFIX")   # §3-5 잠금 경로 3개 — 루트 틱 plist 에 반드시
TICK_DEFAULTS = {"FT_TICK_PIDFILE": "/tmp/ft-tick.pid", "FT_TICK_STATE_DIR": "/tmp/ft-tick-state",
                 "FT_TICK_STAMP_PREFIX": "/tmp/ft-tick-"}   # ft-tick.sh 기본값 — 값이 없는 plist 는 이 값으로 «돈다»


def plist_dir(root: Path | None = None) -> Path:
    """launchd plist 폴더 — FT_TICK_PLIST_DIR 우선 · 샌드박스(FT_TEAM_ATTACH_SANDBOX=1) = <루트>/.fable-team/state/launchd · 기본 ~/Library/LaunchAgents.
    ft_team_attach_lib.paths() 와 «같은 규칙» 이어야 한다(한쪽만 다르면 같은 plist 를 두 곳에서 다르게 판정한다)."""
    if env := os.environ.get("FT_TICK_PLIST_DIR"):
        return Path(env)
    if os.environ.get("FT_TEAM_ATTACH_SANDBOX") == "1" and root is not None:
        return Path(root) / ".fable-team/state/launchd"
    return Path.home() / "Library/LaunchAgents"


def labels(name: str) -> tuple[str, str]:
    return f"com.byz.ft-tick-{name}", f"com.byz.ft-stall-scan-{name}"


def _env_of(path: Path) -> dict[str, str]:
    try:
        doc = plistlib.loads(path.read_bytes())
    except (OSError, ValueError):
        return {}
    env = doc.get("EnvironmentVariables") if isinstance(doc, dict) else None
    return {str(k): str(v) for k, v in env.items()} if isinstance(env, dict) else {}


def lock_conflicts(candidate: dict[str, str], folder: Path, skip: Path | None = None) -> list[str]:
    """X9 — 후보 plist 의 잠금 경로 3개 중 하나라도 «설치된 다른 ft-tick plist» 와 같으면 그 목록(중복 = REJECT 근거)."""
    mine = {k: candidate.get(k) or TICK_DEFAULTS[k] for k in LOCK_ENVS}
    out: list[str] = []
    for other in sorted(folder.glob("com.byz.ft-tick*.plist")):
        if skip is not None and other.resolve() == Path(skip).resolve():
            continue
        theirs = {k: _env_of(other).get(k) or TICK_DEFAULTS[k] for k in LOCK_ENVS}
        out += [f"중복 {k}={mine[k]} ↔ {other.name}" for k in LOCK_ENVS if mine[k] == theirs[k]]
    return out


def root_lock(name: str, row: dict[str, Any]) -> dict[str, str]:
    """roots.tsv «틱잠금접두» → 잠금 경로 3개 · «기본» = BYZ 기본값(그 루트엔 루트 틱을 안 세운다 — 중복으로 REJECT 된다)."""
    prefix = str(row["tick_lock"])
    if prefix == "기본":
        return dict(TICK_DEFAULTS)
    if not prefix.startswith("/"):
        raise AttachError(f"ERROR 루트 명부 판정 불가: {name} 틱잠금접두가 절대경로가 아니다: {prefix}")
    return {"FT_TICK_PIDFILE": prefix + ".pid", "FT_TICK_STATE_DIR": prefix + "-state", "FT_TICK_STAMP_PREFIX": prefix + "-"}
