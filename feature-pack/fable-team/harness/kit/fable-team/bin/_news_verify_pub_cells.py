"""ft-news-verify 9칸 중 발행 쪽 ⓖ~ⓘ (r853 · planner 계획 §2) — 원장 쪽 칸(ⓐ~ⓕ) = _news_verify_cells.py.

| 칸 | 발행본 쪽 | 원천 쪽(다시 부르는 함수) |
|---|---|---|
| ⓖ fetch 실패 | — | 뉴스 로그 «원장 ref fetch 실패» 0줄 + ft_news_ledger.fail_announced (r847) |
| ⓗ 팀 지도 ↔ 실측 | 발행본에 실린 팀 이름 | ft_news_html.live_teams (r850 자리 · 지금 함수) |
| ⓘ 뿌리 글 읽힘 | 발행본 글 자체 | root_readback_guard.check (r1004 가드 재호출 — 판정 새로 구현 0) |

값 못 읽음 = «모름» = 실패로 셈. 선행 카드 모듈·함수가 없음 = «검증 불가»(R1 · V3 · N/9 에 안 셈 · ERROR · 쪽지 0).
"""
import sys
from pathlib import Path

from _news_verify_lib import FAIL, PASS, UNAVAILABLE, UNKNOWN, Ctx, Missing, guarded, need


def _log(ctx: Ctx) -> Path:
    return ctx.log or Path("/tmp/byz-ft-news-planner.log")


@guarded
def cell_g(ctx: Ctx) -> tuple[str, str]:
    """ⓖ 뉴스 로그 «원장 ref fetch 실패» 0줄 + r847 구간 표식 0 (로그에 시각이 없어 창은 표식·꼬리로 근사)."""
    fail_announced = need("ft_news_ledger", "fail_announced")
    log = _log(ctx)
    if not log.is_file():
        return UNKNOWN, f"뉴스 로그 없음 — {log}"
    try:
        lines = log.read_text(encoding="utf-8", errors="replace").splitlines()[-4000:]
        marked = fail_announced()
    except Exception as e:  # noqa: BLE001
        return UNKNOWN, f"로그·표식 못 읽음 — {type(e).__name__}: {e}"
    n = sum(1 for ln in lines if "원장 ref fetch 실패" in ln)
    return (FAIL if n or marked else PASS), f"로그 꼬리 {n}줄 · 구간 표식 {marked}"


@guarded
def cell_h(ctx: Ctx) -> tuple[str, str]:
    """ⓗ 팀 지도 ↔ 실측 불일치 0 — 지도에 안 실린 팀(좌석 살아 있음) 0."""
    try:
        live = need("ft_news_html", "live_teams")(ctx.root)
    except Missing:
        raise
    except Exception as e:  # noqa: BLE001 — 명부 0개·tmux 실패 = 모름
        return UNKNOWN, f"팀 실측 못 함 — {type(e).__name__}: {e}"
    text = "\n".join(ctx.texts)
    missing = [t["team"] for t in live if t["team"] not in text]
    return (FAIL if missing else PASS), (f"지도에 없는 팀 {len(missing)} — {', '.join(missing[:5])}" if missing else f"명부 {len(live)}팀 전부 지도에 있음")


def _guard():
    """r1004 가드 모듈 — 설치 자리(같은 bin 옆 · kit/slack-mirror · bin 옆 slack-mirror · bin 옆 kit/slack-mirror) 넷을 차례로 본다. ImportError = 아직 없음."""
    try:
        import root_readback_guard  # noqa: F401
        return root_readback_guard
    except ImportError as first:
        here = Path(__file__).resolve().parent
        for side in (here.parents[1] / "slack-mirror", here.parent / "slack-mirror", here.parent / "kit" / "slack-mirror", here / "slack-mirror"):
            if not side.is_dir() or str(side) in sys.path:
                continue
            sys.path.append(str(side))
            try:
                import root_readback_guard  # noqa: F401
                return root_readback_guard
            except ImportError:
                sys.path.pop()
        raise first from None


@guarded
def cell_i(ctx: Ctx) -> tuple[str, str]:
    """ⓘ 뿌리 글 읽힘 = r1004 `root_readback_guard.check(text)` 재호출 하나 — None = 참 · 사유 글자 = 거짓.
    모듈은 있는데 check 가 없는 경우도 «검증 불가»(V3 · 함수 확인은 getattr 한 곳 · r1005 반례 1)."""
    try:
        module = _guard()
    except ImportError as e:  # R1 — r1004 미착지 = «검증 불가»
        return UNAVAILABLE, f"되읽기 가드 모듈 없음(root_readback_guard): {type(e).__name__}: {e}"
    check = getattr(module, "check", None)
    if check is None:  # V3 — 모듈만 있고 함수 없음도 같은 값(«모름»·쪽지 아님)
        raise Missing("root_readback_guard.check 함수 없음")
    text = "\n".join(ctx.texts).strip()
    if not text:
        return UNKNOWN, "발행본 글 비어 있음"
    why = check(text)  # r1004 check 반환 = 사유 1줄 아니면 None(짧은 줄·표 금지 = None)
    return (FAIL if why else PASS), (f"가드 위반 — {why}" if why else "가드 위반 0")


CELLS = (("ⓖ fetch 실패", cell_g), ("ⓗ 팀 지도", cell_h), ("ⓘ 뿌리 글", cell_i))
