#!/usr/bin/env bash
# test_decision_count_call_floor_r1178.sh — r1178: ft-decision-count 의 외부 조회(tmux·ft-hil.sh)는 남은 예산이 바닥나도 호출마다 최소 CALL_FLOOR_S(1.5 s)를 받는다.
#   R1 예산 바닥(0.001) · tmux 즉시 · ft-hil 0.5 s → rc0 · «스크립트 1건»(옛 판 = rc4 «TimeoutExpired … 0.1 seconds»)
#   R2 예산 바닥 · ft-hil 9 s 멈춤 → rc4 · «ft-hil.sh TimeoutExpired» · 끝 시각 ≤ 3 s
#   R3 기본 예산 · 둘 다 즉시 → rc0 · 줄 = 옛 판(바닥 0.1) 줄과 같음
#   R4 FT_DECISION_BUDGET_S=2 · ft-hil 3 s → rc4(남은 예산이 바닥보다 크면 예산이 상한)
#   R5 예산 바닥 · tmux 0.5 s · ft-hil 즉시 → rc0(tmux 도 같은 바닥)
#   ⓕ bin·kit cmp 0 · 변이 1(바닥 1.5 → 0.1) → R1 rc4
# 격리: 임시 FT_ROOT · 임시 git 저장소(꺼진 플래그 칸) · 가짜 tmux·ft-hil — 실 쪽지함·실 tmux·실 launchd 0 · 느린 호출 = 아무도 안 쓰는 fifo 의 read -t(고정 sleep 0)
#   자기 재호출은 real_state_guard 의 RSG_ACTIVE 표지로 1번만.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(RSG_ACTIVE 재진입 표지)
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_TEAMS_REF FT_TEAMS_MD FT_REPO_ROOT FT_PLANNER_DIR \
  FT_DECISION_MERGE_QUEUE FT_DECISION_FLAG_DECISIONS FT_DECISION_AUTONOMY_QUEUE FT_DECISION_BUDGET_S FT_FLAG_OFF_REF FT_FLAG_OFF_REPO
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
fail=0; rc=0; out=""; err=""; secs=0; S0=$SECONDS
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc secs=$secs out=${out:0:300} err=${err:0:300}"; fail=$((fail+1)); fi; }
stage() { echo "단계 $1: $((SECONDS - S0))초"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; T="$(cd "$T" && pwd -P)"
R="$T/root"; B="$R/.fable-team/comm/bodies"
ME="byz-planner-master-claude#50"; LIVE="byz-cfo-master-claude#1"
mkdir -p "$R/.fable-team/state/inbox" "$B" "$R/design"
mkfifo "$T/never"   # 아무도 쓰지 않는 fifo — read -t N 이 정확히 N 초 기다린다
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| planner | `design/planner/` | x | 현역 |\n' > "$R/design/TEAMS.md"
printf '{"_master":"%s","_cards_wt":"none"}\n' "$ME" > "$R/.fable-team/seats-planner.json"
printf '[%s->%s] [결정] 값 필요? ①예 ②아니오\n' "$LIVE" "$ME" > "$B/1.txt"
python3 - "$R" "$B" "$LIVE" <<'PY'
import json, sys
R, B, live = sys.argv[1:]
row = {"seq": 1, "ts": "2026-10-15T17:55:00", "from": live, "cls": "②", "prio": 2.0, "group": "g1", "body_path": f"{B}/1.txt", "mark": None, "reported": False}
open(f"{R}/.fable-team/state/inbox/byz-planner-master-claude.jsonl", "w", encoding="utf-8").write(json.dumps(row, ensure_ascii=False) + "\n")
PY
# 가짜 조회: 대기 초(0 = 즉시) 뒤 응답 — 느린 호출은 fifo read -t 로 흉내
stub() { printf '#!/usr/bin/env bash\n[ "%s" = 0 ] || { exec 3<>"%s"; read -r -t %s -u 3 _; }\necho "%s"\n' "$2" "$T/never" "$2" "$3" > "$T/$1"; chmod +x "$T/$1"; }
stub hil-now.sh 0 "h7 1"; stub hil-05.sh 0.5 "h7 1"; stub hil-3.sh 3 "h7 1"; stub hil-9.sh 9 "h7 1"
stub tmux-now.sh 0 "$LIVE"; stub tmux-05.sh 0.5 "$LIVE"

# 꺼진 플래그 저장소: 플래그 0개 · origin/main ref
F="$T/flagrepo"; mkdir -p "$F/clients/web/src" "$F/docker" "$F/.github/workflows"; git init -q -b main "$F"
printf 'FROM node\n' > "$F/docker/web.Dockerfile"; printf 'build-args: |\n  OTHER=x\n' > "$F/.github/workflows/cd-dev.yml"; echo 'x();' > "$F/clients/web/src/a.ts"
git -C "$F" add -A && git -C "$F" commit -qm c && git -C "$F" update-ref refs/remotes/origin/main HEAD

# C <bin 폴더> <tmux 대역> <ft-hil 대역> [예산] — 도구 1회 · secs = 걸린 초(정수 반올림 없이 python 측정)
C() { local t0; t0="$(python3 -c 'import time; print(time.time())')"
  out="$(env FT_ROOT="$R" FT_DECISION_NOW=2026-10-15T18:00:00 FT_DECISION_TMUX="$T/$2" FT_DECISION_HIL="$T/$3" FT_DECISION_BUDGET_S="${4:-}" \
    FT_DECISION_MERGE_QUEUE="$T/none.md" FT_DECISION_AUTONOMY_QUEUE="$T/none2.md" FT_DECISION_FLAG_DECISIONS="$T/none3.md" FT_FLAG_OFF_REPO="$F" \
    python3 -B "$1/ft_decision_count.py" 2>"$T/err")"; rc=$?; err="$(cat "$T/err")"
  secs="$(python3 -c 'import sys, time; print(round(time.time() - float(sys.argv[1]), 2))' "$t0")"; }
le() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) <= float(sys.argv[2]) else 1)' "$1" "$2"; }

for f in ft_decision_count.py; do cmp -s "$BIN/$f" "$KIT/$f"; ck "ⓕ 키트 미러 cmp 0: $f" $?; done
grep -qx 'CALL_FLOOR_S = 1.5  # .*' "$BIN/ft_decision_count.py"; ck "바닥 상수 CALL_FLOOR_S = 1.5 1줄" $?
# 옛 판(기준판) = 바닥만 0.1 로 되돌린 사본 — 변이 1 과 같은 사본
rm -rf "$T/old"; mkdir "$T/old"; cp "$BIN"/*.py "$T/old/"
python3 - "$T/old/ft_decision_count.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read(); a = "CALL_FLOOR_S = 1.5"; assert a in s, a
open(p, "w", encoding="utf-8").write(s.replace(a, "CALL_FLOOR_S = 0.1"))
PY
stage 준비

# ===== R1 예산 바닥 · ft-hil 0.5 s → rc0 · 스크립트 1건 =====
C "$BIN" tmux-now.sh hil-05.sh 0.001
[ "$rc" = 0 ] && grep -q ' · 스크립트 1건 · ' <<<"$out" && [ -z "$err" ]; ck "R1 예산 바닥 + ft-hil 0.5 s → rc0 · «스크립트 1건» · stderr 0" $?
stage R1

# ===== R2 예산 바닥 · ft-hil 9 s 멈춤 → rc4 · 끝 ≤ 3 s =====
C "$BIN" tmux-now.sh hil-9.sh 0.001
[ "$rc" = 4 ] && [ -z "$out" ] && grep -q '^ERROR ft-decision-count: ft-hil.sh TimeoutExpired .*1.5 seconds' <<<"$err" && le "$secs" 3; ck "R2 9 s 멈춤 → rc4 · «TimeoutExpired … 1.5 seconds» · ${secs}s ≤ 3" $?
stage R2

# ===== R3 기본 예산 · 즉시 → rc0 · 줄 = 옛 판 =====
C "$T/old" tmux-now.sh hil-now.sh; base="$out"; base_rc=$rc
C "$BIN" tmux-now.sh hil-now.sh
[ "$rc" = 0 ] && [ "$base_rc" = 0 ] && [ -n "$out" ] && [ "$out" = "$base" ]; ck "R3 기본 예산 → rc0 · 줄 옛 판과 같음 ($out)" $?
stage R3

# ===== R4 예산 2 s · ft-hil 3 s → rc4 =====
C "$BIN" tmux-now.sh hil-3.sh 2
[ "$rc" = 4 ] && grep -q '^ERROR ft-decision-count: ft-hil.sh TimeoutExpired' <<<"$err" && le "$secs" 2.9; ck "R4 예산 2 s 가 상한 → rc4 · ${secs}s ≤ 2.9" $?
stage R4

# ===== R5 예산 바닥 · tmux 0.5 s · ft-hil 즉시 → rc0 =====
C "$BIN" tmux-05.sh hil-now.sh 0.001
[ "$rc" = 0 ] && grep -q ' · 스크립트 1건 · 팀 대기 1건' <<<"$out" && [ -z "$err" ]; ck "R5 tmux 0.5 s 도 바닥 → rc0 · 팀 대기 1건" $?
stage R5

# ===== 변이 1 — 바닥 1.5 → 0.1(옛 판) 이면 R1 이 rc4 =====
C "$T/old" tmux-now.sh hil-05.sh 0.001
[ "$rc" = 4 ] && grep -q 'ft-hil.sh TimeoutExpired .*0.1 seconds' <<<"$err"; ck "변이① 바닥 0.1 → R1 rc4 «0.1 seconds»(시험이 FAIL 로 잡음)" $?
stage 변이

n="$(wc -l < "$BIN/ft_decision_count.py" | tr -d ' ')"; [ "$n" -le 200 ]; ck "ft_decision_count.py ${n}줄 ≤ 200" $?
python3 -B -c 'import sys; compile(open(sys.argv[1], encoding="utf-8").read(), sys.argv[1], "exec")' "$BIN/ft_decision_count.py"; ck "compile(바이트코드 파일 0)" $?
stage 끝
echo "== FAIL $fail"; [ "$fail" = 0 ]
