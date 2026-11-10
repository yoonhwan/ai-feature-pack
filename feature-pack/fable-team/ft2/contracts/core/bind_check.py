"""ft2 코어 상태 계약 의미 결속 검사기 (r1546 · DA R1 보정).

사례표의 의미 expect(처리 결과 · 상태 revision 변화)를 원자료에 결속한다.
  F 결속 = bindings.json 의 실험 낱말·관측이 원자료 results/<폴더>.json 과 같고,
           낱말→계약 낱말 유도와 revision 유도가 expect 와 같은가
  G 출처 = 출처.sha@경로를 git show 로 읽어 함수 정의·근거 문구가 출처.줄 안에 있는가
rc 0 통과 · 1 불일치 · 3 결속표 미비 · 4 원자료 못 읽음(no silent fallback)
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CASES = os.path.join(HERE, "cases")
BINDINGS = os.path.join(HERE, "bindings.json")
RAW = "design/harness/research/ft-2.0/sim-atomic-json/results/%s.json"
DEFAULT_REPO = "/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents"
RESULT_CODES = {
    "ACCEPTED": "접수 성공", "REJECTED": "접수 거부", "REFUSED": "접수 거부",
    "FULL": "용량 부족", "PENDING_CAP": "용량 부족", "PRUNED": "회수 결과",
    "CORRUPT_STATE": "복구 필요",
    "STALE_OWNER": "낡은 실행권", "EXPIRED": "낡은 실행권",
    "BUSY": "BUSY",
    "UNCERTAIN": "완료 유보", "BLOCKED_UNCERTAIN": "완료 유보", "IN_PROGRESS": "완료 유보",
    "DEFERRED": "완료 유보", "RETRY": "완료 유보",
    "EXTERNAL_WAIT_WITHIN_DEADLINE": "완료 유보",
}
_CACHE = {}


class Broken(Exception):
    """결속표·원자료를 읽을 수 없다 — rc≠0."""


def blob(repo, sha, path):
    key = (repo, sha, path)
    if key not in _CACHE:
        proc = subprocess.run(["git", "-C", repo, "show", "%s:%s" % (sha, path)],
                              capture_output=True)
        if proc.returncode != 0:
            raise Broken("원자료 못 읽음: %s (sha %s)" % (path, sha[:12]))
        _CACHE[key] = proc.stdout.decode("utf-8")
    return _CACHE[key]


def load_cases():
    if not os.path.isdir(CASES):
        raise Broken("사례 폴더 없음: %s" % CASES)
    names = sorted(n for n in os.listdir(CASES) if n.endswith(".json") and not n.startswith("_"))
    if not names:
        raise Broken("빈 표: %s" % CASES)
    docs = [json.loads(open(os.path.join(CASES, n), "rb").read().decode("utf-8")) for n in names]
    return {doc["id"]: doc for doc in docs}


def load_bindings():
    if not os.path.exists(BINDINGS):
        raise Broken("결속표 없음: %s" % BINDINGS)
    return json.loads(open(BINDINGS, "rb").read().decode("utf-8")).get("사례 결속") or {}


def raw_checks(repo, case):
    src = case.get("출처") or {}
    text = blob(repo, src.get("정본 sha", ""), RAW % (src.get("폴더") or "?"))
    return {chk["label"]: chk for chk in json.loads(text)["checks"]}


def revision_changed(observed):
    if isinstance(observed, dict):
        if "revision_before" in observed and "revision_after" in observed:
            return observed["revision_before"] != observed["revision_after"]
        if "same_keys" in observed:
            return not observed["same_keys"]
        if "before" in observed and "after" in observed:
            return observed["before"] != observed["after"]
    return True


def check_binding(repo, cases, bound):
    bad = []
    if set(bound) != set(cases):
        bad.append("결속표 %s" % sorted(set(bound) ^ set(cases))[:3])
    for cid, case in sorted(cases.items()):
        entry, expect, raw = bound.get(cid) or {}, case["expect"], raw_checks(repo, case)
        word = entry.get("실험 낱말")
        if RESULT_CODES.get(word) != expect["처리 결과"]:
            bad.append("%s 낱말 유도" % cid)
        pairs = ((expect["근거 검증"], entry.get("관측")),
                 (entry.get("revision 검증"), entry.get("revision 관측")))
        for label, observed in pairs:
            chk = raw.get(label) or {}
            if chk.get("ok") is not True or chk.get("observed") != observed:
                bad.append("%s 관측 %s" % (cid, label))
        text = json.dumps(list(raw.values()), ensure_ascii=False) + blob(
            repo, case["출처"]["정본 sha"], case["출처"]["정본 경로"])
        if not word or word not in text:
            bad.append("%s 낱말 원자료 없음 %s" % (cid, word))
        rev = raw.get(entry.get("revision 검증") or "") or {}
        if "observed" in rev and revision_changed(rev["observed"]) != expect["상태 revision 변화"]:
            bad.append("%s revision 유도" % cid)
    return not bad, "사례 %d · 이상 %s" % (len(cases), bad[:3] or "0")


def check_source(repo, cases, bound):
    bad = []
    for cid, case in sorted(cases.items()):
        src = case["출처"]
        sha = src.get("정본 sha", "")
        if len(sha) != 40:
            bad.append("%s sha 길이 %d" % (cid, len(sha)))
            continue
        lines = blob(repo, sha, src["정본 경로"]).splitlines()
        start, _, end = str(src.get("줄", "")).partition("-")
        lo, hi = int(start or 0), int(end or start or 0)
        if not 1 <= lo <= hi <= len(lines):
            bad.append("%s 줄 범위 %s" % (cid, src.get("줄")))
            continue
        body = "\n".join(lines[lo - 1:hi])
        if ("def %s(" % src.get("함수")) not in body:
            bad.append("%s 함수 정의 없음" % cid)
        entry = bound.get(cid) or {}
        for label in (case["expect"]["근거 검증"], entry.get("revision 검증")):
            if label not in body:
                bad.append("%s 근거 문구 없음 %s" % (cid, label))
    return not bad, "출처 %d · 이상 %s" % (len(cases), bad[:3] or "0")


def run_checks(repo=DEFAULT_REPO):
    cases, bound = load_cases(), load_bindings()
    results = {"F 의미 결속": check_binding(repo, cases, bound),
               "G 출처 실재": check_source(repo, cases, bound)}
    return [(name, ok, detail) for name, (ok, detail) in results.items()]


def main(argv=None):
    parser = argparse.ArgumentParser(description="ft2 코어 상태 계약 의미 결속 검사")
    parser.add_argument("--repo", default=os.environ.get("FT20_BYZ_REPO") or DEFAULT_REPO)
    args = parser.parse_args(argv)
    try:
        rows = run_checks(args.repo)
    except Broken as exc:
        print("BIND-BROKEN: %s" % exc)
        return 4
    except ValueError as exc:
        print("BIND-BROKEN: 원자료가 JSON 이 아님 — %s" % exc)
        return 4
    for name, ok, detail in rows:
        print("%s %s — %s" % ("PASS" if ok else "FAIL", name, detail))
    bad = [name for name, ok, _ in rows if not ok]
    print("BIND %s — 통과 %d/%d" % ("OK" if not bad else "FAIL", len(rows) - len(bad), len(rows)))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
