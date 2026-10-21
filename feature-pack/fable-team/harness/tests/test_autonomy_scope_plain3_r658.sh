#!/usr/bin/env bash
# test_autonomy_scope_plain3_r658.sh — r658 자율 켜짐 알림 슬랙 글 = 사람 말 3줄(켜짐 · 혼자 해도 되는 것 · 언제까지 · 내부 번호 0) · 기계 줄(approve-scope·grants.audit) 바이트 무변경
# 격리: 임시 루트(FT_ROOT·FT_AUTONOMY_STATE_DIR·FT_PLANNER_DIR) + FT_NOW 고정 시계 + 가짜 분류기·가짜 슬랙 게시(본문을 파일에 기록) — 실 슬랙·실 state·외부 호출 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset FT_AUTONOMY_LEVEL
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; MIR="$HERE/../kit/fable-team/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/planner"
S="$T/state"; LOG="$S/autonomy.log"; P="$T/post.log"; SD="$S/autonomy-scope"; AU="$SD/grants.audit"
mkdir -p "$T/.fable-team" "$S" "$T/planner"
T0=1800000000; NOW=$T0
cat > "$T/cls.sh" <<'EOF'
#!/usr/bin/env bash
# 가짜 분류기 — check-revert = OK · classify = CLASS docs(실 git·실 분류기 0)
[ "$1" = check-revert ] && { echo OK; exit 0; }
echo "CLASS docs"
EOF
cat > "$T/post.sh" <<'EOF'
#!/usr/bin/env bash
# 가짜 슬랙 게시 — 본문은 STUB_POST_LOG 에 그대로 모은다(여러 줄 = 여러 줄) · 성공 = `SLACK-TS <ts>`
[ "$1" = --text ] && printf '%s\n' "$2" >> "${STUB_POST_LOG:-/dev/null}"
[ "${STUB_POST_RC:-0}" = 0 ] || { echo "ERR 게시 실패" >&2; exit "$STUB_POST_RC"; }
echo "SLACK-TS 1800000000.000100"
EOF
export FT_SCOPE_CLASSIFY="$T/cls.sh" FT_SCOPE_SLACK_POST="$T/post.sh" STUB_POST_LOG="$P"
a() { FT_NOW="$NOW" "$BASH" "$BIN/ft-autonomy.sh" "$@"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
fresh() { rm -rf "$S"; mkdir -p "$S"; rm -f "$P"; NOW=$T0; }
hhmm() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M; }
sha() { printf '%040x' "$1"; }
body() { cat "$P"; }
bad() {  # 본문에 내부 번호·영어 칸 이름·10자리 숫자 0
  local b="$1" x=0
  grep -Eq '(^|[^[:alnum:]_])[AS][0-9]+([^[:alnum:]_]|$)' <<<"$b" && x=1
  grep -Eqi 'max|daily|classes|level|codemax|repos|epoch|큐 *[0-9]|대리 *[0-9]' <<<"$b" && x=1
  grep -Eq '(^|[^0-9])[0-9]{10}([^0-9]|$)' <<<"$b" && x=1
  return $x
}
unit() { bash -c 'HERE=$1; STATE=$2; LOG=$3; shift 3; hhmm() { echo 09:05; }; . "$HERE/ft-autonomy-scope.sh"; "$@"' -- "$BIN" "$S" "$LOG" "$@" 2>&1; }
mkstate() {  # 옛 판 on(A2 · 범위 줄 없이) 픽스처 — 재발급 경로를 만든다
  printf '%s\toff\tA1\n%s\ton\tA2\n' "$((T0+1))" "$((T0+2))" >> "$LOG"
  printf '{"mode":"on","since":%s,"event":"A2","until":%s,"level":"%s"}\n' "$((T0+2))" "$((T0+50000))" "$1" > "$S/autonomy.json"
}

for f in ft-autonomy-scope.sh ft-autonomy-level.sh; do bash -n "$BIN/$f"; ck "bash -n $f" $?; cmp -s "$BIN/$f" "$MIR/$f"; ck "키트 짝 cmp0 $f" $?; done

# ===== ⓐ 실패 시험 먼저 — 고치기 전 판은 여기서 FAIL(옛 글 «[범위 승인] S1 · A1 · ~HH:MM까지 · max 30 · … · 부여 1800000000») =====
fresh; run a on --level full --for 12h
[ $rc = 0 ] && [ "$(body | wc -l | tr -d ' ')" = 3 ]; ck "ⓐ 켜기 알림 = 정확히 3줄" $?
bad "$(body)"; ck "ⓐ 본문에 내부 번호·영어 칸 이름·10자리 숫자 0" $?
! grep -q '\[범위 승인\]' <<<"$(body)"; ck "ⓐ 옛 머리말 «[범위 승인] S… 부여 <epoch>» 0" $?

# ===== ⓑ 3줄 원문 — 1줄 켜짐(풀자동|중간) · 2줄 혼자 해도 되는 것 · 3줄 언제까지 =====
fresh; run a on --level full --for 12h
printf '자율 켜짐(풀자동)\n혼자 해도 되는 것: 문서 병합 · 빨리 감기 병합 · 되돌림 30건까지 · 코드 병합 10건까지 · 하루 15건\n언제까지: %s 까지\n' "$(hhmm $((T0+43200)))" > "$T/exp"
cmp -s "$T/exp" "$P"; ck "ⓑ 풀자동 3줄 원문 일치(기본표 classes·code-max·하루)" $?
fresh; run a on --level mid --for 6h
printf '자율 켜짐(중간)\n혼자 해도 되는 것: 문서 병합 · 빨리 감기 병합 · 되돌림 30건까지 · 하루 15건\n언제까지: %s 까지\n' "$(hhmm $((T0+21600)))" > "$T/exp"
cmp -s "$T/exp" "$P"; ck "ⓑ 중간 3줄 원문 일치(code 종류 없음 → 코드 병합 칸 0)" $?
fresh; run a on
printf '자율 켜짐(풀자동)\n혼자 해도 되는 것: 문서 병합 · 빨리 감기 병합 · 되돌림 30건까지 · 코드 병합 10건까지 · 하루 15건\n언제까지: 다음 범위 승인까지 · 24시간\n' > "$T/exp"
cmp -s "$T/exp" "$P"; ck "ⓑ 끝 없는 ON → «다음 범위 승인까지 · 24시간»" $?
fresh; a on --level full --for 12h >/dev/null 2>&1; : > "$P"; grant() { run a approve-scope "$@"; }
grant --for 10h --max 5 --daily 2 --classes docs,ff
printf '자율 켜짐(풀자동)\n혼자 해도 되는 것: 문서 병합 · 빨리 감기 병합 5건까지 · 하루 2건\n언제까지: %s 까지\n' "$(hhmm $((T0+36000)))" > "$T/exp"
[ $rc = 0 ] && cmp -s "$T/exp" "$P"; ck "ⓑ 손 범위 승인(approve-scope)도 같은 3줄(레벨 = 지금 ON)" $?

# ===== ⓒ 금지 글자 — 켜짐 글마다(풀자동·중간·손 승인·끝 없음) =====
for s in "on --level full --for 12h" "on --level mid --for 6h" "on"; do fresh; a $s >/dev/null 2>&1; bad "$(body)"; ck "ⓒ 내부 번호 0 ($s)" $?; done
fresh; a on --level full --for 12h >/dev/null 2>&1; : > "$P"; grant --for 10h --max 5 --classes docs; bad "$(body)"; ck "ⓒ 내부 번호 0 (손 범위 승인)" $?

# ===== ⓓ 쉬운 말 대응표 1곳 · 표에 없는 종류 = 게시 «전» REJECT =====
[ "$(unit scope_class_plain docs)" = "문서 병합" ] && [ "$(unit scope_class_plain ff)" = "빨리 감기 병합" ] \
  && [ "$(unit scope_class_plain revert)" = "되돌림" ] && [ "$(unit scope_class_plain code)" = "코드 병합" ]; ck "ⓓ 대응표 4종(docs·ff·revert·code)" $?
out="$(unit scope_class_plain move-changed)"; rc=$?; [ $rc = 1 ] && [ -z "$out" ]; ck "ⓓ 표에 없는 종류 → rc 1(조용히 키 그대로 0)" $?
out="$(unit scope_slack_body $((T0+9)) 5 5 docs,bogus 0 full '')"; rc=$?; [ $rc = 1 ] && has '모르는 종류: bogus' && ! has '혼자 해도 되는 것'; ck "ⓓ 본문 만들기 = 모르는 종류 REJECT(본문 0)" $?
: > "$P"; : > "$T/g.log"; out="$(unit scope_grant_post A1 "$T0" $((T0+9)) 5 5 docs,bogus 0 byz full '')"; rc=$?
[ $rc = 2 ] && [ ! -s "$P" ] && has '모르는 종류'; ck "ⓓ 게시 «전» REJECT — 슬랙 0" $?

# ===== ⓔ 기계 줄 = 바이트 그대로(grant 줄·grants.audit) =====
fresh; a on --level full --for 12h >/dev/null 2>&1; : > "$P"; grant --for 10h --max 5 --daily 2 --classes docs,ff
grep -qxF "approve-scope S2 A1 $T0 until=$((T0+36000)) max=5 daily=2 classes=docs,ff" "$LOG"; ck "ⓔ approve-scope 줄 바이트 그대로(내부 칸 이름 유지)" $?
printf 'S2\tA1\t%s\tuntil=%s\tmax=5\tdaily=2\tclasses=docs,ff\tslack_ts=1800000000.000100\n' "$T0" "$((T0+36000))" | cmp -s - <(tail -1 "$AU"); ck "ⓔ grants.audit 줄 바이트 그대로(슬랙 ts 칸 포함)" $?
st="$(grep -c '^scope-use ' "$LOG")"; run a scope-approve "$(sha 9)"
[ $rc = 0 ] && [ "$(grep -c '^scope-use ' "$LOG")" = "$((st+1))" ] && grep -qxF "scope-use S2 $(sha 9) docs $T0" "$LOG"; ck "ⓔ scope-use 줄 바이트 그대로" $?
run a scope-status --audit; [ $rc = 0 ] && has '^AUDIT-OK'; ck "ⓔ --audit OK(게시 본문을 바꿔도 대조 그대로)" $?
STUB_POST_RC=1 grant --for 1h --max 2 --classes docs; [ $rc = 1 ] && has '슬랙 게시 실패'; ck "ⓔ 게시 실패 → grant 쓰기 0 그대로(rc 1)" $?

# ===== ⓕ 레벨 each = 게시 0 그대로 · 범위 재승인(SCOPE-RENEWED)도 사람 말 3줄 =====
fresh; run a on --level each --for 2h; [ $rc = 0 ] && [ ! -s "$P" ] && ! grep -q '^approve-scope ' "$LOG"; ck "ⓕ each → 슬랙 0 · 범위 승인 줄 0 그대로" $?
fresh; a on --for 12h >/dev/null 2>&1; mkstate full; : > "$P"; run a scope-approve "$(sha 2)"
[ $rc = 0 ] && has '^SCOPE-RENEWED S2 A2 level=full' && [ "$(body | wc -l | tr -d ' ')" = 3 ] && bad "$(body)"; ck "ⓕ 재발급도 사람 말 3줄(SCOPE-RENEWED 경로)" $?
printf '자율 켜짐(풀자동)\n혼자 해도 되는 것: 문서 병합 · 빨리 감기 병합 · 되돌림 30건까지 · 코드 병합 10건까지 · 하루 15건\n언제까지: %s 까지\n' "$(hhmm $((T0+50000)))" > "$T/exp"
cmp -s "$T/exp" "$P"; ck "ⓕ 재발급 본문 원문 = 같은 값·같은 3줄" $?

echo "fail=$fail"; [ "$fail" = 0 ]
