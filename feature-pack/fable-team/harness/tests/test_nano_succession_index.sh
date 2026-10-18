#!/usr/bin/env bash
# test_nano_succession_index.sh — R370: 나노 승계(ft-seat-retire.sh)가 후계 행에 카드 경로 index 를 잇고,
#   ft-nano-close.sh ⑥ 은 index 가 비면 _replaces 사슬로 구 행의 index 로 후퇴한다(끝까지 없으면 기존 REJECT · 순환 차단).
# 임시 git 리포 + 가짜 tmux(PATH 앞) + 가짜 cherry 게이트만 쓴다 — 실제 명부·tmux·재개 기록 0.
set -uo pipefail
export FT_ALLOW_TRACKED_BIN=1
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../scripts/harness-install/fable-team/bin"
RETIRE="$HERE/../../scripts/fable-team-bin/ft-seat-retire.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export ZC_RESUME_DIR="$T/resume"   # 재개 기록은 임시 폴더로(실 ~/.claude 0)
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }
J() { jq -r "$2" "$1"; }

bash -n "$RETIRE" && ok "bash -n ft-seat-retire.sh" || bad "bash -n ft-seat-retire.sh"
bash -n "$SRC/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

echo "== ⓐ retire: 후계 행 생성 → index 상속 · 구 행 index 보존 · 다른 키 그대로"
S="$T/seats-a.json"; IDXA='design/harness/indices/진행/card-a.md'
printf '{"O#0":{"role":"nano","agent":"claude","model":"m1","tick":null,"index":"%s"}}\n' "$IDXA" > "$S"
bash "$RETIRE" 'O#0' 'O#1' --seats "$S" >/dev/null; rc=$?
chk "ⓐ rc" "$rc" 0
chk "ⓐ 후계 index = 카드 A" "$(J "$S" '.["O#1"].index')" "$IDXA"
chk "ⓐ 구 행 index 보존" "$(J "$S" '.["O#0"].index')" "$IDXA"
chk "ⓐ 후계 다른 키(role·agent·model·_replaces)" "$(J "$S" '.["O#1"]|[.role,.agent,.model,(._replaces|join("+"))]|join(",")')" "nano,claude,m1,O#0"
chk "ⓐ 구 행 은퇴 키(_replaced_by·role)" "$(J "$S" '.["O#0"]|[._replaced_by,.role]|join(",")')" "O#1,stop-ready"
S="$T/seats-a2.json"
printf '{"O#0":{"role":"nano","agent":"claude","model":"m1","tick":null}}\n' > "$S"
bash "$RETIRE" 'O#0' 'O#1' --seats "$S" >/dev/null
chk "ⓐ 구 행 index 없음 → 후계에 index 키 안 만든다" "$(J "$S" '.["O#1"]|has("index")')" false

echo "== ⓑ retire: 후계 행이 이미 있으면 index 덮어쓰기 0"
S="$T/seats-b.json"
printf '{"O#0":{"role":"nano","agent":"claude","model":"m1","tick":null,"index":"%s"},"O#1":{"role":"nano","index":"design/other.md"}}\n' "$IDXA" > "$S"
bash "$RETIRE" 'O#0' 'O#1' --seats "$S" >/dev/null
chk "ⓑ 후계 기존 index 유지" "$(J "$S" '.["O#1"].index')" "design/other.md"
S="$T/seats-b2.json"
printf '{"O#0":{"role":"nano","agent":"claude","model":"m1","tick":null,"index":"%s"},"O#1":{"role":"nano"}}\n' "$IDXA" > "$S"
bash "$RETIRE" 'O#0' 'O#1' --seats "$S" >/dev/null
chk "ⓑ 후계 행 있고 index 없음 → 복사" "$(J "$S" '.["O#1"].index')" "$IDXA"

# ── nano-close 하네스(test_nano_close_named_wt.sh 와 같은 틀) ──
mkdir -p "$T/bin" "$T/fake"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-wt-sweep.sh" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
cp "$SRC/ft-hil.sh" "$T/bin/"
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

REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q -b main && git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
mkdir -p "$REPO/.fable-team" "$REPO/design/planner/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"; : > "$T/ledger.md"
BASE='byz-planner-nano-ovr'; CARD_REL='design/planner/indices/진행/ovr.md'; CARD="$REPO/$CARD_REL"
NW="$REPO/.worktrees/cfo-ovr"; BR="fix/ovr-verdict"
GIT worktree add -q "$NW" -b "$BR"
git -C "$NW" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "work"
SHA="$(git -C "$NW" rev-parse HEAD)"
SF="$REPO/.fable-team/seats-planner.json"

run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
prep() {  # prep <닫을 좌석 번호> <명부 json 본문> — 명부·pane·카드·가짜 tmux 상태를 «정상» 으로 리셋
  SEAT="$BASE#$1"
  printf '%s\n' "$2" > "$SF"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$NW" > "$T/pane-cwds"; printf '%s' "$NW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ledger.md"; rm -rf "$T/wtclean" "$T/hil"
  printf '## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
}
close() { run FT_NANO_PREFIX=byz-planner-nano- FT_SEATS_JSON="$SF" FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 \
  FT_WT_CLEAN_DIR="$T/wtclean" timeout 60 bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 --wt "$NW" --branch "$BR"; }

echo "== ⓒ nano-close: 후계 index 없음 + _replaces=[구] + 구 행 index → 카드로 ⑥ 진행"
prep 1 "{\"$BASE#0\":{\"role\":\"stop-ready\",\"index\":\"$CARD_REL\",\"_replaced_by\":\"$BASE#1\"},\"$BASE#1\":{\"role\":\"nano\",\"_replaces\":[\"$BASE#0\"]}}"
out="$(close)"; rc=$?
chk "ⓒ rc" "$rc" 0
hasnt "$out" "카드 못 찾음" "ⓒ «카드 못 찾음» 0"
has "$out" "INFO index 상속 ← $BASE#0" "ⓒ 출처 1줄"
has "$out" "CLOSED $SEAT" "ⓒ 닫힘"

echo "== ⓓ 사슬 2단(#0→#1→#2 · #2 만 index 없음 · #1 도 없음)"
prep 2 "{\"$BASE#0\":{\"role\":\"stop-ready\",\"index\":\"$CARD_REL\",\"_replaced_by\":\"$BASE#1\"},\"$BASE#1\":{\"role\":\"stop-ready\",\"_replaces\":[\"$BASE#0\"],\"_replaced_by\":\"$BASE#2\"},\"$BASE#2\":{\"role\":\"nano\",\"_replaces\":[\"$BASE#1\"]}}"
out="$(close)"; rc=$?
chk "ⓓ rc" "$rc" 0
hasnt "$out" "카드 못 찾음" "ⓓ «카드 못 찾음» 0"
has "$out" "INFO index 상속 ← $BASE#0" "ⓓ 맨 위 구 행에서 상속"

echo "== ⓔ 사슬 끝까지 index 없음 → 지금과 같은 REJECT"
prep 1 "{\"$BASE#0\":{\"role\":\"stop-ready\",\"_replaced_by\":\"$BASE#1\"},\"$BASE#1\":{\"role\":\"nano\",\"_replaces\":[\"$BASE#0\"]}}"
out="$(close)"; rc=$?
chk "ⓔ rc" "$rc" 1
has "$out" "⑥카드 못 찾음: seats.json index=<빈 값>" "ⓔ 기존 REJECT 문구 그대로"
chk "ⓔ kill 0" "$(cat "$T/tlog")" ""
jq -e --arg s "$SEAT" 'has($s)' "$SF" >/dev/null && ok "ⓔ 명부 그대로" || bad "ⓔ 명부 삭제됨"

echo "== ⓕ 사슬 순환(_replaces 가 서로 가리킴) → 무한 루프 0 · REJECT"
prep 1 "{\"$BASE#1\":{\"role\":\"nano\",\"_replaces\":[\"$BASE#2\"]},\"$BASE#2\":{\"role\":\"stop-ready\",\"_replaces\":[\"$BASE#1\"]}}"
out="$(close)"; rc=$?
chk "ⓕ rc (timeout 124 아님)" "$rc" 1
has "$out" "⑥카드 못 찾음" "ⓕ REJECT"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
