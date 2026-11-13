"""r1416 — 다른 루트로 간 쪽지의 «영수»: 보낸 쪽 루트 우편함 기록(mailbox.log.jsonl)에 1줄 → answered_seqs 가 «회신 #N» 을 센다.

왜: ft_inbox_core.answered_seqs 는 «내 루트 기록» 의 from = 내 계보 줄만 센다(R337 규칙 그대로).
  다리(r1309 mbox_roots.bridge)·직접 송신(FT_MBOX_DIR=그 루트 · ft-root-hil.sh 꼴)은 받는 쪽 루트에만 줄을 쓴다
  → 다른 루트 좌석 [HIL] 에 답해도 «30분 넘은 팀 대기» 거짓 경보(aifp·kakao 실사건).
영수 줄 = 기록에만 · 큐(mailbox.jsonl)·doorbell 0 = 배달 0 · "seq" 칸 0(그 번호는 받는 루트 것 — find_seq·idle-nudge·board 가
  내 쪽지로 읽지 않는다) · "bridged" = 받는 루트 이름 · "remote_seq" = 그 루트 seq · 쓰기 실패 = WARN 1줄(송신 rc 그대로).
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

import mbox_roots


def receipt(comm: Path, to: str, frm: str, body: str, where: str, remote_seq: int) -> None:
    row = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "to": to, "from": frm, "body": body,
           "bridged": where, "remote_seq": remote_seq}
    try:
        with open(Path(comm) / "mailbox.log.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    except OSError as e:
        print(f"WARN 다리 영수 기록 실패({type(e).__name__} · {comm}) — 송신 {where} seq={remote_seq} 는 정상 · "
              f"회신 셈에 안 들어감", file=sys.stderr)


def home(to: str, frm: str, body: str, seq: int) -> None:
    """B6 — FT_MBOX_BRIDGED=1 로 이 우편함에 쓴 쪽지(다른 루트에서 직접 송신) rc0 뒤 보낸 이의 루트 기록에 영수 1줄.

    보낸 쪽 = roots.tsv 현역 루트 중 보낸 이(역할 키)가 명부에 있는 루트 · 이 우편함 루트 명부에 있으면 0(같은 루트)
    · 다리 부모가 이미 썼으면(FT_MBOX_RECEIPT=done) 0 · 명부 깨짐 = WARN 1줄(송신은 이미 끝남)."""
    canon = mbox_roots.CANON
    if os.environ.get("FT_MBOX_BRIDGED") != "1" or os.environ.get("FT_MBOX_RECEIPT") == "done" or not canon:
        return
    here, want = mbox_roots.own_root(), mbox_roots.role_key(frm)
    try:
        live = [r for r in mbox_roots.roots() if r["state"] == "현역"]
    except mbox_roots.RootsError as e:
        print(f"WARN 다리 영수 판정 불가({e})", file=sys.stderr)
        return
    if here is not None and want in mbox_roots.roster_keys(here):
        return
    same = [str(r["name"]) for r in live if here is not None and Path(str(r["path"])).resolve() == here.resolve()]
    where = same[0] if same else str(canon)
    for row in live:
        comm = mbox_roots.comm_of(Path(str(row["path"])))
        if comm.resolve() != Path(canon).resolve() and want in mbox_roots.roster_keys(Path(str(row["path"]))):
            receipt(comm, to, frm, body, where, seq)
            return
