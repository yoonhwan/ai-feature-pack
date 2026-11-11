#!/usr/bin/env bash
# test_successor_open_codex_wait_r1660.sh — 후계 개설이 «관측할 수 없는 신호» 를 상한까지 기다리지 않는다 (r1660 · Issue #8313).
# 실사건: issues-master-sol#60 codex 개설 rc124 2회 — SessionStart 대기 60초 + 송신·도달 확인이 70초 상한을 넘어 기계 [인계] 0(손 전송 #283274).
#   ⓐ codex = 대기 0 + «생략» 1줄 ⓑ claude·pi 대기 불변 ⓒ 한 실행 FT_SO_BUDGET 안 · 넘으면 rc5+재실행 1줄 ⓓ 재실행 이어가기 ⓔ 회귀 0 · 가짜 tmux·tmuxc·pgrep·ps·date(시계)·send·mbox·reach·retire + 임시 리포 · sleep 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; SO0="$BIN/ft-successor-open.sh"; SO="$SO0"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=$((fail+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; BODY="$TMP/body.txt"; CLK="$TMP/clock"; HCNT="$TMP/hcnt"; PCNT="$TMP/pcnt"
mkdir -p "$REPO/.fable-team/state" "$REPO/design" "$FAKE"; git -C "$REPO" init -q
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| t | `design/t/` | h | 현역 |\n' > "$REPO/design/TEAMS.md"
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$REPO/.fable-team/state/all-stop.log"
printf '{"_master":"byz-t-master-claude#1","_arch":"byz-t-arch-claude#1"}\n' > "$REPO/.fable-team/seats-t.json"
STATE="$REPO/.fable-team/state/successor"; OLD="byz-t-old-codex#1"; NEW="byz-t-old-codex#2"
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
mkstub tmux 'case "$1" in
  has-session) n=$(cat "$HCNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$HCNT"; [ "$n" -ge "${HAS_AT:-3}" ] && exit 0; exit 1;;   # 1=OLD 승계 판정 · 2=ⓑ-0 재실행 판정 · 3=열기 뒤 확인
  list-panes) echo 4242;;
  show-environment) [ -n "${BOOT_TEXT:-}" ] && echo "TMUXC_BOOT_TEXT=$BOOT_TEXT"; exit 0;;
  display-message) case "$*" in *":"*) echo "$PANE_CWD";; esac;;
esac; exit 0'
mkstub tmuxc 'case "$1" in boot-enter) echo "bootenter $2" >> "$LOG";; *) echo "open $2" >> "$LOG";; esac; exit 0'
mkstub pgrep 'case "$*" in
  "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";;
  "-P "*) n=$(cat "$PCNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$PCNT"; [ "$n" -gt "${UP_AT:-0}" ] && { echo 5555; exit 0; }; exit 1;;
esac; echo 5555; exit 0'
mkstub ps 'case "$1 $2 $3" in "-o lstart= -p") echo "Thu Oct 29 18:00:00 2026";; *) exec /bin/ps "$@";; esac'
mkstub send 'echo send >> "$LOG"; echo "QUEUED seq=777 to=$1"; exit 0'
mkstub mbox 'echo "mbox $1" >> "$LOG"; exit 0'
: > "$FAKE/mbox_doorbell.sh"
mkstub reach 'exit "${REACH_RC:-4}"'
mkstub retire 'echo "retire $1 $2" >> "$LOG"; echo "RETIRED $1 -> $2"; exit 0'
# 격리 시계(DA HOLD §3): date 는 «읽기만» · sleep 이 요청받은 초만큼 시계를 민다(실제로 안 자서 시험은 빠르다) — 시계는 «기다린 곳» 에서만 간다
mkstub date 'case "$1" in +%s) cat "$CLK" 2>/dev/null || /bin/date +%s;; *) exec /bin/date "$@";; esac'
mkstub sleep 'n=$(cat "$CLK" 2>/dev/null || /bin/date +%s); echo $(( n + ${1%%.*} )) > "$CLK"'
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok; SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
# 문지기 대역이 export 한 FT_RES_ROOT = 도구가 보는 하네스 데이터 루트 → arch 게이트(ft_teamset arch-live)도 이 루트의 명단을 본다
mkdir -p "$RES/design" && cp "$REPO/design/TEAMS.md" "$RES/design/TEAMS.md" && cp "$REPO/.fable-team/seats-t.json" "$RES/.fable-team/seats-t.json"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문\n' > "$BODY"
PI="$TMP/pisess"; cd_proj() { printf '%s' "$REPO" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g'; }; cd_pi() { printf '%s' "$REPO" | sed -e 's|^[/\\]||' -e 's|[/\\:]|-|g'; }
world() {   # world [claude|pi] — 후계 시작 기록 상태 · 로그·카운터·시계 초기화
  rm -rf "$TMP/home" "$PI" "$STATE"; : > "$LOG"; echo 0 > "$HCNT"; echo 0 > "$PCNT"; rm -f "$CLK"; mkdir -p "$TMP/home/.claude/projects"
  case "${1:-none}" in
    claude) mkdir -p "$TMP/home/.claude/projects/$(cd_proj)"
            printf '{"agentName":"%s"}\n{"type":"attachment","hookEvent":"SessionStart"}\n' "$NEW" > "$TMP/home/.claude/projects/$(cd_proj)/a.jsonl";;
    pi) mkdir -p "$PI/--$(cd_pi)--"
        printf '{"type":"session_info","name":"%s"}\n' "$NEW" > "$PI/--$(cd_pi)--/s.jsonl";;
  esac
}
run() {   # run <agent> [env…]
  local ag="$1"; shift
  env TZ=Asia/Seoul HOME="$TMP/home" PANE_CWD="$REPO" PATH="$FAKE:$PATH" LOG="$LOG" CLK="$CLK" HCNT="$HCNT" PCNT="$PCNT" \
      FT_SO_POLL=0 FT_SO_WAIT_MAX=2 FT_RES_ROOT="$RES" SENSORS="$SENSORS" FT_PI_SESSIONS_DIR="$PI" \
      FT_GOV_MD="$HERE/../../skill/references/main-team-governance.md" \
      FT_SEND_VERIFIED="$FAKE/send" FT_MBOX_SH="$FAKE/mbox" FT_REACH_CHECK="$FAKE/reach" FT_SEAT_RETIRE="$FAKE/retire" \
      "$@" bash "$SO" "$OLD" "$REPO" --name "$NEW" --agent "$ag" --model model-x --body-file "$BODY" > "$TMP/out" 2>&1
  RC=$?
}
n() { grep -c "^$1" "$LOG"; }
reached_ok() { [ -f "$STATE/$OLD.json" ] && grep -q "\"successor\":\"$NEW\"" "$STATE/$OLD.json"; }
SOUTC() { tr '\n' ' ' < "$TMP/out" | cut -c1-300; }
# ⓐ codex = 관측 못 하는 신호를 안 기다린다 — 대기 0 · «생략» 1줄 · 곧바로 송신·도달
world; run codex
{ [ "$RC" = 0 ] && reached_ok && grep -q 'SessionStart 관측 생략(codex — 기록 없음)' "$TMP/out" && ! grep -q 'SessionStart 미관측' "$TMP/out" && [ "$(n open)" = 1 ] && [ "$(n send)" = 1 ]; } \
  && ok "ⓐ codex → SessionStart 대기 0 · «생략» 1줄 · 송신 1 · 도달 파일" || bad "ⓐ rc=$RC $(SOUTC)"
# 변이 M1 codex 생략 조건 삭제(사본만) → ⓐ 가 도로 «미관측» 대기로 돌아가야 한다
mkdir -p "$TMP/mut"; cp -R "$BIN/." "$TMP/mut/"
sed 's/^if \[ "\$AGENT" = codex \] || \[ "\$AGENT" = cmd \] || \[ "\$AGENT" = opencode \]; then$/if false; then/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
[ "$(grep -c '^if false; then$' "$TMP/mut/ft-successor-open.sh")" = 1 ] || bad "변이 M1 적용 실패"
SO="$TMP/mut/ft-successor-open.sh"; world; run codex
{ [ "$RC" = 0 ] && ! grep -q '관측 생략' "$TMP/out" && grep -q 'SessionStart 미관측' "$TMP/out"; } \
  && ok "M1 codex 생략 삭제 → ⓐ FAIL 재현(도로 «미관측» 대기)" || bad "M1 이 ⓐ 에 안 잡힘 rc=$RC $(SOUTC)"
SO="$SO0"
# ⓑ claude·pi 는 대기 그대로 — 기록이 있으면 곧바로 관측(«생략» 0)
world claude; run claude
{ [ "$RC" = 0 ] && reached_ok && grep -q "SessionStart 관측 $NEW" "$TMP/out" && ! grep -q '관측 생략' "$TMP/out"; } \
  && ok "ⓑ claude → SessionStart 관측(대기 그대로 · «생략» 0)" || bad "ⓑ claude rc=$RC $(SOUTC)"
world pi; run pi
{ [ "$RC" = 0 ] && reached_ok && grep -q "SessionStart 관측 $NEW" "$TMP/out" && ! grep -q '관측 생략' "$TMP/out"; } \
  && ok "ⓑ pi → SessionStart 관측(대기 그대로 · «생략» 0)" || bad "ⓑ pi rc=$RC $(SOUTC)"
# ⓒ 한 실행 시간 상한 — FT_SO_BUDGET 을 넘기 전에 단계 사이에서 멈추고 rc5 + «다시 실행» 1줄(70초 래퍼 rc124 0)
world; run codex UP_AT=999 FT_SO_WAIT_MAX=60 FT_SO_POLL=1 FT_SO_BUDGET=60
{ [ "$RC" = 5 ] && grep -q '다음: 같은 인자로 다시 실행(이어가기 r609)' "$TMP/out" && ! reached_ok && [ "$(n send)" = 0 ] && [ "$(n open)" = 1 ]; } \
  && ok "ⓒ 상한 초과 → rc5 + «다시 실행» 1줄 · 송신 0 · 도달 파일 0(세션은 열림)" || bad "ⓒ rc=$RC $(SOUTC)"
# ⓓ ⓒ 뒤 같은 인자 재실행 = 열기 건너뛰고 송신·도달 파일·retire 까지(r609 경로) · 송신 1회(두 번 송신 0)
OPEN1="$(n open)"; rm -f "$CLK"; run codex
{ [ "$RC" = 0 ] && [ "$(n open)" = "$OPEN1" ] && [ "$(n send)" = 1 ] && reached_ok && [ "$(n retire)" = 1 ] && grep -q '이어감' "$TMP/out"; } \
  && ok "ⓓ 재실행 → 열기 건너뜀 · 송신 1 · 도달 파일 1 · retire 1" || bad "ⓓ rc=$RC open=$(n open)/$OPEN1 $(SOUTC)"
# ⓖ (DA HOLD §3) 송신 단계 예산: 격리 시계로 «기동 58초» 만 소비 → 잔여 2초 < 송신·도달 예약 40초 → 송신 0 · rc5 · 이어가기 1줄
world; run codex UP_AT=58 FT_SO_WAIT_MAX=60 FT_SO_POLL=1 FT_SO_BUDGET=60
{ [ "$RC" = 5 ] && [ "$(n send)" = 0 ] && ! reached_ok && grep -q '다음: 같은 인자로 다시 실행(이어가기 r609)' "$TMP/out"; } \
  && ok "ⓖ 잔여 2초 → 송신 전 rc5 · 송신 0 · 도달 파일 0(중복 송신 0)" || bad "ⓖ rc=$RC send=$(n send) $(SOUTC)"
# 변이 M3 송신 예약 삭제(사본만) → ⓖ 에서 송신에 들어가 중복 위험이 돌아온다
sed 's/^so_send_ready || so_budget_stop/so_budget_ok || so_budget_stop/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
[ "$(grep -c '^so_budget_ok || so_budget_stop' "$TMP/mut/ft-successor-open.sh")" = 1 ] || bad "변이 M3 적용 실패"
SO="$TMP/mut/ft-successor-open.sh"; world; run codex UP_AT=58 FT_SO_WAIT_MAX=60 FT_SO_POLL=1 FT_SO_BUDGET=60
{ [ "$(n send)" -ge 1 ]; } && ok "M3 송신 예약 삭제 → ⓖ FAIL 재현(잔여 2초에 송신 진입)" || bad "M3 가 ⓖ 에 안 잡힘 rc=$RC $(SOUTC)"
SO="$SO0"
# 변이 M2 시간 상한 삭제(사본만) → ⓒ 의 rc5 칸이 안 잡혀야 한다(재현 검증)
sed 's/^  exit 5$/  return 0/' "$SO0" > "$TMP/mut/ft-successor-open.sh"
[ "$(grep -c '^  return 0$' "$TMP/mut/ft-successor-open.sh")" = 1 ] || bad "변이 M2 적용 실패"
SO="$TMP/mut/ft-successor-open.sh"; world; run codex UP_AT=999 FT_SO_WAIT_MAX=60 FT_SO_POLL=1 FT_SO_BUDGET=60
{ [ "$RC" != 5 ] && ! reached_ok && [ "$(n send)" = 0 ]; } \
  && ok "M2 상한 삭제 → ⓒ rc5 칸 FAIL 재현(rc=$RC · 안 멈춤)" || bad "M2 가 ⓒ 에 안 잡힘 rc=$RC $(SOUTC)"
SO="$SO0"
# ⓔ 기존 successor_open 시험 회귀 0 — 기준선 = 이 환경에서 origin/main 도 같은 4칸 FAIL(ⓝ·ⓗ·ⓘ·ⓚ · comm 폴더·카드 폴더 없음 = r1660 과 무관한 환경 결함). 새 FAIL 0 이면 회귀 0.
bash "$HERE/test_successor_open.sh" > "$TMP/reg" 2>&1; RRC=$?
NEWF="$(grep '^FAIL ' "$TMP/reg" | grep -vE '^FAIL (ⓝ|ⓗ|ⓘ|ⓚ) ')"
[ -z "$NEWF" ] && ok "ⓔ test_successor_open.sh 새 FAIL 0(기준선 4칸 밖 · rc=$RRC)" || bad "ⓔ 새 FAIL: $(printf '%s' "$NEWF" | cut -c1-200)"
cmp -s "$SO0" "$HERE/../kit/fable-team/bin/ft-successor-open.sh" && ok "ⓕ bin·kit 짝 cmp0" || bad "ⓕ kit 짝 다름"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
