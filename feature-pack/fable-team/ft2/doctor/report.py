"""ft2 doctor 보고 — 계약(r1550) 8필드 보고 1개를 «읽기만» 해서 만든다 (r1586 · PR④ 첫 장).

정본 ROUTE §3 ④ «doctor 최소 입출력» 의 앞 장이다. 하는 일은 셋뿐이다: ① 팀 runtime 의 state
revision 을 `core/record.read_state_guarded` 로 읽는다(쓰기 0) ② 그 상태로 보고 8필드 1개를 만든다
③ `contracts/doctor/schema_check.check` 로 자기 검사를 한다(위반 0 이 아니면 보고하지 않는다).
판독이 안 되면(받을 수 없는 state·runtime 없음) 숨기지 않고 `undetermined` + 사유로 드러낸다
(`docs/rules/no_silent_fallback.md`). 증상 탐지·국소 복구·재검증 실행은 이 카드 범위 밖이라
`allowed_recovery` 는 늘 비었고 `reverified.done` 은 늘 false 다.
"""
import argparse
import importlib.util
import json
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_FT2 = os.path.dirname(_HERE)
_SCHEMA_PATH = os.path.join(_FT2, "contracts", "doctor", "doctor-io.schema.json")
SYMPTOM = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
INSTALL_SHA = re.compile(r"^[0-9a-f]{40}$")


def _load(name, folder):
    """계약·코어 모듈을 경로로 읽는다(1.x import 0 · ft2 안 파일만)."""
    path = os.path.join(folder, name + ".py")
    spec = importlib.util.spec_from_file_location("ft2_doctor_" + name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


record = _load("record", os.path.join(_FT2, "core"))
schema_check = _load("schema_check", os.path.join(_FT2, "contracts", "doctor"))


class Refused(ValueError):
    """보고를 낼 수 없다 — 사유 1줄(CLI rc1 · stdout 0)."""


def state_path(root, team):
    """팀 runtime state 1곳 — 코어 `Intake` 와 같은 자리(읽기만 한다)."""
    return os.path.join(os.path.abspath(root), ".fable-team", "teams", team, "runtime", "state.json")


def check_inputs(symptom_key, install_sha, evidence, owner):
    """거절 사유 3종: 형식 위반·근거 0건·미해결 owner 없음(계약 if/then)."""
    if not isinstance(symptom_key, str) or not SYMPTOM.search(symptom_key):
        raise Refused("symptom_key 형식 위반: %r" % (symptom_key,))
    if not isinstance(install_sha, str) or not INSTALL_SHA.search(install_sha):
        raise Refused("install_sha 40자 소문자 hex 아님: %r" % (install_sha,))
    if not evidence:
        raise Refused("evidence 0건 — 근거 없는 보고는 내지 않는다")
    for one in evidence:
        if not isinstance(one, dict) or not str(one.get("source") or "").strip() \
                or not str(one.get("ref") or "").strip():
            raise Refused("evidence 칸 누락(source·ref): %r" % (one,))
    if not str(owner or "").strip():
        raise Refused("미해결 owner 없음 — open=true 보고에는 owner 가 필수다")


def read_revision(root, team):
    """state revision 을 읽는다. 판독 불가면 (0, 사유) — 예외를 삼키지 않고 사유로 옮긴다."""
    path = state_path(root, team)
    runtime = os.path.dirname(path)
    if not os.path.isdir(runtime):
        return 0, "runtime 없음: %s" % runtime
    try:
        return record.read_state_guarded(path)["revision"], None
    except record.CorruptStateError as exc:
        return 0, str(exc)


def build(root, team, symptom_key, install_sha, evidence, owner):
    """계약 8필드 보고 1개. 판독 불가는 `undetermined` + 사유, 보고는 그대로 낸다."""
    check_inputs(symptom_key, install_sha, evidence, owner)
    revision, reason = read_revision(root, team)
    observation = {"verdict": "observed"} if reason is None else {"verdict": "undetermined",
                                                                 "reason": reason}
    report = {
        "symptom_key": symptom_key,
        "install_sha": install_sha,
        "state_revision": revision,
        "evidence": [{"source": str(one["source"]).strip(), "ref": str(one["ref"]).strip()}
                     for one in evidence],
        "observation": observation,
        "allowed_recovery": [],
        "reverified": {"done": False},
        "unresolved": {"open": True, "owner": str(owner).strip()},
    }
    bad = schema_check.check(report, schema_check.read(_SCHEMA_PATH))
    if bad:
        raise Refused("계약 위반: " + "; ".join(bad[:3]))
    return report


def main(argv=None):
    """stdout = 보고 1개(rc0) · stderr = 거절 사유 1줄(rc1)."""
    parser = argparse.ArgumentParser(description="ft2 doctor 보고 1개(읽기만 · 쓰기 0)")
    parser.add_argument("--root", required=True)
    parser.add_argument("--team", required=True)
    parser.add_argument("--symptom-key", required=True)
    parser.add_argument("--install-sha", required=True)
    parser.add_argument("--evidence", action="append", default=[], metavar="SOURCE=REF")
    parser.add_argument("--owner", default="")
    args = parser.parse_args(argv)
    evidence = [{"source": source, "ref": ref}
                for source, _, ref in (one.partition("=") for one in args.evidence)]
    try:
        report = build(args.root, args.team, args.symptom_key, args.install_sha, evidence,
                       args.owner)
    except Refused as exc:
        print("거절: %s" % exc, file=sys.stderr)
        return 1
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
