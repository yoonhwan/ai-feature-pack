#!/usr/bin/env bash
# r1660_successor_env.sh — r1660 시험 두 파일(후계 개설 대기 분리 · 송신 예산)의 공통 준비 (source 전용).
#   임시 git 리포 + 가짜 tmux·tmuxc·pgrep·ps·send·mbox·reach·retire + 자원 문지기 대역 + 격리 시계.
#   실 tmux·실 좌석·실 우편함 없음 · sleep 은 안 자고 시계만 민다(시험이 빠르고, 시계는 «기다린 곳» 에서만 간다 — DA HOLD §3 꼴).
#   쓰는 법: `. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/r1660_successor_env.sh"` 뒤 `world [claude|pi]` · `run <agent> [env…]`
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." && pwd)"   # tests/
BIN="$HERE/../bin"; SO0="$BIN/ft-successor-open.sh"; SV0="$HERE/../comm/ft-send-verified.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; FAKE="$TMP/fakebin"; LOG="$TMP/calls.log"; BODY="$TMP/body.txt"
CLK="$TMP/clock"; HCNT="$TMP/hcnt"; PCNT="$TMP/pcnt"; PI="$TMP/pisess"
mkdir -p "$REPO/.fable-team/state" "$REPO/design" "$FAKE"; git -C "$REPO" init -q
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| t | `design/t/` | h | 현역 |\n' > "$REPO/design/TEAMS.md"
printf '2026-10-21T00:00:00\toff\tinstall\tinit\n' > "$REPO/.fable-team/state/all-stop.log"
printf '{"_master":"byz-t-master-claude#1","_arch":"byz-t-arch-claude#1"}\n' > "$REPO/.fable-team/seats-t.json"
STATE="$REPO/.fable-team/state/successor"; SENT="$STATE"; OLD="byz-t-old-codex#1"; NEW="byz-t-old-codex#2"
mkstub() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$FAKE/$1"; chmod +x "$FAKE/$1"; }
clk() { cat "$CLK" 2>/dev/null || /bin/date +%s; }
mkstub tmux 'case "$1" in
  has-session) n=$(cat "$HCNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$HCNT"; [ "$n" -ge "${HAS_AT:-3}" ] && exit 0; exit 1;;   # 1=OLD 승계 판정 · 2=ⓑ-0 재실행 판정 · 3=열기 뒤 확인
  list-panes) echo 4242;;
  show-environment) [ -n "${BOOT_TEXT:-}" ] && echo "TMUXC_BOOT_TEXT=$BOOT_TEXT"; exit 0;;
  display-message) case "$*" in *":"*) echo "$PANE_CWD";; esac;;
  capture-pane) [ "${RUNNING:-0}" = 1 ] && echo "✢ Hullaballooing… (9m 16s · ↓ 7.3k tokens)"; exit 0;;
esac; exit 0'
mkstub tmuxc 'case "$1" in boot-enter) echo "bootenter $2" >> "$LOG";; *) echo "open $2" >> "$LOG";; esac; exit 0'
mkstub pgrep 'case "$*" in
  "-a -x claude"|"-a -x codex") exec "$SENSORS/pgrep" "$@";;
  "-P "*) n=$(cat "$PCNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$PCNT"; [ "$n" -gt "${UP_AT:-0}" ] && { echo 5555; exit 0; }; exit 1;;
esac; echo 5555; exit 0'
mkstub ps 'case "$1 $2 $3" in "-o lstart= -p") echo "Thu Oct 29 18:00:00 2026";; *) exec /bin/ps "$@";; esac'
mkstub send 'echo send >> "$LOG"; echo "QUEUED seq=777 to=$1"; exit 0'
# mbox: send 는 queued 한 줄 · ring 은 doorbell 한 줄(둘 다 로그) — ft-send-verified 도 이 대역을 쓴다
mkstub mbox 'case "$1" in
  send) echo "mbox send" >> "$LOG"; echo "QUEUED seq=${SEQN:-777} to=${2:-?} doorbell=sent";;
  ring) echo "mbox ring" >> "$LOG"; echo "doorbell=sent";;
  *) echo "mbox $1" >> "$LOG";;
esac; exit 0'
: > "$FAKE/mbox_doorbell.sh"
# reach 대역: 프러브(FT_REACH_COUNT_ONLY)는 «읽힘» 만 답하고 시간을 안 쓴다 · 본 판정은 요청받은 timeout 만큼 시계를 밀고 REACH_RC 로 답한다
mkstub reach 'if [ -n "${FT_REACH_COUNT_ONLY:-}" ]; then exit 0; fi
echo "reach $2 to=${3:-0}" >> "$LOG"
n=$(cat "$CLK" 2>/dev/null || /bin/date +%s); echo $(( n + ${3:-0} )) > "$CLK"
exit "${REACH_RC:-4}"'
mkstub retire 'echo "retire $1 $2" >> "$LOG"; echo "RETIRED $1 -> $2"; exit 0'
# 격리 시계: date 는 읽기만 · sleep 이 요청받은 초만큼 민다(실제로 안 자서 시험은 빠르다)
mkstub date 'case "$1" in +%s) cat "$CLK" 2>/dev/null || /bin/date +%s;; *) exec /bin/date "$@";; esac'
mkstub sleep 'n=$(cat "$CLK" 2>/dev/null || /bin/date +%s); echo $(( n + ${1%%.*} )) > "$CLK"'
. "$HERE/lib/fake_resource_env.sh"; fake_resource_env "$TMP/sensors" ok
SENSORS="$TMP/sensors/fake-sensors"; RES="$FT_RES_ROOT"
# 문지기 대역이 export 한 FT_RES_ROOT = 도구가 보는 하네스 데이터 루트 → arch 게이트(ft_teamset arch-live)도 이 루트의 명단을 본다
mkdir -p "$RES/design" && cp "$REPO/design/TEAMS.md" "$RES/design/TEAMS.md" && cp "$REPO/.fable-team/seats-t.json" "$RES/.fable-team/seats-t.json"
printf '골 원문 1줄\n골 원문 2줄\n골 원문 3줄\n본문\n열린 칸 감시: 없음\n' > "$BODY"
cd_proj() { printf '%s' "$REPO" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g'; }
cd_pi() { printf '%s' "$REPO" | sed -e 's|^[/\\]||' -e 's|[/\\:]|-|g'; }
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
      FT_SEND_VERIFIED="${FT_SEND_VERIFIED_OVERRIDE:-$FAKE/send}" \
      FT_MBOX_SH="$FAKE/mbox" FT_REACH_CHECK="$FAKE/reach" FT_SEAT_RETIRE="$FAKE/retire" \
      "$@" bash "$SO" "$OLD" "$REPO" --name "$NEW" --agent "$ag" --model model-x --body-file "$BODY" > "$TMP/out" 2>&1
  RC=$?
}
n() { grep -c "^$1" "$LOG"; }
reached_ok() { [ -f "$STATE/$OLD.json" ] && grep -q "\"successor\":\"$NEW\"" "$STATE/$OLD.json"; }
sent_file() { cat "$STATE/$OLD.sent" 2>/dev/null; }
SOUTC() { tr '\n' ' ' < "$TMP/out" | cut -c1-300; }
