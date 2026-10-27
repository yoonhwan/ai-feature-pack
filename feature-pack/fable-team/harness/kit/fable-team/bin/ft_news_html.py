"""ft_news_html — 뉴스 HTML 모드(r478 · 오빠 확정 10-19 19:3x): 원장·좌석 상태·main 커밋·[긴급] 쪽지 머리를 한 묶음(input.json)으로 모아
opencode run(딥식 무료 · 비대화 1회)에 넘기고 «요약 3줄 + 팀 지도 HTML» 을 받아, 린트 통과분만 슬랙에 «한 줄 + 요약 2줄 + HTML 첨부» 로 올린다.

  ft_news_html.py build --out <폴더>                           input.json + prompt.txt
  ft_news_html.py run [--input <input.json>] --out <폴더>       (input 없으면 build 부터) → NEWS-<날짜>-<HHMM>.html + .summary.txt · 실패 rc1(발행 0)
  ft_news_html.py publish --html <f> --summary <f>            린트(rc3 = 발행 0) → 게시(ft_news_publish.publish_html)
뉴스 틱(ft_news_ledger.py · FT_NEWS_MODE=html)은 tick() — 원장 내용(블롭)이 바뀌었거나 골 정본 내용이 바뀌었거나(r737) 그날 첫 발행 = 지도 1장(어느 팀이든 main 커밋이 왔다는 것만으로는 아니다 · r656) · 변화 0 = FT_NEWS_REPEAT_MIN(기본 30)분마다
«[뉴스 HH:MM] 변화 없음 · 지도 <직전 지도 링크>» 한 줄만. 미첨부(rc3)로 올라간 글은 다음 틱이 그 글 스레드에 첨부를 다시 시도한다.
지도 만들기 실패가 FT_NEWS_DELAY_TICKS(기본 3)틱 연속이면 고정 문구 «뉴스 지연» 한 줄 1번(정지 1건당 · 모델·판단 0) · 다음 지도 발행 때 «뉴스 복구» 한 줄(r510 · state/news-delay.json).
env: FT_ROOT · FT_LEDGER_REPO · FT_LEDGER_PATH · FT_NEWS_DIR · FT_NEWS_NOW · FT_NEWS_REPEAT_MIN · FT_NEWS_COMMITS(기본 15) · FT_NEWS_MAIN_REF(기본 origin/main)
     + ft_news_html_render(FT_NEWS_MODEL · FT_NEWS_EFFORT · FT_NEWS_DEPTH · FT_OPENCODE) · ft_news_publish(FT_NEWS_HEAD 등)
"""
import argparse
import hashlib
import json
import logging
import math
import os
import re
import subprocess
import sys
import traceback
from datetime import datetime, timedelta
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from ft_news_html_lint import FOOT, SECRET, problem_records, problems  # noqa: E402
from ft_news_html_render import DROP_ENV, PARTS, NewsHtmlError, build_prompt, call_model, render  # noqa: E402

LOG = logging.getLogger("ft_news_html")
KEEP = ("오빠 할 일", "팀 작업", "드러난 문제", "체크리스트")  # 원장에서 싣는 절(머리 글자) — 나머지(완료 보관·옛 지시)는 지도 원천이 아니다
SECTION_CHARS, LEDGER_CHARS, URGENT_N, MAILBOX_TAIL = 2500, 9000, 5, 262144
HEAD = re.compile(r"^(#{2,3})\s+(.*)")
SEAT_S = 7  # tmux ls 1회 상한(7초 룰)
GIT_S = 7  # 이 경로의 git 호출 1회 상한(7초 룰 · r907 r4) — 넘으면 «모름»/지도 만들기 실패
SHA40 = re.compile(r"[0-9a-f]{40}")
KEY_SCAN_N = 200  # 판정 키 — 원장 경로를 건드린 최근 커밋 몇 개까지 보나(r907 r5 · 이 안에 «채움 아닌» 커밋이 없으면 키 모름)
MIN_GAP_MIN = 10.0 # r907 r2 — 지도 게시 사이 최소 간격(분 · env FT_NEWS_MIN_GAP_MIN · 그 안의 변화는 다음 틱으로)


def _git(repo: Path, *a: str) -> str:
    try:
        done = subprocess.run(["git", "-C", str(repo), *a], capture_output=True, text=True, encoding="utf-8", check=False, timeout=GIT_S)  # r907 r4 — 7초 룰(넘으면 RuntimeError = 지도 만들기 실패 경로)
    except subprocess.TimeoutExpired as e:
        raise RuntimeError(f"git {a[0]} 시간 초과({GIT_S}초)") from e
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
    """기준선 뒤 착지 «전부»(r851 ⓓ · 15개 상한 0 · 매거진·원장 채움과 같은 함수) — 기준선 없는 첫 판만 FT_NEWS_COMMITS(15)개."""
    from ft_ledger_fill_src import landed_commits  # 실패 = FillError(RuntimeError) — 지도 만들기 실패 경로 그대로
    return landed_commits(repo, base, os.environ.get("FT_NEWS_MAIN_REF", "origin/main"), os.environ.get("FT_NEWS_COMMITS", "15"))


def ledger_fill(root: Path, repo: Path, rel: str, cur: str) -> str:
    """r851 A1 — 발행 직전 원장 표 기계 채움 1회(FT_LEDGER_FILL=0 = 끔 · 되돌림) · push 된 새 커밋이면 그 커밋이 이번 판.
    실패 = ERROR 로그 + 지금 판으로 계속(오래 실패하면 아래 신선도 머리 줄이 알린다)."""
    if os.environ.get("FT_LEDGER_FILL", "1") == "0":
        return cur
    from ft_ledger_fill import FillError, fill, now
    push = os.environ.get("FT_LEDGER_FILL_PUSH", "1") != "0"
    try:
        _rc, sha = fill(root, repo, rel, os.environ.get("FT_NEWS_MAIN_REF", "origin/main"), now(), do_fetch=False, push=push)
    except FillError as e:  # r870 ⓒ — 같은 원인 push 실패 연속(repeat)은 경고로(실패 구간당 ERROR 1통)
        (LOG.warning if getattr(e, "repeat", False) else LOG.error)("원장 채움 실패 — 표 갱신 0: %s", e)
        return cur
    return sha if sha and push else cur


def ledger_fresh(root: Path, repo: Path, rel: str, cur: str) -> str:
    """r851 A2 — '' = 신선 · 아니면 «원장 N분 낡음 · 담당 X»(planner [긴급] 1통은 fresh_note 가 같은 사건 1번) · FT_LEDGER_FRESH_GATE=0 = 끔(되돌림)."""
    if os.environ.get("FT_LEDGER_FRESH_GATE", "1") == "0":
        return ""
    from ft_ledger_fill import fresh_note, now
    try:
        return fresh_note(root, _git(repo, "show", f"{cur}:{rel}"), now())
    except (RuntimeError, OSError, ValueError) as e:
        LOG.error("원장 신선도 못 잼: %s", e)
        return f"원장 신선도 못 잼 — {str(e)[:80]}"


def autonomy(root: Path) -> str:
    """자율 모드 실측 — 데이터 루트(`<root>/.fable-team/LIVE_ROOT` 1행 · 없으면 root)의 ft-autonomy.sh mode(on|off) → ON·OFF · 위변조·실패·시간 초과 = «모름».
    r563: FT_ROOT 로 공용 루트를 그대로 넘기면 상태 폴더가 달라 «off» 로 오독했다(자율 ON 인데 본문이 «승인을 기다린다»)."""
    try:
        data_root = (root / ".fable-team" / "LIVE_ROOT").read_text(encoding="utf-8").splitlines()[0].strip()
    except (OSError, IndexError):
        data_root = ""
    if not data_root.startswith("/") or not Path(data_root).is_dir():
        data_root = str(root)
    try:
        done = subprocess.run(["bash", str(HERE / "ft-autonomy.sh"), "mode"], capture_output=True, text=True, timeout=SEAT_S, check=False,
                              env={**os.environ, "FT_ROOT": data_root})
    except (OSError, subprocess.TimeoutExpired):
        return "모름"
    return {"on": "ON", "off": "OFF"}.get(done.stdout.strip() if done.returncode == 0 else "", "모름")


def facts(live: list[dict], auto: str) -> dict:
    """요약·중요한 일 문장이 따라야 할 코드 판정(r478d) — 일하는 팀(좌석 많은 순)·확인 불가(일하는 0 ∧ 확인 불가 ≥1 · r490)·쉬는 팀(둘 다 0)·자율."""
    work = sorted((t for t in live if t["working"]), key=lambda t: (-t["working"], t["team"]))
    return {"일하는 팀": [t["team"] for t in work], "확인 불가": [t["team"] for t in live if not t["working"] and t.get("unknown")],
            "쉬는 팀": [t["team"] for t in live if not t["working"] and not t.get("unknown")], "자율": auto}


def build(root: Path, repo: Path, rel: str, base: str, cur: str, now: datetime) -> dict:
    live, goal_rows = live_teams(root), goals()
    if not goal_rows:  # r563 — 골 없는 뉴스를 «정상» 으로 내지 않는다(조용한 0 줄 금지)
        raise RuntimeError("골 표 0줄 — 지도 발행 0(정본·원장 상태 칸을 읽지 못했다)")
    data = {"now": f"{now:%Y-%m-%d %H:%M}", "facts": facts(live, autonomy(root)), "goals": goal_rows,
            "ledger": ledger_parts(_git(repo, "show", f"{cur}:{rel}")),
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


def _drop_one(html: str, summary: str, attr: str) -> tuple[str, str] | None:
    """귀속(«summary 3»·«important 2») 하나를 그 줄·항목 통째로 뺐다 — (html, summary) · 못 빼면 None(굳은 위반과 같은 처리)."""
    kind, _, num = attr.partition(" ")
    if not num.isdigit():
        return None
    n = int(num)
    if kind == "summary":
        lines = [ln for ln in summary.splitlines() if ln.strip()]
        if n < 2 or n > len(lines):  # 1번 = 코드가 넣은 팀 상태 줄 · 빼지 않는다
            return None
        del lines[n - 1]
        return html, "\n".join(lines) + "\n"
    if kind == "important":
        prio = re.search(r'<section class="prio">(.*?)</section>', html, re.S)
        items = re.findall(r"<li[ >].*?</li>", prio[1], re.S) if prio else []
        if not 1 <= n <= len(items) or len(items) <= 1:  # 빼고 나니 0개 = 발행 0(지금과 같음)
            return None
        return html.replace(items[n - 1], "", 1), summary
    return None


def _tail(summary: str, n: int) -> str:
    """«(빠진 줄 N)» 꼬리를 마지막 줄에 붙인 미리보기 — 줄 수를 늘리지 않는다(합계 600B 판정은 린트가 한다)."""
    lines = [ln.rstrip() for ln in summary.splitlines() if ln.strip()]
    if n and lines:
        lines[-1] = f"{lines[-1]} (빠진 줄 {n})"
    return "\n".join(lines) + "\n" if lines else summary


def _footnote(html: str, dropped: list[str]) -> str:
    """각주(단일 <p class="foot">)에 «빠진 줄 N개 — <갈래 번호>: <사유>» — 화면 경고(#0 RULE 예외 ③)."""
    foot = FOOT.search(html)
    if not dropped or not foot:
        return html
    note = f" · 빠진 줄 {len(dropped)}개 — {'; '.join(dropped)}"
    at = foot.end() - len("</p>")
    return html[:at] + note + html[at:]


def drop_soft(html: str, summary: str, limit: int = 12) -> tuple[str, str, list[str]]:
    """(html, summary, 빠진 줄 설명) — 무른 위반(린트가 «summary N»·«important N» 로 꾸는 것)의 그 줄·항목만 빼고 다시 본다.
    굳은 위반(구조·시크릿·각주 밖 번호·귀속 없음)은 건드리지 않는다 — 뺄 수 없으면 지금 판 그대로 돌려준다(발행 0)."""
    dropped: list[str] = []
    for _ in range(limit):
        soft = [(m, a) for m, a in problem_records(html, _tail(summary, len(dropped))) if a]
        if not soft:
            return (_footnote(html, dropped), _tail(summary, len(dropped)), dropped) if dropped else (html, summary, [])
        msg, attr = soft[-1]
        got = _drop_one(html, summary, attr)
        if got is None:
            break
        html, summary = got
        dropped.append(f"{attr}: {msg.replace(f'[{attr}] ', '').replace(f'[{attr}]', '')}")
    return html, summary, []


def publish_files(html_p: Path, sum_p: Path, now: datetime) -> tuple[int, dict | None]:
    """(rc, 영수증) — 린트 위반 = (3, None) 발행 0 · 게시 결과는 ft_news_publish.publish_html 그대로(미첨부 = rc3 + 영수증).
    r603: `FT_NEWS_DROP_LINE=1` 이면 무른 위반 줄·항목을 빼고 각주·꼬리로 보이게 하고 ERROR 로그 1줄 남긴 뒤 다시 린트한다."""
    summary, html = sum_p.read_text(encoding="utf-8"), html_p.read_text(encoding="utf-8")
    if os.environ.get(DROP_ENV, "").strip() == "1":
        html, summary, dropped = drop_soft(html, summary)
        if dropped:
            LOG.error("무른 위반 %d건 — 줄 빼고 발행 (%s)", len(dropped), " · ".join(dropped))
            html_p.write_text(html, encoding="utf-8")
            sum_p.write_text(summary, encoding="utf-8")
    if found := problems(html, summary):
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
        gone = _since(last, "map_at", now)
        if gone == timedelta.max:  # 직전 판 시각 모름 = 지연 시작 시각부터
            gone = _since(d, "since", now)
        mins = 0 if gone == timedelta.max else int(gone.total_seconds() // 60)
        publish_line(f"뉴스 복구 {now:%H:%M} · 지연 {mins}분", now)


def _min_gap_min() -> float:
    """게시 최소 간격(분) — 유한하고 1 ≤ 값 ≤ 1440 만 쓰고 그 밖(숫자 아님·0 이하·nan·inf·1e308) = 10."""
    try:
        v = float(os.environ.get("FT_NEWS_MIN_GAP_MIN", str(MIN_GAP_MIN)))
    except ValueError:
        return MIN_GAP_MIN
    return v if math.isfinite(v) and 1 <= v <= 1440 else MIN_GAP_MIN


def _since(last: dict, key: str, now: datetime, required: bool = True) -> timedelta:
    """지도 상태의 시각 칸(map_at · fail_at · at) 읽기 — 한 곳(r907 r5·r6). 지금까지 걸린 시간.
    기본 required=True(r6: «모름» 을 조용히 정상으로 넘기는 기본값 뒤집기) — 상태 파일은 있는데(last 비어 있지 않음) 칸 없음 · 형 다름 · 파싱 실패 · 미래(허용 1분 밖) = «모름» = timedelta.max(대기 0 · 지금 가능) + WARN 1줄 · 예외 0.
    «없어도 정상» 인 칸만 호출하는 쪽이 required=False 를 적는다(지금은 fail_at 하나 — 실패한 적 없음 = 칸 없음). 상태 파일 자체가 없음(last 비어 있음) = 첫 판 = WARN 0."""
    raw = last.get(key)
    if not raw:
        if required and last:
            LOG.warning("지도 상태 시각 모름 — %s 칸 없음 · 대기 0(지금 가능)", key)
        return timedelta.max
    try:
        at = datetime.strptime(raw, "%Y-%m-%d %H:%M")
        if (at - now) > timedelta(minutes=1):  # 미래 시각 = 시계 뒤틀림/손상
            raise ValueError("미래 시각 — 시계 뒤틀림/손상")
    except (ValueError, TypeError, OverflowError) as e:
        LOG.warning("지도 상태 시각 모름 — %s=%r: %s · 대기 0(지금 가능)", key, raw, e)
        return timedelta.max
    return now - at


def _gap_ok(last: dict, now: datetime) -> bool:
    """게시 가능? = 마지막 지도 게시(map_at)에서 최소 간격이 지났나. 상태 없음 = 첫 판(게시 가능) · 시각 «모름» = 게시 가능(_since)."""
    return not last or _since(last, "map_at", now) >= timedelta(minutes=_min_gap_min())


def _human_key(repo: Path, rel: str, cur: str) -> str | None:
    """판정 키(r907 r5) — 원장 경로를 건드린 최근 KEY_SCAN_N 커밋 중 «채움이 아닌» 첫 커밋의 sha. 채움 판별 = 커미터 이메일(ft_ledger_fill 의 WHO@byz.local · 메시지는 안 본다).
    채움(ft_ledger_fill)이 커밋마다 그 이메일을 쓴다 — 채움 커밋만 쌓이면 키 그대로 · 사람 커밋 1개면 키 바뀜. 사람 PR 본문에 채움 문구가 들어 있어도 사람 커밋이다(메시지 거름 0).
    왜: 채움이 매 틱 §2·표 칸을 다시 써서 커밋하므로(«기다린 지 N분») 원장 블롭 그대로면 «바뀐 것» 으로 읽혀 매 틱 지도를 다시 낸다(하루 235회 게시 · 평균 205초 · arch 실측).
    못 구하면(채움 모듈 없음 · rc≠0 · 시간 초과 · KEY_SCAN_N 개가 전부 채움) None = 모름 = 항상 «바뀜» 쪽(게시 후보 · 최소 간격이 상한)."""
    try:
        from ft_ledger_fill import WHO  # 채움 커미터 이름 — 한 곳
    except Exception as e:  # noqa: BLE001 — 채움 모듈 없음 = 키 모름
        LOG.warning("판정 키 모름 — 채움 커미터 이름을 못 읽음: %s", e)
        return None
    try:
        done = subprocess.run(["git", "-C", str(repo), "log", f"-n{KEY_SCAN_N}", "--format=%H%x00%ce", cur, "--", rel],
                              capture_output=True, text=True, encoding="utf-8", check=False, timeout=GIT_S)
    except (OSError, subprocess.TimeoutExpired) as e:
        LOG.warning("판정 키 모름 — git log 실패: %s", e)
        return None
    if done.returncode != 0:
        LOG.warning("판정 키 모름 — git log rc=%s: %s", done.returncode, done.stderr.strip()[:200])
        return None
    for ln in done.stdout.splitlines():
        sha, _, email = ln.partition("\x00")
        if SHA40.fullmatch(sha) and email.strip() != f"{WHO}@byz.local":
            return sha
    LOG.warning("판정 키 모름 — 최근 %s 커밋에 채움 아닌 커밋이 없다", KEY_SCAN_N)
    return None


def _canon_sha() -> str:
    """골 정본 «내용» sha256 앞10 — 정본만 바뀐 커밋(원장 그대로)도 지도를 다시 내게 한다(r737).
    load_canon 의 sha10 은 gitref 모드에서 ref 커밋 sha 라 main 커밋마다 흔들린다(r656 이 되돌아간다) — 그래서 본문을 다시 해싱한 내용 sha 를 쓴다.
    못 읽으면 ''(판정 0 = r656 판정 그대로 · 뉴스 틱은 안 죽는다)."""
    import ft_goal_table as gt
    try:
        text, _sha, _src = gt.load_canon()
    except Exception as e:  # noqa: BLE001 — 정본 없음·깨짐이 뉴스 틱을 멈추게 두지 않는다
        LOG.error("골 정본 못 읽음 — 정본 sha 판정 0: %s", e)  # r737 arch §199: 조용한 info 금지 — 정본이 사라진 것은 ERROR
        return ""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:10]


def _save_base(state: Path, cur: str, blob: str | None, canon: str = "") -> None:
    """기준선 세 칸 — last.sha(최근 커밋 칸 기준 = main 머리) · last.blob(변화 판정 = 원장 내용) · last.canon(변화 판정 = 골 정본 내용 · r737).
    한 칸이라도 못 쓰면 셋 다 그대로(r656)."""
    sha_f, blob_f = state / "last.sha", state / "last.blob"
    canon_f = state / "last.canon"
    old = {f: (f.read_text(encoding="utf-8") if f.is_file() else None) for f in (sha_f, blob_f, canon_f)}
    try:
        sha_f.write_text(cur + "\n", encoding="utf-8")
        if blob:
            blob_f.write_text(blob + "\n", encoding="utf-8")
        if canon:
            canon_f.write_text(canon + "\n", encoding="utf-8")
    except OSError:
        for f, text in old.items():
            f.unlink() if text is None else f.write_text(text, encoding="utf-8")
        raise


def zero_change_line(now, last: dict, warn: str) -> str:
    """r809 — 변화 0 반복 줄. 받기 실패(warn)면 «변화 없음» 이 아니라 «판정 불가» 머리 줄(낡은 판을 «변화 0» 으로 읽지 않게)."""
    tail = f"지도 {last.get('link') or last.get('map_at') or '없음'}"  # r847 r4: 지도 기록 전 첫 실패도 줄을 낸다(KeyError 0)
    return f"[뉴스 {now:%H:%M}] 판정 불가 — {warn} · {tail}" if warn else f"[뉴스 {now:%H:%M}] 변화 없음 · {tail}"


def tick(root: Path, state: Path, repo: Path, rel: str, news: Path, base: str, cur: str) -> tuple[int, str]:
    """뉴스 틱 HTML 경로 — (rc, 정지 감시용 사유). r847 r4: 상태 파일(fetch-last) 쓰기 실패(FT_NEWS_STATE_ERROR) = rc 1 + 그 사유(launchd 종료 코드로 보이게 · 조용한 rc0 0)."""
    try:
        rc, why = _tick(root, state, repo, rel, news, base, cur)
    except Exception as e:  # noqa: BLE001 — r907 r4: 어떤 예외든 «전파하지 않는다» → 부른 쪽(ft_news_ledger.run)이 정지 감시(check_stale)를 건너뛰지 않는다(ERROR 1줄 + rc 1)
        tb = traceback.extract_tb(e.__traceback__)[-1]
        LOG.error("뉴스 틱 예외 — 게시 중단(정지 감시는 계속): %s: %s (%s:%s)", type(e).__name__, e, Path(tb.filename).name, tb.lineno)
        return 1, f"뉴스 틱 예외 {type(e).__name__}"
    state_err = os.environ.get("FT_NEWS_STATE_ERROR", "")
    return (1, state_err) if state_err else (rc, why)


def _load_last(hs: Path) -> dict:
    """지도 상태(html.json) 읽기 — 없음 = 첫 판 · 읽기 실패·깨진 JSON·dict 아님 = {} · at/map_at/fail_at 이 문자열 아님 = 그 칸 버림. 전부 «마지막 게시 모름» = 게시 가능 + WARN 1줄 · 예외 0(r907 r4)."""
    if not hs.is_file():
        return {}
    try:
        data = json.loads(hs.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        LOG.warning("지도 상태 파일 못 읽음 — 마지막 지도 게시 모름 · 지금 게시 가능: %s (%s)", hs, e)
        return {}
    if not isinstance(data, dict):
        LOG.warning("지도 상태 파일이 객체가 아님(%s) — 마지막 지도 게시 모름 · 지금 게시 가능: %s", type(data).__name__, hs)
        return {}
    for k in ("at", "map_at", "fail_at"):
        if k in data and not isinstance(data[k], str):
            LOG.warning("지도 상태 %s 이 문자열이 아님(%r) — 그 칸 버림 · 마지막 지도 게시 모름", k, data[k])
            del data[k]
    return data


def _tick(root: Path, state: Path, repo: Path, rel: str, news: Path, base: str, cur: str) -> tuple[int, str]:
    """«바뀌었나» = 원장 경로의 «기계 채움이 아닌» 마지막 커밋 sha(r907 r4 · 글자 파싱 0) · 기준선 두 칸은 지도 글이 올라갔을 때만 옮긴다."""
    from ft_news_post import news_now
    from ft_news_publish import publish_line, retry_attach
    now, hs = news_now(), state / "html.json"
    last, stamp = _load_last(hs), f"{now:%Y-%m-%d %H:%M}"
    since = lambda k, required=True: _since(last, k, now, required)  # noqa: E731  r6 — 기본 required=True · fail_at 만 «없어도 정상»
    warn = os.environ.get("FT_LEDGER_SYNC_ERROR", "")  # r503·r809 — 원장 ref 받기 실패 사유
    if warn:  # r907 r2 — 판정 불가 = 게시 0(오빠 13:5x «이런 상태면 발행하지 마라 토큰 낭비») · ERROR 1줄 = 구간 첫 틱 만 · rc 1(launchd 종료 코드 → check_stale 정지 경보)
        if os.environ.get("FT_LEDGER_SYNC_REPEAT") == "1":  # 이 구간 경고는 이미 나감 — 게시 0 · 로그 0(오래 가면 check_stale 정지 경보 1통)
            LOG.info("원장 ref fetch 실패 구간 계속 — 게시 0")
            return 1, "원장 ref fetch 실패 계속"
        from ft_news_ledger import mark_fail_announced
        LOG.error("원장 ref 받기 실패 — 판정 불가 · 게시 0: %s", warn)  # 이 구간 1줄(다음 틱 0)
        mark_fail_announced()  # 이 구간 1통은 냈다(다음 틱 ERROR 0 · 게시 0 그대로)
        return 1, "원장 ref fetch 실패"
    retry_attach(now)  # r847 r5 — 받기 실패 틱 = 첨부 재시도 0(게시 0) · 대기 기록은 남아 회복 틱에 이어서
    if since("fail_at", required=False) < timedelta(minutes=int(os.environ.get("FT_NEWS_RETRY_MIN", "5"))):
        return 1, "지도 만들기 실패(재시도 대기)"
    stale = os.environ.get("FT_LEDGER_STALE_HEAD", "")  # r907 — 받기 실패지만 직전 판이 나이 상한 안: 그 판으로 정상 경로 + 머리 맨 앞 경고 구
    if stale and stale not in os.environ.get("FT_NEWS_HEAD", ""):
        os.environ["FT_NEWS_HEAD"] = f"{stale} · {os.environ.get('FT_NEWS_HEAD') or '팀 지도'}"
    if not stale:  # r907 ⓔ — 낡은 ref 위 원장 커밋 0 · 받기 회복 틱에 다시
        cur = ledger_fill(root, repo, rel, cur)  # r851 — 표 세 개 기계 채움(변화 있을 때만 커밋)
    if (fresh := ledger_fresh(root, repo, rel, cur)) and fresh not in os.environ.get("FT_NEWS_HEAD", ""):
        os.environ["FT_NEWS_HEAD"] = f"{os.environ.get('FT_NEWS_HEAD') or '팀 지도'} · {fresh}"
    blob, blob_f = _human_key(repo, rel, cur), state / "last.blob"  # last.blob = 판정 키 저장 칸(r907 r4 부터 값 = 사람 커밋 sha · 옛 블롭 값이면 첫 틱 «바뀜» 1회 = 수용)
    saved_blob = blob_f.read_text(encoding="utf-8").strip() if blob_f.is_file() else ""
    canon, canon_f = _canon_sha(), state / "last.canon"
    saved_canon = canon_f.read_text(encoding="utf-8").strip() if canon_f.is_file() else ""
    changed = blob != saved_blob if blob else True  # r656 — 판정 = 원장 키(r907 r5: 키 = 채움 아닌 마지막 커밋 · 키 모름 = base==cur 여도 항상 «바뀜» = 게시 후보 · 최소 간격이 상한)
    changed = changed or (canon != saved_canon if canon else False)  # r737 — 정본만 바뀐 커밋도 지도를 다시 낸다(옛 상태 = 칸 없음 → 첫 판 1회 재발행)
    if not changed and last.get("map_at", "")[:10] == stamp[:10]:  # 변화 0(원장 내용 그대로) · 오늘 지도 있음 = 적정한 반복 한 줄만
        if since("at") < timedelta(minutes=int(os.environ.get("FT_NEWS_REPEAT_MIN", "30"))):
            return 0, "원장 커밋 0"
        rc = publish_line(zero_change_line(now, last, warn) + "".join(f" · {x}" for x in (fresh, stale) if x), now)  # warn = "" (받기 실패는 위에서 끝남 · r847 r4) · r907 경고 구 유지
        if rc == 0:
            _save(hs, {**last, "at": stamp})
        return rc, "원장 커밋 0"
    if not _gap_ok(last, now):  # r907 r2·r3 — 게시 최소 간격(그 안의 변화는 다음 틱으로) · 상태가 깨짐/미래 = «모름» = 게시 가능(예외 0)
        LOG.info("지도 게시 최소 간격 안 — 다음 틱으로: 지도 %s", last.get("map_at") or "없음")
        return 0, "게시 간격 안"
    try:
        html_p, sum_p = run_files(build(root, repo, rel, base, cur, now), news, now)
    except (NewsHtmlError, RuntimeError, OSError, ValueError, KeyError) as e:
        LOG.error("지도 만들기 실패 — 발행 0: %s", e)
        LOG.info("직전 판 유지 %s(%s)", last.get("map_at") or "없음", last.get("link") or "링크 없음")  # r563 — 실패 틱마다 1줄(r510 지연 글은 3틱 연속)
        _save(hs, {**last, "fail_at": stamp})
        _delay_fail(state, now, f"지도 만들기 실패 — 발행 0: {e}", last)
        return 1, "지도 만들기 실패"
    rc, got = publish_files(html_p, sum_p, now)
    if got is not None:  # 글이 올라갔다(미첨부 rc3 포함) — 기준선 전진
        _delay_clear(state, now, last)
        _save(hs, {"at": stamp, "map_at": stamp, "ts": got.get("ts"), "link": got.get("permalink")})
        state.mkdir(parents=True, exist_ok=True)
        _save_base(state, cur, blob, canon)  # 세 칸 같이 전진(마지막 main 머리 · 원장 블롭 · 정본 내용)
    elif rc:
        _save(hs, {**last, "fail_at": stamp})
    return rc, (f"게시 실패 rc={rc}" if rc else "지도 발행")


def _ledger_args() -> tuple[Path, Path, str, str, str]:
    """(루트, 원장 리포, 원장 경로, 기준선, 지금 커밋) — 뉴스 틱과 같은 풀이 · r563: 판은 사본 체크아웃 HEAD 아니라 origin/main ref(fetch 만 5분 지나면 1회)."""
    import ft_board_env as env
    from ft_goal_ledger import live_root
    from ft_news_ledger import fetch_if_stale, news_cur, planner_ledger_rel
    root = env.ft_root()
    repo = Path(os.environ.get("FT_LEDGER_REPO") or live_root(RuntimeError, root))
    fetch_if_stale(repo)  # r563 — 체크아웃 전진 0 · ref 만 최신(실패는 ERROR 로그 · 지금 ref 로 계속)
    rel = os.environ.get("FT_LEDGER_PATH") or planner_ledger_rel(repo)
    base_f = root / ".fable-team" / "state" / "news-ledger" / "last.sha"
    return root, repo, rel, base_f.read_text(encoding="utf-8").strip() if base_f.exists() else "", news_cur(repo, rel, ref_mode=True)


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
