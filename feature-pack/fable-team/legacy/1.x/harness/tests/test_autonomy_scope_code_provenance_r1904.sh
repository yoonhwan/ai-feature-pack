#!/usr/bin/env bash
# test_autonomy_scope_code_provenance_r1904.sh — 범위 승인 종류 code 의 카드 «세트:» 줄 출처 = 원장(ROOT git-common-dir) 고정 ref origin/ops/main-base 커밋 판뿐 (r1904 · DA 설계 APPROVE #298671)
# 실사건: /tmp 카드 사본의 세트 줄을 미승인 head 로 바꿔 scope-approve --card → TRY-OK + 승인 파일. 반례 ①~⑤ + DA 계약(다른 worktree · checkout HEAD 만 커밋) · 실 원장·승인 파일 0(임시 git)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/autonomy_scope_setup.sh"

R="$T/r"; OR="$T/origin.git"; export STUB_OUT="CLASS code"
G() { git -C "$R" "$@"; }; cm() { G add -A && G commit -q -m "$1"; }; hd() { G rev-parse HEAD; }
git init -q --bare -b main "$OR"; git clone -q "$OR" "$R" 2>/dev/null; G config user.name t; G config user.email t@t
echo base > "$R/README.md"; cm base; G push -q origin HEAD:main; G fetch -q origin
G checkout -q -B nano origin/main; mkdir -p "$R/src"; echo 'x = 1' > "$R/src/x.py"; cm code1; A="$(hd)"
G checkout -q -B main origin/main; echo m > "$R/b.txt"; cm main1; G push -q origin main; G fetch -q origin
G checkout -q nano; G merge -q --no-edit origin/main >/dev/null 2>&1; SM="$(hd)"                       # SM = A 위 main 병합만(EQUIV)
H=design/harness/indices/진행; . "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/card_ref_fixture.sh"
body() { printf '# 카드\n## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$1"; }
pub() {  # <카드 이름> <세트 sha> → 원장 고정 ref origin/ops/main-base 에 팀 카드(H/<이름>) 커밋(작업 브랜치·HEAD 무변경 · fetch 0 꼴 · r1951 fixture = 팀 카드 꼴 + 표 harness 행)
  local f; f="$(fx_card_path "$R" "$1")"; body "$2" > "$f"; fx_card_pub "$R" "$f" "$(G rev-parse -q --verify refs/remotes/origin/ops/main-base)"; }
ar() { FT_ROOT="$R" a "$@"; }
nap() { [ ! -e "$AP/$1" ]; }
fresh; grant --for 2h --max 9 --classes docs,ff,revert,code --code-max 9 >/dev/null

# ① /tmp 사본(원장 밖) · 세트 = head → REJECT «원장 밖» · 승인 파일 0
body "$SM" > "$T/copy.md"
run ar scope-approve "$SM" --card "$T/copy.md"; [ $rc = 2 ] && has '카드 출처 아님\(원장 밖 경로\)' && nap "$SM"; ck "① /tmp 카드 사본(세트=head) → SCOPE-REJECT 원장 밖 · 승인 0" $?
# ①' /tmp 가짜 git 리포 안 커밋된 카드 → common-dir 다름 → REJECT «원장 밖»
F="$T/fake"; git init -q -b main "$F"; mkdir -p "$F/cards"; body "$SM" > "$F/cards/c.md"
git -C "$F" add -A; git -C "$F" -c user.name=t -c user.email=t@t commit -q -m c; git -C "$F" update-ref refs/remotes/origin/ops/main-base HEAD
run ar scope-approve "$SM" --card "$F/cards/c.md"; [ $rc = 2 ] && has '카드 출처 아님\(원장 밖 경로\)' && nap "$SM"; ck "①' 가짜 리포 안 커밋된 카드 → SCOPE-REJECT 원장 밖 · 승인 0" $?
# ② 원장 안 커밋된 카드 · 작업 파일만 세트 줄 바꿈 → REJECT «손 수정»
pub c2.md "$A"; body "$SM" > "$R/$H/c2.md"
run ar scope-approve "$SM" --card "$R/$H/c2.md"; [ $rc = 2 ] && has '카드 손 수정\(커밋 판과 다름' && nap "$SM"; ck "② 작업 파일만 세트=head 로 고침 → SCOPE-REJECT 손 수정 · 승인 0" $?
# ⑤ 추적 안 된 새 카드(원장 안 · 고정 ref 에 없음) → REJECT «커밋 판 없음»
body "$SM" > "$R/$H/new.md"
run ar scope-approve "$SM" --card "$R/$H/new.md"; [ $rc = 2 ] && has '카드 출처 아님\(커밋 판 없음' && nap "$SM"; ck "⑤ 추적 안 된 새 카드 → SCOPE-REJECT 커밋 판 없음 · 승인 0" $?
# DA: checkout HEAD 에만 새 세트 커밋(고정 ref 는 옛 판) → REJECT
rm -f "$R/$H/c2.md"; G checkout -q -B cardwork origin/ops/main-base; body "$SM" > "$R/$H/c2.md"; cm head-only
run ar scope-approve "$SM" --card "$R/$H/c2.md"; [ $rc = 2 ] && has '카드 손 수정' && nap "$SM"; ck "DA checkout HEAD 에만 세트 커밋 → SCOPE-REJECT · 승인 0" $?
G checkout -q nano
[ ! -d "$AP" ] || [ -z "$(ls -A "$AP")" ]; ck "거절 전부 승인 파일 0" $?
# ③ 원장 안 커밋된 카드 · 세트 = head · rc=0 → 통과(승인 줄 1)
pub c3.md "$A"; body "$A" > "$R/$H/c3.md"
run ar scope-approve "$A" --card "$R/$H/c3.md"; [ $rc = 0 ] && has "^SCOPE-OK $A class=code " && [ "$(cat "$AP/$A")" = "approve-merge $A A1 $T0" ]; ck "③ 커밋된 카드 세트=head → SCOPE-OK · 승인 줄 1" $?
# ④ 원장 안 커밋된 카드 · 세트 ≠ head · EQUIV(main 병합뿐) → 통과
run ar scope-approve "$SM" --card "$R/$H/c3.md"; [ $rc = 0 ] && has "^SCOPE-OK $SM class=code .* equiv=$A\$"; ck "④ 세트≠head · EQUIV → SCOPE-OK equiv" $?
# DA: 같은 원장의 다른 worktree 안 카드 → common-dir 같음 → 통과
G checkout -q -B nano3 origin/main; mkdir -p "$R/src"; echo 'w = 3' > "$R/src/w.py"; cm code3; B="$(hd)"; G checkout -q nano; pub c4.md "$B"
G worktree add -q --detach "$T/wt" origin/ops/main-base 2>/dev/null
run ar scope-approve "$B" --card "$T/wt/$H/c4.md"; [ $rc = 0 ] && has "^SCOPE-OK $B class=code "; ck "DA 같은 원장 다른 worktree 카드 → SCOPE-OK" $?

echo "fail=$fail"; [ "$fail" = 0 ]
