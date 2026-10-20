#!/usr/bin/env bash
# test_resource_reclaim_preventive.sh — R332 ft-resource-reclaim.sh --preventive · 쉬는 역할 좌석(판정 2197) · DA⑥ H1 (+ 변이 3·4). 공용 가짜 세계 = lib/fake_reclaim_world.sh
# test_resource_reclaim.sh 에서 분할(H5 — 한 파일 5분 상한). 같은 가짜 도구·임시 HOME·임시 명부만 쓴다 — 실 tmux kill 0.
# 변이: 승인 표 판정 제거(resume_ok 항상 통과) → 범위 밖 좌석 kill 단언 FAIL · 잠금 제거 → 동시 2호출 중복 kill FAIL.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다(LIVE_BIN 으로 넘기지 않음)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"
SCRIPT_NAME=ft-resource-reclaim.sh
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:300}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }
cnt()  { local n; n="$(grep -c -F -- "$2" "$1" 2>/dev/null)"; echo "${n:-0}"; }

bash -n "$BIN/$SCRIPT_NAME" && ok "bash -n $SCRIPT_NAME" || bad "bash -n $SCRIPT_NAME"
for f in ft-nano-spawn.sh ft-role-spawn.sh ft-successor-open.sh; do bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; done
for f in $SCRIPT_NAME ft-nano-spawn.sh ft-role-spawn.sh ft-successor-open.sh; do cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 사본 cmp 0 $f" || bad "키트 사본 어긋남 $f"; done
[ -x "$BIN/$SCRIPT_NAME" ] && ok "실행 권한 $SCRIPT_NAME" || bad "실행 권한 없음 $SCRIPT_NAME"

. "$HERE/lib/fake_reclaim_world.sh"

# ── R332: --preventive — 문지기 상태와 무관한 선제 회수(승인 두 행 · 공통 경로) · 문지기·[HIL]·재부팅 줄 0 · 잠금 경합이면 대기 0 ──
prev_suite() {   # $1=시험할 스크립트 경로 — 문지기·ft-hil 대역을 «옆에» 둔 임시 bin 에서 돌려 호출 0 을 센다
  local S="$1" out rc t0 PB="$T/pbin" LK
  rm -rf "$PB"; mkdir -p "$PB"; cp "$S" "$PB/ft-resource-reclaim.sh"
  printf '#!/bin/bash\necho gate >> "%s/pv.calls"; echo "OK disk=99GiB"\n' "$T" > "$PB/ft-resource-gate.sh"
  printf '#!/bin/bash\necho hil >> "%s/pv.calls"; echo "! bash /tmp/h999"\n' "$T" > "$PB/ft-hil.sh"; chmod +x "$PB"/*.sh
  LK="$T/root/.fable-team/state/reclaim.lock.d"

  # ⓐ 문지기 정상(호출 0)인데 후보가 있으면 승인 두 행 전부 닫는다 — 병합 끝 나노(완성/ 5분↑·그 밖 30분↑) + 재개 기록 있는 직전 세대
  swapworld; rm -f "$T/pv.calls"
  out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"; rc=$?
  eq "$rc" 0 "R332 ⓐ preventive rc0"
  eq "$(awk '{print $1}' "$ST/nc.log" | sort | tr '\n' ' ')" "byz-t-nano-a#0 byz-t-nano-e#0 byz-t-nano-f#0 " "R332 ⓐ nano-close = a·e(30분↑) · f(완성 카드 6분) — b attached·c WORKING·d pending·g 3분·h 미완성 6분 0"
  eq "$(cat "$ST/kill.log")" "byz-t-role-claude#1" "R332 ⓐ kill-session = 재개 기록 있는 직전 세대뿐"
  has "$out" "PREVENTIVE reclaimed=4 candidates=12 skipped=7" "R332 ⓐ 출력 1줄 = 닫음 4 · 후보 12(나노 8 + 직전 세대 4) · SKIP 7"
  [ ! -e "$T/pv.calls" ] && ok "R332 ⓐ 문지기·ft-hil 호출 0" || bad "R332 ⓐ 문지기/ft-hil 을 불렀다: $(cat "$T/pv.calls")"
  eq "$(grep -c '^send ' "$ST/mbox.log")" 0 "R332 ⓐ [HIL] 쪽지 0"
  ls "$T/root/.fable-team/state"/reboot-plan-*.sh.hil >/dev/null 2>&1 && bad "R332 ⓐ 재부팅 계획 파일을 만들었다" || ok "R332 ⓐ 재부팅 계획 0"
  [ ! -e "$T/root/.fable-team/state/reclaim-hil.sig" ] && ok "R332 ⓐ HIL sig 0" || bad "R332 ⓐ HIL sig 를 썼다"
  has "$(cat "$T/root/.fable-team/state/reclaim.log")" "mode=preventive" "R332 ⓐ reclaim.log 모드 칸 preventive"
  eq "$(grep '^PREVENTIVE ' "$T/root/.fable-team/state/reclaim.log")" "PREVENTIVE reclaimed=4 candidates=12 skipped=7 pressure=0 swap=10%" "R332 ⓐ log 에 요약줄 1(뉴스 칸이 읽는 줄 · r500 압력 꼬리)"

  # 닫기 직전 재확인(fresh_ok)은 그대로 — 첫 판정 뒤 WORKING 으로 바뀐 직전 세대는 안 닫는다
  swapworld; echo 1 > "$ST/flip.byz-t-role-claude_1"
  out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  eq "$(cat "$ST/kill.log")" "" "R332 재확인 WORKING 전환 → kill 0"
  has "$out" "byz-t-role-claude#1 | 직전 세대 좌석 | - | SKIP(재확인 거절) jsonl WORKING" "R332 재확인 거절 표 행"

  # ⓖ --dry-run = 실행권·로그·닫기·쪽지 전부 0
  swapworld
  out="$(run "$PB/ft-resource-reclaim.sh" --preventive --dry-run)"
  has "$out" "WOULD-CLOSE(nano-close)" "R332 ⓖ dry-run 표시"; has "$out" "PREVENTIVE reclaimed=4 candidates=12 skipped=7" "R332 ⓖ dry-run 요약줄"
  eq "$(cat "$ST/kill.log" "$ST/nc.log" "$ST/mbox.log" | wc -l | tr -d ' ')" 0 "R332 ⓖ dry-run kill·close·mbox 0"
  { [ ! -e "$T/root/.fable-team/state/reclaim.log" ] && [ ! -d "$LK" ]; } && ok "R332 ⓖ dry-run 로그·잠금 0" || bad "R332 ⓖ dry-run 이 로그/잠금을 만들었다"

  # ⓓ 회수 잠금이 살아 있는 pid 에 점유 = 대기 0 · 닫기 0 · 로그 0 · 즉시 `PREVENTIVE skipped=lock` (기존 30회×1초 대기는 --on-reject 전용)
  swapworld; mkdir -p "$LK"; echo $$ > "$LK/pid"; t0=$SECONDS
  out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"; rc=$?
  eq "$rc" 0 "R332 ⓓ 잠금 경합 rc0"; eq "$out" "PREVENTIVE skipped=lock" "R332 ⓓ 출력 = PREVENTIVE skipped=lock 한 줄"
  [ $((SECONDS - t0)) -le 2 ] && ok "R332 ⓓ 대기 0(≤2초)" || bad "R332 ⓓ 잠금 경합에서 $((SECONDS - t0))초 기다렸다"
  eq "$(cat "$ST/kill.log" "$ST/nc.log" | wc -l | tr -d ' ')" 0 "R332 ⓓ 경합 = 닫기 0"
  { [ ! -e "$T/root/.fable-team/state/reclaim.log" ] && [ "$(cat "$LK/pid")" = "$$" ]; } && ok "R332 ⓓ 로그 0 · 남의 잠금 그대로" || bad "R332 ⓓ 로그를 썼거나 남의 잠금을 건드렸다"
  rm -rf "$LK"; true & LKP=$!; wait $LKP; mkdir -p "$LK"; echo "$LKP" > "$LK/pid"   # 죽은 pid 잠금 = 회수 후 실행
  out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  has "$out" "PREVENTIVE reclaimed=4" "R332 ⓓ 죽은 pid 의 낡은 잠금은 회수 후 실행"

  # ── 판정 2197(오빠 N=3시간): 쉬는 역할 좌석 = 팀 명부 `_master`·`_arch` 현역 ∧ 대기 카드 0 ∧ pending 0 ∧ 턴 종료 180분↑ IDLE ∧ 재개 기록 → kill-session. 선제 모드만 ──
  roleworld() {   # roleworld [idle분] — 기본 세계 + 현역 arch(byz-t-arch-claude#3 · 재개 기록 O) · 팀 카드 폴더(대기/ 비어 있음)
    setup; local d="$T/root/.worktrees/wt/design/t/indices"; rm -rf "$T/root/.worktrees"; mkdir -p "$d/대기" "$d/진행"
    mkseat "byz-t-arch-claude#3" "${1:-200}" 0 94001; mkrecord "byz-t-arch-claude#3" 94001 4201
    python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["byz-t-arch-claude#3"]={"role":"arch","agent":"claude"};d["_arch"]="byz-t-arch-claude#3";d["_cards"]="design/t/indices";d["_cards_wt"]="wt";json.dump(d,open(p,"w"),ensure_ascii=False)' "$ST/seats.json"
  }
  AK="byz-t-arch-claude_3"; AL() { printf '%s\n' "$out" | grep 'byz-t-arch-claude#3 |'; }
  roleworld
  out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  has "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 판정 2197 쉬는 현역 arch(대기 0·pending 0·IDLE·180분↑·재개 기록) → kill-session"
  has "$(AL)" "쉬는 역할 좌석 | 오빠 판정 2197 · tmux 정리 2026-07-11 · 재개: zombie-clean.sh resume 'byz-t-arch-claude#3' | CLOSED" "R332 2197 표 행(근거·재개 명령)"
  touch "$T/root/.worktrees/wt/design/t/indices/대기/README.md"; roleworld; touch "$T/root/.worktrees/wt/design/t/indices/대기/README.md"
  out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"; has "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 대기/README.md 만 있으면 0장으로 본다"
  roleworld 170; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 세션 idle 170분 → kill 0"; has "$(AL)" "분 < 180분" "R332 2197 idle 문턱 180분 표 행"
  roleworld; touch "$T/root/.worktrees/wt/design/t/indices/대기/x.md"; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 대기 카드 1장 → kill 0"; has "$(AL)" "SKIP 대기 카드 1장" "R332 2197 대기 카드 SKIP 사유"
  roleworld; echo 1 > "$ST/pend.$AK"; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 pending>0 → kill 0"; has "$(AL)" "SKIP mbox pending=1" "R332 2197 pending SKIP 사유"
  roleworld; echo "WORKING - - - jsonl" > "$ST/turn.$AK"; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 WORKING → kill 0"
  roleworld; echo "IDLE $(python3 -c 'import datetime;print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(minutes=100)).strftime("%Y-%m-%dT%H:%M:%SZ"))') 1 1 jsonl" > "$ST/turn.$AK"; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 세션 idle 200분이어도 jsonl 턴 종료 100분 전이면 kill 0(크론 틱 등 출력 활동)"; has "$(AL)" "턴 종료 10" "R332 2197 턴 종료 나이 SKIP 사유"
  roleworld; echo "IDLE - 1 1 jsonl" > "$ST/turn.$AK"; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 턴 종료 시각 없음 → kill 0"; has "$(AL)" "턴 종료 시각 없음" "R332 2197 시각 없음 SKIP 사유"
  roleworld; sed -i '' -E 's/^(byz-t-arch-claude#3 [0-9]+) 0 /\1 1 /' "$ST/sessions"; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 attached → kill 0"
  roleworld; rm -f "$H/.claude/state/seat-resume/byz-t-arch-claude#3.json"; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 재개 기록 없음 → kill 0"; has "$(AL)" "HIL(승인 범위 밖: 재개 기록 없음" "R332 2197 재개 기록 없음 = 승인 범위 밖 행"
  roleworld; touch "$ST/active.$AK"; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 V65 active → kill 0"
  roleworld; python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["_arch"]="byz-t-other-claude#9";json.dump(d,open(p,"w"))' "$ST/seats.json"; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 명부 현역(_arch)이 아니면 kill 0"
  roleworld; python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["_hil_route"]="byz-t-arch-claude#3";json.dump(d,open(p,"w"))' "$ST/seats.json"; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 _hil_route 좌석 kill 0"
  roleworld; python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["byz-t-arch-claude#3"]["role"]="planner";json.dump(d,open(p,"w"))' "$ST/seats.json"; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 role 이 master·arch 가 아니면 kill 0"
  roleworld; python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["_arch"]="x";json.dump(d,open(p,"w"))' "$ST/seats.json"
  python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));d["_master"]="byz-t-arch-claude#3";d["_cards"]="design/t/indices";d["_cards_wt"]="wt";d["byz-t-arch-claude#3"]={"role":"master"};json.dump(d,open(sys.argv[2],"w"))' "$ST/seats.json" "$ST/seats-planner.json"
  out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"; hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 planner 명부의 오케는 kill 0"
  # DA⑥ H1: 폴더는 있는데 목록 조회가 실패하면 «0장» 이 아니라 후보 아님(열거 성공과 0장을 분리) — 정상 빈 폴더(위 첫 단언)는 그대로 닫음
  roleworld; chmod 000 "$T/root/.worktrees/wt/design/t/indices/대기"; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"; chmod 755 "$T/root/.worktrees/wt/design/t/indices/대기"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 H1 대기 폴더 존재 + 조회 실패 → 닫기 0"; has "$(AL)" "SKIP 대기 폴더 조회 실패" "R332 H1 조회 실패 SKIP 사유"
  roleworld; rm -rf "$T/root/.worktrees/wt/design/t/indices/대기"; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 대기 폴더를 못 읽으면(0장 증명 불가) 후보 아님"
  roleworld; echo "$SWAP_REJ" > "$ST/rej.text"; touch "$ST/rej.hard"
  out="$(run "$PB/ft-resource-reclaim.sh" --on-reject "$SWAP_REJ" --gate "$F/gate-res.sh")"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 --on-reject 경로는 역할 좌석을 닫지 않음(계약 변경 0)"
  roleworld; out="$(run "$PB/ft-resource-reclaim.sh" --preventive --dry-run)"
  has "$(AL)" "WOULD-CLOSE(kill-session)" "R332 2197 dry-run 표시"; eq "$(cat "$ST/kill.log" | wc -l | tr -d ' ')" 0 "R332 2197 dry-run kill 0"
  roleworld; echo 1 > "$ST/flip.$AK"; out="$(run "$PB/ft-resource-reclaim.sh" --preventive)"
  hasnt "$(cat "$ST/kill.log")" "byz-t-arch-claude#3" "R332 2197 닫기 직전 재확인에서 WORKING → kill 0"; has "$(AL)" "SKIP(재확인 거절) jsonl WORKING" "R332 2197 재확인 거절 행"
}
prev_suite "$BIN/$SCRIPT_NAME"
[ "$fail" -eq 0 ] && ok "R332 실물 묶음 전부 통과" || bad "R332 실물 묶음 실패 ${fail}건"

# ── r502: launchd 기본 PATH(/usr/bin:/bin)에서도 tmux 를 찾는다 · tmux 조회 실패 ≠ 세션 0 ──
#   ★FT_RECLAIM_EXTRA_PATH 는 늘 가짜·빈 폴더로 준다 — 기본값(/opt/homebrew/bin)이면 실 tmux 를 부른다★
rawrun() {   # rawrun <PATH> <스크립트> [인자…] — run() 과 같은 env 이되 PATH 를 그대로 쓴다(가짜 폴더를 앞에 붙이지 않음)
  local p="$1" s="$2"; shift 2
  PATH="$p" HOME="$H" FT_RES_ROOT="$T/root" FT_SEATS_JSON="$ST/seats.json" FT_SEAT_STATUS="$F/seat-status.sh" FT_NANO_CLOSE="$F/nano-close.sh" \
    FT_MBOX_SH="$F/mbox.sh" ZC_RESUME_DIR="$H/.claude/state/seat-resume" FT_PRESS_PERMIT_DIR="$T/permits" FT_RECLAIM_LOCK_TRIES=10 \
    FT_PACK_ROOT="$P" FT_LANDED_CHECK="$BIN/ft-landed-check.sh" FT_SWAPUSAGE="$SWAP_LOW" /bin/bash "$s" "$@" 2>&1
}
E="$T/empty"; mkdir -p "$E" "$T/tfail" "$T/tnosrv"
printf '#!/bin/bash\ncase "$1" in list-sessions) echo "error connecting to /private/tmp/tmux-501/default (Permission denied)" >&2; exit 1;; *) exec "%s/tmux" "$@";; esac\n' "$F" > "$T/tfail/tmux"
printf '#!/bin/bash\ncase "$1" in list-sessions) echo "no server running on /private/tmp/tmux-501/default" >&2; exit 1;; *) exec "%s/tmux" "$@";; esac\n' "$F" > "$T/tnosrv/tmux"
chmod +x "$T/tfail/tmux" "$T/tnosrv/tmux"
r502_suite() {   # $1=시험할 회수 도구
  local S="$1" out rc LOGF="$T/root/.fable-team/state/reclaim.log"
  # ⓐ PATH 에 tmux 없음 + FT_RECLAIM_EXTRA_PATH=가짜 tmux 폴더 → 도구가 덧붙여 찾음 → 후보 = 픽스처 세션
  swapworld; out="$(FT_RECLAIM_EXTRA_PATH="$F" rawrun /usr/bin:/bin "$S" --preventive --dry-run)"; rc=$?
  eq "$rc" 0 "r502 ⓐ PATH=/usr/bin:/bin + EXTRA=가짜 tmux 폴더 → rc0"
  has "$out" "candidates=12 " "r502 ⓐ 덧붙인 PATH 에서 tmux 를 찾아 후보 12(조용한 0 아님)"
  swapworld; out="$(FT_RECLAIM_EXTRA_PATH="$E" rawrun /usr/bin:/bin "$S" --preventive)"; rc=$?
  eq "$rc" 4 "r502 ⓐ' 어디에도 tmux 없음 → rc4"; has "$out" "ERROR tmux 없음(PATH=/usr/bin:/bin:$E)" "r502 ⓐ' ERROR tmux 없음 + PATH 원문"
  hasnt "$out" "PREVENTIVE " "r502 ⓐ' 요약줄 0"
  # ⓑ tmux 찾음 · list-sessions rc1 + 서버 없음 아닌 stderr → ERROR rc4 · 요약줄 0 · 닫기 0 · 잠금 해제
  swapworld; out="$(FT_RECLAIM_EXTRA_PATH="$E" rawrun "$T/tfail:$F:/usr/bin:/bin" "$S" --preventive)"; rc=$?
  eq "$rc" 4 "r502 ⓑ list-sessions 실패 → rc4"
  has "$out" "ERROR tmux list-sessions rc=1: error connecting to /private/tmp/tmux-501/default (Permission denied)" "r502 ⓑ ERROR 줄 = rc + stderr 첫 줄"
  hasnt "$out" "PREVENTIVE " "r502 ⓑ 출력 요약줄 0"; eq "$(cnt "$LOGF" PREVENTIVE)" 0 "r502 ⓑ reclaim.log 요약줄 0"
  eq "$(cat "$ST/kill.log" "$ST/nc.log" | wc -l | tr -d ' ')" 0 "r502 ⓑ 닫기 0"
  [ ! -d "$T/root/.fable-team/state/reclaim.lock.d" ] && ok "r502 ⓑ 잠금 해제" || bad "r502 ⓑ 잠금이 남았다"
  # ⓑ' 감시자 보조(ft-resource-preventive.sh)가 이 실패를 stamp 0 + resource-watch.log ERROR 로 받는다(다음 틱 재시도)
  swapworld; FT_RECLAIM_EXTRA_PATH="$E" PATH="$T/tfail:$F:/usr/bin:/bin" HOME="$H" FT_RES_ROOT="$T/root" FT_SEATS_JSON="$ST/seats.json" FT_SEAT_STATUS="$F/seat-status.sh" \
    FT_NANO_CLOSE="$F/nano-close.sh" FT_MBOX_SH="$F/mbox.sh" FT_PACK_ROOT="$P" FT_SWAPUSAGE="$SWAP_LOW" FT_RECLAIM_SH="$S" /bin/bash "$BIN/ft-resource-preventive.sh" >/dev/null 2>&1
  [ ! -e "$T/root/.fable-team/state/.preventive-last" ] && ok "r502 ⓑ' stamp 0(다음 틱 재시도)" || bad "r502 ⓑ' 실패인데 stamp 를 찍었다"
  has "$(cat "$T/root/.fable-team/state/resource-watch.log" 2>/dev/null)" "ERROR preventive rc=4 ERROR tmux list-sessions rc=1" "r502 ⓑ' resource-watch.log ERROR 1줄"
  # ⓒ «no server running» 만 세션 0 으로 인정 → rc0 · candidates=0
  swapworld; out="$(FT_RECLAIM_EXTRA_PATH="$E" rawrun "$T/tnosrv:$F:/usr/bin:/bin" "$S" --preventive)"; rc=$?
  eq "$rc" 0 "r502 ⓒ 서버 없음 → rc0"; has "$out" "PREVENTIVE reclaimed=0 candidates=0 skipped=0" "r502 ⓒ 서버 없음 = 세션 0 정상 요약줄"
}
r502_suite "$BIN/$SCRIPT_NAME"
# ⓓ 감시자 머리 PATH — env -i PATH=/usr/bin:/bin 로 tick → 하위(선제 회수·표본)가 받은 PATH 끝 = FT_RECLAIM_EXTRA_PATH(기본 /opt/homebrew/bin:/usr/local/bin)
WB="$T/wbin"; mkdir -p "$WB"; cp "$BIN/ft-resource-watch.sh" "$BIN/ft-resource-du-lib.sh" "$WB/"   # r534: 감시자가 형제 du-lib 를 source
printf '#!/bin/bash\nprintf "%%s\\n" "$PATH" > "%s/sample.path"\n' "$T" > "$WB/ft-resource-sample.sh"
printf '#!/bin/bash\necho "ERROR gate 대역(측정 0 · 동결·알림 0)"; exit 4\n' > "$WB/ft-resource-gate.sh"
printf '#!/bin/bash\nprintf "%%s\\n" "$PATH" > "%s/pv.path"\n' "$T" > "$T/pvpath.sh"; chmod +x "$WB"/*.sh "$T/pvpath.sh"
env -i HOME="$H" PATH=/usr/bin:/bin FT_RES_ROOT="$T/wroot" FT_PREVENTIVE_SH="$T/pvpath.sh" FT_RECLAIM_EXTRA_PATH="$T/xp" /bin/bash "$WB/ft-resource-watch.sh" tick >/dev/null 2>&1
eq "$(cat "$T/pv.path" 2>/dev/null)" "/usr/bin:/bin:$T/xp" "r502 ⓓ 선제 회수가 받은 PATH = launchd PATH + EXTRA"
eq "$(cat "$T/sample.path" 2>/dev/null)" "/usr/bin:/bin:$T/xp" "r502 ⓓ 표본도 같은 PATH"
rm -f "$T/pv.path"; env -i HOME="$H" PATH=/usr/bin:/bin FT_RES_ROOT="$T/wroot" FT_PREVENTIVE_SH="$T/pvpath.sh" /bin/bash "$WB/ft-resource-watch.sh" tick >/dev/null 2>&1
eq "$(cat "$T/pv.path" 2>/dev/null)" "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin" "r502 ⓓ EXTRA 미설정 = 기본 홈브루 경로"
bash -n "$BIN/ft-resource-watch.sh" && ok "bash -n ft-resource-watch.sh" || bad "bash -n ft-resource-watch.sh"
cmp -s "$BIN/ft-resource-watch.sh" "$KIT/ft-resource-watch.sh" && ok "키트 사본 cmp 0 ft-resource-watch.sh" || bad "키트 사본 어긋남 ft-resource-watch.sh"

MUT="$T/mut"; mkdir -p "$MUT"
sed 's/\[ "\$PREV" = 1 \] && tries=1//' "$BIN/$SCRIPT_NAME" > "$MUT/$SCRIPT_NAME"   # R332: 선제 모드의 «대기 0» 제거 → 잠금 경합에서 기다린다
saved=$fail; fail=0; prev_suite "$MUT/$SCRIPT_NAME" >"$T/mut3.out"; m3=$fail; fail=$saved
[ "$m3" -gt 0 ] && ok "변이3(선제 모드 대기 0 제거) → 단언 FAIL ${m3}건" || bad "변이3 이 잡히지 않음(시험이 약하다)"
sed 's/\[ "\${wc:-x}" = 0 \] || /true || /' "$BIN/$SCRIPT_NAME" > "$MUT/$SCRIPT_NAME"   # 판정 2197: 쉬는 역할 좌석의 «대기 카드 0» 판정 제거 → 대기 카드가 있어도 닫는다
saved=$fail; fail=0; prev_suite "$MUT/$SCRIPT_NAME" >"$T/mut4.out"; m4=$fail; fail=$saved
[ "$m4" -gt 0 ] && ok "변이4(대기 카드 0 판정 제거) → 단언 FAIL ${m4}건" || bad "변이4 가 잡히지 않음(시험이 약하다)"
sed 's/return 4;; esac/sess="";; esac/' "$BIN/$SCRIPT_NAME" > "$MUT/$SCRIPT_NAME"   # r502: tmux 조회 실패를 «세션 0» 으로 삼킴(옛 동작)
saved=$fail; fail=0; r502_suite "$MUT/$SCRIPT_NAME" >"$T/mut5.out"; m5=$fail; fail=$saved
[ "$m5" -gt 0 ] && ok "변이5(tmux 실패 = 세션 0) → 단언 FAIL ${m5}건" || bad "변이5 가 잡히지 않음(시험이 약하다)"
grep -v 'FT_RECLAIM_EXTRA_PATH:-' "$BIN/$SCRIPT_NAME" > "$MUT/$SCRIPT_NAME"   # r502: PATH 덧붙임 제거 → launchd PATH 에서 tmux 를 못 찾는다
saved=$fail; fail=0; r502_suite "$MUT/$SCRIPT_NAME" >"$T/mut6.out"; m6=$fail; fail=$saved
[ "$m6" -gt 0 ] && ok "변이6(PATH 덧붙임 제거) → 단언 FAIL ${m6}건" || bad "변이6 이 잡히지 않음(시험이 약하다)"


[ "$(git -C "$REPO" config --get core.bare)" = false ] && ok "core.bare=false" || bad "core.bare 이상"
echo "---- fail=$fail"
[ "$fail" -eq 0 ]
