#!/usr/bin/env bash
# test_opencode_reap.sh — r286: ft-opencode-reap.sh(좌석 나무·부모 잃은 serve·pid 파일 회수 · 남의 opencode 0) + 훅 opencode-reap-check.sh.
# 진짜 opencode 실행 0 — 스텁 = 이름이 opencode 인 bash 스크립트(sleep 루프) · tmux = 가짜(FT_TMUX_BIN) · 신호는 이 시험이 띄운 스텁에만.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REAP="${OC_REAP:-$HERE/../bin/ft-opencode-reap.sh}"
HOOK="$HERE/../kit/hooks/opencode-reap-check.sh"
T="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() { for p in $(ps -axww -o pid=,command= | awk -v s="$T/" 'index($0, s) {print $1}'); do kill -9 "$p" 2>/dev/null; done; rm -rf "$T"; }
trap cleanup EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:500}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «$2» ← ${1:0:300}";; *) ok "$3";; esac; }
alive() { kill -0 "$1" 2>/dev/null; }
dead()  { local i; for i in 1 2 3 4 5 6 7 8 9 10; do alive "$1" || return 0; sleep 0.2; done; return 1; }

mkdir -p "$T/stub" "$T/oc" "$T/wt/.git" "$T/wt/sub" "$T/else" "$T/pids"
cat > "$T/stub/opencode" <<'EOF'
#!/bin/bash
[ -n "${OC_PIDOUT:-}" ] && echo $$ > "$OC_PIDOUT"
[ "${STUB_NOTERM:-0}" = 1 ] && trap '' TERM
while :; do sleep 0.3; done
EOF
cat > "$T/tmux" <<'EOF'
#!/bin/bash
[ "$1" = list-panes ] || exit 0
[ -s "$FAKE_PANES" ] && { cat "$FAKE_PANES"; exit 0; }; echo "no server running on /tmp/fake"; exit 1
EOF
chmod +x "$T/stub/opencode" "$T/tmux"
export FT_OC_STATE_DIR="$T/oc" FT_TMUX_BIN="$T/tmux" FAKE_PANES="$T/panes"
S=$'\t'; ST="$T/stub/opencode"
# pane <이름> <cwd> [env…] — 가짜 pane 셸 1개 + 자식 opencode 둘(run · serve) · pid = $PANE · 자식 pid 파일 $T/pids/<이름>-{run,serve}
pane() { local n="$1" d="$2"; shift 2
  ( cd "$d" && exec env "$@" bash -c 'OC_PIDOUT="$1-run" "$0" run & OC_PIDOUT="$1-serve" "$0" serve & wait' "$ST" "$T/pids/$n" ) & PANE=$!
  local i; for i in $(seq 1 30); do [ -s "$T/pids/$n-run" ] && [ -s "$T/pids/$n-serve" ] && break; sleep 0.1; done; }
# orphan <이름> <cwd> — 부모가 곧 끝나 ppid 1 이 된 serve 스텁
orphan() { bash -c 'cd "$1" || exit 1; OC_PIDOUT="$2" nohup "$0" serve >/dev/null 2>&1 &' "$ST" "$2" "$T/pids/$1"   # 단순 명령 & = bash -c 의 직접 자식 · bash -c 가 곧 끝남 → ppid 1
  local i; for i in $(seq 1 30); do [ -s "$T/pids/$1" ] && [ "$(ps -o ppid= -p "$(cat "$T/pids/$1")" | tr -d ' ')" = 1 ] && return 0; sleep 0.1; done; echo "FAIL 시험 준비: $1 이 부모를 잃지 않음"; fail=$((fail+1)); }
pid() { cat "$T/pids/$1"; }

bash -n "$REAP" && ok "bash -n ft-opencode-reap.sh" || bad "bash -n ft-opencode-reap.sh"
bash -n "$HOOK" && ok "bash -n opencode-reap-check.sh" || bad "bash -n opencode-reap-check.sh"
out="$(bash "$REAP" 2>&1)"; [ $? -eq 2 ] && ok "인자 없음 → rc 2(usage)" || bad "인자 없음 rc≠2 ← $out"

echo "== 남의 opencode 셋 + 좌석 나무 + 좌석 워크트리 cwd 의 부모 잃은 serve"
orphan x1 "$T/else"                                   # ⓑ① 부모 잃음 · 다른 cwd
( cd "$T/else" && OC_PIDOUT="$T/pids/x2" exec "$ST" serve ) & X2P=$!   # ⓑ② 다른 부모(이 시험 셸) · 다른 cwd
pane other "$T/wt/sub"; OTHER=$PANE                   # ⓑ③ 다른 tmux 세션 나무 · cwd 는 좌석 워크트리 안
pane seat "$T/wt"; SEATP=$PANE
orphan o1 "$T/wt"                                     # ⓐ 부모 잃은 serve · cwd = 좌석 워크트리
for i in 1 2 3; do [ -s "$T/pids/x2" ] && break; sleep 0.2; done
printf 'seat#0%s%s\nother#0%s%s\n' "$S" "$SEATP" "$S" "$OTHER" > "$T/panes"
out="$(bash "$REAP" 'seat#0' --wt "$T/wt")"; rc=$?
[ $rc -eq 0 ] && has "$out" "pid=$(pid seat-run) via=①" "조사: 좌석 나무 run(①)" || bad "조사 rc=$rc"
has "$out" "pid=$(pid seat-serve) via=①" "조사: 좌석 나무 serve(①)"
has "$out" "pid=$(pid o1) via=③" "조사: 부모 잃은 serve · cwd ⊂ 워크트리(③)"
for x in x1 x2 other-run other-serve; do hasnt "$out" "pid=$(pid $x) " "조사: 남의 opencode($x) 후보 0"; done
alive "$(pid seat-run)" && ok "조사는 kill 0" || bad "조사가 프로세스를 죽였다"

echo "== ⓐ --apply → REAPED left=0 · ⓑ 남의 것 생존"
out="$(bash "$REAP" 'seat#0' --wt "$T/wt" --apply)"; rc=$?
[ $rc -eq 0 ] && has "$out" "REAPED seat#0 n=3 left=0 rc=0" "ⓐ REAPED n=3 left=0 rc 0" || bad "ⓐ rc=$rc ← $out"
for x in seat-run seat-serve o1; do dead "$(pid $x)" && ok "ⓐ $x 소멸" || bad "ⓐ $x 살아 있음"; done
for x in x1 x2 other-run other-serve; do alive "$(pid $x)" && ok "ⓑ 남의 opencode $x 생존" || bad "ⓑ 남의 opencode $x 가 죽었다"; done
hasnt "$out" "oc-kill pid=$SEATP " "ⓐ pane 셸(opencode 아님) 은 kill-session 몫 — 신호 0"
kill "$SEATP" 2>/dev/null; wait "$SEATP" 2>/dev/null

echo "== ⓒ TERM 무시 스텁 → KILL 로 left=0"
pane seat2 "$T/wt" STUB_NOTERM=1; P2=$PANE; printf 'seat2#0%s%s\n' "$S" "$P2" > "$T/panes"
out="$(bash "$REAP" 'seat2#0' --apply)"; rc=$?
[ $rc -eq 0 ] && has "$out" "left=0 rc=0" "ⓒ TERM 무시 → left=0 rc 0" || bad "ⓒ rc=$rc ← $out"
dead "$(pid seat2-serve)" && ok "ⓒ TERM 무시 serve 소멸(KILL)" || bad "ⓒ 살아 있음"
kill "$P2" 2>/dev/null; wait "$P2" 2>/dev/null

echo "== ⓓ 못 멈추면 rc 1 + oc-left 줄(FT_REAP_NOSIGNAL) · 닫기 FAIL 은 test_nano_close_fail_closed ⓗ"
pane seat3 "$T/wt"; P3=$PANE; printf 'seat3#0%s%s\n' "$S" "$P3" > "$T/panes"
out="$(FT_REAP_NOSIGNAL=1 bash "$REAP" 'seat3#0' --apply)"; rc=$?
[ $rc -eq 1 ] && has "$out" "REAPED seat3#0 n=0 left=2 rc=1" "ⓓ left=2 rc 1" || bad "ⓓ rc=$rc ← $out"
has "$out" "oc-left pid=$(pid seat3-serve)" "ⓓ oc-left 줄"
out="$(bash "$REAP" 'seat3#0' --apply)"; has "$out" "left=0 rc=0" "ⓓ 신호 켜고 다시 → left=0"
kill "$P3" 2>/dev/null; wait "$P3" 2>/dev/null

echo "== pid 파일: 스폰 기록 → 세션 사라짐(pane 셸 소멸 · cwd 밖) → 기록으로 회수 · 시작 시각 다르면 0"
pane seat4 "$T/else"; P4=$PANE; printf 'seat4#0%s%s\n' "$S" "$P4" > "$T/panes"
out="$(bash "$REAP" 'seat4#0' --record)"; has "$out" "oc-record seat4#0 n=2" "기록 n=2"
kill "$P4"; wait "$P4" 2>/dev/null; : > "$T/panes"; sleep 0.3
[ "$(ps -o ppid= -p "$(pid seat4-serve)" | tr -d ' ')" = 1 ] && ok "pane 셸 소멸 → serve 부모 잃음(ppid 1)" || bad "ppid ≠ 1"
out="$(bash "$REAP" 'seat4#0' --apply)"; rc=$?
[ $rc -eq 0 ] && has "$out" "left=0 rc=0" "pid 파일로 회수 left=0" || bad "pid 파일 회수 rc=$rc ← $out"
dead "$(pid seat4-serve)" && ok "기록된 serve 소멸" || bad "기록된 serve 살아 있음"
[ ! -f "$T/oc/seat4#0.pids" ] && ok "left=0 → pid 파일 삭제" || bad "pid 파일 남음"
printf '# since 0\n%s\tMon Jan  1 00:00:00 2001\torphan\n' "$(pid x1)" > "$T/fake.pids"
out="$(bash "$REAP" --pid-file "$T/fake.pids" --apply)"; has "$out" "left=0 rc=0" "시작 시각 다른 기록 → 대상 0"
alive "$(pid x1)" && ok "ⓑ pid 재사용 가드 — x1 생존" || bad "ⓑ 시작 시각 다른 x1 이 죽었다"

echo "== new: --since 뒤 뜬 부모 잃은 serve(cwd 밖) 는 기록되지만, 다른 opencode 가 살아 있으면 회수 때 건너뜀(공유)"
: > "$T/panes"; SINCE=$(( $(date +%s) - 1 )); orphan n1 "$T/else"
out="$(bash "$REAP" 'seat5#0' --record --since "$SINCE")"; has "$out" "oc-record seat5#0" "new 기록"
grep -q "^$(pid n1)${S}.*${S}new$" "$T/oc/seat5#0.pids" && ok "new 기록 줄(n1)" || bad "new 기록 줄 없음"
out="$(bash "$REAP" 'seat5#0' --apply)"; has "$out" "oc-skip pid=$(pid n1)" "다른 opencode 생존 → oc-skip"
alive "$(pid n1)" && ok "공유 의심 serve 생존" || bad "공유 의심 serve 가 죽었다"

echo "== ⓔ 훅: opencode 실행 뒤 고아 → 알림(kill 0) · 글자로만 든 opencode → 출력 0"
hk() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" | bash "$HOOK"; }
out="$(hk 'opencode run "hi"')"; rc=$?
[ $rc -eq 0 ] && has "$out" "opencode 고아" "ⓔ opencode run → 알림" || bad "ⓔ rc=$rc ← $out"
has "$out" "$(pid x1)" "ⓔ 알림에 고아 pid"; has "$out" "ft-opencode-reap.sh --pid-file $T/oc/orphans-" "ⓔ 회수 명령 = --pid-file"
alive "$(pid x1)" && ok "ⓔ 훅은 kill 0" || bad "ⓔ 훅이 죽였다"
for c in 'echo opencode' 'grep -n opencode notes.txt' 'git log --grep "opencode serve"' 'cat <<EOF
opencode run x
EOF'; do out="$(hk "$c")"; [ -z "$out" ] && ok "ⓔ 출력 0: ${c%%$'\n'*}" || bad "ⓔ «$c» → $out"; done
for c in 'cd /tmp && opencode run x' 'timeout 7 opencode run x' 'FOO=1 nohup opencode serve &' "bash -c 'opencode run x'"; do out="$(hk "$c")"; has "$out" "opencode 고아" "ⓔ 실행 자리 인식: $c"; done
out="$(printf '{"tool_name":"Read","tool_input":{"file_path":"opencode"}}' | bash "$HOOK")"; [ -z "$out" ] && ok "ⓔ Bash 아닌 도구 → 출력 0" || bad "ⓔ Read → $out"
out="$(printf 'not json' | bash "$HOOK" 2>&1)"; [ $? -eq 1 ] && has "$out" "opencode-reap-check: ERROR" "ⓔ 깨진 입력 → rc 1 + ERROR(조용한 통과 0)" || bad "ⓔ 깨진 입력 ← $out"

kill "$X2P" "$OTHER" 2>/dev/null
echo
[ "$fail" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILED $fail"; exit 1; }
