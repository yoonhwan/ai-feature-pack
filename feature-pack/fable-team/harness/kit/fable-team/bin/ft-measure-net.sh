#!/bin/bash
# ft-measure-net.sh — 팀 운영 구조 효과 측정 3지표 (PLAN-harness-networking §9 · 판정 1073·1075 · N1 r-net-tick-line). 읽기만 · 쓰기 0 · 외부 호출 0.
# 추적 사본: scripts/fable-team-bin/ft-measure-net.sh · 런타임 자리: <워크트리>/.fable-team/bin/ (gitignore)
#
# usage: ft-measure-net.sh succession|interview|planner-mail <from> <to>      (from/to = 로컬 시각 ISO · 양끝 포함 · interview 만 UTC)
#        ft-measure-net.sh baseline          (PLAN §9 baseline 창 고정 · 라이브 로그 읽기만 · 1줄 JSON {raw,succession,first_boot,interview,window})
#   baseline 창: 우편 = 10-08 21:04 ~ 10-11 23:45:59 (PLAN 「23:45」 = 그 분 끝까지 · 로컬=KST) · 인터뷰 = UTC 10-08 00:00 ~ 10-11 14:45:59(= 23:45 KST · UTC 일자 4일). PLAN 값 180/154/26/460.
# 출력: 1줄 JSON. 정리 전 baseline 과 설치 7일 뒤가 «같은 정규식·같은 분류 규칙»으로만 돈다 — 규칙은 아래 상수가 정본이다.
#   succession   역할 좌석 부팅 보고 쪽지 = mailbox.log.jsonl(+.1) 행 중 from ~ FROM_RE ∧ body ~ BODY_RE · 같은 from 은 1건(가장 이른 ts) ·
#                창 = 쪽지 ts. raw = 그 수 · first_boot = 계보(from 의 `#N` 뗀 이름) 수(= 계보 첫 부팅 · 분류 불가로 따로 센다) ·
#                succession = raw − first_boot(같은 계보의 선행 부팅이 같은 불변 로그 창 안에 있는 것). 현재 명부·_opened 같은 가변 값은 쓰지 않는다.
#   interview    AskUserQuestion tool_use 사건 = BYZ 프로젝트 전 세션 jsonl 의 assistant 레코드 tool_use.name 일치 · tool_use.id 로 중복 제거 ·
#                timestamp 의 «기록된 UTC 일자». {total, by_day}. 이 지표만 <from> <to> 도 UTC 로 읽는다(baseline 460 = 110·167·104·79 가 UTC 일자 —
#                로컬 일자로 세면 116·137·133·86 으로 갈린다. 2026-10-12 실측).
#   planner-mail mailbox 로그 행 중 to 가 «그 시각 현역» planner 좌석인 것 · 1행 1건 · ts 일자. 계보 = seats-planner.json `_master` 의 `#N` 뗀 이름,
#                현역 = 그 계보 «부팅 보고» 쪽지(좌석당 첫 1건) ts 오름차순에서 쪽지 직전의 마지막 좌석(불변 로그 재현 · 현재 명부 0 · PLAN §9 ③).
#                {total, by_seat, unclassified(첫 부팅 전 구간), by_day}. 은퇴한 같은 계보 좌석 앞 쪽지는 세지 않는다.
# 실패는 raise(rc 1): 로그 없음·해석 실패·프로젝트 jsonl 없음은 0 이 아니라 실패다. usage 오류 rc 2.
# env: FT_ROOT · FT_MEASURE_PROJECTS_DIRS(공백 구분 · 기본 ~/.claude/projects/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents*)

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -z "${FT_ROOT:-}" ]; then
  common="$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || common=""
  [ -n "$common" ] && FT_ROOT="$(dirname "$common")"
fi
export FT_ROOT
[ $# -eq 3 ] || [ "${1:-}" = baseline -a $# -eq 1 ] || { echo "usage: $0 succession|interview|planner-mail <from> <to> | baseline" >&2; exit 2; }

exec python3 - "$@" <<'PY'
import datetime as dt
import glob
import json
import os
import re
import sys
from collections import Counter
from pathlib import Path

FROM_RE = re.compile(r"^(byz|ft)-[a-z0-9]+-(master|arch|da|tester|pm|checker)-[a-z]+#\d+$")
BODY_RE = re.compile(r"^\s*(\[(byz|ft)[^\]]*\]\s*)?\[?(부팅 보고|첫 보고|부팅)\b")
LOGS = ("mailbox.log.jsonl.1", "mailbox.log.jsonl")
metric = sys.argv[1]
BASELINE = {"mailbox": ("2026-10-08T21:04:00", "2026-10-11T23:45:59"), "interview": ("2026-10-08T00:00:00", "2026-10-11T14:45:59")}
if metric == "baseline":
    t0, t1 = (dt.datetime.fromisoformat(x) for x in BASELINE["mailbox"])
else:
    try:
        t0, t1 = (dt.datetime.fromisoformat(x) for x in sys.argv[2:4])
    except ValueError:
        print("usage: ft-measure-net.sh succession|interview|planner-mail <from> <to> (ISO 시각)", file=sys.stderr); sys.exit(2)
    if metric not in ("succession", "interview", "planner-mail") or t1 < t0:
        print("usage: ft-measure-net.sh succession|interview|planner-mail <from> <to>", file=sys.stderr); sys.exit(2)
root = Path(os.environ["FT_ROOT"])
head = {"metric": metric, "from": sys.argv[2] if len(sys.argv) > 2 else None, "to": sys.argv[3] if len(sys.argv) > 3 else None}


def fail(msg: str):
    print(f"ft-measure-net: {msg}", file=sys.stderr); sys.exit(1)


def lineage(name: str) -> str:
    return re.sub(r"#\d+$", "", name)


def mail_rows() -> list[dict]:
    by_seq, found = {}, False
    for fn in LOGS:
        p = root / ".fable-team" / "comm" / fn
        if not p.exists():
            continue
        found = True
        for n, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip():
                continue
            try:
                r = json.loads(line)
                by_seq.setdefault(int(r["seq"]), {"seq": int(r["seq"]), "ts": dt.datetime.fromisoformat(r["ts"]),
                                                  "from": str(r["from"]), "to": str(r["to"]), "body": str(r["body"])})
            except (ValueError, KeyError, TypeError):
                fail(f"{fn} {n}행 해석 실패")
    if not found:
        fail("우편 로그 파일 없음(mailbox.log.jsonl·.1) — 0 이 아니라 측정 실패")
    return [by_seq[k] for k in sorted(by_seq)]


def per_day(days: list[str]) -> dict:
    return dict(sorted(Counter(days).items()))


def succession(t0, t1) -> dict:
    first = {}
    for r in mail_rows():
        if t0 <= r["ts"] <= t1 and FROM_RE.match(r["from"]) and BODY_RE.match(r["body"]):
            if r["from"] not in first or r["ts"] < first[r["from"]]:
                first[r["from"]] = r["ts"]
    lineages = {lineage(f) for f in first}
    days = max((t1 - t0).total_seconds() / 86400, 1e-9)
    n = len(first) - len(lineages)
    return dict(raw=len(first), succession=n, first_boot=len(lineages), lineages=len(lineages), days=round(days, 2), per_day=round(n / days, 1))


def interview(t0, t1) -> dict:
    dirs = os.environ.get("FT_MEASURE_PROJECTS_DIRS") or str(Path.home() / ".claude/projects/-Users-yoonhwan-Project-Agent-BYZ-Work-BYZ-Agents*")
    roots = [d for pat in dirs.split() for d in glob.glob(pat) if os.path.isdir(d)]
    if not roots:
        fail("프로젝트 jsonl 폴더 없음 — 0 이 아니라 측정 실패")
    seen, days = set(), []
    for top in roots:
        for dp, _, fs in os.walk(top):
            for fn in fs:
                if not fn.endswith(".jsonl"):
                    continue
                with open(os.path.join(dp, fn), "rb") as fh:
                    for line in fh:
                        if b"AskUserQuestion" not in line:
                            continue
                        try:
                            rec = json.loads(line)
                            ts = dt.datetime.fromisoformat(str(rec["timestamp"]).replace("Z", "+00:00"))
                        except (ValueError, KeyError):
                            continue
                        utc = ts.astimezone(dt.timezone.utc).replace(tzinfo=None) if ts.tzinfo else ts  # UTC 일자(baseline 과 같은 자)
                        content = (rec.get("message") or {}).get("content") if rec.get("type") == "assistant" else None
                        for b in content if isinstance(content, list) else []:
                            if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "AskUserQuestion" \
                                    and b.get("id") not in seen and t0 <= utc <= t1:
                                seen.add(b.get("id")); days.append(utc.strftime("%F"))
    return dict(total=len(days), by_day=per_day(days))


def planner_mail(t0, t1) -> dict:
    """그 시각 현역 planner 앞 쪽지만 센다 — 현역 = 같은 계보 «부팅 보고» 쪽지(첫 1건·ts 오름차순) 중 쪽지 ts 직전의 마지막 좌석(현재 명부 0).
    첫 부팅 전 구간의 계보 앞 쪽지는 unclassified 로 따로 센다. 현역이 아닌(은퇴한) 같은 계보 좌석 앞 쪽지는 세지 않는다."""
    sp = root / ".fable-team" / "seats-planner.json"
    try:
        planner = lineage(json.loads(sp.read_text(encoding="utf-8"))["_master"])
    except (OSError, ValueError, KeyError):
        fail("seats-planner.json 의 _master 를 읽을 수 없음")
    rows = mail_rows()
    boots = {}
    for r in rows:
        if lineage(r["from"]) == planner and FROM_RE.match(r["from"]) and BODY_RE.match(r["body"]):
            boots[r["from"]] = min(boots.get(r["from"], r["ts"]), r["ts"])
    timeline = sorted((ts, seat) for seat, ts in boots.items())
    by_seat, days, unclassified = Counter(), [], 0
    for r in rows:
        if not (t0 <= r["ts"] <= t1 and lineage(r["to"]) == planner):
            continue
        active = next((seat for ts, seat in reversed(timeline) if ts <= r["ts"]), None)
        if active is None:
            unclassified += 1
        elif r["to"] == active:
            by_seat[active] += 1; days.append(r["ts"].strftime("%F"))
    return dict(planner=planner, total=sum(by_seat.values()), by_seat=dict(sorted(by_seat.items())), unclassified=unclassified, by_day=per_day(days))


if metric == "baseline":
    s, i = succession(t0, t1), interview(*(dt.datetime.fromisoformat(x) for x in BASELINE["interview"]))
    head.update(raw=s["raw"], succession=s["succession"], first_boot=s["first_boot"], interview=i["total"],
                window={"mailbox": list(BASELINE["mailbox"]), "interview": [BASELINE["interview"][0] + "Z", BASELINE["interview"][1] + "Z"]})
else:
    head.update({"succession": succession, "planner-mail": planner_mail, "interview": interview}[metric](t0, t1))
print(json.dumps(head, ensure_ascii=False))
PY
