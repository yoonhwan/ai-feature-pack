"""magazine_run_emit — `byz_morning_magazine.py --emit-model <json>` (시트 아침판 입력 · PLAN-status-sheet r4 §4 · S2).

구조 모델 → 요약 → 쉬운 판 여부를 JSON 한 파일로 낸다. 슬랙 게시·PDF·상태 파일 쓰기는 0 — 발행은 시트(ft-board-publish --sheet)가 한다.
md 는 하루 1회 ops/magazine 브랜치로 push 한다(판정 348 경로 · Actions 0) — `--no-push`·`--dry-run` 이면 파일만.
`summary` = 요약 3줄을 이은 한 문단. 숫자·# 가 섞였으면 비운다(시트 이야기 절은 상태 글자를 만들지 못한다 — 비면 시트가 «생성 실패» 를 보인다).
"""
import argparse
import json
import logging
import re
from datetime import datetime
from pathlib import Path

from magazine_block import planner_seats
from magazine_git import publish_md
from magazine_publish import KST
from magazine_render_full import build_eli5, render_full
from magazine_slack import eli5_warning_line
from magazine_summary import summarize_model

LOG = logging.getLogger("byz_morning_magazine")


def story_of(lines: list[str]) -> str:
    text = " ".join(lines)
    return "" if re.search(r"\d|#", text) else text


def run_emit(args: argparse.Namespace) -> int:
    from byz_morning_magazine import collect_model, resolve  # 순환 import 를 호출 시점으로 미룬다
    try:
        date, model = resolve(args)
        model = model or collect_model(args, date)
        summary = summarize_model(model, args.summary_cmd, planner_seats(args))
        eli5, cause = build_eli5(model, args.summary_cmd, summary.lines)
        out = Path(args.out_dir).expanduser()
        out.mkdir(parents=True, exist_ok=True)
        md, _ = render_full(model, summary.lines, datetime.now(KST).strftime("%Y-%m-%d %H:%M KST"), eli5_warning_line(cause) if cause else None)
        md_path = out / f"MAGAZINE-{str(date).replace('-', '')}.md"
        md_path.write_text(md, encoding="utf-8")
        if not (args.no_push or args.dry_run):
            publish_md(Path(args.worktree), md, md_path.name, str(date))
        data = {"date": date, "lines": summary.lines, "summary": story_of(summary.lines), "eli5_ok": eli5 is not None,
                "failure": summary.failure or cause, "md": str(md_path)}
        Path(args.emit_model).expanduser().write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    except Exception as e:  # noqa: BLE001 — 어떤 수집·렌더 실패든 «보이게» 알리고 exit 1 (반쪽 파일 0)
        LOG.error("모델 내보내기 실패: %s: %s", type(e).__name__, e)
        return 1
    print(f"emit-model date={date} file={args.emit_model} md={md_path} eli5_ok={eli5 is not None}")
    return 0
