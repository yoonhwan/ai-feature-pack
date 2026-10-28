#!/usr/bin/env python3
"""ft_news_desk — 뉴스 틱마다 desk 세션 화면에 붙일 «전문» 3블록을 만들고, 바뀐 틱에만 desk 로 relay 1통 (r1055 · Issue #4004).

블록 순서(Q1=ⓐ · 오빠 승인 본보기 그대로) = ①골 표(원장 «메인 골» 표 · 골 칸 글자 그대로) ②팀별 표(명단 TEAMS.md · ft-card-flow 숫자 ·
명부 열린 좌석 · 보드 스냅샷 «지금 하는 일») ③오빠 손(h 목록 실행 대기 · 답 대기 질문). 그 밖 블록 0.
못 읽은 재료는 그 블록만 «확인 불가» 1줄로 바꾸고 다른 블록은 그대로 내보낸다(빈 표·0 금지 · R2).
digest = 머리의 «분»을 지운 본문 sha1 — 같은 내용이면 relay 0(판정 1430 «바뀐 것만» · R4).
desk 좌석 = 명부(seats-planner.json) `_desk` 의 현역 — 못 찾으면 rc≠0 «판정 불가» 1줄 · 옛 이름으로 보내기 0(R5).
env: FT_ROOT · FT_LEDGER_REPO · FT_LEDGER_PATH · FT_DESK_LEDGER_FILE(픽스처 = 파일 직접) · FT_DESK_LEDGER_REF(기본 origin/main)
     FT_DESK_LEDGER_TIMEOUT·FT_DESK_CARD_TIMEOUT·FT_DESK_TOOL_TIMEOUT(각 7초 · 하드 룰 12) · FT_DESK_GIT(느린 ref 흉내)
     FT_CARD_FLOW · FT_MBOX · FT_DESK_HIL · FT_DESK_DECISION · FT_DESK_SEATS · FT_DESK_STATE(기본 <루트>/.fable-team/state/news-desk) · FT_DESK_NOW
"""
import hashlib
import json
import logging
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ft_board_env as env  # noqa: E402
from ft_news_status import latest_snapshot  # noqa: E402
from ft_team_lib import TeamPathError, team_root, teams_md  # noqa: E402

LOG = logging.getLogger("ft_news_desk")
GOAL = re.compile(r"^##\s+메인 골")
CLOCK = re.compile(r"\b\d{1,2}:\d{2}\b")
TABLE_SEP = re.compile(r"^\|[\s:|-]+\|$")
CARD_NUMS = re.compile(r"대기 (\d+) · 진행 (\d+)")
DOING_CHARS = 40


def _run(cmd: list[str], timeout: float) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise RuntimeError(f"{Path(cmd[0]).name} 실행 실패: {e}") from e


def _timeout(name: str) -> float:
    try:
        return float(os.environ.get(name, "7"))
    except ValueError:
        return 7.0


def _why(e: Exception) -> str:
    return re.sub(r"\s+", " ", str(e)).strip()[:DOING_CHARS]


def ledger_text(root: Path) -> str:
    """원장 본문 — 픽스처 파일(FT_DESK_LEDGER_FILE) 아니면 `git show <ref>:<경로>` 1회(7초). 실패 = RuntimeError."""
    if f := os.environ.get("FT_DESK_LEDGER_FILE"):
        try:
            return Path(f).read_text(encoding="utf-8")
        except OSError as e:
            raise RuntimeError(f"원장 파일 읽기 실패 {f}: {e.strerror}") from e
    repo = os.environ.get("FT_LEDGER_REPO") or (root / ".fable-team" / "LIVE_ROOT").read_text(encoding="utf-8").split("\n")[0].strip()
    rel = os.environ.get("FT_LEDGER_PATH") or "design/teams/planner/PLAN-oppa-ledger.md"
    ref = os.environ.get("FT_DESK_LEDGER_REF") or "origin/main"
    done = _run([os.environ.get("FT_DESK_GIT") or "git", "-C", repo, "show", f"{ref}:{rel}"], _timeout("FT_DESK_LEDGER_TIMEOUT"))
    if done.returncode != 0:
        raise RuntimeError(f"원장 ref 읽기 실패 rc={done.returncode} {done.stderr.strip()[:DOING_CHARS]}")
    return done.stdout


def goal_rows(text: str) -> list[list[str]]:
    """원장 `## 메인 골` 절 첫 표의 데이터 행 — [골, 지금 상태, 닫히려면 남은 것] 그대로(자르기 0 · R1)."""
    lines = text.splitlines()
    start = next((i for i, ln in enumerate(lines) if GOAL.match(ln)), None)
    if start is None:
        raise RuntimeError("원장에 «## 메인 골» 절이 없다")
    rows: list[list[str]] = []
    for ln in lines[start + 1:]:
        if not ln.startswith("|"):
            if rows:
                break
            continue
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if TABLE_SEP.match(ln.strip()) or cells[0].startswith("골"):
            continue
        if len(cells) < 3 or not all(cells[:3]):
            raise RuntimeError(f"원장 골 표 행 칸이 3개가 아니거나 비었다: {ln[:DOING_CHARS]}")
        rows.append(cells)
    if not rows:
        raise RuntimeError("원장 골 표에 행이 없다")
    return rows


def goal_block(root: Path) -> list[str]:
    try:
        rows = goal_rows(ledger_text(root))
    except (RuntimeError, OSError) as e:
        LOG.error("골 표 확인 불가: %s", e)
        return [f"확인 불가 — 원장 골 표를 못 읽었다({_why(e)})"]
    body = [f"| {i} | {c[0]} | {c[1]} | {c[2]} |" for i, c in enumerate(rows, 1)]
    return [f"## 골 {len(rows)}줄 지금 상태", "", "| # | 골 | 지금 상태 | 닫히려면 남은 것 |", "|---|---|---|---|", *body]


def team_list(root: Path) -> list[str]:
    """명단(TEAMS.md) 표의 현역 팀 이름 — 「팀 | 폴더 | 오케 좌석 계열 | 상태」."""
    out: list[str] = []
    for ln in teams_md(root).read_text(encoding="utf-8").splitlines():
        cells = [c.strip() for c in ln.strip().strip("|").split("|")] if ln.startswith("|") else []
        if len(cells) >= 4 and cells[0] != "팀" and not TABLE_SEP.match(ln.strip()) and cells[3] == "현역":
            out.append(cells[0])
    return out


def card_nums(root: Path, team: str, folder: Path | None) -> tuple[str, str, str]:
    """ft-card-flow 1회 = (대기, 진행, 완성). 도구를 못 돌리면 셋 다 «확인 불가»(R3 — 숫자를 지어내지 않는다)."""
    if folder is None:
        return "확인 불가", "확인 불가", "확인 불가"
    tool = os.environ.get("FT_CARD_FLOW") or str(HERE / "ft-card-flow.sh")
    try:
        done = _run(["bash", tool, "--team", team, "--root", str(root), "--dir", str(folder)], _timeout("FT_DESK_CARD_TIMEOUT"))
    except RuntimeError as e:
        LOG.error("%s 카드 숫자 확인 불가: %s", team, e)
        return "확인 불가", "확인 불가", "확인 불가"
    if done.returncode != 0 or not (m := CARD_NUMS.search(done.stdout)):
        LOG.error("%s 카드 숫자 확인 불가: rc=%s %s", team, done.returncode, done.stdout.strip()[:DOING_CHARS])
        return "확인 불가", "확인 불가", "확인 불가"
    try:
        done_n = len([p for p in (folder / "indices" / "완성").iterdir() if p.name.endswith(".md")])
    except OSError as e:
        LOG.error("%s 완성 카드 수 확인 불가: %s", team, e)
        return m[1], m[2], "확인 불가"
    return m[1], m[2], str(done_n)


def open_seats(root: Path, team: str) -> str:
    """명부 열린 좌석 수 = 닫힘(_closed)·대체(_replaced_by)·은퇴(stop-ready·_retired_role) 아닌 행."""
    for name in (f"seats-{team}.json", "seats.json"):
        path = root / ".fable-team" / name
        if not path.is_file():
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as e:
            LOG.error("%s 명부 못 읽음: %s", team, e)
            return "확인 불가"
        if not isinstance(data, dict):
            return "확인 불가"
        rows = [v for k, v in data.items() if not k.startswith("_") and isinstance(v, dict)]
        return str(sum(1 for v in rows if not v.get("_closed") and not v.get("_replaced_by")
                       and not v.get("_retired_role") and v.get("role") not in ("", "stop-ready")))
    return "확인 불가"


def snapshot(root: Path) -> dict[str, dict]:
    """보드 스냅샷(ft_news_status 재료와 같은 한 장) → {팀 key: 그 팀 dict}. 못 읽음 = 빈 dict(«지금 하는 일» 칸이 확인 불가)."""
    try:
        return {t["key"]: t for t in json.loads(latest_snapshot(root)[0].read_text(encoding="utf-8"))["teams"] if t.get("key")}
    except (RuntimeError, OSError, ValueError, KeyError, TypeError) as e:
        LOG.error("보드 스냅샷 확인 불가: %s", e)
        return {}


def _short(title: str) -> str:
    return re.sub(r"\s+", " ", (title or "").split(" — ", 1)[-1]).replace("|", "/")[:DOING_CHARS]


def doing(team: dict | None) -> str:
    if team is None:
        return "보드 스냅샷 없음"
    if team.get("error"):
        return "못 읽음: " + _why(Exception(str(team["error"])))
    cards = [_short(c.get("title", "")) for c in (team.get("progress") or {}).values() if isinstance(c, dict)]
    queue = [_short(c.get("title", "")) for c in (team.get("queue") or []) if isinstance(c, dict)]
    head = "진행: " + " · ".join(c for c in cards[:2] if c) if cards else "진행 카드 없음"
    return head + (f" / 다음 대기: {queue[0]}" if queue and queue[0] else "")


def team_block(root: Path, snap: dict[str, dict]) -> list[str]:
    try:
        teams = team_list(root)
    except OSError as e:
        LOG.error("팀 명단 확인 불가: %s", e)
        return [f"확인 불가 — 팀 명단을 못 읽었다({_why(e)})"]
    body = []
    for team in teams:
        try:
            folder: Path | None = team_root(team, root)
        except (TeamPathError, OSError) as e:
            LOG.error("%s 폴더 확인 불가: %s", team, e)
            folder = None
        wait, doing_n, done_n = card_nums(root, team, folder)
        body.append(f"| {team} | {doing(snap.get(team))} | {wait} | {doing_n} | {done_n} | {open_seats(root, team)} |")
    return ["## 팀별 작업 상황", "",
            "카드 수 = ft-card-flow(대기·진행) + indices/완성 파일 수 · 열린 좌석 = 명부 · «지금 하는 일» = 보드 스냅샷", "",
            "| 팀 | 지금 하는 일 | 대기 | 진행 | 완성 | 열린 좌석 |", "|---|---|---|---|---|---|", *body]


def _hil(root: Path) -> list[str]:
    tool = os.environ.get("FT_DESK_HIL") or str(HERE / "ft-hil.sh")
    each = _run(["bash", tool, "--pending", "--each"], _timeout("FT_DESK_TOOL_TIMEOUT"))
    if each.returncode != 0:
        raise RuntimeError(f"ft-hil --pending rc={each.returncode} {each.stderr.strip()[:DOING_CHARS]}")
    count = len([x for x in each.stdout.splitlines() if x.strip()])
    summary = _run(["bash", tool, "--pending"], _timeout("FT_DESK_TOOL_TIMEOUT"))
    return [f"- 실행할 스크립트: {count}개 ({summary.stdout.strip() or f'미실행 h {count}개'})"]


def _questions(root: Path) -> list[str]:
    done = _run(["bash", os.environ.get("FT_DESK_DECISION") or str(HERE / "ft-decision-count.sh")], _timeout("FT_DESK_TOOL_TIMEOUT"))
    body = [x for x in done.stdout.strip().splitlines() if x.strip()]
    if done.returncode != 0 or not body:
        raise RuntimeError(f"ft-decision-count rc={done.returncode} {done.stderr.strip()[:DOING_CHARS]}")
    return [f"- 답 대기 질문: {body[-1]}"]


def oppa_block(root: Path) -> list[str]:
    out = ["## 오빠 손"]
    for part in (_hil, _questions):
        try:
            out += part(root)
        except (RuntimeError, OSError) as e:
            LOG.error("오빠 손 칸 확인 불가: %s", e)
            out.append(f"- 확인 불가({_why(e)})")
    return out


def build(root: Path, now: datetime) -> str:
    head = [f"# 뉴스 전문 — {now:%m-%d %H:%M} (뉴스 틱 자동 생성 · 손글 0)"]
    return "\n\n".join(["\n".join(head), *("\n".join(b) for b in (goal_block(root), team_block(root, snapshot(root)), oppa_block(root)))]) + "\n"


def digest(text: str) -> str:
    """«분»만 다르고 같은 내용이면 같은 digest(R4 · 판정 1430)."""
    return hashlib.sha1(CLOCK.sub("HH:MM", text).encode("utf-8")).hexdigest()


def desk_seat(root: Path) -> str:
    """명부 `_desk` 의 현역 좌석 — 없음·닫힘·대체 = RuntimeError(R5: 옛 이름으로 보내지 않는다)."""
    path = Path(os.environ.get("FT_DESK_SEATS") or root / ".fable-team" / "seats-planner.json")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        seat = data["_desk"]
        row = data[seat]
    except (OSError, ValueError, KeyError, TypeError) as e:
        raise RuntimeError(f"명부에서 desk 좌석을 못 찾았다({path.name}): {e}") from e
    if not isinstance(row, dict) or row.get("_closed") or row.get("_replaced_by"):
        raise RuntimeError(f"명부 desk 좌석 {seat} 이 현역이 아니다(닫힘·대체)")
    return seat


def relay(root: Path, path: Path, seat: str, summary: str) -> None:
    mbox = os.environ.get("FT_MBOX") or str(root / ".fable-team" / "comm" / "mbox.sh")
    done = _run(["bash", mbox, "relay", seat, "ft-news-desk", str(path), summary], _timeout("FT_DESK_TOOL_TIMEOUT") * 2)
    if done.returncode != 0:
        raise RuntimeError(f"desk relay 실패 rc={done.returncode} {(done.stderr or done.stdout).strip()[:DOING_CHARS]}")


def tick() -> int:
    root = env.ft_root()
    state = Path(os.environ.get("FT_DESK_STATE") or root / ".fable-team" / "state" / "news-desk")
    now = datetime.strptime(os.environ["FT_DESK_NOW"], "%Y-%m-%d %H:%M") if os.environ.get("FT_DESK_NOW") else datetime.now()
    text = build(root, now)
    dg = digest(text)
    last = state / "digest.sha"
    if last.is_file() and last.read_text(encoding="utf-8").strip() == dg:
        LOG.info("바뀐 것 없음 — desk relay 0")
        return 0
    try:
        seat = desk_seat(root)
    except RuntimeError as e:
        print(f"판정 불가 desk 좌석 — {e}", file=sys.stderr)
        return 1
    out = state / f"{now:%Y%m%d-%H%M}.md"
    try:
        state.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8")
        relay(root, out, seat, f"뉴스 전문 3블록 · {now:%H:%M} · 골 표 + 팀 표 + 오빠 손 (전문 파일 첨부)")
    except (RuntimeError, OSError) as e:
        print(f"판정 불가 relay — {e}", file=sys.stderr)
        return 1
    last.write_text(dg + "\n", encoding="utf-8")
    return 0


def main(argv: list[str]) -> int:
    if argv[:1] == ["render"]:
        root = env.ft_root()
        now = datetime.strptime(os.environ["FT_DESK_NOW"], "%Y-%m-%d %H:%M") if os.environ.get("FT_DESK_NOW") else datetime.now()
        print(build(root, now), end="")
        return 0
    if argv[:1] not in ([], ["run"]):
        print("usage: ft_news_desk.py [run|render]", file=sys.stderr)
        return 2
    return tick()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    raise SystemExit(main(sys.argv[1:]))
