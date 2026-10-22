#!/usr/bin/env bash
# test_autonomy_scope_pack.sh — r466 ⓙ 팩 저장소 PR 범위 승인: scope-approve --repo pack(승인 줄 repos=byz,pack 일 때만) · 팩 분류표 전달 · code 세트 검사도 팩 리포 · 원장 repo= 칸
# 격리: 임시 BYZ 루트 + 임시 팩 리포(bare origin + clone · FT_HARNESS_ROOT) + 가짜 분류기·슬랙 — 실 리포·실 슬랙 0 · GIT_* env 0
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset FT_AUTONOMY_LEVEL
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
has() { grep -qE -- "$1" <<<"$out"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export FT_ROOT="$T/byz" FT_AUTONOMY_STATE_DIR="$T/state" FT_PLANNER_DIR="$T/planner"
S="$T/state"; LOG="$S/autonomy.log"; mkdir -p "$T/byz/.fable-team" "$S" "$T/planner"
T0=1800000000
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/args.log"\n[ "$1" = check-revert ] && { echo OK; exit 0; }\necho "${STUB_OUT:-CLASS docs}"\n' "$T" > "$T/cls.sh"
printf '#!/usr/bin/env bash\necho "SLACK-TS 1800000000.000100"\n' > "$T/post.sh"
export FT_SCOPE_CLASSIFY="$T/cls.sh" FT_SCOPE_SLACK_POST="$T/post.sh" FT_AUTONOMY_GOAL_TABLE=0
# 팩 리포: bare origin + clone · 하네스 루트 = <리포>/feature-pack/fable-team/harness(kit/fable-team 실재)
OR="$T/pack.git"; P="$T/pack"; G() { git -C "$P" "$@"; }
git init -q --bare -b main "$OR"; git clone -q "$OR" "$P" 2>/dev/null; G config user.name t; G config user.email t@t
KB="$P/feature-pack/fable-team/harness/kit/fable-team/bin"; mkdir -p "$KB"; echo base > "$KB/ft-x.sh"; G add -A; G commit -q -m base; G push -q origin HEAD:main; G fetch -q origin
G checkout -q -B nano origin/main; echo 'echo 1' >> "$KB/ft-x.sh"; G add -A; G commit -q -m kit1; A="$(G rev-parse HEAD)"
export FT_HARNESS_ROOT="$P/feature-pack/fable-team/harness"; PT="$(G rev-parse --show-toplevel)"
a() { FT_NOW="$T0" "$BASH" "$BIN/ft-autonomy.sh" "$@"; }
run() { out="$("$@" 2>&1)"; rc=$?; }
sha() { printf '%040x' "$1"; }
fresh() { rm -rf "$S" "$T/args.log"; mkdir -p "$S"; }

# full = repos=byz,pack
fresh; a on --for 12h >/dev/null 2>&1; grep -q ' repos=byz,pack level=full$' "$LOG"; ck "ⓙ full 승인 줄 repos=byz,pack" $?
run a scope-approve "$(sha 1)" --repo pack --pr 99
[ $rc = 0 ] && has "^SCOPE-OK $(sha 1) class=docs used=1/30 today=1/15 repo=pack$"; ck "ⓙ --repo pack · docs → SCOPE-OK … repo=pack (가짜 sha = 못 재면 칸 없음 = 셈 1)" $?
grep -q "^classify $(sha 1) --repo $PT --remote origin --target main --scope S1 --table .*/scope-classes-pack.tsv$" "$T/args.log" && grep -q "^check-revert --repo $PT " "$T/args.log"; ck "ⓙ 분류기·되돌림 검사에 팩 리포 + 팩 분류표(DDL 기록표 0)" $?
grep -qx "scope-use S1 $(sha 1) docs $T0 repo=pack" "$LOG" && [ "$(a mode)" = on ]; ck "ⓙ log scope-use … repo=pack · 위변조 아님" $?
[ "$(awk -F'\t' '{print $5}' "$S/autonomy-scope/S1.ledger.tsv")" = "repo=pack" ]; ck "ⓙ 원장 5번째 칸 repo=pack" $?
# code — 시험 통과 세트 검사도 팩 리포에서(evidence-check · approval-equiv)
CARD="$T/card.md"; printf '# 카드\n## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$A" > "$CARD"
STUB_OUT="CLASS code" run a scope-approve "$A" --repo pack --card "$CARD"
[ $rc = 0 ] && has "^SCOPE-OK $A class=code code=1/10 .* repo=pack$"; ck "ⓙ --repo pack · code + 카드 세트 → SCOPE-OK(증거 검사 = 팩 리포)" $?
[ "$(awk -F'\t' 'NR==2{print $5}' "$S/autonomy-scope/S1.ledger.tsv")" = "evidence=$CARD@$A repo=pack" ]; ck "ⓙ 원장 evidence=…@A repo=pack" $?
# 범위 밖
fresh; a on --level mid --for 12h >/dev/null 2>&1; run a scope-approve "$(sha 2)" --repo pack; [ $rc = 2 ] && has '저장소 pack 은 승인 범위\(repos=byz\) 밖'; ck "ⓙ mid(repos 칸 없음) → --repo pack SCOPE-REJECT" $?
[ ! -e "$T/args.log" ]; ck "ⓙ 범위 밖 = 분류기 호출 0 · 쓰기 0" $?
run a scope-approve "$(sha 3)" --repo elsewhere; [ $rc = 2 ] && has '--repo 는 byz 또는 pack'; ck "ⓙ --repo 모르는 값 → REJECT" $?
fresh; a on --for 12h >/dev/null 2>&1; FT_HARNESS_ROOT="$T/none" run a scope-approve "$(sha 4)" --repo pack; [ $rc = 2 ] && has '팩 리포를 못 풂'; ck "ⓙ 팩 리포 못 풂 → REJECT(닫힌 쪽)" $?
run a scope-approve "$(sha 5)"; [ $rc = 0 ] && grep -q "^classify $(sha 5) --repo $T/byz .*--ddl-records .*/scope-ddl-record.tsv$" "$T/args.log"; ck "ⓙ --repo 생략 = byz(FT_ROOT) + DDL 기록표" $?
# ===== r748 2b: approve-scope --repos 생략 기본 = byz,pack (새 승인부터 · 소급 0) =====
fresh; a on --level each >/dev/null 2>&1; run a approve-scope --for 12h --max 30 --classes docs
[ $rc = 0 ] && grep -q '^approve-scope S[0-9]* A[0-9]* [0-9]* until=[0-9]* max=30 daily=10 classes=docs repos=byz,pack$' "$LOG"; ck "ⓝ --repos 생략 → 승인 줄 끝 repos=byz,pack" $?
run a scope-approve "$(sha 6)" --repo pack; [ $rc = 0 ] && has "^SCOPE-OK $(sha 6) class=docs .* repo=pack$"; ck "ⓝ 생략 승인으로 팩 sha scope-approve → SCOPE-OK(종류 = 팩 표)" $?
fresh; a on --level each >/dev/null 2>&1; run a approve-scope --for 12h --max 30 --classes docs --repos byz
[ $rc = 0 ] && ! grep -q ' repos=' "$LOG"; ck "ⓞ --repos byz 명시 → 승인 줄에 repos 칸 없음(byz 만)" $?
run a scope-approve "$(sha 7)" --repo pack; [ $rc = 2 ] && has '저장소 pack 은 승인 범위\(repos=byz\) 밖'; ck "ⓞ --repos byz 명시 → 팩 sha REJECT(지금과 같음)" $?

# ⓟ 실 분류기 1벌 — 팩 manifest.json 은 docs 지만 .md 만이 아니다 = 셈 1 (r748 DA⑥ r1)
fresh; a on --level each >/dev/null 2>&1; run a approve-scope --for 12h --max 30 --classes docs,ff --repos byz,pack
G checkout -q -B nano2 origin/main; mkdir -p "$P/feature-pack/fable-team"; echo '{}' > "$P/feature-pack/fable-team/manifest.json"; G add -A; G commit -q -m manifest; MAN="$(G rev-parse HEAD)"
FT_SCOPE_CLASSIFY= run a scope-approve "$MAN" --repo pack
[ $rc = 0 ] && has "^SCOPE-OK $MAN class=(docs|ff) used=1/30 today=1/10 repo=pack$"; ck "ⓟ 팩 manifest.json(docs · .md 아님) → 칸 없음 = 셈 1" $?

[ "$(git -C "$P" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
echo "fail=$fail"; [ "$fail" = 0 ]
