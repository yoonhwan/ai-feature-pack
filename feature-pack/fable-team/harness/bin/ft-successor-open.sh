#!/usr/bin/env bash
# ft-successor-open.sh <구 좌석> <워크트리> --name <후계> --agent A --model M [--ctx C] [--effort E] --body-file <발주 본문 파일>
#   R107 · 승계 후계 개설을 «도구가 강제» — 열기 → 에이전트 기동 확인(pgrep) → 새 좌석 jsonl SessionStart → 검증 송신 → 도달 파일.
#   exit 0 = 도달(도달 파일 기록) · 1 = REJECT(송신 0) · 2 = usage · 5 = 열렸으나 도달 미확인(도달 파일 0 · 구 좌석 닫기 0)
#   팀 무관 · 명부(seats*.json) 수정 0 — 명부는 ft-seat-retire.sh 가 후계 부팅 때 한다.
#   도달 파일 = <리포 루트>/.fable-team/state/successor/<구 좌석>.json — context-distill-gate.sh 가 400k 넘은 좌석의 recv 를 이 파일로 푼다. `model` 칸(R282) = --model 값 — ft-seat-retire.sh 가 후계 행 model 로 쓴다.
#   송신 판정은 ft-send-verified 의 jsonl 도달 하나뿐이다(exit 0 만 성공). 2·5 면 같은 seq 로 ring 1회 + 재확인.
#   env(시험용): FT_SEND_VERIFIED · FT_MBOX_SH · FT_REACH_CHECK · FT_SO_WAIT_MAX(기동 대기 횟수 60) · FT_SO_POLL(간격 초 1)
set -uo pipefail
usage() { echo "usage: $0 <구 좌석> <워크트리> --name <후계> --agent claude|codex|cmd|opencode --model M [--ctx C] [--effort E] --body-file F" >&2; exit 2; }
[ $# -ge 2 ] || usage
OLD="$1"; WT="$2"; shift 2
NAME=""; AGENT=""; MODEL=""; CTX=""; EFFORT=""; BODY=""
while [ $# -gt 0 ]; do case "$1" in
  --name) NAME="${2:-}"; shift 2;; --agent) AGENT="${2:-}"; shift 2;; --model) MODEL="${2:-}"; shift 2;;
  --ctx) CTX="${2:-}"; shift 2;; --effort) EFFORT="${2:-}"; shift 2;; --body-file) BODY="${2:-}"; shift 2;; *) usage;; esac; done
[ -n "$NAME" ] && [ -n "$AGENT" ] && [ -n "$MODEL" ] && [ -n "$BODY" ] || usage
case "$AGENT" in claude|codex|cmd|opencode) ;; *) usage;; esac
printf '%s\n%s\n' "$OLD" "$NAME" | grep -qvE '^[A-Za-z0-9._#-]+$' && { echo "REJECT 좌석명은 [A-Za-z0-9._#-] 만" >&2; exit 2; }
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# ★자원 게이트 (Res-1014)★: 디스크·스왑·메모리·에이전트 수가 한계를 넘으면 열지 않는다(부작용 전). 우회 플래그 없음 — 조정은 env 문턱만.
[ -f "$HERE/ft-resource-gate.sh" ] || { echo "REJECT ft-resource-gate.sh 없음: $HERE (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
# R213 DA⑥ H3(r2): agents 면제(--succession)는 «실제 1석 교대» 일 때만 — ①NAME == OLD 계보 베이스#(N+1) ②OLD 가 팀 명부(seats*.json)의 역할 키(_master·_arch 등 `_` 시작 키) 값 ③OLD tmux 세션 생존. 하나라도 아니면 일반 새 좌석 문턱.
_rgroot="${FT_RES_ROOT:-$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}"; _rgsucc=""
if [[ "$OLD" =~ ^(.+)#([0-9]+)$ ]] && [ "$NAME" = "${BASH_REMATCH[1]}#$((BASH_REMATCH[2]+1))" ] && tmux has-session -t "=$OLD" 2>/dev/null \
   && python3 -c 'import glob,json,sys
for f in glob.glob(sys.argv[1]+"/.fable-team/seats*.json"):
    try: d=json.load(open(f))
    except Exception: continue
    if any(k.startswith("_") and v==sys.argv[2] for k,v in d.items() if isinstance(v,str)): sys.exit(0)
sys.exit(1)' "$_rgroot" "$OLD" 2>/dev/null; then _rgsucc="--succession"; fi
_rgout="$(bash "$HERE/ft-resource-gate.sh" check $_rgsucc 2>&1)"; _rgrc=$?
# R198(판정 1767): 에이전트 수로 막혔을 때만 — 기존 표준승인 범위 안의 유휴·완료 좌석을 자동 정리한 뒤 문지기 재검(FT_RECLAIM=0 으로 끔)
if [ "$_rgrc" != 0 ] && [ "${FT_RECLAIM:-1}" != 0 ] && [ -f "$HERE/ft-resource-reclaim.sh" ]; then
  _rgout="$(bash "$HERE/ft-resource-reclaim.sh" --on-reject "$_rgout" --gate "$HERE/ft-resource-gate.sh" 2>&1)"; _rgrc=$?
  [ "$_rgrc" = 0 ] && printf '%s\n' "$_rgout" >&2
fi
[ "$_rgrc" != 0 ] && { printf '%s\n' "$_rgout"; exit "$_rgrc"; }
SEND="${FT_SEND_VERIFIED:-$HERE/ft-send-verified.sh}"; MBOX="${FT_MBOX_SH:-$HERE/../comm/mbox.sh}"; REACH="${FT_REACH_CHECK:-$HERE/ft-reach-check.sh}"
WAIT_MAX="${FT_SO_WAIT_MAX:-60}"; POLL="${FT_SO_POLL:-1}"
# 형제 도구 3개(env 로 바뀐 «최종 경로» 기준)는 설치 폴더에만 있다 — 원본 폴더에서 돌리면 좌석을 연 «뒤» 송신에서 죽는다. 열기 «전»에 거절한다(R134).
for _sib in "$SEND" "$MBOX" "$REACH"; do
  [ -f "$_sib" ] || { echo "REJECT $(basename -- "$_sib") 없음: $(dirname -- "$_sib") (런타임 .fable-team/bin/ 에서 실행하라)"; exit 1; }
done
ROOT="$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')"
[ -n "$ROOT" ] || { echo "REJECT 워크트리가 git 이 아니다: $WT"; exit 1; }
STATE="$ROOT/.fable-team/state/successor"
hil() { echo "[HIL] 후계 $NAME 도달 미확인 — 구 좌석 닫기 0 (구=$OLD) · 도달 파일 없음 · $1"; }

# ⓐ 본문 첫 3줄 = 골 원문 자리(하드 룰 7) — 하나라도 비면 열지 않는다
[ -f "$BODY" ] || { echo "REJECT 본문 파일 없음: $BODY"; exit 1; }
[ "$(sed -n '1,3p' "$BODY" | grep -c '[^[:space:]]')" = 3 ] || { echo "REJECT 본문 첫 3줄(골 원문)이 비었다: $BODY"; exit 1; }

# ⓑ 열기 — tmuxc 옵션은 에이전트별로 다르다(ft-role-spawn.sh 와 같은 규칙: --ctx 는 claude 만 · --effort 는 claude·cmd·codex)
OPEN=(tmuxc open "$WT" --name "$NAME" --agent "$AGENT" --model "$MODEL")
[ "$AGENT" = claude ] && [ -n "$CTX" ] && OPEN+=(--ctx "$CTX")
case "$AGENT" in claude|cmd|codex) [ -n "$EFFORT" ] && OPEN+=(--effort "$EFFORT");; esac
"${OPEN[@]}" >/dev/null 2>&1 || { echo "REJECT tmuxc open 실패 ($NAME) — 송신 0"; exit 1; }
tmux has-session -t "=$NAME" 2>/dev/null || { echo "REJECT 세션이 안 떴다: $NAME — 송신 0"; exit 1; }

# ⓒ 에이전트 기동 확인 — pane pid 의 자식이 생길 때까지(BOOT 7 HARD GATE: pgrep 0건이면 send 금지). 상한 넘으면 송신 0.
PID="$(tmux list-panes -t "=$NAME" -F '#{pane_pid}' 2>/dev/null | head -1)"
up=0; i=0
while [ "$i" -lt "$WAIT_MAX" ]; do i=$((i+1)); pgrep -P "$PID" >/dev/null 2>&1 && { up=1; break; }; sleep "$POLL"; done
[ "$up" = 1 ] || { echo "REJECT $NAME 에서 에이전트 프로세스 기동 미확인(pgrep ${WAIT_MAX}회) — 송신 0"; hil "새 pane 을 사람이 확인"; exit 1; }

# ⓒ-2 새 좌석 jsonl 의 SessionStart — 실측 꼴(SessionStart 뒤 16초 Enter 미제출)을 줄이려 기다린다. 못 봐도 «미관측» 을 드러내고 송신(도달 판정은 아래 send-verified 몫).
CWD="$(tmux display-message -p -t "=$NAME" '#{pane_current_path}' 2>/dev/null)"
JDIR="$HOME/.claude/projects/$(printf '%s' "$CWD" | LC_ALL=C sed 's|[^A-Za-z0-9]|-|g')"
seen=0; i=0
while [ "$i" -lt "$WAIT_MAX" ]; do i=$((i+1))
  f="$(grep -lF -e "\"agentName\":\"$NAME\"" -e "\"customTitle\":\"$NAME\"" "$JDIR"/*.jsonl 2>/dev/null)"
  [ -n "$f" ] && printf '%s\n' "$f" | xargs grep -lF SessionStart >/dev/null 2>&1 && { seen=1; break; }; sleep "$POLL"; done
[ "$seen" = 1 ] && echo "SessionStart 관측 $NAME" || echo "SessionStart 미관측 $NAME (${WAIT_MAX}회) — 송신 후 도달 판정으로 확인"

# ⓓ 검증 송신 — 본문은 mbox 큐 · 창엔 doorbell 한 줄 · 도달은 jsonl 층(ft-send-verified exit 0 만 성공)
OUT="$(FT_SEND_FROM="$OLD" bash "$SEND" "$NAME" "$(cat "$BODY")" 2>&1)"; RC=$?
printf '%s\n' "$OUT"
SEQ="$(printf '%s\n' "$OUT" | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2)"
# ⓕ 2·5 → 같은 seq 로 ring 1회 + 도달 재확인(본문 재큐잉 0). 1(SEND_FAILED)·seq 없음 = 그대로 실패.
if [ "$RC" -ne 0 ] && { [ "$RC" -eq 2 ] || [ "$RC" -eq 5 ]; } && [ -n "$SEQ" ]; then
  bash "$MBOX" ring "$NAME" "$SEQ" 2>&1 && bash "$REACH" "$NAME" "[발주 #$SEQ]" 20 0 >/dev/null 2>&1 && RC=0
fi
[ "$RC" -eq 0 ] || { hil "send-verified rc=$RC"; exit 5; }

# ⓔ 도달 파일 — 훅(context-distill-gate.sh)이 이 파일이 있어야 400k 넘은 좌석의 recv 를 푼다
mkdir -p "$STATE" && printf '{"successor":"%s","seq":%s,"reached_at":"%s","rc":0,"model":"%s"}\n' "$NAME" "${SEQ:-null}" "$(date +%FT%T%z)" "$MODEL" > "$STATE/$OLD.json" \
  || { hil "도달 파일 쓰기 실패 $STATE"; exit 5; }
echo "OK successor=$NAME seq=${SEQ:-null} file=$STATE/$OLD.json"
