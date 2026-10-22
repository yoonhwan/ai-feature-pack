"""ft_goal_readjust — 골 «하루 두 번 재조정» 회차 수집기 (r714a · 설계 r3 §1~§6 + 오빠 10-22 정정(자동 시계 0 · 수동 진입점 · 하루 최대 2회)).
★자동 시계 0 — launchd 07:35/19:35 없음. 회차는 «요청받을 때만» 돈다: 수동 진입점 = ft-goal-readjust.sh 하나(오빠·오케가 부른다). 요청 없는 날은 회차 0(건너뛴다).★
★하루 최대 2회★ — 오늘 회차(요청) 수가 2 면 3번째 요청은 `REJECT 오늘 2회 다 씀 · 다음 = 내일` rc2(쪽지 0 · 파일 0). run = `<YYYYMMDD>-<k>`(k = 1|2 = 그날 몇 번째 요청).
재시도 = 미완 회차(ERROR 또는 claimed 무영수증) 이어서(자동 · 쪽지 0 안전) ∨ `--retry`(마지막 회차 이어서 · 측정값만 다시 잼).
rc = 0 OK · 1 ERROR 회차 · 2 usage/REJECT(--request 없음 · 상한 초과) · 3 회차는 끝났으나 송신 실패/모름(조용한 rc0 0 · DA H8).

한 회차 = ①잠금 ②`git fetch origin main`(7초 · 재시도 1 · 실패 2회 = ERROR) 뒤 commit 하나로 입력을 고정(디스크 폴더 실재는 안 본다)
③행별 사실 측정 + 라벨(기준·확인 불가·마감·움직임·변화 0(N시간)) ④회차 파일 `rounds/<run>-<nn>.json`(+ 보고서 `.md`) ⑤planner 쪽지 run 당 1통(여러 골 변경 = 사실 한 본문에 묶어 1통) ⑥영수증 `.sent.json`/`.send-failed.json` ⑦log 1줄.
★덮어쓰기 0★ — 회차 파일(.json·.md 둘 다)은 `.tmp` → rename 1회로만 쓰고, 이미 있는 이름이면 쓰지 않고 다음 attempt 로 간다(DA H1). «마지막 성공»·«최근 시도» 는 읽는 쪽이 목록에서 파생한다(ft_goal_readjust_state).
★쪽지 = run 당 총 1통★(종류 무관) · 재시도 0 — 보낸 뒤 중단되면 재실행은 «송신 상태 모름» 경보만 남기고 다시 보내지 않는다(수신 측 중복 제거가 없으므로 송신 측에서만 닫는다 · DA r2 A1).
  ★그 «모름» 은 영수증이 생길 때까지 이후 attempt·다음 run 경보에 이어진다★(DA H2 — 한 회차만 보이고 사라지면 송신 여부를 영원히 모른다).
★쓰기 허용 목록 = `<루트>/.fable-team/state/goal-readjust/` 아래 + `git fetch`(refs/remotes·FETCH_HEAD·objects) 뿐★ — 그 밖 쓰기 0(작업 트리·refs/heads·인덱스 무변경).
선택 입력(다른 카드 자리 · 없으면 «모름» 글자 — 0 으로 합치지 않는다): `goal-evidence.json`(r693 `{"rows":{"<n>":"✅ 전부"}}`) · `goal-row-swap.json`(r702 `{"stale_rows":[n…]}`) ·
`goal-landed.json`(r664) · `goal-live.json`(r708). 꼴은 각 카드가 소유하고 이 장치는 «있나» 만 본다(착지 때 맞춘다).
요청 = `--request "<요청 출처 1줄>"` **필수**(없으면 usage rc2 · 회차 파일 `request` 칸에 그대로 · DA H12) · 무효 LIVE_ROOT = ERROR(조용한 FT_ROOT 대체 0 · DA H13).
env: FT_ROOT · FT_LEDGER_REPO · FT_GOAL_REPO · FT_TEAMS_REF(origin/main) · FT_GOAL_A6_MD · FT_GOAL_A6_LEDGER · FT_HARNESS_ROOT · FT_HARNESS_REF · FT_MBOX ·
FT_NOW("YYYY-MM-DD HH:MM") · FT_GOAL_STALL_H(24) · FT_GOAL_READJUST_MAX_H(26) · FT_GOAL_READJUST_BUDGET(65초).
"""
from __future__ import annotations

import fcntl
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from ft_goal_readjust_measure import ReadjustError, _env_h, measure
from ft_goal_readjust_state import StatePathError, state_dir

BODY_MAX = 700
SKIP = (".sent.json", ".send-failed.json")
RC_ERROR, RC_USAGE, RC_SEND = 1, 2, 3
ROUND_FILE = re.compile(r"^(?P<run>.+)-(?P<n>\d{2})(?P<suf>\.[a-z]+)$")


def _now() -> datetime:
    """회차 시계 — FT_NOW("YYYY-MM-DD HH:MM")가 있으면 그 분(시험 고정 시계) · 없으면 지금. started·finished 가 같은 시계를 쓴다."""
    value = os.environ.get("FT_NOW")
    return datetime.strptime(value, "%Y-%m-%d %H:%M") if value else datetime.now()



def _prior_rounds(d: Path, run: str) -> list[dict]:
    out = []
    for path in sorted((d / "rounds").glob(f"{run}-*.json")):
        if path.name.endswith(SKIP):
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(data, dict):
            out.append({**data, "_file": path.name})
    return out


def _run_key(d: Path, now: datetime, retry: bool) -> tuple[str | None, str]:
    """(run, 사유) — run = `<YYYYMMDD>-<k>`(k = 그날 몇 번째 «요청» · 최대 2) · 이어서(미완 회차) 면 그 run 그대로.
    ★자동 시계 0★: 오늘 요청이 없으면 회차 파일도 없다 — 부르는 쪽(사람·오케)이 유일한 방아쇠다."""
    today = f"{now:%Y%m%d}"
    seen: list[str] = []
    for path in sorted((d / "rounds").glob(f"{today}-*.json")):
        if path.name.endswith(SKIP):
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(data, dict) and data.get("run") and data["run"] not in seen:
            seen.append(data["run"])
    if seen:
        last = _prior_rounds(d, seen[-1])[-1]
        claimed = (last.get("send") or {}).get("state") == "claimed" and not _receipt(d, seen[-1], int(last.get("attempt") or 0))
        if last.get("status") != "OK" or claimed:
            return seen[-1], "이어서(미완 회차)"
        if retry:
            return seen[-1], "--retry(마지막 회차 이어서)"
    k = len(seen) + 1
    if k > 2:
        return None, f"REJECT 오늘 2회 다 씀 — 오늘 회차 {len(seen)}회(최대 2회 · 다음 = 내일)"
    return f"{today}-{k}", ""


def _receipt(d: Path, run: str, attempt: int) -> bool:
    return any((d / "rounds" / f"{run}-{attempt:02d}{suf}").is_file() for suf in (".sent.json", ".send-failed.json"))


def _attempts(d: Path, run: str) -> int:
    """이미 쓴 회차 번호의 최대값 — ★.json 과 .md 둘 다 센다★(보고서만 쓰고 끊긴 회차를 덮어쓰지 않는다 · DA H1)."""
    best = 0
    for path in (d / "rounds").glob(f"{run}-*"):
        m = ROUND_FILE.match(path.name)
        if m and m["suf"] in (".json", ".md"):
            best = max(best, int(m["n"]))
    return best



def _repeat(d: Path, run: str, alarms: list[str]) -> int:
    """같은 경보 집합이 몇 회차째 이어지나(기준 파일부터 이름 역순 · 최대 24회차) — 보고서 «반복 k회차» 1줄."""
    k = 0
    for path in reversed(sorted((d / "rounds").glob("*.json"))):
        if path.name.endswith(SKIP) or path.name.startswith(run):
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            break
        if not isinstance(data, dict) or data.get("status") != "OK":
            continue
        if data.get("alarms") != alarms:
            break
        k += 1
        if k >= 24:
            break
    return k


def _write(path: Path, text: str, fresh: bool = False) -> None:
    """`.tmp` → rename 1회(한 번 쓴 파일은 고치지 않는다 · ft-leak-watch put() 꼴).
    fresh=True 면 이미 있는 이름에 쓰지 않는다 — 회차 파일 덮어쓰기 0(set -C 꼴 · DA H1)."""
    if fresh and path.exists():
        raise ReadjustError(f"회차 파일 덮어쓰기 금지: {path.name}")
    tmp = path.with_name(path.name + f".tmp{os.getpid()}")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def _report(rec: dict, repeat: int) -> str:
    lines = [f"# 골 재조정 회차 {rec['run']}-{rec['attempt']:02d} — {rec['status']}", "",
             f"- 시작 {rec['started']} · 끝 {rec.get('finished', '-')} · key GR-{rec['run']}",
             f"- 기준: {(rec.get('baseline') or {}).get('file') or '없음'} {('(' + rec['baseline_reason'] + ')') if rec.get('baseline_reason') else ''}".rstrip(),
             f"- 요청: {rec.get('request') or '-'}",
             f"- 입력: {json.dumps((rec.get('inputs') or {}).get('repos') or {}, ensure_ascii=False)}"]
    if rec["status"] != "OK":
        lines += ["", f"ERROR {rec.get('error', '')}"]
    else:
        lines += ["", "| n | 골 | 팀 | 라벨 | 카드 | 증거 | 원장 변화 | 행 나이(h) |", "|---|---|---|---|---|---|---|---|"]
        for r in rec["rows"]:
            lines.append(f"| {r['n']} | {r['goal12']} | {r['team']} | {r['label']} | {r['cards_added']} | {r['evidence']} | "
                         f"{'있음' if r['ledger_row_changed'] else '-'} | {r['row_age_h'] if r['row_age_h'] is None else int(r['row_age_h'])} |")
        facts = rec["facts"]
        lines += ["", f"- 닫힘 후보: {facts['close_candidates'] or '없음'} · 정본 밖 골 파일: {facts['goal_files_outside_canon'] or '없음'}",
                  f"- 안 묶인 카드: {len(facts['unassigned_cards'])} · 번호 밖 골좌표 카드: {len(facts['stale_numbered_cards'])}",
                  f"- 시작 카드: {json.dumps(facts['open_cards'], ensure_ascii=False)}",
                  f"- 모름: {' · '.join(facts.get('unknown') or []) or '없음'}",
                  f"- 경보: {' · '.join(rec['alarms']) if rec['alarms'] else '경보 0'}" + (f" · 반복 {repeat}회차" if repeat else "")]
    lines += ["", f"- 송신: {json.dumps(rec.get('send') or {}, ensure_ascii=False)}"]
    return "\n".join(lines) + "\n"


def _unresolved(d: Path, skip_run: str | None = None) -> list[str]:
    """선점(claimed)했는데 영수증이 없는 run 목록 — ★영수증이 생길 때까지 이어진다★(DA H2 · 다른 run 도 포함)."""
    out: list[str] = []
    for path in sorted((d / "rounds").glob("*.json")):
        if path.name.endswith(SKIP):
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(data, dict) or (data.get("send") or {}).get("state") != "claimed":
            continue
        run = str(data.get("run") or "")
        if not run or run == skip_run or _receipt(d, run, int(data.get("attempt") or 0)):
            continue
        if run not in out:
            out.append(run)
    return out


def _need(rec: dict, prior: list[dict], d: Path, run: str) -> dict:
    """송신 상태 — ★run 당 총 1통★(종류 무관) · 선점 파일이 하나라도 있으면 «모름» 만(재송신 0 · 설계 §1 · DA H2)."""
    key = f"GR-{run}"
    if any((p.get("send") or {}).get("state") == "claimed" and not _receipt(d, run, int(p.get("attempt") or 0)) for p in prior):
        return {"state": "unknown", "key": key, "reason": f"송신 상태 모름 {key}"}
    if prior:
        return {"state": "none", "key": key, "reason": "run 상한"}
    if rec["status"] == "OK" and not (rec["alarms"] or rec["facts"]["close_candidates"] or rec["facts"]["goal_files_outside_canon"]):
        return {"state": "none", "key": key, "reason": "알릴 사실 없음"}
    if _planner() is None:
        return {"state": "failed", "key": key, "reason": "planner 좌석·mbox 없음(송신 못 함) · 조용한 OK 0"}
    return {"state": "claimed", "key": key}


def _common_root() -> Path | None:
    """공용 루트 — env FT_ROOT › cwd 의 git 공용 루트(ft_comm_dir/ft_repo_root 와 같은 규칙 · LIVE_ROOT 는 안 본다 · DA H13)."""
    if os.environ.get("FT_ROOT"):
        return Path(os.environ["FT_ROOT"])
    try:
        done = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
                              capture_output=True, text=True, timeout=7, check=False)
    except (OSError, subprocess.SubprocessError):
        return None
    common = done.stdout.strip()
    if done.returncode != 0 or not common:
        return None
    return Path(common).parent if common.endswith("/.git") else Path(common)


def _planner() -> tuple[str, Path] | None:
    """(현역 planner 이름, mbox 경로) — `seats-planner.json _master` · 공용 루트에서 찾는다 · 없으면 None(송신 실패 rc3 · DA H8)."""
    base = _common_root()
    if base is None:
        return None
    try:
        name = str(json.loads((base / ".fable-team" / "seats-planner.json").read_text(encoding="utf-8")).get("_master") or "")
    except (OSError, ValueError):
        return None
    mbox = Path(os.environ.get("FT_MBOX") or base / ".fable-team" / "comm" / "mbox.sh")
    return (name, mbox) if name and mbox.is_file() else None


def _body(rec: dict, repeat: int, report: Path) -> str:
    """쪽지 본문(≤700B) — [결정] 3줄 고정(비가역·선례·선택지) ∨ [긴급] 실패 1줄 · 머리에 GR-<run>(설계 §6)."""
    key = f"GR-{rec['run']}"
    if rec["status"] != "OK":
        return f"[긴급] 골 재조정 실패 {rec['run']} {key} — {' '.join(str(rec.get('error')).split())[:200]}"
    facts = rec["facts"]
    labels = " · ".join(f"{r['n']}={r['label']}" for r in rec["rows"])
    body = "\n".join([
        f"[결정] 골 재조정 {rec['run']} {key} · 닫힘 후보 {len(facts['close_candidates'])} · 정본 밖 골 파일 {len(facts['goal_files_outside_canon'])} · 경보 {len(rec['alarms'])}",
        "비가역: 아니오 — 정본·원장은 사람 손만 · 이 쪽지는 사실·경보 목록",
        f"선례: {('기준 회차 라벨 ' + labels)[:200] if rec.get('baseline') else '없음(첫 회차)'}",
        "선택지: ① 원장 «지금 상태» 그 행 갱신 ② 정본 h(새 골·내림) ③ 응답 절 1줄(r714c 문법)",
        f"사실: 닫힘 후보 행 {facts['close_candidates'] or '없음'} · 정본 밖 {', '.join(facts['goal_files_outside_canon']) or '없음'} · "
        f"경보: {' · '.join(rec['alarms']) or '경보 0'}{f' (반복 {repeat}회차)' if repeat else ''} · 보고서: {report}",
    ])
    while len(body.encode("utf-8")) > BODY_MAX and len(body.splitlines()) > 4:
        lines = body.splitlines()
        body = "\n".join(lines[:4] + [lines[4][: max(0, len(lines[4]) - 40)]])
    return body


def _send(rec: dict, d: Path, report: Path) -> dict:
    """송신 1회(7초 · 재시도 0) → 결과 dict · 실패도 예외 0(영수증에 적는다)."""
    seat = _planner()
    if seat is None:
        return {"state": "failed", "error": "planner 좌석·mbox 없음"}
    name, mbox = seat
    body = _body(rec, _repeat(d, rec["run"], rec["alarms"] if rec["status"] == "OK" else []), report)
    try:
        done = subprocess.run(["bash", str(mbox), "send", name, "ft-goal-readjust", body], capture_output=True, text=True, timeout=7, check=False)
    except (OSError, subprocess.SubprocessError) as e:
        return {"state": "failed", "error": f"송신 실패: {e}"}
    if done.returncode != 0:
        return {"state": "failed", "error": f"송신 실패 rc={done.returncode}: {done.stderr.strip()[:120]}"}
    seq = next((ln.split("seq=")[1].split()[0] for ln in done.stdout.splitlines() if "seq=" in ln), "")
    return {"state": "sent", "seq": seq, "at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")}


def _log(d: Path, line: str) -> None:
    try:
        with open(d / "goal-readjust.log", "a", encoding="utf-8") as fh:
            fh.write(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')} {line}\n")
    except OSError as e:
        print(f"WARN 골 재조정 log 못 씀 {d}: {e}", file=sys.stderr)


def collect(retry: bool = False, request: str = "") -> int:
    now, t0 = _now(), time.monotonic()
    try:
        d = state_dir(strict=True)            # 무효 LIVE_ROOT = ERROR(조용한 FT_ROOT 대체 0 · DA H13)
    except StatePathError as e:
        raise ReadjustError(f"데이터 루트 {e}") from e
    if d is None:
        raise ReadjustError("데이터 루트를 못 풀었다(FT_ROOT·LIVE_ROOT)")
    d.mkdir(parents=True, exist_ok=True)
    (d / "rounds").mkdir(parents=True, exist_ok=True)
    lock = open(d / "goal-readjust.lock", "a+", encoding="utf-8")
    try:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        _log(d, "SKIP busy — 다른 회차가 도는 중(이번 회차 쓰기 0)")
        return 0
    run, why = _run_key(d, now, retry)
    if run is None:                            # 상한 초과 = REJECT rc2(회차 파일 0 · 쪽지 0 · DA H12)
        _log(d, why)
        print(f"ERROR 골 재조정 — {why}", file=sys.stderr)
        return RC_USAGE
    attempt = _attempts(d, run) + 1
    try:
        if time.monotonic() - t0 > _env_h("FT_GOAL_READJUST_BUDGET", 65):
            raise ReadjustError("시간 초과 — 이번 회차 측정 못 함")
        rec = measure(d, now, run)
    except ReadjustError as e:
        rec = _error_round(run, now, str(e))
    except Exception as e:                     # 측정 예외 = ERROR 회차 파일(DA H9 — traceback 만 남기고 회차 파일 0 인 채 끝나지 않는다)
        rec = _error_round(run, now, f"{type(e).__name__}: {e}")
    rec["attempt"] = attempt
    rec["request"] = request
    rec["finished"] = (now if os.environ.get("FT_NOW") else datetime.now()).strftime("%Y-%m-%d %H:%M:%S")
    prior = _prior_rounds(d, run)
    carried = [f"송신 상태 모름 GR-{r}" for r in _unresolved(d, run)]   # 영수증 없는 선점은 계속 경보(DA H2)
    rec["alarms"] = [*rec["alarms"], *carried]        # ★_need() «앞»★ — 이월 경보도 쪽지·머리에 실린다(DA 회귀 H2)
    plan = _need(rec, prior, d, run)
    rec["send"] = {**plan}
    if plan["state"] == "unknown" and plan.get("reason"):
        rec["alarms"] = [*rec["alarms"], plan["reason"]]
    stem = d / "rounds" / f"{run}-{attempt:02d}"
    report = stem.with_suffix(".md")
    _write(report, _report(rec, _repeat(d, run, rec["alarms"])), fresh=True)
    _write(stem.with_suffix(".json"), json.dumps(rec, ensure_ascii=False, indent=1) + "\n", fresh=True)   # ← 이 파일 존재 = 회차 완료
    if plan["state"] == "claimed":
        out = _send(rec, d, report)
        suffix = ".sent.json" if out["state"] == "sent" else ".send-failed.json"
        _write(d / "rounds" / f"{run}-{attempt:02d}{suffix}", json.dumps(out, ensure_ascii=False) + "\n")
        rec["send"] = {**plan, **out}
    labels = " ".join(f"{r['n']}={r['label']}" for r in rec["rows"]) or "-"
    _log(d, f"run={run} attempt={attempt:02d} status={rec['status']} send={rec['send'].get('state')} "
            f"alarms={len(rec['alarms'])} label={labels[:200]}{(' err=' + rec['error'][:120]) if rec['status'] != 'OK' else ''}")
    if rec["status"] != "OK":
        print(f"ERROR 골 재조정 {run}-{attempt:02d}: {rec['error']}", file=sys.stderr)
        return RC_ERROR
    print(f"OK 골 재조정 {run}-{attempt:02d} send={rec['send'].get('state')} rows={len(rec['rows'])} alarms={len(rec['alarms'])}")
    if rec["send"].get("state") in ("failed", "unknown"):   # 조용한 OK 0 — 송신 실패/모름은 rc3(DA H8)
        print(f"ERROR 골 재조정 {run}-{attempt:02d} — 송신 {rec['send'].get('state')}: {rec['send'].get('error') or rec['send'].get('reason')}", file=sys.stderr)
        return RC_SEND
    return 0


def _error_round(run: str, now: datetime, error: str) -> dict:
    """ERROR 회차 dict — 입력·행 없이 사유만(쪽지는 [긴급] 1통 · 설계 §1 «실패»)."""
    return {"run": run, "attempt": 0, "started": now.strftime("%Y-%m-%d %H:%M:%S"), "status": "ERROR", "error": error,
            "inputs": {}, "rows": [], "facts": {"close_candidates": [], "goal_files_outside_canon": [], "unassigned_cards": [],
                                                "stale_numbered_cards": [], "open_cards": {}, "broken_links": [], "unknown": []},
            "alarms": [], "baseline": None, "baseline_reason": "", "request": "",
            "send": {"state": "none", "key": f"GR-{run}"}}


def _parse(argv: list[str]) -> tuple[str | None, bool, list[str]]:
    """(--request 값, --retry, 남은 인자) — ★--request 는 필수★(DA H12 · 없으면 usage rc2)."""
    request, retry, rest = None, False, []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--request":
            if i + 1 >= len(argv) or argv[i + 1].startswith("--") or not argv[i + 1].strip():
                return None, retry, rest + ["--request 값 없음"]
            request, i = argv[i + 1].strip(), i + 2
            continue
        if arg.startswith("--request="):
            request = arg.split("=", 1)[1].strip() or None
        elif arg == "--retry":
            retry = True
        else:
            rest.append(arg)
        i += 1
    return request, retry, rest


def main(argv: list[str]) -> int:
    request, retry, rest = _parse(argv)
    if request and not rest:
        try:
            return collect(retry=retry, request=request)
        except (ReadjustError, OSError, StatePathError) as e:
            print(f"ERROR 골 재조정 — {e}", file=sys.stderr)
            return RC_ERROR
    if rest == ["--request 값 없음"]:
        print("usage: ft_goal_readjust.py --request \"<요청 출처 1줄>\" [--retry] — --request 뒤에 출처가 필요하다", file=sys.stderr)
        return RC_USAGE
    if not request:
        print("usage: ft_goal_readjust.py --request \"<요청 출처 1줄>\" [--retry] — 요청 출처가 없으면 회차를 돌리지 않는다(rc2)", file=sys.stderr)
        return RC_USAGE
    print(f"usage: ft_goal_readjust.py --request \"<요청 출처 1줄>\" [--retry] — 모르는 인자: {' '.join(rest)}", file=sys.stderr)
    return RC_USAGE


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
