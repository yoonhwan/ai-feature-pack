#!/usr/bin/env bash
# test_tmuxc_pi_boot_wait_r2328.sh — r2328: tmuxc pi 좌석 부팅 글 = 입력 상자 뜬 뒤 주입(X1) · 전문 기록(X2) · boot-enter pi 갈래(X3) · 불변(X5).
#   사건: pi 좌석은 고정 sleep 4 뒤 부팅 글을 넣었다. load 가 높아 pi 화면이 늦게 그려지면 Enter 는 먼저 쓰이고 글만 입력창에 남았다.
#   가짜 pane = 실물 pi 1.5.2 capture 꼴(유휴 1 · 바쁨 1 · 카드 상태 줄 · 경로·숫자는 아무 글자) · 입력 글 = 줄마다 2칸 앞칸 + 폭 감김(DA#41 H1) · claude 상자 꼴(❯) 0.
#   가짜 tmux·sleep(시계만 민다) · 실 tmux·실 pi 0 · sleep 0 · 시험 대상 = env FT_TMUXC_PATH(기준판으로 돌리면 ①·③ 빨강).
#   칸: ① 상자 6초 뒤 → 주입 시각 ≥ 6 · 제출 · BOOT_TEXT = 넣은 전문 / ② 30초 안 안 뜸(빈 화면 · 바쁨) → 주입 0 · not-ready · rc≠0
#       ③ boot-enter 입력줄 = 전문 · 기록 없음 → Enter 1 · 기록 생김 · rc0 / ④ 다른 글자(고스트 제안 꼴) → Enter 0 · rc≠0
#       ⑤ 기록 이미 있음 → Enter 0 · rc0 / ⑦ claude·codex open → tmux·sleep 호출 기록 = 기준판과 같음(id 값만 지움)
#   변이(사본만 · 원본 대조 = 위 칸): M1 pi 대기 → 고정 sleep 4 (→ ① FAIL) · M2 완전 일치 → 앞 20자 비교 (→ ④ FAIL)
#                                    M4 pi 첫 줄 앞칸 벗김 지움 (→ ③ FAIL · DA#41 H1)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TMUXC="${FT_TMUXC_PATH:-$HERE/../core/bin/tmuxc}"
BASE_SHA=24d192abc33fee0756cdea818bd0549e612af542
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail + 1)); }
[ -f "$TMUXC" ] || { echo "FAIL 대상 없음: $TMUXC"; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
D="$T/state"; OB="$T/bin"; PIS="$T/pisess"; mkdir -p "$OB" "$T/home" "$T/wt"
NAME="byz-t-nano-r2328#1"
SID0="0f0e0d0c-1111-4222-8333-444455556666"

# ---------- 가짜 sleep(시계만 민다) · curl(헤드룸 없음) ----------
cat > "$OB/sleep" <<'SH'
#!/bin/sh
D="${FAKE_AGENT_DIR:?}"; printf 'sleep %s\n' "$1" >> "$D/log"
awk -v a="$(cat "$D/clock" 2>/dev/null || echo 0)" -v b="$1" 'BEGIN{printf "%.1f\n", a + b}' > "$D/clock.n" && mv "$D/clock.n" "$D/clock"
SH
printf '#!/bin/sh\nexit 1\n' > "$OB/curl"

# ---------- 가짜 tmux(pi 1.5.2 화면 꼴) ----------
#   mode = idle | busy | never(빈 화면) | clock(t<2 빈 화면 · t<READY_AT 바쁨 · 그 뒤 유휴)
#   첫 글자+Enter = 셸 명령(에이전트 기동) · 그 뒤 글자 = 입력창 buffer · Enter = 유휴 화면 ∧ buffer 있음일 때만 제출
#   제출 = pi 세션 기록 파일(FT_PI_SESSIONS_DIR/--wt--/<ts>_<id>.jsonl) · claude 는 TMUXC_CLAUDE_PROJECTS/-p/<id>.jsonl user 레코드
cat > "$OB/tmux" <<'SH'
#!/usr/bin/env bash
D="${FAKE_AGENT_DIR:?}"
printf 'tmux %s\n' "$*" >> "$D/log"
R80="$(printf '─%.0s' $(seq 1 80))"; R67="$(printf '─%.0s' $(seq 1 67))"
frame() {
  local t; t="$(cat "$D/clock" 2>/dev/null || echo 0)"
  case "$(cat "$D/mode" 2>/dev/null || echo idle)" in
    idle) echo idle ;; busy) echo busy ;; never) echo blank ;;
    clock) awk -v t="$t" -v r="${READY_AT:-6}" 'BEGIN{ if (t < 2) print "blank"; else if (t < r) print "busy"; else print "idle" }' ;;
  esac
}
# 실물 pi 1.5.2 입력 상자 꼴(DA#41 H1): 줄마다 왼쪽 2칸 · 폭 감김(낱말 경계 · 60글자) · 빈 상자 = 빈 줄
pi_box() { [ -f "$D/env_TMUXC_PI_SESSION_ID" ] || { cat "$D/buffer" 2>/dev/null; return; }; python3 -c 'import sys,textwrap;t=sys.argv[1];print("\n".join("  "+l for l in textwrap.wrap(t,60)) if t else "")' "$(cat "$D/buffer" 2>/dev/null)"; }
cmd="$1"; shift || true
case "$cmd" in
  has-session) [ "${FAKE_NOSESS:-0}" = 1 ] && exit 1; exit 0 ;;
  new-session)
    while [ $# -gt 0 ]; do case "$1" in -e) kv="$2"; printf '%s' "${kv#*=}" > "$D/env_${kv%%=*}"; shift 2 ;; *) shift ;; esac; done; exit 0 ;;
  set-environment) [ $# -ge 4 ] && printf '%s' "$4" > "$D/env_$3"; exit 0 ;;
  show-environment) key="${*: -1}"; [ -f "$D/env_$key" ] || exit 1; printf '%s=%s\n' "$key" "$(cat "$D/env_$key")"; exit 0 ;;
  display-message) echo fakeorch; exit 0 ;;
  list-panes) printf '%s|%%0\n' "${FAKE_NAME:-sess}"; exit 0 ;;
  capture-pane)
    case "$(frame)" in
      blank) printf '$ pi --session-id …\n' ;;
      busy)  printf ' Elapsed 0.0s\n\n\n── ⠋ Working %s\n\n%s\n~/wt …\n↑168 ↓31k … model-x • medium\n' "$R67" "$R80" ;;
      idle)  printf ' 앞 출력 1\n 앞 출력 2\n\n%s\n%s\n%s\n~/wt (nano/x) • R2328…\n↑92 ↓29k … model-x • medium\n' "$R80" "$(pi_box)" "$R80" ;;
    esac
    exit 0 ;;
  send-keys)
    lit=0; arg=""
    while [ $# -gt 0 ]; do case "$1" in -t) shift 2 ;; -l) lit=1; shift ;; *) arg="$1"; shift ;; esac; done
    if [ "$lit" = 1 ]; then
      if [ ! -f "$D/started" ]; then printf '%s' "$arg" > "$D/shellcmd"; exit 0; fi
      printf 'L %s\n' "$(cat "$D/clock" 2>/dev/null || echo 0)" >> "$D/lits"; printf '%s' "$arg" >> "$D/typed"; printf '%s' "$arg" >> "$D/buffer"; exit 0
    fi
    [ "$arg" = Enter ] || exit 0
    if [ ! -f "$D/started" ]; then : > "$D/started"; exit 0; fi
    if [ "$(frame)" != idle ] || [ ! -s "$D/buffer" ]; then echo lost >> "$D/enters"; exit 0; fi
    echo sub >> "$D/enters"
    if [ -f "$D/env_TMUXC_PI_SESSION_ID" ]; then
      mkdir -p "$FT_PI_SESSIONS_DIR/--wt--"
      printf '{"type":"session"}\n' > "$FT_PI_SESSIONS_DIR/--wt--/20261120T000000000Z_$(cat "$D/env_TMUXC_PI_SESSION_ID").jsonl"
    elif [ -f "$D/env_TMUXC_CLAUDE_SESSION_ID" ]; then
      mkdir -p "$TMUXC_CLAUDE_PROJECTS/-p"
      python3 -c 'import json,sys;print(json.dumps({"type":"user","message":{"content":sys.argv[1]}},ensure_ascii=False))' "$(cat "$D/buffer")" \
        >> "$TMUXC_CLAUDE_PROJECTS/-p/$(cat "$D/env_TMUXC_CLAUDE_SESSION_ID").jsonl"
    fi
    : > "$D/buffer"; exit 0 ;;
esac
exit 0
SH
chmod +x "$OB/sleep" "$OB/curl" "$OB/tmux"

fresh() { rm -rf "$D" "$PIS" "$T/proj"; mkdir -p "$D" "$PIS" "$T/proj"; printf '%s' "${1:-idle}" > "$D/mode"; echo 0 > "$D/clock"; }
run() {  # run <tmuxc> <out> [env…] -- <tmuxc 인자…> → RC
  local tx="$1" out="$2"; shift 2; local ev=()
  while [ "$1" != -- ]; do ev+=("$1"); shift; done; shift
  env -i PATH="$OB:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$T/home" FAKE_AGENT_DIR="$D" FAKE_NAME="$NAME" \
    FT_PI_SESSIONS_DIR="$PIS" TMUXC_CLAUDE_PROJECTS="$T/proj" TMUXC_SUBMIT_WAIT=1 ${ev[@]+"${ev[@]}"} \
    bash "$tx" "$@" > "$out" 2> "$out.err"
  RC=$?
}
n_lit()   { [ -f "$D/lits" ] && wc -l < "$D/lits" | tr -d ' ' || echo 0; }
n_enter() { [ -f "$D/enters" ] && wc -l < "$D/enters" | tr -d ' ' || echo 0; }
pi_file() { ls "$PIS"/*/*_"$1".jsonl 2>/dev/null | head -1; }
first_lit_t() { awk 'NR==1{print $2}' "$D/lits" 2>/dev/null; }
errl() { tr '\n' ' ' < "$1.err" | cut -c1-240; }

case_1() {  # case_1 <tmuxc> → C1 (0 = PASS)
  fresh clock; run "$1" "$T/o1" READY_AT=6 FAKE_NOSESS=1 -- open "$T/wt" --name "$NAME" --agent pi
  local t sid; t="$(first_lit_t)"; sid="$(cat "$D/env_TMUXC_PI_SESSION_ID" 2>/dev/null)"
  C1MSG="rc=$RC lit_t=${t:-none} lits=$(n_lit) enters=$(tr '\n' ',' < "$D/enters" 2>/dev/null) err=$(errl "$T/o1")"
  [ "$RC" = 0 ] && grep -qx 'tmuxc session created' "$T/o1" && [ -n "$t" ] \
    && awk -v t="$t" 'BEGIN{exit !(t >= 6)}' && [ -n "$(pi_file "$sid")" ] && [ ! -s "$D/buffer" ]
  C1=$?
}
# ① 상자가 6초 뒤 그려짐(2초까지 빈 화면 · 6초까지 바쁨) → 상자 뜬 뒤 주입 · 제출 · 고정 4초 주입 0
case_1 "$TMUXC"
[ "$C1" = 0 ] && ok "① 상자 6초 뒤 → 주입 시각 ≥ 6 · 제출(기록 파일) · 입력창 빔 · $C1MSG" || bad "① $C1MSG"
cmp -s "$D/env_TMUXC_BOOT_TEXT" "$D/typed" && grep -q 'tmuxc Pi 세션' "$D/typed" \
  && ok "① X2 TMUXC_BOOT_TEXT = 넣은 부팅 글 전문" || bad "① X2 BOOT_TEXT=[$(cut -c1-60 "$D/env_TMUXC_BOOT_TEXT" 2>/dev/null)]"

# ② 30초 안에 안 뜸 — 빈 화면 · 바쁨(Working) 둘 다 → 주입 0 · state=not-ready · rc≠0
for m in never busy; do
  fresh "$m"; run "$TMUXC" "$T/o2" FAKE_NOSESS=1 -- open "$T/wt" --name "$NAME" --agent pi
  { [ "$RC" != 0 ] && [ "$(n_lit)" = 0 ] && grep -q 'state=not-ready' "$T/o2.err" && grep -q '부팅 문장 제출 실패 rc=' "$T/o2" \
    && awk -v t="$(cat "$D/clock")" 'BEGIN{exit !(t >= 30 && t < 32)}'; } \
    && ok "② $m → 주입 0 · not-ready · rc=$RC · 시계 $(cat "$D/clock")초" \
    || bad "② $m rc=$RC lits=$(n_lit) clock=$(cat "$D/clock") err=$(errl "$T/o2")"
done

MSG="[fakeorch→$NAME] tmuxc Pi 세션. 통신 표준: ~/.agents/skills/tmuxc/COMM-GUIDE-BOOT.md(12줄)를 지금 read로 읽고 그대로 따를 것."
be_world() {  # be_world <입력줄 글자> [have_file]
  fresh idle; : > "$D/started"; printf '%s' "$SID0" > "$D/env_TMUXC_PI_SESSION_ID"; printf '%s' "$MSG" > "$D/env_TMUXC_BOOT_TEXT"
  printf '%s' "$1" > "$D/buffer"
  [ "${2:-}" = have_file ] && { mkdir -p "$PIS/--wt--"; : > "$PIS/--wt--/20261120T000000000Z_$SID0.jsonl"; }
  return 0
}
case_4() {  # case_4 <tmuxc> → C4
  be_world "${MSG:0:30} 자동완성 제안 꼬리"; run "$1" "$T/o4" -- boot-enter "$NAME"
  C4MSG="rc=$RC enters=$(n_enter) err=$(errl "$T/o4")"
  [ "$RC" != 0 ] && [ "$(n_enter)" = 0 ] && [ -z "$(pi_file "$SID0")" ]
  C4=$?
}
# ③ 입력줄 = 부팅 글 전문 · 기록 없음 → Enter 1 · 가짜 pi 가 기록 파일 씀 → rc0
#   입력 글 = 실물 꼴(줄마다 2칸 앞칸 · 60글자 감김 · DA#41 H1)
case_3() {  # case_3 <tmuxc> → C3
  be_world "$MSG"; run "$1" "$T/o3" -- boot-enter "$NAME"
  C3MSG="rc=$RC enters=$(n_enter) out=$(tr '\n' ' ' < "$T/o3") err=$(errl "$T/o3")"
  [ "$RC" = 0 ] && [ "$(n_enter)" = 1 ] && [ -n "$(pi_file "$SID0")" ] && grep -q 'state=submitted' "$T/o3"
  C3=$?
}
case_3 "$TMUXC"
[ "$C3" = 0 ] && ok "③ 전문(2칸 앞칸·감김) · 기록 없음 → Enter 1 · 기록 생김 · rc0" || bad "③ $C3MSG"
# ④ 다른 글자(앞 30자 같고 뒤가 고스트 제안 꼴) → Enter 0 · rc≠0
case_4 "$TMUXC"
[ "$C4" = 0 ] && ok "④ 고스트 제안 꼴 → Enter 0 · $C4MSG" || bad "④ $C4MSG"
# ⑤ 기록 파일 이미 있음 → Enter 0 · rc0
be_world "$MSG" have_file; run "$TMUXC" "$T/o5" -- boot-enter "$NAME"
{ [ "$RC" = 0 ] && [ "$(n_enter)" = 0 ]; } && ok "⑤ 기록 이미 있음 → Enter 0 · rc0" || bad "⑤ rc=$RC enters=$(n_enter) err=$(errl "$T/o5")"

# ⑦ claude·codex open → tmux·sleep 호출 기록 = 기준판과 같음(uuid 만 <ID>)
ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null)"
norm() { [ -s "$D/log" ] || { echo "NO-LOG"; return; }; sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/<ID>/g' "$D/log"; }
if [ -n "$ROOT" ] && git -C "$ROOT" cat-file -e "${BASE_SHA}:feature-pack/tmuxc/core/bin/tmuxc" 2>/dev/null; then
  mkdir -p "$T/base/core/bin" "$T/base/core/libexec"
  git -C "$ROOT" show "${BASE_SHA}:feature-pack/tmuxc/core/bin/tmuxc" > "$T/base/core/bin/tmuxc"
  git -C "$ROOT" show "${BASE_SHA}:feature-pack/tmuxc/core/libexec/agent-inject.sh" > "$T/base/core/libexec/agent-inject.sh"
  for ag in claude codex; do
    fresh idle; run "$T/base/core/bin/tmuxc" "$T/o7b" FAKE_NOSESS=1 -- open "$T/wt" --name "$NAME" --agent "$ag" --model m7; BRC=$RC; norm > "$T/l7b"
    fresh idle; run "$TMUXC" "$T/o7n" FAKE_NOSESS=1 -- open "$T/wt" --name "$NAME" --agent "$ag" --model m7; norm > "$T/l7n"
    { [ "$RC" = "$BRC" ] && ! grep -q NO-LOG "$T/l7n" && cmp -s "$T/l7b" "$T/l7n" && cmp -s "$T/o7b" "$T/o7n"; } \
      && ok "⑦ $ag open → 호출 기록·stdout 기준판(${BASE_SHA:0:8})과 같음 · rc=$RC" \
      || bad "⑦ $ag rc=$RC base=$BRC diff=$(diff "$T/l7b" "$T/l7n" | tr '\n' ' ' | cut -c1-240)"
  done
else
  bad "⑦ 기준판 ${BASE_SHA:0:8} 을 못 읽음(root=${ROOT:-none})"
fi

# 변이(사본만) — 위 칸이 원본 대조다
mutant() {  # mutant <이름> <python 치환 코드> [고칠 파일 = core 아래 경로] → MT(사본 tmuxc 경로) · 적용 실패 = 빈 값
  rm -rf "$T/mut"; mkdir -p "$T/mut"; cp -R "$(dirname "$TMUXC")/.." "$T/mut/core"
  MT="$T/mut/core/bin/tmuxc"
  python3 - "$T/mut/core/${3:-bin/tmuxc}" "$2" <<'PY' || MT=""
import sys
p, code = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
ns = {"s": s}; exec(code, ns)
if ns["s"] == s: sys.exit(1)
open(p, "w", encoding="utf-8").write(ns["s"])
PY
}
if grep -q '^pi_wait_input_box()' "$TMUXC"; then
  mutant M1 'o1 = "[[ \"$agent\" == \"claude\" || \"$agent\" == \"pi\" ]] || sleep 4\n"
o2 = "if [[ \"$agent\" == \"pi\" ]] && ! pi_wait_input_box \"$name\"; then"
assert s.count(o1) == 1 and s.count(o2) == 2
s = s.replace(o1, "[[ \"$agent\" == \"claude\" ]] || sleep 4\n").replace(o2, "if false; then")'
  if [ -n "$MT" ]; then case_1 "$MT"; [ "$C1" != 0 ] && ok "M1 pi 대기 → 고정 sleep 4 → ① FAIL 재현 · $C1MSG" || bad "M1 이 ① 에 안 잡힘 · $C1MSG"
  else bad "M1 적용 실패"; fi
  mutant M2 'i = s.index("boot_enter_pi() {")
o = "st=0; input_is_message \"$pane\" \"$text\" pilines || st=$?"
j = s.index(o, i)
s = s[:j] + "st=0; [[ \"$(capture_input_line \"$pane\" pilines | head -1)\" == \"${text:0:20}\"* ]] || st=1" + s[j + len(o):]'
  if [ -n "$MT" ]; then case_4 "$MT"; [ "$C4" != 0 ] && ok "M2 완전 일치 → 앞 20자 비교 → ④ FAIL 재현 · $C4MSG" || bad "M2 가 ④ 에 안 잡힘 · $C4MSG"
  else bad "M2 적용 실패"; fi
  mutant M4 'o = "        if (pi) sub(/^[[:space:]]+/, \"\", s)\n"
assert s.count(o) == 1
s = s.replace(o, "")' libexec/agent-inject.sh
  if [ -n "$MT" ]; then case_3 "$MT"; [ "$C3" != 0 ] && ok "M4 pi 첫 줄 앞칸 벗김 지움 → ③ FAIL 재현 · $C3MSG" || bad "M4 가 ③ 에 안 잡힘 · $C3MSG"
  else bad "M4 적용 실패"; fi
else
  bad "M1·M2·M4 대상 함수 없음(기준판)"
fi

echo "----"
[ "$fail" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $fail"; exit 1
