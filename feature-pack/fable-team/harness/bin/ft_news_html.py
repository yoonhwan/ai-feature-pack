"""ft_news_html — 뉴스 HTML 모드(r478 · 오빠 확정 10-19 19:3x): 원장·좌석 상태·main 커밋·[긴급] 쪽지 머리를 한 묶음(input.json)으로 모아
opencode run(딥식 무료 · 비대화 1회)에 넘기고 «요약 3줄 + 팀 지도 HTML» 을 받아, 린트 통과분만 슬랙에 «한 줄 + 요약 2줄 + HTML 첨부» 로 올린다.

  ft_news_html.py build --out <폴더>                           input.json + prompt.txt
  ft_news_html.py run [--input <input.json>] --out <폴더>       (input 없으면 build 부터) → NEWS-<날짜>-<HHMM>.html + .summary.txt · 실패 rc1(발행 0)
  ft_news_html.py publish --html <f> --summary <f>            린트(rc3 = 발행 0) → 게시(ft_news_publish.publish_html)
뉴스 틱(ft_news_ledger.py · FT_NEWS_MODE=html)은 tick() — 원장 새 커밋 또는 그날 첫 발행 = 지도 1장 · 변화 0 = FT_NEWS_REPEAT_MIN(기본 30)분마다
«[뉴스 HH:MM] 변화 없음 · 지도 <직전 지도 링크>» 한 줄만. 미첨부(rc3)로 올라간 글은 다음 틱이 그 글 스레드에 첨부를 다시 시도한다.
지도 만들기 실패가 FT_NEWS_DELAY_TICKS(기본 3)틱 연속이면 고정 문구 «뉴스 지연» 한 줄 1번(정지 1건당 · 모델·판단 0) · 다음 지도 발행 때 «뉴스 복구» 한 줄(r510 · state/news-delay.json).
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

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ft_news_html_lint import SECRET, problems  # noqa: E402
from ft_news_html_render import PARTS, NewsHtmlError, build_prompt, call_model, render  # noqa: E402

LOG = logging.getLogger("ft_news_html")
KEEP = ("오빠 할 일", "팀 작업", "드러난 문제", "체크리스트")  # 원장에서 싣는 절(머리 글자) — 나머지(완료 보관·옛 지시)는 지도 원천이 아니다
SECTION_CHARS, LEDGER_CHARS, URGENT_N, MAILBOX_TAIL = 2500, 9000, 5, 262144
HEAD = re.compile(r"^(#{2,3})\s+(.*)")
SEAT_S = 7  # tmux ls 1회 상한(7초 룰)


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


def _sessions() -> list[str]:
    """tmux 세션 이름 전부 — 서버 없음 = [] · 그 밖의 실패 = RuntimeError(발행 0)."""
    done = subprocess.run(["tmux", "ls", "-F", "#{session_name}"], capture_output=True, text=True, timeout=SEAT_S, check=False)
    if done.returncode != 0 and "no server running" not in done.stderr:
        raise RuntimeError(f"tmux ls 실패 rc={done.returncode}: {done.stderr.strip()[:120]}")
    return done.stdout.split() if done.returncode == 0 else []


def _turns(seats: list[str]) -> dict[str, tuple[str, str]]:
    """좌석들 → (WORKING·IDLE·…|«?», 사유) 한 번에 — 판정기 = ft_seat_turn(셸 도구와 같은 것 · 좌석별 하위 프로세스 0 · r504)."""
    from ft_seat_turn import turns
    try:
        return turns(seats, os.environ.get("FT_TMUX", "tmux"), Path(os.environ.get("FT_CLAUDE_PROJECTS") or Path.home() / ".claude" / "projects"))
    except subprocess.TimeoutExpired:  # tmux list-panes 7초 초과 — 전 좌석 «확인 불가»(사유 보임 · 쉼 아님)
        return {s: ("?", "tmux 시간 초과") for s in seats}


def _unknown_reason(reasons: list[str]) -> str:
    return " · ".join(f"{r} {reasons.count(r)}석" for r in dict.fromkeys(reasons))  # «jsonl 없음 N석 · 읽기 실패 N석» (r490 꼴)


def live_teams(root: Path) -> list[dict]:
    """팀별 라이브 좌석 실측(r478c): 팀 = 명부 seats-<팀>.json(+ seats.json = v65) · 좌석 = tmux 세션 중 `byz-<팀>-`·`ft-<팀>-` 로 시작하는 것 ·
    일하는 좌석 = 턴 판정(ft_seat_turn)이 WORKING · 확인 불가 = «?»(사유 unknown_reason · r490). 쪽지 문장·스냅샷의 옛 «일함» 값은 쓰지 않는다."""
    fable = root / ".fable-team"
    names = [p.name[len("seats-"):-len(".json")] for p in fable.glob("seats-*.json")] + (["v65"] if (fable / "seats.json").is_file() else [])
    if not names:
        raise RuntimeError(f"명부 0개({fable}/seats-*.json) — 팀 실측 불가")
    sessions = _sessions()
    seats = {t: [s for s in sessions if s.startswith((f"byz-{t}-", f"ft-{t}-"))] for t in sorted(set(names))}
    state = _turns(sorted({s for ss in seats.values() for s in ss}))
    return [{"team": t, "live": len(ss), "working": sum(state[s][0] == "WORKING" for s in ss), "unknown": sum(state[s][0] == "?" for s in ss),
             "unknown_reason": _unknown_reason([state[s][1] for s in ss if state[s][0] == "?"])} for t, ss in seats.items()]


def commits(repo: Path, base: str) -> list[str]:
    ref, n = os.environ.get("FT_NEWS_MAIN_REF", "origin/main"), os.environ.get("FT_NEWS_COMMITS", "15")
    return _git(repo, "log", "--format=%h %s", "-n", n, f"{base}..{ref}" if base else ref).splitlines()


def autonomy(root: Path) -> str:
    """자율 모드 실측 — ft-autonomy.sh mode(on|off) → ON·OFF · 위변조·실패·시간 초과 = «모름»(요약에 승인·자율 문장 금지 · r478d)."""
    try:
        done = subprocess.run(["bash", str(HERE / "ft-autonomy.sh"), "mode"], capture_output=True, text=True, timeout=SEAT_S, check=False,
                              env={**os.environ, "FT_ROOT": str(root)})
    except (OSError, subprocess.TimeoutExpired):
        return "모름"
    return {"on": "ON", "off": "OFF"}.get(done.stdout.strip() if done.returncode == 0 else "", "모름")


def facts(live: list[dict], auto: str) -> dict:
    """요약·중요한 일 문장이 따라야 할 코드 판정(r478d) — 일하는 팀(좌석 많은 순)·확인 불가(일하는 0 ∧ 확인 불가 ≥1 · r490)·쉬는 팀(둘 다 0)·자율."""
    work = sorted((t for t in live if t["working"]), key=lambda t: (-t["working"], t["team"]))
    return {"일하는 팀": [t["team"] for t in work], "확인 불가": [t["team"] for t in live if not t["working"] and t.get("unknown")],
            "쉬는 팀": [t["team"] for t in live if not t["working"] and not t.get("unknown")], "자율": auto}


def build(root: Path, repo: Path, rel: str, base: str, cur: str, now: datetime) -> dict:
    live = live_teams(root)
    data = {"now": f"{now:%Y-%m-%d %H:%M}", "facts": facts(live, autonomy(root)), "goals": goals(), "ledger": ledger_parts(_git(repo, "show", f"{cur}:{rel}")),
            "urgent": urgent(root, now), "teams": teams(root), "live": live, "commits": commits(repo, base)}
    return _scrub(data)


def run_files(data: dict, out: Path, now: datetime) -> tuple[Path, Path]:
    from ft_news_html_render import model_id
    c, secs, fixed = call_model(data)
    page = render(c, data["goals"], now, (data.get("facts") or {}).get("자율", "모름"))
    out.mkdir(parents=True, exist_ok=True)
    html_p = out / f"NEWS-{now:%Y%m%d-%H%M}.html"
    sum_p = html_p.with_suffix(".summary.txt")
    html_p.write_text(page, encoding="utf-8")
    sum_p.write_text("\n".join(s.strip() for s in c["summary"] if s.strip()) + "\n", encoding="utf-8")
    print(f"ft-news-html: 만듦 {html_p.name} secs={max(secs.values()):.1f}({' '.join(f'{p}={s:.1f}' for p, s in secs.items())}) fixed={fixed:.1f}s model={model_id()} important={len(c['important'])} summary={len(sum_p.read_bytes())}B")
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


def _delay_fail(state: Path, now: datetime, why: str, last: dict) -> None:
    """r510 5b — 지도 만들기 실패 1틱 셈 · 연속 FT_NEWS_DELAY_TICKS 째에 고정 문구 지연 글 1번(같은 정지 동안 다시 0 · 발신 실패면 다음 틱 재시도)."""
    from ft_news_publish import publish_line
    f = state / "news-delay.json"
    d = json.loads(f.read_text(encoding="utf-8")) if f.is_file() else {}
    d = {"n": d.get("n", 0) + 1, "why": d.get("why") or why[:120], "since": d.get("since") or f"{now:%Y-%m-%d %H:%M}", "sent": d.get("sent", False)}
    if not d["sent"] and d["n"] >= int(os.environ.get("FT_NEWS_DELAY_TICKS", "3")):
        mark = last.get("map_at", "")[11:] or "없음"
        d["sent"] = publish_line(f"뉴스 지연 — 사유: {d['why']} · 마지막 판 {mark}({last.get('link') or '링크 없음'}) · 부하 {os.getloadavg()[0]:.2f}", now) == 0
    _save(f, d)


def _delay_clear(state: Path, now: datetime, last: dict) -> None:
    """지도 글이 올라갔다 — 지연 셈 지움 · 지연 글을 냈던 정지면 «뉴스 복구 HH:MM · 지연 N분»(N = 직전 판부터) 한 줄."""
    from ft_news_publish import publish_line
    f = state / "news-delay.json"
    if not f.is_file():
        return
    d = json.loads(f.read_text(encoding="utf-8"))
    f.unlink()
    if d.get("sent"):
        mins = int((now - datetime.strptime(last.get("map_at") or d["since"], "%Y-%m-%d %H:%M")).total_seconds() // 60)
        publish_line(f"뉴스 복구 {now:%H:%M} · 지연 {mins}분", now)


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
    warn = os.environ.get("FT_LEDGER_SYNC_ERROR", "")  # r503 — 원장 사본 갱신 실패면 «변화 없음» 줄·지도 글 머리에 그 사유를 싣는다(낡은 판을 «변화 없음» 으로 읽지 않게)
    if warn and warn not in os.environ.get("FT_NEWS_HEAD", ""):
        os.environ["FT_NEWS_HEAD"] = f"{os.environ.get('FT_NEWS_HEAD') or '팀 지도'} · {warn}"
    if base == cur and last.get("map_at", "")[:10] == stamp[:10]:  # 변화 0 · 오늘 지도 있음 = 적정한 반복 한 줄만
        if since("at") < timedelta(minutes=int(os.environ.get("FT_NEWS_REPEAT_MIN", "30"))):
            return 0, "원장 커밋 0"
        rc = publish_line(f"[뉴스 {now:%H:%M}] 변화 없음 · 지도 {last.get('link') or last['map_at']}" + (f" · {warn}" if warn else ""), now)
        if rc == 0:
            _save(hs, {**last, "at": stamp})
        return rc, "원장 커밋 0"
    try:
        html_p, sum_p = run_files(build(root, repo, rel, base, cur, now), news, now)
    except (NewsHtmlError, RuntimeError, OSError, ValueError, KeyError) as e:
        LOG.error("지도 만들기 실패 — 발행 0: %s", e)
        _save(hs, {**last, "fail_at": stamp})
        _delay_fail(state, now, f"지도 만들기 실패 — 발행 0: {e}", last)
        return 1, "지도 만들기 실패"
    rc, got = publish_files(html_p, sum_p, now)
    if got is not None:  # 글이 올라갔다(미첨부 rc3 포함) — 기준선 전진
        _delay_clear(state, now, last)
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
    from ft_news_ledger import planner_ledger_rel, sync_repo
    sync_repo()  # r503 — 명시된 원장 사본만 origin/main 전진 · 실패는 ERROR 로그(지금 판으로 계속)
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
