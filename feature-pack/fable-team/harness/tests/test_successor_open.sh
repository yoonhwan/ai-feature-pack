#!/usr/bin/env bash
# test_successor_open.sh — ft-successor-open.sh (R107): 승계 후계 개설 = 기동 확인(pgrep) → 검증 송신 → 도달 파일.
# 가짜 tmux·tmuxc·pgrep·ft-send-verified·mbox·ft-reach-check(PATH 앞 스텁 + env) + 임시 git 리포만 쓴다 — 실 세션·홈·명부 쓰기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다(LIVE_BIN 으로 넘기지 않음)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SO="${FT_SO_PATH:-$HERE/../../harness/kit/fable-team/bin/ft-successor-open.sh}"   # r609: FT_SO_PATH = 실패 시험 먼저(base 판)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

[ -f "$SO" ] && bash -n "$SO" && ok "bash -n" || { bad "ft-successor-open.sh 없음·구문 오류: $SO"; echo "FAILED $fail"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; CNT="$TMP/pgrep.cnt"; BODY="$TMP/body.txt"
mkdir -p "$REPO" "$FAKE"; git -C "$REPO" init -q
STATE="$REPO/.fable-team/state/successor"; OLD="byz-t-old-claude#1"; NEW="byz-t-new-claude#2"
OPENED="$TMP/opened"   # r609: tmuxc open 이 세션을 열었음을 tmux 스텁에게 알리는 표식(열기 전 has-session = 1)

mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux   'case "$1" in
  has-session) [ -n "${EXISTS:-}" ] && case "$*" in *"=$EXISTS"*) exit 0;; esac; [ -f "$OPENED" ] && exit 0; exit 1;;
  list-panes) echo 4242;;
  display-message) t=""; while [ $# -gt 0 ]; do [ "$1" = "-t" ] && { t="${2:-}"; break; }; shift; done
    case "$t" in "") :;; *:) [ -z "${PANE_CWD_UNREADABLE:-}" ] && echo "${PANE_CWD_OVERRIDE:-$PANE_CWD}";; *) :;; esac;;   # r622: 실제 tmux 꼴 — «=이름»(콜론 없음) 은 창 대상에서 빈 값, «=이름:» 만 pane 을 고른다
esac; exit 0'
mkstub tmuxc  'echo "tmuxc $*" >> "$LOG"; [ "${TMUXC_RC:-0}" = 0 ] && : > "$OPENED"; exit "${TMUXC_RC:-0}"'
mkstub pgrep  'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; esac; echo pgrep >> "$LOG"; n=$(cat "$CNT" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$CNT"; [ "$n" -ge "${PGREP_UP_AT:-3}" ] && { echo 5555; exit 0; }; exit 1'
mkstub send   'echo send >> "$LOG"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit "${SEND_RC:-0}"'
mkstub mbox   'echo "mbox $1" >> "$LOG"; echo "RING seq=$3 doorbell=sent"; exit 0'
: > "$FAKE/mbox_doorbell.sh"   # r607: 고른 mbox 폴더의 짝 파일 검사 — 열기 전 REJECT 를 피하려면 있어야 한다
mkstub reach  'echo reach >> "$LOG"; exit "${REACH_RC:-0}"'
# 자원 문지기 격리(R218) — 실 머신 압력·실 pressure.tsv 를 재지 않는다: 공통 가짜 센서 헬퍼(압력 1·에이전트 35 · 임시 FT_RES_ROOT).
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문 나머지\n' > "$BODY"

JDIR="$TMP/home/.claude/projects/$(printf '%s' "$TMP/pane" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"
run() { # run <환경 KEY=VAL…> — 호출마다 로그·카운터·도달 파일 초기화. 출력은 $TMP/out, rc 는 $RC
  rm -f "$LOG" "$CNT" "$OPENED"; rm -rf "$STATE"; : > "$LOG"
  # r609 ⓞ: 도달 파일을 미리 심는다(«이미 도달» 갈래) — run 이 STATE 를 비우므로 환경 플래그로 심는다
  [ -n "${SEED_REACHED:-}" ] && mkdir -p "$STATE" && printf '{"successor":"%s","seq":777,"reached_at":"t","rc":0,"model":"m"}\n' "$NEW" > "$STATE/$OLD.json"
  env HOME="$TMP/home" PANE_CWD="$TMP/pane" PATH="$FAKE:$PATH" LOG="$LOG" CNT="$CNT" OPENED="$OPENED" EXISTS="${EXISTS:-}" \
      PANE_CWD_OVERRIDE="${PANE_CWD_OVERRIDE:-}" FT_SO_POLL=0 FT_SO_WAIT_MAX=5 \
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
: > "$CALLER/comm/mbox_doorbell.sh"
mkdir -p "$REPO/.fable-team/comm"
printf '#!/usr/bin/env bash\necho "mbox-target $1" >> "$LOG"; echo "RING seq=$3 doorbell=sent"\n' > "$REPO/.fable-team/comm/mbox.sh"
: > "$REPO/.fable-team/comm/mbox_doorbell.sh"
mkstub send   'echo send >> "$LOG"; echo "mboxenv $(cd -- "$(dirname -- "${FT_MBOX_SH:-.}")" && pwd -P)/$(basename -- "${FT_MBOX_SH:-.}")" >> "$LOG"; echo "QUEUED seq=777 to=$1 pending=1 doorbell=sent"; exit "${SEND_RC:-0}"'   # r607: 경로 꼴(/var vs /private) 무관하게 실제 폴더로 비교
runx() { # runx <설치 사본> <대상 워크트리> <환경 KEY=VAL…> — FT_MBOX_SH 를 걸지 않는다
  local sox="$1" wt="$2"; shift 2; rm -f "$LOG" "$CNT" "$OPENED"; rm -rf "$STATE"; : > "$LOG"
  env -u FT_MBOX_SH HOME="$TMP/home" PANE_CWD="$TMP/pane" PATH="$FAKE:$PATH" LOG="$LOG" CNT="$CNT" OPENED="$OPENED" EXISTS="${EXISTS:-}" \
      PANE_CWD_OVERRIDE="${PANE_CWD_OVERRIDE:-}" FT_SO_POLL=0 FT_SO_WAIT_MAX=5 \
      FT_RES_ROOT="$RES" SENSORS="$SENSORS" FT_SEND_VERIFIED="$FAKE/send" FT_REACH_CHECK="$FAKE/reach" "$@" \
      bash "$sox" "$OLD" "$wt" --name "$NEW" --agent claude --model 'claude-opus-5-5[1m]' --ctx 1m --effort high --body-file "$BODY" > "$TMP/out" 2>&1
  RC=$?
}
TMBOX="$(cd -- "$REPO" && pwd -P)/.fable-team/comm/mbox.sh"   # r607: ROOT = git --git-common-dir 물리 경로(/private/var…)

# ⓗ 다른 리포 WT → ring·송신 환경·꼬리 모두 대상 리포 mbox · 호출자 mbox 0
runx "$CALLER/bin/ft-successor-open.sh" "$REPO" SEND_RC=2 REACH_RC=0
{ [ "$RC" -eq 0 ] && [ "$(count 'mbox-target ring')" = 1 ] && [ "$(count 'mbox-caller')" = 0 ] && grep -q "^mboxenv $TMBOX\$" "$LOG" \
  && grep -q "mbox=$TMBOX" "$TMP/out"; } \
  && ok "ⓗ 다른 리포 → 대상 리포 mbox(ring·송신·꼬리 mbox=) · 호출자 0" || bad "ⓗ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓘ 같은 리포(설치 사본이 대상 리포 안) → 같은 mbox · 도달 파일 불변
mkdir -p "$REPO/.fable-team"; cp -R "$CALLER/bin" "$REPO/.fable-team/bin"
mkdir -p "$REPO/.fable-team/state"; printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$REPO/.fable-team/state/all-stop.log"   # r626 r4: 설치 꼴 루트 = 원장 없음이면 전팀 정지 — 설치가 남기는 init 줄
runx "$REPO/.fable-team/bin/ft-successor-open.sh" "$REPO" SEND_RC=2 REACH_RC=0
{ [ "$RC" -eq 0 ] && [ "$(count 'mbox-target ring')" = 1 ] && [ -f "$STATE/$OLD.json" ] && grep -q "$NEW" "$STATE/$OLD.json"; } \
  && ok "ⓘ 같은 리포 → 같은 mbox · 도달 파일" || bad "ⓘ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"
rm -rf "$REPO/.fable-team/bin"

# ⓙ 대상 리포에 mbox 없음 → REJECT rc2 · 루트 경로 표시 · open·송신·호출자 mbox 0
NOM="$TMP/nombox"; mkdir -p "$NOM"; git -C "$NOM" init -q
runx "$CALLER/bin/ft-successor-open.sh" "$NOM" SEND_RC=0
{ [ "$RC" -eq 2 ] && grep -q '대상 리포 mbox 없음' "$TMP/out" && grep -q "$NOM/.fable-team/comm/mbox.sh" "$TMP/out" \
  && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ] && [ "$(count 'mbox-caller')" = 0 ]; } \
  && ok "ⓙ mbox 없는 리포 → REJECT rc2 · open·송신 0 · 호출자 mbox 0" || bad "ⓙ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓚ r607 — 링크 워크트리 안에 옛 mbox 사본이 있어도 «리포 루트» mbox 를 고른다(옛 판 = 사본을 먼저 골랐다 = 승계 SEND_FAILED 원인)
git -C "$REPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$REPO" worktree add -q "$TMP/wt" -b wtb 2>/dev/null
mkdir -p "$TMP/wt/.fable-team/comm"; printf '#!/usr/bin/env bash\necho "mbox-wt $1" >> "$LOG"; echo "RING seq=$3 doorbell=sent"\n' > "$TMP/wt/.fable-team/comm/mbox.sh"
runx "$CALLER/bin/ft-successor-open.sh" "$TMP/wt" SEND_RC=2 REACH_RC=0
{ [ "$RC" -eq 0 ] && [ "$(count 'mbox-target ring')" = 1 ] && [ "$(count 'mbox-wt')" = 0 ] && grep -q "mbox=$TMBOX" "$TMP/out"; } \
  && ok "ⓚ 링크 워크트리 사본 있음 → 리포 루트 mbox 고름 · 사본 0" || bad "ⓚ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓛ r607 — 고른 mbox 폴더에 mbox_doorbell.sh 없음 → 열기(tmuxc) «전» REJECT rc2 · 송신 0
TMBOXDIR="$(cd -- "$REPO/.fable-team/comm" && pwd -P)"
mv "$REPO/.fable-team/comm/mbox_doorbell.sh" "$TMP/doorbell.bak"
runx "$CALLER/bin/ft-successor-open.sh" "$TMP/wt" SEND_RC=0
{ [ "$RC" -eq 2 ] && grep -q "mbox 짝 파일 없음: $TMBOXDIR/mbox_doorbell.sh" "$TMP/out" \
  && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ] && [ ! -e "$STATE/$OLD.json" ]; } \
  && ok "ⓛ 짝 파일 없음 → RC2 · open·송신 0" || bad "ⓛ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"
mv "$TMP/doorbell.bak" "$REPO/.fable-team/comm/mbox_doorbell.sh"

# ⓜ r607 — FT_MBOX_SH 명시는 지금과 같다(회귀 0)
run SEND_RC=0
{ [ "$RC" -eq 0 ] && [ "$(count send)" = 1 ] && [ -f "$STATE/$OLD.json" ]; } \
  && ok "ⓜ FT_MBOX_SH 명시 → 지금과 같음" || bad "ⓜ rc=$RC log=$(tr '\n' ' ' < "$LOG")"

# ⓝ r609(card ⓐ) — 세션은 이미 있고(같은 구 좌석이 연 것) 도달 파일은 없다 → 다시 돌리면 «이어감» · 열기 건너뜀 · ⓒ~ⓔ 그대로 · 도달 파일 1
EXISTS="$NEW" PANE_CWD_OVERRIDE="$REPO" run SEND_RC=0
{ [ "$RC" -eq 0 ] && grep -q "이어감: 세션 있음 $NEW — 열기 건너뜀" "$TMP/out" && [ "$(count tmuxc)" = 0 ] \
  && [ "$(count send)" = 1 ] && [ -f "$STATE/$OLD.json" ] && grep -q "$NEW" "$STATE/$OLD.json"; } \
  && ok "ⓝ r609 ⓐ 세션 이미 있음 → 이어감 · 열기 건너뜀 · 송신 1 · 도달 파일" || bad "ⓝ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓞ r609(card ⓑ) — 세션도 있고 도달 파일도 이미 이 NAME → «이미 도달» rc0 · 송신 0
EXISTS="$NEW" SEED_REACHED=1 run SEND_RC=0
{ [ "$RC" -eq 0 ] && grep -q '이미 도달' "$TMP/out" && [ "$(count send)" = 0 ] && [ "$(count tmuxc)" = 0 ] \
  && [ "$(jq -r '.seq' "$STATE/$OLD.json")" = 777 ]; } \
  && ok "ⓞ r609 ⓑ 이미 도달 → rc0 · 송신 0(도달 파일 불변)" || bad "ⓞ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓟ r609(card ⓒ) — 같은 이름 세션인데 pane 작업 폴더가 $WT 와 다름(남의 세션) → REJECT · 이어가기·송신 0
OTHER="$TMP/other_repo"; mkdir -p "$OTHER"; git -C "$OTHER" init -q
EXISTS="$NEW" PANE_CWD_OVERRIDE="$OTHER" run SEND_RC=0
{ [ "$RC" -ne 0 ] && grep -q 'REJECT 세션' "$TMP/out" && grep -q '남의 세션' "$TMP/out" \
  && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ] && [ ! -e "$STATE/$OLD.json" ]; } \
  && ok "ⓟ r609 ⓒ 남의 세션 → REJECT · 열기·송신 0 · 도달 파일 0" || bad "ⓟ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"

# ⓠ r622(카드 ⓐ·ⓑ) — 실제 tmux 꼴: 같은 이름 세션이 «같은 워크트리» 에 이미 있으면 «이어감»(옛 판 = 창 대상 «=이름» 이라 빈 값 → «작업 폴더가 다르다 pane=?» REJECT) · 다른 워크트리면 그 «실제 경로» 를 찍고 REJECT
EXISTS="$NEW" PANE_CWD_OVERRIDE="$REPO" run SEND_RC=0
{ [ "$RC" -eq 0 ] && grep -q "이어감: 세션 있음 $NEW — 열기 건너뜀" "$TMP/out" && [ "$(count tmuxc)" = 0 ] \
  && [ "$(count send)" = 1 ] && [ -f "$STATE/$OLD.json" ]; } \
  && ok "ⓠ r622 같은 폴더 → 이어감 · 열기 건너뜀 · 송신 1" || bad "ⓠ rc=$RC log=$(tr '\n' ' ' < "$LOG") out=$(cat "$TMP/out")"
EXISTS="$NEW" PANE_CWD_OVERRIDE="$OTHER" run SEND_RC=0
{ [ "$RC" -ne 0 ] && grep -q '작업 폴더가 다르다' "$TMP/out" && grep -qF "pane=$OTHER" "$TMP/out" && ! grep -q 'pane=?' "$TMP/out" \
  && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ]; } \
  && ok "ⓠ' r622 다른 폴더 → REJECT · 실제 경로(pane=) 찍힘" || bad "ⓠ' rc=$RC out=$(cat "$TMP/out")"

# ⓡ r622(카드 ⓒ) — 판 경로를 못 읽음(대역으로 빈 값) → «못 읽음(판정 불가)» 로 REJECT · «다르다» 문구 0
EXISTS="$NEW" PANE_CWD_OVERRIDE="$REPO" PANE_CWD_UNREADABLE=1 run SEND_RC=0
{ [ "$RC" -ne 0 ] && grep -q '작업 폴더를 못 읽음(판정 불가' "$TMP/out" && ! grep -q '작업 폴더가 다르다' "$TMP/out" \
  && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ] && [ ! -e "$STATE/$OLD.json" ]; } \
  && ok "ⓡ r622 못 읽음 → 판정 불가 REJECT · «다르다» 0 · 송신 0" || bad "ⓡ rc=$RC out=$(cat "$TMP/out")"

# ⓢ r622(카드 ⓓ) — 새로 연 좌석의 CWD 를 «실제 경로» 로 읽어 JDIR 이 그 워크트리 jsonl 폴더 → SessionStart 관측(옛 판 = «=이름» 빈 값 → 엉뚱한 폴더 → 미관측)
JDIR_WT="$TMP/home/.claude/projects/$(printf '%s' "$REPO" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"
mkdir -p "$JDIR_WT"; printf '{"type":"agent-name","agentName":"%s"}\n{"hookEvent":"SessionStart"}\n' "$NEW" > "$JDIR_WT/s.jsonl"
PANE_CWD_OVERRIDE="$REPO" run SEND_RC=0
{ [ "$RC" -eq 0 ] && grep -q 'SessionStart 관측' "$TMP/out" && ! grep -q '미관측' "$TMP/out"; } \
  && ok "ⓢ r622 새 좌석 CWD 실제 경로 → JDIR 그 워크트리 · SessionStart 관측" || bad "ⓢ rc=$RC out=$(cat "$TMP/out")"
rm -rf "$JDIR_WT"

# ⓣ r660(카드 ⓗ) desk 승계 본문 = planner 안내서 27줄 원문 필수 · 팀 직발 예시 금지(열기 «전» REJECT)
#   원문 출처 = 대상 리포 origin/main(못 읽으면 REJECT · fail-closed) · planner 역할 승계 판정 불변(문 밖).
GDIR="$REPO/design/teams/planner"; mkdir -p "$GDIR"
GUIDE_LINE='- **desk 좌석(판정 1779 · R205)**: desk 는 인터뷰·응대·요청 정리만(코드·커밋 0 · 팀 직접 발주 0 · 정리한 요청은 master 에 1통).'
{ for i in $(seq 1 26); do echo "- 안내서 $i 줄"; done; echo "$GUIDE_LINE"; } > "$GDIR/GUIDE-planner.md"
git -C "$REPO" add -A && git -C "$REPO" -c user.name=t -c user.email=t@t commit -q -m 'guide-planner 27줄'
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n%s\n' "$GUIDE_LINE" > "$TMP/desk_ok.txt"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n인계: 오빠 응대 이어받아라\n' > "$TMP/desk_noguide.txt"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n%s\n팀에는 이렇게 보낸다: send byz-harness-master-claude#92 "[발주] 이거 해라"\n' "$GUIDE_LINE" > "$TMP/desk_direct.txt"
DESK_OLD='byz-planner-desk-claude#38'; DESK_NEW='byz-planner-desk-claude#39'
OLD="$DESK_OLD"; NEW="$DESK_NEW"; BODY_USE="$TMP/desk_noguide.txt"; run SEND_RC=0
{ [ "$RC" -ne 0 ] && grep -q 'REJECT desk 승계 본문' "$TMP/out" && grep -q '27줄 원문 구절이 없다' "$TMP/out" \
  && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ]; } \
  && ok "ⓣ r660 desk 본문에 GUIDE 27줄 없음 → 열기 전 REJECT · open·송신 0" || bad "ⓣ rc=$RC out=$(cat "$TMP/out")"
BODY_USE="$TMP/desk_direct.txt"; run SEND_RC=0
{ [ "$RC" -ne 0 ] && grep -q '팀 직발 예시가 있다' "$TMP/out" && grep -q 'byz-harness-master-claude#92' "$TMP/out" \
  && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ]; } \
  && ok "ⓣ r660 desk 본문에 팀 직발 예시 → 열기 전 REJECT · open·송신 0" || bad "ⓣ 직발 rc=$RC out=$(cat "$TMP/out")"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n%s\n팀에는 이렇게 보낸다: relay '\''byz-harness-master-claude#92'\'' /tmp/x "[발주] 이거 해라"\n' "$GUIDE_LINE" > "$TMP/desk_direct_q.txt"
BODY_USE="$TMP/desk_direct_q.txt"; run SEND_RC=0
{ [ "$RC" -ne 0 ] && grep -q '팀 직발 예시가 있다' "$TMP/out" && grep -q 'byz-harness-master-claude#92' "$TMP/out" \
  && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ]; } \
  && ok "ⓣ r660 따옴표 주소(relay + 작은따옴표) 직발 예시 → 열기 전 REJECT" || bad "ⓣ 따옴표 rc=$RC out=$(cat "$TMP/out")"
BODY_USE="$TMP/desk_ok.txt"; run SEND_RC=0
{ [ "$RC" -eq 0 ] && [ "$(count send)" = 1 ] && grep -q "successor=$DESK_NEW" "$TMP/out"; } \
  && ok "ⓣ r660 desk 본문 = 27줄 원문 포함 → 통과 · 송신 1" || bad "ⓣ ok rc=$RC out=$(cat "$TMP/out")"
OLD='byz-planner-master-claude#94'; NEW='byz-planner-master-claude#95'; BODY_USE="$TMP/desk_noguide.txt"; run SEND_RC=0
{ [ "$RC" -eq 0 ] && [ "$(count send)" = 1 ]; } \
  && ok "ⓣ planner 역할 승계 = 이 문 밖(판정 불변 · GUIDE 줄 없어도 송신 1)" || bad "ⓣ planner rc=$RC out=$(cat "$TMP/out")"
OLD='byz-planner-desk-claude#38'; NEW='byz-planner-desk-claude#39'; BODY_USE="$TMP/desk_ok.txt"
run FT_GUIDE_PATH=design/teams/planner/NOPE.md SEND_RC=0
{ [ "$RC" -ne 0 ] && grep -q '줄을 읽지 못했다' "$TMP/out" && [ "$(count tmuxc)" = 0 ] && [ "$(count send)" = 0 ]; } \
  && ok "ⓣ r660 GUIDE 원문을 못 읽음 → REJECT · open·송신 0(fail-closed)" || bad "ⓣ guide없음 rc=$RC out=$(cat "$TMP/out")"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
