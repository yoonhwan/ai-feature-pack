#!/usr/bin/env bash
# test_nano_index_rel_r1118.sh — r1118: 명부 index 를 리포 상대경로로 — ft_index_rel(ft-team-lib.sh) 1개를 spawn 등록·close 읽기가 같이 쓴다.
#   계약(카드 계약↔시험 대응표 그대로):
#   ① 절대 → 마지막 design/…/indices/<단계>/<파일> 꼬리 · teams/ 유지 · R1~R4    ⓐ ft_index_rel 칸 · 변이(`##` → `#` 최단 일치) → R4 FAIL
#   ② close 정규화 뒤 ⑥ 통과 · R1·R6                                          ⓑ «INFO index 정규화» + STAGE 완성 · REJECT 0 · 변이(close 호출 줄 삭제) → R1 rc128 REJECT
#   ③ 상대 index 불변 · R5                                                    ⓒ 정규화 줄 0 · STAGE 완성 그대로
#   ④ spawn 상대 등록 · 꼴 밖 REJECT(부작용 전) · R7·R8                        ⓓ 블록 추출 실행 — PLAN·명부 행 상대 · REJECT 블록이 base_sha 쓰기·워크트리·명부보다 앞 · 변이(호출 줄 삭제) → R7 FAIL
#   ⑤ bin·kit 같은 내용                                                       ⓔ cmp0 · bash -n
# 임시 git 리포 + bare origin + 가짜 tmux(PATH 앞)만 쓴다(픽스처 꼴 = test_nano_close_card_stage_ref_r842.sh) — 실 리포·명부·tmux 0 · 자기 재호출은 real_state_guard 의 RSG_ACTIVE 표지 뒤 1회뿐.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 RSG_ACTIVE)
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
BIN="$HERE/../bin"; SRC="$HERE/../kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0; S0="$(date +%s)"; SECS=""
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
lap() { local n; n="$(date +%s)"; SECS="${SECS:+$SECS · }$1 $((n-S0))s"; S0="$n"; }
mut_line() {  # mut_line <원본> <사본> <표지> <바꿀 글> — 표지 줄 1개를 바꾼 사본
  python3 - "$@" <<'PY'
import sys
src, dst, mark, repl = sys.argv[1:5]
lines = open(src, encoding="utf-8").read().split("\n")
hit = [i for i, l in enumerate(lines) if mark in l]
assert len(hit) == 1, hit
lines[hit[0]] = repl
open(dst, "w", encoding="utf-8").write("\n".join(lines))
PY
}

echo "== ⓔ bin·kit 같은 바이트 + bash -n"
for f in ft-team-lib.sh ft-nano-spawn.sh ft-nano-close.sh; do
  cmp -s "$BIN/$f" "$SRC/$f" && ok "cmp $f (bin == kit)" || bad "cmp $f 다름"
  bash -n "$SRC/$f" && ok "bash -n $f" || bad "bash -n $f"
done

section_unit() {  # section_unit <lib> — ft_index_rel 칸(R1~R5·R8)
  local lib="$1" o r
  rel() { ( . "$lib"; ft_index_rel "$1" ); }
  o="$(rel /x/scratch/design/v65/indices/완성/g7s2-4.md 2>&1)"; r=$?
  [ "$r" = 0 ] && [ "$o" = design/v65/indices/완성/g7s2-4.md ] && ok "ⓐ R1 스크래치 절대 → design/v65/…" || bad "ⓐ R1 rc=${r} «${o}»"
  o="$(rel /r/.worktrees/graphics-arch-g1160-card/design/graphics/indices/진행/g.md 2>&1)"; r=$?
  [ "$r" = 0 ] && [ "$o" = design/graphics/indices/진행/g.md ] && ok "ⓐ R2 BYZ 다른 워크트리 절대 → design/graphics/…" || bad "ⓐ R2 rc=${r} «${o}»"
  o="$(rel /r/s/design/teams/harness/indices/진행/y.md 2>&1)"; r=$?
  [ "$r" = 0 ] && [ "$o" = design/teams/harness/indices/진행/y.md ] && ok "ⓐ R3 teams/ 유지" || bad "ⓐ R3 rc=${r} «${o}»"
  o="$(rel /a/design/old/.worktrees/w/design/v65/indices/진행/c.md 2>&1)"; r=$?
  [ "$r" = 0 ] && [ "$o" = design/v65/indices/진행/c.md ] && ok "ⓐ R4 design/ 둘 → 마지막 꼬리" || bad "ⓐ R4 rc=${r} «${o}»"
  o="$(rel design/planner/indices/진행/cs.md 2>&1)"; r=$?
  [ "$r" = 0 ] && [ "$o" = design/planner/indices/진행/cs.md ] && ok "ⓐ R5 상대 → 그대로" || bad "ⓐ R5 rc=${r} «${o}»"
  o="$(rel /tmp/x.md 2>&1)"; r=$?
  [ "$r" = 1 ] && has "$o" "ERROR index 꼴 아님" "ⓐ R8 꼴 밖 절대 → ERROR rc1" || bad "ⓐ R8 rc=${r} «${o}»"
  o="$(rel /a/design/planner/notes.md 2>&1)"; r=$?
  [ "$r" = 1 ] && ok "ⓐ design/ 아래지만 indices 꼴 아님 → rc1" || bad "ⓐ 꼴 아님 rc=${r} «${o}»"
}
echo "== ⓐ ft_index_rel 단위"
section_unit "$BIN/ft-team-lib.sh"
lap unit

echo "== ⓓ spawn 블록(추출 실행) — R7 다른 체크아웃 카드 · R8 꼴 밖 REJECT"
SP="$BIN/ft-nano-spawn.sh"
blk() { awk '/^# r1118: 명부 index = 리포 상대경로/{f=1} f{print} f&&/^IDX_WT=/{exit}' "$1"; }
BLK="$(blk "$SP")"; [ -n "$BLK" ] || bad "ⓓ 블록 추출 0 — r1118 머리 주석 없음"
REG="$(awk '/^python3 - "\$SEATS" "\$NAME"/{f=1} f{print} f&&/^PY$/{exit}' "$SP")"; [ -n "$REG" ] || bad "ⓓ 명부 등록 블록 추출 0"
PLANL="$(grep -m1 '^echo "PLAN seat=' "$SP")"; [ -n "$PLANL" ] || bad "ⓓ PLAN 줄 추출 0"
A="$T/ckA"; B="$T/ckB"; mkdir -p "$A/design/planner/indices/대기" "$B/design/planner/indices/대기"
echo '# 인덱스: s' > "$A/design/planner/indices/대기/s.md"; echo '# 인덱스: b' > "$B/design/planner/indices/대기/b.md"
run_spawn_blk() {  # run_spawn_blk <블록> <WT> <IDX> → OUT·RC (블록 뒤 PLAN 줄 + 명부 등록 실행)
  printf '{}\n' > "$T/seats.json"
  OUT="$( WT="$2" IDX="$3" LIB="$BIN/ft-team-lib.sh" SEATS="$T/seats.json" bash -c '. "$LIB"; human() { echo "HUMAN $1"; exit 9; }
NAME=byz-planner-nano-s#0 AGENT=claude MODEL="" ROLE=nano RAISE="" FROM=me'$'\n'"$1"$'\n''echo "IDX_REL=$IDX_REL"; echo "IDX_WT=$IDX_WT"'$'\n'"$PLANL"$'\n'"$REG" 2>&1 )"; RC=$?
}
run_spawn_blk "$BLK" "$B" "$A/design/planner/indices/대기/s.md"
[ "$RC" = 0 ] && has "$OUT" "IDX_REL=design/planner/indices/대기/s.md" "ⓓ R7 cwd=B · 카드=A → IDX_REL 상대" || bad "ⓓ R7 rc=$RC ← ${OUT:0:500}"
has "$OUT" "IDX_WT=$A" "  └ IDX_WT = 카드가 있는 체크아웃 A(발주문 카드 경로)"
has "$OUT" "index=design/planner/indices/대기/s.md" "  └ PLAN 줄 index= 상대"
R7IDX="$(jq -r '."byz-planner-nano-s#0".index' "$T/seats.json" 2>/dev/null)"
[ "$R7IDX" = design/planner/indices/진행/s.md ] && ok "  └ 명부 행 index = design/planner/indices/진행/s.md(상대)" || bad "ⓓ R7 명부 index «$R7IDX»"
run_spawn_blk "$BLK" "$B" "$B/design/planner/indices/대기/b.md"
{ [ "$RC" = 0 ] && has "$OUT" "IDX_REL=design/planner/indices/대기/b.md" "ⓓ 같은 체크아웃 카드 → 지금과 같은 상대값"; } || bad "ⓓ 같은 체크아웃 rc=$RC"
has "$OUT" "IDX_WT=$B" "  └ IDX_WT = WT(지금 발주문 경로 그대로)"
echo '# 인덱스: x' > "$T/x.md"
run_spawn_blk "$BLK" "$B" "$T/x.md"
[ "$RC" = 1 ] && has "$OUT" "REJECT 카드는 design/…/indices/<단계>/ 아래에" "ⓓ R8 꼴 밖 절대 → REJECT rc1" || bad "ⓓ R8 rc=$RC ← ${OUT:0:400}"
hasnt "$OUT" "IDX_REL=" "  └ REJECT 뒤 진행 0"
[ "$(jq -r 'length' "$T/seats.json")" = 0 ] && ok "  └ 명부 행 0" || bad "ⓓ R8 명부 행 생김"
L_BLK="$(grep -n '^# r1118: 명부 index = 리포 상대경로' "$SP" | cut -d: -f1)"
L_CB="$(grep -n 'python3 - "\$IDX" "\$CUR_HEAD"' "$SP" | head -1 | cut -d: -f1)"
L_WTADD="$(grep -n 'worktree add "\$WTDIR"' "$SP" | head -1 | cut -d: -f1)"
L_REG="$(grep -n '^# ⑤ seats.json 등록' "$SP" | cut -d: -f1)"
{ [ -n "$L_BLK" ] && [ "$L_BLK" -lt "$L_CB" ] && [ "$L_BLK" -lt "$L_WTADD" ] && [ "$L_BLK" -lt "$L_REG" ]; } \
  && ok "ⓓ R8 REJECT 자리(:$L_BLK) < 카드 base_sha 쓰기(:$L_CB) · worktree add(:$L_WTADD) · 명부 등록(:$L_REG)" || bad "ⓓ 블록 순서 blk=$L_BLK cb=$L_CB wt=$L_WTADD reg=$L_REG"
lap spawn

echo "== ⓑⓒ close 실행 픽스처(r842 꼴)"
mkdir -p "$T/bin" "$T/fake" "$T/tmp"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-team-lib.sh" "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-nano-superseded-check.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-wt-sweep.sh" "$T/bin/"
cp "$SRC/ft_teamset.py" "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
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
git -C "$REPO" init -q -b main && git -C "$REPO" remote add origin "$ORIGIN"
mkdir -p "$REPO/design" "$REPO/.fable-team" "$T/comm/bodies"
printf '| 팀 | 폴더 |\n|---|---|\n| planner | design/planner/ |\n' > "$REPO/design/TEAMS.md"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
gitc add -A && gitc commit -q -m "A0: 명단"; SHA_A0="$(git -C "$REPO" rev-parse HEAD)"
SEAT='byz-planner-nano-cs#0'; NW="$REPO/.worktrees/v65-cs"; LW="$T/ledger-wt"
PRG='design/planner/indices/진행/cs.md'; DONE='design/planner/indices/완성/cs.md'
git -C "$REPO" worktree add -q "$NW" -b nano/cs
EVL="$(printf -- '- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0' "$SHA_A0")"
mkdir -p "$REPO/design/planner/indices/완성"; printf '# 인덱스: cs\n## 상태\n- 완성\n' > "$REPO/$DONE"
gitc add design && gitc commit -q -m "B: 카드 완성"; SHA_B="$(git -C "$REPO" rev-parse HEAD)"; gitc push -q origin main; gitc reset -q --hard "$SHA_A0"   # ROOT = 카드 없는 판(디스크 사본 = LEDGER_WT 완성/ 하나)
git -C "$REPO" worktree add -q --detach "$LW" "$SHA_B"
LEDGER="$T/ledger.md"
run() { ( cd "$REPO" && env -i HOME="$HOME" TMPDIR="$T/tmp" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {  # setup <index> — 명부·pane·원장 리셋 · LEDGER_WT 완성/ 사본에 증거 줄
  git -C "$NW" reset -q --hard "$SHA_A0"; git -C "$NW" clean -qfd
  gitc reset -q --hard "$SHA_A0"; gitc clean -qfd -- design
  git -C "$LW" checkout -q -- .; git -C "$LW" clean -qfd; printf '%s\n' "$EVL" >> "$LW/$DONE"
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$1" > "$REPO/.fable-team/seats-planner.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$LEDGER"; rm -rf "$T/wtclean" "$T/tmp"/*
}
CLOSE_BIN="$T/bin/ft-nano-close.sh"
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_LEDGER_WT="$LW" FT_NANO_FEAT=main \
  FT_CHERRY_OVERRIDE_LEDGER="$T/cherry.log" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 bash "$CLOSE_BIN" "$SEAT" --result "$T/result.md" --recv 1; }
R1IDX="/x/scratch/$PRG"
section_r1() {
  echo "== ⓑ R1 명부 index 절대(스크래치) · origin/main=완성 → 정규화 + STAGE 완성 · 닫힘"
  setup "$R1IDX"; out="$(close)"; rc=$?
  has "$out" "INFO index 정규화 ← $R1IDX → $PRG" "ⓑ R1 «INFO index 정규화 ← <절대> → <상대>» 1줄"
  has "$out" "INFO 카드 단계(origin/main) ← 완성" "  └ STAGE 완성"
  hasnt "$out" "ls-tree 실패" "  └ ls-tree rc128 0"
  [ "$rc" -eq 0 ] && has "$out" "CLOSED" "  └ 닫기 rc0 · REJECT 0" || bad "ⓑ R1 rc=$rc ← ${out: -900}"
}
section_r1
echo "== ⓑ R6 쌍둥이 꼴 절대(design/teams/planner) · ref 는 design/planner/완성 → 정규화 뒤 쌍둥이로 STAGE 완성"
R6IDX="/x/scratch/design/teams/planner/indices/진행/cs.md"
setup "$R6IDX"; out="$(close)"; rc=$?
has "$out" "INFO index 정규화 ← $R6IDX → design/teams/planner/indices/진행/cs.md" "ⓑ R6 정규화(teams/ 유지)"
has "$out" "INFO 카드 단계(origin/main) ← 완성" "  └ 쌍둥이 후보로 STAGE 완성"
[ "$rc" -eq 0 ] && has "$out" "CLOSED" "  └ 닫기 rc0" || bad "ⓑ R6 rc=$rc ← ${out: -900}"
echo "== ⓒ R5 상대 index → 정규화 줄 0 · 결과 그대로"
setup "$PRG"; out="$(close)"; rc=$?
hasnt "$out" "index 정규화" "ⓒ R5 정규화 줄 0"
has "$out" "INFO 카드 단계(origin/main) ← 완성" "  └ STAGE 완성(r842 판정 그대로)"
[ "$rc" -eq 0 ] && has "$out" "CLOSED" "  └ 닫기 rc0" || bad "ⓒ R5 rc=$rc ← ${out: -900}"
echo "== ⓒ R8 close 꼴 밖 절대 index → «팀 카드 꼴 아님» 길 그대로"
setup "/tmp/nowhere/x.md"; out="$(close)"
hasnt "$out" "index 정규화" "ⓒ R8 정규화 줄 0"
has "$out" "INFO 카드 단계 판정 0 — idx 가 팀 카드 꼴 아님" "  └ 지금 «팀 카드 꼴 아님» INFO 길"
hasnt "$out" "ls-tree 실패" "  └ 단계 ERROR 0"
lap close

echo "== ⓖ 변이 — lib 최단 일치 → R4 FAIL · close 호출 줄 삭제 → R1 rc128 REJECT(기준값) · spawn 호출 줄 삭제 → R7 FAIL"
mut_line "$BIN/ft-team-lib.sh" "$T/lib.mut" "# r1118-mut:last" '  t="design/${p#*/design/}"'
sub="$(section_unit "$T/lib.mut")"
case "$sub" in *"FAIL ⓐ R4"*) ok "ⓖ 최단 일치 → R4 FAIL";; *) bad "ⓖ 최단 일치여도 R4 통과";; esac
mut_line "$T/bin/ft-nano-close.sh" "$T/bin/ft-nano-close.mut.sh" "# r1118-mut:close" ':'
CLOSE_BIN="$T/bin/ft-nano-close.mut.sh"; setup "$R1IDX"; out="$(close)"; rc=$?; CLOSE_BIN="$T/bin/ft-nano-close.sh"
{ [ "$rc" -eq 1 ] && case "$out" in *"ls-tree 실패(rc=128)"*REJECT*|*REJECT*"ls-tree 실패(rc=128)"*) true;; *) false;; esac; } \
  && ok "ⓖ close 호출 줄 삭제 → R1 «ls-tree 실패(rc=128)» REJECT(옛 동작 = 기준값)" || bad "ⓖ close 변이 rc=$rc ← ${out:0:500}"
sub="$(CLOSE_BIN="$T/bin/ft-nano-close.mut.sh" section_r1)"
case "$sub" in *FAIL*) ok "  └ 같은 변이에서 ⓑ R1 FAIL";; *) bad "  └ close 변이에도 ⓑ R1 통과";; esac
mut_line "$SP" "$T/spawn.mut" "# r1118-mut:spawn" ':'
run_spawn_blk "$(blk "$T/spawn.mut")" "$B" "$A/design/planner/indices/대기/s.md"
case "$OUT" in *"IDX_REL=design/planner/indices/대기/s.md"*) bad "ⓖ spawn 호출 줄 삭제에도 R7 상대";; *) ok "ⓖ spawn 호출 줄 삭제 → R7 절대경로 등록(FAIL)";; esac
lap mutation

echo
echo "단계별 초: $SECS"
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
