"""이어가기 블록·스레드 장부 시험 공용 도구 — 가짜 재개 스크립트 · 빈 장부 · 좌석표 · 카드 · 커밋된 정본. 네트워크 0 · 실제 슬랙 0."""
import json
import subprocess
from pathlib import Path

import pytest

from _proposal_fakes import KEY  # noqa: F401 — sys.path 에 키트 경로를 넣는다

# r1089 — 사람 채널 슬랙 글 머리에 붙는 planner 카운팅 머리줄의 정본 모양
STATUS_HEAD = "스크립트 3 · 인터뷰 3 · 막힌 팀 대기 2"


@pytest.fixture(autouse=True)
def status_head_file(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """r1089 — 머리줄 입력을 임시 TEAM-STATUS 로 고정한다(실 파일 읽기 0 · 방금 갱신 = «낡음» 없음).

    이 fixture 이름을 import 한 시험 파일에만 autouse 로 걸린다.
    """
    f = tmp_path / "TEAM-STATUS.md"
    f.write_text(f"{STATUS_HEAD}\n머리줄 시험용\n", encoding="utf-8")
    monkeypatch.setenv("FT_TEAM_STATUS_FILE", str(f))
    return f


def body_after_status_head(text: str) -> str:
    """r1089 머리줄을 띤 본문에서 머리줄을 떼어 낸다 — 답 본문 계약(앞뒤 글자 0)은 머리줄 «뒤»에서 잰다."""
    return text.split("\n", 1)[1] if text.startswith(f"{STATUS_HEAD}\n") else text

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
