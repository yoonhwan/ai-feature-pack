"""ft2 병렬 배정·실행권 계약 사례표 재생 검사기 (r1549).
`cases/*.json` 이 r1507 배정 실험·r1509 checker 관측과 1:1 인지 본다(읽기만 · 실험 코드 실행 0).
A 사례 수·id(ⓐ) B 칸 꼴·극성(ⓑ) C compare 1:1 D counts 1:1 E 키 소진 — 카드 ⓔ 는 시험 파일.
rc 0 통과 · 1 불일치 · 3 표 없음/빈 표 · 4 원자료 못 읽음(no silent fallback)
"""
import argparse
import json
import os
import subprocess
import sys

CASE_COUNT, SHA = 8, "db18c453c77868355ffeb813d3b4c49f2047806a"
DEFAULT_REPO = "~/Project/Agent/BYZ-Work/BYZ-Agents"  # 사례표 밖 원자료 = git show
BASE = "design/harness/research/ft-2.0/parallel-dispatch/checker-r1509"
PATHS = {"compare": BASE + "/compare.json", "판1": BASE + "/counts.json",
         "보정": BASE + "/raw2/counts2.json"}
COLS = (("dispatch", "dispatch_journal"), ("owner", "owner"), ("reserved", "reserved"),
        ("delivery", "delivery"), ("reassess", "reassess_journal"),
        ("release", "release_journal"), ("uncertain_release", "uncertain_release"))
TOP = {"id", "사례 이름", "축", "극성", "출처", "given", "expect"}
SRC_KEYS = {"정본 경로", "정본 sha", "함수", "줄", "비교 키", "관측 키"}
EXPECT_KEYS, ROW_KEYS = {"판정", "계약", "관측"}, {"키", "갈래", "원자료", "값"}
SOURCES, AXES, POLARITY = ("판1", "보정"), {"E1", "E2", "E3", "E4"}, {"정상", "변이", "주입"}

class TableBroken(Exception):
    """사례표·원자료를 읽을 수 없다 — rc≠0."""

def read_json(spec):
    try:
        if spec.startswith("git:"):
            repo, sha, path = spec[4:].split("@", 2)
            proc = subprocess.run(["git", "-C", os.path.expanduser(repo), "show",
                                   "%s:%s" % (sha, path)], capture_output=True)
            if proc.returncode != 0:
                raise TableBroken("git show 실패: %s" % proc.stderr.decode()[:200])
            blob = proc.stdout
        else:
            with open(spec, "rb") as fh:
                blob = fh.read()
        return json.loads(blob.decode("utf-8"))
    except (OSError, ValueError) as exc:
        raise TableBroken("원자료 못 읽음/JSON 아님: %s" % exc)

def read_cases(folder):
    names = sorted(n for n in os.listdir(folder) if n.endswith(".json")) if os.path.isdir(folder) else []
    if not names:
        raise TableBroken("사례 폴더 없음/빈 표: %s" % folder)
    return [read_json(os.path.join(folder, n)) for n in names]

def seven(values):
    out = {col: values.get(field) for col, field in COLS}
    if values.get("dispatch_state", out["dispatch"]) != out["dispatch"]:
        out["dispatch"] = "journal/state 불일치"      # 표가 journal·state 를 갈라 적으면 틀린 표다
    return out

def check_shape(cases):
    ids, pola, bad = [c.get("id") for c in cases], [c.get("극성") for c in cases], []
    for c in cases:
        cid, exp, src = c.get("id", "?"), c.get("expect") or {}, c.get("출처") or {}
        rows = exp.get("관측") or []
        rules = ((set(c) == TOP and set(src) == SRC_KEYS and set(exp) == EXPECT_KEYS, "칸"),
                 (bool(rows) and all(set(r) == ROW_KEYS and r["원자료"] in SOURCES for r in rows),
                  "관측 행"),
                 ([r["키"] for r in rows] == src.get("관측 키"), "관측 키 != 행 키"),
                 (c.get("축") in AXES and c.get("극성") in POLARITY and bool(c.get("given"))
                  and bool(exp.get("계약")) and exp.get("판정") in ("PASS", "FAIL"), "축/극성"),
                 ((c.get("극성") == "변이") == (exp.get("판정") == "FAIL"), "극성↔판정"))
        bad += ["%s %s" % (cid, why) for ok, why in rules if not ok]
    bad += ["%s id 접두/중복" % i for i in ids
            if not str(i).startswith("case_") or ids.count(i) > 1]
    return [(len(cases) == CASE_COUNT and not bad,
             "사례 %d/%d · 이상 %d" % (len(cases), CASE_COUNT, len(bad))),
            (not bad, "변이 %d(의도 FAIL 1) · 정상 %d · 주입 %d · 이상 %s" % (
                pola.count("변이"), pola.count("정상"), pola.count("주입"), bad[:2] or "0"))]

def check_compare(cases, cmp_doc, srcs):
    """C compare 1:1 · D counts 1:1(선언 칸 전부 — 7수 · 같은 attempt 억제 수 · attempt id)."""
    pairs, bad, rows = cmp_doc.get("pairs") or {}, [], []
    for c in cases:
        rows += c["expect"]["관측"]
        key, pair = c["출처"]["비교 키"], pairs.get(c["출처"]["비교 키"])
        mine = seven(c["expect"]["관측"][0]["값"])
        if pair is None:
            bad.append("%s pair 없음" % key)
            continue
        bad += ["%s %s %r≠%r" % (key, col, mine[col], pair["cols"][col]["checker"])
                for col, _ in COLS if mine[col] != pair["cols"][col]["checker"]
                or pair["cols"][col]["implementer"] != pair["cols"][col]["checker"]]
        if c["expect"]["판정"] != pair["verdict"]:
            bad.append("%s 판정 %s≠%s" % (key, c["expect"]["판정"], pair["verdict"]))
    if cmp_doc.get("cells") != len(pairs) * len(COLS) or cmp_doc.get("mismatch"):
        bad.append("compare 머리말 cells/mismatch")
    rows_bad = ["%s %s" % (r["키"], f) for r in rows for f, v in r["값"].items()
                if _observed(srcs[r["원자료"]], r["키"]).get(f, v) != v]
    if [f for _, f in COLS if f not in rows[0]["값"]]:
        rows_bad.append("첫 행 7수 누락")
    return (not bad, "pair %d × %d수 = %d칸 · 이상 %s" % (
        len(pairs), len(COLS), len(pairs) * len(COLS), bad[:3] or "0")), \
        (not rows_bad, "관측 행 %d · 선언 칸 전부 일치 · 이상 %s" % (len(rows),
                                                          rows_bad[:3] or "0"))

def _observed(doc, key):
    value = doc["cases"].get(key) or (doc["prefixes"] or {}).get(key)
    if value is None:
        raise TableBroken("%s 원자료 키 없음" % key)
    return value

def check_cover(cases, cmp_doc, srcs):
    """E 관측 키 소진 — 표에만/관측에만 0 · 같은 관측 키 재사용 0."""
    rows = [r for c in cases for r in c["expect"]["관측"]]
    mine, pairs, bad = {c["출처"]["비교 키"] for c in cases}, set(cmp_doc.get("pairs") or {}), []
    if mine ^ pairs:
        bad.append("비교 키 %s" % sorted(mine ^ pairs)[:3])
    for src in SOURCES:
        known = set(srcs[src]["cases"]) | set(srcs[src]["prefixes"] or {})
        declared = {r["키"] for r in rows if r["원자료"] == src}
        if declared - known or not declared or (src == "판1" and known - declared):
            bad.append("%s 키 %s" % (src, sorted(declared ^ known)[:3]))
    usage = [r["키"] for r in rows if r["키"] != "E4v-evidenceonly"]
    if {k for k in usage if usage.count(k) > 1}:
        bad.append("행 중복")
    return not bad, "비교 %d · 판1 %d · 보정 %d 키 소진 · 이상 %s" % (len(mine), *(
        len([r for r in rows if r["원자료"] == s]) for s in SOURCES), bad[:3] or "0")

def main(argv=None):
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description="ft2 병렬 배정·실행권 계약 사례표 재생 검사")
    ap.add_argument("--cases", default=os.path.join(here, "cases"))
    args = ap.parse_args(argv)
    try:
        cases = read_cases(args.cases)
        srcs = {n: read_json(p if p.startswith("git:") or os.path.exists(p) else
                             "git:%s@%s@%s" % (os.environ.get("FT2_BYZ_REPO", DEFAULT_REPO),
                                              os.environ.get("FT2_BYZ_SHA", SHA), p))
                for n, p in PATHS.items()}
        cmp_row, cnt_row = check_compare(cases, srcs["compare"], srcs)
        rows = list(zip(("A 사례 수·id", "B 칸 꼴·극성"), check_shape(cases))) + [
                ("C compare 1:1", cmp_row), ("D counts 1:1", cnt_row),
                ("E 관측 키 소진", check_cover(cases, srcs["compare"], srcs))]
    except TableBroken as exc:
        print("REPLAY-BROKEN: %s" % exc)
        return 3
    for name, (ok, detail) in rows:
        print("%s %s — %s" % ("PASS" if ok else "FAIL", name, detail))
    bad = [n for n, (ok, _) in rows if not ok]
    print("REPLAY %s — 통과 %d/%d" % ("OK" if not bad else "FAIL", len(rows) - len(bad), len(rows)))
    return 0 if not bad else 1

if __name__ == "__main__":
    sys.exit(main())
