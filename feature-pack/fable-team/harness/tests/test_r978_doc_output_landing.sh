#!/usr/bin/env bash
# test_r978_doc_output_landing.sh — r978: 조사·문서 산출(코드 0)이 «닫기» 와 «완성» 게이트에서 오빠 h 없이 흐르게
#   고침 1(ft-nano-close.sh --research) — 커밋·미커밋이 있어도 그 경로 «전부» 가 --result 1개뿐이면 통과(r976 꼴) · 그 밖 경로 1개라도 있으면 REJECT
#   고침 2(ft-finished-check.sh · ft-index-move-canon.sh) — «설치: 없음 ∧ 문서 가지 조상 ∧ 바꾼 경로 전부 design/**.md» 셋 다일 때만 문서 가지 착지 인정
#   고침 3(r2 반송 r1 · DA HOLD 3) — «바뀐 경로 목록» 읽기 도우미 1개(ft-team-lib.sh ft_changed_paths/ft_changed_paths_wt)를 세 자리가 같이 쓴다:
#     이름 변경 = 삭제+추가 둘 다(--no-renames · 미커밋 R/C 는 원경로·새경로 둘 다)
#   고침 4(r2 반송 r2 · DA r2 HOLD 3) — `-c core.quotePath=false` 로도 git 은 «따옴표·역슬래시·공백(미추적)» 경로를 인용한다 → 경로 목록은 -z(NUL)로 받아 자른다(mktemp + RETURN trap 정리)
# 임시 git 리포 + bare origin + 가짜 tmux(PATH 앞)만 쓴다 — 실제 리포·명부·tmux 세션은 건드리지 않는다. GIT_* 환경 변수는 쓰지 않는다.
#   변이: 경로 검사 빼고 커밋 수만 0 허용 → ⓐ 다른 파일 칸 FAIL · 설치: 없음 조건 제거 → ⓑ 설치: 있음 칸 FAIL · 한 자리만 새 함수 → ⓑ 한쪽 FAIL
#         --no-renames 제거 → ⓒ 도우미 단위 FAIL · R/C 확장 제거 → ⓒ 미커밋 R 칸 FAIL · -z 제거 → ⓒ 반례 4·5·6 칸 FAIL
#         (quotePath 끄기 제거 변이는 -z 가 인용을 없애 «뜻이 없는 변이» 가 되므로 폐기 — 통과해도 당연한 것을 綠 로 세지 않는다)
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
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"   # r1113 자식 정리 = 같은 bin 스텁(실 프로세스 0)
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
  git -C "$REPO" config --unset core.quotePath 2>/dev/null; git -C "$REPO" config --unset-all core.quotePath 2>/dev/null
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
mutate "# r978-mut:paths" '      _rs_out=0; _rs_paths=""; _rs_prc=0'
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

section_b() {
echo "== ⓑ(고침 2) 완성 인정 — «설치: 없음 ∧ 문서 가지 조상 ∧ 바뀜 경로 전부 design/**.md» 셋 다일 때만"
# ── 완성 게이트 픽스처: R2 = 카드 리포 · origin/main 은 문서 커밋을 «모른다» · origin/ops/main-base 가 문서 가지
rm -rf "$T/R2"; R2="$T/R2"; mkdir -p "$R2/design/teams/harness/indices/완성" "$R2/.fable-team/state" "$T/fcbin"
printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | h | 현역 |\n' > "$R2/design/TEAMS.md"
echo r > "$R2/README"
G2() { git -C "$R2" -c user.name=t -c user.email=t@t "$@"; }
git -C "$R2" init -q -b main && G2 add design README && G2 commit -qm base
git -C "$R2" update-ref refs/remotes/origin/main HEAD
printf '#!/bin/sh\n[ "$1" = list-sessions ] && exit 0\nexit 0\n' > "$T/fcbin/tmux"; chmod 755 "$T/fcbin/tmux"
mkdir -p "$R2/design/harness/evidence/r978"
# 문서 커밋 1(design/**.md 만) = 문서 가지 ref 에만 있다(main 은 모름)
G2 checkout -q -b docs
printf '# 조사 표\n값 1\n' > "$R2/design/harness/evidence/r978/TABLE-doc1.md"; G2 add -A; G2 commit -qm "문서 산출 1"
DOCSHA="$(git -C "$R2" rev-parse HEAD)"; git -C "$R2" update-ref refs/remotes/origin/ops/main-base "$DOCSHA"
# 문서 커밋 2(design/**.md + .sh) = 경로 섬임
printf '#!/bin/sh\necho x\n' > "$R2/design/harness/evidence/r978/x.sh"; G2 add -A; G2 commit -qm "문서 + 코드"
DOCSH="$(git -C "$R2" rev-parse HEAD)"; git -C "$R2" update-ref refs/remotes/origin/ops/mixed "$DOCSH"
G2 checkout -q main
nb() { TREE="$(git -C "$R2" rev-parse 'main^{tree}')"; C="$(G2 commit-tree "$TREE" -p main -m "$1")"; git -C "$R2" update-ref "refs/heads/nano/$1" "$C"; }
nb doc1; nb doc2; nb doc3; nb doc4; nb doc5
fcard() { local n="$1" sha="$2" inst="${3:-없음}"; printf '# 인덱스: %s\n## 상태\n- 설치: %s\n- 정본 영향 없음: 문서 카드라 정본 갱신 없음\n- 착지: %s\n' "$n" "$inst" "$sha" > "$R2/design/teams/harness/indices/완성/$n.md"; }
fc3() { OUT2="$(cd "$R2" && env FT_DOC_LAND_REF="$2" FT_TMUX_BIN="$T/fcbin/tmux" FT_FINISHED_CARD_ROOTS="$R2" FT_SEATS_DIR="$R2/.fable-team" FT_FINISHED_MAIN=origin/main bash "$T/bin/ft-finished-check.sh" "$1" --repo "$R2" 2>&1)"; RC2=$?; V2="${OUT2%%$'\n'*}"; V2="${V2%% *}"; }
fc2() { OUT2="$(cd "$R2" && env FT_TMUX_BIN="$T/fcbin/tmux" FT_FINISHED_CARD_ROOTS="$R2" FT_SEATS_DIR="$R2/.fable-team" FT_FINISHED_MAIN=origin/main bash "$T/bin/ft-finished-check.sh" "$1" --repo "$R2" 2>&1)"; RC2=$?; V2="${OUT2%%$'\n'*}"; V2="${V2%% *}"; }
fcard doc1 "$DOCSHA"; fc2 nano/doc1
{ [ "$RC2" = 0 ] && [ "$V2" = FINISHED ] && printf '%s' "$OUT2" | grep -q '^E1 ok 착지 .* ⊂ origin/ops/main-base(문서 카드'; } \
  && ok "ⓑ 설치: 없음 + 문서 가지 조상 + .md 만 → FINISHED(E1 ok … 문서 카드)" || bad "ⓑ 인정 칸 rc=$RC2 [$OUT2]"
fcard doc2 "$DOCSH"; fc3 nano/doc2 origin/ops/mixed   # 문서 가지 = 그 커밋이 들어 있는 ref(mixed)
{ [ "$V2" = ACTIVE ] && printf '%s' "$OUT2" | grep -q 'design/\*\*.md 밖 경로: design/harness/evidence/r978/x.sh'; } \
  && ok "ⓑ .sh 섞임(경로 검사) → 인정 0(ACTIVE · 밖 경로 첫 줄)" || bad "ⓑ .sh 섞임 [$OUT2]"
fcard doc3 "$DOCSHA" 있음; fc2 nano/doc3
{ [ "$V2" = ACTIVE ] && printf '%s' "$OUT2" | grep -q 'design/\*\*.md 밖\|설치: 없음.* 아니다'; } \
  && ok "ⓑ 설치: 있음 + 문서 가지 조상 → 인정 0(ACTIVE)" || bad "ⓑ 설치: 있음 [$OUT2]"
# origin/main 조상 카드 = 지금과 같음(main 에 착지한 카드)
LANDS="$(G2 commit-tree "$(git -C "$R2" rev-parse 'main^{tree}')" -p main -m "main 착지")"; G2 update-ref refs/heads/main "$LANDS"; git -C "$R2" update-ref refs/remotes/origin/main "$LANDS"
fcard doc4 "$LANDS" 있음; fc2 nano/doc4
{ [ "$V2" = FINISHED ] && printf '%s' "$OUT2" | grep -q '^E1 ok 착지 .* ⊂ origin/main$'; } && ok "ⓑ origin/main 착지 카드는 지금 그대로(FINISHED · E1 ok ⊂ origin/main)" || bad "ⓑ main 착지 [$OUT2]"
# 문서 가지 ref 없음 → 인정 0(동작 불변 · 판정 불가로 안 끝남)
fcard doc5 "$DOCSHA"; fc2_2() { OUT2="$(cd "$R2" && env FT_DOC_LAND_REF=origin/ops/none FT_TMUX_BIN="$T/fcbin/tmux" FT_FINISHED_CARD_ROOTS="$R2" FT_SEATS_DIR="$R2/.fable-team" FT_FINISHED_MAIN=origin/main bash "$T/bin/ft-finished-check.sh" "$1" --repo "$R2" 2>&1)"; RC2=$?; V2="${OUT2%%$'\n'*}"; V2="${V2%% *}"; }
fc2_2 nano/doc5
{ [ "$RC2" = 0 ] && [ "$V2" = ACTIVE ]; } && ok "ⓑ 문서 가지 ref 없음 → ACTIVE(인정 0 · rc0)" || bad "ⓑ ref 없음 rc=$RC2 [$OUT2]"
# ft-index-move-canon.sh — 같은 판정 함수를 두 번째 자리에서도 부른다
imc() { printf '## 상태\n- 정본 영향 없음: 문서 카드라 정본 갱신 없음\n' | ( cd "$R2" && env FT_LAND_REF=origin/main FT_DOC_LAND_REF="$1" bash "$T/bin/ft-index-move-canon.sh" "$R2/design/teams/harness/indices/완성/$2.md" "$R2" "$3" 2>&1 ); }
fcard doc1 "$DOCSHA"; o="$(imc origin/ops/main-base doc1 "$DOCSHA")"
{ case "$o" in *"착지 인정 = 인정 ref origin/ops/main-base"*) true;; *) false;; esac; } && ok "ⓑ index-move-canon: 문서 카드 착지 인정 1줄" || bad "ⓑ imc 인정 [$o]"
o="$(imc origin/ops/main-base doc3 "$DOCSHA")"
{ case "$o" in REJECT*) true;; *) false;; esac; } && ok "ⓑ index-move-canon: 설치: 있음 카드는 REJECT(동작 불변)" || bad "ⓑ imc 설치: 있음 [$o]"
}
echo "== ⓕ(고침 2) 변이 — «설치: 없음» 검사를 빼면 ⓑ 설치: 있음 칸 FAIL · 두 자리 중 한 곳(imc)만 새 함수면 ⓑ imc 인정 칸 FAIL"
mutate_f() {  # mutate_f <src> <표지> <바꿀 글> <출력이름>
  python3 - "$1" "$T/bin/$4" "$2" "$3" <<'PY'
import sys
src, dst, mark, repl = sys.argv[1:5]
lines = open(src, encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if mark in l]
assert len(hit) == 1, hit
lines[hit[0]] = repl
open(dst, "w", encoding="utf-8").write("\n".join(lines))
PY
}
mutate_f "$T/bin/ft-team-lib.sh" '# r978-mut:setup' '  :' ft-team-lib.mut.sh
cp "$T/bin/ft-team-lib.mut.sh" "$T/bin/ft-team-lib.sh"
sub="$(section_b)"; case "$sub" in *"FAIL ⓑ 설치: 있음"*) ok "ⓕ 설치: 없음 조건 제거 → ⓑ 설치: 있음 칸 FAIL";; *) bad "ⓕ 설치 조건 제거해도 ⓑ 설치: 있음 칸이 통과";; esac
cp "$SRC/ft-team-lib.sh" "$T/bin/ft-team-lib.sh"
mutate_f "$T/bin/ft-index-move-canon.sh" '# r978-mut:imc' '  _drc=1' ft-index-move-canon.mut.sh
cp "$T/bin/ft-index-move-canon.mut.sh" "$T/bin/ft-index-move-canon.sh"
sub="$(section_b)"; case "$sub" in *"FAIL ⓑ imc 인정"*) ok "ⓕ imc 한 자리만 판정 함수를 끔 → ⓑ imc 인정 칸 FAIL(두 자리 공유 확인)";; *) bad "ⓕ imc 자리를 꺼도 ⓑ imc 칸이 통과";; esac
cp "$SRC/ft-index-move-canon.sh" "$T/bin/ft-index-move-canon.sh"

doc_land() {  # doc_land <리포> <문서파일이름> — «공통 함수 rc» · «imc 출력» 두 줄(문서 카드 픽스쳐 새로 만든다)
  local R="$1" nm="$2" G3 DOC3 CARD3 o
  rm -rf "$R"; mkdir -p "$R/design/teams/harness/indices/완성" "$R/.fable-team/state" "$R/design/harness/evidence/r978"
  printf '| 팀 | 폴더 | 오케 | 상태 |\n|---|---|---|---|\n| harness | `design/teams/harness/` | h | 현역 |\n' > "$R/design/TEAMS.md"
  G3() { git -C "$R" -c user.name=t -c user.email=t@t "$@"; }
  git -C "$R" init -q -b main && G3 add design && G3 commit -qm base && git -C "$R" config core.quotePath true
  git -C "$R" update-ref refs/remotes/origin/main HEAD
  G3 checkout -q -b docs; printf '# 조사 표\n값 1\n' > "$R/design/harness/evidence/r978/$nm"; G3 add -A; G3 commit -qm "문서 산출 1"
  DOC3="$(git -C "$R" rev-parse HEAD)"; git -C "$R" update-ref refs/remotes/origin/ops/main-base "$DOC3"
  CARD3="$R/design/teams/harness/indices/완성/doc-land.md"
  printf '# 인덱스: doc\n## 상태\n- 설치: 없음\n- 정본 영향 없음: 문서 카드라 정본 갱신 없음\n- 착지: %s\n' "$DOC3" > "$CARD3"
  o="$( cd "$R" && bash -c '. "$1/ft-team-lib.sh"; ft_doc_card_landed "$2" "$3" "$4"' _ "$T/bin" "$R" "$DOC3" "$CARD3" 2>&1 )"; echo "①$? · ${o//$'\n'/ }"
  o="$( printf '## 상태\n- 정본 영향 없음: 문서 카드라 정본 갱신 없음\n' | ( cd "$R" && env FT_LAND_REF=origin/main FT_DOC_LAND_REF=origin/ops/main-base bash "$T/bin/ft-index-move-canon.sh" "$CARD3" "$R" "$DOC3" 2>&1 ) )"; echo "②${o//$'\n'/ }"
}

section_c() {
echo "== ⓒ(r2 반송 r1·r2) «바뀐 경로 목록» — 이름 변경은 삭제+추가 둘 다 · 한글·공백·따옴표·역슬래시 경로 인용 끔(-z)"
KO='design/harness/evidence/r978/조사.md'
# ① 반례 1(커밋) — 코드 경로를 문서 이름으로 git mv 한 커밋 → 옛 코드 경로가 «밖 경로»
setup; mkdir -p "$NW/design/harness/evidence/r978"; git -C "$NW" mv scripts/x.py "$OUT"; git -C "$NW" commit -q -m "코드→문서 이름 변경"
out="$(close --result "$NW/$OUT" --recv 1 --research)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "리서치 아님" "ⓒ 반례 1 이름 변경(커밋) → REJECT" || bad "ⓒ 반례 1 커밋 rc=$rc ← ${out:0:600}"
has "$out" "밖 경로 1개" "  └ 사유에 «밖 경로 1개» — 옛 코드 경로를 건너뛰지 않는다"
# ①' 같은 이름 변경을 «커밋 전»(staged R)에 둔 꼴 — 원경로를 먹지 않는다
setup; mkdir -p "$NW/design/harness/evidence/r978"; git -C "$NW" mv scripts/x.py "$OUT"
out="$(close --result "$NW/$OUT" --recv 1 --research)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "리서치 아님" "ⓒ 반례 1 이름 변경(미커밋 R) → REJECT" || bad "ⓒ 반례 1 미커밋 R rc=$rc ← ${out:0:600}"
# ② 반례 2 — core.quotePath=true 에서 한글 .md 1개만 바꿔도 «산출» 로 읽힌다
setup; git -C "$REPO" config core.quotePath true; mkdir -p "$NW/design/harness/evidence/r978"; printf '# 표\n값 1\n' > "$NW/$KO"; git -C "$NW" add -A; git -C "$NW" commit -q -m "한글 문서 산출"
out="$(close --result "$NW/$KO" --recv 1 --research)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "RESEARCH-OK" "ⓒ 반례 2 한글 경로(커밋 · quotePath=true) → rc0" || bad "ⓒ 반례 2 커밋 rc=$rc ← ${out:0:600}"
setup; git -C "$REPO" config core.quotePath true; mkdir -p "$NW/design/harness/evidence/r978"; printf '# 표\n값 1\n' > "$NW/$KO"
out="$(close --result "$NW/$KO" --recv 1 --research)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "RESEARCH-OK" "ⓒ 반례 2 한글 경로(미커밋 · quotePath=true) → rc0" || bad "ⓒ 반례 2 미커밋 rc=$rc ← ${out:0:600}"
git -C "$REPO" config --unset-all core.quotePath 2>/dev/null
# ③ 반례 3 — 같은 한글 .md 커밋을 문서 가지가 가리키고 카드 «설치: 없음» → 공통 함수도 imc 도 인정
D1="$(doc_land "$T/R3" '조사.md')"; o3="$D1"
case "$o3" in "①0"*"인정 ref origin/ops/main-base"*) ok "ⓒ 반례 3 공통 함수: 한글 .md + 설치: 없음 + 문서 가지 조상 → 인정 rc0";; *) bad "ⓒ 반례 3 함수 [$o3]";; esac
case "$o3" in *"②착지 인정 = 인정 ref origin/ops/main-base"*) ok "ⓒ 반례 3 index-move-canon: «착지 인정 = … origin/ops/main-base» 1줄";; *) bad "ⓒ 반례 3 imc [$o3]";; esac
# ④ 도우미 단위 — /bin/bash 3.2 로 1회 고정(커밋 목록 = 삭제+추가 2줄 · 미커밋 R = 원경로·새경로 2줄)
setup; mkdir -p "$NW/design/harness/evidence/r978"; git -C "$NW" mv scripts/x.py "$OUT"; git -C "$NW" commit -q -m "이름 변경"
u1="$( cd "$NW" && /bin/bash -c '. "$1/ft-team-lib.sh"; ft_changed_paths "$2" "$3" HEAD; echo "rc=$?"' _ "$T/bin" "$NW" "$SHA_A" 2>&1 )"
setup; mkdir -p "$NW/design/harness/evidence/r978"; git -C "$NW" mv scripts/x.py "$OUT"
u2="$( cd "$NW" && /bin/bash -c '. "$1/ft-team-lib.sh"; ft_changed_paths_wt "$2"; echo "rc=$?"' _ "$T/bin" "$NW" 2>&1 )"
U1="$( printf '%s\n' "$u1" | grep -v '^rc=' | sort | tr '\n' ' ')"; U2="$( printf '%s\n' "$u2" | grep -v '^rc=' | cut -f2 | sort | tr '\n' ' ')"
{ [ "$U1" = "$( printf '%s\n%s\n' "$OUT" scripts/x.py | sort | tr '\n' ' ')" ] && [ "$U2" = "$U1" ] \
    && printf '%s\n' "$u1" | grep -qx 'rc=0' && printf '%s\n' "$u2" | grep -qx 'rc=0'; } \
  && ok "ⓒ 도우미 단위(/bin/bash 3.2): 커밋 = 삭제+추가 2줄 · 미커밋 R = 원경로+새경로 2줄" || bad "ⓒ 도우미 단위 ← [$U1] / [$U2]"
# ⑤ 반례 4·5(DA r2) — 공백·따옴표·역슬래시 경로: git 은 quotePath=false 에서도 따옴표로 감싼다 → -z 로 받아야 «산출» 로 읽힌다
SP='design/harness/evidence/r978/my report.md'; QQ='design/harness/evidence/r978/a"b.md'; BS='design/harness/evidence/r978/a\b.md'
setup; mkdir -p "$NW/design/harness/evidence/r978"; printf '# 표\n값 1\n' > "$NW/$SP"
out="$(close --result "$NW/$SP" --recv 1 --research)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "RESEARCH-OK" "ⓒ 반례 4 공백 경로(미추적) → rc0" || bad "ⓒ 반례 4 미추적 rc=$rc ← ${out:0:600}"
setup; mkdir -p "$NW/design/harness/evidence/r978"; printf '# 표\n값 1\n' > "$NW/$SP"; git -C "$NW" add -A
out="$(close --result "$NW/$SP" --recv 1 --research)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "RESEARCH-OK" "ⓒ 반례 4 공백 경로(staged) → rc0" || bad "ⓒ 반례 4 staged rc=$rc ← ${out:0:600}"
setup; mkdir -p "$NW/design/harness/evidence/r978"; printf '# 표\n값 1\n' > "$NW/$QQ"; git -C "$NW" add -A; git -C "$NW" commit -q -m "따옴표 문서"
out="$(close --result "$NW/$QQ" --recv 1 --research)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "RESEARCH-OK" "ⓒ 반례 5 따옴표 든 경로(커밋) → rc0" || bad "ⓒ 반례 5 따옴표 rc=$rc ← ${out:0:600}"
setup; mkdir -p "$NW/design/harness/evidence/r978"; printf '# 표\n값 1\n' > "$NW/$BS"; git -C "$NW" add -A; git -C "$NW" commit -q -m "역슬래시 문서"
out="$(close --result "$NW/$BS" --recv 1 --research)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "RESEARCH-OK" "ⓒ 반례 5 역슬래시 든 경로(커밋) → rc0" || bad "ⓒ 반례 5 역슬래시 rc=$rc ← ${out:0:600}"
setup; mkdir -p "$NW/design/harness/evidence/r978"; printf '# 표\n값 1\n' > "$NW/$QQ"
out="$(close --result "$NW/$QQ" --recv 1 --research)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "RESEARCH-OK" "ⓒ 반례 5 따옴표 든 경로(미커밋) → rc0" || bad "ⓒ 반례 5 미커밋 rc=$rc ← ${out:0:600}"
# ⑥ 반례 6(DA r2) — 따옴표 든 문서 커밋이 문서 가지 조상 + 카드 «설치: 없음» → 공통 함수 인정 + imc 인정 줄
D6="$(doc_land "$T/R6" 'a"b.md')"
case "$D6" in "①0"*"인정 ref origin/ops/main-base"*) ok "ⓒ 반례 6 공통 함수: 따옴표 든 .md + 설치: 없음 + 문서 가지 조상 → 인정 rc0";; *) bad "ⓒ 반례 6 함수 [$D6]";; esac
case "$D6" in *"②착지 인정 = 인정 ref origin/ops/main-base"*) ok "ⓒ 반례 6 index-move-canon: «착지 인정 = … origin/ops/main-base» 1줄";; *) bad "ⓒ 반례 6 imc [$D6]";; esac
}

echo "== ⓕ(r2) 변이 — --no-renames · -z · R/C 확장을 하나씩 빼면 그 ⓒ 칸이 FAIL(quotePath 변이는 -z 도입으로 뜻이 없어 폐기)"
mutate_f "$T/bin/ft-team-lib.sh" '# r978-mut:norenames' '_FT_GIT_NOREN=(--no-color)' ft-team-lib.mut.sh
cp "$T/bin/ft-team-lib.mut.sh" "$T/bin/ft-team-lib.sh"
sub="$(section_c)"; case "$sub" in *"FAIL ⓒ 반례 1 이름 변경(커밋)"*|*"FAIL ⓒ 반례 1 커밋 rc="*|*"FAIL ⓒ 도우미 단위"*) ok "ⓕ --no-renames 제거 → ⓒ 도우미 단위 칸 FAIL";; *) bad "ⓕ --no-renames 를 빼도 ⓒ 이름 변경 칸이 통과";; esac
cp "$SRC/ft-team-lib.sh" "$T/bin/ft-team-lib.sh"
# quotePath 변이는 r2 에서 뜻이 없어짐 — -z 는 경로를 인용하지 않으므로 `-c core.quotePath=false` 를 빼도 ⓒ 한글 칸이 그대로 통과한다.
#   통과해도 당연한 것을 綠 로 세면 측정 조작이 되므로 목록에서 빼고, 그 자리는 -z 변이가 맡는다.
mutate_f "$T/bin/ft-team-lib.sh" '# r978-mut:renames' "      case \"\${e:0:2}\" in *R*|*C*) IFS= read -r -d '' p;; esac" ft-team-lib.mut.sh
cp "$T/bin/ft-team-lib.mut.sh" "$T/bin/ft-team-lib.sh"
sub="$(section_c)"; case "$sub" in *"FAIL ⓒ 반례 1 미커밋 R rc="*) ok "ⓕ 미커밋 R 확장 제거 → ⓒ 이름 변경(미커밋 R) 칸 FAIL";; *) bad "ⓕ 미커밋 R 확장을 빼도 ⓒ 칸이 통과";; esac
cp "$SRC/ft-team-lib.sh" "$T/bin/ft-team-lib.sh"
mutate_f "$T/bin/ft-team-lib.sh" '# r978-mut:zsep' '_FT_GIT_Z=(--no-color)' ft-team-lib.mut.sh
cp "$T/bin/ft-team-lib.mut.sh" "$T/bin/ft-team-lib.sh"
sub="$(section_c)"; case "$sub" in *"FAIL ⓒ 반례 4"*|*"FAIL ⓒ 반례 5"*|*"FAIL ⓒ 반례 6"*) ok "ⓕ -z 제거 → ⓒ 반례 4·5·6(공백·따옴표·역슬래시) 칸 FAIL";; *) bad "ⓕ -z 를 빼도 ⓒ 공백·따옴표 칸이 통과";; esac
cp "$SRC/ft-team-lib.sh" "$T/bin/ft-team-lib.sh"

section_a
section_b
section_c

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
