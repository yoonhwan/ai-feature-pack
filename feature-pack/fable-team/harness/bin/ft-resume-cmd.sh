#!/usr/bin/env bash
# ft-resume-cmd.sh <좌석> — 슬랙 이어가기 블록의 «재개» 칸 값 1줄 (설계 DESIGN-resume-index-20261008 §2 · 판정 404)
#   ① 그 이름의 tmux 세션이 «정확히» 살아 있음  → bash <루트>/.fable-team/comm/mbox.sh ring <좌석>
#   ② 좌석표 행에 session_uuid·cwd·agent=claude + ~/.claude/projects/<cwd 인코딩>/<uuid>.jsonl 의 sessionId·cwd 일치
#        → cd <cwd> && ~/.headroom/claude-hr.sh --resume <uuid>   (printf %q 인용 · R524: 헤드룸 래퍼 — 날 claude 는 프록시 미경유 직결)
#   ③ 그 밖 → stdout `없음(좌석 종료 · 확인된 세션 매핑 없음 — 카드 정본으로 새로 연다)` + rc 3
# ★jsonl 본문에서 좌석 이름을 검색하지 않는다★(이름 언급 ≠ 소유권). 환경: FT_ROOT(루트) · CLAUDE_PROJECTS_DIR(시험용).
set -uo pipefail
SEAT="${1:-}"
[ -n "$SEAT" ] || { echo "usage: ft-resume-cmd.sh <seat>" >&2; exit 2; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_ROOT:-}"   # r385: 라이브 루트 = FT_ROOT → ft_data_root(cwd LIVE_ROOT · 옛 설치 꼴) → ERROR (새 설치본 위치로 풀지 않는다)
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_data_root "$HERE")"; } || exit 3
NONE='없음(좌석 종료 · 확인된 세션 매핑 없음 — 카드 정본으로 새로 연다)'

if tmux has-session -t "=$SEAT" 2>/dev/null; then
  printf 'bash %q ring %q\n' "$ROOT/.fable-team/comm/mbox.sh" "$SEAT"
  exit 0
fi

# 좌석표 행 → cwd / uuid 두 줄(정확히 1건 + agent=claude + jsonl 일치일 때만). 아니면 출력 0.
MAP="$(python3 -I - "$SEAT" "$ROOT/.fable-team" "${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}" <<'PY'
import glob, json, os, re, sys
seat, ftdir, projects = sys.argv[1:4]
rows = []
for f in sorted(glob.glob(os.path.join(ftdir, "seats*.json"))):
    try:
        row = json.load(open(f, encoding="utf-8")).get(seat)
    except (OSError, ValueError, AttributeError):
        continue
    if isinstance(row, dict):
        rows.append(row)
if len(rows) != 1:
    sys.exit(0)
row = rows[0]
uuid, cwd, agent = row.get("session_uuid"), row.get("cwd"), row.get("agent")
if agent != "claude" or not all(isinstance(x, str) and x for x in (uuid, cwd)) or "\n" in uuid + cwd:
    sys.exit(0)
path = os.path.join(projects, re.sub(r"[^A-Za-z0-9-]", "-", cwd), uuid + ".jsonl")
try:
    with open(path, encoding="utf-8") as fh:
        for _, ln in zip(range(200), fh):
            try:
                d = json.loads(ln)
            except ValueError:
                continue
            if isinstance(d, dict) and d.get("sessionId"):
                if d.get("sessionId") == uuid and d.get("cwd") == cwd:
                    print(cwd)
                    print(uuid)
                sys.exit(0)
except OSError:
    pass
PY
)"
if [ -n "$MAP" ]; then
  CWD="$(printf '%s\n' "$MAP" | sed -n 1p)"; UUID="$(printf '%s\n' "$MAP" | sed -n 2p)"
  printf 'cd %q && ~/.headroom/claude-hr.sh --resume %q\n' "$CWD" "$UUID"
  exit 0
fi
printf '%s\n' "$NONE"
exit 3
