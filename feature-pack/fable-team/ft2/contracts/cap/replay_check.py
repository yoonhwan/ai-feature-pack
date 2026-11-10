"""ft2 기록 cap·회전 계약 사례표 재생 검사기 (r1548 · DA R1 보정).

원자료(checker results/*.json)는 git show 로 읽기만 한다(실험 코드 실행 0). A 사례 4 · B 칸·낱말 · C 관측 1:1(44키) ·
D 수치는 후보값 표식 · E 미처리 삭제 0 · F 낱말↔관측 결속 · rc 0 통과 / 1 불일치 / 3 원자료 없음(빈 통과 0) / 4 JSON 아님
"""
import argparse
import json
import os
import re
import subprocess
import sys
CASE_COUNT, OBS_KEY_COUNT = 4, 44
CHECKER_FILE, SOURCE_FILE, OBS_KEYS = "_checker.json", "_source.json", {"원자료 키", "관측"}
RESULT_WORDS = ("접수 성공", "접수 거부", "복구 필요", "낡은 실행권", "BUSY", "용량 부족", "완료 유보", "회수 결과")
BINDING = {"회수 결과": ("/seg_unlink", "gt", 0), "복구 필요": ("/restart/recover_use_recount", "gt", 0),
           "용량 부족": ("/max_total", "ratio", 0.9), "접수 성공": ("/journal_append_rows", "gt", 0)}
TOP_KEYS = {"id", "사례 이름", "출처", "given", "expect", "비채택"}
EXPECT_KEYS = {"처리 결과", "근거 검증", "관측 대조"}
SOURCE_KEYS = {"정본 경로", "정본 sha", "함수", "줄", "실험 literal 필드명"}
NONADOPT, FORBIDDEN = "비채택: ", ("DROP_OLDEST", "미처리 삭제", "오래된 순 삭제")
NUM = re.compile(r"\d[\d,]*\s*(?:B|KiB|MiB|GiB|초|%)|\d{1,3}(?:,\d{3})+|\d{4,}")
TableBroken = RuntimeError  # 사례표·원자료를 읽을 수 없다 — rc≠0
def read_json(path):
    return json.loads(open(path, "rb").read().decode("utf-8"))
def read_cases(folder):
    names = sorted(n for n in os.listdir(folder) if n.endswith(".json") and not n.startswith("_")) if os.path.isdir(folder) else []
    if not names:
        raise TableBroken("사례 폴더 없음/빈 표: %s" % folder)
    return [read_json(os.path.join(folder, n)) for n in names]
def load_sources(manifest, repo):
    out, sha, folder = {}, manifest["정본 sha"], manifest["정본 폴더"]
    for alias, name in manifest["파일"].items():
        proc = subprocess.run(["git", "-C", repo, "show", "%s:%s/%s" % (sha, folder, name)],
                              capture_output=True)
        if proc.returncode != 0:  # no silent fallback — 원자료가 없으면 표 검사도 없다
            raise TableBroken("원자료 git show 실패 %s: %s" % (name, proc.stderr.decode()[:160]))
        out[alias] = json.loads(proc.stdout.decode("utf-8"))
    return out
def pointer(doc, path):  # JSON pointer(/a/b/0 · ~1 = /)
    for raw in path.split("/")[1:]:
        doc = doc[int(raw)] if isinstance(doc, list) else doc[raw.replace("~1", "/")]
    return doc
def check_count(cases):
    ids = [c.get("id") for c in cases]
    bad = [i for i in ids if not isinstance(i, str) or not i.startswith("case_")]
    return (len(cases) == CASE_COUNT and not bad and len(set(ids)) == len(ids),
            "사례 %d/%d · id 이상 %d · 중복 %d" % (len(cases), CASE_COUNT, len(bad), len(ids) - len(set(ids))))
def check_shape(cases):
    bad = []
    for case in cases:
        cid, expect = case.get("id", "?"), case.get("expect") or {}
        literals = (case.get("출처") or {}).get("실험 literal 필드명") or []
        if set(case) != TOP_KEYS:
            bad.append("%s 칸 %s" % (cid, sorted(set(case) ^ TOP_KEYS)))
        elif set(expect) != EXPECT_KEYS:
            bad.append("%s expect 칸" % cid)
        elif expect["처리 결과"] not in RESULT_WORDS:
            bad.append("%s 결과 낱말 %r" % (cid, expect["처리 결과"]))

        if not case.get("given") or set(case.get("출처") or {}) != SOURCE_KEYS:
            bad.append("%s given/출처 칸" % cid)
        if not literals:
            bad.append("%s literal 0" % cid)
        bad.extend("%s literal %s" % (cid, n) for n in literals if n in case or n in expect)
    return not bad, "사례 %d · 이상 %s" % (len(cases), bad[:3] or "0")
def check_observations(cases, checker, sources):
    rows = [r for c in cases for r in c["expect"]["관측 대조"]] + list(checker.get("관측 대조") or [])
    bad, keys = [], []
    for row in rows:
        key = row.get("원자료 키")
        if set(row) != OBS_KEYS or not key or "#" not in key:
            bad.append("관측 칸/키 꼴 %r" % key)
            continue
        keys.append(key)
        alias, path = key.split("#", 1)
        try:
            got = pointer(sources[alias], path)
        except (KeyError, IndexError, ValueError, TypeError):
            bad.append("%s 원자료에 없음" % key)
            continue
        if got != row["관측"]:
            bad.append("%s 값 불일치 %r" % (key, got))
    dup = sorted({k for k in keys if keys.count(k) > 1})
    bad += ["중복 키 %s" % dup[:3]] if dup else []
    if len(keys) != OBS_KEY_COUNT:
        bad.append("키 수 %d/%d" % (len(keys), OBS_KEY_COUNT))
    return not bad, "관측 %d/%d 키 · 이상 %s" % (len(keys), OBS_KEY_COUNT, bad[:3] or "0")
def check_binding(cases):
    bad = []
    for case in cases:
        expect = case.get("expect") or {}
        suffix, kind, thr = BINDING[expect.get("처리 결과")]
        vals = {r["원자료 키"].split("#", 1)[-1]: r["관측"] for r in expect.get("관측 대조") or []}
        hit = False
        for key, val in vals.items():
            cap = vals.get(key[: -len(suffix)] + "/cap")
            if key.endswith(suffix) and isinstance(val, int):
                hit = hit or ((cap is not None and val / cap >= thr) if kind == "ratio" else val > thr)
        bad += [] if hit else ["%s 낱말 %s 를 뒷받침하는 관측 없음" % (case.get("id"), expect.get("처리 결과"))]
    return not bad, "낱말 결속 %d · 이상 %s" % (len(cases), bad[:3] or "0")
def check_numbers(cases):
    total, bad = 2 * len(cases), []
    for case in cases:
        cid, expect = case.get("id"), case.get("expect") or {}
        for text in (expect.get("처리 결과"), expect.get("근거 검증")):
            if isinstance(text, str) and NUM.search(text) and "후보값" not in text:
                bad.append("%s 수치에 후보값 표식 없음" % cid)
        total += len(case.get("비채택") or [])
        for entry in case.get("비채택") or []:
            mark, obs = entry.get("표시", ""), entry.get("관측")
            good = mark.startswith(NONADOPT) and len(mark) > len(NONADOPT) + 6 and obs
            bad += [] if good else ["%s 비채택 꼴" % cid]
    return not bad, "검사 %d · 이상 %s" % (total, bad[:3] or "0")
def check_no_delete(cases):
    bad = []
    for case in cases:
        text = json.dumps({k: v for k, v in case.items() if k != "비채택"}, ensure_ascii=False)
        bad.extend("%s 기대에 미처리 삭제 %r" % (case.get("id"), t) for t in FORBIDDEN if t in text)
    return not bad, "비채택 밖 미처리 삭제 기대 0 · 이상 %s" % (bad[:3] or "0")

def run_checks(cases_dir, sources):
    cases = read_cases(cases_dir)
    checker_path = os.path.join(cases_dir, CHECKER_FILE)
    if not os.path.exists(checker_path):
        raise TableBroken("checker 관측 파일 없음: %s" % checker_path)
    checked = [("A 사례 수·id", check_count(cases)), ("B 칸·결과 낱말", check_shape(cases)),
               ("C 관측 1:1", check_observations(cases, read_json(checker_path), sources)), ("D 후보값 표식", check_numbers(cases)),
               ("E 미처리 삭제 0", check_no_delete(cases)), ("F 낱말 결속", check_binding(cases))]
    return [(name, ok, detail) for name, (ok, detail) in checked]
def main(argv=None):
    parser = argparse.ArgumentParser(description="ft2 기록 cap 계약 사례표 재생 검사")
    parser.add_argument("--cases", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "cases"))
    parser.add_argument("--repo", default=os.environ.get("FT20_BYZ_REPO"), help="원자료가 있는 BYZ 저장소 경로")
    args = parser.parse_args(argv)
    try:
        if not args.repo:
            raise TableBroken("원자료 저장소 없음 — --repo 또는 FT20_BYZ_REPO 를 지정해야 한다")
        manifest = read_json(os.path.join(args.cases, SOURCE_FILE))
        rows = run_checks(args.cases, load_sources(manifest, args.repo))
    except (TableBroken, ValueError) as exc:  # 원자료를 못 읽으면 빈 표로 통과하지 않는다
        print("REPLAY-BROKEN(%s): %s" % (type(exc).__name__, exc))
        return 3 if isinstance(exc, TableBroken) else 4
    for name, ok, detail in rows:
        print("%s %s — %s" % ("PASS" if ok else "FAIL", name, detail))
    bad = [name for name, ok, _ in rows if not ok]
    print("REPLAY %s — 통과 %d/%d" % ("OK" if not bad else "FAIL", len(rows) - len(bad), len(rows)))
    return 0 if not bad else 1

if __name__ == "__main__":
    sys.exit(main())
