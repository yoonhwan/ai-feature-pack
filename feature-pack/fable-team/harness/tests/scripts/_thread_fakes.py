"""이어가기 블록·스레드 장부 시험 공용 도구 — 가짜 재개 스크립트 · 빈 장부 · 좌석표 · 카드 · 커밋된 정본. 네트워크 0 · 실제 슬랙 0."""
import json
import subprocess
from pathlib import Path

from _proposal_fakes import KEY  # noqa: F401 — sys.path 에 키트 경로를 넣는다

CARD = "# 인덱스: 시험 카드\n- 상태: 진행\n\n## 구현 범위\n1. x\n\n## 상태\n- base_sha: abc\n"
CMD = "RESUME-CMD({seat})"


def resume_script(tmp: Path, rc: int = 0, out: str = CMD) -> Path:
    """ft-resume-cmd.sh 대역 — `$1` 을 넣어 1줄을 내고 rc 로 끝난다(3 = 매핑 없음 문구)."""
    p = tmp / "resume.sh"
    p.write_text(f'#!/bin/sh\nprintf \'%s\\n\' "{out.replace("{seat}", "$1")}"\nexit {rc}\n', encoding="utf-8")
    return p


def ledger(tmp: Path, data: dict | None = None) -> Path:
    p = tmp / "threads.json"
    p.write_text(json.dumps(data or {}), encoding="utf-8")
    return p


def seats(tmp: Path, master: str = "master#1") -> Path:
    p = tmp / "seats.json"
    p.write_text(json.dumps({"_master": master}), encoding="utf-8")
    return p


def card(tmp: Path, team: str = "feature", name: str = "F-x-proposal") -> Path:
    p = tmp / "design" / team / "indices" / "진행" / f"{name}.md"
    p.parent.mkdir(parents=True, exist_ok=True)
    if not p.exists():
        p.write_text(CARD, encoding="utf-8")
    return p


def commit_all(root: Path) -> None:
    """root 를 git 리포로 만들고 지금 있는 파일을 전부 커밋 — 정본 `경로@sha` 의 근거."""
    for args in (["init", "-q"], ["config", "user.email", "t@t"], ["config", "user.name", "t"], ["add", "-A"], ["commit", "-qm", "x"]):
        subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)
