#!/usr/bin/env bash
# test_nano_close_card_ref_prefix_r1070.sh — r1070: 명부 index 에 «.worktrees/<이름>/» 접두가 붙어 있어도 ft-nano-close 가 FT_CARD_REF(기본 origin/main) 판 카드를 찾는다(접두 한 토막을 뗀 경로를 «원래 경로 다음» 후보로)
#   계기(실측): byz-v65 나노 4석의 명부 index = «.worktrees/v65-master-main/design/teams/v65/indices/진행/<카드>.md» → 조회 경로 «origin/main:.worktrees/…» 가 없어 hit 0 → 루트 체크아웃의 낡은 대기/ 사본(증거 줄 없음)을 읽어 ⑥ REJECT.
# 임시 git 리포 + bare origin + 가짜 tmux(PATH 앞)만 쓴다 — 실제 리포·명부·tmux 세션은 건드리지 않는다. GIT_* 환경 변수는 쓰지 않는다.
# 축 ⓐ R1 상대 접두 · ⓑ R2 절대경로 접두 → ⑥ 통과 + INFO «(워크트리 접두 뗌)» ⓒ R3 접두 없는 index = 지금 동작 그대로(INFO 표기 0)
#    ⓓ R4 접두를 떼도 ref 에 없음 → 작업 트리 후보로(접두 표기 0 · ⑥ REJECT) ⓔ R5 닫기 전후 루트 status·HEAD 불변
#    ⓕ 변이(접두 후보 끔 → ⓐ·ⓑ FAIL · 루트 ff 주입 → ⓔ FAIL) ⓖ bash -n · 키트 짝 cmp0 · 600/300·외부 호출·GIT_* 0
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

echo "== ⓖ 키트 2곳 같은 바이트 + bash -n"
cmp -s "$HERE/../../harness/bin/ft-nano-close.sh" "$SRC/ft-nano-close.sh" && ok "cmp ft-nano-close.sh (bin == kit)" || bad "cmp ft-nano-close.sh 다름"
bash -n "$SRC/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

mkdir -p "$T/bin" "$T/fake" "$T/tmp"
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"   # r1113 자식 정리 = 같은 bin 스텁(실 프로세스 0)
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-nano-superseded-check.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-wt-sweep.sh" "$T/bin/"
cp "$SRC/ft_teamset.py" "$SRC/ft-team-lib.sh" "$SRC/ft_git_capped.py" "$T/bin/"
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
git -C "$REPO" update-ref refs/remotes/origin/main HEAD   # 카드 단계 ref 실재(없으면 ERROR + REJECT)
git -C "$REPO" remote add origin "$ORIGIN"
mkdir -p "$REPO/.fable-team" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"

SEAT='byz-planner-nano-rs#0'; BR='nano/rs'; NW="$REPO/.worktrees/v65-rs"
OLD_REL='design/planner/indices/대기/rs.md'
PREFIX='.worktrees/v65-master-main'
IDX_PFX="$PREFIX/design/planner/indices/진행/rs.md"   # R1: 명부 index 꼴(워크트리 접두)
DONE_REL='design/planner/indices/완성/rs.md'
# 커밋 A = 루트 로컬이 머문 판(대기/ 옛 사본 · 증거 줄 없음)
mkdir -p "$REPO/design/planner/indices/대기"
printf '# 인덱스: rs\n## 상태\n- 대기\n' > "$REPO/$OLD_REL"
mkdir -p "$REPO/scripts"; echo 'print(0)' > "$REPO/scripts/x.py"
gitc add -A && gitc commit -q -m "A: 카드 대기"
SHA_A="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
# 커밋 B = ref 새 판(완성/ · 증거 줄) — origin 에만 올리고 로컬 main 은 A 로 되돌린다(루트가 뒤처진 꼴 = 실사건)
mkdir -p "$REPO/design/planner/indices/완성"
gitc mv "$OLD_REL" "$DONE_REL"
printf '# 인덱스: rs\n## 상태\n- 완성\n- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n' "$SHA_A" > "$REPO/$DONE_REL"
gitc add -A && gitc commit -q -m "B: 카드 완성 + 증거"
gitc push -q origin main
SHA_B="$(git -C "$REPO" rev-parse HEAD)"
gitc reset -q --hard "$SHA_A"; gitc clean -qfd
git -C "$REPO" rev-parse -q --verify refs/remotes/origin/main >/dev/null && ok "준비: origin/main = B · 로컬 main = A(대기/ 옛 사본 · 뒤처짐)" || bad "준비 실패"

LEDGER="$T/ledger.md"
run() { ( cd "$REPO" && env -i HOME="$HOME" TMPDIR="$T/tmp" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {  # 명부·pane·나노 HEAD 리셋 · 카드 = 루트 대기/ 옛 사본만 · origin/main = B
  git -C "$NW" reset -q --hard "$SHA_A"; git -C "$NW" clean -qfd
  gitc reset -q --hard "$SHA_A"; gitc clean -qfd -- design scripts
  mkdir -p "$REPO/.fable-team"
  git -C "$REPO" remote set-url origin "$ORIGIN"
  git -C "$ORIGIN" update-ref refs/heads/main "$SHA_B"; gitc update-ref refs/remotes/origin/main "$SHA_B"
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "${1:-$IDX_PFX}" > "$REPO/.fable-team/seats-planner.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$LEDGER"; rm -rf "$T/tmp"/*
}
CLOSE_BIN="$T/bin/ft-nano-close.sh"
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 bash "$CLOSE_BIN" "$SEAT" --result "$T/result.md" --recv 1 "$@"; }

echo "== ⓐ R1 상대 접두 index → ⑥ 통과 + INFO «(워크트리 접두 뗌)»"
setup; out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED" "ⓐ 접두 index → CLOSED rc0" || bad "ⓐ rc=$rc ← ${out:0:700}"
has "$out" "카드 위치 ← origin/main:$DONE_REL" "  └ INFO 카드 위치 ← origin/main:<완성/ 경로>"
has "$out" "워크트리 접두 뗌" "  └ INFO 줄 끝 «(워크트리 접두 뗌)»"
hasnt "$out" "카드 못 찾음" "  └ ⑥ «카드 못 찾음» 0"
has "$(cat "$REPO/$OLD_REL" 2>/dev/null)" "- 대기" "  └ 루트 대기/ 사본 안 바뀜(쓰기 0)"
[ ! -f "$REPO/$DONE_REL" ] && ok "  └ 루트에 완성/ 사본 만들지 않음" || bad "  └ 루트에 완성/ 사본 생김"
[ -z "$(ls -A "$T/tmp")" ] && ok "  └ 꺼낸 임시 카드 파일 정리" || bad "  └ 임시 파일 남음: $(ls -A "$T/tmp")"

echo "== ⓑ R2 절대경로 접두 index → ⓐ 와 같음"
setup "$REPO/$IDX_PFX"; out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED" "ⓑ 절대경로 접두 index → CLOSED rc0" || bad "ⓑ rc=$rc ← ${out:0:700}"
has "$out" "카드 위치 ← origin/main:$DONE_REL" "  └ INFO 카드 위치 ← origin/main:<완성/ 경로>"
has "$out" "워크트리 접두 뗌" "  └ INFO 줄 끝 «(워크트리 접두 뗌)»"

echo "== ⓒ R3 접두 없는 index(지금 꼴) → 지금 동작 그대로(접두 표기 0 · 작업 트리 사본으로 판정)"
setup 'design/planner/indices/진행/rs.md'
mkdir -p "$REPO/design/planner/indices/진행"
printf '# 인덱스: rs\n## 상태\n- 진행\n- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n' "$SHA_A" > "$REPO/design/planner/indices/진행/rs.md"
out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED" "ⓒ 접두 없음 → CLOSED rc0(회귀 0)" || bad "ⓒ rc=$rc ← ${out:0:700}"
hasnt "$out" "워크트리 접두 뗌" "  └ «(워크트리 접두 뗌)» 표기 0"
has "$out" "쓰기 = $REPO/design/planner/indices/진행/rs.md" "  └ ref 판은 읽기만(r888 그대로) · 쓰기 = 작업 트리 진행/ 사본"

echo "== ⓓ R4 접두를 떼도 ref 에 카드 없음 → 작업 트리 후보로(접두 표기 0 · ⑥ REJECT)"
setup
gitc checkout -q -B tmpdrop "$SHA_B"; gitc rm -q "$DONE_REL"; gitc commit -q -m "C: 카드 없음"
gitc push -q origin tmpdrop:main; SHA_C="$(git -C "$REPO" rev-parse HEAD)"
gitc reset -q --hard "$SHA_A"; gitc clean -qfd -- design scripts
git -C "$ORIGIN" update-ref refs/heads/main "$SHA_C"; gitc update-ref refs/remotes/origin/main "$SHA_C"
out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "⑥카드 못 찾음" "ⓓ ref 에 카드 없음 → ⑥ «카드 못 찾음» REJECT" || bad "ⓓ rc=$rc ← ${out:0:700}"
hasnt "$out" "워크트리 접두 뗌" "  └ «(워크트리 접두 뗌)» 표기 0"
grep -q 'CLOSED' <<< "$out" && bad "ⓓ 닫힘 0 이어야 함" || ok "  └ CLOSED 0"
gitc update-ref refs/remotes/origin/main "$SHA_B"; git -C "$ORIGIN" update-ref refs/heads/main "$SHA_B"; gitc update-ref -d refs/heads/tmpdrop 2>/dev/null

echo "== ⓔ R5 닫기 전후 루트 체크아웃 status·HEAD 같음"
setup; before_st="$(gitc status --porcelain)"; before_hd="$(git -C "$REPO" rev-parse HEAD)"
out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓔ 닫힘 rc0" || bad "ⓔ rc=$rc ← ${out:0:600}"
[ "$before_st" = "$(gitc status --porcelain)" ] && ok "ⓔ 루트 status 불변" || bad "ⓔ 루트 status 바뀜"
[ "$before_hd" = "$(git -C "$REPO" rev-parse HEAD)" ] && ok "ⓔ 루트 HEAD 불변(A 그대로)" || bad "ⓔ 루트 HEAD 바뀜 → $(git -C "$REPO" rev-parse --short HEAD)"

echo "== ⓕ 변이 — 접두 후보 끔 → ⓐ FAIL · 루트 ff 주입 → ⓔ FAIL"
mutate() {  # mutate <표지> <바꿀 글>
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
mutate "# r1070-mut:wtreffix" ':'
CLOSE_BIN="$T/bin/ft-nano-close.mut.sh"
setup; o1="$(close)"; rc1=$?
[ "$rc1" -eq 1 ] && has "$o1" "카드 못 찾음" "ⓕ 접두 후보 끔 → ⓐ REJECT «카드 못 찾음»" || bad "ⓕ 접두 후보 꺼도 rc=$rc1 ← ${o1:0:500}"
hasnt "$o1" "워크트리 접두 뗌" "  └ 접두 표기 0"
mutate "# r888-mut:cardref" '_card_ref_read; git -C "$ROOT" merge -q --ff-only origin/main >/dev/null 2>&1 || :'
setup; before_hd="$(git -C "$REPO" rev-parse HEAD)"
o2="$(close)"; [ "$before_hd" = "$(git -C "$REPO" rev-parse HEAD)" ] && bad "ⓕ 루트 ff 주입해도 ⓔ 통과(시험이 루트 불변을 못 잡음)" || ok "ⓕ 루트 ff 주입 → ⓔ FAIL(불변 대조가 잡음)"
CLOSE_BIN="$T/bin/ft-nano-close.sh"

echo "== ⓖ 600/300 s · 외부 호출 · GIT_* env 0 (r1070 줄)"
NEWL="$(grep 'r1070\|_r1070_strip_wt\|워크트리 접두' "$SRC/ft-nano-close.sh")"
[ -n "$NEWL" ] && ok "ⓖ r1070 줄 실재" || bad "ⓖ r1070 줄 0"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE '(^|[^0-9])(600|300)([^0-9]|$)')" ":" "ⓖ 600/300 숫자 0"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE 'curl|wget|https?://|gh |nc ')" ":" "ⓖ 외부 호출 0"
hasnt "$NEWL" "GIT_DIR=" "ⓖ GIT_DIR env 0"
hasnt "$NEWL" "GIT_WORK_TREE=" "ⓖ GIT_WORK_TREE env 0"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
