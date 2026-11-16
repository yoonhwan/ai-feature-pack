#!/usr/bin/env bash
# test_desk_tick_launch_list_r2102.sh — ft-desk-tick.sh LAUNCH 항목(r2102 · A3 · A4).
#   ④ 점검 라벨 = stall-scan · keeper · board-news 3줄(이 순서) · 옛 라벨 0 / keeper 만 rc 113 → 그 라벨 실패 줄 1 · 나머지 2줄
#   ⑤ NEWS 줄 = news-last.json at → `NEWS last_post=<분> age=<N>h` · 상한(기본 6 · env FT_DESK_TICK_NEWS_STALE_H) 이상 = STALE + 결정 필요 +1
#      파일 없음 · 깨진 json = `NEWS 판정 불가 — news-last.json` 1줄 + 결정 필요 +1
# 전부 합성(임시 루트 · 가짜 mbox · hil · launchctl · ps) · 실 launchctl · 실 우편함 0 · sleep 0. R2102_BIN = 시험할 bin(변이 사본용).
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
S="${R2102_BIN:-$HERE/../bin}/ft-desk-tick.sh"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

NOW=1794103664
DESK='byz-planner-desk-claude#121'; PLANNER='byz-planner-master-claude#240'
R="$T/root/.fable-team"; NL="$R/state/board/news-last.json"
mkdir -p "$R/comm" "$R/state/board" "$T/fakebin" "$T/hil" "$T/state"
printf '{"_master":"%s","_desk":"%s"}\n' "$PLANNER" "$DESK" > "$R/seats-planner.json"
printf '#!/usr/bin/env bash\ncase "$1" in send) echo QUEUED; exit 0;; recv) echo "SCANNED 1 mailbox(es): fake"; exit 0;; esac\nexit 2\n' > "$R/comm/mbox.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/hil/ft-hil.sh"
cat > "$T/fakebin/launchctl" <<'EOS'
#!/usr/bin/env bash
case "$2" in *"${FAKE_LAUNCH_BAD:-없음}") echo "Could not find service" >&2; exit 113;; esac
printf '%s\n\tstate = running\n\tlast exit code = 0\n' "$2"
EOS
printf '#!/usr/bin/env bash\necho "4242 python3 -u - /x %s"\n' "$DESK" > "$T/fakebin/ps"
chmod +x "$T/fakebin/launchctl" "$T/fakebin/ps"
printf 'ts=%s stall=0\n' "$NOW" > "$T/stall.log"
printf '{"ts":"2026-11-08T11:02:44Z","from":"%s","to":"x","body":"y"}\n' "$PLANNER" > "$R/comm/mailbox.log.jsonl"
run() {
  env FT_ROOT="$T/root" FT_HIL_DIR="$T/hil" FT_DESK_TICK_MBOX="$R/comm/mbox.sh" FT_DESK_TICK_HIL="$T/hil/ft-hil.sh" \
      FT_DESK_TICK_LAUNCHCTL="$T/fakebin/launchctl" FT_DESK_TICK_PS="$T/fakebin/ps" FT_DESK_TICK_STALL_LOG="$T/stall.log" \
      FT_DESK_TICK_LOG="$R/comm/mailbox.log.jsonl" FT_DESK_TICK_NOW="$NOW" FT_DESK_TICK_UID=501 FT_DESK_TICK_STATE_DIR="$T/state" \
      bash "$S" "$DESK" 2>&1
}
at() { python3 -c 'import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1])).isoformat())' "$((NOW - $1))"; }
news() { printf '{"at": "%s", "key": [], "snap": {}}\n' "$(at "$1")" > "$NL"; }
dec() { printf '%s\n' "$OUT" | tail -1 | sed -n 's/^결정 필요: //p'; }
has() { printf '%s\n' "$OUT" | grep -c -- "$1" | tr -d ' '; }

# ④ 점검 라벨(A3)
news 7200; OUT="$(run)"
chk "④ LAUNCH 3줄 = stall-scan · keeper · board-news 순서" '[ "$(printf "%s\n" "$OUT" | sed -n "s/^LAUNCH \([a-z-]*\) .*/\1/p" | tr "\n" " ")" = "stall-scan keeper board-news " ]'
chk "④ 옛 라벨 ft-tick · news-planner · news-desk 0회" '[ "$(has ft-tick)" = 0 ] && [ "$(has news-planner)" = 0 ] && [ "$(has news-desk)" = 0 ]'
chk "④ 전부 rc0 = 결정 필요 0" '[ "$(dec)" = 0 ]'
OUT="$(FAKE_LAUNCH_BAD=com.byz.ft2-keeper run)"
chk "④ keeper rc 113 → «LAUNCH keeper 판정 불가 rc=113» 1줄" '[ "$(has "^LAUNCH keeper 판정 불가 rc=113$")" = 1 ]'
chk "④ keeper 실패 · 나머지 2줄 그대로" '[ "$(has "^LAUNCH stall-scan state=running last_exit=0$")" = 1 ] && [ "$(has "^LAUNCH board-news state=running last_exit=0$")" = 1 ]'

# ⑤ 뉴스 마지막 발행 줄(A4)
news 7200; OUT="$(run)"; D0="$(dec)"
chk "⑤ 2시간 전 → «NEWS last_post=<분> age=2h» · STALE 0" '[ "$(has "^NEWS last_post=$(at 7200 | cut -c1-16) age=2h$")" = 1 ]'
chk "⑤ 2시간 전 → 결정 필요 0" '[ "$D0" = 0 ]'
news 25200; OUT="$(run)"
chk "⑤ 7시간 전 → age=7h STALE · 결정 필요 +1" '[ "$(has "^NEWS last_post=.* age=7h STALE$")" = 1 ] && [ "$(dec)" = $((D0 + 1)) ]'
news 7200; OUT="$(FT_DESK_TICK_NEWS_STALE_H=1 run)"
chk "⑤ env 상한 1 + 2시간 전 → STALE" '[ "$(has "^NEWS last_post=.* age=2h STALE$")" = 1 ] && [ "$(dec)" = $((D0 + 1)) ]'
rm -f "$NL"; OUT="$(run)"
chk "⑤ 파일 없음 → «NEWS 판정 불가 — news-last.json» 1줄 + 결정 필요 +1" '[ "$(has "^NEWS 판정 불가 — news-last.json$")" = 1 ] && [ "$(dec)" = $((D0 + 1)) ]'
printf '{"at": ' > "$NL"; OUT="$(run)"
chk "⑤ 깨진 json → «NEWS 판정 불가 — news-last.json» 1줄 + 결정 필요 +1" '[ "$(has "^NEWS 판정 불가 — news-last.json$")" = 1 ] && [ "$(dec)" = $((D0 + 1)) ]'

echo "fail=$fail"; [ "$fail" = 0 ]
