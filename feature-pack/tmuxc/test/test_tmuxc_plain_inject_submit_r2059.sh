#!/usr/bin/env bash
# test_tmuxc_plain_inject_submit_r2059.sh — r2059 plain 주입(pi·codex 좌석) 정규화 + 제출 확인(반례 ①~⑥).
#   사건: pi 입력 상자는 자동완성 목록이 열린 채 Enter 를 받으면 후보를 채택하고 제출하지 않는다.
#         tmuxc plain 주입은 글자 → Enter 1회 → 확인 0 이라 본문이 입력줄에 남은 채 «session created» 였다.
#   틀 = _harness_tmuxc_inject.sh(함수 추출·call) · 가짜 tmux 는 이 파일이 pi 입력 상자 꼴로 덮어쓴다.
#   sleep = 함수 대역(실 sleep 0) · 실 tmux·실 pi 0 · 시험 대상 = env FT_TMUXC_PATH(기준판으로 돌리면 Red 칸이 빨강).
#   칸: ① 끝 공백·개행 뗌 / 빈 글 rc2 · ② Enter 1회 비워짐 · ③ 일하는 중 테두리 + 꼬리 «.beads/» 1회 남음 → try=2
#       ④ 3회 남음 → stuck rc≠0 · ⑤ 판독 불가 → unverified rc0 / 쉼 테두리 빈 상자 → try=1 · ⑥ open --agent pi --prompt
#   변이(FT_MUTATE): M1 = 정규화 지움(→ ① FAIL) · M2 = 확인 고리를 Enter 1회로 되돌림(→ ③ FAIL)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
R2059_MUTATE="${FT_MUTATE:-0}"
case "$R2059_MUTATE" in M1|M2) FT_MUTATE=0 ;; esac   # 틀의 변이(J·P·…)와 섞지 않는다
. "$HERE/_harness_tmuxc_inject.sh"
MUTATE="$R2059_MUTATE"

# ---------- 이 시험의 함수 추가 추출(plain 판독·고리 · 기준판에는 없다) ----------
for f in plain_input_line plain_submit_loop; do
  grep -q "^${f}()" "$SHIM" || sed -n "/^${f}()/,/^}/p" "$TMUXC" >> "$SHIM"
done
printf 'sleep() { printf "%%s\\n" "$1" >> "$FAKE_AGENT_DIR/sleeps"; }\n' >> "$SHIM"
case "$MUTATE" in
  M1) python3 - "$SHIM" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = 'message="${message%"${message##*[!$ws]}"}"'
assert old in s, "M1 대체 실패"
open(p, "w", encoding="utf-8").write(s.replace(old, ': # MUTATE M1', 1))
PY
  ;;
  M2) python3 - "$SHIM" <<'PY'
import sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read()
old = 'for try in 1 2 3; do'
assert s.count(old) >= 1, "M2 대체 실패"
i = s.index('plain_submit_loop()'); j = s.index(old, i)
open(p, "w", encoding="utf-8").write(s[:j] + 'for try in 1; do  # MUTATE M2' + s[j + len(old):])
PY
  ;;
esac

# ---------- 가짜 tmux(pi 입력 상자 꼴) ----------
#   frame=working → 위 테두리 «── ⠇ Working ──…» · 아니면 «─────…» · 상자 줄 = 2칸 들여쓰기 + 끝 공백
#   stick=N → Enter N회까지는 제출 0(첫 회에 꼬리 «.beads/» 를 붙임) · stick_match = 그 글자를 담은 입력줄에만 적용
#   cap_rc1 → 정상 모양 + rc1 · no_border → 테두리 없는 화면 · FAKE_NOSESS=1 → has-session rc1(open 용)
cat > "$B/tmux" <<'SH'
#!/usr/bin/env bash
D="${FAKE_AGENT_DIR:?}"
printf '%s\n' "$*" >> "$D/log"
cmd="$1"; shift || true
case "$cmd" in
  has-session) [ "${FAKE_NOSESS:-0}" = 1 ] && exit 1; exit 0 ;;
  display-message) echo fakeorch; exit 0 ;;
  list-panes) printf 'sess|%%0\n'; exit 0 ;;
  capture-pane)
    if [ -f "$D/no_border" ]; then printf 'codex\n› \n'; exit 0; fi
    [ -f "$D/transcript" ] && cat "$D/transcript"
    if [ -f "$D/frame" ] && [ "$(cat "$D/frame")" = working ]; then printf '── ⠇ Working ──────────────────────\n'
    else printf '──────────────────────────────────\n'; fi
    buf="$(cat "$D/buffer" 2>/dev/null || true)"
    if [ -n "$buf" ]; then printf '%s\n' "$buf" | sed 's/^/  /; s/$/      /'; else printf '      \n'; fi
    printf '──────────────────────────────────\n'
    printf '~/wt\n'
    [ -f "$D/cap_rc1" ] && exit 1
    exit 0 ;;
  send-keys)
    lit=0; arg=""
    while [ $# -gt 0 ]; do case "$1" in
      -t) shift 2 ;;
      -l) lit=1; shift ;;
      *)  arg="$1"; shift ;;
    esac; done
    if [ "$lit" = 1 ]; then printf '%s' "$arg" >> "$D/buffer"; printf '%s' "$arg" >> "$D/typed"; exit 0; fi
    [ "$arg" = Enter ] || exit 0
    printf 'E\n' >> "$D/enters"
    n="$(cat "$D/stick" 2>/dev/null || echo 0)"
    if [ "$n" -gt 0 ] && { [ ! -f "$D/stick_match" ] || grep -qF "$(cat "$D/stick_match")" "$D/buffer" 2>/dev/null; }; then
      printf '%s\n' "$((n - 1))" > "$D/stick"
      grep -qF '.beads/' "$D/buffer" || printf '%s' '.beads/' >> "$D/buffer"
      exit 0
    fi
    cat "$D/buffer" >> "$D/transcript" 2>/dev/null; printf '\n' >> "$D/transcript"; : > "$D/buffer"
    exit 0 ;;
esac
exit 0
SH
chmod +x "$B/tmux"

n_enter() { [ -f "$D/enters" ] && wc -l < "$D/enters" | tr -d ' ' || echo 0; }
n_lit()   { grep -c -- ' -l ' "$D/log" 2>/dev/null || echo 0; }
no_esc()  { ! grep -qE 'send-keys .*(Escape|C-u)' "$D/log" 2>/dev/null; }
outl()    { tr '\n' ' ' < "$T/out" | cut -c1-240; }

# ① 끝 «— » + 개행 2개 → 친 글자 = 끝 공백·개행 없는 글 · 가운데 바이트 그대로 / 공백만 → rc2 · 친 글자 0
fresh; M1IN=$'줄1 #308313 가운데  두칸\n줄2 — \n\n'; M1EX=$'줄1 #308313 가운데  두칸\n줄2 —'
call_limited inject_message sess "$M1IN"
cmp -s "$D/typed" <(printf '%s' "$M1EX") \
  && ok "① 끝 «— »+개행 2개 → 친 글자 = 끝 공백·개행 없음 · 가운데 바이트 같음" \
  || bad "① typed=[$(od -An -c "$D/typed" 2>/dev/null | tr -s ' ' | tr '\n' ' ' | cut -c1-200)] rc=$RC"
fresh; call_limited inject_message sess $'  \t\n '
{ [ "$RC" = 2 ] && [ ! -s "$D/typed" ] && [ "$(n_enter)" = 0 ] && grep -q '빈 글' "$T/out"; } \
  && ok "① 공백만인 글 → rc=2 «빈 글» · 친 글자 0 · Enter 0" \
  || bad "① 빈 글 rc=$RC typed=$(wc -c < "$D/typed" 2>/dev/null) enters=$(n_enter) out=$(outl)"

# ② 상자가 Enter 1회에 비워짐 → state=submitted try=1 · Enter 1 · rc0
fresh; call_limited inject_message sess "pi 본문 한 줄"
{ [ "$RC" = 0 ] && grep -q 'state=submitted.*try=1' "$T/out" && [ "$(n_enter)" = 1 ]; } \
  && ok "② Enter 1회에 비워짐 → state=submitted try=1 · Enter 1 · rc=0" \
  || bad "② rc=$RC enters=$(n_enter) out=$(outl)"

# ③ 일하는 중 테두리 + Enter 1회째 꼬리 «.beads/» 붙고 남음 · 2회째 비워짐 → try=2 · Enter 2 · rc0
fresh; printf working > "$D/frame"; printf 1 > "$D/stick"
call_limited inject_message sess "골좌표: 6 #308375 #308382 하네스 운영 정리 —"
{ [ "$RC" = 0 ] && grep -q 'state=submitted.*try=2' "$T/out" && [ "$(n_enter)" = 2 ] && [ "$(n_lit)" = 1 ]; } \
  && ok "③ Working 테두리 · 꼬리 «.beads/» 1회 남음 → state=submitted try=2 · Enter 2 · rc=0" \
  || bad "③ rc=$RC enters=$(n_enter) lit=$(n_lit) out=$(outl)"

# ④ 3회 모두 남음 → state=stuck · Enter 3 · rc≠0 · 다시 치기 0 · Escape·C-u 0
fresh; printf 9 > "$D/stick"
call_limited inject_message sess "남는 본문 #1 #2"
{ [ "$RC" != 0 ] && [ "$RC" != 124 ] && grep -q 'state=stuck' "$T/out" && grep -q '제출 실패' "$T/out" \
  && [ "$(n_enter)" = 3 ] && [ "$(n_lit)" = 1 ] && no_esc; } \
  && ok "④ 3회 남음 → state=stuck «제출 실패» · Enter 3 · rc=$RC · 다시 치기·Escape 0" \
  || bad "④ rc=$RC enters=$(n_enter) lit=$(n_lit) out=$(outl)"

# ⑤ capture rc1 / 테두리 0개 → state=unverified · Enter 1 · rc0 · 쉼 테두리 + 빈 상자 → try=1
fresh; : > "$D/cap_rc1"; call_limited inject_message sess "codex 본문"
{ [ "$RC" = 0 ] && grep -q 'state=unverified' "$T/out" && [ "$(n_enter)" = 1 ]; } \
  && ok "⑤ capture rc1 → state=unverified · Enter 1 · rc=0" || bad "⑤ cap_rc1 rc=$RC enters=$(n_enter) out=$(outl)"
fresh; : > "$D/no_border"; call_limited inject_message sess "codex 본문"
{ [ "$RC" = 0 ] && grep -q 'state=unverified' "$T/out" && [ "$(n_enter)" = 1 ]; } \
  && ok "⑤ 테두리 0개 → state=unverified · Enter 1 · rc=0" || bad "⑤ no_border rc=$RC enters=$(n_enter) out=$(outl)"
fresh; printf idle > "$D/frame"; call_limited inject_message sess "쉼 상자 본문"
{ [ "$RC" = 0 ] && grep -q 'state=submitted.*try=1' "$T/out" && [ "$(n_enter)" = 1 ]; } \
  && ok "⑤ 쉼 테두리 2개 + 빈 상자 → state=submitted try=1" || bad "⑤ idle rc=$RC enters=$(n_enter) out=$(outl)"

# ⑥ open --agent pi --prompt — 부팅 문장 ②꼴 · 본문 ④꼴 → «부팅 문장 제출 실패 rc=» · rc≠0 / 둘 다 ②꼴 → stdout = 기준판과 바이트 같음
BASE_SHA=92c2dac2ae1606124bbf8f7746194c70b5ef95b6
OB="$T/obin"; mkdir -p "$OB" "$T/home" "$T/wt"; cp "$B/tmux" "$OB/tmux"
printf '#!/bin/sh\nexit 0\n' > "$OB/sleep"; chmod +x "$OB/sleep"   # 실 sleep 0
open_run() { # open_run <tmuxc> <결과 stdout 파일> → ORC
  rm -rf "$D"; mkdir -p "$D"; [ -n "${STICK:-}" ] && { printf '%s' "$STICK" > "$D/stick"; printf 'PROMPTBODY' > "$D/stick_match"; }
  env -i PATH="$OB:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$T/home" FAKE_AGENT_DIR="$D" FAKE_NOSESS=1 \
    bash "$1" open "$T/wt" --name T2059 --agent pi --prompt "PROMPTBODY 발주 #308375 본문" > "$2" 2> "$2.err"
  ORC=$?
}
STICK=9 open_run "$TMUXC" "$T/o6a"
{ [ "$ORC" -ne 0 ] && grep -q '부팅 문장 제출 실패 rc=' "$T/o6a" && ! grep -qx 'tmuxc session created' "$T/o6a"; } \
  && ok "⑥ open pi: 부팅 ②꼴 · 본문 ④꼴 → «부팅 문장 제출 실패» · rc=$ORC" \
  || bad "⑥ rc=$ORC out=$(tr '\n' ' ' < "$T/o6a" | cut -c1-200) err=$(tr '\n' ' ' < "$T/o6a.err" | cut -c1-200)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"
if [ -n "$ROOT" ] && git -C "$ROOT" cat-file -e "${BASE_SHA}:feature-pack/tmuxc/core/bin/tmuxc" 2>/dev/null; then
  mkdir -p "$T/base/core/bin" "$T/base/core/libexec"
  git -C "$ROOT" show "${BASE_SHA}:feature-pack/tmuxc/core/bin/tmuxc" > "$T/base/core/bin/tmuxc"
  git -C "$ROOT" show "${BASE_SHA}:feature-pack/tmuxc/core/libexec/agent-inject.sh" > "$T/base/core/libexec/agent-inject.sh"
  STICK='' open_run "$T/base/core/bin/tmuxc" "$T/o6base"; BRC=$ORC
  STICK='' open_run "$TMUXC" "$T/o6b"
  { [ "$ORC" = 0 ] && [ "$BRC" = 0 ] && cmp -s "$T/o6base" "$T/o6b" && grep -qx 'tmuxc session created' "$T/o6b"; } \
    && ok "⑥ open pi: 둘 다 ②꼴 → stdout 기준판(${BASE_SHA:0:8})과 바이트 같음 · rc=0" \
    || bad "⑥ 성공 출력 rc=$ORC base_rc=$BRC diff=$(diff "$T/o6base" "$T/o6b" | tr '\n' ' ' | cut -c1-200)"
else
  bad "⑥ 기준판 ${BASE_SHA:0:8} 을 못 읽어 성공 출력을 못 잰다(root=${ROOT:-none})"
fi

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS (mutate=$MUTATE)"; exit 0; }
echo "FAILED $fail (mutate=$MUTATE)"; exit 1
