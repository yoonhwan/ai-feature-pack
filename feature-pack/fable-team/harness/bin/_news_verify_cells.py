"""ft-news-verify 9칸 중 원장 쪽 ⓐ~ⓕ (r853 · planner 계획 §2) — 칸마다 «선행 카드의 함수를 다시 부르기» 만 한다(같은 판정 두 번 구현 0).

| 칸 | 발행본 쪽(글에서 읽는다) | 원천 쪽(다시 부르는 함수) |
|---|---|---|
| ⓐ 오빠 할 일 건수 | «질문 —»·«실행 줄 —»·«자율 큐 —» 항목 수 | ft_ledger_fill.gather → open_questions · hil_pending · queue_open (r851) |
| ⓑ 한 일 | «<sha> [tag]» 착지 줄 + «완료·착지 쪽지 N통» 수 | landed_commits(상한 0) · mbox_done (r851) |
| ⓒ 팀 수 | «팀 N개» | ft_ledger_fill_src.teams (명부 · r851) |
| ⓓ 발행 sha | 발행본 머리 sha(없으면 지도 상태 last.sha) | read_ref + rev-parse(origin/main 머리 · r851) |
| ⓔ 같은 경고 | 하루 발행본에 경고 문구 2회 이상 0 | 경고 문구 3종(계획 §2 ⓔ) |
| ⓕ 완료 줄 | — | ft_ledger_fill_tables.lower_closed 재적용 «내려야 할 줄 0» (r851) |

값 못 읽음 = «모름» = 실패로 셈(계획 §2 · 조용한 9/9 0). 선행 카드 모듈·함수가 없음 = «검증 불가»(R1 · V3).
발행 쪽 칸(ⓖ~ⓘ) = _news_verify_pub_cells.py.
"""
import re
from pathlib import Path

from _news_verify_lib import FAIL, PASS, UNKNOWN, Ctx, Missing, bad_vals, baseline, guarded, load, need, save, sources

WARNINGS = ("원장 ref fetch 실패", "자동 교대 불가", "판정 불가")  # 계획 §2 ⓔ 같은 경고 3종
COMMIT_LINE = re.compile(r"^[0-9a-f]{7,10}\s+\[(?:feature|fix|docs|structure|test|chore|harness|design|land)\]", re.M)
NOTE_N = re.compile(r"완료·착지 쪽지 (\d+)통")
SHA = re.compile(r"\b[0-9a-f]{7,40}\b")
TEAM_N = re.compile(r"팀\s*(\d+)\s*개")


@guarded
def cell_a(ctx: Ctx) -> tuple[str, str]:
    """ⓐ «오빠 할 일» 건수 = 질문 장부 열린 수 + ft-hil 대기 수 + 자율 큐 처리됨 빈칸 수."""
    s = sources(ctx)
    qs, hils, queue = s["qs"], s["hil"], s["queue"]
    if any(isinstance(v, Exception) for v in (qs, hils, queue)):
        return UNKNOWN, f"장부 못 읽음 — {bad_vals(qs, hils, queue)}"
    src = len(qs) + len(hils) + len(queue)
    text = "\n".join(ctx.texts)
    pub = text.count("질문 —") + text.count("실행 줄 —") + text.count("자율 큐 —")
    if pub == 0 and "오빠 할 일" not in text:
        return UNKNOWN, "발행본에 «오빠 할 일» 항목 없음"
    return (PASS if pub == src else FAIL), f"발행본 {pub}건 ≠ 장부 {src}건(질문 {len(qs)} · 실행 줄 {len(hils)} · 자율 큐 {len(queue)})"


@guarded
def cell_b(ctx: Ctx) -> tuple[str, str]:
    """ⓑ «한 일» = 기준선 뒤 착지 커밋 전부(상한 0) + 팀 [완료] 쪽지 수."""
    landed_commits = need("ft_ledger_fill_src", "landed_commits")
    s = sources(ctx)
    if isinstance(s["cards"], Exception) or isinstance(s["notes"], Exception):
        return UNKNOWN, f"카드·쪽지 장부 못 읽음 — {bad_vals(s['cards'], s['notes'])}"
    try:
        commits = landed_commits(ctx.repo, baseline(ctx), ctx.ref, "15")
    except Exception as e:  # noqa: BLE001 — 커밋 못 읽음 = 모름(조용한 통과 0)
        return UNKNOWN, f"착지 커밋 못 읽음 — {type(e).__name__}: {e}"
    notes, src = sum(s["notes"].values()), len(commits) + sum(s["notes"].values())
    text = "\n".join(ctx.texts)
    pub = len(COMMIT_LINE.findall(text)) + sum(int(n) for n in NOTE_N.findall(text))
    if not COMMIT_LINE.search(text) and not NOTE_N.search(text):
        return UNKNOWN, "발행본에 착지 줄·완료 쪽지 줄 없음"
    return (PASS if pub == src else FAIL), f"발행본 {pub}줄 ≠ 기준선 뒤 착지 {len(commits)}건 + 완료 쪽지 {notes}통"


@guarded
def cell_c(ctx: Ctx) -> tuple[str, str]:
    """ⓒ 팀 지도 «팀 N개» = 명부 팀 수."""
    try:
        names = need("ft_ledger_fill_src", "teams")(ctx.repo, ctx.ref)
    except Missing:
        raise
    except Exception as e:  # noqa: BLE001
        return UNKNOWN, f"명부 못 읽음 — {type(e).__name__}: {e}"
    m = TEAM_N.search("\n".join(ctx.texts))
    if not m:
        return UNKNOWN, "발행본에 «팀 N개» 없음"
    return (PASS if int(m.group(1)) == len(names) else FAIL), f"발행본 {m.group(1)}개 ≠ 명부 {len(names)}개"


def _head_sha(ctx: Ctx) -> str:
    """발행본 머리 20줄의 첫 sha(리포에 실재하는 것만) → 없으면 지도 상태 last.sha."""
    git = need("ft_ledger_fill_src", "git")
    head = "\n".join(ctx.texts[0].splitlines()[:20]) if ctx.texts else ""
    for sha in SHA.findall(head):
        try:
            git(ctx.repo, "rev-parse", "--verify", "-q", f"{sha}^{{commit}}")
            return sha
        except Exception:  # noqa: BLE001 — 리포에 없는 글자(카드 sha 등) = 건너뜀
            continue
    return baseline(ctx)


@guarded
def cell_d(ctx: Ctx) -> tuple[str, str]:
    """ⓓ 발행본 머리 sha = 발행 시각의 origin/main 머리(차이 0 커밋)."""
    git, ancestor = need("ft_ledger_fill_src", "git"), need("ft_ledger_fill_src", "ancestor")
    pub = _head_sha(ctx)
    if not pub:
        return UNKNOWN, "발행본·지도 상태에 머리 sha 없음"
    try:
        actual = git(ctx.repo, "rev-parse", "--verify", f"{ctx.ref}^{{commit}}").strip()
        same = pub == actual or ancestor(ctx.repo, pub, actual)
    except Exception as e:  # noqa: BLE001
        return UNKNOWN, f"origin/main 머리 못 읽음 — {type(e).__name__}: {e}"
    return (PASS if same else FAIL), f"발행본 sha {pub[:10]} · {ctx.ref} {actual[:10]}" + ("" if same else " (발행본이 옛 판)")


@guarded
def cell_e(ctx: Ctx) -> tuple[str, str]:
    """ⓔ 같은 경고 문장이 하루 발행본에 2회 이상 0 — 셈은 발행 1회당 1(하루 창).
    V1(DA⑥ r1): «같은 경고 2회 이상» 을 이미 재는 선행 함수는 없다(탐색 원문 = evidence/r853/v1-warning-dedup-search.txt).
    r847 fail_announced = «구간당 1통» · fresh_note = «사건 키 1통» 이라 «하루 횟수» 판정이 아니다 — arch 판단 전까지 이 칸은 그대로."""
    f = (ctx.verify_state or Path()) / "warn-day.json"
    day, data = f"{ctx.now:%Y-%m-%d}", load((ctx.verify_state or Path()) / "warn-day.json", {})
    if data.get("date") != day:
        data = {"date": day, "n": {}}
    hit = [w for w in WARNINGS if w in "\n".join(ctx.texts)]
    for w in hit:
        data["n"][w] = data["n"].get(w, 0) + 1
    save(f, data)
    bad = [f"{w} {n}회" for w, n in data["n"].items() if n >= 2]
    return (FAIL if bad else PASS), ("같은 경고 " + " · ".join(bad) if bad else f"오늘 경고 {len(hit)}종 · 2회 이상 없음")


@guarded
def cell_f(ctx: Ctx) -> tuple[str, str]:
    """ⓕ «오빠가 본 완료 줄» 은 다음 판 1절에 없음 = lower_closed 가 내릴 줄 0."""
    git, published_at = need("ft_ledger_fill", "src").git, need("ft_ledger_fill", "published_at")
    try:
        text = git(ctx.repo, "show", f"{baseline(ctx) or ctx.ref}:{ctx.rel}")
        pub_at = published_at()
    except Exception as e:  # noqa: BLE001
        return UNKNOWN, f"원장·발행 기록 못 읽음 — {type(e).__name__}: {e}"
    if not pub_at:
        return UNKNOWN, "매거진 발행 성공 기록 없음(내릴 기준 0)"
    try:
        _out, _keep, moved = need("ft_ledger_fill_tables", "lower_closed")(text.split("\n"), load((ctx.verify_state or Path()) / "closed-seen.json", {}), pub_at, ctx.now)
    except Missing:
        raise
    except Exception as e:  # noqa: BLE001 — 원장 꼴 틀림 = 모름
        return UNKNOWN, f"원장 1·5절 못 읽음 — {type(e).__name__}: {e}"
    return (FAIL if moved else PASS), f"내려야 할 완료 줄 {moved}개(발행 성공 {pub_at})"


CELLS = (("ⓐ 오빠 할 일 건수", cell_a), ("ⓑ 한 일", cell_b), ("ⓒ 팀 수", cell_c),
         ("ⓓ 발행 sha", cell_d), ("ⓔ 같은 경고", cell_e), ("ⓕ 완료 줄", cell_f))
