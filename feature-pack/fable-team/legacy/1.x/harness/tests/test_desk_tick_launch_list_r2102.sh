#!/usr/bin/env bash
# test_desk_tick_launch_list_r2102.sh — ft-desk-tick.sh LAUNCH 항목(r2102 · A3 · A4).
#   ④ 점검 라벨 = stall-scan · keeper · board-news 3줄(이 순서) · 옛 라벨 0 / keeper 만 rc 113 → 그 라벨 실패 줄 1 · 나머지 2줄
#   ⑤ NEWS 줄 = `NEWS last_post=<분|?> table=<분> age=<h>h behind=<N>` · T = origin/main 에서 «## 골 진행» 절을 마지막으로 고친 커밋
#      N = origin/main · origin/ops/main-base 에서 닿고 T 에서 안 닿고 커밋 시각 ≥ T 인 «완성/ 에 파일 더한» 커밋 수
#      age ≥ 상한(기본 3 · env FT_DESK_TICK_NEWS_STALE_H) ∧ N ≥ 1 = STALE + 결정 필요 +1 · git 실패 = `NEWS 판정 불가 — <단계> rc=<n>` + 결정 필요 +1
# 전부 합성(임시 루트 · 임시 git 리포 · 커밋 시각 = GIT_COMMITTER_DATE · 가짜 mbox · hil · launchctl · ps) · 실 launchctl · 실 우편함 0 · sleep 0.
# R2102_BIN = 시험할 bin(변이 사본용).
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
R="$T/root/.fable-team"; NL="$R/state/board/news-last.json"; LED=design/teams/planner/PLAN-oppa-ledger.md
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
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = log ] && exit 9; done\nexec git "$@"\n' > "$T/fakebin/git"
chmod +x "$T/fakebin/launchctl" "$T/fakebin/ps" "$T/fakebin/git"
printf 'ts=%s stall=0\n' "$NOW" > "$T/stall.log"
printf '{"ts":"2026-11-08T11:02:44Z","from":"%s","to":"x","body":"y"}\n' "$PLANNER" > "$R/comm/mailbox.log.jsonl"
run() {
  env FT_ROOT="$T/root" FT_HIL_DIR="$T/hil" FT_DESK_TICK_MBOX="$R/comm/mbox.sh" FT_DESK_TICK_HIL="$T/hil/ft-hil.sh" \
      FT_DESK_TICK_LAUNCHCTL="$T/fakebin/launchctl" FT_DESK_TICK_PS="$T/fakebin/ps" FT_DESK_TICK_STALL_LOG="$T/stall.log" \
      FT_DESK_TICK_LOG="$R/comm/mailbox.log.jsonl" FT_DESK_TICK_NOW="$NOW" FT_DESK_TICK_UID=501 FT_DESK_TICK_STATE_DIR="$T/state" \
      bash "$S" "$DESK" 2>&1
}
at() { python3 -c 'import datetime,sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1])).isoformat())' "$((NOW - $1))"; }
mi() { at "$1" | cut -c1-16; }   # mi <초 전> = 지역 시각 분까지
news() { printf '{"at": "%s", "key": [], "snap": {}}\n' "$(at "$1")" > "$NL"; }
dec() { printf '%s\n' "$OUT" | tail -1 | sed -n 's/^결정 필요: //p'; }
has() { printf '%s\n' "$OUT" | grep -c -- "$1" | tr -d ' '; }
nl() { printf '%s\n' "$OUT" | grep '^NEWS '; }
# 임시 원장 리포 — 커밋 시각은 «NOW − 초» 주입
G() { git -C "$T/root" -c user.email=t@t -c user.name=t "$@"; }
fresh() { rm -rf "$T/root/.git" "$T/root/design"; G init -q -b main; mkdir -p "$T/root/design/teams/planner" "$T/root/design/harness/indices/대기" "$T/root/design/harness/indices/완성"; }
tbl() { printf '# 원장\n\n## 골 진행\n\n| 1 | %s |\n\n## 다른 절\n\n%s\n' "$1" "$2" > "$T/root/$LED"; }   # tbl <표 값> <다른 절 값>
cm() { G add -A design; GIT_COMMITTER_DATE="$((NOW - $1)) +0000" GIT_AUTHOR_DATE="$((NOW - $1)) +0000" G commit -qm "$2"; }   # cm <초 전> <글>
card() { echo x > "$T/root/design/harness/indices/완성/$1.md"; }
refs() { G update-ref refs/remotes/origin/main "$1"; G update-ref refs/remotes/origin/ops/main-base "$2"; }
two_done() { fresh; tbl a x; cm "$1" T; G checkout -q -b ops; card c1; cm "$2" c1; card c2; cm "$3" c2; refs main ops; }   # 표 T 뒤 ops 에 완성 2

# ④ 점검 라벨(A3)
fresh; tbl a x; cm 14400 T; refs HEAD HEAD; news 7200; OUT="$(run)"
chk "④ LAUNCH 3줄 = stall-scan · keeper · board-news 순서" '[ "$(printf "%s\n" "$OUT" | sed -n "s/^LAUNCH \([a-z-]*\) .*/\1/p" | tr "\n" " ")" = "stall-scan keeper board-news " ]'
chk "④ 옛 라벨 ft-tick · news-planner · news-desk 0회" '[ "$(has ft-tick)" = 0 ] && [ "$(has news-planner)" = 0 ] && [ "$(has news-desk)" = 0 ]'
chk "④ 전부 rc0 = 결정 필요 0" '[ "$(dec)" = 0 ]'
OUT="$(FAKE_LAUNCH_BAD=com.byz.ft2-keeper run)"
chk "④ keeper rc 113 → «LAUNCH keeper 판정 불가 rc=113» 1줄" '[ "$(has "^LAUNCH keeper 판정 불가 rc=113$")" = 1 ]'
chk "④ keeper 실패 · 나머지 2줄 그대로" '[ "$(has "^LAUNCH stall-scan state=running last_exit=0$")" = 1 ] && [ "$(has "^LAUNCH board-news state=running last_exit=0$")" = 1 ]'

# ⑤ 뉴스 줄과 표 뒤처짐(A4)
OUT="$(run)"; D0="$(dec)"
chk "⑤ 표 4시간 전 · 완성 커밋 0 → «behind=0» · STALE 0 · 결정 필요 0" '[ "$(nl)" = "NEWS last_post=$(mi 7200) table=$(mi 14400) age=4h behind=0" ] && [ "$D0" = 0 ]'
two_done 14400 10800 10000; OUT="$(run)"
chk "⑤ ops 에 완성 2 + 표 4시간 전 → «age=4h behind=2 STALE» · 결정 필요 +1" '[ "$(nl)" = "NEWS last_post=$(mi 7200) table=$(mi 14400) age=4h behind=2 STALE" ] && [ "$(dec)" = $((D0 + 1)) ]'
G checkout -q ops; tbl a y; cm 3600 other; refs ops ops; OUT="$(run)"
chk "⑤ 원장 다른 절만 고침 → table 시각 그대로" 'nl | grep -q " table=$(mi 14400) age=4h behind=2 STALE$"'
tbl b y; cm 3000 T2; refs ops ops; OUT="$(run)"
chk "⑤ 표 절을 고친 커밋 더함 → «behind=0» · table 새 시각" '[ "$(nl)" = "NEWS last_post=$(mi 7200) table=$(mi 3000) age=0h behind=0" ]'
two_done 3600 1800 1000; OUT="$(run)"
chk "⑤ 같은 입력 + 표 1시간 전 → «behind=2» · STALE 0" '[ "$(nl)" = "NEWS last_post=$(mi 7200) table=$(mi 3600) age=1h behind=2" ] && [ "$(dec)" = "$D0" ]'
OUT="$(FT_DESK_TICK_NEWS_STALE_H=1 run)"
chk "⑤ env 상한 1 + 1시간 전 → STALE" 'nl | grep -q " age=1h behind=2 STALE$" && [ "$(dec)" = $((D0 + 1)) ]'
two_done 14400 10800 10000; rm -f "$NL"; OUT="$(run)"
chk "⑤ news-last.json 없음 → «last_post=?» · behind 그대로 셈" '[ "$(nl)" = "NEWS last_post=? table=$(mi 14400) age=4h behind=2 STALE" ]'
printf '{"at": ' > "$NL"; OUT="$(run)"
chk "⑤ 깨진 news-last.json → «last_post=?»" 'nl | grep -q "^NEWS last_post=? table="'
news 7200; fresh; tbl a x; cm 14400 T; refs HEAD HEAD; OUT="$(FT_DESK_TICK_GIT="$T/fakebin/git" run)"
chk "⑤ 가짜 git log rc 9 → «NEWS 판정 불가 — 표 rc=9» 1줄 · 결정 필요 +1" '[ "$(has "^NEWS 판정 불가 — 표 rc=9$")" = 1 ] && [ "$(has "^NEWS last_post")" = 0 ] && [ "$(dec)" = $((D0 + 1)) ]'
# 같은 초 두 순서(판정문 R1) · 둘 다 4시간 전 같은 초
fresh; tbl a x; cm 14400 T; card c; cm 14400 C; refs HEAD HEAD; OUT="$(run)"
chk "⑤ 같은 초 T → C(C 의 부모 = T) → «behind=1 STALE»" 'nl | grep -q " age=4h behind=1 STALE$"'
fresh; card c; cm 14400 C; tbl a x; cm 14400 T; refs HEAD HEAD; OUT="$(run)"
chk "⑤ 같은 초 C → T(T 의 부모 = C) → «behind=0» · STALE 0" 'nl | grep -q " age=4h behind=0$" && [ "$(dec)" = "$D0" ]'
# 갈라진 가지 · 옮긴 파일
fresh; tbl a x; cm 36000 R0; G branch side; tbl b x; cm 14400 T; G checkout -q side
for s in 30000 25000 20000 10000; do card "s$s"; cm "$s" "c$s"; done; refs main side; OUT="$(run)"
chk "⑤ 갈라진 가지: 완성 커밋 T 앞 3 · 뒤 1 → «behind=1»" 'nl | grep -q " table=$(mi 14400) age=4h behind=1 STALE$"'
fresh; echo x > "$T/root/design/harness/indices/대기/m.md"; tbl a x; cm 14400 T; G mv design/harness/indices/대기/m.md design/harness/indices/완성/m.md; cm 10000 mv; refs HEAD HEAD; OUT="$(run)"
chk "⑤ 대기/ → 완성/ git mv 1(T 뒤) → «behind=1»" 'nl | grep -q " age=4h behind=1 STALE$"'

echo "fail=$fail"; [ "$fail" = 0 ]
