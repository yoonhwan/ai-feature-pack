#!/usr/bin/env bash
# test_pi_agent_allow_r540.sh — r540: pi 를 하네스 에이전트로 허용(이름 lint · 열기 도구 --agent/모델/--effort · 준비 확인 · 승계 열기 · 도달 확인).
#   가짜 tmux·tmuxc·pgrep·mbox + 임시 HOME·git 리포 + fixtures/r540 화면 글자만 쓴다 — 실 세션·실 pi·외부 호출·명부 쓰기 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1   # R201: 시험은 추적 사본 원본을 직접 부른다(LIVE_BIN 으로 넘기지 않음)
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
H="$HERE/.."; KIT="$H/kit/fable-team/bin"; SKILL="$H/../skill/scripts"; FIX="$HERE/fixtures/r540"
PIM="opengateway/deepseek/deepseek-v4.1-flash-ultrafast"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# ⓐ·ⓑ·ⓘ 이름 lint — 추적본·키트 둘 다
for L in "$H/bin/ft-name-lint.sh" "$KIT/ft-name-lint.sh"; do
  t="${L#"$H"/}"
  for n in "aifp-worker-master-pi#0" "aifp-pi-master-pi#0"; do
    out="$(bash "$L" "$n" 2>&1)"; [ $? -eq 0 ] && [ "$out" = "PASS $n" ] && ok "$t: $n PASS" || bad "$t: $n → $out"
  done
  out="$(bash "$L" "aifp-pi-master#0" 2>&1)"; [ $? -eq 1 ] && echo "$out" | grep -q '에이전트 꼬리 필수' && ok "$t: aifp-pi-master#0 REJECT 꼬리 필수" || bad "$t: aifp-pi-master#0 → $out"
  out="$(bash "$L" "byz-x-master-pii#0" 2>&1)"; [ $? -eq 1 ] && echo "$out" | grep -q '에이전트여야' && ok "$t: byz-x-master-pii#0 REJECT(오타 0)" || bad "$t: pii → $out"
done
bash "$HERE/test_name_lint.sh" >/dev/null 2>&1 && ok "기존 test_name_lint.sh rc0" || bad "기존 test_name_lint.sh rc≠0"

# ⓒ ft-role-spawn --agent pi --dry-run → tmuxc 인자 --agent pi --model … --effort high · --ctx 0 (추적본·키트)
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; mkdir -p "$REPO/.fable-team/comm" "$REPO/design/v65/indices/inbox/master" "$FAKE"
git -C "$REPO" init -q; : > "$REPO/design/v65/SEATBELT-README.md"; echo '{}' > "$REPO/.fable-team/seats.json"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| v65 | `design/v65/` | x | 현역 |\n' > "$REPO/design/TEAMS.md"
printf '#!/usr/bin/env bash\ncase "$1" in has-session) exit 1;; *) exit 0;; esac\n' > "$FAKE/tmux"
printf '#!/usr/bin/env bash\necho "TMUXC $*"\n' > "$FAKE/tmuxc"; chmod +x "$FAKE/tmux" "$FAKE/tmuxc"
for SP in "$H/bin/ft-role-spawn.sh" "$KIT/ft-role-spawn.sh"; do
  t="$(basename "$(dirname "$(dirname "$SP")")")"
  out="$(cd "$REPO" && FT_ROOT="$REPO" PATH="$FAKE:$PATH" bash "$SP" master --agent pi --model "$PIM" --effort high --dry-run 2>&1)"
  tl="$(printf '%s\n' "$out" | grep '^TMUXC open')"
  { printf '%s\n' "$out" | grep -q '^PLAN seat=byz-v65-master-pi#0 .*agent=pi' && printf '%s' "$tl" | grep -qF -- "--agent pi --model $PIM --effort high" \
    && ! printf '%s' "$tl" | grep -q -- '--ctx'; } && ok "$t: role-spawn pi dry-run 인자" || bad "$t: role-spawn pi → $(printf '%s' "$out" | tail -5 | tr '\n' '|')"
done
grep -qF 'case "$AGENT" in claude|codex|cmd|opencode|pi) ;;' "$SKILL/ft-role-spawn.sh" && grep -qF 'case "$AGENT" in claude|cmd|codex|pi) OPEN+=(--effort' "$SKILL/ft-role-spawn.sh" \
  && ok "skill: role-spawn pi 허용·effort" || bad "skill: role-spawn pi 줄 없음"

# ⓓ ft-nano-spawn — 모델 표 pi 기본 · OPEN 에 --effort · --ctx 0 (선택 블록·OPEN 블록을 꺼내 돌린다 — test_nano_spawn_tier 꼴)
for SP in "$H/bin/ft-nano-spawn.sh" "$KIT/ft-nano-spawn.sh"; do
  t="$(basename "$(dirname "$(dirname "$SP")")")"
  _s="$(grep -n '^if \[ -z "\$MODEL" \]; then case' "$SP" | head -1 | cut -d: -f1)"
  { [ -n "$_s" ] && sed -n "${_s},\$p" "$SP" | awk '{print} /^fi$/{exit}' && echo 'echo "$AGENT|$MODEL"'; } > "$TMP/sel.sh"
  r="$(env -i PATH="$PATH" AGENT=pi MODEL= bash "$TMP/sel.sh" 2>&1)"; [ "$r" = "pi|$PIM" ] && ok "$t: nano-spawn --agent pi 기본 모델" || bad "$t: nano 모델 → $r"
  r="$(env -i PATH="$PATH" AGENT=pi MODEL= FT_PI_MODEL=x/y bash "$TMP/sel.sh" 2>&1)"; [ "$r" = "pi|x/y" ] && ok "$t: FT_PI_MODEL 우선" || bad "$t: FT_PI_MODEL → $r"
  { grep -E '^OPEN=\(tmuxc open "\$WTDIR"' "$SP"; grep -E '^\[ "\$AGENT" = claude \] && OPEN\+=\(--ctx 1m\)' "$SP"; grep -E '^case "\$AGENT" in claude\|cmd\|codex(\|pi)?\) OPEN\+=\(--effort' "$SP"; echo 'echo "${OPEN[*]}"'; } > "$TMP/open.sh"
  r="$(env -i PATH="$PATH" AGENT=pi MODEL="$PIM" EFFORT=high WTDIR=/w NAME=n bash "$TMP/open.sh" 2>&1)"
  [ "$r" = "tmuxc open /w --name n --agent pi --model $PIM --effort high" ] && ok "$t: nano-spawn pi OPEN 인자" || bad "$t: nano OPEN → $r"
done
grep -qF 'case "$AGENT" in claude|cmd|codex|pi) OPEN+=(--effort' "$SKILL/ft-nano-spawn.sh" && ok "skill: nano-spawn pi effort" || bad "skill: nano-spawn pi effort 줄 없음"

# ⓕ 준비 확인 식 — pi 화면 끝 줄(라이브 149 · 폭 80 시작·잘림·thinking off) MATCH · claude·codex 화면 오탐 0 (키트·skill)
for TS in "$KIT/ft-tmux-spawn.sh" "$SKILL/ft-tmux-spawn.sh"; do
  t="$(basename "$(dirname "$TS")")"
  re_line="$(grep -E '^PI_READY_RE=' "$TS" | head -1)"
  [ -n "$re_line" ] || { bad "$t: PI_READY_RE 줄 없음"; continue; }
  RE="$(env -i bash -c "$re_line; printf '%s' \"\$PI_READY_RE\"")"
  for f in pi-w149-live pi-w80-start pi-w80-start-unknown-ctx pi-w80-thinking-off pi-w80-truncated; do
    grep -qE "$RE" "$FIX/$f.txt" && ok "$t: 준비 MATCH $f" || bad "$t: 준비 불일치 $f (식=$RE)"
  done
  for f in claude-tail-live codex-tail-live; do
    grep -qE "$RE" "$FIX/$f.txt" && bad "$t: 오탐 $f" || ok "$t: 오탐 0 $f"
  done
  grep -qE '^  if \[ "\$AGENT" = "pi" \]; then' "$TS" && grep -qE '^    claude\|cmd\|pi\) +\[ -n "\$MODEL" \]' "$TS" && ok "$t: pi 준비 분기·--effort 전달" || bad "$t: pi 분기 없음"
done

# ⓗ 같은 코드 벌 대조 — 추적본=키트 cmp0 · skill/키트 차이는 base 그대로(tmux-spawn 1줄) · reach-check 두 벌의 pi 블록 동일
for f in ft-name-lint.sh ft-role-spawn.sh ft-nano-spawn.sh ft-successor-open.sh; do
  cmp -s "$H/bin/$f" "$KIT/$f" && ok "cmp0 bin=kit $f" || bad "bin≠kit $f"
done
[ "$(diff "$KIT/ft-tmux-spawn.sh" "$SKILL/ft-tmux-spawn.sh" | grep -c '^[<>]')" = 2 ] && ok "tmux-spawn kit↔skill 차이 = base 의 BOOT 줄 1쌍뿐" || bad "tmux-spawn kit↔skill 차이 늘어남"
pib() { sed -n '/^# ─ pi 좌석 (r540)/,/^# ─ pi 좌석 끝/p' "$1"; }
[ -n "$(pib "$KIT/ft-reach-check.sh")" ] && [ "$(pib "$KIT/ft-reach-check.sh")" = "$(pib "$H/comm/ft-reach-check.sh")" ] && ok "reach-check pi 블록 kit=comm" || bad "reach-check pi 블록 없음·불일치"

# ⓙ 도달 확인(ft-reach-check) 단위 — pi 대화 기록 session_info.name 으로 좌석 특정 · user 레코드 마커
RC_SH="$KIT/ft-reach-check.sh"; RH="$TMP/rhome"; PANE="/Users/x/Project/pi-agent-ops/.worktrees/pi-master"
PDIR="$RH/.pi/agent/sessions/--Users-x-Project-pi-agent-ops-.worktrees-pi-master--"
RF="$TMP/rfake"; mkdir -p "$RF"
printf '#!/usr/bin/env bash\ncase "$*" in *pane_pid*) echo 4242;; *) echo "$PANE_CWD";; esac\n' > "$RF/tmux"
printf '#!/usr/bin/env bash\n[ "$*" = "-P 4242 -x pi" ] && [ -n "${PANE_PI:-}" ] && { echo 99; exit 0; }; exit 1\n' > "$RF/pgrep"; chmod +x "$RF/tmux" "$RF/pgrep"
mkpi() { # mkpi <좌석명> <user 본문|-> — pi 꼴 기록 1파일
  mkdir -p "$PDIR"; { printf '{"type":"session","version":3,"id":"u","cwd":"%s"}\n{"type":"session_info","id":"a","name":"%s"}\n' "$PANE" "$1"
    [ "$2" = - ] || printf '{"type":"message","id":"b","message":{"role":"user","content":[{"type":"text","text":"%s"}]}}\n' "$2"; } > "$PDIR/$RANDOM.jsonl"; }
reach() { env HOME="$RH" PANE_CWD="$PANE" PATH="$RF:$PATH" "$@" bash "$RC_SH" "$SEAT" "[발주 #777]" 1 0 >"$TMP/rout" 2>&1; echo $?; }
SEAT="aifp-pi-master-pi#0"
rm -rf "$RH"; mkpi "$SEAT" "[발주 #777] 본문"
[ "$(reach FT_REACH_AGENT=pi)" = 0 ] && grep -q '^REACHED' "$TMP/rout" && ok "ⓙ pi user 레코드 마커 → REACHED(env)" || bad "ⓙ env → $(cat "$TMP/rout")"
[ "$(reach PANE_PI=1)" = 0 ] && ok "ⓙ pane 본체 pi 감지 → REACHED" || bad "ⓙ pane 감지 → $(cat "$TMP/rout")"
rm -rf "$RH"; mkpi "$SEAT" - ; mkpi "other-x-master-pi#0" "[발주 #777] 남의 것"
[ "$(reach FT_REACH_AGENT=pi)" = 4 ] && ok "ⓙ 내 파일에 user 레코드 없음(남의 좌석엔 있음) → NOT_REACHED 4" || bad "ⓙ 남의 좌석 → $(cat "$TMP/rout")"
rm -rf "$RH"; mkdir -p "$RH/.pi/agent/sessions"
[ "$(reach FT_REACH_AGENT=pi)" = 4 ] && grep -q '아직 없음' "$TMP/rout" && ok "ⓙ 좌석 폴더 아직 없음 → 4 · 사유 출력" || bad "ⓙ 폴더 없음 → $(cat "$TMP/rout")"
rm -rf "$RH"
[ "$(reach FT_REACH_AGENT=pi)" = 5 ] && grep -q 'UNVERIFIABLE' "$TMP/rout" && ok "ⓙ pi 기록 뿌리 없음 → UNVERIFIABLE 5" || bad "ⓙ 뿌리 없음 → $(cat "$TMP/rout")"
# claude 좌석은 그대로 — agentName 파일의 user 레코드
SEAT="byz-t-master-claude#1"; CJ="$RH/.claude/projects/$(printf '%s' "$PANE" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"; mkdir -p "$CJ"
printf '{"type":"agent-name","agentName":"%s"}\n{"type":"user","message":{"content":"[발주 #777] x"}}\n' "$SEAT" > "$CJ/c.jsonl"
[ "$(reach)" = 0 ] && ok "ⓙ claude 좌석 도달 그대로(pi 감지 0)" || bad "ⓙ claude → $(cat "$TMP/rout")"

# ⓙ ft-successor-open --agent pi — 가짜 tmuxc 가 tmuxc 부팅 문장을 pi 꼴 기록으로 남기고, 가짜 mbox 가 doorbell 제출을 남긴다 · 실 send-verified·reach-check
SO="$KIT/ft-successor-open.sh"; SREPO="$TMP/srepo"; SF="$TMP/sfake"; SLOG="$TMP/s.log"; BODY="$TMP/body.txt"; SH="$TMP/shome"
mkdir -p "$SREPO" "$SF"; git -C "$SREPO" init -q; printf '골 1\n골 2\n골 3\n본문\n' > "$BODY"
SPD="$SH/.pi/agent/sessions/--$(printf '%s' "$PANE" | sed -e 's|^/||' -e 's|/|-|g')--"
SENSORS="$TMP/sensors/fake-sensors"
mks() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$SF/$1"; chmod +x "$SF/$1"; }
mks tmux  'case "$1" in has-session) exit 0;; list-panes) echo 4242;; capture-pane) exit 0;; display-message) case "$*" in *pane_pid*) echo 4242;; *) echo "$PANE_CWD";; esac;; esac; exit 0'
mks tmuxc 'echo "tmuxc $*" >> "$SLOG"; [ -n "${NO_BOOT:-}" ] && exit 0; mkdir -p "$SPD"; printf "{\"type\":\"session\",\"cwd\":\"%s\"}\n{\"type\":\"session_info\",\"name\":\"%s\"}\n{\"type\":\"message\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"통신 표준 부팅\"}]}}\n" "$PANE_CWD" "$4" > "$SPD/s.jsonl"'
mks pgrep 'case "$*" in "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";; "-P 4242") echo 5555; exit 0;; esac; exit 1'
mks mbox  'case "$1" in send) [ -n "${SUBMIT:-}" ] && printf "{\"type\":\"message\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"[발주 #777] recv\"}]}}\n" >> "$SPD/s.jsonl"; echo "QUEUED seq=777 to=$2 pending=1 doorbell=sent";; ring) echo "RING seq=$3 doorbell=sent";; esac; echo "mbox $1" >> "$SLOG"; exit 0'
srun() { : > "$SLOG"; rm -rf "$SH" "$SREPO/.fable-team/state"
  env HOME="$SH" PANE_CWD="$PANE" SPD="$SPD" SLOG="$SLOG" SENSORS="$SENSORS" PATH="$SF:$PATH" FT_SO_POLL=0 FT_SO_WAIT_MAX=3 \
      FT_RES_ROOT="$FT_RES_ROOT" FT_MBOX_SH="$SF/mbox" FT_SEND_VERIFIED="$KIT/ft-send-verified.sh" "$@" \
      bash "$SO" "aifp-pi-master#1" "$SREPO" --name "aifp-pi-master-pi#0" --agent pi --model "$PIM" --effort high --body-file "$BODY" > "$TMP/sout" 2>&1
  echo $?; }
r="$(srun SUBMIT=1)"
{ [ "$r" = 0 ] && grep -q '^OK successor=aifp-pi-master-pi#0 seq=777' "$TMP/sout" && [ -f "$SREPO/.fable-team/state/successor/aifp-pi-master#1.json" ] \
  && grep -q 'SessionStart 관측 aifp-pi-master-pi#0' "$TMP/sout" && grep -qF -- "--agent pi --model $PIM --effort high" "$SLOG" && ! grep -q -- '--ctx' "$SLOG" && [ "$(grep -c '^mbox ring' "$SLOG")" = 0 ]; } \
  && ok "ⓙ 승계 pi → 시작 확인(session_info) · 도달 · OK · 도달 파일 · ring 0" || bad "ⓙ 승계 pi rc=$r out=$(tr '\n' '|' < "$TMP/sout") log=$(tr '\n' '|' < "$SLOG")"
r="$(srun FT_PI_SESSIONS_DIR="$TMP/none")"
{ [ "$r" = 5 ] && grep -q '\[HIL\]' "$TMP/sout" && [ ! -e "$SREPO/.fable-team/state/successor/aifp-pi-master#1.json" ]; } \
  && ok "ⓙ pi 기록 못 읽음 → rc5 · [HIL] · 도달 파일 0(조용한 통과 0)" || bad "ⓙ 못 읽음 rc=$r out=$(tr '\n' '|' < "$TMP/sout")"
r="$(srun NO_BOOT=1 FT_PI_SESSIONS_DIR="$TMP/none")"
grep -q 'SessionStart 미관측 aifp-pi-master-pi#0' "$TMP/sout" && ok "ⓙ pi 시작 기록 없음 → 미관측 표시" || bad "ⓙ 미관측 out=$(tr '\n' '|' < "$TMP/sout")"

[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
