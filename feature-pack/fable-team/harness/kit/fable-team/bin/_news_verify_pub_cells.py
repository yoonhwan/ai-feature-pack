"""ft-news-verify 9칸 중 발행 쪽 ⓖ~ⓘ (r853 · planner 계획 §2) — 원장 쪽 칸(ⓐ~ⓕ) = _news_verify_cells.py.

| 칸 | 발행본 쪽 | 원천 쪽(다시 부르는 함수) |
|---|---|---|
| ⓖ 원천 가져오기 | — | ft_news_ledger._git_capped 로 «원격 ref vs 로컬 ref» 직접 비교 1회(로그·표식 추측 0 · r1005 반송 r4) |
| ⓗ 팀 지도 ↔ 실측 | 발행본에 실린 팀 이름 | ft_news_html.live_teams (r850 자리 · 지금 함수) |
| ⓘ 뿌리 글 읽힘 | 발행본 글 자체 | root_readback_guard.check (r1004 가드 재호출 — 판정 새로 구현 0) |

값 못 읽음 = «모름» = 실패로 셈. 선행 카드 모듈·함수가 없음 = «검증 불가»(R1 · V3 · N/9 에 안 셈 · ERROR · 쪽지 0).
"""
import os
import sys
import time
from pathlib import Path

from _news_verify_lib import FAIL, PASS, UNAVAILABLE, UNKNOWN, Ctx, Missing, guarded, need

CAP_ENV = "FT_NEWS_FETCH_BUDGET"  # 선행 모듈(ft_news_ledger)의 묻기 마감 — 칸 상한 7초 안(첫 묻기 5.5초 = 7 − 유예 1.5)으로 끊으려고 이 칸에서만 7초로 둔다


def _br() -> str:
    """원장 사본 브랜치 이름 — 선행 함수 재호출(r851 branch). 이름 규칙 위반·못 읽음 = «검증 불가»(Missing)."""
    try:
        return need("ft_ledger_fill_src", "branch")()
    except Missing:
        raise
    except Exception as e:  # noqa: BLE001 — FillError(이름 규칙) 등 = 그 값을 쓸 수 없다
        raise Missing(f"원장 브랜치 이름 못 읽음 — {type(e).__name__}: {e}") from e


def _capped(ctx: Ctx, *a: str) -> tuple[int | None, str, str]:
    """ft_news_ledger._git_capped 재호출 — 이 칸의 총 마감 7초(첫 묻기 5.5초 · 칸 상한 7초 안 · rc None = 시간 초과)."""
    old = os.environ.get(CAP_ENV)
    os.environ[CAP_ENV] = "7"
    try:
        return need("ft_news_ledger", "_git_capped")(ctx.repo, time.monotonic(), *a)
    finally:
        if old is None:
            os.environ.pop(CAP_ENV, None)
        else:
            os.environ[CAP_ENV] = old


@guarded
def cell_g(ctx: Ctx) -> tuple[str, str]:
    """ⓖ 원천 가져오기 = «지금» 원격 ref 와 로컬 ref 를 1회 직접 비교(r1005 반송 r4 · 결정 3 · 로그·표식 추측 0).
    같음 = 참 · 다름 = 거짓 · ls-remote 실패·시간 초과·로컬 ref 조회 실패 = 검증 불가(C2 · 9/9 아님 · 쪽지 0)."""
    br = _br()
    rc, out, err = _capped(ctx, "ls-remote", "origin", "refs/heads/main", f"refs/heads/{br}")
    remote = dict(reversed(r.split("\t")) for r in out.splitlines() if r.count("\t") == 1) if rc == 0 else {}
    if rc != 0 or "refs/heads/main" not in remote:
        return UNAVAILABLE, f"ls-remote 실패 — rc={rc} {(err.strip() or out.strip() or '출력 없음')[:120]}"
    bad = []
    for name in ("main", br):
        lrc, lout, lerr = _capped(ctx, "rev-parse", "--verify", "-q", f"refs/remotes/origin/{name}")
        if lrc not in (0, 1):
            return UNAVAILABLE, f"로컬 ref 조회 실패 — {name} rc={lrc} {lerr.strip()[:80]}"
        want, got = remote.get(f"refs/heads/{name}", ""), lout.strip()
        if want != got:
            bad.append(f"{name} {want[:8] or '없음'}≠{got[:8] or '없음'}")
    return (FAIL if bad else PASS), ("원장 원천이 뒤처짐: " + " · ".join(bad) if bad else "원격 ref = 로컬 ref")


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
