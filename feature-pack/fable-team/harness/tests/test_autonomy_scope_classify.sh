#!/usr/bin/env bash
# test_autonomy_scope_classify.sh — R298 2/3: 세트 종류 분류기(autonomy_scope_classify.py) + ft-merge-land 착지 뒤 원장 기록
# 임시 origin(bare)+clone · gh 는 스텁 · 실 gh·실 원격·실 Redis 0 (GIT_* 환경 변수 안 건다 — BOOT 25)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../../harness/bin"; CLS="$BIN/autonomy_scope_classify.py"; LAND="$BIN/ft-merge-land.sh"
. "$HERE/_merge_fixture.sh"
fail=0; rc=0; out=""
ck() { if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 :: rc=$rc out=${out:0:300}"; fail=$((fail+1)); fi; }
T="$(mktemp -d)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkrepo "$T"; mkdir -p "$T/state/autonomy-scope" "$T/.fable-team"
export FT_ROOT="$T" FT_AUTONOMY_STATE_DIR="$T/state"
LEDGER="$T/state/autonomy-scope/S1.ledger.tsv"

# 기준 저장소: BASE(문서·README·스크립트가 있는 main) → main 은 M1 로 한 칸 더 전진 — BASE 에서 딴 가지 = main 조상 아님(docs) · M1 에서 딴 가지 = main 후손(ff)
mkdir -p "$W/design" "$W/docs" "$W/scripts"; echo d > "$W/design/x.md"; echo d > "$W/docs/a.md"; echo r > "$W/README.md"; echo '#!/bin/sh' > "$W/scripts/run.sh"
cm "$W" base2; git -C "$W" push -q origin main; BASE="$(sha "$W" HEAD)"
echo m1 > "$W/m1.txt"; cm "$W" m1; git -C "$W" push -q origin main; git -C "$W" fetch -q origin; M1="$(sha "$W" HEAD)"
mk() {  # mk <가지> <시작점> <셸 명령…> — 시작점에서 가지를 따 명령 실행 후 커밋 → SHA
  local br="$1" from="$2"; shift 2; git -C "$W" checkout -q -B "$br" "$from"; ( cd "$W" && eval "$*" ); cm "$W" "$br"; SHA="$(sha "$W" HEAD)"
}
cls() { out="$(python3 "$CLS" classify "$1" --repo "$W" --scope S1 2>&1)"; rc=$?; }
want() { [ "$rc" = "$2" ] && [[ "$out" == $3* ]]; ck "$1" $?; }   # want <이름> <rc> <출력 머리>

bash -n "$LAND"; ck "bash -n land" $?
python3 -I -m py_compile "$CLS"; ck "py_compile classify" $?
[ "$(wc -l < "$CLS" | tr -d ' ')" -le 200 ]; ck "classify ≤ 200줄" $?
[ "$(wc -l < "$LAND" | tr -d ' ')" -le 120 ]; ck "ft-merge-land.sh ≤ 120줄" $?

# 문서
mk d1 "$BASE" 'echo n > design/new.md';                 cls "$SHA"; want "design/*.md 추가(main 조상 아님) → CLASS docs" 0 "CLASS docs"
mk d2 "$BASE" 'echo e >> design/x.md; echo e >> docs/a.md'; cls "$SHA"; want "design·docs .md 수정 → CLASS docs" 0 "CLASS docs"
mk d3 "$BASE" 'echo n > design/x.py';                   cls "$SHA"; want "design/x.py(경로만 문서) → code" 0 "CLASS code"
mk d4 "$BASE" 'echo n > docs/run.sh';                   cls "$SHA"; want "docs/run.sh → code" 0 "CLASS code"
mk d5 "$BASE" 'echo e >> README.md';                    cls "$SHA"; want "루트 README.md → code(루트 .md 는 문서 아님)" 0 "CLASS code"
mk d6 "$BASE" 'echo n > design/new.md; echo n > design/n.py'; cls "$SHA"; want "문서 + 코드 섞임 → code" 0 "CLASS code"
mk d7 "$BASE" 'git rm -q docs/a.md';                    cls "$SHA"; want "docs/a.md 삭제 → FORBID" 3 "FORBID kind=delete 상태 D"
mk d8 "$BASE" 'git mv docs/a.md docs/b.md';             cls "$SHA"; want "이름 바꾸기(삭제 숨기기) → FORBID" 3 "FORBID kind=rename 상태 R"
mk d9 "$BASE" 'chmod +x design/x.md';                   cls "$SHA"; want "실행 비트만 변경 → FORBID" 3 "FORBID kind=mode 모드"
mk d10 "$BASE" 'echo n > design/new.sh; chmod +x design/new.sh'; cls "$SHA"; want "새 실행 파일 → FORBID" 3 "FORBID kind=mode 모드"

# 불가 범위 (문서 모양이어도 하나라도 걸리면 FORBID)
mk f1 "$BASE" 'mkdir -p db/migrations; echo s > db/migrations/001.sql'; cls "$SHA"; want "DDL(migrations) · 적용 기록 없음 → FORBID" 3 "FORBID kind=ddl-no-record DDL"
mk f2 "$BASE" 'mkdir -p .github/workflows; echo y > .github/workflows/x.yml'; cls "$SHA"; want "배포 설정(workflows) → FORBID" 3 "FORBID kind=deploy 배포"
mk f3 "$BASE" 'mkdir -p app; echo k > app/.env';        cls "$SHA"; want ".env → FORBID" 3 "FORBID kind=key 키"
mk f4 "$BASE" 'echo "-----BEGIN RSA PRIVATE KEY-----" > design/leak.md'; cls "$SHA"; want "문서 속 비밀 꼴 줄 → FORBID" 3 "FORBID kind=secret 추가 줄에 비밀 꼴"
mk f5 "$BASE" 'mkdir -p gateway/billing; echo b > gateway/billing/x.py'; cls "$SHA"; want "과금 경로(코드) → FORBID" 3 "FORBID kind=billing 과금"
mk f5b "$BASE" 'echo b > design/billing-notes.md';      cls "$SHA"; want "이름에 과금 낱말 든 문서 → CLASS docs(낱말 금지는 문서 줄 아래 · r514)" 0 "CLASS docs"
mk f6 "$BASE" 'echo "{}" > package.json';               cls "$SHA"; want "package.json → FORBID" 3 "FORBID kind=deps 의존"
mk f7 "$BASE" 'echo "{}" > package-lock.json';          cls "$SHA"; want "lockfile → FORBID" 3 "FORBID kind=deps 의존"
mk f8 "$BASE" 'mkdir -p .claude/rules; echo r > .claude/rules/x.md'; cls "$SHA"; want ".claude/ → FORBID" 3 "FORBID kind=global-rule 전역 규칙"
mk f9 "$BASE" 'mkdir -p scripts/harness-install; echo r > scripts/harness-install/x.md'; cls "$SHA"; want "scripts/harness-install/ → FORBID" 3 "FORBID kind=global-rule 전역 규칙"
mk f10 "$BASE" 'echo "cat secrets/x.cred" > design/leak2.md'; cls "$SHA"; want "문서 속 비밀 조회 명령 줄(ft_secret_judge 재사용) → FORBID" 3 "FORBID"
mk f11 "$BASE" 'echo n > design/block-diagram.md';      cls "$SHA"; want "block 글자는 lockfile 오탐 아님 → docs" 0 "CLASS docs"

# ff — main 이 sha 의 조상(M1 에서 딴 가지)
mk g1 "$M1" 'echo n > design/f.md';                     cls "$SHA"; want "main 조상 + 문서만 → CLASS ff" 0 "CLASS ff"
mk g2 "$M1" 'echo n > design/f.py';                     cls "$SHA"; want "main 조상 + .py 하나 → code(ff 아님)" 0 "CLASS code"
mk g3 "$M1" 'git rm -q docs/a.md';                      cls "$SHA"; want "main 조상 + 삭제 → FORBID(ff 도 같은 불가 범위)" 3 "FORBID"

# revert — 원장 착지 L 의 정확한 역 diff 만
mk l1 "$M1" 'echo land > design/landed.md'; git -C "$W" push -q origin l1:main; git -C "$W" fetch -q origin; L="$SHA"
printf 'x\t%s\t5\tdocs\tda\t%s\tgit revert --no-edit %s\n' "p" "$L" "$L" > "$LEDGER"
git -C "$W" checkout -q -B r1 origin/main; git -C "$W" revert --no-edit "$L" >/dev/null 2>&1; R="$(sha "$W" HEAD)"
cls "$R"; want "원장 착지의 git revert 커밋 → CLASS revert(삭제여도 불가 범위 대조 전에 판정)" 0 "CLASS revert"
mk r2 origin/main 'echo n > design/other.py'; git -C "$W" commit -q --amend -m "Revert \"l1\"" -m "This reverts commit $L."; SHA="$(sha "$W" HEAD)"
cls "$SHA"; want "메시지만 Revert(역 diff 아님) → code" 0 "CLASS code"
printf 'x\t%s\t5\tdocs\tda\t\t\n' "p" > "$LEDGER"; cls "$R"; want "원장 착지 칸이 비면 revert 아님 → FORBID(삭제)" 3 "FORBID kind=delete 상태 D"
printf 'x\t%s\t5\tdocs\tda\t%s\tgit revert --no-edit %s\n' "p" "$L" "$L" > "$LEDGER"

# 오류는 닫힌 쪽
cls "abc"; want "40hex 아님 → ERROR rc1" 1 "ERROR"
cls "0000000000000000000000000000000000000000"; want "없는 sha → ERROR rc1" 1 "ERROR"
out="$(python3 "$CLS" classify "$R" --repo "$W" --scope X1 2>&1)"; rc=$?; want "scope 꼴 오류 → ERROR rc1" 1 "ERROR"
out="$(python3 "$CLS" classify "$R" --repo "$T/none" --scope S1 2>&1)"; rc=$?; want "저장소 없음 → ERROR rc1" 1 "ERROR"
out="$(python3 "$CLS" 2>&1)"; rc=$?; want "인자 없음 → ERROR rc1" 1 "ERROR"

# check-revert
chk() { out="$(python3 "$CLS" check-revert --repo "$W" --scope "${1:-S1}" 2>&1)"; rc=$?; }
chk; want "되돌림 없음 → OK rc0" 0 "OK"
chk S9; want "원장 없는 scope → OK rc0" 0 "OK"
git -C "$W" push -q origin r1:main; git -C "$W" fetch -q origin
chk; want "main 에 This reverts commit L → REVERTED rc4" 4 "REVERTED $L by $R"

# r466 ⓗ~ⓙ·학습 — 카드 이동 = docs · 적용 기록 있는 새 sql = docs · 팩 분류표 · 학습된 종류 키(secret 제외)
clsx() { out="$(python3 "$CLS" classify "$@" --repo "$W" --scope S1 2>&1)"; rc=$?; }
KT="$HERE/../kit/fable-team/templates"; PT="$KT/scope-classes-pack.tsv"; DT="$T/ddl.tsv"
printf -- '-\t%s\ndesign/ledger.md\t%s\n' '{sql}.*applied:?\s*(판정\s*)?[0-9]+' '{sql}.*applied:?\s*(판정\s*)?[0-9]+' > "$DT"
git -C "$W" checkout -q -B c0 origin/main; mkdir -p "$W/design/idx/대기" "$W/design/idx/진행"
for i in 1 2 3 4; do seq 1 40 | sed "s/^/card $i line /" > "$W/design/idx/대기/c$i.md"; done
echo "- 005_w.sql applied: 판정 77" > "$W/design/ledger.md"; cm "$W" c0; C0="$(sha "$W" HEAD)"
echo m2 > "$W/m2.txt"; cm "$W" m2; git -C "$W" push -q origin c0:main; git -C "$W" fetch -q origin   # main = C0 위 한 칸 → C0 가지 = docs(ff 아님)
mk() { local br="$1" from="$2"; shift 2; git -C "$W" checkout -q -B "$br" "$from"; ( cd "$W" && mkdir -p design/idx/진행 && eval "$*" ); cm "$W" "$br"; SHA="$(sha "$W" HEAD)"; }   # 빈 폴더(진행/)는 가지 전환에 사라진다
mk h1 "$C0" 'for i in 1 2 3; do git mv design/idx/대기/c$i.md design/idx/진행/; done'; cls "$SHA"; want "ⓗ 카드 3장 대기→진행 이동(내용 동일) → CLASS docs" 0 "CLASS docs"
mk h2 "$C0" 'git mv design/idx/대기/c1.md design/idx/진행/; echo more >> design/idx/진행/c1.md'; cls "$SHA"; want "ⓗ 이동 + 내용 바뀜 → FORBID move-changed" 3 "FORBID kind=move-changed 상태 R"
mk h3 "$C0" 'git mv design/idx/대기/c1.md design/idx/진행/c9.md'; cls "$SHA"; want "ⓗ 이동 + 이름 바뀜 → FORBID rename" 3 "FORBID kind=rename"
mk h4 "$C0" 'git mv design/idx/대기/c1.md design/idx/진행/; echo n > design/n.py'; cls "$SHA"; want "ⓗ 이동 + 코드 → code" 0 "CLASS code"
mk i1 "$C0" 'mkdir -p db/migrations; echo "create table t();" > db/migrations/002_x.sql; echo "- 002_x.sql applied: 판정 1234" > design/ddl-log.md'
clsx "$SHA" --ddl-records "$DT"; want "ⓘ 새 sql + 같은 PR 적용 기록 줄 → CLASS docs" 0 "CLASS docs"
cls "$SHA"; want "ⓘ 기록표 없음(--ddl-records 미지정) → FORBID ddl-no-record" 3 "FORBID kind=ddl-no-record"
mk i2 "$C0" 'mkdir -p db/migrations; echo "create table t();" > db/migrations/003_y.sql'; clsx "$SHA" --ddl-records "$DT"; want "ⓘ 기록 없음 → FORBID ddl-no-record" 3 "FORBID kind=ddl-no-record DDL"
mk i3 "$C0" 'mkdir -p db/migrations; echo "create table w();" > db/migrations/005_w.sql'; clsx "$SHA" --ddl-records "$DT"; want "ⓘ 원장(design/ledger.md) 적용 기록 줄 → CLASS docs" 0 "CLASS docs"
mk i4 "$C0" 'mkdir -p db/migrations; echo "create table w();" > db/migrations/005_w.sql; echo n > design/n.py'; clsx "$SHA" --ddl-records "$DT"; want "ⓘ 기록 있어도 그 밖 코드 변경 → FORBID ddl" 3 "FORBID kind=ddl DDL 기록 PR"
mk i5 "$C0" 'mkdir -p db/migrations; echo "create table t();" > db/migrations/006_v.sql; echo "- 002_x.sql applied: 판정 1234" > design/ddl-log.md'; clsx "$SHA" --ddl-records "$DT"; want "ⓘ 다른 sql 이름의 기록 → FORBID" 3 "FORBID kind=ddl-no-record"
python3 "$CLS" classify "$SHA" --repo "$W" --scope S1 --ddl-records "$KT/scope-ddl-record.tsv" >/dev/null 2>&1; [ $? = 3 ]; ck "ⓘ 키트 기록표 파일 해석 OK(정규식 오류 0)" $?
mk j1 "$C0" 'mkdir -p feature-pack/fable-team/harness/kit/fable-team/bin; echo x > feature-pack/fable-team/harness/kit/fable-team/bin/ft-x.sh'; clsx "$SHA" --table "$PT"; want "ⓙ 팩 표: kit 1파일 → CLASS code" 0 "CLASS code"
mk j2 "$C0" 'mkdir -p feature-pack/fable-team/harness/evidence/r1; echo c > feature-pack/fable-team/CHANGES.md; echo e > feature-pack/fable-team/harness/evidence/r1/a.txt'; clsx "$SHA" --table "$PT"; want "ⓙ 팩 표: CHANGES·evidence → CLASS docs" 0 "CLASS docs"
mk j3 "$C0" 'echo h > hooks.txt'; clsx "$SHA" --table "$PT"; want "ⓙ 팩 표: 하네스 밖 경로 → FORBID repo-outside" 3 "FORBID kind=repo-outside"
printf 'bad line\n' > "$T/bad.tsv"; clsx "$SHA" --table "$T/bad.tsv"; want "ⓙ 분류표 꼴 틀림 → ERROR rc1" 1 "ERROR 분류표"
mk k1 "$C0" 'mkdir -p .claude/rules; echo r > .claude/rules/y.md'; cls "$SHA"; want "ⓚ 학습 없음 → FORBID global-rule" 3 "FORBID kind=global-rule"
clsx "$SHA" --learned global-rule; want "ⓚ 학습된 종류 → CLASS docs kind=… learned" 0 "CLASS docs kind=global-rule learned"
mk k2 "$C0" 'mkdir -p .claude/rules; echo r > .claude/rules/y.md; echo "{}" > package.json'; clsx "$SHA" --learned global-rule; want "ⓚ 다른 종류(deps) 섞임 → FORBID deps" 3 "FORBID kind=deps"
mk k3 "$C0" 'echo "-----BEGIN RSA PRIVATE KEY-----" > design/leak3.md'; clsx "$SHA" --learned secret; want "ⓚ secret 은 학습 불가 → FORBID secret" 3 "FORBID kind=secret"
clsx "$SHA" --learned 'Bad Key'; want "ⓚ --learned 키 꼴 틀림 → ERROR" 1 "ERROR"
! grep -nE '\b(600|300)\b' "$BIN/autonomy_scope_rules.py" "$CLS" >/dev/null; ck "600/300 상한 0" $?

# ft-merge-land 착지 뒤 원장 기록 — gh 는 스텁
export FT_GH="$T/gh-stub" FT_GH_WRITE="$T/gh-stub" STUB_LOG="$T/gh.log" STUB_JSON="$T/pr.json"
printf '#!/bin/bash\n[ "$1 $2" = "pr view" ] && { cat "$STUB_JSON"; exit 0; }\necho "$*" >> "$STUB_LOG"\n' > "$T/gh-stub"; chmod +x "$T/gh-stub"
mkpr() {  # mkpr <번호> — origin/main 위 PR head → origin refs/pull/N/head · 스텁 JSON
  git -C "$W" checkout -q -B "pr$1" origin/main; echo "pr$1" > "$W/pr$1.txt"; cm "$W" "pr $1"; git -C "$W" push -q origin "pr$1:refs/pull/$1/head"; PRSHA="$(sha "$W" HEAD)"
  python3 -c 'import json,sys;print(json.dumps({"headRefOid":sys.argv[1],"title":"t "+sys.argv[2],"body":"b","state":"OPEN","baseRefName":"main"}))' "$PRSHA" "$1" > "$STUB_JSON"
}
land() { apv "$@"; out="$(bash "$LAND" "$@" --repo "$W" 2>&1)"; rc=$?; }
row() { printf 'T0\t%s\t%s\tdocs\tda\t%s\t%s\n' "$1" "$2" "$3" "$4"; }
git -C "$W" fetch -q origin; mkpr 31; P31="$PRSHA"; P32=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; git -C "$W" fetch -q origin   # P32 = 이 PR 이 아닌 «다른 승인 sha» 행
{ row "$P31" 31 "" ""; row "$P32" 32 "" ""; row "$L" 5 "$L" "keep"; } > "$LEDGER"
S2L="$T/state/autonomy-scope/S2.ledger.tsv"; row "$P31" 99 "" "" > "$S2L"   # DA⑥ H3: 같은 sha 의 빈 행이 S2 원장에도 — log 의 마지막 scope-use 가 S1 이면 S1 만 채운다
printf 'scope-use S2 %s docs 1\nscope-use S1 %s docs 2\n' "$P31" "$P31" > "$T/state/autonomy.log"
land 31 --approve-sha "$P31"; Q1="$(git -C "$ORIGIN" rev-parse main)"
[ "$(cut -f6,7 "$S2L")" = "$(printf '\t')" ]; ck "같은 sha 빈 행이 다른 원장(S2)에도 있어도 log 마지막 scope-use=S1 → S2 불변" $?
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]]; ck "원장 행 있음 → 착지 rc0 · LANDED" $?
[ "$(awk -F'\t' -v s="$P31" '$2==s{print $6}' "$LEDGER")" = "$Q1" ]; ck "원장 착지 sha 칸 = 착지 sha" $?
[ "$(awk -F'\t' -v s="$P31" '$2==s{print $7}' "$LEDGER")" = "git revert --no-edit $Q1" ]; ck "원장 되돌림 명령 칸 = git revert --no-edit <착지 sha>" $?
[ "$(awk -F'\t' -v s="$P32" '$2==s{print $6 $7}' "$LEDGER")" = "" ] && [ "$(awk -F'\t' -v s="$L" '$2==s{print $7}' "$LEDGER")" = "keep" ]; ck "다른 승인 sha 행·이미 찬 행은 불변" $?
[ "$(wc -l < "$LEDGER" | tr -d ' ')" = 3 ] && [ -z "$(ls "$T/state/autonomy-scope" | grep -v 'ledger.tsv$')" ]; ck "행 수 불변 · 임시 파일 잔재 0" $?
[[ "$out" != *WARN* ]]; ck "정상이면 WARN 0" $?

git -C "$W" fetch -q origin; mkpr 33; P33="$PRSHA"; git -C "$W" fetch -q origin
rm -rf "$T/state/autonomy-scope"; printf 'scope-use S1 %s docs 3\n' "$P33" >> "$T/state/autonomy.log"; land 33 --approve-sha "$P33"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [[ "$out" != *WARN* ]] && [[ "$out" != *원장* ]]; ck "원장 없음 → 출력 변화 0 · 착지 rc0" $?

git -C "$W" fetch -q origin; mkpr 34; P34="$PRSHA"; git -C "$W" fetch -q origin
printf 'scope-use S1 %s docs 4\n' "$P34" >> "$T/state/autonomy.log"
mkdir -p "$T/state/autonomy-scope"; row "$P34" 34 "" "" > "$LEDGER"; chmod 555 "$T/state/autonomy-scope"
land 34 --approve-sha "$P34"; chmod 755 "$T/state/autonomy-scope"
[ "$rc" = 0 ] && [[ "$out" == LANDED* ]] && [ "$(printf '%s\n' "$out" | grep -c '^WARN 대리 승인 원장 기록 실패')" = 1 ] && [ "$(awk -F'\t' '{print $6}' "$LEDGER")" = "" ]; ck "원장 쓰기 실패 → WARN 1줄 · 착지 rc0 · 행 불변" $?

[ "$(git -C "$W" config --get core.bare)" != true ]; ck "core.bare 오염 0" $?
cmp -s "$BIN/ft-merge-land.sh" "$HERE/../../harness/kit/fable-team/bin/ft-merge-land.sh" && cmp -s "$CLS" "$HERE/../../harness/kit/fable-team/bin/autonomy_scope_classify.py"; ck "키트 사본 == scripts/fable-team-bin (cmp0)" $?
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILED $fail"; exit 1; }
