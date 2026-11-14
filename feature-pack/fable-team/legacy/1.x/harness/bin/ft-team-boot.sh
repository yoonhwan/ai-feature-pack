#!/usr/bin/env bash
# ft-team-boot.sh <팀> — 팀 «부팅 1명령» (r1519 · DESIGN-r1498 §4 B0~B5 · 모델 0 · 크론·설정파일 신설 0)
#   B0 정본 읽기  : <ref 기본 origin/main> 의 design/teams/<팀>/ «재귀» 에서 이름 CLOSEOUT-<팀>-*.md 만 · 2장 이상이면 파일 이름 날짜(YYYYMMDD) 최대값 → 같은 날이면 최신 커밋 1장 ·
#                  0장 = «정본 없음» 멈춤(손 부팅 대체 0) · `ft-all-stop.sh check` rc≠0 = 그 REJECT 그대로 멈춤
#   B1 중복 0     : boot plan <데이터 루트>/.fable-team/state/team-boot/<팀>-<ts>.plan · 같은 시도의 B2 이름이 살아 있으면 그 plan 으로 남은 단계부터 재개(spawn 0) · 그 밖 살아 있는 byz-<팀>-… = «이미 부팅됨» 멈춤 · FT_BOOT_STATE 를 «명시하지 않았고» 새 자리에 plan 이 없으면 옛 자리($ROOT/state/team-boot)의 plan 으로 재개(R3 · 이동 0)
#   B2 팀장 1석   : ft-successor-open.sh <마지막 팀장> <워크트리> --name <#N+1> --agent <명부> --model <명부> --body-file <부팅 본문>(첫 3줄 = 골 원문 · 4줄 = CLOSEOUT 경로)
#                   명부 읽기 = ft-team-seats-lib.sh 1곳(r1535) · airag = 팩 위성팀 — 명부 PACK/.fable-team/seats-aifp.json 의 «aifp-<팀>-master-*» 행 중 #N 최대 · 워크트리 뿌리 PACK/.worktrees · 행 0 = 멈춤(팩 _master 대체 0)
#                   명부 행에 재개 기록(_resume_uuid)이 있고 여는 도구 usage 가 --resume 을 받으면 인자 1개 추가 · 못 받으면 WARN 1줄(새 세션 · 조용한 대체 아님 · §9 ③)
#   B3 필요한 하위: 그 CLOSEOUT 의 «재개: 예» 행만 ft-nano-spawn.sh <카드> --reopen (역할 좌석은 여기서 0)
#   B4 크론·클론 0: launchd com.byz.ft-tick-<팀> = «plist 파일 유무» 아니라 launchctl print gui/$UID 로드 여부(r1536 B-3) · launchctl 자체 실패 = «판정 불가» 1줄(하드 룰 20) · 살아 있는 계보 1석 확인(그 밖 = «부팅 직후 잔존»)
#                  · 정본 본문에 «CronCreate» 줄이 있으면 WARN 1줄(줄 수 · 멈추지 않음 · r1534)
#   B5 보고 1통  : planner master 에 [부팅] 1통 · seq 를 plan 에 적고 status=완료 · 송신 실패 = «보고 미도달»(재실행 = 같은 plan 으로 B5 만)
#                  · cron 칸 = 팀장 agent 로 정한다(pi=none(pi) · 그 밖=«판정 불가» · 고정 «none» 0 · r1534)
#   실패마다 «멈춤 <이유>» 1줄 + rc(1 멈춤 · 2 usage · 5 보고 미도달) · 데몬·루프·sleep 0 · 한 실행 ≤70초
#   env(시험용): FT_REPO_ROOT FT_BOOT_REF FT_BOOT_STATE FT_BOOT_ME FT_BOOT_WT FT_BOOT_REPORT_TO FT_SEATS_JSON FT_MBOX_SH FT_SUCCESSOR_OPEN
#                FT_NANO_SPAWN FT_ALL_STOP FT_TMUX FT_LAUNCHAGENTS FT_LAUNCHCTL FT_PACK_ROOT FT_AIFP_ROOT
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -f "$HERE/ft-live-entry.sh" ] && . "$HERE/ft-live-entry.sh" "$@"
usage() { echo "usage: $0 <팀>   (팀 예: harness · planner · ops · ccu · airag)" >&2; exit 2; }
[ $# -eq 1 ] || usage
TEAM="$1"; case "$TEAM" in -*|"") usage;; esac
REF="${FT_BOOT_REF:-origin/main}"
ROOT="${FT_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$ROOT" ] || { echo "멈춤 리포 루트를 못 찾았다(FT_REPO_ROOT 또는 git 안에서 실행)"; exit 1; }
PACK="${FT_PACK_ROOT:-$HOME/Project/ai-feature-pack}"
# airag 만 aifp 리포 design/aifp/ (DESIGN-r1498 §4 B0 · ROUTE 판 2 §5.3 예외 1줄)
if [ "$TEAM" = airag ]; then DROOT="${FT_AIFP_ROOT:-$PACK}"; CREPO="$PACK"; CDIR="design/aifp"; SAT=1; WROOT="$PACK/.worktrees"
else DROOT="$ROOT"; CREPO="$ROOT"; CDIR="design/teams/$TEAM"; SAT=0; WROOT="$ROOT/.worktrees"; fi
STATE="${FT_BOOT_STATE:-$DROOT/.fable-team/state/team-boot}"   # r1536 B-4: plan 자리 = 데이터 루트(워크트리마다 흩어지지 않는다)
ME="${FT_BOOT_ME:-${FT_SEND_FROM:-ft-team-boot}}"
STOP() { echo "멈춤 $*"; exit "${STOP_RC:-1}"; }
T0=$SECONDS; T=(); step_end() { T+=("$1=$((SECONDS - ${2:-0}))s"); }
# ---------- 골 원문·다시 여는 법·재개 카드 = CLOSEOUT 1장에서만 ----------
sec_lines() { awk -v want="$2" -v maxn="$3" '$0 ~ /^#+ / { inh = ($0 ~ want); next } inh && NF { n++; print; if (n >= maxn) exit }'; }
first_tokens() { awk -v want="$2" '$0 ~ /^#+ / { inh = ($0 ~ want); next } inh && NF { n++; print; if (n >= 3) exit }'; }
# ---------- B0 ----------
B0=$SECONDS
stop_out="$(bash "${FT_ALL_STOP:-$HERE/ft-all-stop.sh}" check 2>&1)"; stop_rc=$?
[ "$stop_rc" -eq 0 ] || { echo "$stop_out"; STOP_RC=1 STOP "전팀 정지 중(check rc=$stop_rc) — 위 REJECT 그대로"; }
cands="$(git -C "$CREPO" ls-tree -r --name-only "$REF" -- "$CDIR" 2>/dev/null | grep -E "(^|/)CLOSEOUT-$TEAM-[^/]*\.md$" || true)"
[ -n "$cands" ] || STOP "정본 없음 — $CREPO@$REF:$CDIR/CLOSEOUT-$TEAM-*.md 0장 · 손 부팅(ft-role-spawn) 또는 CLOSEOUT 작성 먼저"
best=""
# 결정 순서(동점 포함 · ls-tree 경로 순서를 쓰지 않는다): 이름 날짜 → 계보(조상이면 뒤가 최신) → 커밋초 → 커밋 sha → 경로
cdate() { local d; d="$(printf '%s' "${1##*/}" | grep -oE '[0-9]{8}' | tail -1)"; printf '%s' "${d:-00000000}"; }
cct()   { local v; v="$(git -C "$CREPO" log -1 --format=%ct "$REF" -- "$1" 2>/dev/null)"; case "$v" in ''|*[!0-9]*) v=0;; esac; printf '%012d' "$v"; }
ctop()  { git -C "$CREPO" log -1 --format=%H "$REF" -- "$1" 2>/dev/null; }
newer() {  # $2 가 $1 보다 새 정본이면 0
  local da db ca cb cta ctb
  da="$(cdate "$1")"; db="$(cdate "$2")"
  [ "$db" \> "$da" ] && return 0; [ "$db" \< "$da" ] && return 1
  ca="$(ctop "$1")"; cb="$(ctop "$2")"
  if [ "$ca" != "$cb" ]; then
    git -C "$CREPO" merge-base --is-ancestor "$ca" "$cb" 2>/dev/null && return 0
    git -C "$CREPO" merge-base --is-ancestor "$cb" "$ca" 2>/dev/null && return 1
    cta="$(cct "$1")"; ctb="$(cct "$2")"
    [ "$ctb" \> "$cta" ] && return 0; [ "$ctb" \< "$cta" ] && return 1
    [ "$cb" \> "$ca" ] && return 0 || return 1
  fi
  [ "$2" \> "$1" ]
}
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [ -z "$best" ] || newer "$best" "$p"; then best="$p"; fi
done <<< "$cands"
text="$(git -C "$CREPO" show "$REF:$best" 2>/dev/null)" || STOP "정본 읽기 실패 $REF:$best(boot plan 판정 불가)"
sha="$(git -C "$CREPO" rev-parse "$REF:$best" 2>/dev/null | cut -c1-40)"
GOAL3="$(printf '%s\n' "$text" | sec_lines x '골 원문' 3)"
GSOURCE="CLOSEOUT"
if [ -z "$GOAL3" ]; then gsrc=""; for c in "$CDIR/GOAL-$TEAM.md" "design/$TEAM/GOAL-$TEAM.md"; do
    gt="$(git -C "$CREPO" show "$REF:$c" 2>/dev/null)" && { GOAL3="$(printf '%s\n' "$gt" | first_tokens x '골')"; gsrc="$c"; } && break; done
  [ -n "$GOAL3" ] || STOP "골 원문 없음 — $best 에 «## 골 원문» 절 0 · GOAL-$TEAM.md 0"
  GSOURCE="$gsrc"
fi
REOPEN1="$(printf '%s\n' "$text" | sec_lines x '다시 여는 법' 1)"
step_end B0 "$B0"
# ---------- 팀장·워크트리·카드 (명부) ----------
[ -f "$HERE/ft-team-seats-lib.sh" ] || STOP "명부 lib 없음 $HERE/ft-team-seats-lib.sh"
. "$HERE/ft-team-seats-lib.sh"   # SEATS · OLD · AGENT · MODEL · NEXT · RESUME_UUID · WT (r1535)
CARDS="$(printf '%s\n' "$text" | grep -E '재개: *예' | grep -oE 'indices/진행/[^ `)|<>]+\.md' || true)"
NREOPEN=0; [ -n "$CARDS" ] && NREOPEN="$(printf '%s\n' "$CARDS" | sort -u | wc -l | tr -d ' ')"
# ---------- B1 boot plan · 중복 0 ----------
B1=$SECONDS
tmux_ls() { "${FT_TMUX:-tmux}" ls -F '#{session_name}' 2>/dev/null || true; }
live_sessions() { tmux_ls | grep -E "^(byz|aifp)-$TEAM-" || true; }
mkdir -p "$STATE" || STOP "boot plan 폴더 못 만듦 $STATE"
PLAN=""; b2name=""
last="$(ls -1t "$STATE/$TEAM"-*.plan 2>/dev/null | head -1)"
LEGACY="$ROOT/state/team-boot"   # r1536 R3(DA): FT_BOOT_STATE 를 «명시하지 않았을 때만» 옛 기본 자리를 본다(R3-b · 명시 = 그 자리만이 그 생명)
if [ -z "$last" ] && [ -z "${FT_BOOT_STATE:-}" ] && [ "$STATE" != "$LEGACY" ]; then
  last="$(ls -1t "$LEGACY/$TEAM"-*.plan 2>/dev/null | head -1)"
  [ -z "$last" ] || echo "B1 옛 자리 plan 재개 $last(새 기본 $STATE · 파일 이동 0)"
fi
if [ -n "$last" ]; then
  grep -q '^ts=' "$last" 2>/dev/null || STOP "boot plan 판정 불가 $last(ts 줄 없음)"
  psha="$(sed -n 's/^closeout=.* sha=\([^ ]*\).*/\1/p' "$last" | tail -1)"
  pb2="$(sed -n 's/^b2=done name=\([^ ]*\).*/\1/p' "$last" | tail -1)"
  if grep -q '^status=완료' "$last"; then
    # 앞 생명의 plan 이 완료여도 «정본이 다르면» 새 생명이다 — 완료 plan 이 새 CLOSED→BOOTING 을 영구 차단하지 않는다(DA r1519 R2)
    [ "$psha" = "$sha" ] && STOP "이미 부팅됨 ${pb2:-<plan 완료>}(plan 완료 $last · 같은 정본 sha=$sha)"
    echo "B1 새 생명 — 앞 plan 완료(정본 ${psha:-?}) · 새 정본 sha=$sha → 새 plan"
  else
    PLAN="$last"; b2name="$pb2"
    [ -n "$b2name" ] && { tmux_ls | grep -qx "$b2name" || STOP "plan 팀장 세션 없음 $b2name — 두 번 열지 않는다(사람 확인)"; }
    [ -n "$b2name" ] || { alive="$(live_sessions | head -1)"; [ -z "$alive" ] || STOP "이미 부팅됨 $alive"; }
    echo "B1 재개 같은 시도 plan=$PLAN"
  fi
fi
if [ -z "$PLAN" ]; then
  alive="$(live_sessions | head -1)"
  [ -n "$alive" ] && STOP "이미 부팅됨 $alive"
  base="$STATE/$TEAM-$(date +%Y%m%dT%H%M%S)"; PLAN="$base.plan"; i=2
  while [ -e "$PLAN" ]; do PLAN="$base-$i.plan"; i=$((i+1)); done
  { echo "team=$TEAM"; echo "ts=$(date +%Y%m%dT%H%M%S)"; echo "ref=$REF"; echo "closeout=$best sha=$sha";
    echo "b0=done"; echo "b2=pending"; echo "b3=pending"; echo "b4=pending"; echo "b5=pending"; echo "status=booting"; } > "$PLAN" \
    || STOP "boot plan 못 씀 $PLAN"
fi
step_end B1 "$B1"
plan_set() { local k="$1" v="$2" t; t="$(mktemp "${PLAN}.XXXX")" || return 1
  awk -v k="$k" -v v="$v" 'index($0, k "=") == 1 { print k "=" v; done = 1; next } { print } END { if (!done) print k "=" v }' "$PLAN" > "$t" && mv "$t" "$PLAN"; }
done_step() { sed -n "s/^$1=done.*/1/p" "$PLAN" | grep -q 1; }
BODY="$STATE/$TEAM-$(date +%Y%m%dT%H%M%S).body"
# ---------- B2 팀장 1석 ----------
B2=$SECONDS
if done_step b2; then echo "B2 skip plan 에 done ($b2name)"
else
  { printf '%s\n' "$GOAL3" | head -3; echo; echo "정본: $CREPO@$REF:$best (sha $sha · 출처 $GSOURCE)";
    [ -n "$REOPEN1" ] && echo "다시 여는 법: $REOPEN1"
    echo "재개 카드: ${NREOPEN}장 · 크론 0 · 호출될 때만"
    # r1957 «열린 칸 감시: » 1줄 = CLOSEOUT «## 열린 칸 감시» 절 항목 전부(부분 선택 0 · 160자 초과 = successor-open REJECT → B2 STOP) · 절 없으면 «없음» + 근거 sha
    W1957="$(printf '%s\n' "$text" | sec_lines x '열린 칸 감시' 9999 | sed -E 's/^[[:space:]]*-[[:space:]]+//' | awk 'NR > 1 { printf " · " } { printf "%s", $0 }')"
    echo "열린 칸 감시: ${W1957:-없음(새 생명 · CLOSEOUT ${sha:0:10} 기준 · 재개 카드 ${NREOPEN}장 = B3)}"; } > "$BODY" || STOP "부팅 본문 못 씀 $BODY"
  SO="${FT_SUCCESSOR_OPEN:-$HERE/ft-successor-open.sh}"
  so_args=("$OLD" "$WT" --name "$NEXT" --agent "$AGENT" --model "$MODEL" --body-file "$BODY")
  if [ -n "$RESUME_UUID" ]; then
    if grep -q -- '--resume' <(bash "$SO" 2>&1 | head -3) 2>/dev/null; then so_args+=(--resume); echo "B2 재개 기록 있음 — --resume 1개"
    else echo "WARN --resume 미지원($SO usage 에 없음 · 재개 기록 $RESUME_UUID) — 새 세션으로 연다"; fi
  fi
  so_out="$(bash "$SO" "${so_args[@]}" 2>&1)"; so_rc=$?
  echo "B2 $NEXT rc=$so_rc"; printf '%s\n' "$so_out" | tail -3
  [ "$so_rc" -eq 0 ] || { plan_set b2 "rc=$so_rc name=$NEXT"; STOP "팀장 미도달 rc=$so_rc(하위 0 · $NEXT)"; }
  plan_set b2 "done name=$NEXT rc=0"; b2name="$NEXT"
fi
step_end B2 "$B2"
# ---------- B3 «재개: 예» 카드만 ----------
B3=$SECONDS
if done_step b3; then echo "B3 skip plan 에 done"
else
  printf '%s\n' "$CARDS" | sort -u | while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    card="$DROOT/$CDIR/$tok"
    o="$(bash "${FT_NANO_SPAWN:-$HERE/ft-nano-spawn.sh}" "$card" --reopen 2>&1)"; r=$?
    if [ "$r" -eq 0 ]; then echo "B3 재개 $tok"; else echo "B3 spawn REJECT rc=$r $tok — $(printf '%s' "$o" | head -1)"; fi
  done
  plan_set b3 "done n=$NREOPEN"
fi
step_end B3 "$B3"
# ---------- B4 크론·클론 0 ----------
B4=$SECONDS
plist="${FT_LAUNCHAGENTS:-$HOME/Library/LaunchAgents}/com.byz.ft-tick-$TEAM.plist"
if done_step b4; then
  ld="$(sed -n 's/^b4=done launchd=\([^ ]*\).*/\1/p' "$PLAN" | tail -1)"; n_seat="$(sed -n 's/^b4=.*계보=\([0-9]*\).*/\1/p' "$PLAN" | tail -1)"
  echo "B4 skip plan 에 done (launchd=$ld 계보=$n_seat)"
else
  tick_launchd_loaded "$TEAM"; ld="$LD_CELL"   # r1536 B-3: 파일 유무 아니라 로드 여부(실패 = 판정 불가 1줄)
  n_seat="$(live_sessions | grep -c . || true)"; [ "$n_seat" -ge 1 ] || n_seat=0
  resid=""; case "$ld" in 등재*) resid="$ld";; esac; [ "$n_seat" -gt 1 ] && resid="${resid:+$resid · }계보 ${n_seat}석"
  [ -z "$resid" ] || echo "부팅 직후 잔존 $resid"
  echo "B4 launchd=$ld 계보=${n_seat}석"
  ncron="$(printf '%s\n' "$text" | grep -c 'CronCreate' || true)"
  [ "${ncron:-0}" -eq 0 ] || echo "WARN 정본에 CronCreate 줄 ${ncron} — 오빠 11-08 자기 틱 크론 0(#274576) · 그 줄 지우고 다시 부팅"
  plan_set b4 "done launchd=$ld 계보=${n_seat}"
fi
step_end B4 "$B4"
# ---------- B5 보고 1통 ----------
B5=$SECONDS
if done_step b5; then echo "B5 skip plan 에 done"
else
  TO="${FT_BOOT_REPORT_TO:-$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("_master",""))' "$ROOT/.fable-team/seats-planner.json" 2>/dev/null)}"
  [ -n "$TO" ] || { plan_set b5 "보고 미도달"; STOP_RC=5 STOP "보고 미도달 — planner 명부 _master 판정 불가"; }
  MB="${FT_MBOX_SH:-$ROOT/.fable-team/comm/mbox.sh}"
  ci_s=불가; command -v ci >/dev/null 2>&1 && ci_s=가능
  win="미기재"; case "$MODEL" in *"[1m]"*) win=1000000;; esac
  cron_cell="판정 불가(세션 안 · 팀장 부팅 보고가 CronList 실측)"   # r1534: claude·codex 세션 크론은 밖에서 못 잰다
  [ "$AGENT" = pi ] && cron_cell="none(pi · CronCreate 도구 없음)"        # pi 만 확정 — 도구 자체가 없다
  body="[부팅] $TEAM — 좌석=${b2name:-$NEXT} · 모델=$MODEL · 창=$win · ci=$ci_s · adhd=1 · cron=$cron_cell · launchd=$ld · 재개 카드 n=$NREOPEN · CLOSEOUT sha=$sha"
  mo="$(bash "$MB" send "$TO" "$ME" "$body" 2>&1)"; mr=$?
  seq="$(printf '%s' "$mo" | sed -n 's/.*seq=\([0-9][0-9]*\).*/\1/p' | tail -1)"
  echo "B5 to=$TO rc=$mr seq=${seq:-?}"; [ -n "$mo" ] && printf '%s\n' "$mo" | tail -1
  [ "$mr" -eq 0 ] || { plan_set b5 "보고 미도달 rc=$mr"; STOP_RC=5 STOP "보고 미도달 rc=$mr(재실행 = 같은 plan 으로 B5 만)"; }
  plan_set b5 "done seq=${seq:-?}"
  plan_set status 완료
fi
step_end B5 "$B5"
echo "부팅 완료 $TEAM plan=$PLAN closeout=$best sha=$sha 좌석=$NEXT 재개카드=$NREOPEN"
echo "${T[*]} total=$((SECONDS - T0))s"
