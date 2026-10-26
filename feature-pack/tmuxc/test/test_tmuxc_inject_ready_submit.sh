#!/usr/bin/env bash
# test_tmuxc_inject_ready_submit.sh — r925(인덱스 r925-tmuxc-inject-submit-verify-and-succ)
#   tmuxc inject_message 가 «고정 sleep → 글자 → Enter 1번» 이라 컴퓨터가 바쁘면 글자만 입력줄에 남고 Enter 가
#   사라졌다(ops #56→#57 3회 정지). 고친 뒤 계약:
#     ⓐ 준비 늦음(6초 동안 입력 안 받음) → 준비 확인 뒤 입력 · 제출 1 · 입력줄 빔
#     ⓑ 첫 Enter 유실 → 재전송 1회로 제출 · 글자는 한 번만 들어간다(중복 0)
#     ⓒ Enter 전부 유실 → rc≠0 «제출 실패» · 글자 재입력 0
#     ⓔ 준비 빠름 → 제출 1 · 추가 대기 0.5초 이내
#   픽스처 = 가짜 tmux(상태 폴더 파일) — 실 tmux 서버·실 에이전트·홈 쓰기 0.
#   시험 대상 경로 = env FT_TMUXC_PATH (기본 = 이 저장소 사본) — base 사본으로 돌리면 빨강이어야 한다.
#   변이(FT_MUTATE=1|2): 1 = 옛 거동(준비 확인 0 + 확인 없는 Enter 1번) → ⓐ 빨강 · 2 = 재전송 무한 → ⓒ 빨강.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TMUXC="${FT_TMUXC_PATH:-$HERE/../core/bin/tmuxc}"
MUTATE="${FT_MUTATE:-0}"
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail + 1)); }

[ -f "$TMUXC" ] || { echo "FAIL 대상 없음: $TMUXC"; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
D="$T/state"; B="$T/bin"; mkdir -p "$D" "$B"
SHIM="$T/shim.sh"
MSG='[byz-t-old-claude#1→byz-t-new-claude#2] 통신 표준: 지금 read로 읽고 그대로 따를 것'

# ---------- 가짜 tmux — 준비 전에는 입력 상자를 안 그리고, 준비 전 Enter 는 유실된다 ----------
cat > "$B/tmux" <<'SH'
#!/usr/bin/env bash
D="${FAKE_AGENT_DIR:?}"
printf '%s\n' "$*" >> "$D/log"
cmd="$1"; shift || true
case "$cmd" in
  list-panes) printf 'sess|%%0\n'; exit 0 ;;
  capture-pane)
    # TUI 가 아직 안 그려진 상태 = 구분선 없음 → capture_input_line 이 rc1
    if [ ! -f "$D/ready" ]; then printf 'starting agent...\n'; exit 0; fi
    printf '─────\n'
    printf '❯ %s\n' "$(cat "$D/buffer" 2>/dev/null || true)"
    printf '─────\n'
    printf '  status\n'
    exit 0 ;;
  send-keys)
    lit=0; arg=""
    while [ $# -gt 0 ]; do case "$1" in
      -t) shift 2 ;;
      -l) lit=1; shift ;;
      *)  arg="$1"; shift ;;
    esac; done
    if [ "$lit" = 1 ]; then
      printf '%s' "$arg" >> "$D/buffer"     # pty 는 준비 전에도 글자를 받아 둔다(실측: 글자만 남고 Enter 가 사라진다)
      exit 0
    fi
    [ "$arg" = Enter ] || exit 0
    [ -f "$D/ready" ] || exit 0             # 준비 전 Enter = 유실
    n="$(cat "$D/enters_lost" 2>/dev/null || echo 0)"
    if [ "$n" -gt 0 ]; then printf '%s\n' "$((n - 1))" > "$D/enters_lost"; exit 0; fi
    { cat "$D/buffer" 2>/dev/null || true; printf '\n'; } >> "$D/submitted"
    : > "$D/buffer"
    exit 0 ;;
esac
exit 0
SH
chmod +x "$B/tmux"

# ---------- 함수 추출(대상 tmuxc 사본에서 그대로 잘라 온다 — 사본이 바뀌면 이 시험이 따라간다) ----------
sed -n '/^pane_id_of()/,/^}/p; /^capture_input_line()/,/^}/p; /^wait_input_box()/,/^}/p; /^box_cleared()/,/^}/p; /^inject_message()/,/^}/p' "$TMUXC" > "$SHIM"
printf 'session_agent_probe() { return 1; }\n' >> "$SHIM"
grep -q '^inject_message()' "$SHIM" || { echo "FAIL inject_message 를 못 잘랐다: $TMUXC"; exit 1; }
grep -q '^wait_input_box()' "$SHIM" || { echo "FAIL wait_input_box 없음(고치기 전 사본)"; }

case "$MUTATE" in
  1) # 옛 거동 복원 — 준비 확인 0 · 확인 없는 Enter 1번
     python3 - "$SHIM" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s = s.replace('if ! wait_input_box "$pane" "$ready_max"; then', 'if false; then  # MUTATE1', 1)
old = '''  for try in 1 2 3; do
    tmux send-keys -t "$pane" Enter
    if box_cleared "$pane" "$message"; then
      printf 'state=submitted session=%s try=%s\\n' "$session" "$try"
      return 0
    fi
  done'''
new = '''  tmux send-keys -t "$pane" Enter  # MUTATE1
  printf 'state=submitted session=%s try=1\\n' "$session"
  return 0'''
assert old in s, "MUTATE1 대체 실패"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
     ;;
  2) # 재전송 무한 — 회수를 안 빨아들이고 계속 누른다
     sed -i '' 's/^  for try in 1 2 3; do$/  for try in $(seq 1 1000); do  # MUTATE2/' "$SHIM" 2>/dev/null || sed -i 's/^  for try in 1 2 3; do$/  for try in $(seq 1 1000); do  # MUTATE2/' "$SHIM"
     grep -q 'MUTATE2' "$SHIM" || { echo "FAIL 변이2 적용 실패"; exit 1; }
     ;;
esac

# ---------- 한 판 실행 ----------
# run <준비 지연초> <Enter 유실 수> — 결과는 $D/{submitted,buffer,log} 와 $T/{rc,secs}(서브셸이라 파일로 넘긴다)
run() {
  local delay="$1" lost="$2"
  rm -rf "$D"; mkdir -p "$D"; rm -f "$T/rc" "$T/secs"
  printf '%s\n' "$lost" > "$D/enters_lost"
  local bg=""
  if [ "$delay" = 0 ]; then : > "$D/ready"; else ( sleep "$delay"; : > "$D/ready" ) & bg=$!; fi
  local t0 t1 rc
  t0="$(python3 -c 'import time;print(time.time())')"
  ( set -uo pipefail; . "$SHIM"; FAKE_AGENT_DIR="$D" PATH="$B:$PATH" inject_message sess "$MSG" agent ) > "$T/out" 2>&1
  rc=$?
  t1="$(python3 -c 'import time;print(time.time())')"
  [ -n "$bg" ] && { wait "$bg" 2>/dev/null || true; }
  printf '%s\n' "$rc" > "$T/rc"
  python3 -c "print(round($t1-$t0,2))" > "$T/secs"
}

# 무한 대기(변이2) 방지 — 20초 넘으면 124 로 찍고 끊는다
run_limited() {
  local lim=20 p i
  ( run "$@" ) & p=$!
  i=0
  while kill -0 "$p" 2>/dev/null; do
    sleep 0.2; i=$((i + 1))
    if [ "$i" -gt $((lim * 5)) ]; then
      kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null
      printf '124\n' > "$T/rc"; printf '%s\n' "$lim" > "$T/secs"; return 0
    fi
  done
  wait "$p" 2>/dev/null
}

load() { RC="$(cat "$T/rc" 2>/dev/null || echo 999)"; SECS="$(cat "$T/secs" 2>/dev/null || echo 0)"; }

submitted_ok() { [ -f "$D/submitted" ] && [ "$(sed -n '1p' "$D/submitted")" = "$MSG" ]; }
typed_count()  { grep -c 'send-keys' "$D/log" 2>/dev/null || true; }
typed_lit()    { grep -c ' -l ' "$D/log" 2>/dev/null || true; }

# ⓐ 준비 늦음 6초
run_limited 6 0; load
{ [ "$RC" = 0 ] && submitted_ok && [ ! -s "$D/buffer" ]; } \
  && ok "ⓐ 준비 6초 늦음 → 준비 확인 뒤 제출 1 · 입력줄 빔 (rc=$RC ${SECS}s)" \
  || bad "ⓐ rc=$RC submitted=[$(cat "$D/submitted" 2>/dev/null)] buffer=[$(cat "$D/buffer" 2>/dev/null)]"

# ⓑ 첫 Enter 유실 → 재전송 1회로 제출 · 글자 중복 0
run_limited 0 1; load
{ [ "$RC" = 0 ] && submitted_ok && [ "$(wc -l < "$D/submitted" 2>/dev/null | tr -d ' ')" = 1 ] && [ "$(typed_lit)" = 1 ] && [ ! -s "$D/buffer" ]; } \
  && ok "ⓑ 첫 Enter 유실 → Enter 재전송 1회 제출 · 글자 1회(중복 0) (rc=$RC ${SECS}s)" \
  || bad "ⓑ rc=$RC lines=$(wc -l < "$D/submitted" 2>/dev/null) lit=$(typed_lit) buffer=[$(cat "$D/buffer" 2>/dev/null)]"

# ⓒ Enter 전부 유실 → rc≠0 «제출 실패» · 글자 재입력 0
run_limited 0 999; load
{ [ "$RC" != 0 ] && grep -q '제출 실패' "$T/out" && [ ! -s "$D/submitted" ] && [ "$(typed_lit)" = 1 ]; } \
  && ok "ⓒ Enter 전부 유실 → rc=$RC «제출 실패» · 글자 재입력 0" \
  || bad "ⓒ rc=$RC lit=$(typed_lit) out=[$(tr '\n' ' ' < "$T/out")]"

# ⓔ 준비 빠름 → 제출 1 · 추가 대기 0.5초 이내
run_limited 0 0; load
ADD="$(python3 -c "print(round(${SECS}-0.3,2))")"
{ [ "$RC" = 0 ] && submitted_ok && python3 -c "import sys; sys.exit(0 if ${ADD} <= 0.9 else 1)"; } \
  && ok "ⓔ 준비 빠름 → 제출 1 · 확인 추가 대기 ${ADD}s (≤0.9)" \
  || bad "ⓔ rc=$RC 추가대기=${ADD}s submitted=[$(cat "$D/submitted" 2>/dev/null)]"

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS (mutate=$MUTATE)"; exit 0; }
echo "FAILED $fail (mutate=$MUTATE)"; exit 1
