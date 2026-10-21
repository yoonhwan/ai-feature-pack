#!/usr/bin/env bash
# test_nano_close_rerun_early.sh — 카드 r520: reap CLOSE-FAIL 뒤 «같은 close 재실행» 이 카드 찾기 «앞»에서 RERUN 으로 판별돼 남은 정리만 하는가 + reap 1회 재시도
# 픽스처 = test_nano_close_pack_wt.sh 꼴(임시 BYZ 꼴 리포 R · 팩 꼴 리포 P + bare 원격 · 가짜 tmux · 가짜 cherry 게이트) + 가짜 reap(모드 파일 · 호출 횟수 기록)
# 실제 리포·seats·tmux 세션·외부 호출 0 · GIT_* env 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:700}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

bash -n "$SRC/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

mkdir -p "$T/bin" "$T/fake"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-hil.sh" "$T/bin/"
cp "$SRC/ft_teamset.py" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
# 가짜 reap — 모드 파일: ok = left=0 · always1 = 늘 left=1 · once1 = 1회째 left=1 뒤 left=0. 호출마다 $T/reap.calls 에 1줄.
cat > "$T/bin/ft-seat-reap.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$T/reap.calls"; n="\$(grep -c . "$T/reap.calls")"
case "\$(cat "$T/reap.mode")" in
  ok) echo "reap \$1 stopped=0 left=0 rc=0"; exit 0;;
  always1) echo "reap \$1 stopped=0 left=1 rc=1"; exit 1;;
  once1) if [ "\$n" -le 1 ]; then echo "reap \$1 stopped=0 left=1 rc=1"; exit 1; else echo "reap \$1 stopped=1 left=0 rc=0"; exit 0; fi;;
esac
EOF
cat > "$T/bin/ft-nano-cherry-gate.sh" <<'EOF'
#!/usr/bin/env bash
echo "OK cherry stub"; exit 0
EOF
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

GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
R="$T/repo"; mkdir -p "$R"; git -C "$R" init -q -b main; GC "$R" commit -q --allow-empty -m init
GC "$R" worktree add -q "$R/.worktrees/harness-k" -b nano/k
RW="$R/.worktrees/harness-k"
git init -q --bare -b main "$T/P-origin.git"
P="$T/pack"; mkdir -p "$P"; git -C "$P" init -q -b main; GC "$P" commit -q --allow-empty -m pinit
git -C "$P" remote add origin "$T/P-origin.git"; git -C "$P" push -q origin main; git -C "$P" fetch -q origin
GC "$P" worktree add -q "$P/.worktrees/k" -b nano/k origin/main
PW="$P/.worktrees/k"; echo kit > "$PW/kit.sh"; GC "$PW" add kit.sh; GC "$PW" commit -q -m work
SHA="$(git -C "$PW" rev-parse HEAD)"

mkdir -p "$R/.fable-team" "$R/design/harness/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-harness-nano-k#0'; CARD="$R/design/harness/indices/진행/k.md"
SEATS="$R/.fable-team/seats-harness.json"

run() { ( cd "$R" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {  # setup <reap 모드> — 명부·pane·카드·원장을 «처음 닫기 전» 으로 리셋
  printf '{"%s":{"role":"nano","index":"design/harness/indices/진행/k.md"}}\n' "$SEAT" > "$SEATS"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$RW" > "$T/pane-cwds"; printf '%s' "$RW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ledger.md"; : > "$T/reap.calls"; rm -rf "$T/wtclean"; echo "$1" > "$T/reap.mode"
  printf '# 인덱스: k\n<!-- ledger: design/harness/GOAL-harness.md -->\n- 설치: 있음 — 팩 키트 1\n\n## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
}
close() { run FT_NANO_PREFIX=byz-harness-nano- FT_NANO_WT_PREFIX=harness- FT_NANO_FEAT=origin/main FT_PACK_ROOT="$P" FT_REAP_RETRY_SLEEP=0 \
  FT_SEATS_JSON="$SEATS" FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" \
  bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 --wt "$PW" --branch nano/k "$@"; }
rows() { grep -cF "\`$SEAT\` 닫힘(ft-nano-close)" "$T/ledger.md"; }
calls() { grep -c . "$T/reap.calls"; }

echo "== ⓐ 1차 reap 늘 left=1 → CLOSE-FAIL · 2차 같은 명령(reap left=0) → «재실행» + 카드 검사 건너뜀 + CLOSED · 원장 행 1개 그대로"
setup always1; out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "CLOSE-FAIL reap left=1" "ⓐ 1차 → CLOSE-FAIL(rc=1)" || bad "ⓐ 1차 rc=$rc ← ${out:0:900}"
jq -e --arg s "$SEAT" 'has($s)' "$SEATS" >/dev/null; [ "$?" -eq 1 ] && ok "  └ 1차 뒤 명부 행 없음(실사건 꼴)" || bad "  └ 1차 뒤 명부 행이 남음"
[ "$(rows)" = 1 ] && ok "  └ 1차 뒤 원장 닫힘 행 1" || bad "  └ 1차 뒤 원장 행 $(rows)"
hasnt "$(cat "$T/tlog")" "kill-session" "  └ 1차 세션 보존"
echo ok > "$T/reap.mode"; : > "$T/reap.calls"
out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "ⓐ 2차(재실행) → CLOSED(rc=0)" || bad "ⓐ 2차 rc=$rc ← ${out:0:900}"
has "$out" "재실행 — 명부에 없고 원장 닫힘 행 있음" "  └ 조기 재실행 판별 출력"
hasnt "$out" "카드 못 찾음" "  └ 카드 검사 건너뜀"
hasnt "$out" "REJECT" "  └ REJECT 0"
[ "$(rows)" = 1 ] && ok "  └ 원장 닫힘 행 1개 그대로(append 0)" || bad "  └ 원장 행 $(rows)"
[ "$(calls)" = 1 ] && has "$(cat "$T/reap.calls")" "--wt $PW" "  └ reap 1회 · --wt = 팩 워크트리" || bad "  └ reap 호출 $(calls) · $(cat "$T/reap.calls")"
has "$(cat "$T/tlog")" "set-option -t %1 -u @zc_v65_active" "  └ 태그 해제"
has "$(cat "$T/tlog")" "kill-session -t %1" "  └ 세션 kill"
[ -d "$PW" ] && git -C "$P" rev-parse --verify -q refs/heads/nano/k >/dev/null && ok "  └ 팩 워크트리·브랜치 그대로" || bad "  └ 워크트리/브랜치 사라짐"

echo "== ⓐ' 재실행인데 세션도 이미 없음 → reap 만 · CLOSED(세션 없음) · kill 0"
: > "$T/panes"; : > "$T/pane-cwds"; : > "$T/tlog"; : > "$T/reap.calls"
out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "ⓐ' 세션 없음 재실행 → CLOSED" || bad "ⓐ' rc=$rc ← ${out:0:900}"
[ -z "$(cat "$T/tlog")" ] && ok "  └ tmux 변경 0" || bad "  └ tmux 변경: $(cat "$T/tlog")"
[ "$(rows)" = 1 ] && ok "  └ 원장 행 1개 그대로" || bad "  └ 원장 행 $(rows)"

echo "== ⓑ reap 1회째 left=1 · 2회째 left=0 → 1차에서 바로 CLOSED(재시도 1회)"
setup once1; out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "ⓑ 재시도로 CLOSED" || bad "ⓑ rc=$rc ← ${out:0:900}"
has "$out" "reap 재시도 1" "  └ «reap 재시도 1» 출력"
[ "$(calls)" = 2 ] && ok "  └ reap 2회" || bad "  └ reap 호출 $(calls)"
has "$(cat "$T/tlog")" "kill-session" "  └ 세션 kill"
[ "$(rows)" = 1 ] && ok "  └ 원장 행 1" || bad "  └ 원장 행 $(rows)"

echo "== ⓒ reap 늘 left=1 → 재시도 1회 뒤 CLOSE-FAIL(무한 재시도 0)"
setup always1; out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "CLOSE-FAIL reap left=1" "ⓒ CLOSE-FAIL" || bad "ⓒ rc=$rc ← ${out:0:900}"
[ "$(calls)" = 2 ] && ok "  └ reap 정확히 2회" || bad "  └ reap 호출 $(calls)"
has "$out" "reap 재시도 1" "  └ 재시도 출력"
hasnt "$(cat "$T/tlog")" "kill-session" "  └ 세션 보존"

echo "== ⓓ 명부 행 없음 ∧ 원장 닫힘 행 없음 → 조기 재실행 0 · REJECT(처음 보는 좌석을 검사 없이 닫지 않음)"
setup ok; printf '{}\n' > "$SEATS"; out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "REJECT $SEAT" "ⓓ REJECT" || bad "ⓓ rc=$rc ← ${out:0:900}"
hasnt "$out" "재실행" "  └ 재실행 판별 0"
[ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 0" || bad "  └ tmux 변경: $(cat "$T/tlog")"
[ "$(calls)" = 0 ] && ok "  └ reap 0" || bad "  └ reap 호출 $(calls)"
[ "$(rows)" = 0 ] && ok "  └ 원장 행 0" || bad "  └ 원장 행 $(rows)"

echo "== ⓔ 명부 행 있음 = 지금 경로 그대로(카드·증거 검사 · reap 1회 · append 1)"
setup ok; out="$(close)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "ⓔ CLOSED" || bad "ⓔ rc=$rc ← ${out:0:900}"
has "$out" "OK 증거 줄" "  └ ⑥ 증거 검사 거침"
hasnt "$out" "재실행" "  └ 재실행 판별 0"
hasnt "$out" "reap 재시도" "  └ 재시도 0"
[ "$(calls)" = 1 ] && ok "  └ reap 1회" || bad "  └ reap 호출 $(calls)"
[ "$(rows)" = 1 ] && ok "  └ 원장 append 1" || bad "  └ 원장 행 $(rows)"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
