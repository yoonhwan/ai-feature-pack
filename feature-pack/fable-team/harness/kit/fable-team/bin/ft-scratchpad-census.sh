#!/usr/bin/env bash
# ft-scratchpad-census.sh — r1080: 세션 scratchpad 의 git 사본을 «죽은 세션 · 깨끗 · 24h» 판정 표로 남긴다. 기본은 삭제 0.
#   찾기: <루트=FT_SP_ROOT 기본 /private/tmp/claude-$UID>/*/*/scratchpad/* 중 `.git`(폴더=clone · 파일=linked)이 바로 있는 폴더. 중첩 사본은 바깥 것 하나로 센다.
#   세션 판정(3단 · 앞이 참이면 멈춤 · r1082): ① `ps -axo pid=,command=` 의 `--session-id <uuid>` 에 있으면 LIVE. ② `<FT_SP_PROJECTS>/<프로젝트 폴더 이름>/<uuid>.jsonl` 이 1440분 안에 쓰임 → LIVE «기록 24h 안»(파일 없음 = 정상 미일치 · ③으로 · find 실패·시간 초과 = UNKNOWN). ③ `--session-id` 없는 살아 있는 claude(실행 파일 끝 `/claude`)의 cwd(`lsof -a -d cwd -Fpn` 짝)를 `/`·`.` → `-` 로 바꾼 이름이 사본의 프로젝트 폴더 이름과 같으면 DEAD-KEEP «세션 모름(인자 없는 좌석 <pid>)». 셋 다 아니면 dead(아래 idle·dirty·unique 로 이어짐). ps 실패·0줄 = «판정 불가» rc2 · 표 0.
#   점유: `lsof -a -d cwd -Fpn` 1회(p<pid>·n<cwd> 짝 · r1082 — ③ 의 pid↔cwd 짝에 재사용 · held 는 지금처럼 n 줄만 읽는다) · 실패·0줄 = «판정 불가» rc2. 사본 폴더 또는 그 아래가 cwd 면 held.
#   사본별 판정: idle = 사본 아래 최근 쓰기(find -mmin · 1440분 문턱 · .git 은 뺀다 — 우리 git status 가 .git/index mtime 을 갱신해 스스로 «최근쓰기» 로 보이는 것 방지) · dirty = git status --porcelain 줄 수 · unique = HEAD 를 담은 ref 0개(`git for-each-ref --contains HEAD`) · 크기 = du -sk(7초 넘으면 «?»)
#   판정 칸: DEAD-SAFE(dead ∧ held 0 ∧ idle ≥1440 ∧ dirty 0 ∧ unique 0) · DEAD-KEEP(사유) · LIVE · UNKNOWN(판정 불가)
#   출력: 표 .fable-team/state/scratchpad-census.tsv (tmp+mv 통째 교체 · 일반 파일) · stdout 요약 1줄. 회차 상한 FT_SP_BUDGET_SEC(기본 60) — 외부 호출 앞마다 남은 예산을 보고 상한을 줄이고, 넘으면 커서로 넘긴다(«부분 k/N»).
#   ★삭제 스위치(기본 끔)★ .fable-team/state/scratchpad-sweep.enabled 가 있을 때만 DEAD-SAFE 를 지운다: 지우기 직전 같은 사본 재판정 → 로그(경로·HEAD·remote·MB) 먼저 → clone = 폴더 삭제 · linked = 원 저장소에서 그 경로 하나만 worktree remove(prune 0).
#   ★r1081 — LIVE 행 쪽지 갈래(삭제 0)★ 표를 쓴 뒤 LIVE 행 중 «72h 안 바뀜(≥4320분) ∧ 미커밋 0 ∧ 유일커밋 0 ∧ cwd사용중 0» 을 세션별로 묶어 그 세션 좌석에 쪽지 1통: «[scratchpad 사본] N개 X.X GiB · 72h 안 바뀜 · 깨끗 — 필요 없으면 지우고, 다시 쓸 거면 ft-scratch-repo.sh <sha> --repo <저장소> 로 옮겨라 · 앞 3: 경로…». 좌석 이름 = 같은 ps 줄의 `--name <좌석>`(없으면 그 세션 건너뛰고 요약 «이름 없음 N»). 중복 방지 .fable-team/state/scratchpad-mailed.tsv(경로·HEAD·보낸 날) — 같은 경로·같은 HEAD 는 다시 안 보냄. 발신 실패 = 기록 0 + 로그 1줄(다음 회차 재시도). FT_SP_MAIL_DRY=1 이면 발신 0 으로 목록만.
#   env(시험용): FT_RES_ROOT · FT_SP_ROOT · FT_SP_STATE · FT_SP_BUDGET_SEC · FT_SP_PS_OUT(파일|읽기 실패면 판정 불가) · FT_SP_LSOF_OUT · FT_SP_GIT · FT_SP_MAILED · FT_SP_MBOX · FT_SP_MAIL_DRY · FT_SP_PROJECTS(기본 ~/.claude/projects) · FT_SP_TRACE(있으면 단계 호출 이름을 그 파일에 1줄씩 — 시험 전용)
set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT="${FT_RES_ROOT:-}"
[ -n "$ROOT" ] || { . "$HERE/ft-harness-root.sh" && ROOT="$(ft_repo_root "$HERE")"; } || exit 4
[ -n "$ROOT" ] && [ -d "$ROOT" ] || { echo "ERROR 리포 루트를 못 찾음(FT_RES_ROOT)" >&2; exit 4; }
STATE="${FT_SP_STATE:-$ROOT/.fable-team/state}"
mkdir -p "$STATE" 2>/dev/null || { echo "ERROR 상태 폴더 생성 실패: $STATE" >&2; exit 4; }
OUT="$STATE/scratchpad-census.tsv"; CUR="$STATE/scratchpad-census.cursor"
SLOG="$STATE/scratchpad-sweep.log"; SWITCH="$STATE/scratchpad-sweep.enabled"
MAILED="${FT_SP_MAILED:-$STATE/scratchpad-mailed.tsv}"; MAILLOG="$STATE/scratchpad-mail.log"
SPROOT="${FT_SP_ROOT:-/private/tmp/claude-$UID}"
BUDGET="${FT_SP_BUDGET_SEC:-60}"
GITBIN="${FT_SP_GIT:-git}"
PROJECTS="${FT_SP_PROJECTS:-$HOME/.claude/projects}"
UTRACE="${FT_SP_TRACE:-}"
trace() { [ -z "$UTRACE" ] || printf '%s\n' "$1" >> "$UTRACE"; }
DEADLINE=$(( $(date +%s) + BUDGET ))
left() { local r=$(( DEADLINE - $(date +%s) )); [ "$r" -gt 0 ] && echo "$r" || echo 0; }
cap() { local r; r="$(left)"; [ "$r" -gt 0 ] || return 1; [ "$r" -gt 7 ] && echo 7 || echo "$r"; }
iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

PS_SNAP=""; LS_SNAP=""
snapshot_ps() { PS_SNAP=""; if [ -n "${FT_SP_PS_OUT:-}" ]; then [ -r "$FT_SP_PS_OUT" ] || return 1; PS_SNAP="$(cat "$FT_SP_PS_OUT")"
  else local c; c="$(cap)" || return 1; PS_SNAP="$(timeout "$c" ps -axo pid=,command= 2>/dev/null)" || return 1; fi
  [ -n "$PS_SNAP" ]; }
snapshot_lsof() { LS_SNAP=""; if [ -n "${FT_SP_LSOF_OUT:-}" ]; then [ -r "$FT_SP_LSOF_OUT" ] || return 1; LS_SNAP="$(cat "$FT_SP_LSOF_OUT")"
  else local c; c="$(cap)" || return 1; LS_SNAP="$(timeout "$c" lsof -a -d cwd -Fpn 2>/dev/null)" || return 1; fi
  [ -n "$LS_SNAP" ]; }
# ── r1082 ③: --session-id 없는 살아 있는 claude 의 «cwd → 프로젝트 폴더 이름» 집합(첫 필요 때 1회) ──
UNK_SET=""; UNK_BUILT=0; U_PID=""
unflagged_pids() { awk '{
    if ($1 !~ /^[0-9]+$/) next
    cmd=$0; sub(/^[ \t]*[0-9]+[ \t]+/, "", cmd)
    if (split(cmd, a, /[ \t]+/) < 1) next
    if (a[1] !~ /\/claude$/) next
    if (cmd ~ /--session-id/) next
    print $1 }' <<<"$PS_SNAP"; }
cwd_pairs() { awk '/^p[0-9]+[ \t]*$/ {pid=substr($0,2)+0; next} /^n/ {if (pid != "") {print pid"\t"substr($0,2); pid=""}}' <<<"$LS_SNAP"; }
build_unk() { UNK_SET=""; UNK_BUILT=1; trace unk; local pids pid cwd
  pids="$(unflagged_pids)"; [ -n "$pids" ] || return 0
  while IFS=$'\t' read -r pid cwd; do
    [ -n "$pid" ] || continue
    grep -qx -- "$pid" <<<"$pids" || continue
    UNK_SET="${UNK_SET}$(printf '%s' "$cwd" | sed 's#[/.]#-#g')"$'\t'"$pid"$'\n'
  done <<<"$(cwd_pairs)"
  return 0; }
unk_pid_of() { [ "$UNK_BUILT" = 1 ] || build_unk; [ -n "$UNK_SET" ] || return 1; local pid
  pid="$(awk -F'\t' -v n="$1" '$1==n{print $2; exit}' <<<"$UNK_SET")"; [ -n "$pid" ] || return 1
  U_PID="$pid"; }
# ── r1082 ②: 그 세션 대화 기록이 1440분 안에 쓰였나(파일 없음 = 정상 미일치 · ③으로) ──
proj_of() { basename "$(dirname "$(dirname "$(dirname "$1")")")"; }
record_state() { # 0 = 24h 안(LIVE) · 3 = 기록 없음/묵음 · 4 = 판정 불가(시간 초과·find 실패)
  local rec c o
  rec="$PROJECTS/$(proj_of "$1")/$V_UUID.jsonl"
  [ -e "$rec" ] || return 3
  c="$(cap)" || return 4; trace rec
  o="$(timeout "$c" find "$rec" -mmin -1440 -print -quit 2>/dev/null)" || return 4
  [ -n "$o" ] && return 0
  return 3; }
git_c() { local d="$1"; shift; local c; c="$(cap)" || return 1; timeout "$c" "$GITBIN" -C "$d" "$@" 2>/dev/null; }
idle_of() { # $2 = 문턱(분 · 기본 1440) · 결과 "<b" 또는 ">=<문턱>" — find 실패·시간 초과면 rc1
  local d="$1" th="${2:-1440}" c o; c="$(cap)" || return 1
  o="$(timeout "$c" find "$d" -name .git -prune -o -mmin -"$th" -print -quit 2>/dev/null)" || return 1
  if [ -z "$o" ]; then echo ">=$th"; return 0; fi
  local b; for b in 15 30 60 180 360 720 1440; do [ "$b" -ge "$th" ] && break; c="$(cap)" || return 1
    [ -n "$(timeout "$c" find "$d" -name .git -prune -o -mmin -"$b" -print -quit 2>/dev/null)" ] && { echo "<$b"; return 0; }; done
  echo "<$th"; }
size_of() { local d="$1" c sk; c="$(cap)" || { echo "?"; return 0; }
  sk="$(timeout "$c" du -sk "$d" 2>/dev/null | awk 'NR==1{print $1}')"
  case "$sk" in ''|*[!0-9]*) echo "?";; *) awk -v k="$sk" 'BEGIN{printf "%.1f", k/1024}';; esac; }
held_of() { local p="$1" ln; while IFS= read -r ln; do case "$ln" in n*) ln="${ln#n}"
    [ "$ln" = "$p" ] && return 0; case "$ln" in "$p"/*) return 0;; esac;; esac; done <<<"$LS_SNAP"; return 1; }
uuid_of() { basename "$(dirname "$(dirname "$1")")"; }
repo_of() { # linked 사본의 원 저장소 루트 — 못 찾으면 빈 값
  local p="$1" c; c="$(git_c "$p" rev-parse --git-common-dir)" || return 1
  case "$c" in '') return 1;; /*) :;; *) c="$p/$c";; esac
  case "$c" in */.git) printf '%s' "${c%/.git}";; *) printf '%s' "$c";; esac; }

V_PATH=""; V_KIND=""; V_UUID=""; V_VERDICT=""; V_REASON=""; V_IDLE="-"; V_MB="?"; V_HEAD="-"; V_REMOTE="-"; V_REPO=""
judge() { local p="$1" idle dirty uniq n="0"
  V_PATH="$p"; V_UUID="$(uuid_of "$p")"; V_REASON=""; V_IDLE="-"; V_MB="?"; V_HEAD="-"; V_REMOTE="-"; V_REPO=""
  V_KIND=clone; [ -f "$p/.git" ] && V_KIND=linked
  if grep -q -e "--session-id $V_UUID" <<<"$PS_SNAP"; then V_VERDICT=LIVE; V_REASON="세션 살아 있음"; return 0; fi
  record_state "$p"; case $? in
    0) V_VERDICT=LIVE; V_REASON="기록 24h 안"; return 0;;
    4) V_VERDICT=UNKNOWN; V_REASON="판정 불가(기록)"; return 0;;
  esac
  if unk_pid_of "$(proj_of "$p")"; then V_VERDICT=DEAD-KEEP; V_REASON="세션 모름(인자 없는 좌석 $U_PID)"; return 0; fi
  if held_of "$p"; then V_VERDICT=DEAD-KEEP; V_REASON="cwd사용중"; return 0; fi
  V_IDLE="$(idle_of "$p")" || { V_VERDICT=UNKNOWN; V_REASON="판정 불가(idle)"; return 0; }
  dirty="$(git_c "$p" status --porcelain)" || { V_VERDICT=UNKNOWN; V_REASON="판정 불가(git status)"; return 0; }
  n="$(grep -c . <<<"$dirty")"
  uniq="$(git_c "$p" for-each-ref --contains HEAD --format='%(refname)' refs/heads refs/remotes)" || { V_VERDICT=UNKNOWN; V_REASON="판정 불가(git for-each-ref)"; return 0; }
  V_HEAD="$(git_c "$p" rev-parse --short=8 HEAD)" || V_HEAD="-"
  V_REMOTE="$(git_c "$p" config --get remote.origin.url)"; [ -n "$V_REMOTE" ] || V_REMOTE="-"
  V_MB="$(size_of "$p")"
  if [ "$V_IDLE" != ">=1440" ]; then V_VERDICT=DEAD-KEEP; V_REASON="최근쓰기"
  elif [ "$n" != 0 ]; then V_VERDICT=DEAD-KEEP; V_REASON="미커밋$n"
  elif [ -z "$uniq" ]; then V_VERDICT=DEAD-KEEP; V_REASON="유일커밋"
  elif [ "$V_KIND" = linked ]; then V_REPO="$(repo_of "$p")" || V_REPO=""
    if [ -z "$V_REPO" ]; then V_VERDICT=DEAD-KEEP; V_REASON="원 저장소 없음"; else V_VERDICT=DEAD-SAFE; fi
  else V_VERDICT=DEAD-SAFE; fi
  return 0; }
recheck() { # 지우기 직전 같은 사본을 처음과 «같은 규칙»으로 다시 판정 — DEAD-SAFE 일 때만 0(ps·lsof·기록 find 를 새로 조회 · 처음 판정 결과 재사용 0)
  snapshot_ps || return 1; snapshot_lsof || return 1; UNK_BUILT=0; judge "$1"; [ "$V_VERDICT" = DEAD-SAFE ]; }
delete_one() { # 0 = 지움 · 1 = 거절(로그 1줄). 로그를 먼저 쓰고 지운다.
  local p="$1" kind="$2" repo="$3" c
  recheck "$p" || { printf '%s\t%s\t재판정 거절\n' "$(iso)" "$p" >> "$SLOG"; return 1; }
  printf '%s\t%s\tHEAD=%s\tremote=%s\tMB=%s\n' "$(iso)" "$p" "${V_HEAD}" "${V_REMOTE}" "${V_MB}" >> "$SLOG"
  c="$(cap || echo 7)"
  if [ "$kind" = linked ]; then timeout "$c" "$GITBIN" -C "$repo" worktree remove "$p" >/dev/null 2>&1
  else rm -rf -- "$p"; fi
  [ -e "$p" ] && return 1
  return 0; }

# ── r1081: LIVE 행 중 «72h 묵음 ∧ 깨끗» 사본 → 그 세션 좌석에 쪽지(좌석당 1통 · 삭제 0) ──
MBOX="${FT_SP_MBOX:-$ROOT/.fable-team/comm/mbox.sh}"
SEAT=""
seat_of() { local line; line="$(grep -F -- "--session-id $1" <<<"$PS_SNAP" | head -1)"
  [ -n "$line" ] || return 1
  SEAT="$(awk '{for(i=1;i<NF;i++) if($i=="--name"){print $(i+1); exit}}' <<<"$line")"
  [ -n "$SEAT" ]; }
mailed_already() { [ -s "$MAILED" ] || return 1
  awk -F'\t' -v p="$1" -v h="$2" '$1==p && $2==h{f=1} END{exit f?0:1}' "$MAILED"; }
send_group() { # <좌석> <N> <GiB> <sha> <저장소> <경로들> — 0 = 보냄 · 3 = 발신 0 모드(목록만) · 1 = 실패
  local body
  body="[scratchpad 사본] $2개 $3GiB · 72h 안 바뀜 · 깨끗 — 필요 없으면 지우고, 다시 쓸 거면 \`ft-scratch-repo.sh $4 --repo $5\` 로 옮겨라 · 앞 3: $6"
  [ -z "${FT_SP_MAIL_DRY:-}" ] || { printf '[scratchpad 사본 쪽지·발신 0] %s ← %s\n' "$1" "$body"; return 3; }
  bash "$MBOX" send "$1" ft-scratchpad-census "$body" >/dev/null 2>>"$MAILLOG" && return 0
  printf '%s\t%s\t발신 실패 — 기록 0(다음 회차 재시도)\n' "$(iso)" "$1" >> "$MAILLOG"; return 1; }
G_CUR=""; G_N=0; G_MB=0; G_SHA=""; G_REPO=""; G_PATHS=""; G_REC=""
flush_group() { # 모인 묶음 1통 발신 + 경로·HEAD 기록(발신 성공일 때만 · 발신 0 모드는 기록도 0)
  [ -n "$G_CUR" ] && [ "$G_N" -gt 0 ] || return 0
  send_group "$G_CUR" "$G_N" "$(awk -v m="$G_MB" 'BEGIN{printf "%.2f", m/1024}')" "$G_SHA" "$G_REPO" "$G_PATHS"
  case $? in
    0) SENT=$((SENT+1))
       while IFS=$'\t' read -r rp rh; do [ -n "$rp" ] && printf '%s\t%s\t%s\n' "$rp" "$rh" "$(iso)" >> "$MAILED"; done <<<"$G_REC";;
    3) DRY=$((DRY+1));;
  esac
  G_CUR=""; G_N=0; G_MB=0; G_SHA=""; G_REPO=""; G_PATHS=""; G_REC=""; return 0; }
mail_live() { # 표의 LIVE 행을 좌석별로 묶어 1통씩 — 예산 0 이면 아무 외부 호출도 하지 않는다
  local list="$STATE/.sp-mail.$$" v kind mb idle uuid p reason head remote d u flag seat
  SENT=0; DUP=0; NONAME=0; DRY=0
  : > "$list"
  while IFS=$'\t' read -r v kind mb idle uuid p reason head remote; do
    [ "$v" = LIVE ] || continue
    [ "$(left)" -gt 0 ] || break
    held_of "$p" && continue
    [ "$(idle_of "$p" 4320)" = ">=4320" ] || continue
    d="$(git_c "$p" status --porcelain)" || continue
    [ -z "$d" ] || continue
    u="$(git_c "$p" for-each-ref --contains HEAD --format='%(refname)' refs/heads refs/remotes)" || continue
    [ -n "$u" ] || continue
    head="$(git_c "$p" rev-parse --short=8 HEAD)" || continue
    flag=0; mailed_already "$p" "$head" && flag=1
    remote="$(git_c "$p" config --get remote.origin.url)"; [ -n "$remote" ] || remote="-"
    seat=""; seat_of "$uuid" && seat="$SEAT"
    [ -n "$seat" ] || { NONAME=$((NONAME+1)); continue; }   # 이름 없음 = 목록에 안 넣는다(IFS 탭은 빈 칸을 삼킨다)
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$seat" "$flag" "$p" "$head" "$remote" "$(size_of "$p")" >> "$list"
  done < "$OUT"
  while IFS=$'\t' read -r seat flag p head remote mb; do
    [ -n "$seat" ] || continue
    [ "$seat" = "$G_CUR" ] || { flush_group; G_CUR="$seat"; }
    [ "$flag" = 1 ] && { DUP=$((DUP+1)); continue; }
    G_N=$((G_N+1)); G_MB="$(awk -v a="$G_MB" -v b="$mb" 'BEGIN{print a+b}')"
    [ -n "$G_SHA" ] || G_SHA="$head"
    { [ "$G_REPO" = "-" ] || [ -z "$G_REPO" ]; } && { [ "$remote" = "-" ] || G_REPO="$remote"; }
    G_REC="${G_REC}${p}"$'\t'"${head}"$'\n'
    [ "$G_N" -gt 3 ] || G_PATHS="${G_PATHS:+$G_PATHS ; }$p"
  done < <(sort -t$'\t' -k1,1 "$list")
  flush_group
  rm -f "$list"
  printf '[scratchpad 사본 쪽지] %s통 · 이미 보냄 %s · 이름 없음 %s\n' "$SENT" "$DUP" "$NONAME"
  return 0; }

# ── 사본 목록(중첩 제외 = scratchpad 바로 아래만) ──
fresh=""; for d in "$SPROOT"/*/*/scratchpad/*/; do [ -d "$d" ] || continue; [ -e "${d%/}/.git" ] || continue; fresh="$fresh${d%/}"$'\n'; done
TOTAL="$(printf '%s' "$fresh" | grep -c .)"
work="$fresh"
if [ -s "$CUR" ]; then work=""; while IFS= read -r l; do [ -n "$l" ] && [ -d "$l" ] && work="$work$l"$'\n'; done < "$CUR"
  while IFS= read -r l; do [ -n "$l" ] && ! grep -qxF -- "$l" <<<"$work" && work="$work$l"$'\n'; done <<<"$fresh"; fi
TMP="$OUT.tmp.$$"; : > "$TMP"
judged=0; rest=""; safe=0; keeps=0; lives=0; unks=0; dels=0; mbsum=0
if [ "$(left)" -gt 0 ]; then   # 남은 예산 0 이면 외부 호출 0 — 아래 루프가 전부 커서로 넘긴다
  if ! snapshot_ps; then echo "[scratchpad 사본] 판정 불가 — ps 실패 또는 0줄 (표 0 · 삭제 0)" >&2
    echo "판정 불가: ps 실패 또는 0줄"; rm -f "$TMP"; exit 2; fi
  if ! snapshot_lsof; then echo "[scratchpad 사본] 판정 불가 — lsof 실패 또는 0줄 (표 0 · 삭제 0)" >&2
    echo "판정 불가: lsof 실패 또는 0줄"; rm -f "$TMP"; exit 2; fi
fi
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [ "$(left)" -le 0 ]; then rest="$rest$p"$'\n'; continue; fi
  judge "$p"; judged=$((judged+1))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$V_VERDICT" "$V_KIND" "$V_MB" "$V_IDLE" "$V_UUID" "$V_PATH" \
    "${V_REASON:--}" "$V_HEAD" "$V_REMOTE" >> "$TMP"
  case "$V_VERDICT" in
    DEAD-SAFE) safe=$((safe+1)); mbsum="$(awk -v a="$mbsum" -v b="$V_MB" 'BEGIN{print a+b}')"
      if [ -e "$SWITCH" ]; then delete_one "$V_PATH" "$V_KIND" "$V_REPO" && dels=$((dels+1)); fi;;
    DEAD-KEEP) keeps=$((keeps+1));; LIVE) lives=$((lives+1));; *) unks=$((unks+1));;
  esac
done <<<"$work"
if ! mv -f "$TMP" "$OUT" 2>/dev/null; then cp -f "$TMP" "$OUT"; fi; rm -f "$TMP"
if [ -n "$rest" ]; then printf '%s' "$rest" > "$CUR"; else rm -f "$CUR"; fi
gib="$(awk -v m="$mbsum" 'BEGIN{printf "%.2f", m/1024}')"
part=""; [ -z "$rest" ] || part=" · 부분 $judged/$TOTAL"
# ★쪽지 갈래는 반드시 요약 «앞» 이다★ — ft-disk-alarm 은 stdout 의 tail -1 을 요약으로 읽어 DEAD-SAFE·DEAD-KEEP·UNKNOWN 수를 뽑는다(뒤에 두면 세 값이 비어 매일 쪽지 1통이 나간다 · arch#174 격리 r1)
mail_live
printf '[scratchpad 사본] DEAD-SAFE %s개 %sGiB · DEAD-KEEP %s · LIVE %s · UNKNOWN %s · 삭제 %s%s\n' \
  "$safe" "$gib" "$keeps" "$lives" "$unks" "$dels" "$part"
exit 0
