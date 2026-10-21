#!/usr/bin/env bash
# test_reboot_restore_r641.sh — r641: 재부팅 뒤 좌석 복구 1줄 도구 ft-reboot-restore.sh 시험 ⓐ~ⓘ.
#   ⓐ 스냅샷 2석 → tmux 세션 2개 · 래퍼 인자·세션 환경 FT_SEAT·시작 셸 zsh -l·cwd ⓑ 확인표(이름·결과·pid·8317 O/X·uuid) · X 면 rc 3
#   ⓒ 살아 있는 세션 = SKIP(열기·보내기 0) ⓓ 대화 파일 없음 = FAIL 1줄 · 다른 좌석은 계속 ⓔ 끝난 나노(rested rc 0) = SKIP
#   ⓕ 스냅샷 없음·깨짐 → seat-live(effort 기본 high) · 둘 다 없음 = ERROR rc 2 ⓖ 병렬 상한 4 · 기동 확인 상한 넘으면 FAIL · 원장 줄
#   ⓗ --dry-run = 세션 0 · tmuxc restore 계획 모드 출력 맨 위 안내 1줄
#   ⓘ r626 전팀 정지 켜짐 = 세션 0 · rc 1 · 그 REJECT 줄 그대로(변이: 검사 줄 삭제 → 이 칸 FAIL)
# 전부 mktemp 안 — 임시 HOME(스냅샷·seat-live·projects·가짜 claude-hr.sh) · 임시 FT_ROOT ·
#   ★tmux 는 격리 소켓(-L ftrr-test-<pid>) 셔임을 PATH 앞에 — 사용자 tmux 서버의 세션은 보지도 건드리지도 않는다(실좌석 kill·send-keys 0)★.
# base 대조: R641_BIN=<origin/main 판 키트 bin 폴더> bash <이 파일> — 그 폴더에 ft-reboot-restore.sh 가 없으면 전부 FAIL.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY TMUX TMUX_PANE
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."; BIN="${R641_BIN:-$REPO/harness/kit/fable-team/bin}"; TMUXC="$REPO/../tmuxc/core/bin/tmuxc"
TOOL="$BIN/ft-reboot-restore.sh"
RT="$(command -v tmux)"; SOCK="ftrr-test-$$"
T="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() {
  "$RT" -L "$SOCK" list-sessions -F '#{session_name}' 2>/dev/null | while IFS= read -r s; do "$RT" -L "$SOCK" kill-session -t "=$s" 2>/dev/null; done
  [ -f "$T/pids" ] && while read -r p; do kill "$p" 2>/dev/null; done < "$T/pids"
  rm -f "${TMUX_TMPDIR:-/tmp}/tmux-$(id -u)/$SOCK"; rm -rf "$T"   # 서버가 끝나도 남는 격리 소켓 파일
}
trap cleanup EXIT
fail=0
ok()   { echo "PASS $1"; }
bad()  { echo "FAIL $1"; fail=$((fail+1)); }
eq()   { [ "$1" = "$2" ] && ok "$3" || bad "$3 — «${1}» ≠ «${2}»"; }
has()  { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «${2}» ← ${1:0:400}";; esac; }
hasnt(){ case "$1" in *"$2"*) bad "$3 — 있으면 안 됨: «${2}»";; *) ok "$3";; esac; }

# ── 격리 tmux · 임시 HOME · 가짜 헤드룸 래퍼 ──
F="$T/fake"; H="$T/home"; export HOME="$H" FT_ROOT="$T/root"
mkdir -p "$F" "$H/.tmuxc/snapshots" "$H/.claude/state/seat-live" "$H/.claude/projects" "$H/.headroom" "$FT_ROOT/.fable-team/state"
# r626: 꺼짐 증거 = 정지 원장의 init 줄 — 상태 폴더만 있고 원장이 없으면 ft-all-stop 은 «정지» 로 본다(상태 폴더 없음 = hard).
FT_ROOT="$FT_ROOT" bash "$BIN/ft-all-stop.sh" init > /dev/null 2>&1 || bad "r626 정지 원장 init"
: > "$H/.zshrc"; : > "$H/.zshenv"
printf '#!/bin/bash\nexec %q -L %q "$@"\n' "$RT" "$SOCK" > "$F/tmux"; chmod +x "$F/tmux"; export PATH="$F:$PATH"
cat > "$H/.headroom/claude-hr.sh" <<EOF
#!/bin/bash
n="\$FT_SEAT"; printf '%s\n' "\$@" > "$T/args.\$n"; pwd -P > "$T/cwd.\$n"; echo "\$\$" >> "$T/pids"
python3 -c 'import time;print("S",time.time())' >> "$T/conc.\$n"
sleep "\$(cat "$T/hold.\$n" 2>/dev/null || cat "$T/hold" 2>/dev/null || echo 0)"
python3 -c 'import time;print("E",time.time())' >> "$T/conc.\$n"
exec env ANTHROPIC_BASE_URL="\$(cat "$T/url.\$n" 2>/dev/null || echo http://127.0.0.1:8317)" python3 -c 'import time; time.sleep(300)'
EOF
# ★자식은 /bin/sleep 아님 — macOS 는 시스템 바이너리의 환경을 ps eww 로 안 보여 준다(실측) · claude 처럼 사용자 바이너리(python3)로★
chmod +x "$H/.headroom/claude-hr.sh"
enc() { python3 -c 'import re,sys;print(re.sub("[^A-Za-z0-9]","-",sys.argv[1]))' "$1"; }
jsonl_of() { echo "$H/.claude/projects/$(enc "$T/cwd-$1")/$2.jsonl"; }
mkseat() {   # <이름> <uuid> [jsonl 만들기 1|0]
  mkdir -p "$T/cwd-$1"; [ "${3:-1}" = 1 ] || return 0
  mkdir -p "$(dirname "$(jsonl_of "$1" "$2")")"; echo '{"type":"user"}' > "$(jsonl_of "$1" "$2")"
}
snap() {   # snap <이름:uuid> ... → latest.json (claude · model claude-opus-5-5[1m] · effort xhigh)
  python3 - "$H/.tmuxc/snapshots/latest.json" "$T" "$@" <<'PY'
import json, sys
out, t, rows = sys.argv[1], sys.argv[2], sys.argv[3:]
ss = [dict(name=n, cwd=f"{t}/cwd-{n}", agent="claude", model="claude-opus-5-5[1m]", effort="xhigh", session_id=u) for n, u in (r.split(":") for r in rows)]
ss.append(dict(name="ftrr-test-shell", cwd=t, agent="shell"))
json.dump(dict(schema=1, created_at="2026-10-21T05:28:01Z", host="t", session_count=len(ss), sessions=ss), open(out, "w"))
PY
}
alive() { tmux has-session -t "=$1" 2>/dev/null; }
reset_tmux() { tmux list-sessions -F '#{session_name}' 2>/dev/null | while IFS= read -r s; do tmux kill-session -t "=$s"; done; rm -f "$T"/args.* "$T"/conc.*; }
run() { OUT="$(bash "$TOOL" "$@" 2>&1)"; RC=$?; }

if [ -f "$TOOL" ]; then bash -n "$TOOL" && ok "bash -n ft-reboot-restore.sh" || bad "bash -n ft-reboot-restore.sh"; else bad "도구 없음 $TOOL"; fi
[ -z "${R641_BIN:-}" ] && { cmp -s "$TOOL" "$REPO/harness/bin/ft-reboot-restore.sh" && ok "harness/bin 사본 cmp 0" || bad "harness/bin 사본 어긋남"; }

# ⓐ 스냅샷 2석 → 두 세션 · 래퍼 인자·환경·셸·cwd
A=ftrr-test-a; B=ftrr-test-b; UA=11111111-aaaa-4000-8000-000000000001; UB=22222222-bbbb-4000-8000-000000000002
mkseat $A $UA; mkseat $B $UB; snap "$A:$UA" "$B:$UB"
run
eq "$RC" 0 "ⓐ rc 0"
alive $A && alive $B && ok "ⓐ 세션 2개 생김" || bad "ⓐ 세션 2개 생김"
eq "$(tr '\n' ' ' < "$T/args.$A" 2>/dev/null)" "--dangerously-skip-permissions --model claude-opus-5-5[1m] --effort xhigh --resume $UA --name $A " "ⓐ 래퍼 인자(a)"
eq "$(tr '\n' ' ' < "$T/args.$B" 2>/dev/null)" "--dangerously-skip-permissions --model claude-opus-5-5[1m] --effort xhigh --resume $UB --name $B " "ⓐ 래퍼 인자(b)"
eq "$(tmux show-environment -t "=$A" FT_SEAT 2>/dev/null)" "FT_SEAT=$A" "ⓐ 세션 환경 FT_SEAT"
has "$(tmux display -p -t "=$A:" '#{pane_start_command}' 2>/dev/null)" "zsh -l" "ⓐ 시작 셸 zsh -l"
eq "$(cat "$T/cwd.$A" 2>/dev/null)" "$T/cwd-$A" "ⓐ cwd = 행의 cwd"
hasnt "$(tmux list-sessions -F '#{session_name}' 2>/dev/null)" "ftrr-test-shell" "ⓐ shell 행은 좌석 아님(열기 0)"
# ⓑ 확인표 · 8317 X → rc 3
has "$OUT" "$A · OK · " "ⓑ 표 줄(a OK)"
[[ "$OUT" =~ $A\ ·\ OK\ ·\ [0-9]+\ ·\ O\ ·\ $UA ]] && ok "ⓑ 표 줄 = 이름·결과·pid·8317 O·uuid" || bad "ⓑ 표 줄 꼴 — $OUT"
reset_tmux; echo "http://localhost:8790" > "$T/url.$B"
run
eq "$RC" 3 "ⓑ 8317 X 하나 → rc 3"
[[ "$OUT" =~ $B\ ·\ OK\ ·\ [0-9]+\ ·\ X\ · ]] && ok "ⓑ b 줄 8317 X" || bad "ⓑ b 줄 8317 X — $OUT"
rm -f "$T/url.$B"
# ⓒ 살아 있는 세션 = SKIP · 래퍼 호출 0
rm -f "$T"/args.*
run
eq "$RC" 0 "ⓒ rc 0"
has "$OUT" "$A · SKIP 살아 있음" "ⓒ a SKIP 살아 있음"
[ ! -e "$T/args.$A" ] && [ ! -e "$T/args.$B" ] && ok "ⓒ 래퍼 호출 0(send-keys 0)" || bad "ⓒ 래퍼가 다시 불림"
# ⓓ 대화 파일 없음 = FAIL · 다른 좌석은 계속
reset_tmux; rm -f "$(jsonl_of $A $UA)"
run
eq "$RC" 3 "ⓓ FAIL 있음 → rc 3"
has "$OUT" "$A · FAIL 대화 파일 없음" "ⓓ a FAIL 대화 파일 없음"
alive $A && bad "ⓓ a 세션 열림" || ok "ⓓ a 세션 열기 0"
alive $B && ok "ⓓ b 는 계속 열림" || bad "ⓓ b 안 열림"
# ⓔ 끝난 나노 = SKIP · 같은 기록이라도 나노 아닌 좌석은 연다
reset_tmux; N=ftrr-test-nano-a; UN=33333333-cccc-4000-8000-000000000003; mkseat $N $UN; mkseat $A $UA
python3 -c 'import json,sys
f=open(sys.argv[1],"w")
for r in ({"type":"assistant","message":{"content":"[완료·휴식] 끝"}},{"type":"system","subtype":"turn_duration"}): f.write(json.dumps(r,ensure_ascii=False)+"\n")' "$(jsonl_of $N $UN)"
cp "$(jsonl_of $N $UN)" "$(jsonl_of $A $UA)"
snap "$N:$UN" "$A:$UA"
run
has "$OUT" "$N · SKIP 끝난 나노" "ⓔ 끝난 나노 SKIP"
alive $N && bad "ⓔ 끝난 나노 세션 열림" || ok "ⓔ 끝난 나노 열기 0"
alive $A && ok "ⓔ 나노 아닌 좌석은 열림" || bad "ⓔ 나노 아닌 좌석 안 열림"
eq "$RC" 0 "ⓔ rc 0"
# ⓕ 스냅샷 없음·깨짐 → seat-live · 둘 다 없음 = ERROR rc 2
reset_tmux; rm -f "$H/.tmuxc/snapshots/latest.json"
python3 -c 'import json,sys;json.dump(dict(name=sys.argv[1],engine="claude",uuid=sys.argv[2],jsonl=sys.argv[3],cwd=sys.argv[4],model="claude-sonnet-5-5[1m]"),open(sys.argv[5],"w"))' \
  $A $UA "$(jsonl_of $A $UA)" "$T/cwd-$A" "$H/.claude/state/seat-live/$A.json"
run
eq "$RC" 0 "ⓕ seat-live rc 0"
has "$OUT" "출처=seat-live" "ⓕ 로그 출처=seat-live"
has "$(cat "$FT_ROOT/.fable-team/state/reboot-restore.log" 2>/dev/null)" "출처=seat-live" "ⓕ 원장 출처=seat-live"
has "$(tr '\n' ' ' < "$T/args.$A" 2>/dev/null)" "--model claude-sonnet-5-5[1m] --effort high " "ⓕ effort 기본 high"
reset_tmux; echo '{' > "$H/.tmuxc/snapshots/latest.json"
run
has "$OUT" "출처=seat-live" "ⓕ 깨진 스냅샷 → seat-live"
reset_tmux; rm -f "$H/.tmuxc/snapshots/latest.json" "$H"/.claude/state/seat-live/*.json
run
eq "$RC" 2 "ⓕ 둘 다 없음 rc 2"
has "$OUT" "ERROR" "ⓕ ERROR 줄"
# ⓖ 병렬 상한 4 · 기동 확인 상한 · 원장 좌석별 줄
reset_tmux; : > "$FT_ROOT/.fable-team/state/reboot-restore.log"; G=()
for i in 1 2 3 4 5 6; do n=ftrr-test-g$i; u=4444444$i-dddd-4000-8000-00000000000$i; mkseat $n $u; G+=("$n:$u"); done
snap "${G[@]}"; echo 2 > "$T/hold"
run
eq "$RC" 0 "ⓖ 6석 rc 0"
MAXC="$(python3 - "$T" <<'PY'
import glob, sys
ev = []
for f in glob.glob(sys.argv[1] + "/conc.*"):
    for l in open(f): k, t = l.split(); ev.append((float(t), 1 if k == "S" else -1))
cur = top = 0
for _, d in sorted(ev, key=lambda e: (e[0], e[1])): cur += d; top = max(top, cur)
print(top)
PY
)"
[ "${MAXC:-0}" -le 4 ] && [ "${MAXC:-0}" -ge 2 ] && ok "ⓖ 동시 래퍼 수 2..4 (=${MAXC})" || bad "ⓖ 동시 래퍼 수 ${MAXC}"
eq "$(grep -c ' OK ' "$FT_ROOT/.fable-team/state/reboot-restore.log")" 6 "ⓖ 원장 좌석별 OK 6줄"
reset_tmux; rm -f "$T/hold"; echo 6 > "$T/hold.ftrr-test-g1"; snap "${G[0]}"
OUT="$(FT_RR_WAIT=2 bash "$TOOL" 2>&1)"; RC=$?
eq "$RC" 3 "ⓖ 기동 확인 없음 rc 3"
has "$OUT" "ftrr-test-g1 · FAIL 기동 확인 없음" "ⓖ FAIL 기동 확인 없음"
has "$(cat "$FT_ROOT/.fable-team/state/reboot-restore.log")" "ftrr-test-g1 FAIL" "ⓖ 원장 FAIL 줄"
# ⓗ --dry-run = 세션 0 · tmuxc restore 맨 위 안내 1줄
reset_tmux; rm -f "$T/hold.ftrr-test-g1"; mkseat $A $UA; mkseat $B $UB; snap "$A:$UA" "$B:$UB"
run --dry-run
eq "$RC" 0 "ⓗ dry-run rc 0"
has "$OUT" "$A · 계획 열기" "ⓗ 계획 표"
alive $A || alive $B && bad "ⓗ dry-run 이 세션을 열었다" || ok "ⓗ dry-run 세션 0"
[ ! -e "$T/args.$A" ] && ok "ⓗ dry-run 래퍼 호출 0" || bad "ⓗ dry-run 래퍼 호출"
TOP="$(bash "$TMUXC" restore < /dev/null 2>&1 | head -1)"
has "$TOP" "tmuxc restore --select all --go" "ⓗ tmuxc restore 맨 위 실행 안내"
has "$TOP" "ft-reboot-restore.sh" "ⓗ tmuxc restore 맨 위 많으면 안내"
alive $A && bad "ⓗ tmuxc restore 계획 모드가 세션을 열었다" || ok "ⓗ tmuxc restore 동작 변경 0(계획만)"

# ⓘ r626 전팀 정지 켜짐 = 새 세션 0 · rc 1 · 그 REJECT 줄 그대로
reset_tmux; rm -f "$T"/args.*; mkseat $A $UA; mkseat $B $UB; snap "$A:$UA" "$B:$UB"
printf '{"since":1761000000,"by":"r641-test","reason":"시험"}\n' > "$FT_ROOT/.fable-team/state/ALL_STOP.json"
run
eq "$RC" 1 "ⓘ 정지 켜짐 rc 1"
has "$OUT" "REJECT 전팀 정지 중(" "ⓘ 그 REJECT 줄 그대로"
hasnt "$OUT" "REBOOT-RESTORE" "ⓘ 정지면 좌석 표도 안 냄"
alive $A || alive $B && bad "ⓘ 정지인데 세션 열림" || ok "ⓘ 정지 새 세션 0"
[ ! -e "$T/args.$A" ] && [ ! -e "$T/args.$B" ] && ok "ⓘ 정지 래퍼 호출 0" || bad "ⓘ 정지인데 래퍼 호출"
rm -f "$FT_ROOT/.fable-team/state/ALL_STOP.json"
run --dry-run
eq "$RC" 0 "ⓘ 정지 끄면 --dry-run 다시 rc 0"

echo "== r641 fail=$fail"
[ "$fail" -eq 0 ] && echo "ALL PASS" || exit 1
