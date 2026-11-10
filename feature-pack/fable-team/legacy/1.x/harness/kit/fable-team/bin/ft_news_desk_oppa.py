#!/usr/bin/env python3
"""ft_news_desk_oppa — 뉴스 전문 ③오빠 손 블록 (r1055 · r1229 에서 ft_news_desk.py 파일 상한 200줄 분리).

칸 3개(r1229 K6) = 실행할 스크립트(h 번호·개수) · 답 대기 질문 · 오늘 착지(main PR 번호·카드). 칸 이름은 늘 남는다.
칸마다 외부 도구 7초+재시도 1(하드 룰 12) · 둘 다 실패하면 «확인 불가 · (HH:MM 기준 직전 값)» ·
직전 값이 30분 넘으면 숫자 없이 «확인 불가(직전 값 N분 전)» · 그도 없으면 «확인 불가(사유)» (R2′ · arch#190 #211002).
직전 값 파일 = FT_DESK_STATE 아래(실험 격리 · R7) · 없으면 <루트>/.fable-team/state/ft-news-desk-last.json.
env: FT_DESK_HIL · FT_DESK_DECISION · FT_DESK_TOOL_TIMEOUT · FT_DESK_STATE · FT_DESK_GIT · FT_DESK_LAND_REPO · FT_DESK_LAND_REF
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ft_news_desk_blocks import DOING_CHARS, LOG, _run, _timeout, _why  # noqa: E402

STALE_MIN = 30
LAND_SHOW = 10
LAND_PR = re.compile(r"^PR #(\d+) \(head ", re.M)
CARD = re.compile(r"\b(r\d{3,5}[a-z0-9]*)\b")


def _tool(cmd: list[str], env_name: str) -> subprocess.CompletedProcess[str]:
    """외부 도구 1회 + 재시도 1(하드 룰 12 · 상한은 _timeout(env_name)). rc≠0·시간 초과 둘 다 재시도 대상."""
    err: Exception | None = None
    for _ in range(2):
        try:
            done = _run(cmd, _timeout(env_name))
        except RuntimeError as e:
            err = e
            continue
        if done.returncode == 0:
            return done
        err = RuntimeError(f"{Path(cmd[1]).name} rc={done.returncode} {(done.stderr or done.stdout).strip()[:DOING_CHARS]}")
    raise err  # type: ignore[misc]


def _hil(root: Path, now: datetime) -> str:
    """ft-hil 1번(--pending --each --held)으로 번호·개수·가장 오래된 분(R6 — 두 번째 --pending 호출 0).
    `h<N> <분>` 줄 = 실행할 스크립트 · `held h<N> <분> <사유>` 줄 = 보류(r1236 — 개수에서 빠지고 « · 보류 M(h번호)» 로 따로)."""
    tool = os.environ.get("FT_DESK_HIL") or str(HERE / "ft-hil.sh")
    each = _tool(["bash", tool, "--pending", "--each", "--held"], "FT_DESK_TOOL_TIMEOUT")
    split = [x.split() for x in each.stdout.splitlines() if x.strip()]
    rows = [r for r in split if r[0] != "held"]
    held = "·".join(r[1] for r in split if r[0] == "held" and len(r) > 1)
    oldest = max((int(r[-1]) for r in rows if r[-1].isdigit()), default=0)
    names = "·".join(r[0] for r in rows)
    return (f"{len(rows)}개" + (f"({names})" if names else "") + (f" · 가장 오래된 {oldest}분" if oldest else "")
            + (f" · 보류 {held.count('·') + 1}({held})" if held else ""))


def _questions(root: Path, now: datetime) -> str:
    done = _tool(["bash", os.environ.get("FT_DESK_DECISION") or str(HERE / "ft-decision-count.sh")], "FT_DESK_TOOL_TIMEOUT")
    body = [x for x in done.stdout.strip().splitlines() if x.strip()]
    if not body:
        raise RuntimeError(f"ft-decision-count 빈 응답 rc={done.returncode}")
    return body[-1]


def _land_repo(root: Path) -> str:
    return os.environ.get("FT_DESK_LAND_REPO") or (root / ".fable-team" / "LIVE_ROOT").read_text(encoding="utf-8").split("\n")[0].strip()


def _landed(root: Path, now: datetime) -> str:
    """오늘 main 착지 = first-parent 커밋 본문 «PR #N (head …)» 줄(ft-merge-land 꼴) · git log 1회 7초+재시도 1 · PR 중복 1줄."""
    ref = os.environ.get("FT_DESK_LAND_REF") or "origin/main"
    cmd = [os.environ.get("FT_DESK_GIT") or "git", "-C", _land_repo(root), "log", ref, "--first-parent",
           f"--since={now:%Y-%m-%d} 00:00", "--format=%x1e%s%x1f%b"]
    done = _tool(cmd, "FT_DESK_TOOL_TIMEOUT")
    seen: dict[str, str] = {}
    for rec in done.stdout.split("\x1e"):
        subject, _, body = rec.partition("\x1f")
        if (m := LAND_PR.search(body)) and m[1] not in seen:
            card = CARD.search(subject)
            seen[m[1]] = card[1] if card else re.sub(r"^\[\w+\]\s*", "", subject.strip())[:DOING_CHARS]
    if not seen:
        return "없음(오늘 main 착지 0건)"
    rows = [f"  - PR #{pr} · {card}" for pr, card in list(seen.items())[:LAND_SHOW]]
    more = [f"  - 외 {len(seen) - LAND_SHOW}건"] if len(seen) > LAND_SHOW else []
    return "\n".join([f"{len(seen)}건", *rows, *more])


def _sticky_path(root: Path) -> Path:
    if state := os.environ.get("FT_DESK_STATE"):
        return Path(state) / "ft-news-desk-last.json"
    return root / ".fable-team" / "state" / "ft-news-desk-last.json"


def _sticky(root: Path) -> dict:
    try:
        data = json.loads(_sticky_path(root).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def _sticky_put(root: Path, key: str, value: str, now: datetime) -> None:
    """성공한 칸 값을 tmp+mv 로 남긴다 — 다음 틱이 실패하면 «확인 불가 · (HH:MM 기준 …)» 으로 보인다(R4)."""
    data = _sticky(root)
    data[key] = {"value": value, "at": f"{now:%H:%M}", "ts": f"{now:%Y-%m-%d %H:%M}"}
    path = _sticky_path(root)
    tmp = path.parent / (path.name + ".tmp")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_text(json.dumps(data, ensure_ascii=False) + "\n", encoding="utf-8")
        tmp.replace(path)
    except OSError as e:
        LOG.error("직전 값 저장 실패: %s", e)


def _age_min(prev: dict, now: datetime) -> int:
    """직전 값 나이(분) — ts 가 없던 옛 파일은 at(HH:MM)을 오늘로 읽고 미래면 하루 전."""
    try:
        at = datetime.strptime(prev["ts"], "%Y-%m-%d %H:%M")
    except (KeyError, ValueError):
        at = datetime.combine(now.date(), datetime.strptime(prev["at"], "%H:%M").time())
        at -= timedelta(days=1) if at > now else timedelta()
    return int((now - at).total_seconds() // 60)


def _unknown(name: str, prev: dict, now: datetime, e: Exception) -> str:
    """실패 칸 — 숫자보다 «확인 불가 · » 가 먼저 · 30분 넘은 직전 값은 숫자 0 (R2′)."""
    if not prev.get("at"):
        return f"- {name}: 확인 불가({_why(e)})"
    age = _age_min(prev, now)
    if age > STALE_MIN:
        return f"- {name}: 확인 불가(직전 값 {age}분 전) · 사유 {_why(e)}"
    return f"- {name}: 확인 불가 · ({prev['at']} 기준 {str(prev.get('value', '')).splitlines()[0]}) · 사유 {_why(e)}"


def oppa_block(root: Path, now: datetime | None = None) -> list[str]:
    """③오빠 손 — 칸 3개 늘 있음(K6) · 칸마다 7초+재시도 1 · 실패 = _unknown(R2′)."""
    out = ["## 오빠 손"]
    now = now or datetime.now()
    for name, fn in (("실행할 스크립트", _hil), ("답 대기 질문", _questions), ("오늘 착지", _landed)):
        try:
            value = fn(root, now)
        except (RuntimeError, OSError) as e:
            LOG.error("오빠 손 %s 칸 확인 불가: %s", name, e)
            out.append(_unknown(name, _sticky(root).get(name) or {}, now, e))
            continue
        _sticky_put(root, name, value, now)
        out.append(f"- {name}: {value}")
    return out
