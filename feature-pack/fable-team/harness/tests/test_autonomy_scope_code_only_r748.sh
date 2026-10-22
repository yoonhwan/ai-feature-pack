#!/usr/bin/env bash
# test_autonomy_scope_code_only_r748.sh — 자율 범위 몫(총·하루)은 «제품 코드 병합» 과 «.md 만이 아닌 docs·ff» 만 깎는다 (r748 · 오빠 «자율범위 매번하지말고 하네스 업데이트» · DA⑥ r1 처방 1·2)
#   셈 0 = revert·equiv · docs·ff 이고 바뀐 경로가 «전부 .md»(scope-use 끝 counted=0 칸) · 셈 1 = code · 학습표 통과분(learned=) · counted=0 칸이 없는 docs·ff(옛 줄 포함 · r748 r2 실패 닫힘)
#   ※ 분류기 stub 0 — 실제 분류기(autonomy_scope_classify.py)·실 git 으로 판정한다. 격리: 임시 리포(origin+clone) + FT_NOW 고정 + 가짜 슬랙만.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset FT_AUTONOMY_LEVEL FT_SCOPE_CLASSIFY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="$HERE/../.."; BIN="$ROOT/harness/bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/planner" FT_AUTONOMY_HOOK_LOG="$T/hook.log"
S="$T/state"; LOG="$S/autonomy.log"; AP="$S/autonomy-merge-approved"
mkdir -p "$T/.fable-team" "$S" "$T/planner"
T0=1800000000
printf '#!/usr/bin/env bash\necho "SLACK-TS 1800000000.000100"\n' > "$T/stub-post.sh"
export FT_SCOPE_SLACK_POST="$T/stub-post.sh"

a() { FT_NOW="$T0" "$BASH" "$BIN/ft-autonomy.sh" "$@"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
ar() { FT_ROOT="$R" a "$@"; }   # 승인·되돌림 검사는 리포(FT_ROOT=R)에서 본다
grant() { run a approve-scope "$@"; }
fresh() { rm -rf "$S"; mkdir -p "$S"; run a on --level each >/dev/null 2>&1; }   # A1 ON · 레벨 each(= 범위 승인 자동 발급 0) · 시계 T0
uses() { grep -c '^scope-use ' "$LOG" 2>/dev/null || true; }
card() { printf '# 카드\n## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$1" > "$CARD"; }

# ===== 실 git 하네스 — origin+clone · B0 = 옛 main(ff 아님 = docs) · B1 = 지금 origin/main(ff) =====
R="$T/r"; OR="$T/origin.git"; CARD="$T/card.md"
G() { git -C "$R" "$@"; }; cm() { G add -A && G commit -q -m "$1"; }; hd() { G rev-parse HEAD; }
git init -q --bare -b main "$OR"; git clone -q "$OR" "$R" 2>/dev/null; G config user.name t; G config user.email t@t
echo base > "$R/README.md"; cm base; G push -q origin HEAD:main; B0="$(hd)"
echo m1 > "$R/m1.md"; cm main1; G push -q origin HEAD:main; G fetch -q origin; B1="$(hd)"   # origin/main = B1
w() { mkdir -p "$(dirname "$R/$1")"; printf '%s\n' "${2:-x}" >> "$R/$1"; }
br() { G checkout -q -B "$1" "$2"; }
doc() { br "$1" "$2"; shift 2; for p in "$@"; do w "$p"; done; cm "$1" >/dev/null 2>&1 || true; hd; }
D1="$(doc d1 "$B0" design/harness/cards/c1.md)"; D2="$(doc d2 "$B0" design/harness/cards/c2.md)"; D3="$(doc d3 "$B0" design/harness/cards/c3.md)"
SHIL="$(doc n1 "$B0" design/teams/v65/x.sh.hil)"; JS="$(doc n2 "$B0" design/teams/v65/x.js)"
JSN="$(doc n3 "$B0" design/teams/v65/x.json)"; ESH="$(doc n4 "$B0" design/teams/v65/evidence-r1/e.sh)"
br n5 "$B0"; w design/teams/v65/x.sql; w design/teams/v65/NOTE.md 'x.sql applied 1234'; cm n5 >/dev/null 2>&1; SQL="$(hd)"   # 적용 기록 있는 새 .sql = docs
FFMD="$(doc f1 "$B1" design/harness/cards/ff.md)"; FFJS="$(doc f2 "$B1" design/teams/v65/y.js)"
FORBIDC="$(doc fb "$B0" design/teams/v65/q.sql)"                                             # 기록 없는 .sql = FORBID kind=ddl-no-record
CODE="$(doc cd1 "$B0" src/x.py)"; CODE2="$(doc cd2 "$B0" src/y.py)"; PKG="$(doc pk "$B0" package.json)"

# ===== ⓐ 빨강 먼저였던 자리: docs(.md 만) 3건 — daily=2 인데 셋째도 OK · 셈 0 =====
fresh; grant --for 2h --max 3 --daily 2 --classes docs,ff,code --code-max 2
[ $rc = 0 ] && has '^SCOPE-GRANTED S1 A1 .* max=3 daily=2 classes=docs,ff,code codemax=2 repos=byz,pack$'; ck "ⓐ grant S1 max=3 daily=2 codemax=2" $?
run ar scope-approve "$D1"; [ $rc = 0 ] && has "^SCOPE-OK $D1 class=docs used=0/3 today=0/2 counted=0$"; ck "ⓑ .md 만 docs → counted=0 칸 · 셈 0" $?
grep -qxF "scope-use S1 $D1 docs $T0 counted=0" "$LOG"; ck "ⓑ scope-use 줄 끝 = counted=0 (작성기가 만드는 유일한 칸)" $?
run ar scope-approve "$D2"; run ar scope-approve "$D3"
[ $rc = 0 ] && has "^SCOPE-OK $D3 class=docs used=0/3 today=0/2 counted=0$"; ck "ⓑ docs 3건째도 OK (옛 판 = «하루 건수 도달»)" $?
[ "$(uses)" = 3 ] && [ "$(wc -l < "$S/autonomy-scope/S1.ledger.tsv" | tr -d ' ')" = 3 ] && [ "$(ls "$AP" | wc -l | tr -d ' ')" = 3 ]; ck "ⓑ 원장 3행 · scope-use 3줄 · 승인 파일 3개 (감사 그대로)" $?
run a scope-status; has '^\[범위 승인 S1 · A1 · .* 0/3 · 오늘 0/2 · docs,ff,code · code 0/2\]$'; ck "ⓗ scope-status 숫자 = 셈 0(0/3 · 오늘 0/2)" $?
run a scope-status --audit; [ $rc = 0 ] && has '^AUDIT-OK grants=1 used=3$'; ck "ⓘ --audit = AUDIT-OK(셈 0 종류도 승인 파일·scope-use 를 씀)" $?

# ===== ⓒ ff(.md 만) 도 셈 0 · ff(.js) 는 셈 1 =====
run ar scope-approve "$FFMD"; [ $rc = 0 ] && has "^SCOPE-OK $FFMD class=ff used=0/3 today=0/2 counted=0$"; ck "ⓒ ff(.md 만) → counted=0 · 셈 0" $?
run ar scope-approve "$FFJS"; [ $rc = 0 ] && has "^SCOPE-OK $FFJS class=ff used=1/3 today=1/2$"; ck "ⓟ ff(.js) → 칸 없음 = 셈 1" $?
grep -qxF "scope-use S1 $FFJS ff $T0" "$LOG"; ck "ⓟ scope-use 줄에 counted 칸 «없음»(칸 없음 = 셈 1)" $?

# ===== ⓟ 실 분류기 6종 — docs 판정이어도 .md 만이 아니면 셈 1 (daily=1 이면 둘째 거절) =====
fresh; grant --for 2h --max 5 --daily 5 --classes docs,ff,code --code-max 2 >/dev/null
n=0; for sha in "$SHIL" "$JS" "$JSN" "$ESH" "$SQL"; do
  n=$((n+1)); run ar scope-approve "$sha"
  [ $rc = 0 ] && has "^SCOPE-OK $sha class=docs used=$n/5 today=$n/5$"; ck "ⓟ docs(.md 아님 #$n) → 칸 없음 · 셈 $n" $?
done
STUB="$SQL"; run a scope-status; has " 5/5 · 오늘 5/5 · docs,ff,code · code 0/2\]$"; ck "ⓟ counted 는 codemax 를 안 깎는다(code 0/2)" $?
fresh; grant --for 2h --max 5 --daily 1 --classes docs,ff >/dev/null
run ar scope-approve "$JS"; [ $rc = 0 ] && has "used=1/5 today=1/1"; ck "ⓟ daily=1 · 첫 .md 아님 docs = OK" $?
run ar scope-approve "$JSN"; [ $rc = 2 ] && has '하루 건수 도달\(오늘 1/1\)'; ck "ⓟ 둘째 .md 아님 docs → 하루 건수 도달" $?
run ar scope-approve "$D1"; [ $rc = 0 ] && has "class=docs used=1/5 today=1/1 counted=0$"; ck "ⓟ 그 사이 .md 만 docs 는 계속 OK(셈 0)" $?

# ===== ⓓ code = 몫을 깎는다(codemax 경계 유지) =====
fresh; grant --for 2h --max 3 --daily 3 --classes docs,ff,code --code-max 2 >/dev/null; card "$CODE"
run ar scope-approve "$CODE" --card "$CARD"; [ $rc = 0 ] && has "class=code code=1/2 used=1/3 today=1/3$"; ck "ⓓ code 1건 → code=1/2 used=1/3" $?
G checkout -q -B sm "$CODE"; G merge -q --no-edit origin/main >/dev/null 2>&1; SM="$(hd)"
run ar scope-approve "$SM" --card "$CARD"; [ $rc = 0 ] && has "class=code code=2/2 used=2/3 today=2/3 equiv=$CODE$"; ck "ⓓ code 2건(세트 위 main 병합 head) → code=2/2 used=2/3" $?
run ar scope-approve "$CODE2" --card "$CARD"; [ $rc = 2 ] && has '정지: code 건수 도달\(2/2\)'; ck "ⓓ code 3건째 → 정지(code 건수 도달 2/2 · 진짜 경계 유지)" $?
[ ! -e "$AP/$CODE2" ]; ck "ⓓ 정지 = 승인 0" $?

# ===== ⓔ 하루 몫도 셈 1 종류에만 — code 둘째가 daily=1 에서 걸린다 =====
fresh; grant --for 2h --max 5 --daily 1 --classes docs,ff,code --code-max 2 >/dev/null; card "$CODE"
run ar scope-approve "$CODE" --card "$CARD"; [ $rc = 0 ] && has 'used=1/5 today=1/1'; ck "ⓔ code 1건 = 오늘 1/1" $?
run ar scope-approve "$D1"; [ $rc = 0 ] && has "^SCOPE-OK $D1 class=docs used=1/5 today=1/1 counted=0$"; ck "ⓔ 하루 몫이 차도 .md 만 docs 는 OK" $?
run ar scope-approve "$SM" --card "$CARD"; [ $rc = 2 ] && has '하루 건수 도달\(오늘 1/1\)'; ck "ⓔ code 둘째 → 하루 건수 도달" $?
[ ! -e "$AP/$SM" ] && [ ! -f "$S/autonomy-scope/S1.stopped" ]; ck "ⓔ 하루 도달 = 쓰기 0 · 정지 아님(내일 풀림)" $?

# ===== ⓕ revert·equiv 셈 0 그대로 (셈 = code ∨ learned= ∨ counted=0 칸이 «없는» docs·ff) =====
fresh; grant --for 2h --max 5 --daily 5 --classes docs,ff >/dev/null
printf 'scope-use S1 %s revert %s\n' "$(printf '%040x' 901)" "$T0" >> "$LOG"
printf 'scope-use S1 %s equiv %s\n' "$(printf '%040x' 902)" "$T0" >> "$LOG"
run a scope-status; has ' 0/5 · 오늘 0/5 ·'; ck "ⓕ revert·equiv 줄은 셈 0 그대로" $?
run ar scope-approve "$JS"; run a scope-status; has ' 1/5 · 오늘 1/5 ·'; ck "ⓕ 같은 판에서 칸 없는 docs(.js) 는 셈 1(대조)" $?

# ===== ⓖ 범위 밖 종류·FORBID 는 그대로 거절(승인 0) =====
fresh; grant --for 2h --max 3 --classes docs >/dev/null
run ar scope-approve "$CODE"; [ $rc = 2 ] && has '종류 code 는 승인 범위\(docs\) 밖'; ck "ⓖ 범위 밖 종류 code → REJECT" $?
run ar scope-approve "$FORBIDC"; [ $rc = 2 ] && has '분류기 거절 rc=3: FORBID kind=ddl-no-record'; ck "ⓖ 기록 없는 .sql → FORBID(승인 0)" $?
[ "$(awk -F'\t' 'END{print $2}' "$S/autonomy-scope/denied.tsv")" = ddl-no-record ] && [ ! -e "$AP/$FORBIDC" ]; ck "ⓖ FORBID 거절 원장 1행 · 승인 0" $?

# ===== ⓜ 학습표 통과분(learned=)은 docs 여도 셈 1 — 무제한이 되지 않는다(arch 125) =====
rm -rf "$S"; mkdir -p "$S"; run a on --level full >/dev/null 2>&1; printf 'deps\n' > "$S/autonomy-scope/learned-kinds.tsv"
run ar scope-approve "$PKG"; [ $rc = 0 ] && has "class=docs used=1/30 today=1/15 learned=deps$"; ck "ⓜ 학습표 통과분(package.json = deps) → docs + 셈 1" $?
grep -qxF "scope-use S1 $PKG docs $T0 learned=deps" "$LOG"; ck "ⓜ scope-use 줄에 learned=deps 칸" $?
run a scope-status; has ' 1/30 · 오늘 1/15 ·'; ck "ⓜ learned= 은 «다음 셈»에서도 1 (scope_used 가 센다)" $?

# ===== ⓐ2 옛 줄 이어받기 — r748 전 꼴(칸 없음) = 셈 1 (실패 닫힘 · master 결정 A) =====
fresh; grant --for 2h --max 1 --classes docs,ff >/dev/null
printf 'scope-use S1 %s docs %s\n' "$(printf '%040x' 701)" "$T0" >> "$LOG"   # 옛 줄 — counted 칸이 없다(비-md 승인이었던 것)
[ "$(a mode)" = on ]; ck "ⓐ2 칸 없는 옛 docs 줄은 위변조 아님(정규식 통과)" $?
run a scope-status; has ' 1/1 · 오늘 1/1 ·'; ck "ⓐ2 칸 없는 옛 docs 줄 = 셈 1" $?
run ar scope-approve "$JS"; [ $rc = 2 ] && has '건수 도달\(1/1\)'; ck "ⓐ2 옛 줄이 몫을 써서 다음 docs(.js = 셈 1) 승인 거절" $?
run a scope-status; has '정지: 건수 도달\(1/1\)'; ck "ⓐ2 정지 표시" $?

# ===== ⓓ2 정규식 — counted=0 만 · 종류 docs·ff 뒤에만 =====
mode_of() { fresh; grant --for 2h --max 3 --classes docs,ff,revert,code --code-max 2 >/dev/null; printf '%s\n' "$1" >> "$LOG"; a mode; }
for k in revert code; do
  [ "$(mode_of "scope-use S1 $(printf '%040x' 711) $k $T0 counted=0")" = tamper ]; ck "ⓓ2 $k … counted=0 → 거절(위변조)" $?
done
[ "$(mode_of "scope-use S1 $(printf '%040x' 712) docs $T0 counted=1")" = tamper ]; ck "ⓓ2 docs … counted=1 → 거절(위변조)" $?
for k in docs ff; do
  [ "$(mode_of "scope-use S1 $(printf '%040x' 713) $k $T0 counted=0")" = on ]; ck "ⓓ2 $k … counted=0 → 허용" $?
done
run ar scope-approve "$D1"; [ "$(a mode)" = on ]; ck "ⓓ2 작성기가 쓴 counted=0 줄도 위변조 아님" $?

# ===== 짝 사본(설치 미러) · 문법 =====
MIRB="$ROOT/harness/kit/fable-team/bin"
cmp -s "$BIN/ft-autonomy-scope.sh" "$MIRB/ft-autonomy-scope.sh"; ck "설치 미러 cmp0 (ft-autonomy-scope.sh)" $?
bash -n "$BIN/ft-autonomy-scope.sh"; ck "bash -n ft-autonomy-scope.sh" $?

echo "fail=$fail"; [ "$fail" = 0 ]
