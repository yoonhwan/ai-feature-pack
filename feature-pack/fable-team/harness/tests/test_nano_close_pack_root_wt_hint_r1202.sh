#!/usr/bin/env bash
# test_nano_close_pack_root_wt_hint_r1202.sh — 카드 r1202: ft-nano-close.sh ⓐ 거절 줄이 --wt <팩 루트·팩 안 경로> 에 «맞는 --wt» 와 «--suspended» 를 안내한다(판정 그대로 · 문구만)
# 반례 R1~R5(카드 동결) + 변이 1(안내 호출 삭제 → R1 꼬리 0). 픽스처 = test_nano_close_pack_wt.sh 꼴(임시 BYZ 꼴 R · 팩 꼴 P · 가짜 tmux·cherry) — 실 리포·좌석·tmux 0 · 외부 호출 0.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행(RSG_ACTIVE 재진입 표지)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:600}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

bash -n "$SRC/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

mkdir -p "$T/bin" "$T/fake"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-hil.sh" "$SRC/ft-team-lib.sh" "$SRC/ft_teamset.py" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
printf '#!/bin/sh\necho "QUIESCED $1 stub left=0"\n' > "$T/bin/ft-seat-quiesce.sh"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/bin/sh\necho "OK cherry stub"\n' > "$T/bin/ft-nano-cherry-gate.sh"
cat > "$T/fake/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-panes)
    case "$*" in
      *pane_current_path*) cat "$FAKE_PANE_CWDS";;
      *) cat "$FAKE_PANES";;
    esac;;
  display-message) cat "$FAKE_CWD";;
  has-session) exit 1;;
  set-option|kill-session) echo "$*" >> "$FAKE_LOG";;
esac
EOF
chmod +x "$T/bin/"* "$T/fake/"*

GC() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
R="$T/repo"; mkdir -p "$R"; git -C "$R" init -q -b main; GC "$R" commit -q --allow-empty -m init
git init -q --bare "$T/R-origin.git"; git -C "$R" remote add origin "$T/R-origin.git"; git -C "$R" push -q origin HEAD:main; git -C "$R" fetch -q origin
GC "$R" worktree add -q "$R/.worktrees/harness-k" -b nano/k
RW="$R/.worktrees/harness-k"
git init -q --bare -b main "$T/P-origin.git"
P="$T/pack"; mkdir -p "$P/design"; git -C "$P" init -q -b main; GC "$P" commit -q --allow-empty -m pinit
git -C "$P" remote add origin "$T/P-origin.git"; git -C "$P" push -q origin main; git -C "$P" fetch -q origin
GC "$P" worktree add -q "$P/.worktrees/k" -b nano/k origin/main
PW="$P/.worktrees/k"; echo kit > "$PW/kit.sh"; GC "$PW" add kit.sh; GC "$PW" commit -q -m work
SHA="$(git -C "$PW" rev-parse HEAD)"
mkdir -p "$T/elsewhere" "$R/.fable-team" "$R/design/harness/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-harness-nano-k#0'; CARD="$R/design/harness/indices/진행/k.md"

run() { ( cd "$R" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {
  printf '{"%s":{"role":"nano","index":"design/harness/indices/진행/k.md"}}\n' "$SEAT" > "$R/.fable-team/seats-harness.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$RW" > "$T/pane-cwds"; printf '%s' "$RW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ledger.md"; rm -rf "$T/wtclean"
  printf '# 인덱스: k\n<!-- ledger: design/harness/GOAL-harness.md -->\n- 설치: 있음 — 팩 키트 1\n\n## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "$SHA" > "$CARD"
}
close() { local bin="$1"; shift; run FT_NANO_PREFIX=byz-harness-nano- FT_NANO_WT_PREFIX=harness- FT_NANO_FEAT=origin/main FT_PACK_ROOT="$P" \
  FT_SEATS_JSON="$R/.fable-team/seats-harness.json" FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" \
  bash "$bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 "$@"; }
aline() { printf '%s\n' "$1" | grep -F 'ⓐ--wt(' | head -1; }
SUSP_TAIL=' · 착지 전 휴식 닫기 = --suspended "<사유>"(브랜치·PR 보존)'
OLD_HEAD="가 이 리포($R)에 등록된 .worktrees/ 아래 워크트리가 아니다 · 팩 경로는 하네스 카드(첫 5줄 원장 줄 GOAL-harness)만"

echo "== R1 --wt <팩 루트> --branch nano/k · 등록 워크트리 PW 있음 → REJECT 꼬리에 맞는 --wt + --suspended"
setup; out="$(close "$T/bin" --wt "$P" --branch nano/k)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "REJECT $SEAT" "R1 REJECT 그대로(rc=1)" || bad "R1 rc=$rc ← ${out:0:600}"
has "$(aline "$out")" "ⓐ--wt($P)$OLD_HEAD · 팩 나노는 --wt $PW --branch nano/k$SUSP_TAIL" "R1 ⓐ 줄 = 옛 머리 + 등록 워크트리 안내 + --suspended"
hasnt "$out" "worktree move $P " "  └ 팩 루트를 옮기라는 틀린 안내 0(_pack_move_hint 루트 제외)"
[ -z "$(cat "$T/tlog")" ] && ok "  └ kill 0" || bad "  └ kill 발생: $(cat "$T/tlog")"

echo "== R2 --wt <팩 루트>/design(팩 안 다른 경로) → R1 과 같은 안내"
setup; out="$(close "$T/bin" --wt "$P/design" --branch nano/k)"; rc=$?
[ "$rc" -eq 1 ] || bad "R2 rc=$rc"
has "$(aline "$out")" "ⓐ--wt($P/design)$OLD_HEAD · 팩 나노는 --wt $PW --branch nano/k$SUSP_TAIL" "R2 팩 안 경로 → 같은 안내"

echo "== R3 --wt <팩 루트> · 그 가지 등록 워크트리 0 → «.worktrees/<이름>(이 가지 등록 워크트리 0)»"
setup; out="$(close "$T/bin" --wt "$P" --branch nano/none)"; rc=$?
[ "$rc" -eq 1 ] || bad "R3 rc=$rc"
has "$(aline "$out")" "ⓐ--wt($P)$OLD_HEAD · 팩 나노는 --wt $P/.worktrees/none(이 가지 등록 워크트리 0)$SUSP_TAIL" "R3 등록 0 안내"

echo "== R4 --wt <BYZ 밖 · 팩 밖> → 안내 0(문구 3 만 바뀐 옛 줄)"
setup; out="$(close "$T/bin" --wt "$T/elsewhere" --branch nano/k)"; rc=$?
[ "$rc" -eq 1 ] || bad "R4 rc=$rc"
[ "$(aline "$out")" = "  - ⓐ--wt($T/elsewhere)$OLD_HEAD" ] || [ "$(aline "$out" | sed 's/^[[:space:]-]*//')" = "ⓐ--wt($T/elsewhere)$OLD_HEAD" ] \
  && ok "R4 ⓐ 줄 = 옛 줄(문구 3 만)" || bad "R4 ⓐ 줄: $(aline "$out")"
hasnt "$out" "팩 나노는" "  └ 팩 안내 0"; hasnt "$out" "착지 전 휴식 닫기" "  └ --suspended 안내 0"

echo "== R5 --wt <팩 등록 워크트리> + 하네스 카드 → ⓐ 통과 · CLOSED(r508 그대로)"
setup; out="$(close "$T/bin" --wt "$PW" --branch nano/k)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "R5 CLOSED(rc=0)" || bad "R5 rc=$rc ← ${out:0:600}"
hasnt "$out" "ⓐ--wt(" "  └ ⓐ 거절 0"; hasnt "$out" "팩 나노는" "  └ 안내 0"

echo "== 변이: 안내 호출 삭제(r1202-mut:hint) → R1 꼬리 0 이어야 한다(시험이 잡음)"
mkdir -p "$T/mut"; find "$T/bin" -maxdepth 1 -type f -exec cp -p {} "$T/mut/" \;
sed -i.bak '/r1202-mut:hint/s/\$(_pack_wt_hint "\$_nw" "\$NBR")//' "$T/mut/ft-nano-close.sh"
cmp -s "$T/bin/ft-nano-close.sh" "$T/mut/ft-nano-close.sh" && bad "변이 적용 실패(파일 같음)" || ok "변이 적용"
setup; out="$(close "$T/mut" --wt "$P" --branch nano/k)"
case "$(aline "$out")" in *"팩 나노는 --wt $PW"*) bad "변이 생존 — 안내가 여전히 찍힘";; *) ok "변이 FAIL 확인 — R1 안내 꼬리 0(시험이 이 차이를 잡는다)";; esac

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
