#!/usr/bin/env bash
# ft-successor-open.sh <구 좌석> <워크트리> --name <후계> --agent A --model M [--ctx C] [--effort E] --body-file <발주 본문 파일>
#   R107 · 승계 후계 개설을 «도구가 강제» — 열기 → 에이전트 기동 확인(pgrep) → 새 좌석 jsonl SessionStart → 검증 송신 → 도달 파일.
#   exit 0 = 도달(도달 파일 기록) · 1 = REJECT(송신 0) · 2 = usage · 5 = 열렸으나 도달 미확인(도달 파일 0 · 구 좌석 닫기 0)
#   팀 무관 · 명부(seats*.json) 수정 0 — 명부는 ft-seat-retire.sh 가 후계 부팅 때 한다.
#   도달 파일 = <리포 루트>/.fable-team/state/successor/<구 좌석>.json — context-distill-gate.sh 가 550k 넘은 좌석의 recv 를 이 파일로 푼다. `model` 칸(R282) = --model 값 — ft-seat-retire.sh 가 후계 행 model 로 쓴다.
#   재실행(r609) = 같은 이름 세션이 이미 있고 그 pane 작업 폴더가 $WT 면 열기를 건너뛰고 ⓒ~ⓔ 를 잇는다(도달 파일이 이미 있으면 «이미 도달» rc0 · 송신 0). 남의 세션이면 REJECT. 판 폴더를 못 읽으면 «다르다» 가 아니라 «못 읽음(판정 불가)» 로 REJECT(r622 — 창·판 대상은 «=이름:» 꼴만 pane 을 고른다).
#   송신 판정은 ft-send-verified 의 jsonl 도달 하나뿐이다(exit 0 만 성공). 2·5 면 같은 seq 로 ring 1회 + 재확인.
#   mbox(R343·r607) = 대상 워크트리의 리포 것($ROOT 의 .fable-team/comm/mbox.sh · 워크트리 안 사본은 보지 않는다) — 없으면 REJECT rc2. 고른 폴더에 짝 파일 mbox_doorbell.sh 가 없으면 열기 «전» REJECT rc2. ★ft-role-spawn·ft-nano-spawn 은 «워크트리 = 이 리포(BYZ)» 전제라 이 결정 대상이 아니다★.
#   env(시험용): FT_SEND_VERIFIED · FT_MBOX_SH · FT_REACH_CHECK · FT_SO_WAIT_MAX(기동 대기 횟수 60) · FT_SO_POLL(간격 초 1)
set -uo pipefail
[ -f "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" ] && . "$(dirname -- "${BASH_SOURCE[0]:-$0}")/ft-live-entry.sh" "$@"   # R201: 비설치 위치면 LIVE_BIN 으로 exec
usage() { echo "usage: $0 <구 좌석> <워크트리> --name <후계> --agent claude|codex|cmd|opencode|pi --model M [--ctx C] [--effort E] --body-file F" >&2; exit 2; }
[ $# -ge 2 ] || usage
OLD="$1"; WT="$2"; shift 2
NAME=""; AGENT=""; MODEL=""; CTX=""; EFFORT=""; BODY=""
while [ $# -gt 0 ]; do case "$1" in
  --name) NAME="${2:-}"; shift 2;; --agent) AGENT="${2:-}"; shift 2;; --model) MODEL="${2:-}"; shift 2;;
  --ctx) CTX="${2:-}"; shift 2;; --effort) EFFORT="${2:-}"; shift 2;; --body-file) BODY="${2:-}"; shift 2;; *) usage;; esac; done
[ -n "$NAME" ] && [ -n "$AGENT" ] && [ -n "$MODEL" ] && [ -n "$BODY" ] || usage
case "$AGENT" in claude|codex|cmd|opencode|pi) ;; *) usage;; esac
printf '%s\n%s\n' "$OLD" "$NAME" | grep -qvE '^[A-Za-z0-9._#-]+$' && { echo "REJECT 좌석명은 [A-Za-z0-9._#-] 만" >&2; exit 2; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# ★spawn 정지 파일 (R320)★: 승계는 1석 교대(순증 0)라 정지 중이어도 막지 않고 WARN 1줄만(문지기 --succession 과 같은 원칙).
if [ -f "$HERE/ft-spawn-hold.sh" ]; then
  _hold="$(bash "$HERE/ft-spawn-hold.sh" status 2>&1)" || echo "WARN spawn 정지 중이나 승계는 막지 않는다 — $_hold" >&2
fi
# ★자원 게이트 (Res-1014)★: 디스크·스왑·메모리·에이전트 수가 한계를 넘으면 열지 않는다(부작용 전). 우회 플래그 없음 — 조정은 env 문턱만.
[ -f "$HERE/ft-resource-gate.sh" ] || { echo "REJECT ft-resource-gate.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
# R213 DA⑥ H3(r2): agents 면제(--succession)는 «실제 1석 교대» 일 때만 — ①NAME == OLD 계보 베이스#(N+1) ②OLD 가 팀 명부(seats*.json)의 역할 키(_master·_arch 등 `_` 시작 키) 값 ③OLD tmux 세션 생존. 하나라도 아니면 일반 새 좌석 문턱.
_rgroot="${FT_RES_ROOT:-$(. "$HERE/ft-harness-root.sh" && ft_repo_root "$HERE" 2>/dev/null)}"; _rgsucc=""   # r385b: 옛 설치 꼴 · cwd 리포 공용 루트
if [[ "$OLD" =~ ^(.+)#([0-9]+)$ ]] && [ "$NAME" = "${BASH_REMATCH[1]}#$((BASH_REMATCH[2]+1))" ] && tmux has-session -t "=$OLD" 2>/dev/null \
   && python3 -c 'import glob,json,sys
for f in glob.glob(sys.argv[1]+"/.fable-team/seats*.json"):
    try: d=json.load(open(f))
    except Exception: continue
    if any(k.startswith("_") and v==sys.argv[2] for k,v in d.items() if isinstance(v,str)): sys.exit(0)
sys.exit(1)' "$_rgroot" "$OLD" 2>/dev/null; then _rgsucc="--succession"; fi
# ★전팀 정지 게이트 (r626 DA⑥ r1 Q1)★: 정지 중엔 «진짜 승계»(구 좌석이 명부에 있고 새 이름 = 같은 계보 #N+1)만 연다 — 그 밖 새 이름은 REJECT(부작용 전 · 판정 = ft_all_stop.py true_succession).
_asr="${FT_ROOT:-$(. "$HERE/ft-harness-root.sh" && ft_repo_root "$HERE" 2>/dev/null)}"
[ -e "$_asr/.fable-team/state/ALL_STOP.json" ] && { _aout="$(FT_ROOT="$_asr" bash "$HERE/ft-all-stop.sh" check --succession "$OLD" "$NAME" 2>&1)" || { printf '%s\n' "$_aout"; exit 1; }; printf '%s\n' "$_aout" >&2; }
# ★R342 arch 상시 게이트★: 교대 대상이 «arch 상시» 팀의 `_master`·`_desk` 인데 그 팀 `_arch` 가 라이브가 아니면 열지 않는다(부작용 전). `_arch` 자신의 교대·표 «없음» 팀·명부에 없는 좌석은 통과 — 판정기 하나 = ft_teamset.py arch-live.
_agout="$(python3 "$HERE/ft_teamset.py" arch-live --root "$_rgroot" --md "${FT_TEAMSET_MD:-gitref:origin/main:design/TEAMSET.md}" --seat "$OLD" 2>&1)"; _agrc=$?
[ "$_agrc" = 0 ] || { [ "$_agrc" = 3 ] && echo "REJECT 그 팀 arch 좌석 없음 — 먼저 arch 를 열어라(아래 «→ 열기» 명령 · R437) · $_agout" || echo "REJECT arch 판정 실패(rc=$_agrc) · $_agout"; exit 1; }
_rgout="$(bash "$HERE/ft-resource-gate.sh" check $_rgsucc 2>&1)"; _rgrc=$?
# R198(판정 1767): 에이전트 수로 막혔을 때만 — 기존 표준승인 범위 안의 유휴·완료 좌석을 자동 정리한 뒤 문지기 재검(FT_RECLAIM=0 으로 끔)
if [ "$_rgrc" != 0 ] && [ "${FT_RECLAIM:-1}" != 0 ] && [ -f "$HERE/ft-resource-reclaim.sh" ]; then
  _rgout="$(bash "$HERE/ft-resource-reclaim.sh" --on-reject "$_rgout" --gate "$HERE/ft-resource-gate.sh" 2>&1)"; _rgrc=$?
  [ "$_rgrc" = 0 ] && printf '%s\n' "$_rgout" >&2
fi
[ "$_rgrc" != 0 ] && { printf '%s\n' "$_rgout"; exit "$_rgrc"; }
SEND="${FT_SEND_VERIFIED:-$HERE/ft-send-verified.sh}"; REACH="${FT_REACH_CHECK:-$HERE/ft-reach-check.sh}"
WAIT_MAX="${FT_SO_WAIT_MAX:-60}"; POLL="${FT_SO_POLL:-1}"
# 형제 도구 2개(env 로 바뀐 «최종 경로» 기준)는 설치 폴더에만 있다 — 원본 폴더에서 돌리면 좌석을 연 «뒤» 송신에서 죽는다. 열기 «전»에 거절한다(R134).
for _sib in "$SEND" "$REACH"; do
  [ -f "$_sib" ] || { echo "REJECT $(basename -- "$_sib") 없음: $(dirname -- "$_sib") (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
done
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
[ -n "$ROOT" ] || { echo "REJECT 워크트리가 git 이 아니다: $WT"; exit 1; }
# ★mbox = «대상 워크트리의 리포» 것 (R343)★: 승계 발주 본문·ring·recv 지시문은 후계가 읽는 리포 mbox 로 가야 한다 — 설치 폴더(BYZ) 기준이면 별도 리포 좌석이 0건으로 부팅한다.
# 순서(r607): FT_MBOX_SH(시험·명시) → $ROOT/.fable-team/comm/mbox.sh. 못 찾으면 호출자 mbox 로 후퇴하지 않고 열기 «전» REJECT(#0 RULE).
#   ★$WT 단계 삭제★: 링크 워크트리 안의 옛 사본(짝 파일 빠짐·따로 된 큐)이 리포 루트 것보다 먼저 잡혀 승계 발주가 죽었다(rc=5 · cfo 125653 · r607).
if [ -n "${FT_MBOX_SH:-}" ]; then MBOX="$FT_MBOX_SH"
elif [ -f "$ROOT/.fable-team/comm/mbox.sh" ]; then MBOX="$ROOT/.fable-team/comm/mbox.sh"
else echo "REJECT 대상 리포 mbox 없음 — $ROOT/.fable-team/comm/mbox.sh (호출자 mbox 로 보내지 않는다 · 워크트리 안 사본은 보지 않는다)"; exit 2; fi
[ -f "$MBOX" ] || { echo "REJECT $(basename -- "$MBOX") 없음: $(dirname -- "$MBOX") (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
# ★짝 파일 검사(r607)★: mbox.sh 는 `source "$DIR/mbox_doorbell.sh"`(DIR = 고른 경로의 폴더 · 링크면 링크가 놓인 폴더)로 시작한다 — 없으면 첫 송신이 죽는다. 열기 «전»에 거절.
MDIR="$(dirname -- "$MBOX")"
[ -f "$MDIR/mbox_doorbell.sh" ] || { echo "REJECT mbox 짝 파일 없음: $MDIR/mbox_doorbell.sh (mbox.sh 가 source 하는 mbox_doorbell.sh · 짝이 빠진 폴더는 쓰지 않는다)"; exit 2; }
STATE="$ROOT/.fable-team/state/successor"
hil() { echo "[HIL] 후계 $NAME 도달 미확인 — 구 좌석 닫기 0 (구=$OLD) · 도달 파일 없음 · $1"; }

# ⓐ 본문 첫 3줄 = 골 원문 자리(하드 룰 7) — 하나라도 비면 열지 않는다
[ -f "$BODY" ] || { echo "REJECT 본문 파일 없음: $BODY"; exit 1; }
[ "$(sed -n '1,3p' "$BODY" | grep -c '[^[:space:]]')" = 3 ] || { echo "REJECT 본문 첫 3줄(골 원문)이 비었다: $BODY"; exit 1; }
# ⓐ' (r414) desk·planner 승계 본문의 슬랙 뿌리 ts 손 복사 = 열지 않는다 — 보고 스레드 뿌리는 등록부(slack-threads.json)가 소유
case "$NAME" in *-desk-*|*-planner-*) grep -qE -- '--ts [0-9]{10}\.[0-9]{6}' "$BODY" && { echo "REJECT 본문에 슬랙 ts 손 복사(--ts …) — 방 글 = post --to <이름> · 오빠 글 답 = reply --to-slack <ts>"; exit 1; };; esac

# ⓑ-0 재실행 이어가기 (r609) — desk 전경 30초 상한에 끊긴 판(세션만 열리고 도달 파일 0)을 다시 돌리면 잇는다.
#   이미 있는 세션이 «내 것»(pane 작업 폴더 toplevel == $WT)이면 열기를 건너뛰고 ⓒ~ⓔ 를 그대로 한다.
#   도달 파일이 이미 이 NAME 을 담고 있으면 «이미 도달» rc0(두 번 송신 0) · 폴더가 다르면 남의 세션 = REJECT(추측 0).
RESUMED=0
if tmux has-session -t "=$NAME" 2>/dev/null; then
  if [ -f "$STATE/$OLD.json" ] && grep -qE "\"successor\"[[:space:]]*:[[:space:]]*\"$NAME\"" "$STATE/$OLD.json" 2>/dev/null; then
    echo "이미 도달: successor=$NAME file=$STATE/$OLD.json — 송신 0"; exit 0
  fi
  # r622: 창·판 대상 명령은 «=이름» 만으로는 빈 값이다(세션 정확 일치는 세션 명령 전용) — «=이름:» 꼴이어야 pane 을 고른다.
  PCWD="$(tmux display-message -p -t "=$NAME:" '#{pane_current_path}' 2>/dev/null)"
  [ -n "$PCWD" ] || { echo "REJECT 세션 $NAME 의 작업 폴더를 못 읽음(판정 불가 · 이어가기 0 · 남의 세션 판정 0) — wt=$WT"; exit 1; }
  PTOP="$(git -C "$PCWD" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)"
  WTOP="$(git -C "$WT" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)"
  [ -n "$PTOP" ] && [ -n "$WTOP" ] && [ "$PTOP" = "$WTOP" ] \
    || { echo "REJECT 세션 $NAME 이 이미 있으나 작업 폴더가 다르다(남의 세션 · 이어가기 0 · 추측 0) — pane=$PCWD wt=$WT"; exit 1; }
  echo "이어감: 세션 있음 $NAME — 열기 건너뜀"
  RESUMED=1
fi

# ⓑ 열기 — tmuxc 옵션은 에이전트별로 다르다(ft-role-spawn.sh 와 같은 규칙: --ctx 는 claude 만 · --effort 는 claude·cmd·codex·pi)
if [ "$RESUMED" = 0 ]; then
OPEN=(tmuxc open "$WT" --name "$NAME" --agent "$AGENT" --model "$MODEL")
[ "$AGENT" = claude ] && [ -n "$CTX" ] && OPEN+=(--ctx "$CTX")
case "$AGENT" in claude|cmd|codex|pi) [ -n "$EFFORT" ] && OPEN+=(--effort "$EFFORT");; esac
"${OPEN[@]}" >/dev/null 2>&1 || { echo "REJECT tmuxc open 실패 ($NAME) — 송신 0"; exit 1; }
tmux has-session -t "=$NAME" 2>/dev/null || { echo "REJECT 세션이 안 떴다: $NAME — 송신 0"; exit 1; }
fi

# ⓒ 에이전트 기동 확인 — pane pid 의 자식이 생길 때까지(BOOT 7 HARD GATE: pgrep 0건이면 send 금지). 상한 넘으면 송신 0.
PID="$(tmux list-panes -t "=$NAME" -F '#{pane_pid}' 2>/dev/null | head -1)"
up=0; i=0
while [ "$i" -lt "$WAIT_MAX" ]; do i=$((i+1)); pgrep -P "$PID" >/dev/null 2>&1 && { up=1; break; }; sleep "$POLL"; done
[ "$up" = 1 ] || { echo "REJECT $NAME 에서 에이전트 프로세스 기동 미확인(pgrep ${WAIT_MAX}회) — 송신 0"; hil "새 pane 을 사람이 확인"; exit 1; }

# ⓒ-2 새 좌석 jsonl 의 SessionStart — 실측 꼴(SessionStart 뒤 16초 Enter 미제출)을 줄이려 기다린다. 못 봐도 «미관측» 을 드러내고 송신(도달 판정은 아래 send-verified 몫).
CWD="$(tmux display-message -p -t "=$NAME:" '#{pane_current_path}' 2>/dev/null)"   # r622: «=이름:» — «=이름» 은 창 대상에서 빈 값(새 좌석 jsonl 폴더가 엉뚱해진다)
JDIR="$HOME/.claude/projects/$(printf '%s' "$CWD" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"
SKEYS=(-e "\"agentName\":\"$NAME\"" -e "\"customTitle\":\"$NAME\""); SMARK=SessionStart
# r540: pi 좌석 = pi 대화 기록 폴더(ft-reach-check 와 같은 규칙)의 session_info.name — pi 는 tmuxc 부팅 문장이 제출된 뒤에야 파일을 쓴다
[ "$AGENT" = pi ] && { JDIR="${FT_PI_SESSIONS_DIR:-$HOME/.pi/agent/sessions}/--$(printf '%s' "$CWD" | sed -e 's|^[/\\]||' -e 's|[/\\:]|-|g')--"; SKEYS=(-e "\"name\":\"$NAME\""); SMARK='"type":"session_info"'; }
seen=0; i=0
while [ "$i" -lt "$WAIT_MAX" ]; do i=$((i+1))
  f="$(grep -lF "${SKEYS[@]}" "$JDIR"/*.jsonl 2>/dev/null)"
  [ -n "$f" ] && printf '%s\n' "$f" | xargs grep -lF "$SMARK" >/dev/null 2>&1 && { seen=1; break; }; sleep "$POLL"; done
[ "$seen" = 1 ] && echo "SessionStart 관측 $NAME" || echo "SessionStart 미관측 $NAME (${WAIT_MAX}회) — 송신 후 도달 판정으로 확인"

# ⓓ 검증 송신 — 본문은 mbox 큐 · 창엔 doorbell 한 줄 · 도달은 jsonl 층(ft-send-verified exit 0 만 성공)
OUT="$(FT_REACH_AGENT="$AGENT" FT_MBOX_SH="$MBOX" FT_SEND_FROM="$OLD" bash "$SEND" "$NAME" "$(cat "$BODY")" 2>&1)"; RC=$?
printf '%s\n' "$OUT"
SEQ="$(printf '%s\n' "$OUT" | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2)"
# ⓕ 2·5 → 같은 seq 로 ring 1회 + 도달 재확인(본문 재큐잉 0). 1(SEND_FAILED)·seq 없음 = 그대로 실패.
if [ "$RC" -ne 0 ] && { [ "$RC" -eq 2 ] || [ "$RC" -eq 5 ]; } && [ -n "$SEQ" ]; then
  bash "$MBOX" ring "$NAME" "$SEQ" 2>&1 && FT_REACH_AGENT="$AGENT" bash "$REACH" "$NAME" "[발주 #$SEQ]" 20 0 >/dev/null 2>&1 && RC=0
fi
[ "$RC" -eq 0 ] || { hil "send-verified rc=$RC"; exit 5; }

# ⓔ 도달 파일 — 훅(context-distill-gate.sh)이 이 파일이 있어야 550k 넘은 좌석의 recv 를 푼다
mkdir -p "$STATE" && printf '{"successor":"%s","seq":%s,"reached_at":"%s","rc":0,"model":"%s"}\n' "$NAME" "${SEQ:-null}" "$(date +%FT%T%z)" "$MODEL" > "$STATE/$OLD.json" \
  || { hil "도달 파일 쓰기 실패 $STATE"; exit 5; }
echo "OK successor=$NAME seq=${SEQ:-null} file=$STATE/$OLD.json mbox=$MBOX"
