#!/usr/bin/env bash
# test_nano_close_suspended.sh — r450: ft-nano-close.sh --suspended "<사유>" (팀 정지 등으로 «미완» 인 채 멈춘 나노 닫기 · ⑥ 만 면제)
# 임시 git 리포 + 가짜 tmux(PATH 앞) + 실제 cherry 게이트(원장은 임시 경로)만 쓴다 — 실제 리포·seats·tmux 세션은 건드리지 않는다. GIT_* 환경 변수는 쓰지 않는다.
# 축 ⓐ 빈 사유 usage 2 ⓑ 통과 = ⑥ 면제·⑤ override·CLOSED suspended=1·카드 중단 끝줄·원장 행·브랜치 보존 ⓒ 미커밋 → [wip] 먼저(실패 = REJECT)
#    ⓓ 다른 우회 인자와 동시 usage 2 ⓔ 중단 줄 멱등 ⓕ 인자 없으면 불변(rc=1 증거 줄 REJECT) ⓖ 600/300·외부 호출·GIT_* 0 + 키트 짝 cmp0
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T0="$(mktemp -d)"; trap 'rm -rf "$T0"' EXIT; T="$(cd "$T0" && pwd -P)"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

echo "== ⓖ 키트 2곳 같은 바이트 + bash -n"
for f in ft-nano-close.sh ft-nano-suspended-check.sh; do
  cmp -s "$HERE/../../harness/bin/$f" "$SRC/$f" && ok "cmp $f (bin == kit)" || bad "cmp $f 다름"
  bash -n "$SRC/$f" && ok "bash -n $f" || bad "bash -n $f"
done

mkdir -p "$T/bin" "$T/fake"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"   # r448: 닫기의 reap = 같은 bin 스텁(env -i 시험 · 실기계 프로세스 0) · reap 자체는 test_seat_reap_left0.sh
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-suspended-check.sh" "$SRC/ft-nano-superseded-check.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-nano-cherry-gate.sh" "$SRC/ft-wt-sweep.sh" "$T/bin/"
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

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"

SEAT='byz-planner-nano-sus#0'; BR='nano/sus'; NW="$REPO/.worktrees/v65-sus"
CARD_REL='design/planner/indices/진행/sus.md'; CARD="$REPO/$CARD_REL"
REASON='팀 정지(판정 2365) · 시험 905 passed / 4 failed'
git -C "$REPO" worktree add -q "$NW" -b "$BR"
git -C "$NW" config user.email t@t; git -C "$NW" config user.name t
mkdir -p "$NW/scripts" && echo 'print(1)' > "$NW/scripts/unlanded.py"
git -C "$NW" add scripts/unlanded.py && git -C "$NW" commit -q -m "work (미랜딩 코드)"
SHA0="$(git -C "$NW" rev-parse HEAD)"
LEDGER="$T/ledger.md"; CHERRY_LOG="$T/cherry-override.log"

run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {  # 명부·pane·카드·나노 HEAD 를 «정상(세션 없음 · 미커밋 0 · 시험 rc=1 증거 줄)» 으로 리셋
  git -C "$NW" reset -q --hard "$SHA0"; git -C "$NW" clean -qfd
  printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$REPO/.fable-team/seats-planner.json"
  : > "$T/panes"; printf '%s' "$NW" > "$T/cwd"; : > "$T/tlog"; : > "$LEDGER"; rm -f "$CHERRY_LOG"; rm -rf "$T/wtclean"
  printf '# 인덱스: sus\n## 상태\n- 2026-10-19 진행\n- 세트: %s · 시험: bash t.sh (905 passed / 4 failed) rc=1 · 이슈: 1\n\n## 정본\n- 뒤 절\n' "$SHA0" > "$CARD"
}
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$LEDGER" FT_NANO_FEAT=main \
  FT_CHERRY_OVERRIDE_LEDGER="$CHERRY_LOG" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" FT_WT_AUTOCLEAN=0 bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 "$@"; }
status_last() { awk '/^## 상태[[:space:]]*$/{inb=1; last=""; next} /^## /{inb=0} inb && NF{last=$0} END{print last}' "$CARD"; }
untouched() {  # untouched <이름> — REJECT/usage 인데 명부·tmux·원장·카드가 그대로
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 해제 0" || bad "$1: tmux 변경"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 그대로" || bad "$1: 명부 삭제"
  [ ! -s "$LEDGER" ] && ok "  └ 닫힘 원장 행 0" || bad "$1: 원장 행 생김"
  hasnt "$(cat "$CARD")" "중단:" "  └ 카드 중단 줄 0"
}
usage2() {  # usage2 <이름> <close 인자...>
  local name="$1"; shift; setup; out="$(close "$@")"; rc=$?
  [ "$rc" -eq 2 ] && ok "$name → usage rc=2" || bad "$name — rc=$rc ← ${out:0:300}"
  untouched "$name"
}

echo "== ⓐ 빈 사유 → usage rc2 · 닫힘 0"
usage2 "ⓐ --suspended \"\"" --suspended ""
usage2 "ⓐ --suspended \"   \"(공백)" --suspended "   "
usage2 "ⓐ --suspended 값 누락" --suspended
usage2 "ⓐ 여러 줄 사유" --suspended $'한 줄\n두 줄'

echo "== ⓓ 다른 우회 인자와 동시 → usage rc2"
usage2 "ⓓ --suspended + --superseded-by" --suspended "$REASON" --superseded-by design/planner/indices/진행/other.md
usage2 "ⓓ --superseded-by + --suspended(순서 바꿈)" --superseded-by design/planner/indices/진행/other.md --suspended "$REASON"
usage2 "ⓓ --suspended + --cherry-override" --suspended "$REASON" --cherry-override "사람 사유"
usage2 "ⓓ --cherry-override + --suspended(순서 바꿈)" --cherry-override "사람 사유" --suspended "$REASON"

echo "== ⓕ 인자 없으면 지금 동작 그대로 — rc=1 증거 줄은 ⑥ REJECT"
setup; out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "REJECT $SEAT" "ⓕ 인자 없음 + 시험 rc=1 증거 줄 → REJECT" || bad "ⓕ rc=$rc ← ${out:0:400}"
has "$out" "rc=1" "  └ 사유 = 증거 줄 rc=1"
hasnt "$out" "suspended" "  └ 출력에 suspended 표식 없음"
untouched "ⓕ"

echo "== ⓑ --suspended 통과 (세션 없음) → CLOSED-ABSENT suspended=1 · 카드 중단 끝줄 · 원장 · cherry override · 브랜치 보존"
setup; out="$(close --suspended "$REASON")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED-ABSENT $SEAT suspended=1 reason=$REASON set=$SHA0" "ⓑ 통과 rc=0 · CLOSED-ABSENT <좌석> suspended=1 reason=<사유> set=<HEAD>" || bad "ⓑ rc=$rc ← ${out:0:800}"
has "$out" "SUSPENDED-OK card=" "  └ ⑥ 자리 = 중단 검사 통과 줄"
hasnt "$out" "증거 줄" "  └ ⑥ 증거 줄 검사 면제"
L="$(status_last)"
case "$L" in "중단: $REASON · 세트 $SHA0 · "*" · 재개 = planner 발주 뒤 새 세션(브랜치 $BR 보존)") ok "  └ 카드 «## 상태» 맨 끝줄 = 중단: <사유> · 세트 <HEAD> · <날짜> · 재개 …";; *) bad "  └ 상태 끝줄 «${L}»";; esac
[[ "$L" =~ ·\ 세트\ [0-9a-f]{40}\ ·\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}\ · ]] && ok "  └ 세트 40hex · 날짜 YYYY-MM-DD HH:MM" || bad "  └ 세트/날짜 꼴 «${L}»"
has "$(tail -2 "$CARD")" "- 뒤 절" "  └ 뒤 절(## 정본)은 그대로 · 중단 줄은 상태 절 안"
has "$(cat "$LEDGER")" "suspended=1 reason=$REASON set=$SHA0" "  └ 닫힘 원장 행에 suspended=1 reason=<사유> set=<HEAD>"
[ "$(wc -l < "$CHERRY_LOG" | tr -d ' ')" = "1" ] && has "$(cat "$CHERRY_LOG")" "reason=suspended: $REASON" "  └ ⑤ cherry override 원장 1행 · 사유 = suspended: <사유>" || bad "  └ cherry 원장: $(cat "$CHERRY_LOG" 2>&1)"
jq -e --arg s "$SEAT" 'has($s) | not' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 삭제(기존 CLOSED 경로)" || bad "명부에 좌석 남음"
git -C "$REPO" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 실재(삭제 0)" || bad "브랜치 삭제됨"
[ "$(git -C "$NW" rev-parse HEAD)" = "$SHA0" ] && ok "  └ 미커밋 0 이면 HEAD 그대로([wip] 0)" || bad "HEAD 가 움직임"

echo "== ⓑ 세션이 살아 있는 좌석 → CLOSED suspended=1 + kill (브랜치 보존)"
setup; printf '%s|%%1\n' "$SEAT" > "$T/panes"
out="$(close --suspended "$REASON")"
has "$out" "CLOSED $SEAT suspended=1 reason=$REASON set=$SHA0 (명부 삭제 · 원장 append)" "살아 있는 좌석 → CLOSED <좌석> suspended=1 reason=<사유> set=<HEAD>"
has "$out" "KILLED $SEAT" "  └ 세션 kill(표준승인 경로)"
git -C "$REPO" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 삭제 0" || bad "브랜치 삭제됨"

echo "== ⓒ 미커밋 있음 → [wip] 커밋 먼저 · 그 HEAD 로 중단"
setup; echo 'wip' > "$NW/scripts/half.py"; echo 'x' >> "$NW/scripts/unlanded.py"
out="$(close --suspended "$REASON")"; rc=$?
SHA1="$(git -C "$NW" rev-parse HEAD)"
[ "$rc" -eq 0 ] && [ "$SHA1" != "$SHA0" ] && ok "ⓒ 미커밋 → rc=0 · HEAD 이동([wip] 커밋)" || bad "ⓒ rc=$rc head=$SHA1 ← ${out:0:600}"
has "$(git -C "$NW" log -1 --format=%s)" "[wip] nano close $SEAT" "  └ 커밋 메시지 [wip] nano close <좌석>"
[ -z "$(git -C "$NW" status --porcelain)" ] && ok "  └ 미커밋 0(새 파일·수정 전부 커밋)" || bad "  └ 미커밋 남음: $(git -C "$NW" status --porcelain)"
has "$out" "set=$SHA1" "  └ CLOSED 의 set = [wip] 뒤 HEAD"
has "$(status_last)" "· 세트 $SHA1 ·" "  └ 카드 중단 줄 세트 = [wip] 뒤 HEAD"
setup; echo 'wip' > "$NW/scripts/half.py"
printf '#!/bin/sh\nexit 1\n' > "$REPO/.git/hooks/pre-commit"; chmod +x "$REPO/.git/hooks/pre-commit"
out="$(close --suspended "$REASON")"; rc=$?
rm -f "$REPO/.git/hooks/pre-commit"
[ "$rc" -eq 1 ] && has "$out" "[wip] 커밋 실패" "ⓒ [wip] 커밋 실패 → REJECT" || bad "ⓒ 커밋 실패 rc=$rc ← ${out:0:400}"
untouched "ⓒ 커밋 실패"
[ "$(git -C "$NW" rev-parse HEAD)" = "$SHA0" ] && ok "  └ HEAD 그대로" || bad "  └ HEAD 이동"

echo "== ⓔ 멱등 — 같은 세트의 중단 끝줄이 이미 있으면 다시 쓰지 않는다"
setup; out="$(close --suspended "$REASON")"
printf '{"%s":{"role":"nano","index":"%s"}}\n' "$SEAT" "$CARD_REL" > "$REPO/.fable-team/seats-planner.json"; : > "$LEDGER"
out="$(close --suspended "$REASON")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "기록=이미 있음" "ⓔ 같은 세트로 다시 닫기 → rc=0 · 기록=이미 있음" || bad "ⓔ rc=$rc ← ${out:0:400}"
[ "$(grep -c '^중단:' "$CARD")" = 1 ] && ok "  └ 카드 중단 줄 1개(중복 append 0)" || bad "  └ 중단 줄 $(grep -c '^중단:' "$CARD")개"
CHK() { run bash "$T/bin/ft-nano-suspended-check.sh" "$CARD" --wt "$NW" "$@"; }
setup; CHK --reason "$REASON" --apply >/dev/null; out="$(CHK --reason "$REASON" --apply)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "기록=이미 있음" "ⓔ 검사 단독 --apply 2회 → 두 번째 이미 있음" || bad "ⓔ 단독 rc=$rc ← $out"
[ "$(grep -c '^중단:' "$CARD")" = 1 ] && ok "  └ 중단 줄 1개" || bad "  └ 중단 줄 $(grep -c '^중단:' "$CARD")개"

echo "== 검사 단독 REJECT/usage — detached · 미커밋 · 상태 절 없음 · 빈 사유 · --apply 없으면 쓰기 0"
setup; out="$(CHK --reason "$REASON")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "기록=검사만" "--apply 없음 → 통과 · 기록=검사만" || bad "검사만 rc=$rc ← $out"
hasnt "$(cat "$CARD")" "중단:" "  └ 카드 쓰기 0"
setup; echo x > "$NW/new.txt"; out="$(CHK --reason "$REASON" --apply)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "[wip] 먼저" "미커밋 → REJECT «[wip] 먼저»" || bad "미커밋 rc=$rc ← $out"
hasnt "$(cat "$CARD")" "중단:" "  └ 카드 쓰기 0"
setup; git -C "$NW" checkout -q --detach; out="$(CHK --reason "$REASON")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "detached" "detached HEAD → REJECT" || bad "detached rc=$rc ← $out"
git -C "$NW" checkout -q "$BR"
setup; printf '# 인덱스: sus\n## 배경\n- x\n' > "$CARD"; out="$(CHK --reason "$REASON" --apply)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "«## 상태» 절이 없다" "상태 절 없음 → REJECT" || bad "상태 절 없음 rc=$rc ← $out"
setup; out="$(CHK --reason "  ")"; rc=$?; [ "$rc" -eq 2 ] && ok "빈 사유 → usage 2" || bad "빈 사유 rc=$rc"
setup; out="$(CHK)"; rc=$?; [ "$rc" -eq 2 ] && ok "--reason 누락 → usage 2" || bad "--reason 누락 rc=$rc"

echo "== ⓖ 600/300 s · 외부 호출 · GIT_* env 0 (새 검사 스크립트 + close 의 r450 줄)"
NEWL="$(cat "$SRC/ft-nano-suspended-check.sh"; grep -n 'r450\|SUSP\|_susp_wip\|_su_' "$SRC/ft-nano-close.sh")"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE '(^|[^0-9])(600|300)([^0-9]|$)')" ":" "ⓖ 600/300 숫자 0"
hasnt "$(printf '%s\n' "$NEWL" | grep -nE 'curl|wget|https?://|gh |nc ')" ":" "ⓖ 외부 호출 0"
hasnt "$NEWL" "GIT_DIR=" "ⓖ GIT_DIR env 0"
hasnt "$NEWL" "GIT_WORK_TREE=" "ⓖ GIT_WORK_TREE env 0"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
