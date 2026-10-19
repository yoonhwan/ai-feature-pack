#!/usr/bin/env bash
# test_nano_close_pack_wt.sh — 카드 r508: ft-nano-close.sh --wt <팩 .worktrees/…> --branch nano/<키> (하네스 «팩 나노» 닫기 · ⑥·⑤·미커밋 = 팩 리포 기준)
# 임시 리포 2개(BYZ 꼴 R · 팩 꼴 P + P 의 bare 원격) + 가짜 tmux(PATH 앞) + 스크립트 사본(가짜 cherry 게이트) — 실제 리포·seats·tmux 세션·외부 호출 0 · GIT_* env 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="$HERE/../../harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2»";; *) ok "$3";; esac; }

bash -n "$SRC/ft-nano-close.sh" && ok "bash -n ft-nano-close.sh" || bad "bash -n ft-nano-close.sh"

mkdir -p "$T/bin" "$T/fake"
cp "$SRC/ft-nano-close.sh" "$SRC/ft-nano-evidence-check.sh" "$SRC/ft-wt-sweep.sh" "$SRC/ft-hil.sh" "$T/bin/"
cp "$SRC/ft-sheet-events.sh" "$SRC/ft_sheet_events.py" "$SRC/ft_sheet_confirm.py" "$SRC/ft_sheet_key.py" "$SRC/ft_board_env.py" "$SRC/ft_board_mail.py" "$T/bin/"
export FT_SHEET_ROOT="$T/sheet-root"; mkdir -p "$FT_SHEET_ROOT/.fable-team/state"
printf '#!/bin/sh\necho "reap $1 stopped=0 left=0 rc=0"\n' > "$T/bin/ft-seat-reap.sh"
# 가짜 cherry 게이트 — <feat> <가지> 와 --repo 값을 기록하고 통과(실제 게이트는 test_nano_cherry_gate* 가 시험)
cat > "$T/bin/ft-nano-cherry-gate.sh" <<EOF
#!/usr/bin/env bash
r=""; a=("\$@"); for ((i=0; i<\${#a[@]}; i++)); do [ "\${a[\$i]}" = --repo ] && r="\${a[\$((i+1))]}"; done
echo "\$1 \$2 repo=\$r" > "$T/cherry.args"; echo "OK cherry stub"; exit 0
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
# R = BYZ 꼴 리포 — spawn 이 만든 같은 이름 빈 워크트리(.worktrees/harness-k · nano/k) 가 있다(실사건 꼴)
R="$T/repo"; mkdir -p "$R"; git -C "$R" init -q -b main; GC "$R" commit -q --allow-empty -m init
GC "$R" worktree add -q "$R/.worktrees/harness-k" -b nano/k
RW="$R/.worktrees/harness-k"
# P = 팩 꼴 리포 + bare 원격(origin/main fetch 가 실제로 된다)
git init -q --bare -b main "$T/P-origin.git"
P="$T/pack"; mkdir -p "$P"; git -C "$P" init -q -b main; GC "$P" commit -q --allow-empty -m pinit
git -C "$P" remote add origin "$T/P-origin.git"; git -C "$P" push -q origin main; git -C "$P" fetch -q origin
GC "$P" worktree add -q "$P/.worktrees/k" -b nano/k origin/main
PW="$P/.worktrees/k"; echo kit > "$PW/kit.sh"; GC "$PW" add kit.sh; GC "$PW" commit -q -m work
SHA="$(git -C "$PW" rev-parse HEAD)"
mkdir -p "$P/.worktrees/plain-dir"   # 팩 .worktrees/ 아래 «미등록» 폴더(ⓒ)

mkdir -p "$R/.fable-team" "$R/design/harness/indices/진행" "$T/comm/bodies"
echo seq > "$T/comm/bodies/1.txt"; echo res > "$T/result.md"
SEAT='byz-harness-nano-k#0'; CARD="$R/design/harness/indices/진행/k.md"

run() { ( cd "$R" && env -i HOME="$HOME" FT_SHEET_ROOT="$FT_SHEET_ROOT" HIL_DIR="$T/hil" HIL_CLIP=0 PATH="$T/fake:$PATH" FAKE_PANES="$T/panes" FAKE_CWD="$T/cwd" FAKE_PANE_CWDS="$T/pane-cwds" FAKE_LOG="$T/tlog" "$@" 2>&1 ); }
setup() {  # setup [설치 칸] — 명부·pane(cwd = BYZ 쪽 워크트리 · 실사건 꼴)·카드를 «정상» 으로 리셋
  printf '{"%s":{"role":"nano","index":"design/harness/indices/진행/k.md"}}\n' "$SEAT" > "$R/.fable-team/seats-harness.json"
  printf '%s|%%1\n' "$SEAT" > "$T/panes"; printf '%s|%s\n' "$SEAT" "$RW" > "$T/pane-cwds"; printf '%s' "$RW" > "$T/cwd"
  : > "$T/tlog"; : > "$T/ledger.md"; rm -rf "$T/wtclean" "$T/cherry.args"
  printf '# 인덱스: k\n- 설치: %s\n\n## 상태\n- 세트: %s · 시험: bash t.sh rc=0 · 이슈: 0\n' "${1:-있음 — 팩 키트 1}" "$SHA" > "$CARD"
}
close() { run FT_NANO_PREFIX=byz-harness-nano- FT_NANO_WT_PREFIX=harness- FT_NANO_FEAT=origin/main FT_PACK_ROOT="$P" \
  FT_SEATS_JSON="$R/.fable-team/seats-harness.json" FT_NANO_LEDGER="$T/ledger.md" FT_INBOX_ROOT="$T/comm" FT_NANO_IDLE_MIN=0 FT_WT_CLEAN_DIR="$T/wtclean" \
  bash "$T/bin/ft-nano-close.sh" "$SEAT" --result "$T/result.md" --recv 1 "$@"; }
untouched() {  # REJECT 뒤 kill·명부·팩 워크트리 변경 0
  [ -z "$(cat "$T/tlog")" ] && ok "  └ kill·태그 해제 0" || bad "REJECT 인데 tmux 변경: $(cat "$T/tlog")"
  jq -e --arg s "$SEAT" 'has($s)' "$R/.fable-team/seats-harness.json" >/dev/null && ok "  └ 명부 그대로" || bad "REJECT 인데 명부 삭제"
  [ "$(git -C "$PW" rev-parse HEAD)" = "$SHA" ] && ok "  └ 팩 HEAD 그대로(WIP 커밋 0)" || bad "팩 HEAD 가 움직임"
}

echo "== ⓐ --wt 팩 등록 워크트리 + 하네스 카드(- 설치: 있음) → ⑥ 팩 HEAD 대조 PASS · CLOSED"
setup; out="$(close --wt "$PW" --branch nano/k)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "CLOSED $SEAT" "ⓐ 팩 경로 → CLOSED(rc=0)" || bad "ⓐ rc=$rc ← ${out:0:900}"
has "$out" "OK 증거 줄" "  └ ⑥ 증거 줄 = 팩 워크트리 HEAD 대조 통과"
[ "$(cat "$T/cherry.args" 2>/dev/null)" = "origin/main nano/k repo=$P" ] && ok "  └ ⑤ cherry = --repo 팩 리포 · origin/main · --branch" || bad "  └ cherry 인자: $(cat "$T/cherry.args" 2>/dev/null)"
has "$out" "INFO 팩 워크트리 정리 = 별 경로" "  └ 정리 계획 0 · INFO 1줄"
hasnt "$out" "워크트리 정리 계획:" "  └ PLANNED/계획 안내 0"
[ ! -e "$T/wtclean/$SEAT.sh" ] && [ ! -e "$T/wtclean/$SEAT.sh.hil" ] && ok "  └ wt-clean 계획 파일 0" || bad "  └ 계획 파일이 생김: $(ls "$T/wtclean" 2>&1)"
has "$(cat "$T/ledger.md")" "mode=pack-wt wt=$PW branch=nano/k" "  └ 원장 행 mode=pack-wt"
has "$(cat "$T/tlog")" "kill-session" "  └ 세션 kill(표준승인 경로)"
[ -d "$PW" ] && [ -d "$RW" ] && ok "  └ 팩·BYZ 워크트리 그대로" || bad "  └ 워크트리가 사라짐"
git -C "$P" rev-parse --verify -q refs/heads/nano/k >/dev/null && ok "  └ 팩 브랜치 그대로" || bad "  └ 팩 브랜치 삭제됨"

echo "== ⓑ 같은 입력 · 카드 «- 설치: 없음»(제품 카드) → ⓐ REJECT(팩 경로는 하네스 카드만)"
setup "없음"; out="$(close --wt "$PW" --branch nano/k)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "REJECT $SEAT" "ⓑ 제품 카드 → REJECT" || bad "ⓑ rc=$rc ← ${out:0:600}"
has "$out" "ⓐ--wt($PW)가 이 리포($R)에 등록된 .worktrees/ 아래 워크트리가 아니다" "  └ 지금 ⓐ 문구 그대로"
has "$out" "팩 경로는 하네스 카드(- 설치: 있음)만" "  └ 덧말"
untouched

echo "== ⓒ --wt 가 팩 .worktrees/ 아래 미등록 폴더 → REJECT"
setup; out="$(close --wt "$P/.worktrees/plain-dir" --branch nano/k)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "ⓐ--wt(" "ⓒ 미등록 폴더 → ⓐ REJECT" || bad "ⓒ rc=$rc ← ${out:0:600}"
untouched

echo "== ⓓ 팩 워크트리 미커밋 1 → REJECT(팩 리포 기준 ⓔ)"
setup; echo dirty > "$PW/dirty.txt"
out="$(close --wt "$PW" --branch nano/k)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "ⓔ--wt 미커밋 변경 1건" "ⓓ 팩 미커밋 → ⓔ REJECT" || bad "ⓓ rc=$rc ← ${out:0:600}"
untouched; rm -f "$PW/dirty.txt"

echo "== ⓔ --wt 없이(표준 해석) 팩 나노 → 지금처럼 BYZ 워크트리 대조(동작 변경 0)"
setup; out="$(close)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "세트 HEAD ${SHA:0:9} != 현재 나노 HEAD $(git -C "$RW" rev-parse --short=9 HEAD)" "ⓔ 표준 해석 → BYZ HEAD 대조 REJECT(지금 그대로)" || bad "ⓔ rc=$rc ← ${out:0:600}"
hasnt "$out" "팩 워크트리" "  └ 팩 경로 분기 0"
untouched

echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
