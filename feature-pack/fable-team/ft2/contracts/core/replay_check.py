"""ft2 코어 상태 계약 사례표 재생 검사기 (r1546).

사례표(cases/*.json)가 r1496·r1497 원자료 관측과 1:1 인지 본다. 실험 코드 실행 0 · 원자료 읽기만.
A 사례 수·id 12 · B 4칸·정본 결과 낱말 7군 · C 관측 1:1(13키) · D «비채택: …» 표시 · E literal 은 출처 칸만
rc 0 통과 · 1 불일치 · 3 사례 폴더 없음/빈 표 · 4 원자료 못 읽음(no silent fallback)
"""
import argparse
import json
import os
import subprocess
import sys

CASE_COUNT = 12
RUN_FILE = "_judge-run.json"
RESULT_WORDS = ("접수 성공", "접수 거부", "복구 필요", "낡은 실행권",
                "BUSY", "용량 부족", "완료 유보", "회수 결과")
TOP_KEYS = {"id", "사례 이름", "출처", "given", "expect", "비채택"}
EXPECT_KEYS = {"처리 결과", "상태 revision 변화", "근거 검증", "관측 대조"}
SOURCE_KEYS = {"정본 경로", "정본 sha", "함수", "줄", "실험 literal 필드명"}
JUDGE_ROW_KEYS = {"원자료 키", "관측"}
NONADOPT = "비채택: "


class TableBroken(Exception):
    """사례표·원자료를 읽을 수 없다 — rc≠0."""


def read_json(path):
    with open(path, "rb") as fh:
        return json.loads(fh.read().decode("utf-8"))


def read_cases(folder):
    names = sorted(n for n in os.listdir(folder)
                   if n.endswith(".json") and not n.startswith("_")) if os.path.isdir(folder) else []
    if not names:
        raise TableBroken("사례 폴더 없음/빈 표: %s" % folder)
    return [read_json(os.path.join(folder, n)) for n in names]


def check_count(cases):
    ids = [c.get("id") for c in cases]
    bad = [i for i in ids if not isinstance(i, str) or not i.startswith("case_")]
    dup = {i for i in ids if isinstance(i, str) and ids.count(i) > 1}
    return (len(cases) == CASE_COUNT and not bad and not dup,
            "사례 %d/%d · id 이상 %d · 중복 %d" % (len(cases), CASE_COUNT, len(bad), len(dup)))


def check_shape(cases):
    bad, bad_e, bad_d, total = [], [], [], 0
    for case in cases:
        cid, expect = case.get("id", "?"), case.get("expect") or {}
        literals = (case.get("출처") or {}).get("실험 literal 필드명") or []
        if set(case) != TOP_KEYS:
            bad.append("%s 칸 %s" % (cid, sorted(set(case) ^ TOP_KEYS)))
        elif set(expect) != EXPECT_KEYS:
            bad.append("%s expect 칸" % cid)
        elif expect["처리 결과"] not in RESULT_WORDS:
            bad.append("%s 결과 낱말 %r" % (cid, expect["처리 결과"]))
        if not isinstance(expect.get("상태 revision 변화"), bool):
            bad.append("%s revision 변화 bool 아님" % cid)
        if not case.get("given"):
            bad.append("%s given 0" % cid)
        if set(case.get("출처") or {}) != SOURCE_KEYS:
            bad.append("%s 출처 칸" % cid)
        if not literals:
            bad_e.append("%s literal 0" % cid)
        bad_e.extend("%s literal %s" % (cid, n) for n in literals if n in case or n in expect)
        for entry in case.get("비채택") or []:
            total += 1
            mark = entry.get("표시", "")
            if not mark.startswith(NONADOPT) or len(mark) <= len(NONADOPT) + 6 \
                    or not entry.get("관측"):
                bad_d.append("%s 비채택 꼴" % cid)
    return ((not bad, "사례 %d · 이상 %s" % (len(cases), bad[:3] or "0")),
            (not bad_e, "literal 은 출처 칸만 · 이상 %s" % (bad_e[:3] or "0")),
            (not bad_d and total > 0, "비채택 %d건 · 이상 %s" % (total, bad_d[:3] or "0")))


def check_judge(cases, run_doc, judge):
    rows = [(c.get("id"), r) for c in cases for r in c["expect"]["관측 대조"]]
    rows += [(RUN_FILE, r) for r in run_doc.get("관측 대조", [])]
    bad, keys = [], []
    for cid, row in rows:
        key = row.get("원자료 키")
        if set(row) != JUDGE_ROW_KEYS or not key:
            bad.append("%s 관측 칸" % cid)
            continue
        keys.append(key)
        bad.extend([] if judge.get(key, row["관측"]) == row["관측"] else ["%s 값 불일치" % key])
    for label, diff in (("중복 키", sorted({k for k in keys if keys.count(k) > 1})),
                        ("원자료에만", sorted(set(judge) - set(keys))),
                        ("표에만", sorted(set(keys) - set(judge)))):
        if diff:
            bad.append("%s %s" % (label, diff))
    if [k for k, v in judge.items() if not v.get("ok")]:
        bad.append("원자료 ok 아님")
    ok = not bad and len(keys) == len(judge)
    return ok, "대조 %d/%d 키 · 이상 %s" % (len(keys), len(judge), bad[:3] or "0")


def run_checks(cases_dir, judge):
    cases = read_cases(cases_dir)
    run_path = os.path.join(cases_dir, RUN_FILE)
    if not os.path.exists(run_path):
        raise TableBroken("회차 관측 파일 없음: %s" % run_path)
    shape, semantic, nonadopt = check_shape(cases)
    checked = [("A 사례 수·id", check_count(cases)), ("B 칸·결과 낱말", shape),
               ("C 관측 1:1", check_judge(cases, read_json(run_path), judge)),
               ("D 비채택 표시", nonadopt), ("E 의미 이름", semantic)]
    return [(name, ok, detail) for name, (ok, detail) in checked]


def load_judge(spec):
    if spec.startswith("git:"):
        repo, sha, path = spec[4:].split("@", 2)
        proc = subprocess.run(["git", "-C", repo, "show", "%s:%s" % (sha, path)],
                              capture_output=True)
        if proc.returncode != 0:
            raise TableBroken("원자료 git show 실패: %s" % proc.stderr.decode()[:200])
        return json.loads(proc.stdout.decode("utf-8"))
    if not os.path.exists(spec):
        raise TableBroken("원자료 없음: %s" % spec)
    return read_json(spec)


def main(argv=None):
    here = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description="ft2 코어 상태 계약 사례표 재생 검사")
    parser.add_argument("--cases", default=os.path.join(here, "cases"))
    parser.add_argument("--judge", required=True, help="원자료 경로 또는 git:<repo>@<sha>@<경로>")
    args = parser.parse_args(argv)
    try:
        rows = run_checks(args.cases, load_judge(args.judge))
    except TableBroken as exc:
        print("REPLAY-BROKEN: %s" % exc)
        return 3
    except ValueError as exc:
        print("REPLAY-BROKEN: 원자료가 JSON 이 아님 — %s" % exc)
        return 4
    for name, ok, detail in rows:
        print("%s %s — %s" % ("PASS" if ok else "FAIL", name, detail))
    bad = [name for name, ok, _ in rows if not ok]
    print("REPLAY %s — 통과 %d/%d" % ("OK" if not bad else "FAIL", len(rows) - len(bad), len(rows)))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
