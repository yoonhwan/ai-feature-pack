#!/usr/bin/env bash
# test_nano_close_landed_pr_cherry_r1112.sh — r1112: ft-nano-close.sh --landed-pr ⑥ «cherry 착지»
#   나노 가지가 문서 가지 위(팀 문서 변경을 품음) · 착지 PR 은 코드 커밋만 옮김 → PR head ≠ 세트 · 병합 꼴도 아님.
#   세트가 바꾼 코드 경로(design/teams/ 아래 · *.md 제외) ≥1 이고 그 전부의 blob 이 PR head 와 같으면 통과.
# 임시 git 리포 + 가짜 tmux·gh(PATH 앞)만 쓴다 — 실 리포·seats·tmux·gh(네트워크) 0 · 자기 재호출 0 · 고정 sleep 0.
# 칸: ⓐ R1 ccu 꼴(코드 2 같음 + 팀 문서 3 다름) → CLOSED · INFO · 원장 «landed-pr=501 cherry»
#     ⓑ R2 코드 1개 blob 다름 → REJECT «cherry 착지 아님: <경로>» · R4 세트가 코드 삭제 · PR 엔 있음 → REJECT
#     ⓒ R3 세트가 팀 문서만 → REJECT(지금과 같음 · cherry 문구 0)
#     ⓓ R5 기존 길 = 회귀 시험(test_nano_close_landed_pr_r1011.sh) 몫
#     ⓔ bin·kit 같은 바이트 · 변이 «cherry 길 끔»→ⓐ FAIL · «blob 비교 끔»→ⓑ FAIL
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0; TS="$(date +%s)"
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:600}";; *) ok "$3";; esac; }

echo "== ⓔ 키트 2곳 같은 바이트 + bash -n (/bin/bash 3.2 포함)"
cmp -s "$HERE/../../harness/bin/ft-nano-close.sh" "$SRC/ft-nano-close.sh" && ok "cmp ft-nano-close.sh (bin == kit)" || bad "cmp ft-nano-close.sh 다름"
/bin/bash -n "$SRC/ft-nano-close.sh" && ok "/bin/bash 3.2 -n" || bad "/bin/bash 3.2 -n"

mkdir -p "$T/bin" "$T/fake"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-nano-superseded-check.sh" \
   "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-team-lib.sh" "$SRC/ft_git_capped.py" "$SRC/ft_teamset.py" \
   "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" \
   "$SRC/ft-approval-equiv.sh" "$SRC/ft_approval_equiv.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
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
chmod +x "$T/bin/"* "$T/fake/"*

# ── 리포: main(M1: main.txt · lib/old.py) · origin = 자기 자신(insteadOf · 네트워크 0)
REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
BYZ_URL='https://github.com/lptest/byz.git'
git -C "$REPO" remote add origin "$BYZ_URL"; git -C "$REPO" config "url.$REPO.insteadOf" "$BYZ_URL"
mkdir -p "$REPO/lib" "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$T/comm/bodies"
echo m1 > "$REPO/main.txt"; echo 'old = 1' > "$REPO/lib/old.py"
git -C "$REPO" add main.txt lib/old.py; git -C "$REPO" commit -q -m 'main 1'; M1="$(git -C "$REPO" rev-parse HEAD)"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"

# mk <부모> <메시지> <경로=내용|경로=-(삭제)>… → 새 커밋 sha (작업 트리 0 · 임시 index)
mk() {
  local parent="$1" msg="$2" kv p v blob idx="$T/idx.$$"; shift 2
  rm -f "$idx"; GIT_INDEX_FILE="$idx" git -C "$REPO" read-tree "$parent"
  for kv in "$@"; do
    p="${kv%%=*}"; v="${kv#*=}"
    if [ "$v" = - ]; then GIT_INDEX_FILE="$idx" git -C "$REPO" update-index --force-remove "$p"
    else blob="$(printf '%s\n' "$v" | git -C "$REPO" hash-object -w --stdin)"; GIT_INDEX_FILE="$idx" git -C "$REPO" update-index --add --cacheinfo "100644,$blob,$p"; fi
  done
  git -C "$REPO" commit-tree "$(GIT_INDEX_FILE="$idx" git -C "$REPO" write-tree)" -p "$parent" -m "$msg"
}
# 문서 가지(master 문서) → 그 위 나노 세트(코드 2 + 팀 문서 1) = 세트가 바꾼 경로: 코드 2 · 팀 문서 3
DOC="$(mk "$M1" docs 'design/teams/x/a.md=a' 'design/teams/x/b.md=b')"
S1="$(mk "$DOC" set1 'tools/seg.py=print(1)' 'tests/test_seg.py=assert 1' 'design/teams/x/c.md=c')"
H1="$(mk "$M1" pr501 'tools/seg.py=print(1)' 'tests/test_seg.py=assert 1' 'design/teams/ccu/arch.md=arch')"      # R1 코드 cherry-pick + 다른 문서 1
H2="$(mk "$M1" pr502 'tools/seg.py=print(2)' 'tests/test_seg.py=assert 1')"                                        # R2 한 줄 고침
S3="$(mk "$DOC" set3 'design/teams/x/c.md=c')"; H3="$(mk "$M1" pr503 'design/teams/x/z.md=z')"                     # R3 팀 문서만
S4="$(mk "$DOC" set4 'tools/seg.py=print(1)' 'lib/old.py=-')"; H4="$(mk "$M1" pr504 'tools/seg.py=print(1)')"      # R4 세트는 삭제 · PR 엔 있음
# r1112 r2(DA① HOLD): 한글 경로 — core.quotePath=true 에서 이름이 «"…"» 로 감싸지면 안 된다
S5="$(mk "$DOC" set5 'tools/한글.py=print(1)')"; H5="$(mk "$M1" pr505 'tools/한글.py=print(2)')"                    # R2 꼴 한글 코드 blob 다름
S6="$(mk "$DOC" set6 'docs/한글.md=doc')"; H6="$(mk "$M1" pr506 'docs/다른.md=other')"                              # R3 꼴 한글 .md 만(코드 0)
# main = squash 착지(끝줄 «PR #N (head <H>)» · ft-merge-land 꼴) — PR head 는 main 조상 아님
Q="$M1"
for nh in "501:$H1" "502:$H2" "503:$H3" "504:$H4" "505:$H5" "506:$H6"; do
  Q="$(git -C "$REPO" commit-tree "$M1^{tree}" -p "$Q" -m "squash ${nh%%:*}" -m "PR #${nh%%:*} (head ${nh#*:})")"
done
git -C "$REPO" update-ref refs/heads/main "$Q"; git -C "$REPO" reset -q --hard "$Q"; git -C "$REPO" update-ref refs/remotes/origin/main "$Q"

SEAT='byz-planner-nano-lp#0'; BR='nano/lp'; NW="$REPO/.worktrees/v65-lp"
CARD_REL='design/planner/indices/진행/lp.md'; CARD="$REPO/$CARD_REL"; LEDGER="$T/ledger.md"
git -C "$REPO" worktree add -q "$NW" -b "$BR" "$S1"

run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FT_PACK_ROOT="$T/nopack" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" FAKE_GH_JSON="$T/gh.json" "$@" 2>&1 ); }
setup() {  # setup <PR 번호> <세트> <PR head> — 명부·pane·카드·나노 HEAD 리셋 · gh = CLOSED(ft-merge-land 꼴)
  git -C "$NW" reset -q --hard "$2"; git -C "$NW" clean -qfd; rm -f "$NW/.worktree-info.json"
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$REPO/.fable-team/seats-planner.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$T/ghlog"; : > "$LEDGER"; rm -rf "$T/wtclean"
  printf '# 인덱스: lp\n## 상태\n- 2026-10-29 진행\n- 세트: %s · 시험: bash t.sh (5 passed) rc=0 · 이슈: 0\n- 대상: %s/tools/seg.py(r1112 시험)\n- 착지: PR #%s squash\n' "$2" "$REPO" "$1" > "$CARD"
  printf '{"state":"CLOSED","mergeCommit":null,"headRefOid":"%s"}\n' "$3" > "$T/gh.json"
}
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 bash "${CLOSE_BIN:-$T/bin/ft-nano-close.sh}" "$SEAT" --result "$T/result.md" --recv 1 "$@"; }
untouched() {
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 해제 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 닫힘 원장 행 0" || bad "$1: 원장 행 생김"
}
mutant() {  # mutant <old> <new> → $T/mutbin/ft-nano-close.sh
  rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin"
  python3 - "$T/mutbin/ft-nano-close.sh" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1:4]; s = open(p, encoding="utf-8").read()
assert old in s, "변이 자리 없음: " + old[:60]
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}

echo "== ⓐ R1 ccu 꼴: 코드 2 blob 같음 + 팀 문서 3 다름 → CLOSED · cherry 착지"
setup 501 "$S1" "$H1"; out="$(close --landed-pr 501)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓐ rc=0" || bad "ⓐ rc=$rc ← ${out:0:900}"
has "$out" "INFO ⑥--landed-pr cherry 착지: 코드 2개 blob 같음 · 팀 문서 3개 제외 · PR head ${H1:0:9}" "  └ INFO 줄(코드 2 · 팀 문서 3)"
has "$out" "LANDED-PR-OK #501" "  └ ⑥ 자리 = LANDED-PR-OK"
has "$out" "(cherry 착지)" "  └ LANDED-PR-OK 줄 = cherry 꼴"
has "$out" "CLOSED-ABSENT $SEAT landed-pr=501 cherry" "  └ 꼬리 landed-pr=501 cherry"
has "$(cat "$LEDGER")" "landed-pr=501 cherry" "  └ 원장 행 landed-pr=501 cherry"
hasnt "$out" "equiv=" "  └ equiv= 0(병합 길 아님)"

echo "== ⓑ R2 코드 1개 blob 다름 → REJECT «cherry 착지 아님: tools/seg.py»"
setup 502 "$S1" "$H2"; out="$(close --landed-pr 502)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "cherry 착지 아님: tools/seg.py" "ⓑ R2 → REJECT 첫 경로" || bad "ⓑ R2 rc=$rc ← ${out:0:900}"
untouched "ⓑ R2"
echo "== ⓑ R4 세트가 lib/old.py 삭제 · PR head 엔 있음 → REJECT"
setup 504 "$S4" "$H4"; out="$(close --landed-pr 504)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "cherry 착지 아님: lib/old.py" "ⓑ R4 → REJECT(한쪽만 없음 = 다름)" || bad "ⓑ R4 rc=$rc ← ${out:0:900}"
untouched "ⓑ R4"

echo "== ⓒ R3 세트가 design/teams/ 문서만(코드 0) → REJECT 지금과 같음"
setup 503 "$S3" "$H3"; out="$(close --landed-pr 503)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "«세트 + main 병합뿐» 도 아님(판정기 rc=" "ⓒ R3 → 판정기 사유 그대로 REJECT" || bad "ⓒ R3 rc=$rc ← ${out:0:900}"
hasnt "$out" "cherry 착지" "  └ cherry 문구 0(이 길 아님)"
untouched "ⓒ R3"

echo "== ⓕ core.quotePath=true(git 기본) · R2 꼴 한글 코드 blob 다름 → REJECT"
git -C "$REPO" config core.quotePath true
setup 505 "$S5" "$H5"; out="$(close --landed-pr 505)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "cherry 착지 아님: tools/한글.py" "ⓕ R2 한글 → REJECT 첫 경로(따옴표 0)" || bad "ⓕ R2 한글 rc=$rc ← ${out:0:900}"
untouched "ⓕ R2 한글"
echo "== ⓖ core.quotePath=true · R3 꼴 한글 .md 만 → 이 길 아님(판정기 사유 그대로 REJECT)"
setup 506 "$S6" "$H6"; out="$(close --landed-pr 506)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "«세트 + main 병합뿐» 도 아님(판정기 rc=" "ⓖ R3 한글 .md → 판정기 사유 그대로 REJECT" || bad "ⓖ R3 한글 rc=$rc ← ${out:0:900}"
hasnt "$out" "cherry 착지" "  └ cherry 문구 0(.md 제외가 먹음)"
untouched "ⓖ R3 한글"
echo "== ⓗ 변이 «-z 제거» → ⓕ 가 닫힌다(변이 FAIL)"
mutant 'diff -z --no-renames --name-only' 'diff --no-renames --name-only'
setup 505 "$S5" "$H5"; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 505)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓗ 변이(-z 제거) → 한글 blob 다름인데 닫힘 = ⓕ 가 잡는다" || bad "ⓗ 변이 -z rc=$rc — 변이가 안 먹었다: $(printf '%s' "$out" | grep -m1 -A1 REJECT)"
git -C "$REPO" config --unset core.quotePath

echo "== ⓔ 변이 «cherry 길 끔» → ⓐ 가 REJECT 로 바뀐다(변이 FAIL)"
mutant '_lp_cherry_gate; rc=$?   # r1112-mut:cherry' 'rc=1'
setup 501 "$S1" "$H1"; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 501)"; rc=$?
[ "$rc" -eq 1 ] && ok "ⓔ 변이(cherry 끔) → R1 REJECT = ⓐ 가 잡는다" || bad "ⓔ 변이 cherry rc=$rc — 변이가 안 먹었다"
echo "== ⓔ 변이 «blob 비교 끔» → ⓑ R2 가 닫힌다(변이 FAIL)"
mutant '[ "$a" = "$b" ] || { first="$p"; break; }   # r1112-mut:blob' ':'
setup 502 "$S1" "$H2"; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 502)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓔ 변이(blob 끔) → R2 닫힘 = ⓑ 가 잡는다" || bad "ⓔ 변이 blob rc=$rc — 변이가 안 먹었다: $(printf '%s' "$out" | grep -m1 REJECT)"

echo "경과 $(( $(date +%s) - TS ))s"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
