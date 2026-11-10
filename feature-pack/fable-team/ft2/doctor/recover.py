"""ft2 doctor 복구·재검증·기억 환류 — 증상 1종을 코어 동사만으로 닫는다 (r1612 · PR④ 둘째 장).

r1586 `doctor/report.py` 는 «읽기만» 이라 `allowed_recovery` 가 늘 비고 `reverified.done` 이 늘 false 다.
이 파일이 그 자리를 잇는다. 증상 1종 = «좌석 부재인데 실행권을 쥔 일»(`symptom_key=seat.absent.holding`).
① `cli project` 로 투영을 읽어 owner(holder) 가 «살아 있는 좌석 목록» 에 없고 완료도 아닌 일을 찾는다
② 그 일마다 보고 8필드 1개를 `report.build` 로 만든다(계약·enum 은 r1586 그대로 · report.py 수정 0)
③ 허용 복구 1종 `cli.recover` 1회 — 이 파일은 state 를 직접 쓰지 않고 코어 동사만 부른다
④ `cli project` 를 다시 읽어 holder 가 놓였으면 `reverified.done=true` + revision, 아니면 `done=false` +
   `unresolved.open=true` + owner(복구가 실행권을 놓지 못한 사실을 숨기지 않는다)
⑤ 보고 1개마다 `doctor/memory.jsonl` 1줄 — 다음 진단은 같은 증상의 그 이전 줄을 evidence 로 단다
판독이 안 되면 복구 0 · 보고는 `undetermined` + 사유로 낸다(`docs/rules/no_silent_fallback.md`).
"""
import argparse
import importlib.util
import json
import os
import subprocess
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
_FT2 = os.path.dirname(_HERE)
CLI = os.path.join(_FT2, "core", "cli.py")
SCHEMA_PATH = os.path.join(_FT2, "contracts", "doctor", "doctor-io.schema.json")
SYMPTOM, RECOVERY, TIMEOUT = "seat.absent.holding", "cli.recover", 7    # 외부 호출 1회 7초(하드 룰 12)
OK, CORRUPT, NONE = "접수 성공", "복구 필요", "증상 없음"


def _load(name, folder):
    """계약·보고 모듈을 경로로 읽는다(1.x import 0 · ft2 안 파일만)."""
    path = os.path.join(folder, name + ".py")
    spec = importlib.util.spec_from_file_location("ft2_doctor_recover_" + name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


report = _load("report", _HERE)          # 8필드 보고·계약 검사는 r1586 그대로 쓴다(수정 0)


def run_cli(verb, root, team):
    """코어 동사 1회 — stdout JSON 1줄. 못 읽으면 (복구 필요, 사유) 로 접는다(숨김 0)."""
    try:
        done = subprocess.run([sys.executable, CLI, verb, "--root", root, "--team", team],
                              capture_output=True, text=True, timeout=TIMEOUT)
        return json.loads(done.stdout or "")
    except (subprocess.TimeoutExpired, ValueError) as exc:
        return {"result": CORRUPT, "reason": "%s 판독 실패(제한 %d초): %s" % (verb, TIMEOUT, exc)}


def live_missing(projection, live):
    """투영 → [(work, holder)] — 살아 있는 좌석 목록에 없는 holder 가 쥔, 완료 아닌 일(오름차순)."""
    rows = sorted((projection.get("works") or {}).items())
    return [(work, (row.get("owner") or {}).get("holder")) for work, row in rows
            if not row.get("done") and (row.get("owner") or {}).get("holder") not in set(live) | {None}]


def _remember(path, at, work, holder, revision, recovery, reverified, after):
    """기억 1줄 덧붙임 — 증상·결과·revision(폴더가 없으면 만든다 · 1보고 = 1줄 · UTF-8)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    line = {"at": at, "symptom_key": SYMPTOM, "work": work, "holder": holder, "revision": revision,
            "recovery": recovery, "reverified": reverified, "revision_after": after}
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(line, ensure_ascii=False, sort_keys=True) + "\n")


def _evidence(path, root, work, holder, revision):
    """보고 근거 — work·holder·revision + 같은 증상의 이전 기억 줄 1개(파일 없음 = 이전 0 · 오류 아님)."""
    out = [{"source": "cli/project", "ref": "works.%s.owner=%s" % (work, holder)},
           {"source": "cli/project", "ref": "revision=%d" % revision}]
    seen = None
    for number, line in enumerate(open(path, encoding="utf-8") if os.path.isfile(path) else [], 1):
        try:
            one = json.loads(line)
        except ValueError:
            continue                      # 깨진 줄은 그 줄만 건너뛴다(진단을 멈추지 않는다)
        seen = number if isinstance(one, dict) and one.get("symptom_key") == SYMPTOM else seen
    return out + ([{"source": os.path.relpath(path, root), "ref": "line=%d" % seen}] if seen else [])


def _report(root, team, install_sha, owner, evidence, reason="", released=False, after=0):
    """보고 8필드 1개 — reason 이 있으면 판정불가(복구 0), 없으면 복구·재검증 결과를 싣는다."""
    one = report.build(root, team, SYMPTOM, install_sha, evidence, owner)
    if reason:                                   # 판정 불가 — 판독 실패를 숨기지 않는다
        one["observation"] = {"verdict": "undetermined", "reason": "cli project 판독 불가: " + reason}
    else:
        one["allowed_recovery"] = [RECOVERY]
        one["reverified"] = ({"done": True, "evidence_ref": "cli/project revision=%d" % after}
                             if released else {"done": False})
        one["unresolved"] = {"open": False} if released else one["unresolved"]
    bad = report.schema_check.check(one, report.schema_check.read(SCHEMA_PATH))
    if bad:                                     # 계약 위반이면 보고하지 않는다(report.py 와 같은 태도)
        raise report.Refused("계약 위반: " + "; ".join(bad[:3]))
    return one


def diagnose(root, team, live, install_sha, owner):
    """진단 → 복구 1회 → 재검증 → 기억 1줄. 판독 불가는 복구 0, 증상 0 은 쓰기 0."""
    root, at = os.path.abspath(root), os.environ.get("FT_NOW") or time.strftime("%Y-%m-%dT%H:%M:%S")
    path = os.path.join(root, ".fable-team", "teams", team, "doctor", "memory.jsonl")
    before = run_cli("project", root, team)
    if before.get("result") != OK:                       # 판정 불가 = 복구 0 · 보고는 낸다
        one = _report(root, team, install_sha, owner,
                      [{"source": "cli/project", "ref": "result=%s" % before.get("result")}],
                      reason=str(before.get("reason") or before.get("result")))
        _remember(path, at, "", "", one["state_revision"], "", False, one["state_revision"])
        return {"result": CORRUPT, "team": team, "state_revision": one["state_revision"],
                "reports": [one], "recovery": {"verb": "", "calls": 0, "result": ""},
                "reason": one["observation"]["reason"]}
    found = live_missing(before, live)
    if not found:                                        # 증상 0 = 복구 0 · 쓰기 0
        return {"result": NONE, "team": team, "state_revision": before.get("revision", 0),
                "reports": [], "recovery": {"verb": "", "calls": 0, "result": ""}, "reason": ""}
    recovery = run_cli("recover", root, team)
    after = run_cli("project", root, team)
    reports = []
    for work, holder in found:
        row = (after.get("works") or {}).get(work) or {}
        released = not row.get("done") and not (row.get("owner") or {}).get("holder")
        reports.append(_report(root, team, install_sha, owner,
                               _evidence(path, root, work, holder, before.get("revision", 0)),
                               released=released, after=after.get("revision", 0)))
        _remember(path, at, work, holder, before.get("revision", 0),
                  recovery.get("result", ""), released, after.get("revision", 0))
    return {"result": OK, "team": team, "state_revision": before.get("revision", 0),
            "reports": reports, "recovery": {"verb": RECOVERY, "calls": 1,
                                             "result": recovery.get("result", "")}, "reason": ""}


def main(argv=None):
    """stdout = 진단 1개(JSON · rc0) · stderr = 거절 사유 1줄(rc1). 복구는 코어 동사로만 한다."""
    parser = argparse.ArgumentParser(description="ft2 doctor 복구·재검증·기억 환류(복구 1종)")
    for name in ("root", "team", "install-sha", "owner"):        # 빠지면 rc64 · 쓰기 0
        parser.add_argument("--" + name, required=True)
    parser.add_argument("--live-seat", action="append", default=[], metavar="좌석")
    args = parser.parse_args(argv)
    try:
        out = diagnose(args.root, args.team, args.live_seat, args.install_sha, args.owner)
    except report.Refused as exc:
        print("거절: %s" % exc, file=sys.stderr)
        return 1
    print(json.dumps(out, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
