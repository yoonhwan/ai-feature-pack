"""ft-board 입력 수집의 바깥 호출 모음 — gh·tmux·판정 원장·인박스·좌석 상태. 전부 env 로 스텁할 수 있다(시험은 실제 호출 0).

실패는 전부 raise(#0 RULE) — 호출이 깨졌는데 빈 값으로 보드를 그리지 않는다.
  FT_ROOT            루트(없으면 이 스크립트가 든 리포의 git common dir 부모)
  FT_BOARD_NOW       시각 주입(ISO) — 날짜 경계·최근 시험용
  FT_BOARD_TMUX      살아 있는 세션 목록 명령(기본 `tmux ls -F #{session_name}`)
  FT_BOARD_GH        gh issue list JSON 명령 · FT_BOARD_GH_TTL 캐시 초(기본 600)
  FT_BOARD_GH_REFRESH  1 이면 gh 갱신 허용(`ft-board.py --refresh-gh` 가 설정). ★불변: 플래그 없는 호출 = 외부 0★ — 캐시 없음/오래됨은 그대로 읽고
                       (없으면 빈 목록) ⑤ 절이 «(캐시 … · 미확인)» 으로 드러낸다. 갱신 호출은 launchd ft-board-publish.sh 가 명시적으로 붙인다.
  gh 갱신은 외부 호출 7초 + 재시도 1(하드 룰 12 · shared/config/external_call.py 와 같은 값) — 실패하면 캐시가 있을 때 캐시 유지, 없으면 raise
  FT_VERDICT_BIN     ft-verdict.sh 경로 · FT_BOARD_INBOX 인박스 show 명령 접두 · FT_BOARD_SEAT_STATUS `ft-seat-status.sh turn <좌석> --json` 스텁/경로(ft_board_seat.py)
"""
import datetime as dt
import json
import os
import re
import shlex
import subprocess
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent


def ft_root() -> Path:
    if os.environ.get("FT_ROOT"):
        return Path(os.environ["FT_ROOT"])
    out = subprocess.run(["git", "-C", str(HERE), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                         capture_output=True, text=True, check=True).stdout.strip()
    return Path(out).parent


def now() -> dt.datetime:
    v = os.environ.get("FT_BOARD_NOW")
    return dt.datetime.fromisoformat(v) if v else dt.datetime.now()


GH_TIMEOUT_S, GH_RETRIES = 7, 1  # 하드 룰 12 — 외부 호출 1회 7초 + 재시도 1


def run(cmd: list[str], what: str, env: dict | None = None, timeout: int = 60) -> str:
    r = subprocess.run(cmd, capture_output=True, text=True, env=env, timeout=timeout)
    if r.returncode != 0:
        raise RuntimeError(f"{what} 실패 rc={r.returncode}: {r.stderr.strip()[:200]}")
    return r.stdout


def tmux_alive() -> set[str]:
    cmd = shlex.split(os.environ.get("FT_BOARD_TMUX", "tmux ls -F #{session_name}"))
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if r.returncode != 0:
        if "no server running" in r.stderr or "no sessions" in r.stderr:
            return set()
        raise RuntimeError(f"tmux 세션 조회 실패 rc={r.returncode}: {r.stderr.strip()[:200]}")
    return {s.strip() for s in r.stdout.splitlines() if s.strip()}


def gh_issues(root: Path) -> list[dict]:
    cache = root / ".fable-team" / "state" / "board" / "gh-cache.json"
    ttl = int(os.environ.get("FT_BOARD_GH_TTL", "600"))
    if cache.exists() and time.time() - cache.stat().st_mtime < ttl:
        data = json.loads(cache.read_text(encoding="utf-8"))
    elif os.environ.get("FT_BOARD_GH_REFRESH") != "1":  # 기본 = 캐시 전용 — 외부 0
        data = json.loads(cache.read_text(encoding="utf-8")) if cache.exists() else []
    else:
        cmd = shlex.split(os.environ.get(
            "FT_BOARD_GH", "gh issue list --state all --limit 100 --json number,title,labels,updatedAt,state"))
        env = {k: v for k, v in os.environ.items() if k != "GH_TOKEN"}  # 워크트리 gh 실패 함정 4
        err = None
        for _ in range(GH_RETRIES + 1):
            try:
                data = json.loads(run(cmd, "gh issue list", env, GH_TIMEOUT_S))
                cache.parent.mkdir(parents=True, exist_ok=True)
                cache.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
                break
            except (RuntimeError, subprocess.TimeoutExpired, ValueError) as e:
                err = e
        else:
            if not cache.exists():
                raise RuntimeError(f"gh issue list 실패(캐시 없음): {err}")
            data = json.loads(cache.read_text(encoding="utf-8"))  # 캐시 유지 — ⑤ 절이 캐시 시각으로 «미확인» 을 드러낸다
    return [{"number": i["number"], "title": i["title"], "state": i["state"].lower(),
             "labels": sorted(x["name"] for x in i.get("labels", []))} for i in data]


def verdicts(root: Path, date: str) -> list[dict]:
    exe = os.environ.get("FT_VERDICT_BIN", str(HERE / "ft-verdict.sh"))
    rows = json.loads(run(["bash", exe, "list", "--json"], "ft-verdict.sh list", {**os.environ, "FT_ROOT": str(root)}))
    return [{"n": r["n"], "title": r["title"], "teams": r["teams"], "state": r["state"],
             "oppa_todo": r.get("oppa_todo") or "", "today": r["ts"].startswith(date)}
            for r in rows if r["state"] == "open" or r["ts"].startswith(date)]


def mail_ts(root: Path, seq: int) -> str | None:
    for fn in ("mailbox.jsonl", "mailbox.log.jsonl"):
        p = root / ".fable-team" / "comm" / fn
        if not p.exists():
            continue
        for line in p.read_text(encoding="utf-8").splitlines():
            if f'"seq": {seq},' in line or f'"seq":{seq},' in line:
                return json.loads(line)["ts"]
    return None


def inbox(root: Path, master: str) -> dict:
    # 미보고 = ft-inbox.sh show 의 줄 수(정본 술어 obligation_closed 가 거짓인 줄만 나온다 — 술어 재작성 0)
    cmd = shlex.split(os.environ.get("FT_BOARD_INBOX", f"bash {HERE / 'ft-inbox.sh'} show")) + [master]
    out = run(cmd, "ft-inbox.sh show", {**os.environ, "FT_ROOT": str(root)})
    lines = [x for x in out.splitlines() if x.strip() and x.strip() != "EMPTY"]
    seqs = [int(s) for x in lines for grp in re.findall(r"미닫힘=([\d,]+)", x) for s in grp.split(",") if s]
    return {"unreported": len(lines), "oldest_ts": mail_ts(root, min(seqs)) if seqs else None}


def pending(root: Path, master: str) -> int:
    # 수신 대기 = mailbox 큐에 남은 그 좌석 앞 쪽지 수(인박스 미보고와 따로 센다 — 설계 :56)
    p = root / ".fable-team" / "comm" / "mailbox.jsonl"
    if not p.exists():
        return 0
    return sum(1 for x in p.read_text(encoding="utf-8").splitlines() if x.strip() and json.loads(x).get("to") == master)
