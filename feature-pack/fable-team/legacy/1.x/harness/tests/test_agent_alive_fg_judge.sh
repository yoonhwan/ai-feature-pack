#!/usr/bin/env bash
# test_agent_alive_fg_judge.sh — R346: tmux 세션은 살아 있는데 전경이 «맨 셸» 인 좌석(정지(T) 본체 · 재기동 실패 래퍼만 · 자식 0)을
#   «살아 있음» 으로 세지 않는다. 판정기 하나(ft-agent-alive.sh)를 doorbell · ft-tick · ft-seat-live 가 같이 쓴다.
#   표본 4: ①전경 claude(R+)=ALIVE ②전경 zsh + claude T(정지)=NOAGENT ③전경 zsh + claude-hr 래퍼만=NOAGENT ④전경 zsh + 자식 0=NOAGENT
#   ⓐ판정기 CLI rc·출력 ⓑdoorbell(noagent·주입 0) ⓒ틱 fire(NOAGENT 발사 0 + alert 1회 · 회복 뒤 재경보) ⓓseat-live 칸 2 ⓔ판정기 한 벌 ⓕ키트 두 사본
# 가짜 tmux(export -f 함수 · FT_TMUX 스크립트) + 가짜 ps(FT_PS_CMD) — 실 tmux·실 claude 0 · GIT_DIR 류 0(R121). 모든 쓰기는 mktemp scratch.
. "$(dirname -- "${BASH_SOURCE[0]:-$0}")/lib/real_state_guard.sh" && guard_begin "$@"   # r541: 실 상태 지문 + git 밖 cwd 재실행
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO="$HERE/../.."
AL="$REPO/harness/comm/ft-agent-alive.sh"; DB="$REPO/harness/comm/mbox_doorbell.sh"
KIT="$REPO/harness/bin"; INST="$REPO/harness/kit/fable-team/bin"
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT
fail=0
ok()  { echo "PASS $1"; }
bad() { echo "FAIL $1"; fail=$((fail+1)); }
chk() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got=[$2] want=[$3])"; fi; }

bash -n "$AL" 2>/dev/null && ok "bash -n ft-agent-alive.sh" || bad "bash -n ft-agent-alive.sh (없음 또는 문법 오류)"
mkdir -p "$T/comm"; cp "$AL" "$T/comm/" 2>/dev/null
cat > "$T/seats.json" <<'J'
{"_master":"seatX","seatX":{"role":"master","agent":"claude","tick":"ft-master-tick"}}
J
cat > "$T/fakeps" <<'S'
#!/bin/bash
echo call >> "${PS_LOG:-/dev/null}"
[ -z "${PS_HANG:-}" ] || sleep 30
[ -z "${PS_RC:-}" ] || exit "$PS_RC"
case "$*" in *"pid=,ppid=,stat=,args="*) cat "$PS_ROWS";; *) exit 9;; esac
S
chmod +x "$T/fakeps"
PANE=100; export PANE
table() { # <표본> → PS_ROWS («pid ppid stat args» — 자기 ps 1회 출력 서식)
  echo "$PANE 1 Ss -zsh" > "$T/ps.rows"
  case "$1" in
    claudeR) echo "101 $PANE R+ claude --dangerously-skip-permissions" >> "$T/ps.rows";;
    claudeT) echo "101 $PANE T claude --dangerously-skip-permissions" >> "$T/ps.rows";;
    claudeZ) echo "101 $PANE Z claude --dangerously-skip-permissions" >> "$T/ps.rows";;
    wrapper) echo "101 $PANE S+ /x/claude-hr.sh --dangerously-skip-permissions" >> "$T/ps.rows";;
    none) ;;
  esac
}
tmux() { # 가짜 — 부르는 쪽마다 -F 서식이 다르다(3칸 · 2칸 | · 2칸 공백 · pane_pid)
  case "$1" in
    list-panes) case "$*" in
        *"#{session_name}|#{pane_id}|#{pane_pid}"*) printf 'seatX|%%9|%s\n' "$PANE";;
        *"#{session_name}|#{pane_id}"*) echo "seatX|%9";;
        *"#{session_name} #{pane_id}"*) echo "seatX %9";;
        *"#{pane_pid}"*) echo "$PANE";;
      esac;;
    display-message) [ -n "${FAKE_FG_FAIL:-}" ] && return 1; echo "${FAKE_FG:-2.1.302}";;
    capture-pane) :;;
    send-keys) echo "$*" >> "$TLOG";;
  esac; }
export -f tmux
export FT_PS_CMD="$T/fakeps" PS_ROWS="$T/ps.rows" PS_LOG="$T/ps.log" FT_SEATS_JSON="$T/seats.json" TLOG="$T/tlog" TMPDIR="$T"
judge() { bash "$T/comm/ft-agent-alive.sh" seatX 2>/dev/null; }

echo "== ⓐ 판정기 CLI — 표본 4 + 변이"
for row in "①|claudeR|2.1.302|0|ALIVE" "②|claudeT|zsh|1|NOAGENT" "③|wrapper|zsh|1|NOAGENT" "④|none|zsh|1|NOAGENT" \
           "⑤ 정지 본체만(전경 claude 이름)|claudeT|2.1.302|1|NOAGENT" "⑥ 전경 셸만(본체 R+)|claudeR|zsh|1|NOAGENT" \
           "⑦ 본체 Z|claudeZ|2.1.302|1|NOAGENT" "⑧ 전경 -zsh|claudeR|-zsh|1|NOAGENT"; do
  IFS='|' read -r nm smp fg want_rc want_w <<< "$row"; table "$smp"
  out="$(FAKE_FG="$fg" judge)"; rc=$?
  chk "ⓐ $nm rc" "$rc" "$want_rc"; case "$out" in "$want_w seat=seatX fg=$fg body="*) ok "ⓐ $nm 출력 «${out}»";; *) bad "ⓐ $nm 출력 [$out]";; esac
done
table claudeR; out="$(FAKE_FG_FAIL=1 judge)"; rc=$?
chk "ⓐ tmux display 실패 → rc2 (alive 로 안 돌림)" "$rc" 2; case "$out" in UNKNOWN*) ok "ⓐ 판정 불가 줄 UNKNOWN";; *) bad "ⓐ UNKNOWN 줄 [$out]";; esac
out="$(FT_PS_CMD=false judge)"; rc=$?; chk "ⓐ ps 실패 → rc2" "$rc" 2
table claudeR; out="$(FAKE_FG=2.1.302 judge)"; case "$out" in *body=101) ok "ⓐ ALIVE 줄 body=pid";; *) bad "ⓐ body=pid [$out]";; esac
table none; out="$(FAKE_FG=zsh judge)"; case "$out" in *body=none) ok "ⓐ NOAGENT 줄 body=none";; *) bad "ⓐ body=none [$out]";; esac

echo "== ⓑ doorbell — noagent · 주입 0"
bell() { ( export SELF=/x/mbox.sh; _seats_json() { echo "$T/seats.json"; }; . "$DB"; pane_of() { echo "%9"; }; doorbell seatX 1 5 ) 2>/dev/null; }
for row in "①|claudeR|2.1.302|sent" "②|claudeT|zsh|noagent" "③|wrapper|zsh|noagent" "④|none|zsh|noagent" "⑤|claudeT|2.1.302|noagent" "⑥|claudeR|zsh|noagent"; do
  IFS='|' read -r nm smp fg want <<< "$row"; table "$smp"; : > "$TLOG"; rm -f "$T"/mbox-doorbell-*
  r="$(FAKE_FG="$fg" bell)"
  chk "ⓑ $nm doorbell 상태" "$r" "$want"
  if [ "$want" = sent ]; then [ -s "$TLOG" ] && ok "ⓑ $nm 주입 1" || bad "ⓑ $nm 주입 0건"; else [ ! -s "$TLOG" ] && ok "ⓑ $nm 주입 0" || bad "ⓑ $nm 주입 발생: $(cat "$TLOG")"; fi
done
table claudeR; : > "$TLOG"; rm -f "$T"/mbox-doorbell-*; r="$(FAKE_FG_FAIL=1 bell)"
chk "ⓑ tmux display 실패 → error" "$r" error; [ ! -s "$TLOG" ] && ok "ⓑ display 실패 주입 0" || bad "ⓑ display 실패인데 주입"

echo "== ⓒ 틱 fire — NOAGENT 발사 0 · alert 1회 · 회복 뒤 재경보"
SW="FT_TICK_API_OUTAGE=0 FT_TICK_AUTONOMY=0 FT_TICK_DRIFT=0 FT_TICK_HIL=0 FT_TICK_IDLE_ENABLED=0 FT_TICK_IDLE_LONG=0 FT_TICK_LAUNCHD=0 FT_TICK_LIVE_SNAPSHOT=0 FT_TICK_MAGAZINE=0 FT_TICK_NEWS_LEDGER=0 FT_TICK_NEWS_WATCH=0 FT_TICK_RAISED=0 FT_TICK_RESUME=0 FT_TICK_WT_SWEEP=0"
printf '#!/bin/bash\nexit 0\n' > "$T/goal-stub.sh"
for tick in "$KIT/ft-tick.sh" "$KIT/ft-tick-team.sh"; do
  tn="$(basename "$tick" .sh)"; P="$T/$tn-"; : > "$T/$tn.alert"
  pass() { env $SW FT_TICK_SEATS="$T/seats.json" FT_TICK_STAMP_PREFIX="$P" FT_TICK_STATE_DIR="$T/$tn-state" FT_TICK_PIDFILE="$T/$tn.pid" \
      FT_TICK_MBOX="$T/comm/mbox.sh" FT_TICK_GOAL_TICK="$T/goal-stub.sh" FT_TICK_STALL_INTERVAL=99999999999 FT_TICK_LOOP_SEC=1 \
      bash "$tick" --once 2>&1; }
  alerts() { [ -f "${P}DEAD-SEATS.alert" ] && grep -c 'agent absent' "${P}DEAD-SEATS.alert" || echo 0; }
  table claudeT; : > "$TLOG"; out="$(FAKE_FG=zsh pass)"
  [ ! -s "$TLOG" ] && ok "ⓒ $tn NOAGENT → send-keys 0" || bad "ⓒ $tn NOAGENT 인데 발사: $(cat "$TLOG")"
  chk "ⓒ $tn alert 1줄" "$(alerts)" 1
  grep -q 'agent absent seatX fg=zsh (session alive)' "${P}DEAD-SEATS.alert" 2>/dev/null && ok "ⓒ $tn alert 문구" || bad "ⓒ $tn alert 문구 [$(cat "${P}DEAD-SEATS.alert" 2>/dev/null)]"
  FAKE_FG=zsh pass >/dev/null; chk "ⓒ $tn 두 번째 틱 alert 중복 0" "$(alerts)" 1
  table claudeR; : > "$TLOG"; FAKE_FG=2.1.302 pass >/dev/null
  [ -s "$TLOG" ] && ok "ⓒ $tn 회복(ALIVE) → 발사 1" || bad "ⓒ $tn 회복인데 발사 0"
  rm -f "${P}seatX.master.last" "${P}seatX.pm.last"; table claudeT; : > "$TLOG"; FAKE_FG=zsh pass >/dev/null
  chk "ⓒ $tn 회복 뒤 다시 죽으면 alert 2줄" "$(alerts)" 2
  rm -f "${P}seatX.master.last"; table claudeR; : > "$TLOG"; out="$(FAKE_FG_FAIL=1 FAKE_FG=2.1.302 pass)"
  [ ! -s "$TLOG" ] && ok "ⓒ $tn 판정 불가(rc2) → 발사 0" || bad "ⓒ $tn 판정 불가인데 발사"
  case "$out" in *"판정 불가"*) ok "ⓒ $tn 판정 불가 로그 1줄";; *) bad "ⓒ $tn 판정 불가 로그 없음";; esac
  chk "ⓒ $tn 판정 불가는 alert 늘리지 않음" "$(alerts)" 2
done

echo "== ⓓ seat-live — agent_alive · fg 칸 2 (기존 칸 불변)"
mkdir -p "$T/seats"
cat > "$T/seats/seats-x.json" <<'J'
{"ft-x-master#1":{"role":"master","agent":"claude","model":"m1"},"ft-x-nano#3":{"role":"nano","agent":"claude"},"ft-x-da#1":{"role":"da","agent":"claude"}}
J
cat > "$T/fake-tmux" <<'S'
#!/usr/bin/env bash
case "$1" in
  list-sessions) case "$*" in *session_created*) fmt='%s\t1700000000\t0\n';; *) fmt='%s\n';; esac
                 printf "$fmt" "ft-x-master#1" "ft-x-nano#3" "ft-x-da#1";;
  list-panes) case "$*" in
      *"session_name}|#{pane_id}|#{pane_pid}"*) printf '%s|%s|%s\n' "ft-x-master#1" %1 111 "ft-x-nano#3" %2 222 "ft-x-da#1" %3 333;;
      *) printf '%s\t%s\n' "ft-x-master#1" 111 "ft-x-nano#3" 222 "ft-x-da#1" 333;;
    esac;;
  display-message) case "$*" in *%1*) echo 2.1.302;; *%2*) echo zsh;; *) exit 1;; esac;;
  *) exit 9;;
esac
S
chmod +x "$T/fake-tmux"
cat > "$T/ps.rows" <<'P'
111 1 Ss -zsh
1111 111 R+ claude --dangerously-skip-permissions
222 1 Ss -zsh
2222 222 T claude --dangerously-skip-permissions
333 1 Ss -zsh
3333 333 R+ claude --dangerously-skip-permissions
P
export FT_SEATS_DIR="$T/seats" FT_STATE_DIR="$T/state" FT_TMUX="$T/fake-tmux" FT_AGENT_ALIVE_BIN="$T/comm/ft-agent-alive.sh" FT_SEATS_JSON="$T/seats/seats-x.json"
out="$(bash "$KIT/ft-seat-live.sh" 2>"$T/err")"; rc=$?; chk "ⓓ 생성 rc0" "$rc" 0
L="$T/state/seats.live.json"
row() { jq -c --arg s "$1" '.rows[]|select(.session==$s)' "$L" 2>/dev/null; }
row "ft-x-master#1" | jq -e '.agent_alive==true and .fg=="2.1.302"' >/dev/null 2>&1 && ok "ⓓ 전경 claude → agent_alive=true fg=2.1.302" || bad "ⓓ master 행 [$(row ft-x-master#1)]"
row "ft-x-nano#3" | jq -e '.agent_alive==false and .fg=="zsh"' >/dev/null 2>&1 && ok "ⓓ 전경 zsh → agent_alive=false fg=zsh" || bad "ⓓ nano 행 [$(row ft-x-nano#3)]"
row "ft-x-da#1" | jq -e '.agent_alive==null and .fg==null' >/dev/null 2>&1 && ok "ⓓ 판정 불가 → agent_alive=null (거짓 true/false 0)" || bad "ⓓ da 행 [$(row ft-x-da#1)]"
row "ft-x-master#1" | jq -e '.pane_pid==111 and .role=="master" and .model=="m1" and .base=="ft-x-master"' >/dev/null 2>&1 && ok "ⓓ 기존 칸 불변" || bad "ⓓ 기존 칸 변함"

echo "== ⓔ 판정기 한 벌 · ⓕ 키트 두 사본"
cnt=0; for f in "$DB" "$KIT/ft-tick.sh" "$KIT/ft-tick-team.sh" "$KIT/ft-seat-live.sh"; do grep -q '^agent_body_pids()' "$f" 2>/dev/null && cnt=$((cnt+1)); done
chk "ⓔ doorbell·tick·team·seat-live 에 본체 판별 함수 정의 0" "$cnt" 0
grep -q '^agent_body_pids()' "$AL" 2>/dev/null && ok "ⓔ 판정기 파일에 정의 1" || bad "ⓔ 판정기 파일에 정의 없음"
# 복제 남은 자리(DA⑥ H2-5): ft-agent-ready.sh(기동 확인 · 옛 args 판별) 만 — 합치기는 후속 R 후보. 새 복제가 생기면 이 목록이 깨진다.
dups="$(cd "$REPO" && grep -rl '^agent_body_pids()' tools scripts 2>/dev/null | sort | tr '\n' ' ')"
chk "ⓔ 본체 판별 함수 정의 파일 목록(판정기 + 기동확인 복제 2사본)" "$dups" "scripts/fable-team-bin/ft-agent-ready.sh scripts/harness-install/fable-team/bin/ft-agent-ready.sh tools/comm-canonical/ft-agent-alive.sh "
for f in ft-tick.sh ft-tick-team.sh ft-seat-live.sh ft-harness-info.sh; do chk "ⓕ 키트 두 사본 동일 $f" "$(cmp -s "$KIT/$f" "$INST/$f" && echo same || echo differ)" same; done
for f in ft-tick.sh ft-tick-team.sh ft-seat-live.sh ft-harness-info.sh; do bash -n "$KIT/$f" 2>/dev/null && ok "bash -n $f" || bad "bash -n $f"; done

# ⓓ 가 건 seat-live 용 환경을 되돌린다 — ⓖ 는 다시 함수 tmux·fakeps·seats.json 으로
unset FT_TMUX FT_SEATS_DIR FT_STATE_DIR FT_AGENT_ALIVE_BIN; export FT_SEATS_JSON="$T/seats.json" PS_ROWS="$T/ps.rows"
echo "== ⓖ H1 실제 실행 주체 — 래퍼 인자 속 claude 는 본체가 아님"
w1() { echo "$PANE 1 Ss -zsh" > "$T/ps.rows"; printf '%s\n' "$@" >> "$T/ps.rows"; }
w1 "101 $PANE S+ caffeinate -i /opt/x/claude --resume u"; out="$(FAKE_FG=caffeinate judge)"; rc=$?
chk "ⓖ H1 caffeinate 인자 속 claude --resume → NOAGENT rc" "$rc" 1; case "$out" in "NOAGENT seat=seatX fg=caffeinate body=none") ok "ⓖ H1 줄 «${out}»";; *) bad "ⓖ H1 줄 [$out]";; esac
: > "$TLOG"; rm -f "$T"/mbox-doorbell-*; r="$(FAKE_FG=caffeinate bell)"; [ "$r" = noagent ] && [ ! -s "$TLOG" ] && ok "ⓖ H1 doorbell noagent · 주입 0" || bad "ⓖ H1 doorbell r=$r"
w1 "101 $PANE S+ caffeinate -i /opt/x/claude --resume u" "102 101 S+ claude --resume u"; out="$(FAKE_FG=caffeinate judge)"; rc=$?
chk "ⓖ H1 같은 표본 + 실제 claude 자식 → ALIVE rc" "$rc" 0; case "$out" in *"body=102") ok "ⓖ H1 본체 pid = 102";; *) bad "ⓖ H1 본체 pid [$out]";; esac
for w in "timeout 5 claude --resume u" "env A=1 claude --dangerously-skip-permissions" "nohup claude --resume u" "bash -c claude --resume u" "setsid /x/claude --resume u"; do
  w1 "101 $PANE S+ $w"; FAKE_FG=2.1.302 judge >/dev/null; rc=$?; chk "ⓖ H1 래퍼 «${w%% *}» → NOAGENT" "$rc" 1
done
w1 "101 $PANE S+ node --no-warnings /usr/lib/@anthropic-ai/claude-code/cli.js --dangerously-skip-permissions"; FAKE_FG=2.1.302 judge >/dev/null; rc=$?; chk "ⓖ H1 node + claude-code 스크립트(옛 설치형) → ALIVE" "$rc" 0
cp1() { ( . "$AL"; printf '%s\n' "$2" | agent_body_pids "$PANE" "$1" ); }
rows_c="$PANE 1 Ss -zsh
101 $PANE S+ npm exec @openai/codex --dangerously-bypass-approvals-and-sandbox -c model=x"
chk "ⓖ H1 codex: npm exec @openai/codex 인식" "$(cp1 codex "$rows_c")" 101
chk "ⓖ H1 codex: node /x/bin/codex 인식" "$(cp1 codex "$PANE 1 Ss -zsh
101 $PANE S+ node /x/bin/codex --foo")" 101
chk "ⓖ H1 codex: caffeinate 인자 속 codex → 본체 아님" "$(cp1 codex "$PANE 1 Ss -zsh
101 $PANE S+ caffeinate -i codex --foo")" ""
chk "ⓖ H1 claude: R335 claude --resume <uuid> 인식 유지" "$(cp1 claude "$PANE 1 Ss -zsh
101 $PANE S+ /x/bin/claude --resume 0d4c8f2e")" 101
chk "ⓖ H1 claude: 래퍼 claude-hr + --resume → 본체 아님" "$(cp1 claude "$PANE 1 Ss -zsh
101 $PANE S+ /x/bin/claude-hr.sh --resume 0d4c8f2e")" ""

echo "== ⓖ H2 ps 오류 은폐 0 · 7초 상한 · 스냅샷 계약"
table claudeR; PS_RC=9 judge >/dev/null; rc=$?; chk "ⓖ H2 ps rc9 → rc2" "$rc" 2
w1 "101 $PANE S+ claude --dangerously-skip-permissions"; sed -i '' 's/^101 \([0-9]*\) S+ /101 \1 /' "$T/ps.rows"; FAKE_FG=2.1.302 judge >/dev/null; rc=$?; chk "ⓖ H2 stat 칸 없는 행(깨진 표) → rc2 (ALIVE 아님)" "$rc" 2
: > "$T/ps.rows"; judge >/dev/null; rc=$?; chk "ⓖ H2 ps 빈 출력 → rc2" "$rc" 2
table claudeR; t0=$SECONDS; PS_HANG=1 FT_AGENT_ALIVE_TIMEOUT=1 judge >/dev/null; rc=$?; el=$((SECONDS-t0))
chk "ⓖ H2 ps 멈춤 + 상한 1초 → rc2" "$rc" 2; [ "$el" -le 5 ] && ok "ⓖ H2 1초 상한 ${el}s 안에 끝" || bad "ⓖ H2 1초 상한인데 ${el}s"
t0=$SECONDS; PS_HANG=1 judge >/dev/null; rc=$?; el=$((SECONDS-t0))
chk "ⓖ H2 ps 멈춤(기본 상한) → rc2" "$rc" 2; [ "$el" -ge 6 ] && [ "$el" -le 11 ] && ok "ⓖ H2 기본 상한 7초 뒤 rc2 (${el}s)" || bad "ⓖ H2 기본 상한 소요 ${el}s"
clamp() { ( . "$AL"; FT_AGENT_ALIVE_TIMEOUT="$1" _aa_timeout_s ); }
chk "ⓖ H2 상한 클램프 99→7" "$(clamp 99)" 7; chk "ⓖ H2 상한 비숫자→7" "$(clamp abc)" 7; chk "ⓖ H2 상한 0→7" "$(clamp 0)" 7; chk "ⓖ H2 상한 3→3" "$(clamp 3)" 3
tmuxhang() { ( tmux() { case "$1" in display-message) sleep 30;; *) command true;; esac; }; export -f tmux; FT_AGENT_ALIVE_TIMEOUT=1 judge ); }
table claudeR; t0=$SECONDS; tmuxhang >/dev/null; rc=$?; el=$((SECONDS-t0)); chk "ⓖ H2 tmux 멈춤 + 상한 1초 → rc2" "$rc" 2
snap() { printf '%s\n' "$@" > "$T/snap.txt"; }
S1="100 1 100 Sun Oct 18 01:08:06 2026 00:00.10 Ss -zsh"
snap "$S1" "101 100 101 Sun Oct 18 01:08:07 2026 00:00.50 R+ claude --dangerously-skip-permissions"; : > "$T/ps.log"
out="$(FT_PS_SNAPSHOT="$T/snap.txt" FAKE_FG=2.1.302 judge)"; rc=$?; chk "ⓖ H2 스냅샷 정상 7필드 → ALIVE rc" "$rc" 0; [ ! -s "$T/ps.log" ] && ok "ⓖ H2 스냅샷이면 ps 호출 0회" || bad "ⓖ H2 스냅샷인데 ps 호출 $(wc -l < "$T/ps.log")회"
snap "$S1" "101 100 101 Sun Oct 18 01:08:07 2026 00:00.50 T claude --dangerously-skip-permissions"
FT_PS_SNAPSHOT="$T/snap.txt" FAKE_FG=2.1.302 judge >/dev/null; rc=$?; chk "ⓖ H2 스냅샷 정지(T) 본체 → NOAGENT" "$rc" 1
snap "$S1" "101 100 101 Sun Oct 18 01:08:07 2026 00:00.50 claude --dangerously-skip-permissions"; : > "$T/ps.log"
FT_PS_SNAPSHOT="$T/snap.txt" FAKE_FG=2.1.302 judge >/dev/null; rc=$?; chk "ⓖ H2 스냅샷 필드 6개(stat 없음) → rc2" "$rc" 2; [ ! -s "$T/ps.log" ] && ok "ⓖ H2 깨진 스냅샷 → 자기 ps 폴백 0" || bad "ⓖ H2 깨진 스냅샷인데 자기 ps 호출"
FT_PS_SNAPSHOT="$T/none.txt" judge >/dev/null; rc=$?; chk "ⓖ H2 스냅샷 파일 없음 → rc2 (폴백 0)" "$rc" 2; [ ! -s "$T/ps.log" ] && ok "ⓖ H2 스냅샷 파일 없음 → 자기 ps 0" || bad "ⓖ H2 파일 없음인데 ps 호출"

echo "== ⓖ H3 alert 표식 전이 — 좌석별 잠금"
printf '#!/bin/bash\nsleep 1; echo "NOAGENT seat=$1 fg=zsh body=none"; exit 1\n' > "$T/stub-noagent-slow.sh"
printf '#!/bin/bash\nsleep 1; echo "ALIVE seat=$1 fg=2.1.302 body=7"; exit 0\n' > "$T/stub-alive-slow.sh"
printf '#!/bin/bash\necho "NOAGENT seat=$1 fg=zsh body=none"; exit 1\n' > "$T/stub-noagent.sh"
for tick in "$KIT/ft-tick.sh" "$KIT/ft-tick-team.sh"; do
  tn="$(basename "$tick" .sh)"
  passx() { env $SW FT_TICK_SEATS="$T/seats.json" FT_TICK_AGENT_ALIVE="$1" FT_TICK_STAMP_PREFIX="$2" FT_TICK_STATE_DIR="$2state" FT_TICK_PIDFILE="$2pid" \
      FT_TICK_MBOX="$T/comm/mbox.sh" FT_TICK_GOAL_TICK="$T/goal-stub.sh" FT_TICK_STALL_INTERVAL=99999999999 bash "$tick" --once 2>&1; }
  nal() { [ -f "$1DEAD-SEATS.alert" ] && grep -c 'agent absent' "$1DEAD-SEATS.alert" || echo 0; }
  P="$T/h3-$tn-a-"; ( passx "$T/stub-noagent-slow.sh" "$P" >/dev/null & passx "$T/stub-noagent-slow.sh" "$P" >/dev/null & wait )
  chk "ⓖ H3 $tn 같은 좌석·같은 prefix 동시 두 호출 → 경보 1건" "$(nal "$P")" 1
  [ ! -d "${P}seatX.noagent.last.lock" ] && ok "ⓖ H3 $tn 잠금 정리됨" || bad "ⓖ H3 $tn 잠금 남음"
  P="$T/h3-$tn-b-"; mkdir "${P}DEAD-SEATS.alert"
  out="$(passx "$T/stub-noagent.sh" "$P")"
  [ ! -f "${P}seatX.noagent.last" ] && ok "ⓖ H3 $tn append 실패 → 표식 저장 0" || bad "ⓖ H3 $tn append 실패인데 표식 저장"
  case "$out" in *"alert 쓰기 실패"*) ok "ⓖ H3 $tn append 실패 로그";; *) bad "ⓖ H3 $tn append 실패 로그 없음";; esac
  rmdir "${P}DEAD-SEATS.alert"; passx "$T/stub-noagent.sh" "$P" >/dev/null
  chk "ⓖ H3 $tn 다음 호출에서 재시도 → 경보 1건" "$(nal "$P")" 1; [ -f "${P}seatX.noagent.last" ] && ok "ⓖ H3 $tn 재시도 성공 뒤 표식 저장" || bad "ⓖ H3 $tn 재시도 뒤 표식 없음"
  P="$T/h3-$tn-c-"; ( passx "$T/stub-noagent-slow.sh" "$P" >/dev/null & passx "$T/stub-alive-slow.sh" "$P" >/dev/null & wait )
  m=0; [ -f "${P}seatX.noagent.last" ] && m=1
  chk "ⓖ H3 $tn ALIVE 복귀 rm vs NOAGENT 기록 경쟁 → 표식 있음 ⇔ 경보 1건 (일관)" "$(nal "$P")" "$m"; [ ! -d "${P}seatX.noagent.last.lock" ] && ok "ⓖ H3 $tn 경쟁 뒤 잠금 정리됨" || bad "ⓖ H3 $tn 경쟁 뒤 잠금 남음"
  P="$T/h3-$tn-d-"; mkdir "${P}seatX.noagent.last.lock"; touch -t 202001010000 "${P}seatX.noagent.last.lock"
  passx "$T/stub-noagent.sh" "$P" >/dev/null; chk "ⓖ H3 $tn 오래된(죽은 주인) 잠금은 회수 → 경보 1건" "$(nal "$P")" 1
  P="$T/h3-$tn-e-"; mkdir "${P}seatX.noagent.last.lock"; : > "$TLOG"
  passx "$T/stub-noagent.sh" "$P" >/dev/null; chk "ⓖ H3 $tn 방금 잡힌 잠금 → 이 틱 건너뜀(경보 0 · 발사 0)" "$(nal "$P")|$([ -s "$TLOG" ] && echo 1 || echo 0)" "0|0"
done

echo; [ "$fail" -eq 0 ] && echo "ALL PASS" || echo "FAIL $fail"; exit "$fail"
