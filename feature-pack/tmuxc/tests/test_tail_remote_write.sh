#!/usr/bin/env bash
# test_tail_remote_write.sh — r1047 카드2 시험: tmm s/a/kill · tmuxc send/ask/open/kill/list 의 «원격 쓰기 라우팅».
# 설계 정본: docs/multihost/DESIGN-tail-remote-and-light-git-20261028.md §1.4 계약 보강 4(송신 직렬화·캐시 키)·5(이름 순서·원격 reach 판정).
#
# 이 파일은 «자기 자신을 다시 부르지 않는다»(r1041) — 변이는 도구 사본(tmm·tmuxc)만 뜯어 고친다.
# 시험 환경은 전부 임시다: HOME·명부(hosts.tsv)·가짜 ssh·가짜 tmux(PATH 앞). 실제 mini 로 나가는 호출 0.
#
# 4칸 각각 단독:
#   ⓐ 원격 송신+도달 (≤16초) + 변이(원격 reach 대신 화면 판정 → FAIL)
#   ⓑ 락 — 가짜 ssh 2병렬 + 변이(락 제거 → 섞임 → FAIL)
#   ⓒ 이름 순서 — 로컬 단위(lint 실패면 send 0 · 접두 충돌 = exit 2)
#   ⓓ open+kill 왕복 (≤30초)
set -uo pipefail
export LC_ALL=C

CARD_DIR="$(cd "$(dirname "$0")/.." && pwd)"      # feature-pack/tmuxc
FP="$(cd "$CARD_DIR/.." && pwd)"                   # feature-pack
TMM="$FP/tmm/core/bin/tmm"
TMUXC="$CARD_DIR/core/bin/tmuxc"
HOSTLIB="$FP/tmm/core/libexec/host-lib.sh"
REACH="$FP/fable-team/harness/kit/fable-team/bin/ft-reach-check.sh"
LINT="$FP/fable-team/harness/kit/fable-team/bin/ft-name-lint.sh"
INJECT_LIB="$CARD_DIR/core/libexec/agent-inject.sh"

for f in "$TMM" "$TMUXC" "$HOSTLIB" "$REACH" "$LINT" "$INJECT_LIB"; do
  [ -f "$f" ] || { echo "ERROR 없음: $f" >&2; exit 2; }
done

T="$(mktemp -d "${TMPDIR:-/tmp}/tlrw.XXXXXX")" || exit 2
cleanup() { rm -rf "$T"; }
trap cleanup EXIT

FAIL=0
pass() { printf 'ok   %s\n' "$*"; }
fail() { printf 'FAIL %s\n' "$*"; FAIL=$((FAIL + 1)); }
now_ms() { python3 -c 'import time;print(int(time.time()*1000))'; }

# ── 시험 환경: 임시 HOME·명부·가짜 ssh·가짜 tmux ───────────────────────────────
mk_env() {  # <환경 폴더 절대경로> → $E
  E="$1"; mkdir -p "$E/home/.tmm" "$E/home/.ssh" "$E/bin" "$E/state/sessions" "$E/remote/repo" "$E/lib"
  printf 'm3\tlocal\t-\t-\t1\tthis-mac\nmini\ttail-remote\tmini\t%s:%s\t1\tfake-mini\n' \
    "$E/bin" "$E/home/.local/bin" > "$E/home/.tmm/hosts.tsv"
  cp "$HOSTLIB" "$E/lib/host-lib.sh"; cp "$(dirname "$HOSTLIB")/host-run.sh" "$E/lib/host-run.sh"
  # ★ControlMaster 소켓을 «이미 서 있는 것처럼» 만든다★ — 소켓이 없으면 host-lib 이 «최초 수립 락» 을 잡아
  #  모든 호출을 직렬화한다(그러면 송신 락의 효과를 관측할 수 없다). 파일 종류만 socket 이면 된다.
  mkdir -p "$E/home/.ssh/ft-cm"
  mk_socket "$E/home/.ssh/ft-cm/mini"
}

mk_socket() {  # <경로> — ControlMaster «이미 수립됨» 표지(파일 종류만 socket)
  python3 - "$1" <<'PY'
import socket, sys, os
p = sys.argv[1]
if os.path.exists(p):
    os.unlink(p)
socket.socket(socket.AF_UNIX).bind(p)
PY

  # 가짜 ssh — 옵션·alias 를 건너뛰고 `--` 뒤 원격 명령을 «이 맥에서» 실행한다(원격 시뮬레이션).
  cat > "$E/bin/ssh" <<'EOS'
#!/usr/bin/env bash
# 가짜 ssh — `--` 뒤 원격 명령을 «원격 셸처럼» 한 번 더 파싱해서 이 맥에서 실행한다.
#   (진짜 ssh 는 argv 를 공백으로 이어 원격 셸에 넘긴다 — 그 성질을 그대로 재현해야 host-lib 의
#    printf %q 부트스트랩 따옴표가 풀린다.)
while [ $# -gt 0 ]; do
  case "$1" in
    --)
      shift
      # ★진짜 ssh 처럼 «공백으로 이어 붙인다»★ — 다시 quoting 하면 host-lib 의 printf %q 결과를
      #  이중으로 이스케이프해 버린다(실측: bash: <부트스트랩>: No such file or directory).
      c="$*"
      FAKE_VIA_SSH=1; export FAKE_VIA_SSH
      # 원격 HOME 시뮬레이션(ⓕ) — 주면 «원격 셸» 의 HOME 을 다른 폴더로 바꾼다(이 맥 HOME 과 분리).
      if [ -n "${FAKE_REMOTE_HOME:-}" ]; then HOME="$FAKE_REMOTE_HOME"; export HOME; fi
      exec bash -c "$c"
      ;;
    -o|-p|-i|-l) shift 2 ;;
    -*) shift ;;
    *) shift ;;
  esac
done
echo "fake-ssh: 원격 명령 없음" >&2
exit 255
EOS

  # 가짜 tmux — 세션 상태를 폴더로, 송신을 로그로 남긴다.
  cat > "$E/bin/tmux" <<'EOS'
#!/usr/bin/env bash
S="${FAKE_TMUX_STATE:?FAKE_TMUX_STATE 없음}"
mkdir -p "$S/sessions"
printf '%s\n' "$*" >> "$S/calls.log"
cmd="$1"; shift
tgt_of() { local t="$1"; t="${t#=}"; printf '%s' "${t%:}"; }
case "$cmd" in
  send-keys)
    sess=""; lit=0; text=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -t) sess="$(tgt_of "$2")"; shift 2 ;;
        -l) lit=1; shift ;;
        *) text="$1"; shift ;;
      esac
    done
    if [ "$lit" = 1 ]; then
      printf '%s\tTEXT\t%s\t%s\t%s\n' "$sess" "$text" "${FAKE_VIA_SSH:-0}" "$(date +%s)" >> "$S/sent.log"
      # ★입력줄 상태를 기록한다★ — r1075 반례 R6(그리기 지연)·R7(첫 Enter 삼킴) 이 이 파일을 본다.
      printf '%s' "$text" > "$S/sessions/$sess/input"
      date +%s > "$S/sessions/$sess/input_ts"
    else
      # Enter — 좌석이 «기록» 하는 성질(record 표지)이 있으면 jsonl 에 제출 기록을 쓴다(실측 모사).
      [ -n "${FAKE_ENTER_DELAY:-}" ] && sleep "$FAKE_ENTER_DELAY"
      printf '%s\tENTER\t\t%s\t%s\n' "$sess" "${FAKE_VIA_SSH:-0}" "$(date +%s)" >> "$S/sent.log"
      sd="$S/sessions/$sess"
      n_enter=$(( $(cat "$sd/enters" 2>/dev/null || echo 0) + 1 )); printf '%s\n' "$n_enter" > "$sd/enters"
      # R7: 첫 Enter 를 삼키는 좌석(삼켜지면 제출 0 — 입력줄은 그대로 남는다)
      if [ -f "$sd/ignore_first_enter" ] && [ "$n_enter" = 1 ]; then exit 0; fi
      if [ -f "$sd/record" ]; then
        # ★Enter 시점의 «입력줄» 이 제출된다★ — 그리기 지연(draw_delay) 중이면 잘린 글자가 제출된다(R6 의 사고 모사).
        txt="$(cat "$sd/input" 2>/dev/null)"
        draw="$(cat "$sd/draw_delay" 2>/dev/null)"
        if [ -n "$draw" ]; then
          ts="$(cat "$sd/input_ts" 2>/dev/null || echo 0)"; now="$(date +%s)"
          [ $(( now - ts )) -lt "$draw" ] && txt="${txt:0:5}"
        fi
        cwd=$(cat "$sd/cwd" 2>/dev/null)
        enc=$(printf '%s' "$cwd" | sed 's|[^A-Za-z0-9]|-|g')
        sid=$(awk -F= '$1=="TMUXC_CLAUDE_SESSION_ID"{print $2; exit}' "$sd/env" 2>/dev/null)
        # ★jsonl 쓰기는 좌석이 나중에 한다★(실제로도 4초 안쪽 지연이 있다) — baseline 을 보내기 전에 잡아도
        #  미도달로 오판하지 않도록 «뒤늦게» 쓴다.
        # ★첫 제출이 «디렉터리도 같이 만든다»★ — 실제 claude 는 첫 사용자 턴이 기록되면서
        #  ~/.claude/projects/<enc>/ 를 새로 만든다(r1047 r3 · h146: 21:07:36 폴더 생성 = 도착과 같은 초).
        ( sleep "${FAKE_RECORD_DELAY:-0}"; mkdir -p "$HOME/.claude/projects/$enc"
          printf '{"type":"user","message":{"content":"%s"}}\n' "$txt" \
            >> "$HOME/.claude/projects/$enc/${sid:-a}.jsonl" ) >/dev/null 2>&1 &
      fi
    fi
    ;;
  display|display-message)
    t2=""; fmt=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -p) shift ;;
        -t) t2="$(tgt_of "$2")"; shift 2 ;;
        *) fmt="$1"; shift ;;
      esac
    done
    case "$fmt" in
      *pane_current_command*) cat "$S/sessions/$t2/cmd" 2>/dev/null || printf 'zsh\n' ;;
      *pane_current_path*)    cat "$S/sessions/$t2/cwd" 2>/dev/null || printf '%s\n' "$S" ;;
      *pane_pid*) ;;
      *) ;;
    esac
    ;;
  has-session)
    t2=""; while [ $# -gt 0 ]; do case "$1" in -t) t2="$(tgt_of "$2")"; shift 2 ;; *) shift ;; esac; done
    [ -d "$S/sessions/$t2" ]
    ;;
  new-session)
    name=""; wd=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -s) name="$2"; shift 2 ;;
        -c) wd="$2"; shift 2 ;;
        -e) shift 2 ;;
        -d) shift ;;
        *) shift ;;
      esac
    done
    mkdir -p "$S/sessions/$name" && printf '%s\n' "$wd" > "$S/sessions/$name/cwd" && printf 'zsh\n' > "$S/sessions/$name/cmd"
    ;;
  set-environment)
    shift; n="$1"; k="$2"; v="$3"
    printf '%s=%s\n' "$k" "$v" >> "$S/sessions/$n/env"
    ;;
  show-environment)
    t2=""; key=""
    while [ $# -gt 0 ]; do case "$1" in -t) t2="$(tgt_of "$2")"; shift 2 ;; *) key="$1"; shift ;; esac; done
    line=$(grep -m1 "^$key=" "$S/sessions/$t2/env" 2>/dev/null)
    [ -n "$line" ] || { printf 'unknown variable: %s\n' "$key" >&2; exit 1; }
    printf '%s\n' "$line"
    ;;
  set) ;;
  capture-pane)
    t2=""; while [ $# -gt 0 ]; do case "$1" in -t) t2="$(tgt_of "$2")"; shift 2 ;; *) shift ;; esac; done
    sd="$S/sessions/$t2"
    # R1·R2: 상자 그리기를 늦추는 좌석(box_after 초) — 그 전에는 «아직 그리는 중» 화면(= 구분선 0)
    ba="$(cat "$sd/box_after" 2>/dev/null)"
    if [ -n "$ba" ]; then
      st="$(cat "$sd/start" 2>/dev/null || echo 0)"
      [ $(( $(date +%s) - st )) -lt "$ba" ] && { printf 'starting claude…\n'; exit 0; }
    fi
    inp=""; if [ -f "$sd/input" ]; then inp="$(cat "$sd/input")"; fi
    # R6: 글자가 «다 그려지기 전» 화면 — 앞 5글자만 보인다(그 때 Enter 하면 잘린 글이 제출된다)
    draw="$(cat "$sd/draw_delay" 2>/dev/null)"
    if [ -n "$draw" ] && [ -n "$inp" ]; then
      ts="$(cat "$sd/input_ts" 2>/dev/null || echo 0)"
      [ $(( $(date +%s) - ts )) -lt "$draw" ] && inp="${inp:0:5}"
    fi
    printf '─────────────────────\n'
    printf '❯ %s\n' "$inp"
    printf '─────────────────────\n'
    printf '⏵⏵ bypass permissions on\n'
    ;;
  kill-session)
    t2=""; while [ $# -gt 0 ]; do case "$1" in -t) t2="$(tgt_of "$2")"; shift 2 ;; *) shift ;; esac; done
    rm -rf "${S:?}/sessions/$t2"
    ;;
  list-sessions)
    for d in "$S"/sessions/*; do [ -d "$d" ] && printf '%s\t%s\t0\n' "$(basename "$d")" "$S"; done
    ;;
  *) ;;
esac
EOS
  chmod +x "$E/bin/ssh" "$E/bin/tmux"

  # 좌석 1개 + 그 좌석의 jsonl(제출 기록) 을 만든다 — 좌석 이름·cwd 는 인자로.
  return 0
}

mk_seat() {  # <환경> <좌석> <cwd> <에이전트 cmd>
  local e="$1" seat="$2" cwd="$3" cmd="${4:-claude}"
  mkdir -p "$e/state/sessions/$seat"
  printf '%s\n' "$cwd" > "$e/state/sessions/$seat/cwd"
  printf '%s\n' "$cmd" > "$e/state/sessions/$seat/cmd"
  date +%s > "$e/state/sessions/$seat/start"
}

# r1075 반례용 — 좌석에 «세션 env 기록 id» 와 지연·삼킴 성질을 붙인다.
seat_props() {  # <환경> <좌석> [sid] [box_after] [draw_delay] [ignore_first_enter]
  local e="$1" seat="$2" sid="${3:-}" box="${4:-}" draw="${5:-}" swallow="${6:-}"
  local sd="$e/state/sessions/$seat"
  [ -n "$sid" ] && printf 'TMUXC_CLAUDE_SESSION_ID=%s\n' "$sid" >> "$sd/env"
  [ -n "$box" ] && printf '%s\n' "$box" > "$sd/box_after"
  [ -n "$draw" ] && printf '%s\n' "$draw" > "$sd/draw_delay"
  [ -n "$swallow" ] && : > "$sd/ignore_first_enter"
  return 0
}

add_jsonl() {  # <환경> <cwd> <좌석> [record] — 좌석 jsonl 에 «이름» 레코드를 만든다 · record 면 좌석이 수신 기록을 쓰는 표지
  local e="$1" cwd="$2" seat="$3" rec="${4:-}" enc dir
  enc="$(printf '%s' "$cwd" | sed 's|[^A-Za-z0-9]|-|g')"
  dir="$e/home/.claude/projects/$enc"; mkdir -p "$dir"
  printf '{"type":"agent-name","agentName":"%s","sessionId":"s1"}\n' "$seat" > "$dir/a.jsonl"
  [ "$rec" = record ] && : > "$e/state/sessions/$seat/record"
  return 0
}

# 도구를 «이 시험 전용 환경» 으로 돌린다.
run_tool() {  # <환경> <도구경로> <인자…>
  local e="$1" tool="$2"; shift 2
  env -i PATH="$e/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
      HOME="$e/home" FAKE_TMUX_STATE="$e/state" \
      TMUXC_HOSTLIB="$e/lib/host-lib.sh" \
      TMM_REACH_CHECK="${REACH_OVERRIDE:-$REACH}" TMUXC_REACH_CHECK="${REACH_OVERRIDE:-$REACH}" \
      FT_REACH_COUNT_ONLY="${FT_REACH_COUNT_ONLY:-}" \
      TMUXC_NAME_LINT="$LINT" TMM_REACH_TIMEOUT="${REACH_TO:-2}" TMUXC_REACH_TIMEOUT="${REACH_TO:-2}" \
      TMUXC_AGENT_INJECT_LIB="${INJECT_LIB_OVERRIDE:-$INJECT_LIB}" TMM_AGENT_INJECT_LIB="${INJECT_LIB_OVERRIDE:-$INJECT_LIB}" \
      TMUXC_READY_MAX="${TMUXC_READY_MAX:-}" TMUXC_SUBMIT_WAIT="${TMUXC_SUBMIT_WAIT:-}" \
      FAKE_ENTER_DELAY="${FAKE_ENTER_DELAY:-}" FAKE_RECORD_DELAY="${FAKE_RECORD_DELAY:-0}" \
      FAKE_REMOTE_HOME="${FAKE_REMOTE_HOME:-}" \
      TERM=dumb "$tool" "$@"
}

# ── ⓐ 원격 송신 + 도달 판정 ───────────────────────────────────────────────────
t0="$(now_ms)"
e="$T/a"; mk_env "$e"
# 좌석1(수신 기록 없음) — 원격 send-keys 는 가고, jsonl 에 제출 기록이 없으면 NOT_REACHED(rc 4)
mk_seat "$e" byz-satnano-nano-alpha#0 "$e/remote/repo" claude
add_jsonl "$e" "$e/remote/repo" byz-satnano-nano-alpha#0
REACH_TO=0
out="$(run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-alpha#0 "PROBE-A-1" 2>&1)"; rc=$?
REACH_TO=2
el1=$(( $(now_ms) - t0 ))
[ "$el1" -le 16000 ] && pass "ⓐ 송신+reach 1건 ${el1}ms (≤16000)" || fail "ⓐ 송신+reach 1건 ${el1}ms > 16000"
n="$(awk -F'\t' '$2=="TEXT" && $3 ~ /PROBE-A-1/ { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
[ "$n" = 1 ] && pass "ⓐ 원격 send-keys 1회" || fail "ⓐ 원격 send-keys 횟수=$n (기대 1)"
nvia1="$(awk -F'\t' '$2=="TEXT" && $4==1 { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
nvia0="$(awk -F'\t' '$2=="TEXT" && $4!=1 { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
if [ "$nvia1" = 1 ] && [ "$nvia0" = 0 ]; then pass "ⓐ 원격 경유 1 · 로컬 직접 0"
else fail "ⓐ 경유 분리 실패 ssh=$nvia1 local=$nvia0"; fi
[ "$rc" = 4 ] && pass "ⓐ 미도달 판정 = 원격 reach-check rc 4" || fail "ⓐ 미도달 판정 rc=$rc (기대 4) out=$out"

# 좌석2(수신 기록 있음) — 같은 경로로 보내면 REACHED(rc 0)
mk_seat "$e" byz-satnano-nano-beta#0 "$e/remote/repo" claude
add_jsonl "$e" "$e/remote/repo" byz-satnano-nano-beta#0 record
out="$(run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-beta#0 "PROBE-A-2" 2>&1)"; rc=$?
[ "$rc" = 0 ] && pass "ⓐ 도달 판정 = 원격 reach-check rc 0" || fail "ⓐ 도달 판정 rc=$rc (기대 0) out=$out"
case "$out" in *delivered=mini/byz-satnano-nano-beta#0*) pass "ⓐ delivered 줄" ;; *) fail "ⓐ delivered 줄 없음: $out" ;; esac
case "$out" in *"grep -qF"*) fail "ⓐ 화면 판정 문자열 노출" ;; *) pass "ⓐ 화면(capture) 판정 아님" ;; esac
el=$(( $(now_ms) - t0 ))
printf 'info ⓐ 네 송신 합계 %sms (원격 3회/1건 상한 아님 · 1건 상한은 el1)\n' "$el"

# 변이: 원격 reach 판정을 «화면 판정» 으로 바꾸면 미도달 건이 delivered 로 뒤집힌다 → 시험이 잡는다.
em="$T/a-mut"; rm -rf "$em"; cp -R "$e" "$em"; : > "$em/state/sent.log"
mk_socket "$em/home/.ssh/ft-cm/mini"
mvar="$T/tmuxc-mut-capture"; cp "$TMUXC" "$mvar"
python3 - "$mvar" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '    remote_reach_check "$R_HOST" "$R_SESS" "$*" "$base"\n    rc=$?'
new = '    if tmux capture-pane -t "$R_SESS" -p 2>/dev/null | grep -qF "$*"; then rc=0; else rc=4; fi\n'
assert old in s, "변이 지점 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
REACH_TO=0
mout="$(run_tool "$em" "$mvar" send mini/byz-satnano-nano-alpha#0 "PROBE-M-1" 2>&1)"; mrc=$?
REACH_TO=2
[ "$mrc" = 0 ] && pass "ⓐ 변이 FAIL 확인(화면 판정 → rc 4 대신 0 · 시험이 잡는다)" \
  || fail "ⓐ 변이 미검출 — 화면 판정으로 바꿔도 rc=$mrc (기대 0 ≠ 정상 4) out=$mout"

# ── ⓑ 송신 락 — 같은 좌석 동시 송신 2 ────────────────────────────────────────
e="$T/b"; mk_env "$e"
mk_seat "$e" byz-satnano-nano-beta#0 "$e/remote/repo" claude
add_jsonl "$e" "$e/remote/repo" byz-satnano-nano-gamma#0
# Enter 쓰기 앞에 지연을 두어 «두 송신이 겹치는 창» 을 만든다 — 락이 없으면 본문/Enter 가 엇갈린다.
export FAKE_ENTER_DELAY=1.2
run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-beta#0 "LOCK-A" >/dev/null 2>&1 &
pid1=$!
run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-beta#0 "LOCK-B" >/dev/null 2>&1 &
pid2=$!
wait "$pid1"; wait "$pid2"
mixed="$(awk -F'\t' 'BEGIN{bad=0; last=""}
  { if ($2=="TEXT") { if (last=="TEXT") bad=1; last="TEXT" } else { if (last!="TEXT") bad=1; last="ENTER" } }
  END{ print bad }' "$e/state/sent.log" 2>/dev/null)"
n="$(grep -c $'\tTEXT\t' "$e/state/sent.log" 2>/dev/null | tr -d ' ')"
if [ "$n" = 2 ] && [ "$mixed" = 0 ]; then pass "ⓑ 락 직렬화 (본문 2 · 섞임 0)"
else fail "ⓑ 락 실패 n=$n mixed=$mixed"; fi

# 변이: 락을 떼면 본문/Enter 가 엇갈린다.
em="$T/b-mut"; rm -rf "$em"; cp -R "$e" "$em"; : > "$em/state/sent.log"
mk_socket "$em/home/.ssh/ft-cm/mini"
mvar="$T/tmuxc-mut-nolock"; cp "$TMUXC" "$mvar"
python3 - "$mvar" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = 'hl _h_with_lock "$lock" h_pipe_write'
new = 'hl h_pipe_write'
assert old in s, "변이 지점 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, new, 1))
PY
run_tool "$em" "$mvar" send mini/byz-satnano-nano-beta#0 "LOCK-C" >/dev/null 2>&1 &
pid1=$!
run_tool "$em" "$mvar" send mini/byz-satnano-nano-beta#0 "LOCK-D" >/dev/null 2>&1 &
pid2=$!
wait "$pid1"; wait "$pid2"
mmixed="$(awk -F'\t' 'BEGIN{bad=0; last=""}
  { if ($2=="TEXT") { if (last=="TEXT") bad=1; last="TEXT" } else { if (last!="TEXT") bad=1; last="ENTER" } }
  END{ print bad }' "$em/state/sent.log" 2>/dev/null)"
[ "$mmixed" = 1 ] && pass "ⓑ 변이 FAIL 확인(락 제거 → 섞임 1)" || fail "ⓑ 변이 미검출 mixed=$mmixed (기대 1)"

# ── ⓒ 이름 순서 — 접두를 뗀 뒤 lint · 접두 충돌은 exit 2 ─────────────────────
e="$T/c"; mk_env "$e"
mk_seat "$e" byz-satnano-nano-gamma#0 "$e/remote/repo" claude
out="$(run_tool "$e" "$TMUXC" send "mini/Mini_Bad#0" "X" 2>&1)"; rc=$?
[ "$rc" = 1 ] && pass "ⓒ lint 실패 = exit 1" || fail "ⓒ lint 실패 rc=$rc (기대 1) out=$out"
[ -s "$e/state/sent.log" ] && fail "ⓒ lint 실패인데 송신됨" || pass "ⓒ lint 실패면 send 0"
out="$(run_tool "$e" "$TMUXC" send "mini/byz-satnano-nano-gamma#0" "X" --host oci 2>&1)"; rc=$?
[ "$rc" = 2 ] && pass "ⓒ 접두·--host 충돌 = exit 2" || fail "ⓒ 충돌 rc=$rc (기대 2) out=$out"
mk_seat "$e" local-seat "$e/remote/repo" claude
out="$(run_tool "$e" "$TMUXC" send "local-seat" "PROBE-C" 2>&1)"; rc=$?
lvia0="$(awk -F'\t' '$2=="TEXT" && $4!=1 { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
if [ "$rc" = 0 ] && [ "$lvia0" -ge 1 ] && [[ "$out" == delivered=local-seat* ]]; then
  pass "ⓒ 접두 없는 로컬 주소 = 지금 동작(ssh 경유 0)"
else fail "ⓒ 로컬 경로 rc=$rc local_text=$lvia0 out=$out"; fi

# ── ⓔ tmm s «호스트/좌석» — R1 (원격 send-keys 1회 · 로컬 0) ────────────────
e="$T/e"; mk_env "$e"
mk_seat "$e" byz-satnano-nano-eps#0 "$e/remote/repo" claude
add_jsonl "$e" "$e/remote/repo" byz-satnano-nano-eps#0 record
out="$(run_tool "$e" "$TMM" s "mini/byz-satnano-nano-eps#0" "PROBE-E-1" 2>&1)"; rc=$?
nssh="$(awk -F'\t' '$2=="TEXT" && $3 ~ /PROBE-E-1/ && $4==1 { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
nloc="$(awk -F'\t' '$2=="TEXT" && $3 ~ /PROBE-E-1/ && $4!=1 { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
if [ "$nssh" = 1 ] && [ "$nloc" = 0 ]; then pass "ⓔ tmm s mini/<좌석> = 원격 1 · 로컬 0"
else fail "ⓔ tmm s 경유 분리 실패 ssh=$nssh local=$nloc"; fi
[ "$rc" = 0 ] && pass "ⓔ tmm s 도달 판정 rc 0" || fail "ⓔ tmm s rc=$rc (기대 0) out=$out"
case "$out" in *delivered=mini/byz-satnano-nano-eps#0*) pass "ⓔ tmm s delivered 줄" ;; *) fail "ⓔ tmm s delivered 줄 없음: $out" ;; esac

# ── ⓓ open + kill 왕복 ──────────────────────────────────────────────────────
t0="$(now_ms)"
e="$T/d"; mk_env "$e"
mkdir -p "$e/home/.pi/agent/sessions"
out="$(run_tool "$e" "$TMUXC" open "$e/remote/repo" --host mini --name byz-satnano-nano-delta#0 --agent pi 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ -d "$e/state/sessions/byz-satnano-nano-delta#0" ]; then
  pass "ⓓ open --host mini = 원격 세션 생성"
else fail "ⓓ open rc=$rc out=$out"; fi
out="$(run_tool "$e" "$TMM" kill "mini/byz-satnano-nano-delta#0" --yes 2>&1)"; rc=$?
if [ "$rc" = 0 ] && [ ! -d "$e/state/sessions/byz-satnano-nano-delta#0" ]; then
  pass "ⓓ tmm kill mini/<좌석> = 원격 종료"
else fail "ⓓ kill rc=$rc out=$out"; fi
grep -q 'new-session' "$e/state/calls.log" && grep -q 'kill-session' "$e/state/calls.log" \
  && pass "ⓓ 원격 호출 2회(생성·종료)" || fail "ⓓ 원격 호출 흔적 없음"
el=$(( $(now_ms) - t0 ))
[ "$el" -le 30000 ] && pass "ⓓ 단계 초 ${el}ms (≤30000)" || fail "ⓓ 단계 초 ${el}ms > 30000"

# ── ⓕ 원격 open 의 에이전트 명령 = «원격» HOME (r1047 r2 · h135 반송) ────────
# h135 실측: 원격 pane 이 /Users/<이 맥>/.headroom/claude-hr.sh 를 받아 실행 실패(그 경로 없음).
# 가짜 원격 HOME 을 이 맥과 다르게 두고, 보낸 글자에 «이 맥 홈 경로 0 · $HOME/.headroom 1» 을 본다.
e="$T/f"; mk_env "$e"
mkdir -p "$e/remote/home"
export FAKE_REMOTE_HOME="$e/remote/home"
mf="claude-sonnet-5-5"
out="$(run_tool "$e" "$TMUXC" open "$e/remote/repo" --host mini --name byz-satnano-nano-zeta#0 --agent claude --model "$mf" --dry-run 2>&1)"; rc=$?
case "$out" in
  *'command=$HOME/.headroom/claude-hr.sh'*) pass "ⓕ dry-run command = \$HOME/.headroom" ;;
  *) fail "ⓕ dry-run command 이상 rc=$rc out=$out" ;;
esac
case "$out" in
  *"$e/home"*|*"$HOME/"*) fail "ⓕ dry-run 에 이 맥 홈 경로 노출" ;;
  *) pass "ⓕ dry-run 이 맥 홈 경로 0" ;;
esac
out="$(run_tool "$e" "$TMUXC" open "$e/remote/repo" --host mini --name byz-satnano-nano-zeta#0 --agent claude --model "$mf" 2>&1)"; rc=$?
[ -d "$e/state/sessions/byz-satnano-nano-zeta#0" ] && pass "ⓕ 원격 open 세션 생성" || fail "ⓕ open rc=$rc out=$out"
sent="$(awk -F'\t' '$2=="TEXT"{print $3}' "$e/state/sent.log" 2>/dev/null)"
nrh="$(printf '%s\n' "$sent" | grep -oF '$HOME/.headroom/claude-hr.sh' | wc -l | tr -d ' ')"
nlh="$(printf '%s\n' "$sent" | grep -cF "$e/home" | tr -d ' ')"
nlh="${nlh:-0}"
if [ "$nrh" = 1 ] && [ "$nlh" = 0 ]; then pass "ⓕ 원격 pane 에 보낸 글자 = \$HOME/.headroom 1 · 이 맥 홈 0"
else fail "ⓕ 원격 명령 글자 rh=$nrh localhome=$nlh sent=$sent"; fi

# 변이: 치환을 끄면 이 맥 홈 경로가 그대로 나간다(원격에서 실행 실패) → 시험이 잡는다.
mvar="$T/tmuxc-mut-homelit"; cp "$TMUXC" "$mvar"
python3 - "$mvar" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '  run_cmd="${run_cmd//"$HOME"/\\$HOME}"\n'
assert old in s, "변이 지점 없음"
open(p, "w", encoding="utf-8").write(s.replace(old, "", 1))
PY
: > "$e/state/sent.log"
mout="$(run_tool "$e" "$mvar" open "$e/remote/repo" --host mini --name byz-satnano-nano-eta#0 --agent claude --model "$mf" 2>&1)"; mrc=$?
msent="$(awk -F'\t' '$2=="TEXT"{print $3}' "$e/state/sent.log" 2>/dev/null)"
mlh="$(printf '%s\n' "$msent" | grep -cF "$e/home" | tr -d ' ')"
mlh="${mlh:-0}"
[ "$mlh" -ge 1 ] && pass "ⓕ 변이 FAIL 확인(치환 끔 → 이 맥 홈 경로 그대로)" \
  || fail "ⓕ 변이 미검출 rc=$mrc localhome=$mlh sent=$msent"
unset FAKE_REMOTE_HOME

# ── ⓖ 새 원격 좌석(기록 디렉터리 없음) → 보내면 REACHED (r1047 r3 · h146 반송) ─────
# h146 실측: 보내기 전 baseline 이 «디렉터리 없음» 으로 rc5 → tmm 이 그 실패를 빈 값으로 삼킴 →
#  보낸 뒤 잰 1 이 baseline(=1) 이 되어 ★도착한 메시지가 NOT_REACHED★ 로 뒤집혔다.
# 고침 = ⓐ ft-reach-check 의 COUNT_ONLY 가 «디렉터리 없음» 검사보다 앞(0 · rc0) · ⓑ baseline rc≠0 은 판정 불가(rc5).
e="$T/g"; mk_env "$e"
mk_seat "$e" byz-satnano-nano-theta#0 "$e/remote/repo" claude
# ★projects 폴더를 «만들지 않는다»★ — 새 좌석은 첫 제출 전까지 jsonl 디렉터리가 없다.
: > "$e/state/sessions/byz-satnano-nano-theta#0/record"
enc="$(printf '%s' "$e/remote/repo" | sed 's|[^A-Za-z0-9]|-|g')"
if [ -d "$e/home/.claude/projects/$enc" ]; then fail "ⓖ 사전 조건: projects 폴더가 이미 있다"; else pass "ⓖ 사전 조건 = projects 폴더 없음(새 좌석)"; fi
# ① 단독 확인: baseline 모드가 rc0 · 값 0
# ★접두 환경변수는 «명령치환 안» 에 둔다★ — 밖에 두면 이 셸에 남아 뒤의 리모트 판정까지 COUNT_ONLY 로 돈다.
out="$(FT_REACH_COUNT_ONLY=1 run_tool "$e" "$REACH" byz-satnano-nano-theta#0 "PROBE-G" 2>&1)"; rc=$?
trim="$(printf '%s' "$out" | tr -d '[:space:]')"
if [ "$rc" = 0 ] && [ "$trim" = 0 ]; then pass "ⓖ baseline(COUNT_ONLY) = 0 · rc0 (디렉터리 없어도)"
else fail "ⓖ baseline rc=$rc out=$out (기대 rc0 · 0)"; fi
# ② 전체 경로: 보내면 좌석이 폴더+사용자 턴을 만들고 판정 = REACHED
out="$(run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-theta#0 "PROBE-G-1" 2>&1)"; rc=$?
n="$(awk -F'\t' '$2=="TEXT" && $3 ~ /PROBE-G-1/ { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
if [ "$rc" = 0 ] && [ "$n" = 1 ]; then pass "ⓖ 새 좌석 송신 = REACHED(rc0) · 원격 send 1회"
else fail "ⓖ 새 좌석 판정 rc=$rc n=$n (기대 rc0 · 1) out=$out"; fi
case "$out" in *"verification=not-reached"*) fail "ⓖ 도착했는데 not-reached 로 뒤집힘(h146 그 증상)" ;; *) pass "ⓖ not-reached 오판 0" ;; esac
if [ -f "$e/home/.claude/projects/$enc/a.jsonl" ] && grep -qF 'PROBE-G-1' "$e/home/.claude/projects/$enc/a.jsonl" 2>/dev/null; then
  pass "ⓖ 첫 제출이 폴더+사용자 턴을 만들었다"
else fail "ⓖ jsonl 디렉터리/사용자 턴 안 생김"; fi

# 변이 ① — COUNT_ONLY 가 «기록 디렉터리 없음» 검사를 «먼저» 하던 옛 순서로 되돌리면 ⓖ 가 NOT_REACHED(rc≠0) 로 뒤집힌다.
mutg="$T/reach-mut-order.sh"
{ printf '#!/usr/bin/env bash\n'
  printf 'if [ -n "${FT_REACH_COUNT_ONLY:-}" ]; then\n'
  printf '  cwd=$(tmux display-message -p -t "$1" %s 2>/dev/null)\n' "'#{pane_current_path}'"
  printf '  enc=$(printf %%s "$cwd" | LC_ALL=C sed %s)\n' "'s|[^A-Za-z0-9]|-|g'"
  printf '  [ -d "$HOME/.claude/projects/$enc" ] || { echo "UNVERIFIABLE jsonl dir 없음(옛 순서)" >&2; exit 5; }\n'
  printf 'fi\n'
  printf 'exec bash %s "$@"\n' "$(printf '%q' "$REACH")"
} > "$mutg"; chmod +x "$mutg"
eg="$T/g-mut"; rm -rf "$eg"; cp -R "$e" "$eg"; : > "$eg/state/sent.log"; rm -rf "$eg/home/.claude/projects"
mk_socket "$eg/home/.ssh/ft-cm/mini"
mout="$(REACH_OVERRIDE="$mutg" run_tool "$eg" "$TMUXC" send mini/byz-satnano-nano-theta#0 "PROBE-G-M" 2>&1)"; mrc=$?
[ "$mrc" != 0 ] && pass "ⓖ 변이 FAIL 확인(옛 순서 → rc=$mrc ≠ 0)" \
  || fail "ⓖ 변이 미검출 — 옛 순서인데도 rc0 out=$mout"

# ── ⓗ baseline 호출 실패 → «판정 불가 rc5» (REACHED·NOT_REACHED 둘 다 아님) ────────
# baseline 이 실패했는데 빈 값으로 넘기면 판정기가 «보낸 뒤» 자기 baseline 을 잡아 미도달로 오판한다.
e="$T/h"; mk_env "$e"
mk_seat "$e" byz-satnano-nano-iota#0 "$e/remote/repo" claude
add_jsonl "$e" "$e/remote/repo" byz-satnano-nano-iota#0 record
wrap="$T/reach-baseline-fail.sh"
{ printf '#!/usr/bin/env bash\n'
  printf 'if [ -n "${FT_REACH_COUNT_ONLY:-}" ]; then echo "UNVERIFIABLE 주입: baseline 실패" >&2; exit 5; fi\n'
  printf 'exec bash %s "$@"\n' "$(printf '%q' "$REACH")"
} > "$wrap"; chmod +x "$wrap"
out="$(REACH_OVERRIDE="$wrap" run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-iota#0 "PROBE-H-1" 2>&1)"; rc=$?
n="$(awk -F'\t' '$2=="TEXT" && $3 ~ /PROBE-H-1/ { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
if [ "$rc" = 5 ] && [ "$n" = 1 ]; then pass "ⓗ baseline rc5 → 판정 불가 rc5 · 송신은 했다(1회)"
else fail "ⓗ rc=$rc n=$n (기대 rc5 · 1) out=$out"; fi
case "$out" in
  *"verification=unverifiable"*) pass "ⓗ unverifiable 줄" ;;
  *"delivered="*|*"verification=not-reached"*) fail "ⓗ REACHED/NOT_REACHED 로 단정함: $out" ;;
  *) fail "ⓗ 판정 줄 없음: $out" ;;
esac
# tmm 도 같은 계약(R6 = 원격 쓰기 경로가 둘이다)
tout="$(REACH_OVERRIDE="$wrap" run_tool "$e" "$TMM" s mini/byz-satnano-nano-iota#0 "PROBE-H-2" 2>&1)"; trc=$?
tn="$(awk -F'\t' '$2=="TEXT" && $3 ~ /PROBE-H-2/ { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
if [ "$trc" = 5 ] && [ "$tn" = 1 ]; then pass "ⓗ tmm s 도 판정 불가 rc5 · 송신 1회"
else fail "ⓗ tmm s rc=$trc n=$tn (기대 rc5 · 1) out=$tout"; fi

# 변이 ② — baseline 실패를 다시 «빈 값» 으로 삼키면 ⓗ 가 rc5 가 아니라 4(NOT_REACHED) 로 뒤집힌다.
mvh="$T/tmuxc-mut-emptybase"; cp "$TMUXC" "$mvh"
python3 - "$mvh" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = 'base="$(remote_reach_baseline "$R_HOST" "$R_SESS" "$*" 2>/dev/null)" || baserc=$?'
assert old in s, "변이 지점 1 없음"
s = s.replace(old, 'base="$(remote_reach_baseline "$R_HOST" "$R_SESS" "$*" 2>/dev/null)" || base=""', 1)
s2, k = re.subn(r'\n *if \[\[ "\$baserc" -ne 0 \]\]; then.*?\n *fi\n', '\n', s, count=1, flags=re.S)
assert k == 1, "변이 지점 2 없음"
open(p, "w", encoding="utf-8").write(s2)
PY
: > "$e/state/sent.log"
hmout="$(REACH_OVERRIDE="$wrap" run_tool "$e" "$mvh" send mini/byz-satnano-nano-iota#0 "PROBE-H-M" 2>&1)"; hmrc=$?
# 옛 동작은 판정 불가가 아니라 «REACHED(0) 아니면 NOT_REACHED(4)» 로 단정해 버린다.
# (둘 중 어느 쪽으로 떨어지는지는 jsonl 쓰기 시점에 달렸다 — 어느 쪽이든 rc5 가 아니면 변이 검출이다.)
if [ "$hmrc" = 0 ] || [ "$hmrc" = 4 ]; then pass "ⓗ 변이 FAIL 확인(빈 값으로 삼킴 → rc=$hmrc · 판정 불가 아님)"
else fail "ⓗ 변이 미검출 rc=$hmrc (기대 0 또는 4) out=$hmout"; fi

# ── ⓘ r1075 — 원격 주입 = 로컬 agent_inject 절차(상자 기다림 → 입력줄 전문 확인 → session-id 기록 판정 → 재전송 1) ──
# 반례 집합 r2(arch#173 · #182367 · 동결): R1 상자 3초 뒤 → 기다렸다 넣음 · rc0 / R2 상한 안에 안 뜸 → send 0 · rc5 not-ready /
#  R3 이미 상자 있음 → 기다림 0 / R4 원격 open --session-id 1개 + env 같은 값 + 판정이 그 파일(warn 0) /
#  R5 TMUXC_READY_MAX 빈 값·글자 → 30 / R6 글자가 1초 뒤 완성 → Enter 는 전문 뒤 1번 · rc0 / R7 첫 Enter 삼킴 → 재전송 1번 · Enter 총 2 · rc0
t0="$(now_ms)"
e="$T/i"; mk_env "$e"
SID1="11111111-1111-1111-1111-111111111111"
SID2="22222222-2222-2222-2222-222222222222"
SID3="33333333-3333-3333-3333-333333333333"

# R1 — 상자를 3초 뒤에 그리는 좌석 → 기다렸다 넣고 제출 확인(rc0)
mk_seat "$e" byz-satnano-nano-r1#0 "$e/remote/repo" claude
seat_props "$e" byz-satnano-nano-r1#0 "$SID1" 3
: > "$e/state/sessions/byz-satnano-nano-r1#0/record"
st1="$(cat "$e/state/sessions/byz-satnano-nano-r1#0/start")"
out="$(TMUXC_READY_MAX=10 TMUXC_SUBMIT_WAIT=2 run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-r1#0 "R1-BODY-ONE" 2>&1)"; rc=$?
txt_ts="$(awk -F'\t' '$2=="TEXT" && $3 ~ /R1-BODY-ONE/ { print $5 }' "$e/state/sent.log" 2>/dev/null | tail -1)"
n="$(awk -F'\t' '$2=="TEXT" && $3 ~ /R1-BODY-ONE/ { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
if [ "$rc" = 0 ] && [ "$n" = 1 ] && [ -n "$txt_ts" ] && [ $(( txt_ts - st1 )) -ge 3 ]; then
  pass "R1 상자 3초 뒤 → 기다렸다 넣음(wait $(( txt_ts - st1 ))s) · rc0 · send-keys 1"
else fail "R1 rc=$rc n=$n wait=$(( ${txt_ts:-0} - ${st1:-0} ))s (기대 rc0·1회·≥3s) out=$out"; fi

# R2 — 상한 안에 상자가 안 뜸 → send-keys 0 · rc5 state=not-ready
mk_seat "$e" byz-satnano-nano-r2#0 "$e/remote/repo" claude
seat_props "$e" byz-satnano-nano-r2#0 "$SID2" 999
out="$(TMUXC_READY_MAX=2 TMUXC_SUBMIT_WAIT=1 run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-r2#0 "R2-BODY" 2>&1)"; rc=$?
n="$(awk -F'\t' '$2=="TEXT" && $3 ~ /R2-BODY/ { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
e2="$(awk -F'\t' '$1=="byz-satnano-nano-r2#0" && $2=="ENTER" { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
if [ "$rc" = 5 ] && [ "$n" = 0 ] && [ "$e2" = 0 ]; then pass "R2 상자 안 뜸 → rc5 · send-keys 0 · Enter 0"
else fail "R2 rc=$rc text=$n enter=$e2 (기대 rc5·0·0) out=$out"; fi
case "$out" in *state=not-ready*) pass "R2 state=not-ready 줄(주입 0 사유)" ;; *) fail "R2 not-ready 줄 없음: $out" ;; esac

# R3 — 이미 상자가 떠 있는 좌석 → 기다림 0 · rc0
mk_seat "$e" byz-satnano-nano-r3#0 "$e/remote/repo" claude
seat_props "$e" byz-satnano-nano-r3#0 "$SID3"
: > "$e/state/sessions/byz-satnano-nano-r3#0/record"
k0="$(now_ms)"
out="$(TMUXC_READY_MAX=10 TMUXC_SUBMIT_WAIT=2 run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-r3#0 "R3-BODY" 2>&1)"; rc=$?
el3=$(( $(now_ms) - k0 ))
if [ "$rc" = 0 ] && [ "$el3" -lt 3000 ]; then pass "R3 이미 상자 → 기다림 0(${el3}ms) · rc0"
else fail "R3 rc=$rc ${el3}ms (기대 rc0·<3000ms) out=$out"; fi

# R4 — 원격 open claude = --session-id 1개 · env 같은 값 · ft-reach-check 가 그 파일로 특정(warn 0)
mf="claude-sonnet-5-5"
dout="$(run_tool "$e" "$TMUXC" open "$e/remote/repo" --host mini --name byz-satnano-nano-r4#0 --agent claude --model "$mf" --dry-run 2>&1)"
n_sid="$(printf '%s\n' "$dout" | grep -oE -- '--session-id [0-9a-f-]{36}' | wc -l | tr -d ' ')"
case "$dout" in *'command='*'--session-id '*) pass "R4 dry-run 명령에 --session-id 1개" ;; *) fail "R4 dry-run session-id 없음: $dout" ;; esac
run_tool "$e" "$TMUXC" open "$e/remote/repo" --host mini --name byz-satnano-nano-r4#0 --agent claude --model "$mf" >/dev/null 2>&1
cmd_sid="$(awk -F'\t' '$2=="TEXT" && $3 ~ /--session-id/ { print $3; exit }' "$e/state/sent.log" 2>/dev/null | grep -oE -- '--session-id [0-9a-f-]{36}' | awk '{print $2}')"
env_sid="$(awk -F= '$1=="TMUXC_CLAUDE_SESSION_ID"{print $2; exit}' "$e/state/sessions/byz-satnano-nano-r4#0/env" 2>/dev/null)"
if [ -n "$cmd_sid" ] && [ "$cmd_sid" = "$env_sid" ]; then pass "R4 명령·env 의 session-id 같다(${cmd_sid:0:8}…)"
else fail "R4 cmd_sid=$cmd_sid env_sid=$env_sid (기대 같은 uuid)"; fi
# 그 id 의 기록으로 판정되고 warn(디렉터리 전수) 줄이 없어야 한다
enc="$(printf '%s' "$e/remote/repo" | sed 's|[^A-Za-z0-9]|-|g')"
mkdir -p "$e/home/.claude/projects/$enc"
printf '{"type":"user","message":{"content":"PROBE-R4"}}\n' > "$e/home/.claude/projects/$enc/$cmd_sid.jsonl"
rout="$(run_tool "$e" "$REACH" byz-satnano-nano-r4#0 "PROBE-R4" 2 0 2>&1)"; rrc=$?
if [ "$rrc" = 0 ]; then pass "R4 도달 판정이 그 id 파일로 REACHED"; else fail "R4 reach rc=$rrc out=$rout"; fi
case "$rout" in *"warn: 좌석 파일 특정 실패"*) fail "R4 warn 줄 있음(전수 폴백) : $rout" ;; *) pass "R4 warn 줄 0(디렉터리 전수 아님)" ;; esac

# R5 — TMUXC_READY_MAX 가 글자 → 30 으로 정규화(기록 id 없는 좌석은 rc6 + ready_max=30 줄)
mk_seat "$e" byz-satnano-nano-r5#0 "$e/remote/repo" claude
out="$(TMUXC_READY_MAX="abc" TMUXC_SUBMIT_WAIT=1 run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-r5#0 "R5-BODY" 2>&1)"; rc=$?
case "$out" in *ready_max=30*) pass "R5 글자 상한 → ready_max=30 (rc=$rc)" ;; *) fail "R5 정규화 안 됨: $out" ;; esac
# 기록 id 없는 좌석은 내부 신호 rc6 → 호출자가 ft-reach-check 로 넘긴다(이 시험의 최종 rc = 그 판정).
case "$out" in *state=sent-no-id*) pass "R5 기록 id 없는 좌석 = rc6 내부 신호 후 reach 판정(rc=$rc)" ;; *) fail "R5 sent-no-id 줄 없음: $out" ;; esac

# R6 — 글자가 1초 뒤에 다 그려짐 → Enter 는 전문이 그려진 뒤 1번 · rc0
SID6="66666666-6666-6666-6666-666666666666"
mk_seat "$e" byz-satnano-nano-r6#0 "$e/remote/repo" claude
seat_props "$e" byz-satnano-nano-r6#0 "$SID6" "" 1
: > "$e/state/sessions/byz-satnano-nano-r6#0/record"
out="$(TMUXC_READY_MAX=10 TMUXC_SUBMIT_WAIT=3 run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-r6#0 "R6-BODY-LONG-ENOUGH" 2>&1)"; rc=$?
n_enter="$(awk -F'\t' '$1=="byz-satnano-nano-r6#0" && $2=="ENTER" { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
gap="$(awk -F'\t' '$1=="byz-satnano-nano-r6#0" { if ($2=="TEXT") t=$5; else if ($2=="ENTER" && !t2) t2=$5 } END{ print (t2&&t)?t2-t:0 }' "$e/state/sent.log" 2>/dev/null)"
if [ "$rc" = 0 ] && [ "$n_enter" = 1 ] && [ "${gap:-0}" -ge 1 ]; then pass "R6 그리기 지연 → Enter 전문 뒤 1번(gap ${gap}s) · rc0"
else fail "R6 rc=$rc enters=$n_enter gap=${gap:-0} (기대 rc0·1·≥1s) out=$out"; fi
case "$out" in *delivered=*) pass "R6 제출 확인(delivered) 줄" ;; *) fail "R6 delivered 줄 없음: $out" ;; esac

# R7 — 첫 Enter 가 삼켜짐 → 절반 시점 재전송 1번 · Enter 총 2 · rc0
SID7="77777777-7777-7777-7777-777777777777"
mk_seat "$e" byz-satnano-nano-r7#0 "$e/remote/repo" claude
seat_props "$e" byz-satnano-nano-r7#0 "$SID7" "" "" swallow
: > "$e/state/sessions/byz-satnano-nano-r7#0/record"
out="$(TMUXC_READY_MAX=10 TMUXC_SUBMIT_WAIT=4 run_tool "$e" "$TMUXC" send mini/byz-satnano-nano-r7#0 "R7-BODY" 2>&1)"; rc=$?
n_enter="$(awk -F'\t' '$1=="byz-satnano-nano-r7#0" && $2=="ENTER" { n++ } END{ print n+0 }' "$e/state/sent.log" 2>/dev/null)"
if [ "$rc" = 0 ] && [ "$n_enter" = 2 ]; then pass "R7 첫 Enter 삼킴 → 재전송 1회(총 2) · rc0"
else fail "R7 rc=$rc enters=$n_enter (기대 rc0·2) out=$out"; fi
el_i=$(( $(now_ms) - t0 ))
printf 'info ⓘ R1~R7 합계 %sms\n' "$el_i"
[ "$el_i" -le 70000 ] && pass "ⓘ 단계 초 ${el_i}ms (≤70000)" || fail "ⓘ 단계 초 ${el_i}ms > 70000"

# ── 변이 3 (r1075) — libexec/agent-inject.sh 사본을 뜯어 고친다(자기 파일 재호출 0) ──
# 변이 ①: 상자 기다림 끔 → R1 이 rc0 이 아니게 된다(상자 전 주기 = 판독 불가)
em1="$T/i-mut1"; rm -rf "$em1"; cp -R "$e" "$em1"; : > "$em1/state/sent.log"
rm -f "$em1/state/sessions/byz-satnano-nano-r1#0/enters"; date +%s > "$em1/state/sessions/byz-satnano-nano-r1#0/start"
mk_socket "$em1/home/.ssh/ft-cm/mini"
ml1="$T/lib-mut-nowait"; cp "$INJECT_LIB" "$ml1"
python3 - "$ml1" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '  if ! wait_input_box "$pane" "$ready_max"; then'
assert old in s, "변이 지점 없음"
s = s.replace(old, '  if false; then', 1)
open(p, "w", encoding="utf-8").write(s)
PY
mout="$(INJECT_LIB_OVERRIDE="$ml1" TMUXC_READY_MAX=10 TMUXC_SUBMIT_WAIT=2 run_tool "$em1" "$TMUXC" send mini/byz-satnano-nano-r1#0 "R1-MUT" 2>&1)"; mrc=$?
[ "$mrc" != 0 ] && pass "변이① FAIL 확인(상자 기다림 끔 → rc=$mrc ≠ 0)" || fail "변이① 미검출(기다림 없이도 rc0) out=$mout"

# 변이 ②: 입력줄 전문 확인을 0.3초 고정 대기로 되돌리면 R6 이 깨진다(잘린 글이 제출됨)
em2="$T/i-mut2"; rm -rf "$em2"; cp -R "$e" "$em2"; : > "$em2/state/sent.log"
rm -f "$em2/state/sessions/byz-satnano-nano-r6#0/enters"
rm -f "$em2/home/.claude/projects/"*/*.jsonl
# 그리기 지연을 2초로 바꿔 «0.3초 고정 대기» 가 확실히 잘린 글자를 제출하게 만든다(초 경계 흔들림 제거).
printf '2\n' > "$em2/state/sessions/byz-satnano-nano-r6#0/draw_delay"
mk_socket "$em2/home/.ssh/ft-cm/mini"
ml2="$T/lib-mut-confirm"; cp "$INJECT_LIB" "$ml2"
python3 - "$ml2" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
start = s.index('  # ② 그리기 지연을 짧게 기다린다')
end = s.index('  case "$st" in', start)
s = s[:start] + '  sleep 0.3\n  st=0\n' + s[end:]
open(p, "w", encoding="utf-8").write(s)
PY
mout="$(INJECT_LIB_OVERRIDE="$ml2" TMUXC_READY_MAX=10 TMUXC_SUBMIT_WAIT=3 run_tool "$em2" "$TMUXC" send mini/byz-satnano-nano-r6#0 "R6-MUT-BODY" 2>&1)"; mrc=$?
m_enter="$(awk -F'\t' '$1=="byz-satnano-nano-r6#0" && $2=="ENTER" { n++ } END{ print n+0 }' "$em2/state/sent.log" 2>/dev/null)"
# 변이② 의 증상은 «rc≠0» 이 아니라 «Enter 가 일찌감치 여러 번 / 잘린 글이 제출됨» 이다 — 그 축으로 잡는다.
if [ "$mrc" != 0 ] || [ "$m_enter" != 1 ]; then pass "변이② FAIL 확인(입력줄 확인 끔 → Enter ${m_enter}회 · rc=$mrc)"
else fail "변이② 미검출(rc=0 · Enter 1) out=$mout"; fi

# 변이 ③: 재전송을 끄면 R7 이 rc0 이 아니게 된다(첫 Enter 삼킴 그대로)
em3="$T/i-mut3"; rm -rf "$em3"; cp -R "$e" "$em3"; : > "$em3/state/sent.log"
rm -f "$em3/state/sessions/byz-satnano-nano-r7#0/enters"
rm -f "$em3/home/.claude/projects/"*/*.jsonl
mk_socket "$em3/home/.ssh/ft-cm/mini"
ml3="$T/lib-mut-resend"; cp "$INJECT_LIB" "$ml3"
python3 - "$ml3" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '    if [[ "$resent" -eq 0 && "$now" -ge "$t_mid" ]]; then'
assert old in s, "변이 지점 없음"
s = s.replace(old, '    if false; then', 1)
open(p, "w", encoding="utf-8").write(s)
PY
mout="$(INJECT_LIB_OVERRIDE="$ml3" TMUXC_READY_MAX=10 TMUXC_SUBMIT_WAIT=4 run_tool "$em3" "$TMUXC" send mini/byz-satnano-nano-r7#0 "R7-MUT" 2>&1)"; mrc=$?
[ "$mrc" != 0 ] && pass "변이③ FAIL 확인(재전송 끔 → rc=$mrc ≠ 0)" || fail "변이③ 미검출 rc=$mrc out=$mout"

echo "---"
[ "$FAIL" = 0 ] && { echo "ALL PASS"; exit 0; }
echo "FAILED $FAIL"
exit 1
