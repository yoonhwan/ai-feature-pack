#!/usr/bin/env bash
# test_r978_doc_output_landing.sh — r978: 조사·문서 산출(코드 0)이 «닫기» 와 «완성» 게이트에서 오빠 h 없이 흐르게
#   고침 1(ft-nano-close.sh --research) — 커밋·미커밋이 있어도 그 경로 «전부» 가 --result 1개뿐이면 통과(r976 꼴) · 그 밖 경로 1개라도 있으면 REJECT
#   고침 2(ft-finished-check.sh · ft-index-move-canon.sh) — «설치: 없음 ∧ 문서 가지 조상 ∧ 바꾼 경로 전부 design/**.md» 셋 다일 때만 문서 가지 착지 인정
# 임시 git 리포 + bare origin + 가짜 tmux(PATH 앞)만 쓴다 — 실제 리포·명부·tmux 세션은 건드리지 않는다. GIT_* 환경 변수는 쓰지 않는다.
#   변이: 경로 검사 빼고 커밋 수만 0 허용 → ⓐ 다른 파일 칸 FAIL · 설치: 없음 조건 제거 → ⓑ 설치: 있음 칸 FAIL · 한 자리만 새 함수 → ⓑ 한쪽 FAIL
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

echo "== 짝 사본 2곳 같은 바이트 + bash -n"
for f in ft-nano-close.sh ft-finished-check.sh ft-index-move-canon.sh ft-team-lib.sh; do
  cmp -s "$HERE/../../harness/bin/$f" "$SRC/$f" && ok "cmp $f (bin == kit)" || bad "cmp $f 다름"
  bash -n "$SRC/$f" && ok "bash -n $f" || bad "bash -n $f"
done

mkdir -p "$T/bin" "$T/fake" "$T/tmp"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-nano-superseded-check.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-wt-sweep.sh" "$T/bin/"
cp "$SRC/ft_teamset.py" "$SRC/ft-team-lib.sh" "$SRC/ft_git_capped.py" "$SRC/ft-finished-check.sh" "$SRC/ft-index-move-canon.sh" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
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
chmod +x "$T/bin/"* "$T/fake/"*

ORIGIN="$T/origin.git"; git init -q --bare "$ORIGIN"
REPO="$T/repo"; mkdir -p "$REPO"
gitc() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
git -C "$REPO" init -q -b main && gitc commit -q --allow-empty -m init
git -C "$REPO" remote add origin "$ORIGIN"
mkdir -p "$REPO/.fable-team" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"

SEAT='byz-planner-nano-rd#0'; BR='nano/rd'; NW="$REPO/.worktrees/v65-rd"
CARD='design/planner/indices/진행/rd.md'
OUT='design/harness/evidence/r978/TABLE-rd.md'   # 산출(문서) — 좌석 워크트리 안
mkdir -p "$REPO/design/planner/indices/진행" "$REPO/scripts"
printf '# 인덱스: rd\n## 상태\n- 진행\n- 설치: 없음\n' > "$REPO/$CARD"
echo 'print(0)' > "$REPO/scripts/x.py"
gitc add -A && gitc commit -q -m "A: 카드 대기"
SHA_A="$(git -C "$REPO" rev-parse HEAD)"
gitc push -q origin main
git -C "$REPO" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t

LEDGER="$T/ledger.md"
run() { ( cd "$REPO" && env -i HOME="$HOME" TMPDIR="$T/tmp" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {
  git -C "$NW" reset -q --hard "$SHA_A"; git -C "$NW" clean -qfd
  gitc reset -q --hard "$SHA_A"; gitc clean -qfd -- design scripts
  mkdir -p "$REPO/.fable-team"
  rm -rf "$NW/.serena"; rm -rf "$T/tmp"/*
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD" > "$REPO/.fable-team/seats-planner.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$LEDGER"
}
CLOSE_BIN="$T/bin/ft-nano-close.sh"
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT="${FEAT:-main}" \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 bash "$CLOSE_BIN" "$SEAT" "$@"; }
out_file() { mkdir -p "$NW/$(dirname "$OUT")"; printf '# 표\n값 1\n' > "$NW/$OUT"; }

section_a() {
  echo "== ⓐ(고침 1) 리서치 닫기 — 산출 경로 «전부» 가 --result 1개뿐이면 통과"
  setup; out_file; git -C "$NW" add -A; git -C "$NW" commit -q -m "산출 표 1"
  out="$(close --result "$NW/$OUT" --recv 1 --research)"; rc=$?
  [ "$rc" -eq 0 ] && has "$out" "RESEARCH-OK" "ⓐ 산출 커밋 1(--result 만) → rc0 RESEARCH-OK" || bad "ⓐ 산출 커밋 rc=$rc ← ${out:0:600}"
  has "$out" "산출 1경로만" "  └ ⑥ 자리 = 산출 1경로 인정 줄"
  setup; out_file
  out="$(close --result "$NW/$OUT" --recv 1 --research)"; rc=$?
  [ "$rc" -eq 0 ] && has "$out" "RESEARCH-OK" "ⓐ 산출 미커밋(--result 만) → rc0 RESEARCH-OK" || bad "ⓐ 산출 미커밋 rc=$rc ← ${out:0:600}"
  setup; out_file; echo 'print(1)' > "$NW/scripts/y.py"; git -C "$NW" add -A; git -C "$NW" commit -q -m "산출 + 코드"
  out="$(close --result "$NW/$OUT" --recv 1 --research)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "리서치 아님" "ⓐ 산출 + 다른 파일 1 커밋 → REJECT" || bad "ⓐ 산출+코드 커밋 rc=$rc ← ${out:0:600}"
  has "$out" "산출($OUT) 밖 경로 1개" "  └ 사유에 «산출 … 밖 경로 1개»"
  setup; out_file; git -C "$NW" add -A; git -C "$NW" commit -q -m "산출만"; echo 'print(2)' > "$NW/scripts/z.py"
  out="$(close --result "$NW/$OUT" --recv 1 --research)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "리서치 아님" "ⓐ 산출 커밋 + 다른 미커밋 1 → REJECT" || bad "ⓐ 산출커밋+미커밋 rc=$rc ← ${out:0:600}"
  setup; out_file; echo 'print(3)' > "$NW/scripts/w.py"; git -C "$NW" add -A; git -C "$NW" commit -q -m "산출 + 코드(경로 2)"
  git -C "$NW" rm -q "$OUT"; git -C "$NW" commit -q -m "산출 삭제(그물 0)"
  out="$(close --result "$NW/$OUT" --recv 1 --research)"; rc=$?   # 되돌림 뒤 산출 파일이 없다 → ① REJECT(경로 검사보다 먼저)
  [ "$rc" -eq 1 ] && has "$out" "①결과 경로 없음" "ⓐ 산출을 지운 꼴 → ① REJECT(경로 그물 밖)" || bad "ⓐ 삭제 꼴 rc=$rc ← ${out:0:500}"
}
echo "== ⓕ 변이 — 경로 검사를 빼면 ⓐ «다른 파일» 칸이 FAIL · 커밋 수만 0 허용으로 되돌리면 ⓐ «산출 커밋» 칸이 FAIL"
mutate() {  # mutate <표지> <바꿀 글> — 표지 줄을 바꾼 사본으로 섹션을 돌려 FAIL 이 나는지
  local mark="$1" repl="$2"
  python3 - "$T/bin/ft-nano-close.sh" "$T/bin/ft-nano-close.mut.sh" "$mark" "$repl" <<'PY'
import sys
src, dst, mark, repl = sys.argv[1:5]
lines = open(src, encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if mark in l]
assert len(hit) == 1, hit
lines[hit[0]] = repl
open(dst, "w", encoding="utf-8").write("\n".join(lines))
PY
}
CLOSE_BIN="$T/bin/ft-nano-close.sh"
mutate "# r978-mut:paths" '      done <<< ""'
CLOSE_BIN="$T/bin/ft-nano-close.mut.sh"; sub="$(section_a)"
case "$sub" in *"FAIL ⓐ 산출 + 다른 파일 1 커밋"*) ok "ⓕ 경로 검사 제거 → ⓐ 다른 파일 칸 FAIL";; *) bad "ⓕ 경로 검사 제거해도 ⓐ 다른 파일 칸이 통과(시험이 경로 검사를 못 잡음)";; esac
mutate "# r978-mut:count" '      elif [ "$_rs_n" -gt 0 ] || [ "$_rs_side" -gt 0 ] || [ "$_rs_dirty" -gt 0 ] || [ -n "$_rs_self" ]; then'
CLOSE_BIN="$T/bin/ft-nano-close.mut.sh"; sub="$(section_a)"
case "$sub" in *"FAIL ⓐ 산출 커밋 rc="*|*"FAIL ⓐ 산출 커밋 1(--result 만)"*) ok "ⓕ 커밋 수만 0 허용으로 되돌림 → ⓐ 산출 커밋 칸 FAIL";; *) bad "ⓕ 옛 규칙으로 되돌려도 ⓐ 산출 커밋 칸이 통과";; esac
CLOSE_BIN="$T/bin/ft-nano-close.sh"

# 고침 1 이 판을 바꾼 자리 밖: 외부 호출·600/300 초·GIT_* env 0 (r888 과 같은 줄 검사)
NEWL="$(grep 'r978\|_rs_out\|_rs_rok\|_rs_rel' "$SRC/ft-nano-close.sh")"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE '(^|[^0-9])(600|300)([^0-9]|$)')" ":" "ⓖ 600/300 숫자 0"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE 'curl|wget|https?://|gh |nc ')" ":" "ⓖ 외부 호출 0"
hasnt "$NEWL" "GIT_DIR=" "ⓖ GIT_DIR env 0"

section_a

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
