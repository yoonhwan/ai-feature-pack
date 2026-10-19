#!/usr/bin/env bash
# test_da_hold_gate.sh — R387(판정 2282): 같은 카드 DA 보류 2회 → 3번째 발주 가드 REJECT · 재설계 해제 · 리서치 나노.
# 설계 DESIGN-da-hold2-redesign-research-loop §7-4 + §8-4 케이스 전부. 전부 mktemp — 임시 저장소·가짜 명부·가짜 우편함·가짜 tmux. 실 좌석·실 큐·실 kill 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="$REPO/harness/bin"; KIT="$REPO/harness/kit/fable-team/bin"; SRC="$REPO/harness/comm"
GATE="$KIT/ft_da_hold_gate.py"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/design"; printf '| 팀 | 폴더 | 팀장 | 상태 |\n|---|---|---|---|\n| planner | `design/planner/` | p | 현역 |\n| v65 | `design/v65/` | v | 현역 |\n' > "$T/design/TEAMS.md"   # R383: 린트가 planner·v65 폴더를 명단으로 푼다(lint 시험 cwd = $T)
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }

# ── 0. 문법·키트 사본 동일 ──
for f in ft-nano-spawn.sh ft-nano-close.sh ft-index-move.sh; do bash -n "$BIN/$f" && ok "bash -n $f" || bad "bash -n $f"; cmp -s "$BIN/$f" "$KIT/$f" && ok "키트 cmp 0 $f" || bad "키트 불일치 $f"; done
cmp -s "$BIN/ft_da_hold_gate.py" "$GATE" && ok "키트 cmp 0 ft_da_hold_gate.py" || bad "키트 불일치 ft_da_hold_gate.py"
for f in "$SRC/mbox_guard.sh" "$SRC/mbox_guard_da.sh" "$KIT/ft-index-lint.sh"; do bash -n "$f" && ok "bash -n $(basename "$f")" || bad "bash -n $(basename "$f")"; done
ruff check "$GATE" >/dev/null 2>&1 && ok "ruff $(basename "$GATE")" || bad "ruff"
[ "$(wc -l < "$SRC/mbox_guard.sh")" -le 200 ] && ok "mbox_guard.sh ≤ 200줄" || bad "mbox_guard.sh 200줄 초과"
grep -vE '^[[:space:]]*#' "$BIN/ft_da_hold_gate.py" "$SRC/mbox_guard_da.sh" | grep -qE '\b(600|300)\b' && bad "600/300 초 값 발견" || ok "600/300 값 0"

# ── 픽스처: 명부 · 우편함 · 카드 ──
mkdir -p "$T/s" "$T/c" "$T/resume" "$T/design/alpha/indices/진행"; export FT_SEAT_RESUME_DIR="$T/resume"; git -C "$T" init -q
M='byz-alpha-master-claude#1'; P='byz-planner-master-claude#2'; A='byz-alpha-arch-claude#3'
printf '{"_master":"%s","_hil_route":"%s","_arch":"%s"}\n' "$M" "$P" "$A" > "$T/s/seats-alpha.json"
rec() { python3 -c 'import json,sys;print(json.dumps({"seq":int(sys.argv[1]),"from":sys.argv[2],"to":sys.argv[3],"body":sys.argv[4]},ensure_ascii=False))' "$@" >> "$T/c/mailbox.log.jsonl"; }
RELBODY() { printf '[재설계 해제 %s.md] 해제=1 · 새 범위 설계 §7+§8 · DESIGN r3' "$1"; }
# card <이름> <상태 줄…> — 카드 경로를 CARD 에
card() { local n="$1"; shift; CARD="$T/design/alpha/indices/진행/$n.md"; { echo "# 인덱스: $n"; echo "## 배경"; echo "x"; echo "## 상태"; printf '%s\n' "$@"; } > "$CARD"; }
g() { python3 "$GATE" "$CARD" --seats-dir "$T/s" --comm "$T/c" "$@" 2>&1; }
# chk <라벨> <기대 rc> <기대 부분문자열> <실제 출력> <실제 rc>
chk() { { [ "$5" = "$2" ] && [[ "$4" == *"$3"* ]]; } && ok "$1" || bad "$1 → rc=$5 $4"; }

# ── 1. 사건 셈 (판정기 단독) ──
card h0 '- base_sha: x'; o="$(g)"; chk "HOLD 0 → rc0" 0 "events=0" "$o" $?
card h1 '- 2026-10-18 — DA⑥ r1 HOLD 4'; o="$(g)"; chk "HOLD 1 사건 → rc0" 0 "events=1" "$o" $?
card h2 '- 2026-10-18 — DA⑥ r1 HOLD 4' '- 2026-10-18 — DA⑥ r2 HOLD 1'; o="$(g)"; chk "r382d 꼴(⑥r1·⑥r2) → rc3 budget 0" 3 "events=2" "$o" $?
card m7 '- 2026-10-12 — DA② HOLD(abc1234) 수용' '- 2026-10-13 — DA② r2 HOLD 1'; o="$(g)"; chk "v65 M7 꼴(r 없음 = r1 · 2사건) → rc3" 3 "events=2" "$o" $?
card pg '- 2026-10-10 — DA② r1 HOLD3 반영' '- 2026-10-10 — DA② r1 HOLD 재기록(보강 뒤)'; o="$(g)"; chk "cfo pg-pool 꼴(같은 키 재기록 2줄 → 1사건) → rc0" 0 "events=1" "$o" $?
card rc '- 2026-10-11 — DA② r1 HOLD 2' '- 2026-10-11 — DA② r2 HOLD 1' '- 2026-10-12 — DA⑥ r1 HOLD 3'; o="$(g)"; chk "cfo reconcile 꼴(②r1·②r2·⑥r1 → 3사건) → rc3" 3 "events=3" "$o" $?
card up '- 2026-10-12 — DA 확인 HOLD 몇 건'; o="$(g)"; chk "해석 못 하는 후보 줄 → UNPARSED rc3(fail-closed)" 3 "UNPARSED" "$o" $?
card rd '- 2026-10-18 — DA⑥ r1 HOLD 4' '- 2026-10-18 — DA⑥ r2 HOLD 1' '- 재설계: design/alpha/DESIGN-x.md#r3 · 상향: 나노 Fable'; o="$(g)"; chk "재설계 줄은 카운트를 되돌리지 않는다 → rc3" 3 "events=2" "$o" $?
card nd '- 2026-10-18 — DA⑥ r1 HOLD 1' '- 상위 설명: 이 줄은 DA⑥ 와 무관 HOLD 라는 글자만 있다'; o="$(g)"; chk "머리가 DA 가 아닌 줄은 후보 아님 → rc0" 0 "events=1" "$o" $?

# ── 2. 해제 검증 (§8-1) ──
rec 7001 "$M" "$A" "$(RELBODY rel)"; rec 7101 "$M" "$A" "$(RELBODY ex)"; rec 7102 "$M" "$A" "$(RELBODY cl)"
card rel '- 2026-10-18 — DA② r1 HOLD 1' '- 2026-10-18 — DA② r2 HOLD 1' '- 재설계 해제: #7001'; o="$(g)"; chk "유효 해제 1 → 예산 1 → rc0" 0 "releases=1/0 budget_left=1" "$o" $?
rec 7002 "$M" "$A" '[재설계 해제 rel2.md] 해제 보류 · 검토 결과만 보내라'
card rel2 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #7002'; o="$(g)"; chk "보류 쪽지(머리 다름/해제=1 없음) INVALID → rc3" 3 "RELEASE-INVALID #7002" "$o" $?
rec 7003 "$M" "$A" 'rel3 카드 이야기입니다. 해제=1 새 범위 DESIGN r3 (머리 없음)'
card rel3 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #7003'; o="$(g)"; chk "카드명만 언급한 쪽지 INVALID → rc3" 3 "RELEASE-INVALID #7003" "$o" $?
rec 7004 "byz-alpha-master-claude#9" "$A" "$(RELBODY rel4)"
card rel4 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #7004'; o="$(g)"; chk "from 이 명부 이름과 1글자 다름 INVALID → rc3" 3 "from 이 명부" "$o" $?
rec 7005 "$P" "$A" "$(RELBODY rel5)"
card rel5 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #7005'; o="$(g)"; chk "_hil_route(planner) 해제도 유효 → rc0" 0 "releases=1/0" "$o" $?
card rel6 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #7005'; o="$(g)"; chk "다른 카드 이름 머리의 쪽지 → INVALID" 3 "머리 불일치" "$o" $?
card rel5 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #7005' '- 재설계 해제: #7005'; o="$(g)"; chk "같은 seq 두 줄 → RELEASE-DUP" 0 "RELEASE-DUP #7005" "$o" $?
card rel7 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #9999'; o="$(g)"; chk "없는 seq → INVALID(쪽지 없음)" 3 "쪽지 없음" "$o" $?

# ── 3. 소진 (§9-2 입장 줄) · 입장 검사 ──
card ex '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #7101' '- DA⑥ r1 발주 (arch 가 미리 쓰는 줄 = 소진 아님)'
o="$(g)"; chk "해제 뒤 arch 발주 줄은 소진이 아니다 → releases=1/0" 0 "releases=1/0 budget_left=1" "$o" $?
o="$(g --entry ⑥ r1)"; chk "입장 검사(기록 0) → rc0" 0 "budget_left=1" "$o" $?
o="$(g --entry ⑥ r1 --record --order-file /x/발주서.md)"; rc=$?; chk "입장 허용 + --record → rc0" 0 "budget_left=1" "$o" $rc
tail -1 "$CARD" | grep -qE '^- DA 입장: ⑥r1 · 발주서 /x/발주서.md · 해제 #7101 · 20[0-9]{2}-' && ok "입장 줄 기록(단계r라운드 · 발주서 · 해제 seq · 시각)" || bad "입장 줄 «$(tail -1 "$CARD")»"
o="$(g)"; chk "입장 줄 뒤 → 해제 소진 releases=1/1 budget_left=-1 rc3" 3 "releases=1/1" "$o" $?
o="$(g --entry ⑥ r1)"; chk "같은 (카드,단계,rN) 재입장 → DUP-ENTRY rc3" 3 "DUP-ENTRY ⑥r1" "$o" $?
card ex '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #7101' '- DA⑥ r1 발주' '- DA 입장: ⑥r1 · 발주서 x · 해제 #7101 · 2026-10-18T18:00:00' '- DA⑥ r2 발주'
o="$(g --entry ⑥ r2)"; chk "소진된 해제로 다음 라운드 입장 → rc3(새 해제 필요)" 3 "budget_left=" "$o" $?
card ex '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #7101' '- DA⑥ r1 발주' '- DA⑥ r1 CLOSE'
o="$(g)"; chk "입장 줄 없는 옛 꼴: 해제 뒤 CLOSE 판정 줄도 소진" 3 "releases=1/1" "$o" $?
card ex '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #7101'
o="$(g --entry ⑥ r1)"; chk "발주 줄 없는 입장 → NO-ORDER-LINE rc3" 3 "NO-ORDER-LINE DA⑥ r1" "$o" $?
card ex '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- DA⑥ r3 발주 (이름만 바꿔 재발주)'
o="$(g --entry ⑥ r3)"; chk "해제 없이 r3 이름만 바꾼 재발주 → rc3" 3 "budget_left=0" "$o" $?
card ex '- DA② r1 HOLD 1' '- DA② r2 발주 (검토 2회째 · HOLD 사건 1/2)' '- 2026 — 나노 범위 DA⑥ 1회 · 실사건 ⓒ = 이 카드(②r1·②r2 HOLD → 3번째)'
o="$(g)"; chk "발주 줄·문맥 속 HOLD 글자는 사건이 아니다(사이 단계 기호·발주 금지) → events=1" 0 "events=1" "$o" $?
card ex '- 2026-10-13 21:2x byz-x-arch#28 — 사전 DA② r1 HOLD 4 → 반영' '- 2026-10-13 nano#0 — DA⑥ r1 HOLD 3 보강'
o="$(g)"; chk "작성자·«사전» prefix 가 붙은 실제 줄 꼴도 사건으로 센다 → events=2" 3 "events=2" "$o" $?
card ex '- 2026-10-13 — DA r1 HOLD 2 (단계 기호 없음)'
o="$(g)"; chk "DA 와 HOLD 가 있는데 단계 기호 없음 → UNPARSED rc3" 3 "UNPARSED" "$o" $?

# ── 3b. 입장 식(§10) — 사건은 이력 · 해제는 입장권: 해제로 연 검토가 HOLD 여도 새 해제가 있으면 입장 ──
rec 7201 "$M" "$A" "$(RELBODY ab)"; rec 7202 "$M" "$A" "$(RELBODY ab)"
E1='- DA 입장: ⑥r1 · 발주서 x · 해제 #7201 · 2026-10-18T18:00:00'; E2='- DA 입장: ⑥r2 · 발주서 x · 해제 #7202 · 2026-10-18T18:30:00'
card ab '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #7201' '- DA⑥ r1 발주' "$E1" '- DA⑥ r1 HOLD 2' '- 재설계 해제: #7202' '- DA⑥ r2 발주'
o="$(g --entry ⑥ r2)"; chk "§10 ①: HOLD 2 → 해제 A → ⑥r1 입장 → HOLD(사건 3) → 해제 B → ⑥r2 입장 = rc0 (events=3 releases=2/1 budget_left=1)" 0 "events=3 reviews=5 releases=2/1 budget_left=1" "$o" $?
card ab '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #7201' '- DA⑥ r1 발주' "$E1" '- DA⑥ r1 HOLD 2' '- DA⑥ r2 발주'
o="$(g --entry ⑥ r2)"; chk "§10 ①: 같은 상태에서 해제 B 없이 ⑥r2 입장 = rc3 (budget_left=0)" 3 "releases=1/1 budget_left=0" "$o" $?
card ab '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #7201' '- DA⑥ r1 발주' "$E1" '- DA⑥ r1 HOLD 2' '- 재설계 해제: #7202' '- DA⑥ r2 발주' "$E2" '- DA⑥ r2 HOLD 1' '- DA⑥ r3 발주'
o="$(g --entry ⑥ r3)"; chk "§10 ②: 해제 B 소진 뒤 ⑥r3 입장 = rc3 (events=4 releases=2/2 budget_left=0 · 새 해제 필요)" 3 "events=4 reviews=7 releases=2/2 budget_left=0" "$o" $?
card ab1 '- DA② r1 HOLD 1' '- 재설계 해제: #7201'
o="$(g)"; chk "§10: 사건 < 2 면 기본 예산 2−사건(해제는 더하지 않는다) → budget_left=1" 0 "events=1 reviews=1 releases=0/0 budget_left=1" "$o" $?

# ── 4. 완성 이동 모드(--closing) ──
card cl '- DA② r1 HOLD 1' '- DA② r2 HOLD 1'; o="$(g --closing)"; chk "closing: 사건 2 · 해제 0 → rc3" 3 "events=2" "$o" $?
card cl '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계 해제: #7102' '- DA⑥ r1 발주' '- DA 입장: ⑥r1 · 발주서 x · 해제 #7102 · 2026-10-18T18:00:00'; o="$(g --closing)"; chk "closing: 소진된 유효 해제 있음 → rc0" 0 "releases=1/1" "$o" $?
card cl '- DA② r1 HOLD 1'; o="$(g --closing)"; chk "closing: 사건 1 → rc0" 0 "events=1" "$o" $?

# ── 4b. 실제 카드 3꼴 사본 회귀 + 이 카드(§9-3 · §9-1) ──
FXD="$REPO/harness/fixtures/da_hold"
fx() { python3 "$GATE" "$FXD/$1.md" --seats-dir "$T/nonexistent" --comm "$T/c" 2>&1; }
o="$(fx v65-M7)"; chk "실제 v65 M7 카드 사본(작성자 prefix · r 없는 DA② HOLD + DA② r2 HOLD) → events=2" 3 "events=2" "$o" $?; echo "  실제 카드 출력: ${o%%$'\n'*}"
o="$(fx cfo-pg-pool)"; chk "실제 cfo pg-pool 사본(②r1 · ⑥r1 두 단계) → events=2" 3 "events=2" "$o" $?; echo "  실제 카드 출력: ${o%%$'\n'*}"
o="$(fx cfo-reconcile)"; chk "실제 cfo reconcile 사본(②r1·②r2·⑥r1) → events=3" 3 "events=3" "$o" $?; echo "  실제 카드 출력: ${o%%$'\n'*}"
# 이 카드: 명부 master#68(현역) · 은퇴 기록 #67 · 해제 #108869 의 쪽지(승계 전 발신 #67)
mkdir -p "$T/h/design/harness/indices/진행" "$T/h/.fable-team/comm"; git -C "$T/h" init -q; cp "$FXD/r387-card.md" "$T/h/design/harness/indices/진행/r387-da-hold2-redesign-research-loop.md"
printf '{"_master":"byz-harness-master-claude#68","_hil_route":"byz-planner-master-claude#70","_arch":"byz-harness-arch-claude#87"}\n' > "$T/h/.fable-team/seats-harness.json"
python3 -c 'import json;print(json.dumps({"seq":108869,"from":"byz-harness-master-claude#67","to":"byz-harness-arch-claude#87","body":"[재설계 해제 r387-da-hold2-redesign-research-loop.md] 해제=1 · 새 범위 설계 §7+§8 · DESIGN r3"},ensure_ascii=False))' > "$T/h/.fable-team/comm/mailbox.log.jsonl"
HC="$T/h/design/harness/indices/진행/r387-da-hold2-redesign-research-loop.md"; hg() { python3 "$GATE" "$HC" --root "$T/h" --resume-dir "$T/resume" 2>&1; }
o="$(hg)"; chk "계보: 기록 없는 직전 세대(#67) 발신 해제 → INVALID" 3 "RELEASE-INVALID #108869 from 이 명부" "$o" $?
echo '{}' > "$T/resume/byz-harness-master-claude#67.json"
o="$(hg)"; rc=$?; echo "  이 카드 출력: $(printf '%s' "$o" | tr '\n' ' ')"; chk "계보: 은퇴 기록 있는 직전 세대(#67 → #68) 해제 유효 · events=3 releases=1/1" 3 "events=3" "$o" $rc
[[ "$o" == *"releases=1/1"* && "$o" == *"RELEASE-OK #108869 from=byz-harness-master-claude#67(계보 #67→#68)"* ]] && ok "계보 라벨 from=…(계보 #67→#68) 출력" || bad "계보 라벨 $o"
rm -f "$T/resume/byz-harness-master-claude#67.json"; echo '{}' > "$T/resume/byz-other-master-claude#67.json"
o="$(hg)"; [[ "$o" == *"RELEASE-INVALID"* ]] && ok "계보: 다른 베이스 이름 기록은 무효" || bad "다른 베이스 $o"
echo '{}' > "$T/resume/byz-harness-master-claude#69.json"; sed 's/#67/#69/' "$T/h/.fable-team/comm/mailbox.log.jsonl" > "$T/h/.fable-team/comm/m2" && mv "$T/h/.fable-team/comm/m2" "$T/h/.fable-team/comm/mailbox.log.jsonl"
o="$(hg)"; [[ "$o" == *"RELEASE-INVALID"* ]] && ok "계보: 현역보다 번호가 큰 이름은 무효" || bad "번호 큰 이름 $o"

# ── 5. 쪽지 가드(mbox.sh send · 격리 큐) ──
new_env() { ENV="$(mktemp -d "$T/env.XXXXXX")"; mkdir -p "$ENV/.fable-team/comm" "$ENV/.fable-team/bin" "$ENV/.fable-team/state" "$ENV/seats" "$ENV/design/alpha/indices/진행"
  cp "$SRC"/mbox*.py "$SRC"/mbox*.sh "$SRC"/bang_command_check.py "$ENV/.fable-team/comm/"; cp "$GATE" "$ENV/.fable-team/bin/"; git -C "$ENV" init -q
  echo '{}' > "$ENV/seats/seats.json"; cp "$T/s/seats-alpha.json" "$ENV/seats/"; : > "$ENV/.fable-team/comm/mailbox.log.jsonl"
  mkdir -p "$T/stub"; printf '#!/bin/sh\nexit 1\n' > "$T/stub/tmux"; chmod +x "$T/stub/tmux"; }
gcard() { GC="$ENV/design/alpha/indices/진행/$1.md"; shift; { echo "# c"; echo "## 상태"; printf '%s\n' "$@"; } > "$GC"; }
send_da() { # <수신자> <본문>
  OUT="$(cd "$ENV" && env -u FT_BIN PATH="$T/stub:$PATH" FT_SEATS_JSON="$ENV/seats/seats.json" FT_PLANNER_HEAD_MODE=reject FT_MBOX_DIR="$ENV/.fable-team/comm" FT_MBOX_RATE_N=999 FT_MBOX_FANOUT_WINDOW=0 \
    bash "$ENV/.fable-team/comm/mbox.sh" send "$1" "me#1" "$2" 2>&1)"; RC=$?; }
queued() { local n; n="$(grep -c '"to": *"byz-alpha-da-codex#1"' "$ENV/.fable-team/comm/mailbox.jsonl" 2>/dev/null)"; echo "${n:-0}"; }
DA='byz-alpha-da-codex#1'
new_env
gcard bad '- DA⑥ r1 HOLD 4' '- DA⑥ r2 HOLD 1' '- DA⑥ r3 발주'
send_da "$DA" "$(printf '[DA⑥ r3 발주] 3번째\n- 카드: %s' "$GC")"; { [ "$RC" = 3 ] && [[ "$OUT" == *"REJECT DA 보류 2회"* ]] && [ "$(queued)" = 0 ]; } && ok "가드: HOLD 2 카드 → REJECT DA 보류 2회 · 큐 적재 0" || bad "가드 HOLD2 rc=$RC $OUT"
echo "REJECT 원문: $(printf "%s" "$OUT" | grep "^REJECT" | head -1 | cut -c1-220)"
gcard good '- DA⑥ r1 HOLD 4' '- DA⑥ r2 발주'
send_da "$DA" "$(printf '[DA⑥ r2 발주] 2번째\n- 카드: %s' "$GC")"; { [ "$RC" = 0 ] && [ "$(queued)" = 1 ]; } && ok "가드: HOLD 1 카드 → 큐 적재" || bad "가드 HOLD1 rc=$RC $OUT"
grep -q '^- DA 입장: ⑥r2 · 발주서 본문 · 해제 #없음' "$GC" && ok "가드: 입장 허용 순간 카드에 «- DA 입장:» 줄 기록" || bad "가드 입장 줄 기록 없음"
send_da "$DA" "$(printf '[DA⑥ r2 발주 · 마지막] 같은 키 재입장\n- 카드: %s' "$GC")"; { [ "$RC" = 3 ] && [[ "$OUT" == *"같은 입장 재사용"* ]] && [ "$(queued)" = 1 ]; } && ok "가드: 같은 (카드,단계,rN) 두 번째 → REJECT DUP-ENTRY · 큐 적재 0" || bad "가드 DUP-ENTRY rc=$RC $OUT"
gcard good2 '- DA⑥ r1 HOLD 4' '- DA⑥ r2 발주'
send_da "$DA" "$(printf '[DA⑥ r2 발주 · 마지막] 꼬리 머리\n- 카드: %s' "$GC")"; { [ "$RC" = 0 ] && [ "$(queued)" = 2 ]; } && ok "가드: [DA⑥ r2 발주 · 마지막] 머리 매치 → 통과" || bad "가드 꼬리 머리 rc=$RC $OUT"
send_da "$DA" '[DA⑥ r2 발주] 카드 줄 없음'; { [ "$RC" = 3 ] && [[ "$OUT" == *"카드 경로 0개"* ]]; } && ok "가드: - 카드: 줄 0개 → REJECT(fail-closed)" || bad "가드 카드줄0 rc=$RC $OUT"
send_da "$DA" "$(printf '[DA⑥ r2 발주] 둘\n- 카드: %s\n- 카드: %s' "$GC" "$ENV/design/alpha/indices/진행/bad.md")"; { [ "$RC" = 3 ] && [[ "$OUT" == *"카드 경로 2개"* ]]; } && ok "가드: - 카드: 줄 2개 → REJECT" || bad "가드 카드줄2 rc=$RC $OUT"
send_da "$DA" "$(printf '[DA⑥ r2 발주] 없는 파일\n- card x\n- 카드: %s/design/alpha/indices/진행/none.md' "$ENV")"; { [ "$RC" = 3 ] && [[ "$OUT" == *"없는 카드 파일"* ]]; } && ok "가드: 없는 파일 → REJECT" || bad "가드 없는파일 rc=$RC $OUT"
gcard noline '- DA⑥ r1 HOLD 1'
send_da "$DA" "$(printf '[DA⑥ r2 발주] 발주 줄 없음\n- 카드: %s' "$GC")"; { [ "$RC" = 3 ] && [[ "$OUT" == *"카드 발주 줄 없음"* ]]; } && ok "가드: 카드에 같은 rN 발주 줄 없음 → REJECT" || bad "가드 발주줄 rc=$RC $OUT"
gcard unp '- DA 확인 HOLD 몇 건' '- DA⑥ r1 발주'
send_da "$DA" "$(printf '[DA⑥ r1 발주] x\n- 카드: %s' "$GC")"; { [ "$RC" = 3 ] && [[ "$OUT" == *"판정 불가"* ]]; } && ok "가드: UNPARSED 줄 → REJECT(fail-closed)" || bad "가드 UNPARSED rc=$RC $OUT"
send_da "byz-alpha-arch-claude#3" "$(printf '[DA⑥ r3 발주] DA 가 아닌 수신자\n- 카드: %s' "$ENV/nowhere.md")"; [ "$RC" = 0 ] && ok "가드: DA 수신자가 아니면 검사 0" || bad "가드 비DA rc=$RC $OUT"
send_da "$DA" '[HIL] 안전 보고는 DA 발주 머리가 아니다'; [ "$RC" = 0 ] && ok "가드: [HIL] 은 대상 밖" || bad "가드 HIL rc=$RC $OUT"
# R389 ⓒ: 판정기 자리가 bash shim(루트 .fable-team/bin 꼴 · exec python3 <실파일>)이어도 판정기가 돈다
gcard shim '- DA⑥ r1 HOLD 4' '- DA⑥ r2 발주'; mkdir -p "$ENV/real"; mv "$ENV/.fable-team/bin/ft_da_hold_gate.py" "$ENV/real/"
printf '#!/usr/bin/env bash\nexec python3 "%s/real/ft_da_hold_gate.py" "$@"\n' "$ENV" > "$ENV/.fable-team/bin/ft_da_hold_gate.py"; chmod +x "$ENV/.fable-team/bin/ft_da_hold_gate.py"
Q0="$(queued)"; send_da "$DA" "$(printf '[DA⑥ r2 발주] shim 판정기\n- 카드: %s' "$GC")"
{ [ "$RC" = 0 ] && [ "$(queued)" = $((Q0+1)) ] && grep -q '^- DA 입장: ⑥r2' "$GC"; } && ok "가드: 판정기 bash shim → 큐 적재 1 · «- DA 입장:» 줄(R389 ⓒ)" || bad "가드 shim rc=$RC $OUT"
rm -f "$ENV/.fable-team/bin/ft_da_hold_gate.py"
send_da "$DA" "$(printf '[DA⑥ r2 발주] 판정기 없음\n- 카드: %s' "$GC")"; { [ "$RC" = 3 ] && [[ "$OUT" == *"판정기 없음"* ]]; } && ok "가드: 판정기 부재 → REJECT(fail-closed)" || bad "가드 판정기없음 rc=$RC $OUT"
rm -f "$ENV/.fable-team/comm/mbox_guard_da.sh"
send_da "$DA" "$(printf '[DA⑥ r2 발주] 본체 없음\n- 카드: %s' "$GC")"; { [ "$RC" = 3 ] && [[ "$OUT" == *"가드 본체 없음"* ]]; } && ok "가드: 본체 파일 부재 → DA 발주 REJECT(설치 순서)" || bad "가드 본체없음 rc=$RC $OUT"

# ── 6. 린트 INFO · 채택 vs 위반 (§3 · §8-3) ──
G1='골 첫 줄 시험용 문장이다.'; G2='골 둘째 줄 시험용 문장이다.'; G3='골 셋째 줄 시험용 문장이다.'
printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3" > "$T/goal.txt"; mkdir -p "$T/src" "$T/design"; echo '원장 본문: 닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.' > "$T/design/LEDGER.md"; printf 'l1\n' > "$T/src/target.sh"
lintcard() { local f="$T/lint-$1.md"; shift; { echo '# 인덱스: lint'; echo '- 제안서: 없음 — 시험 카드'; echo '## 골 원문'; printf '%s\n%s\n%s\n' "$G1" "$G2" "$G3"; echo '## 골좌표'; echo '닫는 증거: 「닫는 증거는 이 문장 전체를 복붙한 것이어야 한다.」'
    echo '## 배경'; echo '시험.'; echo '## 구현 범위'; echo '1. src/target.sh 수정'; echo '## 완료 조건'; echo '통과.'; echo '## 상태'; printf '%s\n' "$@"; } > "$f"; echo "$f"; }
lint() { ( cd "$T" && FT_GOAL_LINES_FILE="$T/goal.txt" FT_GOAL_LEDGER="design/LEDGER.md" bash "$KIT/ft-index-lint.sh" "$1" 2>&1 ); }
o="$(lint "$(lintcard hold2 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1')")"; rc=$?; { [ "$rc" = 0 ] && [[ "$o" == *"INFO"*"DA 보류 2회"* ]] && [[ "$o" == *"OK "* ]]; } && ok "lint ⓓ: HOLD 2 + 재설계/리서치 줄 없음 → INFO 1줄(REJECT 아님)" || bad "lint INFO rc=$rc $o"
o="$(lint "$(lintcard hold2r '- DA② r1 HOLD 1' '- DA② r2 HOLD 1' '- 재설계: design/x.md#r3')")"; [[ "$o" != *"INFO"*"DA 보류"* ]] && ok "lint: 재설계 줄 있으면 INFO 0" || bad "lint 재설계 INFO $o"
o="$(lint "$(lintcard viol '- 리서치: s#0 base=abc1234 허용=design/alpha/RESEARCH-*.md' '- 리서치 위반: s#0 src/x.py' '- 리서치 채택: design/alpha/RESEARCH-a.md · 설계 r4')")"; rc=$?; { [ "$rc" = 1 ] && [[ "$o" == *"위반 산출은 채택 불가"* ]]; } && ok "lint: 위반 뒤 새 워커 없이 채택 → REJECT" || bad "lint 위반채택 rc=$rc $o"
o="$(lint "$(lintcard viol2 '- 리서치: s#0 base=abc1234 허용=x' '- 리서치 위반: s#0 src/x.py' '- 리서치: s2#0 base=abc1234 허용=x' '- 리서치 채택: design/alpha/RESEARCH-a.md · 설계 r4')")"; rc=$?; [ "$rc" = 0 ] && ok "lint: 새 워커 줄 뒤 채택 → OK" || bad "lint 새워커채택 rc=$rc $o"

# ── 7. ft-index-move 부모 완성 게이트(§7-3) — 게이트는 정본·슬랙 검사보다 앞이라 임시 저장소로 충분 ──
mkdir -p "$T/mv/design/alpha/indices/진행" "$T/mv/.fable-team"; git -C "$T/mv" init -q
printf '## §1 판정\n닫힘 — 대상 카드: mv1\n' > "$T/mv/da.md"
mvcard() { MVC="$T/mv/design/alpha/indices/진행/$1.md"; shift; { echo '# c'; echo '## 상태'; printf '%s\n' "$@"; } > "$MVC"; }
mvrun() { ( cd "$T/mv" && PATH="$T/stub:$PATH" bash "$KIT/ft-index-move.sh" "$MVC" 완성 --da "$T/mv/da.md#§1" --seat s 2>&1 ); }
mvcard mv1 '- 리서치: byz-alpha-nano-x-research#0 base=abc1234 허용=design/alpha/RESEARCH-*.md'; o="$(mvrun)"; { [[ "$o" == *"REJECT 리서치 좌석 열림 byz-alpha-nano-x-research#0"* ]]; } && ok "index-move: 리서치 닫힘 줄 없음 → REJECT 리서치 좌석 열림" || bad "index-move 닫힘줄없음 $o"
mvcard mv1 '- 리서치: byz-alpha-nano-x-research#0 base=abc1234 허용=x' '- 리서치 닫힘: byz-alpha-nano-x-research#0 2026-10-18 reap 없음'; o="$(mvrun)"; [[ "$o" == *"REJECT 리서치 좌석 열림"* ]] && ok "index-move: 닫힘 줄에 left=0·kill rc=0 없음 → REJECT" || bad "index-move left0없음 $o"
mvcard mv1 '- DA② r1 HOLD 1' '- DA② r2 HOLD 1'; o="$(mvrun)"; [[ "$o" == *"REJECT DA 보류 가드: HOLD events=2"* ]] && ok "index-move: 사건 2 · 해제 0 → REJECT DA 보류 가드: HOLD events=2(r456 판정기 첫 줄)" || bad "index-move 보류2 $o"
mvcard mv1 '- 리서치: byz-alpha-nano-x-research#0 base=abc1234 허용=x' '- 리서치 닫힘: byz-alpha-nano-x-research#0 2026-10-18 kill rc=0'; o="$(mvrun)"; [[ "$o" != *"리서치 좌석 열림"* && "$o" != *"DA 보류 가드"* ]] && ok "index-move: 닫힘 줄(kill rc=0) + 보류 0 → 이 게이트 통과(뒤 검사로 진행)" || bad "index-move 통과 $o"

# ── 8. ft-nano-close 리서치 위반 기록 블록(스크립트에서 python 블록을 꺼내 실행) ──
_s="$(grep -n 'python3 - "\$CARD" "\$SEAT" "\$SEAT_WT" "\$RS_LINE"' "$BIN/ft-nano-close.sh" | head -1 | cut -d: -f1)"; _e="$(awk -v s="${_s:-0}" 'NR>s && /^PY$/{print NR; exit}' "$BIN/ft-nano-close.sh")"
sed -n "$((_s+1)),$((_e-1))p" "$BIN/ft-nano-close.sh" > "$T/rs_viol.py"
[ -s "$T/rs_viol.py" ] && ok "close: 위반 검사 python 블록 추출" || bad "close: 블록 추출 실패"
mkdir -p "$T/wt"; git -C "$T/wt" init -q; git -C "$T/wt" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base; BASE="$(git -C "$T/wt" rev-parse HEAD)"
mkdir -p "$T/wt/design/alpha"; echo r > "$T/wt/design/alpha/RESEARCH-a.md"; echo c > "$T/wt/code.py"; git -C "$T/wt" add -A; git -C "$T/wt" -c user.name=t -c user.email=t@t commit -q -m work
printf '# c\n## 상태\n- 리서치: s#0 base=%s 허용=design/alpha/RESEARCH-*.md\n' "$BASE" > "$T/rscard.md"; echo dirty > "$T/wt/wip.txt"
python3 "$T/rs_viol.py" "$T/rscard.md" "s#0" "$T/wt" "$(grep '리서치:' "$T/rscard.md")" >/dev/null 2>&1; v="$(grep '^- 리서치 위반:' "$T/rscard.md")"
{ [[ "$v" == *"code.py"* ]] && [[ "$v" == *"wip.txt"* ]] && [[ "$v" != *"RESEARCH-a.md"* ]]; } && ok "close: 허용 밖 커밋·작업트리 변경만 «리서치 위반» 으로 기록(허용 경로 제외)" || bad "close 위반 기록 «${v}»"
git -C "$T/wt" rm -q --cached code.py -f; rm -f "$T/wt/code.py" "$T/wt/wip.txt"; git -C "$T/wt" -c user.name=t -c user.email=t@t commit -q -m rm; git -C "$T/wt" reset -q --hard "$BASE"; mkdir -p "$T/wt/design/alpha"; echo r > "$T/wt/design/alpha/RESEARCH-b.md"
printf '# c\n## 상태\n- 리서치: s#0 base=%s 허용=design/alpha/RESEARCH-*.md\n' "$BASE" > "$T/rscard2.md"
python3 "$T/rs_viol.py" "$T/rscard2.md" "s#0" "$T/wt" "$(grep '리서치:' "$T/rscard2.md")" >/dev/null 2>&1; grep -q '리서치 위반' "$T/rscard2.md" && bad "close: 허용 경로만 변경인데 위반 기록" || ok "close: 허용 경로(RESEARCH-*.md)만 → 위반 0"
grep -q 'ft-opencode-reap.sh' "$BIN/ft-nano-close.sh" && grep -q '리서치 닫힘' "$BIN/ft-nano-close.sh" && ok "close: 닫힘 줄 기록 + opencode reap 연결 실재" || bad "close: 닫힘 줄 코드 없음"

# ── 8b. ft-nano-close 리서치 닫힘 줄 · reap 실패 흡수 금지(§9-3) — 스크립트에서 닫힘 블록을 꺼내 가짜 reap 으로 실행 ──
_s="$(grep -n '^# R387 §7-3·§9-3' "$BIN/ft-nano-close.sh" | head -1 | cut -d: -f1)"; _e="$(awk -v s="${_s:-0}" 'NR>s && /^fi$/{print NR; exit}' "$BIN/ft-nano-close.sh")"
sed -n "$((_s+1)),${_e}p" "$BIN/ft-nano-close.sh" > "$T/rs_close.sh"
[ -s "$T/rs_close.sh" ] && ok "close: 닫힘 블록 추출" || bad "close: 닫힘 블록 추출 실패"
mkdir -p "$T/rh"; rcls() { # <reap 본문|-> <agent> → OUT·RC · 카드 CD
  CD="$T/rcard.md"; printf '# c\n## 상태\n' > "$CD"; rm -f "$T/rh/ft-opencode-reap.sh"; [ "$1" = - ] || printf '%s\n' "$1" > "$T/rh/ft-opencode-reap.sh"
  OUT="$(RS_LINE=x RS_AGENT="$2" HERE="$T/rh" SEAT='s#0' CARD="$CD" bash "$T/rs_close.sh" 2>&1)"; RC=$?; }
rcls '#!/bin/sh
echo "left=1"; exit 1' opencode; { [ "$RC" = 1 ] && [[ "$OUT" == *"CLOSE-FAIL reap left=1 rc=1"* ]] && grep -q '리서치 닫힘: s#0 .* CLOSE-FAIL reap left=1 rc=1' "$CD"; } && ok "close: reap(left=1 · rc1) → CLOSE-FAIL 출력 + exit 1 + 카드 원문(도구 없음으로 흡수 0)" || bad "close reap 실패 rc=$RC $OUT"
rcls '#!/bin/sh
echo "left=0"; exit 0' opencode; { [ "$RC" = 0 ] && grep -q '리서치 닫힘: s#0 .* reap left=0 rc=0' "$CD"; } && ok "close: reap(left=0 · rc0) → 닫힘 줄 left=0" || bad "close reap 성공 rc=$RC $OUT"
rcls '#!/bin/sh
echo "left=0"; exit 2' opencode; { [ "$RC" = 1 ] && grep -q 'CLOSE-FAIL reap left=0 rc=2' "$CD"; } && ok "close: left=0 인데 rc2 → CLOSE-FAIL" || bad "close reap rc2 rc=$RC $OUT"
rcls - opencode; { [ "$RC" = 0 ] && grep -q 'reap 도구 없음' "$CD"; } && ok "close: reap 도구 미설치만 «도구 없음»" || bad "close reap 미설치 rc=$RC $OUT"
rcls - claude; { [ "$RC" = 0 ] && grep -q '리서치 닫힘: s#0 .* kill rc=0' "$CD"; } && ok "close: Fable 좌석 → kill rc=0 줄" || bad "close Fable rc=$RC $OUT"

# ── 8c. staged 문서 = 홈 원본 + 40번/§12 추가만 (삭제 줄 0) ──
for pair in "$HOME/.claude/skills/tmuxc/COMM-GUIDE-BOOT.md:COMM-GUIDE-BOOT.md" "$HOME/.claude/skills/fable-team/references/main-team-governance.md:main-team-governance.md"; do
  hf="${pair%%:*}"; sf="$REPO/harness/design/harness/staged-r387/${pair##*:}"
  if [ -f "$hf" ]; then n="$(diff "$hf" "$sf" | grep -c '^<')"; [ "$n" = 0 ] && ok "staged ${pair##*:}: 홈 대비 삭제 줄 0" || bad "staged ${pair##*:}: 홈 대비 삭제 $n 줄(홈이 바뀐 뒤 사본을 다시 뜬다)"; else echo "SKIP 홈 파일 없음 $hf"; fi
done

# ── 9. ft-nano-spawn --research (--dry-run · 임시 bin 사본에 lint·제안서 게이트만 대역) ──
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$T" ok
FAKE="$T/fake"; mkdir -p "$FAKE"; printf '#!/bin/sh\ncase "$1" in has-session) exit 1;; list-sessions) exit 0;; *) exit 1;; esac\n' > "$FAKE/tmux"; chmod 755 "$FAKE/tmux"
SB="$T/bin"; cp -R "$KIT" "$SB"; printf '#!/bin/sh\necho OK\nexit 0\n' > "$SB/ft-index-lint.sh"; printf '#!/bin/sh\necho gate-ok\nexit 0\n' > "$SB/ft-proposal-gate.sh"; rm -f "$SB/ft-opencode-reap.sh"
mkdir -p "$T/repo"; git init -q "$T/repo"; git -C "$T/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$T/repo/design/alpha/indices/진행" "$T/repo/design/alpha/indices/대기" "$T/repo/.fable-team/comm"; echo '{"_name":"alpha"}' > "$T/repo/.fable-team/seats-alpha.json"
echo '# 카드' > "$T/repo/design/alpha/indices/진행/x.md"; echo '# 카드' > "$T/repo/design/alpha/indices/대기/y.md"
spr() { ( cd "$T/repo" && export FT_ROOT="$T/repo" FT_NANO_PREFIX="byz-alpha-nano-" FT_SEATS_JSON="$T/repo/.fable-team/seats-alpha.json" FT_TEAMSET=0 && PATH="$FAKE:$PATH" bash "$SB/ft-nano-spawn.sh" "$@" --from byz-alpha-master-claude#1 2>&1 ); }
o="$(spr design/alpha/indices/진행/x.md --agent claude --model 'claude-fable-5-1[1m]' --raise "리서치" --research --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"PLAN seat=byz-alpha-nano-x-research#0"* ]] && [[ "$o" == *"RESEARCH seat=byz-alpha-nano-x-research#0 allow=design/alpha/RESEARCH-*.md"* ]] && [[ "$o" == *"리서치 워커(판정 2282"*"산출 1개"*"코드 수정 0"*"[완료·휴식]"* ]]; } && ok "spawn --research --dry-run(Fable): 이름 꼬리 -research · 고정 문단 · 허용 경로" || bad "spawn dry-run rc=$rc $o"
o="$(spr design/alpha/indices/진행/x.md --agent opencode --model deepseek/deepseek-v4-flash --research --dry-run)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"REJECT --research --agent opencode"*"ft-opencode-reap.sh(r286) 미설치"* ]]; } && ok "spawn --research opencode + reap 도구 없음 → REJECT 원문" || bad "spawn opencode 무reap rc=$rc $o"
printf '#!/bin/sh\necho left=0\n' > "$SB/ft-opencode-reap.sh"
o="$(spr design/alpha/indices/진행/x.md --agent opencode --model deepseek/deepseek-v4-flash --research --dry-run)"; rc=$?
{ [ "$rc" = 0 ] && [[ "$o" == *"byz-alpha-nano-x-research#0"* ]]; } && ok "spawn --research opencode + reap 도구 있음 → 통과" || bad "spawn opencode reap rc=$rc $o"
o="$(spr design/alpha/indices/대기/y.md --agent claude --model 'claude-fable-5-1[1m]' --raise "r" --research --dry-run)"; rc=$?
{ [ "$rc" = 1 ] && [[ "$o" == *"--research 는 진행/"* ]]; } && ok "spawn --research 는 진행/ 부모 카드만" || bad "spawn 대기카드 rc=$rc $o"
o="$(spr design/alpha/indices/진행/x.md --agent claude --model 'claude-fable-5-1[1m]' --raise "r" --dry-run)"; [[ "$o" == *"REJECT 대기/ 에 있는 인덱스만 연다"* ]] && ok "spawn 기본(--research 없음): 진행/ 카드는 여전히 REJECT" || bad "spawn 기본 동작 변함 $o"

echo "fail=$fail"; [ "$fail" = 0 ]
