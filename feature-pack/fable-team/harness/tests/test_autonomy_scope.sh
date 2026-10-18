#!/usr/bin/env bash
# test_autonomy_scope.sh — 범위 사전 승인 4명령(approve-scope·scope-approve·scope-stop·scope-status) + 위변조 판정 + 상태 폴더 훅 시험 (R298 1/3 · 판정 2055)
# 격리: 임시 루트(FT_ROOT·FT_AUTONOMY_STATE_DIR) + FT_NOW 고정 시계 + 가짜 분류기(FT_SCOPE_CLASSIFY) — 실 state·실 git 분류 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; BIN="$ROOT/harness/bin"; SG="$ROOT/harness/kit/fable-team/templates/hooks/autonomy-state-guard.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/planner" FT_AUTONOMY_HOOK_LOG="$T/hook.log"
S="$T/state"; LOG="$S/autonomy.log"; AP="$S/autonomy-merge-approved"; mkdir -p "$T/.fable-team" "$S" "$T/planner"
T0=1800000000; NOW=$T0
cat > "$T/stub-classify.sh" <<'EOF'
#!/usr/bin/env bash
# 가짜 분류기 — classify: STUB_RC·STUB_OUT(`CLASS <종류>` / `FORBID …`) · check-revert: STUB_REVERT_RC·STUB_REVERT_OUT(rc 4 = `REVERTED L by <sha>`)
printf '%s\n' "$*" >> "${STUB_ARGS_LOG:-/dev/null}"
if [ "$1" = check-revert ]; then printf '%s\n' "${STUB_REVERT_OUT:-OK}"; exit "${STUB_REVERT_RC:-0}"; fi
printf '%s\n' "${STUB_OUT:-CLASS docs}"; exit "${STUB_RC:-0}"
EOF
export FT_SCOPE_CLASSIFY="$T/stub-classify.sh"
cat > "$T/stub-post.sh" <<'EOF'
#!/usr/bin/env bash
# 가짜 슬랙 게시 — 실제 게시 0. 본문은 STUB_POST_LOG 에 모은다 · STUB_POST_RC≠0 이면 게시 실패(ERR) · 성공 = `SLACK-TS <ts>`
[ "$1" = --text ] && printf '%s\n' "$2" >> "${STUB_POST_LOG:-/dev/null}"
[ "${STUB_POST_RC:-0}" = 0 ] || { echo "ERR chat.postMessage 호출 실패: URLError" >&2; exit "$STUB_POST_RC"; }
echo "SLACK-TS 1800000000.000100"
EOF
export FT_SCOPE_SLACK_POST="$T/stub-post.sh" STUB_POST_LOG="$T/post.log"

a() { FT_NOW="$NOW" "$BASH" "$BIN/ft-autonomy.sh" "$@"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
fresh() { rm -rf "$S"; mkdir -p "$S"; NOW=$T0; a on >/dev/null 2>&1; }   # A1 ON · 시계 T0
sha() { printf '%040x' "$1"; }
lines() { wc -l < "$LOG" | tr -d ' '; }
grant() { run a approve-scope "$@"; }

for f in ft-autonomy.sh ft-autonomy-scope.sh ft-autonomy-scope-code.sh; do bash -n "$BIN/$f" 2>/dev/null; ck "bash -n $f" $?; done
python3 -m py_compile "$BIN/autonomy_scope_post.py" 2>/dev/null; ck "py_compile autonomy_scope_post.py" $?
MIRB="$ROOT/harness/kit/fable-team/bin"
cmp -s "$BIN/ft-autonomy.sh" "$MIRB/ft-autonomy.sh" && cmp -s "$BIN/ft-autonomy-scope.sh" "$MIRB/ft-autonomy-scope.sh" && cmp -s "$BIN/ft-autonomy-scope-code.sh" "$MIRB/ft-autonomy-scope-code.sh" && cmp -s "$BIN/autonomy_scope_post.py" "$MIRB/autonomy_scope_post.py"; ck "설치 미러 cmp0 (bin 네 파일)" $?

# ===== approve-scope =====
rm -rf "$S"; mkdir -p "$S"
grant --for 10h --max 5 --classes docs; [ $rc = 2 ] && has 'ON 이 아님'; ck "approve-scope OFF → REJECT rc 2" $?
fresh
grant --for 10h --max 5 --classes docs,code; [ $rc = 2 ] && has '--code-max 1~max\(5\) 필수\(받은 값: 없음\)'; ck "classes 에 code · --code-max 없음 → REJECT (R411)" $?
grant --for 10h --max 5 --classes code --code-max 0; [ $rc = 2 ] && has '--code-max 1~max'; ck "--code-max 0 → REJECT" $?
grant --for 10h --max 5 --classes code --code-max 6; [ $rc = 2 ] && has '--code-max 1~max'; ck "--code-max > max → REJECT" $?
grant --for 10h --max 5 --classes docs --code-max 2; [ $rc = 2 ] && has 'code 가 있을 때만'; ck "code 없는데 --code-max → REJECT" $?
grant --for 73h --max 5 --classes docs; [ $rc = 2 ]; ck "--for 73h → REJECT" $?
grant --for 0h --max 5 --classes docs; [ $rc = 2 ]; ck "--for 0h → REJECT" $?
grant --for 10 --max 5 --classes docs; [ $rc = 2 ]; ck "--for 단위 없음 → REJECT" $?
grant --for 10h --max 31 --classes docs; [ $rc = 2 ]; ck "--max 31 → REJECT" $?
grant --for 10h --max 0 --classes docs; [ $rc = 2 ]; ck "--max 0 → REJECT" $?
grant --for 10h --max 5 --daily 6 --classes docs; [ $rc = 2 ]; ck "--daily > max → REJECT" $?
grant --for 10h --max 5 --classes docs,foo; [ $rc = 2 ]; ck "모르는 종류 → REJECT" $?
grant --for 10h --max 5 --classes docs,docs; [ $rc = 2 ]; ck "종류 중복 → REJECT" $?
grant --for 10h --max 5 --classes docs,,ff; [ $rc = 2 ]; ck "빈 종류 → REJECT" $?
grant --for 10h --classes docs; [ $rc = 2 ]; ck "--max 없음 → REJECT" $?
[ "$(lines)" = 1 ]; ck "REJECT 전부 log 쓰기 0 (모드 줄 1줄만)" $?
grant --for 10h --max 5 --daily 2 --classes docs,ff,revert
[ $rc = 0 ] && has '^SCOPE-GRANTED S1 A1 until=[0-9]{2}:[0-9]{2} max=5 daily=2 classes=docs,ff,revert$'; ck "정상 grant → SCOPE-GRANTED S1" $?
grep -qxF "approve-scope S1 A1 $T0 until=$((T0+36000)) max=5 daily=2 classes=docs,ff,revert" "$LOG"; ck "log 에 approve-scope 줄 꼴" $?
[ "$(a mode)" = on ]; ck "정상 범위 줄은 위변조 아님 (mode=on)" $?
grant --for 5h --max 3 --classes docs; [ $rc = 0 ] && has '^SCOPE-GRANTED S2 .* max=3 daily=3 classes=docs$'; ck "두 번째 grant = S2 · daily 기본 min(10,max)" $?
run a scope-status; has '^\[범위 승인 S2 · A1 · ~[0-9]{2}:[0-9]{2}까지 · 0/3 · 오늘 0/3 · docs\]$'; ck "앞 grant 자동 대체 — status 는 S2" $?

# ===== scope-approve =====
fresh; grant --for 10h --max 5 --daily 3 --classes docs,ff,revert >/dev/null
run a scope-approve "$(sha 1)" --pr 7
[ $rc = 0 ] && has "^SCOPE-OK $(sha 1) class=docs used=1/5 today=1/3$"; ck "범위 안 → SCOPE-OK" $?
[ "$(cat "$AP/$(sha 1)")" = "approve-merge $(sha 1) A1 $T0" ] && grep -qxF "$(cat "$AP/$(sha 1)")" "$LOG"; ck "승인 파일 1줄 == log 한 줄(기존 형식 · 병합 가드 결속)" $?
grep -qxF "scope-use S1 $(sha 1) docs $T0" "$LOG"; ck "log 에 scope-use 줄" $?
printf '%s\t%s\t7\tdocs\t\t\t\n' "$T0" "$(sha 1)" | cmp -s - "$S/autonomy-scope/S1.ledger.tsv"; ck "원장 1행(시각·sha·PR·종류·빈칸 3)" $?
[ "$(awk -F'\t' 'END{print NF}' "$S/autonomy-scope/S1.ledger.tsv")" = 7 ] && [ "$(awk -F'\t' '{print $6}' "$S/autonomy-scope/S1.ledger.tsv")" = "" ]; ck "원장 7칸(시각·sha·PR·종류·판정문·착지 sha·되돌림) · 6번째 = 착지 sha 빈칸 (r298b LEDGER_LANDED_COL)" $?
[ "$(a mode)" = on ]; ck "scope-use·approve-merge 줄 뒤에도 mode=on" $?
n0="$(lines)"; run a scope-approve "$(sha 1)"; [ $rc = 0 ] && has '^SCOPE-NOOP .* used=1/5'; ck "같은 sha 두 번 → SCOPE-NOOP" $?
[ "$(lines)" = "$n0" ]; ck "NOOP 은 쓰기 0 (건수 불변)" $?
run a scope-approve "$(sha 2)"; run a scope-approve "$(sha 3)"; [ $rc = 0 ]; ck "daily 3 안의 3건째 OK" $?
run a scope-approve "$(sha 4)"; [ $rc = 2 ] && has '하루 건수 도달'; ck "daily 도달 → REJECT" $?
[ ! -e "$AP/$(sha 4)" ] && ! grep -q "$(sha 4)" "$LOG"; ck "daily REJECT 쓰기 0" $?
run a scope-status; ! has '정지' && has '^\[범위 승인 S1 · A1 .* 3/5 · 오늘 3/3 · docs,ff,revert\]$'; ck "daily 도달은 정지 아님(내일 풀림)" $?

# max · 자동 정지 · revert 건수 0
fresh; grant --for 10h --max 2 --daily 2 --classes docs,ff,revert >/dev/null
STUB_OUT="CLASS revert"; export STUB_OUT
run a scope-approve "$(sha 11)"; run a scope-approve "$(sha 12)"; [ $rc = 0 ] && has 'used=0/2'; ck "revert 는 건수 0 (used=0/2)" $?
STUB_OUT="CLASS docs"
run a scope-approve "$(sha 13)"; run a scope-approve "$(sha 14)"; [ $rc = 0 ] && has 'used=2/2'; ck "docs 2건 = max" $?
run a scope-approve "$(sha 15)"; [ $rc = 2 ] && has '건수 도달'; ck "max 도달 → REJECT" $?
[ -f "$S/autonomy-scope/S1.stopped" ] && grep -q '^scope-stop S1 ' "$LOG"; ck "max 도달 → 자동 정지(log + .stopped)" $?
STUB_OUT="CLASS revert"; run a scope-approve "$(sha 16)"; [ $rc = 2 ] && has '정지'; ck "정지 뒤 revert 도 REJECT" $?
run a scope-status; has '^\[범위 승인 S1 정지: 건수 도달\(2/2\)\]$'; ck "status 정지 꼴" $?
STUB_OUT="CLASS docs"

# until 지남 · 사건 번호 바뀜
fresh; grant --for 1h --max 5 --classes docs >/dev/null
NOW=$((T0+3600)); run a scope-approve "$(sha 21)"; [ $rc = 2 ] && has '기간 끝 도달'; ck "until 지남 → REJECT" $?
[ -f "$S/autonomy-scope/S1.stopped" ]; ck "until 지남 → 자동 정지" $?
fresh; grant --for 10h --max 5 --classes docs >/dev/null
a off >/dev/null; a on >/dev/null 2>&1; run a scope-approve "$(sha 22)"; [ $rc = 2 ] && has '사건 번호 바뀜\(A1→A2\)'; ck "OFF→ON 다시 켬(A2) → 옛 S1 REJECT" $?
[ -f "$S/autonomy-scope/S1.stopped" ]; ck "사건 번호 바뀜 → 자동 정지" $?
fresh; grant --for 10h --max 5 --classes docs >/dev/null; a off >/dev/null
run a scope-approve "$(sha 23)"; [ $rc = 2 ] && has '자율 모드 OFF'; ck "자율 OFF → REJECT" $?
[ ! -e "$AP/$(sha 23)" ]; ck "OFF REJECT 쓰기 0" $?

# 분류기
fresh; grant --for 10h --max 5 --classes docs,ff >/dev/null; n0="$(lines)"
STUB_OUT="FORBID code-touch" STUB_RC=2 run a scope-approve "$(sha 31)"; [ $rc = 2 ] && has '분류기 거절 rc=2: FORBID code-touch'; ck "분류기 FORBID → REJECT(사유 그대로)" $?
FT_SCOPE_CLASSIFY=/nonexistent run a scope-approve "$(sha 32)"; [ $rc = 2 ] && has '분류기 없음'; ck "분류기 없음 → REJECT" $?
STUB_OUT="garbage" run a scope-approve "$(sha 33)"; [ $rc = 2 ] && has '꼴 틀림'; ck "분류기 출력 꼴 틀림 → REJECT" $?
STUB_OUT="CLASS code" run a scope-approve "$(sha 34)"; [ $rc = 2 ] && has '범위\(docs,ff\) 밖'; ck "종류 code → 범위 밖 REJECT" $?
STUB_OUT="CLASS revert" run a scope-approve "$(sha 35)"; [ $rc = 2 ] && has '범위\(docs,ff\) 밖'; ck "grant 에 없는 종류(revert) → REJECT" $?
[ "$(lines)" = "$n0" ] && [ ! -d "$AP" ]; ck "분류기 REJECT 5종 전부 쓰기 0" $?
run a scope-approve "xyz"; [ $rc = 2 ]; ck "sha 형식 틀림 → REJECT" $?
rm -rf "$S"; mkdir -p "$S"; a on >/dev/null 2>&1; run a scope-approve "$(sha 36)"; [ $rc = 2 ] && has '활성 범위 승인 없음'; ck "grant 없음 → REJECT" $?

# check-revert(r298b) — 분류 «전» 첫 단계: rc 4 = 정지 + REJECT · rc 1 = REJECT · rc 0 = 진행
fresh; grant --for 10h --max 5 --classes docs >/dev/null; export STUB_ARGS_LOG="$T/stub-args.log"; : > "$STUB_ARGS_LOG"
run a scope-approve "$(sha 61)"; [ $rc = 0 ]; ck "check-revert rc 0 → 진행(SCOPE-OK)" $?
[ "$(head -1 "$STUB_ARGS_LOG")" = "check-revert --repo $T --remote origin --target main --scope S1" ] && [ "$(sed -n 2p "$STUB_ARGS_LOG")" = "classify $(sha 61) --repo $T --remote origin --target main --scope S1" ]; ck "check-revert 가 classify «전» 에 · 인자(--repo ROOT --remote origin --target main --scope S1)" $?
n0="$(lines)"; ls "$AP" > "$T/ap.before"
STUB_REVERT_RC=4 STUB_REVERT_OUT="REVERTED $(sha 61) by $(sha 99)" run a scope-approve "$(sha 62)"
[ $rc = 2 ] && has "정지: REVERTED $(sha 61) by $(sha 99)"; ck "check-revert rc 4 → REJECT + 사유 그대로" $?
[ -f "$S/autonomy-scope/S1.stopped" ] && grep -q "^scope-stop S1 [0-9]* REVERTED $(sha 61) by $(sha 99)$" "$LOG"; ck "rc 4 → scope_write_stop(log + .stopped)" $?
[ "$(lines)" = "$((n0 + 1))" ] && ! grep -q "$(sha 62)" "$LOG" && [ ! -e "$AP/$(sha 62)" ] && [ "$(ls "$AP")" = "$(cat "$T/ap.before")" ]; ck "rc 4 쓰기 = stop 1줄뿐(scope-use·승인 0)" $?
[ "$(a mode)" = on ]; ck "REVERTED stop 줄도 위변조 아님" $?
run a scope-status; has '^\[범위 승인 S1 정지: REVERTED '; ck "REVERTED 뒤 status 정지" $?
fresh; grant --for 10h --max 5 --classes docs >/dev/null; n0="$(lines)"
STUB_REVERT_RC=1 STUB_REVERT_OUT="git 오류" run a scope-approve "$(sha 63)"; [ $rc = 2 ] && has '되돌림 감지 실패 rc=1: git 오류'; ck "check-revert rc 1 → REJECT(닫힌 쪽)" $?
[ "$(lines)" = "$n0" ] && [ ! -e "$S/autonomy-scope/S1.stopped" ] && [ ! -d "$AP" ]; ck "rc 1 → 쓰기 0 · 정지 아님" $?
unset STUB_ARGS_LOG

# ===== scope-stop =====
fresh; grant --for 10h --max 5 --classes docs >/dev/null
run a scope-stop S1 $'탭\t개행\n포함 사유'; [ $rc = 0 ] && has '^SCOPE-STOPPED S1: 탭 개행 포함 사유$'; ck "scope-stop 사유의 탭·개행은 공백으로" $?
[ "$(a mode)" = on ]; ck "stop 줄도 위변조 아님" $?
run a scope-approve "$(sha 41)"; [ $rc = 2 ] && has '정지: 탭 개행 포함 사유'; ck "scope-stop 뒤 scope-approve REJECT" $?
run a scope-stop S1 again; [ $rc = 0 ] && has '이미 정지'; ck "scope-stop 멱등" $?
run a scope-stop S9 x; [ $rc = 2 ]; ck "없는 S → REJECT" $?
run a scope-stop S1 ""; [ $rc = 2 ]; ck "사유 없음 → REJECT" $?
grant --for 10h --max 5 --classes docs >/dev/null; run a scope-approve "$(sha 42)"; [ $rc = 0 ]; ck "새 approve-scope(S2) 로만 재개" $?

# ===== 위변조 판정 =====
fresh; grant --for 10h --max 5 --classes docs >/dev/null; printf 'scope-use S1 notasha docs 1\n' >> "$LOG"
[ "$(a mode)" = tamper ]; ck "scope-use 꼴 틀림 → tamper" $?
fresh; printf 'approve-scope S1 A1 1 until=2 max=3 daily=1 classes=foo\n' >> "$LOG"
[ "$(a mode)" = tamper ]; ck "classes=foo 줄 → tamper (꼴 밖)" $?
fresh; printf 'approve-scope S1 A1 1 until=2 max=3 daily=1 classes=code codemax=x\n' >> "$LOG"
[ "$(a mode)" = tamper ]; ck "codemax=x 줄 → tamper (꼴 밖)" $?
fresh; printf 'scope-use S1 %s foo 1\n' "$(sha 1)" >> "$LOG"
[ "$(a mode)" = tamper ]; ck "scope-use 종류 foo → tamper" $?
fresh; printf 'scope-stop S1 1 \n' >> "$LOG"
[ "$(a mode)" = tamper ]; ck "사유 빈 scope-stop 줄 → tamper" $?
fresh; grant --for 10h --max 5 --classes docs >/dev/null; run a scope-approve "$(sha 51)"; printf 'junk line\n' >> "$LOG"
run a scope-approve "$(sha 52)"; [ $rc = 2 ] && has '위변조'; ck "위변조 상태 scope-approve REJECT" $?
run a scope-status; has '^\[범위 승인 S1 정지: 위변조'; ck "위변조 status 정지 표시" $?
run a scope-status; rm -rf "$S"; mkdir -p "$S"; run a scope-status; has '^\[범위 승인 없음\]$'; ck "status 승인 없음 꼴" $?

# ===== r3: grant 슬랙 1줄 + grants.audit + scope-status --audit (판정 2078 ⓐ — 직접 쓰기는 막지 못하고 «들킨다») =====
AU="$S/autonomy-scope/grants.audit"; : > "$STUB_POST_LOG"
fresh; grant --for 10h --max 5 --daily 2 --classes docs,ff
[ $rc = 0 ] && [ "$(wc -l < "$AU" | tr -d ' ')" = 1 ] && printf 'S1\tA1\t%s\tuntil=%s\tmax=5\tdaily=2\tclasses=docs,ff\tslack_ts=1800000000.000100\n' "$T0" "$((T0+36000))" | cmp -s - "$AU"; ck "게시 성공 → grant + grants.audit 1줄(슬랙 ts 포함)" $?
grep -qE "^\[범위 승인\] S1 · A1 · ~[0-9]{2}:[0-9]{2}까지 · max 5 · 하루 2 · docs,ff · 부여 $T0\$" "$STUB_POST_LOG" && [ "$(wc -l < "$STUB_POST_LOG" | tr -d ' ')" = 1 ]; ck "슬랙 본문 1줄 꼴([범위 승인] S·A·~HH:MM·max·하루·classes·부여)" $?
n0="$(lines)"; rm -f "$AU"
STUB_POST_RC=1 grant --for 10h --max 5 --classes docs; [ $rc = 1 ] && has '슬랙 게시 실패 rc=1'; ck "게시 실패 → REJECT rc 1" $?
[ "$(lines)" = "$n0" ] && [ ! -e "$AU" ] && ! grep -q '^approve-scope S2' "$LOG"; ck "게시 실패 → grant·audit 쓰기 0" $?
FT_SCOPE_SLACK_POST=/nonexistent grant --for 10h --max 5 --classes docs; [ $rc = 1 ] && has '슬랙 게시 도구 없음'; ck "게시 도구 없음 → REJECT rc 1 · 쓰기 0" $?
[ "$(lines)" = "$n0" ]; ck "도구 없음 쓰기 0" $?
run a scope-status --audit; [ $rc = 3 ] && has '^AUDIT-MISMATCH'; ck "audit 줄을 지운 상태(S1 grant 만 남음) → MISMATCH rc 3" $?
fresh; run a scope-status --audit; [ $rc = 0 ] && has '^AUDIT-OK grants=0 used=0$'; ck "--audit grant 없음 → AUDIT-OK grants=0" $?
grant --for 10h --max 5 --classes docs >/dev/null; run a scope-approve "$(sha 71)"; run a scope-approve "$(sha 72)"
run a scope-status --audit; [ $rc = 0 ] && has '^AUDIT-OK grants=1 used=2$'; ck "정상 흐름 → AUDIT-OK grants=1 used=2" $?
cp "$LOG" "$T/log.keep"; cp "$AU" "$T/au.keep"
printf 'approve-scope S2 A1 %s until=%s max=30 daily=30 classes=docs,ff,revert\n' "$((T0+5))" "$((T0+999999))" >> "$LOG"
run a scope-status --audit; [ $rc = 3 ] && has '^AUDIT-MISMATCH S2 grant'; ck "log 에 직접 덧붙인 grant(슬랙 줄 없음) → MISMATCH S2 rc 3" $?
[ "$(a mode)" = on ]; ck "덧붙인 grant 줄 꼴은 위변조 판정에 안 걸림(그래서 --audit 이 잡는다)" $?
cp "$T/log.keep" "$LOG"; sed -i '' 's/max=5/max=9/' "$AU"
run a scope-status --audit; [ $rc = 3 ] && has '^AUDIT-MISMATCH S1 grant'; ck "audit 값을 바꿈(max=9) → MISMATCH S1" $?
cp "$T/au.keep" "$AU"; sed -i '' 's/slack_ts=[0-9.]*/slack_ts=/' "$AU"
run a scope-status --audit; [ $rc = 3 ] && has '^AUDIT-MISMATCH S1 grant'; ck "audit 의 슬랙 ts 를 비움 → MISMATCH" $?
cp "$T/au.keep" "$AU"
grep -v "^scope-use S1 $(sha 72) " "$LOG" > "$T/log.cut" && cp "$T/log.cut" "$LOG"
run a scope-status --audit; [ $rc = 3 ] && has '^AUDIT-MISMATCH S1 used: scope-use 1 ≠ 원장 2행'; ck "scope-use 줄 삭제 → MISMATCH used(원장 행과 어긋남) rc 3" $?
cp "$T/log.keep" "$LOG"; rm -f "$AP/$(sha 72)"
run a scope-status --audit; [ $rc = 3 ] && has '^AUDIT-MISMATCH S1 used: scope-use 2 > 승인 파일 1'; ck "승인 파일 삭제 → MISMATCH used(승인 파일 수 < scope-use 수) rc 3" $?
printf 'approve-merge %s A1 %s\n' "$(sha 73)" "$((T0+7))" > "$AP/$(sha 73)"; printf '%s\n' "approve-merge $(sha 72) A1 $T0" > "$AP/$(sha 72)"
run a scope-status --audit; [ $rc = 0 ] && has '^AUDIT-OK grants=1 used=2$'; ck "오빠 수동 approve-merge 가 더 있어도(파일 3 ≥ 2) AUDIT-OK" $?

# ===== R411: 종류 code — 시험 통과 세트만 · code-max 안 (판정 2326) · 실 git(임시 origin+clone) + 실 evidence-check·approval-equiv · 분류기만 스텁 =====
R="$T/r"; OR="$T/origin.git"; CARD="$T/card.md"; export STUB_OUT="CLASS code"
G() { git -C "$R" "$@"; }; cm() { G add -A && G commit -q -m "$1"; }; hd() { G rev-parse HEAD; }
git init -q --bare -b main "$OR"; git clone -q "$OR" "$R" 2>/dev/null; G config user.name t; G config user.email t@t
echo base > "$R/README.md"; cm base; G push -q origin HEAD:main; G fetch -q origin
G checkout -q -B nano origin/main; mkdir -p "$R/src"; echo 'x = 1' > "$R/src/x.py"; cm code1; A="$(hd)"                       # 나노 세트 A(코드 1커밋)
G checkout -q -B main origin/main; echo m > "$R/b.txt"; cm main1; G push -q origin main; G fetch -q origin                   # main 이 1커밋 나아감
G checkout -q nano; G merge -q --no-edit origin/main >/dev/null 2>&1; SM="$(hd)"                                               # SM = A 위 main 병합만
G checkout -q -B nano2 "$A"; echo 'y = 2' > "$R/src/y.py"; cm own2; SX="$(hd)"                                                 # SX = A 위 자기 변경 더(동일 승인 아님)
G checkout -q -B other origin/main; mkdir -p "$R/src"; echo z > "$R/src/z.py"; cm other; X="$(hd)"; G checkout -q nano                          # X = A 의 조상 아님
card() { printf '# 카드\n## 상태\n- 세트: %s · 시험: %s · 이슈: 0\n' "$1" "${2:-bash t.sh rc=0}" > "$CARD"; }
ar() { FT_ROOT="$R" a "$@"; }
# ⓐ grant
fresh; grant --for 2h --max 5 --classes docs,ff,revert,code --code-max 2
[ $rc = 0 ] && has '^SCOPE-GRANTED S1 A1 until=[0-9]{2}:[0-9]{2} max=5 daily=5 classes=docs,ff,revert,code codemax=2$'; ck "ⓐ code grant → SCOPE-GRANTED … codemax=2" $?
grep -qxF "approve-scope S1 A1 $T0 until=$((T0+7200)) max=5 daily=5 classes=docs,ff,revert,code codemax=2" "$LOG" && [ "$(a mode)" = on ]; ck "ⓐ log grant 줄 꼴 · SCOPE_GRANT_RE 통과(mode=on)" $?
run a scope-status; has '^\[범위 승인 S1 · A1 · .* 0/5 · 오늘 0/5 · docs,ff,revert,code · code 0/2\]$'; ck "ⓐ scope-status code 0/2" $?
grep -q 'docs,ff,revert,code · code 2 · 부여' "$STUB_POST_LOG" && run a scope-status --audit && [ $rc = 0 ]; ck "ⓐ 슬랙 1줄 code 2 · --audit AUDIT-OK(codemax 칸)" $?
# ⓓ 거절 — 쓰기 0
n0="$(lines)"; card "$A"
run ar scope-approve "$A"; [ $rc = 2 ] && has '--card <카드.md> 필요'; ck "ⓓ --card 없음 → REJECT" $?
printf '# 카드\n## 상태\n- 없음\n' > "$CARD"; run ar scope-approve "$A" --card "$CARD"; [ $rc = 2 ] && has '꼴 아님'; ck "ⓓ 증거 줄 없음 → REJECT" $?
card "$A" "bash t.sh rc=1"; run ar scope-approve "$A" --card "$CARD"; [ $rc = 2 ] && has '꼴 아님'; ck "ⓓ 시험 rc≠0 → REJECT" $?
card "$X"; run ar scope-approve "$A" --card "$CARD"; [ $rc = 2 ] && has '증거 검사 rc=1: REJECT .*조상이 아니다'; ck "ⓓ 세트 sha 가 head 의 조상 아님 → REJECT" $?
card "$A"; run ar scope-approve "$SX" --card "$CARD"; [ $rc = 2 ] && has '동일 승인 아님 rc=1: NOT-EQUIV'; ck "ⓓ A 위 자기 변경 더(NOT-EQUIV) → REJECT" $?
run ar scope-approve "$A" --card "$T/none.md"; [ $rc = 2 ] && has '카드 없음'; ck "ⓓ 카드 파일 없음 → REJECT" $?
[ "$(lines)" = "$n0" ] && [ ! -d "$AP" ] && [ ! -e "$S/autonomy-scope/S1.ledger.tsv" ]; ck "ⓓ 거절 전부 쓰기 0(승인 파일·원장 0)" $?
# ⓑ 세트 == head
card "$A"; run ar scope-approve "$A" --card "$CARD" --pr 9
[ $rc = 0 ] && has "^SCOPE-OK $A class=code code=1/2 used=1/5 today=1/5\$"; ck "ⓑ 세트 == head → SCOPE-OK class=code code=1/2" $?
[ "$(cat "$AP/$A")" = "approve-merge $A A1 $T0" ] && grep -qxF "$(cat "$AP/$A")" "$LOG" && grep -qxF "scope-use S1 $A code $T0" "$LOG"; ck "ⓑ 승인 파일 1줄 == log 한 줄 · scope-use code" $?
printf '%s\t%s\t9\tcode\tevidence=%s@%s\t\t\n' "$T0" "$A" "$CARD" "$A" | cmp -s - "$S/autonomy-scope/S1.ledger.tsv"; ck "ⓑ 원장 5번째 칸 evidence=<카드>@<A>" $?
[ "$(a mode)" = on ]; ck "ⓑ scope-use code 줄은 위변조 아님" $?
STUB_OUT="CLASS docs" run ar scope-approve "$(sha 81)"; [ $rc = 0 ] && has "^SCOPE-OK $(sha 81) class=docs used=2/5 today=2/5\$"; ck "ⓔ docs 는 --card 없이 · code 건수와 별개" $?
# ⓒ head = 세트 위 main 병합만(EQUIV)
run ar scope-approve "$SM" --card "$CARD"
[ $rc = 0 ] && has "^SCOPE-OK $SM class=code code=2/2 used=3/5 today=3/5 equiv=$A\$"; ck "ⓒ 세트 위 main 병합 head → SCOPE-OK equiv=A" $?
[ "$(awk -F'\t' 'NR==3{print $5}' "$S/autonomy-scope/S1.ledger.tsv")" = "evidence=$CARD@$A" ]; ck "ⓒ 원장 evidence=<카드>@<A>" $?
# ⓔ code-max 도달
run ar scope-approve "$SX" --card "$CARD"; [ $rc = 2 ] && has '정지: code 건수 도달\(2/2\)'; ck "ⓔ code-max 도달 → REJECT" $?
[ -f "$S/autonomy-scope/S1.stopped" ] && grep -q '^scope-stop S1 [0-9]* code 건수 도달(2/2)$' "$LOG" && [ ! -e "$AP/$SX" ]; ck "ⓔ 도달 = 기존 건수 도달과 같은 정지(log + .stopped) · 승인 0" $?
run a scope-status --audit; [ $rc = 0 ] && has '^AUDIT-OK grants=1 used=3$'; ck "ⓔ 정상 흐름 --audit AUDIT-OK" $?
fresh; grant --for 2h --max 5 --classes docs,ff,revert >/dev/null; card "$A"; run ar scope-approve "$A" --card "$CARD"; [ $rc = 2 ] && has '종류 code 는 승인 범위\(docs,ff,revert\) 밖'; ck "ⓔ 옛 grant(code 없음 · codemax 없음) → code 범위 밖 REJECT(기본 닫힘)" $?
export STUB_OUT="CLASS docs"

# ===== 훅: 상태 폴더·approve-scope 보호 =====
mkbash() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}},ensure_ascii=False))' "$1" "$T"; }
mkfile() { python3 -c 'import json,sys;print(json.dumps({"tool_name":sys.argv[1],"cwd":sys.argv[3],"tool_input":{"file_path":sys.argv[2],"content":"x"}},ensure_ascii=False))' "$1" "$2" "$T"; }
hook() { out="$(printf '%s' "$1" | "$BASH" "$SG" 2>/dev/null)"; rc=$?; }
dn() { hook "$1"; [ "$rc" = 0 ] && grep -q 'permissionDecision": "deny"' <<<"$out"; ck "$2" $?; }
al() { hook "$1"; [ "$rc" = 0 ] && [ -z "$out" ]; ck "$2" $?; }
bash -n "$SG"; ck "bash -n autonomy-state-guard.sh" $?
dn "$(mkbash "bash $BIN/ft-autonomy.sh approve-scope --for 10h --max 5 --classes docs")" "좌석 approve-scope 실행 → deny"
dn "$(mkbash "ft-autonomy.sh approve-scope --for 1h --max 1 --classes ff")" "ft-autonomy.sh approve-scope → deny"
dn "$(mkbash "FT_ROOT=/x bash -c 'ft-autonomy.sh approve-scope --for 1h'")" "bash -c 안 approve-scope → deny"
al "$(mkbash "bash $BIN/ft-autonomy.sh scope-approve $(sha 1) --pr 3")" "scope-approve → allow (좌석 경로)"
al "$(mkbash "bash $BIN/ft-autonomy.sh scope-stop S1 사유")" "scope-stop → allow"
al "$(mkbash "bash $BIN/ft-autonomy.sh scope-status")" "scope-status → allow"
al "$(mkbash "cat $S/autonomy-scope/S1.ledger.tsv")" "autonomy-scope/ 읽기 → allow"
dn "$(mkbash "echo x > $S/autonomy-scope/S1.stopped")" "autonomy-scope/ 리다이렉트 쓰기 → deny"
dn "$(mkbash "rm $S/autonomy-scope/S1.stopped")" "autonomy-scope/ rm → deny"
dn "$(mkbash "cp /tmp/x $S/autonomy-scope/S9.ledger.tsv")" "autonomy-scope/ cp 대상 → deny"
dn "$(mkfile Write "$S/autonomy-scope/S1.stopped")" "Write autonomy-scope/ → deny"
dn "$(mkfile Edit "$S/autonomy-scope/S1.ledger.tsv")" "Edit autonomy-scope/ → deny"
al "$(mkfile Write "$T/other.txt")" "다른 경로 Write → allow"

echo "fail=$fail"; [ "$fail" = 0 ]
