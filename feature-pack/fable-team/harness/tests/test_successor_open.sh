#!/usr/bin/env bash
# test_successor_open.sh — ft-successor-open.sh (R107): 승계 후계 개설 = 기동 확인(pgrep) → 검증 송신 → 도달 파일.
# 가짜 tmux·tmuxc·pgrep·ft-send-verified·mbox·ft-reach-check(PATH 앞 스텁 + env) + 임시 git 리포만 쓴다 — 실 세션·홈·명부 쓰기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다(LIVE_BIN 으로 넘기지 않음)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SO="$HERE/../../harness/kit/fable-team/bin/ft-successor-open.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

[ -f "$SO" ] && bash -n "$SO" && ok "bash -n" || { bad "ft-successor-open.sh 없음·구문 오류: $SO"; echo "FAILED $fail"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; CNT="$TMP/pgrep.cnt"; BODY="$TMP/body.txt"
mkdir -p "$REPO" "$FAKE"; git -C "$REPO" init -q
STATE="$REPO/.fable-team/state/successor"; OLD="byz-t-old-claude#1"; NEW="byz-t-new-claude#2"

mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux   'case "$1" in has-session) exit 0;; list-panes) echo 4242;; display-message) echo "$PANE_CWD";; esac; exit 0'
mkstub tmuxc  'echo "tmuxc $*" >> "$LOG"; exit "${TMUXC_RC:-0}"'
mkstub pgrep  'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo pgrep >> "$LOG"; n=$(cat "$CNT" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$CNT"; [ "$n" -ge "${PGREP_UP_AT:-3}" ] && { echo 5555; exit 0; }; exit 1'
mkstub send   'echo send >> "$LOG"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit "${SEND_RC:-0}"'
mkstub mbox   'echo "mbox $1" >> "$LOG"; echo "RING seq=$3 doorbell=sent"; exit 0'
mkstub reach  'echo reach >> "$LOG"; exit "${REACH_RC:-0}"'
# 자원 문지기 격리(R218) — 실 머신 압력·실 pressure.tsv 를 재지 않는다: 공통 가짜 센서 헬퍼(압력 1·에이전트 35 · 임시 FT_RES_ROOT).
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문 나머지\n' > "$BODY"

JDIR="$TMP/home/.claude/projects/$(printf '%s' "$TMP/pane" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"
run() { # run <환경 KEY=VAL…> — 호출마다 로그·카운터·도달 파일 초기화. 출력은 $TMP/out, rc 는 $RC
  rm -f "$LOG" "$CNT"; rm -rf "$STATE"; : > "$LOG"
  env HOME="$TMP/home" PANE_CWD="$TMP/pane" PATH="$FAKE:$PATH" LOG="$LOG" CNT="$CNT" FT_SO_POLL=0 FT_SO_WAIT_MAX=5 \
      FT_RES_ROOT="$RES" SENSORS="$SENSORS" \
      FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$FAKE/mbox" FT_REACH_CHECK="$FAKE/reach" "$@" \
      bash "$SO" "$OLD" "$REPO" --name "$NEW" --agent claude --model 'claude-opus-5-5[1m]' --ctx 1m --effort high --body-file "$BODY_USE" > "$TMP/out" 2>&1
  RC=$?
}
count() { grep -c "^$1" "$LOG"; }
BODY_USE="$BODY"

# ⓐ 본문 첫 3줄이 비었다 → REJECT · tmuxc·송신 0
printf '\n\n\n본문\n' > "$TMP/blank.txt"; BODY_USE="$TMP/blank.txt"; run
{ [ "$RC" -ne 0 ] && grep -q 'REJECT' "$TMP/out" && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ]; } \
  && ok "ⓐ 첫 3줄 빈 값 → REJECT · open·송신 0" || bad "ⓐ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"
BODY_USE="$BODY"

# ⓑ pgrep 이 3번째에 뜬다 → 송신은 그 뒤 1회 · 도달 파일
run PGREP_UP_AT=3 SEND_RC=0
order="$(grep -E '^(pgrep|send)$' "$LOG" | tr '\n' ' ')"
{ [ "$RC" -eq 0 ] && [ "$order" = "pgrep pgrep pgrep send " ] && [ -f "$STATE/$OLD.json" ] && grep -q "$NEW" "$STATE/$OLD.json"; } \
  && ok "ⓑ 기동 확인(pgrep 3) → 송신 1회 · 도달 파일" || bad "ⓑ rc=$RC order=$order file=$(ls "$STATE" 2>&1)"
# ⓑ-2 (R282 ③) 도달 파일 model 칸 = --model 값 · 기존 칸 불변
{ [ "$(jq -r '[.successor,.rc,.model]|join(",")' "$STATE/$OLD.json" 2>/dev/null)" = "$NEW,0,claude-opus-5-5[1m]" ] && [ "$(jq -r '.seq' "$STATE/$OLD.json")" = 777 ]; } \
  && ok "ⓑ-2 도달 파일 model = --model 값 · successor·seq·rc 불변" || bad "ⓑ-2 $(cat "$STATE/$OLD.json" 2>&1)"

# ⓒ pgrep 상한 초과 → 송신 0 · 도달 파일 0 · exit≠0 · [HIL] 줄
run PGREP_UP_AT=99
{ [ "$RC" -ne 0 ] && [ "$(count send)" = 0 ] && [ ! -e "$STATE/$OLD.json" ] && grep -q '\[HIL\]' "$TMP/out"; } \
  && ok "ⓒ 기동 미확인 → 송신 0 · 도달 파일 0 · [HIL]" || bad "ⓒ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓓ send-verified 5 → ring 1회 → 다시 5 → 도달 파일 0 · exit 5 · 닫기 0 안내
run SEND_RC=5 REACH_RC=5
{ [ "$RC" -eq 5 ] && [ "$(count 'mbox ring')" = 1 ] && [ ! -e "$STATE/$OLD.json" ] && grep -q '\[HIL\]' "$TMP/out" && grep -q '구 좌석 닫기 0' "$TMP/out"; } \
  && ok "ⓓ 5 → ring 1 → 5 → exit 5 · 도달 파일 0 · 닫기 0" || bad "ⓓ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓔ(카드 설계 보정 1 의 시험 ⓕ) 첫 송신 미제출 — send-verified 2 → ring → 도달 확인 0 → 도달 파일
run SEND_RC=2 REACH_RC=0
{ [ "$RC" -eq 0 ] && [ "$(count 'mbox ring')" = 1 ] && [ -f "$STATE/$OLD.json" ]; } \
  && ok "ⓔ 2 → ring 1 → 도달 → 도달 파일 · exit 0" || bad "ⓔ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓕ tmuxc open 실패 → REJECT · pgrep·송신 0
run TMUXC_RC=1
{ [ "$RC" -ne 0 ] && grep -q 'REJECT' "$TMP/out" && [ "$(count pgrep)" = 0 ] && [ "$(count send)" = 0 ]; } \
  && ok "ⓕ open 실패 → REJECT · 기동 확인·송신 0" || bad "ⓕ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓖ 새 좌석 jsonl 에 SessionStart 가 있으면 «관측», 없으면 상한까지 기다린 뒤 «미관측» 을 드러내고 송신(도달 판정은 send-verified 몫)
mkdir -p "$JDIR"
printf '{"type":"agent-name","agentName":"%s"}\n{"hookEvent":"SessionStart"}\n' "$NEW" > "$JDIR/s.jsonl"; run SEND_RC=0
{ [ "$RC" -eq 0 ] && grep -q 'SessionStart 관측' "$TMP/out" && ! grep -q '미관측' "$TMP/out"; } \
  && ok "ⓖ SessionStart 레코드 있음 → 관측 후 송신" || bad "ⓖ rc=$RC out=$(cat "$TMP/out")"
rm -f "$JDIR/s.jsonl"; run SEND_RC=0
{ [ "$RC" -eq 0 ] && grep -q 'SessionStart 미관측' "$TMP/out" && [ "$(count send)" = 1 ]; } \
  && ok "ⓖ SessionStart 없음 → 미관측 표시 · 송신 1회" || bad "ⓖ' rc=$RC out=$(cat "$TMP/out")"

# R343 — mbox 는 «호출한 설치 폴더» 가 아니라 «대상 워크트리의 리포» 것이다(FT_MBOX_SH 없을 때). 설치 사본 A(호출자) · 대상 리포 B(REPO).
CALLER="$TMP/callerA"; mkdir -p "$CALLER/comm"; cp -R "$(dirname -- "$SO")" "$CALLER/bin"
printf '#!/usr/bin/env bash\necho "mbox-caller $1" >> "$LOG"; echo "RING seq=$3 doorbell=sent"\n' > "$CALLER/comm/mbox.sh"
mkdir -p "$REPO/.fable-team/comm"
printf '#!/usr/bin/env bash\necho "mbox-target $1" >> "$LOG"; echo "RING seq=$3 doorbell=sent"\n' > "$REPO/.fable-team/comm/mbox.sh"
mkstub send   'echo send >> "$LOG"; echo "mboxenv ${FT_MBOX_SH:-}" >> "$LOG"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit "${SEND_RC:-0}"'
runx() { # runx <설치 사본> <대상 워크트리> <환경 KEY=VAL…> — FT_MBOX_SH 를 걸지 않는다
  local sox="$1" wt="$2"; shift 2; rm -f "$LOG" "$CNT"; rm -rf "$STATE"; : > "$LOG"
  env -u FT_MBOX_SH HOME="$TMP/home" PANE_CWD="$TMP/pane" PATH="$FAKE:$PATH" LOG="$LOG" CNT="$CNT" FT_SO_POLL=0 FT_SO_WAIT_MAX=5 \
      FT_RES_ROOT="$RES" SENSORS="$SENSORS" FT_SEND_VERIFIED="$FAKE/send" FT_REACH_CHECK="$FAKE/reach" "$@" \
      bash "$sox" "$OLD" "$wt" --name "$NEW" --agent claude --model 'claude-opus-5-5[1m]' --ctx 1m --effort high --body-file "$BODY" > "$TMP/out" 2>&1
  RC=$?
}
TMBOX="$REPO/.fable-team/comm/mbox.sh"

# ⓗ 다른 리포 WT → ring·송신 환경·꼬리 모두 대상 리포 mbox · 호출자 mbox 0
runx "$CALLER/bin/ft-successor-open.sh" "$REPO" SEND_RC=2 REACH_RC=0
{ [ "$RC" -eq 0 ] && [ "$(count 'mbox-target ring')" = 1 ] && [ "$(count 'mbox-caller')" = 0 ] && grep -q "^mboxenv $TMBOX\$" "$LOG" \
  && grep -q "mbox=$TMBOX" "$TMP/out"; } \
  && ok "ⓗ 다른 리포 → 대상 리포 mbox(ring·송신·꼬리 mbox=) · 호출자 0" || bad "ⓗ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓘ 같은 리포(설치 사본이 대상 리포 안) → 같은 mbox · 도달 파일 불변
mkdir -p "$REPO/.fable-team"; cp -R "$CALLER/bin" "$REPO/.fable-team/bin"
runx "$REPO/.fable-team/bin/ft-successor-open.sh" "$REPO" SEND_RC=2 REACH_RC=0
{ [ "$RC" -eq 0 ] && [ "$(count 'mbox-target ring')" = 1 ] && [ -f "$STATE/$OLD.json" ] && grep -q "$NEW" "$STATE/$OLD.json"; } \
  && ok "ⓘ 같은 리포 → 같은 mbox · 도달 파일" || bad "ⓘ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"
rm -rf "$REPO/.fable-team/bin"

# ⓙ 대상 리포에 mbox 없음 → REJECT rc2 · 두 경로 표시 · open·송신·호출자 mbox 0
NOM="$TMP/nombox"; mkdir -p "$NOM"; git -C "$NOM" init -q
runx "$CALLER/bin/ft-successor-open.sh" "$NOM" SEND_RC=0
{ [ "$RC" -eq 2 ] && grep -q '대상 리포 mbox 없음' "$TMP/out" && grep -q "$NOM/.fable-team/comm/mbox.sh" "$TMP/out" \
  && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ] && [ "$(count 'mbox-caller')" = 0 ]; } \
  && ok "ⓙ mbox 없는 리포 → REJECT rc2 · open·송신 0 · 호출자 mbox 0" || bad "ⓙ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓚ 워크트리 자체 mbox 가 루트 mbox 보다 먼저
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q "$TMP/wt" -b wtb 2>/dev/null
mkdir -p "$TMP/wt/.fable-team/comm"; printf '#!/usr/bin/env bash\necho "mbox-wt $1" >> "$LOG"; echo "RING seq=$3 doorbell=sent"\n' > "$TMP/wt/.fable-team/comm/mbox.sh"
runx "$CALLER/bin/ft-successor-open.sh" "$TMP/wt" SEND_RC=2 REACH_RC=0
{ [ "$RC" -eq 0 ] && [ "$(count 'mbox-wt ring')" = 1 ] && [ "$(count 'mbox-target')" = 0 ]; } \
  && ok "ⓚ 워크트리 mbox 가 루트 mbox 보다 먼저" || bad "ⓚ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
