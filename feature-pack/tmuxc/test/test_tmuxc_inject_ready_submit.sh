#!/usr/bin/env bash
# test_tmuxc_inject_ready_submit.sh — r925(인덱스 r925-tmuxc-inject-submit-verify-and-succ · DA⑥ r1 반송 r2)
#   tmuxc inject_message 가 «고정 sleep → 글자 → Enter 1번» 이라 컴퓨터가 바쁘면 글자만 입력줄에 남고
#   Enter 가 사라졌다(ops #56→#57 3회 정지). 고친 뒤 계약:
#     ⓐ 준비 늦음(6초 동안 입력 안 받음) → 준비 확인 뒤 입력 · 제출 1 · 입력줄 빔
#     ⓑ 첫 Enter 유실 → 재전송 1회로 제출 · 글자는 한 번만 들어간다(중복 0)
#     ⓒ Enter 전부 유실 → rc≠0 «제출 실패» · 글자 재입력 0
#     ⓔ 준비 빠름 → 제출 1 · 추가 대기 0.9초 이내
#   DA⑥ r1 반례 5건의 시험(고침 P1·P2·P3):
#     ⓕ 입력줄에 사람 글자(«HUMAN DRAFT») → 글자 주입 0 · rc≠0 «입력줄에 다른 글자»
#     ⓘ 첫 Enter 유실 + 그 사이 사람이 입력 → 재전송 0(Enter 1회) · 사람 글자 제출 0
#     ⓙ 화면 판독 실패(capture rc1) → rc≠0 · «제출됨» 판정 0
#     ⓚ 입력줄이 사라짐(권한 프롬프트) → rc≠0 · 글자 주입 0
#     ⓛ codex·pi 경로 = 기준 커밋(cbe218a5)과 «같은 tmux 호출 바이트»(P3 회귀 0)
#     ⓜ 여러 줄 작업문이 유실(입력줄은 비는데 위 화면에 증거 없음) → rc≠0 · 글자 재입력 0
#   픽스처 = 가짜 tmux(상태 폴더 파일 · 화면 여러 줄 + 처리 이력) — 실 tmux 서버·실 에이전트·홈 쓰기 0.
#   시험 대상 경로 = env FT_TMUXC_PATH (기본 = 이 저장소 사본) — base 사본으로 돌리면 빨강이어야 한다.
#   변이(FT_MUTATE): 1 = 옛 거동(준비 확인 0 + 확인 없는 Enter 1번) → ⓐ 빨강 · 2 = 재전송 무한 → ⓒ 빨강
#                    4 = 빈 입력줄 검사 끔 → ⓕ 빨강 · 6 = 재전송 전 재확인 끔 → ⓘ 빨강 · 7 = 판독 실패 = 제출됨 → ⓙ 빨강
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
#   파일: ready(준비됨) · buffer(입력줄) · transcript(처리 이력 = 입력 상자 «위») · enters_lost(유실할 Enter 수)
#         submit_void(제출됐지만 화면에 안 남음) · capture_fail(판독 실패) · fail_after(N번째부터 판독 실패)
#         no_box(입력 상자 없음 = 권한 프롬프트) · cap_n(판독 횟수)
cat > "$B/tmux" <<'SH'
#!/usr/bin/env bash
D="${FAKE_AGENT_DIR:?}"
printf '%s\n' "$*" >> "$D/log"
cmd="$1"; shift || true
case "$cmd" in
  list-panes) printf 'sess|%%0\n'; exit 0 ;;
  capture-pane)
    n=$(( $(cat "$D/cap_n" 2>/dev/null || echo 0) + 1 )); printf '%s\n' "$n" > "$D/cap_n"
    # 사람이 «N번째 화면 판독 순간» 에 입력한다(시각 대신 횟수로 잡아 결정적으로 만든다)
    if [ -f "$D/human_at" ] && [ "$n" -ge "$(cat "$D/human_at")" ]; then
      rm -f "$D/human_at"; printf '%s' "${HUMAN_TEXT:- HUMAN LINE}" >> "$D/buffer"
    fi
    [ -f "$D/capture_fail" ] && exit 1
    if [ -f "$D/fail_after" ] && [ "$n" -gt "$(cat "$D/fail_after")" ]; then exit 1; fi
    if [ -f "$D/no_box" ]; then printf 'Do you want to proceed?\n  1. Yes\n  2. No\n'; exit 0; fi
    if [ ! -f "$D/ready" ]; then printf 'starting agent...\n'; exit 0; fi
    [ -f "$D/transcript" ] && cat "$D/transcript"
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
    if [ -f "$D/submit_void" ]; then rm -f "$D/submit_void"; : > "$D/buffer"; exit 0; fi   # 제출됐지만 화면에 안 남음
    { cat "$D/buffer" 2>/dev/null || true; printf '\n'; } >> "$D/transcript"
    : > "$D/buffer"
    exit 0 ;;
esac
exit 0
SH
chmod +x "$B/tmux"

# ---------- 함수 추출(대상 tmuxc 사본에서 그대로 잘라 온다 — 사본이 바뀌면 이 시험이 따라간다) ----------
sed -n '/^pane_id_of()/,/^}/p; /^capture_input_line()/,/^}/p; /^wait_input_box()/,/^}/p; /^text_head()/,/^}/p; /^screen_flat()/,/^}/p; /^buffer_is_ours()/,/^}/p; /^submit_state()/,/^}/p; /^agent_inject()/,/^}/p; /^inject_message()/,/^}/p' "$TMUXC" > "$SHIM"
printf 'session_agent_probe() { return 1; }\n' >> "$SHIM"
grep -q '^inject_message()' "$SHIM" || { echo "FAIL inject_message 를 못 잘랐다: $TMUXC"; exit 1; }
if ! grep -q '^wait_input_box()' "$SHIM"; then
  echo "FAIL 고치기 전 사본 — 준비·제출 확인 함수(wait_input_box·submit_state)가 없다: $TMUXC"
  # 빨강의 «내용» 을 남긴다: 옛 inject_message 로 ⓐ(준비 1초 늦음)를 실제로 돌려 «글자만 남고 제출 0» 을 보인다.
  sed -n '/^inject_message()/,/^}/p' "$TMUXC" > "$SHIM.old"
  printf 'session_agent_probe() { return 1; }\n' >> "$SHIM.old"
  if grep -q '^inject_message()' "$SHIM.old"; then
    rm -rf "$D"; mkdir -p "$D"
    ( sleep 1; : > "$D/ready" ) & oldbg=$!
    ( set -uo pipefail; . "$SHIM.old"; FAKE_AGENT_DIR="$D" PATH="$B:$PATH" inject_message sess "$MSG" ) > "$T/out" 2>&1; oldrc=$?
    wait "$oldbg" 2>/dev/null || true
    echo "옛 판 ⓐ(준비 1초 늦음) 결과: rc=$oldrc 제출=[$(cat "$D/transcript" 2>/dev/null || true)] 입력줄에 남은 글자=[$(cat "$D/buffer" 2>/dev/null || true)]"
  fi
  exit 1
fi

case "$MUTATE" in
  1) # 옛 거동 복원 — 준비 확인 0 · 확인 없는 Enter 1번
     python3 - "$SHIM" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
s = s.replace('  if ! wait_input_box "$pane" "$ready_max"; then', '  if false; then  # MUTATE1', 1)
old = '''    tmux send-keys -t "$pane" Enter
    st=0; submit_state "$pane" "$message" "$head" || st=$?'''
new = '''    tmux send-keys -t "$pane" Enter  # MUTATE1
    printf 'state=submitted session=%s try=%s\\n' "$session" "$try"; return 0
    st=0; submit_state "$pane" "$message" "$head" || st=$?'''
assert old in s, "MUTATE1 대체 실패"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
     ;;
  2) # 재전송 무한 — 회수를 안 빨아들이고 계속 누른다
     sed -i '' 's/^  for try in 1 2 3; do$/  for try in $(seq 1 1000); do  # MUTATE2/' "$SHIM" 2>/dev/null || sed -i 's/^  for try in 1 2 3; do$/  for try in $(seq 1 1000); do  # MUTATE2/' "$SHIM"
     grep -q 'MUTATE2' "$SHIM" || { echo "FAIL 변이2 적용 실패"; exit 1; }
     ;;
  4) # 빈 입력줄 검사 끔 — 사람 글자 뒤에 붙여 제출한다(DA⑥ r1 반례 1)
     python3 - "$SHIM" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '  if [[ -n "$cur" ]]; then\n    printf \'state=input-busy'
new = '  if false; then  # MUTATE4\n    printf \'state=input-busy'
assert old in s, "MUTATE4 대체 실패"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
     ;;
  6) # 재전송 전 재확인 끔 — 사람 글자를 제출한다(DA⑥ r1 반례 2)
     python3 - "$SHIM" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '      buffer_is_ours "$cur" "$message" || {'
new = '      true || {  # MUTATE6 — 재확인 없이 재전송'
assert old in s, "MUTATE6 대체 실패"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
     ;;
  7) # 판독 실패 = 「제출됨」 으로 되돌린다(DA⑥ r1 반례 3)
     python3 - "$SHIM" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = '    cur="$(capture_input_line "$pane" join)" || return 2'
new = '    cur="$(capture_input_line "$pane" join)" || { printf "state=submitted session=%s try=%s\\n" "$1" 1; return 0; }  # MUTATE7'
assert old in s, "MUTATE7 대체 실패"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
     ;;
esac

# ---------- 한 판 실행 ----------
# run <준비 지연초> <Enter 유실 수> [준비 파일…] — 결과는 $D/{transcript,buffer,log} 와 $T/{rc,secs}(서브셸이라 파일로 넘긴다)
run() {
  local delay="$1" lost="$2"; shift 2 || true
  rm -rf "$D"; mkdir -p "$D"; rm -f "$T/rc" "$T/secs"
  printf '%s\n' "$lost" > "$D/enters_lost"
  local bg=""
  if [ "$delay" = 0 ]; then : > "$D/ready"; else ( sleep "$delay"; : > "$D/ready" ) & bg=$!; fi
  local t0 t1 rc
  t0="$(python3 -c 'import time;print(time.time())')"
  ( set -uo pipefail; . "$SHIM"; FAKE_AGENT_DIR="$D" PATH="$B:$PATH" TMUXC_READY_MAX="${TMUXC_READY_MAX:-30}" inject_message sess "$MSG" agent ) > "$T/out" 2>&1
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

submitted_ok() { [ -f "$D/transcript" ] && grep -qxF "$MSG" "$D/transcript"; }
typed_lit()    { grep -c ' -l ' "$D/log" 2>/dev/null || true; }
enters()       { grep -c 'send-keys -t %0 Enter' "$D/log" 2>/dev/null || true; }

# ⓐ 준비 늦음 6초
run_limited 6 0; load
{ [ "$RC" = 0 ] && submitted_ok && [ ! -s "$D/buffer" ]; } \
  && ok "ⓐ 준비 6초 늦음 → 준비 확인 뒤 제출 1 · 입력줄 빔 (rc=$RC ${SECS}s)" \
  || bad "ⓐ rc=$RC transcript=[$(cat "$D/transcript" 2>/dev/null)] buffer=[$(cat "$D/buffer" 2>/dev/null)] out=$(tr '\n' ' ' < "$T/out")"

# ⓑ 첫 Enter 유실 → 재전송 1회로 제출 · 글자 중복 0
run_limited 0 1; load
{ [ "$RC" = 0 ] && submitted_ok && [ "$(grep -c . "$D/transcript" 2>/dev/null | tr -d ' ')" = 1 ] && [ "$(typed_lit)" = 1 ] && [ ! -s "$D/buffer" ]; } \
  && ok "ⓑ 첫 Enter 유실 → Enter 재전송 1회 제출 · 글자 1회(중복 0) (rc=$RC ${SECS}s)" \
  || bad "ⓑ rc=$RC lines=$(grep -c . "$D/transcript" 2>/dev/null) lit=$(typed_lit) buffer=[$(cat "$D/buffer" 2>/dev/null)]"

# ⓒ Enter 전부 유실 → rc≠0 «제출 실패» · 글자 재입력 0
run_limited 0 999; load
{ [ "$RC" != 0 ] && grep -q '제출 실패' "$T/out" && [ ! -s "$D/transcript" ] && [ "$(typed_lit)" = 1 ]; } \
  && ok "ⓒ Enter 전부 유실 → rc=$RC «제출 실패» · 글자 재입력 0" \
  || bad "ⓒ rc=$RC lit=$(typed_lit) out=[$(tr '\n' ' ' < "$T/out")]"

# ⓔ 준비 빠름 → 제출 1 · 추가 대기 0.9초 이내
run_limited 0 0; load
ADD="$(python3 -c "print(round(${SECS}-0.3,2))")"
{ [ "$RC" = 0 ] && submitted_ok && python3 -c "import sys; sys.exit(0 if ${ADD} <= 0.9 else 1)"; } \
  && ok "ⓔ 준비 빠름 → 제출 1 · 확인 추가 대기 ${ADD}s (≤0.9)" \
  || bad "ⓔ rc=$RC 추가대기=${ADD}s transcript=[$(cat "$D/transcript" 2>/dev/null)]"

# ⓕ r2 반례 1 — 입력줄에 사람 글자가 있으면 «붙여 제출» 하지 않는다(빈 줄에만 넣는다)
rm -rf "$D"; mkdir -p "$D"; : > "$D/ready"; printf '%s' 'HUMAN DRAFT — 내가 쓰던 글' > "$D/buffer"
( set -uo pipefail; . "$SHIM"; FAKE_AGENT_DIR="$D" PATH="$B:$PATH" inject_message sess "$MSG" agent ) > "$T/out" 2>&1; RC=$?
{ [ "$RC" != 0 ] && grep -q '입력줄에 다른 글자' "$T/out" && [ "$(typed_lit)" = 0 ] && [ ! -s "$D/transcript" ] \
  && grep -qF 'HUMAN DRAFT' "$D/buffer"; } \
  && ok "ⓕ 입력줄에 사람 글자 → 주입 0 · rc=$RC «입력줄에 다른 글자» · 사람 글자 보존" \
  || bad "ⓕ rc=$RC lit=$(typed_lit) out=$(tr '\n' ' ' < "$T/out") buffer=[$(cat "$D/buffer" 2>/dev/null)]"

# ⓘ r2 반례 2 — 첫 Enter 유실 + 그 사이 사람이 입력(«재전송 직전 재확인» 순간) → 재전송 Enter 0 · 사람 글자 제출 0
#   사람 입력 시점을 «9번째 화면 판독» 으로 고정한다: 준비 1 + 빈 줄 1 + 제출 확인 6 = 8, 그 다음(9번째)이 재전송 직전 재확인.
rm -rf "$D"; mkdir -p "$D"; : > "$D/ready"; printf '1\n' > "$D/enters_lost"; : > "$D/log"
printf '9\n' > "$D/human_at"
( set -uo pipefail; . "$SHIM"; FAKE_AGENT_DIR="$D" PATH="$B:$PATH" inject_message sess "$MSG" agent ) > "$T/out" 2>&1; RC=$?
{ [ "$RC" != 0 ] && [ "$(enters)" = 1 ] && [ ! -s "$D/transcript" ] && grep -q '다른 글자' "$T/out"; } \
  && ok "ⓘ 첫 Enter 유실 + 사람 입력 → 재전송 0(Enter 1회) · 사람 글자 제출 0 · rc=$RC" \
  || bad "ⓘ rc=$RC enters=$(enters) transcript=[$(cat "$D/transcript" 2>/dev/null)] out=$(tr '\n' ' ' < "$T/out")"

# ⓙ r2 반례 3 — 화면 판독 실패를 «입력줄 빔» 으로 읽지 않는다: rc≠0 · «제출됨» 판정 0
rm -rf "$D"; mkdir -p "$D"; : > "$D/ready"; printf '2\n' > "$D/fail_after"   # 준비·빈 줄 확인은 되고, 그 뒤 판독 실패
( set -uo pipefail; . "$SHIM"; FAKE_AGENT_DIR="$D" PATH="$B:$PATH" inject_message sess "$MSG" agent ) > "$T/out" 2>&1; RC=$?
{ [ "$RC" != 0 ] && grep -q '판독' "$T/out" && ! grep -q 'state=submitted' "$T/out" && [ "$(typed_lit)" = 1 ]; } \
  && ok "ⓙ 판독 실패(capture rc1) → rc=$RC «판독 실패» · «제출됨» 0 · 글자 1회" \
  || bad "ⓙ rc=$RC out=$(tr '\n' ' ' < "$T/out")"

# ⓚ 입력 상자가 안 보임(권한 프롬프트) → rc≠0 · 글자 주입 0 (상한 1초)
rm -rf "$D"; mkdir -p "$D"; : > "$D/ready"; : > "$D/no_box"
( set -uo pipefail; . "$SHIM"; FAKE_AGENT_DIR="$D" PATH="$B:$PATH" TMUXC_READY_MAX=1 inject_message sess "$MSG" agent ) > "$T/out" 2>&1; RC=$?
{ [ "$RC" != 0 ] && grep -q '입력 상자가 1초 안에 안 떴다' "$T/out" && [ "$(typed_lit)" = 0 ] && [ "$(enters)" = 0 ]; } \
  && ok "ⓚ 권한 프롬프트(입력줄 없음) → rc=$RC «입력 상자 안 뜸» · 주입·Enter 0" \
  || bad "ⓚ rc=$RC out=$(tr '\n' ' ' < "$T/out")"

# ⓜ r2 반례 4 — 여러 줄 작업문이 유실(입력줄은 비는데 위 화면에 증거 없음) → rc≠0 · 글자 재입력 0
MLINE=$'[byz-t-old-claude#1→byz-t-new-claude#2] 통신 표준\n두째 줄 작업문\n셋째 줄 작업문'
rm -rf "$D"; mkdir -p "$D"; : > "$D/ready"; : > "$D/submit_void"
( set -uo pipefail; . "$SHIM"; FAKE_AGENT_DIR="$D" PATH="$B:$PATH" inject_message sess "$MLINE" agent ) > "$T/out" 2>&1; RC=$?
{ [ "$RC" != 0 ] && grep -q 'state=no-proof' "$T/out" && [ "$(enters)" = 1 ] && [ ! -s "$D/transcript" ]; } \
  && ok "ⓜ 여러 줄 작업문 유실 → rc=$RC «증거 없음» · Enter 1회(재전송 0)" \
  || bad "ⓜ rc=$RC enters=$(enters) out=$(tr '\n' ' ' < "$T/out")"

# ⓛ r2 반례 4(P3) — codex·pi 경로는 기준 커밋(cbe218a5)과 «같은 tmux 호출» 이어야 한다(회귀 0).
#   대역이 준비를 2초 늦춘다: 고친 판이 여기서 기다리거나 캡처하면 호출 로그가 갈린다.
BASE_SHA=cbe218a5
ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"
if [ -n "$ROOT" ] && git -C "$ROOT" cat-file -e "${BASE_SHA}:feature-pack/tmuxc/core/bin/tmuxc" 2>/dev/null; then
  git -C "$ROOT" show "${BASE_SHA}:feature-pack/tmuxc/core/bin/tmuxc" > "$T/base-tmuxc"
  sed -n '/^inject_message()/,/^}/p' "$T/base-tmuxc" > "$T/shim-base.sh"
  plain_calls() { # plain_calls <shim> <결과파일> — 준비 2초 늦은 대역에서 plain 주입 1회의 tmux 호출을 남긴다
    local shim="$1" out="$2"
    rm -rf "$D"; mkdir -p "$D"; printf '0\n' > "$D/enters_lost"
    ( sleep 2; : > "$D/ready" ) &
    ( set -uo pipefail; . "$shim"; FAKE_AGENT_DIR="$D" PATH="$B:$PATH" inject_message sess "$MSG" plain ) > "$out" 2>&1
    printf 'rc=%s\n' "$?" >> "$out"
    wait $! 2>/dev/null || true
    cp "$D/log" "$out.log" 2>/dev/null || : > "$out.log"
  }
  plain_calls "$T/shim-base.sh" "$T/plain-base.txt"
  plain_calls "$SHIM" "$T/plain-new.txt"
  { cmp -s "$T/plain-base.txt.log" "$T/plain-new.txt.log" && cmp -s "$T/plain-base.txt" "$T/plain-new.txt" \
    && grep -q '^rc=0$' "$T/plain-new.txt" && ! grep -q 'capture-pane' "$T/plain-new.txt.log"; } \
    && ok "ⓛ codex·pi(plain) → 기준 커밋 cbe218a5 과 tmux 호출·결과 바이트 같음 · 캡처 0" \
    || bad "ⓛ plain 회귀: base=[$(tr '\n' '|' < "$T/plain-base.txt.log")] new=[$(tr '\n' '|' < "$T/plain-new.txt.log")]"
else
  bad "ⓛ 기준 커밋 ${BASE_SHA} 을 못 읽어 plain 회귀를 못 잰다(root=${ROOT:-none})"
fi

# ⓝ r2 P2 — cmd_open 은 주입이 실패하면 «session created» 성공 문구 대신 실패 문구 + rc≠0
OC="$T/open"; mkdir -p "$OC/bin" "$OC/home" "$OC/wt"
cat > "$OC/bin/tmux" <<'SH'
#!/usr/bin/env bash
echo "tmux $*" >> "$FAKE_OUT/log"
case "$1" in
  has-session) exit 1 ;;
  display-message) echo fakeorch ;;
  list-panes) echo 4242 ;;
  capture-pane) exit 1 ;;          # 판독 실패
  *) exit 0 ;;
esac
SH
chmod +x "$OC/bin/tmux"
OOUT="$(env -i PATH="$OC/bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$OC/home" FAKE_OUT="$OC" TMUXC_READY_MAX=1 \
  bash "$TMUXC" open "$OC/wt" --name T925 --agent claude --model claude-sonnet-5 2>&1)"; ORC=$?
{ [ "$ORC" -ne 0 ] && printf '%s\n' "$OOUT" | grep -q '부팅 문장 제출 실패 rc=' \
  && ! printf '%s\n' "$OOUT" | grep -qx 'tmuxc session created'; } \
  && ok "ⓝ cmd_open 판독 실패 → rc=$ORC «부팅 문장 제출 실패» · «session created» 성공 문구 0" \
  || bad "ⓝ rc=$ORC out=$(printf '%s' "$OOUT" | tr '\n' ' ' | cut -c1-200)"

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS (mutate=$MUTATE)"; exit 0; }
echo "FAILED $fail (mutate=$MUTATE)"; exit 1
