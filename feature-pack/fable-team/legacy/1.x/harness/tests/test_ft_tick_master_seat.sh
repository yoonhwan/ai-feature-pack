#!/usr/bin/env bash
# test_ft_tick_master_seat.sh — R27: 틱의 master 뉴스 대상 = 좌석표 _master 하나(role 첫 행·tick 행 순서 금지).
# 두 틱(키트 ft-tick.sh · 팀 ft-tick-team.sh)을 픽스처 좌석표로 --dry-run + 팀 판 자동 후계(heir_of·retarget_seat) 5경우(가짜 tmux 스텁).
# 모든 쓰기는 mktemp scratch 안 — 라이브 좌석표·stamp·알림 파일 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."
FX="$HERE/fixtures"
TICKS=("$ROOT/harness/bin/ft-tick.sh" "$ROOT/harness/bin/ft-tick-team.sh")
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/comm"   # r691: 틱은 comm 폴더가 없으면 rc1(r459 ft_comm_dir) — 임시 comm 을 FT_MBOX_DIR 로(실 루트 comm 0)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }

ENVX="FT_TICK_LAUNCHD=0 FT_TICK_MAGAZINE=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_WT_SWEEP=0 FT_TICK_HIL=0 FT_TICK_DRIFT=0 FT_TICK_RESUME=0"  # RESUME=0: 죽은 좌석 감시(실 tmux·자율 상태 읽기)는 R27 밖 · r509
# dry <틱> <픽스처> <케이스명> [출력접미사] → stdout/stderr 를 $TMP/<케이스>.out<접미사> 에. 알림 파일 = $TMP/<케이스>/p-DEAD-SEATS.alert
dry() {
  local tick="$1" fx="$2" name="$3" sfx="${4:-}"; mkdir -p "$TMP/$name"
  env $ENVX FT_MBOX_DIR="$TMP/comm" FT_TICK_SEATS="$fx" FT_TICK_STAMP_PREFIX="$TMP/$name/p-" FT_TICK_STATE_DIR="$TMP/$name/state" \
    bash "$tick" --once --dry-run > "$TMP/$name.out$sfx" 2>&1
  echo $?
}
nlines() { grep -c -E "$2" "$1" 2>/dev/null || true; }
alerts() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }

for tick in "${TICKS[@]}"; do
  t="$(basename "$tick" .sh)"; bash -n "$tick" && ok "$t bash -n" || bad "$t bash -n"

  # 1 정상: _master=T#2 · T#1 은 stop-ready
  c="$t-normal"; rc="$(dry "$tick" "$FX/r27-seats-normal.json" "$c")"
  chk "$c rc" "$rc" 0
  chk "$c master 줄 = T#2 만" "$(grep 'kind=master ' "$TMP/$c.out" | sed 's/.*seat=\([^ ]*\) .*/\1/' | tr '\n' ' ')" "T#2 "
  chk "$c WARN 0 · ERROR 0" "$(nlines "$TMP/$c.out" 'WARN|ERROR')" 0

  # 2 R21 재현: T#1 도 role master·ft-master-tick
  c="$t-r21"; rc="$(dry "$tick" "$FX/r27-seats-r21.json" "$c")"
  chk "$c rc" "$rc" 0
  chk "$c master 줄 = T#2 만" "$(grep 'kind=master ' "$TMP/$c.out" | sed 's/.*seat=\([^ ]*\) .*/\1/' | tr '\n' ' ')" "T#2 "
  chk "$c WARN 1줄(T#1)" "$(nlines "$TMP/$c.out" 'WARN master-tick row T#1 ≠ _master T#2')" 1
  chk "$c ERROR 0" "$(nlines "$TMP/$c.out" ERROR)" 0
  echo "--- R21 $t ---"; grep -E 'kind=master |WARN' "$TMP/$c.out"

  # 3 _master 행 없음
  c="$t-nomaster"; rc="$(dry "$tick" "$FX/r27-seats-no-master.json" "$c")"
  chk "$c rc" "$rc" 0
  chk "$c master 줄 0" "$(nlines "$TMP/$c.out" 'kind=master ')" 0
  chk "$c ERROR 1줄" "$(nlines "$TMP/$c.out" 'ERROR master news row invalid')" 1
  chk "$c 알림 1줄" "$(alerts "$TMP/$c/p-DEAD-SEATS.alert")" 1

  # 4 승계 중간(새 행 tick null · 옛 행만 뉴스 tick) + 서명 동일 2회 / 서명 변경
  c="$t-mid"; rc="$(dry "$tick" "$FX/r27-seats-succession-mid.json" "$c")"
  chk "$c rc" "$rc" 0
  chk "$c master 줄 0" "$(nlines "$TMP/$c.out" 'kind=master ')" 0
  chk "$c ERROR 1줄" "$(nlines "$TMP/$c.out" 'ERROR master news row invalid')" 1
  chk "$c 알림 1줄" "$(alerts "$TMP/$c/p-DEAD-SEATS.alert")" 1
  dry "$tick" "$FX/r27-seats-succession-mid.json" "$c" 2 > /dev/null
  chk "$c 같은 서명 2회째 ERROR 0" "$(nlines "$TMP/$c.out2" ERROR)" 0
  chk "$c 같은 서명 2회째 알림 유지 1줄" "$(alerts "$TMP/$c/p-DEAD-SEATS.alert")" 1
  dry "$tick" "$FX/r27-seats-no-master.json" "$c" 3 > /dev/null
  chk "$c 서명 바뀌면 ERROR 1줄" "$(nlines "$TMP/$c.out3" 'ERROR master news row invalid')" 1
  chk "$c 서명 바뀌면 알림 2줄" "$(alerts "$TMP/$c/p-DEAD-SEATS.alert")" 2

  # 5 뉴스 행 0 — 조용
  c="$t-nonews"; rc="$(dry "$tick" "$FX/r27-seats-no-news.json" "$c")"
  chk "$c rc" "$rc" 0
  chk "$c master 줄 0 · ERROR 0 · WARN 0" "$(nlines "$TMP/$c.out" 'kind=master |ERROR|WARN')" 0
  chk "$c 알림 파일 없음" "$([ -e "$TMP/$c/p-DEAD-SEATS.alert" ] && echo yes || echo no)" no
done

# ── 팀 판 자동 후계 5경우(가짜 tmux 스텁: ls 는 FAKE_TMUX_LS · list-panes 는 빈 결과) ──
TEAM="$ROOT/harness/bin/ft-tick-team.sh"
# 틱이 PATH 맨 앞에 /opt/homebrew/bin 을 붙이므로 PATH 스텁은 진짜 tmux 에 진다 — export -f 함수는 PATH 보다 먼저 잡힌다.
tmux() { [ "$1" = ls ] && printf '%s\n' ${FAKE_TMUX_LS:-}; return 0; }
export -f tmux
# heir <케이스> <좌석표 json> <FAKE_TMUX_LS> — 팀 틱을 --once(전송 경로)로 돌린다. 죽은 _master 좌석 → heir_of·retarget_seat·알림 경로.
heir() {
  local c="$1"; mkdir -p "$TMP/$c"; printf '%s' "$2" > "$TMP/$c/seats.json"; cp "$TMP/$c/seats.json" "$TMP/$c/seats.orig"
  FAKE_TMUX_LS="$3" FT_MBOX_DIR="$TMP/comm" FT_TICK_SEATS="$TMP/$c/seats.json" FT_TICK_STAMP_PREFIX="$TMP/$c/p-" FT_TICK_PIDFILE="$TMP/$c/pid" \
    FT_TICK_SEAT_STATUS=/nonexistent FT_TICK_GOAL_TICK=/nonexistent bash "$TEAM" --once > "$TMP/$c.out" 2>&1
}
J() { jq -r "$2" "$TMP/$1/seats.json"; }
same() { cmp -s "$TMP/$1/seats.json" "$TMP/$1/seats.orig" && echo same || echo changed; }
row() { echo "\"$1\": {\"role\": \"master\", \"tick\": \"ft-master-tick\"}"; }

c=heir1; heir $c "{\"_master\": \"X#3\", $(row 'X#3')}" "X#5 X#2"
chk "①후계 X#5 → _master" "$(J $c '._master')" "X#5"
chk "①X#5 tick" "$(J $c '.["X#5"].tick')" ft-master-tick
chk "①X#3 _replaced_by" "$(J $c '.["X#3"]._replaced_by')" "X#5"
chk "①알림 0" "$(alerts "$TMP/$c/p-DEAD-SEATS.alert")" 0
c=heir2; heir $c "{\"_master\": \"X#3\", $(row 'X#3')}" "X#2"
chk "②X#2(낮은 N) → 명부 불변" "$(same $c)" same
chk "②DEAD 알림 1줄" "$(alerts "$TMP/$c/p-DEAD-SEATS.alert")" 1
c=heir3; heir $c "{\"_master\": \"X#3\", $(row 'X#3'), \"X#4\": {\"role\": \"stop-ready\", \"tick\": null, \"_replaced_by\": \"X#9\"}}" "X#4"
chk "③X#4 은퇴 행 → 명부 불변" "$(same $c)" same
chk "③DEAD 알림 1줄" "$(alerts "$TMP/$c/p-DEAD-SEATS.alert")" 1
c=heir4; heir $c "{\"_master\": \"ft-harness-ops#3\", $(row 'ft-harness-ops#3')}" "ft-harness-ops#2 byz-harness-master-claude#14"
chk "④다른 base·낮은 N → 명부 불변(#2 회귀 0)" "$(same $c)" same
chk "④DEAD 알림 1줄" "$(alerts "$TMP/$c/p-DEAD-SEATS.alert")" 1
# ⑤ _master 가 이미 Y#9(≠dead) — 틱 경로는 dead 행을 뉴스로 안 쏘므로 retarget_seat 를 직접 호출
fn="$(sed -n '/^retarget_seat() {/,/^}/p' "$TEAM")"
c=heir5; mkdir -p "$TMP/$c"; printf '%s' "{\"_master\": \"Y#9\", $(row 'Y#9'), $(row 'X#3')}" > "$TMP/$c/seats.json"
SEATS="$TMP/$c/seats.json" bash -c "$fn"$'\n''retarget_seat X#3 5'; rc=$?
chk "⑤retarget_seat rc" "$rc" 0
chk "⑤_master 불변(Y#9)" "$(J $c '._master')" "Y#9"
chk "⑤X#3 _replaced_by=X#5" "$(J $c '.["X#3"]._replaced_by')" "X#5"
chk "⑤X#5 tick 상속" "$(J $c '.["X#5"].tick')" ft-master-tick
c=heir5b; mkdir -p "$TMP/$c"; printf '%s' "{\"_master\": \"X#3\", $(row 'X#3'), \"X#5\": {\"role\": \"stop-ready\", \"tick\": null, \"_replaced_by\": \"X#9\"}}" > "$TMP/$c/seats.json"; cp "$TMP/$c/seats.json" "$TMP/$c/seats.orig"
SEATS="$TMP/$c/seats.json" bash -c "$fn"$'\n''retarget_seat X#3 5'; rc=$?
chk "⑤b 은퇴 행 rc=3" "$rc" 3
chk "⑤b 명부 불변" "$(same $c)" same

echo "fail=$fail"; [ "$fail" = 0 ] && echo "ALL PASS"; exit "$fail"
