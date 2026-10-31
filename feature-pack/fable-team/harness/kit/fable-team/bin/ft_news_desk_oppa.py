#!/usr/bin/env python3
"""ft_news_desk_oppa — 뉴스 전문 ③오빠 손 블록 (r1055 · r1229 에서 ft_news_desk.py 파일 상한 200줄 분리).

칸마다 외부 도구 7초+재시도 1(하드 룰 12) · 둘 다 실패하면 직전 값(HH:MM), 그도 없으면 확인 불가(R3~R5).
env: FT_DESK_HIL · FT_DESK_DECISION · FT_DESK_TOOL_TIMEOUT
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ft_news_desk_blocks import DOING_CHARS, LOG, _run, _timeout, _why  # noqa: E402


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


def _hil(root: Path) -> str:
    """ft-hil 1번(--pending --each)으로 개수와 가장 오래된 분을 함께 만든다(R6 — 두 번째 --pending 호출 0)."""
    tool = os.environ.get("FT_DESK_HIL") or str(HERE / "ft-hil.sh")
    each = _tool(["bash", tool, "--pending", "--each"], "FT_DESK_TOOL_TIMEOUT")
    rows = [x.strip() for x in each.stdout.splitlines() if x.strip()]
    oldest = max((int(m[1]) for x in rows if (m := re.search(r"(\d+)\s*$", x))), default=0)
    tail = f" · 가장 오래된 {oldest}분" if oldest else ""
    return f"{len(rows)}개 (미실행 h {len(rows)}개{tail})"


def _questions(root: Path) -> str:
    done = _tool(["bash", os.environ.get("FT_DESK_DECISION") or str(HERE / "ft-decision-count.sh")], "FT_DESK_TOOL_TIMEOUT")
    body = [x for x in done.stdout.strip().splitlines() if x.strip()]
    if not body:
        raise RuntimeError(f"ft-decision-count 빈 응답 rc={done.returncode}")
    return body[-1]


def _sticky_path(root: Path) -> Path:
    return root / ".fable-team" / "state" / "ft-news-desk-last.json"


def _sticky(root: Path) -> dict:
    try:
        data = json.loads(_sticky_path(root).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def _sticky_put(root: Path, key: str, value: str, now: datetime) -> None:
    """성공한 칸 값을 tmp+mv 로 남긴다 — 다음 틱이 실패하면 «직전 값(HH:MM)» 으로 보인다(R4)."""
    data = _sticky(root)
    data[key] = {"value": value, "at": f"{now:%H:%M}"}
    path = _sticky_path(root)
    tmp = path.parent / (path.name + ".tmp")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_text(json.dumps(data, ensure_ascii=False) + "\n", encoding="utf-8")
        tmp.replace(path)
    except OSError as e:
        LOG.error("직전 값 저장 실패: %s", e)


def oppa_block(root: Path, now: datetime | None = None) -> list[str]:
    """③오빠 손 — 칸마다 7초+재시도 1 · 둘 다 실패하면 직전 값(HH:MM), 그도 없으면 확인 불가(R3~R5)."""
    out = ["## 오빠 손"]
    now = now or datetime.now()
    for name, fn in (("실행할 스크립트", _hil), ("답 대기 질문", _questions)):
        try:
            value = fn(root)
        except (RuntimeError, OSError) as e:
            LOG.error("오빠 손 %s 칸 확인 불가: %s", name, e)
            prev = _sticky(root).get(name) or {}
            out.append(f"- {name}: 직전 값({prev['at']}) · 지금 확인 불가: {_why(e)}" if prev.get("at")
                       else f"- 확인 불가({_why(e)})")
            continue
        _sticky_put(root, name, value, now)
        out.append(f"- {name}: {value}")
    return out
