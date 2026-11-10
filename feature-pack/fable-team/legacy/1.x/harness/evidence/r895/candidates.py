#!/usr/bin/env python3
"""r895 candidates.py <raw 폴더> — 표에 싣는 «한 줄 = 한 후보» 를 만든다(읽기 전용 · 삭제 0).

r1(10-25)은 이 파일을 손으로 만들었다. r2 는 같은 표를 «다시 만들 수 있게» 스크립트로 남긴다.
입력: <리포>-classified.tsv(경로·가지·HEAD·KiB·미커밋·착지·분류) + sparse.tsv(있으면) + scratch-owner.txt(있으면)
출력: <리포>-candidates.tsv — path · GiB · branch · head · land · real_dirty · class · sparse · owner_hint
      표(TABLE)는 이 파일의 «큰 행» 만 인용한다. 정렬 = class → GiB 내림차순.
"""
import csv, os, sys

raw = sys.argv[1]


def load_tsv(p, key="path"):
    if not os.path.exists(p):
        return {}
    return {r[key]: r for r in csv.DictReader(open(p), delimiter="\t")}


def rank(cls):
    """표는 «지울 수 있는 것» 부터 보여 준다: 안 → 안후보 → 밖 → keep → 사라짐 · 그 안에서 GiB 큰 것 부터."""
    for i, p in enumerate(("안:", "안후보:", "밖:", "keep:", "사라짐")):
        if cls.startswith(p):
            return i
    return 9


def owner_hint(path, live, seat_hint):
    if seat_hint:
        return seat_hint
    return f"좌석={live or '없음'}"


def main():
    for f in sorted(os.listdir(raw)):
        if not f.endswith("-classified.tsv"):
            continue
        name = f[: -len("-classified.tsv")]
        rows = list(csv.DictReader(open(f"{raw}/{f}"), delimiter="\t"))
        spare = {r["path"]: r for r in csv.DictReader(open(f"{raw}/{name}-sparse.tsv"), delimiter="\t")} \
            if os.path.exists(f"{raw}/{name}-sparse.tsv") else {}
        seat = {}
        live = load_tsv(f"{raw}/{name}-worktrees.tsv")
        out = f"{raw}/{name}-candidates.tsv"
        with open(out, "w") as fh:
            w = csv.writer(fh, delimiter="\t", lineterminator="\n")
            w.writerow(["path", "GiB", "branch", "head", "land", "real_dirty", "class", "sparse", "owner_hint"])
            for r in sorted(rows, key=lambda r: (rank(r["class"]), -(int(r["kib"]) if r["kib"].isdigit() else 0))):
                kib = int(r["kib"]) if r["kib"].isdigit() else 0
                sp = spare.get(r["path"], {}).get("sparse", "-")
                lv = live.get(r["path"], {}).get("seat_live", "")
                w.writerow([r["path"], f"{kib/1048576:.2f}", r["branch"], r["head"], r["land"],
                            r["dirty"], r["class"], sp, owner_hint(r["path"], lv, seat.get(r["path"], ""))])
        print(f"OK {out}")


main()
