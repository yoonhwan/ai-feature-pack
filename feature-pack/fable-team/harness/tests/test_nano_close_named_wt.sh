#!/usr/bin/env bash
# test_nano_close_named_wt.sh — 카드 nano-close-named-wt: ft-nano-close.sh --wt <경로> --branch <이름> (표준이 아닌 이름의 전용 워크트리 좌석 닫기 · 원장 R8 보강)
# 임시 git 리포 + 가짜 tmux(PATH 앞) + 스크립트 사본(가짜 cherry 게이트)만 쓴다 — 실제 리포·seats·tmux 세션은 건드리지 않는다.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

bash -n "$SRC/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

mkdir -p "$T/bin" "$T/fake"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-wt-sweep.sh" "$T/bin/"   # r166: 계획의 분리 정리(--finish)가 옆의 ft-wt-sweep.sh 를 쓴다
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"   # 사건 원장 훅(PLAN-status-sheet §3-1) 의존 — 설치 폴더 밖 시험이라 FT_SHEET_ROOT 로 임시 루트
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"

# 가짜 cherry 게이트 — 받은 인자를 기록하고 통과(실제 게이트는 test_nano_cherry_gate* 가 따로 시험한다)
printf '#!/usr/bin/env bash\necho "$1 $2" > "%s/cherry.args"\necho "OK cherry stub"; exit 0\n' "$T" > "$T/bin/ft-nano-cherry-gate.sh"
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

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"; : > "$T/ledger.md"

SEAT='byz-planner-nano-ovr#0'; CARD="$REPO/design/planner/indices/진행/ovr.md"
NW="$REPO/.worktrees/cfo-ovr"; BR="fix/ovr-verdict"
GIT worktree add -q "$NW" -b "$BR"
git -C "$NW" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "work"
SHA="$(git -C "$NW" rev-parse HEAD)"

cp "$SRC/ft-hil.sh" "$T/bin/"  # R83: 같은 bin 의 ft-hil.sh 를 부른다 — HIL_DIR 임시 폴더 · HIL_CLIP=0(실 /tmp·실 클립보드 0)
run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="${HIL_DIR_T:-$T/hil}" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {  # setup — 명부·pane·카드·가짜 tmux 상태를 «정상» 으로 리셋(각 케이스가 한 칸만 비튼다)
  printf '{"%s":{"role":"nano","index":"design/planner/indices/진행/ovr.md"}}\n' "$SEAT" > "$REPO/.fable-team/seats-planner.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$NW" > "$T/pane-cwds"; printf '%s' "$NW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ledger.md"; rm -rf "$T/wtclean" "$T/cherry.args"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
}
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$REPO/.fable-team/seats-planner.json" FT_NANO_LEDGER="$T/ledger.md" \
  FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 "$@"; }
reject() {  # reject <사유 조각> <이름> <close 인자...>
  local frag="$1" name="$2"; shift 2
  setup; out="$(close "$@")"; rc=$?
  [ "$rc" -eq 1 ] && has "$out" "REJECT" "$name → REJECT" || bad "$name — rc=$rc ← ${out:0:300}"
  has "$out" "$frag" "  └ 사유 «${frag}»"
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 해제 0" || bad "REJECT 인데 tmux 변경: $(cat "$T/tlog")"
  jq -e --arg s "$SEAT" 'has($s)' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 그대로" || bad "REJECT 인데 명부 삭제"
}

echo "== usage (exit 2)"
setup; out="$(close --wt "$NW")"; rc=$?;                         [ "$rc" -eq 2 ] && ok "--wt 만 → exit 2" || bad "--wt 만 rc=$rc ← ${out:0:200}"
setup; out="$(close --branch "$BR")"; rc=$?;                     [ "$rc" -eq 2 ] && ok "--branch 만 → exit 2" || bad "--branch 만 rc=$rc"
setup; out="$(close --shared-wt --wt "$NW" --branch "$BR")"; rc=$?; [ "$rc" -eq 2 ] && ok "--shared-wt 와 같이 → exit 2" || bad "--shared-wt 동시 rc=$rc"
setup; out="$(close --wt "" --branch "$BR")"; rc=$?;             [ "$rc" -eq 2 ] && ok "--wt 빈 값 → exit 2" || bad "--wt 빈 값 rc=$rc"
setup; out="$(close --wt)"; rc=$?;                               [ "$rc" -eq 2 ] && ok "--wt 값 누락 → exit 2" || bad "--wt 값 누락 rc=$rc"

echo "== REJECT 5종 (ⓐ~ⓔ)"
mkdir -p "$REPO/.worktrees/plain-dir"
reject "ⓐ" "ⓐ 등록 안 된 경로" --wt "$REPO/.worktrees/plain-dir" --branch "$BR"
reject "ⓐ" "ⓐ .worktrees/ 밖 경로" --wt "$T" --branch "$BR"
reject "ⓑ" "ⓑ 브랜치 불일치" --wt "$NW" --branch "fix/other"
reject "ⓑ" "ⓑ 정본 줄기(main) 브랜치" --wt "$NW" --branch "main"
setup; printf '%s' "$REPO" > "$T/cwd"
out="$(close --wt "$NW" --branch "$BR")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "ⓒpane cwd" "ⓒ pane cwd toplevel 불일치 → REJECT" || bad "ⓒ rc=$rc ← ${out:0:300}"
setup; printf '%s|%s\n%s|%s/sub\n' "$SEAT" "$NW" 'other#0' "$NW" > "$T/pane-cwds"
out="$(close --wt "$NW" --branch "$BR")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "--shared-wt 로 닫아라" "ⓓ 다른 pane 이 같은 워크트리 → REJECT(공유)" || bad "ⓓ rc=$rc ← ${out:0:300}"
has "$out" "other#0" "  └ 사유에 그 pane 이름"
echo dirty > "$NW/dirty.txt"
reject "ⓔ" "ⓔ 미커밋 있음" --wt "$NW" --branch "$BR"
rm -f "$NW/dirty.txt"
echo "== 인자 없이 같은 좌석 → 지금처럼 REJECT(무변화)"
setup; out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "추측 금지" "인자 없음 → 기존 fail-closed REJECT" || bad "인자 없음 rc=$rc ← ${out:0:300}"
[ -z "$(cat "$T/tlog")" ] && ok "  └ kill 0" || bad "인자 없음인데 tmux 변경"

echo "== 전부 맞음 → 통과"
setup; out="$(close --wt "$NW" --branch "$BR")"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "전부 맞음 → CLOSED(rc=0)" || bad "통과 rc=$rc ← ${out:0:500}"
has "$out" "OK 증거 줄" "  └ ⓕ 증거 줄(--repo = --wt · 현재 HEAD) 통과"
[ "$(cat "$T/cherry.args" 2>/dev/null)" = "feat/v6-realtime-live $BR" ] && ok "  └ ⓖ cherry 게이트가 --branch 기준으로 호출됨" || bad "cherry 인자: $(cat "$T/cherry.args" 2>/dev/null)"
has "$(cat "$T/tlog")" "kill-session" "  └ 세션 kill(표준승인 경로)"
has "$(cat "$T/ledger.md")" "mode=named-wt wt=$NW branch=$BR" "  └ 원장 행 mode=named-wt wt=<경로> branch=<이름>"
jq -e --arg s "$SEAT" 'has($s) | not' "$REPO/.fable-team/seats-planner.json" >/dev/null && ok "  └ 명부 삭제" || bad "명부에 좌석 남음"
PLAN="$T/wtclean/$SEAT.sh.hil"
[ -f "$PLAN" ] && ok "  └ wt-clean 계획 생성(.sh.hil — sweep 순회 밖)" || bad "계획 파일 없음: $(ls "$T/wtclean" 2>&1)"
[ ! -e "$T/wtclean/$SEAT.sh" ] && ok "  └ .sh 없음 → ft-wt-sweep 이 자동 실행하지 않는다" || bad ".sh 계획이 있음(sweep 이 집행)"
has "$out" "사람 ! 실행" "  └ 출력에 «자율 정리 범위 밖 — 사람 ! 실행»"
has "$out" "사람 ! 실행: ! bash $T/hil/h1" "  └ R83: 안내가 짧은 링크 ! bash <HIL_DIR>/h<N> (긴 계획 경로 아님)"
[ "$(sed -n 's/^# ft-hil-entry plan=//p' "$T/hil/h1")" = "$PLAN" ] && ok "  └ 진입 파일 대상 = 계획 .sh.hil (R186: 링크 → 진입 파일)" || bad "진입 파일 대상 불일치"
has "$out" "브랜치가 nano/* 가 아니라" "  └ 사유 문구(브랜치 nano/* 아님)"
[ -d "$NW" ] && [ -f "$NW/.git" ] && ok "  └ wt-clean 실행 0 — 워크트리 그대로" || bad "워크트리가 사라짐"
git -C "$REPO" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 브랜치 그대로" || bad "브랜치 삭제됨"
[ "$(git -C "$NW" rev-parse HEAD)" = "$SHA" ] && ok "  └ WIP 자동 커밋 0(HEAD 그대로)" || bad "HEAD 가 움직임"
bash -n "$PLAN" && has "$(cat "$PLAN")" "NAMED_BR=fix/ovr-verdict" "  └ 계획에 --branch 값이 구워짐" || bad "계획 문법/내용"
SWEEP="$(cd "$REPO" && FT_WT_CLEAN_DIR="$T/wtclean" bash "$SRC/ft-wt-sweep.sh" --dry-run 2>&1)"
hasnt "$SWEEP" "$SEAT" "  └ ft-wt-sweep --dry-run 순회에 안 잡힌다"

echo "== 사람이 계획을 실행 — nano/* 가 아닌 브랜치도 가드 ③ 을 통과하고 브랜치는 남는다"
printf '#!/usr/bin/env bash\ngit -C "%s" worktree remove --force "$2"\n' "$REPO" > "$T/fake/baton"; chmod +x "$T/fake/baton"
planout="$(cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" PATH="$T/fake:$PATH" BATON_BIN="$T/fake/baton" /bin/bash "$PLAN" 2>&1)"; prc=$?
[ "$prc" -eq 0 ] && has "$(printf '%s' "$planout" | tail -1)" "cleaned" "계획 실행 → cleaned" || bad "계획 실행 rc=$prc ← ${planout:0:400}"
[ ! -d "$NW" ] && ok "  └ 워크트리 정리됨" || bad "워크트리 남음"
git -C "$REPO" rev-parse --verify -q "refs/heads/$BR" >/dev/null && ok "  └ 계획 실행 뒤에도 브랜치 그대로" || bad "브랜치 삭제됨"
has "$(cat "$T/ledger.md")" "wt=cleaned" "  └ 원장 표식 wt=cleaned"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
