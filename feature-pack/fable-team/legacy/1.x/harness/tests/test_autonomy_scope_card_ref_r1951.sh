#!/usr/bin/env bash
# test_autonomy_scope_card_ref_r1951.sh — 범위 승인 code 의 카드 커밋 판 ref = 원장 루트 카드 루트 표(directive-roots.tsv)의 그 팀 행(없으면 «*» 행) (r1951 · DA 설계 APPROVE #301035)
# 실사건: cfo 카드(origin/main 에만)가 «커밋 판 없음 · origin/ops/main-base:…» 로 REJECT. 반례 ①~⑧ · 실 원장·승인 파일 0(임시 git · 가짜 origin ref)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"

R="$T/r"; OR="$T/origin.git"; export STUB_OUT="CLASS code"
G() { git -C "$R" "$@"; }; cm() { G add -A && G commit -q -m "$1"; }; hd() { G rev-parse HEAD; }
git init -q --bare -b main "$OR"; git clone -q "$OR" "$R" 2>/dev/null; G config user.name t; G config user.email t@t
echo base > "$R/README.md"; cm base; G push -q origin HEAD:main; G fetch -q origin
G checkout -q -B nano origin/main; mkdir -p "$R/src"; echo 'x = 1' > "$R/src/x.py"; cm code1; A="$(hd)"
G checkout -q -B nano2 origin/main; mkdir -p "$R/src"; echo 'y = 2' > "$R/src/y.py"; cm code2; B="$(hd)"
G checkout -q -B main origin/main; echo m > "$R/b.txt"; cm main1; G push -q origin main; G fetch -q origin
G checkout -q nano; G merge -q --no-edit origin/main >/dev/null 2>&1; SM="$(hd)"                       # SM = A 위 main 병합만(EQUIV)
G update-ref refs/remotes/origin/ops/main-base origin/main
body() { printf '# 카드\n## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$1"; }
pub() {  # <ref 이름(origin/…)> <원장 상대경로> <세트 sha> → 그 ref 위에 카드 1장 커밋(작업 브랜치·HEAD 무변경 · fetch 0 꼴) + 같은 작업 파일
  local b t; b="$(body "$3" | G hash-object -w --stdin)"
  GIT_INDEX_FILE="$T/ix" G read-tree "$1"; GIT_INDEX_FILE="$T/ix" G update-index --add --cacheinfo "100644,$b,$2"
  t="$(GIT_INDEX_FILE="$T/ix" G write-tree)"; G update-ref "refs/remotes/$1" "$(G commit-tree "$t" -p "$1" -m card)"
  mkdir -p "$(dirname -- "$R/$2")"; body "$3" > "$R/$2"; }
TSV="$R/.fable-team/state/directive-roots.tsv"; mkdir -p "${TSV%/*}"
tsv() { printf '*\t.\torigin/main\tdesign/teams/*/indices\nharness\t.\torigin/ops/main-base\tdesign/harness/indices\n' > "$TSV"; }
ar() { FT_ROOT="$R" a "$@"; }
nap() { [ ! -e "$AP/$1" ]; }
tsv; fresh; grant --for 2h --max 9 --classes docs,ff,revert,code --code-max 9 >/dev/null
CX=design/teams/cfo/indices/진행/x.md; CY=design/teams/cfo/indices/진행/y.md; HZ=design/harness/indices/진행/z.md
pub origin/main "$CX" "$A"; pub origin/ops/main-base "$CY" "$B"; pub origin/ops/main-base "$HZ" "$B"

# ③ cfo 카드가 origin/ops/main-base 에만(origin/main 에 없음) → 팀 행(«*»=origin/main)이 이긴다 → REJECT 커밋 판 없음
run ar scope-approve "$B" --card "$R/$CY"; [ "$rc" = 2 ] && has '카드 출처 아님\(커밋 판 없음 · origin/main:design/teams/cfo/' && nap "$B"; ck "③ cfo 카드 ops/main-base 에만 → SCOPE-REJECT 커밋 판 없음(origin/main) · 승인 0" $?
# ④ cfo 카드 작업 파일이 origin/main 판과 다름 → REJECT 손 수정
body "$B" > "$R/$CX"; run ar scope-approve "$B" --card "$R/$CX"; [ "$rc" = 2 ] && has '카드 손 수정\(커밋 판과 다름 · origin/main:' && nap "$B"; ck "④ cfo 작업 파일 ≠ origin/main 판 → SCOPE-REJECT 손 수정 · 승인 0" $?
body "$A" > "$R/$CX"
# ⑤ 표 파일 없음 → REJECT 판정 불가(origin/main 으로 조용히 바꾸지 않음)
rm -f "$TSV"; run ar scope-approve "$A" --card "$R/$CX"; [ "$rc" = 2 ] && has '카드 출처 판정 불가' && nap "$A"; ck "⑤ 표 없음 → SCOPE-REJECT 판정 불가 · 승인 0" $?
# ⑥ 표 행 ref 가 리포에 없음 → REJECT 판정 불가
printf '*\t.\torigin/nope\tdesign/teams/*/indices\n' > "$TSV"; run ar scope-approve "$A" --card "$R/$CX"; [ "$rc" = 2 ] && has '카드 출처 판정 불가.*origin/nope' && nap "$A"; ck "⑥ 표 행 ref 없음 → SCOPE-REJECT 판정 불가 · 승인 0" $?
tsv
# ⑧ 팀 꼴 아닌 경로(원장 안 docs/x.md · 커밋돼 있어도) → REJECT 팀 꼴 아님
pub origin/main docs/x.md "$A"; run ar scope-approve "$A" --card "$R/docs/x.md"; [ "$rc" = 2 ] && has '카드 출처 판정 불가\(팀 꼴 아님' && nap "$A"; ck "⑧ docs/x.md → SCOPE-REJECT 팀 꼴 아님 · 승인 0" $?
[ ! -d "$AP" ] || [ -z "$(ls -A "$AP")" ]; ck "거절 전부 승인 파일 0" $?
# ① cfo 카드 origin/main 에만 + 표 «*»=origin/main → 통과(CODE_A = 세트 sha)
run ar scope-approve "$A" --card "$R/$CX"; [ "$rc" = 0 ] && has "^SCOPE-OK $A class=code " && [ "$(cat "$AP/$A")" = "approve-merge $A A1 $T0" ]; ck "① cfo 카드(origin/main) → SCOPE-OK · 승인 줄 1" $?
# ⑦ FT_CARD_REF=origin/ops/main-base 를 줘도 ① 결과 그대로(env 무시) · 세트≠head EQUIV
FT_CARD_REF=origin/ops/main-base run ar scope-approve "$SM" --card "$R/$CX"; [ "$rc" = 0 ] && has "^SCOPE-OK $SM class=code .* equiv=$A\$"; ck "⑦ FT_CARD_REF 줘도 cfo 카드 → SCOPE-OK equiv(env 무시)" $?
# ② harness 카드 origin/ops/main-base 에만 + 표 harness 행 → 통과(r1904 회귀)
run ar scope-approve "$B" --card "$R/$HZ"; [ "$rc" = 0 ] && has "^SCOPE-OK $B class=code "; ck "② harness 카드(ops/main-base) → SCOPE-OK" $?

echo "fail=$fail"; [ "$fail" = 0 ]
