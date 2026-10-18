#!/usr/bin/env bash
# test_spawn_agent_ready.sh — R251: ft-nano-spawn 이 «좌석(tmux)은 떴는데 에이전트 본체가 안 뜬» 경우를 거짓 SPAWNED 로 넘기지 않는다.
# 실 좌석·tmux 서버·네트워크 0 — 가짜 pane = bash -c 프로세스 트리 · 가짜 프록시 = 임시 포트 · tmux 는 PATH 가짜.
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
TRK="$HERE/../../scripts/fable-team-bin"
KIT="$HERE/../../scripts/harness-install/fable-team/bin"
DB="$HERE/../../tools/comm-canonical/mbox_doorbell.sh"; AL="$HERE/../../tools/comm-canonical/ft-agent-alive.sh"   # R346: 본체 판별 함수는 판정기 파일로 이사
T="$(cd "$(mktemp -d)" && pwd -P)"; PIDS=()
kill_tree() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do kill_tree "$c"; done; kill "$1" 2>/dev/null; }
trap 'for p in ${PIDS[@]+"${PIDS[@]}"}; do kill_tree "$p"; done; rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
has() { case "$1" in *"$2"*) ok "$3";; *) bad "$3 — 없음: «$2» ← ${1:0:300}";; esac; }
RDY="$TRK/ft-agent-ready.sh"

mkdir -p "$T/bin"
for n in claude claude-hr.sh codex; do printf '#!/bin/bash\nsleep 30\n' > "$T/bin/$n"; chmod +x "$T/bin/$n"; done
# mkpane "<셸 명령>" → PANE_PID (가짜 pane 프로세스 = bash -c)
mkpane() { bash -c "$1 & wait" & PANE_PID=$!; PIDS+=("$PANE_PID"); sleep 0.4; }
C="$T/bin/claude --dangerously-skip-permissions"

echo "== ⓐⓑⓒ 프록시 확인"
ROUTE='printf "  headroom : off\n  cliproxy : on\n"'
S=$SECONDS; out="$(FT_ROUTE_STATUS_CMD="$ROUTE" FT_PROXY_PROBE_URL=http://127.0.0.1:9/v1/models bash "$RDY" --proxy "$T" --agent claude 2>"$T/err")"; rc=$?
[ "$rc" -ne 0 ] && has "$out" "REJECT 프록시" "ⓐ 닫힌 포트 → REJECT 프록시 rc≠0" || bad "ⓐ rc=$rc ← $out"
[ "$(grep -c '시도' "$T/err")" -eq 2 ] && ok "ⓐ 시도 2회" || bad "ⓐ 시도 줄 $(grep -c '시도' "$T/err")"
[ $((SECONDS - S)) -le 8 ] && ok "ⓐ 경과 ≤ 8 s ($((SECONDS - S)) s)" || bad "ⓐ 경과 $((SECONDS - S)) s"
PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')"
mkdir -p "$T/srv/v1"; echo '{}' > "$T/srv/v1/models"
( sleep 1; cd "$T/srv" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 ) & PIDS+=("$!")
out="$(FT_ROUTE_STATUS_CMD="$ROUTE" FT_PROXY_PROBE_URL="http://127.0.0.1:$PORT/v1/models" bash "$RDY" --proxy "$T" --agent claude 2>"$T/err")"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓑ 첫 시도 실패·둘째 성공 → rc0" || bad "ⓑ rc=$rc ← $out"
[ "$(grep -c '시도' "$T/err")" -eq 1 ] && ok "ⓑ 실패 시도 1회만 기록" || bad "ⓑ 시도 줄 $(grep -c '시도' "$T/err")"
out="$(FT_ROUTE_STATUS_CMD='printf "  headroom : off\n  cliproxy : off\n"' FT_PROXY_PROBE_URL=http://127.0.0.1:9/v1/models bash "$RDY" --proxy "$T" --agent claude 2>"$T/err")"; rc=$?
[ "$rc" -eq 0 ] && [ ! -s "$T/err" ] && ok "ⓒ 직결 경유 → 확인 호출 0 · rc0" || bad "ⓒ rc=$rc err=$(cat "$T/err")"
FT_ROUTE_STATUS_CMD=false bash "$RDY" --proxy "$T" --agent codex >/dev/null 2>&1 && ok "ⓒ codex → 확인 0 · rc0" || bad "ⓒ codex"
FT_ROUTE_STATUS_CMD=false bash "$RDY" --proxy "$T" --agent claude >/dev/null 2>&1; [ $? -ne 0 ] && ok "ⓒ 경유 판독 실패 → 조용한 통과 0" || bad "ⓒ 판독 실패가 통과"

echo "== ⓓ~ⓗ 에이전트 본체 확인"
mkpane "$C"; out="$(bash "$RDY" --pid "$PANE_PID" --agent claude --wait 1)"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "READY" "ⓓ claude 본체 → READY rc0" || bad "ⓓ rc=$rc ← $out"
mkpane "sleep 30"; out="$(bash "$RDY" --pid "$PANE_PID" --agent claude --wait 1)"; rc=$?
[ "$rc" -eq 3 ] && has "$out" "NOAGENT" "ⓔ sleep 자식뿐 → NOAGENT rc3" || bad "ⓔ rc=$rc ← $out"
mkpane "$T/bin/claude-hr.sh --dangerously-skip-permissions"; out="$(bash "$RDY" --pid "$PANE_PID" --agent claude --wait 1)"; rc=$?
[ "$rc" -eq 3 ] && ok "ⓕ 래퍼(claude-hr.sh)만 → NOAGENT (래퍼를 본체로 세지 않음)" || bad "ⓕ rc=$rc ← $out"
mkpane "$T/bin/claude-hr.sh --dangerously-skip-permissions & sleep 1; $C"; out="$(bash "$RDY" --pid "$PANE_PID" --agent claude --wait 5)"; rc=$?
pid="${out#READY }"; pid="${pid%% *}"
[ "$rc" -eq 0 ] && case "$(ps -o args= -p "$pid" 2>/dev/null)" in *claude-hr*) bad "ⓕ READY pid 가 래퍼";; *) ok "ⓕ 래퍼 뒤 본체가 뜨면 READY(pid=본체)";; esac || bad "ⓕ 지연 기동 rc=$rc ← $out"
mkpane "$T/bin/codex --dangerously-bypass-approvals-and-sandbox"; out="$(bash "$RDY" --pid "$PANE_PID" --agent codex --wait 1)"; rc=$?
[ "$rc" -eq 0 ] && ok "ⓖ codex 본체 → READY" || bad "ⓖ rc=$rc ← $out"
bash "$RDY" --pid "$PANE_PID" --agent claude --wait 1 >/dev/null; [ $? -eq 3 ] && ok "ⓖ codex pane 을 claude 로 보면 NOAGENT" || bad "ⓖ 교차 판정"
for n in myapp npm; do printf '#!/bin/bash\nsleep 30\n' > "$T/bin/$n"; chmod +x "$T/bin/$n"; done
mkpane "$T/bin/myapp --use-codex"; bash "$RDY" --pid "$PANE_PID" --agent codex --wait 1 >/dev/null; [ $? -eq 3 ] && ok "ⓖ 'myapp --use-codex' → NOAGENT (부분 일치 오판 0)" || bad "ⓖ 부분 일치 오판"
mkpane "$T/bin/npm exec @openai/codex --dangerously-bypass-approvals-and-sandbox"; bash "$RDY" --pid "$PANE_PID" --agent codex --wait 1 >/dev/null; [ $? -eq 0 ] && ok "ⓖ 'npm exec @openai/codex' → READY" || bad "ⓖ npm exec"
mkpane "$T/bin/codex"; bash "$RDY" --pid "$PANE_PID" --agent codex --wait 1 >/dev/null; [ $? -eq 0 ] && ok "ⓖ 경로 끝 /codex 단독 토큰 → READY" || bad "ⓖ 단독 codex"
mkpane "sleep 30"; bash "$RDY" --pid "$PANE_PID" --agent cmd --wait 1 >/dev/null; [ $? -eq 0 ] && ok "ⓖ 모르는 에이전트(cmd) = 기존 «아무 자식» 규칙" || bad "ⓖ cmd"
R="$T/bin/claude --resume 0d4c8f2e-1111-2222-3333-444455556666 --model claude-sonnet-5-5"
mkpane "$R"; bash "$RDY" --pid "$PANE_PID" --agent claude --wait 1 >/dev/null; [ $? -eq 0 ] && ok "ⓘ R335 복구형 claude --resume <uuid> --model → READY" || bad "ⓘ resume 형 본체 불인정"
mkpane "$T/bin/claude-hr.sh --resume 0d4c8f2e-1111-2222-3333-444455556666"; bash "$RDY" --pid "$PANE_PID" --agent claude --wait 1 >/dev/null; [ $? -eq 3 ] && ok "ⓘ R335 래퍼(claude-hr.sh) + --resume → NOAGENT" || bad "ⓘ 래퍼 resume 오판"
mkpane "$T/bin/myapp --daemon --resumable"; bash "$RDY" --pid "$PANE_PID" --agent claude --wait 1 >/dev/null; [ $? -eq 3 ] && ok "ⓘ R335 데몬(--resumable 비슷한 글자) → NOAGENT" || bad "ⓘ 데몬 오판"
printf '#!/bin/bash\nsleep 30\n' > "$T/bin/tmux"; printf '#!/bin/bash\nsleep 30\n' > "$T/bin/git"; chmod +x "$T/bin/tmux" "$T/bin/git"
for neg in "$T/bin/myapp --resume job-1" "$T/bin/tmux --resume=x" "$T/bin/git log --resume" "$T/bin/myapp claude-notes --resume job-1"; do
  mkpane "$neg"; bash "$RDY" --pid "$PANE_PID" --agent claude --wait 1 >/dev/null; [ $? -eq 3 ] && ok "ⓘ R335 DA⑥ 음성(claude 토큰 없음/뒤 아님) «${neg#$T/bin/}» → NOAGENT" || bad "ⓘ R335 DA⑥ 음성 오인정 «${neg#$T/bin/}»"
done
out="$(FT_PS_CMD=false bash "$RDY" --pid "$PANE_PID" --agent claude --wait 1 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && has "$out" "ERROR" "ⓗ ps 실패 → ERROR rc1 (조용한 READY 0)" || bad "ⓗ rc=$rc ← $out"
out="$(FT_PS_CMD=false bash "$RDY" --pid "$PANE_PID" --agent cmd --wait 1 2>&1)"; rc=$?
[ "$rc" -eq 1 ] && ok "ⓗ cmd 도 ps 실패 → ERROR" || bad "ⓗ cmd rc=$rc"

echo "== ⓘ spawn 정적 검사 (줄 순서)"
SP="$TRK/ft-nano-spawn.sh"
ln() { grep -n -F -- "$1" "$SP" | head -1 | cut -d: -f1; }
l_px="$(ln 'ft-agent-ready.sh" --proxy')"; l_wt="$(ln 'worktree add "$WTDIR"')"
l_sess="$(ln 'tmux has-session -t "=$NAME"')"; l_pane="$(ln 'ft-agent-ready.sh" --pane')"; l_roe="$(ln 'set-option -t "$PANE" remain-on-exit on')"
l_reg="$(ln 'python3 - "$SEATS"')"; l_mv="$(ln 'ft-index-move.sh" "$IDX"')"; l_snd="$(ln 'ft-send-verified.sh" "$NAME"')"
[ -n "$l_px" ] && [ -n "$l_wt" ] && [ "$l_px" -lt "$l_wt" ] && ok "ⓘ 프록시 확인 < 워크트리 add" || bad "ⓘ 프록시 줄=$l_px wt=$l_wt"
[ -n "$l_pane" ] && [ "$l_sess" -lt "$l_pane" ] && [ "$l_pane" -lt "$l_roe" ] && ok "ⓘ has-session < 본체 확인 < ④ 태그" || bad "ⓘ sess=$l_sess pane=$l_pane roe=$l_roe"
[ -n "$l_pane" ] && [ "$l_pane" -lt "$l_reg" ] && [ "$l_reg" -lt "$l_mv" ] && [ "$l_mv" -lt "$l_snd" ] && ok "ⓘ 본체 확인 < ⑤명부 < ⑥카드 이동 < ⑦발주" || bad "ⓘ 순서 pane=$l_pane reg=$l_reg mv=$l_mv snd=$l_snd"
sed -n "${l_pane:-1}p" "$SP" | grep -q 'fail_rb' && ok "ⓘ 실패 경로 = fail_rb" || bad "ⓘ 본체 확인 줄에 fail_rb 없음"
grep -q '^sleep 8' "$SP" && bad "ⓘ sleep 8 잔존" || ok "ⓘ sleep 8 제거(확인이 대체)"
for s in ft-nano-spawn.sh ft-agent-ready.sh; do cmp -s "$TRK/$s" "$KIT/$s" && ok "키트 사본 cmp0 $s" || bad "키트 사본 불일치 $s"; done

echo "== ⓙ UNVERIFIED 줄의 rc"
mkdir -p "$T/fk"; printf '#!/bin/bash\nexit 2\n' > "$T/fk/ft-send-verified.sh"
TAIL="$(awk '/^FT_SEND_FROM=/{p=1} p{print}' "$SP")"
[ -n "$TAIL" ] || TAIL="$(awk '/ft-send-verified.sh" "\$NAME"/{p=1} p{print}' "$SP")"
out="$( HERE="$T/fk"; NAME=s#0; BODY=b; FROM=f; NEW_IDX=i; WTDIR=w; eval "$TAIL" 2>&1 )"; rc=$?
has "$out" "SPAWNED-UNVERIFIED s#0 rc=2" "ⓙ 가짜 send rc=2 → rc=2 표기" ; [ "$rc" -eq 5 ] && ok "ⓙ exit 5 유지" || bad "ⓙ exit=$rc"
printf '#!/bin/bash\nexit 0\n' > "$T/fk/ft-send-verified.sh"
out="$( HERE="$T/fk"; NAME=s#0; BODY=b; FROM=f; NEW_IDX=i; WTDIR=w; eval "$TAIL" 2>&1 )"; rc=$?
[ "$rc" -eq 0 ] && has "$out" "SPAWNED s#0" "ⓙ 성공 → SPAWNED exit0" || bad "ⓙ 성공 경로 rc=$rc ← $out"

echo "== ⓚ doorbell"
mkdir -p "$T/shim"; cat > "$T/shim/tmux" <<'SH'
#!/bin/bash
case "$1" in
  list-panes) case "$*" in *" -a "*) echo "seatX|%9";; *) echo "$FAKE_PANE_PID";; esac;;
  send-keys) echo "$*" >> "$TLOG";;
  display-message) echo "${FAKE_FG:-2.1.302}";;   # R346: doorbell 이 전경 명령을 읽는다 — 기본 = claude 본체 이름(버전 숫자)
esac
SH
chmod +x "$T/shim/tmux"
cat > "$T/seats.json" <<J
{"seatX":{"agent":"claude"},"seatC":{"agent":"cmd"},"seatD":{"agent":"codex"}}
J
# R346: 진짜 claude·codex 는 argv0 가 그 이름인 «실행 주체» 인데 시험 대역은 shebang 스크립트라 ps 에 /bin/bash 가 앞선다 — doorbell 판정기에 줄 ps 만 그 접두를 떼어 네이티브 실행처럼 보이게 한다(기동 확인 ft-agent-ready.sh 는 진짜 ps 그대로).
cat > "$T/psfix" <<'S'
#!/bin/bash
ps "$@" | sed -E 's# (/bin/)?bash (/[^ ]*/(claude|codex)) # \2 #'
S
chmod +x "$T/psfix"
bell() { # <좌석> <pane pid> [FT_PS_CMD] → doorbell 상태
  ( export PATH="$T/shim:$PATH" TMPDIR="$T" TLOG="$T/tlog" FAKE_PANE_PID="$2" FT_PS_CMD="${3:-$T/psfix}"; SELF=/x/mbox.sh
    _seats_json() { echo "$T/seats.json"; }; . "$DB"
    tmux() { "$T/shim/tmux" "$@"; }
    pane_of() { echo "%9"; }
    doorbell "$1" 1 5 ) 2>/dev/null; }
: > "$T/tlog"
mkpane "sleep 30"; r="$(bell seatX "$PANE_PID")"
[ "$r" = noagent ] && [ ! -s "$T/tlog" ] && ok "ⓚ 자식이 sleep 뿐 → noagent · 주입 0" || bad "ⓚ r=$r log=$(cat "$T/tlog")"
mkpane "$C"; r="$(bell seatX "$PANE_PID")"
[ "$r" = sent ] && [ -s "$T/tlog" ] && ok "ⓚ claude 본체 자식 → 기존대로 주입(sent)" || bad "ⓚ r=$r"
mkpane "$R"; r="$(bell seatX "$PANE_PID")"
[ "$r" = sent ] && ok "ⓚ R335 복구형 claude --resume <uuid> → sent (초인종 울림)" || bad "ⓚ R335 resume 형 r=$r"
mkpane "$T/bin/claude-hr.sh --resume 0d4c8f2e-1111-2222-3333-444455556666"; r="$(bell seatX "$PANE_PID")"
[ "$r" = noagent ] && ok "ⓚ R335 래퍼 + --resume → noagent" || bad "ⓚ R335 래퍼 r=$r"
mkpane "$T/bin/myapp --daemon --resumable"; r="$(bell seatX "$PANE_PID")"
[ "$r" = noagent ] && ok "ⓚ R335 데몬(--resumable) → noagent" || bad "ⓚ R335 데몬 r=$r"
for neg in "$T/bin/myapp --resume job-1" "$T/bin/tmux --resume=x" "$T/bin/git log --resume" "$T/bin/myapp claude-notes --resume job-1"; do
  mkpane "$neg"; r="$(bell seatX "$PANE_PID")"; [ "$r" = noagent ] && ok "ⓚ R335 DA⑥ 음성 «${neg#$T/bin/}» → noagent" || bad "ⓚ R335 DA⑥ 음성 r=$r «${neg#$T/bin/}»"
done
mkpane "$T/bin/codex --dangerously-bypass-approvals-and-sandbox"; r="$(bell seatD "$PANE_PID")"
[ "$r" = sent ] && ok "ⓚ codex 좌석 + codex 본체 → sent" || bad "ⓚ codex r=$r"
mkpane "sleep 30"; r="$(bell seatC "$PANE_PID")"
[ "$r" = sent ] && ok "ⓚ 모르는 에이전트(cmd) 좌석 → 기존 «아무 자식» 규칙(주입)" || bad "ⓚ cmd r=$r"
echo '{"seatL":{"agent":"claude"}}' > "$T/seats-loom.json"
mkpane "sleep 30"; r="$(bell seatL "$PANE_PID")"
[ "$r" = noagent ] && ok "ⓚ seats-loom.json 에만 있는 claude 좌석 + sleep 뿐 → noagent (팀 명부 glob)" || bad "ⓚ 팀 명부 r=$r"
mkpane "$C"; r="$(bell seatL "$PANE_PID")"; [ "$r" = sent ] && ok "ⓚ 팀 명부 좌석 + claude 본체 → sent" || bad "ⓚ 팀 명부 본체 r=$r"
echo '{broken' > "$T/seats-x.json"; : > "$T/tlog"
mkpane "sleep 30"; r="$(bell seatZ "$PANE_PID")"
[ "$r" = error ] && [ ! -s "$T/tlog" ] && ok "ⓚ 깨진 명부 + 좌석이 거기뿐(어디서도 못 찾음) → error · 주입 0" || bad "ⓚ 깨진 명부 r=$r log=$(cat "$T/tlog")"
r="$(bell seatX "$PANE_PID")"; [ "$r" = noagent ] && ok "ⓚ 깨진 명부가 있어도 정상 명부에서 찾으면 그대로(noagent)" || bad "ⓚ 정상 명부 우선 r=$r"
( export PATH="$T/shim:$PATH" TMPDIR="$T" TLOG="$T/tlog" FAKE_PANE_PID="$PANE_PID"; SELF=/x/mbox.sh; _seats_json() { echo "$T/seats.json"; }; . "$DB"; pane_of() { echo "%9"; }; doorbell seatZ 1 5 2>&1 >/dev/null ) | grep -q "seats-x.json" && ok "ⓚ 깨진 파일 이름을 stderr 에 1줄" || bad "ⓚ stderr 파일명"
rm -f "$T/seats-x.json"
r="$(bell seatX "$PANE_PID" false)"; [ "$r" = error ] && ok "ⓚ ps 실패 → error (조용한 sent·noagent 0)" || bad "ⓚ ps 실패 r=$r"
# R346 DA⑥ H1: 판정기(ft-agent-alive.sh)의 본체 판별은 «실제 실행 주체» 기준으로 바뀌었다 — 이 기동 확인(ft-agent-ready.sh)의 복제는 옛 args 판별 그대로(합치기 = 후속 R 후보 · 복제 목록은 test_agent_alive_fg_judge.sh ⓔ 가 지킨다).
grep -q '^agent_body_pids()' "$RDY" && grep -q '^agent_body_pids()' "$AL" && ok "ⓚ 본체 판별 함수: 판정기(실행 주체 기준) + 기동 확인 복제(옛 판별) — 합치기는 후속 R" || bad "ⓚ 판별 함수 정의 위치 이상"

echo; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL $fail"; exit "$fail"
