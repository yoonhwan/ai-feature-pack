#!/usr/bin/env bash
# test_nano_close_landed_pr_docam_r1169.sh — r1169: ft-nano-close.sh --landed-pr 의 «squash 끝줄» 읽기가 ft-merge-land 문서 자동 병합(docam) 꼬리 1줄
#   «main 자동 병합(문서 전용 · 겹침 0) C=<40hex>» 를 건너뛰고 그 앞 줄 «PR #N (head <40hex>)» 을 끝줄로 본다 · 그 밖 끝줄 꼴은 지금과 같다.
#   2b: squash 착지 확인 줄에 PR state 가 MERGED 가 아니면 «PR state=<상태>·mergedAt 없음은 정상 …» 안내 1줄(판정 불변 · 문구만).
# 임시 git 리포(ROOT + bare REMOTE) + 가짜 tmux·gh(PATH 앞)만 쓴다 — 실 리포·seats·tmux·gh(네트워크) 0 · 고정 sleep 0 · 자기 재호출 0.
# ⓐ R1 끝 2줄 = «PR #7 (head X)» + docam 꼬리 → 착지 확인 squash · CLOSED
# ⓑ R2 끝줄 = «PR #7 (head X)» 만(일반 squash) → 착지 확인(지금과 같음)
# ⓒ R3 꼬리 문구가 다름(짧은 sha · 다른 문구) → REJECT «squash 끝줄 0» · R4 «PR #77 (head X)» + 꼬리 · N=7 → REJECT(접두 겹침)
# ⓒ2 R5 R1 꼴 · state=CLOSED · mergedAt 없음 → 착지 확인 줄 + «정상» 안내 · MERGED → 안내 0
# ⓓ bin == kit cmp0 · bash -n(/bin/bash 3.2 포함)
# 변이 «꼬리 건너뛰기 삭제» → ⓐ 가 잡는다(R1 REJECT = 변이 FAIL)
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

echo "== ⓓ 짝 cmp · bash -n (/bin/bash 3.2 포함)"
cmp -s "$HERE/../../harness/bin/ft-nano-close.sh" "$SRC/ft-nano-close.sh" && ok "cmp bin == kit" || bad "cmp 다름"
bash -n "$SRC/ft-nano-close.sh" && ok "bash -n" || bad "bash -n"
/bin/bash -n "$SRC/ft-nano-close.sh" && ok "/bin/bash 3.2 -n" || bad "/bin/bash 3.2 -n"

mkdir -p "$T/bin" "$T/fake"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-nano-superseded-check.sh" \
   "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-team-lib.sh" "$SRC/ft-card-target-lib.sh" "$SRC/ft_git_capped.py" "$SRC/ft_teamset.py" \
   "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" \
   "$T/bin/"
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

BYZ_URL='https://github.com/lptest/byz.git'
ROOT="$T/repo"; mkdir -p "$ROOT"
git -C "$ROOT" init -q -b main && git -C "$ROOT" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$ROOT" remote add origin "$BYZ_URL"
git -C "$ROOT" config "url.$T/remote.git.insteadOf" "$BYZ_URL"   # 식별자 = github 꼴 · 전송 = 로컬 bare 리포(네트워크 0)
mkdir -p "$ROOT/.fable-team" "$ROOT/design/ops/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
REMOTE="$T/remote.git"; git init -q --bare "$REMOTE"
git -C "$REMOTE" symbolic-ref HEAD refs/heads/main

SEAT='byz-ops-nano-docam#0'; BR='nano/docam'; NW="$ROOT/.worktrees/v65-docam"
CARD_REL='design/ops/indices/진행/docam.md'; CARD="$ROOT/$CARD_REL"
git -C "$ROOT" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
mkdir -p "$NW/docs" && echo 'x' > "$NW/docs/a.md"
git -C "$NW" add docs/a.md && git -C "$NW" commit -q -m "work (착지한 세트)"
X="$(git -C "$NW" rev-parse HEAD)"     # 카드 «세트:» = PR head = 나노 가지
Y="$(printf '%040d' 0 | tr 0 c)"   # docam 꼬리의 C=<40hex>
LEDGER="$T/ledger.md"
TAIL="main 자동 병합(문서 전용 · 겹침 0) C=$Y"

push_main() { git -C "$ROOT" push -q --force "$REMOTE" "$1:refs/heads/main"; }
squash_commit() {  # squash_commit <메시지> — REMOTE main 위에 커밋 1개(트리 = 기준 그대로)
  local base tree c
  base="$(git -C "$ROOT" rev-parse main)"
  tree="$(git -C "$ROOT" rev-parse "$base^{tree}")"
  c="$(git -C "$ROOT" -c user.email=t@t -c user.name=t commit-tree "$tree" -p "$base" -m "$1")"
  push_main "$c"
}
setup() {  # setup <MERGED|OPEN|CLOSED> — 명부·카드·gh·원장 리셋 · origin/main = ROOT main(착지 0)
  git -C "$NW" reset -q --hard "$X"; git -C "$NW" clean -qfd
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$ROOT/.fable-team/seats-ops.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$T/ghlog"; : > "$LEDGER"; rm -rf "$T/wtclean"
  printf '# 인덱스: docam\n## 상태\n- 2026-10-31 진행\n- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n- 착지: PR #7 squash\n' "$X" > "$CARD"
  local m='null'; [ "$1" != MERGED ] || m="{\"oid\":\"$X\"}"
  printf '{"state":"%s","mergeCommit":%s,"headRefOid":"%s"}\n' "$1" "$m" "$X" > "$T/gh.json"
  push_main "$(git -C "$ROOT" rev-parse main)"; git -C "$ROOT" fetch -q origin main
}
close() { ( cd "$ROOT" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FT_PACK_ROOT="$T/nopack" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" FAKE_GH_JSON="$T/gh.json" \
  FT_NANO_PREFIX=byz-ops-nano- FT_SEATS_JSON="$ROOT/.fable-team/seats-ops.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
  bash "${CLOSE_BIN:-$T/bin/ft-nano-close.sh}" "$SEAT" --result "$T/result.md" --recv 1 "$@" 2>&1 ); }
untouched() {
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$ROOT/.fable-team/seats-ops.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 원장 행 0" || bad "$1: 원장 행 생김"
}
closed_ok() {
  jq -e --arg s "$SEAT" 'has($s) | not' "$ROOT/.fable-team/seats-ops.json" >/dev/null && ok "  └ 명부에서 지움" || bad "$1: 명부에 남음"
  has "$(cat "$LEDGER")" "landed-pr=7" "  └ 원장 닫힘 행 landed-pr=7"
}
mutant() {  # mutant <old> <new> → $T/mutbin/ft-nano-close.sh
  rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin"
  python3 - "$T/mutbin/ft-nano-close.sh" "$@" <<'PY'
import sys
p = sys.argv[1]; old, new = sys.argv[2], sys.argv[3]
s = open(p, encoding='utf-8').read()
assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳: {old[:70]}"
open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PY
}
NOTE='PR state=CLOSED·mergedAt 없음은 정상(ft-merge-land 는 병합 버튼 없이 squash 를 main 에 올리고 PR 을 닫는다 · r1058)'

echo "== ⓐ R1 끝 2줄 = «PR #7 (head X)» + docam 꼬리 → 착지 확인 squash · CLOSED"
setup CLOSED; squash_commit "docs 착지

PR #7 (head $X)
$TAIL"
git -C "$ROOT" fetch -q origin main; SSH="$(git -C "$ROOT" rev-parse --short refs/remotes/origin/main)"   # 화면 값 = close 가 읽는 그 ref
out="$(close --landed-pr 7)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓐ rc=0" || bad "ⓐ rc=$rc ← ${out:0:800}"
has "$out" "INFO ⑥--landed-pr 착지 확인: squash $SSH" "  └ INFO «착지 확인: squash <짧은 sha>»"
hasnt "$out" "squash 끝줄 0" "  └ «squash 끝줄 0» REJECT 0"
has "$out" "CLOSED-ABSENT $SEAT landed-pr=7" "  └ CLOSED-ABSENT <좌석> landed-pr=7"
closed_ok "ⓐ"

echo "== ⓑ R2 끝줄 = «PR #7 (head X)» 만(일반 squash) → 착지 확인(지금과 같음)"
setup CLOSED; squash_commit "docs 착지

PR #7 (head $X)"
out="$(close --landed-pr 7)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓑ rc=0" || bad "ⓑ rc=$rc ← ${out:0:800}"
has "$out" "착지 확인: squash" "  └ squash 통과"
closed_ok "ⓑ"

echo "== ⓒ R3 꼬리 문구가 다름 → 지금처럼 끝줄 불일치 REJECT"
for tl in "main 자동 병합(문서 전용 · 겹침 0) C=${Y:0:10}" "main 자동 병합 C=$Y" "main 자동 병합(문서 전용 · 겹침 0) C=${Y}d"; do
  setup CLOSED; squash_commit "docs 착지

PR #7 (head $X)
$tl"
  out="$(close --landed-pr 7)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "main 에 산출 없음(ff 0 · squash 끝줄 0)" "ⓒ R3 꼬리 «${tl:0:40}…» → REJECT" || bad "ⓒ R3 rc=$rc ← ${out:0:600}"
  untouched "ⓒ R3"
done

echo "== ⓒ R4 끝 2줄 = «PR #77 (head X)» + 꼬리 · --landed-pr 7 → REJECT(접두 겹침)"
setup CLOSED; squash_commit "docs 착지

PR #77 (head $X)
$TAIL"
out="$(close --landed-pr 7)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "main 에 산출 없음(ff 0 · squash 끝줄 0)" "ⓒ R4 접두 겹침 → REJECT" || bad "ⓒ R4 rc=$rc ← ${out:0:600}"
untouched "ⓒ R4"

echo "== ⓒ2 R5 R1 꼴 · state=CLOSED · mergedAt 없음 → 착지 확인 줄 + «정상» 안내"
setup CLOSED; squash_commit "docs 착지

PR #7 (head $X)
$TAIL"
out="$(close --landed-pr 7)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓒ2 rc=0" || bad "ⓒ2 rc=$rc ← ${out:0:800}"
has "$out" "· PR state=CLOSED — $NOTE" "  └ 착지 확인 줄 끝 = «정상» 안내"
hasnt "$out" "state=CLOSED · main 에 산출 없음" "  └ «⑥ state=CLOSED · main 에 산출 없음» REJECT 0"
setup MERGED; squash_commit "docs 착지

PR #7 (head $X)
$TAIL"
out="$(close --landed-pr 7)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓒ2 MERGED rc=0" || bad "ⓒ2 MERGED rc=$rc ← ${out:0:800}"
hasnt "$out" "mergedAt 없음은 정상" "  └ MERGED → 안내 0"

echo "== 변이 «꼬리 건너뛰기 삭제» → ⓐ 가 잡는다(변이 FAIL)"
mutant '*) l="$p";; esac; fi   # r1169-mut:skip' '*) ;; esac; fi   # r1169-mut:skip'
setup CLOSED; squash_commit "docs 착지

PR #7 (head $X)
$TAIL"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 7)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "squash 끝줄 0" "변이(꼬리 건너뛰기 삭제) → R1 REJECT = ⓐ 가 잡는다(변이 FAIL)" || bad "변이 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
