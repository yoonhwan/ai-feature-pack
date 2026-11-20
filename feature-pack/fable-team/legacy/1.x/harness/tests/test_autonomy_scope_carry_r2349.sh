#!/usr/bin/env bash
# test_autonomy_scope_carry_r2349.sh — r2349 직전 범위 이어받기(C1~C6): 재개·재발급 때 직전 S 숫자가 기본값 · 낮춤은 오빠 답 --lower 필수
# 격리: 임시 FT_ROOT·STATE · FT_NOW 고정 시계 · 가짜 분류기·가짜 슬랙 게시 — 실 상태·실 슬랙·실 git 분류 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
unset FT_AUTONOMY_LEVEL   # 이 시험은 «--level 생략 = full» 경로를 본다
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; KIT="$HERE/../kit/fable-team/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/planner" FT_AUTONOMY_HOOK_LOG="$T/hook.log"
S="$T/state"; LOG="$S/autonomy.log"; AP="$S/autonomy-merge-approved"
mkdir -p "$T/.fable-team" "$S" "$T/planner"
T0=1800000000; NOW=$T0
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "${STUB_OUT:-CLASS docs}"\n' > "$T/cls.sh"
printf '#!/usr/bin/env bash\n[ "$1" = --text ] && printf "%%s\\n" "$2" >> "%s/post.log"\necho "SLACK-TS 1800000000.000100"\n' "$T" > "$T/post.sh"
chmod +x "$T/cls.sh" "$T/post.sh"
export FT_SCOPE_CLASSIFY="$T/cls.sh" FT_SCOPE_SLACK_POST="$T/post.sh"
a() { FT_NOW="$NOW" "$BASH" "$BIN/ft-autonomy.sh" "$@"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
fresh() { rm -rf "$S"; mkdir -p "$S" "$T/planner"; : > "$T/post.log"; NOW=$T0; }
glast() { grep '^approve-scope ' "$LOG" 2>/dev/null | tail -1; }
lines() { if [ -r "$LOG" ]; then wc -l < "$LOG" | tr -d ' '; else echo 0; fi; }
sha() { printf '%040x' "$1"; }
grant_line() { printf 'approve-scope S2 A1 %s until=%s %s\n' "$T0" "$((T0 + 43200))" "$1"; }
# seed = 오빠가 정한 직전 범위(C1 = S2 A1 at=T0 · 1000/500/200 byz,pack · level 칸 없음 = full)
seed() { NOW=$T0; a on --for 12h >/dev/null 2>&1; grant_line "max=1000 daily=500 classes=docs,ff,revert,code codemax=200 repos=byz,pack" >> "$LOG"; }
L1="$((T0 + 50)).000001"   # 오빠 답 ts 꼴(숫자10.숫자6) · S2 at(T0) 뒤 ∧ 지금(T0+100) 앞

# ① 인자 없는 켜기 = 직전 범위(기본표 30/15/10 아님) — C1 · C2
fresh; seed; a off >/dev/null 2>&1; NOW=$((T0 + 100)); run a on
[ $rc = 0 ] && [ "$(glast)" = "approve-scope S3 A2 $NOW until=$((NOW + 86400)) max=1000 daily=500 classes=docs,ff,revert,code codemax=200 repos=byz,pack level=full" ]
ck "① off → on(인자 없음) = 직전 1000/500/200 byz,pack" $?

# ② 낮춤 = REJECT rc 2 · 쓰기 0 (③ 통과)
fresh; seed; a off >/dev/null 2>&1; n0="$(lines)"; j0="$(cat "$S/autonomy.json")"; NOW=$((T0 + 100))
run a on --max 30 --daily 15; [ $rc = 2 ] && has '보다 낮춤 = 오빠 답 필요' && [ "$(lines)" = "$n0" ] && [ "$(cat "$S/autonomy.json")" = "$j0" ]
ck "② on --max 30 --daily 15 → REJECT rc 2 · log·json 그대로" $?
run a on --max 30 --daily 15 --lower "$L1"; [ $rc = 0 ] && [[ "$(glast)" == *" lower=$L1" ]]
ck "③ ② + --lower → 통과 · grant 줄 끝 lower=$L1" $?
run a scope-status; [ "$(a mode)" = on ] && has '^\[범위 승인 S3 · A2'; ck "③ lower 칸 줄 = 위변조 아님(mode on · status)" $?

# ④ 직전 0줄 = 기본표(지금 동작 유지) — C1 «직전 없음»
fresh; run a on; [ $rc = 0 ] && [ "$(glast)" = "approve-scope S1 A1 $T0 until=$((T0 + 86400)) max=30 daily=15 classes=docs,ff,revert,code codemax=10 repos=byz,pack level=full" ]
ck "④ log 에 approve-scope 0줄 → 기본표 30/15/10" $?

# ⑤ 생략한 --daily·--code-max·--repos = 직전 값 — C3
fresh; seed; NOW=$((T0 + 100)); run a approve-scope --for 12h --max 1000 --classes docs,ff,revert,code
[ $rc = 0 ] && [ "$(glast)" = "approve-scope S3 A1 $NOW until=$((NOW + 43200)) max=1000 daily=500 classes=docs,ff,revert,code codemax=200 repos=byz,pack" ]
ck "⑤ --max 만 준 재발급 → daily=500 codemax=200 repos=byz,pack" $?

# ⑥ h8634 꼴 낮춤 거절 — C4 (⑥b = 클래스까지 준 같은 낮춤: 사유 = 낮춤)
fresh; seed; n0="$(lines)"; NOW=$((T0 + 100))
run a approve-scope --for 12h --max 25 --daily 25; [ $rc = 2 ] && [ "$(lines)" = "$n0" ]; ck "⑥ approve-scope --max 25 --daily 25 → REJECT rc 2 · 쓰기 0" $?
run a approve-scope --for 12h --max 25 --daily 25 --classes docs,ff,revert,code; [ $rc = 2 ] && has '보다 낮춤 = 오빠 답 필요'
ck "⑥b ⑥ + --classes → REJECT 사유 = 낮춤(--lower 필요)" $?

# ⑦ repos 좁힘 — C4
fresh; seed; NOW=$((T0 + 100)); run a approve-scope --for 12h --max 1000 --classes docs,ff,revert,code --repos byz
[ $rc = 2 ] && has '보다 낮춤'; ck "⑦ byz,pack → byz → REJECT rc 2" $?
run a approve-scope --for 12h --max 1000 --classes docs,ff,revert,code --repos byz --lower "$L1"; [ $rc = 0 ] && [[ "$(glast)" != *"repos="* ]]
ck "⑦ + --lower → 통과(좁힘 승인 기록)" $?

# ⑧ 높임 = 통과 · lower 칸 0 — C4
fresh; NOW=$T0; a on --for 12h --max 200 --daily 100 >/dev/null 2>&1; NOW=$((T0 + 100))
run a approve-scope --for 12h --max 1000 --classes docs,ff,revert,code
[ $rc = 0 ] && [[ "$(glast)" == *" max=1000 daily=100 classes=docs,ff,revert,code codemax=10 repos=byz,pack" ]] && [[ "$(glast)" != *lower=* ]]
ck "⑧ 높임(200→1000) → 통과 · lower 칸 0" $?

# ⑨ 위변조 = 직전 없음 — C1 (앞 정상 줄도 안 씀)
fresh; seed; NOW=$((T0 + 100)); printf 'garbage line not a log form\n' >> "$LOG"
run a on-check; has 'base=-$'; ck "⑨ 위변조 뒤 on-check base=-" $?
run a scope-status; has 'base=-'; ck "⑨ 위변조 scope-status base=-" $?
run a on; [ "$(glast)" = "approve-scope S3 A2 $NOW until=$((NOW + 86400)) max=30 daily=15 classes=docs,ff,revert,code codemax=10 repos=byz,pack level=full" ]
ck "⑨ 위변조 log 로는 숫자를 안 읽는다(기본표) · on 은 지금처럼 진행" $?

# ⑩ ─ ⑯ ⑰ --lower 검사 넷 — C4
fresh; seed; NOW=$((T0 + 100)); n0="$(lines)"
run a approve-scope --for 12h --max 100 --classes docs,ff,revert,code --lower abc; [ $rc = 2 ] && has 'Slack ts 꼴'
ck "⑩ --lower abc → REJECT rc 2" $?
run a approve-scope --for 12h --max 100 --classes docs,ff,revert,code --lower "$T0.000001"; [ $rc = 2 ] && has '부여 시각보다 앞'
ck "⑯ --lower 초 = 직전 at → REJECT rc 2" $?
run a approve-scope --for 12h --max 100 --classes docs,ff,revert,code --lower "$((NOW + 1000)).000001"; [ $rc = 2 ] && has '지금보다 뒤'
ck "⑯ --lower 가 지금보다 뒤 → REJECT rc 2" $?
[ "$(lines)" = "$n0" ] && [ ! -d "$AP" ]; ck "⑩⑯ 쓰기 0(log 줄·승인 파일 0)" $?
fresh; seed; printf 'approve-scope S3 A1 %s until=%s max=1000 daily=500 classes=docs,ff,revert,code codemax=200 repos=byz,pack lower=%s\n' "$((T0 + 500))" "$((T0 + 43200))" "$((T0 + 1500)).000001" >> "$LOG"
NOW=$((T0 + 2000)); run a approve-scope --for 12h --max 100 --classes docs,ff,revert,code --lower "$((T0 + 1500)).000001"
[ $rc = 2 ] && has '이미 쓴 오빠 답'; ck "⑰ 이미 쓴 --lower ts 재사용 → REJECT rc 2" $?

# ⑪ base 칸 — C6
fresh; run a on-check; has 'base=-$'; ck "⑪ log 0줄 → on-check base=-" $?
fresh; seed; run a on-check; has 'base=S2 1000/500/200 byz,pack$'; ck "⑪ on-check 끝 칸 base=S2 1000/500/200 byz,pack" $?
run a scope-status; has 'base=S2 1000/500/200 byz,pack\]$'; ck "⑪ scope-status 끝 칸 base=…" $?

# ⑫ lower 칸 있는 줄도 SCOPE 판정 그대로 — C5 정규식 회귀
fresh; seed; NOW=$((T0 + 100)); run a approve-scope --for 12h --max 100 --classes docs,ff,revert,code --lower "$L1"
[ $rc = 0 ] && [ "$(a mode)" = on ]; ck "⑫ lower 칸 grant 줄 = 위변조 0(mode on)" $?
run a scope-approve "$(sha 12)"; [ $rc = 0 ] && has '^SCOPE-OK'; ck "⑫ 그 뒤 scope-approve = 지금처럼 통과" $?

# ⑬ mid·each 는 직전 범위를 안 읽는다 — C2 예외
fresh; seed; a off >/dev/null 2>&1; NOW=$((T0 + 100)); run a on --level mid --for 6h
[ $rc = 0 ] && [ "$(glast)" = "approve-scope S3 A2 $NOW until=$((NOW + 21600)) max=30 daily=15 classes=docs,ff,revert level=mid" ]
ck "⑬ --level mid → 기본표(직전 1000/500/200 안 씀)" $?
a off >/dev/null 2>&1; n1="$(grep -c '^approve-scope ' "$LOG")"; run a on --level each --for 2h
[ $rc = 0 ] && [ "$(grep -c '^approve-scope ' "$LOG")" = "$n1" ]; ck "⑬ --level each → 범위 승인 줄 0" $?

# ⑭ mid 줄은 건너뛴다 — C1 (DA H1)
fresh; seed; a off >/dev/null 2>&1; NOW=$((T0 + 100)); a on --level mid >/dev/null 2>&1; a off >/dev/null 2>&1
NOW=$((T0 + 200)); run a on
[ "$(glast)" = "approve-scope S4 A3 $NOW until=$((NOW + 86400)) max=1000 daily=500 classes=docs,ff,revert,code codemax=200 repos=byz,pack level=full" ]
ck "⑭ mid 줄(30/15) 건너뛰고 full S2 숫자 이어받기" $?

# ⑮ classes 종류 빼기 = 낮춤 · 새 줄 codemax 칸 0 — C4 · C3 (DA H2 · DA#44 B1)
fresh; seed; NOW=$((T0 + 100)); run a approve-scope --for 12h --max 1000 --daily 500 --classes docs,ff,revert
[ $rc = 2 ] && has '보다 낮춤'; ck "⑮ code 빼기(같은 숫자) → REJECT rc 2" $?
run a approve-scope --for 12h --max 1000 --daily 500 --classes docs,ff,revert --lower "$L1"
[ $rc = 0 ] && [[ "$(glast)" == *" classes=docs,ff,revert repos=byz,pack lower=$L1" ]]
ck "⑮ + 새 ts --lower → 통과 · codemax 칸 없음" $?
fresh; NOW=$T0; a on --for 12h >/dev/null 2>&1; grant_line "max=1000 daily=500 classes=docs,ff,code codemax=50" >> "$LOG"
NOW=$((T0 + 100)); run a approve-scope --for 12h --max 1000 --daily 500 --classes docs,ff,revert; [ $rc = 2 ] && has '보다 낮춤'
ck "⑮b 엇갈린 집합(docs,ff,code → docs,ff,revert) → REJECT rc 2" $?

# ⑱ 낮춘 max 에 이어받은 칸 깎기 — DA 메모 1 (+ C6 슬랙 1구)
fresh; seed; NOW=$((T0 + 100)); run a approve-scope --for 12h --max 100 --classes docs,ff,revert,code --lower "$L1"
[ $rc = 0 ] && [ "$(glast)" = "approve-scope S3 A1 $NOW until=$((NOW + 43200)) max=100 daily=100 classes=docs,ff,revert,code codemax=100 repos=byz,pack lower=$L1" ]
ck "⑱ max 100 · 생략한 daily·codemax = 100 으로 깎임" $?
grep -qF "직전보다 줄임(오빠 답 $L1)" "$T/post.log"; ck "C6 낮춤 슬랙 3줄에 «직전보다 줄임(오빠 답 ts)» 1구" $?
fresh; run a on --for 12h >/dev/null 2>&1; ! grep -qF '직전보다 줄임' "$T/post.log"; ck "C6 안 낮춘 켜기 = 그 1구 없음" $?

# ⑲ 직전 classes 에 code 가 없으면 켜기도 code·codemax 를 안 넣는다 — C2 (master-pi#357 #356126)
fresh; NOW=$T0; a on --for 12h >/dev/null 2>&1; grant_line "max=1000 daily=500 classes=docs,ff,revert" >> "$LOG"
a off >/dev/null 2>&1; NOW=$((T0 + 100)); run a on
[ $rc = 0 ] && [ "$(glast)" = "approve-scope S3 A2 $NOW until=$((NOW + 86400)) max=1000 daily=500 classes=docs,ff,revert repos=byz,pack level=full" ]
ck "⑲ 직전 classes=docs,ff,revert → 켜기도 code·codemax 칸 0" $?

# bin = kit 같은 글자 · 200줄 이하
for f in ft-autonomy.sh ft-autonomy-level.sh ft-autonomy-scope.sh; do cmp -s "$BIN/$f" "$KIT/$f"; ck "bin = kit 같은 글자 $f" $?; done
for f in ft-autonomy.sh ft-autonomy-level.sh; do [ "$(wc -l < "$BIN/$f")" -le 200 ]; ck "200줄 이하 $f" $?; done

echo "fail=$fail"; [ "$fail" = 0 ]
