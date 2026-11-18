#!/usr/bin/env python3
# pyright: basic
"""ft_nano_record_seqfind.py — r2272 닫기 요청 발신 «앞» 우편 로그(<comm>/mailbox.log.jsonl · 끝 파일 1개 · 마지막 2000줄)에서 같은 요청 = from <좌석> · to <팀장> · 본문 머리 «[완료·닫기 요청] <stem> 착지 <Q 10자>»
(버려진 seq 제외 · 가장 늦은 seq 1개) → seq(찾음 · INFO 1줄) | 0(찾은 행 0 · 로그 파일 없음 = 지금 길 send) | None(읽기 실패 · 깨진 줄만 = «판정 불가 우편 로그 …» 1줄 · 재발신 0)."""
import json
from collections import deque

from ft_nano_record import Unjudged, seq_dropped


def rows(ctx):   # → 마지막 2000줄의 dict 들 | [](파일 없음) · 못 읽음·깨진 줄만 = Unjudged
    try:
        with open(ctx.comm / "mailbox.log.jsonl", encoding="utf-8") as f:
            lines = [ln for ln in deque(f, 2000) if ln.strip()]
    except FileNotFoundError:
        return []
    except (OSError, UnicodeDecodeError) as e:
        raise Unjudged(f"우편 로그 읽기 rc=1 — {type(e).__name__}") from e   # r2272-mut:readfail
    out = []
    for ln in lines:
        try:
            out.append(json.loads(ln))
        except ValueError:   # 깨진 줄 · 쓰는 중 잘린 끝 줄
            pass
    if lines and not out:
        raise Unjudged(f"우편 로그 깨진 줄만 {len(lines)}줄")
    return [d for d in out if isinstance(d, dict)]


def find_close(ctx, r):   # close_request 의 send 앞 1회(장부에 rec 없을 때만)
    head = f"[완료·닫기 요청] {r['stem']} 착지 {r['q'][:10]}"   # r2272-mut:head
    try:
        hit = sorted({d["seq"] for d in rows(ctx) if d.get("from") == r["seat"] and d.get("to") == r["master"]   # r2272-mut:from
                      and isinstance(d.get("seq"), int) and str(d.get("body") or "").startswith(head)}, reverse=True)
        seq = next((s for s in hit if not seq_dropped(ctx, s)), 0)
    except Unjudged as e:
        print(f"판정 불가 {e}")
        return None
    if seq:
        print(f"INFO 닫기 요청 #{seq} 우편 로그에서 찾음 → 다시 보냄 0")
    return seq
