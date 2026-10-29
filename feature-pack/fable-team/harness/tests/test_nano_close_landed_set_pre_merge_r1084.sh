#!/usr/bin/env bash
# test_nano_close_landed_set_pre_merge_r1084.sh — r1084: --landed-pr 의 «세트 대조» 에 «세트 S ⊂ 끝줄 head X · S..X 첫 부모 = main 병합뿐 · 자기 변경(patch-id) 같음» 칸을 더한다.
#   사건(arch#174 실측 · ops 나노 4324·4338·4302): 카드 세트 = 승인 직전 head S. 착지 도구가 PR 가지에 main 을 병합해 끝줄 head X·PR head H 가 됐고
#     산출은 바이트까지 같다(patch-id S = X). 세 칸(== H · == squash · r1019 판정기) 중 «S 와 X 가 main 병합만 다르다» 를 보는 칸이 없어 전부 REJECT = 나노가 안 닫힌다.
#   계약 ① S→X main 병합뿐 ∧ patch-id 같음 → LANDED-PR-OK «카드 세트 <9> → 끝줄 head <9> = main 병합 N개뿐» · 판정기 호출 0 · R1(병합 1·2)
#   계약 ② 일반 커밋(R2) · 손댄 병합(R3) · 조상 아님(R4) → REJECT(지금 판정기 경로로 내려간다)
#   계약 ③ 착지 안 됨(R5 — landed 단계에서 REJECT · 새 칸 git 호출 0) · 앞 칸 통과는 동작 불변(R6 «== 카드 세트»·«= squash» · 새 칸 호출 0)
#   계약 ④ bin·kit 같은 줄(cmp0)
# 임시 git 리포(ROOT + bare REMOTE) + 가짜 tmux·gh·git(PATH 앞) + 가짜 판정기(로그만 남기고 rc1)만 쓴다 —
#   실 리포·seats·tmux·gh(네트워크) 0 · 고정 sleep 0 · 자기 재호출 0 · ulimit -u + timeout 70.
# 변이 3: ⓐ «새 칸 끔» → R1 이 REJECT 로 오판 · ⓑ «S..X 일반 커밋 검사 끔» → R2 통과 · ⓒ «patch-id 검사 끔» → R3 통과 (셋 다 변이 FAIL = 이 시험이 잡는다)
# 짝: bin == kit cmp0 · /bin/bash 3.2 -n · 회귀(r1083/r1074/r1058)는 이 파일 밖 — 카드 완료 조건에서 함께 rc0 확인.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:600}";; *) ok "$3";; esac; }

echo "== 짝 cmp · bash -n (/bin/bash 3.2 포함)"
cmp -s "$HERE/../../harness/bin/ft-nano-close.sh" "$SRC/ft-nano-close.sh" && ok "cmp bin == kit" || bad "cmp 다름"
bash -n "$SRC/ft-nano-close.sh" && ok "bash -n" || bad "bash -n"
/bin/bash -n "$SRC/ft-nano-close.sh" && ok "/bin/bash 3.2 -n" || bad "/bin/bash 3.2 -n"

mkdir -p "$T/bin" "$T/fake"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"   # r1113 자식 정리 = 같은 bin 스텁(실 프로세스 0)
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-nano-superseded-check.sh" \
   "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-team-lib.sh" "$SRC/ft-card-target-lib.sh" "$SRC/ft_git_capped.py" "$SRC/ft_teamset.py" \
   "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" \
   "$SRC/ft-approval-equiv.sh" "$SRC/ft_approval_equiv.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
# 계약 ① «판정기 호출 0» 을 재려면 판정기가 «세는» 존재여야 한다 — 로그만 남기고 rc1(진짜 판정기는 squash 착지 뒤 언제나 NOT-EQUIV 라 rc 로는 못 가른다).
cat > "$T/bin/ft-approval-equiv.sh" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_EQ_LOG:-}" ] && echo "equiv $*" >> "$FAKE_EQ_LOG"
echo "NOT-EQUIV (가짜 판정기) 세트 $1 ≠ head $2"
exit 1
EOF
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
cat > "$T/fake/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH_LOG"
cat "$FAKE_GH_JSON"
EOF
cat > "$T/fake/git" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_GIT_LOG:-}" ] && echo "$*" >> "$FAKE_GIT_LOG"
exec /usr/bin/git "$@"
EOF
chmod +x "$T/bin/"* "$T/fake/"*

BYZ_URL='https://github.com/lptest/byz.git'
ROOT="$T/repo"; mkdir -p "$ROOT"
git -C "$ROOT" init -q -b main && git -C "$ROOT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$ROOT" remote add origin "$BYZ_URL"
git -C "$ROOT" config "url.$T/remote.git.insteadOf" "$BYZ_URL"   # 식별자 = 설정값(github 꼴) · 전송 = 로컬 bare 리포(네트워크 0)
mkdir -p "$ROOT/.fable-team" "$ROOT/design/ops/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
REMOTE="$T/remote.git"; git init -q --bare "$REMOTE"; git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
git -C "$ROOT" push -q origin main

SEAT='byz-ops-nano-premrg#0'; BR='nano/premrg'; NW="$ROOT/.worktrees/v65-premrg"
CARD_REL='design/ops/indices/진행/premrg.md'; CARD="$ROOT/$CARD_REL"
git -C "$ROOT" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
LEDGER="$T/ledger.md"; EQ="$T/eqlog"; GITLOG="$T/gitlog"
INIT="$(git -C "$ROOT" rev-parse main)"

# main 쪽 진행 = plumbing(commit-tree) — ROOT 의 checkout 을 건드리지 않는다 · push 로 가짜 origin/main 을 만든다
main_commit() {  # main_commit <부모 sha> <메시지> [<경로> <내용>] [<트리 sha>] → 새 sha(stdout)
  local base="$1" msg="$2" path="${3:-}" body="${4:-}" fix="${5:-}" tree blob
  tree="${fix:-$(git -C "$ROOT" rev-parse "$base^{tree}")}"
  if [ -n "$path" ]; then
    blob="$(printf '%s\n' "$body" | git -C "$ROOT" hash-object -w --stdin)"
    GIT_INDEX_FILE="$T/idx" git -C "$ROOT" read-tree "$tree"
    GIT_INDEX_FILE="$T/idx" git -C "$ROOT" update-index --add --cacheinfo "100644,$blob,$path"
    tree="$(GIT_INDEX_FILE="$T/idx" git -C "$ROOT" write-tree)"; rm -f "$T/idx"
  fi
  git -C "$ROOT" -c user.email=t@t -c user.name=t commit-tree "$tree" -p "$base" -m "$msg"
}
pub() { git -C "$ROOT" push -q --force "$REMOTE" "$1:refs/heads/main" && git -C "$ROOT" fetch -q origin main; }
main_add() { pub "$(main_commit "$(git -C "$ROOT" rev-parse refs/remotes/origin/main)" "$1" "$2" "$3")"; }
pr_reset() {  # NW 를 INIT 으로 되돌리고 A(승인 직전 head = 카드 세트 S · pr/f.txt) 를 만든다 · 결과 = $A
  git -C "$NW" reset -q --hard "$INIT"; git -C "$NW" clean -qfd
  mkdir -p "$NW/pr" && printf 'f1\n' > "$NW/pr/f.txt"
  git -C "$NW" add pr/f.txt && git -C "$NW" commit -q -m "work f"
  A="$(git -C "$NW" rev-parse HEAD)"
}
merge_main() { git -C "$NW" fetch -q origin main; git -C "$NW" merge -q --no-ff -m "merge main $1" origin/main; }
sq_head() {  # sq_head <끝줄> <커밋 sha = 그 트리를 쓴다> → main 에 squash 커밋을 얹는다
  local msg="$1" c
  c="$(main_commit "$(git -C "$ROOT" rev-parse refs/remotes/origin/main)" "squash 착지

$msg" "" "" "$(git -C "$ROOT" rev-parse "$2^{tree}")")"; pub "$c"; echo "$c"
}
sx_graph() {  # sx_graph <병합 수 1|2> — A(세트) → main 병합 N회 → X(끝줄 head · PR head) → 그 트리로 squash · 결과 = $X
  pr_reset
  main_add other1 g1.txt 1; merge_main 1
  if [ "${1:-1}" = 2 ]; then main_add other2 g2.txt 2; merge_main 2; fi
  X="$(git -C "$NW" rev-parse HEAD)"
  SQ="$(sq_head "PR #363 (head $X)" "$X")"
}
card_body() {  # card_body [<세트 sha>] — 기본 = A
  printf '# 인덱스: premrg\n## 상태\n- 2026-10-29 진행\n- 세트: %s · 시험: bash t.sh (4 passed) rc=0 · 이슈: 0\n- 착지: PR #363 squash\n\n## 다음 절\n- 세트: %s (절 밖 — 집으면 안 됨)\n' "${1:-${A:-$INIT}}" "${1:-${A:-$INIT}}"
}
setup() {  # setup <MERGED|CLOSED> — main·명부·카드·gh·원장·로그를 «정상(세션 없음 · 미커밋 0)» 으로 리셋(origin/main = INIT)
  git -C "$ROOT" push -q --force "$REMOTE" "$INIT:refs/heads/main" && git -C "$ROOT" fetch -q origin main
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$ROOT/.fable-team/seats-ops.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$T/ghlog"; : > "$LEDGER"; : > "$GITLOG"; : > "$EQ"; rm -rf "$T/wtclean"
  card_body > "$CARD"
  printf '{"state":"%s","mergeCommit":null,"headRefOid":"%s"}\n' "$1" "$(git -C "$NW" rev-parse HEAD)" > "$T/gh.json"
}
gh_head() { printf '{"state":"CLOSED","mergeCommit":null,"headRefOid":"%s"}\n' "$1" > "$T/gh.json"; }
close() { ( cd "$ROOT" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FT_PACK_ROOT="$T/nopack" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" FAKE_GH_JSON="$T/gh.json" FAKE_GIT_LOG="$GITLOG" \
  FAKE_EQ_LOG="$EQ" \
  FT_NANO_PREFIX=byz-ops-nano- FT_SEATS_JSON="$ROOT/.fable-team/seats-ops.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
  bash "${CLOSE_BIN:-$T/bin/ft-nano-close.sh}" "$SEAT" --result "$T/result.md" --recv 1 "$@" 2>&1 ); }
untouched() {
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$ROOT/.fable-team/seats-ops.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 원장 행 0" || bad "$1: 원장 행 생김"
  git -C "$ROOT" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 그대로" || bad "$1: 브랜치 삭제"
}
closed_ok() {
  jq -e --arg s "$SEAT" 'has($s) | not' "$ROOT/.fable-team/seats-ops.json" >/dev/null && ok "  └ 명부에서 지움" || bad "$1: 명부에 남음"
  has "$(cat "$LEDGER")" "landed-pr=363" "  └ 원장 닫힘 행 landed-pr=363"
}
eqcnt() {  # eqcnt <0|1> <이름> — 가짜 판정기 호출 줄 수
  local n; n="$(grep -c . "$EQ" 2>/dev/null)"; [ -n "$n" ] || n=0
  [ "$n" -eq "$1" ] && ok "  └ 판정기 호출 $1줄" || bad "$2: 판정기 호출 ${n}줄(기대 $1) ← $(head -2 "$EQ")"
}
gitcnt() {  # gitcnt <패턴> <기대 수> <이름> — 가짜 git 이 기록한 호출 줄 수(새 칸이 git 을 부르긴 했나)
  local n; n="$(grep -c -- "$1" "$GITLOG" 2>/dev/null)"; [ -n "$n" ] || n=0
  [ "$n" -eq "$2" ] && ok "  └ git «$1» $2줄" || bad "$3: git «$1» ${n}줄(기대 $2)"
}
mutant() {  # mutant <old> <new> → $T/mutbin/ft-nano-close.sh
  rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin"
  python3 - "$T/mutbin/ft-nano-close.sh" "$@" <<'PY'
import sys
p = sys.argv[1]; pairs = sys.argv[2:]
s = open(p, encoding='utf-8').read()
for i in range(0, len(pairs), 2):
    old, new = pairs[i], pairs[i + 1]
    assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳: {old[:70]}"
    s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(s)
PY
}
mutpass() {  # mutpass <출력> <이름> <rc> — 변이가 «통과» 로 오판했는가(= 변이 FAIL · 시험이 잡는다)
  case "$1" in *"LANDED-PR-OK"*) ok "$2";; *) bad "$2 — 변이 안 먹음 rc=$3 ← $(printf '%s' "$1" | tail -3)";; esac
}
mutreject() {  # mutreject <출력> <이름> <rc> — 변이가 «거절» 로 오판했는가(= 변이 FAIL · 시험이 잡는다)
  if [ "$3" -eq 1 ]; then case "$1" in *"LANDED-PR-OK"*) bad "$2 — 변이 안 먹음(아직 통과) ← $(printf '%s' "$1" | tail -3)";; *) ok "$2";; esac
  else bad "$2 — 변이 안 먹음 rc=$3 ← $(printf '%s' "$1" | tail -3)"; fi
}

echo "== ⓐ 계약 ①·R1 실제 꼴 — 세트 S ⊂ 끝줄 head X · S..X main 병합 1개 · patch-id 같음 → LANDED-PR-OK «main 병합 1개뿐» · 판정기 0줄"
setup CLOSED; sx_graph 1; gh_head "$X"; card_body "$A" > "$CARD"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓐ rc=0" || bad "ⓐ rc=$rc ← ${out:0:900}"
has "$out" "LANDED-PR-OK #363" "  └ ⑥ 자리 = LANDED-PR-OK"
has "$out" "카드 세트 ${A:0:9} → 끝줄 head ${X:0:9} = main 병합 1개뿐 · 자기 변경 같음" "  └ 새 칸 문구 «세트 → 끝줄 head = main 병합 1개뿐 · 자기 변경 같음»"
hasnt "$out" "NOT-EQUIV" "  └ 판정기 사유 0(새 칸이 먼저 잡았다)"
eqcnt 0 "ⓐ"
gitcnt "patch-id --stable" 2 "ⓐ"
has "$out" "CLOSED-ABSENT $SEAT landed-pr=363" "  └ CLOSED-ABSENT <좌석> landed-pr=<N>"
closed_ok "ⓐ"

echo "== ⓑ 계약 ①·R1 main 을 2회 병합 — 같은 조건이면 «main 병합 2개뿐» · 판정기 0줄"
setup CLOSED; sx_graph 2; gh_head "$X"; card_body "$A" > "$CARD"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓑ rc=0" || bad "ⓑ rc=$rc ← ${out:0:900}"
has "$out" "카드 세트 ${A:0:9} → 끝줄 head ${X:0:9} = main 병합 2개뿐 · 자기 변경 같음" "  └ 병합 2개를 센다"
eqcnt 0 "ⓑ"
closed_ok "ⓑ"

echo "== ⓒ 계약 ②·R2 S..X 첫 부모에 일반 커밋 1개(내용 변화 0 = 빈 커밋 · ⓑ 만 잡는다) → REJECT(지금 판정기 문구)"
setup CLOSED
pr_reset
git -C "$NW" commit -q --allow-empty -m "승인 뒤 고침"
main_add other1 g1.txt 1; merge_main 1
X="$(git -C "$NW" rev-parse HEAD)"; SQ="$(sq_head "PR #363 (head $X)" "$X")"
gh_head "$X"; card_body "$A" > "$CARD"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && ok "ⓒ rc=1" || bad "ⓒ rc=$rc ← ${out:0:900}"
hasnt "$out" "LANDED-PR-OK" "  └ 통과 0"
has "$out" "«세트 + main 병합뿐» 도 아님" "  └ 지금 판정기 문구 유지"
has "$out" "NOT-EQUIV" "  └ 판정기 rc1 사유 그대로"
eqcnt 1 "ⓒ"
untouched "ⓒ"

echo "== ⓓ 계약 ②·R3 손댄 병합(첫 부모 줄은 병합뿐인데 내용이 달라짐 = patch-id 다름) → REJECT"
setup CLOSED
pr_reset
main_add other1 g1.txt 1
git -C "$NW" fetch -q origin main
git -C "$NW" merge -q --no-ff --no-commit origin/main
printf 'f1 hand\n' > "$NW/pr/f.txt"; git -C "$NW" add pr/f.txt
git -C "$NW" commit -q -m "merge main 1 (손댐)"
X="$(git -C "$NW" rev-parse HEAD)"; SQ="$(sq_head "PR #363 (head $X)" "$X")"
gh_head "$X"; card_body "$A" > "$CARD"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && ok "ⓓ rc=1" || bad "ⓓ rc=$rc ← ${out:0:900}"
hasnt "$out" "LANDED-PR-OK" "  └ 통과 0"
gitcnt "patch-id --stable" 2 "ⓓ"
eqcnt 1 "ⓓ"
untouched "ⓓ"

echo "== ⓔ 계약 ②·R4 세트가 끝줄 head 의 조상 아님(가지 갈아엎음 = amend) → REJECT"
setup CLOSED
pr_reset; S_OLD="$A"
git -C "$NW" commit -q --amend -m "work f (rewritten)"; A="$(git -C "$NW" rev-parse HEAD)"
main_add other1 g1.txt 1; merge_main 1
X="$(git -C "$NW" rev-parse HEAD)"; SQ="$(sq_head "PR #363 (head $X)" "$X")"
gh_head "$X"; card_body "$S_OLD" > "$CARD"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && ok "ⓔ rc=1" || bad "ⓔ rc=$rc ← ${out:0:900}"
hasnt "$out" "LANDED-PR-OK" "  └ 통과 0"
eqcnt 1 "ⓔ"
untouched "ⓔ"

echo "== ⓕ 계약 ③·R5 착지 안 됨(squash 끝줄 0) → landed 단계 REJECT · 새 칸 git 호출 0(patch-id 0줄)"
setup CLOSED; pr_reset; gh_head "$A"; card_body "$A" > "$CARD"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && ok "ⓕ rc=1" || bad "ⓕ rc=$rc ← ${out:0:600}"
has "$out" "main 에 산출 없음(ff 0 · squash 끝줄 0)" "  └ 지금 문구(landed 단계)"
hasnt "$out" "LANDED-PR-OK" "  └ 통과 0"
gitcnt "patch-id --stable" 0 "ⓕ"
gitcnt " --first-parent --no-merges " 0 "ⓕ"
untouched "ⓕ"

echo "== ⓖ 계약 ③·R6 앞 칸 통과는 동작 불변 — 세트 = PR head → «== 카드 세트» · 새 칸 호출 0"
setup CLOSED; pr_reset; SQ="$(sq_head "PR #363 (head $A)" "$A")"; gh_head "$A"; card_body "$A" > "$CARD"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓖ rc=0" || bad "ⓖ rc=$rc ← ${out:0:600}"
has "$out" "== 카드 세트" "  └ 지금 «== 카드 세트» 줄 그대로"
hasnt "$out" "main 병합" "  └ 새 칸 안 탐"
gitcnt "patch-id --stable" 0 "ⓖ"
eqcnt 0 "ⓖ"

echo "== ⓗ 계약 ③·R6 세트 = 이 PR 의 squash → «카드 세트 = squash» · 새 칸 호출 0"
setup CLOSED; pr_reset; SQ="$(sq_head "PR #363 (head $A)" "$A")"; gh_head "$A"; card_body "$SQ" > "$CARD"
SSQ="$(git -C "$ROOT" rev-parse --short "$SQ")"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓗ rc=0" || bad "ⓗ rc=$rc ← ${out:0:600}"
has "$out" "카드 세트 = squash $SSQ" "  └ 지금 «= squash» 줄 그대로"
gitcnt "patch-id --stable" 0 "ⓗ"
eqcnt 0 "ⓗ"

echo "== 변이 ⓐ 새 칸 끔 → R1(S ⊂ X · 병합뿐 · patch-id 같음)을 REJECT 로 오판한다(변이 FAIL = 이 시험이 잡는다)"
mutant '      elif _lp_sx_gate "$_lp_set"; then' '      elif false; then'
setup CLOSED; sx_graph 1; gh_head "$X"; card_body "$A" > "$CARD"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
mutreject "$out" "변이(새 칸 끔) → R1 을 REJECT 로 오판 = 변이 FAIL(테스트가 잡는다)" "$rc"

echo "== 변이 ⓑ «S..X 일반 커밋 0» 검사 끔 → R2(빈 커밋 1개)가 통과한다(변이 FAIL)"
mutant '  [ -z "$out" ] || return 1' '  : "$out"'
setup CLOSED
pr_reset
git -C "$NW" commit -q --allow-empty -m "승인 뒤 고침"
main_add other1 g1.txt 1; merge_main 1
X="$(git -C "$NW" rev-parse HEAD)"; SQ="$(sq_head "PR #363 (head $X)" "$X")"
gh_head "$X"; card_body "$A" > "$CARD"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
mutpass "$out" "변이(ⓑ 검사 끔) → R2 를 통과로 오판 = 변이 FAIL(테스트가 잡는다)" "$rc"

echo "== 변이 ⓒ patch-id 검사 끔 → R3(손댄 병합)이 통과한다(변이 FAIL)"
mutant '  [ -n "$p1" ] && [ -n "$p2" ] || return 1
  [ "$p1" = "$p2" ] || return 1' '  : "$p1$p2"'
setup CLOSED
pr_reset
main_add other1 g1.txt 1
git -C "$NW" fetch -q origin main
git -C "$NW" merge -q --no-ff --no-commit origin/main
printf 'f1 hand\n' > "$NW/pr/f.txt"; git -C "$NW" add pr/f.txt
git -C "$NW" commit -q -m "merge main 1 (손댐)"
X="$(git -C "$NW" rev-parse HEAD)"; SQ="$(sq_head "PR #363 (head $X)" "$X")"
gh_head "$X"; card_body "$A" > "$CARD"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
mutpass "$out" "변이(ⓒ patch-id 끔) → R3 을 통과로 오판 = 변이 FAIL(테스트가 잡는다)" "$rc"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
