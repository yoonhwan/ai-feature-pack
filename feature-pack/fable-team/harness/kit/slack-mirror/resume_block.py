"""resume_block — 슬랙 «이어가기 블록» 생성 한 곳 (설계 §2). 모든 발행 경로가 이 모듈을 import 한다.

6칸(Issue · 카드 · 담당 · 정본 · 다음 · 재개)은 «항상» 찍힌다. 값이 없으면 호출자가 문자 그대로 `없음` 을 넘긴다 —
None·빈 문자열은 raise(#0 RULE: 칸을 조용히 빼지 않는다).
"""
import json
import subprocess
from pathlib import Path

from mirror_lib import MirrorError, esc

NONE = "없음"
RC_NO_SESSION = 3  # ft-resume-cmd.sh: 확인된 세션 매핑 없음 — stdout 이 칸 값(`없음(…)`)


class BlockError(MirrorError):
    pass


def _cell(name: str, value: object) -> str:
    if not isinstance(value, str) or not value.strip():
        raise BlockError(f"이어가기 블록 「{name}」 칸이 비어 있다 — 값이 없으면 문자 「{NONE}」 을 넘긴다")
    return esc(value.strip())


def block(issue: str, card: str, seat: str, canon: str, next_: str, resume: str) -> str:
    """고정 2줄. 6칸 전부 필수."""
    i, c, s, k, n, r = (_cell(a, b) for a, b in
                        (("Issue", issue), ("카드", card), ("담당", seat), ("정본", canon), ("다음", next_), ("재개", resume)))
    return f"↳ 이어가기 · Issue {i} · 카드 {c} · 담당 {s} · 정본 {k}\n↳ 다음: {n} · 재개: {r}"


def _git(top: Path, *args: str) -> str:
    try:
        out = subprocess.run(["git", "-C", str(top), *args], capture_output=True, text=True, timeout=20, check=True)
    except (subprocess.SubprocessError, OSError) as e:
        raise BlockError(f"정본 git 조회 실패: git {' '.join(args)} ({type(e).__name__})") from e
    return out.stdout.strip()


def canon_ref(path: str | Path) -> str:
    """`<리포 상대 경로>@<마지막 커밋 sha 8>` — 추적 밖·미커밋 변경이면 raise(슬랙에 미커밋 정본을 걸지 않는다)."""
    p = Path(path).resolve()
    if not p.is_file():
        raise BlockError(f"정본 파일 없음: {p}")
    top = Path(_git(p.parent, "rev-parse", "--show-toplevel"))
    rel = p.relative_to(top.resolve()).as_posix()
    if not _git(top, "ls-files", "--", rel):
        raise BlockError(f"정본이 git 추적 밖이다: {rel}")
    if _git(top, "status", "--porcelain", "--", rel):
        raise BlockError(f"정본에 미커밋 변경이 있다: {rel}")
    sha = _git(top, "log", "-1", "--abbrev=8", "--format=%h", "--", rel)
    if not sha:
        raise BlockError(f"정본 커밋 이력 없음: {rel}")
    return f"{rel}@{sha}"


def resume_for(seat: str, script: str | Path) -> str:
    """재개 칸 값 — ft-resume-cmd.sh <좌석>. rc 0 = 명령 · rc 3 = `없음(…)` 문구 · 그 밖 raise. 좌석이 `없음` 이면 `없음`."""
    if seat.strip() == NONE:
        return NONE
    try:
        r = subprocess.run(["bash", str(script), seat], capture_output=True, text=True, timeout=30)
    except (subprocess.SubprocessError, OSError) as e:
        raise BlockError(f"재개 명령 실행 실패: {script} ({type(e).__name__})") from e
    if r.returncode not in (0, RC_NO_SESSION) or not r.stdout.strip():
        raise BlockError(f"재개 명령 오류 rc={r.returncode}: {r.stderr.strip()[:200]}")
    return r.stdout.strip()


def mirror_block(row: dict[str, object], label: str, script: str | Path) -> str:
    """mbox 미러 꼬리 — 권위 칸은 행의 «정형 필드»(from·seq)만. Issue·카드 = `없음` 고정(본문 인용 0 · DA §4)."""
    seat = str(row.get("from") or "").strip() or NONE
    return block(NONE, NONE, seat, f"bodies/{row.get('seq')}.txt@mbox", "오빠 판정" if label == "HIL" else NONE, resume_for(seat, script))


def master_seat(seats_file: str | Path) -> str:
    """좌석표의 `_master` — 없으면 raise."""
    try:
        data = json.loads(Path(seats_file).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise BlockError(f"좌석표 읽기 실패: {seats_file} ({type(e).__name__})") from e
    seat = data.get("_master") if isinstance(data, dict) else None
    if not isinstance(seat, str) or not seat:
        raise BlockError(f"좌석표에 _master 없음: {seats_file}")
    return seat
