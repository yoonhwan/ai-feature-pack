#!/usr/bin/env bash
# ft-team-stop.sh <팀> [--verdict <번호>] [--recv <seq>] | <팀> --confirm <plan> — 팀 «종료 1명령» (r1518 · DESIGN-r1498 §2 S0~S5 · §3 가드 · 모델 0 · 크론·설정 신설 0)
#   plan(읽기 + S0 커밋·push): S1 주기 → S2 클론 → S3·S4 가드 → S0 CLOSEOUT 생성·[docs] 커밋·push(실패 = 전체 멈춤 · h 0) → 승인 h 1장(S1 정리→S2→S3→S4→S5) 등록 · kill·close 는 전부 h 안(직접 kill 0)
#   가드(§3 · 첫 번째만 · 그 좌석만 «멈춤 <좌석> <가드> <값>» 1줄 · 나머지는 h 에): Working(3값) · 미착지 · 미커밋 · 미읽음 · 열린 h · kill권한(hil.md:9 밖 ∧ --verdict 없음) ·
#     브랜치·워크트리 삭제 명령 0(정적 시험) · 나노는 --recv <master seq> 없으면 «recv 없음» 멈춤(ft-nano-close ② 요구 · §9 ② 사람 인자)
#   Working: IDLE = seat-resume 기록 jsonl 의 마지막 assistant «뒤» 턴 종료(claude system/turn_duration·stop_hook_summary · pi stopReason=stop · turn_end) ∧ pane 자손 0 ·
#     WORKING = 턴 종료 없음 ∧ 자손≠0(초 무관) · 그 밖 = 판정 불가 멈춤 · tmux 세션 없음 = Working 만 건너뜀
#   S1 세션 cron: 기계 근거 못 찾음(§9 ① · jsonl 에 cron 생성 tool_use 실측 0건) → «좌석 닫기 = cron 종료» 1줄 · launchd bootout·ft-pm-watchd --stop-if-owned = h 안
#   --confirm <plan>(h 끝 줄 · S5): plan 의 closed·clone·멈춤 세션 ≤3회 · 팀 명부 전 행 stop-ready/_closed · launchd 0 → 닫힘 1줄 커밋·push + [종료] 1통 · 남으면 «S5 잔존» rc1 · 이미 닫힘 = 송신 0
#   rc 0 = h 등록 · 1 = 전체 멈춤(upstream main = 거절) · 2 = usage · 3 = 판정 불가(카드 판독·tmux 7s · 섞임) · 외부 호출 1회 7초 + 재시도 1 · env(시험): FT_REPO_ROOT FT_STOP_{REF,STATE,ME,GAP,REPORT_TO}
#     FT_SEATS_JSON FT_TMUX FT_MBOX_SH FT_HIL FT_PM_WATCHD FT_LAUNCHAGENTS FT_LAUNCHCTL ZC_RESUME_DIR HIL_DIR · 재진입 가드 FT_TEAM_STOP_IN
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$HERE/ft-live-entry.sh" ] && . "$HERE/ft-live-entry.sh" "$@"
[ -z "${FT_TEAM_STOP_IN:-}" ] || { echo "멈춤 재진입(FT_TEAM_STOP_IN=$FT_TEAM_STOP_IN) — 자기 재호출 0"; exit 1; }
export FT_TEAM_STOP_IN=$$
usage() { echo "usage: $0 <팀> [--verdict <번호>] [--recv <seq>] | $0 <팀> --confirm <plan>" >&2; exit 2; }
TEAM="${1:-}"; case "$TEAM" in -*|"") usage;; esac; shift
VERDICT=""; RECV=""; CONFIRM=""
while [ $# -gt 0 ]; do case "$1" in
  --verdict) VERDICT="${2:-}"; [[ "$VERDICT" =~ ^[0-9]+$ ]] || usage; shift 2;;
  --recv) RECV="${2:-}"; [[ "$RECV" =~ ^[0-9]+$ ]] || usage; shift 2;;
  --confirm) CONFIRM="${2:-}"; [ -f "$CONFIRM" ] || usage; shift 2;;
  *) usage;; esac; done
[ "$TEAM" != airag ] || { echo "멈춤 airag = 팩 위성팀 — 명부·CLOSEOUT 자리가 달라 이 판 범위 밖"; exit 1; }
REF="${FT_STOP_REF:-origin/main}"
ROOT="${FT_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] || { echo "멈춤 리포 루트를 못 찾았다(FT_REPO_ROOT 또는 git 안에서 실행)"; exit 1; }
SAT=0; PACK="${FT_PACK_ROOT:-$HOME/Project/ai-feature-pack}"; DROOT="$ROOT"; WROOT="$ROOT/.worktrees"; CDIR="design/teams/$TEAM"
STATE="${FT_STOP_STATE:-$ROOT/.fable-team/state/team-stop}"; HD="${HIL_DIR:-/tmp}"
TM="${FT_TMUX:-tmux}"; MB="${FT_MBOX_SH:-$ROOT/.fable-team/comm/mbox.sh}"; ME="${FT_STOP_ME:-${FT_SEND_FROM:-ft-team-stop}}"
RC=0; T0=$SECONDS; TS=(); step() { TS+=("$1=$((SECONDS - $2))s"); }
STOP() { echo "멈춤 ${LIBCTX:+명부 판정 불가 ${SEATS:-?} — }$*"; exit 1; }; UNK() { echo "판정 불가 $*"; exit 3; }   # 하드 룰 20
LIBCTX=1; [ -f "$HERE/ft-team-seats-lib.sh" ] || STOP "lib 없음 $HERE/ft-team-seats-lib.sh"
. "$HERE/ft-team-seats-lib.sh"; LIBCTX=""   # SEATS · OLD(= 팀장) · tick_launchd_loaded (r1535 · 복사 0)
q() { local v="${1//\'/\'\\\'\'}"; printf "'%s'" "$v"; }   # 사람이 읽는 h — 작은따옴표 인용(한글 그대로)
tls() {  # 세션|pane_pid 줄 — 1회 7초 + 재시도 1(push7 꼴 · R4) · 서버 없음 = 빈 값 · 둘 다 실패 = rc 1(판정 불가)
  local o r t; for t in 1 2; do o="$(perl -e 'alarm 7; exec @ARGV' "$TM" list-panes -a -F '#{session_name}|#{pane_pid}' 2>&1 </dev/null)"; r=$?
    [ "$r" -eq 0 ] && { printf '%s\n' "$o"; return 0; }; case "$o" in *"no server running"*|*"No such file or directory"*) return 0;; esac; done; return 1; }
upchk() {  # R5 — upstream 이 main(또는 원격 기본 가지)이면 거절 · 허용 = 그 밖 upstream 만
  local d; u="$(git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || { PRC="upstream 없음"; return 1; }; d="$(git -C "$ROOT" symbolic-ref -q --short "refs/remotes/${u%%/*}/HEAD" 2>/dev/null)"
  case "${u#*/}" in main|"${d#*/}") PRC="거절 main 직접 push — 정본 가지(ops/main-base·팀 가지)에서 실행(upstream $u)"; return 1;; esac; }
push7() {  # 현재 가지의 upstream 으로 push 1회 7초 + 재시도 1(하드 룰 12) · 착지 호출 0
  local u t=0; upchk || return 1
  while :; do t=$((t+1)); perl -e 'alarm 7; exec @ARGV' git -C "$ROOT" push -q "${u%%/*}" "HEAD:${u#*/}" >/dev/null 2>&1 </dev/null; PRC=$?
    [ "$PRC" -eq 0 ] || [ "$t" -ge 2 ] || continue; break; done; [ "$PRC" -eq 0 ]; }
commit_push() {  # <파일> <메시지> — upstream 확인 먼저(R5 · 커밋 0) · 그 파일만 커밋 · 바뀐 것 없으면 커밋 0 · push 1회
  local u; upchk || return 1; git -C "$ROOT" add -- "$1" || { PRC="add rc=$?"; return 1; }
  git -C "$ROOT" diff --cached --quiet -- "$1" || git -C "$ROOT" commit -q -m "$2" -- "$1" >/dev/null || { PRC="commit rc=$?"; return 1; }
  push7; }
# ---------- S5 확인 (--confirm · h 끝 줄) ----------
if [ -n "$CONFIRM" ]; then
  CO="$(sed -n 's/^# ft-team-stop plan .*closeout=\([^ ]*\).*/\1/p' "$CONFIRM" | head -1)"; [ -n "$CO" ] && [ -f "$ROOT/$CO" ] || STOP "S5 CLOSEOUT 못 찾음(${CO:-plan 머리 없음})"
  ! grep -qF "plan ${CONFIRM##*/}" "$ROOT/$CO" || { echo "이미 닫힘 ${CONFIRM##*/} — [종료] 송신 0(보고 1통 유지 · R3)"; exit 0; }
  LEFT=(); NM="$(sed -nE 's/^# (closed|clone) //p; s/^# 멈춤 ([^ ]+) .*/\1/p' "$CONFIRM")"   # R1: closed·clone + held(멈춤) 좌석
  while IFS= read -r n; do [ -n "$n" ] || continue; gone=0
    for t in 1 2 3; do P2="$(tls)" || UNK "tmux 7s(S5 list-panes 1회 7초 + 재시도 1)"
      printf '%s\n' "$P2" | cut -d'|' -f1 | grep -qxF -- "$n" || { gone=1; break; }
      [ "$t" -lt 3 ] && sleep "${FT_STOP_GAP:-1}"; done
    [ "$gone" = 1 ] || LEFT+=("세션 $n"); done <<< "$NM"
  CL="$(sed -nE 's/^# closed //p' "$CONFIRM")"
  ST="$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
for k,v in d.items():
    if not k.startswith("_") and isinstance(v,dict) and not (v.get("role")=="stop-ready" or v.get("_closed")): print(k)' "$SEATS")" || STOP "S5 명부 판정 불가 $SEATS"   # R1: 팀 명부 전 행
  while IFS= read -r s; do [ -z "$s" ] || LEFT+=("명부 $s"); done <<< "$ST"
  tick_launchd_loaded "$TEAM"; case "$LD_CELL" in 등재*|판정불가*) LEFT+=("launchd com.byz.ft-tick-$TEAM $LD_CELL");; esac
  [ ${#LEFT[@]} -eq 0 ] || { printf 'S5 잔존 %s\n' "${LEFT[@]}"; echo "멈춤 S5 잔존 ${#LEFT[@]}건 — 닫힘 커밋·[종료] 0 · 재실행 = 같은 plan 으로 남은 것만"; exit 1; }
  upchk || STOP "S5 $PRC"
  grep -q '^## 닫힘' "$ROOT/$CO" || printf '\n## 닫힘\n\n' >> "$ROOT/$CO"
  echo "- $(date '+%F %T') S5 확인 — 세션 0 · 명부 닫힘 · launchd 0 · 닫힘 $(printf '%s\n' "$CL" | grep -c .)석 · plan ${CONFIRM##*/}" >> "$ROOT/$CO"
  commit_push "$ROOT/$CO" "[docs] $TEAM CLOSEOUT 닫힘 (ft-team-stop r1518 S5)" || STOP "S5 정본 미착지 $PRC"
  TO="${FT_STOP_REPORT_TO:-$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("_master",""))' "$ROOT/.fable-team/seats-planner.json" 2>/dev/null)}"
  [ -n "$TO" ] || STOP "S5 보고 미도달 — planner 명부 _master 판정 불가"
  mo="$(bash "$MB" send "$TO" "$ME" "[종료] $TEAM — CLOSEOUT $CO $(git -C "$ROOT" rev-parse --short=10 HEAD) · S5 확인 · plan ${CONFIRM##*/}" 2>&1 </dev/null)" || STOP "S5 보고 미도달 — $mo"
  echo "S5 확인 $TEAM 닫힘 · $mo"; exit 0
fi
# ---------- 명부 (현역 행만) ----------
ROWS="$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); print("C\t"+str(d.get("_cards") or ""))
for k,v in d.items():
    if k.startswith("_") or not isinstance(v,dict) or v.get("role")=="stop-ready" or v.get("_closed"): continue
    kind="master" if k==sys.argv[2] else "nano" if (v.get("role")=="nano" or "-nano-" in k) else "role"
    print("\t".join(["A",k,kind,str(v.get("worktree") or "")]))' "$SEATS" "$OLD")" || STOP "명부 판정 불가 $SEATS(JSON 읽기 실패)"
# ---------- S1 주기 0 ----------
S1=$SECONDS; tick_launchd_loaded "$TEAM"; LDC="$LD_CELL"
case "$LDC" in 판정불가*) RC=3; echo "S1 launchd 판정 불가 com.byz.ft-tick-$TEAM $LDC";; 등재*) echo "S1 launchd com.byz.ft-tick-$TEAM 등재 · bootout 은 h 안";; *) echo "S1 launchd $LDC";; esac
echo "S1 세션 cron = 기계 근거 없음(§9 ① · jsonl cron 생성 tool_use 실측 0) → 좌석 닫기 = cron 종료"
PMW="${FT_PM_WATCHD:-$HERE/ft-pm-watchd.sh}"
if [ -f "$PMW" ]; then echo "S1 ft-pm-watchd --stop-if-owned 은 h 안"; else echo "S1 ft-pm-watchd 없음($PMW) — 정리 줄 0"; PMW=""; fi
step S1 "$S1"
# ---------- S2 클론 0 ----------
S2=$SECONDS; PANES="$(tls)" || UNK "tmux 7s(list-panes 1회 7초 + 재시도 1 실패) — h 0 · 정본 push 0"
SESS="$(printf '%s\n' "$PANES" | cut -d'|' -f1 | grep -E "^byz-$TEAM-" | sort -u || true)"
ACTIVE="$(printf '%s\n' "$ROWS" | awk -F'\t' '$1=="A"{print $2}')"
bigger() { local b="${1%#*}" n="${1##*#}" s; [[ "$n" =~ ^[0-9]+$ ]] || return 1
  while IFS= read -r s; do [ "${s%#*}" = "$b" ] && [[ "${s##*#}" =~ ^[0-9]+$ ]] && [ "${s##*#}" -gt "$n" ] && return 0; done <<< "$SESS"; return 1; }
CLONES=(); while IFS= read -r s; do [ -n "$s" ] || continue; printf '%s\n' "$ACTIVE" | grep -qxF -- "$s" && continue
  CLONES+=("$s"); if bigger "$s"; then echo "S2 클론 $s (표준승인 안 · hil.md:9)"; else echo "S2 클론 $s (표준승인 밖 · h 판정)"; fi; done <<< "$SESS"
step S2 "$S2"
# ---------- S3·S4 가드 ----------
wk() { python3 - "$1" <<'P'
import json,sys,os,time,datetime
la=le=-1; ts=None
try:
    for i,l in enumerate(open(sys.argv[1],encoding="utf-8")):
        try: d=json.loads(l)
        except Exception: continue
        t=d.get("type"); m=d.get("message") if isinstance(d.get("message"),dict) else {}
        a=t=="assistant" or (t=="message" and m.get("role")=="assistant")
        if a: la=i; ts=d.get("timestamp")
        if (t=="system" and d.get("subtype") in ("turn_duration","stop_hook_summary")) or t=="turn_end" or (a and m.get("stopReason")=="stop"): le=i
    try: age=int(time.time()-datetime.datetime.fromisoformat(str(ts).replace("Z","+00:00")).timestamp())
    except Exception: age=int(time.time()-os.path.getmtime(sys.argv[1]))
    print("END" if le>=0 and le>=la else "NOEND", age)
except Exception as x: print("ERR", type(x).__name__)
P
}
kids() { local o r; o="$(pgrep -P "$1" 2>/dev/null)"; r=$?; [ "$r" -le 1 ] || return 1; [ -z "$o" ] && echo 0 || printf '%s\n' "$o" | wc -l | tr -d ' '; }
open_h() { local f p; for f in "$HD"/h[0-9]*; do case "${f##*/}" in *.*) continue;; esac
  [ -e "$f.ran" ] || [ -e "$f.superseded" ] && continue
  p="$(sed -n 's/^# ft-hil-entry plan=//p' "$f" 2>/dev/null | head -1)"; [ -n "$p" ] || continue
  sed -n 's/^# ft-hil-request seat=//p' "$p" 2>/dev/null | tr ' ' '\n' | grep -qxF -- "$1" && { echo "${f##*/}"; return; }; done; }
guard() {  # <좌석> <kind> <worktree> → G="" 통과 · G="<가드> <값>" 멈춤
  local s="$1" k="$2" w="$3" pid rec j r a n p o h; G=""
  pid="$(printf '%s\n' "$PANES" | awk -F'|' -v s="$s" '$1==s{print $2; exit}')"
  if [ -n "$pid" ]; then
    rec="${ZC_RESUME_DIR:-$HOME/.claude/state/seat-resume}/$s.json"
    j="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("jsonl",""))' "$rec" 2>/dev/null)"
    [ -n "$j" ] && [ -r "$j" ] || { G="Working 판정 불가 jsonl 없음(${rec##*/})"; return; }
    read -r r a <<< "$(wk "$j")"; n="$(kids "$pid")" || { G="Working 판정 불가 pgrep 실패"; return; }
    case "$r:$n" in END:0) ;; NOEND:0) G="Working 판정 불가 턴 종료 기록 없음·자손 0"; return;;
      NOEND:*) G="Working ${a}초 전(턴 종료 없음 · 자손 $n)"; return;; END:*) G="Working 판정 불가 턴 종료 뒤 자손 $n"; return;;
      *) G="Working 판정 불가 jsonl 판독($r $a)"; return;; esac
  fi
  if [ -n "$w" ]; then p="$WROOT/$w"
    [ -d "$p" ] || { G="미커밋 판정 불가 워크트리 없음 $p"; return; }
    git -C "$p" merge-base --is-ancestor HEAD "$REF" 2>/dev/null; r=$?
    case "$r" in 0) ;; 1) G="미착지 $(git -C "$p" rev-list --count "$REF..HEAD" 2>/dev/null) 커밋 · 브랜치 $(git -C "$p" branch --show-current 2>/dev/null)"; return;;
      *) G="미착지 판정 불가 merge-base rc=$r"; return;; esac
    o="$(git -C "$p" status --porcelain 2>/dev/null)" || { G="미커밋 판정 불가 git status"; return; }
    [ -z "$o" ] || { G="미커밋 $(printf '%s\n' "$o" | wc -l | tr -d ' ') $(printf '%s\n' "$o" | head -1 | cut -c4-)"; return; }
  fi
  o="$(bash "$MB" peek "$s" 2>&1 </dev/null)" || { G="미읽음 판정 불가 peek 실패"; return; }
  n="$(printf '%s\n' "$o" | sed -n 's/^pending=\([0-9][0-9]*\).*/\1/p' | head -1)"; [ -n "$n" ] || { G="미읽음 판정 불가 pending 칸 없음"; return; }
  [ "$n" -eq 0 ] || { G="미읽음 $n · 첫 seq $(printf '%s\n' "$o" | grep -oE 'seq=[0-9]+' | head -1 | cut -d= -f2)"; return; }
  h="$(open_h "$s")"; [ -z "$h" ] || { G="열린 h $h 실행 전"; return; }
  [ "$k" = nano ] || bigger "$s" || [ -n "$VERDICT" ] || { G="kill권한 표준승인 밖 · --verdict 필요"; return; }
  [ "$k" != nano ] || [ -n "$RECV" ] || G="recv 없음 · --recv <master seq> 필요"
}
S3=$SECONDS; LINES=(); NANO=(); ROLE=(); HELD=(); MST=""
while IFS= read -r l; do LINES+=("$l"); done <<< "$ROWS"
for l in "${LINES[@]}"; do IFS=$'\t' read -r t s k w <<< "$l"; [ "$t" = A ] || continue
  guard "$s" "$k" "$w"
  if [ -n "$G" ]; then echo "멈춤 $s $G"; HELD+=("$s $G"); case "$G" in *"판정 불가"*) RC=3;; esac; continue; fi
  case "$k" in master) MST="$s";; nano) NANO+=("$s");; *) ROLE+=("$s");; esac; done
step S3 "$S3"
if [ -z "$MST" ]; then echo "멈춤 S4 팀장 $OLD 가드 멈춤 — 팀장 닫기 0"
elif [ ${#HELD[@]} -gt 0 ]; then echo "멈춤 S4 하위 ${#HELD[@]} 석 미닫힘 — 팀장 $MST 은 마지막이라 h 밖"; MST=""; fi
# ---------- S0 정본 갱신 (실패 = 전체 멈춤 · h 0) ----------
S0=$SECONDS; GOAL3=""; for c in "$CDIR/GOAL-$TEAM.md" "design/$TEAM/GOAL-$TEAM.md"; do
  GOAL3="$(git -C "$ROOT" show "$REF:$c" 2>/dev/null | awk '$0 ~ /^#+ / { inh = ($0 ~ /골/); next } inh && NF { n++; print; if (n >= 3) exit }')"; [ -z "$GOAL3" ] || break; done
[ -n "$GOAL3" ] || STOP "S0 정본 미착지 골 원문 없음($REF:$CDIR/GOAL-$TEAM.md · design/$TEAM/GOAL-$TEAM.md)"
CR="$(printf '%s\n' "$ROWS" | sed -n 's/^C	//p')"
CARDS=""; [ -z "$CR" ] || { CARDS="$(perl -e 'alarm 7; exec @ARGV' git -C "$ROOT" ls-tree --name-only "$REF" -- "$CR/진행/" 2>/dev/null)" || UNK "S0 카드 판독 rc=$? — CLOSEOUT 커밋·push 0 · h 0(R2)"; CARDS="$(printf '%s\n' "$CARDS" | grep '\.md$' || true)"; }
CO="$CDIR/CLOSEOUT-$TEAM-$(date +%Y%m%d).md"; mkdir -p "$ROOT/$CDIR" || STOP "S0 정본 미착지 폴더 $CDIR"
{ echo "# CLOSEOUT $TEAM $(date +%F) — ft-team-stop 자동(r1518) · 사람은 «재개» 칸만 고친다"; echo
  echo "## 골 원문"; echo; printf '%s\n' "$GOAL3"; echo
  echo "## 진행 카드 ($REF · 사본 0)"; echo
  if [ -n "$CARDS" ]; then while IFS= read -r c; do echo "- \`indices/진행/${c##*/}\` · 재개: 아니오(예 로 바꾸면 ft-team-boot B3 가 연다)"; done <<< "$CARDS"; else echo "- 없음(${CR:-명부 _cards 없음})"; fi; echo
  echo "## 좌석"; echo; for s in "${NANO[@]}" "${ROLE[@]}" $MST; do echo "- $s · 닫기 대상(h)"; done
  for x in "${HELD[@]}"; do echo "- 멈춤 $x"; done; for c in "${CLONES[@]}"; do echo "- 클론 $c · kill 대상(h)"; done; echo
  echo "## 대기 h"; echo; printf '%s\n' "${HELD[@]}" | grep '열린 h' | sed 's/^/- /' || echo "- 없음"; echo
  echo "## 크론·launchd"; echo; echo "- launchd com.byz.ft-tick-$TEAM = $LDC · 세션 cron = 기계 근거 없음 → 좌석 닫기 = cron 종료"; echo
  echo "## 되돌림"; echo; echo "- 명부 .bak-close-<ts>(ft-seat-close ①) · seat-resume 기록 · 브랜치·워크트리 삭제 0"; echo
  echo "## 다시 여는 법"; echo; echo "- ft-team-boot.sh $TEAM"; } > "$ROOT/$CO" || STOP "S0 정본 미착지 쓰기 실패 $CO"
commit_push "$ROOT/$CO" "[docs] $TEAM CLOSEOUT 자동 갱신 (ft-team-stop r1518 S0)" || STOP "S0 정본 미착지 $PRC"
SHA="$(git -C "$ROOT" rev-parse --short=10 HEAD)"; echo "S0 정본 $CO sha=$SHA push ok"; step S0 "$S0"
# ---------- 승인 h 1장 ----------
mkdir -p "$STATE" || STOP "plan 폴더 못 만듦 $STATE"
HP="$STATE/$TEAM-$(date +%Y%m%dT%H%M%S)-$$.sh.hil"; WHY="팀 종료 $TEAM · CLOSEOUT $SHA"
NCL=$(( ${#NANO[@]} + ${#ROLE[@]} )); [ -z "$MST" ] || NCL=$((NCL+1))
{ echo '#!/usr/bin/env bash'; echo "# ft-team-stop plan team=$TEAM closeout=$CO sha=$SHA"
  [[ "$ME" =~ ^[A-Za-z0-9._#-]+$ ]] && echo "# ft-hil-request seat=$ME"
  echo "# ft-hil-expect: closed=$NCL held=${#HELD[@]} clones=${#CLONES[@]}"
  for c in "${CLONES[@]}"; do echo "# clone $c"; done; for s in "${NANO[@]}" "${ROLE[@]}" $MST; do echo "# closed $s"; done
  for x in "${HELD[@]}"; do echo "# 멈춤 $x"; done
  echo 'set -u; rc=0'
  case "$LDC" in 등재*) echo "launchctl bootout gui/\$UID/com.byz.ft-tick-$TEAM || rc=1   # S1 launchd";; esac
  [ -z "$PMW" ] || echo "bash $(q "$PMW") --stop-if-owned --root $(q "$ROOT") || rc=1   # S1 ft-pm-watchd"
  for c in "${CLONES[@]}"; do echo "$(q "$TM") kill-session -t $(q "=$c") || rc=1   # S2 클론"; done
  for s in "${NANO[@]}"; do echo "bash $(q "$HERE/ft-nano-close.sh") $(q "$s") --result $(q "$ROOT/$CO") --recv $RECV --suspended $(q "$WHY") || rc=1   # S3 나노"; done
  for s in "${ROLE[@]}"; do echo "bash $(q "$HERE/ft-seat-close.sh") $(q "$s") --reason $(q "$WHY")${VERDICT:+ --verdict $VERDICT} || rc=1   # S3 역할"; done
  [ -z "$MST" ] || echo "if [ \$rc -eq 0 ]; then bash $(q "$HERE/ft-seat-close.sh") $(q "$MST") --reason $(q "$WHY")${VERDICT:+ --verdict $VERDICT} || rc=1; else echo \"S4 멈춤 하위 미닫힘(rc=\$rc)\"; fi   # S4 팀장"
  echo "bash $(q "$HERE/ft-team-stop.sh") $(q "$TEAM") --confirm \"\$0\" || rc=1   # S5 확인"
  echo 'exit $rc'; } > "$HP" || STOP "h 계획 못 씀 $HP"
HO="$(bash "${FT_HIL:-$HERE/ft-hil.sh}" --add "$HP" 2>&1 </dev/null)"; HR=$?
echo "h 1장 closed=$NCL held=${#HELD[@]} clones=${#CLONES[@]} plan=$HP"; printf '%s\n' "$HO" | tail -2
[ "$HR" -eq 0 ] || { echo "h 등록 실패 rc=$HR — 계획 파일 그대로 $HP"; RC=3; }
echo "${TS[*]} total=$((SECONDS - T0))s"; exit "$RC"
