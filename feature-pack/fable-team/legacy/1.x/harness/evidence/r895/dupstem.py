#!/usr/bin/env python3
"""r895 dupstem.py <classified.tsv> — 중복 생성 묶음(읽기 전용). 이름 줄기 = 폴더 이름에서 -rN · .stale-* · -YYYYMMDD(-HHMM) · 끝 숫자 꼬리를 뗀 것.
같은 줄기 2개 이상 + TMPDIR repo-<sha8>-* 같은 sha 2개 이상을 묶어 «개수·GiB·예» 를 낸다."""
import csv, re, sys
from collections import defaultdict
g = defaultdict(list)
for r in csv.DictReader(open(sys.argv[1]), delimiter="\t"):
    if r["class"].startswith("사라짐"):
        continue
    b = r["path"].rstrip("/").split("/")[-1]
    m = re.match(r"repo-([0-9a-f]{8})-", b)
    stem = f"repo-{m.group(1)}-*(같은 sha 사본)" if m else re.sub(r"(\.stale-.*|-r\d+|-\d{8}(-\d{4})?|\d+)$", "", re.sub(r"(\.stale-.*|-r\d+|-\d{8}(-\d{4})?)$", "", b))
    g[stem].append((b, int(r["kib"]) if r["kib"].isdigit() else 0))
rows = sorted(((s, v) for s, v in g.items() if len(v) > 1), key=lambda x: -sum(k for _, k in x[1]))
print("stem\tcount\tGiB\texamples")
for s, v in rows:
    print(f"{s}\t{len(v)}\t{sum(k for _, k in v)/1048576:.1f}\t{' '.join(b for b, _ in v[:4])}")
