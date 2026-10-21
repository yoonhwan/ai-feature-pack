#!/usr/bin/env bash
# ft-resource-watch.sh [tick|scan] — Res-1014 · launchd 가 60초마다 부르는 1회 실행형 감시자 + 원인 귀속 스냅샷.
#   계기: 2026-10-14 03:31 watchdog 패닉. ★파일 삭제·prune 기능 없음 — 오빠 승인 별건★. 좌석 회수는 tick 진입 직후 ft-resource-preventive.sh(600초 · 승인 두 행 안 · ft-resource-reclaim --preventive 경유 · 측정·동결과 독립 · R332). 나머지는 «감시·귀속·동결». deferral-lint: ok 기능 부재 설명이며 연기 아님
#   tick (기본, launchd 호출): - ft-resource-sample.sh 로 압력 표본 1줄(pressure.tsv · R213) 뒤 gate status 로 disk/swap/memfree 측정(측정 실패 rc4 → 로그 ERROR·동결 손대지 않음).
#     - 동결 «생성» 근거(r633 · 이 한 곳이 정본): disk<FT_RES_DISK_MIN(25GiB) | memfree<FT_RES_MEM_MIN(10%) | level>=FT_RES_LEVEL_FREEZE(4 · 커널 «위험») — 동결파일 없으면: 즉시 스냅샷 → RESOURCE_FREEZE 생성(사유·시각·증가1위 1줄) + osascript 알림 + 로그 1줄. swap>12288MiB & level>=2 는 동결 0 → 유휴 좌석 닫기 목록 쪽지(ft-resource-swapwarn-lib.sh) — hard 동결 판정·생성 «뒤», hard 조건이 참인 틱엔 쪽지 0(DA⑥ r1 ①) · FT_RES_SWAP_FREEZE=1 = swap 축만 옛 동작(swap∧level2 도 동결 · level 4 단독 동결은 env 무관) · R357 swap 단독 동결 폐기는 그대로.
#     - 동결 «해제» 근거 = 회복(R320 · disk>=35 & memfree>=20 & level=1 & swap 비증가, 압력 표본 «최근 3개 연속» — swap 절대량은 조건 아님: macOS swap 은 줄지 않는다 · R320c: 추가로 문지기와 같은 rate(gate status 의 마지막 6표본 MiB/분) ≤ 허용치 512 · na 면 유지) + 동결파일 있으면: RESOURCE_FREEZE 제거(우리 마커 · 사용자 데이터 아님) + 로그 1줄.
#     - (r522) 표본 뒤 CPU 폭주 감지 1회(ft-resource-cause.sh cpu · 상한 FT_RES_CPU_CAP_SEC 7초): 주인 줄 → state/runaway-cpu.log 1줄 · 서명(명령·주인·개수)이 바뀌면 planner 명부(FT_SEATS_JSON) _master 에 [CPU 폭주] 쪽지 1통(FT_MBOX_SH) · 프로세스 끄기 0.
#     - 10분마다(틱 10번째 ≈ 590초 경과) 원인 스냅샷: disk-attrib.tsv · mem-attrib.tsv 에 누적. 3일 넘은 줄은 같은 실행에서 잘라낸다(회전).  scan: 직전/1시간 대비 증가 상위 5(항목·+GiB·MB/min) + 디스크 여유·바닥까지 N분 + 메모리 상위 5·claude 수.
#   R323: 스냅샷의 du 는 전부 nice 19 · 호출당 상한 FT_RES_DU_CAP_SEC(7초 · 넘으면 죽이고 TIMEOUT) · 스냅샷 전체에 잠금 1개(du-scan.lock.d · 살아 있는 스캔이 있으면 이번 스냅샷 건너뜀) — 39분짜리 du 가 틱을 붙잡던 사고(2026-10-17).
#   r534: 워크트리·claude.projects·caches·pytest 는 통째 du 대신 1단계 폴더별 «증분»(틱당 FT_RES_WT_PER_TICK(25)개 · 폴더별 캐시 du-cache.tsv · 합 = 캐시 합 + «<칸>.known 앎/전체») · 스냅샷 측정 예산 FT_RES_SNAP_BUDGET_SEC(55) · 상한 넘긴 폴더는 1단계 하위로 나눔(깊이 FT_RES_SPLIT_DEPTH(3)).  env(시험용): FT_SWAP_LEVEL_MIN(2 · R357) · FT_RES_ROOT · FT_WORKTREES · FT_RES_DISK_MIN(25) · FT_RES_SWAP_MAX(12288) · FT_RES_MEM_MIN(10) · FT_RES_SNAP_SEC(590) · FT_RES_DU_CAP_SEC · FT_RES_WT_PER_TICK · FT_RES_SNAP_BUDGET_SEC · FT_RES_SPLIT_DEPTH · FT_RECLAIM_PREVENT_SEC(600) · FT_RECLAIM_SH · FT_PREVENTIVE_SH
set -uo pipefail
PATH="$PATH:${FT_RECLAIM_EXTRA_PATH:-/opt/homebrew/bin:/usr/local/bin}"; export PATH   # r502: launchd 기본 PATH 에 홈브루 경로를 덧붙인다 — 표본·문지기·선제 회수 하위 호출 전부 같은 tmux·도구를 본다(plist 손 생성물 수정 0)

CMD="${1:-tick}"
case "$CMD" in tick|scan) ;; *) echo "usage: $0 [tick|scan]" >&2; exit 2;; esac

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# 리포 루트 = git common-dir — 워크트리 bin 에서 불러도 메인 리포 루트로 통일(동결·tsv 한 곳). git 미가용(launchd) 대비 FT_RES_ROOT 우선 · 그다음 ft_repo_root(옛 설치 꼴 · cwd) · 못 풀면 ERROR
RES_ROOT="${FT_RES_ROOT:-}"   # r385: 리포 공용 루트 = env → ft_repo_root(옛 설치 꼴 · cwd) → ERROR (새 설치본이 git 밖이라 자기 위치로 풀지 않는다)
[ -n "$RES_ROOT" ] || { . "$HERE/ft-harness-root.sh" && RES_ROOT="$(ft_repo_root "$HERE")"; } || exit 3
STATE="$RES_ROOT/.fable-team/state"
FREEZE="$STATE/RESOURCE_FREEZE"
LOG="$STATE/resource-watch.log"
DISK_TSV="$STATE/disk-attrib.tsv"
MEM_TSV="$STATE/mem-attrib.tsv"
PTSV="$STATE/pressure.tsv"
LAST_SNAP="$STATE/.disk-attrib-last"
WORKTREES="${FT_WORKTREES:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees}"
GATE="$HERE/ft-resource-gate.sh"

DISK_MIN="${FT_RES_DISK_MIN:-25}"
SWAP_MAX="${FT_RES_SWAP_MAX:-12288}"
MEM_MIN="${FT_RES_MEM_MIN:-10}"
SWAP_LEVEL_MIN="${FT_SWAP_LEVEL_MIN:-2}"; SLM_WARN=""   # R357: swap 트리거는 level>=이 값과 결합(문지기와 같은 env) · 무효값 = 기본 2 + 로그 WARN(tick 첫 줄) — 빈 값·미설정은 WARN 0
case "$SWAP_LEVEL_MIN" in ''|*[!0-9]*) SLM_WARN=1;; *) [ "$((10#$SWAP_LEVEL_MIN))" -ge 1 ] || SLM_WARN=1;; esac; [ -z "$SLM_WARN" ] || { SLM_WARN="WARN FT_SWAP_LEVEL_MIN=${FT_SWAP_LEVEL_MIN} 무효(양의 정수 아님) — 기본 2 사용"; SWAP_LEVEL_MIN=2; }
SNAP_SEC="${FT_RES_SNAP_SEC:-590}"

mkdir -p "$STATE" 2>/dev/null || true
DU_CAP="${FT_RES_DU_CAP_SEC:-7}"
DU_CACHE="$STATE/du-cache.tsv"; DU_LOCK="$STATE/du-scan.lock.d"
PER_TICK="${FT_RES_WT_PER_TICK:-25}"; SNAP_BUDGET="${FT_RES_SNAP_BUDGET_SEC:-55}"; SPLIT_MAX="${FT_RES_SPLIT_DEPTH:-3}"   # r534 증분 측정

now_epoch() { date +%s; }
# R320: pressure.tsv 마지막 3줄(5칸 숫자)이 전부 memfree>=20 · level=1 · swap 이 앞 표본보다 늘지 않음 → rc0
calm3() { tail -n 3 "$PTSV" 2>/dev/null | awk -F'\t' 'NF==5 && $1~/^[0-9]+$/ {n++; if($3+0<20||$4+0!=1) bad=1; if(n>1&&$2+0>p) bad=1; p=$2+0} NF!=5{bad=1} END{exit !(n==3&&!bad)}'; }
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

logline() { printf '%s\t%s\n' "$(now_utc)" "$1" >> "$LOG"; }

# R323: 명령을 nice 19 로 돌리고 DU_CAP 초 안에 안 끝나면 죽인다(rc 124) — timeout 바이너리 없는 맥에서도 상한이 선다. stdout = 명령 출력.
run_capped() {
  local out="$STATE/.capped.$$.$RANDOM" pid i=0 max=$((DU_CAP*10)) rc
  nice -n 19 "$@" > "$out" 2>/dev/null & pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$i" -ge "$max" ]; then kill -TERM "$pid" 2>/dev/null; sleep 0.2; kill -KILL "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rm -f "$out"; return 124; fi
    sleep 0.1; i=$((i+1))
  done
  wait "$pid"; rc=$?; cat "$out"; rm -f "$out"; return $rc
}
. "$HERE/ft-resource-du-lib.sh" || exit 3   # r534 du 함수(du_line · du_lock · 증분 inc_group 등) — 감시자 줄 수 상한(≤245) 때문에 따로 둔다
. "$HERE/ft-resource-selflink-lib.sh" || exit 3; . "$HERE/ft-resource-swapwarn-lib.sh" || exit 3   # r589 루트 node_modules 자기 링크 감시 · r633 swap 경고 닫기 목록 쪽지 — 같은 이유로 lib

snapshot_disk() { # now
  local now="$1" raw rc freek cnt rec logk end g kn pf dr
  end=$((SECONDS+SNAP_BUDGET)); [ -f "$DU_CACHE" ] || : > "$DU_CACHE"
  freek=$(df -Pk /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4+0}')
  printf '%s\tdisk.free\t%s\n' "$now" "${freek:-0}" >> "$DISK_TSV"
  # /private/tmp 1단계 하위 상위 15
  raw=$(run_capped du -sk -d1 /private/tmp); rc=$?
  if [ "$rc" = 124 ]; then printf '%s\t/private/tmp\tTIMEOUT\n' "$now" >> "$DISK_TSV"
  else printf '%s\n' "$raw" | awk '$2!="/private/tmp" && $1 ~ /^[0-9]+$/ {print $1"\t"$2}' \
      | sort -rn | head -15 | awk -v now="$now" -F'\t' '{print now"\t"$2"\t"$1}' >> "$DISK_TSV"; fi
  # worktrees 개수·최근2시간
  if [ -d "$WORKTREES" ]; then
    cnt=$(find "$WORKTREES" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    rec=$(find "$WORKTREES" -mindepth 1 -maxdepth 1 -type d -mmin -120 2>/dev/null | wc -l | tr -d ' ')
    printf '%s\tworktrees.count\t%s\n' "$now" "${cnt:-0}" >> "$DISK_TSV"
    printf '%s\tworktrees.recent2h\t%s\n' "$now" "${rec:-0}" >> "$DISK_TSV"
  fi
  du_line "$now" colima.diffdisk "$HOME/.colima/_lima/colima/diffdisk"
  logk=$(run_capped du -sk /tmp/byz-*.log | awk '{s+=$1} END{print s+0}')
  printf '%s\tbyz.logs\t%s\n' "$now" "${logk:-0}" >> "$DISK_TSV"
  # r534: 큰 폴더 넷 = 1단계 증분(칸 이름 그대로 합 + <칸>.known) · 남은 예산(SNAP_BUDGET)을 남은 칸 수로 나눠 차례로 — 워크트리를 맨 끝에 둬 앞 칸이 남긴 시간까지 받는다
  set -- "claude.projects|claude.projects.known|claude.projects|$HOME/.claude/projects" "caches|caches.known|caches|$HOME/Library/Caches" \
    "pytest|pytest.known|pytest|${TMPDIR:-/tmp}/pytest-of-$USER" "worktrees.total|worktrees.known|wt|$WORKTREES"
  while [ $# -gt 0 ]; do IFS='|' read -r g kn pf dr <<<"$1"; inc_group "$now" "$g" "$kn" "$pf" "$dr" $((SECONDS+(end-SECONDS)/$#)); shift; done
}

snapshot_mem() { # now
  local now="$1" c x
  ps -axo rss=,comm= 2>/dev/null | awk '{name=$2; for(i=3;i<=NF;i++) name=name" "$i; if(name=="")name="?"; r[name]+=$1} END{for(n in r) print r[n]"\t"n}' \
    | sort -rn | head -8 | awk -v now="$now" -F'\t' '{print now"\tmem:"$2"\t"$1}' >> "$MEM_TSV"
  c=$(pgrep -x claude 2>/dev/null | wc -l | tr -d ' ')
  x=$(pgrep -f 'codex( |$)' 2>/dev/null | wc -l | tr -d ' ')
  printf '%s\tproc.claude\t%s\n' "$now" "${c:-0}" >> "$MEM_TSV"
  printf '%s\tproc.codex\t%s\n' "$now" "${x:-0}" >> "$MEM_TSV"
}

rotate_tsv() { # file cutoff
  local F="$1" cutoff="$2" tmp
  [ -f "$F" ] || return 0
  tmp="$F.tmp.$$"
  if awk -F'\t' -v c="$cutoff" '($1+0)>=c' "$F" > "$tmp" 2>/dev/null; then mv "$tmp" "$F"; else rm -f "$tmp"; fi
}

do_snapshot() { # now — 디스크·메모리 스냅샷 + 회전 + 마커
  local now="$1" cutoff
  if du_lock; then snapshot_disk "$now"; rm -r -f "$DU_LOCK"; else logline "du 스캔 진행 중 — 이번 디스크 스냅샷 건너뜀(잠금 $DU_LOCK)"; fi
  snapshot_mem "$now"
  cutoff=$((now-259200))   # 3일
  rotate_tsv "$DISK_TSV" "$cutoff"; rotate_tsv "$MEM_TSV" "$cutoff"
  printf '%s\n' "$now" > "$LAST_SNAP"
}

top1_disk() { # 증가 1위 항목 + 속도 (freeze 알림용)
  local F="$DISK_TSV" t2 t1
  [ -f "$F" ] || { echo "원인 미상"; return; }
  t2=$(cut -f1 "$F" | sort -n | tail -1)
  t1=$(cut -f1 "$F" | sort -un | tail -2 | head -1)
  if [ "$t1" = "$t2" ]; then echo "원인 미상(스냅샷 1개)"; return; fi
  awk -F'\t' -v t1="$t1" -v t2="$t2" '
    $1==t1 && $3 ~ /^[0-9]+$/ {a[$2]=$3}
    $1==t2 && $3 ~ /^[0-9]+$/ {b[$2]=$3}
    END{ best=""; bd=0; for(k in b){ if(k ~ /\.(count|recent2h|free)$/) continue; d=b[k]-(a[k]+0); if(d>bd){bd=d;best=k} }
      if(best==""){printf "원인 미상"} else {dt=t2-t1; printf "%s +%.1fG/%d분", best, bd/1048576, (dt+30)/60} }' "$F"   # DA⑥ H4: 입력 파일 명시 — 없으면 awk 가 stdin 을 읽어 tty 없는 셸에서 tick 이 멈춘다
}

# ---- scan (사람 보고) ----
disk_top() { # t1 t2 label
  local F="$DISK_TSV" t1="$1" t2="$2"
  awk -F'\t' -v t1="$t1" -v t2="$t2" '
    $1==t1 && $3 ~ /^[0-9]+$/ {a[$2]=$3}
    $1==t2 && $3 ~ /^[0-9]+$/ {b[$2]=$3}
    END{ for(k in b){ if(k ~ /\.(count|recent2h|free)$/) continue; d=b[k]-(a[k]+0); if(d>0) print d"\t"k } }' "$F" \
    | sort -rn | head -5 | awk -v dt=$((t2-t1)) -F'\t' '{printf "  %s  +%.2fG  %.1fMB/min\n", $2, $1/1048576, ($1/1024)/(dt/60)}'
}
floor_line() {
  local F="$DISK_TSV" t2 t1
  t2=$(cut -f1 "$F" | sort -n | tail -1)
  t1=$(cut -f1 "$F" | sort -un | tail -2 | head -1)
  awk -F'\t' -v t1="$t1" -v t2="$t2" '
    $1==t1 && $2=="disk.free"{a=$3}
    $1==t2 && $2=="disk.free"{b=$3}
    END{
      if(b==""){print "디스크 여유 미상"}
      else{ freeg=b/1048576
        if(t1==t2 || a==""){printf "디스크 여유 %.1fG · 속도 미상(스냅샷 1개)\n", freeg}
        else{ dt=(t2-t1)/60; dec=(a-b)/dt
          if(dec<=0){printf "디스크 여유 %.1fG · 감소 없음(안정)\n", freeg}
          else{printf "디스크 여유 %.1fG · 이 속도면 %d분 뒤 바닥 (%.1fMB/min 감소)\n", freeg, b/dec, dec/1024} } } }' "$F"
}
mem_top() {
  local F="$MEM_TSV" t2
  [ -f "$F" ] || { echo "  (데이터 없음)"; return; }
  t2=$(cut -f1 "$F" | sort -n | tail -1)
  awk -F'\t' -v t2="$t2" '$1==t2 && $2 ~ /^mem:/ {sub(/^mem:/,"",$2); printf "  %s  %.2fG\n", $2, $3/1048576}' "$F" | head -5
  awk -F'\t' -v t2="$t2" '$1==t2 && $2=="proc.claude"{print "  claude 프로세스 "$3"개"}' "$F"
  awk -F'\t' -v t2="$t2" '$1==t2 && $2=="proc.codex"{print "  codex 프로세스 "$3"개"}' "$F"
}
scan() {
  if [ ! -f "$DISK_TSV" ]; then echo "스냅샷 없음 — tick 이 10분마다 쌓는다"; return 0; fi
  local t2 tlast thour
  t2=$(cut -f1 "$DISK_TSV" | sort -n | tail -1)
  tlast=$(cut -f1 "$DISK_TSV" | sort -un | tail -2 | head -1)
  thour=$(cut -f1 "$DISK_TSV" | sort -un | awk -v t=$((t2-3600)) '$1<=t{c=$1} END{print c}')
  echo "== 디스크 증가 상위 (직전 스냅샷 대비) =="
  if [ "$tlast" != "$t2" ]; then disk_top "$tlast" "$t2"; else echo "  (스냅샷 1개)"; fi
  echo "== 디스크 증가 상위 (1시간 전 대비) =="
  if [ -n "$thour" ] && [ "$thour" != "$t2" ]; then disk_top "$thour" "$t2"; else echo "  (1시간 데이터 부족)"; fi
  echo "== 디스크 여유 =="
  floor_line
  echo "== 메모리 상위 =="
  mem_top
}

# r522: CPU 폭주(같은 이름 ≥3 · 각 ≥30% · ≥5분) 주인 한 줄 → runaway-cpu.log + 서명(명령·주인·개수)이 바뀌면 planner _master 에 쪽지 1통. 기록·알림만 · 동결 판정과 독립.
cpu_watch() {
  local out rc sig seats route mbox cm sigf="$STATE/.runaway-cpu.sig"
  out="$(DU_CAP="${FT_RES_CPU_CAP_SEC:-7}" run_capped bash "${FT_RESOURCE_CAUSE_SH:-$HERE/ft-resource-cause.sh}" cpu)"; rc=$?
  [ "$rc" = 0 ] || { logline "ERROR cpu 원인 rc=$rc$([ "$rc" = 124 ] && echo ' (상한 초과)') — 동결 판정은 계속"; return 0; }
  [ -n "$out" ] || { rm -f "$sigf"; return 0; }   # 폭주가 끝나면 서명을 지운다 — 다음 폭주는 새 사건으로 알린다
  printf '%s\t%s\n' "$(now_utc)" "$out" >> "$STATE/runaway-cpu.log"
  sig="$(printf '%s' "$out" | sed 's/ CPU [0-9]*% [0-9]*분//g')"
  [ "$sig" != "$(cat "$sigf" 2>/dev/null)" ] || return 0
  seats="${FT_SEATS_JSON:-$RES_ROOT/.fable-team/seats-planner.json}"
  route="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("_master",""))' "$seats" 2>/dev/null)"
  [ -n "$route" ] || { logline "ERROR CPU 폭주 쪽지 수신자 없음(planner _master · $seats) — $out"; return 0; }
  mbox="${FT_MBOX_SH:-}"; [ -n "$mbox" ] || { . "$HERE/ft-harness-root.sh" && cm="$(ft_comm_dir "$HERE")" && mbox="$cm/mbox.sh"; } || { logline "ERROR CPU 폭주 쪽지 우편함 못 풂"; return 0; }
  if bash "$mbox" send "$route" ft-resource-watch "[CPU 폭주] $out · 끄기는 사람 판단 · kill 0" >/dev/null 2>>"$LOG"; then printf '%s\n' "$sig" > "$sigf"
  else logline "ERROR CPU 폭주 쪽지 발신 실패 to=$route"; fi
}

# ---- tick (launchd) ----
tick() {
  local gout rc disk swap memfree level rate now trax recov swarn
  FT_RES_ROOT="$RES_ROOT" bash "${FT_PREVENTIVE_SH:-$HERE/ft-resource-preventive.sh}" >/dev/null 2>&1 || logline "ERROR ft-resource-preventive rc=$? (tick 은 계속)"   # R332 선제 회수 · 조기 종료(측정 오류·동결 생성)보다 앞 · 실패가 tick 을 바꾸지 않음
  bash "$HERE/ft-resource-sample.sh" >/dev/null 2>>"$LOG" || logline "ERROR sample rc=$? (표본 끊김 — 문지기 stale 로 이어짐)"
  [ -z "$SLM_WARN" ] || { logline "$SLM_WARN"; echo "$SLM_WARN" >&2; }   # R357: 설정이 바뀐 사실을 숨기지 않는다(조용한 후퇴 금지)
  cpu_watch   # r522: 표본 뒤 · 문지기·동결 분기보다 앞(측정 오류·동결 생성으로 tick 이 일찍 끝나도 CPU 축은 본다)
  selflink_watch   # r589: 동결 분기보다 앞(이른 return 에도 돈다) · test -L 1회 · 삭제 0 · 쪽지 1통
  gout="$(bash "$GATE" status 2>&1)"; rc=$?
  printf '%s\n' "$gout" | grep '^WARN ' | grep -v FT_SWAP_LEVEL_MIN | while IFS= read -r _w; do logline "gate $_w"; done   # R357: 문지기 WARN 은 rc0 이어도 버리지 않고 로그로(SWAP_LEVEL_MIN WARN 은 위 줄과 중복이라 제외)
  if [ "$rc" != 0 ]; then logline "ERROR gate status rc=$rc out=$gout"; exit 4; fi
  disk=$(printf '%s' "$gout" | sed -n 's/.*disk=\([0-9]*\).*/\1/p')
  swap=$(printf '%s' "$gout" | sed -n 's/.*swap=\([0-9]*\).*/\1/p')
  level=$(printf '%s' "$gout" | sed -n 's/.*level=\([0-9]*\).*/\1/p')
  memfree=$(printf '%s' "$gout" | sed -n 's/.*memfree=\([0-9]*\).*/\1/p')
  rate=$(printf '%s' "$gout" | sed -n 's/.* rate=\(-\{0,1\}[0-9a-z]*\).*/\1/p')   # R320c: 해제 swap 축 = 문지기와 같은 rate(마지막 6표본 MiB/분) ≤ 허용치 512 · na·못 읽음 = 유지
  case "$disk$swap$memfree" in ''|*[!0-9]*) logline "ERROR parse gate=$gout"; exit 4;; esac
  now=$(now_epoch); FT_RES_ROOT="$RES_ROOT" bash "$HERE/ft-disk-alarm.sh" >/dev/null 2>&1 || logline "ERROR ft-disk-alarm rc=$? (tick 은 계속)"   # R246 쪽지 경보 · 동결 분기보다 먼저

  trax=""; [ "$disk" -lt "$DISK_MIN" ] && trax="disk"   # R357: 트리거 축 이름 — swap 은 level>=SWAP_LEVEL_MIN 과 결합할 때만(절대량 단독 동결 폐기 — 해제가 swap 절대량을 안 봐 플래핑)
  swarn=""; if [ "$swap" -gt "$SWAP_MAX" ] && [ "${level:-0}" -ge "$SWAP_LEVEL_MIN" ]; then if [ "${FT_RES_SWAP_FREEZE:-0}" = 1 ]; then trax="${trax:+$trax+}swap"; else swarn=1; fi; fi   # r633: swap 경고 = 막지 않음 · 쪽지는 hard 동결 판정 뒤
  [ "$memfree" -lt "$MEM_MIN" ] && trax="${trax:+$trax+}memfree"; [ "${level:-0}" -ge "${FT_RES_LEVEL_FREEZE:-4}" ] && trax="${trax:+$trax+}level"   # r633: level 4(위험) 단독 동결

  if [ -n "$trax" ] && [ ! -f "$FREEZE" ]; then
    do_snapshot "$now"
    local cause cseat ckind=disk; cause="$(top1_disk)"
    case "$trax" in *swap*|*memfree*|*level*) ckind=mem;; esac
    cseat="$(bash "$HERE/ft-resource-cause.sh" "$ckind" 2>/dev/null | head -1)"   # R320: 원인 좌석 한 줄(자료 없으면 «자료 부족»)
    printf 'FREEZE %s disk=%sG swap=%sM level=%s memfree=%s%% 1위 %s · 원인 좌석(%s) %s\n' "$(now_utc)" "$disk" "$swap" "${level:-?}" "$memfree" "$cause" "$ckind" "${cseat:-자료 부족}" > "$FREEZE"
    osascript -e "display notification \"디스크 ${disk}G · 1위 $cause\" with title \"FT 자원 동결(spawn 차단)\"" >/dev/null 2>&1 || true
    logline "FREEZE created disk=${disk}G swap=${swap}M level=${level:-?} memfree=${memfree}% trig=$trax cause=$cause"
    return 0
  fi
  recov=0; [ -z "$swarn" ] || [ -n "$trax" ] || swapwarn_send "$swap" "${level:-0}"   # r633 DA⑥ r1 ①: hard 동결(위)이 먼저 · hard 조건 참인 틱은 쪽지 0 · 실패는 lib 가 ERROR 1줄(동결 판정 영향 0)
  if [ "$disk" -ge 35 ] && [ "$memfree" -ge 20 ] && [ "${level:-0}" = 1 ] && calm3; then recov=1; fi
  [ "$recov" = 0 ] || { case "$rate" in ''|na|*[!0-9-]*) false;; *) [ "$rate" -le "${FT_SWAP_RATE_MAX:-512}" ];; esac; } || { recov=0; [ ! -f "$FREEZE" ] || logline "THAW held rate=${rate:-?} (허용 ${FT_SWAP_RATE_MAX:-512} 초과·판정 불가)"; }
  if [ "$recov" = 1 ] && [ -f "$FREEZE" ] && [ -n "$trax" ]; then logline "THAW held trig=$trax"   # R357 불변식: 닫는 사건(THAW)이 여는 사건(트리거)을 바로 되살리지 않는다
  elif [ "$recov" = 1 ] && [ -f "$FREEZE" ]; then
    rm -f "$FREEZE"
    osascript -e "display notification \"디스크 ${disk}G 회복 · spawn 재개\" with title \"FT 자원 동결 해제\"" >/dev/null 2>&1 || true
    logline "THAW removed disk=${disk}G swap=${swap}M memfree=${memfree}% rate=${rate}"
  fi

  # 10분마다 원인 스냅샷
  local last=0; [ -f "$LAST_SNAP" ] && last="$(cat "$LAST_SNAP" 2>/dev/null)"
  case "$last" in ''|*[!0-9]*) last=0;; esac
  if [ $((now-last)) -ge "$SNAP_SEC" ]; then do_snapshot "$now"; fi
}

case "$CMD" in
  scan) scan;;
  tick) tick;;
esac
