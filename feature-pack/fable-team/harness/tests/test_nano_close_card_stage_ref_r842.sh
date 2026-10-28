#!/usr/bin/env bash
# test_nano_close_card_stage_ref_r842.sh — r842: ft-nano-close.sh 카드 «단계» = ref 트리(ft_card_stage_ref) · 디스크 사본은 그 단계에서만 WT→LEDGER_WT→ROOT
# 임시 git 리포 + bare origin + 가짜 tmux(PATH 앞)만 쓴다 — 실제 리포·명부·tmux 세션은 건드리지 않는다. GIT_* 환경 변수는 쓰지 않는다.
# 축 ⓐ origin/main = 완성/ · ROOT 디스크 = 진행/ 옛 사본 · LEDGER_WT 디스크 = 완성/ → LEDGER_WT 완성/ 사본 + «INFO 카드 단계(origin/main) ← 완성»
#    ⓑ origin/main 에 카드 없음 → 지금 규칙 그대로(단계 줄 0) ⓒ 그 단계 디스크 사본 없음 → REJECT «디스크 사본 없음 … 낡은 사본» · 옛 단계 후퇴 0
#    ⓓ ref 못 읽음(FT_CARD_REF 명시 · 원격 있는데 ref 없음 · 원격 자체가 없음) → ERROR 1줄 + REJECT · 옛 규칙 후퇴 0 ⓔ 나노 WT 안 진행/ 카드 · origin/main 도 진행/ → WT 사본 그대로
#    ⓓ3 DA⑥ r2 반례(ref 에 TEAMS.md 없음 + 완성/ 카드 + ROOT 옛 진행/) → 완성/ 사본 선택 · 옛 진행/ 선택 0
#    ⓓ4 ls-tree 실패 주입(가짜 git 이 ls-tree 에만 rc128) → ERROR + REJECT ⓓ5 단계 함수가 빈 출력 rc0 → ERROR + REJECT(빈 출력은 «카드 없음»이 아니다)
#    ⓓ6 문지기(단계 함수 없는 lib → REJECT · 팀 카드 꼴 아닌 idx → 단계 판정 0)
#    ⓓ7 lib 통째로 없음 + 팀 카드 꼴 → REJECT(r3 반례 1) ⓓ7b 같은 입력 + 원격 없음 → REJECT ⓓ8 기존 Python 4파일 = 기준판과 같은 통과 수
#    ⓔ' ABSENT + ROOT 대기/ 사본(증거 줄 없음) + 나노 WT 진행/ 사본 유효 → 나노 WT 사본으로 닫힘(DA⑥ r4 반례 · IDX 우선 집기는 단계가 정해졌을 때만)
#    ⓗ ft_card_stage_ref 단위(STAGE 완성 · ABSENT · 2+ ERROR · ref 없음 ERROR · idx 꼴 ERROR · 명단 없는 ref 도 STAGE)
#    ⓖ 변이(단계 제거 → ⓐ FAIL · ⓒ 를 옛 단계 후퇴로 → ⓒ FAIL · 조회 실패를 «카드 없음» 으로 → ⓓ·ⓓ2·ⓓ5 FAIL · 빈 출력을 없음으로 → ⓓ5 FAIL · 명부 없음 = ABSENT → ⓓ3 FAIL) + 키트 짝 cmp0 · bash -n
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
for f in ft-nano-close.sh ft-team-lib.sh; do
  cmp -s "$HERE/../../harness/bin/$f" "$SRC/$f" && ok "cmp $f (bin == kit)" || bad "cmp $f 다름"
  bash -n "$SRC/$f" && ok "bash -n $f" || bad "bash -n $f"
done

mkdir -p "$T/bin" "$T/fake" "$T/tmp"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-team-lib.sh" "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-nano-superseded-check.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-wt-sweep.sh" "$T/bin/"
cp "$SRC/ft_teamset.py" "$T/bin/"
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
cp "$T/bin/ft-team-lib.sh" "$T/lib.orig"   # r842 변이 — 단계 함수 원판(변이 때마다 여기서 다시 만든다)
restore_lib() { cp "$T/lib.orig" "$T/bin/ft-team-lib.sh"; }

ORIGIN="$T/origin.git"; git init -q --bare "$ORIGIN"
REPO="$T/repo"; mkdir -p "$REPO"
gitc() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
git -C "$REPO" init -q -b main && git -C "$REPO" remote add origin "$ORIGIN"
mkdir -p "$REPO/design" "$REPO/.fable-team" "$T/comm/bodies"
printf '| 팀 | 폴더 |\n|---|---|\n| planner | design/planner/ |\n' > "$REPO/design/TEAMS.md"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
gitc add -A && gitc commit -q -m "A0: 명단"
SHA_A0="$(git -C "$REPO" rev-parse HEAD)"
SEAT='byz-planner-nano-cs#0'; BR='nano/cs'; NW="$REPO/.worktrees/v65-cs"; LW="$T/ledger-wt"
PRG='design/planner/indices/진행/cs.md'; DONE='design/planner/indices/완성/cs.md'
git -C "$REPO" worktree add -q "$NW" -b "$BR"   # 나노 = A0(카드 없음)
# A = 루트 로컬이 머문 판(진행/ 옛 사본 · 증거 줄 없음) · B = origin/main(완성/ 으로 옮김 · 증거 줄 아직 없음)
mkdir -p "$REPO/design/planner/indices/진행"; printf '# 인덱스: cs\n## 상태\n- 진행\n' > "$REPO/$PRG"
gitc add design && gitc commit -q -m "A: 카드 진행"; SHA_A="$(git -C "$REPO" rev-parse HEAD)"
mkdir -p "$REPO/design/planner/indices/완성"; gitc mv "$PRG" "$DONE"; printf '# 인덱스: cs\n## 상태\n- 완성\n' > "$REPO/$DONE"
gitc add design && gitc commit -q -m "B: 카드 완성"; SHA_B="$(git -C "$REPO" rev-parse HEAD)"
gitc push -q origin main; gitc reset -q --hard "$SHA_A"
git -C "$REPO" worktree add -q --detach "$LW" "$SHA_B"
EVL="$(printf -- '- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0' "$SHA_A0")"
[ -f "$REPO/$PRG" ] && [ -f "$LW/$DONE" ] && [ ! -e "$NW/$PRG" ] && ok "준비: ROOT=진행/ 옛 사본 · LEDGER_WT=완성/ · origin/main=B(완성/)" || bad "준비 실패"

LEDGER="$T/ledger.md"; CHERRY_LOG="$T/cherry-override.log"
run() { ( cd "${RUN_CWD:-$REPO}" && env -i HOME="$HOME" TMPDIR="$T/tmp" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="${RUN_PATH:-$T/fake:$PATH}" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {  # setup <index> — 명부·pane·나노·원장 WT 리셋 · LEDGER_WT 완성/ 사본에 증거 줄(미착지 · 작업 트리에 막 쓴 줄)
  git -C "$NW" reset -q --hard "$SHA_A0"; git -C "$NW" clean -qfd
  gitc reset -q --hard "$SHA_A"; gitc clean -qfd -- design
  git -C "$LW" checkout -q --detach "$SHA_B"; git -C "$LW" checkout -q -- .; git -C "$LW" clean -qfd
  git -C "$REPO" remote set-url origin "$ORIGIN"
  printf '%s\n' "$EVL" >> "$LW/$DONE"
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$1" > "$REPO/.fable-team/seats-planner.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$LEDGER"; rm -f "$CHERRY_LOG"; rm -rf "$T/wtclean"; rm -rf "$T/tmp"/*
}
CLOSE_BIN="$T/bin/ft-nano-close.sh"
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_LEDGER_WT="$LW" FT_NANO_FEAT=main \
  FT_CHERRY_OVERRIDE_LEDGER="$CHERRY_LOG" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 ${CREF:+FT_CARD_REF="$CREF"} bash "$CLOSE_BIN" "$SEAT" --result "$T/result.md" --recv 1 "$@"; }
untouched() {
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 해제 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 닫힘 원장 행 0" || bad "$1: 원장 행 생김"
}

section_a() {
  echo "== ⓐ origin/main=완성/ · ROOT=진행/ 옛 사본 · LEDGER_WT=완성/ → LEDGER_WT 완성/ 사본"
  setup "$PRG"; out="$(close)"; rc=$?
  has "$out" "INFO 카드 단계(origin/main) ← 완성" "ⓐ «INFO 카드 단계(origin/main) ← 완성» 1줄"
  has "$out" "INFO 카드 위치(팀 폴더) ← $LW/$DONE" "  └ 카드 = LEDGER_WT 완성/ 사본"
  hasnt "$out" "← $REPO/$PRG" "  └ ROOT 진행/ 옛 사본 안 잡음"
  [ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT" "  └ 닫기 rc0" || bad "ⓐ rc=$rc ← ${out:0:700}"
}
section_a

echo "== ⓑ origin/main 에 카드 없음(착지 전) → 지금 규칙 그대로"
OTH='design/planner/indices/진행/cs-new.md'
setup "$OTH"; printf '# 인덱스: cs\n## 상태\n- 진행\n%s\n' "$EVL" > "$REPO/$OTH"
out="$(close)"; rc=$?
hasnt "$out" "카드 단계(" "ⓑ 단계 줄 0(ref 에 카드 없음)"
has "$out" "CLOSED-ABSENT $SEAT" "  └ 지금 규칙 그대로(ROOT 진행/ 카드로 닫힘)"
hasnt "$out" "디스크 사본 없음" "  └ 단계 REJECT 0"
[ "$rc" -eq 0 ] && ok "  └ 닫기 rc0" || bad "ⓑ rc=$rc ← ${out:0:600}"

section_c() {
  echo "== ⓒ origin/main=완성/ 인데 완성/ 디스크 사본 없음 → REJECT · 옛 진행/ 사본 후퇴 0"
  setup "$PRG"; rm -f "$LW/$DONE"
  out="$(close)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "카드 단계 origin/main=완성 · 디스크 사본 없음" "ⓒ REJECT «카드 단계 origin/main=완성 · 디스크 사본 없음»" || bad "ⓒ rc=$rc ← ${out:0:600}"
  has "$out" "진행($REPO/design/planner)" "  └ 다른 단계 사본 = 진행(ROOT)"
  has "$out" "낡은 사본" "  └ «낡은 사본» 표기"
  hasnt "$out" "카드 위치" "  └ 카드 위치 줄 0(옛 사본 안 잡음)"
  untouched "ⓒ"
}
section_c

section_r1040() {   # r1040 · R6-a(arch #177970) · R7 — «정상 순서»(착지 → 완성 이동 → 나노 닫기): 완성 카드는 origin/main 에만 있고 디스크 사본이 없다
  echo "== r1040 ⓡ6-a origin/main 완성 카드(증거 줄 있음) · 디스크 사본 어느 단계에도 없음 → 통과 (ops 실입력 꼴)"
  gitc checkout -q -B r1040b "$SHA_B"; printf '%s\n' "$EVL" >> "$REPO/$DONE"; gitc add design; gitc commit -q -m "B2: 완성 카드 + 증거 줄"
  B2="$(git -C "$REPO" rev-parse HEAD)"; gitc push -q origin r1040b:main; gitc checkout -q main
  setup "$PRG"; rm -f "$REPO/$PRG" "$LW/$DONE"
  { [ ! -e "$REPO/$PRG" ] && [ ! -e "$LW/$DONE" ]; } && ok "  준비: 디스크 사본 0(진행·완성 모두)" || bad "r1040 준비 실패"
  out="$(close)"; rc=$?
  has "$out" "INFO 카드 단계 origin/main=완성 · 디스크 사본 없음 → ref 완성 카드로 ⑥ 검사" "ⓡ6-a 완성 카드 판독 INFO 1줄"
  has "$out" "INFO 카드 위치 ← origin/main:$DONE" "  └ 카드 읽기 = origin/main 완성 판"
  [ "$rc" -eq 0 ] && has "$out" "CLOSED" "  └ 닫기 rc0(통과)" || bad "ⓡ6-a rc=$rc ← ${out:0:700}"
  echo "== r1040 ⓡ7 origin/main=진행 · 디스크 사본 없음 → 지금처럼 REJECT(후퇴 0)"
  git -C "$ORIGIN" update-ref refs/heads/main "$SHA_A"; gitc update-ref refs/remotes/origin/main "$SHA_A"
  setup "$PRG"; rm -f "$REPO/$PRG" "$LW/$DONE"
  out="$(close)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "카드 단계 origin/main=진행 · 디스크 사본 없음" "ⓡ7 진행 단계 + 사본 없음 → REJECT" || bad "ⓡ7 rc=$rc ← ${out:0:700}"
  hasnt "$out" "CLOSED" "  └ 닫힘 0"
  untouched "ⓡ7"
  git -C "$ORIGIN" update-ref refs/heads/main "$B2"; gitc update-ref refs/remotes/origin/main "$B2"
}
section_r1040

section_d() {
  echo "== ⓓ ref 못 읽음(FT_CARD_REF=없는 ref) → ERROR 1줄 + REJECT"
  setup "$PRG"; out="$(CREF=nope/main close)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "ERROR 카드 단계 판정 실패(nope/main · rc=1)" "ⓓ ERROR 1줄" || bad "ⓓ rc=$rc ← ${out:0:600}"
  has "$out" "⑥카드 단계(nope/main)를 못 읽음" "  └ REJECT 사유"
  [ "$(printf '%s\n' "$out" | grep -c '^ERROR')" = 1 ] && ok "  └ ERROR 정확히 1줄" || bad "  └ ERROR 줄 수 ≠ 1"
  hasnt "$out" "카드 위치" "  └ 지금 규칙으로 후퇴 0"
  untouched "ⓓ"
}
section_d
section_d2() {   # DA⑥ r1 반례: 원격 없음 + FT_CARD_REF 없음 이 옛 규칙으로 새던 길
  echo "== ⓓ2 원격 없음 · FT_CARD_REF 없음 → ERROR + REJECT(옛 규칙으로 새지 않는다)"
  setup "$PRG"; git -C "$REPO" remote remove origin; gitc update-ref -d refs/remotes/origin/main 2>/dev/null
  out="$(close)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "ERROR 카드 단계 판정 실패(origin/main" "ⓓ2 ERROR 1줄" || bad "ⓓ2 rc=$rc ← ${out:0:600}"
  has "$out" "⑥카드 단계(origin/main)를 못 읽음" "  └ REJECT 사유"
  hasnt "$out" "카드 위치" "  └ 옛 규칙 후퇴 0(ROOT 진행/ 사본 안 집음)"
  hasnt "$out" "CLOSED" "  └ 닫힘 0"
  untouched "ⓓ2"
  git -C "$REPO" remote add origin "$ORIGIN"; gitc fetch -q origin; gitc update-ref refs/remotes/origin/main "$SHA_B"
}
section_d2
echo "== ⓓ 원격 origin 은 있는데 origin/main ref 없음 → ERROR + REJECT"
setup "$PRG"; gitc update-ref -d refs/remotes/origin/main
out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "⑥카드 단계(origin/main)를 못 읽음" "ⓓ origin/main 없음 → REJECT" || bad "ⓓ ref 없음 rc=$rc ← ${out:0:600}"
gitc update-ref refs/remotes/origin/main "$SHA_B"

section_d3() {   # DA⑥ r2 반례: ref 에 design/TEAMS.md 없음 + 완성/ 카드 → 명부가 없어도 단계는 완성
  echo "== ⓓ3 ref 에 TEAMS.md 없음 + 완성/cs.md + ROOT 옛 진행/cs.md → 완성/ 사본(LEDGER_WT) · 옛 진행/ 0"
  gitc checkout -q -b noteams3 "$SHA_B" 2>/dev/null; gitc rm -q design/TEAMS.md 2>/dev/null; gitc commit -q -m "명단 없음(완성 카드는 있음)" 2>/dev/null; NT="$(git -C "$REPO" rev-parse HEAD)"; gitc checkout -q main
  setup "$PRG"; gitc update-ref refs/remotes/origin/main "$NT"
  out="$(close)"; rc=$?
  has "$out" "INFO 카드 단계(origin/main) ← 완성" "ⓓ3 단계 = 완성(명부 무관)"
  has "$out" "INFO 카드 위치(팀 폴더) ← $LW/$DONE" "  └ 카드 = LEDGER_WT 완성/ 사본"
  hasnt "$out" "← $REPO/$PRG" "  └ ROOT 옛 진행/ 선택 0"
  [ "$rc" -eq 0 ] && ok "  └ 닫기 rc0" || bad "ⓓ3 rc=$rc ← ${out:0:600}"
  gitc update-ref refs/remotes/origin/main "$SHA_B"
}
section_d3

section_d4() {   # ls-tree 만 rc128 로 실패하는 가짜 git — 조회 실패는 ABSENT 가 아니다
  echo "== ⓓ4 ls-tree 실패 주입 → ERROR + REJECT"
  mkdir -p "$T/fake4"; REALGIT="$(command -v git)"
  cat > "$T/fake4/git" <<EOF
#!/usr/bin/env bash
case " \$* " in *" ls-tree "*) exit 128;; esac
exec "$REALGIT" "\$@"
EOF
  chmod +x "$T/fake4/git"
  setup "$PRG"; out="$(RUN_PATH="$T/fake4:$T/fake:$PATH" close)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "ERROR 카드 단계 판정 실패" "ⓓ4 ERROR 1줄" || bad "ⓓ4 rc=$rc ← ${out:0:600}"
  has "$out" "ls-tree 실패" "  └ 사유 = ls-tree"
  hasnt "$out" "카드 위치" "  └ 옛 규칙 후퇴 0"
  untouched "ⓓ4"
}
section_d4

section_d5() {   # 부르는 쪽 계약: 빈 출력 rc0 = 모르는 글자 = REJECT · 인자를 주면 «이미 변이된 부르는 쪽» 으로 같은 시험
  echo "== ⓓ5 단계 함수가 빈 출력 rc0 → ERROR + REJECT"
  { cat "$T/lib.orig"; printf '\nft_card_stage_ref() { return 0; }\n'; } > "$T/bin/ft-team-lib.sh"
  CLOSE_BIN="$T/bin/ft-nano-close.sh"; [ -z "${1:-}" ] || CLOSE_BIN="$T/bin/ft-nano-close.mut.sh"
  setup "$PRG"; out="$(close)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "ERROR 카드 단계 판정 실패" "ⓓ5 ERROR 1줄" || bad "ⓓ5 rc=$rc ← ${out:0:600}"
  hasnt "$out" "카드 위치" "  └ 빈 출력으로 후퇴 0"
  hasnt "$out" "CLOSED" "  └ 닫힘 0"
  untouched "ⓓ5"
  CLOSE_BIN="$T/bin/ft-nano-close.sh"; restore_lib
}
section_d5

section_d6() {   # ⓑ2 문지기: 단계 함수가 없는 lib · idx 꼴 불일치 → 건너뛰지 않고 ERROR + REJECT
  echo "== ⓓ6 ft_card_stage_ref 없는 lib(미로드 스텁) · idx 꼴 불일치 → ERROR + REJECT"
  python3 - "$T/lib.orig" "$T/bin/ft-team-lib.sh" <<'PY'
import sys
src, dst = sys.argv[1:3]
out = []; skip = False
for l in open(src, encoding="utf-8").read().split("\n"):
    if l.startswith("ft_card_stage_ref() {"): skip = True; continue
    if skip:
        if l.rstrip().endswith("echo ABSENT; }"): skip = False
        continue
    out.append(l)
open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
  setup "$PRG"; out="$(close)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "ERROR 카드 단계 함수 없음" "ⓓ6 lib 미로드 → ERROR 1줄" || bad "ⓓ6 rc=$rc ← ${out:0:600}"
  hasnt "$out" "카드 위치" "  └ 옛 규칙 후퇴 0"
  untouched "ⓓ6"
  restore_lib
  setup "design/planner/cs.md"; out="$(close)"; rc=$?
  has "$out" "INFO 카드 단계 판정 0 — idx 가 팀 카드 꼴 아님" "ⓓ6 팀 카드 꼴 아닌 idx → 단계 판정 0(오류 아님)"
  hasnt "$out" "⑥카드 단계" "  └ 단계 REJECT 0(범위 밖)"
  hasnt "$out" "ERROR 카드 단계" "  └ 단계 ERROR 0"
}
section_d6

section_d7() {   # DA⑥ r3 반례 1: lib 통째로 없음 + 팀 카드 꼴 → 옛 규칙으로 새지 않고 ERROR + REJECT
  echo "== ⓓ7 ft-team-lib.sh 통째로 없음(팀 카드 꼴) → ERROR + REJECT · ⓓ7b 같은 입력 + 원격 없음 → REJECT"
  mv "$T/bin/ft-team-lib.sh" "$T/lib.away"
  setup "$PRG"; out="$(close)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "ERROR 카드 단계 함수 없음" "ⓓ7 lib 없음 → ERROR 1줄" || bad "ⓓ7 rc=$rc ← ${out:0:600}"
  hasnt "$out" "카드 위치" "  └ ROOT 옛 진행/ 사본 안 집음"
  hasnt "$out" "CLOSED" "  └ 닫힘 0"
  untouched "ⓓ7"
  git -C "$REPO" remote remove origin; gitc update-ref -d refs/remotes/origin/main 2>/dev/null
  out="$(close)"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "ERROR 카드 단계 함수 없음" "ⓓ7b lib 없음 + 원격 없음 → ERROR 1줄" || bad "ⓓ7b rc=$rc ← ${out:0:600}"
  hasnt "$out" "CLOSED" "  └ 닫힘 0"
  untouched "ⓓ7b"
  git -C "$REPO" remote add origin "$ORIGIN"; gitc fetch -q origin; gitc update-ref refs/remotes/origin/main "$SHA_B"
  mv "$T/lib.away" "$T/bin/ft-team-lib.sh"
}
section_d7

section_d8() {   # DA⑥ r4 ⑥: 팀 카드 꼴이 아닌 IDX 는 기준판과 같은 결과 — 기존 Python 시험 4파일 · 인자를 주면 변이 사본으로
  echo "== ⓓ8 기존 Python 시험 4파일(팀 카드 꼴 아닌 index) → 기준판과 같은 통과 수"
  PYROOT="$HERE/.."
  if [ -n "${1:-}" ]; then   # 변이 — harness/bin 사본에 $1 표지를 $2 로 바꿔 끼우고 그 나무에서 돌린다
    rm -rf "$T/mut8"; PYROOT="$T/mut8/feature-pack/fable-team/harness"; mkdir -p "$PYROOT/tests"
    cp -a "$HERE/../bin" "$PYROOT/bin"; cp -a "$HERE/scripts" "$PYROOT/tests/scripts"; cp -a "$HERE/lib" "$PYROOT/tests/lib"
    python3 - "$HERE/../bin/ft-nano-close.sh" "$PYROOT/bin/ft-nano-close.sh" "$1" "$2" <<'PYMUT'
import sys
src, dst, mark, repl = sys.argv[1:5]
lines = open(src, encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if mark in l]
assert len(hit) == 1, hit
lines[hit[0]] = repl
open(dst, "w", encoding="utf-8").write("\n".join(lines))
PYMUT
  fi
  PYOUT="$( cd "$PYROOT" && python3.11 -m pytest tests/scripts/test_nano_close_cherry_origin_main.py tests/scripts/test_nano_close_cherry_override.py tests/scripts/test_nano_close_evidence_wiring.py tests/scripts/test_nano_close_respawn_worktree.py -q 2>&1 )"; PYRC=$?
  PASSED="$(printf '%s\n' "$PYOUT" | grep -oE '[0-9]+ passed' | tail -1 | awk '{print $1}')"; FAILED="$(printf '%s\n' "$PYOUT" | grep -oE '[0-9]+ failed' | tail -1 | awk '{print $1}')"
  # 병합(origin/main 78커밋) 뒤 기준판 = 29 passed 3 failed — origin/main 판 자체가 같은 3건을 실패한다(⑤ cherry 메시지 꼴 · r842 범위 밖).
  #   그래서 «절대값 32» 가 아니라 «기준판과 같은 통과 수 29 이상 · 실패 3 이하» 로 잰다(변이는 실패가 늘어 여기서 걸린다).
  [ "${PASSED:-0}" -ge 29 ] && [ "${FAILED:-0}" -le 3 ] && ok "ⓓ8 Python 4파일 ${PASSED:-0} passed ${FAILED:-0} failed(기준판 origin/main 29 passed 3 failed — 같은 3건)" || bad "ⓓ8 Python rc=$PYRC passed=${PASSED:-0} failed=${FAILED:-0} ← $(printf '%s\n' "$PYOUT" | grep -E '^FAILED' | head -3)"
}
section_d8

echo "== ⓔ 호출 워크트리(WT · 나노가 증거 줄을 쓴 진행/ 사본) · origin/main 도 진행/ → WT 사본 그대로"
E_IDX='design/planner/indices/진행/cs-e.md'; OW="$REPO/.worktrees/ops"
setup "$E_IDX"; mkdir -p "$REPO/design/planner/indices/진행"; printf '# 인덱스: cs-e\n## 상태\n- 진행\n' > "$REPO/$E_IDX"
gitc add "$E_IDX" && gitc commit -q -m "E: 진행 카드" && gitc push -q origin HEAD:main --force; SHA_E="$(git -C "$REPO" rev-parse HEAD)"
[ -d "$OW" ] || git -C "$REPO" worktree add -q --detach "$OW" "$SHA_E"
printf '%s\n' "$EVL" >> "$OW/$E_IDX"
out="$(RUN_CWD="$OW" close)"; rc=$?
has "$out" "INFO 카드 단계(origin/main) ← 진행" "ⓔ 단계 = 진행"
has "$out" "INFO 카드 위치(팀 폴더) ← $OW/$E_IDX" "  └ 카드 = 호출 WT 사본(증거 검사 대상 불변)"
[ "$rc" -eq 0 ] && ok "  └ 닫기 rc0(WT 사본 증거 줄)" || bad "ⓔ rc=$rc ← ${out:0:600}"
git -C "$ORIGIN" update-ref refs/heads/main "$SHA_B"; gitc update-ref refs/remotes/origin/main "$SHA_B"

section_e2() {   # DA⑥ r4 반례: ABSENT 에서 :842 의 IDX 경로(ROOT 대기/ 사본)를 먼저 집으면 나노 WT 진행/ 증거 사본을 가린다 → 지금 규칙(r444 ⑥) 그대로여야 한다
  echo "== ⓔ' origin/main 에 카드 없음(ABSENT) · ROOT 대기/ 사본 = 증거 줄 없음 · 나노 WT 진행/ 사본 = 유효 → CLOSED-ABSENT rc0"
  E2_IDX='design/planner/indices/대기/cs-e2.md'; E2_PRG='design/planner/indices/진행/cs-e2.md'
  setup "$E2_IDX"
  mkdir -p "$REPO/design/planner/indices/대기"
  printf '# 인덱스: cs-e2\n## 상태\n- 대기(ROOT 사본 · 증거 줄 없음)\n' > "$REPO/$E2_IDX"
  mkdir -p "$NW/design/planner/indices/진행"; printf '# 인덱스: cs-e2\n## 상태\n- 진행\n%s\n' "$EVL" > "$NW/$E2_PRG"
  out="$(RUN_CWD="$NW" close)"; rc=$?
  hasnt "$out" "카드 단계(" "ⓔ' 단계 줄 0(ref 에 카드 없음 = 단계 판정 없음)"
  has "$out" "INFO 카드 위치(팀 폴더) ← $NW/$E2_PRG" "  └ 카드 = 나노 WT 진행/ 사본(지금 규칙)"
  hasnt "$out" "← $REPO/$E2_IDX" "  └ ROOT 대기/ 사본 안 집음(IDX 우선 집기 0)"
  hasnt "$out" "⑥카드 단계" "  └ 단계 REJECT 0"
  [ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT" "  └ 닫기 rc0(나노 WT 증거 사본)" || bad "ⓔ' rc=$rc ← ${out:0:700}"
  rm -f "$REPO/$E2_IDX"
}
section_e2

echo "== ⓗ ft_card_stage_ref 단위(idx 직접 · 명부 무관 · 세 갈래)"
PIDX='design/planner/indices/진행/cs.md'
st() { ( unset FT_CARD_REF; . "$T/bin/ft-team-lib.sh"; ft_card_stage_ref "$@" ); }
o="$(st "$REPO" "$PIDX" origin/main 2>&1)"; r=$?; [ "$r" = 0 ] && [ "$o" = 'STAGE 완성' ] && ok "ⓗ 1단계 = STAGE 완성 rc0" || bad "ⓗ 1단계 rc=$r «${o}»"
o="$(st "$REPO" design/planner/indices/진행/none.md origin/main 2>&1)"; r=$?; [ "$r" = 0 ] && [ "$o" = ABSENT ] && ok "ⓗ 카드 없음 = ABSENT rc0" || bad "ⓗ 없음 rc=$r «${o}»"
o="$(st "$REPO" "$PIDX" "$SHA_A0" 2>&1)"; r=$?; [ "$r" = 0 ] && [ "$o" = ABSENT ] && ok "ⓗ 카드 없는 판 = ABSENT rc0" || bad "ⓗ A0 rc=$r «${o}»"
o="$(st "$REPO" "$PIDX" nope/main 2>&1)"; r=$?; [ "$r" = 1 ] && has "$o" "ERROR 카드 단계 ref(nope/main)를 못 읽음" "ⓗ ref 없음 = ERROR rc1" || bad "ⓗ ref 없음 rc=$r «${o}»"
o="$(st "$T/tmp" "$PIDX" origin/main 2>&1)"; r=$?; [ "$r" = 1 ] && has "$o" "ERROR" "ⓗ 리포 아님 = ERROR rc1" || bad "ⓗ 리포 아님 rc=$r «${o}»"
o="$(st "$REPO" design/planner/cs.md origin/main 2>&1)"; r=$?; [ "$r" = 1 ] && has "$o" "idx 꼴 아님" "ⓗ idx 꼴 아님 = ERROR rc1" || bad "ⓗ idx 꼴 rc=$r «${o}»"
gitc checkout -q -b two "$SHA_B"; mkdir -p "$REPO/design/planner/indices/진행"; cp "$REPO/$DONE" "$REPO/$PRG"; gitc add design; gitc commit -q -m "두 단계"
o="$(st "$REPO" "$PIDX" two 2>&1)"; r=$?; [ "$r" = 1 ] && has "$o" "여러 단계(진행 완성)" "ⓗ 2단계 = ERROR rc1" || bad "ⓗ 2단계 rc=$r «${o}»"
o="$(st "$REPO" "$PIDX" noteams3 2>&1)"; r=$?; [ "$r" = 0 ] && [ "$o" = 'STAGE 완성' ] && ok "ⓗ 명단 없는 ref 도 STAGE 완성(명부 의존 0)" || bad "ⓗ 명단 없음 rc=$r «${o}»"
gitc checkout -q main; gitc reset -q --hard "$SHA_A"

echo "== ⓖ 변이 — 단계 제거 → ⓐ FAIL · ⓒ 후퇴 → ⓒ FAIL · 조회 실패를 카드 없음으로 → ⓓ·ⓓ2·ⓓ5 FAIL · 빈 출력을 없음으로 → ⓓ5 FAIL · 명부 없음 = ABSENT → ⓓ3 FAIL"
mutate() {  # mutate <표지> <바꿀 글> — 표지 줄을 바꾼 사본(부르는 쪽)
  python3 - "$T/bin/ft-nano-close.sh" "$T/bin/ft-nano-close.mut.sh" "$1" "$2" <<'PY'
import sys
src, dst, mark, repl = sys.argv[1:5]
lines = open(src, encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if mark in l]
assert len(hit) == 1, hit
lines[hit[0]] = repl
open(dst, "w", encoding="utf-8").write("\n".join(lines))
PY
}
mutate_lib() {  # mutate_lib <표지> <바꿀 글> — 단계 함수 쪽 사본을 바꿔 끼운다(끝나면 restore_lib)
  [ -f "$T/lib.orig" ] || cp "$T/bin/ft-team-lib.sh" "$T/lib.orig"
  python3 - "$T/lib.orig" "$T/bin/ft-team-lib.sh" "$1" "$2" <<'PY'
import sys
src, dst, mark, repl = sys.argv[1:5]
lines = open(src, encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if mark in l]
assert len(hit) == 1, hit
lines[hit[0]] = repl
open(dst, "w", encoding="utf-8").write("\n".join(lines))
PY
}
mutate "# r842-mut:stage" '      :'
CLOSE_BIN="$T/bin/ft-nano-close.mut.sh"; sub="$(section_a)"
case "$sub" in *FAIL*) ok "ⓖ 단계 판정 제거(디스크 고리) → ⓐ FAIL";; *) bad "ⓖ 단계 판정 없어도 ⓐ 통과";; esac
mutate "# r842-mut:nostage" '  if false; then'
sub="$(section_c)"
case "$sub" in *FAIL*) ok "ⓖ ⓒ 를 옛 단계 후퇴로 → ⓒ FAIL";; *) bad "ⓖ 옛 단계 후퇴여도 ⓒ 통과";; esac
mutate "# r842-mut:referr" '      *) _cs="";;'
sub="$(section_d)$(section_d2)$(section_d5)"
case "$sub" in *FAIL*) ok "ⓖ 조회 실패를 «카드 없음» 으로 → ⓓ·ⓓ2·ⓓ5 FAIL";; *) bad "ⓖ 조회 실패를 카드 없음으로 읽어도 ⓓ·ⓓ2·ⓓ5 통과";; esac
mutate "# r842-mut:absent" '      0:ABSENT|0:) _cs="";;'
sub="$(section_d5 mut)"
case "$sub" in *FAIL*) ok "ⓖ 빈 출력 rc0 을 «없음» 으로 → ⓓ5 FAIL";; *) bad "ⓖ 빈 출력을 없음으로 읽어도 ⓓ5 통과";; esac
CLOSE_BIN="$T/bin/ft-nano-close.sh"
mutate_lib "# r842-mut:teams" '  git -C "$r" cat-file -e "$ref:design/TEAMS.md" 2>/dev/null || { echo ABSENT; return 0; }'
sub="$(section_d3)"
case "$sub" in *FAIL*) ok "ⓖ «명부 없음 = ABSENT» → ⓓ3 FAIL";; *) bad "ⓖ 명부 없음에 ABSENT 를 내도 ⓓ3 통과";; esac
restore_lib
mutate "# r1040-mut:donecard" '    if false; then'   # r1040 변이 — 완성 카드 분기 제거
CLOSE_BIN="$T/bin/ft-nano-close.mut.sh"; sub="$(section_r1040)"; CLOSE_BIN="$T/bin/ft-nano-close.sh"
case "$sub" in *FAIL*) ok "ⓖ «완성 단계 + 디스크 사본 없음 = 통과» 분기 제거 → ⓡ6-a FAIL(r1040)";; *) bad "ⓖ 완성 카드 분기를 없애도 ⓡ6-a 통과";; esac
mutate "# r842-mut:absentidx" '  if false; then'
CLOSE_BIN="$T/bin/ft-nano-close.mut.sh"; sub="$(section_e2)"; CLOSE_BIN="$T/bin/ft-nano-close.sh"
case "$sub" in *FAIL*) ok "ⓖ «ABSENT 에도 IDX 우선 집기» → ⓔ' FAIL(DA⑥ r4)";; *) bad "ⓖ ABSENT 에서 IDX 를 먼저 집어도 ⓔ' 통과";; esac
mutate "# r842-mut:libskip" 'if [ -n "$IDX" ] && declare -F ft_card_stage_ref >/dev/null; then'
CLOSE_BIN="$T/bin/ft-nano-close.mut.sh"; sub="$(section_d7)"; CLOSE_BIN="$T/bin/ft-nano-close.sh"
case "$sub" in *FAIL*) ok "ⓖ «lib 없으면 블록 건너뜀» → ⓓ7 FAIL";; *) bad "ⓖ lib 없이 건너뛰어도 ⓓ7 통과";; esac
sub="$(section_d8 "# r842-mut:idxshape" '  _istage=1; _ct=planner; _cf=card.md;')"
case "$sub" in *FAIL*) ok "ⓖ «꼴 불일치 = REJECT» → ⓓ8 FAIL(Python 4파일)";; *) bad "ⓖ 꼴 불일치를 REJECT 로 만들어도 ⓓ8 통과";; esac

echo "== ⓖ 600/300 s · 외부 호출 · GIT_* env 0 (r842 줄)"
NEWL="$(grep 'r842\|_cstg\|_cbases\|_cold\|ft_card_stage_ref' "$SRC/ft-nano-close.sh" "$SRC/ft-team-lib.sh")"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE '(^|[^0-9])(600|300)([^0-9]|$)')" ":" "ⓖ 600/300 숫자 0"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE 'curl|wget|https?://|gh |nc ')" ":" "ⓖ 외부 호출 0"
hasnt "$NEWL" "GIT_DIR=" "ⓖ GIT_DIR env 0"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
