#!/usr/bin/env bash
# test_nano_close_landed_ancestry_r1058.sh — r1058: ft-nano-close.sh --landed-pr 의 착지 판정 = PR 상태 칸이 아니라 «origin/main 에 산출이 있는가»
#   우리 착지 도구(ft-merge-land)는 squash 커밋을 main 에 직접 올리고 PR 을 CLOSED 또는 OPEN 으로 남긴다 → 상태가 MERGED 가 아니어도 정상 착지다.
#   ⓐ PR head 가 origin/main 의 조상(ff) ⓑ origin/main 커밋 «끝줄» 이 정확히 «PR #<N> (head <PR head 40hex>)»(squash) · 둘 다 없으면 REJECT · fetch 실패 = «판정 불가» REJECT.
# 임시 git 리포(ROOT + bare REMOTE) + 가짜 tmux·gh(PATH 앞)만 쓴다 — 실 리포·seats·tmux·gh(네트워크) 0 · 고정 sleep 0 · GIT_* env 0 · 자기 재호출 0.
# ⓐ R1 CLOSED + squash 끝줄 → CLOSED · INFO «착지 확인: squash»
# ⓑ R2 OPEN + 같은 squash → CLOSED(토큰 권한으로 못 닫은 경우) · ⓒ R3 CLOSED + head 가 main 의 조상(ff) → CLOSED · INFO ff
# ⓓ R4 CLOSED · 끝줄 0 · 조상 아님 → REJECT «main 에 산출 없음» · ⓔ R5 끝줄 head 가 H 와 다름 → REJECT · ⓕ R6 본문 가운데/꼬리 붙은 끝줄 → REJECT
# ⓖ R7 MERGED → 지금처럼 통과(동작 불변 · origin/main fetch 0) · ⓗ R8 fetch 실패 → «판정 불가» REJECT(옛 ref 로 통과 0)
# 변이: «끝줄 찾기 끔» → ⓐ FAIL · «조상 검사 끔» → ⓒ FAIL · «head 비교 없이 번호만» → ⓔ FAIL · «정확 일치 대신 포함» → ⓕ FAIL
# 짝: bin == kit cmp0 · /bin/bash 3.2 -n · r1011·r1053 시험 회귀는 이 파일 밖(카드 완료 조건에서 함께 rc0 확인)
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
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-nano-superseded-check.sh" \
   "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-team-lib.sh" "$SRC/ft_git_capped.py" "$SRC/ft_teamset.py" \
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
git -C "$ROOT" config "url.$T/remote.git.insteadOf" "$BYZ_URL"   # 식별자 = 설정값(github 꼴) · 전송 = 로컬 bare 리포(네트워크 0)
mkdir -p "$ROOT/.fable-team" "$ROOT/design/ops/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
# REMOTE = 가짜 origin(main). bare 라서 push 가 자유롭다 — main 에 무엇을 놓느냐로 R1~R8 을 만든다.
REMOTE="$T/remote.git"; git init -q --bare "$REMOTE"
git -C "$REMOTE" symbolic-ref HEAD refs/heads/main

SEAT='byz-ops-nano-anc#0'; BR='nano/anc'; NW="$ROOT/.worktrees/v65-anc"
CARD_REL='design/ops/indices/진행/anc.md'; CARD="$ROOT/$CARD_REL"
git -C "$ROOT" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
mkdir -p "$NW/web" && echo 'x' > "$NW/web/a.txt"
git -C "$NW" add web/a.txt && git -C "$NW" commit -q -m "work (착지한 세트)"
SET="$(git -C "$NW" rev-parse HEAD)"     # 카드 «세트:» = PR head
OTH="$(git -C "$ROOT" -c user.email=t@t -c user.name=t commit-tree HEAD^{tree} -p HEAD -m 'other')"   # PR head 가 아닌 «다른 커밋»
LEDGER="$T/ledger.md"

push_main() {  # push_main <sha> — REMOTE 의 main 을 그 커밋으로(가짜 origin/main)
  git -C "$ROOT" push -q --force "$REMOTE" "$1:refs/heads/main"
}
squash_commit() {  # squash_commit <끝줄> — REMOTE main 위에 «끝줄 = 인자» 인 커밋 1개를 얹는다(기본 = ft-merge-land 꼴)
  local base tree c
  base="$(git -C "$ROOT" rev-parse refs/remotes/origin/main 2>/dev/null || git -C "$ROOT" rev-parse main)"
  tree="$(git -C "$ROOT" rev-parse "$base^{tree}")"
  c="$(git -C "$ROOT" -c user.email=t@t -c user.name=t commit-tree "$tree" -p "$base" -m "$1")"
  push_main "$c"
}
card_body() {  # card_body — 상태 절에 «세트:» · «- 착지:» 있음 · «대상:» 줄 0(= 리포 = ROOT · r1053 갈래)
  printf '# 인덱스: anc\n## 상태\n- 2026-10-28 진행\n- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n- 착지: PR #363 squash\n' "$SET"
}
setup() {  # setup <MERGED|OPEN|CLOSED> — 명부·카드·gh·원장을 «정상(세션 없음 · 미커밋 0)» 으로 리셋 · origin/main = ROOT main(착지 0 기본값)
  git -C "$NW" reset -q --hard "$SET"; git -C "$NW" clean -qfd
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$ROOT/.fable-team/seats-ops.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$T/ghlog"; : > "$LEDGER"; rm -rf "$T/wtclean"
  card_body > "$CARD"
  local m='null'; [ "$1" != MERGED ] || m="{\"oid\":\"$SET\"}"
  printf '{"state":"%s","mergeCommit":%s,"headRefOid":"%s"}\n' "$1" "$m" "$SET" > "$T/gh.json"
  set_origin "$REMOTE"
  push_main "$(git -C "$ROOT" rev-parse main)"; git -C "$ROOT" fetch -q origin main   # 기본 = main 에 착지 0
}
set_origin() {  # set_origin <리포 경로> — insteadOf 규칙을 «하나만» 남긴다(둘이 같은 url 을 가리키면 git 이 모호로 실패한다)
  while read -r _k _v; do git -C "$ROOT" config --unset-all "$_k" 2>/dev/null; done < <(git -C "$ROOT" config --get-regexp '^url\..*\.insteadof$' 2>/dev/null)
  git -C "$ROOT" config "url.$1.insteadOf" "$BYZ_URL"
}
close() { ( cd "$ROOT" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FT_PACK_ROOT="$T/nopack" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" FAKE_GH_JSON="$T/gh.json" \
  FT_NANO_PREFIX=byz-ops-nano- FT_SEATS_JSON="$ROOT/.fable-team/seats-ops.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 \
  bash "${CLOSE_BIN:-$T/bin/ft-nano-close.sh}" "$SEAT" --result "$T/result.md" --recv 1 "$@" 2>&1 ); }
untouched() {  # untouched <이름> — REJECT 인데 닫기 흔적 0
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$ROOT/.fable-team/seats-ops.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 원장 행 0" || bad "$1: 원장 행 생김"
  git -C "$ROOT" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 그대로" || bad "$1: 브랜치 삭제"
}
closed_ok() {  # closed_ok <이름> — 닫기가 실제로 끝났는가
  jq -e --arg s "$SEAT" 'has($s) | not' "$ROOT/.fable-team/seats-ops.json" >/dev/null && ok "  └ 명부에서 지움" || bad "$1: 명부에 남음"
  has "$(cat "$LEDGER")" "landed-pr=363" "  └ 원장 닫힘 행 landed-pr=363"
}
mutant() {  # mutant <old> <new> [<old2> <new2> …] → $T/mutbin/ft-nano-close.sh (매번 새 사본 · 자리마다 1곱)
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

echo "== ⓐ R1 CLOSED + main 끝줄 «PR #363 (head <PR head>)» → 착지 확인 squash · CLOSED"
setup CLOSED; squash_commit "squash 착지

PR #363 (head $SET)"
git -C "$ROOT" fetch -q origin main; SSH="$(git -C "$ROOT" rev-parse --short refs/remotes/origin/main)"   # 화면 값 = close 가 읽는 그 ref
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓐ rc=0" || bad "ⓐ rc=$rc ← ${out:0:800}"
has "$out" "INFO ⑥--landed-pr 착지 확인: squash $SSH" "  └ INFO «착지 확인: squash <짧은 sha>»"
has "$out" "· PR state=CLOSED" "  └ 사유에 PR state=CLOSED"
has "$out" "LANDED-PR-OK #363" "  └ ⑥ 자리 = LANDED-PR-OK"
has "$out" "state=CLOSED" "  └ OK 줄의 state = 실제 값(CLOSED)"
has "$out" "CLOSED-ABSENT $SEAT landed-pr=363" "  └ CLOSED-ABSENT <좌석> landed-pr=<N>"
closed_ok "ⓐ"

echo "== ⓑ R2 OPEN + 같은 squash 끝줄 → 통과(토큰 권한으로 못 닫은 경우)"
setup OPEN; squash_commit "squash 착지

PR #363 (head $SET)"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓑ rc=0" || bad "ⓑ rc=$rc ← ${out:0:800}"
has "$out" "착지 확인: squash" "  └ squash 통과"
has "$out" "· PR state=OPEN" "  └ state=OPEN 도 같은 판정"
closed_ok "ⓑ"

echo "== ⓒ R3 CLOSED + PR head 가 origin/main 의 조상(--ff 착지) → 착지 확인 ff"
setup CLOSED; push_main "$SET"; git -C "$ROOT" fetch -q origin main
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓒ rc=0" || bad "ⓒ rc=$rc ← ${out:0:800}"
has "$out" "INFO ⑥--landed-pr 착지 확인: ff · PR state=CLOSED" "  └ INFO «착지 확인: ff»"
closed_ok "ⓒ"

echo "== ⓓ R4 CLOSED · main 에 끝줄 0 · 조상 아님 → REJECT «main 에 산출 없음»"
setup CLOSED; out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "main 에 산출 없음(ff 0 · squash 끝줄 0)" "ⓓ 착지 0 → REJECT" || bad "ⓓ rc=$rc ← ${out:0:600}"
untouched "ⓓ"

echo "== ⓔ R5 끝줄의 head 가 PR head 와 다름(같은 번호 · 옛 head) → REJECT"
setup CLOSED; squash_commit "squash 착지

PR #363 (head $OTH)"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "main 에 산출 없음" "ⓔ 옛 head 끝줄 → REJECT" || bad "ⓔ rc=$rc ← ${out:0:600}"
untouched "ⓔ"

echo "== ⓕ R6 본문 가운데 줄 · 끝줄에 꼬리 붙음 → 그 커밋으로 통과 0"
setup CLOSED; squash_commit "PR #363 (head $SET)

본문 마지막 줄"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "main 에 산출 없음" "ⓕ 끝줄이 본문 가운데 → REJECT" || bad "ⓕ(가운데) rc=$rc ← ${out:0:600}"
untouched "ⓕ 가운데"
setup CLOSED; squash_commit "PR #363 (head $SET) (cherry-picked)"
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "main 에 산출 없음" "ⓕ 끝줄에 꼬리(포함은 되나 정확 아님) → REJECT" || bad "ⓕ(꼬리) rc=$rc ← ${out:0:600}"
untouched "ⓕ 꼬리"

echo "== ⓖ R7 MERGED → 지금처럼 통과 · origin/main fetch 0(동작 불변)"
setup MERGED; set_origin "$T/nope.git"   # origin 을 못 받는 상태로 만들어도 MERGED 는 통과해야 한다
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓖ MERGED rc=0(fetch 를 안 탄다)" || bad "ⓖ rc=$rc ← ${out:0:600}"
has "$out" "state=MERGED" "  └ OK 줄 state=MERGED(불변)"
hasnt "$out" "착지 확인" "  └ 착지 확인 INFO 0(예전 길 그대로)"
closed_ok "ⓖ"
set_origin "$REMOTE"

echo "== ⓗ R8 origin fetch 실패 → «판정 불가» REJECT · 옛 ref 로 통과 0"
setup CLOSED; push_main "$SET"; git -C "$ROOT" fetch -q origin main   # 옛 ref = SET(조상) — fetch 가 성공하면 통과할 값
set_origin "$T/nope.git"                                            # 이제 fetch 는 반드시 실패
out="$(close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "판정 불가로 닫지 않는다" "ⓗ fetch 실패 → «판정 불가» REJECT" || bad "ⓗ rc=$rc ← ${out:0:600}"
has "$out" "origin/main 을 받지 못했다" "  └ 사유 = fetch 실패"
hasnt "$out" "착지 확인: ff" "  └ 옛 ref 로 통과 0"
untouched "ⓗ"
set_origin "$REMOTE"

echo "== 변이 «끝줄 찾기 끔» → ⓐ 가 잡는다(변이 FAIL)"
mutant 'out="$(nf_bound "$cap" git -C "$repo" log refs/remotes/origin/main --fixed-strings --grep="$grepw" --format=%H 2>&1)"; rc=$?' 'out=""; rc=0'   # r1074: grep 인자가 ««PR #N (head » 접두로 바뀌었다(변이 자리만 따라옮김)
setup CLOSED; squash_commit "squash 착지

PR #363 (head $SET)"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && ok "변이(끝줄 찾기 끔) → REJECT = ⓐ 가 잡는다(변이 FAIL)" || bad "변이 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"

echo "== 변이 «조상 검사 끔» → ⓒ 가 잡는다(변이 FAIL)"
mutant 'if git -C "$repo" merge-base --is-ancestor "${_lp_head}" refs/remotes/origin/main 2>/dev/null; then' 'if false; then'
setup CLOSED; push_main "$SET"; git -C "$ROOT" fetch -q origin main
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 1 ] && ok "변이(조상 검사 끔) → REJECT = ⓒ 가 잡는다(변이 FAIL)" || bad "변이 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"

echo "== 변이 «head 비교 없이 번호만» → ⓔ 가 잡는다(변이 FAIL)"
mutant 'want="PR #$LANDED_PR (head $_lp_head)"' 'want="PR #$LANDED_PR"' \
  'if [ "$last" = "$want" ]; then' 'if case "$last" in "PR #$LANDED_PR "*) true;; *) false;; esac; then'
setup CLOSED; squash_commit "squash 착지

PR #363 (head $OTH)"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "변이(head 비교 끔) → 옛 head 끝줄로 닫힘 = ⓔ 가 잡는다(변이 FAIL)" || bad "변이 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"

echo "== 변이 «정확 일치 대신 포함» → ⓕ 가 잡는다(변이 FAIL)"
mutant 'if [ "$last" = "$want" ]; then' 'if case "$last" in *"$want"*) true;; *) false;; esac; then'
setup CLOSED; squash_commit "PR #363 (head $SET) (cherry-picked)"
out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 363)"; rc=$?
[ "$rc" -eq 0 ] && ok "변이(포함으로 완화) → 꼬리 붙은 끝줄로 닫힘 = ⓕ 가 잡는다(변이 FAIL)" || bad "변이 안 먹음 rc=$rc ← $(printf '%s' "$out" | tail -3)"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
