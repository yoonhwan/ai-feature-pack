"""ft_team_main_assign — r1322 팀 메인 파일 제0목표 + ④ 배정표 절 + ASSIGN.md 틀(render·attach 공용).
배정표 = 팀장 손 파일 `<데이터 루트>/.fable-team/state/team-main/<팀>/ASSIGN.md` — render 는 읽기만(쓰기 0 · 없을 때만 틀 1개).
읽기 실패 = «판정 불가» 1줄(조용한 빈 절 0) · 수정 20분 초과 = «낡음 N분» 1줄. 도구 실행 0 · 네트워크 0.
"""
from __future__ import annotations

import os
import time
from pathlib import Path

import ft_team_lib

GOAL0 = "제0목표: 진행 중 카드를 완성하고 닫는다"   # R13 — 팀 메인 파일 1행 고정 글자(휴면 팀도 같다)
TEAM_MAIN = ".fable-team/state/team-main"
HEADER = "| 카드 | 좌석 | 선행 | 다음 수 | 줄 주인 |"
STALE_SEC = 20 * 60   # G4 — 두 루프(20분) 넘으면 낡음


def assign_template() -> list[str]:
    """틀 = 1행 제0목표 · 2행 표 머리 (없을 때만 쓴다 · 있으면 절대 안 덮는다)."""
    return [GOAL0, HEADER]


def data_dir(root: Path) -> Path:   # FT_ROOT 우선 · 아니면 공용 루트의 LIVE_ROOT(ft_team_lib.data_root 규칙 그대로)
    if os.environ.get("FT_ROOT"):
        return Path(os.environ["FT_ROOT"])
    out = ft_team_lib._git_out(root, "rev-parse", "--path-format=absolute", "--git-common-dir")
    common = out.stdout.strip()
    if out.returncode or not common:
        raise OSError("git 공용 루트 못 읽음")
    return Path(ft_team_lib.data_root(Path(common).parent if common.endswith("/.git") else Path(common)))


def team_folder(root: Path, team: str) -> Path:
    return data_dir(root) / TEAM_MAIN / team


def ensure(folder: Path, dry: bool = False) -> bool:   # 없을 때만 틀 · 있으면 바이트 무변경(G3·A3) · 반환 = «만들었다(만들 것이다)»
    path = folder / "ASSIGN.md"
    if path.exists():
        return False
    if not dry:   # A8 — dry 면 쓰기 0
        folder.mkdir(parents=True, exist_ok=True)
        with path.open("w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(assign_template()) + "\n")
            fh.flush(), os.fsync(fh.fileno())
    return True


def ensure_team(root: Path, team: str, dry: bool = False) -> bool:   # ft-team-attach 새 팀 경로(G5) — 데이터 루트를 못 풀면 후퇴 쓰기 0(A9)
    try:
        folder = team_folder(root, team)
    except (OSError, ft_team_lib.TeamPathError) as e:
        raise OSError(f"데이터 루트 판정 불가 · {e}") from None
    return ensure(folder, dry)


def section(folder: Path, now: float) -> list[str]:   # → «## ④ 배정표» 절 줄들(본문 그대로)
    path = folder / "ASSIGN.md"
    try:
        if path.is_dir():
            raise OSError("ASSIGN.md 가 폴더")
        ensure(folder)
        body = path.read_text(encoding="utf-8").splitlines()
        mtime = path.stat().st_mtime
    except OSError as e:
        why = " ".join(str(e).split())[:60]
        return ["## ④ 배정표 (팀장 손 · 파일 판정 불가)", f"판정 불가(ASSIGN.md 읽기 실패 · {why})"]
    out = [f"## ④ 배정표 (팀장 손 · 파일 {time.strftime('%H:%M', time.localtime(mtime))})"]
    if now - mtime > STALE_SEC:
        out.append(f"낡음 {int((now - mtime) // 60)}분 — 팀장이 이번 루프에 다시 쓴다(R12)")
    return out + body
