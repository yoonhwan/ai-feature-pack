#!/usr/bin/env bash
# test_tmuxc_serena_retired_r1182.sh — r1182: Serena 은퇴(10-22) 판 tmuxc 0.4.9.
#   R1 pi --serena --dry-run → rc 2 · stderr «Serena 은퇴» 1줄 · 세션 열기 0
#   R2 claude --serena(실전 open) → 같은 거부 · tmux 호출 0
#   R3 pi --dry-run(플래그 없음) → mcp 줄 0 · serena 줄 0 · .pi/mcp.json 쓰기 0
#   R4 bin 실행 줄에 serena ensure·mcp.json 쓰기 코드 0
#   변이 1: open 의 «--serena) die_serena_retired» 줄을 지운 사본 → R1 이 FAIL 로 잡혀야 한다
#   픽스처 = 가짜 tmux(호출 기록 · rc1) · 임시 HOME · 실 tmux·실 serena·외부 호출 0 · 자기 재호출 0.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TMUXC="$HERE/../core/bin/tmuxc"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
mkdir -p "$T/bin" "$T/home" "$T/wt"
git -C "$T/wt" init -q .
cat > "$T/bin/tmux" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_TMUX_LOG"
exit 1
SH
chmod +x "$T/bin/tmux"
export FAKE_TMUX_LOG="$T/tmux.log"
run() {  # <bin> <args...> → $T/out · $T/err · rc
  local bin="$1"; shift
  : > "$FAKE_TMUX_LOG"
  env -u TMUX -u TMUXC_PI_SESSION_ID HOME="$T/home" PATH="$T/bin:$PATH" "$bin" "$@" >"$T/out" 2>"$T/err" </dev/null
}
# R1 판정 — 변이 사본에도 같은 함수를 쓴다(rc 0 = 계약 지킴)
check_r1() {  # <bin>
  run "$1" open "$T/wt" --agent pi --serena --dry-run; local rc=$?
  [ "$rc" -eq 2 ] || return 1
  [ "$(wc -l < "$T/err" | tr -d ' ')" = 1 ] || return 1
  grep -q 'Serena 은퇴' "$T/err" || return 1
  grep -q 'ci(sym' "$T/err" || return 1
  [ ! -s "$T/out" ] && [ ! -s "$FAKE_TMUX_LOG" ]
}

check_r1 "$TMUXC" && ok "R1 pi --serena --dry-run → rc2 · 은퇴 1줄 · 세션 0" \
  || bad "R1 rc/err: $(cat "$T/err") · tmux: $(cat "$FAKE_TMUX_LOG")"

run "$TMUXC" open "$T/wt" --agent claude --serena; rc=$?
if [ "$rc" -eq 2 ] && grep -q 'Serena 은퇴' "$T/err" && [ ! -s "$FAKE_TMUX_LOG" ]; then ok "R2 claude --serena(실전) → rc2 · tmux 호출 0"
else bad "R2 rc=$rc err=$(cat "$T/err") tmux=$(cat "$FAKE_TMUX_LOG")"; fi

for args in "fork X --serena" "save --serena"; do
  sub="${args%% *}"
  # shellcheck disable=SC2086
  run "$TMUXC" $args; rc=$?
  if [ "$rc" -eq 2 ] && grep -q 'Serena 은퇴' "$T/err"; then ok "R2b $sub --serena → rc2"
  else bad "R2b $sub rc=$rc err=$(cat "$T/err")"; fi
done

run "$TMUXC" open "$T/wt" --agent pi --dry-run; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^command=pi ' "$T/out" && ! grep -q '^mcp' "$T/out" \
   && ! grep -qi 'serena' "$T/out" "$T/err" && [ ! -e "$T/wt/.pi/mcp.json" ]; then ok "R3 pi --dry-run → mcp·serena 줄 0 · mcp.json 0"
else bad "R3 rc=$rc out=$(cat "$T/out") err=$(cat "$T/err")"; fi

leak="$(grep -nE '^[^#]*(ensure_serena|serena_project_for|pi_serena_write_files|mcp__serena|TMUXC_PI_SERENA|\.pi/mcp\.json|serena=)' "$TMUXC")"
[ -z "$leak" ] && ok "R4 bin 실행 줄에 serena 코드 0" || bad "R4 남은 줄: $leak"

# 변이 — 거부 줄을 지운 사본(같은 폴더 구조 · core/libexec 도 따라 복사)
M="$T/mut/core"; mkdir -p "$M"; cp -R "$HERE/../core/." "$M/"
python3 - "$M/bin/tmuxc" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
line = "      --serena) die_serena_retired ;;\n"
i = s.index(line)  # 첫 번째 = cmd_open
open(p, "w", encoding="utf-8").write(s[:i] + s[i + len(line):])
PY
check_r1 "$M/bin/tmuxc" && bad "변이(거부 줄 삭제)가 R1 을 통과했다 — 시험이 못 잡음" \
  || ok "변이(거부 줄 삭제) → R1 FAIL 로 잡힘"

echo "fail=$fail"
[ "$fail" -eq 0 ]
