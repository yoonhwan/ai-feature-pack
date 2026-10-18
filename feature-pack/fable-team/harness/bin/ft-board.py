#!/usr/bin/env python3
"""ft-board.py — 상태판 생성기 (판정 421 · 496). 원장 3종(명부 seats*.json · 카드 폴더 · 판정 원장)에서만 읽는다 — 손 트리 없음.

  ft-board.py collect [--out <파일>]        중간 dict 한 장(JSON) — 시험·디버그용 · --out = 파일로(수집 1회 — 아래 --from 이 읽는다)
  ft-board.py render --sheet [--text|--html|--slack|--rev]   현황판 트리(PLAN-status-sheet) — 기본 md · --rev = 구조 rev·발행 rev JSON
  ft-board.py sheet-notes <파일>             보정 메모 lint(행 id·필드 실재 · 거절이 있으면 rc 1)
  ft-board.py render --term | --slack [--full]   같은 dict 에서 꼴만 다르게(슬랙은 mrkdwn 문자열만 stdout · 발행 0). --full = env FT_NEWS_FULL=1
  ft-board.py stalled [--min N] [--team <명부 파일>]   ⚠정지·완료 뒤 작업·완료 선언 미처리 좌석만 `|` 구분 행(없으면 출력 0) — 팀 master·planner 틱용
  ft-board.py teams [--team <명부 파일>]       팀마다 한 줄 «일함 <좌석들>» 또는 «정지 N분 · 기다리는 것 = …» + 진행 카드 수 (R132a · 확인 불가 좌석은 줄 끝에 드러남)
  ft-board.py snapshot                    dict 를 불변 스냅샷으로 먼저 쓰고 직전과의 변경 단위 JSON 출력. 쓰기 실패 = rc≠0 · stdout 빈 값
  ft-board.py prune --days N                N일 지난 스냅샷 날짜 폴더 삭제(명시 명령만)
  --from <파일>   (render --sheet · snapshot 전용) collect 를 다시 돌리지 않고 `collect --out` 파일의 dict 를 읽는다 — 출력 동일 · 한 틱 수집 1회(ft-sheet-publish)
  전역 플래그 --refresh-gh                  gh 이슈 캐시 갱신 허용(7초+1) — 없으면 외부 호출 0 · 캐시가 없거나 오래되면 ⑤ 절이 «(캐시 … · 미확인)». launchd ft-board-publish.sh 만 붙인다
명부 새 키: `_cards`(카드 폴더 리포 상대) · `_cards_wt`(그 폴더가 든 워크트리 이름) · `_label`(표시 이름) · `_tree`(NEWS-TREE 경로 · `_cards_wt` 기준).
env·스텁 목록은 ft_board_env.py 머리말. 출력 순서: ⓪ 팀 요약 → ① 완성 트리 → ② 세션 트리 → ③ 큐 → ④ 오늘 판정표 → ⑤ 오빠가 정할 것(ft_board_decide.py).
"""
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ft_board_env as env  # noqa: E402
from ft_board_collect import collect  # noqa: E402
from ft_board_render import render  # noqa: E402
from ft_board_seat import stalled_lines  # noqa: E402
from ft_board_sheet import render_cli  # noqa: E402
from ft_board_sheet_notes import lint_notes  # noqa: E402
from ft_board_teams import team_lines  # noqa: E402
from ft_board_snapshot import prune, snapshot  # noqa: E402


def _stalled(args: list[str]) -> str:
    opts = dict(zip(args[0::2], args[1::2]))
    if len(args) % 2 or set(opts) - {"--min", "--team"} or not opts.get("--min", "3").isdigit():
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)
    files = [Path(opts["--team"])] if "--team" in opts else None
    return "\n".join(stalled_lines(collect(files), int(opts.get("--min", "3"))))


def _teams(args: list[str]) -> str:
    if len(args) not in (0, 2) or (args and args[0] != "--team"):
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)
    return "\n".join(team_lines(collect([Path(args[1])] if args else None)))


def _opt(args: list[str], name: str) -> tuple[str | None, list[str]]:
    """`name <값>` 한 쌍을 뺀다 — 값이 없으면 사용법 종료(rc 2)."""
    if name not in args:
        return None, args
    i = args.index(name)
    if i + 1 >= len(args):
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)
    return args[i + 1], args[:i] + args[i + 2:]


def main(argv: list[str]) -> int:
    full = "--full" in argv or os.environ.get("FT_NEWS_FULL") == "1"
    if "--refresh-gh" in argv:
        os.environ["FT_BOARD_GH_REFRESH"] = "1"
    args = [a for a in argv if a not in ("--full", "--refresh-gh")]
    src, args = _opt(args, "--from")
    dst, args = _opt(args, "--out")
    cmd = args[0] if args else ""
    if src and not (cmd == "snapshot" or (cmd == "render" and args[1:2] == ["--sheet"])) or dst and cmd != "collect":
        print(__doc__, file=sys.stderr)
        return 2
    load = (lambda: json.loads(Path(src).read_text(encoding="utf-8"))) if src else collect  # --from = 수집 결과 파일(없거나 비어 있으면 raise)
    if cmd == "collect" and len(args) == 1 and dst:
        Path(dst).write_text(json.dumps(collect(), ensure_ascii=False), encoding="utf-8")  # 키 순서 보존(렌더 바이트 동일)
        out = ""
    elif cmd == "collect" and len(args) == 1:
        out = json.dumps(collect(), ensure_ascii=False, sort_keys=True, indent=1)
    elif cmd == "render" and len(args) == 2 and args[1] in ("--term", "--slack"):
        out = render(collect(), args[1][2:], full)
    elif cmd == "render" and len(args) >= 2 and args[1] == "--sheet" and set(args[2:]) <= {"--text", "--html", "--slack", "--rev"}:
        out = render_cli(args[2:], load)
    elif cmd == "sheet-notes" and len(args) == 2:
        res = lint_notes(env.ft_root(), Path(args[1]))
        print("\n".join(f"{'OK' if ok else 'REJECT'} {ln.split('|')[0].strip()}" + (f" — {why}" if why else "") for ok, ln, why in res))
        return 0 if all(r[0] for r in res) else 1
    elif cmd == "stalled":
        out = _stalled(args[1:])
    elif cmd == "teams":
        out = _teams(args[1:])
    elif cmd == "snapshot" and len(args) == 1:
        out = json.dumps(snapshot(load(), env.ft_root(), env.now()), ensure_ascii=False)
    elif cmd == "prune" and len(args) == 3 and args[1] == "--days" and args[2].isdigit():
        out = json.dumps(prune(env.ft_root(), env.now(), int(args[2])), ensure_ascii=False)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    if out:
        print(out)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # noqa: BLE001 — 실패는 숨기지 않고 사유와 함께 rc≠0 (#0 RULE)
        print(f"ft-board: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
