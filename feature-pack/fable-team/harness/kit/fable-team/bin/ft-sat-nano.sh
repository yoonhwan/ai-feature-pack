#!/usr/bin/env bash
# ft-sat-nano.sh — 위성(mini) 나노 도구 하나 (r902 · arch 140 발주 2026-10-25)
#   골 축: 하네스 골 C «메인 하네스를 유니크하게 머신들에 완전히 독립 배분해 운용» — 이 맥 대신 mini 에 작업 좌석을 열고 쓰고 닫는다.
#   원형 흡수: docs/multihost/satellite/sat-mbox.py(push/pull/dedupe/ack) + h-mini-satellite-nano-test.sh(열기·작업·회수·닫기) — ba9de431
#   명령: open <카드파일> [--run R] [--name N] · task <세션> <파일> · pull --seats A,B [--every N] · fetch <세션> · close <세션>
#   ★닫기는 «이 도구가 연 세션만» — opened.tsv 에 없으면 REJECT(남의 세션·프로세스 kill 0). 확인 실패면 강제 kill 없이 rc6 으로 표시만.★
#   ★원격 쓰기 = mini 의 ~/Project/satellite-nano/<run>/ 와 mini 쪽지함뿐. BYZ 소스·서버·Redis·settings·authorized_keys 접촉 0.★
#   ★7초 룰: 원격 호출 한 번은 SAT_TMO(기본 7초) 를 넘지 않는다(open 의 tmuxc 만 SAT_OPEN_TMO). 넘으면 rc5.★
#   env: MINI(mini) · SAT_TMO(7) · SAT_OPEN_TMO(45) · SAT_ROOT_REMOTE(Project/satellite-nano) · SAT_MODEL
#        SAT_STATE_DIR(~/.fable-team/sat) · SAT_MINI_MBOX_PY · SAT_MBOX_SH · SAT_OUT_DIR(harness/evidence/r902)
#        SAT_NOWAIT(1=pi 기동 대기 생략·시험용) · SAT_SEAT(pull 기본 수신자) · SAT_PULL_MAX(30)
#   rc: 0 ok · 2 usage/전제실패 · 3 세션 열기 실패 · 4 전달 실패 · 5 원격 실패·시간 초과 · 6 닫기 확인 실패
set -uo pipefail
MINI="${MINI:-mini}"; TMO="${SAT_TMO:-7}"; OTMO="${SAT_OPEN_TMO:-45}"
RROOT="${SAT_ROOT_REMOTE:-Project/satellite-nano}"
MODEL="${SAT_MODEL:-opengateway/deepseek/deepseek-v4.1-flash-ultrafast}"
STATE="${SAT_STATE_DIR:-$HOME/.fable-team/sat}"
OPENED="$STATE/opened.tsv"    # name<TAB>run<TAB>dir<TAB>ts
DELIVERED="$STATE/delivered"  # mini:<seq> 한 줄씩(같은 쪽지 2번 배달 0)
HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTD="${SAT_OUT_DIR:-$HARNESS/evidence/r902}"
MPY="${SAT_MINI_MBOX_PY:-\$HOME/.claude/skills/fable-team/scripts/ft-mbox.py}"
SO=(-o BatchMode=yes -o ConnectTimeout=6 -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
say() { printf '[sat] %s\n' "$*"; }
die() { printf '[sat] REJECT rc=%s %s\n' "$1" "$2" >&2; exit "$1"; }
rsh() { local t="$1"; shift; timeout "$t" ssh "${SO[@]}" "$MINI" "export PATH=/opt/homebrew/bin:\$HOME/.local/bin:\$PATH; $*"; }
_opened() { cut -f1 "$OPENED" 2>/dev/null | grep -qxF -- "$1"; }
_seen() { grep -qxF -- "$1" "$DELIVERED" 2>/dev/null; }
field() { awk -F'\t' -v n="$1" -v c="$2" '$1==n{print $c}' "$OPENED" 2>/dev/null; }
mbox_sh() {
  [ -n "${SAT_MBOX_SH:-}" ] && { printf '%s' "$SAT_MBOX_SH"; return 0; }
  local c
  for c in "$HOME/.claude/skills/fable-team/scripts/ft-mbox.sh" "$HARNESS/kit/fable-team/bin/ft-mbox.sh" "$HARNESS/bin/ft-mbox.sh"; do
    [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}
pre() { # 원격 사전점검 — key=value 한 덩어리
  rsh "$TMO" "echo tmuxc=\$(command -v tmuxc >/dev/null && echo ok || echo MISSING); echo pi=\$(command -v pi >/dev/null && echo ok || echo MISSING); echo sess=\$(tmux has-session -t '=$1' 2>/dev/null && echo EXISTS || echo absent); echo dir=\$([ -e \$HOME/$2 ] && echo EXISTS || echo absent)" 2>&1
}
wait_pi() { # HARD GATE — pane 자식 프로세스 1개 이상(최대 30초)
  local i n
  for i in 1 2 3 4 5 6; do
    n="$(rsh "$TMO" "pp=\$(tmux display -p -t '=$1:' '#{pane_pid}' 2>/dev/null); [ -n \"\$pp\" ] && pgrep -P \$pp | wc -l | tr -d ' '" 2>/dev/null)"
    [ "${n:-0}" -ge 1 ] 2>/dev/null && return 0
    sleep 5
  done
  return 1
}
sendtask() { # $1=세션 $2=원격 상대경로 — -l 과 Enter 는 별도 호출
  local msg="[발주 #1] \$HOME/$2 를 읽고 그대로 수행해라. 결과는 같은 폴더 out.md."
  rsh "$TMO" "tmux send-keys -t '=$1:' -l \"$msg\"" >/dev/null 2>&1 || return 1
  sleep 1
  rsh "$TMO" "tmux send-keys -t '=$1:' Enter" >/dev/null 2>&1 || return 1
}

cmd_open() {
  local card="${1:-}"; [ $# -gt 0 ] && shift; local run="" name="byz-sat-nano-pi#0"
  while [ $# -gt 0 ]; do case "$1" in --run) run="${2:?}"; shift 2;; --name) name="${2:?}"; shift 2;; *) die 2 "usage open <카드파일> [--run R] [--name N]";; esac; done
  [ -n "$card" ] && [ -f "$card" ] || die 2 "카드 파일이 없다: ${card:-<없음>}"
  [ -n "$run" ] || run="$(basename "$card" | sed 's/\.[^.]*$//' | tr -c 'A-Za-z0-9._-' '-' | cut -c1-40)"
  local dir="$RROOT/$run" p
  p="$(pre "$name" "$dir")" || die 5 "mini 접속 실패: ${p:-<무응답>}"
  printf '%s\n' "$p" | sed 's/^/[sat]   /'
  case "$p" in *MISSING*) die 2 "mini 에 필요한 도구가 없다(위 MISSING)";; esac
  case "$p" in *sess=EXISTS*) die 2 "같은 이름 세션이 이미 있다 — 남의 세션이라 건드리지 않는다: $name";; esac
  case "$p" in *dir=EXISTS*) die 2 "작업 폴더가 이미 있다 — --run <다른이름> 으로 다시: $dir";; esac
  mkdir -p "$STATE" || die 2 "상태 폴더 생성 실패: $STATE"
  rsh "$TMO" "mkdir -p \$HOME/$dir && cat > \$HOME/$dir/TASK.md" <"$card" >/dev/null || die 4 "TASK.md 쓰기 실패"
  say "1/4 작업 폴더·TASK.md — $dir/TASK.md"
  local op; op="$(rsh "$OTMO" "tmuxc open \$HOME/$dir --name '$name' --agent pi --role worker --model '$MODEL' --effort medium 2>&1" 2>&1)" \
    || die 3 "tmuxc open 실패: $(printf '%s' "$op" | tail -3)"
  printf '%s\n' "$op" | tail -4 | sed 's/^/[sat]   /'
  printf '%s\t%s\t%s\t%s\n' "$name" "$run" "$dir" "$(date -u +%FT%TZ)" >>"$OPENED"
  say "2/4 세션 열기 — $name (이 도구가 연 세션으로 기록)"
  if [ "${SAT_NOWAIT:-0}" != "1" ]; then
    wait_pi "$name" || die 3 "pi 프로세스가 안 떴다(HARD GATE: 자식 0건 — 입력 전송 금지)"
    say "3/4 pi 기동 확인"
  fi
  sendtask "$name" "$dir/TASK.md" || die 4 "지시 전달 실패"
  say "4/4 지시 전달 — TASK.md · 회수 fetch $name · 닫기 close $name"
}

cmd_task() {
  local name="${1:-}" file="${2:-}"
  [ -n "$name" ] && [ -f "${file:-}" ] || die 2 "usage task <세션> <파일>"
  _opened "$name" || die 5 "이 도구가 연 세션이 아니다 — 남의 세션에는 쓰지 않는다: $name"
  local dir sum target; dir="$(field "$name" 3)"; [ -n "$dir" ] || die 2 "상태 기록이 깨졌다: $name"
  sum="$(shasum -a 256 "$file" | cut -c1-8)"; target="$dir/TASK-$sum.md"
  if rsh "$TMO" "[ -f \$HOME/$target ]" >/dev/null 2>&1; then say "SKIP 같은 작업이 이미 전달됐다(중복 0) — $target"; exit 0; fi
  rsh "$TMO" "cat > \$HOME/$target" <"$file" >/dev/null || die 4 "작업 파일 전달 실패: $target"
  sendtask "$name" "$target" || die 4 "지시 전달 실패"
  say "TASK ok run=$(field "$name" 2) file=$target"
}

cmd_pull() {
  local seats="${SAT_SEAT:-}" every=0
  while [ $# -gt 0 ]; do case "$1" in --seats) seats="${2:?}"; shift 2;; --every) every="${2:?}"; shift 2;; *) die 2 "usage pull --seats A,B [--every N]";; esac; done
  [ -n "$seats" ] || die 2 "수신 좌석이 없다 — pull --seats A,B (또는 SAT_SEAT)"
  local mb; mb="$(mbox_sh)" || die 2 "이 맥 ft-mbox.sh 를 못 찾았다(SAT_MBOX_SH 로 지정)"
  mkdir -p "$STATE" || die 2 "상태 폴더 생성 실패: $STATE"
  local READ_PY ACK_PY
  READ_PY="import importlib.util,json,os,sys;s=importlib.util.spec_from_file_location('m',os.path.expandvars('$MPY'));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);seats=set(sys.argv[1].split(','));rows=m._locked(m.CANON,lambda:[r for r in m._load(m.CANON) if r.get('to') in seats]);print(json.dumps(rows,ensure_ascii=False))"
  ACK_PY="import importlib.util,json,os,sys;s=importlib.util.spec_from_file_location('m',os.path.expandvars('$MPY'));m=importlib.util.module_from_spec(s);s.loader.exec_module(m);seqs=set(json.loads(sys.argv[1]))
def op():
  rows=m._load(m.CANON);keep=[r for r in rows if r.get('seq') not in seqs]
  if len(keep)!=len(rows): m._save(m.CANON,keep)
  print(len(rows)-len(keep))
m._locked(m.CANON,op)"
  local i=0 max="${SAT_PULL_MAX:-30}" rows plan ok seq to frm b64 key body
  while :; do
    i=$((i + 1))
    rows="$(rsh "$TMO" "python3 -c \"\$(cat)\" '$seats'" <<<"$READ_PY" 2>&1)" || die 5 "mini 쪽지함 읽기 실패: $(printf '%s' "$rows" | tail -2)"
    plan="$(python3 -c 'import base64,json,sys
for r in json.loads(sys.argv[1] or "[]"):
  print("\t".join([str(r.get("seq")), str(r.get("to","")), str(r.get("from","")), base64.b64encode(str(r.get("body","")).encode()).decode()]))' "$rows" 2>/dev/null)" || die 5 "mini 쪽지함 응답 해석 실패"
    ok=""
    while IFS=$'\t' read -r seq to frm b64; do
      [ -n "${seq:-}" ] || continue
      key="mini:$seq"
      _seen "$key" && { ok="$ok $seq"; continue; }
      body="$(printf '%s' "$b64" | base64 -d 2>/dev/null)"
      if bash "$mb" send "$to" "$frm" "$body" 2>&1 | grep -q QUEUED; then
        printf '%s\n' "$key" >>"$DELIVERED"; ok="$ok $seq"
      else
        say "DELIVER_FAIL seq=$seq (ack 안 함 — 다음 pull 에서 재시도)"
      fi
    done <<<"$plan"
    local ackjson; ackjson="[$(printf '%s' "$ok" | tr ' ' '\n' | grep -v '^$' | paste -sd, -)]"
    if [ "$ackjson" != "[]" ]; then
      rsh "$TMO" "python3 -c \"\$(cat)\" '$ackjson'" <<<"$ACK_PY" >/dev/null \
        || say "ACK_FAIL (다음 pull 에서 중복 없이 재시도)"
    fi
    say "PULL ok seen=$(printf '%s\n' "$plan" | grep -c . ) delivered=$(printf '%s' "$ok" | wc -w | tr -d ' ') every=$every turn=$i"
    [ "$every" -gt 0 ] 2>/dev/null || break
    [ "$i" -lt "$max" ] || break
    sleep "$every"
  done
}

cmd_fetch() {
  local name="${1:-}"; [ -n "$name" ] || die 2 "usage fetch <세션>"
  _opened "$name" || die 5 "이 도구가 연 세션이 아니다: $name"
  local run dir f dest n=0; run="$(field "$name" 2)"; dir="$(field "$name" 3)"
  [ -n "$run" ] && [ -n "$dir" ] || die 2 "상태 기록이 깨졌다: $name"
  mkdir -p "$OUTD/$run" || die 2 "회수 폴더 생성 실패: $OUTD/$run"
  for f in out.md TASK.md; do
    dest="$OUTD/$run/$f"
    if rsh "$TMO" "cat \$HOME/$dir/$f 2>/dev/null" >"$dest" 2>/dev/null && [ -s "$dest" ]; then
      n=$((n + 1)); say "FETCH $dest"
    else
      rm -f "$dest"
    fi
  done
  [ "$n" -gt 0 ] || die 5 "회수할 결과가 없다(아직 안 썼거나 경로가 다르다): $dir"
  say "FETCH ok run=$run files=$n"
}

cmd_close() {
  local name="${1:-}"; [ -n "$name" ] || die 2 "usage close <세션>"
  _opened "$name" || die 5 "이 도구가 연 세션이 아니다 — 남의 세션은 닫지 않는다: $name"
  local dir out; dir="$(field "$name" 3)"; [ -n "$dir" ] || die 2 "상태 기록이 깨졌다: $name"
  out="$(rsh "$TMO" "tmux kill-session -t '=$name' 2>&1; sleep 2; left=\$(for p in \$(pgrep -x pi 2>/dev/null); do c=\$(lsof -a -p \$p -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'); case \"\$c\" in \"\$HOME/$dir\"*) echo \$p;; esac; done | wc -l | tr -d ' '); s=\$(tmux has-session -t '=$name' 2>/dev/null && echo alive || echo gone); echo session=\$s pi_left=\$left" 2>&1)"
  printf '%s\n' "$out" | sed 's/^/[sat]   /'
  grep -q "session=gone pi_left=0" <<<"$out" || die 6 "닫기 확인 실패 — 세션/프로세스가 남았다(강제 kill 은 하지 않는다): $name"
  grep -vF "$name"$'\t' "$OPENED" >"$OPENED.tmp" 2>/dev/null; mv "$OPENED.tmp" "$OPENED" 2>/dev/null
  say "CLOSE ok $name — 세션 없음 · 이 폴더에서 도는 pi 0"
}

case "${1:-}" in
  open)  shift; cmd_open "$@" ;;
  task)  shift; cmd_task "$@" ;;
  pull)  shift; cmd_pull "$@" ;;
  fetch) shift; cmd_fetch "$@" ;;
  close) shift; cmd_close "$@" ;;
  *) echo "usage: ft-sat-nano.sh {open <카드파일> [--run R] [--name N]|task <세션> <파일>|pull --seats A,B [--every N]|fetch <세션>|close <세션>}" >&2; exit 2 ;;
esac
