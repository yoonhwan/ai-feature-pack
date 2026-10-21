"""r677 시험용 인박스 큐 생성기 — 5000행(묶음 다수 · 본문 일부 없음 · 닫힌 묶음 섞음).

usage: python3 make_queue.py <FT_ROOT> [행수]
  .fable-team/state/inbox/master-x.jsonl  (좌석 master-x#1 의 큐)
  .fable-team/comm/bodies/<seq>.txt       (97행마다 하나씩 «파일 없음»)
"""
import json
import os
import sys


def build(root, n):
    qdir = os.path.join(root, ".fable-team", "state", "inbox")
    bdir = os.path.join(root, ".fable-team", "comm", "bodies")
    os.makedirs(qdir, exist_ok=True)
    os.makedirs(bdir, exist_ok=True)
    rows = []
    for i in range(n):
        seq = 1000 + i
        body = os.path.join(bdir, f"{seq}.txt")
        if i % 97:
            with open(body, "w", encoding="utf-8") as f:
                f.write(f"[a#1->master-x#1] {seq} 원문 첫 줄\n둘째 줄\n")
        must = i % 2 == 0  # ③ = 보고 의무 등급(닫히려면 reported/waived 필요)
        mark = None
        if i % 7 == 0:  # 7묶음 중 1묶음 = 닫힘
            mark = {"kind": "처리", "note": "닫힘", "ts": "2026-10-22T00:00:00"}
        elif i % 11 == 0:  # 표시는 있는데 reported=false = 여전히 미닫힘
            mark = {"kind": "보류", "note": "확인", "ts": "2026-10-22T00:00:00"}
        rows.append({"seq": seq, "ts": "2026-10-22T00:00:00", "from": f"a#{i % 5}",
                     "cls": "③" if must else "⑤", "prio": 3.0 if must else 5.0,
                     "group": f"g-{i:04d}", "body_path": body, "mark": mark,
                     "reported": mark is not None, "via": "rule"})
    with open(os.path.join(qdir, "master-x.jsonl"), "w", encoding="utf-8") as f:
        f.writelines(json.dumps(x, ensure_ascii=False) + "\n" for x in rows)
    return len(rows)


if __name__ == "__main__":
    print(f"rows={build(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 5000)}")
