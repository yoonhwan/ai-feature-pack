"""ft_inbox_window.py — 큐 파일 «끝 1MB» 창 읽기 + 기계용(본문 0) 묶음 줄(r1052).

`ft-inbox.sh show <좌석> --seqs` 의 몸통(r1052). 큐 파일 전체 json 해석 0(끝 1MB 창만) · 본문 파일 open 0 —
호출부(슬랙 미러 데몬)는 «미닫힘=» 번호만 쓰므로 미리보기를 만들지 않는다.
창 위가 잘렸으면 그 첫 묶음은 판정 불가 → «보류(범위 밖)» 로 보수 보고한다(침묵 폴백 0 · 오빠 15:4x «최근 유효한 라인만 읽어»).
"""
import json
import os
import sys

from ft_inbox_core import obligation_closed

SEQ_B = 1 << 20  # 창 = 큐 파일 «끝 1MB» — 판정 범위를 mirror_board 의 같은 창과 일치시킨다(줄 수 상한 없음)


def tail_rows(path):
    """(rows, 위가 잘렸나) — 큐 파일 끝 SEQ_B 창만 json 해석. 깨진 줄은 stderr 1줄 남기고 건너뛴다(조용한 0 아님)."""
    if not os.path.exists(path):
        return [], False
    with open(path, "rb") as f:
        off = max(0, f.seek(0, os.SEEK_END) - SEQ_B)
        f.seek(off)
        lines = [x for x in f.read().decode("utf-8", "replace").split("\n")[1 if off else 0:] if x.strip()]
    rows = []
    for x in lines:
        try:
            rows.append(json.loads(x))
        except json.JSONDecodeError:
            print(f"WARN r1052 깨진 큐 줄 건너뜀 {os.path.basename(path)}", file=sys.stderr)
    return rows, off > 0


def view_seqs(rows, cut):
    """view 와 같은 묶음·같은 미닫힘 판정, 본문 파일 open 0. 창 위가 잘린 첫 묶음 = «보류(범위 밖)»."""
    head = rows[0]["group"] if rows and cut else None
    mem = {}
    for x in sorted(rows, key=lambda x: (x["prio"], x["seq"])):
        mem.setdefault(x["group"], []).append(x)
    out = []
    for g, ms in mem.items():
        un = [x["seq"] for x in ms if not obligation_closed(x)] or ([ms[0]["seq"]] if g == head else [])
        if un:
            out.append(f"[{ms[0]['cls']}] {g} seq={','.join(str(x['seq']) for x in ms)} 미닫힘={','.join(map(str, un))} from={ms[0]['from']} 원문= | "
                       + ("보류(범위 밖)" if g == head else ""))
    return out
