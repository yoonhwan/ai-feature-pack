#!/usr/bin/env bash
# test_queue_remind_origin_main_r557.sh — 읽기만 하는 ft-queue.sh remind|due = 오빠 큐를 origin/main 판에서 읽는다(r557)
#   ⓐ 체크아웃에 새 자리(design/teams/planner/) 없음 → remind (전 FAIL «큐 읽기 실패» rc2) / 후 = origin/main 판 due 줄마다 [재질문] · err=0 rc0
#   ⓑ 체크아웃에 낡은 옛 큐가 있어도 remind·due 는 origin/main 내용(낡은 체크아웃으로 내려가기 0)
#   ⓒ origin/main 에도 큐 없음 → ERROR rc2 + 원인 문구에 origin/main:<경로>(옛 자리·체크아웃으로 후퇴 0 · 조용한 0건 통과 0)
#   ⓓ FT_QUEUE_FILE 명시 → 그 파일(지금과 같음) ⓔ FT_PLANNER_DIR 명시 → 그 폴더(지금과 같음)
#   ⓕ shown·take·add = base 그대로(ft_planner_queue 자리 · origin/main 에 쓰기 0) ⓖ 기존 큐 시험·본체 base 대조 diff 0
# 격리: 임시 git 리포(가짜 origin/main) + 임시 상태·TMPDIR·가짜 mbox(받은 argv 기록) · 실 우편함·실 큐 쓰기 0 · GIT_* 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_AUTONOMY_LEVEL=each
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY FT_PLANNER_DIR FT_QUEUE_FILE FT_TEAMS_REF FT_LEDGER_REPO
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; MIR="$HERE/../../harness/kit/fable-team/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:240}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"   # ft_queue_ref 임시 파일 자리 = 격리(남은 파일도 여기서 센다)

for f in ft-queue.sh ft_queue.py ft_queue_remind.py; do cmp -s "$BIN/$f" "$MIR/$f"; ck "키트 미러 cmp 0: $f" $?; done
bash -n "$BIN/ft-queue.sh" 2>/dev/null; ck "bash -n ft-queue.sh" $?
for f in ft-queue.sh ft_queue.py ft_queue_remind.py; do [ "$(wc -l < "$BIN/$f" 2>/dev/null || echo 999)" -le 200 ]; ck "$f ≤ 200줄" $?; done

NOWV='2026-10-20 10:00'
mkq() { # $1 = 파일 · $2 = 질문 접두 — q1 = 보여준 지 72분(대기) · q2 = 30분(대기)
  { printf '# AUTONOMY-QUEUE\n\n%s\n|---|---|---|---|---|---|---|---|---|---|\n' \
      '| 자율 | 시각 | 종류 | 질문 | 추천안 | 사유 | 상태 | 번호 | 팀 | 보여준 시각 |'
    printf '| A9 | 2026-10-20 08:00 | card-start | %s 하나 | 추 | 사 | 대기 | q1 | graphics | 2026-10-20 08:48 |\n' "$2"
    printf '| A9 | 2026-10-20 08:00 | card-start | %s 최근 | 추 | 사 | 대기 | q2 | graphics | 2026-10-20 09:30 |\n' "$2"; } > "$1"; }
mkrepo() { # $1 = 리포 · $2=1 이면 origin/main 에도 큐 없음 — 체크아웃은 «큐 자리 이동 전» 가지
  local r="$1"; mkdir -p "$r/design"; git -C "$r" init -q -b main
  git -C "$r" config user.email t@t.example; git -C "$r" config user.name t
  printf '| 팀 | 폴더 | 비고 |\n|---|---|---|\n| planner | design/teams/planner/ | 오빠 결정 큐 |\n' > "$r/design/TEAMS.md"
  git -C "$r" add -A >/dev/null && git -C "$r" commit -qm 'old: 큐 자리 이동 전'; git -C "$r" branch old
  if [ "${2:-0}" != 1 ]; then mkdir -p "$r/design/teams/planner"; mkq "$r/design/teams/planner/AUTONOMY-QUEUE.md" origin-main
    git -C "$r" add -A >/dev/null && git -C "$r" commit -qm 'new: design/teams/planner/AUTONOMY-QUEUE.md'; fi
  git -C "$r" update-ref refs/remotes/origin/main refs/heads/main; git -C "$r" checkout -q old; }
QSRC() { git -C "$1" rev-parse origin/main | tr -d '\n'; git -C "$1" show "origin/main:${2:-design/teams/planner/AUTONOMY-QUEUE.md}" 2>/dev/null | shasum | cut -c1-8; }

S="$T/state"; RS="$T/rosters"; mkdir -p "$S" "$RS"
printf '{"_master":"byz-graphics-master-claude#22"}\n' > "$RS/seats-graphics.json"
printf '{"_master":"byz-planner-master-claude#83"}\n' > "$RS/seats.json"
printf '#!/usr/bin/env bash\nprintf "%%s\\t" "$@" >> "%s"; echo >> "%s"\n' "$T/mbox.log" "$T/mbox.log" > "$T/mbox.sh"
FT_ROOT="$T/none" FT_AUTONOMY_STATE_DIR="$S" "$BASH" "$BIN/ft-autonomy.sh" off >/dev/null 2>&1
[ "$(FT_ROOT="$T/none" FT_AUTONOMY_STATE_DIR="$S" "$BASH" "$BIN/ft-autonomy.sh" mode)" != on ]; ck "준비: 자율 OFF" $?
export FT_AUTONOMY_STATE_DIR="$S"
FQr() { out="$(FT_NOW="$NOWV" "$BASH" "$BIN/ft-queue.sh" "$@" 2>&1)"; rc=$?; }
fresh() { rm -f "$T/mbox.log" "$S/queue-reask.json"; }

# ===== ⓐ 체크아웃에 새 자리 없음 → origin/main 판 =====
RR="$T/r-a"; mkrepo "$RR"; export FT_ROOT="$RR"; unset FT_PLANNER_DIR FT_QUEUE_FILE; fresh
FQr remind --rosters "$RS" --mbox "$T/mbox.sh" --min 60; echo "  ⓐ 원문: $(head -2 <<<"$out" | tr '\n' ' ')"
[ "$rc" = 0 ] && ! grep -q '큐 읽기 실패' <<<"$out" && grep -qx 'QUEUE-REMIND sent=1 skip=0 err=0' <<<"$out"
ck "ⓐ 체크아웃에 새 자리 없음 → origin/main 판에서 remind rc0 · err=0 (전 FAIL = «큐 읽기 실패» rc2)" $?
echo "  ⓐ 쪽지: $(cut -f4 "$T/mbox.log" 2>/dev/null)"
grep -qF '[재질문] q1 · 보여준 지 72분 · origin-main 하나' "$T/mbox.log" 2>/dev/null
ck "ⓐ 쪽지 = origin/main 판 due 줄(q1 · 72분) · q2(30분) 쪽지 0" $?
[ -f "$S/queue-reask.json" ] && [ -z "$(ls -A "$TMPDIR" 2>/dev/null)" ]
ck "ⓐ 상태 기록 = ROOT 기준 \$S(임시 큐 dirname 아님) · 임시 파일 정리(trap)" $?
FQr due --team graphics --min 60; echo "  ⓐ due: $(tr '\n' ' ' <<<"$out")"
[ "$rc" = 0 ] && grep -qx 'QUEUE-DUE n=1 old=0' <<<"$out" && grep -q '^DUE q1 team=graphics ' <<<"$out"
ck "ⓐ due 도 origin/main 판(rc0 · n=1)" $?

# ===== ⓑ 낡은 체크아웃 큐가 있어도 origin/main 내용 =====
RR="$T/r-b"; mkrepo "$RR"; export FT_ROOT="$RR"; unset FT_PLANNER_DIR FT_QUEUE_FILE
STALE="$RR/.fable-team/state/planner/AUTONOMY-QUEUE.md"; mkdir -p "$(dirname "$STALE")"; mkq "$STALE" 낡은-체크아웃
old_stale="$(shasum "$STALE" | cut -c1-8)"; fresh
FQr remind --rosters "$RS" --mbox "$T/mbox.sh" --min 60
[ "$rc" = 0 ] && grep -qF 'origin-main 하나' "$T/mbox.log" && ! grep -qF '낡은-체크아웃' "$T/mbox.log"
ck "ⓑ remind = origin/main 내용 · 낡은 체크아웃 큐로 내려가기 0" $?
FQr due --team graphics --min 60
grep -qx 'QUEUE-DUE n=1 old=0' <<<"$out" && grep -qF 'q=origin-main 하나' <<<"$out" && ! grep -qF '낡은-체크아웃' <<<"$out"
ck "ⓑ due = origin/main 내용(낡은 파일 질문 0)" $?
[ "$(shasum "$STALE" | cut -c1-8)" = "$old_stale" ]; ck "ⓑ 읽기 명령은 낡은 체크아웃 큐를 안 건드림(바이트 0 변경)" $?

# ===== ⓒ origin/main 에도 큐 없음 → ERROR rc2 · 후퇴 0 =====
RR="$T/r-c"; mkrepo "$RR" 1; export FT_ROOT="$RR"; unset FT_PLANNER_DIR FT_QUEUE_FILE
STALE="$RR/.fable-team/state/planner/AUTONOMY-QUEUE.md"; mkdir -p "$(dirname "$STALE")"; mkq "$STALE" 낡은-체크아웃; fresh
FQr remind --rosters "$RS" --mbox "$T/mbox.sh" --min 60; echo "  ⓒ 원문: $out"
[ "$rc" = 2 ] && grep -qF 'ERROR 오빠 큐 origin/main 판을 못 읽음: origin/main:design/teams/planner/AUTONOMY-QUEUE.md' <<<"$out"
ck "ⓒ origin/main 에 큐 없음 → ERROR rc2 · 문구에 origin/main:<경로>" $?
[ ! -s "$T/mbox.log" ] && [ -z "$(ls -A "$TMPDIR" 2>/dev/null)" ]
ck "ⓒ 조용한 0건 통과 0(쪽지 0 · rc2) · 임시 파일 정리" $?

# ===== ⓓ FT_QUEUE_FILE 명시 =====
RR="$T/r-d"; mkrepo "$RR"; export FT_ROOT="$RR"; unset FT_PLANNER_DIR
fq() { out="$(FT_NOW="$NOWV" FT_QUEUE_FILE="$T/direct.md" "$BASH" "$BIN/ft-queue.sh" "$@" 2>&1)"; rc=$?; }
mkq "$T/direct.md" 직접지정; fresh; fq remind --rosters "$RS" --mbox "$T/mbox.sh" --min 60
[ "$rc" = 0 ] && grep -qF '직접지정 하나' "$T/mbox.log" && ! grep -qF 'origin-main' "$T/mbox.log"
ck "ⓓ FT_QUEUE_FILE 명시 → 그 파일(지금과 같음)" $?

# ===== ⓔ FT_PLANNER_DIR 명시 =====
RR="$T/r-e"; mkrepo "$RR"; export FT_ROOT="$RR"; mkdir -p "$T/pdir"; mkq "$T/pdir/AUTONOMY-QUEUE.md" 플래너디렉터리
fq2() { out="$(FT_NOW="$NOWV" FT_PLANNER_DIR="$T/pdir" "$BASH" "$BIN/ft-queue.sh" "$@" 2>&1)"; rc=$?; }
fresh; fq2 remind --rosters "$RS" --mbox "$T/mbox.sh" --min 60
[ "$rc" = 0 ] && grep -qF '플래너디렉터리 하나' "$T/mbox.log" && ! grep -qF 'origin-main' "$T/mbox.log"
ck "ⓔ FT_PLANNER_DIR 명시 → 그 폴더(지금과 같음)" $?

# ===== ⓕ shown·take·add = base 그대로(ft_planner_queue 자리 · origin/main 쓰기 0) =====
unset FT_PLANNER_DIR FT_QUEUE_FILE; RR="$T/r-f"; mkrepo "$RR"; export FT_ROOT="$RR"
STALE="$RR/.fable-team/state/planner/AUTONOMY-QUEUE.md"; mkdir -p "$(dirname "$STALE")"; mkq "$STALE" 쓰기자리
qsrc_before="$(QSRC "$RR")"; fresh
FQr shown q1 --at '2026-10-20 09:10'; [ "$rc" = 0 ] && grep -qF '2026-10-20 09:10' "$STALE"
ck "ⓕ shown q1 = 쓰기 자리(ft_planner_queue 경로 · rc0)" $?
FQr take q2 --value 'v2' --by 'byz-graphics-master-claude#22' --verdict 7; [ "$rc" = 0 ] && grep -qF '진행 — byz-graphics-master-claude#22' "$STALE"
ck "ⓕ take q2 = 쓰기 자리(rc0)" $?
FQr add --ev E1 --kind card-start --q '새 질문' --choice c --why w; [ "$rc" = 0 ] && grep -qF '새 질문' "$STALE"
ck "ⓕ add = 쓰기 자리(rc0)" $?
[ "$(QSRC "$RR")" = "$qsrc_before" ]; ck "ⓕ origin/main 판에 쓰기 0(커밋·blob 불변)" $?

# ===== ⓖ 기존 큐 시험·본체 base 대조 diff 0 =====
PACK="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"
n_t="$(git -C "$PACK" diff --name-only origin/main -- '*tests/test_queue_reask_r529.sh' '*tests/test_queue_state_r528.sh' '*tests/test_queue_bulk_r530.sh' '*tests/test_proxy_decide_queue_card_resolve.sh' 2>/dev/null | grep -c '')"
[ -n "$PACK" ] && [ "$n_t" = 0 ]; ck "ⓖ 기존 큐 시험 파일 base 대조 diff 0(새 칸만)" $?
n_q="$(git -C "$PACK" diff --name-only origin/main -- '*bin/ft_queue*.py' '*bin/ft-queue.sh' 2>/dev/null | grep -c 'ft_queue')"
[ "$n_q" = 0 ]; ck "ⓖ ft_queue.py·ft_queue_remind.py·ft_queue_state.py base 대조 diff 0(본체 변경 0)" $?

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
