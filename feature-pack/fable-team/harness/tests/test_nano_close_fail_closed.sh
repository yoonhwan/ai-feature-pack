#!/usr/bin/env bash
# test_nano_close_fail_closed.sh — R400 r3(판정 2307 ①②): ft-nano-close 기본 원장 = «명단은 ref(origin/main) · 폴더는 원장 워크트리» + fail-closed(명부·원장 입구 · 명부 쓰기 실패)
# 임시 git 리포 + 가짜 tmux(PATH 앞) + 스크립트 사본만 쓴다 — 실제 리포·명부·tmux 세션·라이브 0. 픽스처 꼴 = test_nano_close_named_wt.sh.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/bin"; printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"   # r448: 닫기의 reap = 같은 bin 스텁(env -i 시험 · 실기계 프로세스 0) · reap 자체는 test_seat_reap_left0.sh
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

bash -n "$SRC/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"
bash -n "$SRC/ft-team-lib.sh" && ok "bash -n ft-team-lib.sh" || bad "bash -n ft-team-lib.sh"

mkdir -p "$T/bin" "$T/fake"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-hil.sh" "$SRC/ft-team-lib.sh" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
printf '#!/usr/bin/env bash\necho "OK cherry stub"; exit 0\n' > "$T/bin/ft-nano-cherry-gate.sh"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    case "$*" in
      *pane_current_path*) if [ -s "$FAKE_PANE_CWDS" ]; then cat "$FAKE_PANE_CWDS"; else echo "no server running on /tmp/fake"; exit 1; fi;;
      *) if [ -s "$FAKE_PANES" ]; then cat "$FAKE_PANES"; else echo "no server running on /tmp/fake"; exit 1; fi;;
    esac;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/bin/"* "$T/fake/"*

REPO="$T/repo"; mkdir -p "$REPO/design"
git -C "$REPO" init -q -b main
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
printf '| 팀 | 폴더 | 메모 |\n|---|---|---|\n| v65 | design/teams/v65/ | 이동 뒤 |\n| planner | design/planner/ | |\n' > "$REPO/design/TEAMS.md"
GIT add design/TEAMS.md && GIT commit -q -m "teams on main"
MAIN="$(git -C "$REPO" rev-parse HEAD)"
printf '| 팀 | 폴더 | 메모 |\n|---|---|---|\n| planner | design/planner/ | 옛 명단(v65 행 없음) |\n' > "$REPO/design/TEAMS.md"   # 실사건 1 재현: 원장 워크트리 사본은 옛 명단
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
OLDL="$REPO/design/v65/20260912/NANO-LEDGER-pm1-temp-sessions.md"; NEWL="$REPO/design/teams/v65/20260912/NANO-LEDGER-pm1-temp-sessions.md"

SEAT='byz-planner-nano-ovr#0'; CARD="$REPO/design/planner/indices/진행/ovr.md"; SEATS="$REPO/.fable-team/seats-planner.json"
NW="$REPO/.worktrees/cfo-ovr"; BR="fix/ovr-verdict"
GIT worktree add -q "$NW" -b "$BR"
git -C "$NW" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "work"
SHA="$(git -C "$NW" rev-parse HEAD)"

run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {  # 명부·pane·카드·원장 «정상» 리셋 — 원장은 옛 꼴(design/v65) 1곳에만 · origin/main ref 있음
  printf '{"%s":{"role":"nano","index":"design/planner/indices/진행/ovr.md"}}\n' "$SEAT" > "$SEATS"; chmod 644 "$SEATS"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$NW" > "$T/pane-cwds"; printf '%s' "$NW" > "$T/cwd"
  : > "$T/tlog"; rm -rf "$T/wtclean" "$REPO/design/v65" "$REPO/design/teams"
  mkdir -p "$(dirname "$OLDL")"; : > "$OLDL"
  git -C "$REPO" update-ref refs/remotes/origin/main "$MAIN"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
}
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="${SEATS_OVR:-$SEATS}" FT_NANO_LEDGER_WT="$REPO" \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 --wt "$NW" --branch "$BR"; }
rejected() {  # rejected <출력> <rc> <이름> — CLOSED 0 · kill 0 · 명부 좌석 그대로
  [ "$2" -eq 1 ] && ok "$3 → rc 1" || bad "$3 — rc=$2 ← ${1:0:400}"
  hasnt "$1" "CLOSED" "  └ «CLOSED» 0"
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 해제 0" || bad "  └ tmux 변경: $(cat "$T/tlog")"
  jq -e --arg s "$SEAT" 'has($s)' "$SEATS" >/dev/null && ok "  └ 명부 좌석 그대로" || bad "  └ 명부에서 좌석 사라짐"
}

echo "== ⓐ 명단 = origin/main(작업 트리 사본은 옛 명단) · 원장 = 쌍둥이(design/v65) 1곳에만 → CLOSED"
setup; out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "ⓐ CLOSED(rc=0)" || bad "ⓐ rc=$rc ← ${out:0:600}"
has "$out" "INFO 원장 ← $OLDL (명단 origin/main)" "  └ INFO 원장 ← <쌍둥이 경로> (명단 origin/main)"
[ "$(grep -c "\`$SEAT\` 닫힘(ft-nano-close)" "$OLDL")" = 1 ] && ok "  └ 원장에 닫힘 행 1" || bad "  └ 원장 닫힘 행 $(grep -c 닫힘 "$OLDL")"

echo "== ⓑ 두 쌍둥이 모두 원장 → REJECT 후보 2개"
setup; mkdir -p "$(dirname "$NEWL")"; : > "$NEWL"; out="$(close)"; rc=$?
rejected "$out" "$rc" "ⓑ"; has "$out" "REJECT v65 원장 후보 2개: $NEWL · $OLDL" "  └ 사유(명단 꼴 먼저 · 쌍둥이 뒤)"

echo "== ⓒ 어느 쪽에도 원장 없음 → REJECT 못 찾았다(후보 목록)"
setup; rm -f "$OLDL"; out="$(close)"; rc=$?
rejected "$out" "$rc" "ⓒ"; has "$out" "REJECT v65 원장을 못 찾았다 — 후보: $NEWL $OLDL" "  └ 사유 + 후보 2"

echo "== ⓓ origin/main ref 없음 → REJECT 명단 못 읽음(작업 트리 사본으로 후퇴 0)"
setup; git -C "$REPO" update-ref -d refs/remotes/origin/main; out="$(close)"; rc=$?
rejected "$out" "$rc" "ⓓ"; has "$out" "REJECT 팀 명단(origin/main)을 못 읽음" "  └ 사유"

echo "== ⓔ 명부 파일 없음 → REJECT 명부 없음(입구 · 원장 쓰기 0)"
setup; out="$(SEATS_OVR="$T/no-such-seats.json" close)"; rc=$?
rejected "$out" "$rc" "ⓔ"; has "$out" "REJECT 명부 없음: $T/no-such-seats.json" "  └ 사유"
[ ! -s "$OLDL" ] && ok "  └ 원장 행 0" || bad "  └ 원장에 행이 생김"

echo "== ⓕ 명부 쓰기 실패(chmod 444) → REJECT 명부 쓰기 실패 · 원장 행 0"
setup; chmod 444 "$SEATS"; out="$(close)"; rc=$?
rejected "$out" "$rc" "ⓕ"; has "$out" "명부 쓰기 실패(rc=" "  └ 사유"
[ ! -s "$OLDL" ] && ok "  └ 원장 행 0" || bad "  └ 원장에 행이 생김"
chmod 644 "$SEATS"

echo "== ⓖ r448: 닫기 출력 reap 줄 · reap left≠0 → CLOSE-FAIL rc 1 · kill 0(reap 은 kill «앞» · --wt 좌석 워크트리 전달)"
setup; out="$(close)"; has "$out" "reap left=0 rc=0" "ⓖ 성공 출력에 reap left=0 rc=0"
setup; printf '#!/bin/sh\necho "$*" > "%s/reap-args"\necho "reap $1 stopped=0 left=1 rc=1"; exit 1\n' "$T" > "$T/bin/ft-seat-reap.sh"; out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "CLOSE-FAIL reap left=1 rc=1" "ⓖ CLOSE-FAIL reap left=1 rc=1 (rc 1)" || bad "ⓖ rc=$rc ← ${out:0:600}"
hasnt "$(cat "$T/tlog")" "kill-session" "  └ kill-session 0"
has "$(cat "$T/reap-args")" "$SEAT --wt $NW" "  └ reap 인자 = 좌석 + --wt 좌석 워크트리"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
