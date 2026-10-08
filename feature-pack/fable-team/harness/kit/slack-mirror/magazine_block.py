"""magazine_block — 매거진 뿌리 글 이어가기 블록 + 장부 기록 (byz_morning_magazine 에서 분리 · 200줄 한도).

Issue 없음 · 카드 없음 · 담당 = 좌석표 `_master` · 정본 = 매거진 md@sha(push 한 경우만 — `--no-push` 면 없음) · 다음 = 「결정 대기 N건」 · 재개 = ft-resume-cmd.
장부 키 `magazine/<날짜>` kind=report — 보고서라 결과 답글 강제 대상이 아니다(설계 §3 · DA 반박 대상으로 명시).
"""
import argparse
from pathlib import Path

import resume_block as rb
import thread_ledger as lg
from magazine_git import REL_DIR


def planner_seats(args: argparse.Namespace) -> str:
    """결정 자리 줄의 근거 — planner 명부 «경로» (현역 이름은 매번 live_planner 가 정한다)."""
    return f"{args.repo_root}/.fable-team/seats-planner.json"


def block_for(args: argparse.Namespace, md_name: str, hil: int, pushed: bool) -> str:
    root = args.repo_root
    seats = args.seats_file or f"{root}/.fable-team/seats-harness.json"
    script = args.resume_script or f"{root}/.fable-team/bin/ft-resume-cmd.sh"
    seat = rb.master_seat(seats)
    canon = rb.canon_ref(Path(args.worktree) / REL_DIR / md_name) if pushed else rb.NONE
    return rb.block(rb.NONE, rb.NONE, seat, canon, f"결정 대기 {hil}건", rb.resume_for(seat, script))


def record(args: argparse.Namespace, date: str, root_ts: str, *, replace: bool = False) -> None:
    lg.ensure_report(Path(args.ledger).expanduser(), f"magazine/{date}", channel=args.channel, root_ts=root_ts, replace=replace)
