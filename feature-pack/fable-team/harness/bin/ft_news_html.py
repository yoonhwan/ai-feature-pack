"""ft_news_html — 뉴스 HTML 모드(r478 · 오빠 확정 10-19 19:3x): 원장·좌석 상태·main 커밋·[긴급] 쪽지 머리를 한 묶음(input.json)으로 모아
opencode run(딥식 무료 · 비대화 1회)에 넘기고 «요약 3줄 + 팀 지도 HTML» 을 받아, 린트 통과분만 슬랙에 «한 줄 + 요약 2줄 + HTML 첨부» 로 올린다.

  ft_news_html.py build --out <폴더>                           input.json + prompt.txt
  ft_news_html.py run [--input <input.json>] --out <폴더>       (input 없으면 build 부터) → NEWS-<날짜>-<HHMM>.html + .summary.txt · 실패 rc1(발행 0)
  ft_news_html.py publish --html <f> --summary <f>            린트(rc3 = 발행 0) → 게시(ft_news_publish.publish_html)
뉴스 틱(ft_news_ledger.py · FT_NEWS_MODE=html)은 tick() — 원장 새 커밋 또는 그날 첫 발행 = 지도 1장 · 변화 0 = FT_NEWS_REPEAT_MIN(기본 30)분마다
«[뉴스 HH:MM] 변화 없음 · 지도 <직전 지도 링크>» 한 줄만. 미첨부(rc3)로 올라간 글은 다음 틱이 그 글 스레드에 첨부를 다시 시도한다.
env: FT_ROOT · FT_LEDGER_REPO · FT_LEDGER_PATH · FT_NEWS_DIR · FT_NEWS_NOW · FT_NEWS_REPEAT_MIN · FT_NEWS_COMMITS(기본 15) · FT_NEWS_MAIN_REF(기본 origin/main)
     + ft_news_html_render(FT_NEWS_MODEL · FT_NEWS_EFFORT · FT_NEWS_DEPTH · FT_OPENCODE) · ft_news_publish(FT_NEWS_HEAD 등)
"""
import argparse
import json
import logging
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ft_news_html_lint import SECRET, problems  # noqa: E402
from ft_news_html_render import PARTS, NewsHtmlError, build_prompt, call_model, render  # noqa: E402

LOG = logging.getLogger("ft_news_html")
KEEP = ("오빠 할 일", "팀 작업", "드러난 문제", "체크리스트")  # 원장에서 싣는 절(머리 글자) — 나머지(완료 보관·옛 지시)는 지도 원천이 아니다
SECTION_CHARS, LEDGER_CHARS, URGENT_N, MAILBOX_TAIL = 2500, 9000, 5, 262144
HEAD = re.compile(r"^(#{2,3})\s+(.*)")


def _git(repo: Path, *a: str) -> str:
    done = subprocess.run(["git", "-C", str(repo), *a], capture_output=True, text=True, encoding="utf-8", check=False)
    if done.returncode != 0:
        raise RuntimeError(f"git {a[0]} 실패: {done.stderr.strip()[:200]}")
    return done.stdout


def _scrub(v):
    """시크릿 꼴 가림 — 입력 묶음 전체(문자열 칸마다)."""
    if isinstance(v, str):
        return SECRET.sub("[가림]", v)
    if isinstance(v, list):
        return [_scrub(x) for x in v]
    return {k: _scrub(x) for k, x in v.items()} if isinstance(v, dict) else v


def goals() -> list[dict]:
    import ft_goal_table as gt  # 골 표 정본·원장 상태 칸(뉴스·매거진·쪽지 가드와 같은 판정기)
    text, _, _ = gt.load_canon()
    _, states = gt.ledger_state(gt._ledger_show, gt.GoalError)
    return [{"n": i, "goal": g, "team": t, "state": states.get(i, gt.NO_STATE)} for i, (g, t, _e) in enumerate(gt.parse_rows(text), 1)]


def ledger_parts(text: str) -> list[dict]:
    """원장에서 KEEP 절(## · ###)과 «**지금» 줄만 — 절마다 SECTION_CHARS · 합 LEDGER_CHARS(넘으면 «…(줄임)» 표시)."""
    out, cur, level = [], None, 0
    for ln in text.splitlines():
        if m := HEAD.match(ln):
            if cur is not None and len(m[1]) <= level:
                cur = None
            if cur is None and any(k in m[2] for k in KEEP):
                cur, level = {"title": m[2].strip(), "text": ""}, len(m[1])
                out.append(cur)
            continue
        if cur is not None:
            cur["text"] += ln + "\n"
        elif ln.startswith("**지금"):
            out.append({"title": "지금", "text": ln})
    total = 0
    for p in out:
        cut = p["text"].strip()[: min(SECTION_CHARS, max(0, LEDGER_CHARS - total))]
        p["text"], total = cut + ("…(줄임)" if len(cut) < len(p["text"].strip()) else ""), total + len(cut)
    return [p for p in out if p["text"]]


def urgent(root: Path, now: datetime) -> list[str]:
    """쪽지함 꼬리에서 24시간 안 [긴급 쪽지 머리 1줄(최근 URGENT_N) — 쪽지함 없음 = «원천 없음» 줄."""
    box = root / ".fable-team" / "comm" / "mailbox.jsonl"
    if not box.is_file():
        return [f"원천 없음: {box} 없음"]
    with box.open("rb") as f:
        f.seek(max(0, f.seek(0, 2) - MAILBOX_TAIL))
        tail = f.read().decode("utf-8", "replace").splitlines()
    out = []
    for ln in tail:
        try:
            row = json.loads(ln)
            at = datetime.fromisoformat(str(row.get("ts", ""))[:19])
        except ValueError:
            continue
        head = str(row.get("body", "")).splitlines()[0] if row.get("body") else ""
        if "[긴급" in head and now - at <= timedelta(hours=24):
            out.append(head[:160])
    return out[-URGENT_N:]


def teams(root: Path) -> list[str] | str:
    """보드 스냅샷(ft-board collect dict · ft_news_status 와 같은 원천) → 팀마다 «일함 N · 정지 … / 해야 할 일 …» · 못 읽으면 «원천 없음» 그대로."""
    from ft_news_status import _lines, latest_snapshot
    try:
        path, taken = latest_snapshot(root)
        return [f"(스냅샷 {taken:%m-%d %H:%M})", *_lines(json.loads(path.read_text(encoding="utf-8")), True)]
    except (RuntimeError, OSError, ValueError, KeyError, TypeError) as e:
        return f"원천 없음: {e}"


def commits(repo: Path, base: str) -> list[str]:
    ref, n = os.environ.get("FT_NEWS_MAIN_REF", "origin/main"), os.environ.get("FT_NEWS_COMMITS", "15")
    return _git(repo, "log", "--format=%h %s", "-n", n, f"{base}..{ref}" if base else ref).splitlines()


def build(root: Path, repo: Path, rel: str, base: str, cur: str, now: datetime) -> dict:
    data = {"now": f"{now:%Y-%m-%d %H:%M}", "goals": goals(), "ledger": ledger_parts(_git(repo, "show", f"{cur}:{rel}")),
            "urgent": urgent(root, now), "teams": teams(root), "commits": commits(repo, base)}
    return _scrub(data)


def run_files(data: dict, out: Path, now: datetime) -> tuple[Path, Path]:
    from ft_news_html_render import model_id
    c, secs = call_model(data)
    page = render(c, data["goals"], now)
    out.mkdir(parents=True, exist_ok=True)
    html_p = out / f"NEWS-{now:%Y%m%d-%H%M}.html"
    sum_p = html_p.with_suffix(".summary.txt")
    html_p.write_text(page, encoding="utf-8")
    sum_p.write_text("\n".join(s.strip() for s in c["summary"] if s.strip()) + "\n", encoding="utf-8")
    print(f"ft-news-html: 만듦 {html_p.name} secs={max(secs.values()):.1f}({' '.join(f'{p}={s:.1f}' for p, s in secs.items())}) model={model_id()} important={len(c['important'])} summary={len(sum_p.read_bytes())}B")
    return html_p, sum_p


def publish_files(html_p: Path, sum_p: Path, now: datetime) -> tuple[int, dict | None]:
    """(rc, 영수증) — 린트 위반 = (3, None) 발행 0 · 게시 결과는 ft_news_publish.publish_html 그대로(미첨부 = rc3 + 영수증)."""
    summary = sum_p.read_text(encoding="utf-8")
    if found := problems(html_p.read_text(encoding="utf-8"), summary):
        print("\n".join(f"LINT {p}" for p in found))
        LOG.error("린트 위반 %d건 — 발행 0 (%s)", len(found), found[0])
        return 3, None
    from ft_news_publish import publish_html
    return publish_html(html_p, summary, now)


def _save(f: Path, data: dict) -> None:
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")


def tick(root: Path, state: Path, repo: Path, rel: str, news: Path, base: str, cur: str) -> tuple[int, str]:
    """뉴스 틱 HTML 경로 — (rc, 정지 감시용 사유). 기준선(state/last.sha)은 지도 글이 올라갔을 때만 옮긴다."""
    from ft_news_post import news_now
    from ft_news_publish import publish_line, retry_attach
    now, hs = news_now(), state / "html.json"
    last, stamp = (json.loads(hs.read_text(encoding="utf-8")) if hs.is_file() else {}), f"{now:%Y-%m-%d %H:%M}"
    retry_attach(now)
    since = lambda k: now - datetime.strptime(last[k], "%Y-%m-%d %H:%M") if last.get(k) else timedelta.max  # noqa: E731
    if since("fail_at") < timedelta(minutes=int(os.environ.get("FT_NEWS_RETRY_MIN", "5"))):
        return 1, "지도 만들기 실패(재시도 대기)"
    if base == cur and last.get("map_at", "")[:10] == stamp[:10]:  # 변화 0 · 오늘 지도 있음 = 적정한 반복 한 줄만
        if since("at") < timedelta(minutes=int(os.environ.get("FT_NEWS_REPEAT_MIN", "30"))):
            return 0, "원장 커밋 0"
        rc = publish_line(f"[뉴스 {now:%H:%M}] 변화 없음 · 지도 {last.get('link') or last['map_at']}", now)
        if rc == 0:
            _save(hs, {**last, "at": stamp})
        return rc, "원장 커밋 0"
    try:
        html_p, sum_p = run_files(build(root, repo, rel, base, cur, now), news, now)
    except (NewsHtmlError, RuntimeError, OSError, ValueError, KeyError) as e:
        LOG.error("지도 만들기 실패 — 발행 0: %s", e)
        _save(hs, {**last, "fail_at": stamp})
        return 1, "지도 만들기 실패"
    rc, got = publish_files(html_p, sum_p, now)
    if got is not None:  # 글이 올라갔다(미첨부 rc3 포함) — 기준선 전진
        _save(hs, {"at": stamp, "map_at": stamp, "ts": got.get("ts"), "link": got.get("permalink")})
        state.mkdir(parents=True, exist_ok=True)
        (state / "last.sha").write_text(cur + "\n", encoding="utf-8")
    elif rc:
        _save(hs, {**last, "fail_at": stamp})
    return rc, (f"게시 실패 rc={rc}" if rc else "지도 발행")


def _ledger_args() -> tuple[Path, Path, str, str, str]:
    """(루트, 원장 리포, 원장 경로, 기준선, 지금 커밋) — 뉴스 틱(ft_news_ledger._run)과 같은 풀이."""
    import ft_board_env as env
    from ft_goal_ledger import live_root
    from ft_news_ledger import planner_ledger_rel
    root = env.ft_root()
    repo = Path(os.environ.get("FT_LEDGER_REPO") or live_root(RuntimeError, root))
    rel = os.environ.get("FT_LEDGER_PATH") or planner_ledger_rel(repo)
    base_f = root / ".fable-team" / "state" / "news-ledger" / "last.sha"
    return root, repo, rel, base_f.read_text(encoding="utf-8").strip() if base_f.exists() else "", _git(repo, "log", "-1", "--format=%H", "--", rel).strip()


def main(argv: list[str]) -> int:
    from ft_news_post import news_now
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("build").add_argument("--out", required=True)
    pr = sub.add_parser("run")
    pr.add_argument("--input")
    pr.add_argument("--out", required=True)
    pp = sub.add_parser("publish")
    pp.add_argument("--html", required=True)
    pp.add_argument("--summary", required=True)
    a, now = p.parse_args(argv), news_now()
    try:
        if a.cmd == "publish":
            return publish_files(Path(a.html), Path(a.summary), now)[0]
        data = json.loads(Path(a.input).read_text(encoding="utf-8")) if a.cmd == "run" and a.input else build(*_ledger_args(), now)
        if a.cmd == "build":
            out = Path(a.out)
            out.mkdir(parents=True, exist_ok=True)
            _save(out / "input.json", data)
            for part in PARTS:
                (out / f"prompt-{part}.txt").write_text(build_prompt(data, part), encoding="utf-8")
            print(f"ft-news-html: 묶음 {out / 'input.json'} · 프롬프트 {out}/prompt-{{{','.join(PARTS)}}}.txt")
            return 0
        run_files(data, Path(a.out), now)
        return 0
    except (NewsHtmlError, RuntimeError, OSError, ValueError, KeyError) as e:
        print(f"ft-news-html: 실패 — {e} (발행 0)", file=sys.stderr)
        return 1


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    raise SystemExit(main(sys.argv[1:]))
