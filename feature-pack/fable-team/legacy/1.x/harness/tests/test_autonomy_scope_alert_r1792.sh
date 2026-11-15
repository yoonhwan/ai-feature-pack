#!/usr/bin/env bash
# test_autonomy_scope_alert_r1792.sh — 범위 승인 소진 경보 (r1792 · 반례 ①~⑥ · ⑦ = 기존 시험 따로)
# 격리: 임시 루트(FT_ROOT·state) · FT_NOW 고정 시계 · TZ=UTC · 손으로 쓴 approve-scope·scope-use 줄 · 가짜 슬랙 게시·가짜 mbox(FT_AUTONOMY_MBOX)·FT_AUTONOMY_DESK
#   실 autonomy.log·실 명부·실 mbox·Slack 호출 0 · ⑤ stall-scan = 임시 bin(실 bin 링크 + ft_stall_*.py 대역 · 다른 틱 일 4개는 안 넣음)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
export TZ=UTC FT_AUTONOMY_LEVEL=each FT_AUTONOMY_DESK=fake-desk
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"; BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
printf '#!/usr/bin/env bash\nprintf "%%s\\t%%s\\t%%s\\n" "$2" "$3" "$4" >> "%s/mbox.log"; exit "${FAKE_MBOX_RC:-0}"\n' "$T" > "$T/mbox.sh"
printf '#!/usr/bin/env bash\necho "SLACK-TS 1800000000.000100"\n' > "$T/post.sh"
export FT_AUTONOMY_MBOX="$T/mbox.sh" FT_SCOPE_SLACK_POST="$T/post.sh" FT_PLANNER_DIR="$T/planner"; mkdir -p "$T/planner"
T0=1800046800   # 21:00 UTC — 범위 시작 · 다음 날짜(00:00)가 3시간 뒤
R="$T/r"; NOW=$T0
a() { FT_NOW="$NOW" FT_ROOT="$R" FT_AUTONOMY_STATE_DIR="$R/.fable-team/state" "$BASH" "$BIN/ft-autonomy.sh" "$@"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
sha() { printf '%040x' "$1"; }
hm() { date -u -r "$1" '+%m-%d %H:%M' 2>/dev/null || date -u -d "@$1" '+%m-%d %H:%M'; }
fresh() {  # <root> <max> <daily> [code-max] — ON · 24h 범위 S1
  R="$1"; NOW=$T0; rm -rf "$R"; mkdir -p "$R/.fable-team/state"; a on >/dev/null 2>&1
  if [ -n "${4:-}" ]; then a approve-scope --for 24h --max "$2" --daily "$3" --classes docs,ff,revert,code --code-max "$4" >/dev/null 2>&1
  else a approve-scope --for 24h --max "$2" --daily "$3" --classes docs,ff,revert >/dev/null 2>&1; fi
}
use() { local i; for i in $(seq "$2" "$3"); do printf 'scope-use S1 %s %s %s\n' "$(sha "$i")" "$1" "$((T0 + 120 + (i - 1) * 300))" >> "$R/.fable-team/state/autonomy.log"; done; }   # <종류> <첫 번째> <마지막> · i 번째 = 시작 + 2분 + (i-1)×5분
sent() { wc -l < "$T/mbox.log" 2>/dev/null | tr -d ' '; }
: > "$T/mbox.log"

for f in ft-autonomy.sh ft-autonomy-scope.sh ft-autonomy-scope-alert.sh ft-stall-scan.sh; do bash -n "$BIN/$f" && cmp -s "$BIN/$f" "$KIT/$f"; ck "bash -n · kit 사본 같은 바이트: $f" $?; done
[ "$(wc -l < "$BIN/ft-autonomy-scope-alert.sh" | tr -d ' ')" -le 60 ] && [ "$(wc -l < "$BIN/ft-autonomy.sh" | tr -d ' ')" -le 200 ]; ck "크기: 새 파일 ≤60 · ft-autonomy.sh ≤200" $?

# ① S45 재연 — 하루 20/20 · 첫 빈자리(1번째 + 24h) > 범위 끝 → 꼬리 · 머리 그대로 · 한 줄 (revert·equiv 줄은 빈자리 셈 밖)
fresh "$T/s45" 30 20; printf 'scope-use S1 %s revert %s\nscope-use S1 %s equiv %s\n' "$(sha 90)" "$((T0 + 60))" "$(sha 91)" "$((T0 + 90))" >> "$R/.fable-team/state/autonomy.log"
use docs 1 20; NOW=$((T0 + 120 + 19 * 300 + 60))
run a scope-status
[ $rc = 0 ] && [ "$(wc -l <<<"$out" | tr -d ' ')" = 1 ] && has '^\[범위 승인 S1 · A1 · ' && [ "$out" = "[범위 승인 S1 · A1 · ~$(hm $((T0 + 86400)))까지 · 20/30 · 오늘 20/20 · docs,ff,revert · 새 승인 없이 0건(끝 $(hm $((T0 + 86400))) < 빈자리 $(hm $((T0 + 120 + 86400))))]" ]; ck "① S45 재연 → 꼬리 «새 승인 없이 0건(끝 < 빈자리)» · 한 줄 · 머리 그대로" $?
S1OUT="$out"

# ② 1번째를 시작 − 1시간으로(빈자리 < 끝) → 꼬리 0 · used=max → (전체 한도)
fresh "$T/early" 30 20; printf 'scope-use S1 %s docs %s\n' "$(sha 1)" "$((T0 - 3600))" >> "$R/.fable-team/state/autonomy.log"; use docs 2 20; NOW=$((T0 + 120 + 19 * 300 + 60))
run a scope-status; [ $rc = 0 ] && [ "$out" = "[범위 승인 S1 · A1 · ~$(hm $((T0 + 86400)))까지 · 20/30 · 오늘 20/20 · docs,ff,revert]" ]; ck "② 빈자리 < 끝 → 꼬리 0" $?
fresh "$T/full" 20 20; use docs 1 20; NOW=$((T0 + 120 + 19 * 300 + 60))
run a scope-status; [ $rc = 0 ] && [ "$out" = "[범위 승인 S1 · A1 · ~$(hm $((T0 + 86400)))까지 · 20/20 · 오늘 20/20 · docs,ff,revert · 새 승인 없이 0건(전체 한도)]" ]; ck "② used=max → «(전체 한도)» 꼬리" $?
fresh "$T/none" 30 20; use docs 1 5; NOW=$((T0 + 3600)); run a scope-status; [ "$out" = "[범위 승인 S1 · A1 · ~$(hm $((T0 + 86400)))까지 · 5/30 · 오늘 5/20 · docs,ff,revert]" ]; ck "② 여유 있음 → 줄 바이트 그대로" $?

# ③ scope-alert — 15/20 → 1통 · 같은 시각 다시 → 0통 · 다음 날짜 → 1통 · 14/20 → 0통
fresh "$T/a3" 30 20; use docs 1 15; NOW=$((T0 + 120 + 14 * 300 + 60)); : > "$T/mbox.log"
run a scope-alert; [ $rc = 0 ] && has '^SCOPE-ALERT-SENT S1 75%\(오늘 15/20\)' && [ "$(sent)" = 1 ] && grep -qF "fake-desk	ft-autonomy	[긴급] 범위 승인 S1 사용률 75%(오늘 15/20) · 끝 $(hm $((T0 + 86400))) → 새 승인 h 준비" "$T/mbox.log"; ck "③ 오늘 15/20 → desk [긴급] 1통" $?
grep -qxF "S1 daily $(date -u -r "$NOW" +%Y%m%d 2>/dev/null || date -u -d "@$NOW" +%Y%m%d)" "$R/.fable-team/state/autonomy-scope/alert.sent" && [ -f "$R/.fable-team/state/autonomy-scope/alert.sent" ] && [ ! -L "$R/.fable-team/state/autonomy-scope/alert.sent" ]; ck "③ 장부 alert.sent 키 «S1 daily YYYYMMDD» · 일반 파일" $?
run a scope-alert; [ $rc = 0 ] && [ "$out" = SCOPE-ALERT-NONE ] && [ "$(sent)" = 1 ]; ck "③ 같은 시각 다시 → 0통" $?
NOW=$((T0 + 3 * 3600 + 600)); run a scope-alert; [ $rc = 0 ] && has '^SCOPE-ALERT-SENT S1 75%' && [ "$(sent)" = 2 ]; ck "③ 다음 날짜(오늘 창 15 그대로) → 1통" $?
fresh "$T/a14" 30 20; use docs 1 14; NOW=$((T0 + 120 + 13 * 300 + 60)); : > "$T/mbox.log"
run a scope-alert; [ $rc = 0 ] && [ "$out" = SCOPE-ALERT-NONE ] && [ "$(sent)" = 0 ]; ck "③ 14/20(70%) → 0통" $?
fresh "$T/code" 30 20 4; use code 1 3; NOW=$((T0 + 3600)); : > "$T/mbox.log"
run a scope-alert; [ $rc = 0 ] && has '^SCOPE-ALERT-SENT S1 75%\(code 3/4\)' && [ "$(sent)" = 1 ]; ck "③ code 3/4 → 1통" $?
rm -rf "$T/nos"; R="$T/nos"; mkdir -p "$R/.fable-team/state"; a on >/dev/null 2>&1; run a scope-alert; [ $rc = 0 ] && [ "$out" = SCOPE-ALERT-NONE ] && [ "$(sent)" = 1 ]; ck "③ 범위 없음 → NONE rc0 · 0통" $?
R="$T/a3"; NOW=$((T0 + 86400 + 60)); run a scope-alert; [ $rc = 0 ] && [ "$out" = SCOPE-ALERT-NONE ] && [ "$(sent)" = 1 ]; ck "③ 범위 끝(정지) → NONE · 0통" $?

# ④ 75% 이미 보낸 뒤 ① 상태 → «S1 zero» 1통 더 · 그 뒤 0통 · mbox 실패 → 장부 그대로 rc1 · 다음 호출 재발신
fresh "$T/a4" 30 20; use docs 1 15; NOW=$((T0 + 120 + 14 * 300 + 60)); : > "$T/mbox.log"; a scope-alert >/dev/null 2>&1
use docs 16 20; NOW=$((T0 + 120 + 19 * 300 + 60))
run a scope-alert; [ $rc = 0 ] && has '^SCOPE-ALERT-SENT S1 100%\(오늘 20/20\) · 새 승인 없이 0건\(끝 ' && [ "$(sent)" = 2 ] && tail -1 "$T/mbox.log" | grep -qF "· 끝 $(hm $((T0 + 86400))) · 새 승인 없이 0건(끝 $(hm $((T0 + 86400))) < 빈자리 $(hm $((T0 + 120 + 86400)))) → 새 승인 h 준비" && grep -qx 'S1 zero' "$R/.fable-team/state/autonomy-scope/alert.sent"; ck "④ 75% 보낸 뒤 0건 꼬리 → zero 1통 더" $?
run a scope-alert; [ $rc = 0 ] && [ "$out" = SCOPE-ALERT-NONE ] && [ "$(sent)" = 2 ]; ck "④ 그 뒤 0통" $?
fresh "$T/a4f" 30 20; use docs 1 15; NOW=$((T0 + 120 + 14 * 300 + 60)); : > "$T/mbox.log"
run env FAKE_MBOX_RC=1 FT_NOW="$NOW" FT_ROOT="$R" FT_AUTONOMY_STATE_DIR="$R/.fable-team/state" "$BASH" "$BIN/ft-autonomy.sh" scope-alert
[ $rc = 1 ] && [ "$(wc -l <<<"$out" | tr -d ' ')" = 1 ] && has '판정 불가' && [ ! -s "$R/.fable-team/state/autonomy-scope/alert.sent" ]; ck "④ mbox rc1 → rc1 «판정 불가» 1줄 · 장부 쓰기 0" $?
run a scope-alert; [ $rc = 0 ] && has '^SCOPE-ALERT-SENT' && [ "$(sent)" = 2 ]; ck "④ 다음 호출 재발신" $?
fresh "$T/a4d" 30 20; use docs 1 15; NOW=$((T0 + 120 + 14 * 300 + 60))
run env -u FT_AUTONOMY_DESK FT_NOW="$NOW" FT_ROOT="$R" FT_AUTONOMY_STATE_DIR="$R/.fable-team/state" "$BASH" "$BIN/ft-autonomy.sh" scope-alert; [ $rc = 1 ] && has '판정 불가 .*desk 못 찾음'; ck "④ desk 못 찾음(명부 없음) → rc1 판정 불가" $?
mkdir -p "$R/.fable-team"; echo '{"_desk": "roster-desk"}' > "$R/.fable-team/seats-planner.json"
run env -u FT_AUTONOMY_DESK FT_NOW="$NOW" FT_ROOT="$R" FT_AUTONOMY_STATE_DIR="$R/.fable-team/state" "$BASH" "$BIN/ft-autonomy.sh" scope-alert; [ $rc = 0 ] && has '→ roster-desk$'; ck "④ desk = ROOT 명부 _desk" $?

# ⑤ stall-scan 줄 — FT_ROOT=A(범위 없음) · A/.fable-team/LIVE_ROOT=B(75%) → B 를 보고 1통 / LIVE_ROOT 없음 → A 그대로 0통
SB="$T/sbin"; mkdir -p "$SB"
for f in "$BIN"/*; do case "${f##*/}" in ft-stall-scan.sh|ft_stall_scan.py|ft_stall_detect.py|ft_penalty.py|ft-child-watch.sh|ft-issues-daily-check.sh|ft_desk_reply_wake.py|ft_goal_stall_alert.py) ;; *) ln -s "$f" "$SB/" ;; esac; done
cp "$BIN/ft-stall-scan.sh" "$SB/"; for f in ft_stall_scan.py ft_stall_detect.py ft_penalty.py; do echo 'print("stall=0")' > "$SB/$f"; done
fresh "$T/B" 30 20; use docs 1 15; NOW=$((T0 + 120 + 14 * 300 + 60))
rm -rf "$T/A"; R="$T/A"; mkdir -p "$R/.fable-team/state"; a on >/dev/null 2>&1; printf '%s\n' "$T/B" > "$T/A/.fable-team/LIVE_ROOT"; : > "$T/mbox.log"
run env -u FT_AUTONOMY_STATE_DIR FT_NOW="$NOW" FT_ROOT="$T/A" "$BASH" "$SB/ft-stall-scan.sh"
[ "$out" = stall=0 ] && [ "$(sent)" = 1 ] && grep -q 'S1 사용률 75%' "$T/mbox.log" && [ -f "$T/B/.fable-team/state/autonomy-scope/alert.sent" ] && [ ! -e "$T/A/.fable-team/state/autonomy-scope/alert.sent" ]; ck "⑤ LIVE_ROOT=B → B 를 보고 1통 · stall 판정 그대로" $?
rm -f "$T/A/.fable-team/LIVE_ROOT"; rm -rf "$T/B/.fable-team/state/autonomy-scope/alert.sent"; : > "$T/mbox.log"
run env -u FT_AUTONOMY_STATE_DIR FT_NOW="$NOW" FT_ROOT="$T/A" "$BASH" "$SB/ft-stall-scan.sh"; [ "$out" = stall=0 ] && [ "$(sent)" = 0 ]; ck "⑤ LIVE_ROOT 없음 → A 그대로 · 0통" $?
run env -u FT_AUTONOMY_STATE_DIR FT_NOW="$NOW" FT_ROOT="$T/B" "$BASH" "$SB/ft-stall-scan.sh" --dry-run; [ "$(sent)" = 0 ]; ck "⑤ --dry-run → 경보 0" $?

# ⑥ ① 출력 → ft_scope_plan_judge scope_state = S1 · oppa_gate REJECT · child-watch autonomy() 정규식 = on
R="$T/s45"; NOW=$((T0 + 120 + 19 * 300 + 60))
run env FT_SCOPE_STATUS_CMD="env FT_NOW=$NOW FT_ROOT=$R FT_AUTONOMY_STATE_DIR=$R/.fable-team/state $BASH $BIN/ft-autonomy.sh scope-status" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import ft_scope_plan_judge as j; print(j.scope_state())' "$BIN"
[ $rc = 0 ] && [ "$out" = S1 ]; ck "⑥ ft_scope_plan_judge scope_state = S1" $?
run a approve-merge "$(sha 77)"; [ $rc = 2 ] && has 'REJECT 범위 승인 S1 중 approve-merge'; ck "⑥ oppa_gate = REJECT(범위 살아 있음)" $?
python3 -c 'import re,sys; sys.exit(0 if re.match(r"\[범위 승인 \S+ · ", sys.argv[1].strip()) else 1)' "$S1OUT"; ck "⑥ child-watch autonomy() 정규식 = on" $?

echo "fail=$fail"; [ "$fail" = 0 ]
