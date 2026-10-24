"""ft_news_ledger — 오빠 원장(PLAN-oppa-ledger.md) 한 파일에서 «마지막 발행 뒤 바뀐 줄만» 뉴스 1개 만들어 발행 (R125 · 판정 1437). 쓰는 쪽은 ft-news-ledger.sh · ft-tick.sh.

줄 키 = 칸(`## N.`) · 소제목(`### `) · 표 첫 칸(순번 칸 제외)/목록·문단 줄 전체. 뉴스는 «커밋된» 판 둘(기준선 ↔ 지금)의 차이만 — 미커밋 수정·안 바뀐 줄은 싣지 않는다.
기준선(state/news-ledger/last.sha)은 «전 판» 발행 성공(rc 0) 뒤에만 옮긴다(3500B 넘으면 칸 경계로 n/N 판 · ft_news_ledger_text.py) · 첫 실행 = 기준선만. 원장 문장 그대로라 Haiku 0.
알림 = «(오빠)» 판정인데 원장 본문에 번호가 없으면 planner 에 한 틱 1통 묶음(뉴스 본문 0 · ft_news_ledger_notify.py).
FT_NEWS_MODE=html(r478) = 판 대신 ft_news_html.tick(팀 지도 HTML 첨부 + 한 줄 · 변화 0 은 FT_NEWS_REPEAT_MIN 간격 한 줄) · 그 밖의 값은 이 경로 그대로.
env: FT_ROOT · FT_LEDGER_REPO(기본 <루트>/.fable-team/LIVE_ROOT 1행 — 없으면 ERROR · R382) · FT_LEDGER_PATH(기본 그 리포 TEAMS.md 의 planner 폴더/PLAN-oppa-ledger.md) — 원장 정본 = 이 두 값 «한 곳»: sha·경로·뉴스 폴더(<루트>/<원장 폴더>/news)·골 표 원장 모두 여기서 푼다 · 기준선 판에 같은 경로가 없으면 ERROR(R458) · FT_NEWS_DIR · FT_NEWS_PUBLISH(기본 ft-news-publish.sh) · FT_NEWS_NOW("YYYY-MM-DD HH:MM") · FT_MBOX
"""
import logging
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ft_board_env as env  # noqa: E402
from ft_goal_ledger import live_root  # noqa: E402
from ft_news_ledger_notify import notify  # noqa: E402
from ft_news_digest import maybe_send  # noqa: E402
from ft_news_ledger_text import MAX_BYTES, Lines, build_blocks, render_parts  # noqa: E402,F401  (MAX_BYTES 는 시험이 발행 도구 한도와 대조)
from ft_news_post import goal_gate, is_draft, news_now, pending_now, procs_block, publish, teams_block  # noqa: E402
from ft_news_status import interval_s, last_status, mark_status, status_or_none  # noqa: E402
from ft_news_watch import check_stale, locked  # noqa: E402
from ft_team_lib import TeamPathError, team_rel  # noqa: E402

LOG = logging.getLogger("ft_news_ledger")
HERE = Path(__file__).resolve().parent
SECTION = re.compile(r"^##\s+(\d+(?:-\d+)?)\.\s*(.*)")
NOW_LINE = re.compile(r"^\*\*지금 전체 상태\*\*\s*:\s*(.+)")
VERDICT_ROW = re.compile(r"^\|\s*(\d+)\s*\|\s*(\d{1,2}):([\dx]{2})\s*\|\s*(.*?)\s*\|?\s*$")
SKIP_KEY_HEADERS = {"순번"}


def _cells(ln: str) -> list[str]:
    return [c.strip() for c in ln.strip().strip("|").split("|")]


def parse_ledger(text: str) -> Lines:
    """{(칸, 소제목, 줄 키): 값 칸들}. 표 = 순번 칸을 뺀 첫 칸이 키 · 목록·문단 = 줄 전체가 키(값 비어 있음)."""
    out: Lines = {}
    cell, sub, header = "", "", None
    rows = text.splitlines()
    for i, ln in enumerate(rows):
        if m := SECTION.match(ln):
            cell, sub, header = m[1], "", None
        elif ln.startswith("###"):
            sub, header = ln.lstrip("# ").strip(), None
        elif not cell:
            if m := NOW_LINE.match(ln):
                out[("now", "", "지금 전체 상태")] = (m[1].strip(),)
        elif ln.startswith("|"):
            nxt = rows[i + 1] if i + 1 < len(rows) else ""
            if re.match(r"^\|[\s:|-]+\|$", nxt.strip()) and header is None:
                header = _cells(ln)
            elif not re.match(r"^\|[\s:|-]+\|$", ln.strip()):
                _row(out, cell, sub, header or [], _cells(ln))
        elif ln.strip() and not ln.startswith((">", "#", "---")):
            header = None
            out.setdefault((cell, sub, re.sub(r"^[-*]\s+", "", ln.strip())), ())
    return out


def _row(out: Lines, cell: str, sub: str, header: list[str], cols: list[str]) -> None:
    ki = next((i for i, h in enumerate(header) if h not in SKIP_KEY_HEADERS), 0)
    key = cols[ki] if ki < len(cols) and cols[ki] else "|".join(cols)
    while (cell, sub, key) in out:
        key += " "  # 같은 소제목 안에서 키가 겹치면 공백으로 구분(순서대로 짝지어진다)
    out[(cell, sub, key)] = tuple(c for i, c in enumerate(cols) if i != ki and c)


def _join(vals: tuple[str, ...]) -> str:
    return " · ".join(vals)


def diff_ledger(old: Lines, new: Lines) -> list[tuple[str, str]]:
    """[(새로|바뀜|빠짐, 한 줄)] — 새 판 순서대로 새로·바뀜, 이어서 빠짐. 안 바뀐 줄은 없다."""
    out = []
    for k, v in new.items():
        if k not in old:
            out.append(("새로", f"{k[2].strip()} — {_join(v)}" if v else k[2].strip()))
        elif old[k] != v:
            out.append(("바뀜", f"{k[2].strip()}: {_join(old[k])} → {_join(v)}"))
    out += [("빠짐", f"{k[2].strip()} (원장에서 빠짐)") for k in old if k not in new]
    return out


def _git(repo: Path, *a: str) -> str:
    done = subprocess.run(["git", "-C", str(repo), *a], capture_output=True, text=True, encoding="utf-8", check=False)
    if done.returncode != 0:
        raise RuntimeError(f"git {a[0]} 실패: {done.stderr.strip()[:200]}")
    return done.stdout


def run() -> int:
    root = env.ft_root()
    state = root / ".fable-team" / "state" / "news-ledger"
    with locked(state) as got:
        if not got:
            LOG.info("다른 뉴스 실행이 일하는 중 — 건너뜀")
            return 0
        rc, why = _run(root, state)
        if interval_s() > 0:
            check_stale(root, state, news_now(), why)
        return rc


def stale_only() -> int:
    """게시 방아쇠와 독립된 정지 감시(H1) — v65 틱이 FT_TICK_NEWS_LEDGER=0 이어도 매 루프 부른다 · 게시 0."""
    root = env.ft_root()
    state = root / ".fable-team" / "state" / "news-ledger"
    with locked(state) as got:
        if got and interval_s() > 0:
            check_stale(root, state, news_now(), "원장 커밋 0 또는 뉴스 방아쇠 정지")
    return 0


def stall_cell(root: Path) -> str:
    """뉴스 첫 줄의 `stall=N` 칸(R320b) = ft-stall-scan 이 남긴 stall-scan.log «마지막 줄»(요약)의 `stall=N a=.. b=.. c=.. d=..`. 로그 없음·읽기 실패 = 칸 없음(뉴스는 막지 않는다)."""
    try:
        last = (root / ".fable-team" / "state" / "stall-scan.log").read_text(encoding="utf-8").splitlines()[-1]
    except (OSError, IndexError):
        return ""
    return " ".join(last.split()[:5]) if last.startswith("stall=") else ""


def reclaim_cell(root: Path) -> str:
    """뉴스 첫 줄의 `reclaimed=N` 칸(R332) = ft-resource-reclaim --preventive 가 reclaim.log 에 남긴 «마지막 `PREVENTIVE reclaimed=N …` 요약줄»의 N(꼬리 64KB 만 읽음). 로그 없음·요약 없음·경합 줄(`skipped=lock`) = 칸 생략이 아니라 `reclaimed=미관측` 명시(0 으로 읽히지 않게 · DA⑥ H3) · 뉴스는 막지 않는다."""
    try:
        with (root / ".fable-team" / "state" / "reclaim.log").open("rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 65536))
            tail = f.read().decode("utf-8", "replace")
    except OSError:
        return "reclaimed=미관측"
    for line in reversed(tail.splitlines()):
        hit = re.match(r"PREVENTIVE reclaimed=(\d+)\b", line)
        if hit:
            return f"reclaimed={hit.group(1)}"
    return "reclaimed=미관측"


def decision_line(root: Path) -> str:
    """뉴스 첫 줄(R214 · 판정 1804) = ft-decision-count.sh 한 줄 + stall 칸(R320b) + reclaimed 칸(R332). planner 좌석표가 없는 루트(팀 밖·시험)는 줄 없음 · 도구 실패는 ERROR 로그(뉴스는 막지 않는다)."""
    if not (root / ".fable-team" / "seats-planner.json").is_file():
        return ""
    text = ""
    try:
        done = subprocess.run(["bash", str(HERE / "ft-decision-count.sh")], capture_output=True, text=True, timeout=7, env={**os.environ, "FT_ROOT": str(root)})
        if done.returncode != 0:
            LOG.error("결정 대기열 줄 건너뜀: rc=%s %s", done.returncode, done.stderr.strip()[:120])
        else:
            text = done.stdout.strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        LOG.error("결정 대기열 줄 건너뜀: %s", e)
    return " · ".join(x for x in (text, stall_cell(root), reclaim_cell(root)) if x)


def planner_ledger_rel(repo: Path) -> str:
    """원장의 git 상대 경로 — 명단 꼴이 리포 밖(꼴3 $FT_HARNESS_ROOT)이면 git show 대상이 아니므로 명시 오류."""
    folder = team_rel("planner", repo)
    if not folder.startswith("design/"):
        raise TeamPathError(f"ERROR planner 폴더가 리포 밖 꼴이라 원장을 git 상대 경로로 못 만든다: {folder} (FT_LEDGER_PATH 로 지정)")
    return folder + "PLAN-oppa-ledger.md"


def news_dir(root: Path, rel: str) -> Path:
    """뉴스 폴더 = <루트>/<원장 경로의 폴더>/news — 원장 정본(리포+경로) 한 값에서 푼다(R458 · 루트 체크아웃의 옛 명단 0) · 없으면 RuntimeError(폴백 0)."""
    news = root / Path(rel).parent / "news"
    if not news.is_dir():
        raise RuntimeError(f"뉴스 폴더 없음 {news}(원장 경로 {rel} 기준 · FT_NEWS_DIR 로 지정 가능)")
    return news


def check_base(repo: Path, sha: str, rel: str) -> None:
    """기준선 sha 판도 원장 정본(같은 리포·같은 경로)이어야 한다(R458) — 다른 리포 판·옛 경로 판이면 RuntimeError(경로 후퇴·쌍둥이 읽기 0 · #0 RULE)."""
    if subprocess.run(["git", "-C", str(repo), "cat-file", "-e", f"{sha}:{rel}"], capture_output=True, check=False).returncode != 0:
        raise RuntimeError(f"기준선 {sha[:10]} 판에 원장 정본 {rel} 이 없다(원장 리포 {repo}) — 기준선이 다른 리포·옛 경로 판이다 · "
                           "원장을 이 경로 판으로 커밋한 뒤 기준선(state/news-ledger/last.sha)을 그 판으로 다시 잡아야 발행된다(옛 경로 후퇴 0)")


def _stamp_file() -> Path:
    """동기화 성공 기록 1줄(에포크 초) — 기본 <루트>/.fable-team/state/news-ledger/last-sync.ts."""
    if os.environ.get("FT_LEDGER_SYNC_STAMP"):
        return Path(os.environ["FT_LEDGER_SYNC_STAMP"])
    return env.ft_root() / ".fable-team" / "state" / "news-ledger" / "last-sync.ts"


def _recent_sync(now: float, max_s: float) -> bool:
    """마지막 성공이 max_s 안인가 — 기록 없음·깨짐 = False(지금 실행)."""
    try:
        return now - float(_stamp_file().read_text(encoding="utf-8").strip()) < max_s
    except (OSError, ValueError):
        return False


def _mark_sync(now: float) -> None:
    try:
        f = _stamp_file()
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(f"{now:.0f}\n", encoding="utf-8")
    except OSError as e:
        LOG.warning("동기화 시각 기록 못 씀 — 다음 틱에 또 시도: %s", e)


def sync_repo() -> str:
    """r503 — env FT_LEDGER_REPO 로 «명시된» 원장 사본만 ft-ledger-repo-sync.sh(FT_LEDGER_SYNC 로 대역)로 origin/main 전진 · 기본 LIVE_ROOT(공용 루트 체크아웃)는 옮기지 않는다.
    r563 — 마지막 성공(FT_LEDGER_SYNC_MIN 기본 120초) 안이면 건너뜀 + INFO 1줄(매분 fetch 가 부하를 더하던 것).
    같은 틱 1회(FT_LEDGER_SYNCED=1 · 자식 프로세스도 물려받음). 반환 = 뉴스 머리 줄(정상·건너뜀 = "") — 실패면 ERROR 로그 + FT_LEDGER_SYNC_ERROR 에 같은 줄 · 발행은 지금 판으로 계속(조용한 낡음 0)."""
    repo = os.environ.get("FT_LEDGER_REPO")
    if not repo or os.environ.get("FT_LEDGER_SYNCED") == "1":
        return os.environ.get("FT_LEDGER_SYNC_ERROR", "")
    os.environ["FT_LEDGER_SYNCED"] = "1"
    now = time.time()
    if _recent_sync(now, float(os.environ.get("FT_LEDGER_SYNC_MIN", "120"))):
        LOG.info("원장 사본 동기화 건너뜀 — 마지막 성공 2분 안(%s)", _stamp_file())
        return os.environ.get("FT_LEDGER_SYNC_ERROR", "")
    try:
        done = subprocess.run(["bash", os.environ.get("FT_LEDGER_SYNC") or str(HERE / "ft-ledger-repo-sync.sh"), repo], capture_output=True, text=True, timeout=FETCH_BUDGET_S)  # r847: 스크립트 = ls-remote 7 + fetch 30 + 재시도 — 총 마감 70초
        lines = (done.stdout.strip() or done.stderr.strip()).splitlines()
        line, rc = (lines[-1] if lines else f"rc={done.returncode} 출력 없음"), done.returncode
    except (OSError, subprocess.TimeoutExpired) as e:
        line, rc = f"ERROR ledger 사본 sync 실행 실패: {e}", 1
    if rc == 0:
        LOG.info("%s", line)
        _mark_sync(now)
        os.environ.pop("FT_LEDGER_SYNC_ERROR", None)
        return ""
    LOG.error("원장 사본 갱신 안 됨 rc=%s: %s", rc, line)
    os.environ["FT_LEDGER_SYNC_ERROR"] = f"원장 사본 갱신 안 됨 — {line[:160]}"
    return os.environ["FT_LEDGER_SYNC_ERROR"]


FETCH_TIMEOUT_S = 30.0  # r847 — 이 경로(뉴스 원장 ref) 시도당 상한(오빠 «뉴스는 30초로 상향» · 하드 룰 12 «크기 아는 배치» 70초 천장 안 · 공용 fm_t7 7초는 그대로)
FETCH_BUDGET_S = 70.0  # r569 — 재시도까지 합친 마감(전역 하드 룰 12 · env 로 크게 줘도 여기서 자름)
LS_REMOTE_TIMEOUT_S = 7.0  # r847 — 원격 main sha 묻기·로컬 ref 조회(7초 룰)
KILL_GRACE_S = 1.0  # r847 — 시간 초과 때 TERM → KILL 사이 유예
STAGE_SLACK_S = 0.5  # r847 r2 — 단계마다 프로세스 기동·KILL 뒤 회수 몫(유예까지 빼도 총 마감을 넘던 71.0초 반례 · 0.25초 = 69.77초로 여유 부족)


def _attempt_timeout(spent: float, per: float | None = None) -> float:
    """r569 · r847 r2 — 이번 단계 상한 = min(단계 상한, 남은 마감 − TERM→KILL 유예 − 회수 여유) · ≤ 0 = 그 단계 시작 0.
    단계 상한 기본 = FT_NEWS_FETCH_TIMEOUT(30초) · 마감 = FT_NEWS_FETCH_BUDGET(70초 넘으면 70초)."""
    if per is None:
        per = float(os.environ.get("FT_NEWS_FETCH_TIMEOUT", str(FETCH_TIMEOUT_S)))
    budget = min(float(os.environ.get("FT_NEWS_FETCH_BUDGET", str(FETCH_BUDGET_S))), FETCH_BUDGET_S)
    return min(per, budget - spent - KILL_GRACE_S - STAGE_SLACK_S)


def _fetch_stamp_file() -> Path:
    """r706 — 원장 ref fetch 성공 시각 1줄(에포크 초 · fetch 성공 때만 씀) — 기본 <루트>/.fable-team/state/news-ledger/fetch.stamp.
    옛 판은 git FETCH_HEAD(«<sha>\\t\\tbranch …») 를 숫자로 읽어 늘 ValueError → 매분 fetch(10-22 시간 초과 351줄)."""
    if os.environ.get("FT_NEWS_FETCH_STAMP"):
        return Path(os.environ["FT_NEWS_FETCH_STAMP"])
    return env.ft_root() / ".fable-team" / "state" / "news-ledger" / "fetch.stamp"


def _last_fetch() -> float | None:
    """마지막 fetch 성공 시각 — 표식 없음 = None(지금 fetch) · 깨짐 = None + WARN 1줄(지금 fetch)."""
    f = _fetch_stamp_file()
    try:
        raw = f.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return None
    except OSError as e:
        LOG.warning("fetch 표식 못 읽음 — 지금 fetch: %s (%s)", f, e)
        return None
    try:
        return float(raw)
    except ValueError:
        LOG.warning("fetch 표식 깨짐 — 지금 fetch: %s 내용=%r", f, raw[:40])
        return None


def _mark_fetch(now: float) -> None:
    try:
        f = _fetch_stamp_file()
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(f"{now:.0f}\n", encoding="utf-8")
    except OSError as e:
        LOG.warning("fetch 표식 못 씀 — 다음 틱에 또 fetch: %s", e)


def _fetch_age(last: float | None) -> str:
    """r569 — 그 ref 를 «몇 분 전에 받은 판» 인지(r706: 전용 표식 = 마지막 fetch 성공 시각 · 모르면 «받은 시각 모름»)."""
    return "받은 시각 모름" if last is None else f"{int((time.time() - last) // 60)}분 전 받은 판"


def _run_capped(cmd: list[str], cap: float) -> tuple[int | None, str, str]:
    """r847 — (rc, stdout, stderr — 날것 · 재시도 판정이 «0바이트» 를 보도록) · cap 초를 넘으면 rc None — 프로세스 묶음 전체에 TERM → 1초 뒤 KILL(손자 git·TERM 무시 자식까지 · 남은 자식 0)."""
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        out, err = p.communicate(timeout=cap)
        return p.returncode, out, err
    except subprocess.TimeoutExpired:
        for sig, grace in ((signal.SIGTERM, KILL_GRACE_S), (signal.SIGKILL, 0.0)):
            try:
                os.killpg(p.pid, sig)
            except (ProcessLookupError, PermissionError):  # 묶음이 이미 끝남 · macOS = 좀비만 남은 묶음에 EPERM
                pass
            time.sleep(grace)
        out, err = p.communicate()
        return None, out, err


def _first(out: str, err: str) -> str:
    return (err.strip() or out.strip()).split("\n")[0]


def _git_capped(repo: Path, t0: float, *a: str) -> tuple[int | None, str, str]:
    """r847 r2 — 묻기 단계(ls-remote·로컬 ref) = min(7초, 남은 마감 − 유예) 안에서만 · 남은 시간 없음 = 시작 0(rc None)."""
    cap = _attempt_timeout(time.monotonic() - t0, LS_REMOTE_TIMEOUT_S)
    return _run_capped(["git", "-C", str(repo), *a], cap) if cap > 0 else (None, "", "총 마감 안에 시작 못 함")


LEDGER_REFSPEC = "+refs/heads/ledger/*:refs/remotes/origin/ledger/*"  # r851 r3 ③ — 원장 사본 브랜치(ledger/ 만 · 원격에 없어도 실패 0)


def _remote_same(repo: Path, t0: float, br: str) -> bool:
    """r847 — 원격 sha(`ls-remote` 7초) == 사본 원격 추적 ref 이면 True(fetch 0). 묻기 실패·sha 다름·origin/main 없음 = False(fetch 로 진행 · 판정 불가 아님) + 로그 1줄.
    r851 r3 ③ — 두 ref(main · 원장 사본 브랜치 br) 를 함께 비교(사본 브랜치만 전진해도 받는다 · 원격에 없음 = 로컬에도 없어야 같음)."""
    rc, out, err = _git_capped(repo, t0, "ls-remote", "origin", "refs/heads/main", f"refs/heads/{br}")
    rows = dict(reversed(r.split("\t")) for r in out.splitlines() if r.count("\t") == 1) if rc == 0 else {}
    remote = rows.get("refs/heads/main", "")
    if not remote:
        LOG.warning("ls-remote 실패 — fetch 로 진행: rc=%s %s", rc, _first(out, err)[:160] or "출력 없음")
        return False
    local = []
    for ref in ("refs/remotes/origin/main", f"refs/remotes/origin/{br}"):
        rc, sha, _err = _git_capped(repo, t0, "rev-parse", "--verify", "-q", ref)
        if rc not in (0, 1):
            return False
        local.append(sha.strip())
    if [remote, rows.get(f"refs/heads/{br}", "")] != local:
        return False
    LOG.info("fetch 생략(ls-remote 같음) origin/main=%s %s=%s", local[0][:10], br, local[1][:10] or "없음")
    return True


def _fetch_last_file() -> Path:
    """r847 r3 — 원장 ref 받기 «마지막 결과» 1칸(ok|fail) — 기본 <루트>/.fable-team/state/news-ledger/fetch-last.
    경고 = 실패 구간당 1통(성공→실패 전이) — 실패 글자(사유·pid·출력)는 비교하지 않는다(r2 DA: 출력 해시 키 = pid 바뀌는 같은 장애가 매 틱 새 경고)."""
    if os.environ.get("FT_NEWS_FETCH_LAST"):
        return Path(os.environ["FT_NEWS_FETCH_LAST"])
    return env.ft_root() / ".fable-team" / "state" / "news-ledger" / "fetch-last"


def _read_last() -> str:
    """마지막 결과 — 표식 없음 = ""(성공 쪽 · 다음 실패에 경고) · 못 읽음(권한 등) = "" + ERROR(알 수 없음 = 경고 냄 쪽 · 그 틱 원자 쓰기가 파일을 새로 만들어 다음 틱부터 정상 · r847 r4)."""
    try:
        return _fetch_last_file().read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return ""
    except OSError as e:
        LOG.error("fetch 마지막 결과 못 읽음 — 알 수 없음으로 보고 경고 냄: %s", e)
        return ""


def _write_last(value: str) -> None:
    """r847 r4 — 원자 쓰기: 같은 폴더 임시 파일(fetch-last.tmp.<pid>)에 쓰고 os.replace — 파일 권한(000·444)이 상태를 굳히지 않는다(폴더만 쓰이면 성공).
    폴더도 못 쓰면(권한·디스크) ERROR + FT_NEWS_STATE_ERROR(ft_news_html.tick 이 rc 1 로 돌려줌 · 그때 구간당 1통은 보장 안 함 — 보이게만)."""
    f = _fetch_last_file()
    tmp = f.parent / f"{f.name}.tmp.{os.getpid()}"
    try:
        f.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_text(value + "\n", encoding="utf-8")
        os.replace(tmp, f)
    except OSError as e:
        try:
            tmp.unlink(missing_ok=True)
        except OSError:
            pass
        why = f"상태 파일 {f.name} 쓰기 실패: {e}"
        LOG.error("%s", why)
        os.environ["FT_NEWS_STATE_ERROR"] = why


def fail_announced() -> bool:
    """이 실패 구간의 경고를 이미 냈나 = 마지막 결과가 fail(경고가 실제 글로 나간 뒤에만 적힘)."""
    return _read_last() == "fail"


def mark_fail_announced() -> None:
    """뉴스가 이 틱의 실패 경고를 실제 글로 냈을 때만(ft_news_html.tick) fail 로 적는다 — 못 낸 경고(게시 실패)는 다음 틱에 다시."""
    _write_last("fail")


def _fetch_ok() -> str:
    """fetch 성공(또는 ls-remote 같음) — 표식 전진 · 마지막 결과 ok(다음 실패 = 새 구간 = 새 1통) · 머리 줄 경고 0."""
    _mark_fetch(time.time())  # r706: 성공 때만 전진 — 실패 뒤 낡은 ref 를 최신으로 보지 않는다
    _write_last("ok")
    os.environ.pop("FT_LEDGER_SYNC_REPEAT", None)
    return os.environ.pop("FT_LEDGER_SYNC_ERROR", "")


def fetch_if_stale(repo: Path) -> str:
    """r563 — 뉴스(HTML) 경로: 사본 «체크아웃 전진» 대신 origin/main ref 만 최신으로. 마지막 성공이 FT_NEWS_FETCH_MIN(300초) 안이면 건너뜀 ·
    r847: 그다음 `ls-remote`(7초) 원격 main·원장 사본 브랜치 == 원격 추적 ref 이면 fetch 0 · 아니면 `git fetch origin main <ledger/*>`(r851 r3 ③ · 시도당 30초 · TERM→1초 KILL ·
    재시도 1 = 첫 시도 출력 0 일 때만 · ls-remote 포함 총 마감 70초 · FT_LEDGER_FETCH 로 대역).
    실패 = 머리 줄에 «N분 전 받은 판»(발행은 지금 ref 로 계속 · 조용한 낡음 0) · 이 실패 구간 경고를 이미 냈으면 FT_LEDGER_SYNC_REPEAT=1(구간당 1통 · r3)."""
    os.environ.pop("FT_NEWS_STATE_ERROR", None)  # r847 r4 — 이 틱의 상태 쓰기 실패만 싣는다
    min_s = float(os.environ.get("FT_NEWS_FETCH_MIN", "300"))
    last = _last_fetch()
    if last is not None and -1 <= time.time() - last < min_s:  # 미래 시각(시계 뒤틀림) = 최신 아님 · r847: 1초 = 표식 «{:.0f}» 반올림 몫(같은 초에 쓴 표식이 미래로 읽히던 간헐 fetch)
        return os.environ.get("FT_LEDGER_SYNC_ERROR", "")
    t_start = time.monotonic()
    from ft_ledger_fill_src import FillError, branch
    try:
        br = branch()  # r851 r3 ① — ledger/ 밖 이름 = 입구 거절(받기 실패 갈래 · 판정 불가)
    except FillError as e:
        br, line = "", str(e)
    if br and _remote_same(repo, t_start, br):
        return _fetch_ok()
    script = os.environ.get("FT_LEDGER_FETCH")
    cmd = ["bash", script, str(repo)] if script else ["git", "-C", str(repo), "fetch", "--quiet", "origin", "main", LEDGER_REFSPEC]
    if br:
        line = ""
    for _ in range(2 if br else 0):
        left = _attempt_timeout(time.monotonic() - t_start)
        if left <= 0:
            line = f"fetch 실행 실패: 총 마감 {FETCH_BUDGET_S:.0f}초 안에 시도 못 함"
            break
        try:
            rc, out, err = _run_capped(cmd, left)
        except OSError as e:
            rc, out, err = 1, "", f"fetch 실행 실패: {e}"
        if rc == 0:
            return _fetch_ok()
        first = _first(out, err)
        line = first if rc is not None else f"fetch 실행 실패: 시도 상한 {left:.0f}초 초과{' · ' + first if first else ''}"
        if out or err:  # 출력(1바이트 이상)이 있는 실패 = 확정 실패 — 재시도 0(하드 룰 12 «첫 출력 전 실패» 만)
            break
    why = f"원장 ref fetch 실패 — {line[:160] or 'fetch 실패(출력 없음)'} · origin/main = {_fetch_age(last)}"
    os.environ["FT_LEDGER_SYNC_ERROR"] = why
    repeat = fail_announced()
    if repeat:
        LOG.warning("fetch 실패 구간 계속 — 경고는 이미 1통(머리·줄 생략 · 오래 가면 check_stale): %s", why)
    else:
        LOG.error("%s", why)
    os.environ["FT_LEDGER_SYNC_REPEAT"] = "1" if repeat else ""
    return why


def news_ref(repo: Path | None = None) -> str:
    """뉴스가 읽는 ref — 사본 체크아웃 HEAD 가 아니라 origin/main(다른 도구 fetch 로 이미 최신 · r563).
    r851 r2: 원장 사본 브랜치(origin/ledger/auto)가 main 을 품으면(앞섬) 그 브랜치 · 없거나 뒤처짐 = origin/main(읽는 ref 고르는 곳 = 여기 1곳 · FT_NEWS_MAIN_REF = 고정)."""
    if os.environ.get("FT_NEWS_MAIN_REF"):
        return os.environ["FT_NEWS_MAIN_REF"]
    if repo is None:
        return "origin/main"
    from ft_ledger_fill_src import read_ref
    return read_ref(repo)


def news_cur(repo: Path, rel: str, ref_mode: bool | None = None) -> str:
    """뉴스 판 = ref_mode(기본 = FT_NEWS_MODE=html)면 ref 커밋(사본 체크아웃 전진 0) · 아니면 옛 꼴(그 경로 마지막 커밋).
    «바뀌었나» 판정은 이 커밋이 아니라 원장 블롭(ledger_blob)이다(html 모드 · r656)."""
    if ref_mode is None:
        ref_mode = os.environ.get("FT_NEWS_MODE") == "html"
    if not ref_mode:
        return _git(repo, "log", "-1", "--format=%H", "--", rel).strip()
    ref = news_ref(repo)
    return _git(repo, "rev-parse", "--verify", f"{ref}^{{commit}}").strip()


def ledger_blob(repo: Path, rel: str, cur: str) -> str:
    """`<cur>:<원장>` 블롭 해시 — html 모드 «변화 판정» 의 기준(r656: 어느 팀 커밋만 와도 지도를 내던 결함). 없으면 RuntimeError."""
    return _git(repo, "rev-parse", "--verify", f"{cur}:{rel}").strip()


def _run(root: Path, state: Path) -> tuple[int, str]:
    html = os.environ.get("FT_NEWS_MODE") == "html"
    try:
        # r809 — 리포를 «받기 전» 에 정한다: html 이면 env 유무와 무관하게 그 리포를 받는다(옛 판 = env 없으면 받기 0 → 낡은 origin/main 을 «변화 없음» 으로 발행)
        repo = Path(os.environ.get("FT_LEDGER_REPO") or live_root(RuntimeError, root))
        sync_note = fetch_if_stale(repo) if html else sync_repo()
        # R383: planner 팀 폴더는 design/TEAMS.md 로(팀 이름 글자 0) — 원장 경로는 git 상대(꼴1·꼴2), 뉴스 폴더는 절대경로. 못 풀면 TeamPathError(RuntimeError) → 아래 «원장 읽기 실패»
        rel = os.environ.get("FT_LEDGER_PATH") or planner_ledger_rel(repo)
        news = Path(os.environ["FT_NEWS_DIR"]) if os.environ.get("FT_NEWS_DIR") else news_dir(root, rel)
        cur = news_cur(repo, rel)
        if not cur:
            raise RuntimeError(f"{rel} 가 커밋되지 않았다(뉴스는 커밋된 판만)")
        base_f = state / "last.sha"
        base = base_f.read_text(encoding="utf-8").strip() if base_f.exists() else ""
        if base and base != cur:
            check_base(repo, base, rel)
        try:
            notify(root, _git(repo, "show", f"{cur}:{rel}"), state)
        except Exception as e:  # 알림 실패가 뉴스를 막지 않는다
            LOG.error("알림 건너뜀: %s", e)
        if os.environ.get("FT_NEWS_MODE") == "html":  # r478 — 팀 지도 HTML + 한 줄(ft_news_html) · 모드 없음 = 옛 판 경로 그대로
            from ft_news_html import tick
            return tick(root, state, repo, rel, news, base, cur)
        status = status_or_none(root, news_now())
        why = "스냅샷 오래됨" if interval_s() > 0 and (status is None or status[0][1][0].startswith("(세션 상태 스냅샷")) else "원장 커밋 0"
        if base == cur:
            return _status_only(news, state, rel, cur, status, why) if interval_s() > 0 else (0, why)
        diff = diff_ledger(parse_ledger(_git(repo, "show", f"{base}:{rel}")), parse_ledger(new_text := _git(repo, "show", f"{cur}:{rel}"))) if base else []
        now = pending_now(state, base, cur) if diff else news_now()
        if diff and interval_s() > 0 and status is None:  # 필수 절을 못 만들면 게시·기준선 전진 0 — 재시도 가능(H2)
            return 1, why
        extra, new = (status[0],) if status else (), parse_ledger(new_text) if diff else {}
        lead = " · ".join(x for x in (sync_note, decision_line(root)) if x)
        parts = render_parts(now, new, diff, rel, extra, lead, goal_gate.goal_block(state.parent), teams_block() + procs_block()) if diff else []
    except (RuntimeError, OSError, ValueError) as e:
        LOG.error("원장 뉴스 실패: %s", e)
        return 1, "원장 읽기 실패"
    rc, posts = publish(news, state, parts, now, cur)
    if rc == 0 and parts and status and not is_draft():
        mark_status(state, status[1], now)
    if rc == 0 and parts and not is_draft():
        maybe_send(root, state, now, diff, build_blocks(new, diff, extra), status, len(parts), posts)
    return rc or (1 if interval_s() > 0 and status is None else 0), (f"게시 실패 rc={rc}" if rc else why)


def _status_only(news: Path, state: Path, rel: str, cur: str, status, why: str) -> tuple[int, str]:
    """원장 새 커밋이 없을 때 — 주기가 지났고 절 digest 가 마지막 발행과 다를 때만 그 절 1판(판정 1430 «바뀐 것만»)."""
    if status is None:
        return 1, why
    block, digest = status
    last = last_status(state)
    if last and (last[0] == digest or (news_now() - last[1]).total_seconds() < interval_s()):
        return 0, why
    now = pending_now(state, "status", digest)
    rc, posts = publish(news, state, render_parts(now, {}, [], rel, (block,), goal=goal_gate.goal_block(state.parent), teams=teams_block() + procs_block()), now, cur)
    if rc == 0 and not is_draft():
        mark_status(state, digest, now)
        maybe_send(env.ft_root(), state, now, [], build_blocks({}, [], (block,)), status, 1, posts)
    return rc, (f"게시 실패 rc={rc}" if rc else why)


def main(argv: list[str]) -> int:
    return {(): run, ("run",): run, ("stale",): stale_only}.get(tuple(argv[:1]), lambda: 2)()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    raise SystemExit(main(sys.argv[1:]))
