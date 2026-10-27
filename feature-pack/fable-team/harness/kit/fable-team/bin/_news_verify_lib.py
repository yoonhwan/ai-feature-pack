"""ft-news-verify 공용 — 4값 판정 상수 · 선행 함수 재호출(need/guarded · V3) · 발행본 글 다듬기 · 상태 파일 읽기.

칸 파일 둘(_news_verify_cells.py 원장 쪽 ⓐ~ⓕ · _news_verify_pub_cells.py 발행 쪽 ⓖ~ⓘ)이 같이 쓴다 — 파일 200줄 상한(CLAUDE.md Code Metrics).
"""
import html as htmlmod
import importlib
import json
import re
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

PASS, FAIL, UNKNOWN, UNAVAILABLE = "참", "거짓", "모름", "검증 불가"  # 4값 — 검증 불가는 N/9 에 안 셈(R1)


class Missing(Exception):
    """선행 카드의 모듈·함수가 아직 없다 — R1 «검증 불가»(N/9 에 안 셈 · ERROR · 쪽지 0)."""


def need(module: str, name: str):
    """선행 함수 하나 — 모듈 없음과 «모듈은 있는데 함수 없음» 을 같은 값으로 본다(V3 · 확인은 여기 한 곳)."""
    try:
        mod = importlib.import_module(module)
    except ImportError as e:
        raise Missing(f"{module} 모듈 없음: {e}") from e
    fn = getattr(mod, name, None)
    if fn is None:
        raise Missing(f"{module}.{name} 함수 없음")
    return fn


def guarded(fn):
    """칸 함수 — 선행 함수 없음(Missing) = «검증 불가» · 그 밖 예외는 부르는 쪽이 «모름» 으로 받는다."""
    def wrapped(ctx):
        try:
            return fn(ctx)
        except Missing as e:
            return UNAVAILABLE, str(e)
    wrapped.__name__ = fn.__name__
    return wrapped


@dataclass
class Ctx:
    """검증 1회의 입력 — 발행본 글(texts)은 태그를 걷어낸 줄 목록 그대로."""
    kind: str
    texts: list[str]
    root: Path
    repo: Path
    rel: str
    ref: str = "origin/main"
    state: Path | None = None
    verify_state: Path | None = None
    log: Path | None = None
    now: datetime = field(default_factory=datetime.now)


def plain(text: str) -> str:
    """발행본(HTML·md) → 사람이 읽는 줄 — 블록 태그는 줄바꿈, 나머지 태그는 공백(«오빠 할 일» 절 머리가 줄로 남는다)."""
    t = re.sub(r"</(?:h[1-6]|section|li|p|div|tr|td|th)>", "\n", text)
    t = htmlmod.unescape(re.sub(r"<[^>]+>", " ", t))
    return "\n".join(re.sub(r"[ \t]+", " ", ln).strip() for ln in t.splitlines())


def read_body(path: Path) -> str:
    return plain(path.read_text(encoding="utf-8", errors="replace"))


def load(f: Path | None, default):
    """상태 파일 — 없음·깨짐·꼴 다름(리스트/문자열) = 기본값(검증기가 상태 꼴에 죽지 않게 · V4)."""
    try:
        data = json.loads(f.read_text(encoding="utf-8")) if f and f.is_file() else default
    except (OSError, ValueError):
        return default
    return data if type(data) is type(default) else default


def save(f: Path, data) -> None:
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


def sources(ctx: Ctx) -> dict:
    """r851 원천 한 번(gather) — 실패한 원천은 FillError 값 그대로(그 칸만 모름)."""
    return need("ft_ledger_fill", "gather")(ctx.root, ctx.repo, ctx.ref, ctx.now)


def bad_vals(*vals) -> str:
    return "; ".join(f"{type(v).__name__}: {v}" for v in vals if isinstance(v, Exception))[:200]


def baseline(ctx: Ctx) -> str:
    """기준선 = 지도 상태 last.sha(발행 시각 머리) — 없으면 ''."""
    f = (ctx.state or Path()) / "last.sha"
    return f.read_text(encoding="utf-8").strip() if f.is_file() else ""


