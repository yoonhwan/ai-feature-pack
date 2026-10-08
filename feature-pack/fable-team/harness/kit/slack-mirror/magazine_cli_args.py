"""magazine_cli_args — 아침 매거진 CLI 인자 (byz_morning_magazine 에서 분리 · 200줄 한도).

모드 계약(설계 §6 F2): --reattach 는 --force·--force-root 와 상호배타 — 원격 호출 «전» exit 2.
"""
import argparse
import os
from pathlib import Path

from magazine_reattach import REV
from magazine_slack import SLACK_BASE
from magazine_summary import DEFAULT_CMD

HOME = Path.home()


def parse_args(argv: list[str]) -> argparse.Namespace:
    root = os.environ.get("BYZ_ROOT", "")
    p = argparse.ArgumentParser(description="아침 매거진 발행")
    p.add_argument("--date", help="예정 발행일 YYYY-MM-DD (없으면 예약 모드)")
    p.add_argument("--dry-run", action="store_true", help="md·html·PDF 만 만들고 슬랙 글을 stdout 에 — 게시·push·상태 0")
    p.add_argument("--force", action="store_true", help="done 이어도 «새 뿌리 글을 만듦» (사람이 명시한 수동 예외 — 재첨부는 --reattach)")
    p.add_argument("--force-root", action="store_true", help="posting+표식 없음(불명)을 사람이 확인한 뒤 뿌리 글 재게시")
    p.add_argument("--reattach", metavar="rN", help="발행된 날의 스레드에 답글 + 풀 디테일 PDF·쉬운 판 HTML 을 다시 붙임 (새 뿌리 글 0 · --date 필수)")
    p.add_argument("--force-file", action="append", choices=("pdf", "html"), default=[], help="첨부 불명(공유 시도 기록만 있음)을 사람이 채널에서 확인한 뒤 그 파일만 새로 첨부")
    p.add_argument("--no-push", action="store_true", help="ops/magazine push 끔(수동 시험)")
    p.add_argument("--model-file", help="구조 모델 JSON (수집 모듈 대신 — 시험·재발행용)")
    p.add_argument("--summary-cmd", default=DEFAULT_CMD)
    p.add_argument("--out-dir", default=str(HOME / ".hermes/magazine"))
    p.add_argument("--state", default=str(HOME / ".hermes/state/byz_morning_magazine.json"))
    p.add_argument("--token-file", default=str(HOME / ".hermes/secrets/yoonhwan_bot.env"))
    p.add_argument("--slack-base", default=SLACK_BASE)
    p.add_argument("--channel", default=os.environ.get("MAGAZINE_CHANNEL", "C0C6MJGRR89"))
    p.add_argument("--mention", default=os.environ.get("MAGAZINE_MENTION", "U0AC2JF0M7D"))
    p.add_argument("--repo", default=os.environ.get("GH_REPO", "SecondWindStudio/byz-agents"))
    p.add_argument("--worktree", default=os.environ.get("MAGAZINE_WORKTREE", f"{root}/.worktrees/ops-magazine"))
    p.add_argument("--repo-root", default=root, help="자료 수집용 git 리포 루트 (기본 $BYZ_ROOT)")
    p.add_argument("--mailbox", default=os.environ.get("MAGAZINE_MAILBOX", ""), help="mbox 사본 jsonl (기본 <repo-root>/.fable-team/comm/mailbox.log.jsonl)")
    args = p.parse_args(argv)
    if args.reattach and (args.force or args.force_root):
        p.error("--reattach 는 --force·--force-root 와 같이 쓸 수 없어요 (새 뿌리 글을 막기 위해 — 원격 호출 전 거부)")
    if args.force_file and args.force:
        p.error("--force-file 은 --force 와 같이 쓸 수 없어요")
    if args.reattach and not (REV.fullmatch(args.reattach) and args.date):
        p.error("--reattach 는 rN(N≥1)과 --date 가 필요해요")
    return args
