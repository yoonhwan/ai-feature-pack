#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record_fmt.py — due·notify 줄 1개의 출력 꼴(r1717 A2 · ft_nano_record_due 에서 옮김 · r2202 [structure] · 동작 0)."""
from __future__ import annotations


def fmt(r):
    tail = f"pr={r.get('pr')} 착지={str(r.get('q') or '')[:10]}"
    k = r["k"]
    if k == "차례":
        return f"차례 {r['seat']} 종류={r['sort']} 빠짐={r['miss']} 카드={r['stem']} {tail}"
    if k == "밀림":
        return f"닫기 요청 밀림 {r['seat']} 카드={r['stem']} {tail} rec={r['rec']}"
    if k == "끝":
        return f"끝 {r['stem']} {tail} 좌석={r.get('seat') or '-'} ({r['why']})"
    if k == "주인없음":
        return f"주인 없음 {r['stem']} 담당={r['master'] or '-'} 빠짐={r['miss']} {tail}"
    if k == "카드없음":
        return f"카드 없음 PR #{r.get('pr')} 담당={r['master'] or '-'} 착지={str(r.get('q') or '')[:10]}"
    if k == "카드ref불가":
        return f"판정 불가 카드 ref {r['why']} pr={r.get('pr')} 착지={str(r.get('q') or '')[:10]}"
    return f"판정 불가 {r['stem']} {r['why']}"
