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

# ===== 공용 대역(쪼갠 두 시험이 함께 쓴다 · r1075 · arch#173 반송 r3) =====
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

