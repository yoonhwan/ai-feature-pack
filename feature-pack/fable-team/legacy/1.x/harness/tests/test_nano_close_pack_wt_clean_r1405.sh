#!/usr/bin/env bash
# test_nano_close_pack_wt_clean_r1405.sh — r1405: 팩 리포 워크트리에서 일한 나노를 ft-nano-close 로 닫으면 그 팩 워크트리 정리 계획을
#   <팩>/.fable-team/state/wt-clean/<좌석>.sh 로 «BYZ 와 같은 생성기» 로 만들고 kill 뒤(세션이 이미 없으면 그 자리) 바로 실행한다 · 브랜치 삭제 0.
# 임시 리포 2개(BYZ 꼴 R · 팩 꼴 P · 각 bare 원격) + 가짜 tmux·gh·baton·ft-wt-sweep(호출 기록만) — 실 리포·명부·tmux 세션·gh(네트워크) 0 · 고정 sleep 0 · GIT_* env 0.
# P1 --wt 팩 경로 --branch nano/k · 착지 끝 · 깨끗함 → 계획 생성 + 실행 → 워크트리 0 · 가지 그대로 · rc0
# P2 --landed-pr · --wt 없음 · 세션 0 · BYZ 워크트리 0 · 좌석 워크트리가 팩에만 → 키로 찾아 P1 과 같음(CLOSED-BACKFILL) · 원장 행 pack=<팩 경로>
# P3 P2 + 팩 워크트리 미커밋 1줄 → 계획 가드 skipped · 워크트리 그대로 · 원장 표식 · rc0
# P4 가지 이름 nano/ 아님(r1363 꼴 · 착지 끝) → 계획 0 + INFO «가지 이름 nano/» · 워크트리 그대로
# P5 같은 키 팩 워크트리 2개(nano/k · nano/k-r2) → 계획 0 + INFO «후보 2» · 손 0
# P6 BYZ 나노(팩 후보 0) → 출력 = 기준판(STEP 줄 제외) · 팩 계획 폴더 0
# P7 실사건 꼴 재실행(명부 행 0 · 원장 wt=none · 세션 0) → 같은 close 재실행이 팩 워크트리 정리
# P8 git 실패(팩 worktree list rc42 주입) · 착지 판정기 rc2 → 초회·재실행 모두 «판정 불가» + rc≠0 · 닫기·정리 0 (하드 룰 20 · DA HOLD 298689)
# 기준판 FAIL = P1·P2 · 변이 6(5 = git 실패를 정리 0 으로 합침 → P8a·P8b · 6 = 판정기 rc2 를 미착지로 합침 → P8c): 계획 0 으로 되돌림 → P1·P2 · 키로 찾기 삭제 → P2 · nano/ 검사 삭제 → P4 · 후보 수 검사 삭제 → P5 (전부 FAIL 이어야 한다)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
BASE_REV=bdd38a99
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:900}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:600}";; *) ok "$3";; esac; }

echo "== 짝 cmp · bash -n (/bin/bash 3.2 포함)"
cmp -s "$HERE/../bin/ft-nano-close.sh" "$SRC/ft-nano-close.sh" && ok "cmp bin == kit" || bad "cmp bin ≠ kit"
bash -n "$SRC/ft-nano-close.sh" && /bin/bash -n "$SRC/ft-nano-close.sh" && ok "bash -n · /bin/bash 3.2 -n" || bad "bash -n"

mkdir -p "$T/bin" "$T/fake"
for f in ft-nano-close.sh ft-nano-evidence-check.sh ft-nano-superseded-check.sh ft-nano-suspended-check.sh ft-hil.sh ft-landed-check.sh \
         ft-team-lib.sh ft-card-target-lib.sh ft_git_capped.py ft_teamset.py ft_team_lib.py ft-sheet-events.sh ft_sheet_events.py ft_sheet_confirm.py ft_sheet_key.py ft_board_env.py ft_board_mail.py \
         ft-approval-equiv.sh ft_approval_equiv.py; do cp "$SRC/$f" "$T/bin/"; done
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/bin/sh\necho "OK cherry stub"; exit 0\n' > "$T/bin/ft-nano-cherry-gate.sh"
printf '#!/bin/sh\necho "$*" >> "%s"\n' "$T/baton.calls" > "$T/bin/baton"            # 가짜 baton = 기록만(실 아카이브·삭제 0)
printf '#!/bin/sh\necho "$*" >> "%s"\n' "$T/sweep.calls" > "$T/bin/ft-wt-sweep.sh"   # 가짜 분리 정리 = 기록만(.deleting-<ts> 는 남는다)
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    case "$*" in
      *pane_current_path*) if [ -s "$FAKE_PANE_CWDS" ]; then cat "$FAKE_PANE_CWDS"; else echo "no server running on /tmp/fake"; exit 1; fi;;
      *) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
    esac;;
  ls) if [ -s "$FAKE_PANES" ]; then cut -d'|' -f1 "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option) echo "$*" >> "$FAKE_LOG";;
  kill-session) echo "$*" >> "$FAKE_LOG"; : > "$FAKE_PANES"; : > "$FAKE_PANE_CWDS";;   # kill 뒤 세션 0(계획 ① 계보 검사가 본다)
esac
EOF
# P8: 팩 리포 «git worktree list» 만 rc42 로 주입(그 밖 git 은 진짜) — 표식 파일이 있을 때만
cat > "$T/fake/git" <<EOF
#!/usr/bin/env bash
if [ -e "$T/gitfail" ]; then case " \$* " in *" -C $T/pack worktree list"*) echo "fatal: injected rc42" >&2; exit 42;; esac; fi
exec $(command -v git) "\$@"
EOF
cat > "$T/fake/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_GH_LOG"; cat "$FAKE_GH_JSON"
EOF
chmod +x "$T/bin/"* "$T/fake/"*
rm -rf "$T/basebin"; cp -R "$T/bin" "$T/basebin"
git -C "$HERE" show "$BASE_REV:feature-pack/fable-team/legacy/1.x/harness/bin/ft-nano-close.sh" > "$T/basebin/ft-nano-close.sh" 2>/dev/null && [ -s "$T/basebin/ft-nano-close.sh" ] \
  && ok "기준판 $BASE_REV 꺼냄" || bad "기준판 $BASE_REV 를 못 꺼냄"

GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
# R = BYZ 꼴(원격 = github 꼴 이름 → 로컬 bare) · 가지 nano/k 만 있고 워크트리 0(세트 SHA0)
R="$T/repo"; mkdir -p "$R"; git -C "$R" init -q -b main; GC "$R" commit -q --allow-empty -m init
BYZ_URL='https://github.com/lptest/byz.git'; git init -q --bare -b main "$T/R-origin.git"
git -C "$R" remote add origin "$BYZ_URL"; git -C "$R" config "url.$T/R-origin.git.insteadOf" "$BYZ_URL"; git -C "$R" push -q origin main; git -C "$R" fetch -q origin
GC "$R" worktree add -q "$R/.worktrees/harness-k" -b nano/k
mkdir -p "$R/.worktrees/harness-k/scripts"; echo 'print(1)' > "$R/.worktrees/harness-k/scripts/landed.py"
GC "$R/.worktrees/harness-k" add scripts/landed.py; GC "$R/.worktrees/harness-k" commit -q -m 세트
SHA0="$(git -C "$R" rev-parse nano/k)"; git -C "$R" worktree remove --force "$R/.worktrees/harness-k"
mkdir -p "$R/.fable-team" "$R/design/harness/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-harness-nano-k#0'; CARD="$R/design/harness/indices/진행/k.md"; SEATS="$R/.fable-team/seats-harness.json"; LEDGER="$T/ledger.md"
# P = 팩 꼴 + bare 원격 · .worktree-info.json 은 «추적 파일» 이고 가지 값이 낡았다(실측 꼴)
git init -q --bare -b main "$T/P-origin.git"
P="$T/pack"; mkdir -p "$P"; git -C "$P" init -q -b main
printf '{"branch":"feat/daily-trend-viewer"}\n' > "$P/.worktree-info.json"; printf '.fable-team/\n' > "$P/.gitignore"
GC "$P" add .worktree-info.json .gitignore; GC "$P" commit -q -m pinit
git -C "$P" remote add origin "$T/P-origin.git"; git -C "$P" push -q origin main; git -C "$P" fetch -q origin
PW="$P/.worktrees/k"; PPLAN="$P/.fable-team/state/wt-clean/$SEAT.sh"

pack_wt() {  # pack_wt <폴더 이름> <가지> <착지 1|0> — 팩 워크트리 1개(커밋 1 · 착지면 origin/main 에 ff)
  local w="$P/.worktrees/$1"
  GC "$P" worktree add -q "$w" -b "$2" origin/main
  echo "$1" > "$w/kit-$1.sh"; GC "$w" add "kit-$1.sh"; GC "$w" commit -q -m "work $1"
  if [ "$3" = 1 ]; then git -C "$P" push -q origin "$2:main"; git -C "$P" fetch -q origin; fi
  find "$w" -exec touch -t 202601010000 {} +   # ③ 유휴 검사(최근 편집 0) — 픽스처 mtime 고정(타이밍 의존 0)
}
reset_all() {  # 팩 워크트리·가지·계획 폴더·원격 main 을 처음으로
  local w
  for w in "$P/.worktrees/"*; do [ -e "$w" ] && git -C "$P" worktree remove --force "$w" 2>/dev/null; rm -rf "$w"; done
  git -C "$P" worktree prune
  for b in $(git -C "$P" for-each-ref --format='%(refname:short)' refs/heads/ | grep -vx main); do git -C "$P" branch -q -D "$b"; done
  git -C "$P" push -q -f origin main:main; git -C "$P" fetch -q --prune origin
  rm -rf "$P/.fable-team" "$T/wtclean" "$T/gitfail"; mkdir -p "$T/wtclean"
  : > "$T/panes"; : > "$T/pane-cwds"; printf '%s' "$R" > "$T/cwd"; : > "$T/tlog"; : > "$T/ghlog"; : > "$T/baton.calls"; : > "$T/sweep.calls"; : > "$LEDGER"
  printf '{"%s":{"role":"nano","index":"design/harness/indices/진행/k.md"}}\n' "$SEAT" > "$SEATS"
}
card_byz() {  # P2 꼴 — 세트 = BYZ SHA0 · 대상 = BYZ 경로 · 착지 PR #77
  printf '# 인덱스: k\n<!-- ledger: design/harness/GOAL-harness.md -->\n## 상태\n- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n- 대상: %s/scripts/landed.py\n- 착지: PR #77 squash\n' "$SHA0" "$R" > "$CARD"
  printf '{"state":"MERGED","mergeCommit":{"oid":"%s"},"headRefOid":"%s"}\n' "$SHA0" "$SHA0" > "$T/gh.json"
}
card_pack() {  # P1 꼴 — 세트 = 팩 워크트리 HEAD
  printf '# 인덱스: k\n<!-- ledger: design/harness/GOAL-harness.md -->\n- 설치: 있음 — 팩 키트 1\n\n## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$(git -C "$PW" rev-parse HEAD)" > "$CARD"
}
close() { ( cd "$R" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FT_PACK_ROOT="$P" BATON_BIN="$T/bin/baton" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" FAKE_GH_JSON="$T/gh.json" \
  FT_NANO_PREFIX=byz-harness-nano- FT_NANO_WT_PREFIX=harness- FT_NANO_FEAT=origin/main FT_REAP_RETRY_SLEEP=0 \
  FT_SEATS_JSON="$SEATS" FT_NANO_LEDGER="$LEDGER" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" \
  bash "${CLOSE_BIN:-$T/bin/ft-nano-close.sh}" "$SEAT" --result "$T/result.md" --recv 1 "$@" 2>&1 ); }
live() { printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$1" > "$T/pane-cwds"; printf '%s' "$1" > "$T/cwd"; }
cleaned() {  # cleaned <이름> — 팩 워크트리 0 · 가지 그대로 · 계획 .done · 분리 정리 위임 · BYZ 계획 폴더 0
  [ ! -e "$PW" ] && ok "  └ $1 팩 워크트리 0(이름 바꿈 → 분리 정리)" || bad "$1: 팩 워크트리 남음"
  git -C "$P" rev-parse -q --verify refs/heads/nano/k >/dev/null && ok "  └ $1 팩 가지 nano/k 그대로" || bad "$1: 팩 가지 삭제됨"
  [ -f "$PPLAN.done" ] && ok "  └ $1 계획 = <팩>/.fable-team/state/wt-clean/<좌석>.sh(.done)" || bad "$1: 팩 계획 없음: $(ls -A "$P/.fable-team/state/wt-clean" 2>&1)"
  [ -s "$T/sweep.calls" ] && ok "  └ $1 분리 정리 위임 기록" || bad "$1: sweep 위임 0"
  [ -z "$(ls -A "$T/wtclean")" ] && ok "  └ $1 BYZ 계획 폴더 0" || bad "$1: BYZ 계획 폴더에 생김: $(ls -A "$T/wtclean")"
}
mutant() {  # mutant <old> <new> → $T/mutbin/ft-nano-close.sh (자리 1곳 강제)
  rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin"
  python3 - "$T/mutbin/ft-nano-close.sh" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding='utf-8').read()
assert s.count(old) == 1, f"변이 자리 {s.count(old)}곳: {old[:70]}"
open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PY
}
p1() { reset_all; pack_wt k nano/k 1; card_pack; live "$PW"; out="$(close --wt "$PW" --branch nano/k "$@")"; rc=$?; }
p2() { reset_all; pack_wt k nano/k 1; card_byz; out="$(close --landed-pr 77)"; rc=$?; }

echo "== P1 --wt 팩 경로 --branch nano/k · 착지 끝 · 깨끗함 → 계획 생성 + kill 뒤 실행"
p1
[ "$rc" -eq 0 ] && has "$out" "KILLED $SEAT" "P1 rc0 · KILLED" || bad "P1 rc=$rc ← ${out:0:900}"
has "$out" "워크트리 정리 계획(팩): $PPLAN" "  └ 계획 안내 1줄(팩 폴더)"
has "$out" "워크트리 정리: cleaned" "  └ 실행 결과 cleaned"
hasnt "$out" "INFO 팩 워크트리 정리 = 별 경로" "  └ «별 경로» 계획 0 줄 없음"
hasnt "$out" "사람 ! 실행" "  └ .sh.hil 사람 안내 0(자동 실행)"
cleaned P1
has "$(cat "$LEDGER")" "mode=pack-wt wt=$PW branch=nano/k" "  └ 원장 mode=pack-wt"
has "$(cat "$LEDGER")" "· wt=cleaned" "  └ 원장 표식 wt=cleaned"

echo "== P2 --landed-pr · --wt 없음 · 세션 0 · 좌석 워크트리가 팩에만 → 키로 찾아 정리"
p2
[ "$rc" -eq 0 ] && has "$out" "CLOSED-BACKFILL $SEAT" "P2 rc0 · CLOSED-BACKFILL" || bad "P2 rc=$rc ← ${out:0:900}"
has "$out" "워크트리 정리 계획(팩): $PPLAN" "  └ 키로 찾아 계획(팩 폴더)"
has "$out" "워크트리 정리: cleaned" "  └ 실행 결과 cleaned"
cleaned P2
has "$(cat "$LEDGER")" "pack=$PW" "  └ 원장 행에 팩 경로"
has "$(cat "$LEDGER")" "· wt=cleaned" "  └ 원장 표식 wt=cleaned"

echo "== P3 P2 + 팩 워크트리 미커밋 1줄 → 계획 가드 skipped · 워크트리 그대로 · rc0"
reset_all; pack_wt k nano/k 1; card_byz; echo dirty > "$PW/dirty.txt"; out="$(close --landed-pr 77)"; rc=$?
[ "$rc" -eq 0 ] && ok "P3 rc0" || bad "P3 rc=$rc ← ${out:0:900}"
has "$out" "[HIL] 실작업물 미커밋 1파일" "  └ 가드 skipped → [HIL] 1줄"
[ -d "$PW" ] && [ -f "$PW/dirty.txt" ] && ok "  └ 워크트리·미커밋 파일 그대로" || bad "P3: 워크트리 손댐"
has "$(cat "$LEDGER")" "wt=skipped:실작업물 미커밋 1파일" "  └ 원장 표식 skipped"
[ -f "$PPLAN.hil" ] && ok "  └ 계획 .sh.hil(사람 판정)" || bad "P3: .hil 없음 $(ls -A "$P/.fable-team/state/wt-clean" 2>&1)"

echo "== P4 가지 이름 nano/ 아님(r1363 꼴 · 착지 끝) → 계획 0 + INFO · 워크트리 그대로"
reset_all; pack_wt k k 1; card_byz; out="$(close --landed-pr 77)"; rc=$?
[ "$rc" -eq 0 ] && ok "P4 rc0" || bad "P4 rc=$rc ← ${out:0:900}"
has "$out" "INFO 팩 워크트리 $PW — 가지 이름 nano/" "  └ INFO «가지 이름 nano/ 아님»"
hasnt "$out" "워크트리 정리 계획(팩)" "  └ 계획 0"
[ -d "$PW" ] && [ ! -e "$P/.fable-team/state/wt-clean" ] && ok "  └ 워크트리 그대로 · 팩 계획 폴더 0" || bad "P4: 손댐"

echo "== P5 같은 키 팩 워크트리 2개 → 계획 0 + INFO «후보 2»"
reset_all; pack_wt k nano/k 1; pack_wt k-r2 nano/k-r2 1; card_byz; out="$(close --landed-pr 77)"; rc=$?
[ "$rc" -eq 0 ] && ok "P5 rc0" || bad "P5 rc=$rc ← ${out:0:900}"
has "$out" "후보 2(" "  └ INFO «후보 2»"
[ -d "$PW" ] && [ -d "$P/.worktrees/k-r2" ] && [ ! -e "$P/.fable-team/state/wt-clean" ] && ok "  └ 두 워크트리 그대로 · 계획 0" || bad "P5: 손댐"

echo "== P6 BYZ 나노(팩 후보 0) → 출력 = 기준판 · 팩 계획 폴더 0"
reset_all; card_byz; a="$(close --landed-pr 77 | grep -v '^STEP ')"
reset_all; card_byz; b="$(CLOSE_BIN="$T/basebin/ft-nano-close.sh" close --landed-pr 77 | grep -v '^STEP ')"; b="${b//$T\/basebin/$T/bin}"
[ "$a" = "$b" ] && ok "P6 출력 = 기준판" || bad "P6 출력 다름: $(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | head -8 | tr '\n' '|')"
[ ! -e "$P/.fable-team" ] && ok "  └ 팩 계획 폴더 0" || bad "P6: 팩 폴더 생김"

echo "== P7 실사건 꼴 재실행(명부 행 0 · 원장 wt=none · 세션 0) → 같은 close 재실행이 팩 워크트리 정리"
reset_all; pack_wt k nano/k 1; card_byz; printf '{}\n' > "$SEATS"
printf -- '- **[2026-11-05 22:56 KST] `%s` 닫힘(ft-nano-close)**: ①결과 x. kill=1 · landed-pr=77 repo=lptest/byz · wt=none\n' "$SEAT" > "$LEDGER"
out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT (재실행" "P7 rc0 · 재실행 CLOSED" || bad "P7 rc=$rc ← ${out:0:900}"
has "$out" "워크트리 정리: cleaned" "  └ 실행 결과 cleaned"
cleaned P7
has "$(cat "$LEDGER")" "· wt=cleaned" "  └ 원장 wt=none → wt=cleaned"

echo "== P8 git 실패(팩 worktree list rc42) · 착지 판정기 rc2 → «판정 불가» 1줄 + rc≠0 · 닫기·정리 0 (하드 룰 20 · DA HOLD 298689)"
reset_all; pack_wt k nano/k 1; card_byz; : > "$T/gitfail"; out="$(close --landed-pr 77)"; rc=$?
[ "$rc" -ne 0 ] && ok "P8a 초회 rc=$rc(≠0)" || bad "P8a 초회 rc=0 ← ${out:0:600}"
has "$out" "판정 불가" "  └ P8a «판정 불가» 줄"
hasnt "$out" "CLOSED-BACKFILL" "  └ P8a CLOSED-BACKFILL 0"
[ -d "$PW" ] && jq -e --arg s "$SEAT" 'has($s)' "$SEATS" >/dev/null && [ ! -s "$LEDGER" ] && ok "  └ P8a 워크트리·명부 그대로 · 원장 행 0" || bad "P8a: 상태 바뀜"
reset_all; pack_wt k nano/k 1; card_byz; printf '{}\n' > "$SEATS"; : > "$T/gitfail"
printf -- '- **[2026-11-05 22:56 KST] `%s` 닫힘(ft-nano-close)**: ①결과 x. kill=1 · wt=none\n' "$SEAT" > "$LEDGER"
out="$(close)"; rc=$?
[ "$rc" -ne 0 ] && ok "P8b 재실행 rc=$rc(≠0)" || bad "P8b 재실행 rc=0 ← ${out:0:600}"
has "$out" "판정 불가" "  └ P8b «판정 불가» 줄"
hasnt "$out" "CLOSED $SEAT" "  └ P8b CLOSED 0"
[ -d "$PW" ] && ok "  └ P8b 워크트리 그대로" || bad "P8b: 워크트리 손댐"
rm -rf "$T/lcbin"; cp -R "$T/bin" "$T/lcbin"; printf '#!/bin/sh\necho no; echo "ref 없음" >&2; exit 2\n' > "$T/lcbin/ft-landed-check.sh"
reset_all; pack_wt k nano/k 1; card_byz; out="$(CLOSE_BIN="$T/lcbin/ft-nano-close.sh" close --landed-pr 77)"; rc=$?
[ "$rc" -ne 0 ] && has "$out" "판정 불가" "P8c 착지 판정기 rc2 → 판정 불가 rc=$rc" || bad "P8c rc=$rc ← ${out:0:600}"
[ -d "$PW" ] && [ ! -s "$LEDGER" ] && ok "  └ P8c 워크트리 그대로 · 원장 행 0" || bad "P8c: 상태 바뀜"

echo "== 기준판 — P1·P2 가 FAIL 이어야 한다(팩 워크트리 남음)"
CLOSE_BIN="$T/basebin/ft-nano-close.sh" p1; [ -d "$PW" ] && ok "  └ 기준판 P1 FAIL(워크트리 남음 rc=$rc)" || bad "기준판 P1 이 통과 — 시험이 못 가른다"
CLOSE_BIN="$T/basebin/ft-nano-close.sh" p2; [ -d "$PW" ] && ok "  └ 기준판 P2 FAIL(워크트리 남음 rc=$rc)" || bad "기준판 P2 이 통과 — 시험이 못 가른다"

echo "== 변이 — 전부 FAIL 이어야 한다"
mutant '_wt_clean_plan; PK_PLAN="$PLAN"   # r1405-mut:plan' 'PK_PLAN=""'
CLOSE_BIN="$T/mutbin/ft-nano-close.sh" p1; [ -d "$PW" ] && ok "  └ 변이 1(계획 0) → P1 FAIL" || bad "변이 1 P1 통과"
CLOSE_BIN="$T/mutbin/ft-nano-close.sh" p2; [ -d "$PW" ] && ok "  └ 변이 1(계획 0) → P2 FAIL" || bad "변이 1 P2 통과"
mutant '  else _pack_find; r=$?; fi   # r1405-mut:find' '  else r=1; fi'
CLOSE_BIN="$T/mutbin/ft-nano-close.sh" p2; [ -d "$PW" ] && ok "  └ 변이 2(키로 찾기 삭제) → P2 FAIL" || bad "변이 2 P2 통과"
mutant '_is_seat_branch "$br" || { _PK_INFO="INFO 팩 워크트리 $wt — 가지 이름' 'true || { _PK_INFO="INFO 팩 워크트리 $wt — 가지 이름'
reset_all; pack_wt k k 1; card_byz; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 77)"
[ ! -d "$PW" ] && ok "  └ 변이 3(nano/ 검사 삭제) → P4 FAIL(워크트리 지워짐)" || bad "변이 3 P4 통과 ← $(printf '%s' "$out" | tail -4 | tr '\n' '|')"
mutant 'if [ "${#hits[@]}" -gt 1 ]; then _PK_INFO=' 'if false; then _PK_INFO='
reset_all; pack_wt k nano/k 1; pack_wt k-r2 nano/k-r2 1; card_byz; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 77)"
case "$out" in *"후보 2("*) bad "변이 4 P5 통과";; *) ok "  └ 변이 4(후보 수 검사 삭제) → P5 FAIL(INFO 없음)";; esac
mutant 'return 2; }   # r1405-mut:gitfail' 'return 1; }'
reset_all; pack_wt k nano/k 1; card_byz; : > "$T/gitfail"; CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 77 >/dev/null; rc=$?
[ "$rc" -eq 0 ] && ok "  └ 변이 5(git 실패 = 정리 0 으로 합침) → P8a FAIL(rc0 닫힘)" || bad "변이 5 P8a 통과 rc=$rc"
reset_all; pack_wt k nano/k 1; card_byz; printf '{}\n' > "$SEATS"; : > "$T/gitfail"
printf -- '- **[2026-11-05 22:56 KST] `%s` 닫힘(ft-nano-close)**: ①결과 x. kill=1 · wt=none\n' "$SEAT" > "$LEDGER"
CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close >/dev/null; rc=$?
[ "$rc" -eq 0 ] && ok "  └ 변이 5 → P8b FAIL(재실행 rc0)" || bad "변이 5 P8b 통과 rc=$rc"
mutant 'return 2;;   # r1405-mut:landfail' 'return 1;;'
cp "$T/lcbin/ft-landed-check.sh" "$T/mutbin/ft-landed-check.sh"
reset_all; pack_wt k nano/k 1; card_byz; CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 77 >/dev/null; rc=$?
[ "$rc" -eq 0 ] && ok "  └ 변이 6(판정기 rc2 = 미착지로 합침) → P8c FAIL(rc0 닫힘)" || bad "변이 6 P8c 통과 rc=$rc"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
