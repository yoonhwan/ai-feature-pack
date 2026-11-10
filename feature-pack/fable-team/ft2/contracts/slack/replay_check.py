#!/usr/bin/env python3
"""ft2 Slack 사례 재생 검사기 — 표·사례·원자료 3자 대조(ⓐ 사례 수 ⓑ 계약 18줄 원문·사례 대응 ⓒ expect
↔ 원자료 결과 칸 ⓓ 키 3종·계약 낱말 ⓔ 비밀값 0). rc 0 통과 · 1 불일치 · 3 원자료 못 읽음."""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SECRET = re.compile(r"xox[abposre]-|xapp-\d")
MD = "CONTRACT-18.md"


def git(repo, sha, path, ls=False):
    sub = ["ls-tree", "--name-only", sha, path] if ls else ["show", f"{sha}:{path}"]
    p = subprocess.run(["git", "-C", str(repo)] + sub, capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(f"FAIL 원자료를 못 읽었다: {sha}:{path} rc={p.returncode} {p.stderr.strip()[:200]}")
    return [x for x in p.stdout.split() if x.endswith(".json")] if ls else p.stdout


def canonical(repo, sha):
    html = git(repo, sha, "design/harness/research/ft-2.0/slack.html")
    block = html[html.index("연결 계약 18줄"):]
    return re.findall(r"<li>(.*?)</li>", block[: block.index("</ol>")], re.S)


def load_cases(root):
    out = []
    for p in sorted((root / "cases").glob("*.json")):
        d = json.loads(p.read_text(encoding="utf-8"))
        d["_file"] = p.name
        out.append(d)
    return out


def parse_rows(md, head):
    """head 절의 markdown 표 데이터 행(셀 = | 분리 · 머리/구분선 제외)."""
    rows, on = [], False
    for line in md.splitlines():
        if line.startswith("## "):
            on = line[3:].strip() == head
            continue
        if on and line.startswith("|"):
            cells = [c.strip() for c in line.strip("|").split("|")]
            if set("".join(cells)) <= set("-: ") or cells[0] in ("줄", "id"):
                continue
            rows.append(cells)
    return rows


def case_ids(cell):
    return [] if cell.startswith("미시험") else [x.strip() for x in cell.split(",") if x.strip()]


def check(root, repo, sha=None):
    md = (root / MD).read_text(encoding="utf-8")
    cases = load_cases(root)
    if not cases:
        sys.exit("FAIL 사례 0 — cases/*.json 이 없으면 표가 아니다")
    sha = sha or cases[0]["source"]["sha"]
    lines, bad = canonical(repo, sha), []
    print(f"ⓐ 사례 표 {len(cases)}행 · 정본 계약 {len(lines)}줄 · sha {sha[:12]}")

    dirs = {c["source"]["path"].rsplit("/", 1)[0] for c in cases}
    if len(dirs) != 1:
        bad.append(f"사례 source 폴더가 갈린다: {sorted(dirs)[:3]}")
    raw_n = len(git(repo, sha, dirs.pop() + "/", ls=True))
    if raw_n != len(cases):
        bad.append(f"ⓐ 사례 수 불일치 — 표 {len(cases)} vs 원자료 {raw_n} (차이 {abs(len(cases) - raw_n)})")

    ids = [c["id"] for c in cases]
    if len(set(ids)) != len(ids):
        bad.append("사례 id 중복")
    derived = {n: [] for n in range(1, 19)}
    for c in cases:
        for n in c["contract"]:
            if n in derived:
                derived[n].append(c["id"])
            else:
                bad.append(f"ⓑ 사례 {c['id']}: 계약 번호 {n} 는 18줄 밖")
        for k in ("workspace", "channel", "ts"):
            if not str(c["given"].get(k, "")).strip():
                bad.append(f"ⓓ 사례 {c['id']}: given 키 {k} 없음")
        if not c["contract"]:
            if not c.get("contract_gap") or c["expect"]["words"]:
                bad.append(f"ⓓ 사례 {c['id']}: 계약 밖이면 contract_gap 1줄 · 계약 낱말 0")
        for w in c["expect"]["words"]:
            if not any(w in t for t in lines):
                bad.append(f"ⓓ 사례 {c['id']}: 낱말 «{w}» 가 계약 18줄 원문에 없다")
        raw = json.loads(git(repo, sha, c["source"]["path"]))
        if c["expect"]["observed"] != (want := {k: raw[k] for k in
                                               ("pass", "checks", "evidence_kind", "real_slack_calls")}):
            bad.append(f"ⓒ 사례 {c['id']}: expect 가 원자료 결과 칸과 다르다")
        if c["title"] != raw["case"]:
            bad.append(f"ⓒ 사례 {c['id']}: title 불일치 «{c['title']}» vs «{raw['case']}»")
        if raw["real_slack_calls"] != 0 or SECRET.search(json.dumps(c, ensure_ascii=False)):
            bad.append(f"ⓔ 사례 {c['id']}: 실 Slack 호출 {raw['real_slack_calls']} 또는 비밀값 꼴")
    if SECRET.search(md):
        bad.append("ⓔ CONTRACT-18.md 에 비밀값 꼴 문자열")
    rows = parse_rows(md, "대응표")
    if len(rows) != 18:
        bad.append(f"ⓑ 대응표 행 {len(rows)}개 (18 이어야 한다)")
    for n, cells in enumerate(rows, 1):
        if len(cells) < 3:
            bad.append(f"ⓑ 줄 {n}: 칸이 3개 미만")
            continue
        if n <= len(lines) and cells[1] != lines[n - 1]:
            bad.append(f"ⓑ 줄 {n}: 원문이 정본과 다르다")
        got, declared = sorted(derived.get(n, [])), sorted(case_ids(cells[2]))
        if got != declared:
            tag = "표시 미시험" if not declared else ("미시험이어야 한다" if not got else "대응 불일치")
            bad.append(f"ⓑ 줄 {n}: {tag} — 선언 {declared} vs 실제 {got} (차이 {len(set(got) ^ set(declared))})")
    mapped, covered = {i for v in derived.values() for i in v}, len([n for n, v in derived.items() if v])
    print(f"ⓑ 덮인 줄 {covered}/18 · 미시험 {18 - covered}줄 · 계약 밖 사례 "
          f"{len(set(ids) - mapped)} {sorted(set(ids) - mapped)}")

    for r in parse_rows(md, "사례 21 (원자료 순)"):
        d = next((c for c in cases if c["id"] == r[0]), None)
        if d is None:
            bad.append(f"ⓑ 사례표 행 {r[0]}: cases/ 에 없는 id")
            continue
        want = "계약 밖" if not d["contract"] else ", ".join(str(n) for n in d["contract"])
        if r[2] != want:
            bad.append(f"ⓑ 사례표 행 {r[0]}: 계약 줄 «{r[2]}» vs cases {want}")
        if r[1] != d["_file"]:
            bad.append(f"ⓑ 사례표 행 {r[0]}: 파일 «{r[1]}» vs {d['_file']}")

    if bad:
        for b in bad:
            print("FAIL " + b)
        print(f"결과 FAIL {len(bad)}건")
        return 1
    print("결과 PASS — ⓐⓑⓒⓓⓔ 전부 일치")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(HERE), help="계약 폴더(CONTRACT-18.md · cases/)")
    ap.add_argument("--byz", required=True, help="BYZ 리포(원자료 정본)")
    ap.add_argument("--sha", default=None, help="기본 = 사례 첫 파일의 source.sha")
    a = ap.parse_args()
    return check(Path(a.root), Path(a.byz), a.sha)


if __name__ == "__main__":
    sys.exit(main())
