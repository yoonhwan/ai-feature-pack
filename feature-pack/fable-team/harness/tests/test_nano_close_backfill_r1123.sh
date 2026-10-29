#!/usr/bin/env bash
# test_nano_close_backfill_r1123.sh — r1123: ft-nano-close.sh --landed-pr <N> 에서 좌석이 «세션 없음 ∧ 워크트리 없음» 이면 착지 판정 통과 때만 명부 행을 닫는다(CLOSED-BACKFILL).
# 임시 git 리포 + 가짜 tmux·gh(PATH 앞)만 쓴다 — 실 리포·명부·tmux·gh(네트워크) 0 · 자기 재호출은 real_state_guard 의 RSG_ACTIVE 재진입 표지 하나뿐 · 고정 sleep 0.
# 반례(카드 동결): R1 n5c 꼴(세트 = PR head) → CLOSED-BACKFILL · 명부 닫힘 · 원장 backfill=1 · kill 0  R2 세트 ≠ head(판정기 NOT-EQUIV) → CLOSED-BACKFILL + WARN 세트 불일치
#   R2b 판정기 rc3(판정 불가) → REJECT 그대로  R3 카드 없음 → CLOSED-BACKFILL + WARN 카드 없음(리포 = 좌석 가지가 사는 곳) · R3b 가지 0곳 → REJECT · gh 0
#   R4 PR 미착지(OPEN · main 에 산출 없음) → ③세션 없음 + 착지 사유 REJECT  R5 --landed-pr 없음 → ③ REJECT  R6 워크트리 있음 → ABSENT 길  R7 세션 있음 → 지금 길  R8 gh 실패 → REJECT
#   R4·R5·R6·R7·R8 = 기준판(팩 origin/main 3959eb0144 의 ft-nano-close.sh) 출력과 바이트 같음(STEP 줄 제외)
#   변이: «분기 끔» → R1 이 ③ REJECT · «착지 판정 생략» → R4 가 닫힘 · «판정 불가도 WARN» → R2b 가 닫힘 (전부 변이 FAIL 이어야 한다)
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(재진입 표지 RSG_ACTIVE)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
BASE_REV=3959eb0144
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:700}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:700}";; *) ok "$3";; esac; }

echo "== ⓔ bin == kit · bash -n (/bin/bash 3.2 포함)"
cmp -s "$HERE/../bin/ft-nano-close.sh" "$SRC/ft-nano-close.sh" && ok "cmp bin == kit" || bad "cmp bin ≠ kit"
bash -n "$SRC/ft-nano-close.sh" && /bin/bash -n "$SRC/ft-nano-close.sh" && ok "bash -n · /bin/bash 3.2 -n" || bad "bash -n"

mkdir -p "$T/bin" "$T/fake"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
for f in ft-nano-close.sh ft-nano-evidence-check.sh ft-nano-cherry-gate.sh ft-nano-superseded-check.sh ft-nano-suspended-check.sh ft-wt-sweep.sh \
         ft-team-lib.sh ft_git_capped.py ft_teamset.py ft-sheet-events.sh ft_sheet_events.py ft_sheet_confirm.py ft_sheet_key.py ft_board_env.py ft_board_mail.py \
         ft-approval-equiv.sh ft_approval_equiv.py; do cp "$SRC/$f" "$T/bin/"; done
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
[ "${FAKE_GH_RC:-0}" = 0 ] || { echo "gh: Not Found (HTTP 404)" >&2; exit "$FAKE_GH_RC"; }
cat "$FAKE_GH_JSON"
EOF
chmod +x "$T/bin/"* "$T/fake/"*
# 기준판 = 같은 bin 에 ft-nano-close.sh 만 옛 판으로
rm -rf "$T/basebin"; cp -R "$T/bin" "$T/basebin"
git -C "$HERE" show "$BASE_REV:feature-pack/fable-team/harness/bin/ft-nano-close.sh" > "$T/basebin/ft-nano-close.sh" 2>/dev/null && [ -s "$T/basebin/ft-nano-close.sh" ] \
  && ok "기준판 $BASE_REV 꺼냄" || bad "기준판 $BASE_REV 를 못 꺼냄"

REPO="$T/repo"; PACK="$T/pack"; mkdir -p "$REPO" "$PACK"
for r in "$REPO" "$PACK"; do git -C "$r" init -q -b main && git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init; done
BYZ_URL='https://github.com/lptest/byz.git'
git -C "$REPO" remote add origin "$BYZ_URL"; git -C "$REPO" config "url.$REPO.insteadOf" "$BYZ_URL"
git -C "$PACK" remote add origin 'https://github.com/lptest/pack.git'
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-planner-nano-bf#0'; BR='nano/bf'; NW="$REPO/.worktrees/v65-bf"
CARD_REL='design/planner/indices/진행/bf.md'; CARD="$REPO/$CARD_REL"
git -C "$REPO" worktree add -q "$NW" -b "$BR"
mkdir -p "$NW/scripts" && echo 'print(1)' > "$NW/scripts/landed.py"
git -C "$NW" add scripts/landed.py && git -C "$NW" -c user.email=t@t -c user.name=t commit -q -m "세트"
SHA0="$(git -C "$NW" rev-parse HEAD)"
echo 'print(9)' > "$NW/scripts/landed.py"; git -C "$NW" -c user.email=t@t -c user.name=t commit -qam "세트 뒤 변경(PR head · 세트와 다름)"
SHAX="$(git -C "$NW" rev-parse HEAD)"
git -C "$NW" reset -q --hard "$SHA0"; git -C "$REPO" worktree remove --force "$NW"   # 세션 0 · 워크트리 0 · 가지만 남음(lecture 꼴)
printf 'm1\n' > "$REPO/main.txt"; git -C "$REPO" add main.txt; git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m 'main 1'
git -C "$REPO" update-ref refs/remotes/origin/main HEAD
LEDGER="$T/ledger.md"

run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FT_PACK_ROOT="$PACK" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" FAKE_GH_LOG="$T/ghlog" FAKE_GH_JSON="$T/gh.json" FAKE_GH_RC="${FAKE_GH_RC:-0}" "$@" 2>&1 ); }
gh_json() { printf '{"state":"%s","mergeCommit":%s,"headRefOid":"%s"}\n' "$1" "$2" "$3" > "$T/gh.json"; }
setup() {  # 세션 0 · 워크트리 0 · 명부 행 · 카드(세트 = SHA0 · 착지 줄) · gh MERGED head = SHA0
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$REPO/.fable-team/seats-planner.json"
  : > "$T/panes"; printf '%s' "$REPO" > "$T/cwd"; : > "$T/tlog"; : > "$T/ghlog"; : > "$LEDGER"; rm -rf "$T/wtclean"
  git -C "$REPO" worktree remove --force "$NW" 2>/dev/null; git -C "$REPO" worktree prune
  git -C "$REPO" rev-parse -q --verify "refs/heads/$BR" >/dev/null || git -C "$REPO" branch -q "$BR" "$SHA0"
  printf '# 인덱스: bf\n## 상태\n- 세트: %s · 시험: bash t.sh (3 passed) rc=0 · 이슈: 0\n- 대상: %s/scripts/landed.py\n- 착지: PR #77 squash\n' "$SHA0" "$REPO" > "$CARD"
  gh_json MERGED "{\"oid\":\"$SHAX\"}" "$SHA0"
}
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 bash "${CLOSE_BIN:-$T/bin/ft-nano-close.sh}" "$SEAT" --result "$T/result.md" --recv 1 "$@"; }
untouched() {
  [ ! -s "$T/tlog" ] && ok "  └ kill·태그 해제 0" || bad "$1: tmux 변경 $(cat "$T/tlog")"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 원장 행 0" || bad "$1: 원장 행 생김"
}
closed_bf() {  # closed_bf <이름> — 명부 닫힘 · 원장 backfill=1 · kill 0 · 브랜치 보존 · 정리 계획 0
  jq -e --arg s "$SEAT" 'has($s) | not' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 행 닫힘" || bad "$1: 명부에 좌석 남음"
  has "$(cat "$LEDGER")" "backfill=1" "  └ 원장 꼬리 backfill=1"
  has "$(cat "$LEDGER")" "landed-pr=77" "  └ 원장 꼬리 landed-pr=77"
  [ ! -s "$T/tlog" ] && ok "  └ kill·태그 해제 0" || bad "$1: tmux 변경 $(cat "$T/tlog")"
  git -C "$REPO" rev-parse -q --verify "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 보존" || bad "$1: 브랜치 삭제"
  [ ! -d "$T/wtclean" ] || [ -z "$(ls -A "$T/wtclean")" ] && ok "  └ 정리 계획 0" || bad "$1: 정리 계획 생김"
}
same_as_base() {  # same_as_base <이름> <인자…> — 새 판·기준판 출력(STEP 줄 제외)이 같다
  local name="$1" a b; shift
  setup; [ -z "${PREP:-}" ] || eval "$PREP"; a="$(close "$@" | grep -v '^STEP ')"
  setup; [ -z "${PREP:-}" ] || eval "$PREP"; b="$(CLOSE_BIN="$T/basebin/ft-nano-close.sh" close "$@" | grep -v '^STEP ')"; b="${b//$T\/basebin/$T/bin}"   # bin 폴더 이름만 다르다
  [ "$a" = "$b" ] && ok "$name 출력 = 기준판" || bad "$name 출력 다름(< 새 · > 기준): $(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | head -12)"
  out="$a"
}

echo "== R1 n5c 꼴: 세션·워크트리 없음 + MERGED · 세트 = head → CLOSED-BACKFILL"
setup; out="$(close --landed-pr 77)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED-BACKFILL $SEAT landed-pr=77" "R1 rc0 · CLOSED-BACKFILL <좌석> landed-pr=<N>" || bad "R1 rc=$rc ← ${out:0:900}"
hasnt "$out" "WARN backfill" "  └ WARN 0"
closed_bf R1
[ "$(cat "$T/ghlog")" = "pr view 77 -R lptest/byz --json state,mergeCommit,headRefOid" ] && ok "  └ gh 1회 · -R lptest/byz" || bad "  └ gh: $(cat "$T/ghlog")"
setup; out="$(CLOSE_BIN="$T/basebin/ft-nano-close.sh" close --landed-pr 77)"
has "$out" "③세션 없음: $SEAT" "  └ 기준값: 기준판은 같은 입력을 ③세션 없음 REJECT"

echo "== R2 l10 꼴: 세트 ≠ head(판정기 NOT-EQUIV) → CLOSED-BACKFILL + WARN 세트 불일치"
setup; gh_json MERGED "{\"oid\":\"$SHAX\"}" "$SHAX"; out="$(close --landed-pr 77)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "WARN backfill: 세트 불일치(${SHA0:0:9}≠${SHAX:0:9})" "R2 rc0 · WARN 세트 불일치" || bad "R2 rc=$rc ← ${out:0:900}"
has "$out" "CLOSED-BACKFILL $SEAT landed-pr=77" "  └ CLOSED-BACKFILL"
has "$(cat "$LEDGER")" "warn=세트불일치" "  └ 원장 꼬리 warn=세트불일치"
closed_bf R2

echo "== R2b 판정기 rc3(판정 불가) → WARN 아님 · REJECT 그대로"
printf '#!/usr/bin/env bash\necho "ERROR 객체 없음(대조 불가)"\nexit 3\n' > "$T/rc3.sh"
R2B='cp "$T/rc3.sh" "$T/bin/ft-approval-equiv.sh"; gh_json MERGED "{\"oid\":\"$SHAX\"}" "$SHAX"'
setup; eval "$R2B"; out="$(close --landed-pr 77)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "판정기 rc=3" "R2b rc3 → REJECT" || bad "R2b rc=$rc ← ${out:0:700}"
has "$out" "③세션 없음: $SEAT" "  └ 첫 사유 = ③세션 없음 문구 그대로"
untouched R2b
cp "$SRC/ft-approval-equiv.sh" "$T/bin/ft-approval-equiv.sh"

echo "== R3 l46c 꼴: 카드 없음 → CLOSED-BACKFILL + WARN 카드 없음(리포 = 가지 nano/bf 가 사는 곳)"
setup; rm -f "$CARD"; out="$(close --landed-pr 77)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "WARN backfill: 카드 없음(index=$CARD_REL)" "R3 rc0 · WARN 카드 없음" || bad "R3 rc=$rc ← ${out:0:900}"
has "$out" "INFO backfill: 카드 없음 → 리포 = 좌석 가지 nano/bf 가 사는 곳($REPO)" "  └ 리포 근거 = 가지"
has "$(cat "$LEDGER")" "warn=카드없음" "  └ 원장 꼬리 warn=카드없음"
closed_bf R3
echo "== R3b 카드 없음 + 가지 0곳 → REJECT · gh 0"
setup; rm -f "$CARD"; git -C "$REPO" branch -q -D "$BR"; out="$(close --landed-pr 77)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "리포를 정할 수 없다(backfill · 카드 없음" "R3b → REJECT" || bad "R3b rc=$rc ← ${out:0:700}"
[ ! -s "$T/ghlog" ] && ok "  └ gh 0" || bad "  └ gh: $(cat "$T/ghlog")"
untouched R3b

echo "== R4 PR 미착지(OPEN · main 에 산출 없음) → ③세션 없음 + 착지 사유 · 기준판과 같음"
PREP='gh_json OPEN null "$SHA0"' same_as_base R4 --landed-pr 77
has "$out" "③세션 없음: $SEAT" "R4 ③세션 없음 문구"; has "$out" "state=OPEN · main 에 산출 없음" "  └ 착지 사유"; untouched R4
echo "== R5 --landed-pr 없음 → ③ REJECT · 기준판과 같음"
same_as_base R5; has "$out" "③세션 없음: $SEAT" "R5 ③세션 없음"; untouched R5
echo "== R6 세션 없음 ∧ 워크트리 있음 → ABSENT 길 · 기준판과 같음"
PREP='git -C "$REPO" worktree add -q "$NW" "$BR"' same_as_base R6 --landed-pr 77
has "$out" "CLOSED-ABSENT $SEAT landed-pr=77" "R6 CLOSED-ABSENT"; hasnt "$out" "backfill" "  └ backfill 0"
echo "== R7 세션 있음 → 지금 길 · 기준판과 같음"
PREP='git -C "$REPO" worktree add -q "$NW" "$BR"; find "$NW" -type f -exec touch -t 202001010000 {} +; printf "%s|%%9\n" "$SEAT" > "$T/panes"; printf "%s" "$NW" > "$T/cwd"' same_as_base R7 --landed-pr 77   # 유휴(③) = 옛 mtime
has "$out" "KILLED $SEAT" "R7 세션 kill 길 그대로"; hasnt "$out" "backfill" "  └ backfill 0"
echo "== R8 gh 실패 → REJECT · 기준판과 같음"
FAKE_GH_RC=1 same_as_base R8 --landed-pr 77
has "$out" "gh pr view 77 실패(rc=1" "R8 gh 실패 사유"; untouched R8

mutant() {  # mutant <old> <new> → $T/mutbin/ft-nano-close.sh
  rm -rf "$T/mutbin"; cp -R "$T/bin" "$T/mutbin"
  python3 - "$T/mutbin/ft-nano-close.sh" "$1" "$2" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read(); assert old in s, "변이 자리 없음: " + old[:60]
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
}
echo "== 변이 1 «분기 끔» → R1 이 ③ REJECT (변이 FAIL)"
mutant 'elif [ -n "$LANDED_PR" ]; then BACKFILL=1   # r1123-mut:branch' 'elif false; then BACKFILL=1'
setup; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 77)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "③세션 없음: $SEAT" "변이 1 → R1 REJECT = 시험이 잡는다" || bad "변이 1 rc=$rc — 변이가 안 먹었다"
echo "== 변이 2 «착지 판정 생략» → R4 가 닫힘 (변이 FAIL)"
mutant '  _lp_landed_gate || return 1
  return 0' '  return 0'
setup; gh_json OPEN null "$SHA0"; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 77)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED-BACKFILL" "변이 2 → R4 닫힘 = 시험이 잡는다" || bad "변이 2 rc=$rc — 변이가 안 먹었다: ${out:0:300}"
echo "== 변이 3 «판정 불가도 WARN» → R2b 가 닫힘 (변이 FAIL)"
mutant '[ "$BACKFILL" = 1 ] && [ -z "$_lp_undecided" ]; then' '[ "$BACKFILL" = 1 ]; then'
cp "$T/rc3.sh" "$T/mutbin/ft-approval-equiv.sh"
setup; gh_json MERGED "{\"oid\":\"$SHAX\"}" "$SHAX"; out="$(CLOSE_BIN="$T/mutbin/ft-nano-close.sh" close --landed-pr 77)"; rc=$?
[ "$rc" -eq 0 ] && ok "변이 3 → R2b 닫힘 = 시험이 잡는다" || bad "변이 3 rc=$rc — 변이가 안 먹었다: ${out:0:300}"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
