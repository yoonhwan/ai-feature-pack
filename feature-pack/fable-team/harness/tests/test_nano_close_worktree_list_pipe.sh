#!/usr/bin/env bash
# test_nano_close_worktree_list_pipe.sh — 카드 r453: `set -o pipefail` 아래 `git worktree list --porcelain | grep -qxF …` 는 목록이 64 KB 를 넘으면
#   grep 이 찾고 먼저 닫아 git 이 SIGPIPE(141) → 파이프 실패 → --plan-only 가 등록 워크트리를 «아니다» 로 REJECT(판정 2367 정리 막힘).
#   고침 = 목록을 변수로 받은 뒤 here-string 으로 grep. 픽스처 = 임시 리포 + 긴 이름 등록 워크트리 수백 개(porcelain > 64 KB) + 가짜 tmux(PATH 앞).
#   ⓐ 고치기 전 꼴 재현(rc 141 · RED 모양) ⓑ --plan-only 등록 경로 → PLANNED(목록 앞·뒤 둘 다) ⓒ 미등록 → 기존 REJECT ⓓ --shared-wt ⓑ 검사 등록/미등록.
#   실제 리포·seats·tmux 세션은 건드리지 않는다 · GIT_* env 0 · 외부 호출 0.
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

mkdir -p "$T/bin" "$T/fake" "$T/comm/bodies"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-landed-check.sh" "$SRC/ft-hil.sh" "$SRC/ft-team-lib.sh" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
printf '#!/usr/bin/env bash\necho "OK cherry stub"; exit 0\n' > "$T/bin/ft-nano-cherry-gate.sh"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
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
GIT() { git -C "$REPO" -c user.email=t@t -c user.name=t "$@"; }
git -C "$REPO" init -q -b main
printf '.worktrees/\n.fable-team/\n.worktree-info.json\n' > "$REPO/.gitignore"; GIT add .gitignore; GIT commit -qm init
mkdir -p "$REPO/.fable-team"; echo '{}' > "$REPO/.fable-team/seats.json"; : > "$T/ledger.md"; echo res > "$T/result.md"; echo seq > "$T/comm/bodies/1.txt"

# 착지(squash) 나노 2석 — 이름으로 목록 맨 앞(aaa)·맨 뒤(zzz) 에 놓인다
landed() {  # landed <키> — .worktrees/v65-<키> · nano/<키> · 같은 patch 를 main 에도(cherry «-»)
  local k="$1" w="$REPO/.worktrees/v65-$1"
  GIT worktree add -q -b "nano/$k" "$w" main
  printf '{"branch":"nano/%s"}\n' "$k" > "$w/.worktree-info.json"
  echo "$k" > "$w/$k.txt"; git -C "$w" -c user.email=t@t -c user.name=t add "$k.txt"; git -C "$w" -c user.email=t@t -c user.name=t commit -qm "$k work"
  echo "$k" > "$REPO/$k.txt"; GIT add "$k.txt"; GIT commit -qm "main lands $k"
}
landed aaa
GIT worktree add -q -b feat/shared "$REPO/.worktrees/aab-shared" main   # ⓓ 공유 좌석 워크트리(브랜치 nano/* 아님) — 목록 앞쪽
PAD="$(printf 'p%.0s' $(seq 1 200))"
for i in $(seq -w 1 450); do GIT worktree add -q --detach --no-checkout "$REPO/.worktrees/v65-m$PAD-$i" main 2>/dev/null; done   # 채움 — 이름순으로 v65-aaa 뒤 · v65-zzz 앞(키 aaa·zzz 와 안 맞음)
landed zzz

PORC="$(git -C "$REPO" worktree list --porcelain)"
[ "${#PORC}" -gt 65536 ] && ok "픽스처 porcelain ${#PORC} B > 64 KB" || bad "픽스처 porcelain ${#PORC} B ≤ 64 KB — 결함 모양을 못 만든다"
WL="$(sed -n 's/^worktree //p' <<<"$PORC")"   # 1행 = 메인 워크트리
[ "$(sed -n 3p <<<"$WL")" = "$REPO/.worktrees/v65-aaa" ] && [ "$(tail -1 <<<"$WL")" = "$REPO/.worktrees/v65-zzz" ] \
  && ok "목록 순서: v65-aaa = 앞(3행) · v65-zzz = 맨 뒤" || bad "목록 순서 가정 깨짐: 3행=$(sed -n 3p <<<"$WL") · 끝=$(tail -1 <<<"$WL")"

echo "== ⓐ 고치기 전 꼴 재현(RED 모양) — pipefail + 파이프 grep -q → 141"
old_form() { git -C "$REPO" worktree list --porcelain 2>/dev/null | grep -qxF "worktree $1"; }
old_printf_form() { printf '%s\n' "$PORC" | grep -qxF "worktree $1"; }
old_form "$REPO/.worktrees/v65-aaa"; rc=$?
[ "$rc" -eq 141 ] && ok "ⓐ git worktree list | grep -qxF (목록 앞) → rc 141" || bad "ⓐ 옛 꼴 rc=$rc (141 기대)"
old_printf_form "$REPO/.worktrees/v65-aaa"; rc=$?
[ "$rc" -eq 141 ] && ok "ⓐ printf | grep -qxF 도 같음 → rc 141 (카드 처방 printf 파이프는 고침이 아니다)" || bad "ⓐ printf 꼴 rc=$rc (141 기대)"
grep -qxF "worktree $REPO/.worktrees/v65-aaa" <<<"$PORC"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓐ here-string 꼴 → rc 0" || bad "ⓐ here-string rc=$rc"

run() { ( cd "$REPO" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" \
  FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" \
  FT_NANO_PREFIX=ft-v65-temp- FT_SEATS_JSON="$REPO/.fable-team/seats.json" FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" \
  FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtc" FT_WT_AUTOCLEAN=0 FT_CENSUS_MAIN=main "$@" 2>&1 ); }
dead() { printf 'other#0|%%9\n' > "$T/panes"; : > "$T/pane-cwds"; : > "$T/cwd"; : > "$T/tlog"; }

echo "== ⓑ --plan-only 등록 경로 → PLANNED (목록 앞·뒤)"
for k in aaa zzz; do
  dead; out="$(run bash "$T/bin/ft-nano-close.sh" "ft-v65-temp-$k#0" --plan-only "$REPO/.worktrees/v65-$k")"; rc=$?
  [ "$rc" -eq 0 ] && has "$out" "PLANNED $T/wtc/ft-v65-temp-$k#0.sh" "ⓑ v65-$k → PLANNED(rc=0)" || bad "ⓑ v65-$k rc=$rc ← ${out:0:400}"
  hasnt "$out" "등록 워크트리가 아니다" "  └ 오판 REJECT 0"
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 변경 0" || bad "  └ tmux 변경: $(cat "$T/tlog")"
done

echo "== ⓒ 미등록 경로 → 기존 REJECT 그대로(fail-closed)"
mkdir -p "$REPO/.worktrees/v65-plain"
dead; out="$(run bash "$T/bin/ft-nano-close.sh" 'ft-v65-temp-plain#0' --plan-only "$REPO/.worktrees/v65-plain")"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "REJECT --plan-only: 이 리포 .worktrees/ 아래 등록 워크트리가 아니다" "ⓒ 미등록 → REJECT(rc=1)" || bad "ⓒ rc=$rc ← ${out:0:400}"
[ ! -e "$T/wtc/ft-v65-temp-plain#0.sh" ] && ok "  └ 계획 0" || bad "  └ 미등록인데 계획 생성"

echo "== ⓓ --shared-wt ⓑ 검사 — 등록 cwd 통과 · 미등록 cwd bad 1줄"
SEAT='ft-v65-temp-shr#0'
live() { printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$1" > "$T/pane-cwds"; printf '%s' "$1" > "$T/cwd"; : > "$T/tlog"; }
live "$REPO/.worktrees/aab-shared"
out="$(run bash "$T/bin/ft-nano-close.sh" "$SEAT" --shared-wt --result "$T/result.md" --recv 1)"
hasnt "$out" "toplevel 이 등록된 워크트리가 아니다" "ⓓ 등록 공유 워크트리(목록 앞) → ⓑ 오판 0"
hasnt "$out" "나노 브랜치" "  └ 브랜치 feat/shared 읽음(nano/* 아님)"
OUT="$T/outside"; mkdir -p "$OUT"; git -C "$OUT" init -q
live "$OUT"
out="$(run bash "$T/bin/ft-nano-close.sh" "$SEAT" --shared-wt --result "$T/result.md" --recv 1)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "ⓑpane cwd($OUT)의 toplevel 이 등록된 워크트리가 아니다" "ⓓ 미등록 cwd → ⓑ bad 1줄 · REJECT" || bad "ⓓ 미등록 rc=$rc ← ${out:0:400}"

echo "== GIT_* 0"
[ -z "$(env | grep -E '^GIT_(DIR|WORK_TREE|INDEX_FILE|COMMON_DIR|OBJECT_DIRECTORY)=')" ] && ok "GIT_* env 0" || bad "GIT_* env 있음"

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
