#!/usr/bin/env bash
# ft-resource-watch.sh [tick|scan]
#   Res-1014 · launchd 가 60초마다 부르는 1회 실행형 감시자 + 원인 귀속 스냅샷.
#   계기: 2026-10-14 03:31 watchdog 패닉. ★파일 삭제·prune 기능 없음 — 오빠 승인 별건★. 하는 일은 «감시·귀속·동결»뿐. deferral-lint: ok 기능 부재 설명이며 연기 아님
#   tick (기본, launchd 호출):
#     - ft-resource-sample.sh 로 압력 표본 1줄(pressure.tsv · R213) 뒤 gate status 로 disk/swap/memfree 측정(측정 실패 rc4 → 로그 ERROR·동결 손대지 않음).
#     - 동결 트리거(disk<25GiB | swap>12288MiB | memfree<10%) + 동결파일 없으면: 즉시 스냅샷 → RESOURCE_FREEZE 생성(사유·시각·증가1위 1줄) + osascript 알림 + 로그 1줄.
#     - 회복(disk>=35 & swap<4096 & memfree>=20) + 동결파일 있으면: RESOURCE_FREEZE 제거(우리 마커 · 사용자 데이터 아님) + 로그 1줄.
#     - 10분마다(틱 10번째 ≈ 590초 경과) 원인 스냅샷: disk-attrib.tsv · mem-attrib.tsv 에 누적. 3일 넘은 줄은 같은 실행에서 잘라낸다(회전).
#   scan: 직전/1시간 대비 증가 상위 5(항목·+GiB·MB/min) + 디스크 여유·바닥까지 N분 + 메모리 상위 5·claude 수.
#   env(시험용): FT_RES_ROOT · FT_WORKTREES · FT_RES_DISK_MIN(25) · FT_RES_SWAP_MAX(12288) · FT_RES_MEM_MIN(10) · FT_RES_SNAP_SEC(590)
set -uo pipefail

CMD="${1:-tick}"
case "$CMD" in tick|scan) ;; *) echo "usage: $0 [tick|scan]" >&2; exit 2;; esac

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)"
# 리포 루트 = git common-dir — 워크트리 bin 에서 불러도 메인 리포 루트로 통일(동결·tsv 한 곳). git 미가용(launchd) 대비 FT_RES_ROOT 우선 · 최종 fallback $HERE/../..
RES_ROOT="${FT_RES_ROOT:-$(git -C "$HERE" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||')}"
[ -n "$RES_ROOT" ] || RES_ROOT="$(cd -- "$HERE/../.." && pwd)"
STATE="$RES_ROOT/.fable-team/state"
FREEZE="$STATE/RESOURCE_FREEZE"
LOG="$STATE/resource-watch.log"
DISK_TSV="$STATE/disk-attrib.tsv"
MEM_TSV="$STATE/mem-attrib.tsv"
LAST_SNAP="$STATE/.disk-attrib-last"
WORKTREES="${FT_WORKTREES:-/Users/yoonhwan/Project/Agent/BYZ-Work/BYZ-Agents/.worktrees}"
GATE="$HERE/ft-resource-gate.sh"

DISK_MIN="${FT_RES_DISK_MIN:-25}"
SWAP_MAX="${FT_RES_SWAP_MAX:-12288}"
MEM_MIN="${FT_RES_MEM_MIN:-10}"
SNAP_SEC="${FT_RES_SNAP_SEC:-590}"

mkdir -p "$STATE" 2>/dev/null || true
TIMEOUT=""
if command -v gtimeout >/dev/null 2>&1; then TIMEOUT="gtimeout 20s"
elif command -v timeout >/dev/null 2>&1; then TIMEOUT="timeout 20s"; fi

now_epoch() { date +%s; }
now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }

logline() { printf '%s\t%s\n' "$(now_utc)" "$1" >> "$LOG"; }

du_line() { # now name path
  local now="$1" name="$2" p="$3" raw rc
  if [ ! -e "$p" ]; then printf '%s\t%s\t0\n' "$now" "$name" >> "$DISK_TSV"; return; fi
  raw=$($TIMEOUT du -sk "$p" 2>/dev/null); rc=$?
  if [ "$rc" = 124 ]; then printf '%s\t%s\tTIMEOUT\n' "$now" "$name" >> "$DISK_TSV"; return; fi
  printf '%s\t%s\t%s\n' "$now" "$name" "$(printf '%s' "$raw" | awk 'END{print $1+0}')" >> "$DISK_TSV"
}

snapshot_disk() { # now
  local now="$1" raw rc freek cnt rec logk
  freek=$(df -Pk /System/Volumes/Data 2>/dev/null | awk 'NR==2{print $4+0}')
  printf '%s\tdisk.free\t%s\n' "$now" "${freek:-0}" >> "$DISK_TSV"
  # /private/tmp 1단계 하위 상위 15
  raw=$($TIMEOUT du -sk -d1 /private/tmp 2>/dev/null); rc=$?
  if [ "$rc" = 124 ]; then printf '%s\t/private/tmp\tTIMEOUT\n' "$now" >> "$DISK_TSV"
  else printf '%s\n' "$raw" | awk '$2!="/private/tmp" && $1 ~ /^[0-9]+$/ {print $1"\t"$2}' \
      | sort -rn | head -15 | awk -v now="$now" -F'\t' '{print now"\t"$2"\t"$1}' >> "$DISK_TSV"; fi
  # worktrees 총량·개수·최근2시간
  if [ -d "$WORKTREES" ]; then
    raw=$($TIMEOUT du -sk "$WORKTREES" 2>/dev/null); rc=$?
    if [ "$rc" = 124 ]; then printf '%s\tworktrees.total\tTIMEOUT\n' "$now" >> "$DISK_TSV"
    else printf '%s\tworktrees.total\t%s\n' "$now" "$(printf '%s' "$raw" | awk 'END{print $1+0}')" >> "$DISK_TSV"; fi
    cnt=$(find "$WORKTREES" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
    rec=$(find "$WORKTREES" -mindepth 1 -maxdepth 1 -type d -mmin -120 2>/dev/null | wc -l | tr -d ' ')
    printf '%s\tworktrees.count\t%s\n' "$now" "${cnt:-0}" >> "$DISK_TSV"
    printf '%s\tworktrees.recent2h\t%s\n' "$now" "${rec:-0}" >> "$DISK_TSV"
  fi
  du_line "$now" colima.diffdisk "$HOME/.colima/_lima/colima/diffdisk"
  du_line "$now" claude.projects "$HOME/.claude/projects"
  du_line "$now" caches "$HOME/Library/Caches"
  du_line "$now" pytest "${TMPDIR:-/tmp}/pytest-of-$USER"
  logk=$($TIMEOUT du -sk /tmp/byz-*.log 2>/dev/null | awk '{s+=$1} END{print s+0}')
  printf '%s\tbyz.logs\t%s\n' "$now" "${logk:-0}" >> "$DISK_TSV"
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
  snapshot_disk "$now"; snapshot_mem "$now"
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
      if(best==""){printf "원인 미상"} else {dt=t2-t1; printf "%s +%.1fG/%d분", best, bd/1048576, (dt+30)/60} }'
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

# ---- tick (launchd) ----
tick() {
  local gout rc disk swap memfree now trig recov
  bash "$HERE/ft-resource-sample.sh" >/dev/null 2>>"$LOG" || logline "ERROR sample rc=$? (표본 끊김 — 문지기 stale 로 이어짐)"
  gout="$(bash "$GATE" status 2>&1)"; rc=$?
  if [ "$rc" != 0 ]; then logline "ERROR gate status rc=$rc out=$gout"; exit 4; fi
  disk=$(printf '%s' "$gout" | sed -n 's/.*disk=\([0-9]*\).*/\1/p')
  swap=$(printf '%s' "$gout" | sed -n 's/.*swap=\([0-9]*\).*/\1/p')
  memfree=$(printf '%s' "$gout" | sed -n 's/.*memfree=\([0-9]*\).*/\1/p')
  case "$disk$swap$memfree" in ''|*[!0-9]*) logline "ERROR parse gate=$gout"; exit 4;; esac
  now=$(now_epoch)

  trig=0
  [ "$disk" -lt "$DISK_MIN" ] && trig=1
  [ "$swap" -gt "$SWAP_MAX" ] && trig=1
  [ "$memfree" -lt "$MEM_MIN" ] && trig=1

  if [ "$trig" = 1 ] && [ ! -f "$FREEZE" ]; then
    do_snapshot "$now"
    local cause; cause="$(top1_disk)"
    printf 'FREEZE %s disk=%sG swap=%sM memfree=%s%% 1위 %s\n' "$(now_utc)" "$disk" "$swap" "$memfree" "$cause" > "$FREEZE"
    osascript -e "display notification \"디스크 ${disk}G · 1위 $cause\" with title \"FT 자원 동결(spawn 차단)\"" >/dev/null 2>&1 || true
    logline "FREEZE created disk=${disk}G swap=${swap}M memfree=${memfree}% cause=$cause"
    return 0
  fi

  recov=0
  if [ "$disk" -ge 35 ] && [ "$swap" -lt 4096 ] && [ "$memfree" -ge 20 ]; then recov=1; fi
  if [ "$recov" = 1 ] && [ -f "$FREEZE" ]; then
    rm -f "$FREEZE"
    osascript -e "display notification \"디스크 ${disk}G 회복 · spawn 재개\" with title \"FT 자원 동결 해제\"" >/dev/null 2>&1 || true
    logline "THAW removed disk=${disk}G swap=${swap}M memfree=${memfree}%"
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
